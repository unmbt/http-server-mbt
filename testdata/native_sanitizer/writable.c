/* N-24 / D-05: real backpressure cannot consume the only file worker.
 * Linux-only syscall integration test; orchestration lives in .mbtx. */
#define _GNU_SOURCE
#include <assert.h>
#define HS_IO_TESTING
#include "../../internal/native/native.c"
#undef assert
#define assert(x) do { if(!(x)) { fprintf(stderr,"ASSERT %s:%d: %s\n",__FILE__,__LINE__,#x);abort(); } } while(0)
moonbit_bytes_t moonbit_make_bytes(int32_t n,int value) {
  unsigned char *b=malloc((size_t)n+1);assert(b);memset(b,value,(size_t)n+1);return b;
}
static void wait_job(hs_job *j) {
  assert(j);
  for(int i=0;!hs_io_done(j);i++){assert(i<5000);usleep(1000);}
}
int main(void) {
#ifdef __linux__
  int notify[2];assert(pipe2(notify,O_NONBLOCK|O_CLOEXEC)==0);
  hs_pool *pool=hs_io_pool_new(1,16,notify[1],1048576,1048576);assert(pool);
  hs_job *job=hs_io_submit(pool,0,NULL,"testdata/public",0,0,0);wait_job(job);assert(job->code==0);
  hs_file *root=hs_io_take_file(job);hs_io_job_free(job);
  job=hs_io_submit(pool,0,root,"hello.txt",0,0,0);wait_job(job);assert(job->code==0);
  hs_file *file=hs_io_take_file(job);hs_io_job_free(job);
  for(int round=0;round<32;round++) {
    int sockets[2];assert(socketpair(AF_UNIX,SOCK_STREAM|SOCK_NONBLOCK|SOCK_CLOEXEC,0,sockets)==0);
    int small=4096;assert(setsockopt(sockets[0],SOL_SOCKET,SO_SNDBUF,&small,sizeof(small))==0);
    char fill[4096]={0};while(send(sockets[0],fill,sizeof(fill),MSG_NOSIGNAL)>0){}
    assert(errno==EAGAIN);
    hs_job *blocked=hs_io_submit(pool,4,file,"",0,14,(uintptr_t)sockets[0]);assert(blocked);
    usleep(20000);
    assert(!hs_io_done(blocked));
    hs_job *read=hs_io_submit(pool,1,file,"",0,14,0);wait_job(read);assert(read->code==0 && read->value==14);
    hs_io_job_free(read);
    if(round%2==0) {
      hs_io_cancel(blocked);wait_job(blocked);assert(blocked->code==-9);
    } else {
      while(recv(sockets[1],fill,sizeof(fill),0)>0){}
      wait_job(blocked);assert(blocked->code==0 && blocked->value==14);
    }
    hs_io_job_free(blocked);
    close(sockets[0]);close(sockets[1]); // Reuse descriptors on the next round.
  }
  hs_io_file_free(file);hs_io_file_free(root);hs_io_pool_free(pool);
  close(notify[0]);close(notify[1]);
  puts("32 backpressure/cancel/fd-reuse rounds drained; file worker remains available");
#endif
  return 0;
}
