#include <windows.h>
#include <stdio.h>
#define P(...) do{ printf(__VA_ARGS__); fflush(stdout); }while(0)
__declspec(noinline) int target(void){ return 0xAAAA; }
__declspec(noinline) int replacement(void){ return 0xBBBB; }
int main(void){
    P("step1 pre-hook target()=0x%04X\n", target());
    unsigned char *t=(unsigned char*)target;
    P("step2 target@%p replacement@%p\n",(void*)target,(void*)replacement);
    P("step3 first bytes: %02X %02X %02X %02X\n",t[0],t[1],t[2],t[3]);
    DWORD old=0;
    BOOL ok=VirtualProtect(t,16,PAGE_EXECUTE_READWRITE,&old);
    P("step4 VirtualProtect=%d old=0x%lX err=%lu\n",ok,old,ok?0UL:GetLastError());
    if(!ok) return 2;
    unsigned char patch[12]; unsigned long long dst=(unsigned long long)replacement;
    patch[0]=0x48;patch[1]=0xB8; memcpy(patch+2,&dst,8); patch[10]=0xFF;patch[11]=0xE0;
    memcpy(t,patch,12);
    P("step5 patched, now: %02X %02X %02X %02X\n",t[0],t[1],t[2],t[3]);
    FlushInstructionCache(GetCurrentProcess(),t,12);
    P("step6 flushed, calling target()...\n");
    int r=target();
    P("step7 post-hook target()=0x%04X\n",r);
    P("RESULT: %s\n", r==0xBBBB?"HOOK WORKS":(r==0xAAAA?"HOOK IGNORED (stale translation)":"UNEXPECTED"));
    return r==0xBBBB?0:1;
}
