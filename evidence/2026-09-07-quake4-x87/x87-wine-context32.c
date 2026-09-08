/* x87-wine-context32.c — does a 32-bit Windows process keep a truthful x87 tag
 * word across the calls that make Wine convert FPU context?
 *
 * WHY THIS EXISTS
 *   Quake 4 dies on frame 1 on this rig with TAGS=0xffc0 / TOP=0 while its own
 *   decoder reports "num values on stack = 0". Three freestanding probes
 *   (x87-tagword64.S, x87-tagword32.S, x87-fxsave-roundtrip32.S) show FEX's
 *   FNSTENV and its FXSAVE abridged->full tag reconstruction are all CORRECT, so
 *   the JIT is not inventing the tag word. What remains is Wine.
 *
 *   A 32-bit CONTEXT carries FloatSave in FSAVE layout (full 16-bit tag word,
 *   indexed by PHYSICAL register R0..R7). A 64-bit CONTEXT carries FltSave in
 *   FXSAVE layout (abridged 8-bit tag). Every Win32 call from a 32-bit process
 *   crosses that boundary. And the arithmetic fits: take a real 3-push leak
 *   (physical R5,R6,R7, TOP=5) and re-index it STACK-relative -- R5->slot0,
 *   R6->slot1, R7->slot2 -- and you get exactly 0xffc0.
 *
 *   Scenario E is the one that matters. If an EMPTY x87 stack comes back
 *   non-0xffff after a Win32 call, that alone is fatal to every id Tech 4 game,
 *   because Sys_FPU_StackIsEmpty() reads nothing but the tag word.
 *
 * Build (no sudo; toolchain from tools/setup-mingw.sh MINGW_ARCH=i686):
 *   i686-w64-mingw32-gcc-win32 -O0 -o x87ctx.exe x87-wine-context32.c
 * Run under the same Proton that runs the game, so the result is about the
 * stack under test rather than some other Wine.
 */
#include <windows.h>
#include <stdio.h>

/* A macro, never a function: with values deliberately stranded on the x87 stack
 * we are already violating "stack empty at a call", so a call here could perturb
 * the very thing being measured. */
#define SNAP(buf) __asm__ __volatile__("fnstenv %0" : "=m"(buf) :: "memory")
#define CLEAR()   __asm__ __volatile__("finit")
#define PUSH3()   __asm__ __volatile__("fld1; fld1; fld1")

static unsigned char A[32], B[32], C[32], D[32], E[32], F[32], G[32], H[32];

static LONG CALLBACK veh(EXCEPTION_POINTERS *ep) {
    /* Step over the 1-byte int3 and resume. Returning CONTINUE_EXECUTION forces
     * Wine to rebuild and restore the whole CONTEXT, FPU state included --
     * which is the conversion this test exists to exercise. */
    ep->ContextRecord->Eip += 1;
    return EXCEPTION_CONTINUE_EXECUTION;
}

static unsigned r16(const unsigned char *b, int o) { return b[o] | (b[o+1] << 8); }
static unsigned r32(const unsigned char *b, int o) {
    return b[o] | (b[o+1] << 8) | ((unsigned)b[o+2] << 16) | ((unsigned)b[o+3] << 24);
}

static int report(const char *what, const unsigned char *b, unsigned etw, int etop) {
    unsigned cw = r16(b,0), sw = r16(b,4), tw = r16(b,8);
    int top = (sw >> 11) & 7;
    int ok = (tw == etw && top == etop);
    printf("%-38s CW=%04x SW=%04x TW=%04x TOP=%d FIP=%08x  [%s]\n",
           what, cw, sw, tw, top, r32(b,12), ok ? "OK" : "MISMATCH");
    if (!ok) {
        static const char *n[4] = {"Valid","Zero","Special","Empty"};
        printf("%-38s   expected TW=%04x TOP=%d\n", "", etw, etop);
        printf("%-38s   tags:", "");
        for (int r = 0; r < 8; r++) printf(" R%d=%s", r, n[(tw >> (2*r)) & 3]);
        printf("\n");
    }
    return ok;
}

int main(void) {
    PVOID h;

    CLEAR();               SNAP(A);            /* baseline, no Win32 in between */
    CLEAR(); PUSH3();      SNAP(B);            /* 3 pushes, no Win32 in between */

    CLEAR(); PUSH3(); Sleep(0);   SNAP(C);     /* cheapest Win32 call          */
    CLEAR(); PUSH3(); Sleep(10);  SNAP(D);     /* a real wait, certain syscall */
    CLEAR();          Sleep(10);  SNAP(E);     /* EMPTY across a Win32 call    */

    /* OutputDebugString raises DBG_PRINTEXCEPTION_C (0x40010006) and Wine
     * dispatches + unwinds it like any other exception. A +seh trace of Quake 4
     * shows 828 of these on ONE thread during startup, all from Wine's
     * OutputDebugString address -- so this is the exception the game actually
     * takes, hundreds of times, before the frame-1 FPU check. */
    CLEAR(); PUSH3(); OutputDebugStringA("x87probe");  SNAP(G);
    CLEAR();          OutputDebugStringA("x87probe");  SNAP(H);

    h = AddVectoredExceptionHandler(1, veh);
    CLEAR(); PUSH3();
    __asm__ __volatile__("int3");              /* full CONTEXT save + restore  */
    SNAP(F);
    if (h) RemoveVectoredExceptionHandler(h);

    CLEAR();                                   /* clean stack before any printf */

    printf("x87 tag word across Wine context conversion (32-bit PE)\n");
    printf("%s\n", "---------------------------------------------------------------------------");
    report("A  empty, no Win32 call",            A, 0xffff, 0);
    report("B  3 pushes, no Win32 call",         B, 0x03ff, 5);
    report("C  3 pushes + Sleep(0)",             C, 0x03ff, 5);
    report("D  3 pushes + Sleep(10)",            D, 0x03ff, 5);
    int e = report("E  EMPTY + Sleep(10)",       E, 0xffff, 0);
    report("G  3 pushes + OutputDebugStringA",   G, 0x03ff, 5);
    int hh = report("H  EMPTY + OutputDebugStringA", H, 0xffff, 0);
    report("F  3 pushes + caught exception",     F, 0x03ff, 5);
    if (!hh)
        printf("\n*** H FAILED: an EMPTY x87 stack is reported non-empty after one\n"
               "    OutputDebugString. Quake 4 takes 828 of these before frame 1.\n"
               "    That is the whole id Tech 4 failure, with no game involved. ***\n\n");
    printf("%s\n", "---------------------------------------------------------------------------");
    printf("id Tech 4 verdict: an empty stack across a Win32 call reads TW=%04x -> %s\n",
           r16(E,8), e ? "engine would be happy"
                       : "*** FatalError: 'the FPU stack is not empty' ***");
    printf("Quake 4 observed CW=013f TAGS=ffc0 TOP=0; anything matching that shape here\n"
           "localises the bug to Wine's 32<->64-bit CONTEXT conversion, not to FEX.\n");
    return 0;
}
