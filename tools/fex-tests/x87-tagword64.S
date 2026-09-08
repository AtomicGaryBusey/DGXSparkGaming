/* x87-tagword64.S — dump four raw `fnstenv` images from an x86-64 process.
 *
 * WHY: Quake 4 died on its FIRST frame here with TAGS=0xffc0 while the same
 * FNSTENV image said TOP=0 and all four IP/DP fields were zero. That is not a
 * state three x87 pushes can produce (that would be TOP=5, TAGS=0x03ff), so the
 * suspicion is FEX's FNSTENV, not id Tech 4's math. This is the control.
 *
 * Deliberately freestanding: no libc, no compiler, no Wine, no GPU. Just the
 * four x87 sequences whose correct answers are fixed by the Intel SDM, written
 * to stdout as 4 x 28 raw bytes for the caller to decode. Nothing here can be
 * blamed on a toolchain being clever.
 *
 * Build+run under a JIT (the RootFS ships x86-64 binutils; the host has none):
 *   FEXBash -c 'as -o /tmp/t.o x87-tagword64.S && ld -o /tmp/t /tmp/t.o && /tmp/t'
 */
    .section .bss
    .lcomm  buf, 112

    .section .text
    .globl  _start
_start:
    /* 1. untouched stack: SDM says TW = 0xffff, TOP = 0 */
    finit
    fnstenv buf+0(%rip)

    /* 2. three pushes: SDM says TOP = 5, TW = 0x03ff (R5,R6,R7 valid) */
    finit
    fld1
    fld1
    fld1
    fnstenv buf+28(%rip)

    /* 3. three pushes then three pops: back to TW = 0xffff, TOP = 0 */
    finit
    fld1
    fld1
    fld1
    fstp    %st(0)
    fstp    %st(0)
    fstp    %st(0)
    fnstenv buf+56(%rip)

    /* 4. one balanced pair: TW = 0xffff, and FIP must now be NON-ZERO */
    finit
    fld1
    fstp    %st(0)
    fnstenv buf+84(%rip)

    /* write(1, buf, 112) */
    mov     $1, %rax
    mov     $1, %rdi
    lea     buf(%rip), %rsi
    mov     $112, %rdx
    syscall

    /* exit(0) */
    mov     $60, %rax
    xor     %rdi, %rdi
    syscall
