/* x87-tagword32.S — the same four FNSTENV probes, as a 32-bit x86 process.
 *
 * WHY A SECOND FILE: the 64-bit probe (x87-tagword64.S) came back CLEAN — FEX
 * reports TW=0xffff on an empty stack and 0x03ff/TOP=5 after three pushes, so
 * "FEX fabricates the tag word" was REFUTED before it reached the README.
 * But Quake4.exe is PE32 (32-bit x86, verified with `file`), and a JIT can have
 * an entirely separate 32-bit x87 path. This closes that gap.
 *
 * Only the ABI differs from the 64-bit probe: int $0x80, write=4, exit=1, and
 * absolute rather than RIP-relative addressing. The x87 sequences are identical
 * on purpose, so any difference in the output is a difference in the JIT.
 *
 *   FEXBash -c 'as --32 -o /tmp/t.o x87-tagword32.S &&
 *               ld -m elf_i386 -o /tmp/t /tmp/t.o && /tmp/t'
 */
    .code32
    .section .bss
    .lcomm  buf, 112

    .section .text
    .globl  _start
_start:
    finit
    fnstenv buf+0

    finit
    fld1
    fld1
    fld1
    fnstenv buf+28

    finit
    fld1
    fld1
    fld1
    fstp    %st(0)
    fstp    %st(0)
    fstp    %st(0)
    fnstenv buf+56

    finit
    fld1
    fstp    %st(0)
    fnstenv buf+84

    /* write(1, buf, 112) */
    mov     $4, %eax
    mov     $1, %ebx
    mov     $buf, %ecx
    mov     $112, %edx
    int     $0x80

    /* exit(0) */
    mov     $1, %eax
    xor     %ebx, %ebx
    int     $0x80
