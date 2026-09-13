///|
test "is_reportable_local_ip filters empty, loopback and unspecified" {
  assert_false(is_reportable_local_ip(""))
  assert_false(is_reportable_local_ip("127.0.0.1"))
  assert_false(is_reportable_local_ip("127.8.8.8"))
  assert_false(is_reportable_local_ip("0.0.0.0"))
  assert_true(is_reportable_local_ip("192.168.1.10"))
  assert_true(is_reportable_local_ip("10.0.0.2"))
  assert_true(is_reportable_local_ip("172.16.0.9"))
}

///|
test "parse_local_ips keeps unique reportable addresses in order" {
  let raw = b"192.168.1.10\n192.168.1.10\n0.0.0.0\n127.0.0.1\n10.0.0.2\n"
  debug_inspect(
    parse_local_ips(raw),
    content="[\"192.168.1.10\", \"10.0.0.2\"]",
  )
}

///|
test "parse_local_ips tolerates empty and partial output" {
  debug_inspect(parse_local_ips(b""), content="[]")
  debug_inspect(parse_local_ips(b"\n"), content="[]")
  debug_inspect(parse_local_ips(b"127.0.0.1"), content="[]")
}

///|
test "local_ips ffi output only contains reportable unique addresses" {
  let ips = local_ips()
  for i, ip in ips {
    assert_true(is_reportable_local_ip(ip))
    for j in 0..<i {
      assert_false(ips[j] == ip)
    }
  }
}

///|
test "TEMP debug dump local_ips" {
  debug_inspect(local_ips(), content="")
}
