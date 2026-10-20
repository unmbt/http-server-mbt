/* R-N04 / D-05 / T-023. C-owned completion reactor; no MoonBit calls here. */
#ifdef HS_HAS_URING
struct hs_socket { hs_budget *budget; int fd, refs, closing; };
struct hs_ring {
  hs_budget *budget;
  struct io_uring io;
  pthread_t thread;
  int wake, failed;
  hs_job *pending_head, *pending_tail, *active;
};
static void hs_ring_wakeup(hs_ring *r) {
  uint64_t one=1;ssize_t n;
  do {n=write(r->wake,&one,sizeof(one));}while(n<0 && errno==EINTR);
}
static hs_socket *hs_socket_new(hs_budget *b,int fd) {
  hs_socket *s=calloc(1,sizeof(*s));
  if(!s){close(fd);return NULL;}
  s->budget=b;s->fd=fd;s->refs=1;return s;
}
static void hs_socket_release(hs_socket *s,int closing) {
  hs_budget *b=s->budget;
  LOCK(&b->mutex);
  if(closing){s->closing=1;shutdown(s->fd,SHUT_RDWR);if(b->ring)hs_ring_wakeup(b->ring);}
  if(--s->refs==0){close(s->fd);free(s);}
  UNLOCK(&b->mutex);
}
static int hs_ring_cancelled(hs_job *j) {
  LOCK(&j->pool->mutex);int cancelled=j->cancelled;UNLOCK(&j->pool->mutex);
  return cancelled || (j->net && j->net->closing);
}
/* Called under the budget mutex. Publication ends all access to j. */
static void hs_ring_finish(hs_ring *r,hs_job *j,int result) {
  hs_budget *b=r->budget;hs_pool *p=j->pool;
  b->ring_jobs--;
  if(j->operation==1) {
    j->ring_completed=1;j->ring_result=result;j->ring_next=NULL;j->next=NULL;
    p->active--;p->count++;b->queued++;
    if(b->tail)b->tail->next=j;else b->head=j;b->tail=j;
    hs_wake_all(&b->cond);
    return;
  }
  int code=result<0?-4:0;
  if(j->operation==8 && result==-ETIME)code=0;
  if(j->operation==5 && result>=0) {
    j->accepted=hs_socket_new(b,result);
    if(!j->accepted)code=-7;
  }
  j->value=result>=0?result:0;
  LOCK(&p->mutex);
  if(j->cancelled || (j->net && j->net->closing) || result==-ECANCELED)code=-9;
  j->code=code;j->done=1;
  UNLOCK(&p->mutex);
  hs_notify(p);
  p->active--;
  hs_wake_all(&b->cond);
}
static void hs_ring_poll_wake(hs_ring *r) {
  struct io_uring_sqe *sqe=io_uring_get_sqe(&r->io);
  /* Two SQ slots are reserved for control operations before every submit. */
  if(!sqe)return;
  io_uring_prep_poll_add(sqe,r->wake,POLLIN);sqe->user_data=0;
}
static void hs_ring_prepare(hs_ring *r,hs_job *j,struct io_uring_sqe *sqe) {
  (void)r;
  switch(j->operation) {
    case 1: {
      int length=j->length-j->read_done;
#ifdef HS_IO_TESTING
      if(j->test_short>0 && length>j->test_short)length=j->test_short;
#endif
      io_uring_prep_read(sqe,j->file->fd,j->data+j->read_done,(unsigned)length,(uint64_t)(j->offset+j->read_done));break;
    }
    case 5:io_uring_prep_accept(sqe,j->net->fd,NULL,NULL,SOCK_CLOEXEC);break;
    case 6:io_uring_prep_recv(sqe,j->net->fd,j->data,(unsigned)j->length,0);break;
    case 7:io_uring_prep_send(sqe,j->net->fd,j->data,(unsigned)j->length,MSG_NOSIGNAL);break;
    case 8:io_uring_prep_timeout(sqe,&j->timeout,0,0);break;
  }
  sqe->user_data=j->id;
}
static void *hs_ring_loop(void *arg) {
  hs_ring *r=arg;hs_budget *b=r->budget;
  hs_ring_poll_wake(r);
  for(;;) {
    LOCK(&b->mutex);
    if(b->stopping){UNLOCK(&b->mutex);break;}
    while(r->pending_head && io_uring_sq_space_left(&r->io)>2) {
      hs_job *j=r->pending_head;r->pending_head=j->ring_next;
      if(!r->pending_head)r->pending_tail=NULL;
      if(hs_ring_cancelled(j)){hs_ring_finish(r,j,-ECANCELED);continue;}
      struct io_uring_sqe *sqe=io_uring_get_sqe(&r->io);
      hs_ring_prepare(r,j,sqe);j->cancel_sent=0;
      j->ring_next=r->active;r->active=j;
    }
    for(hs_job *j=r->active;j && io_uring_sq_space_left(&r->io)>1;j=j->ring_next) {
      if(!j->cancel_sent && hs_ring_cancelled(j)) {
        struct io_uring_sqe *sqe=io_uring_get_sqe(&r->io);
        io_uring_prep_cancel64(sqe,j->id,0);
        sqe->user_data=j->id|UINT64_C(0x8000000000000000);j->cancel_sent=1;
      }
    }
    UNLOCK(&b->mutex);
    int ret=io_uring_submit_and_wait(&r->io,1);
    if(ret==-EINTR)continue;
    if(ret<0) {
      /* No runtime fallback or retransmission. Tear down before releasing buffers. */
      io_uring_queue_exit(&r->io);
      LOCK(&b->mutex);r->failed=ret;
      while(r->active){hs_job *j=r->active;r->active=j->ring_next;hs_ring_finish(r,j,ret);}
      while(r->pending_head){hs_job *j=r->pending_head;r->pending_head=j->ring_next;hs_ring_finish(r,j,ret);}
      r->pending_tail=NULL;UNLOCK(&b->mutex);
      return NULL;
    }
    struct io_uring_cqe *cqe;
    while(io_uring_peek_cqe(&r->io,&cqe)==0) {
      uint64_t id=cqe->user_data;int result=cqe->res;
      io_uring_cqe_seen(&r->io,cqe);
      if(id & UINT64_C(0x8000000000000000))continue; // cancel ack is not final completion
      LOCK(&b->mutex);
      if(!id) {
        uint64_t value;while(read(r->wake,&value,sizeof(value))>0){}
        hs_ring_poll_wake(r);
      } else {
        hs_job **entry=&r->active;
        while(*entry && (*entry)->id!=id)entry=&(*entry)->ring_next;
        if(*entry){hs_job *j=*entry;*entry=j->ring_next;hs_ring_finish(r,j,result);}
      }
      UNLOCK(&b->mutex);
    }
  }
  io_uring_queue_exit(&r->io);
  return NULL;
}
static int hs_ring_start(hs_budget *b) {
  if(b->ring)return b->ring->failed;
  hs_ring *r=calloc(1,sizeof(*r));if(!r)return -ENOMEM;
  struct io_uring_params params={0};
  int code=io_uring_queue_init_params(256,&r->io,&params);
  if(code<0){free(r);return code;}
  struct io_uring_probe *probe=io_uring_get_probe_ring(&r->io);
  if(!probe){code=errno?-errno:-EIO;goto fail;}
  unsigned required[]={IORING_OP_ACCEPT,IORING_OP_RECV,IORING_OP_SEND,IORING_OP_READ,IORING_OP_TIMEOUT,IORING_OP_ASYNC_CANCEL,IORING_OP_POLL_ADD};
  for(unsigned i=0;i<sizeof(required)/sizeof(required[0]);i++)
    if(!io_uring_opcode_supported(probe,(int)required[i]))code=-EOPNOTSUPP;
  io_uring_free_probe(probe);if(code<0)goto fail;
  r->wake=eventfd(0,EFD_NONBLOCK|EFD_CLOEXEC);
  if(r->wake<0){code=-errno;goto fail;}
  r->budget=b;
  code=pthread_create(&r->thread,NULL,hs_ring_loop,r);
  if(code){close(r->wake);code=-code;goto fail;}
  b->ring=r;return 0;
fail:
  io_uring_queue_exit(&r->io);free(r);return code;
}
static void hs_ring_destroy(hs_ring *r) {
  pthread_join(r->thread,NULL);close(r->wake);free(r);
}
static void hs_ring_enqueue(hs_ring *r,hs_job *j) {
  j->ring_next=NULL;
  if(r->pending_tail)r->pending_tail->ring_next=j;else r->pending_head=j;
  r->pending_tail=j;r->budget->ring_jobs++;
  hs_ring_wakeup(r);
}
static int hs_ring_defer(hs_job *j) {
  hs_budget *b=j->pool->budget;
  LOCK(&b->mutex);
  if(!b->ring || b->ring->failed){UNLOCK(&b->mutex);return -1;}
  b->active--;hs_ring_enqueue(b->ring,j);hs_wake_all(&b->cond);
  UNLOCK(&b->mutex);return 0;
}
#endif
