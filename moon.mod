name = "unmbt/http-server-mbt"

version = "0.5.0"

import {
  "moonbitlang/async@0.22.7",
  "unmbt/moon-manifest@0.1.1",
  "unmbt/native-toolchain@0.1.1",
}

readme = "README.md"

repository = "https://github.com/unmbt/http-server-mbt"

license = "MIT"

preferred_target = "native"

options(
  "--moonbit-unstable-prebuild": "build.mbtx",
)
