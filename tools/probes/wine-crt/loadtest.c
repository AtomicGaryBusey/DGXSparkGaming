#include <windows.h>
#include <stdio.h>
static char g_mod[MAX_PATH]="?"; static unsigned long long g_rva,g_addr,g_code;
static LONG WINAPI filt(EXCEPTION_POINTERS*ep){
  g_code=ep->ExceptionRecord->ExceptionCode; g_addr=(unsigned long long)ep->ExceptionRecord->ExceptionAddress;
  HMODULE m=NULL;
  if(GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
     (LPCSTR)(uintptr_t)g_addr,&m)&&m){GetModuleFileNameA(m,g_mod,MAX_PATH); g_rva=g_addr-(unsigned long long)m;}
  return EXCEPTION_EXECUTE_HANDLER;
}
int main(int argc,char**argv){
  if(argc<2){printf("usage: loadtest <dll>\n");return 2;}
  printf("loadtest: loading %s\n",argv[1]); fflush(stdout);
  HMODULE h=NULL; DWORD err=0;
  __try { h=LoadLibraryA(argv[1]); err=GetLastError(); }
  __except(filt(GetExceptionInformation())){
    printf("FAULT   code=0x%llx\n        address=0x%llx\n        module=%s\n        RVA=0x%llx\n",
           g_code,g_addr,g_mod,g_rva); fflush(stdout); return 3; }
  if(h){printf("OK      loaded at %p\n",(void*)h); fflush(stdout); return 0;}
  printf("FAILED  LoadLibrary returned NULL, GetLastError=%lu%s\n",err,
         err==998?"  (ERROR_NOACCESS: AV inside DllMain)":err==126?"  (ERROR_MOD_NOT_FOUND: missing dependency)":"");
  fflush(stdout); return 1;
}
