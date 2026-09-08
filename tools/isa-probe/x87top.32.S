/* x87top.32 — do FINCSTP and FDECSTP move TOP *without* disturbing the tags?
 *
 * Intel SDM, FINCSTP/FDECSTP: "Adds one to / subtracts one from the TOP field
 * of the FPU status word... does not affect the tag word or the contents of any
 * register." So moving TOP must leave exactly the same PHYSICAL registers
 * tagged as before.
 *
 * Box64 v0.4.4 fails this. It keeps its tag array STACK-RELATIVE and does not
 * rotate it when TOP moves explicitly, so a value that was in R7 is reported as
 * being in R0. FEX is correct on every case here.
 *
 * WHY IT MATTERS: this is the same root defect as the FSAVE write-out order
 * (notes/upstream/box64-issue-2-fsave-tagword.md) -- tags held stack-relative
 * and not maintained -- but the write-out fix does NOT cover it, because that
 * one rotates by TOP at save time and here the *stored* tags are already wrong.
 * id Tech 4's Sys_FPU_StackIsEmpty() reads the tag word and nothing else, and
 * both Quake4.exe and the Prey/Quake 4 gamex86.dll contain FINCSTP/FDECSTP.
 *
 * RT1 is the control: FINCSTP followed by FDECSTP returns TOP to where it
 * started, the two errors cancel, and Box64 gets it RIGHT. A suite without that
 * case would suggest "TOP handling is broken" generally, which is not the claim.
 *
 * NOTE ON RECORDING: results are stored through %edx (89 /r), never through
 * %eax, because `mov %eax, moffs32` (a3) triggers a separate FEX bug -- see
 * tools/isa-probe/a3store.32.S. This file has no .data section for the same
 * reason. Both constraints are deliberate.
 */
    .code32
    .section .bss
    .lcomm  env, 32
    .lcomm  buf, 64

    .section .text
    .globl  _start
_start:
    /* --- INC1: one push then FINCSTP. R7 stays in use -> 0x3FFF ---------- */
    movl    $0x31434e49, buf+0          /* "INC1" */
    finit
    fld1
    fincstp
    fnstenv env
    movl    env+8, %edx
    movl    %edx, buf+4

    /* --- DEC1: one push then FDECSTP. R7 stays in use -> 0x3FFF ---------- */
    movl    $0x31434544, buf+8          /* "DEC1" */
    finit
    fld1
    fdecstp
    fnstenv env
    movl    env+8, %edx
    movl    %edx, buf+12

    /* --- RT1: FINCSTP then FDECSTP -> back where we started, 0x3FFF ------
     *     CONTROL. Box64 passes this one because the two errors cancel. */
    movl    $0x20315452, buf+16         /* "RT1 " */
    finit
    fld1
    fincstp
    fdecstp
    fnstenv env
    movl    env+8, %edx
    movl    %edx, buf+20

    /* --- IN7: seven pushes then FINCSTP. R1..R7 in use -> 0x0003 --------- */
    movl    $0x20374e49, buf+24         /* "IN7 " */
    finit
    fld1
    fld1
    fld1
    fld1
    fld1
    fld1
    fld1
    fincstp
    fnstenv env
    movl    env+8, %edx
    movl    %edx, buf+28

    movl    $4, %eax                    /* write(1, buf, 32) */
    movl    $1, %ebx
    movl    $buf, %ecx
    movl    $32, %edx
    int     $0x80
    movl    $1, %eax
    xorl    %ebx, %ebx
    int     $0x80
