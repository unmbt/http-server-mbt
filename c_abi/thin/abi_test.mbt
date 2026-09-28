///|
test "c_abi_min_smoke" {
  assert_eq(@thin.hs_abi_version(), 0x00010001U)
}
