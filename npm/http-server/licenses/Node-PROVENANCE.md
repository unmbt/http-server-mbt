# Node-API build inputs

The four headers in `include/` are unmodified from Node.js **v22.14.0**,
`https://nodejs.org/dist/v22.14.0/node-v22.14.0-headers.tar.gz`.
Archive SHA-256: `715aedf641a024efdeeccd545ce4acdc4759155e08c32efdfe9069921fcfa86b`,
verified against that release's `SHASUMS256.txt` on 2026-09-24.
The prior mixed header set was replaced as part of T-025 packaging hardening.
Node's license and third-party notices are in `LICENSE-NODE.txt` (v22.14.0).

Windows links the Node-API import library from
`https://nodejs.org/dist/v20.16.0/win-x64/node.lib`, SHA-256
`87056190b7cd06f40058f8e059efd328cdcc7600b825afa102c0aa5039865af5`.
The driver checks that hash, including cached copies, and never chooses an
arbitrary installed Node version. The addon uses Node-API 8; validation hosts
are Node 22.21.1 and 24.10.0. This records build inputs, not Node 20 support.

The project and npm package metadata use MIT. Vendored Node, MbedTLS/TF-PSA,
MoonBit/async and Mozilla resources retain their respective licenses.
