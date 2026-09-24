#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include "../../c_abi/include/http_server.h"

#include "test_http.h"

int main(void) {
    printf("[test_dynamic_full] Testing hs_abi_version...\n");
    uint32_t ver = hs_abi_version();
    printf("[test_dynamic_full] ABI version: 0x%08X\n", ver);
    assert(ver == 0x00010000);

    printf("[test_dynamic_full] Testing hs_error_copy...\n");
    char err_buf[64];
    size_t err_len = hs_error_copy(HS_ERR_UNSUPPORTED, err_buf, sizeof(err_buf));
    printf("[test_dynamic_full] Error msg: %s (len: %zu)\n", err_buf, err_len);
    assert(err_len > 0);
    assert(strcmp(err_buf, "Unsupported operation") == 0);

    printf("[test_dynamic_full] Testing TLS preflight checks...\n");
    hs_server_t* s_fail = NULL;
    // cert_file without key_file -> error config
    const char* incomplete_tls = "{\"cert_file\": \"test.crt\"}";
    int32_t rc_tls = hs_server_start(incomplete_tls, strlen(incomplete_tls), &s_fail);
    assert(rc_tls == HS_ERR_CONFIG);
    assert(s_fail == NULL);

    // Fallback + proxy conflict
    const char* conflict_cfg = "{\"spa\": true, \"proxy\": \"http://127.0.0.1:3000\"}";
    int32_t rc_conflict = hs_server_start(conflict_cfg, strlen(conflict_cfg), &s_fail);
    assert(rc_conflict == HS_ERR_CONFIG);
    assert(s_fail == NULL);

    printf("[test_dynamic_full] Testing server lifecycle...\n");
    hs_server_t* server = NULL;
    const char* config = "{\"port\": 0, \"root\": \".\", \"silent\": true}";
    int32_t start_rc = hs_server_start(config, strlen(config), &server);
    printf("[test_dynamic_full] hs_server_start returned: %d\n", start_rc);
    assert(start_rc == HS_OK);
    assert(server != NULL);

    int32_t stop_rc = hs_server_stop(server);
    printf("[test_dynamic_full] hs_server_stop returned: %d\n", stop_rc);
    assert(stop_rc == HS_OK);

    hs_server_destroy(server);
    printf("[test_dynamic_full] hs_server_destroy completed successfully.\n");

    printf("[test_dynamic_full] PASS ALL ASSERTIONS!\n");
    test_real_http();
    return 0;
}
