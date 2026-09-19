#include <stdio.h>  
#include <stdint.h>  
int32_t hs_abi_version(void);  
int main(void) { int32_t v = hs_abi_version(); return v == 1 ? 0 : 1; }  
