/*
 * Keep the platform file-transfer ABI in the root static package so thin and
 * full servers share one implementation without importing each other's
 * feature packages. Each included source selects its implementation through
 * the platform guards it already owns.
 */
#include "server/transmit_file_windows.c"
#include "server/transmit_file_linux.c"
#include "server/transmit_file_darwin.c"
