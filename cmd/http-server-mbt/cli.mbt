///|
/// CLI action resulting from command-line argument parsing.
pub enum CliAction {
  Help(String)
  Version(String)
  Run(@core.Config, Int)
} derive(Debug)

///|
pub fn CliAction::to_string(self : CliAction) -> String {
  match self {
    Help(msg) => "Help(" + msg + ")"
    Version(msg) => "Version(" + msg + ")"
    Run(config, port) =>
      "Run(root=" + config.root + ", port=" + port.to_string() + ")"
  }
}

///|
pub impl Show for CliAction with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Build the declarative command specification using `@argparse`.
pub fn build_command() -> @argparse.Command {
  @argparse.Command(
    "http-server-mbt",
    about="Windows Native static HTTP server",
    version="\{server_version}",
    disable_help_flag=true,
    disable_version_flag=true,
    flags=[
      @argparse.FlagArg("help", short='h', long="help", about="Show help"),
      @argparse.FlagArg(
        "version",
        short='v',
        long="version",
        about="Show version",
      ),
      @argparse.FlagArg("spa", long="spa", about="Fallback to root index.html"),
      @argparse.FlagArg(
        "autoIndex",
        short='i',
        long="autoIndex",
        negatable=true,
        about="Display autoIndex [default: true]",
      ),
      @argparse.FlagArg(
        "showDir",
        short='d',
        long="showDir",
        negatable=true,
        about="Show directory listings [default: true]",
      ),
      @argparse.FlagArg("cors", long="cors", about="Enable CORS headers"),
      @argparse.FlagArg(
        "log-ip",
        short='l',
        long="log-ip",
        about="Log client IP address",
      ),
      @argparse.FlagArg(
        "silent",
        short='s',
        long="silent",
        about="Suppress log messages",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "port",
        short='p',
        long="port",
        env="PORT",
        about="Listen TCP port [default: 8080]",
      ),
      @argparse.OptionArg(
        "base-url",
        long="base-url",
        about="Mount URL prefix [default: /]",
      ),
      @argparse.OptionArg(
        "base-dir",
        long="base-dir",
        about="Alias for base-url",
      ),
      @argparse.OptionArg(
        "try-files",
        long="try-files",
        about="Custom fallback file relative to root",
      ),
      @argparse.OptionArg(
        "cache",
        short='c',
        long="cache",
        allow_hyphen_values=true,
        about="Cache duration in seconds or max-age [default: 3600]",
      ),
      @argparse.OptionArg(
        "auth",
        short='a',
        long="auth",
        about="Basic Auth credentials <username:password>",
      ),
      @argparse.OptionArg(
        "cert",
        long="cert",
        about="TLS certificate chain file (PEM) — enables HTTPS",
      ),
      @argparse.OptionArg("key", long="key", about="TLS private key file (PEM)"),
      @argparse.OptionArg(
        "key-passphrase",
        long="key-passphrase",
        env="TLS_KEY_PASSPHRASE",
        about="Passphrase for encrypted TLS private keys",
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "root",
        about="Filesystem root [default: .]",
        num_args=@argparse.ValueRange(lower=0, upper=1),
      ),
    ],
  )
}

///|
fn first_value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
/// Parse an integer string (supporting optional leading '-').
pub fn parse_integer(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let chars = s.to_array()
  let mut is_neg = false
  let mut start = 0
  if chars[0] == '-' {
    is_neg = true
    start = 1
  }
  if start >= chars.length() {
    return None
  }
  let mut n = 0
  for i = start; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + c.to_int() - '0'.to_int()
  }
  if is_neg {
    Some(-n)
  } else {
    Some(n)
  }
}

///|
/// Parse port from CLI value, supporting float truncation (e.g. "9090.86" -> 9090).
/// Rejects <= 0, > 65535, or non-numeric strings.
pub fn parse_port(value : String) -> Int? {
  let s = match value.find(".") {
    Some(idx) => value[:idx].to_owned()
    None => value
  }
  if s.length() == 0 {
    return None
  }
  let chars = s.to_array()
  let mut n = 0
  for c in chars {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + c.to_int() - '0'.to_int()
    if n > 65535 {
      return None
    }
  }
  if n < 1 || n > 65535 {
    None
  } else {
    Some(n)
  }
}

///|
/// Parse cache argument into (cache_seconds, cache_control).
pub fn parse_cache(val : String) -> Result[(Int, String?), String] {
  if val.has_prefix("max-age=") {
    let sec_str = val["max-age=".length():].to_owned()
    match parse_integer(sec_str) {
      Some(sec) =>
        if sec < 0 {
          Err("cache seconds in max-age cannot be negative")
        } else {
          Ok((sec, Some(val)))
        }
      None => Err("invalid cache value: '\{val}'")
    }
  } else {
    match parse_integer(val) {
      Some(sec) =>
        if sec < -1 {
          Err("cache duration cannot be less than -1")
        } else {
          Ok((sec, None))
        }
      None => Err("invalid cache value: '\{val}'")
    }
  }
}

///|
/// Parse basic auth string in "username:password" format.
pub fn parse_auth(val : String) -> Result[(String, String), String] {
  match val.find(":") {
    Some(idx) => {
      let username = val[:idx].to_owned()
      let password = val[idx + 1:].to_owned()
      if username.length() == 0 {
        return Err("auth username cannot be empty")
      }
      if username.contains("\u0000") || password.contains("\u0000") {
        return Err("auth credentials cannot contain null bytes")
      }
      Ok((username, password))
    }
    None => Err("invalid auth format: expected username:password")
  }
}

///|
/// Parse CLI arguments and validate configuration before server startup.
pub fn parse_cli(args : ArrayView[String]) -> Result[CliAction, String] {
  let cmd = build_command()
  let matches = cmd.parse(argv=args) catch {
    err => return Err(err.to_string())
  }
  if matches.flags.get("help") == Some(true) {
    return Ok(CliAction::Help(cmd.render_help()))
  }
  if matches.flags.get("version") == Some(true) {
    return Ok(CliAction::Version("\{server_version}"))
  }

  // 1. Port
  let port = match first_value(matches, "port") {
    Some(val) =>
      match parse_port(val) {
        Some(p) => p
        None =>
          return Err(
            "invalid port '\{val}': port must be an integer between 1 and 65535",
          )
      }
    None => 8080
  }

  // 2. Root positional
  let root = first_value(matches, "root").unwrap_or(".")

  // 3. Base URL / Base Dir
  let raw_base_url = first_value(matches, "base-url")
  let raw_base_dir = first_value(matches, "base-dir")
  let base_url = @core.resolve_base_url(raw_base_url, raw_base_dir) catch {
    err => return Err(err.to_string())
  }

  // 4. SPA & Try-Files
  let spa = matches.flags.get("spa").unwrap_or(false)
  let try_files = first_value(matches, "try-files")
  if spa && try_files is Some(_) {
    return Err(
      "cannot specify both --spa and --try-files (mutual exclusion violation)",
    )
  }

  // 5. autoIndex & showDir
  let auto_index = matches.flags.get("autoIndex").unwrap_or(true)
  let show_dir = matches.flags.get("showDir").unwrap_or(true)

  // 6. Cache
  let (cache_seconds, cache_control) = match first_value(matches, "cache") {
    Some(val) =>
      match parse_cache(val) {
        Ok(c) => c
        Err(err) => return Err(err)
      }
    None => (3600, None)
  }

  // 7. CORS
  let cors = matches.flags.get("cors").unwrap_or(false)

  // 8. Auth
  let basic_auth = match first_value(matches, "auth") {
    Some(val) =>
      match parse_auth(val) {
        Ok(a) => Some(a)
        Err(err) => return Err(err)
      }
    None => None
  }

  // 9. Logging
  let log_ip = matches.flags.get("log-ip").unwrap_or(false)
  let silent = matches.flags.get("silent").unwrap_or(false)

  // 10. TLS (D-08): cert+key enable HTTPS serving; passphrase may come from
  // the TLS_KEY_PASSPHRASE environment variable or the CLI option.
  let cert_file = first_value(matches, "cert")
  let key_file = first_value(matches, "key")
  let key_passphrase = first_value(matches, "key-passphrase")

  // 11. Construct Config
  let mut config = @core.Config::default(root)
  config = {
    ..config,
    port,
    base_url,
    spa,
    try_files,
    auto_index,
    show_dir,
    cache_seconds,
    cache_control,
    cors,
    basic_auth,
    log_ip,
    silent,
    cert_file,
    key_file,
    key_passphrase,
  }

  // 12. Core Validation
  config.validate() catch {
    err => return Err(err.to_string())
  }

  Ok(CliAction::Run(config, port))
}
