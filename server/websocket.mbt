///|
/// RFC 6455 handshake digest only; not a cryptographic signature or file validator.
fn websocket_accept(key : String) -> String {
  let input=@utf8.encode(key+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
  let data=input.to_array()
  data.push(b'\x80')
  while data.length()%64 != 56 { data.push(b'\x00') }
  let bits=input.length().to_uint64()*8UL
  for i in 0..<8 { data.push(((bits >> ((7-i)*8)) & 255UL).to_byte()) }
  let h : FixedArray[UInt]=[0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0]
  let w=FixedArray::make(80,0U)
  for block in 0..<(data.length()/64) {
    for i in 0..<16 {
      let j=block*64+i*4
      w[i]=(data[j].to_uint()<<24)|(data[j+1].to_uint()<<16)|(data[j+2].to_uint()<<8)|data[j+3].to_uint()
    }
    for i in 16..<80 { w[i]=rotate(w[i-3]^w[i-8]^w[i-14]^w[i-16],1) }
    let mut a=h[0]; let mut b=h[1]; let mut c=h[2]; let mut d=h[3]; let mut e=h[4]
    for i in 0..<80 {
      let (f,k)=if i<20 { ((b & c)|((b^0xffffffffU)&d),0x5a827999U) }
        else if i<40 { (b^c^d,0x6ed9eba1U) }
        else if i<60 { ((b&c)|(b&d)|(c&d),0x8f1bbcdcU) }
        else { (b^c^d,0xca62c1d6U) }
      let next=rotate(a,5)+f+e+k+w[i]
      e=d; d=c; c=rotate(b,30); b=a; a=next
    }
    h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d; h[4]+=e
  }
  @base64.encode(Bytes::makei(20,i => ((h[i/4]>>((3-i%4)*8))&255U).to_byte()))
}
///|
fn rotate(value : UInt,bits : Int) -> UInt { (value<<bits)|(value>>(32-bits)) }
///|
async fn tunnel_copy(reader : &@io.Reader,writer : &@io.Writer,block : Int) -> Unit {
  let buffer=FixedArray::make(block,b'\x00')
  for ;; {
    let n=reader.read(buffer)
    if n==0 { return }
    writer.write(buffer.unsafe_reinterpret_as_bytes()[:n])
  }
}
///|
async fn proxy_websocket(server : Server,client : Transport,reader : @framing.Connection,request : @core.Request) -> Unit {
  let charge=server.config.limits.body_block_bytes*2+163840
  if !@native.try_acquire_body(charge) {
    ignore(send_fallback_status(client,503,"Service Unavailable"));return
  }
  defer @native.release_body(charge)
  match @core.evaluate_security_policies(server.config,request) {
    Proceed => ()
    _ => {
      // Reuse the engine to preserve auth/CORS headers on rejected upgrades.
      match server.engine.handle(request) {
        @root.HandleResult::Handled(response) => ignore(send_response(client,response,true))
        _ => ignore(send_fallback_status(client,403,"Forbidden"))
      }
      return
    }
  }
  let headers=request.headers
  if @core.resolve_path(server.config.root,"/",request.target) is Err(_) {
    ignore(send_fallback_status(client,403,"Forbidden")); return
  }
  let key=headers.get("sec-websocket-key").unwrap_or("")
  let nonce=@base64.decode(key) catch { _ => b"" }
  if !(request.meth is Get) || reader.has_body() || nonce.length()!=16 ||
    headers.get("sec-websocket-version")!=Some("13") ||
    !@framing.has_token(headers.get("connection").unwrap_or(""),"upgrade") {
    ignore(send_fallback_status(client,400,"Bad Request")); return
  }
  let (upstream_url,path)=match server.config.proxy_all {
    Some(url) => (url,request.target)
    None => match server.match_proxy_rule(request.target) {
      Some(pair) => pair
      None => match server.config.proxy { Some(url) => (url,request.target); None => { ignore(send_fallback_status(client,404,"Not Found")); return } }
    }
  }
  guard parse_target_url(upstream_url) is Some(target) else { ignore(send_fallback_status(client,502,"Bad Gateway")); return }
  let upstream=server.upstream_connector.connect(target) catch { _ => { ignore(send_fallback_status(client,502,"Bad Gateway")); return } }
  defer upstream.close()
  let head=StringBuilder()
  head.write_string("GET \{target.base_path}\{path} HTTP/1.1\r\nHost: \{target.host}:\{target.port}\r\n")
  for key,value in headers { if key!="host" { head.write_string("\{key}: \{value}\r\n") } }
  head.write_string("\r\n")
  upstream.writer.write(head.to_string())
  let remote=@framing.Connection::new(upstream.reader)
  let line=remote.line(limit=8192)
  let reply=remote.headers()
  if !line.has_prefix("HTTP/1.1 101 ") ||
    !@framing.has_token(reply.get("connection").unwrap_or(""),"upgrade") ||
    !@framing.has_token(reply.get("upgrade").unwrap_or(""),"websocket") ||
    reply.get("sec-websocket-accept")!=Some(websocket_accept(key)) {
    ignore(send_fallback_status(client,502,"Bad Gateway")); return
  }
  if reply.get("sec-websocket-protocol") is Some(selected) {
    let offered=headers.get("sec-websocket-protocol").unwrap_or("")
    if selected.is_empty() || selected.contains(",") || !offered.split(",").any(p => p.trim()==selected) { ignore(send_fallback_status(client,502,"Bad Gateway")); return }
  }
  if reply.get("sec-websocket-extensions") is Some(selected) {
    let offered=headers.get("sec-websocket-extensions").unwrap_or("")
    for ext in selected.split(",") {
      let name=ext.split(";").next().unwrap().trim()
      if name.is_empty() || !offered.split(",").any(e => e.split(";").next().unwrap().trim()==name) {
        ignore(send_fallback_status(client,502,"Bad Gateway")); return
      }
    }
  }
  let response=StringBuilder()
  response.write_string("HTTP/1.1 101 Switching Protocols\r\n")
  for key,value in reply { response.write_string("\{key}: \{value}\r\n") }
  response.write_string("\r\n")
  client.writer.write(response.to_string())
  @async.with_task_group() <| group => {
    let completed=Ref(0)
    let clean=Ref(true)
    let changed=@async.CondVar::Cond()
    let first=group.spawn(allow_failure=true,() => {
      defer { completed.val+=1;changed.broadcast() }
      errdefer { clean.val=false }
      tunnel_copy(reader,upstream.writer,server.config.limits.body_block_bytes)
      if !upstream.shutdown_write() { clean.val=false }
    })
    let second=group.spawn(allow_failure=true,() => {
      defer { completed.val+=1;changed.broadcast() }
      errdefer { clean.val=false }
      tunnel_copy(remote,client.writer,server.config.limits.body_block_bytes)
      if !client.shutdown_write() { clean.val=false }
    })
    while completed.val==0 { changed.wait() }
    if clean.val {
      ignore(@async.with_timeout_opt(5000,() => {
        while completed.val<2 && clean.val { changed.wait() }
      }))
    }
    first.cancel();second.cancel()
  }
}
