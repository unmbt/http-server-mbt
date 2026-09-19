// stdout TTY detection for the CLI startup banner colors.
// Mirrors the original http-server's chalk behavior: colors are only emitted
// when stdout is attached to a terminal (the MoonBit side additionally honors
// NO_COLOR / TERM=dumb / FORCE_COLOR). On Windows the console is switched to
// virtual terminal processing so the ANSI escapes render on legacy conhost.

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fcntl.h>
#include <io.h>

#ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
#define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
#endif
#else
#include <unistd.h>
#endif

#include <stdio.h>
#include <stdint.h>
#include <moonbit.h>

// Returns 1 when stdout is a terminal, 0 otherwise. As a side effect on
// Windows, enables ENABLE_VIRTUAL_TERMINAL_PROCESSING on the console so the
// banner's ANSI colors render; failures are ignored (colors simply degrade).
MOONBIT_FFI_EXPORT int32_t http_server_cli_is_stdout_tty(void) {
#ifdef _WIN32
    int fd = _fileno(stdout);
    if (fd < 0 || _isatty(fd) == 0) {
        return 0;
    }
    HANDLE handle = (HANDLE)_get_osfhandle(fd);
    DWORD mode = 0;
    if (handle != INVALID_HANDLE_VALUE && GetConsoleMode(handle, &mode)) {
        SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }
    return 1;
#else
    return isatty(1) == 1 ? 1 : 0;
#endif
}

// Flushes C stdout so banner and stop messages appear immediately when
// stdout is a pipe or file: the C runtime switches those to full buffering,
// while a long-running server would otherwise hide them until exit.
MOONBIT_FFI_EXPORT int32_t http_server_cli_flush_stdout(void) {
    return (int32_t)fflush(stdout);
}
