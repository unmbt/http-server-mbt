///|
async test "N-20 rooted links permit internal targets and reject escapes before fallback" {
  let dir=@fs.tmpdir(prefix="hs-links-")
  defer @fs.rmdir(dir,recursive=true)
  let root=dir+"/root"
  @fs.mkdir(root)
  @fs.mkdir(root+"/inside")
  @fs.mkdir(dir+"/outside")
  @fs.write_file(root+"/inside/file","inside")
  @fs.write_file(dir+"/outside/file","outside")
  @fs.write_file(root+"/index.html","fallback")
  @fs.symlink(target=@fs.realpath(root+"/inside"),root+"/good")
  @fs.symlink(target=@fs.realpath(dir+"/outside"),root+"/bad")
  let config={..@core.Config::default(root),spa:true}
  @http-server-mbt.with_engine(config,engine => {
    assert_eq(response_for(engine,"/good/file").to_bytes(max_bytes=64),b"inside")
    assert_true(engine.handle({meth:Get,target:"/bad/file",headers:Map([])}) is Error(@http-server-mbt.ServerError::Forbidden(_)))
  })
}
