#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>
#include <moonbit.h>

#pragma comment(lib, "ws2_32.lib")

MOONBIT_FFI_EXPORT
void ext_print_ips(int port) {
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        return;
    }
    
    char hostname[256];
    if (gethostname(hostname, sizeof(hostname)) == SOCKET_ERROR) {
        WSACleanup();
        return;
    }
    
    struct addrinfo hints, *res, *p;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    
    if (getaddrinfo(hostname, NULL, &hints, &res) != 0) {
        WSACleanup();
        return;
    }
    
    for(p = res; p != NULL; p = p->ai_next) {
        void *addr;
        char ipstr[INET6_ADDRSTRLEN];
        if (p->ai_family == AF_INET) {
            struct sockaddr_in *ipv4 = (struct sockaddr_in *)p->ai_addr;
            addr = &(ipv4->sin_addr);
            inet_ntop(p->ai_family, addr, ipstr, sizeof ipstr);
            if (strcmp(ipstr, "127.0.0.1") != 0) {
                printf("  http://%s:\x1b[32m%d\x1b[39m\n", ipstr, port);
            }
        } else if (p->ai_family == AF_INET6) {
            struct sockaddr_in6 *ipv6 = (struct sockaddr_in6 *)p->ai_addr;
            addr = &(ipv6->sin6_addr);
            inet_ntop(p->ai_family, addr, ipstr, sizeof ipstr);
            if (strncmp(ipstr, "fe80", 4) != 0 && strcmp(ipstr, "::1") != 0) {
                printf("  http://[%s]:\x1b[32m%d\x1b[39m\n", ipstr, port);
            }
        }
    }
    
    freeaddrinfo(res);
    WSACleanup();
}

#include <signal.h>
#include <stdlib.h>

void sigint_handler(int sig) {
    printf("\x1b[31mhttp-server stopped.\x1b[39m\n");
    exit(0);
}

MOONBIT_FFI_EXPORT
void ext_register_ctrl_c(void) {
    signal(SIGINT, sigint_handler);
}
