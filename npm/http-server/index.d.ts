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
 * Returns the MoonBit C ABI version (ABI 1.1 is 0x00010001).
 */
export function getAbiVersion(): number;

/**
 * Creates and starts a MoonBit HTTP/HTTPS static server and reverse proxy.
 * @param options Server configuration object or JSON string.
 */
export function createServer(options?: ServerConfig | string): HttpServer;

export interface EngineConfig {
  root?: string;
  base_url?: string;
  default_ext?: string | null;
  spa?: boolean;
  try_files?: string | null;
  gzip?: boolean;
  brotli?: boolean;
  force_content_encoding?: boolean;
  auto_index?: boolean;
  show_dir?: boolean;
  show_dotfiles?: boolean;
  dir_overrides_404?: boolean;
  cache_seconds?: number;
  cache_control?: string | null;
  weak_etags?: boolean;
  weak_compare?: boolean;
  cors?: boolean;
  cors_headers?: string | null;
  coop?: boolean;
  coop_header?: string | null;
  pna?: boolean;
  robots?: boolean;
  handle_error?: boolean;
  basic_auth?: [string, string];
  host_whitelist?: string[];
  custom_headers?: Record<string, string>;
  mime_types?: Record<string, string>;
  limits?: Partial<{ file_workers: number; queued_operations: number;
    connections: number; body_block_bytes: number; body_buffer_bytes: number;
    directory_metadata_bytes: number }>;
}
export interface StaticRequest {
  method: string;
  target: string;
  headers?: [string, string][] | Record<string, string | string[]>;
  signal?: AbortSignal;
}
export type HandleResult = { kind: 'next' } | {
  kind: 'handled'; status: number; headers: [string, string][];
  contentLength: bigint | null; body: import('node:stream').Readable;
};
export class StaticEngine {
  private constructor();
  handle(request: StaticRequest): Promise<HandleResult>;
  close(): Promise<void>;
}
export function createEngine(config?: EngineConfig | string): Promise<StaticEngine>;
export type ConnectMiddleware = (
  req: import('node:http').IncomingMessage,
  res: import('node:http').ServerResponse,
  next: (error?: unknown) => void
) => void;
export function createMiddleware(engine: StaticEngine): ConnectMiddleware;
