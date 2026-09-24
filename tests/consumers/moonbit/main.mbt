///|
async fn verify_http(port : Int) -> Unit {
  let client=@http.Client("http://127.0.0.1:\{port}")
  defer client.close()
  assert_eq(client.get("/hello.txt").code,200)
  assert_eq(client.read_all().binary(),b"hello consumer\n")
}

///|
async fn run() -> Unit {
  let config=@core.Config::default("public")
  @static.with_engine(config, async fn(engine) {
    match engine.handle({meth:Get,target:"/hello.txt",headers:Map([])}) {
      Handled(response) => {
        defer response.close()
        assert_eq(response.to_bytes(max_bytes=1024),b"hello consumer\n")
      }
      _ => fail("static request failed")
    }
  })
  @thin.with_server_at(config,0,async fn(server) { verify_http(server.port()) })
  @full.with_server_at(config,0,async fn(server) { verify_http(server.port()) })
  println("external MoonBit consumer passed: engine / Thin / Full")
}

///|
fn main { @async.run_async_main(run) }
