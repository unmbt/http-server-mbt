///|
fn first_value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
fn parse_port(value : String) -> Int? {
  let chars = value.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut n = 0
  for c in chars {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + c.to_int() - '0'.to_int()
  }
  if n < 1 || n > 65535 {
    None
  } else {
    Some(n)
  }
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "http-server-mbt",
    about="Windows Native static HTTP server",
    version="0.1.5",
    disable_help_flag=true,
    disable_version_flag=true,
    flags=[
      @argparse.FlagArg("help", short='h', long="help", about="show help"),
      @argparse.FlagArg("version", long="version", about="show version"),
    ],
    options=[
      @argparse.OptionArg(
        "port",
        short='p',
        long="port",
        env="PORT",
        about="listen TCP port",
      ),
      @argparse.OptionArg("base-url", long="base-url", about="mount URL prefix"),
    ],
    positionals=[
      @argparse.PositionArg(
        "root",
        about="filesystem root",
        num_args=@argparse.ValueRange(lower=0, upper=1),
      ),
    ],
  )
}

///|
async fn run() -> Unit {
  let argv = @env.args()
  let command = command()
  let matches = command.parse(
    argv=if argv.length() > 1 { argv[1:] } else { [] },
  ) catch {
    _ => {
      println("error: failed to parse arguments")
      println(command.render_help())
      return
    }
  }
  if matches.flags.get("help") == Some(true) {
    println(command.render_help())
    return
  }
  if matches.flags.get("version") == Some(true) {
    println("http-server-mbt 0.1.5")
    return
  }
  let root = first_value(matches, "root").unwrap_or(".")
  let port = match first_value(matches, "port") {
    Some(value) =>
      match parse_port(value) {
        Some(port) => port
        None => {
          println("error: invalid port")
          return
        }
      }
    None => 8080
  }
  let base = first_value(matches, "base-url").unwrap_or("/")
  let config0 : @core.Config = @core.Config::default(root)
  let base_url = @core.normalize_base_url(base) catch {
    _ => {
      println("error: invalid base-url")
      return
    }
  }
  let config : @core.Config = { ..config0, base_url, }
  @server.with_server_at(config, port, async fn(_server) {
    println("Listening on port \{port}")
  }) catch {
    _ if @async.is_being_cancelled() => ()
    error => println("server error: \{error}")
  }
}

///|
fn main {
  @async.run_async_main(run)
}
