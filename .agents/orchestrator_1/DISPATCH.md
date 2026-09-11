# Dispatch Assignment

## 2026-09-11T06:43:35Z

You are the Project Orchestrator for the project http-server-mbt.

Your Working Directory: D:\project\moonbit\http-server-mbt\.agents\orchestrator_1
Your Project Root: D:\project\moonbit\http-server-mbt
Original User Request File: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md

Please read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md and AGENTS.md carefully before proceeding.

Summary of Mission:
1. Complete Windows Native http-server features and test suite:
   - HTTP/1.1 GET/HEAD, conditional requests (ETag strong/weak, If-None-Match, If-Modified-Since, 304 Not Modified).
   - Range requests (206 Partial Content, Content-Range, 416 Range Not Satisfiable).
   - Pre-compression content negotiation (Brotli .br, gzip .gz, Accept-Encoding, forceContentEncoding).
   - MIME types and default extensions, 404 page generation.
   - Directory indexing and HTML directory listing.
   - Security policies and authentication: strict path traversal defense, HTTP Basic Auth (constant time comparison, auth before file probe), CORS/COOP/PNA, Host whitelist.
   - CLI & lifecycle: arguments parsing, invalid arg pre-listen rejection, graceful exit.
2. Core extensions:
   - Windows kernel-level zero-copy transfer: Windows Native TransmitFile / IOCP for static files & ranges, bounded buffer fallback, disconnection/cancellation handling without socket/file handle leaks.
   - BaseURL mount: --base-url & --base-dir route prefix mounting and URL normalization.
   - SPA & try-files: --spa and --try-files <file> fallback, preserving auth/permission errors, mutual exclusion with proxy.
3. Modular architecture and ZERO compiler warnings:
   - Clear decoupling (core, engine, fs/io/zero-copy, server, cmd).
   - Eliminate ALL 46 compiler warnings (redundant_modifier, unused_constructor, unused_package, deprecated APIs, keyword naming like method/use), achieving 0 warnings and 0 errors on `moon check --target native`.
   - Update .mbti with `moon info --target native`, format with `moon fmt`.
   - Strict open-source license compliance: MIT, Apache-2.0, BSD-3-Clause only.
4. Comprehensive test suite migration:
   - Full migration of C001~C042, CC-01~CC-28, CE-01~CE-02, unit and integration tests passing on `moon test --target native`.
