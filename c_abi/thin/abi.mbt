///|
pub fn hs_abi_version() -> UInt {
  0x00010001U
}

///|
fn owner() -> Unit {
  @runtime.run(true, async fn(config, ready) {
    @server.with_server_at(config, config.port, async fn(server) {
      ready(server.port())
    })
  })
}

///|
fn init {
  @runtime.register(fn() { owner() })
}
