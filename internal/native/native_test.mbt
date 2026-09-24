///|
async test "native rooted lease and bounded worker completion" {
  let runtime = @native.Runtime::new(workers=2, capacity=8)
  defer runtime.close()
  let root = runtime.open_root("testdata/public")
  defer root.close()
  let file = root.open("hello.txt")
  defer file.close()
  assert_eq(file.size, 14L)
  assert_eq(file.read(0L, 14), b"hello moonbit\n")
  file.check()
  let (names,charge) = root.names(1048576L)
  defer runtime.release(directory=true,charge)
  assert_true(names.contains("hello.txt"))
}
