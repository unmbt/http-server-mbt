///|
/// Configuration validation error hierarchy.
/// All errors are detected and raised during pre-listen startup.
pub(all) suberror ConfigError {
  InvalidBaseUrl(String)
  InvalidRoot(String)
  InvalidPort(String)
  InvalidTryFiles(String)
  ConflictingBaseUrl(String)
  ConflictingRouting(String)
  InvalidProxy(String)
  InvalidAuth(String)
  InvalidHeader(String)
  InvalidTimeout(String)
  InvalidTls(String)
  InvalidLimits(String)
} derive(Eq, Debug)

///|
pub fn ConfigError::to_string(self : ConfigError) -> String {
  match self {
    InvalidBaseUrl(s) => "InvalidBaseUrl: " + s
    InvalidRoot(s) => "InvalidRoot: " + s
    InvalidPort(s) => "InvalidPort: " + s
    InvalidTryFiles(s) => "InvalidTryFiles: " + s
    ConflictingBaseUrl(s) => "ConflictingBaseUrl: " + s
    ConflictingRouting(s) => "ConflictingRouting: " + s
    InvalidProxy(s) => "InvalidProxy: " + s
    InvalidAuth(s) => "InvalidAuth: " + s
    InvalidHeader(s) => "InvalidHeader: " + s
    InvalidTimeout(s) => "InvalidTimeout: " + s
    InvalidTls(s) => "InvalidTls: " + s
    InvalidLimits(s) => "InvalidLimits: " + s
  }
}

///|
pub impl Show for ConfigError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Normalized static-server configuration model.
/// Contains all configuration settings for protocol, static resolution,
/// routing mounts, SPA fallback, security policies, and upstream proxies.
pub(all) struct Config {
  limits : RuntimeLimits
  // --- Filesystem & Network ---
  root : String // Filesystem root directory (default "." or "public")
  port : Int // TCP listen port (0..65535, 0 = ephemeral)
  address : String // Bind address ("0.0.0.0", "::", etc.)

  // --- Routing & Mounts ---
  base_url : String // Normalized URL mount prefix (e.g. "/", "/app")
  default_ext : String? // Default file extension completion (e.g. Some("html"))
  spa : Bool // SPA fallback to root index.html
  try_files : String? // Custom fallback file relative to root

  // --- Compression ---
  gzip : Bool // Detect & serve pre-compressed .gz files
  brotli : Bool // Detect & serve pre-compressed .br files
  force_content_encoding : Bool // Force Content-Encoding for files ending in .gz/.br

  // --- Directory Handling ---
  auto_index : Bool // Serve index.html when requesting a directory
  show_dir : Bool // Render HTML directory listing if no index file
  show_dotfiles : Bool // Include hidden/dotfiles in directory listing
  dir_overrides_404 : Bool // Directory listing takes precedence over custom 404.html

  // --- Caching & ETag ---
  cache_seconds : Int // Cache duration in seconds (-1 = no-cache, no-store)
  cache_control : String? // Explicit Cache-Control header override
  weak_etags : Bool // Generate weak ETags (W/"...")
  weak_compare : Bool // Compare ETags using weak comparison

  // --- Security & Headers ---
  cors : Bool // Enable CORS headers (Access-Control-Allow-Origin: *)
  cors_headers : String? // Custom Access-Control-Allow-Headers
  coop : Bool // Cross-Origin-Opener-Policy: same-origin
  coop_header : String? // Custom Cross-Origin-Opener-Policy value
  pna : Bool // Access-Control-Allow-Private-Network: true
  basic_auth : (String, String)? // (username, password) for HTTP Basic Auth
  host_whitelist : Array[String] // Allowed Host header values (empty = allow all)
  custom_headers : Map[String, String] // User-defined headers injected into all responses
  robots : Bool // Serve default User-agent: *\nDisallow: / for /robots.txt

  // --- Proxy & Upstream ---
  proxy : String? // Upstream proxy target (e.g. "http://127.0.0.1:3000")
  proxy_all : String? // Proxy all requests upstream (requires proxy to be set)
  proxy_options : Map[String, String] // Upstream proxy options (must be empty if fallback active)
  websocket : Bool // Enable WebSocket proxy upgrade capability (default false)
  proxy_config : String? // Upstream proxy config file or route rules

  // --- TLS (D-08) ---
  // TLS is disabled by default (D-01); setting cert_file and key_file
  // together enables HTTPS serving. ca_file/secure configure client-side
  // upstream verification (consumed by T-013 proxy work).
  cert_file : String? // TLS certificate chain file (PEM/DER), leaf first
  key_file : String? // TLS private key file (PEM/DER)
  key_passphrase : String? // Private key passphrase for encrypted PEM keys
  ca_file : String? // Trust-root CA bundle file (PEM) for upstream clients
  secure : Bool // Verify upstream certificates and hostname (default true)

  // --- Lifecycle & Error Handling ---
  handle_error : Bool // If false, delegates 404/errors to host (middleware Next)
  idle_timeout_ms : Int // Socket idle timeout in ms (0 = disabled, default 120000)
  mime_types : Map[String, String] // Custom extension -> MIME type overrides

  // --- Logging & Output ---
  log_ip : Bool // Enable logging of client IP address (default false)
  silent : Bool // Suppress console log messages (default false)
} derive(Debug)

///|
/// Build Server & CLI defaults for a filesystem root directory.
pub fn Config::default(root : String) -> Config {
  {
    root,
    limits: RuntimeLimits::default(),
    port: 8080,
    address: "0.0.0.0",
    base_url: "/",
    default_ext: Some("html"),
    spa: false,
    try_files: None,
    gzip: false, // Server/CLI default is false per AD-02
    brotli: false,
    force_content_encoding: false,
    auto_index: true,
    show_dir: true,
    show_dotfiles: false,
    dir_overrides_404: false,
    cache_seconds: 3600,
    cache_control: None,
    weak_etags: true,
    weak_compare: true,
    cors: false,
    cors_headers: None,
    coop: false,
    coop_header: None,
    pna: false,
    basic_auth: None,
    host_whitelist: [],
    custom_headers: Map([]),
    robots: false,
    proxy: None,
    proxy_all: None,
    proxy_options: Map([]),
    websocket: false,
    proxy_config: None,
    cert_file: None,
    key_file: None,
    key_passphrase: None,
    ca_file: None,
    secure: true,
    handle_error: true,
    idle_timeout_ms: 120000, // 120 seconds per AD-03
    mime_types: Map([]),
    log_ip: false,
    silent: false,
  }
}

///|
/// Build Core Middleware defaults for a filesystem root directory (AD-02 compatibility).
pub fn Config::middleware_default(root : String) -> Config {
  {
    ..Config::default(root),
    gzip: true, // Core middleware default is true per AD-02
  }
}

///|
/// Determine active page fallback mode.
pub fn Config::fallback_mode(self : Config) -> FallbackMode {
  if self.spa {
    FallbackMode::Spa
  } else {
    match self.try_files {
      Some(f) => FallbackMode::TryFiles(f)
      None => FallbackMode::None
    }
  }
}

///|
/// Returns whether any fallback mode is enabled.
pub fn Config::has_fallback(self : Config) -> Bool {
  self.spa || self.try_files is Some(_)
}

///|
/// Returns whether any upstream proxy mode is configured.
pub fn Config::has_proxy(self : Config) -> Bool {
  self.proxy is Some(_) ||
  self.proxy_all is Some(_) ||
  self.proxy_config is Some(_) ||
  !self.proxy_options.is_empty()
}

///|
/// Returns whether WebSocket proxy capability is enabled.
pub fn Config::has_websocket_proxy(self : Config) -> Bool {
  self.has_proxy() && self.websocket
}

///|
/// Returns whether TLS serving is enabled (D-01: disabled by default).
pub fn Config::has_tls(self : Config) -> Bool {
  self.cert_file is Some(_) || self.key_file is Some(_)
}

///|
/// Return whether configured upstream targets may require a TLS client.
/// Inline/file proxy rules are conservatively treated as HTTPS when their
/// configuration contains an `https://` target.
pub fn Config::proxy_targets_include_https(self : Config) -> Bool {
  if self.proxy is Some(url) && (url.has_prefix("https://") || url.has_prefix("wss://")) {
    return true
  }
  if self.proxy_all is Some(url) && (url.has_prefix("https://") || url.has_prefix("wss://")) {
    return true
  }
  match self.proxy_config {
    Some(value) => value.contains("https://") || value.contains("wss://")
    None => false
  }
}

///|
/// Validate TLS configuration pairing: enabling TLS requires both a
/// certificate and a key (D-01). File readability and key/cert matching are
/// verified during server startup preflight when the acceptor is built,
/// before the listener is created.
pub fn validate_tls(config : Config) -> Unit raise ConfigError {
  match (config.cert_file, config.key_file) {
    (Some(_), Some(_)) => ()
    (Some(_), None) =>
      raise ConfigError::InvalidTls("cert_file requires key_file to be set")
    (None, Some(_)) =>
      raise ConfigError::InvalidTls("key_file requires cert_file to be set")
    (None, None) => ()
  }
}

///|
/// Returns the relative file path to serve on fallback, if enabled.
pub fn Config::fallback_target_file(self : Config) -> String? {
  if self.spa {
    Some("index.html")
  } else {
    self.try_files
  }
}

///|
/// Returns the effective Cache-Control header string.
pub fn Config::effective_cache_control(self : Config) -> String {
  match self.cache_control {
    Some(custom) => custom
    None =>
      if self.cache_seconds < 0 {
        "no-cache, no-store, must-revalidate"
      } else {
        "max-age=" + self.cache_seconds.to_string()
      }
  }
}

///|
/// Validate a filesystem root directory path.
pub fn validate_root(root : String) -> String raise ConfigError {
  if root == "" || root.contains("\u0000") {
    raise ConfigError::InvalidRoot("root cannot be empty or contain null bytes")
  }
  root
}

///|
/// Validate a user-specified try_files relative path.
pub fn validate_try_files_path(path : String) -> String raise ConfigError {
  if path == "" {
    raise ConfigError::InvalidTryFiles("try_files path cannot be empty")
  }
  if path[0] == '/' {
    raise ConfigError::InvalidTryFiles(
      "try_files path must be relative to root, cannot start with '/'",
    )
  }
  if path.contains("\u0000") ||
    path.contains("\\") ||
    path.contains("\r") ||
    path.contains("\n") {
    raise ConfigError::InvalidTryFiles(
      "try_files path contains invalid characters",
    )
  }
  if path.contains("$uri") ||
    path.contains("=404") ||
    path.contains(" ") ||
    path.contains(",") {
    raise ConfigError::InvalidTryFiles(
      "try_files does not support Nginx multi-candidate or variable syntax",
    )
  }
  let parts = path.split("/").to_array()
  for part in parts {
    if part == ".." || part == "." {
      raise ConfigError::InvalidTryFiles(
        "try_files path cannot contain dot segments",
      )
    }
    if part == "" {
      raise ConfigError::InvalidTryFiles(
        "try_files path cannot contain consecutive slashes",
      )
    }
  }
  path
}

///|
/// Validate upstream proxy URL format (http:// or https:// with valid host/port).
pub fn validate_proxy_url(url : String) -> Unit raise ConfigError {
  let url=if url.has_prefix("wss://") { "https://"+url[6:].to_owned() }
    else if url.has_prefix("ws://") { "http://"+url[5:].to_owned() } else { url }
  if !url.has_prefix("http://") && !url.has_prefix("https://") {
    raise ConfigError::InvalidProxy(
      "proxy URL must start with http:// or https://",
    )
  }
  let prefix_len = if url.has_prefix("https://") { 8 } else { 7 }
  let rest = url[prefix_len:].to_owned()
  let auth_end = match rest.find("/") {
    Some(idx) => idx
    None =>
      match rest.find("?") {
        Some(idx) => idx
        None => rest.length()
      }
  }
  let authority = rest[:auth_end].to_owned()
  match authority.find(":") {
    Some(colon_idx) => {
      let port_str = authority[colon_idx + 1:].to_owned()
      if port_str.length() == 0 {
        raise ConfigError::InvalidProxy(
          "proxy URL missing port number after ':'",
        )
      }
      let mut p = 0
      for c in port_str {
        if c < '0' || c > '9' {
          raise ConfigError::InvalidProxy(
            "proxy URL has invalid non-numeric port: " + port_str,
          )
        }
        p = p * 10 + (c.to_int() - '0'.to_int())
        if p > 65535 {
          raise ConfigError::InvalidProxy(
            "proxy URL port exceeds 65535: " + port_str,
          )
        }
      }
    }
    None => ()
  }
}

///|
/// Validate all configuration settings before creating any network listener.
/// Raises ConfigError on any syntactic defect or mutual exclusion conflict.
pub fn validate_config(config : Config) -> Unit raise ConfigError {
  config.limits.validate()
  ignore(validate_root(config.root))
  ignore(normalize_base_url(config.base_url))

  if config.port < 0 || config.port > 65535 {
    raise ConfigError::InvalidPort("port must be between 0 and 65535")
  }

  if config.idle_timeout_ms < 0 {
    raise ConfigError::InvalidTimeout("idle_timeout_ms cannot be negative")
  }

  match config.try_files {
    Some(tf) => ignore(validate_try_files_path(tf))
    None => ()
  }

  if config.spa && config.try_files is Some(_) {
    raise ConfigError::ConflictingRouting(
      "cannot specify both --spa and --try-files (mutual exclusion violation)",
    )
  }

  let has_fallback = config.spa || config.try_files is Some(_)
  let has_proxy = config.proxy is Some(_) ||
    config.proxy_all is Some(_) ||
    config.proxy_config is Some(_) ||
    !config.proxy_options.is_empty()

  if has_fallback && has_proxy {
    raise ConfigError::ConflictingRouting(
      "cannot combine page fallback (--spa or --try-files) with proxy configuration",
    )
  }

  if config.proxy_all is Some(_) && config.proxy is None {
    raise ConfigError::InvalidProxy(
      "--proxy-all requires --proxy to be configured",
    )
  }
  match config.proxy {
    Some(p) => validate_proxy_url(p)
    None => ()
  }

  match config.basic_auth {
    Some((username, password)) =>
      if username.contains(":") ||
        username.contains("\u0000") ||
        password.contains("\u0000") {
        raise ConfigError::InvalidAuth(
          "username cannot contain ':' or null bytes",
        )
      }
    None => ()
  }

  if config.cache_seconds < -1 {
    raise ConfigError::InvalidHeader("cache_seconds cannot be less than -1")
  }

  for k, v in config.custom_headers {
    if k.contains("\r") ||
      k.contains("\n") ||
      v.contains("\r") ||
      v.contains("\n") {
      raise ConfigError::InvalidHeader(
        "custom headers cannot contain CRLF characters",
      )
    }
  }

  validate_tls(config)
}

///|
/// Method syntax for validating a Config instance.
pub fn Config::validate(self : Config) -> Unit raise ConfigError {
  validate_config(self)
}

///|
/// Helper to parse CLI basic auth credentials in format "username:password".
pub fn parse_auth_credential(str : String) -> (String, String)? {
  match str.find(":") {
    Some(idx) => {
      let username = str[:idx].to_owned()
      let password = str[idx + 1:].to_owned()
      Some((username, password))
    }
    None => None
  }
}


///|
pub extend ConfigError with Eq::{not_equal, equal}

///|
pub extend ConfigError with Debug::{to_repr}

///|
pub extend ConfigError with Show::{output}

///|
pub extend Config with Debug::{to_repr}
