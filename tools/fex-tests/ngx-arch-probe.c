// Ask the host ARM64 NGX core what GPU architecture it reports for GB10.
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <wchar.h>
#include <cuda.h>

typedef int (*PFN_CudaInit)(unsigned long long, const wchar_t*, unsigned int);
typedef int (*PFN_GetCaps)(void**);

int main(void){
  CUdevice d; CUcontext c;
  if (cuInit(0)!=CUDA_SUCCESS){puts("cuInit fail");return 1;}
  cuDeviceGet(&d,0); cuCtxCreate(&c,NULL,0,d);
  void*h=dlopen(getenv("NGXLIB")?getenv("NGXLIB"):"libnvidia-ngx.so.1",RTLD_NOW);
  if(!h){printf("dlopen: %s\n",dlerror());return 1;}
  PFN_CudaInit init=(PFN_CudaInit)dlsym(h,"NVSDK_NGX_CUDA_Init");
  PFN_GetCaps caps=(PFN_GetCaps)dlsym(h,"NVSDK_NGX_CUDA_GetCapabilityParameters");
  printf("init=%p caps=%p\n",(void*)init,(void*)caps);
  if(!init) return 1;
  int r = init(0x24480451ull, L"/tmp/ngxdata", 0x0000015u);
  printf("NVSDK_NGX_CUDA_Init => 0x%08X\n", (unsigned)r);
  void* p=NULL;
  if(caps){ int r2=caps(&p); printf("GetCapabilityParameters => 0x%08X params=%p\n",(unsigned)r2,p); }
  return 0;
}
