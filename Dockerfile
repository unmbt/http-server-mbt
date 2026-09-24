# syntax=docker/dockerfile:1
# ----------------------------------------------------------------------
# Full Variant Dockerfile
# Based on Google Distroless static nonroot image (D-15 specification).
# Packages pre-compiled static binary with TLS, Proxy, WebSocket support.
# ----------------------------------------------------------------------

ARG BASE_IMAGE=gcr.io/distroless/static-debian12@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
FROM ${BASE_IMAGE}

ARG BINARY_PATH=http-server-mbt

# Default directory to serve files from
WORKDIR /data

# Copy pre-compiled binary from host / CI build artifact
COPY --chmod=0555 ${BINARY_PATH} /usr/local/bin/http-server-mbt

# UID 65532 is nonroot user in Distroless
USER 65532:65532
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/http-server-mbt"]
CMD [".", "-p", "8080"]
