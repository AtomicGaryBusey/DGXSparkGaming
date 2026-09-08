/* Freestanding x86 (32/64) probe of x87 tag-word / FNSTENV fidelity.
   Why: id Tech 4 (DOOM 3, DOOM 3 BFG, Prey 2006) calls Sys_FPU_StackIsEmpty()
   every frame, which is: fnstenv [buf]; eax = [buf+8]; eax ^= 0xFFFFFFFF;
   eax &= 0xFFFF; empty <=> eax == 0.  i.e. it demands tag word == 0xFFFF.
   This probe prints the tag word after known sequences so FEX and Box64 can be
   compared against the architectural answer instead of guessed at. */

typedef unsigned int u32;
typedef unsigned short u16;

static void sys_write(const char* s, unsigned long n) {
#if defined(__x86_64__)
    __asm__ volatile("syscall" :: "a"(1UL), "D"(1UL), "S"(s), "d"(n) : "rcx", "r11", "memory");
#else
    __asm__ volatile("int $0x80" :: "a"(4), "b"(1), "c"(s), "d"(n) : "memory");
#endif
}
static void sys_exit(int c) {
#if defined(__x86_64__)
    __asm__ volatile("syscall" :: "a"(60UL), "D"((long)c));
#else
    __asm__ volatile("int $0x80" :: "a"(1), "b"(c));
#endif
    __builtin_unreachable();
}
static void puts_(const char* s){ unsigned long n=0; while(s[n]) n++; sys_write(s,n); }
static void hex16(u32 v){ char b[7]="0x0000"; for(int i=0;i<4;i++){int d=(v>>((3-i)*4))&0xF; b[2+i]=d<10?'0'+d:'a'+d-10;} sys_write(b,6); }

static unsigned char env[128] __attribute__((aligned(16)));
static unsigned char fx[512] __attribute__((aligned(16)));
static unsigned char sav[128] __attribute__((aligned(16)));

#define ENV() __asm__ volatile("fnstenv (%0)" :: "r"(env) : "memory")
static u32 tw(void){ ENV(); return *(u16*)(env+8); }
static u32 cw(void){ return *(u16*)(env+0); }
static u32 sw(void){ return *(u16*)(env+4); }

static void show(const char* label, u32 t, u32 expect){
    puts_(label); puts_(" tw="); hex16(t);
    puts_(" expect="); hex16(expect);
    puts_(t==expect ? "  OK" : "  MISMATCH");
    puts_(" | idTech4 verdict: ");
    puts_(((~t)&0xFFFF)==0 ? "EMPTY(pass)" : "NOT EMPTY(fatal)");
    puts_("\n");
}

void _start(void){
    puts_("--- x87 tag word probe ---\n");
    __asm__ volatile("fninit");
    u32 t = tw();
    puts_("after FNINIT           cw="); hex16(cw());
    puts_(" sw="); hex16(sw()); puts_("\n");
    show("after FNINIT          ", t, 0xFFFF);

    __asm__ volatile("fninit; fld1");
    show("after FLD1            ", tw(), 0x3FFF);

    __asm__ volatile("fninit; fld1; fld1");
    show("after FLD1 x2         ", tw(), 0x0FFF);

    __asm__ volatile("fninit; fldz");
    show("after FLDZ (zero tag) ", tw(), 0x7FFF);

    __asm__ volatile("fninit; fld1; fstp %st(0)");
    show("after FLD1;FSTP       ", tw(), 0xFFFF);

    __asm__ volatile("fninit; fld1; ffree %st(0)");
    show("after FLD1;FFREE      ", tw(), 0xFFFF);

    __asm__ volatile("fninit; fld1; fptan; fstp %st(0); fstp %st(0)");
    show("after FPTAN+2 pops    ", tw(), 0xFFFF);

    __asm__ volatile("fninit; fld1; fsincos; fstp %st(0); fstp %st(0)");
    show("after FSINCOS+2 pops  ", tw(), 0xFFFF);

    __asm__ volatile("fninit; fld1; fld1; fucompp");
    show("after FUCOMPP         ", tw(), 0xFFFF);

    __asm__ volatile("fninit; fld1; fincstp; fdecstp; fstp %st(0)");
    show("after FINCSTP/FDECSTP ", tw(), 0xFFFF);

    /* 80-bit round trip through memory */
    __asm__ volatile("fninit; fld1; fstpt (%0); fldt (%0); fstp %%st(0)" :: "r"(sav) : "memory");
    show("after FSTPT/FLDT      ", tw(), 0xFFFF);

    /* FNSAVE reinitialises the FPU on real hw -> stack empty afterwards */
    __asm__ volatile("fninit; fld1; fld1; fnsave (%0)" :: "r"(sav) : "memory");
    show("after FNSAVE (reinit) ", tw(), 0xFFFF);

    /* FRSTOR of that state should restore 2 valid regs */
    __asm__ volatile("frstor (%0)" :: "r"(sav) : "memory");
    show("after FRSTOR          ", tw(), 0x0FFF);

    /* FXSAVE/FXRSTOR abridged tag round trip, ending empty */
    __asm__ volatile("fninit; fld1; fxsave (%0); fninit; fxrstor (%0); fstp %%st(0)" :: "r"(fx) : "memory");
    show("after FXSAVE/FXRSTOR  ", tw(), 0xFFFF);

    /* deep: fill all 8 then empty all 8 */
    __asm__ volatile("fninit; fld1;fld1;fld1;fld1;fld1;fld1;fld1;fld1");
    show("after 8x FLD1 (full)  ", tw(), 0x0000);
    __asm__ volatile("fstp %st(0);fstp %st(0);fstp %st(0);fstp %st(0);fstp %st(0);fstp %st(0);fstp %st(0);fstp %st(0)");
    show("after 8x FSTP (empty) ", tw(), 0xFFFF);

    /* FLDENV of an all-empty env must give 0xFFFF back */
    __asm__ volatile("fninit; fnstenv (%0); fld1; fldenv (%0)" :: "r"(env) : "memory");
    show("after FLDENV(empty)   ", tw(), 0xFFFF);

    puts_("--- done ---\n");
    sys_exit(0);
}
