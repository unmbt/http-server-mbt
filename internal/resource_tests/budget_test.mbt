///|
// Own test executable: intentionally lowering a shared-owner budget also
// constrains other engines, so this must not race unrelated static tests.
async test "N-23 directory admission is shared and HEAD does not enumerate" {
  let base={..@core.Config::default("testdata/public"),auto_index:false,dir_overrides_404:true}
  let config={..base,limits:{..base.limits,directory_metadata_bytes:16}}
  @static.with_engine(base,async fn(other) {
    @static.with_engine(config,async fn(engine) {
      for current in [engine,other] {
        assert_true(current.handle({meth:Get,target:"/",headers:Map([])}) is Error(@static.ServerError::Overloaded))
        let head=current.handle({meth:Head,target:"/",headers:Map([])})
        assert_true(head is Handled(_))
      }
    })
    match other.handle({meth:Get,target:"/",headers:Map([])}) {
      Handled(response) => assert_true(response.to_bytes(max_bytes=1048576).length()>0)
      _ => fail("budget was not restored after the restrictive instance closed")
    }
  })
}
///|
async test "N-23 shared admission and collection credits survive instance close" {
  let a=@native.Runtime::new(workers=1,capacity=1,connections=1,body_bytes=256)
  defer a.close()
  let b=@native.Runtime::new(workers=4,capacity=256,connections=4,body_bytes=1024)
  defer b.close()
  assert_true(@native.try_acquire_connection())
  assert_false(@native.try_acquire_connection())
  @native.release_connection()
  assert_true(@native.try_acquire_body(200))
  assert_false(@native.try_acquire_body(57))
  @native.release_body(200)
  a.reserve(directory=false,200)
  a.close()
  // Closing a runtime returns its outstanding owned credits to the shared pool.
  b.reserve(directory=false,1024)
  b.release(directory=false,1024)
  for _ in 0..<4 { assert_true(@native.try_acquire_connection()) }
  assert_false(@native.try_acquire_connection())
  for _ in 0..<4 { @native.release_connection() }
}
