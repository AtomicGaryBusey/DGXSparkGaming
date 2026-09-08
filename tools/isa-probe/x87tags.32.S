/* x87tags.32 — does FNSTENV report a truthful x87 tag word?
 *
 * This is the probe that cracked the id Tech 4 investigation. id Tech 4's
 * Sys_FPU_StackIsEmpty() reads the tag word and NOTHING else, so a wrong tag
 * word is a fatal error in DOOM 3 / BFG / Prey / Quake 4 even when the x87 stack
 * is genuinely fine.
 *
 * Result on 2026-09-07: FEX correct, **Box64 wrong** — it writes the FSAVE tag
 * word in STACK-relative order where Intel specifies PHYSICAL register order, so
 * three pushes read 0xffc0 instead of 0x03ff. Reproduces in a bare 32-bit ELF
 * with no Wine, no Windows and no game, which is what makes it filable.
 *
 * Refs: Intel SDM vol.1 8.1.7 (tag word), vol.2 FNSTENV/FINIT.
 * Assembled with `as` directly, so no cpp: no #define, no macros.
 */
    .code32
    .section .bss
    .lcomm  env, 32
    .lcomm  buf, 64

    .section .text
    .globl  _start
_start:
    /* --- empty stack: SDM says CW=0x037F, tag word all-Empty = 0xFFFF ------ */
    finit
    fnstenv env
    movl    $0x30445743, buf+0          /* "CWD0" */
    movzwl  env+0, %eax
    movl    %eax, buf+4
    movl    $0x30474154, buf+8          /* "TAG0" */
    movzwl  env+8, %eax
    movl    %eax, buf+12

    /* --- three pushes: TOP=5, physical R5/R6/R7 in use -> tag word 0x03FF -- */
    finit
    fld1
    fld1
    fld1
    fnstenv env
    movl    $0x33474154, buf+16         /* "TAG3" */
    movzwl  env+8, %eax
    movl    %eax, buf+20
    movl    $0x33504f54, buf+24         /* "TOP3" */
    movzwl  env+4, %eax
    shrl    $11, %eax
    andl    $7, %eax
    movl    %eax, buf+28

    /* --- SEVEN pushes: Prey's actual state. SDM says TOP=1, R1..R7 valid,
     *     so the tag word is 0x0003. Added 2026-09-08 because a fix that made
     *     the THREE-push case correct did not fix Prey, whose dump showed
     *     TAGS=0xc000 with TOP=0 -- a combination three pushes never produces.
     *     The probe only covered the path that had already been looked at. */
    finit
    fld1
    fld1
    fld1
    fld1
    fld1
    fld1
    fld1
    fnstenv env
    movl    $0x37474154, buf+48         /* "TAG7" */
    movzwl  env+8, %eax
    movl    %eax, buf+52
    movl    $0x37504f54, buf+56         /* "TOP7" */
    movzwl  env+4, %eax
    shrl    $11, %eax
    andl    $7, %eax
    movl    %eax, buf+60

    /* --- balanced push/pop: back to empty -------------------------------- */
    finit
    fld1
    fstp    %st(0)
    fnstenv env
    movl    $0x42474154, buf+32         /* "TAGB" */
    movzwl  env+8, %eax
    movl    %eax, buf+36
    movl    $0x31504946, buf+40         /* "FIP1" */
    movl    env+12, %eax
    movl    %eax, buf+44

    movl    $4, %eax                    /* write(1, buf, 48) */
    movl    $1, %ebx
    movl    $buf, %ecx
    movl    $64, %edx
    int     $0x80
    movl    $1, %eax                    /* exit(0) */
    xorl    %ebx, %ebx
    int     $0x80
