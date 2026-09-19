#define NAPI_VERSION 8
#include "node_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "http_server.h"

static void server_finalizer(napi_env env, void* data, void* hint) {
    (void)env;
    (void)hint;
    if (data != NULL) {
        hs_server_destroy((hs_server_t*)data);
    }
}

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
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);

    char json_buf[4096] = "{}";
    if (argc > 0) {
        size_t str_len = 0;
        napi_status st = napi_get_value_string_utf8(env, args[0], json_buf, sizeof(json_buf), &str_len);
        if (st != napi_ok) {
            napi_throw_type_error(env, NULL, "Configuration must be a valid JSON string");
            return NULL;
        }
    }

    hs_server_t* server = NULL;
    int32_t err = hs_server_start(json_buf, strlen(json_buf), &server);
    if (err != HS_OK) {
        char err_msg[128];
        hs_error_copy(err, err_msg, sizeof(err_msg));
        napi_throw_error(env, "SERVER_START_ERROR", err_msg);
        return NULL;
    }

    napi_value server_obj;
    napi_create_object(env, &server_obj);
    napi_wrap(env, server_obj, server, server_finalizer, NULL, NULL);

    return server_obj;
}

static napi_value StopServer(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);
    if (argc < 1) {
        napi_throw_type_error(env, NULL, "Expected server handle object");
        return NULL;
    }

    void* server_ptr = NULL;
    napi_unwrap(env, args[0], &server_ptr);
    if (server_ptr != NULL) {
        hs_server_stop((hs_server_t*)server_ptr);
    }
    return NULL;
}

NAPI_MODULE_INIT() {
    napi_value fn_ver, fn_start, fn_stop;
    napi_create_function(env, "getAbiVersion", NAPI_AUTO_LENGTH, GetAbiVersion, NULL, &fn_ver);
    napi_set_named_property(env, exports, "getAbiVersion", fn_ver);

    napi_create_function(env, "startServer", NAPI_AUTO_LENGTH, StartServer, NULL, &fn_start);
    napi_set_named_property(env, exports, "startServer", fn_start);

    napi_create_function(env, "stopServer", NAPI_AUTO_LENGTH, StopServer, NULL, &fn_stop);
    napi_set_named_property(env, exports, "stopServer", fn_stop);

    return exports;
}
