/* a3store.32 — does an ALU result survive a `mov %eax, moffs32` store?
 *
 * On FEX-emu 2607 (armv8.4) it does NOT. In a 32-bit binary whose writable
 * segment is FILE-BACKED (i.e. it has a .data section, RW filesz > 0), the
 * value-producing instruction immediately before an `a3` store -- the EAX-only
 * "mov %eax, moffs32" encoding -- is executed TWICE. Box64 is correct, x86-64
 * is correct, and the same code with no .data section is correct.
 *
 * How it presented: a differential x87 fuzzer appeared to prove that FEX
 * computed 0x3800 >> 11 = 0. That is absurd on its face, which is why it was
 * chased instead of published -- the fuzzer had gained a .data section for its
 * float constants, and every one of its "findings" was this bug. The existing
 * probes in this directory are unaffected only because they happen to use .bss
 * alone. THAT IS AN ACCIDENT, and this probe exists so it stops being one.
 *
 * The .data section below is therefore LOAD-BEARING. Do not "tidy" it away.
 *
 * Each case computes a value and stores it through the encoding under test:
 *   ADD1/INC1/SHR1 store via `a3`   (mov %eax, moffs32)      -- the suspect
 *   EDX1           stores %edx via `89 /r`                   -- the control
 * A control that stays correct while the others break is what separates
 * "this encoding is mishandled" from "arithmetic is broken", and the second
 * reading would have been reported if the control were missing.
 *
 * Refs: Intel SDM vol.2, MOV (A3 = MOV moffs32, EAX). The expected values are
 * plain arithmetic, not a subtle corner of the spec.
 */
    .code32
    .section .data
dpad:   .long   0x12345678          /* LOAD-BEARING: makes RW filesz > 0 */
    .section .bss
    .lcomm  buf, 64

    .section .text
    .globl  _start
_start:
    /* --- ADD1: 0x3800 + 1, stored via a3 -> must be 0x3801 --------------- */
    movl    $0x31444441, buf+0          /* "ADD1" */
    movl    $0x3800, %eax
    addl    $1, %eax
    movl    %eax, buf+4

    /* --- INC1: 0 then INC, stored via a3 -> must be 1 -------------------- */
    movl    $0x31434e49, buf+8          /* "INC1" */
    xorl    %eax, %eax
    incl    %eax
    movl    %eax, buf+12

    /* --- SHR1: 0x3800 >> 11, stored via a3 -> must be 7 ------------------ */
    movl    $0x31524853, buf+16         /* "SHR1" */
    movl    $0x3800, %eax
    shrl    $11, %eax
    movl    %eax, buf+20

    /* --- EDX1: the same add in %edx, stored via 89 /r -> must be 0x3801 -- */
    movl    $0x31584445, buf+24         /* "EDX1" */
    movl    $0x3800, %edx
    addl    $1, %edx
    movl    %edx, buf+28

    movl    $4, %eax                    /* write(1, buf, 32) */
    movl    $1, %ebx
    movl    $buf, %ecx
    movl    $32, %edx
    int     $0x80
    movl    $1, %eax
    xorl    %ebx, %ebx
    int     $0x80
