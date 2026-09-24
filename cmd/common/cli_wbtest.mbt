///|
test "cli: default arguments" {
  let res = parse_cli([])
  match res {
    Ok(Run(config, port)) => {
      assert_eq(port, 8080)
      assert_eq(config.port, 8080)
      assert_eq(config.root, ".")
      assert_eq(config.base_url, "/")
      assert_eq(config.auto_index, true)
      assert_eq(config.show_dir, true)
      assert_eq(config.cache_seconds, 3600)
      assert_eq(config.cache_control, None)
      assert_eq(config.cors, false)
      assert_eq(config.gzip, false)
      assert_eq(config.brotli, false)
      assert_eq(config.basic_auth, None)
      assert_eq(config.spa, false)
      assert_eq(config.try_files, None)
      assert_eq(config.log_ip, false)
      assert_eq(config.silent, false)
    }
    _ => fail("expected Ok(Run)")
  }
}

///|
test "cli: help flag" {
  match parse_cli(["-h"]) {
    Ok(Help(msg)) => assert_true(msg.contains("Usage:"))
    _ => fail("expected Ok(Help)")
  }
  match parse_cli(["--help"]) {
    Ok(Help(msg)) => assert_true(msg.contains("Usage:"))
    _ => fail("expected Ok(Help)")
  }
}

///|
test "cli: version flag" {
  match parse_cli(["-v"]) {
    Ok(Version(msg)) => assert_eq(msg, "\{server_version}")
    _ => fail("expected Ok(Version)")
  }
  match parse_cli(["--version"]) {
    Ok(Version(msg)) => assert_eq(msg, "\{server_version}")
    _ => fail("expected Ok(Version)")
  }
}

///|
test "cli: port variations" {
  // short flag
  match parse_cli(["-p", "9000"]) {
    Ok(Run(config, port)) => {
      assert_eq(port, 9000)
      assert_eq(config.port, 9000)
    }
    _ => fail("expected port 9000")
  }
  // long flag
  match parse_cli(["--port", "3000"]) {
    Ok(Run(config, port)) => {
      assert_eq(port, 3000)
      assert_eq(config.port, 3000)
    }
    _ => fail("expected port 3000")
  }
  // inline long flag
  match parse_cli(["--port=4000"]) {
    Ok(Run(config, port)) => {
      assert_eq(port, 4000)
      assert_eq(config.port, 4000)
    }
    _ => fail("expected port 4000")
  }
  // float truncation per AD-04 / C033
  match parse_cli(["-p", "9090.86"]) {
    Ok(Run(config, port)) => {
      assert_eq(port, 9090)
      assert_eq(config.port, 9090)
    }
    _ => fail("expected port 9090 from float truncation")
  }
}

///|
test "cli: port error validation" {
  // port 0 rejected in CLI
  assert_true(parse_cli(["-p", "0"]) is Err(_))
  // negative port rejected
  assert_true(parse_cli(["-p", "-1"]) is Err(_))
  // port > 65535 rejected
  assert_true(parse_cli(["-p", "65536"]) is Err(_))
  assert_true(parse_cli(["-p", "99999"]) is Err(_))
  // non-numeric rejected
  assert_true(parse_cli(["-p", "abc"]) is Err(_))
  assert_true(parse_cli(["-p", ".86"]) is Err(_))
}

///|
test "cli: root positional argument" {
  match parse_cli(["my_public_dir"]) {
    Ok(Run(config, _port)) => assert_eq(config.root, "my_public_dir")
    _ => fail("expected root my_public_dir")
  }
  match parse_cli(["-p", "8000", "dist"]) {
    Ok(Run(config, port)) => {
      assert_eq(port, 8000)
      assert_eq(config.root, "dist")
    }
    _ => fail("expected root dist with port 8000")
  }
}

///|
test "cli: base-url and base-dir" {
  // --base-url
  match parse_cli(["--base-url", "/app"]) {
    Ok(Run(config, _)) => assert_eq(config.base_url, "/app")
    _ => fail("expected base_url /app")
  }
  // --base-dir alias
  match parse_cli(["--base-dir", "/app"]) {
    Ok(Run(config, _)) => assert_eq(config.base_url, "/app")
    _ => fail("expected base_dir /app")
  }
  // normalization without leading slash
  match parse_cli(["--base-url", "app"]) {
    Ok(Run(config, _)) => assert_eq(config.base_url, "/app")
    _ => fail("expected normalized /app")
  }
  // both matching
  match parse_cli(["--base-url", "/app", "--base-dir", "app"]) {
    Ok(Run(config, _)) => assert_eq(config.base_url, "/app")
    _ => fail("expected matching base-url and base-dir to resolve to /app")
  }
  // conflict rejection
  assert_true(
    parse_cli(["--base-url", "/app", "--base-dir", "/other"]) is Err(_),
  )
  // invalid characters
  assert_true(parse_cli(["--base-url", "/app?query"]) is Err(_))
}

///|
test "cli: spa and try-files" {
  // --spa
  match parse_cli(["--spa"]) {
    Ok(Run(config, _)) => {
      assert_eq(config.spa, true)
      assert_eq(config.try_files, None)
    }
    _ => fail("expected spa=true")
  }
  // --try-files
  match parse_cli(["--try-files", "fallback.html"]) {
    Ok(Run(config, _)) => {
      assert_eq(config.spa, false)
      assert_eq(config.try_files, Some("fallback.html"))
    }
    _ => fail("expected try_files=Some(fallback.html)")
  }
  // mutual exclusion rejection
  assert_true(parse_cli(["--spa", "--try-files", "fallback.html"]) is Err(_))
  // invalid try-files path rejection (starts with /)
  assert_true(parse_cli(["--try-files", "/root.html"]) is Err(_))
  // invalid try-files path rejection (dot segment)
  assert_true(parse_cli(["--try-files", "../escape.html"]) is Err(_))
}

///|
test "cli: autoIndex and showDir negatable flags" {
  // default: both true
  match parse_cli([]) {
    Ok(Run(config, _)) => {
      assert_eq(config.auto_index, true)
      assert_eq(config.show_dir, true)
    }
    _ => fail("expected default true")
  }
  // --no-autoIndex
  match parse_cli(["--no-autoIndex"]) {
    Ok(Run(config, _)) => {
      assert_eq(config.auto_index, false)
      assert_eq(config.show_dir, true)
    }
    _ => fail("expected auto_index=false")
  }
  // -i explicitly true
  match parse_cli(["-i"]) {
    Ok(Run(config, _)) => assert_eq(config.auto_index, true)
    _ => fail("expected auto_index=true")
  }
  // --no-showDir
  match parse_cli(["--no-showDir"]) {
    Ok(Run(config, _)) => {
      assert_eq(config.auto_index, true)
      assert_eq(config.show_dir, false)
    }
    _ => fail("expected show_dir=false")
  }
  // -d explicitly true
  match parse_cli(["-d"]) {
    Ok(Run(config, _)) => assert_eq(config.show_dir, true)
    _ => fail("expected show_dir=true")
  }
  // both disabled
  match parse_cli(["--no-autoIndex", "--no-showDir"]) {
    Ok(Run(config, _)) => {
      assert_eq(config.auto_index, false)
      assert_eq(config.show_dir, false)
    }
    _ => fail("expected both false")
  }
}

///|
test "cli: cache option" {
  // seconds
  match parse_cli(["-c", "60"]) {
    Ok(Run(config, _)) => {
      assert_eq(config.cache_seconds, 60)
      assert_eq(config.cache_control, None)
    }
    _ => fail("expected cache 60")
  }
  // -1 for no-cache
  match parse_cli(["-c", "-1"]) {
    Ok(Run(config, _)) => {
      assert_eq(config.cache_seconds, -1)
      assert_eq(config.cache_control, None)
    }
    _ => fail("expected cache -1")
  }
  // max-age=N
  match parse_cli(["--cache", "max-age=7200"]) {
    Ok(Run(config, _)) => {
      assert_eq(config.cache_seconds, 7200)
      assert_eq(config.cache_control, Some("max-age=7200"))
    }
    _ => fail("expected max-age=7200")
  }
  // negative < -1 rejected
  assert_true(parse_cli(["-c", "-2"]) is Err(_))
  // non-numeric rejected
  assert_true(parse_cli(["-c", "invalid"]) is Err(_))
}

///|
test "cli: cors flag" {
  match parse_cli(["--cors"]) {
    Ok(Run(config, _)) => assert_eq(config.cors, true)
    _ => fail("expected cors=true")
  }
}

///|
test "cli: gzip flag" {
  match parse_cli(["-g"]) {
    Ok(Run(config, _)) => assert_eq(config.gzip, true)
    _ => fail("expected gzip=true with -g")
  }
  match parse_cli(["--gzip"]) {
    Ok(Run(config, _)) => assert_eq(config.gzip, true)
    _ => fail("expected gzip=true with --gzip")
  }
}

///|
test "cli: brotli flag" {
  match parse_cli(["-b"]) {
    Ok(Run(config, _)) => assert_eq(config.brotli, true)
    _ => fail("expected brotli=true with -b")
  }
  match parse_cli(["--brotli"]) {
    Ok(Run(config, _)) => assert_eq(config.brotli, true)
    _ => fail("expected brotli=true with --brotli")
  }
}

///|
test "cli: auth option" {
  // -a
  match parse_cli(["-a", "user:pass"]) {
    Ok(Run(config, _)) => assert_eq(config.basic_auth, Some(("user", "pass")))
    _ => fail("expected user:pass")
  }
  // --auth
  match parse_cli(["--auth", "admin:s3cr3t"]) {
    Ok(Run(config, _)) =>
      assert_eq(config.basic_auth, Some(("admin", "s3cr3t")))
    _ => fail("expected admin:s3cr3t")
  }
  // password with colon
  match parse_cli(["--auth=alice:p:w:d"]) {
    Ok(Run(config, _)) => assert_eq(config.basic_auth, Some(("alice", "p:w:d")))
    _ => fail("expected alice:p:w:d")
  }
  // empty username rejected
  assert_true(parse_cli(["-a", ":pass"]) is Err(_))
  // missing colon rejected
  assert_true(parse_cli(["-a", "nopassword"]) is Err(_))
}

///|
test "cli: logging flags" {
  // log-ip
  match parse_cli(["-l"]) {
    Ok(Run(config, _)) => assert_eq(config.log_ip, true)
    _ => fail("expected log_ip=true")
  }
  match parse_cli(["--log-ip"]) {
    Ok(Run(config, _)) => assert_eq(config.log_ip, true)
    _ => fail("expected log_ip=true")
  }
  // silent
  match parse_cli(["-s"]) {
    Ok(Run(config, _)) => assert_eq(config.silent, true)
    _ => fail("expected silent=true")
  }
  match parse_cli(["--silent"]) {
    Ok(Run(config, _)) => assert_eq(config.silent, true)
    _ => fail("expected silent=true")
  }
}

///|
test "cli: unknown argument rejected" {
  assert_true(parse_cli(["--bad-option"]) is Err(_))
  assert_true(parse_cli(["-x"]) is Err(_))
}

///|
test "cli: parse_port helper coverage" {
  assert_eq(parse_port("8080"), Some(8080))
  assert_eq(parse_port("1"), Some(1))
  assert_eq(parse_port("65535"), Some(65535))
  assert_eq(parse_port("9090.86"), Some(9090))
  assert_eq(parse_port("80.0"), Some(80))
  assert_eq(parse_port("0"), None)
  assert_eq(parse_port("-1"), None)
  assert_eq(parse_port("65536"), None)
  assert_eq(parse_port("abc"), None)
  assert_eq(parse_port(""), None)
  assert_eq(parse_port(".80"), None)
}

///|
test "cli: parse_cache helper coverage" {
  match parse_cache("3600") {
    Ok((sec, control)) => {
      assert_eq(sec, 3600)
      assert_eq(control, None)
    }
    _ => fail("expected parse_cache(3600)")
  }
  match parse_cache("-1") {
    Ok((sec, control)) => {
      assert_eq(sec, -1)
      assert_eq(control, None)
    }
    _ => fail("expected parse_cache(-1)")
  }
  match parse_cache("max-age=60") {
    Ok((sec, control)) => {
      assert_eq(sec, 60)
      assert_eq(control, Some("max-age=60"))
    }
    _ => fail("expected parse_cache(max-age=60)")
  }
  assert_true(parse_cache("-2") is Err(_))
  assert_true(parse_cache("bad") is Err(_))
  assert_true(parse_cache("max-age=-1") is Err(_))
}

///|
test "cli: default banner reproduces the original layout without colors" {
  let config = @core.Config::default(".")
  let banner = startup_banner(config, 8080, "0.1.5", ["192.168.1.5"], false)
  inspect(
    banner,
    content=(
      #|Starting up http-server, serving ./
      #|
      #|http-server version: 0.1.5
      #|
      #|http-server settings: 
      #|COOP: disabled
      #|CORS: disabled
      #|Private Network Access: disabled
      #|Cache: 3600 seconds
      #|Connection Timeout: 120 seconds
      #|Directory Listings: visible
      #|AutoIndex: visible
      #|Serve GZIP Files: false
      #|Serve Brotli Files: false
      #|Default File Extension: html
      #|Base directory: /
      #|
      #|Available on:
      #|  http://192.168.1.5:8080
      #|  http://127.0.0.1:8080
      #|Hit CTRL-C to stop the server
      #|
    ),
  )
}

///|
test "cli: banner wraps segments in ANSI colors like the original chalk output" {
  let config = @core.Config::default(".")
  let banner = startup_banner(config, 8080, "0.1.5", [], true)
  assert_true(
    banner.contains("\u{1b}[33mStarting up http-server, serving \u{1b}[39m"),
  )
  assert_true(banner.contains("\u{1b}[36m./\u{1b}[39m"))
  assert_true(banner.contains("\u{1b}[33m\nhttp-server version: \u{1b}[39m"))
  assert_true(banner.contains("\u{1b}[36m0.1.5\u{1b}[39m"))
  assert_true(banner.contains("\u{1b}[33m\nhttp-server settings: \u{1b}[39m"))
  assert_true(banner.contains("\u{1b}[31mdisabled\u{1b}[39m"))
  assert_true(banner.contains("\u{1b}[36mvisible\u{1b}[39m"))
  assert_true(banner.contains("\u{1b}[31mfalse\u{1b}[39m"))
  assert_true(banner.contains("\u{1b}[33m\nAvailable on:\u{1b}[39m"))
  assert_true(banner.contains("\u{1b}[32m8080\u{1b}[39m"))
  // The CTRL-C hint stays uncolored, like the original.
  assert_true(banner.contains("\nHit CTRL-C to stop the server\n"))
}

///|
test "cli: banner reflects the effective config values" {
  let config = {
    ..@core.Config::default("."),
    cache_seconds: -1,
    idle_timeout_ms: 0,
    show_dir: false,
    auto_index: false,
    gzip: true,
    brotli: true,
    cors: true,
    base_url: "/app",
    default_ext: Some("html"),
  }
  let banner = startup_banner(config, 9000, "0.1.5", [], false)
  assert_true(banner.contains("Cache: disabled"))
  assert_true(banner.contains("Connection Timeout: disabled"))
  assert_true(banner.contains("Directory Listings: not visible"))
  assert_true(banner.contains("AutoIndex: not visible"))
  assert_true(banner.contains("Serve GZIP Files: true"))
  assert_true(banner.contains("Serve Brotli Files: true"))
  assert_true(banner.contains("CORS: true"))
  assert_true(banner.contains("Default File Extension: html"))
  assert_true(banner.contains("Base directory: /app"))
  // The base_url mount prefix is appended to every advertised address.
  assert_true(banner.contains("  http://127.0.0.1:9000/app"))
  assert_true(banner.contains("\nHit CTRL-C to stop the server\n"))
}

///|
test "cli: banner lists loopback last and honors the root spelling" {
  let config = @core.Config::default(".")
  let banner = startup_banner(
    config,
    8080,
    "0.1.5",
    ["10.0.0.2", "10.0.0.1"],
    false,
  )
  let available = "Available on:\n  http://10.0.0.2:8080\n  http://10.0.0.1:8080\n  http://127.0.0.1:8080\n"
  assert_true(banner.contains(available))
  assert_eq(display_root("."), "./")
  assert_eq(display_root("public"), "public")
  assert_eq(available_path_suffix("/"), "")
  assert_eq(available_path_suffix("/app"), "/app")
}

///|
test "cli: color enablement follows the chalk-style env rules" {
  let none : Map[String, String] = Map([])
  assert_true(colors_enabled_for(true, name => none.get(name)))
  assert_false(colors_enabled_for(false, name => none.get(name)))
  let no_color : Map[String, String] = { "NO_COLOR": "1" }
  assert_false(colors_enabled_for(true, name => no_color.get(name)))
  let force_on : Map[String, String] = { "FORCE_COLOR": "1" }
  assert_true(colors_enabled_for(false, name => force_on.get(name)))
  let force_off : Map[String, String] = { "FORCE_COLOR": "0" }
  assert_false(colors_enabled_for(true, name => force_off.get(name)))
  let dumb_term : Map[String, String] = { "TERM": "dumb" }
  assert_false(colors_enabled_for(true, name => dumb_term.get(name)))
}

///|
test "cli: accepts --proxy and -P" {
  let res1 = parse_cli(["--proxy", "http://127.0.0.1:3000"])
  match res1 {
    Ok(Run(config, _port)) =>
      assert_eq(config.proxy, Some("http://127.0.0.1:3000"))
    _ => fail("expected Ok(Run) with --proxy")
  }
  let res2 = parse_cli(["-P", "http://127.0.0.1:4000"])
  match res2 {
    Ok(Run(config, _port)) =>
      assert_eq(config.proxy, Some("http://127.0.0.1:4000"))
    _ => fail("expected Ok(Run) with -P")
  }
}

///|
test "cli: accepts --proxy-all" {
  let res = parse_cli(["--proxy", "http://127.0.0.1:3000", "--proxy-all"])
  match res {
    Ok(Run(config, _port)) => {
      assert_eq(config.proxy, Some("http://127.0.0.1:3000"))
      assert_eq(config.proxy_all, Some("http://127.0.0.1:3000"))
    }
    _ => fail("expected Ok(Run) with proxy-all")
  }
}

///|
test "cli: accepts --proxy-config" {
  let res = parse_cli(["--proxy-config", "proxy.json"])
  match res {
    Ok(Run(config, _port)) => assert_eq(config.proxy_config, Some("proxy.json"))
    _ => fail("expected Ok(Run) with proxy-config")
  }
}

///|
test "cli: banner displays https protocol and through https when TLS is enabled" {
  let config = {
    ..@core.Config::default("."),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  let banner = startup_banner(config, 8443, "0.3.3", ["192.168.1.5"], false)
  assert_true(
    banner.contains("Starting up http-server, serving ./ through https"),
  )
  assert_true(
    banner.contains(
      "Available on:\n  https://192.168.1.5:8443\n  https://127.0.0.1:8443\n",
    ),
  )
}
///|
test "N-12 Full trust flags are explicit and rejected by Thin" {
  let args=["--proxy","https://localhost","--ca-file","roots.pem","--insecure","--websocket"]
  match parse_cli(args[:]) {
    Ok(Run(config,_)) => {
      assert_eq(config.ca_file,Some("roots.pem"))
      assert_false(config.secure)
      assert_true(config.websocket)
    }
    _ => fail("Full trust flags rejected")
  }
  assert_true(parse_cli(args[:],thin=true) is Err(_))
}
