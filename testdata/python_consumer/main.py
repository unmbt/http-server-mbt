"""Public ctypes complete-server consumer (D-11), driven by the .mbtx gate."""
import ctypes
import http.client
from pathlib import Path
import socket
import sys

library = ctypes.CDLL(str(Path(sys.argv[1]).resolve()))
library.hs_abi_version.restype = ctypes.c_uint32
library.hs_server_start.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_void_p)]
library.hs_server_start.restype = ctypes.c_int32
library.hs_server_stop.argtypes = [ctypes.c_void_p]
library.hs_server_stop.restype = ctypes.c_int32
library.hs_server_destroy.argtypes = [ctypes.c_void_p]
library.hs_server_destroy.restype = None
assert library.hs_abi_version() == 0x10000
server = ctypes.c_void_p()
assert library.hs_server_start(b"{bad", 4, ctypes.byref(server)) == 1
assert server.value is None
with socket.socket() as reservation:
    reservation.bind(("127.0.0.1", 0))
    port = reservation.getsockname()[1]
fixture = Path("consumer-fixture.txt")
fixture.write_bytes(b"hello consumer\n")
config = ('{"root":".","port":%d,"silent":true}' % port).encode()
assert library.hs_server_start(config, len(config), ctypes.byref(server)) == 0
try:
    client = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    client.request("GET", "/consumer-fixture.txt")
    response = client.getresponse()
    assert response.status == 200 and response.read() == b"hello consumer\n"
    client.request("HEAD", "/consumer-fixture.txt")
    response = client.getresponse()
    assert response.status == 200 and response.read() == b""
    client.request("GET", "/consumer-fixture.txt", headers={"Range": "bytes=2-5"})
    response = client.getresponse()
    assert response.status == 206 and response.read() == b"llo "
    client.close()
finally:
    assert library.hs_server_stop(server) == 0
    assert library.hs_server_stop(server) == 0
    library.hs_server_destroy(server)
    fixture.unlink()
print("Python ctypes consumer: GET/HEAD/Range/config/stop PASS")
