/* cpuid.32 — which CPUID leaf-1 feature bits does the translator advertise?
 *
 * WHY: Burnout Paradise refuses to start with "This machine does not support the
 * SSE2 Command Set." The README blamed a missing SSE2 bit. That is WRONG --
 * measured 2026-09-07, FEX advertises sse2 -- so the dialog is triggered by
 * something else the game's probe reads. Games of that era commonly test a MASK
 * of leaf-1 EDX bits, not SSE2 alone, so this dumps them individually.
 *
 * Every bit below is architecturally REQUIRED on any CPU that reports SSE2, so
 * the expectations are not opinions. DE (bit 2) and PSE (bit 3) are the ones to
 * watch: they are absent here, and absent bits in a mask test fail the whole
 * test no matter what SSE2 says.
 *
 * Ref: Intel SDM vol.2A, CPUID, Table 3-11 (leaf 01H EDX feature bits).
 */
    .code32
    .section .bss
    .lcomm  buf, 96
    .section .text
    .globl  _start
_start:
    xorl    %eax, %eax
    cpuid
    movl    $0x4c58414d, buf+0          /* "MAXL" — highest basic leaf */
    movl    %eax, buf+4

    movl    $1, %eax
    cpuid
    movl    %edx, %esi                  /* leaf 1 EDX = feature bits */
    movl    %ecx, %edi                  /* leaf 1 ECX */

    movl    $0x20555046, buf+8          /* "FPU " bit 0  */
    movl    %esi, %eax
    andl    $1, %eax
    movl    %eax, buf+12

    movl    $0x20204544, buf+16         /* "DE  " bit 2  */
    movl    %esi, %eax
    shrl    $2, %eax
    andl    $1, %eax
    movl    %eax, buf+20

    movl    $0x20455350, buf+24         /* "PSE " bit 3  */
    movl    %esi, %eax
    shrl    $3, %eax
    andl    $1, %eax
    movl    %eax, buf+28

    movl    $0x20435354, buf+32         /* "TSC " bit 4  */
    movl    %esi, %eax
    shrl    $4, %eax
    andl    $1, %eax
    movl    %eax, buf+36

    movl    $0x20385843, buf+40         /* "CX8 " bit 8  */
    movl    %esi, %eax
    shrl    $8, %eax
    andl    $1, %eax
    movl    %eax, buf+44

    movl    $0x564f4d43, buf+48         /* "CMOV" bit 15 */
    movl    %esi, %eax
    shrl    $15, %eax
    andl    $1, %eax
    movl    %eax, buf+52

    movl    $0x20584d4d, buf+56         /* "MMX " bit 23 */
    movl    %esi, %eax
    shrl    $23, %eax
    andl    $1, %eax
    movl    %eax, buf+60

    movl    $0x20455353, buf+64         /* "SSE " bit 25 */
    movl    %esi, %eax
    shrl    $25, %eax
    andl    $1, %eax
    movl    %eax, buf+68

    movl    $0x32455353, buf+72         /* "SSE2" bit 26 */
    movl    %esi, %eax
    shrl    $26, %eax
    andl    $1, %eax
    movl    %eax, buf+76

    movl    $0x33455353, buf+80         /* "SSE3" ECX bit 0 */
    movl    %edi, %eax
    andl    $1, %eax
    movl    %eax, buf+84

    movl    $4, %eax
    movl    $1, %ebx
    movl    $buf, %ecx
    movl    $88, %edx
    int     $0x80
    movl    $1, %eax
    xorl    %ebx, %ebx
    int     $0x80
