// Local IPv4 interface address enumeration for the CLI startup banner.
// Windows resolves the local hostname via getaddrinfo; POSIX walks getifaddrs.
// Returns UTF-8 text with one address per line (no trailing newline), or
// empty bytes when enumeration finds nothing. Loopback/unspecified filtering
// and display stay in MoonBit, so the raw list is returned unfiltered.

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>

#pragma comment(lib, "ws2_32.lib")
#else
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <sys/socket.h>
#include <sys/types.h>
#endif

#include <stdlib.h>
#include <string.h>
#include <moonbit.h>

typedef struct {
    char* buf;
    size_t len;
    size_t cap;
} IpBuf;

// Appends one address; '\n'-separates from the previous entry.
static int ipbuf_append(IpBuf* b, const char* addr) {
    size_t n = strlen(addr);
    size_t needed = b->len + (b->len > 0 ? 1 : 0) + n;
    if (needed + 1 > b->cap) {
        size_t cap = b->cap ? b->cap : 256;
        while (cap < needed + 1) {
            cap *= 2;
        }
        char* next = (char*)realloc(b->buf, cap);
        if (next == NULL) {
            return 0;
        }
        b->buf = next;
        b->cap = cap;
    }
    if (b->len > 0) {
        b->buf[b->len] = '\n';
        b->len += 1;
    }
    memcpy(b->buf + b->len, addr, n);
    b->len += n;
    return 1;
}

// Copies the collected text into a GC-owned MoonBit Bytes.
static moonbit_bytes_t ipbuf_finish(IpBuf* b) {
    moonbit_bytes_t out = moonbit_make_bytes((int32_t)b->len, 0);
    if (b->len > 0) {
        memcpy(out, b->buf, b->len);
    }
    free(b->buf);
    b->buf = NULL;
    return out;
}

#ifdef _WIN32
MOONBIT_FFI_EXPORT moonbit_bytes_t http_server_cli_local_ips(void) {
    IpBuf b = {NULL, 0, 0};
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        return moonbit_make_bytes(0, 0);
    }
    char hostname[256];
    struct addrinfo hints;
    struct addrinfo* res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (gethostname(hostname, sizeof(hostname)) == 0 &&
        getaddrinfo(hostname, NULL, &hints, &res) == 0 && res != NULL) {
        struct addrinfo* p;
        for (p = res; p != NULL; p = p->ai_next) {
            if (p->ai_family != AF_INET || p->ai_addr == NULL) {
                continue;
            }
            char ipstr[INET_ADDRSTRLEN];
            const struct sockaddr_in* v4 = (const struct sockaddr_in*)p->ai_addr;
            if (inet_ntop(AF_INET, &v4->sin_addr, ipstr, sizeof(ipstr)) != NULL) {
                if (!ipbuf_append(&b, ipstr)) {
                    break;
                }
            }
        }
        freeaddrinfo(res);
    }
    WSACleanup();
    return ipbuf_finish(&b);
}
#else
MOONBIT_FFI_EXPORT moonbit_bytes_t http_server_cli_local_ips(void) {
    IpBuf b = {NULL, 0, 0};
    struct ifaddrs* ifaddr = NULL;
    if (getifaddrs(&ifaddr) == 0 && ifaddr != NULL) {
        struct ifaddrs* ifa;
        for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr == NULL || ifa->ifa_addr->sa_family != AF_INET) {
                continue;
            }
            char ipstr[INET_ADDRSTRLEN];
            const struct sockaddr_in* v4 = (const struct sockaddr_in*)ifa->ifa_addr;
            if (inet_ntop(AF_INET, &v4->sin_addr, ipstr, sizeof(ipstr)) != NULL) {
                if (!ipbuf_append(&b, ipstr)) {
                    break;
                }
            }
        }
        freeifaddrs(ifaddr);
    }
    return ipbuf_finish(&b);
}
#endif
