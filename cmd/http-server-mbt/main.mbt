///|
fn main {
  @async.run_async_main(async fn() {
    @common.run(thin=false, async fn(config, port, ready) {
      @server.with_server_at(config,port,async fn(_server) { ready() })
    })
  })
}
