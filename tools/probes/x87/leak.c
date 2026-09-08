/* x87 stack-balance probe: sequences that classically leak one stack slot in a
   translator. Every case must end with tag word 0xFFFF (id Tech 4's requirement). */
typedef unsigned short u16; typedef unsigned int u32;
static void sys_write(const char*s,unsigned long n){__asm__ volatile("syscall"::"a"(1UL),"D"(1UL),"S"(s),"d"(n):"rcx","r11","memory");}
static void sys_exit(int c){__asm__ volatile("syscall"::"a"(60UL),"D"((long)c));__builtin_unreachable();}
static void puts_(const char*s){unsigned long n=0;while(s[n])n++;sys_write(s,n);}
static void hex16(u32 v){char b[7]="0x0000";for(int i=0;i<4;i++){int d=(v>>((3-i)*4))&0xF;b[2+i]=d<10?'0'+d:'a'+d-10;}sys_write(b,6);}
static unsigned char env[128] __attribute__((aligned(16)));
static u32 tw(void){__asm__ volatile("fnstenv (%0)"::"r"(env):"memory");return *(u16*)(env+8);}
static u32 sw(void){return *(u16*)(env+4);}
static void show(const char*l){u32 t=tw();puts_(l);puts_(" tw=");hex16(t);puts_(" sw=");hex16(sw());
 puts_(((~t)&0xFFFF)==0?"  EMPTY(pass)":"  NOT EMPTY(fatal)");puts_("\n");}
static double big = 1.0e30;      /* > 2^63 : out of range for FSIN/FCOS/FPTAN */
static double one = 1.0, half = 0.5, three = 3.0;
static int i32; static long long i64;

void _start(void){
  puts_("--- x87 stack-balance probe (all lines must say EMPTY) ---\n");

  __asm__ volatile("fninit; fldl (%0); fptan; fstp %%st(0); fstp %%st(0)" :: "r"(&half) : "memory");
  show("FPTAN in range +2 pops ");

  /* out of range: C2=1, NO push. Popping twice would then underflow. Pop only if C2==0. */
  __asm__ volatile("fninit; fldl (%0); fptan; fnstsw %%ax; testb $4,%%ah; jnz 1f; fstp %%st(0); fstp %%st(0); jmp 2f; 1: fstp %%st(0); 2:"
                   :: "r"(&big) : "ax","memory");
  show("FPTAN out of range     ");

  __asm__ volatile("fninit; fldl (%0); fsin; fnstsw %%ax; testb $4,%%ah; jnz 1f; 1: fstp %%st(0)" :: "r"(&big) : "ax","memory");
  show("FSIN out of range      ");

  __asm__ volatile("fninit; fldl (%0); fxtract; fstp %%st(0); fstp %%st(0)" :: "r"(&three) : "memory");
  show("FXTRACT (pushes) +2pops");

  __asm__ volatile("fninit; fldl (%0); fldl (%1); fsincos; fnstsw %%ax; fstp %%st(0); fstp %%st(0); fstp %%st(0)" :: "r"(&one),"r"(&half) : "ax","memory");
  show("FSINCOS +3 pops        ");

  /* FPREM loop: repeat until C2 clears */
  __asm__ volatile("fninit; fldl (%1); fldl (%0); 1: fprem; fnstsw %%ax; testb $4,%%ah; jnz 1b; fstp %%st(0); fstp %%st(0)"
                   :: "r"(&big), "r"(&three) : "ax","memory");
  show("FPREM loop +2 pops     ");

  __asm__ volatile("fninit; fldl (%0); fldl (%1); fscale; fstp %%st(0); fstp %%st(0)" :: "r"(&three),"r"(&one) : "memory");
  show("FSCALE +2 pops         ");

  __asm__ volatile("fninit; fldl (%0); fldl (%1); fyl2x; fstp %%st(0)" :: "r"(&three),"r"(&one) : "memory");
  show("FYL2X (pops 1) +1 pop  ");

  __asm__ volatile("fninit; fldl (%0); f2xm1; fstp %%st(0)" :: "r"(&half) : "memory");
  show("F2XM1 +1 pop           ");

  /* FISTP of an out-of-range value: masked invalid, still pops */
  __asm__ volatile("fninit; fldl (%0); fistpl (%1)" :: "r"(&big), "r"(&i32) : "memory");
  show("FISTP overflow (pops)  ");
  __asm__ volatile("fninit; fldl (%0); fistpll (%1)" :: "r"(&big), "r"(&i64) : "memory");
  show("FISTPLL overflow (pops)");

  /* stack overflow: 9 pushes, masked -> indefinite pushed, TOP wraps. Then 9 pops. */
  __asm__ volatile("fninit; fld1;fld1;fld1;fld1;fld1;fld1;fld1;fld1;fld1;"
                   "fstp %st(0);fstp %st(0);fstp %st(0);fstp %st(0);fstp %st(0);"
                   "fstp %st(0);fstp %st(0);fstp %st(0);fstp %st(0)");
  show("9 push / 9 pop (ovf)   ");

  /* stack underflow: pop from empty then re-init-free */
  __asm__ volatile("fninit; fstp %st(0); fstp %st(0)");
  show("2 pops from empty      ");

  /* FCMOV / FCOMI paths */
  __asm__ volatile("fninit; fld1; fldz; fcomip %st(1),%st; fstp %st(0)");
  show("FCOMIP +1 pop          ");
  __asm__ volatile("fninit; fld1; fldz; fucomip %st(1),%st; fstp %st(0)");
  show("FUCOMIP +1 pop         ");

  /* FFREE + FINCSTP (the canonical Sys_FPU_ClearStack shape) */
  __asm__ volatile("fninit; fld1; fld1; fld1;"
                   "ffree %st(0); fincstp; ffree %st(0); fincstp; ffree %st(0); fincstp");
  show("FFREE+FINCSTP x3       ");

  puts_("--- done ---\n");
  sys_exit(0);
}
