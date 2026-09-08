# isa-probe — ask the translator a question whose answer is already known

Each probe is a freestanding x86 program that exercises **one** CPU behaviour and
writes its observations to stdout as fixed 8-byte records:

    [4 ASCII tag chars][4-byte little-endian value]

A sidecar `<probe>.expect` says what the Intel SDM requires each tag to be. The
runner (`tools/isa-probe.sh`) builds every probe with the x86 binutils **inside
FEX's own RootFS** (the host has none), runs it under **both** FEX and Box64, and
compares against the expectation.

## Why this shape

- **Freestanding.** No libc, no compiler, no Wine, no GPU, no Steam, no 100 GB
  install. A probe answers in seconds what a game launch answers in ten minutes,
  if it answers at all.
- **The expected value is external.** It comes from the SDM, not from whichever
  runtime happened to run first. A probe cannot be "passed" by agreeing with a bug.
- **Both runtimes, every time.** Different wrong answers means the translator is
  implicated. *Identical* wrong answers means suspect the probe — this project has
  been burned by a test that clobbered its own jump target and failed the same way
  under two JITs.
- **Records, not prose.** Adding a probe never means writing a bespoke decoder.

## Provenance

Written 2026-09-07, after three 40-line assembly probes settled in one hour an
id Tech 4 question that had been open for months — and killed three of the
investigator's own hypotheses on the way. The first run of the suite found a
Box64 bug in a bare 32-bit ELF that had previously been misattributed to Wine's
32<->64-bit CONTEXT conversion.

## Expect-file syntax

    TAG  0x037f     # must equal exactly
    TAG  !0         # must be non-zero
    TAG  *          # informational only, never fails
    # comment
