#define HS_STATIC
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include "../../c_abi/include/http_server.h"

int main(void) {
    printf("[test_static_min] Testing hs_abi_version...\n");
    uint32_t ver = hs_abi_version();
    printf("[test_static_min] ABI version: 0x%08X\n", ver);
    assert(ver == 0x00010000);

    printf("[test_static_min] Testing hs_error_copy...\n");
    char err_buf[64];
    size_t err_len = hs_error_copy(HS_ERR_IO, err_buf, sizeof(err_buf));
    printf("[test_static_min] Error msg: %s (len: %zu)\n", err_buf, err_len);
    assert(err_len > 0);
    assert(strcmp(err_buf, "I/O error") == 0);

    printf("[test_static_min] Testing server lifecycle...\n");
    hs_server_t* server = NULL;
    const char* config = "{\"port\": 0, \"root\": \".\", \"silent\": true}";
    int32_t start_rc = hs_server_start(config, strlen(config), &server);
    printf("[test_static_min] hs_server_start returned: %d\n", start_rc);
    assert(start_rc == HS_OK);
    assert(server != NULL);

    int32_t stop_rc = hs_server_stop(server);
    printf("[test_static_min] hs_server_stop returned: %d\n", stop_rc);
    assert(stop_rc == HS_OK);

    hs_server_destroy(server);
    printf("[test_static_min] hs_server_destroy completed successfully.\n");

    printf("[test_static_min] PASS ALL ASSERTIONS!\n");
    return 0;
}
