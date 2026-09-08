#include <windows.h>
#include <stdio.h>
#define P(...) do{ printf(__VA_ARGS__); fflush(stdout); }while(0)

/* replacement FIRST, then a large spacer, so patching target() cannot overlap it */
__declspec(noinline) int replacement(void){ return 0xBBBB; }
__declspec(noinline) int spacer(int x){ volatile int a=x;
  for(int i=0;i<64;i++){ a+=i*3; a^=(a<<1); a-=i; } return a; }
__declspec(noinline) int target(void){ return 0xAAAA; }
__declspec(noinline) int tail_pad(int x){ volatile int a=x;
  for(int i=0;i<64;i++){ a+=i*7; a^=(a<<2); a-=i; } return a; }

int main(void){
    P("addrs: replacement=%p spacer=%p target=%p tail=%p\n",
      (void*)replacement,(void*)spacer,(void*)target,(void*)tail_pad);
    long gap_before=(long)((char*)target-(char*)replacement);
    long gap_after =(long)((char*)tail_pad-(char*)target);
    P("gaps: target-replacement=%ld  tail-target=%ld (need >12)\n",gap_before,gap_after);
    if(gap_after<16){ P("RESULT: TEST INVALID - insufficient padding after target\n"); return 3; }
    P("pre-hook  target()=0x%04X\n", target());
    unsigned char *t=(unsigned char*)target; DWORD old=0;
    if(!VirtualProtect(t,16,PAGE_EXECUTE_READWRITE,&old)){ P("RESULT: VirtualProtect FAILED\n"); return 2; }
    unsigned char patch[12]; unsigned long long dst=(unsigned long long)replacement;
    patch[0]=0x48;patch[1]=0xB8; memcpy(patch+2,&dst,8); patch[10]=0xFF;patch[11]=0xE0;
    memcpy(t,patch,12);
    FlushInstructionCache(GetCurrentProcess(),t,12);
    P("patched; calling target()...\n");
    int r=target();
    P("post-hook target()=0x%04X\n",r);
    P("RESULT: %s\n", r==0xBBBB?"HOOK WORKS - runtime code patching takes effect":
                      (r==0xAAAA?"HOOK IGNORED - stale translated code":"UNEXPECTED"));
    return r==0xBBBB?0:1;
}
