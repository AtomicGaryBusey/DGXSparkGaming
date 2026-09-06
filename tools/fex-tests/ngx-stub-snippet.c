// Minimal fake NGX snippet: exports only the metadata getters the core dlsym's,
// so NGXValidateSnippetMetaData runs and logs the driver's own GPU arch value.
#include <stdio.h>
unsigned int NVSDK_NGX_GetAPIVersion(void){ return 0x0000013u; }
unsigned long long NVSDK_NGX_GetApplicationId(void){ return 0x24480451ull; }
const char* NVSDK_NGX_GetDriverVersion(void){ return "0.0"; }
const char* NVSDK_NGX_GetDriverVersionEx(void){ return "0.0"; }
unsigned int NVSDK_NGX_GetGPUArchitecture(void){ return 0x160u; }
unsigned int NVSDK_NGX_GetSnippetVersion(void){ return 0x00010000u; }
unsigned int NGX_SNIPPETS_GetRequiredDriverSupport(void){ return 0u; }
