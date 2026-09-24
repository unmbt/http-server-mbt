///|
/// Compatibility assertions now target the production lease-based backend.
/// A zero return requires native kernel progress; no buffered fallback exists
/// in this test adapter. The path/offset wrapper is test-only, not a public API.
async fn test_transmit_file(sock : @types.Fd,path : String,offset : Int64,length : Int64) -> Int {
  if length<0L || length>2147483647L { return -1 }
  try {
    let runtime=@native.Runtime::new(workers=4,capacity=256)
    defer runtime.close()
    let root=runtime.open_root(".")
    defer root.close()
    let file=root.open(path)
    defer file.close()
    let mut sent=0L
    // Validate an empty region through the backend too.
    if length==0L { return if file.send(sock,offset,0)==Some(0L) { 0 } else { -1 } }
    while sent<length {
      match file.send(sock,offset+sent,(length-sent).to_int()) {
        None => return -8
        Some(n) => { sent+=n;if n==0L { @async.sleep(1) } }
      }
    }
    0
  } catch { _ => -1 }
}
