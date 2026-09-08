/* x87-fxsave-roundtrip32.S — does an FXSAVE/FXRSTOR round-trip preserve the
 * x87 TAG WORD under FEX?
 *
 * WHY: Quake 4 dies on frame 1 with TAGS=0xffc0 (R0,R1,R2 marked Valid) while
 * the same image reports TOP=0 and "num values on stack = 0". Three pushes give
 * TOP=5/TAGS=0x03ff, so that state is not reachable by a plain x87 leak.
 * x87-tagword32.S and ...64.S both came back CLEAN, so straight-line FNSTENV is
 * fine and the earlier "FEX fabricates the tag word" idea is dead.
 *
 * What is left is the CONVERSION. FXSAVE stores an ABRIDGED 8-bit tag (1 bit per
 * register: in-use / empty). FNSTENV stores the FULL 16-bit tag (2 bits per
 * register: Valid / Zero / Special / Empty). Going abridged -> full requires
 * re-deriving Valid vs Zero vs Special by looking at each register's actual
 * bits, and getting that wrong yields exactly this failure shape. Wine performs
 * that conversion on every context save/restore, and Quake4.exe is 32-bit, so
 * it takes the WoW64 path on every Win32 call.
 *
 * If the round-trip below corrupts the tag word, the bug is reproducible with no
 * Wine, no game and no GPU. If it does NOT, the JIT is exonerated for a second
 * time and the next suspect is Wine's 32<->64-bit CONTEXT conversion.
 *
 * Emits 4 x 28 bytes: [A roundtrip-empty] [B roundtrip-3push] [C direct-3push
 * control] [D = 16 bytes of B's raw FXSAVE header, zero-padded].
 */
    .code32
    .section .bss
    .align  16
    .lcomm  fxa, 512
    .lcomm  buf, 112

    .section .text
    .globl  _start
_start:
    /* A: EMPTY stack through a save/restore round-trip. Must stay 0xffff. */
    finit
    fxsave  fxa
    finit
    fxrstor fxa
    fnstenv buf+0

    /* B: THREE PUSHES through a round-trip. Must stay TOP=5 / 0x03ff. */
    finit
    fld1
    fld1
    fld1
    fxsave  fxa
    finit
    fxrstor fxa
    fnstenv buf+28

    /* C: control — the same three pushes with NO round-trip. */
    finit
    fld1
    fld1
    fld1
    fnstenv buf+56

    /* D: the raw FXSAVE header from B, so the abridged tag byte is visible.
     *    Re-run B's save so fxa holds the 3-push image again. */
    finit
    fld1
    fld1
    fld1
    fxsave  fxa
    mov     $fxa, %esi
    mov     $buf+84, %edi
    mov     $4, %ecx
    rep movsl                     /* copy 16 bytes: FCW FSW FTW rsvd FOP FIP */

    /* write(1, buf, 112) */
    finit
    mov     $4, %eax
    mov     $1, %ebx
    mov     $buf, %ecx
    mov     $112, %edx
    int     $0x80

    mov     $1, %eax
    xor     %ebx, %ebx
    int     $0x80
