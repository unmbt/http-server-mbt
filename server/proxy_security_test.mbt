///|
async test "N-22 direct proxy cannot bypass authentication or path safety" {
  // An unreachable upstream distinguishes local rejection from proxy dispatch.
  let config={..@core.Config::default("testdata/public"),
    proxy:Some("http://127.0.0.1:1"),proxy_all:Some("http://127.0.0.1:1"),basic_auth:Some(("user","pass"))}
  @server.with_server_at(config,0,async fn(server) {
    let (status,headers,_)=test_request(server.port(),"GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
    assert_eq(status,401)
    assert_true(headers.contains("www-authenticate"))
    let (status,_,_)=test_request(server.port(),"GET /%2e%2e/secret HTTP/1.1\r\nHost: localhost\r\nAuthorization: Basic dXNlcjpwYXNz\r\nConnection: close\r\n\r\n")
    assert_eq(status,403)
  })
}
