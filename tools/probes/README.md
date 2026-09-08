# `tools/probes/` — the hand-written probes, recovered from outside the repo

These were written during investigation and lived in `~/dgx-gaming-work/` — outside version
control, unfindable by anyone else, and unfindable by a later session of the same work.

**That cost something concrete.** On 2026-09-07 an ISA probe suite was built from scratch in
`tools/isa-probe/` that reimplemented `x87/x87tag.c` (written hours earlier the same day) and
the CPUID check already sitting in `cpuid/cpuid-probe.sh`. Both had already found their
answers. The duplication happened purely because the originals were not in the repo. That is
the argument for this directory existing.

## The relationship to `tools/isa-probe/`

Both ask the translator questions with known answers. They differ in shape and neither
replaces the other:

| | `tools/isa-probe/` | `tools/probes/` |
|---|---|---|
| Form | freestanding `.S`, 8-byte tag/value records | freestanding C, prints its own text |
| Expected answers | external `.expect` file quoting the Intel SDM | in the probe's own output |
| Runner | `isa-probe.sh`, runs both JITs and diffs vs SDM | run by hand or by a small wrapper |
| Best for | regression-gating a build, adding a case in ~40 lines | one-off questions with awkward setup |

Use `isa-probe.sh` for anything you want re-run automatically. Use these when the question
needs C, a Windows PE, or a shape the record format can't express.

## What is here

### `x87/` — floating-point state fidelity

The id Tech 4 cluster. `Sys_FPU_StackIsEmpty()` is `fnstenv; eax=[buf+8]; eax^=~0; eax&=0xFFFF;`
— it demands a tag word of exactly `0xFFFF` and reads nothing else, so a wrong tag word is a
fatal error in DOOM 3 / Quake 4 / Prey even when the stack is genuinely fine.

| File | Question |
|---|---|
| `x87tag.c` | Tag word after known push/pop sequences, 32- and 64-bit. |
| `leak.c` | Does anything strand values on the x87 stack across a boundary? |
| `emms.c`, `emms32.c`, `emms_call.c` | Does `EMMS` correctly restore x87 state, including across a call? |
| `mmx.c` | MMX/x87 register-file aliasing. |
| `decode-fnstenv.py` | Decodes raw `FNSTENV` images: control/status/tag words, TOP, FIP/FDP. |
| `decode-fxsave.py` | Decodes an `FXSAVE` header including the abridged tag byte. |

The two decoders were used for the finding that **Box64 writes the FSAVE tag word in
stack-relative order where Intel specifies physical** (`0xffc0` where hardware gives `0x03ff`),
while FEX gets it right. They existed only in a scratch directory until now.

### `cpuid/` — what CPU does the translator claim to be?

`cpuid-probe.sh` executes a **real `cpuid` instruction** rather than reading `/proc/cpuinfo`,
using a hand-assembled ELF because this box has no x86 compiler. It corrected a published
claim: FEX *does* advertise SSE2 (leaf 1 EDX bit 26). What it does **not** advertise on
FEX-2607 is bit 2 (DE) and bit 3 (PSE) — and upstream **FEX PR #5807** reports that Burnout
Paradise reads the **DE** bit as its SSE2 flag. `div0.S` probes divide-by-zero exception
behaviour.

### `wine-crt/` — the DLL that would not initialise

`loadtest.c` and `mini.cpp` are the minimal harness that localised a crash to **Wine's builtin
`MSVCP140.dll`** rather than to our own code, after three confident wrong diagnoses. Anything
cross-compiled here with `-fms-runtime-lib=dll` hits it; the same source built
`-fms-runtime-lib=static` loads fine.

### `launcher-shim/` — provenance

`cp2077-shim.c` is the hand-written 10 KB stand-in for `REDprelauncher.exe`, written after that
launcher failed roughly ten hand-offs in a row. `tools/make-launcher-shim.sh` generalises it to
any launcher; this is kept because it is the original, and because its comments explain the one
detail that makes the pattern work: **the shim must wait on the child**, since Steam tracks the
process it started and returning early reads as the game exiting.

## Building them

Freestanding C probes, no libc:

```bash
FEXBash -c 'gcc -nostdlib -static -O1 -o /tmp/p tools/probes/x87/x87tag.c && /tmp/p'
box64 /tmp/p          # always run both — see tools/run-both.sh
```

Windows PEs use the local mingw prefix from `tools/setup-mingw.sh` (`MINGW_ARCH=i686` for
32-bit). Note the host has **no x86 assembler**: `as`/`ld` come from inside FEX's RootFS, which
is why builds are wrapped in `FEXBash`. An earlier attempt compiled a "32-bit x86" probe with
the host toolchain and silently produced an aarch64 binary.
