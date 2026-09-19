#if defined(_WIN32) || defined(_WIN64)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <pthread.h>
#include <unistd.h>
#include <stdbool.h>
#endif
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <moonbit.h>

#define HS_BUILD_DLL
#include "../include/http_server.h"

MOONBIT_EXPORT void moonbit_runtime_init(int argc, char **argv);
MOONBIT_EXPORT void moonbit_init(void);

extern void hs_min_run_server(int64_t server_ptr);

#if defined(_WIN32) || defined(_WIN64)
static volatile LONG s_rt_init = 0;
static void ensure_runtime_init(void) {
    if (InterlockedCompareExchange(&s_rt_init, 1, 0) == 0) {
        moonbit_runtime_init(0, NULL);
        moonbit_init();
    }
}
#else
static pthread_once_t s_rt_init_once = PTHREAD_ONCE_INIT;
static void do_runtime_init(void) {
    moonbit_runtime_init(0, NULL);
    moonbit_init();
}
static void ensure_runtime_init(void) {
    pthread_once(&s_rt_init_once, do_runtime_init);
}
#endif

struct hs_server {
#if defined(_WIN32) || defined(_WIN64)
    HANDLE thread;
    HANDLE ready_event;
    HANDLE stop_event;
#else
    pthread_t thread;
    int thread_started;
    pthread_mutex_t mutex;
    pthread_cond_t ready_cond;
    int is_ready;
    int stop_requested;
#endif
    int32_t start_status;
    int is_stopped;

    // Config fields
    char root[512];
    int port;
    int spa;
    char try_files[256];
    int cors;
    int auto_index;
    int show_dir;
    int show_dotfiles;
    int cache_seconds;
    int gzip;
    int brotli;
    int silent;
};

// --- JSON Parser Helpers ---

typedef struct {
    const char* src;
    size_t len;
    size_t pos;
} json_parser_t;

static void skip_ws(json_parser_t* p) {
    while (p->pos < p->len && (p->src[p->pos] == ' ' || p->src[p->pos] == '\t' ||
                               p->src[p->pos] == '\r' || p->src[p->pos] == '\n')) {
        p->pos++;
    }
}

static char peek_char(json_parser_t* p) {
    skip_ws(p);
    if (p->pos >= p->len) return '\0';
    return p->src[p->pos];
}

static char get_char(json_parser_t* p) {
    skip_ws(p);
    if (p->pos >= p->len) return '\0';
    return p->src[p->pos++];
}

static int parse_string_token(json_parser_t* p, char* out, size_t max_out) {
    if (get_char(p) != '"') return 0;
    size_t out_idx = 0;
    while (p->pos < p->len) {
        char c = p->src[p->pos++];
        if (c == '"') {
            if (out_idx < max_out) out[out_idx] = '\0';
            else out[max_out - 1] = '\0';
            return 1;
        }
        if (c == '\\' && p->pos < p->len) {
            char esc = p->src[p->pos++];
            if (esc == '"') c = '"';
            else if (esc == '\\') c = '\\';
            else if (esc == '/') c = '/';
            else if (esc == 'b') c = '\b';
            else if (esc == 'f') c = '\f';
            else if (esc == 'n') c = '\n';
            else if (esc == 'r') c = '\r';
            else if (esc == 't') c = '\t';
            else if (esc == 'u') {
                // skip 4 hex digits
                for (int i = 0; i < 4 && p->pos < p->len; i++) p->pos++;
                c = '?';
            }
        }
        if (out_idx + 1 < max_out) {
            out[out_idx++] = c;
        }
    }
    return 0; // Unclosed string
}

static int skip_json_value(json_parser_t* p);

static int skip_json_value(json_parser_t* p) {
    char c = peek_char(p);
    if (c == '"') {
        char dummy[16];
        return parse_string_token(p, dummy, sizeof(dummy));
    }
    if (c == '{') {
        get_char(p);
        while (1) {
            char next = peek_char(p);
            if (next == '}') { get_char(p); return 1; }
            if (next == '\0') return 0;
            char key[64];
            if (!parse_string_token(p, key, sizeof(key))) return 0;
            if (get_char(p) != ':') return 0;
            if (!skip_json_value(p)) return 0;
            next = peek_char(p);
            if (next == ',') { get_char(p); continue; }
            if (next == '}') { get_char(p); return 1; }
            return 0;
        }
    }
    if (c == '[') {
        get_char(p);
        while (1) {
            char next = peek_char(p);
            if (next == ']') { get_char(p); return 1; }
            if (next == '\0') return 0;
            if (!skip_json_value(p)) return 0;
            next = peek_char(p);
            if (next == ',') { get_char(p); continue; }
            if (next == ']') { get_char(p); return 1; }
            return 0;
        }
    }
    // Number, bool, null
    if (c == 't' || c == 'f' || c == 'n' || c == '-' || isdigit((unsigned char)c)) {
        while (p->pos < p->len) {
            char ch = p->src[p->pos];
            if (ch == ',' || ch == '}' || ch == ']' || ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') break;
            p->pos++;
        }
        return 1;
    }
    return 0;
}

static int32_t parse_min_json_config(hs_server_t* s, const char* json, size_t len) {
    json_parser_t p = { json, len, 0 };
    if (peek_char(&p) != '{') {
        return HS_ERR_CONFIG;
    }
    get_char(&p);

    int port_set = 0;
    while (1) {
        char c = peek_char(&p);
        if (c == '}') {
            get_char(&p);
            break;
        }
        if (c == '\0') return HS_ERR_CONFIG;

        char key[128];
        if (!parse_string_token(&p, key, sizeof(key))) return HS_ERR_CONFIG;
        if (get_char(&p) != ':') return HS_ERR_CONFIG;

        // Check unsupported features in min build
        if (strcmp(key, "cert_file") == 0 || strcmp(key, "key_file") == 0 ||
            strcmp(key, "key_passphrase") == 0 || strcmp(key, "ca_file") == 0 ||
            strcmp(key, "proxy") == 0 || strcmp(key, "proxy_all") == 0 ||
            strcmp(key, "proxy_options") == 0 || strcmp(key, "websocket") == 0) {
            return HS_ERR_UNSUPPORTED;
        }

        if (strcmp(key, "root") == 0) {
            if (!parse_string_token(&p, s->root, sizeof(s->root))) return HS_ERR_CONFIG;
            if (s->root[0] == '\0') return HS_ERR_CONFIG;
        } else if (strcmp(key, "port") == 0) {
            skip_ws(&p);
            char num_buf[32];
            size_t nidx = 0;
            while (p.pos < p.len && (isdigit((unsigned char)p.src[p.pos]) || p.src[p.pos] == '-')) {
                if (nidx + 1 < sizeof(num_buf)) num_buf[nidx++] = p.src[p.pos];
                p.pos++;
            }
            num_buf[nidx] = '\0';
            if (nidx == 0) return HS_ERR_CONFIG;
            long val = strtol(num_buf, NULL, 10);
            if (val < 0 || val > 65535) return HS_ERR_CONFIG;
            s->port = (int)val;
            port_set = 1;
        } else if (strcmp(key, "spa") == 0) {
            skip_ws(&p);
            if (p.pos + 4 <= p.len && strncmp(p.src + p.pos, "true", 4) == 0) {
                s->spa = 1;
                p.pos += 4;
            } else if (p.pos + 5 <= p.len && strncmp(p.src + p.pos, "false", 5) == 0) {
                s->spa = 0;
                p.pos += 5;
            } else {
                return HS_ERR_CONFIG;
            }
        } else if (strcmp(key, "try_files") == 0) {
            if (!parse_string_token(&p, s->try_files, sizeof(s->try_files))) return HS_ERR_CONFIG;
        } else if (strcmp(key, "cors") == 0) {
            skip_ws(&p);
            if (p.pos + 4 <= p.len && strncmp(p.src + p.pos, "true", 4) == 0) {
                s->cors = 1;
                p.pos += 4;
            } else if (p.pos + 5 <= p.len && strncmp(p.src + p.pos, "false", 5) == 0) {
                s->cors = 0;
                p.pos += 5;
            } else {
                return HS_ERR_CONFIG;
            }
        } else if (strcmp(key, "silent") == 0) {
            skip_ws(&p);
            if (p.pos + 4 <= p.len && strncmp(p.src + p.pos, "true", 4) == 0) {
                s->silent = 1;
                p.pos += 4;
            } else if (p.pos + 5 <= p.len && strncmp(p.src + p.pos, "false", 5) == 0) {
                s->silent = 0;
                p.pos += 5;
            } else {
                return HS_ERR_CONFIG;
            }
        } else if (strcmp(key, "auto_index") == 0) {
            skip_ws(&p);
            if (p.pos + 4 <= p.len && strncmp(p.src + p.pos, "true", 4) == 0) {
                s->auto_index = 1;
                p.pos += 4;
            } else if (p.pos + 5 <= p.len && strncmp(p.src + p.pos, "false", 5) == 0) {
                s->auto_index = 0;
                p.pos += 5;
            } else {
                return HS_ERR_CONFIG;
            }
        } else if (strcmp(key, "show_dir") == 0) {
            skip_ws(&p);
            if (p.pos + 4 <= p.len && strncmp(p.src + p.pos, "true", 4) == 0) {
                s->show_dir = 1;
                p.pos += 4;
            } else if (p.pos + 5 <= p.len && strncmp(p.src + p.pos, "false", 5) == 0) {
                s->show_dir = 0;
                p.pos += 5;
            } else {
                return HS_ERR_CONFIG;
            }
        } else if (strcmp(key, "cache_seconds") == 0) {
            skip_ws(&p);
            char num_buf[32];
            size_t nidx = 0;
            while (p.pos < p.len && (isdigit((unsigned char)p.src[p.pos]) || p.src[p.pos] == '-')) {
                if (nidx + 1 < sizeof(num_buf)) num_buf[nidx++] = p.src[p.pos];
                p.pos++;
            }
            num_buf[nidx] = '\0';
            if (nidx == 0) return HS_ERR_CONFIG;
            long val = strtol(num_buf, NULL, 10);
            if (val < -1) return HS_ERR_CONFIG;
            s->cache_seconds = (int)val;
        } else {
            // Unknown or other option, skip value
            if (!skip_json_value(&p)) return HS_ERR_CONFIG;
        }

        c = peek_char(&p);
        if (c == ',') {
            get_char(&p);
            continue;
        }
        if (c == '}') {
            get_char(&p);
            break;
        }
        return HS_ERR_CONFIG;
    }

    skip_ws(&p);
    if (p.pos < p.len) {
        return HS_ERR_CONFIG; // Trailing junk
    }

    // Mutual exclusion: spa and try_files
    if (s->spa && s->try_files[0] != '\0') {
        return HS_ERR_CONFIG;
    }

    (void)port_set;
    return HS_OK;
}

// --- Bridge FFI for MoonBit ---

MOONBIT_FFI_EXPORT int32_t hs_bridge_get_port(int64_t server_ptr) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    return s ? s->port : 8080;
}

MOONBIT_FFI_EXPORT int32_t hs_bridge_get_spa(int64_t server_ptr) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    return s ? s->spa : 0;
}

MOONBIT_FFI_EXPORT int32_t hs_bridge_get_cors(int64_t server_ptr) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    return s ? s->cors : 0;
}

MOONBIT_FFI_EXPORT int32_t hs_bridge_get_silent(int64_t server_ptr) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    return s ? s->silent : 1;
}

MOONBIT_FFI_EXPORT int32_t hs_bridge_get_auto_index(int64_t server_ptr) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    return s ? s->auto_index : 1;
}

MOONBIT_FFI_EXPORT int32_t hs_bridge_get_show_dir(int64_t server_ptr) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    return s ? s->show_dir : 1;
}

MOONBIT_FFI_EXPORT int32_t hs_bridge_get_cache_seconds(int64_t server_ptr) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    return s ? s->cache_seconds : 3600;
}

static moonbit_string_t utf8_to_moonbit_str(const char* s) {
    if (s == NULL || s[0] == '\0') {
        return moonbit_make_string(0, 0);
    }
#if defined(_WIN32) || defined(_WIN64)
    int wlen = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    if (wlen <= 1) {
        return moonbit_make_string(0, 0);
    }
    moonbit_string_t ms = moonbit_make_string_raw(wlen - 1);
    MultiByteToWideChar(CP_UTF8, 0, s, -1, (wchar_t*)ms, wlen);
    return ms;
#else
    size_t slen = strlen(s);
    uint16_t* tmp = (uint16_t*)malloc((slen + 1) * 2 * sizeof(uint16_t));
    if (tmp == NULL) {
        return moonbit_make_string(0, 0);
    }
    size_t out_len = 0;
    size_t i = 0;
    while (i < slen) {
        uint32_t cp = 0;
        unsigned char c = (unsigned char)s[i];
        if (c < 0x80) {
            cp = c;
            i += 1;
        } else if ((c & 0xE0) == 0xC0) {
            if (i + 1 >= slen) break;
            cp = (c & 0x1F) << 6;
            cp |= (unsigned char)s[i + 1] & 0x3F;
            i += 2;
        } else if ((c & 0xF0) == 0xE0) {
            if (i + 2 >= slen) break;
            cp = (c & 0x0F) << 12;
            cp |= ((unsigned char)s[i + 1] & 0x3F) << 6;
            cp |= (unsigned char)s[i + 2] & 0x3F;
            i += 3;
        } else if ((c & 0xF8) == 0xF0) {
            if (i + 3 >= slen) break;
            cp = (c & 0x07) << 18;
            cp |= ((unsigned char)s[i + 1] & 0x3F) << 12;
            cp |= ((unsigned char)s[i + 2] & 0x3F) << 6;
            cp |= (unsigned char)s[i + 3] & 0x3F;
            i += 4;
        } else {
            i += 1;
            continue;
        }

        if (cp <= 0xFFFF) {
            tmp[out_len++] = (uint16_t)cp;
        } else if (cp <= 0x10FFFF) {
            cp -= 0x10000;
            tmp[out_len++] = (uint16_t)(0xD800 + (cp >> 10));
            tmp[out_len++] = (uint16_t)(0xDC00 + (cp & 0x3FF));
        }
    }
    moonbit_string_t ms = moonbit_make_string_raw((int32_t)out_len);
    memcpy(ms, tmp, out_len * sizeof(uint16_t));
    free(tmp);
    return ms;
#endif
}

MOONBIT_FFI_EXPORT moonbit_string_t hs_bridge_get_root(int64_t server_ptr) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    return utf8_to_moonbit_str(s && s->root[0] ? s->root : ".");
}

MOONBIT_FFI_EXPORT moonbit_string_t hs_bridge_get_try_files(int64_t server_ptr) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    return utf8_to_moonbit_str(s ? s->try_files : "");
}

MOONBIT_FFI_EXPORT void hs_bridge_notify_ready(int64_t server_ptr, int32_t status) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    if (s != NULL) {
        s->start_status = status;
#if defined(_WIN32) || defined(_WIN64)
        SetEvent(s->ready_event);
#else
        pthread_mutex_lock(&s->mutex);
        s->is_ready = 1;
        pthread_cond_broadcast(&s->ready_cond);
        pthread_mutex_unlock(&s->mutex);
#endif
    }
}

MOONBIT_FFI_EXPORT int32_t hs_bridge_is_stopped(int64_t server_ptr) {
    hs_server_t* s = (hs_server_t*)(uintptr_t)server_ptr;
    if (s == NULL || s->is_stopped) return 1;
#if defined(_WIN32) || defined(_WIN64)
    DWORD res = WaitForSingleObject(s->stop_event, 0);
    return (res == WAIT_OBJECT_0) ? 1 : 0;
#else
    int stopped = 0;
    pthread_mutex_lock(&s->mutex);
    stopped = s->stop_requested;
    pthread_mutex_unlock(&s->mutex);
    return stopped;
#endif
}

// --- Thread Procedure ---

#if defined(_WIN32) || defined(_WIN64)
static DWORD WINAPI server_thread_proc(LPVOID param) {
    hs_server_t* s = (hs_server_t*)param;
    ensure_runtime_init();
    hs_min_run_server((int64_t)(uintptr_t)s);
    return 0;
}
#else
static void* server_thread_proc(void* param) {
    hs_server_t* s = (hs_server_t*)param;
    ensure_runtime_init();
    hs_min_run_server((int64_t)(uintptr_t)s);
    return NULL;
}
#endif

// --- Public C ABI Exports ---

HS_EXPORT size_t hs_error_copy(int32_t code, char* buf, size_t cap) {
    const char* msg = "Unknown error";
    switch (code) {
        case HS_OK: msg = "Success"; break;
        case HS_ERR_CONFIG: msg = "Configuration error"; break;
        case HS_ERR_INVALID_ARG: msg = "Invalid argument"; break;
        case HS_ERR_IO: msg = "I/O error"; break;
        case HS_ERR_CLOSED: msg = "Server closed"; break;
        case HS_ERR_UNSUPPORTED: msg = "Unsupported operation"; break;
        default: msg = "Unknown error"; break;
    }
    size_t len = strlen(msg);
    if (buf != NULL && cap > 0) {
        size_t to_copy = (len < cap - 1) ? len : (cap - 1);
        memcpy(buf, msg, to_copy);
        buf[to_copy] = '\0';
    }
    return len;
}

HS_EXPORT int32_t hs_server_start(const char* json_config, size_t config_len, hs_server_t** out_server) {
    if (out_server == NULL) {
        return HS_ERR_INVALID_ARG;
    }
    *out_server = NULL;

    hs_server_t* s = (hs_server_t*)calloc(1, sizeof(hs_server_t));
    if (s == NULL) return HS_ERR_IO;

    strcpy(s->root, ".");
    s->port = 8080;
    s->silent = 1;
    s->auto_index = 1;
    s->show_dir = 1;
    s->cache_seconds = 3600;

    if (json_config != NULL && config_len > 0) {
        int32_t err = parse_min_json_config(s, json_config, config_len);
        if (err != HS_OK) {
            free(s);
            return err;
        }
    }

#if defined(_WIN32) || defined(_WIN64)
    s->ready_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    s->stop_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    s->start_status = HS_OK;
    s->is_stopped = 0;

    s->thread = CreateThread(NULL, 0, server_thread_proc, s, 0, NULL);
    if (s->thread == NULL) {
        CloseHandle(s->ready_event);
        CloseHandle(s->stop_event);
        free(s);
        return HS_ERR_IO;
    }

    WaitForSingleObject(s->ready_event, INFINITE);

    if (s->start_status != HS_OK) {
        int32_t err = s->start_status;
        SetEvent(s->stop_event);
        WaitForSingleObject(s->thread, INFINITE);
        CloseHandle(s->thread);
        CloseHandle(s->ready_event);
        CloseHandle(s->stop_event);
        free(s);
        return err;
    }
#else
    pthread_mutex_init(&s->mutex, NULL);
    pthread_cond_init(&s->ready_cond, NULL);
    s->start_status = HS_OK;
    s->is_stopped = 0;
    s->is_ready = 0;
    s->stop_requested = 0;

    if (pthread_create(&s->thread, NULL, server_thread_proc, s) != 0) {
        pthread_mutex_destroy(&s->mutex);
        pthread_cond_destroy(&s->ready_cond);
        free(s);
        return HS_ERR_IO;
    }
    s->thread_started = 1;

    pthread_mutex_lock(&s->mutex);
    while (!s->is_ready) {
        pthread_cond_wait(&s->ready_cond, &s->mutex);
    }
    pthread_mutex_unlock(&s->mutex);

    if (s->start_status != HS_OK) {
        int32_t err = s->start_status;
        pthread_mutex_lock(&s->mutex);
        s->stop_requested = 1;
        pthread_mutex_unlock(&s->mutex);
        pthread_join(s->thread, NULL);
        pthread_mutex_destroy(&s->mutex);
        pthread_cond_destroy(&s->ready_cond);
        free(s);
        return err;
    }
#endif

    *out_server = s;
    return HS_OK;
}

HS_EXPORT int32_t hs_server_stop(hs_server_t* server) {
    if (server == NULL) {
        return HS_ERR_INVALID_ARG;
    }
    if (server->is_stopped) {
        return HS_OK;
    }
    server->is_stopped = 1;
#if defined(_WIN32) || defined(_WIN64)
    SetEvent(server->stop_event);
    if (server->thread != NULL) {
        WaitForSingleObject(server->thread, INFINITE);
    }
#else
    pthread_mutex_lock(&server->mutex);
    server->stop_requested = 1;
    pthread_mutex_unlock(&server->mutex);
    if (server->thread_started) {
        pthread_join(server->thread, NULL);
        server->thread_started = 0;
    }
#endif
    return HS_OK;
}

HS_EXPORT void hs_server_destroy(hs_server_t* server) {
    if (server == NULL) {
        return;
    }
    if (!server->is_stopped) {
        hs_server_stop(server);
    }
#if defined(_WIN32) || defined(_WIN64)
    if (server->thread != NULL) {
        CloseHandle(server->thread);
        server->thread = NULL;
    }
    if (server->ready_event != NULL) {
        CloseHandle(server->ready_event);
        server->ready_event = NULL;
    }
    if (server->stop_event != NULL) {
        CloseHandle(server->stop_event);
        server->stop_event = NULL;
    }
#else
    pthread_mutex_destroy(&server->mutex);
    pthread_cond_destroy(&server->ready_cond);
#endif
    free(server);
}
