///|
/// D-08: shared bounded HTTP framing, preserving bytes read past headers.
pub suberror ProtocolError { Invalid; Limit } derive(Debug)
///|
priv enum Body { Empty; Fixed(Int); Chunked(Int) }
///|
// async 0.21.3 requires ReaderBuffer to implement its public Reader trait.
// Keep this allowance on the adapter, never on a package or the build.
#warnings("-alert_internal")
pub struct Connection {
  priv source : &@io.Reader
  priv pending : FixedArray[Byte]
  priv mut start : Int
  priv mut end : Int
  priv buffer : @io.ReaderBuffer
  priv mut body : Body
}
///|
pub struct Head {
  request : @core.Request
  http11 : Bool
  keep_alive : Bool
}
///|
#warnings("-alert_internal")
pub fn Connection::new(source : &@io.Reader) -> Connection {
  { source, pending: FixedArray::make(8192, b'\x00'), start: 0, end: 0,
    buffer: @io.ReaderBuffer::new(), body: Empty }
}
///|
pub impl @io.Reader for Connection with fn _get_internal_buffer(self) { self.buffer }
///|
pub impl @io.Reader for Connection with fn _direct_read(self, dst, offset~, max_len~) {
  if self.start < self.end {
    let n=Int::min(max_len,self.end-self.start)
    self.pending.blit_to(dst,src_offset=self.start,dst_offset=offset,len=n)
    self.start += n
    n
  } else { self.source.read(dst,offset~,max_len~) }
}
///|
async fn Connection::byte(self : Connection) -> Byte {
  if self.start == self.end {
    self.end=self.source.read(self.pending)
    self.start=0
    if self.end==0 { raise @io.ReaderClosed }
  }
  let b=self.pending[self.start]
  self.start += 1
  b
}
///|
pub async fn Connection::line(self : Connection, limit~ : Int) -> String {
  let bytes : Array[Byte]=[]
  while bytes.length() <= limit {
    let b=self.byte()
    if b==b'\r' {
      if self.byte()!=b'\n' { raise Invalid }
      return @utf8.decode(Bytes::from_array(bytes)) catch { _ => raise Invalid }
    }
    if b==b'\n' || b==b'\x00' { raise Invalid }
    bytes.push(b)
  }
  raise Limit
}
///|
fn token(text : String) -> Bool {
  if text.is_empty() { return false }
  for c in text {
    if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || "!#$%&'*+-.^_`|~".contains(c.to_string())) { return false }
  }
  true
}
///|
pub fn has_token(value : String, wanted : String) -> Bool {
  value.to_lower().split(",").any(item => item.trim()==wanted)
}
///|
pub async fn Connection::headers(self : Connection) -> Map[String,String] {
  let headers : Map[String,String]=Map([])
  let mut used=0
  let mut count=0
  for ;; {
    let line=self.line(limit=16384-used)
    used += @utf8.encode(line).length()+2
    if used>16384 { raise Limit }
    if line.is_empty() { return headers }
    count += 1
    if count>100 { raise Limit }
    guard line.find(":") is Some(colon) else { raise Invalid }
    let key=line[:colon].to_owned().to_lower()
    if !token(key) { raise Invalid }
    let value=line[colon+1:].trim().to_owned()
    for c in value { if (c<' ' && c!='\t') || c=='\u007f' { raise Invalid } }
    if headers.contains(key) && (key=="content-length" || key=="transfer-encoding" || key=="host") { raise Invalid }
    headers[key]=match headers.get(key) { Some(old) => old+","+value; None => value }
  }
}
///|
pub async fn Connection::read_request(self : Connection) -> Head {
  guard self.body is Empty else { raise Invalid }
  let line=self.line(limit=8192)
  let parts=line.split(" ").to_array()
  guard parts.length()==3 && token(parts[0].to_owned()) && !parts[1].is_empty() else { raise Invalid }
  let http11=parts[2]=="HTTP/1.1"
  if !http11 && parts[2]!="HTTP/1.0" { raise Invalid }
  let headers=self.headers()
  if headers.contains("transfer-encoding") && headers.contains("content-length") { raise Invalid }
  if headers.get("transfer-encoding") is Some(value) {
    if !http11 || value.to_lower()!="chunked" { raise Invalid }
    self.body=Chunked(0)
  } else if headers.get("content-length") is Some(value) {
    if value.is_empty() || value.iter().any(c => c<'0' || c>'9') { raise Invalid }
    let n=@string.parse_int(value) catch { _ => raise Invalid }
    if n<0 { raise Invalid }
    self.body=if n==0 { Empty } else { Fixed(n) }
  }
  let connection=headers.get("connection").unwrap_or("")
  let keep_alive= !has_token(connection,"close") && (http11 || has_token(connection,"keep-alive"))
  let meth=match parts[0] { "GET" => @core.Method::Get; "HEAD" => @core.Method::Head; s => @core.Method::Other(s.to_owned()) }
  { request: {meth,target:parts[1].to_owned(),headers}, http11, keep_alive }
}
///|
pub fn Connection::has_body(self : Connection) -> Bool { !(self.body is Empty) }
///|
pub async fn Connection::read_body(self : Connection, dst : FixedArray[Byte]) -> Int {
  let remaining=match self.body {
    Empty => return 0
    Fixed(n) => n
    Chunked(n) if n>0 => n
    Chunked(_) => {
      let line=self.line(limit=8192)
      let raw=line.split(";").next().unwrap().to_owned()
      if raw.is_empty() || raw.iter().any(c => !((c>='0' && c<='9') || (c>='a' && c<='f') || (c>='A' && c<='F'))) { raise Invalid }
      let n=@string.parse_int(raw,base=16) catch { _ => raise Invalid }
      if n<0 { raise Invalid }
      if n==0 {
        let trailers=self.headers()
        for key in trailers.keys() { if key=="content-length" || key=="transfer-encoding" || key=="host" { raise Invalid } }
        self.body=Empty
        return 0
      }
      self.body=Chunked(n)
      n
    }
  }
  let n=@io.Reader::read(self,dst,max_len=Int::min(dst.length(),remaining))
  if n==0 { raise @io.ReaderClosed }
  self.body=match self.body {
    Fixed(_) => if n==remaining { Empty } else { Fixed(remaining-n) }
    Chunked(_) => {
      if n==remaining && @io.Reader::read_exactly(self,2)!=b"\r\n" { raise Invalid }
      Chunked(remaining-n)
    }
    Empty => Empty
  }
  n
}
///|
pub async fn Connection::drain(self : Connection) -> Unit {
  let buffer=FixedArray::make(8192,b'\x00')
  while self.read_body(buffer)>0 { () }
}


///|
pub extend ProtocolError with Debug::{to_repr}

///|
pub extend Connection with @moonbitlang/async/io.Reader::{read, read_some, _direct_read, drop, read_all, read_until, read_exactly, _get_internal_buffer}
