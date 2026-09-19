#ifndef CLEAN_EXPORTS_H  
#define CLEAN_EXPORTS_H  
#include <stdlib.h>  
#include "moonbit.h"  
#undef MOONBIT_EXPORT  
#define MOONBIT_EXPORT  
#undef MOONBIT_FFI_EXPORT  
#define MOONBIT_FFI_EXPORT  
#endif  
