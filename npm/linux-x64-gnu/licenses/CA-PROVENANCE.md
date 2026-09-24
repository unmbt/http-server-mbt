# Mozilla trust roots

Full embeds Mozilla certificate data extracted by curl, dated **2025-09-09 03:12:01 UTC**, using mk-ca-bundle.pl 1.29.

- Source: https://curl.se/ca/cacert-2025-09-09.pem
- Extraction documentation: https://curl.se/docs/caextract.html
- File SHA-256: `f290e6acaf904a4121424ca3ebdd70652780707e28e8af999221786b86bb1975`
- License: Mozilla Public License 2.0, included in `LICENSE-MPL-2.0.txt`.
- Reproduce the embedded MoonBit source: `moon run scripts/embed_ca.mbtx`.

The hash above covers the complete downloaded file, including its comments. The SHA-256 in the PEM comment refers to the certificate data and is a different hash. Updates require an explicit source/date/hash change and validation. Builds do not fetch trust roots from the network.

An explicit `ca_file` **replaces** this trust store. `secure=false` is the only setting that disables certificate and hostname verification. Thin imports neither this resource nor the MbedTLS backend.
