/* cpuidprobe.c - dump the CPUID answers FEX actually gives a guest.
   Build & run INSIDE the FEX RootFS: FEXBash -c 'gcc -O0 -o cpuidprobe cpuidprobe.c && ./cpuidprobe' */
#include <stdio.h>
#include <string.h>
static void cpuid(unsigned leaf, unsigned sub, unsigned r[4]){
  unsigned a,b,c,d;
  __asm__ volatile("cpuid":"=a"(a),"=b"(b),"=c"(c),"=d"(d):"a"(leaf),"c"(sub));
  r[0]=a; r[1]=b; r[2]=c; r[3]=d;
}
static void bit(const char*n, unsigned v, int b){ printf("  %-28s bit %2d = %d\n", n, b, (v>>b)&1); }
int main(void){
  unsigned r[4]; char v[13]={0};
  cpuid(0,0,r); memcpy(v,&r[1],4); memcpy(v+4,&r[3],4); memcpy(v+8,&r[2],4);
  printf("leaf 0: max=0x%x vendor=%s\n", r[0], v);
  unsigned maxstd=r[0];
  cpuid(1,0,r);
  printf("leaf 1: eax=%08x (fam=%u model=%u step=%u) ebx=%08x ecx=%08x edx=%08x\n",
     r[0], ((r[0]>>8)&0xf)+((r[0]>>20)&0xff), (((r[0]>>16)&0xf)<<4)|((r[0]>>4)&0xf), r[0]&0xf, r[1], r[2], r[3]);
  printf(" leaf1.EDX:\n");
  bit("FPU",r[3],0); bit("VME",r[3],1); bit("DE  (debug ext)",r[3],2);
  bit("PSE (page size ext)",r[3],3); bit("TSC",r[3],4); bit("CX8",r[3],5);
  bit("CMOV",r[3],15); bit("CLFSH",r[3],19); bit("MMX",r[3],23);
  bit("FXSR",r[3],24); bit("SSE",r[3],25); bit("SSE2",r[3],26); bit("HTT",r[3],28);
  printf(" leaf1.ECX:\n");
  bit("SSE3",r[2],0); bit("SSSE3",r[2],9); bit("SSE4.1",r[2],19); bit("SSE4.2",r[2],20);
  bit("XSAVE",r[2],26); bit("OSXSAVE",r[2],27); bit("AVX",r[2],28); bit("HYPERVISOR",r[2],31);
  if(maxstd>=7){ cpuid(7,0,r); printf("leaf 7.0: ebx=%08x ecx=%08x edx=%08x\n",r[1],r[2],r[3]);
    bit("AVX2",r[1],5); bit("HYBRID(edx)",r[3],15); }
  cpuid(0x80000000,0,r); unsigned maxext=r[0];
  printf("leaf 8000_0000: max=0x%x\n", maxext);
  if(maxext>=0x80000001){ cpuid(0x80000001,0,r);
    printf("leaf 8000_0001: ecx=%08x edx=%08x\n", r[2], r[3]);
    bit("MMX",r[3],23); bit("FXSR",r[3],24); bit("FXSR_OPT",r[3],25);
    bit("1GB pages",r[3],26); bit("RDTSCP",r[3],27); bit("LM",r[3],29);
    bit("3DNowExt",r[3],30); bit("3DNow",r[3],31); }
  char b[49]={0};
  if(maxext>=0x80000004){ for(int i=0;i<3;i++){ cpuid(0x80000002+i,0,r); memcpy(b+i*16,r,16);} printf("brand: '%s'\n", b); }
  return 0;
}
