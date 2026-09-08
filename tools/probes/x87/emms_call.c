/* Does the EMMS bug fire when EMMS is in a DIFFERENT dynarec block from the x87 push?
   Models idSIMD_MMX::Memcpy: caller has live x87 pushes, callee does MMX+EMMS. */
typedef unsigned short u16; typedef unsigned int u32;
static void sys_write(const char*s,unsigned long n){__asm__ volatile("syscall"::"a"(1UL),"D"(1UL),"S"(s),"d"(n):"rcx","r11","memory");}
static void sys_exit(int c){__asm__ volatile("syscall"::"a"(60UL),"D"((long)c));__builtin_unreachable();}
static void puts_(const char*s){unsigned long n=0;while(s[n])n++;sys_write(s,n);}
static void hex16(u32 v){char b[7]="0x0000";for(int i=0;i<4;i++){int d=(v>>((3-i)*4))&0xF;b[2+i]=d<10?'0'+d:'a'+d-10;}sys_write(b,6);}
static unsigned char env[128] __attribute__((aligned(16)));
static u32 tw(void){__asm__ volatile("fnstenv (%0)"::"r"(env):"memory");return *(u16*)(env+8);}
static u32 top(void){return (*(u16*)(env+4)>>11)&7;}
static void show(const char*l){u32 t=tw();puts_(l);puts_(" tw=");hex16(t);puts_(" top=");hex16(top());
 puts_(((~t)&0xFFFF)==0?"  EMPTY(pass)":"  NOT EMPTY -> idTech4 FATAL");puts_("\n");}
static unsigned long long src[4]={1,2,3,4}; static unsigned long long dst[4];
/* pure-MMX memcpy + emms, like idSIMD_MMX::Memcpy, in its own function */
__attribute__((noinline)) void mmx_copy(void){
  __asm__ volatile("movq (%0),%%mm0\n\tmovq 8(%0),%%mm1\n\tmovq %%mm0,(%1)\n\tmovq %%mm1,8(%1)\n\temms"
    ::"r"(src),"r"(dst):"memory");
}
__attribute__((noinline)) void just_emms(void){ __asm__ volatile("emms"); }
void _start(void){
  puts_("--- EMMS in a SEPARATE block/function while x87 is live ---\n");
  __asm__ volatile("fninit"); mmx_copy();                       show("call mmx_copy()      ");
  __asm__ volatile("fninit; fld1"); mmx_copy(); __asm__ volatile("fstp %st(0)"); show("fld1;call mmx;fstp   ");
  __asm__ volatile("fninit; fld1"); mmx_copy();                 show("fld1;call mmx_copy   ");
  __asm__ volatile("fninit; fld1"); just_emms();                show("fld1;call just_emms  ");
  /* same block, but MMX-only before EMMS (no x87 push) */
  __asm__ volatile("fninit; movq (%0),%%mm0; emms"::"r"(src):"memory"); show("movq mm0;emms same   ");
  puts_("--- done ---\n"); sys_exit(0);
}
