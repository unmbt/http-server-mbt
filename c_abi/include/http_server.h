#ifndef HTTP_SERVER_H
#define HTTP_SERVER_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(HS_BUILD_DLL)
#define HS_EXPORT __declspec(dllexport)
#elif defined(HS_STATIC)
#define HS_EXPORT
#else
#define HS_EXPORT __declspec(dllimport)
#endif
#else
#define HS_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Additive ABI 1.1. Compare the major; require minor >= 1 for async APIs. */
#define HS_ABI_VERSION UINT32_C(0x00010001)
#define HS_ABI_MAJOR UINT32_C(1)
HS_EXPORT uint32_t hs_abi_version(void);

/* Opaque handles */
typedef struct hs_engine hs_engine_t;
typedef struct hs_server hs_server_t;
typedef struct hs_operation hs_operation_t;
typedef struct hs_response hs_response_t;
typedef struct hs_chunk hs_chunk_t;

/* Error codes */
enum hs_error_code {
  HS_OK = 0,
  HS_ERR_CONFIG = 1,
  HS_ERR_INVALID_ARG = 2,
  HS_ERR_IO = 3,
  HS_ERR_CLOSED = 4,
  HS_ERR_UNSUPPORTED = 5,
  HS_ERR_UPSTREAM = 6,
  HS_ERR_TIMEOUT = 7,
  HS_ERR_CANCELLED = 8,
  HS_ERR_FILE_CHANGED = 9,
  HS_ERR_LIMIT = 10,
  HS_ERR_BUSY = 11,
  HS_ERR_ABI_MISMATCH = 12
};

typedef struct hs_span {
  const uint8_t *data;
  uint64_t length;
} hs_span_t;
typedef struct hs_header {
  hs_span_t name, value;
} hs_header_t;
typedef struct hs_request {
  uint32_t struct_size, abi_major;
  hs_span_t method, target;
  const hs_header_t *headers;
  uint32_t header_count, reserved;
} hs_request_t;
typedef struct hs_response_meta {
  uint32_t struct_size, abi_major;
  int32_t status;
  uint32_t header_count;
  const hs_header_t *headers;
  uint64_t content_length;
  uint32_t has_content_length, reserved;
} hs_response_meta_t;
enum hs_result_kind {
  HS_RESULT_DONE = 0,
  HS_RESULT_ENGINE = 1,
  HS_RESULT_SERVER = 2,
  HS_RESULT_HANDLED = 3,
  HS_RESULT_NEXT = 4,
  HS_RESULT_CHUNK = 5,
  HS_RESULT_EOF = 6
};
/* Event is borrowed during callback. A successful result handle transfers one
 * reference. callback/user_data must survive until this final notification. */
typedef struct hs_event {
  uint32_t struct_size, abi_major;
  int32_t code;
  uint32_t kind;
  hs_engine_t *engine;
  hs_server_t *server;
  hs_response_t *response;
  hs_chunk_t *chunk;
} hs_event_t;
typedef void (*hs_callback_t)(void *user_data, const hs_event_t *event);

/* HS_OK means accepted, exactly one non-inline callback. Any other return
 * rejects, clears out_operation, and never calls callback. Input is copied.
 * Callback may race the return; never wait synchronously on the notifier.
 * All async functions require a callback and out_operation. */
HS_EXPORT int32_t hs_engine_create_async(const char *, size_t, hs_callback_t,
                                         void *, hs_operation_t **);
HS_EXPORT int32_t hs_engine_close_async(hs_engine_t *, hs_callback_t, void *,
                                        hs_operation_t **);
/* Explicit close is required. On a host thread, release of a closing instance
 * waits for close/notification return and joins the last runtime's threads.
 * Release inside a library callback never waits. Unload only on a host thread
 * after this barrier and after releasing all operation/response/chunk handles.
 */
HS_EXPORT void hs_engine_release(hs_engine_t *);
HS_EXPORT int32_t hs_submit_async(hs_engine_t *, const hs_request_t *,
                                  hs_callback_t, void *, hs_operation_t **);
HS_EXPORT void hs_operation_cancel(hs_operation_t *);
HS_EXPORT void hs_operation_release(hs_operation_t *);
/* meta must be initialized with sizeof(*meta), HS_ABI_MAJOR. */
HS_EXPORT int32_t hs_response_meta(hs_response_t *, hs_response_meta_t *meta);
HS_EXPORT int32_t hs_response_read_async(hs_response_t *, uint32_t max_bytes,
                                         hs_callback_t, void *,
                                         hs_operation_t **);
HS_EXPORT void hs_response_release(hs_response_t *);
HS_EXPORT hs_span_t hs_chunk_data(const hs_chunk_t *);
HS_EXPORT void hs_chunk_release(hs_chunk_t *);
HS_EXPORT int32_t hs_server_start_async(const char *, size_t, hs_callback_t,
                                        void *, hs_operation_t **);
HS_EXPORT int32_t hs_server_stop_async(hs_server_t *, hs_callback_t, void *,
                                       hs_operation_t **);
HS_EXPORT void hs_server_release(hs_server_t *);

/* Server lifecycle and error diagnostics */
HS_EXPORT int32_t hs_server_start(const char *json_config, size_t config_len,
                                  hs_server_t **out_server);
HS_EXPORT int32_t hs_server_stop(hs_server_t *server);
HS_EXPORT void hs_server_destroy(hs_server_t *server);
HS_EXPORT size_t hs_error_copy(int32_t code, char *buf, size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* HTTP_SERVER_H */
