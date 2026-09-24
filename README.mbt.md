# Owned MoonBit static engine

The root package supports Native static requests without opening a listening socket.
Use `server/plain` for Thin HTTP and `full` for HTTP/HTTPS and proxy service scopes.
See [the migration contract](docs/migration-0.4.md) for the next minor version's API changes.

```mbt check
async fn example(root : String) -> Bytes {
  @http-server-mbt.with_engine(@core.Config::default(root), engine => {
    match engine.handle({ meth: Get, target: "/index.html", headers: Map([]) }) {
      Handled(response) => {
        defer response.close()
        response.to_bytes(max_bytes=1048576)
      }
      Next => b""
      Error(error) => raise error
    }
  })
}

async test "documented owned engine scope" {
  assert_true(example("testdata/public").length() > 0)
}
```

For large bodies, repeatedly call `response.read()` and await each consumer before
reading the next chunk. Empty bytes mean successful EOF; errors remain errors.
`response.content_length()` returns `None` for a streaming directory listing.

Candidate validation and registry publication are separate. The current module
metadata remains at its existing released version until the release gate is met.
