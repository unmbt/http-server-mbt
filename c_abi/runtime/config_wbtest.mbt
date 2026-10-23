///|
test "C ABI JSON accepts io_backend" {
  let value = @json.parse(
    "{\"root\":\"public\",\"io_backend\":\"auto\",\"port\":0}",
  )
  let config = decode_config_value(value, false, true)
  assert_eq(config.io_backend, "auto")
  assert_eq(config.root, "public")
  assert_eq(config.port, 0)
}

///|
test "C ABI JSON rejects unknown io_backend" {
  let value = @json.parse("{\"io_backend\":\"liburing\"}")
  assert_false(
    try {
      ignore(decode_config_value(value, false, true))
      true
    } catch {
      _ => false
    },
  )
}
