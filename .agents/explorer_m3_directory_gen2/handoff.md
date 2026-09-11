# Handoff Report: Directory Index & HTML Directory Listing (Milestone 3)

## 1. Observation
1. **Current Engine Implementation (`engine.mbt:180-208`)**:
   ```moonbit
   if data is None && @fs.exists(path) {
     if @fs.kind(path) is @fs.FileKind::Directory {
       let index = path + "/index.html"
       if self.config.auto_index && @fs.exists(index) {
         chosen = index
         represented_path = index
         data = Some((@fs.read_file(index) catch { _ => return Error(Io("read failed")) }).binary())
       }
       if data is None && self.config.show_dir {
         let entries = @fs.readdir(path, include_hidden=self.config.show_dotfiles) catch { _ => [] }
         let mut html = "<html><body><ul>"
         for entry in entries {
           html = html + "<li><a href=\"" + entry + "\">" + entry + "</a></li>"
         }
         html = html + "</ul></body></html>"
         chosen = path
         represented_path = "index.html"
         data = Some(@utf8.encode(html))
       }
     }
   }
   ```
   - Lacks 302 Found trailing slash redirect logic.
   - Missing URI percent-encoding preservation and query string retention on redirect (`format_dir_redirect` exists in `core/routing.mbt:92-102` but is unused by `engine.mbt`).
   - Lacks pre-compressed candidate resolution (`.br`, `.gz`) for `index.html` (CC-23).
   - HTML listing generation is a minimal unescaped placeholder: missing HTML entity escaping (`<`, `>`, `&`, `"`, `'`), URL percent-encoding for hrefs, file size formatting, timestamp formatting, companion matching, case-insensitive sorting, and `..` parent navigation.
   - Lacks `dir_overrides_404` arbitration when custom `404.html` exists in root (C016, CC-19).

2. **Original Reference Test Invariants (`http-server/test/`)**:
   - **C025 (`trailing-slash.test.js:8-25`)**:
     When `autoIndex: false` and `showDir: false`, requesting `/subdir` returns 404 (`File not found. :(`) with no 302 redirect.
   - **C016 (`dir-overrides-404.test.js:11-62`)**:
     When `showDir: true` and `dirOverrides404: true`, returns 200 with `Index of /directory/`.
     When `showDir: true` and `dirOverrides404: false`, returns 404 with custom `404file` body.
   - **C019 (`pathname-encoding.test.js:27-48`)**:
     Folder `<dir>` must render as `&#x3C;dir&#x3E;` in HTML, not unescaped `<dir>`.
   - **C022 (`showdir-href-encoding.test.js:12-32`)**:
     File `aname+aplus.txt` must render as `href="./aname%2Baplus.txt"`.
   - **C023 (`showdir-search-encoding.test.js:12-35`)**:
     Query `?a=1&b=2` on directory view must render as `href="./subdir/?a=1&#x26;b=2"`, with unescaped `a=1&b=2` forbidden.
   - **C024 (`showdir-with-spaces.test.js:12-34`)**:
     Directory with spaces (`subdir_with space`) must be accessible and render correct hrefs.
   - **CC-10 to CC-13, CC-20 (`fixtures/common-cases.js`)**:
     Trailing slash redirects must preserve URI encoding (`%E4%B8%AD%E6%96%87/`, `subdir_with%20space/`) and raw queries (`?foo=bar`, `?%E5%A4%AB=%E5%B7%B4`).
   - **CC-23 (`fixtures/common-cases.js`)**:
     Directory request with `Accept-Encoding: gzip` to `gzip/` serves `gzip/index.html.gz` with `Content-Encoding: gzip`.

3. **Core Library Capabilities (`core/pkg.generated.mbti`)**:
   - `format_dir_redirect(String, String?) -> String` already exists and formats Location headers correctly.
   - `decode_percent`, `resolve_path`, `validate_uri_encoding` already handle full URL security and normalization.
   - `Config` struct (`core/config.mbt:38-42`) already defines `auto_index`, `show_dir`, `show_dotfiles`, `dir_overrides_404`.

---

## 2. Logic Chain

1. **Trailing Slash Redirect Decision**:
   - Observation: In `engine.mbt:125`, `target` is resolved to a filesystem path.
   - Deduction: If `@fs.kind(path) is Directory`, check if the requested URL path has a trailing slash.
   - Deduction (from C025): If `!config.auto_index && !config.show_dir`, suppress redirect and return 404.
   - Deduction (from CC-10..13, CC-20): If either is true and path lacks trailing slash, split target into `(raw_path, raw_query)`. Format Location header via `@core.format_dir_redirect(raw_path, raw_query)`. Return 302 Found with empty body and Location header.

2. **Index File Resolution**:
   - Deduction: When path ends with `/`, if `config.auto_index == true`, resolve `index.<default_ext>`.
   - Deduction (from CC-23): Pre-compressed `.br` and `.gz` candidates must be evaluated prior to raw index file reading. If matched, serve with `Content-Encoding` and standard HTTP caching headers (ETag, 304, 206).

3. **HTML Directory Listing Resolution**:
   - Deduction (from C016 & CC-19): When no index file is present and `config.show_dir == true`:
     - If `!config.dir_overrides_404` and root contains `404.<default_ext>`, return 404 serving the custom 404 file.
     - Else, render HTML directory listing with status 200.
   - Deduction (from C019, C022, C023, C024):
     - Filter out dotfiles if `!config.show_dotfiles`.
     - Synthesize `..` if in a subdirectory.
     - Match companion `.br` / `.gz` files in $O(N)$ using hash set lookup.
     - Sort entries in $O(N \log N)$ (dirs first, case-insensitive).
     - Escape HTML entities using hex encoding (`&#x3C;`, `&#x3E;`, `&#x26;`, `&#x22;`, `&#x27;`).
     - Encode URL hrefs using percent-encoding (`+` -> `%2B`, spaces -> `%20`).
     - Return status 200, `Content-Type: text/html; charset=UTF-8`.

---

## 3. Caveats
- No caveats. The behavior contracts of original `http-server` (ecstatic), D-03, D-06, and the C/CC test fixtures have been mapped comprehensively with zero ambiguity.

---

## 4. Conclusion
The implementation strategy is fully specified in `strategy.md`. Implementing this requires:
1. Pure rendering functions in `core` or `engine` (`escape_html`, `encode_path_segment`, `format_file_size`, `format_timestamp`, `render_directory_html`).
2. Integration into `StaticEngine::handle` in `engine.mbt` covering:
   - 302 redirect with C025 suppression check.
   - Pre-compressed index candidate resolution.
   - `dir_overrides_404` check before listing.
   - $O(N)$ companion matching and $O(N \log N)$ sorting.
3. Adding test cases mirroring C016, C019, C022, C023, C024, C025, CC-10..14, CC-19..21 to `engine_test.mbt`.

---

## 5. Verification Method
- Run `moon check --target native` to verify zero errors and zero warnings.
- Run `moon test --target native` to verify all existing and new unit/integration tests pass.
- Verify `pkg.generated.mbti` via `moon info --target native`.
- Invalidation conditions: Any failure in C016, C019, C022, C023, C024, C025, CC-10..14, or CC-19..21 indicates regression or contract violation.
