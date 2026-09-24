# Container base provenance (D-15)

The default base is `gcr.io/distroless/static-debian12` at OCI index digest
`sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab`.
The Linux amd64 image manifest is
`sha256:52dcfbabb7457ea47c82f6e13af8c8a4a1d9f7b0145142b3ecab20f2b888411d`.

On 2026-09-24 the `nonroot` index was retrieved through the NJU registry mirror
(`https://gcr.nju.edu.cn/v2/distroless/static-debian12/manifests/nonroot`).
The 1,514 downloaded bytes independently hash to the index digest above.
Direct GCR access timed out on the local Windows network. The Linux acceptance
job must successfully pull the pinned GCR digest before container validation can
pass; the metadata lookup is not evidence that any image has run.

`BASE_IMAGE=scratch` produces the other two combinations. Each variant reuses
the same verified musl CLI and sets UID/GID 65532. Image inventories and CLI
inventories remain separate; the Distroless base includes its own Debian
copyright and certificate resources. Full's upstream default trust comes from
its embedded pinned Mozilla bundle in either base.
