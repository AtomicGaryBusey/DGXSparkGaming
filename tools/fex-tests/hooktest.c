/* Self-contained inline-hook test. No third-party code.
   Q: does patching a function prologue at runtime take effect under FEX's JIT,
      or does FEX keep executing stale translated code?
   This is exactly what ReShade/Detours/MinHook do. */
#include <windows.h>
#include <stdio.h>

__declspec(noinline) int target(void){ return 0xAAAA; }
__declspec(noinline) int replacement(void){ return 0xBBBB; }

int main(void){
    printf("pre-hook  target() = 0x%04X\n", target());

    unsigned char *t = (unsigned char*)target;
    unsigned char patch[12];
    /* mov rax, imm64 ; jmp rax */
    patch[0]=0x48; patch[1]=0xB8;
    unsigned long long dst=(unsigned long long)replacement;
    memcpy(patch+2,&dst,8);
    patch[10]=0xFF; patch[11]=0xE0;

    DWORD old;
    if(!VirtualProtect(t,sizeof patch,PAGE_EXECUTE_READWRITE,&old)){
        printf("RESULT: VirtualProtect FAILED (%lu)\n",GetLastError()); return 2; }
    memcpy(t,patch,sizeof patch);
    FlushInstructionCache(GetCurrentProcess(),t,sizeof patch);
    VirtualProtect(t,sizeof patch,old,&old);

    int r = target();
    printf("post-hook target() = 0x%04X\n", r);
    if(r==0xBBBB){ printf("RESULT: HOOK WORKS - runtime code patching takes effect\n"); return 0; }
    if(r==0xAAAA){ printf("RESULT: HOOK IGNORED - stale translated code (FEX JIT cache not invalidated)\n"); return 1; }
    printf("RESULT: UNEXPECTED 0x%04X\n",r); return 3;
}
