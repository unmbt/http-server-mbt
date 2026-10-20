/* R-N04 / D-05 / T-023 / N-07. Real syscall capability and lifecycle probe.
 * No performance measurements. Negative errno is retained in JSON. */
#define _GNU_SOURCE
#include <liburing.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <netinet/in.h>
#include <sys/socket.h>

static int completion(struct io_uring *ring,uint64_t expected) {
  struct io_uring_cqe *cqe;
  struct __kernel_timespec timeout={.tv_sec=2};
  int code=io_uring_wait_cqe_timeout(ring,&cqe,&timeout);
  if(code<0)return code;
  int result=cqe->user_data==expected?cqe->res:-EPROTO;
  io_uring_cqe_seen(ring,cqe);
  return result;
}
static int submit(struct io_uring *ring) {
  int n;do {n=io_uring_submit(ring);}while(n==-EINTR);
  return n;
}
int main(void) {
  struct io_uring ring;
  struct io_uring_params params={0};
  const char *phase="setup";
  int code=io_uring_queue_init_params(32,&ring,&params);
  if(code<0) {
    printf("{\"schema\":1,\"available\":false,\"phase\":\"setup\",\"errno\":%d,\"liburing\":\"2.9\"}\n",-code);
    return 77;
  }
  struct io_uring_probe *probe=io_uring_get_probe_ring(&ring);
  if(!probe) {code=-errno;phase="opcode_probe";goto done;}
  unsigned required[]={IORING_OP_NOP,IORING_OP_ACCEPT,IORING_OP_RECV,IORING_OP_SEND,IORING_OP_READ,IORING_OP_TIMEOUT,IORING_OP_ASYNC_CANCEL,IORING_OP_POLL_ADD};
  for(unsigned i=0;i<sizeof(required)/sizeof(required[0]);i++) {
    if(!io_uring_opcode_supported(probe,(int)required[i])){code=-EOPNOTSUPP;phase="required_opcode";break;}
  }
  io_uring_free_probe(probe);
  if(code<0)goto done;
  struct io_uring_sqe *sqe=io_uring_get_sqe(&ring);
  io_uring_prep_nop(sqe);sqe->user_data=1;
  phase="nop";if(submit(&ring)<0 || (code=completion(&ring,1))<0)goto done;

  phase="file_read";
  char path[]="/tmp/http-server-uring-XXXXXX";
  int file=mkstemp(path);
  if(file<0){code=-errno;goto done;}
  unlink(path);
  if(write(file,"uring",5)!=5){code=-errno;close(file);goto done;}
  char bytes[8]={0};
  sqe=io_uring_get_sqe(&ring);io_uring_prep_read(sqe,file,bytes,5,0);sqe->user_data=2;
  if(submit(&ring)<0){code=-EIO;close(file);goto done;}
  code=completion(&ring,2);close(file);
  if(code!=5 || memcmp(bytes,"uring",5)){code=code<0?code:-EIO;goto done;}

  phase="socket_send_recv";
  int sockets[2];
  if(socketpair(AF_UNIX,SOCK_STREAM|SOCK_CLOEXEC,0,sockets)){code=-errno;goto done;}
  sqe=io_uring_get_sqe(&ring);io_uring_prep_send(sqe,sockets[0],"hello",5,MSG_NOSIGNAL);sqe->user_data=3;
  if(submit(&ring)<0 || (code=completion(&ring,3))!=5)goto close_pair;
  memset(bytes,0,sizeof(bytes));
  sqe=io_uring_get_sqe(&ring);io_uring_prep_recv(sqe,sockets[1],bytes,5,0);sqe->user_data=4;
  if(submit(&ring)<0 || (code=completion(&ring,4))!=5 || memcmp(bytes,"hello",5)) {code=-EIO;goto close_pair;}

  phase="cancel_pending_recv";
  sqe=io_uring_get_sqe(&ring);io_uring_prep_recv(sqe,sockets[1],bytes,5,0);sqe->user_data=5;
  if(submit(&ring)<0){code=-EIO;goto close_pair;}
  sqe=io_uring_get_sqe(&ring);io_uring_prep_cancel64(sqe,5,0);sqe->user_data=6;
  if(submit(&ring)<0){code=-EIO;goto close_pair;}
  int original=0,cancel=0;
  for(int i=0;i<2;i++) {
    struct io_uring_cqe *cqe;struct __kernel_timespec timeout={.tv_sec=2};
    code=io_uring_wait_cqe_timeout(&ring,&cqe,&timeout);if(code<0)goto close_pair;
    if(cqe->user_data==5 && cqe->res==-ECANCELED)original++;
    if(cqe->user_data==6 && cqe->res==0)cancel++;
    io_uring_cqe_seen(&ring,cqe);
  }
  code=original==1 && cancel==1?0:-EPROTO;
close_pair:
  close(sockets[0]);close(sockets[1]);
  if(code<0)goto done;
  if(strcmp(phase,"cancel_pending_recv")){code=-EIO;goto done;}

  phase="timeout";
  struct __kernel_timespec delay={.tv_nsec=1000000};
  sqe=io_uring_get_sqe(&ring);io_uring_prep_timeout(sqe,&delay,0,0);sqe->user_data=7;
  if(submit(&ring)<0){code=-EIO;goto done;}
  code=completion(&ring,7);if(code!=-ETIME){code=code<0?code:-EPROTO;goto done;}

  phase="accept";
  int listener=socket(AF_INET,SOCK_STREAM|SOCK_CLOEXEC,0),client=-1;
  if(listener<0){code=-errno;goto done;}
  struct sockaddr_in addr={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
  socklen_t size=sizeof(addr);
  if(bind(listener,(struct sockaddr*)&addr,size) || listen(listener,1) || getsockname(listener,(struct sockaddr*)&addr,&size)) {code=-errno;close(listener);goto done;}
  client=socket(AF_INET,SOCK_STREAM|SOCK_CLOEXEC,0);
  if(client<0 || connect(client,(struct sockaddr*)&addr,size)){code=-errno;if(client>=0)close(client);close(listener);goto done;}
  sqe=io_uring_get_sqe(&ring);io_uring_prep_accept(sqe,listener,NULL,NULL,SOCK_CLOEXEC);sqe->user_data=8;
  if(submit(&ring)<0)code=-EIO;else code=completion(&ring,8);
  if(code>=0){close(code);code=0;}
  close(client);close(listener);
  if(code==0)phase="complete";
done:
  /* Ring teardown completes kernel cancellation before stack buffers go away. */
  io_uring_queue_exit(&ring);
  printf("{\"schema\":1,\"available\":%s,\"phase\":\"%s\",\"errno\":%d,\"features\":%u,\"liburing\":\"2.9\",\"scope\":\"setup/opcodes/nop/read/send/recv/cancel/timeout/accept\"}\n",code==0?"true":"false",phase,code<0?-code:0,params.features);
  return code==0?0:1;
}
