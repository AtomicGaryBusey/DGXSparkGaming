/* Minimal repro: box64 ARM64 dynarec EMMS hard-reset is undone by the deferred
   x87 stack delta.  dynarec_arm64_0f.c case 0x77 calls
   x87_purgecache(dyn, ninst, next=1, ...) then stores top=0/tags=TAGS_EMPTY.
   next=1 leaves dyn->n.x87stack pending, so the block-end purge re-applies the
   +1 from the FLD1 and rewinds top to 7 / tags to 0xfffc.
   Architecturally EMMS must leave tags==0xFFFF and TOP==0 unconditionally. */
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
static unsigned long long src[2]={1,2};
void _start(void){
  puts_("--- EMMS after pending x87 pushes (expect all EMPTY, top=0) ---\n");
  __asm__ volatile("fninit; emms");                       show("emms only            ");
  __asm__ volatile("fninit; fld1; emms");                 show("fld1;emms            ");
  __asm__ volatile("fninit; fld1; fld1; emms");           show("fld1 x2;emms         ");
  __asm__ volatile("fninit; fld1; fld1; fld1; emms");     show("fld1 x3;emms         ");
  __asm__ volatile("fninit; fld1; movq (%0),%%mm0; emms"::"r"(src):"memory"); show("fld1;movq mm0;emms   ");
  __asm__ volatile("fninit; fld1; fstp %st(0); emms");     show("fld1;fstp;emms       ");
  puts_("--- done ---\n"); sys_exit(0);
}
