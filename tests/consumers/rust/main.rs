//! External static-library consumer, complete-server mode only (D-11/T-027).
use std::ffi::{c_char, c_void};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::time::Duration;
extern "C" {
    fn hs_abi_version() -> u32;
    fn hs_server_start(config: *const c_char, len: usize, server: *mut *mut c_void) -> i32;
    fn hs_server_stop(server: *mut c_void) -> i32;
    fn hs_server_destroy(server: *mut c_void);
}
fn request(port: u16, method: &str, range: &str, status: &str, body: &str) {
    let mut stream=TcpStream::connect(("127.0.0.1",port)).unwrap();
    stream.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
    write!(stream,"{method} /consumer-fixture.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n{range}\r\n").unwrap();
    let mut response=String::new();stream.read_to_string(&mut response).unwrap();
    assert!(response.starts_with(status));
    assert_eq!(response.split_once("\r\n\r\n").unwrap().1,body);
}
fn main() {
    let listener=TcpListener::bind(("127.0.0.1",0)).unwrap();
    let port=listener.local_addr().unwrap().port();drop(listener);
    std::fs::write("consumer-fixture.txt",b"hello consumer\n").unwrap();
    let config=format!("{{\"root\":\".\",\"port\":{port},\"silent\":true}}");
    let mut server=std::ptr::null_mut();
    unsafe {
        assert_eq!(hs_abi_version(),0x10000);
        assert_eq!(hs_server_start(b"{bad".as_ptr().cast(),4,&mut server),1);
        assert!(server.is_null());
        assert_eq!(hs_server_start(config.as_ptr().cast(),config.len(),&mut server),0);
    }
    request(port,"GET","","HTTP/1.1 200 ","hello consumer\n");
    request(port,"HEAD","","HTTP/1.1 200 ","");
    request(port,"GET","Range: bytes=2-5\r\n","HTTP/1.1 206 ","llo ");
    unsafe {
        assert_eq!(hs_server_stop(server),0);
        assert_eq!(hs_server_stop(server),0);
        hs_server_destroy(server);
    }
    std::fs::remove_file("consumer-fixture.txt").unwrap();
    println!("Rust static consumer: GET/HEAD/Range/config/stop PASS");
}
