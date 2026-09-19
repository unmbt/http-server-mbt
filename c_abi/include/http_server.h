#ifndef HTTP_SERVER_H
#define HTTP_SERVER_H

#include <stdint.h>
#include <stddef.h>

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

/* ABI version: 0x00010000 represents v1.0 */
HS_EXPORT uint32_t hs_abi_version(void);

/* Opaque handles */
typedef struct hs_engine hs_engine_t;
typedef struct hs_server hs_server_t;

/* Error codes */
enum hs_error_code {
    HS_OK = 0,
    HS_ERR_CONFIG = 1,
    HS_ERR_INVALID_ARG = 2,
    HS_ERR_IO = 3,
    HS_ERR_CLOSED = 4,
    HS_ERR_UNSUPPORTED = 5
};

/* Server lifecycle and error diagnostics */
HS_EXPORT int32_t hs_server_start(const char* json_config, size_t config_len, hs_server_t** out_server);
HS_EXPORT int32_t hs_server_stop(hs_server_t* server);
HS_EXPORT void hs_server_destroy(hs_server_t* server);
HS_EXPORT size_t hs_error_copy(int32_t code, char* buf, size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* HTTP_SERVER_H */
