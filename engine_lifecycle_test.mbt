///|
async fn response_for(engine : @http-server-mbt.StaticEngine,path : String,headers? : Map[String,String] = Map([])) -> @http-server-mbt.Response {
  match engine.handle({meth:Get,target:path,headers}) {
    Handled(response) => response
    _ => fail("expected file response")
  }
}
///|
async test "N-20 mutation matrix including Range and final EOF check" {
  let dir=@fs.tmpdir(prefix="hs-n20-")
  defer @fs.rmdir(dir,recursive=true)
  for replacement in ["ABCDEFGHIJ","abcdefghijklmnop","a"] {
    @fs.write_file(dir+"/file","abcdefghij")
    @http-server-mbt.with_engine(@core.Config::default(dir),engine => {
      let response=response_for(engine,"/file",headers=Map([("Range","bytes=2-7")]))
      assert_eq(response.status,206)
      assert_eq(response.read(max_len=2),b"cd")
      @fs.write_file(dir+"/file",replacement)
      let changed=try { ignore(response.read()); false } catch { @http-server-mbt.ServerError::FileChanged(_) => true; _ => false }
      assert_true(changed)
    })
  }
  @fs.write_file(dir+"/file","abcdefghij")
  @http-server-mbt.with_engine(@core.Config::default(dir),engine => {
    let response=response_for(engine,"/file")
    assert_eq(response.read(),b"abcdefghij")
    @fs.write_file(dir+"/file","changed!!!")
    let changed=try { ignore(response.read()); false } catch { @http-server-mbt.ServerError::FileChanged(_) => true; _ => false }
    assert_true(changed)
  })
}
///|
async test "N-20 replacement and deletion keep the opened representation" {
  let dir=@fs.tmpdir(prefix="hs-n20-swap-")
  defer @fs.rmdir(dir,recursive=true)
  @fs.write_file(dir+"/file","old-version")
  @http-server-mbt.with_engine(@core.Config::default(dir),engine => {
    let response=response_for(engine,"/file")
    @fs.write_file(dir+"/replacement","new-version")
    @fs.rename(dir+"/replacement",dir+"/file",replace=true)
    assert_eq(response.to_bytes(max_bytes=64),b"old-version")
    response.close()
    let next=response_for(engine,"/file")
    @fs.remove(dir+"/file")
    assert_eq(next.to_bytes(max_bytes=64),b"new-version")
  })
}
///|
async test "N-21 close invalidates unconsumed responses and is instance-local" {
  let first=@http-server-mbt.StaticEngine::open(@core.Config::default("testdata/public"))
  defer first.close()
  let second=@http-server-mbt.StaticEngine::open(@core.Config::default("testdata/public"))
  defer second.close()
  let response=response_for(first,"/hello.txt")
  first.close()
  first.close()
  assert_true(first.handle({meth:Get,target:"/hello.txt",headers:Map([])}) is Error(@http-server-mbt.ServerError::Closed))
  let closed=try { ignore(response.read()); false } catch { @http-server-mbt.ServerError::Closed => true; _ => false }
  assert_true(closed)
  assert_eq(response_for(second,"/hello.txt").to_bytes(max_bytes=64),b"hello moonbit\n")
}
///|
async test "N-21 scope exit on failure closes resources" {
  let escaped : Ref[@http-server-mbt.Response?]=Ref(None)
  try @http-server-mbt.with_engine(@core.Config::default("testdata/public"),engine => {
    escaped.val=Some(response_for(engine,"/hello.txt"))
    fail("intentional scope failure")
  }) catch { _ => () }
  let closed=try { ignore(escaped.val.unwrap().read()); false } catch { @http-server-mbt.ServerError::Closed => true; _ => false }
  assert_true(closed)
}
