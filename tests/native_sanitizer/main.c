/* D-18: exercises the production C owner/worker implementation under sanitizers.
 * The sole mock is the owner-thread MoonBit byte allocator; workers must never
 * call it. No network, runtime callbacks or generated MoonBit layout is mocked. */
#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#define HS_IO_TESTING
#include "../../internal/native/native.c"
#undef assert
#define assert(condition) do { if(!(condition)) { fprintf(stderr,"ASSERT %s:%d: %s\n",__FILE__,__LINE__,#condition);fflush(stderr);exit(1); } } while(0)

static unsigned allocations;
moonbit_bytes_t moonbit_make_bytes(int32_t size,int value) {
  unsigned char *data=malloc((size_t)size+1);
  assert(data);memset(data,value,(size_t)size);data[size]=0;allocations++;
  return data;
}
static void wait_job(hs_job *job) {
  assert(job);
  int attempts=0;
  while(!hs_io_done(job)) {
    assert(++attempts<10000);
#ifdef _WIN32
    Sleep(1);
#else
    usleep(1000);
#endif
  }
}
int main(int argc,char **argv) {
  assert(argc==4);
  setvbuf(stdout,NULL,_IONBF,0);
  hs_fd reader,writer;
#ifdef _WIN32
  assert(CreatePipe(&reader,&writer,NULL,65536));
#else
  int pipefds[2];assert(pipe(pipefds)==0);reader=pipefds[0];writer=pipefds[1];
#endif
  hs_pool *pool=hs_io_pool_new(4,8,writer,1048576,1048576);assert(pool);
  hs_job *open=hs_io_submit(pool,0,NULL,argv[1],0,0,0);wait_job(open);assert(open->code==0);
  hs_file *root=hs_io_take_file(open);hs_io_job_free(open);
  open=hs_io_submit(pool,0,root,"hello.txt",0,0,0);wait_job(open);assert(open->code==0);
  hs_file *file=hs_io_take_file(open);hs_io_job_free(open);
  uint32_t seed=(uint32_t)strtoul(argv[2],NULL,16),initial_seed=seed;
  unsigned rounds=(unsigned)strtoul(argv[3],NULL,10);assert(rounds>0 && rounds<=100000);
  unsigned accepted=0,rejected=0,cancelled=0,failed=0;
  uint64_t last=0;
  for(unsigned round=0;round<rounds;round++) {
    hs_job *jobs[16]={0};
    for(unsigned i=0;i<16;i++) {
      seed=seed*1664525u+1013904223u;
      hs_test_delay_ms=(seed%31==0)?10:0;
      hs_test_error=(seed%13==0)?-4:0;
      hs_test_short=(int)(seed%5)+1;
      jobs[i]=hs_io_submit(pool,1,file,"",0,14,0);
      if(!jobs[i]){rejected++;continue;}
      accepted++;assert(jobs[i]->id>last);last=jobs[i]->id;
      assert(jobs[i]->generation==file->generation);
      if(seed&1)hs_io_cancel(jobs[i]);
    }
    for(unsigned i=0;i<16;i++) {
      if(!jobs[i])continue;
      wait_job(jobs[i]);int code=hs_io_code(jobs[i]);assert(code==0 || code==-9 || code==-4);
      if(code==0){unsigned char *bytes=hs_io_bytes(jobs[i]);assert(memcmp(bytes,"hello moonbit\n",14)==0);free(bytes);}
      else if(code==-9)cancelled++;else failed++;
      hs_io_cancel(jobs[i]); // Late cancellation cannot alter published completion.
      assert(hs_io_done(jobs[i]));assert(hs_io_code(jobs[i])==code);
      hs_io_job_free(jobs[i]);
    }
    printf("replay=%08x round=%u accepted=%u rejected=%u cancelled=%u io_errors=%u\n",initial_seed,round,accepted,rejected,cancelled,failed);
  }
  assert(accepted && cancelled && allocations);
  hs_io_file_free(file);hs_io_file_free(root);hs_io_pool_free(pool);
#ifdef _WIN32
  CloseHandle(reader);CloseHandle(writer);
#else
  close(reader);close(writer);
#endif
  printf("seed=%08x rounds=%u accepted=%u rejected=%u cancelled=%u io_errors=%u; drained\n",initial_seed,rounds,accepted,rejected,cancelled,failed);
  return 0;
}
