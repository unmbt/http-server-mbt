// Experimental Node WasmGC host. Node types are supplied by the consuming application.
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
