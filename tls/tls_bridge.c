/*
 * MbedTLS 4.2 bridge for the `tls` package (D-08 / T-012).
 *
 * Ownership contract (AGENTS Native rules):
 * - Acceptor and connection objects are malloc'd C resources referenced by
 *   Int64 handles. MoonBit wraps each handle in a GC finalizer-backed
 *   external object (`hs_tls_*_wrap`), so resources are released even if an
 *   explicit close is missed; explicit close (`hs_tls_*_close`) is the
 *   normal release point and is idempotent (magic-number guarded).
 * - All FFI calls run on the single async event-loop thread; no locking.
 * - Byte buffers passed from MoonBit (`Bytes` / `FixedArray[Byte]`) are
 *   borrowed for the duration of the call only; the bridge never stores them.
 * - Socket syscalls stay in MoonBit (moonbitlang/async). MbedTLS talks to two
 *   bounded ciphertext rings owned by the connection; the MoonBit transport
 *   feeds the input ring from the socket and drains the output ring to it,
 *   mapping MBEDTLS_ERR_SSL_WANT_READ/WRITE to async waits (D-05).
 *
 * Return-code conventions (per function):
 * - `_new` constructors: > 0 = Int64 handle; < 0 = -(1000000 + |mbedtls/psa
 *   code|); constructors never return 0.
 * - `handshake`/`shutdown`: 0 = done, -1 = WANT_READ (feed then retry),
 *   -2 = WANT_WRITE (drain then retry), < -1000 = -(1000000 + |code|).
 * - `read`: > 0 = decrypted bytes, 0 = clean EOF (close_notify),
 *   -1/-2 as above, < -1000 = -(1000000 + |code|).
 * - `write`: >= 0 = plaintext bytes accepted (partial writes possible),
 *   -1/-2 as above, < -1000 = -(1000000 + |code|).
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <mbedtls/ssl.h>
#include <mbedtls/x509_crt.h>
#include <mbedtls/pk.h>
#include <mbedtls/error.h>

#include <psa/crypto.h>

#include "moonbit.h"

#define HS_TLS_BUF_CAP (16384 + 512) /* max TLS record + header/tag margin */

#define HS_TLS_ERR_OFFSET 1000000
#define HS_TLS_ERR(code) (-(HS_TLS_ERR_OFFSET - (code))) /* code < 0 */
#define HS_TLS_ERR_NOMEM HS_TLS_ERR(-0x7F00)
#define HS_TLS_ERR_CLOSED HS_TLS_ERR(-0x7F01)
#define HS_TLS_ERR_BAD_HANDLE HS_TLS_ERR(-0x7F02)
#define HS_TLS_ERR_OVERFLOW HS_TLS_ERR(-0x7F03)
#define HS_TLS_PSA_OFFSET 100000 /* decoded psa code = -(ret + offset) */

#define HS_TLS_CONN_MAGIC 0x4853544C434E4E31ULL /* "HSTLCNN1" */
#define HS_TLS_ACC_MAGIC 0x4853544C41434331ULL  /* "HSTLACC1" */

typedef struct {
  uint64_t magic;
  mbedtls_ssl_config conf;
  mbedtls_x509_crt chain;  /* server: own cert chain; client: trust roots */
  mbedtls_pk_context pkey; /* server only */
  int has_own_cert;
  int is_client;
} hs_tls_acceptor_t;

typedef struct {
  uint64_t magic;
  mbedtls_ssl_context ssl;
  unsigned char *in; /* ciphertext from peer, fed by MoonBit */
  size_t in_len;
  unsigned char *out; /* ciphertext for peer, drained by MoonBit */
  size_t out_len;
} hs_tls_conn_t;

/* GC finalizer thunks (forward declarations for the wrap functions). */
static void hs_tls_conn_finalize(void *ptr);
static void hs_tls_acceptor_finalize(void *ptr);

/* ------------------------------------------------------------------ */
/* Object counters (leak probes for T-012 resource tests)              */

static int hs_tls_conn_count = 0;
static int hs_tls_acceptor_count = 0;

MOONBIT_FFI_EXPORT int32_t
http_server_tls_conn_count(void) {
  return hs_tls_conn_count;
}

MOONBIT_FFI_EXPORT int32_t
http_server_tls_acceptor_count(void) {
  return hs_tls_acceptor_count;
}

/* ------------------------------------------------------------------ */
/* Global PSA init                                                     */

MOONBIT_FFI_EXPORT int32_t
http_server_tls_global_init(void) {
  static int inited = 0;
  if (inited) return 0;
  psa_status_t st = psa_crypto_init();
  if (st != PSA_SUCCESS) {
    return -(HS_TLS_PSA_OFFSET + (int)st);
  }
  inited = 1;
  return 0;
}

/* ------------------------------------------------------------------ */
/* Error string helper                                                 */

/* Returns the human-readable message for a decoded error code as a
 * MoonBit-owned Bytes (null-terminated C string copied out). */
MOONBIT_FFI_EXPORT moonbit_bytes_t
http_server_tls_strerror(int32_t code) {
  char target[512] = {0};
  if (code <= -HS_TLS_PSA_OFFSET) {
    snprintf(target, sizeof target, "PSA error %d",
             -(code + HS_TLS_PSA_OFFSET));
  } else if (code <= -HS_TLS_ERR_OFFSET) {
    mbedtls_strerror(code + HS_TLS_ERR_OFFSET, target, sizeof target);
  } else {
    mbedtls_strerror(code, target, sizeof target);
  }
  int n = (int)strlen(target);
  moonbit_bytes_t out = moonbit_make_bytes(n, 0);
  memcpy(out, target, (size_t)n);
  return out;
}

/* ------------------------------------------------------------------ */
/* Acceptors                                                           */

static void
hs_tls_acceptor_destroy(int64_t handle) {
  hs_tls_acceptor_t *acc = (hs_tls_acceptor_t *)(uintptr_t)handle;
  if (acc == NULL || acc->magic != HS_TLS_ACC_MAGIC) return;
  acc->magic = 0;
  mbedtls_ssl_config_free(&acc->conf);
  mbedtls_x509_crt_free(&acc->chain);
  mbedtls_pk_free(&acc->pkey);
  free(acc);
  hs_tls_acceptor_count -= 1;
}

static int
hs_tls_acceptor_setup_common(hs_tls_acceptor_t *acc, int is_client) {
  int ret = mbedtls_ssl_config_defaults(
    &acc->conf,
    is_client ? MBEDTLS_SSL_IS_CLIENT : MBEDTLS_SSL_IS_SERVER,
    MBEDTLS_SSL_TRANSPORT_STREAM,
    MBEDTLS_SSL_VERSION_TLS1_2);
  if (ret != 0) return ret;
  /* Allow negotiating up to TLS 1.3 on top of the 1.2 defaults. */
  mbedtls_ssl_conf_max_tls_version(&acc->conf, MBEDTLS_SSL_VERSION_TLS1_3);
  return 0;
}

MOONBIT_FFI_EXPORT int64_t
http_server_tls_acceptor_new_server(const char *cert, int32_t cert_len,
                                    const char *key, int32_t key_len,
                                    const char *pass, int32_t pass_len) {
  hs_tls_acceptor_t *acc = calloc(1, sizeof(hs_tls_acceptor_t));
  if (acc == NULL) return HS_TLS_ERR_NOMEM;
  mbedtls_ssl_config_init(&acc->conf);
  mbedtls_x509_crt_init(&acc->chain);
  mbedtls_pk_init(&acc->pkey);
  acc->magic = HS_TLS_ACC_MAGIC;
  hs_tls_acceptor_count += 1;
  acc->is_client = 0;
  int ret;
  if ((ret = hs_tls_acceptor_setup_common(acc, 0)) != 0 ||
      (ret = mbedtls_x509_crt_parse(&acc->chain, (const unsigned char *)cert,
                                    (size_t)cert_len)) != 0) {
    goto fail;
  }
  ret = mbedtls_pk_parse_key(&acc->pkey, (const unsigned char *)key,
                             (size_t)key_len,
                             pass_len > 0 ? (const unsigned char *)pass : NULL,
                             (size_t)pass_len);
  if (ret != 0) goto fail;
  if ((ret = mbedtls_ssl_conf_own_cert(&acc->conf, &acc->chain,
                                       &acc->pkey)) != 0) {
    goto fail;
  }
  acc->has_own_cert = 1;
  return (int64_t)(uintptr_t)acc;
fail:
  hs_tls_acceptor_destroy((int64_t)(uintptr_t)acc);
  return HS_TLS_ERR(ret);
}

MOONBIT_FFI_EXPORT int64_t
http_server_tls_acceptor_new_client(const char *ca, int32_t ca_len,
                                    int32_t insecure) {
  hs_tls_acceptor_t *acc = calloc(1, sizeof(hs_tls_acceptor_t));
  if (acc == NULL) return HS_TLS_ERR_NOMEM;
  mbedtls_ssl_config_init(&acc->conf);
  mbedtls_x509_crt_init(&acc->chain);
  mbedtls_pk_init(&acc->pkey);
  acc->magic = HS_TLS_ACC_MAGIC;
  hs_tls_acceptor_count += 1;
  acc->is_client = 1;
  int ret;
  if ((ret = hs_tls_acceptor_setup_common(acc, 1)) != 0) goto fail;
  if (insecure) {
    mbedtls_ssl_conf_authmode(&acc->conf, MBEDTLS_SSL_VERIFY_NONE);
  } else {
    if (ca_len <= 0) {
      /* No trust roots configured and verification requested: fail fast
       * instead of silently shipping a connection that can never verify. */
      ret = MBEDTLS_ERR_X509_FILE_IO_ERROR;
      goto fail;
    }
    ret = mbedtls_x509_crt_parse(&acc->chain, (const unsigned char *)ca,
                                 (size_t)ca_len);
    if (ret != 0) goto fail;
    mbedtls_ssl_conf_ca_chain(&acc->conf, &acc->chain, NULL);
    mbedtls_ssl_conf_authmode(&acc->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
  }
  return (int64_t)(uintptr_t)acc;
fail:
  hs_tls_acceptor_destroy((int64_t)(uintptr_t)acc);
  return HS_TLS_ERR(ret);
}

MOONBIT_FFI_EXPORT void
http_server_tls_acceptor_close(int64_t handle) {
  hs_tls_acceptor_destroy(handle);
}

static hs_tls_acceptor_t *
hs_tls_acceptor_get(int64_t handle) {
  hs_tls_acceptor_t *acc = (hs_tls_acceptor_t *)(uintptr_t)handle;
  if (acc == NULL || acc->magic != HS_TLS_ACC_MAGIC) return NULL;
  return acc;
}

/* ------------------------------------------------------------------ */
/* Connections                                                         */

static int
hs_tls_bio_send(void *ctx, const unsigned char *buf, size_t len) {
  hs_tls_conn_t *c = (hs_tls_conn_t *)ctx;
  if (c->out_len + len > HS_TLS_BUF_CAP) {
    /* Partial write; MbedTLS retries after MoonBit drains the ring. */
    size_t take = HS_TLS_BUF_CAP - c->out_len;
    if (take == 0) return MBEDTLS_ERR_SSL_WANT_WRITE;
    memcpy(c->out + c->out_len, buf, take);
    c->out_len += take;
    return (int)take;
  }
  memcpy(c->out + c->out_len, buf, len);
  c->out_len += len;
  return (int)len;
}

static int
hs_tls_bio_recv(void *ctx, unsigned char *buf, size_t len) {
  hs_tls_conn_t *c = (hs_tls_conn_t *)ctx;
  if (c->in_len == 0) return MBEDTLS_ERR_SSL_WANT_READ;
  size_t n = len < c->in_len ? len : c->in_len;
  memcpy(buf, c->in, n);
  memmove(c->in, c->in + n, c->in_len - n);
  c->in_len -= n;
  return (int)n;
}

static void
hs_tls_conn_destroy(int64_t handle) {
  hs_tls_conn_t *c = (hs_tls_conn_t *)(uintptr_t)handle;
  if (c == NULL || c->magic != HS_TLS_CONN_MAGIC) return;
  c->magic = 0;
  mbedtls_ssl_free(&c->ssl);
  free(c->in);
  free(c->out);
  free(c);
  hs_tls_conn_count -= 1;
}

MOONBIT_FFI_EXPORT int64_t
http_server_tls_conn_new(int64_t acceptor_handle, const char *hostname,
                         int32_t hostname_len) {
  hs_tls_acceptor_t *acc = hs_tls_acceptor_get(acceptor_handle);
  if (acc == NULL) return HS_TLS_ERR_BAD_HANDLE;
  hs_tls_conn_t *c = calloc(1, sizeof(hs_tls_conn_t));
  if (c == NULL) return HS_TLS_ERR_NOMEM;
  c->magic = HS_TLS_CONN_MAGIC;
  hs_tls_conn_count += 1;
  c->in = malloc(HS_TLS_BUF_CAP);
  c->out = malloc(HS_TLS_BUF_CAP);
  if (c->in == NULL || c->out == NULL) {
    /* magic is set, so destroy releases everything initialized so far. */
    hs_tls_conn_destroy((int64_t)(uintptr_t)c);
    return HS_TLS_ERR_NOMEM;
  }
  mbedtls_ssl_init(&c->ssl);
  int ret = mbedtls_ssl_setup(&c->ssl, &acc->conf);
  if (ret != 0) {
    hs_tls_conn_destroy((int64_t)(uintptr_t)c);
    return HS_TLS_ERR(ret);
  }
  if (hostname_len > 0) {
    /* Hostname doubles as SNI and (client-side) CN/SAN verification target. */
    ret = mbedtls_ssl_set_hostname(&c->ssl, hostname);
    if (ret != 0) {
      hs_tls_conn_destroy((int64_t)(uintptr_t)c);
      return HS_TLS_ERR(ret);
    }
  }
  mbedtls_ssl_set_bio(&c->ssl, c, hs_tls_bio_send, hs_tls_bio_recv, NULL);
  return (int64_t)(uintptr_t)c;
}

static hs_tls_conn_t *
hs_tls_conn_get(int64_t handle) {
  hs_tls_conn_t *c = (hs_tls_conn_t *)(uintptr_t)handle;
  if (c == NULL || c->magic != HS_TLS_CONN_MAGIC) return NULL;
  return c;
}

/* ------------------------------------------------------------------ */
/* GC finalizer wrappers: release the C resource if MoonBit forgot.    */
/*
 * The external object's slot is the SINGLE ownership token. Explicit close
 * and the GC finalizer both go through `hs_tls_*_close_obj`, which zeroes
 * the slot before destroying, so the resource is released exactly once no
 * matter which path runs first (destroying from a stale handle would be a
 * use-after-free once the address has been reused).
 */

MOONBIT_FFI_EXPORT void *
http_server_tls_conn_wrap(int64_t handle) {
  if (hs_tls_conn_get(handle) == NULL) return NULL;
  int64_t *slot = (int64_t *)moonbit_make_external_object(
    hs_tls_conn_finalize, sizeof(int64_t));
  *slot = handle;
  return slot;
}

MOONBIT_FFI_EXPORT void *
http_server_tls_acceptor_wrap(int64_t handle) {
  if (hs_tls_acceptor_get(handle) == NULL) return NULL;
  int64_t *slot = (int64_t *)moonbit_make_external_object(
    hs_tls_acceptor_finalize, sizeof(int64_t));
  *slot = handle;
  return slot;
}

MOONBIT_FFI_EXPORT void
http_server_tls_conn_close_obj(void *obj) {
  int64_t *slot = (int64_t *)obj;
  int64_t handle = *slot;
  if (handle == 0) return;
  *slot = 0;
  hs_tls_conn_destroy(handle);
}

MOONBIT_FFI_EXPORT void
http_server_tls_acceptor_close_obj(void *obj) {
  int64_t *slot = (int64_t *)obj;
  int64_t handle = *slot;
  if (handle == 0) return;
  *slot = 0;
  hs_tls_acceptor_destroy(handle);
}

static void
hs_tls_conn_finalize(void *ptr) {
  http_server_tls_conn_close_obj(ptr);
  /* GC owns the container; only the inner resource is released. */
}

static void
hs_tls_acceptor_finalize(void *ptr) {
  http_server_tls_acceptor_close_obj(ptr);
}

/* ------------------------------------------------------------------ */
/* I/O operations                                                      */

/* Append ciphertext bytes to the connection input ring. */
MOONBIT_FFI_EXPORT int32_t
http_server_tls_feed(int64_t handle, const char *buf, int32_t len) {
  hs_tls_conn_t *c = hs_tls_conn_get(handle);
  if (c == NULL) return HS_TLS_ERR_BAD_HANDLE;
  if (len <= 0) return 0;
  if (c->in_len + (size_t)len > HS_TLS_BUF_CAP) {
    /* MoonBit must respect in_space; treat overflow as a transport bug
     * rather than dropping bytes. */
    return HS_TLS_ERR_OVERFLOW;
  }
  memcpy(c->in + c->in_len, buf, (size_t)len);
  c->in_len += (size_t)len;
  return len;
}

MOONBIT_FFI_EXPORT int32_t
http_server_tls_in_space(int64_t handle) {
  hs_tls_conn_t *c = hs_tls_conn_get(handle);
  if (c == NULL) return HS_TLS_ERR_BAD_HANDLE;
  return (int32_t)(HS_TLS_BUF_CAP - c->in_len);
}

/* Drain pending ciphertext into the caller's buffer. */
MOONBIT_FFI_EXPORT int32_t
http_server_tls_take_output(int64_t handle, char *buf, int32_t cap) {
  hs_tls_conn_t *c = hs_tls_conn_get(handle);
  if (c == NULL) return HS_TLS_ERR_BAD_HANDLE;
  if (cap <= 0 || c->out_len == 0) return 0;
  size_t n = (size_t)cap < c->out_len ? (size_t)cap : c->out_len;
  memcpy(buf, c->out, n);
  memmove(c->out, c->out + n, c->out_len - n);
  c->out_len -= n;
  return (int32_t)n;
}

MOONBIT_FFI_EXPORT int32_t
http_server_tls_output_pending(int64_t handle) {
  hs_tls_conn_t *c = hs_tls_conn_get(handle);
  if (c == NULL) return HS_TLS_ERR_BAD_HANDLE;
  return (int32_t)c->out_len;
}

MOONBIT_FFI_EXPORT int32_t
http_server_tls_handshake(int64_t handle) {
  hs_tls_conn_t *c = hs_tls_conn_get(handle);
  if (c == NULL) return HS_TLS_ERR_BAD_HANDLE;
  int ret = mbedtls_ssl_handshake(&c->ssl);
  if (ret == 0) return 0;
  if (ret == MBEDTLS_ERR_SSL_WANT_READ) return -1;
  if (ret == MBEDTLS_ERR_SSL_WANT_WRITE) return -2;
  return HS_TLS_ERR(ret);
}

/* Decrypt into the caller's buffer at the given offset.
 * Returns > 0 bytes, 0 clean EOF, -1 WANT_READ, -2 WANT_WRITE,
 * < -1000 encoded error. */
MOONBIT_FFI_EXPORT int32_t
http_server_tls_read(int64_t handle, char *buf, int32_t offset, int32_t cap) {
  hs_tls_conn_t *c = hs_tls_conn_get(handle);
  if (c == NULL) return HS_TLS_ERR_BAD_HANDLE;
  if (cap <= 0) return 0;
  int ret = mbedtls_ssl_read(&c->ssl, (unsigned char *)buf + offset,
                             (size_t)cap);
  if (ret > 0) return ret;
  if (ret == 0) return 0; /* peer sent close_notify with no data */
  if (ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) return 0;
  if (ret == MBEDTLS_ERR_SSL_WANT_READ) return -1;
  if (ret == MBEDTLS_ERR_SSL_WANT_WRITE) return -2;
  return HS_TLS_ERR(ret);
}

/* Encrypt plaintext from the caller's buffer at the given offset.
 * Returns >= 0 accepted bytes (may be partial), -1 WANT_READ,
 * -2 WANT_WRITE, < -1000 encoded error. */
MOONBIT_FFI_EXPORT int32_t
http_server_tls_write(int64_t handle, const char *buf, int32_t offset,
                      int32_t len) {
  hs_tls_conn_t *c = hs_tls_conn_get(handle);
  if (c == NULL) return HS_TLS_ERR_BAD_HANDLE;
  if (len <= 0) return 0;
  int ret = mbedtls_ssl_write(&c->ssl, (const unsigned char *)buf + offset,
                              (size_t)len);
  if (ret > 0) return ret;
  if (ret == MBEDTLS_ERR_SSL_WANT_READ) return -1;
  if (ret == MBEDTLS_ERR_SSL_WANT_WRITE) return -2;
  return HS_TLS_ERR(ret);
}

MOONBIT_FFI_EXPORT int32_t
http_server_tls_shutdown(int64_t handle) {
  hs_tls_conn_t *c = hs_tls_conn_get(handle);
  if (c == NULL) return HS_TLS_ERR_BAD_HANDLE;
  int ret = mbedtls_ssl_close_notify(&c->ssl);
  if (ret == 0) return 0;
  if (ret == MBEDTLS_ERR_SSL_WANT_READ) return -1;
  if (ret == MBEDTLS_ERR_SSL_WANT_WRITE) return -2;
  return HS_TLS_ERR(ret);
}

MOONBIT_FFI_EXPORT int32_t
http_server_tls_handshake_over(int64_t handle) {
  hs_tls_conn_t *c = hs_tls_conn_get(handle);
  if (c == NULL) return HS_TLS_ERR_BAD_HANDLE;
  return mbedtls_ssl_is_handshake_over(&c->ssl) ? 1 : 0;
}
