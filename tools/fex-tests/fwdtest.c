#include <windows.h>
#include <stdio.h>
#define P(...) do{ printf(__VA_ARGS__); fflush(stdout);}while(0)
int main(void){
    P("step1 LoadLibraryW(nvngx.dll_nrfwd.dll)...\n");
    HMODULE h=LoadLibraryW(L"nvngx.dll_nrfwd.dll");
    if(!h){ P("RESULT: LOAD FAILED err=%lu\n",GetLastError()); return 1; }
    P("step2 loaded at %p\n",(void*)h);
    const char* n[]={"nrfwd_init","nrfwd_create","nrfwd_evaluate","nrfwd_release"};
    void* f[4]; int ok=0;
    for(int i=0;i<4;i++){ f[i]=(void*)GetProcAddress(h,n[i]);
        P("step3 %-16s %s\n", n[i], f[i]?"resolved":"MISSING"); if(f[i]) ok++; }
    /* guarded no-op paths: prove the forwarder's code actually executes under translation */
    typedef int (*PFN_Eval)(void*,void*,void*);
    typedef void (*PFN_Rel)(void*);
    if(f[2]){ int r=((PFN_Eval)f[2])(NULL,NULL,NULL);
              P("step4 nrfwd_evaluate(NULL,NULL,NULL) -> %d (expect 0)\n", r); }
    if(f[3]){ ((PFN_Rel)f[3])(NULL); P("step5 nrfwd_release(NULL) returned cleanly\n"); }
    P("RESULT: %s (%d/4 exports)\n", ok==4?"FORWARDER LOADS AND EXECUTES UNDER THIS TRANSLATOR":"PARTIAL", ok);
    return ok==4?0:1;
}
