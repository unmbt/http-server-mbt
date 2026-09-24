#ifndef HS_CONSUMER_HTTP_H
#define HS_CONSUMER_HTTP_H
/* Standalone public-ABI consumer; no private engine symbols or repository
 * runtime access. All tests exercise complete-server mode (D-11/T-027). */
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib,"ws2_32.lib")
typedef SOCKET test_socket;
#define test_close closesocket
#else
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
typedef int test_socket;
#define test_close close
#define INVALID_SOCKET (-1)
#endif

static unsigned test_available_port(void) {
    test_socket fd=socket(AF_INET,SOCK_STREAM,0);
    assert(fd!=INVALID_SOCKET);
    struct sockaddr_in address={0};address.sin_family=AF_INET;
    address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    assert(bind(fd,(struct sockaddr*)&address,sizeof(address))==0);
#ifdef _WIN32
    int size=sizeof(address);
#else
    socklen_t size=sizeof(address);
#endif
    assert(getsockname(fd,(struct sockaddr*)&address,&size)==0);
    unsigned port=ntohs(address.sin_port);test_close(fd);return port;
}
static void test_request(unsigned port,const char *request,const char *status,const char *body) {
    test_socket fd=socket(AF_INET,SOCK_STREAM,0);assert(fd!=INVALID_SOCKET);
#ifdef _WIN32
    DWORD timeout=5000;
#else
    struct timeval timeout={5,0};
#endif
    assert(setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,(const char*)&timeout,sizeof(timeout))==0);
    struct sockaddr_in address={0};address.sin_family=AF_INET;
    address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);address.sin_port=htons((unsigned short)port);
    assert(connect(fd,(struct sockaddr*)&address,sizeof(address))==0);
    size_t offset=0,length=strlen(request);
    while(offset<length){int n=(int)send(fd,request+offset,(int)(length-offset),0);assert(n>0);offset+=(size_t)n;}
    char response[8192];size_t used=0;
    for(;;){assert(used<sizeof(response)-1);int n=(int)recv(fd,response+used,(int)(sizeof(response)-used-1),0);assert(n>=0);if(!n)break;used+=(size_t)n;}
    response[used]=0;test_close(fd);
    assert(strstr(response,status)==response);
    const char *split=strstr(response,"\r\n\r\n");assert(split);
    assert(strcmp(split+4,body)==0);
}
static void test_real_http(void) {
#ifdef _WIN32
    WSADATA data;assert(WSAStartup(MAKEWORD(2,2),&data)==0);
#endif
    FILE *fixture=fopen("consumer-fixture.txt","wb");assert(fixture);
    assert(fwrite("hello consumer\n",1,15,fixture)==15);assert(fclose(fixture)==0);
    unsigned port=test_available_port();char config[256];
    snprintf(config,sizeof(config),"{\"root\":\".\",\"port\":%u,\"silent\":true}",port);
    hs_server_t *server=NULL;
    assert(hs_server_start(config,strlen(config),&server)==HS_OK);assert(server);
    test_request(port,"GET /consumer-fixture.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n","HTTP/1.1 200 ","hello consumer\n");
    test_request(port,"HEAD /consumer-fixture.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n","HTTP/1.1 200 ","");
    test_request(port,"GET /consumer-fixture.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=2-5\r\nConnection: close\r\n\r\n","HTTP/1.1 206 ","llo ");
    assert(hs_server_stop(server)==HS_OK);assert(hs_server_stop(server)==HS_OK);
    hs_server_destroy(server);assert(remove("consumer-fixture.txt")==0);
#ifdef _WIN32
    WSACleanup();
#endif
    puts("public ABI GET/HEAD/Range + stop: PASS");
}
#endif
