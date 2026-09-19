export interface ServerConfig {
  /**
   * Root directory path for static files.
   * Defaults to current directory (".").
   */
  root?: string;

  /**
   * Port number to listen on.
   * Set to 0 for automatic port assignment.
   */
  port?: number;

  /**
   * Enable Single Page Application (SPA) fallback.
   * When enabled, missing routes fallback to index.html.
   */
  spa?: boolean;

  /**
   * Enable Cross-Origin Resource Sharing (CORS) headers.
   */
  cors?: boolean;

  /**
   * Suppress console logging.
   */
  silent?: boolean;

  /**
   * Automatically serve index.html when requesting a directory.
   */
  auto_index?: boolean;

  /**
   * Show directory listing when index.html is absent.
   */
  show_dir?: boolean;

  /**
   * Cache-Control max-age in seconds. Defaults to 3600.
   */
  cache_seconds?: number;

  /**
   * Try files sequence (e.g. "/index.html").
   */
  try_files?: string;

  /**
   * Path to TLS certificate file (PEM format).
   */
  cert_file?: string;

  /**
   * Path to TLS private key file (PEM format).
   */
  key_file?: string;

  /**
   * Passphrase for encrypted private key.
   */
  key_passphrase?: string;

  /**
   * Upstream URL for reverse proxying unhandled requests.
   */
  proxy?: string;

  /**
   * Upstream URL for reverse proxying ALL requests.
   */
  proxy_all?: string;
}

export class HttpServer {
  private _handle: unknown;
  private _stopped: boolean;

  /**
   * Gracefully stop the HTTP/HTTPS server and flush ongoing requests.
   */
  stop(): void;
}

/**
 * Returns the MoonBit C ABI version (e.g. 0x00010000).
 */
export function getAbiVersion(): number;

/**
 * Creates and starts a MoonBit HTTP/HTTPS static server and reverse proxy.
 * @param options Server configuration object or JSON string.
 */
export function createServer(options?: ServerConfig | string): HttpServer;
