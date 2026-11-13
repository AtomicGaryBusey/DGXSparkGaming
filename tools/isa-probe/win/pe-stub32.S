/* pe-stub32.S — the ONLY Windows-specific code in the PE build of the isa-probes.
 *
 * WHY THIS EXISTS
 *   Every probe in tools/isa-probe/ is a freestanding Linux ELF that ends in
 *   exactly two `int $0x80` syscalls: write(1, buf, len) and exit(0). Windows
 *   has no such interface, so those probes cannot run under Prism as-is — the
 *   repo said "run isa-probe under Prism on day one" for two months without
 *   anyone noticing that. tools/build-rtx-spark-kit.sh rewrites those two
 *   instructions into calls to the routines below and leaves every other byte
 *   of the probe alone. The probe bodies, and therefore the SDM questions they
 *   ask, are identical on both platforms.
 *
 * CONTRACT (matches the Linux register setup, which is left in place):
 *   __probe_write: %ecx = buffer, %edx = length. Writes to stdout.
 *   __probe_exit:  never returns; exit code 0.
 *
 * No .data section, by the repo's standing rule for probes (FEX a3-store bug).
 */
    .code32
    .section .bss
    .lcomm  __probe_written, 4

    .section .text
    .globl  __probe_write
__probe_write:
    pushl   %ecx                    /* save buf */
    pushl   %edx                    /* save len */
    pushl   $-11                    /* STD_OUTPUT_HANDLE */
    call    _GetStdHandle@4         /* stdcall: callee pops */
    popl    %edx
    popl    %ecx
    pushl   $0                      /* lpOverlapped */
    pushl   $__probe_written        /* lpNumberOfBytesWritten */
    pushl   %edx                    /* nNumberOfBytesToWrite */
    pushl   %ecx                    /* lpBuffer */
    pushl   %eax                    /* hFile */
    call    _WriteFile@20
    ret

    .globl  __probe_exit
__probe_exit:
    pushl   $0
    call    _ExitProcess@4
1:  jmp     1b
