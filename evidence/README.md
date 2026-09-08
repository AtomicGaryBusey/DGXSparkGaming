# `evidence/` — the artefacts behind the claims

A claim in `README.md` should be traceable to something on disk. This directory holds the
small, high-value part of that: **run manifests and engine logs**. The bulk — Proton traces,
GPU telemetry, multi-megabyte capture logs — stays out of git under
`~/dgx-gaming-work/runs/` and `~/dgx-gaming-work/evidence/`, because it runs to tens of
megabytes and is mostly redundant.

`tools/find-logs.sh <appid>` locates the full set for any title on a live machine.

## What a run directory contains

Each `runs/<appid>-<timestamp>/` here carries:

- **`run.json`** — the conditions. `runtime_requested` vs **`runtime_actual`** (read from
  `/proc/<pid>/exe`, not inferred), Proton build, runtime container, executable, launch option,
  load average at start, kernel.
- **`*-qconsole.log`** — the engine's own log, where the engine writes one.

Kept out of git but present on the machine for the same runs: `proton.log`, `launch.log`,
`gpu.csv`.

## Reading `runtime_actual`

**`unknown` means the run cannot be attributed to a translator.** It is not a formality. Early
runs on 2026-09-07 record `unknown` because JIT detection only sampled at teardown and short
runs were already gone — the very runs you most want attributed. Later runs poll during the run
and record `Box64` or `FEX`.

Any conclusion drawn from an `unknown` run is a conclusion about "some translator". This
repository published exactly that mistake once: a play session written up as FEX when binfmt had
handed the whole chain to Box64.

## The runs

| Run | Game | JIT | Proton | Engine-log signatures |
|---|---|---|---|---|
| `2210-20260907-220813` | Quake 4 | **unknown** | Experimental | - |
| `2210-20260907-221956` | Quake 4 | **unknown** | Experimental | - |
| `2210-20260907-222525` | Quake 4 | **unknown** | Experimental | GL ok |
| `2210-20260907-222609` | Quake 4 | **unknown** | Experimental | GL ok |
| `2210-20260907-223229` | Quake 4 | **Box64** | Experimental | GL ok |
| `2210-20260907-225230` | Quake 4 | **FEX** | Experimental | SetPixelFormat, no GL |
| `3970-20260907-225437` | Prey | **unknown** | Experimental | - |
| `3970-20260907-230933` | Prey | **unknown** | Experimental | - |
| `3970-20260907-231149` | Prey | **unknown** | Experimental | - |
| `3970-20260907-231525` | Prey | **Box64** | Experimental | - |
| `3970-20260907-231800` | Prey | **FEX** | Experimental | SetPixelFormat |
| `9050-20260907-232102` | DOOM 3 | **Box64** | Experimental | - |
| `9050-20260907-232337` | DOOM 3 | **FEX** | Experimental | SetPixelFormat |
## `2026-09-08-steamclient-init-box64/`

The `steamclient_init` root cause: four symbols missing from Box64's box32 libc wrapper table.
Documented to the `log-result` convention — the six questions answered explicitly — and shipped
with **`verify.sh`, which re-runs all 16 checks** rather than asking you to trust a transcript.
16/16 pass as of 2026-09-08.

## `2026-09-07-quake4-x87/`

The artefacts behind the id Tech 4 x87 entries in `README.md`:

- `quake4-qconsole-fpu-block.txt` — the engine's own x87 dump one line before it died:
  `CTRL=0000013f STAT=00000100 TAGS=0000ffc0`, all four IP/DP fields zero,
  `num values on stack = 0`, `Top of stack pointer = 0`. `Sys_FPU_StackIsEmpty()` reads
  **only** the tag word, and `0xffc0 ^ 0xffff != 0`, so it fatals.
- `qconsole-DIRECT-LAUNCH-mapload.log` — the run that reached `game/airdefense1`
  (16.3 s, 1635 images, 1130 models) and wrote an autosave. Confirmed playable by a human.
- `probe-bare-elf-fex.txt`, `probe-windows-pe-fex-vs-box64.txt` — the freestanding probes that
  **exonerated FEX** for the tag word and localised the stack-relative bug to Box64.
- `probe-wine-seh.log` — proof the probe's exceptions were genuinely dispatched, so the
  scenarios measured what they claimed to.
- `x87-tagword*.S`, `x87-fxsave-roundtrip32.S`, `x87-wine-context32.c` — copies of the probe
  sources as they were when the measurements were taken. The maintained versions live in
  `tools/`.
- `autoexec.cfg` — the exact diagnostic config used.

One file is deliberately absent: the 244 KB `+seh` trace. Its content is summarised in the
extracts above, and it is on the machine if needed.

## The gap this cannot close

The original crash that started the id Tech 4 investigation printed `TAGS=0000ffc0` — which is
**Box64's** signature bug, not FEX's — but its Proton log was overwritten by the next run before
anyone read the runtime from it. **That attribution is permanently lost.** Every run since
archives its own logs so it cannot happen again. It is the single most expensive mistake in this
project's history and it cost nothing but a filename collision.
