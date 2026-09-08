# [x87] FINCSTP/FDECSTP move TOP without rotating the tag array

**Repo:** ptitSeb/box64 · **Version:** v0.4.4 (`2f130fab1`); also present with the
`fpu_savenv` rotation fix from box64-issue-2 applied, which does **not** cover this.
**Host:** NVIDIA GB10 (Grace-Blackwell), ARM64 · **Guest:** 32-bit ELF, no Wine, no game

## Summary

Box64 stores x87 tags **stack-relative** (indexed by ST(i)). `FINCSTP` and `FDECSTP` change TOP
without moving any data, so a stack-relative tag array must be **rotated** to keep the same
*physical* registers tagged. Box64 does not rotate it, so after an explicit TOP change the tag
word describes the wrong registers.

Intel SDM, FINCSTP / FDECSTP: *"Adds one to / subtracts one from the TOP field of the FPU status
word ... does not affect the tag word or the contents of any register."*

## Reproducer

`tools/isa-probe/x87top.32.S` in <https://github.com/AtomicGaryBusey/DGXSparkGaming>, run by
`tools/isa-probe.sh` under both Box64 and FEX. Freestanding 32-bit ELF: no Wine, no game, no libc.

```
== x87top.32 ==
  INC1   expect 0x3fff    FEX=0x3fff  Box64=0xfffc  <-- MISMATCH
  DEC1   expect 0x3fff    FEX=0x3fff  Box64=0xcfff  <-- MISMATCH
  RT1    expect 0x3fff    FEX=0x3fff  Box64=0x3fff       <- control, passes
  IN7    expect 0x0003    FEX=0x0003  Box64=0x000c  <-- MISMATCH
```

| sequence (after `finit`) | SDM tag word | Box64 | note |
|---|---|---|---|
| `fld1; fincstp` | `0x3fff` | `0xfffc` | value is in R7; Box64 reports R0 |
| `fld1; fdecstp` | `0x3fff` | `0xcfff` | reports R6 |
| `fld1; fincstp; fdecstp` | `0x3fff` | `0x3fff` | **correct** — the two errors cancel |
| `fld1`×7 `; fincstp` | `0x0003` | `0x000c` | whole pattern shifted one slot |

FEX-Emu is correct on all four.

## Relationship to the FSAVE tag-word issue

Same root cause — tags kept stack-relative — but a different symptom, and the `fpu_savenv`
rotation from box64-issue-2 does not fix it: that rotates by TOP when the environment is written,
whereas here the stored tags are already attributed to the wrong registers before the save. A
complete fix is either to hold the tag array in physical order, or to rotate it on **every** TOP
change (push, pop, FINCSTP, FDECSTP) rather than only at save time.

## Why it is worth fixing

id Tech 4 (DOOM 3, Quake 4, Prey) calls `Sys_FPU_StackIsEmpty()` every frame; it reads the tag
word and *nothing else*, and fatals unless it is `0xFFFF`. `FINCSTP`/`FDECSTP` opcodes (`d9 f7` /
`d9 f6`) are present in `Quake4.exe` and in both games' `gamex86.dll`. Whether this is *the* cause
of those titles' "FPU stack is not empty" fatal error is **not established here** — that would
need instrumenting a live run — but it is a mechanism by which correct guest code gets an
incorrect tag word, which is exactly the failure those games report.

## How it was found

A differential x87 fuzzer (`tools/x87-fuzz.py`) with an SDM-derived model of stack occupancy.
The model deliberately tracks only *empty vs non-empty* per physical register plus TOP, not the
tag encoding (Valid/Zero/Special), because the encoding depends on the values and a model that
guessed at it would raise false alarms.
