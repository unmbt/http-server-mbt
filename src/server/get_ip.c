#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <ifaddrs.h>
#endif

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <moonbit.h>

void sigint_handler(int sig) {
    printf("\x1b[31mhttp-server stopped.\x1b[39m\n");
    exit(0);
}

MOONBIT_FFI_EXPORT
void ext_register_ctrl_c(void) {
    signal(SIGINT, sigint_handler);
}

MOONBIT_FFI_EXPORT
void ext_print_ips(int port) {
#ifdef _WIN32
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
#else
    struct ifaddrs *ifaddr, *ifa;
    if (getifaddrs(&ifaddr) == -1) {
        return;
    }
    
    for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL) continue;
        
        int family = ifa->ifa_addr->sa_family;
        if (family == AF_INET) {
            char ipstr[INET_ADDRSTRLEN];
            struct sockaddr_in *ipv4 = (struct sockaddr_in *)ifa->ifa_addr;
            inet_ntop(AF_INET, &(ipv4->sin_addr), ipstr, sizeof(ipstr));
            if (strcmp(ipstr, "127.0.0.1") != 0) {
                printf("  http://%s:\x1b[32m%d\x1b[39m\n", ipstr, port);
            }
        } else if (family == AF_INET6) {
            char ipstr[INET6_ADDRSTRLEN];
            struct sockaddr_in6 *ipv6 = (struct sockaddr_in6 *)ifa->ifa_addr;
            inet_ntop(AF_INET6, &(ipv6->sin6_addr), ipstr, sizeof(ipstr));
            if (strncmp(ipstr, "fe80", 4) != 0 && strcmp(ipstr, "::1") != 0) {
                printf("  http://[%s]:\x1b[32m%d\x1b[39m\n", ipstr, port);
            }
        }
    }
    
    freeifaddrs(ifaddr);
#endif
}
