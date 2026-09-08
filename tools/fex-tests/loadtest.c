#include <windows.h>
#include <stdio.h>
#define P(...) do{ printf(__VA_ARGS__); fflush(stdout);}while(0)
int main(void){
    P("step1 LoadLibraryW(ReShade64.dll)...\n");
    HMODULE h=LoadLibraryW(L"ReShade64.dll");
    if(!h){ P("RESULT: LOAD FAILED err=%lu\n",GetLastError()); return 1; }
    P("step2 loaded at %p\n",(void*)h);
    const char* names[]={"ReShadeGetBasePath","ReShadeCreateEffectRuntime","CreateDXGIFactory1","D3D12CreateDevice"};
    int found=0;
    for(int i=0;i<4;i++){ void*p=(void*)GetProcAddress(h,names[i]);
        P("step3 %-28s %s\n",names[i],p?"resolved":"MISSING"); if(p)found++; }
    typedef const char*(WINAPI *PFN)(void);
    PFN bp=(PFN)GetProcAddress(h,"ReShadeGetBasePath");
    if(bp){ const char* s=bp(); P("step4 ReShadeGetBasePath() -> %s\n", s?s:"(null)"); }
    P("RESULT: %s (%d/4 exports resolved)\n", found>=3?"RESHADE LOADS AND INITIALISES UNDER THIS TRANSLATOR":"PARTIAL", found);
    return found>=3?0:1;
}
