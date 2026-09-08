/* MMX/x87 tag-word aliasing probe.
   Why: MMX instructions alias the x87 register file. On real x86 any MMX op sets
   TOP=0 and the whole tag word to 0x0000 (all valid); EMMS sets it back to 0xFFFF
   (all empty). id Tech 4's idSIMD_MMX (Memcpy/CopyArray, used heavily during map
   load) runs MMX then EMMS, and idCommonLocal::Frame then asserts tag==0xFFFF.
   If EMMS does not restore 0xFFFF under a translator, DOOM 3 dies exactly there. */
typedef unsigned short u16; typedef unsigned int u32;
static void sys_write(const char* s, unsigned long n){
#if defined(__x86_64__)
  __asm__ volatile("syscall"::"a"(1UL),"D"(1UL),"S"(s),"d"(n):"rcx","r11","memory");
#else
  __asm__ volatile("int $0x80"::"a"(4),"b"(1),"c"(s),"d"(n):"memory");
#endif
}
static void sys_exit(int c){
#if defined(__x86_64__)
  __asm__ volatile("syscall"::"a"(60UL),"D"((long)c));
#else
  __asm__ volatile("int $0x80"::"a"(1),"b"(c));
#endif
  __builtin_unreachable();
}
static void puts_(const char*s){unsigned long n=0;while(s[n])n++;sys_write(s,n);}
static void hex16(u32 v){char b[7]="0x0000";for(int i=0;i<4;i++){int d=(v>>((3-i)*4))&0xF;b[2+i]=d<10?'0'+d:'a'+d-10;}sys_write(b,6);}
static unsigned char env[128] __attribute__((aligned(16)));
static unsigned long long src[8]={1,2,3,4,5,6,7,8}, dst[8];
static u32 tw(void){__asm__ volatile("fnstenv (%0)"::"r"(env):"memory");return *(u16*)(env+8);}
static u32 top(void){return (*(u16*)(env+4)>>11)&7;}
static void show(const char*l,u32 t,u32 e){puts_(l);puts_(" tw=");hex16(t);puts_(" top=");hex16(top());
 puts_(" expect_tw=");hex16(e);puts_(t==e?"  OK":"  MISMATCH");
 puts_(" | idTech4: ");puts_(((~t)&0xFFFF)==0?"EMPTY(pass)":"NOT EMPTY(fatal)");puts_("\n");}

void _start(void){
  puts_("--- MMX / x87 tag aliasing probe ---\n");
  __asm__ volatile("fninit; emms");
  show("baseline fninit;emms  ", tw(), 0xFFFF);

  __asm__ volatile("fninit; movq (%0), %%mm0" :: "r"(src) : "memory");
  show("after MMX movq        ", tw(), 0x0000);

  __asm__ volatile("emms");
  show("after EMMS            ", tw(), 0xFFFF);

  /* the idSIMD_MMX::Memcpy shape: several movq loads/stores then emms */
  __asm__ volatile("fninit;"
    "movq   0(%0), %%mm0; movq   8(%0), %%mm1; movq  16(%0), %%mm2; movq 24(%0), %%mm3;"
    "movq %%mm0,  0(%1); movq %%mm1,  8(%1); movq %%mm2, 16(%1); movq %%mm3, 24(%1);"
    :: "r"(src), "r"(dst) : "memory");
  show("MMX memcpy, no EMMS   ", tw(), 0x0000);
  __asm__ volatile("emms");
  show("MMX memcpy, then EMMS ", tw(), 0xFFFF);

  /* x87 value live, then MMX clobbers it, then EMMS: must still end empty */
  __asm__ volatile("fninit; fld1; movq (%0), %%mm0; emms" :: "r"(src) : "memory");
  show("FLD1;MMX;EMMS         ", tw(), 0xFFFF);

  /* MMX then x87 without EMMS (the classic bug), then EMMS */
  __asm__ volatile("fninit; movq (%0), %%mm0; emms; fld1; fstp %%st(0)" :: "r"(src) : "memory");
  show("MMX;EMMS;FLD1;FSTP    ", tw(), 0xFFFF);

  /* FEMMS (3DNow) - id Tech 4 has an idSIMD_3DNow path too */
  __asm__ volatile("fninit; movq (%0), %%mm0" :: "r"(src) : "memory");
  __asm__ volatile(".byte 0x0f,0x0e");  /* femms */
  show("after FEMMS           ", tw(), 0xFFFF);

  puts_("--- done ---\n");
  sys_exit(0);
}
