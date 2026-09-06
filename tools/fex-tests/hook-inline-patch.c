#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#define P(...) do{ printf(__VA_ARGS__); fflush(stdout); }while(0)
__declspec(noinline) int replacement(void){ return 0xBBBB; }
__declspec(noinline) int spacer(int x){ volatile int a=x; for(int i=0;i<64;i++){a+=i*3;a^=(a<<1);a-=i;} return a; }
__declspec(noinline) int target(void){ return 0xAAAA; }
int main(void){
    unsigned char *t=(unsigned char*)target;
    intptr_t rel=(intptr_t)replacement-((intptr_t)target+5);
    P("target=%p replacement=%p rel32=%ld\n",(void*)target,(void*)replacement,(long)rel);
    if(rel> 2147483647 || rel < -2147483648L){ P("RESULT: TEST INVALID - rel32 out of range\n"); return 3; }
    P("pre-hook  target()=0x%04X   first bytes: %02X %02X %02X\n", target(), t[0],t[1],t[2]);
    DWORD old=0;
    if(!VirtualProtect(t,8,PAGE_EXECUTE_READWRITE,&old)){ P("RESULT: VirtualProtect FAILED %lu\n",GetLastError()); return 2; }
    unsigned char patch[5]; patch[0]=0xE9; int32_t r32=(int32_t)rel; memcpy(patch+1,&r32,4);
    memcpy(t,patch,5);
    FlushInstructionCache(GetCurrentProcess(),t,5);
    P("patched (5-byte E9 rel32); first bytes now: %02X %02X %02X\n", t[0],t[1],t[2]);
    int r=target();
    P("post-hook target()=0x%04X\n",r);
    P("RESULT: %s\n", r==0xBBBB?"HOOK WORKS - runtime code patching takes effect under this translator"
        :(r==0xAAAA?"HOOK IGNORED - translator executed stale code":"UNEXPECTED"));
    return r==0xBBBB?0:1;
}
