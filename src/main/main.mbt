async fn main {
  let args = @env.args()
  let mut port = 8080
  let mut addr = "0.0.0.0"
  let mut dir_listing = true
  let mut ext = "html"
  let mut cache_time = 3600
  let mut cors = false
  let mut proxy : String? = None
  let mut root_dir = "./"
  let mut debug = false

  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    match arg {
      "-p" | "--port" => {
        i += 1
        if i < args.length() {
          try {
            port = @string.parse_int(args[i])
          } catch {
            _ => println("Invalid port number")
          }
        }
      }
      "-a" => {
        i += 1
        if i < args.length() {
          addr = args[i]
        }
      }
      "-d" => {
        i += 1
        if i < args.length() {
          dir_listing = args[i] != "false"
        }
      }
      "-g" | "--gzip" => ()
      "-e" | "--ext" => {
        i += 1
        if i < args.length() {
          ext = args[i]
        }
      }
      "-c" => {
        i += 1
        if i < args.length() {
          try {
            cache_time = @string.parse_int(args[i])
          } catch {
            _ => ()
          }
        }
      }
      "--cors" => cors = true
      "-P" | "--proxy" => {
        i += 1
        if i < args.length() {
          proxy = Some(args[i])
        }
      }
      "-D" | "--debug" => debug = true
      _ => {
        if arg.has_prefix("-") == false {
          root_dir = arg
        }
      }
    }
    i += 1
  }

  let config = @server.Config::{
    port,
    addr,
    dir_listing,
    ext,
    cache_time,
    cors,
    proxy,
    root_dir,
    debug
  }
  
  try {
    @server.start_server(config)
  } catch {
    e => println("Server startup failed: \{e}")
  }
}
