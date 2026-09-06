#include <stdio.h>
#include <cuda.h>
int main(int argc,char**argv){
  CUresult r; CUdevice d; CUcontext c; CUmodule m; CUfunction f;
  cuInit(0); cuDeviceGet(&d,0); cuCtxCreate(&c,0,d);
  int mj=0,mn=0; cuDeviceGetAttribute(&mj,CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR,d);
  cuDeviceGetAttribute(&mn,CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR,d);
  printf("device cc = %d.%d\n",mj,mn);
  for(int i=1;i<argc;i++){
    r=cuModuleLoad(&m,argv[i]);
    const char*s=0; cuGetErrorName(r,&s);
    if(r==CUDA_SUCCESS){ r=cuModuleGetFunction(&f,m,"k"); const char*s2=0; cuGetErrorName(r,&s2);
      printf("%-20s LOAD=OK   getfunc=%s\n",argv[i], r==CUDA_SUCCESS?"OK":s2);
    } else printf("%-20s LOAD=FAIL (%s)\n",argv[i], s?s:"?");
  }
  return 0;
}
