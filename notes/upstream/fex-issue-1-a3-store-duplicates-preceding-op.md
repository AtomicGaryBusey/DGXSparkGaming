# [32-bit] Instruction before `mov %eax, moffs32` (`a3`) executes twice when the writable segment is file-backed

**Repo:** FEX-Emu/FEX
**Version:** `fex-emu-armv8.4` 2607-1~n (Ubuntu PPA), `fex-emu-wine` 2608~1-3~n
**Host:** NVIDIA GB10 (Grace-Blackwell), ARM64, Ubuntu, kernel 6.17.0-1032-nvidia
**Guest:** 32-bit static ELF (i386), run via `FEXBash` and via `FEXInterpreter` — same result

## Summary

In a **32-bit** binary whose writable `PT_LOAD` is **file-backed** (`FileSiz > 0`, i.e. the binary
has a `.data` section), the value-producing instruction immediately preceding a
`mov %eax, moffs32` store — the EAX-only `A3` encoding — is executed **twice**.

Box64 is correct on the identical binary. x86-64 is unaffected. The identical program with **no
`.data` section** (`FileSiz == 0`, pure `.bss`) is correct under FEX.

This is silent wrong-arithmetic in ordinary integer code, not a crash.

## Minimal reproducer

```asm
    .code32
    .section .data
dpad:   .long   0x12345678      /* required: makes the RW segment FileSiz > 0 */
    .section .bss
    .lcomm  buf, 64
    .section .text
    .globl  _start
_start:
    xorl    %eax, %eax
    incl    %eax
    movl    %eax, buf+0         /* assembles to A3 = MOV moffs32, EAX */

    movl    $4, %eax            /* write(1, buf, 4) */
    movl    $1, %ebx
    movl    $buf, %ecx
    movl    $4, %edx
    int     $0x80
    movl    $1, %eax
    xorl    %ebx, %ebx
    int     $0x80
```

```
as --32 -o r.o r.S && ld -m elf_i386 -o r r.o
FEXInterpreter ./r | xxd -p     ->  02000000     # 2  -- INC executed twice
box64          ./r | xxd -p     ->  01000000     # 1  -- correct
```

## Observed behaviour, by operation

Starting from `%eax = 0x3800`, storing the result via `A3`:

| instruction | correct | FEX | consistent with |
|---|---|---|---|
| `shr $11, %eax` | `0x7` | `0x0` | `>>22` |
| `shr $1, %eax`  | `0x1c00` | `0x0e00` | `>>2` |
| `shl $1, %eax`  | `0x7000` | `0xe000` | `<<2` |
| `add $1, %eax`  | `0x3801` | `0x3802` | `+2` |
| `imul $3, %eax` | `0xa800` | `0x1f800` | `*9` |
| `not %eax`      | `0xffffc7ff` | `0x3800` | applied twice |
| `xor $0xff, %eax` | `0x38ff` | `0x3800` | applied twice |
| `and $0xff, %eax` | `0x0` | `0x0` | idempotent, hides it |
| `or $1, %eax`   | `0x3801` | `0x3801` | idempotent, hides it |

Every result equals the operation applied exactly twice. Idempotent operations mask the bug.

## What does and does not trigger it

| condition | affected |
|---|---|
| store via `A3` (`mov %eax, moffs32`) | **yes** |
| store via `89 /r` (`mov %eax, disp(%reg)`) | no |
| same arithmetic in `%ebx/%ecx/%edx/%esi/%edi/%ebp`, stored via `89 /r` | no |
| load via `A1` (`mov moffs32, %eax`) | no |
| `NOP`s between the ALU op and the `A3` store | **yes** (still doubles) |
| RW segment `FileSiz == 0` (no `.data`, `.bss` only) | no |
| RW segment `FileSiz > 0` (has `.data`) | **yes** |
| x86-64 equivalent | no |
| address of the store target | irrelevant — same address passes without `.data`, fails with it |

The `FileSiz` dependency is what makes this look like page-tracking rather than decoding: with a
file-backed writable page the store appears to invalidate the enclosing block, which is then
re-entered in a way that repeats the preceding operation. The `A1` load being unaffected is
consistent with that. Determined empirically; the mechanism is a guess and the matrix above is
the evidence.

Verified deterministic: identical output over repeated runs, under both `FEXBash` and
`FEXInterpreter`, with byte-identical instruction encodings in the passing and failing builds
(`objdump` confirms only the address immediates differ).

## Regression test

`tools/isa-probe/a3store.32.S` + `.expect` in
<https://github.com/AtomicGaryBusey/DGXSparkGaming>, run by `tools/isa-probe.sh`, which executes
each probe under both FEX and Box64 and grades against expected values:

```
== a3store.32 ==
  ADD1   expect 0x3801    FEX=0x3802  <-- MISMATCH  Box64=0x3801
  INC1   expect 0x1       FEX=0x0002  <-- MISMATCH  Box64=0x0001
  SHR1   expect 0x7       FEX=0x0000  <-- MISMATCH  Box64=0x0007
  EDX1   expect 0x3801    FEX=0x3801  Box64=0x3801     <- control, same arithmetic via 89 /r
```

## How it was found

A differential x87 fuzzer appeared to show FEX computing `0x3800 >> 11 = 0`. That is absurd on
its face, so it was chased rather than reported: the generated program had acquired a `.data`
section for float constants, and every "x87 finding" was actually this. Worth stating plainly in
case it helps someone triaging: **an emulator bug this basic will usually surface first as an
implausible result somewhere else.**
