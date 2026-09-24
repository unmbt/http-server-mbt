///|
test "c_abi_min_smoke" {
  inspect(@thin.hs_abi_version(), content="65536")
}

