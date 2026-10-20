/* Included at the end of native.c; platform-independent entry points. */
#ifdef _MSC_VER
__declspec(thread) static int hs_backend_error;
#else
static _Thread_local int hs_backend_error;
#endif
MOONBIT_FFI_EXPORT int hs_io_backend_error(void){return hs_backend_error;}
MOONBIT_FFI_EXPORT int hs_io_pool_backend(hs_pool *p){return p->backend;}
MOONBIT_FFI_EXPORT hs_pool *hs_io_pool_new_backend(int workers,int capacity,hs_fd notify,int body,int directory,int backend) {
  hs_backend_error=0;
  int platform=0;
#ifdef __linux__
  platform=2;
#elif defined(__APPLE__)
  platform=3;
#elif defined(_WIN32)
  platform=4;
#endif
  if(backend<0 || backend>6 || (backend>=2 && backend<=4 && backend!=platform)) {hs_backend_error=95;return NULL;}
#ifndef HS_HAS_URING
  if(backend==5 || backend==6){hs_backend_error=95;return NULL;}
#endif
  hs_pool *p=hs_io_pool_new(workers,capacity,notify,body,directory);
  if(!p)return NULL;
#ifdef HS_HAS_URING
  if(backend==1 || backend==5 || backend==6) {
    LOCK(&p->budget->mutex);int code=hs_ring_start(p->budget);UNLOCK(&p->budget->mutex);
    if(code<0) {
      if(backend!=1){hs_backend_error=-code;hs_io_pool_free(p);return NULL;}
    } else p->backend=backend==6?1:2;
  }
#endif
  return p;
}
MOONBIT_FFI_EXPORT hs_socket *hs_net_listen(hs_pool *p,int port) {
#ifdef HS_HAS_URING
  if(p->backend!=2 || port<0 || port>65535)return NULL;
  int fd=socket(AF_INET,SOCK_STREAM|SOCK_CLOEXEC,0);if(fd<0)return NULL;
  int one=1;setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
  struct sockaddr_in addr={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_ANY),.sin_port=htons((uint16_t)port)};
  if(bind(fd,(struct sockaddr*)&addr,sizeof(addr)) || listen(fd,SOMAXCONN)){close(fd);return NULL;}
  return hs_socket_new(p->budget,fd);
#else
  (void)p;(void)port;return NULL;
#endif
}
MOONBIT_FFI_EXPORT int hs_net_port(hs_socket *s) {
#ifdef HS_HAS_URING
  struct sockaddr_in addr;socklen_t length=sizeof(addr);
  return getsockname(s->fd,(struct sockaddr*)&addr,&length)?-1:ntohs(addr.sin_port);
#else
  (void)s;return -1;
#endif
}
MOONBIT_FFI_EXPORT void hs_net_close(hs_socket *s) {
#ifdef HS_HAS_URING
  hs_socket_release(s,1);
#else
  (void)s;
#endif
}
MOONBIT_FFI_EXPORT int hs_net_shutdown(hs_socket *s) {
#ifdef HS_HAS_URING
  return shutdown(s->fd,SHUT_WR)==0;
#else
  (void)s;return 0;
#endif
}
MOONBIT_FFI_EXPORT hs_socket *hs_net_take(hs_job *j) {
#ifdef HS_HAS_URING
  hs_socket *s=j->accepted;j->accepted=NULL;return s;
#else
  (void)j;return NULL;
#endif
}
MOONBIT_FFI_EXPORT hs_job *hs_net_submit(hs_pool *p,int operation,hs_socket *socket,const unsigned char *data,int length) {
#ifdef HS_HAS_URING
  if(p->backend!=2 || operation<5 || operation>8 || length<0)return NULL;
  hs_budget *b=p->budget;
  hs_job *j=calloc(1,sizeof(*j));if(!j)return NULL;
  j->pool=p;j->operation=operation;j->length=length;j->net=socket;
  if(operation==6 || operation==7) {
    j->data=malloc((size_t)length+1);if(!j->data){free(j);return NULL;}
    if(operation==7 && length)memcpy(j->data,data,(size_t)length);
  }
  if(operation==8){j->timeout.tv_sec=length/1000;j->timeout.tv_nsec=(length%1000)*1000000;}
  LOCK(&b->mutex);
  int limit=INT_MAX;for(hs_pool *q=b->pools;q;q=q->budget_next)if(q->capacity<limit)limit=q->capacity;
  if(p->stopping || !b->ring || b->ring->failed || (socket && socket->closing) || b->queued+b->ring_jobs+b->waiting>=limit) {
    UNLOCK(&b->mutex);free(j->data);free(j);return NULL;
  }
  j->id=++b->next_id;if(socket)socket->refs++;
  p->active++;hs_ring_enqueue(b->ring,j);
  UNLOCK(&b->mutex);return j;
#else
  (void)p;(void)operation;(void)socket;(void)data;(void)length;return NULL;
#endif
}
