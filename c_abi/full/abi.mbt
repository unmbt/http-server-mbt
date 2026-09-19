///|
extern "C" fn hs_bridge_get_port(server_ptr : Int64) -> Int = "hs_bridge_get_port"

///|
extern "C" fn hs_bridge_get_spa(server_ptr : Int64) -> Int = "hs_bridge_get_spa"

///|
extern "C" fn hs_bridge_get_cors(server_ptr : Int64) -> Int = "hs_bridge_get_cors"

///|
extern "C" fn hs_bridge_get_silent(server_ptr : Int64) -> Int = "hs_bridge_get_silent"

///|
extern "C" fn hs_bridge_get_auto_index(server_ptr : Int64) -> Int = "hs_bridge_get_auto_index"

///|
extern "C" fn hs_bridge_get_show_dir(server_ptr : Int64) -> Int = "hs_bridge_get_show_dir"

///|
extern "C" fn hs_bridge_get_cache_seconds(server_ptr : Int64) -> Int = "hs_bridge_get_cache_seconds"

///|
extern "C" fn hs_bridge_get_root(server_ptr : Int64) -> String = "hs_bridge_get_root"

///|
extern "C" fn hs_bridge_get_try_files(server_ptr : Int64) -> String = "hs_bridge_get_try_files"

///|
extern "C" fn hs_bridge_get_cert_file(server_ptr : Int64) -> String = "hs_bridge_get_cert_file"

///|
extern "C" fn hs_bridge_get_key_file(server_ptr : Int64) -> String = "hs_bridge_get_key_file"

///|
extern "C" fn hs_bridge_get_key_passphrase(server_ptr : Int64) -> String = "hs_bridge_get_key_passphrase"

///|
extern "C" fn hs_bridge_get_proxy(server_ptr : Int64) -> String = "hs_bridge_get_proxy"

///|
extern "C" fn hs_bridge_get_proxy_all(server_ptr : Int64) -> String = "hs_bridge_get_proxy_all"

///|
extern "C" fn hs_bridge_notify_ready(server_ptr : Int64, status : Int) -> Unit = "hs_bridge_notify_ready"

///|
extern "C" fn hs_bridge_is_stopped(server_ptr : Int64) -> Int = "hs_bridge_is_stopped"

///|
#export_name("hs_abi_version")
pub fn hs_abi_version() -> UInt {
  0x00010000U
}

///|
#export_name("hs_full_run_server")
pub fn hs_full_run_server(server_ptr : Int64) -> Unit {
  let port = hs_bridge_get_port(server_ptr)
  let root = hs_bridge_get_root(server_ptr)
  let base_config = @core.Config::default(root)
  let try_files = hs_bridge_get_try_files(server_ptr)
  let tf_opt = if try_files != "" { Some(try_files) } else { None }
  let cert_file = hs_bridge_get_cert_file(server_ptr)
  let cf_opt = if cert_file != "" { Some(cert_file) } else { None }
  let key_file = hs_bridge_get_key_file(server_ptr)
  let kf_opt = if key_file != "" { Some(key_file) } else { None }
  let key_passphrase = hs_bridge_get_key_passphrase(server_ptr)
  let kp_opt = if key_passphrase != "" { Some(key_passphrase) } else { None }
  let proxy = hs_bridge_get_proxy(server_ptr)
  let px_opt = if proxy != "" { Some(proxy) } else { None }
  let proxy_all = hs_bridge_get_proxy_all(server_ptr)
  let pa_opt = if proxy_all != "" { Some(proxy_all) } else { None }

  let config : @core.Config = {
    ..base_config,
    port,
    spa: hs_bridge_get_spa(server_ptr) != 0,
    cors: hs_bridge_get_cors(server_ptr) != 0,
    silent: hs_bridge_get_silent(server_ptr) != 0,
    auto_index: hs_bridge_get_auto_index(server_ptr) != 0,
    show_dir: hs_bridge_get_show_dir(server_ptr) != 0,
    cache_seconds: hs_bridge_get_cache_seconds(server_ptr),
    try_files: tf_opt,
    cert_file: cf_opt,
    key_file: kf_opt,
    key_passphrase: kp_opt,
    proxy: px_opt,
    proxy_all: pa_opt,
  }

  @async.run_async_main(async fn() {
    @full_server.with_server_at(config, port, async fn(_server) {
      hs_bridge_notify_ready(server_ptr, 0)
      while hs_bridge_is_stopped(server_ptr) == 0 {
        @async.sleep(20)
      }
    }) catch {
      _ => hs_bridge_notify_ready(server_ptr, 3)
    }
  })
}
