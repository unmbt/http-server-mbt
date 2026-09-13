///|
/// ANSI SGR reset-to-default foreground used to close every colored segment,
/// matching the original's chalk output (\x1b[3xm ... \x1b[39m).
let color_reset_suffix : String = "\u{1b}[39m"

///|
/// Wrap text in an SGR foreground-color pair, mirroring the original's
/// chalk usage: yellow 33 (labels), cyan 36 (enabled values), green 32
/// (ports), red 31 (disabled/false values). When colors are disabled the
/// text is emitted verbatim.
fn colorize(enabled : Bool, code : String, text : String) -> String {
  if enabled {
    "\u{1b}[\{code}m\{text}\{color_reset_suffix}"
  } else {
    text
  }
}

///|
fn yellow(enabled : Bool, text : String) -> String {
  colorize(enabled, "33", text)
}

///|
fn cyan(enabled : Bool, text : String) -> String {
  colorize(enabled, "36", text)
}

///|
fn green(enabled : Bool, text : String) -> String {
  colorize(enabled, "32", text)
}

///|
fn red(enabled : Bool, text : String) -> String {
  colorize(enabled, "31", text)
}

///|
/// Decide whether the startup banner uses ANSI colors, approximating the
/// original's chalk/supports-color semantics: FORCE_COLOR wins first, then
/// NO_COLOR, then TERM=dumb, and otherwise colors require a stdout TTY.
fn colors_enabled_for(is_tty : Bool, get_env : (String) -> String?) -> Bool {
  match get_env("FORCE_COLOR") {
    Some(value) => return !(value == "0" || value == "false")
    None => ()
  }
  match get_env("NO_COLOR") {
    Some(value) => if value.length() > 0 { return false }
    None => ()
  }
  match get_env("TERM") {
    Some("dumb") => return false
    _ => ()
  }
  is_tty
}

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn is_stdout_tty_ffi() -> Int = "http_server_cli_is_stdout_tty"

///|
#cfg(not(any(target="native", target="llvm")))
fn is_stdout_tty_ffi() -> Int {
  1
}

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn flush_stdout_ffi() -> Int = "http_server_cli_flush_stdout"

///|
#cfg(not(any(target="native", target="llvm")))
fn flush_stdout_ffi() -> Int {
  0
}

///|
/// Flush C stdout immediately: when stdout is a pipe or file the C runtime
/// buffers fully, and a long-running server would otherwise hide the banner
/// and stop message until process exit (the original's Node writes surface
/// right away).
fn flush_stdout() -> Unit {
  let _ = flush_stdout_ffi()
}

///|
/// Whether the current process should colorize the startup banner.
fn colors_enabled() -> Bool {
  colors_enabled_for(is_stdout_tty_ffi() == 1, name => @env.get_env_var(name))
}
