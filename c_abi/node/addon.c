#define NAPI_VERSION 8
#include "http_server.h"
#include "node_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "async_addon.c"

static napi_value GetAbiVersion(napi_env env, napi_callback_info info) {
  (void)info;
  uint32_t version = hs_abi_version();
  napi_value result;
  napi_create_uint32(env, version, &result);
  return result;
}

static napi_value StartServer(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  hs_node_env *owner = NULL;
  napi_get_cb_info(env, info, &argc, args, NULL, (void **)&owner);
  size_t str_len = 2;
  char *json_buf = argc ? copy_js_string(env, args[0], &str_len) : NULL;
  if (argc && !json_buf)
    return NULL;

  hs_server_t *server = NULL;
  int32_t err = hs_server_start(json_buf ? json_buf : "{}", str_len, &server);
  free(json_buf);
  if (err != HS_OK) {
    char err_msg[128];
    hs_error_copy(err, err_msg, sizeof(err_msg));
    napi_throw_error(env, "SERVER_START_ERROR", err_msg);
    return NULL;
  }

  return wrap_handle(env, owner, 4, server);
}

static napi_value StopServer(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "Expected server handle object");
    return NULL;
  }

  hs_node_handle *h = get_handle(env, args[0], 4);
  if (!h)
    return NULL;
  int32_t code = hs_server_stop(h->ptr);
  if (code) {
    napi_throw(env, node_error(env, code));
    return NULL;
  }
  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

NAPI_MODULE_INIT() {
  hs_node_env *owner = async_addon_init(env, exports);
  napi_value fn_ver, fn_start, fn_stop;
  napi_create_function(env, "getAbiVersion", NAPI_AUTO_LENGTH, GetAbiVersion,
                       NULL, &fn_ver);
  napi_set_named_property(env, exports, "getAbiVersion", fn_ver);

  napi_create_function(env, "startServer", NAPI_AUTO_LENGTH, StartServer, owner,
                       &fn_start);
  napi_set_named_property(env, exports, "startServer", fn_start);

  napi_create_function(env, "stopServer", NAPI_AUTO_LENGTH, StopServer, NULL,
                       &fn_stop);
  napi_set_named_property(env, exports, "stopServer", fn_stop);

  return exports;
}
