/* D-05 / N-24. One readiness waiter per owner, not per socket or file worker.
 * Included by native.c after job/queue/notification definitions. */
#ifdef __linux__
static void hs_wait_wakeup(hs_budget *b) {
  uint64_t value=1;
  ssize_t n;
  do { n=write(b->wait_wake,&value,sizeof(value)); } while(n<0 && errno==EINTR);
  /* EAGAIN means a wakeup is already pending. */
}
static void hs_wait_requeue(hs_budget *b,hs_job **entry,int error) {
  hs_job *j=*entry;hs_pool *p=j->pool;
  *entry=j->wait_next;j->wait_next=NULL;
  epoll_ctl(b->wait_epoll,EPOLL_CTL_DEL,(int)j->socket,NULL);
  b->waiting--;p->active--;
  j->wait_error=error;j->next=NULL;
  if(b->tail)b->tail->next=j;else b->head=j;
  b->tail=j;b->queued++;p->count++;
  hs_wake_all(&b->cond);
}
static void *hs_wait_loop(void *arg) {
  hs_budget *b=arg;
  struct epoll_event events[64];
  for(;;) {
    int n=epoll_wait(b->wait_epoll,events,64,-1);
    if(n<0 && errno==EINTR)continue;
    LOCK(&b->mutex);
    if(b->stopping){UNLOCK(&b->mutex);break;}
    if(n<0) {
      while(b->wait_head)hs_wait_requeue(b,&b->wait_head,-4);
      UNLOCK(&b->mutex);continue;
    }
    for(int i=0;i<n;i++) {
      uint64_t id=events[i].data.u64;
      if(!id) {
        uint64_t value;
        while(read(b->wait_wake,&value,sizeof(value))>0){}
        hs_job **entry=&b->wait_head;
        while(*entry) {
          hs_job *j=*entry;
          LOCK(&j->pool->mutex);int cancelled=j->cancelled;UNLOCK(&j->pool->mutex);
          if(cancelled)hs_wait_requeue(b,entry,0);else entry=&j->wait_next;
        }
      } else {
        /* Resolve a stable generation token, never a possibly recycled pointer. */
        hs_job **entry=&b->wait_head;
        while(*entry && (*entry)->id!=id)entry=&(*entry)->wait_next;
        if(*entry)hs_wait_requeue(b,entry,0);
      }
    }
    UNLOCK(&b->mutex);
  }
  return NULL;
}
static int hs_start_waiter(hs_budget *b) {
  if(b->wait_started)return 0;
  int ep=epoll_create1(EPOLL_CLOEXEC);if(ep<0)return -1;
  int wake=eventfd(0,EFD_CLOEXEC|EFD_NONBLOCK);
  if(wake<0){close(ep);return -1;}
  struct epoll_event event={0};event.events=EPOLLIN;event.data.u64=0;
  if(epoll_ctl(ep,EPOLL_CTL_ADD,wake,&event)) {close(ep);close(wake);return -1;}
  b->wait_epoll=ep;b->wait_wake=wake;
  if(pthread_create(&b->wait_thread,NULL,hs_wait_loop,b)) {close(ep);close(wake);return -1;}
  b->wait_started=1;
  return 0;
}
static int hs_defer_writable(hs_job *j) {
  hs_budget *b=j->pool->budget;
  LOCK(&b->mutex);
  if(hs_start_waiter(b)) {UNLOCK(&b->mutex);return -1;}
  struct epoll_event event={0};event.events=EPOLLOUT|EPOLLONESHOT;event.data.u64=j->id;
  if(epoll_ctl(b->wait_epoll,EPOLL_CTL_ADD,(int)j->socket,&event)) {UNLOCK(&b->mutex);return -1;}
  j->wait_next=b->wait_head;b->wait_head=j;b->waiting++;
  b->active--; /* The operation is still active for its pool, but frees a worker. */
  hs_wake_all(&b->cond);
  /* Closes cancellation-before-registration and readiness-before-wait races. */
  hs_wait_wakeup(b);
  UNLOCK(&b->mutex);
  return 0;
}
#endif
