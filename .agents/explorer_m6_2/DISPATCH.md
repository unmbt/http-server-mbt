# Task Assignment: Explorer M6-2 (Real HTTP Client E2E Testing)

## Working Directory
E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_2

## Authoritative Inputs
- `ORIGINAL_REQUEST.md` (E:\project\moonbit\unmbt\http-server-mbt\.agents\ORIGINAL_REQUEST.md)
- `AGENTS.md` (E:\project\moonbit\unmbt\http-server-mbt\AGENTS.md)
- `docs/tasks.md` (E:\project\moonbit\unmbt\http-server-mbt\docs\tasks.md)
- `docs/design.md` (E:\project\moonbit\unmbt\http-server-mbt\docs\design.md)
- `server/server.mbt`, `server/server_test.mbt`, `server/server_challenger_test.mbt`, `server/server_challenger_m4_2_test.mbt`

## Mission
1. Investigate how real TCP Socket client end-to-end integration tests can be implemented in MoonBit Native under `server/`.
2. Analyze how to boot a test server (using ephemeral or dynamic port, e.g. port 0 or dynamically assigned port), initiate real TCP socket connection(s), send raw HTTP requests, and parse responses.
3. Define test scenarios covering:
   - GET requests (static file, directory index, mime type, 200 OK)
   - HEAD requests (headers only, empty body)
   - OPTIONS requests (if applicable or standard handling)
   - Keep-alive persistent connections (sending multiple requests over the same TCP socket sequentially and verifying correct framing/Content-Length)
   - Error status codes: 400 Bad Request, 404 Not Found, 405 Method Not Allowed, 416 Range Not Satisfiable, etc.
4. Check socket lifecycle, proper shutdown, and zero handle leak requirements.
5. Provide a complete architecture and code design proposal for `server/server_e2e_client_test.mbt`.

Write your findings to `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_2\handoff.md`.

## 2026-09-11T18:11:08Z
You are explorer_m6_2 (Real HTTP Client E2E Explorer).
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_2
Please read your task assignment in: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_2\DISPATCH.md
Also read ORIGINAL_REQUEST.md at E:\project\moonbit\unmbt\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Also read AGENTS.md, docs/tasks.md, docs/design.md, and server/server.mbt, server/server_test.mbt.
Investigate how to implement real TCP Socket client E2E integration tests in MoonBit Native under server/.
Design test cases covering GET, HEAD, OPTIONS, keep-alive framing, and error status codes (400, 404, 405, 416), ensuring clean socket lifecycle and 0 handle leaks.
Write your architecture analysis and proposed test code design to:
E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_2\handoff.md
When finished, send a completion message back.

