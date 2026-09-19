///|
#cfg(any(target="native", target="llvm"))
extern "c" fn runtime_native_exit(code : Int) = "exit"

///|
#cfg(not(any(target="native", target="llvm")))
fn runtime_native_exit(code : Int) -> Unit {
  abort("exit(\{code})")
}

///|
async fn eprint_err(msg : String) -> Unit {
  @stdio.stderr.write(msg) catch {
    _ => ()
  }
}

///|
async fn run() -> Unit {
  let argv = @env.args()
  let args = if argv.length() > 1 { argv[1:] } else { [] }
  let (config, port) = match parse_cli(args) {
    Ok(Help(msg)) => {
      println(msg)
      return
    }
    Ok(Version(msg)) => {
      println(msg)
      return
    }
    Err(err) => {
      eprint_err("error: \{err}\n")
      runtime_native_exit(1)
      return
    }
    Ok(Run(config, port)) => (config, port)
  }

  // Pre-flight check: root directory
  // If root was defaulted to "." and "./public" exists & is a directory, use "public" per D-01
  let mut final_config = config
  if config.root == "." {
    let public_exists = @fs.exists("public")
    let is_public_dir = if public_exists {
      @fs.kind("public") == Directory
    } else {
      false
    }
    if is_public_dir {
      final_config = { ..final_config, root: "public", }
    }
  }

  // Verify final_config.root exists and is a directory
  let exists = @fs.exists(final_config.root) catch { _ => false }
  let is_dir = if exists {
    try @fs.kind(final_config.root) == Directory catch {
      _ => false
    }
  } else {
    false
  }
  if !is_dir {
    eprint_err(
      "error: root directory '\{final_config.root}' does not exist or is not a directory\n",
    )
    runtime_native_exit(1)
    return
  }

  // Thin build runs standard plain HTTP server (0 crypto/TLS/proxy dependencies)
  @server.with_server_at(final_config, port, async fn(_server) {
    print_startup_banner(final_config, port)
    @async.sleep(2147483647)
  }) catch {
    _ if @async.is_being_cancelled() =>
      if !final_config.silent {
        println(red(colors_enabled(), "http-server stopped."))
        flush_stdout()
      }
    error => {
      eprint_err("server error: \{error}\n")
      runtime_native_exit(1)
    }
  }
}

///|
fn main {
  @async.run_async_main(run)
}
