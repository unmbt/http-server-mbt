// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Vendored and adapted from moonbitlang/async@0.21.3 src/http/parser.mbt
// (Apache-2.0). The upstream reader type is package-private and the public
// ServerConnection is bound to @socket.Tcp, which cannot wrap the TLS
// transport (D-08/T-012). This copy generalizes request parsing over any
// `@io.Reader` so TLS connections parse identically to the plaintext path.
// Server-side adaptations versus upstream:
// - gzip auto-decompression and response parsing removed (request-side only;
//   without the gzip layer the produced byte count always equals the
//   transport read count, so the chunk retry branches collapse)
// - PassThrough/WaitConnectionClose body kinds removed (proxy-only features)
// - Set-Cookie in a request is rejected as a protocol error, matching the
//   observable behavior of upstream request parsing
// Upstream changes that generalize ServerConnection should replace this file.

///|
//|

///|
/// Protocol parse errors mirroring the upstream `HttpProtocolError` variants
/// raised during request parsing (the upstream suberror is read-only for
/// external packages).
priv suberror HttpParseError {
  ParseBadRequest
  ParseNotImplemented
  ParseVersionNotSupported(String)
}

//|

///|
priv enum BodyKind {
  Empty
  Fixed(Int)
  Chunked(Int)
}

///|
/// A HTTP reader type that can parse and deliver HTTP requests
/// over an arbitrary `@io.Reader` transport.
#warnings("-alert_internal")
priv struct HttpReader {
  mut body : BodyKind
  transport : &@io.Reader
  read_buf : @io.ReaderBuffer
}

///|
/// Create a new HTTP reader wrapping around existing reader `transport`.
#warnings("-alert_internal")
fn HttpReader::new(transport : &@io.Reader) -> HttpReader {
  { body: Empty, transport, read_buf: @io.ReaderBuffer::new(), }
}

///|
/// Read up to `limit` body bytes into `buf[offset:offset+max_len]`.
/// Returns 0 when the transport reached EOF.
async fn HttpReader::decode_chunk(
  self : HttpReader,
  buf : FixedArray[Byte],
  offset~ : Int,
  max_len~ : Int,
  limit~ : Int,
) -> Int {
  let max_len = @cmp.minimum(max_len, limit)
  self.transport.read(buf, offset~, max_len~)
}

///|
/// Read from the body of the HTTP request
/// that is currently being processed by the HTTP reader.
#warnings("-unused_value")
impl @io.Reader for HttpReader with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  match self.body {
    Empty => 0
    Fixed(remaining) => {
      let consumed = self.decode_chunk(buf, offset~, max_len~, limit=remaining)
      if consumed is 0 {
        raise @io.ReaderClosed
      }
      let remaining = remaining - consumed
      self.body = if remaining == 0 { Empty } else { Fixed(remaining) }
      consumed
    }
    Chunked(0) => {
      guard self.transport.read_until("\r\n") is Some(len_str) else {
        raise @io.ReaderClosed
      }
      let next_chunk_len = @string.parse_int(len_str, base=16) catch {
        _ => raise ParseBadRequest
      }
      guard next_chunk_len > 0 else {
        guard self.transport.read_exactly(2) == b"\r\n" else {
          raise ParseBadRequest
        }
        self.body = Empty
        return 0
      }
      let consumed = self.decode_chunk(
        buf,
        offset~,
        max_len~,
        limit=next_chunk_len,
      )
      if consumed is 0 {
        raise @io.ReaderClosed
      }
      let remaining = next_chunk_len - consumed
      if remaining == 0 {
        guard self.transport.read_exactly(2) == b"\r\n" else {
          raise ParseBadRequest
        }
      }
      self.body = Chunked(remaining)
      consumed
    }
    Chunked(curr_chunk_remaining) => {
      let consumed = self.decode_chunk(
        buf,
        offset~,
        max_len~,
        limit=curr_chunk_remaining,
      )
      if consumed is 0 {
        raise @io.ReaderClosed
      }
      let remaining = curr_chunk_remaining - consumed
      if remaining == 0 {
        guard self.transport.read_exactly(2) == b"\r\n" else {
          raise ParseBadRequest
        }
      }
      self.body = Chunked(remaining)
      consumed
    }
  }
}

///|
impl @io.Reader for HttpReader with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
async fn HttpReader::read_headers(self : HttpReader) -> @http.Headers {
  let headers : @http.Headers = Map([])
  for ;; {
    guard self.transport.read_until("\r\n") is Some(header_line) else {
      raise @io.ReaderClosed
    }
    if header_line is "" {
      // empty line indicates end of header
      break
    }
    guard header_line.find(":") is Some(colon_index) else {
      raise ParseBadRequest
    }
    let key = @http.CaseInsensitiveString(header_line[:colon_index].to_owned())
    guard colon_index + 1 < header_line.length() else { raise ParseBadRequest }
    let value_start = if header_line.code_unit_at(colon_index + 1) == ' ' {
      colon_index + 2
    } else {
      colon_index + 1
    }
    let value = header_line[value_start:].to_owned()
    if key == "Content-Length" {
      guard !(self.body is Fixed(_)) else { raise ParseBadRequest }
      let len = @string.parse_int(value, base=10)
      if self.body is Empty && len > 0 {
        self.body = Fixed(len)
      }
    } else if key == "Transfer-Encoding" {
      guard !(self.body is Chunked(_)) else { raise ParseBadRequest }
      guard @http.CaseInsensitiveString(value) == "chunked" else {
        raise ParseNotImplemented
      }
      self.body = Chunked(0)
    } else if key == "Set-Cookie" {
      // Requests never carry Set-Cookie; upstream request parsing rejects
      // them via the cookie-count guard after header processing.
      raise ParseBadRequest
    }
    match headers.get(key) {
      None => headers[key] = value
      Some(value0) => headers[key] = "\{value0},\{value}"
    }
  }
  headers
}

///|
/// Read the header of a HTTP/1.1 request from a HTTP reader.
/// This function must be called after the body of the last request is
/// consumed, otherwise it will abort the program immediately.
/// After `read_request` successfully returned,
/// the HTTP reader itself can be used to extract the body of the request.
async fn HttpReader::read_request(self : HttpReader) -> @http.Request {
  guard! self.body is Empty
  guard self.transport.read_until("\r\n") is Some(request_line) else {
    raise @io.ReaderClosed
  }
  guard request_line.find(" ") is Some(meth_len) else { raise ParseBadRequest }
  let meth = match request_line[:meth_len] {
    "GET" => @http.RequestMethod::Get
    "HEAD" => @http.RequestMethod::Head
    "POST" => @http.RequestMethod::Post
    "PUT" => @http.RequestMethod::Put
    "DELETE" => @http.RequestMethod::Delete
    "CONNECT" => @http.RequestMethod::Connect
    "OPTIONS" => @http.RequestMethod::Options
    "TRACE" => @http.RequestMethod::Trace
    "PATCH" => @http.RequestMethod::Patch
    _ => raise ParseBadRequest
  }
  let request_line = request_line[meth_len + 1:]
  guard request_line.find(" ") is Some(path_len) else { raise ParseBadRequest }
  let path = request_line[:path_len].to_owned()
  match request_line[path_len + 1:] {
    "HTTP/1.1" | "HTTP/1.0" => ()
    protocol => raise ParseVersionNotSupported(protocol.to_owned())
  }
  let headers = self.read_headers()
  { meth, path, headers, }
}
