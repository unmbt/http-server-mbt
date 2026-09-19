#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include "../../c_abi/include/http_server.h"

int main(void) {
    printf("[test_dynamic_min] Testing hs_abi_version...\n");
    uint32_t ver = hs_abi_version();
    printf("[test_dynamic_min] ABI version: 0x%08X\n", ver);
    assert(ver == 0x00010000);

    printf("[test_dynamic_min] Testing hs_error_copy...\n");
    char err_buf[64];
    size_t err_len = hs_error_copy(HS_ERR_CONFIG, err_buf, sizeof(err_buf));
    printf("[test_dynamic_min] Error msg: %s (len: %zu)\n", err_buf, err_len);
    assert(err_len > 0);
    assert(strcmp(err_buf, "Configuration error") == 0);

    // Query mode
    size_t qlen = hs_error_copy(HS_ERR_INVALID_ARG, NULL, 0);
    assert(qlen > 0);

    printf("[test_dynamic_min] Testing preflight validation...\n");
    hs_server_t* s_fail = NULL;
    // Invalid argument
    int32_t rc_inv = hs_server_start(NULL, 0, NULL);
    assert(rc_inv == HS_ERR_INVALID_ARG);

    // Invalid JSON
    int32_t rc_bad = hs_server_start("{invalid_json:", 14, &s_fail);
    assert(rc_bad == HS_ERR_CONFIG);
    assert(s_fail == NULL);

    // Out of range port
    const char* bad_port = "{\"port\": 99999}";
    int32_t rc_port = hs_server_start(bad_port, strlen(bad_port), &s_fail);
    assert(rc_port == HS_ERR_CONFIG);
    assert(s_fail == NULL);

    // Unsupported feature in min build (TLS cert_file)
    const char* tls_cfg = "{\"cert_file\": \"cert.pem\"}";
    int32_t rc_unsup = hs_server_start(tls_cfg, strlen(tls_cfg), &s_fail);
    assert(rc_unsup == HS_ERR_UNSUPPORTED);
    assert(s_fail == NULL);

    printf("[test_dynamic_min] Testing hs_server_start, hs_server_stop, hs_server_destroy...\n");
    hs_server_t* server = NULL;
    const char* config = "{\"port\": 0, \"root\": \".\", \"silent\": true}";
    int32_t start_rc = hs_server_start(config, strlen(config), &server);
    printf("[test_dynamic_min] hs_server_start returned: %d\n", start_rc);
    assert(start_rc == HS_OK);
    assert(server != NULL);

    int32_t stop_rc = hs_server_stop(server);
    printf("[test_dynamic_min] hs_server_stop returned: %d\n", stop_rc);
    assert(stop_rc == HS_OK);

    // Idempotent stop
    int32_t stop_rc2 = hs_server_stop(server);
    assert(stop_rc2 == HS_OK);

    hs_server_destroy(server);
    printf("[test_dynamic_min] hs_server_destroy completed successfully.\n");

    // Safe destroy with NULL
    hs_server_destroy(NULL);

    printf("[test_dynamic_min] PASS ALL ASSERTIONS!\n");
    return 0;
}
