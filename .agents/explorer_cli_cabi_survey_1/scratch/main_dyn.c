#include <stdio.h>  
#include <stdint.h>  
int32_t hs_abi_version(void);  
int main(void) { int32_t v = hs_abi_version(); printf("Dyn OK: %%d\n", v); return v == 1 ? 0 : 1; }  
