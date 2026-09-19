///|
/// Root spelling shown in the banner. The original stores the defaulted root
/// as './' and prints it verbatim; our default root stays "." per D-01, so
/// only that case is displayed with the original's './' spelling.
fn display_root(root : String) -> String {
  if root == "." {
    "./"
  } else {
    root
  }
}

///|
/// URL path appended to every "Available on:" address. The original appends
/// the raw baseDir and omits the suffix entirely when unset; our normalized
/// base_url is "/" in that case.
fn available_path_suffix(base_url : String) -> String {
  if base_url == "/" {
    ""
  } else {
    base_url
  }
}

///|
/// The "http-server settings: " block lines in the original's order, reading
/// the effective config values (labels yellow; enabled values cyan, disabled
/// ones red). Directory Listings/AutoIndex show the effective visibility;
/// the original instead tests raw `-d`/`-i` CLI flag truthiness, which
/// inverts the display when the flags are passed explicitly (see D-19).
fn settings_block(config : @core.Config, color : Bool) -> String {
  fn state(enabled : Bool, on : String, off : String) -> String {
    if enabled {
      cyan(color, on)
    } else {
      red(color, off)
    }
  }

  let cache_value = if config.cache_seconds == -1 {
    red(color, "disabled")
  } else {
    cyan(color, "\{config.cache_seconds} seconds")
  }
  let timeout_value = if config.idle_timeout_ms == 0 {
    red(color, "disabled")
  } else {
    cyan(color, "\{config.idle_timeout_ms / 1000} seconds")
  }
  let ext_value = match config.default_ext {
    Some(ext) => cyan(color, ext)
    None => red(color, "none")
  }
  [
    "COOP: " +
    state(config.coop, config.coop_header.unwrap_or("true"), "disabled"),
    "CORS: " +
    state(config.cors, config.cors_headers.unwrap_or("true"), "disabled"),
    "Private Network Access: " + state(config.pna, "true", "disabled"),
    "Cache: " + cache_value,
    "Connection Timeout: " + timeout_value,
    "Directory Listings: " + state(config.show_dir, "visible", "not visible"),
    "AutoIndex: " + state(config.auto_index, "visible", "not visible"),
    "Serve GZIP Files: " + state(config.gzip, "true", "false"),
    "Serve Brotli Files: " + state(config.brotli, "true", "false"),
    "Default File Extension: " + ext_value,
    "Base directory: " + cyan(color, config.base_url),
  ].join("\n")
}

///|
/// Build the complete startup banner text reproducing the original's
/// listen-callback output: startup line, version, settings block, optional
/// additional headers, available addresses (given non-loopback IPs first,
/// loopback last as the original enumerates on Windows) and the CTRL-C hint.
/// The returned text ends with a newline so the caller's `println` produces
/// the original's blank spacing line before request logs. Colors follow the
/// original's chalk usage: yellow labels, cyan enabled values, red disabled
/// ones, green ports, and no color for the hint line.
fn startup_banner(
  config : @core.Config,
  port : Int,
  version : String,
  ips : Array[String],
  color : Bool,
) -> String {
  let start_line = yellow(color, "Starting up http-server, serving ") +
    cyan(color, display_root(config.root))
  let version_line = yellow(color, "\nhttp-server version: ") +
    cyan(color, version)
  let mut settings = yellow(color, "\nhttp-server settings: ") +
    "\n" +
    settings_block(config, color)
  if config.custom_headers.length() > 0 {
    settings = settings + "\n" + yellow(color, "Additional Headers:")
    for key, value in config.custom_headers {
      settings = settings +
        "\n" +
        yellow(color, "\t\{key}:") +
        cyan(color, " \{value}")
    }
  }
  let port_text = green(color, port.to_string())
  let suffix = available_path_suffix(config.base_url)
  let mut available = yellow(color, "\nAvailable on:")
  for ip in ips {
    available = available + "\n  http://\{ip}:" + port_text + suffix
  }
  available = available + "\n  http://127.0.0.1:" + port_text + suffix
  "\{start_line}\n\{version_line}\n\{settings}\n\{available}\nHit CTRL-C to stop the server\n"
}

///|
/// Print the original's startup banner for a listening server; silent mode
/// suppresses every banner line, as the original's null logger does.
fn print_startup_banner(config : @core.Config, port : Int) -> Unit {
  if !config.silent {
    println(
      startup_banner(
        config,
        port,
        server_version,
        local_ips(),
        colors_enabled(),
      ),
    )
    flush_stdout()
  }
}
