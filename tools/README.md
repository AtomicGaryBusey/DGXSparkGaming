# `tools/` — what each one is for, and the mistake it exists to prevent

Every tool here was written after something went wrong. The header comment of each
script names the specific failure it prevents; this page is the index, organised by
**what you are trying to do**, not alphabetically.

Two conventions hold throughout:

- **No `sudo`.** Anything needing root is handed to you as a `! sudo ...` command to run
  yourself. Nothing installs system-wide; build tools unpack into `~/dgx-gaming-work/`.
- **Idempotent and re-runnable.** Most take `DRY_RUN=1` or `--undo`.

---

## 1. Testing a game

**Start here. Never launch a game by hand.** A hand-launch once orphaned a Wine tree that
burned ~55% CPU for 1h46m and made the desktop unusable.

| Tool | Use it when |
|---|---|
| **`game-run.sh <appid>`** | Any test launch, always. Runs the game in a systemd cgroup scope (atomic teardown — Wine cannot reparent out), records the JIT that actually ran it, archives its own logs, writes `run.json`. |
| **`idtech4-prep.sh <appid>`** | Before testing any id Tech 4 title. Arms the diagnostic config that made the engine print its own x87 state. |
| **`ab-runtime.sh <appid> [secs]`** | You want to know whether FEX or Box64 is responsible. Runs both, reports side by side. |
| **`run-report.sh [rundir]`** | After any run. Reads the archived evidence and checks every failure signature this project has hit. |
| **`watch-run.sh`** | A run is in progress and you need to know if it is alive or hung. |
| **`experiment.sh`** | A controlled A/B where config changes are part of the result. |
| **`bench-ab.sh`** | Comparing two Protons on one title. Take the **second** run of each — a version switch empties the shader cache. |

### The launch environment, and why it matters

`game-run.sh` launches Proton **directly** rather than via `steam -applaunch`. That is not a
refactor: `-applaunch` is an IPC request to the Steam daemon, which spawns the game with
*its* environment, so every variable the tool set was silently dropped. Five runs produced
GPU telemetry (from our own process) and **zero** MangoHud CSVs before anyone checked.

Useful knobs:

```
RUNTIME=auto|fex|box64   which JIT. `auto` follows binfmt (Box64 here) and says so.
SECONDS_MAX=N            auto-stop after N seconds
LAUNCH_OPTION=option1    a non-default launch entry (see appinfo.py --launch)
DRY_RUN=1                pre-flight only, prints the exact chain it would run
PROTON=proton_10         expect a specific compat tool
NO_PROTON_LOG=1          skip PROTON_LOG (on by default; the corpus needs it)
```

### `run.json` — every run describes its own conditions

The single most expensive error in this project was writing up a session as FEX when
`binfmt_misc` had handed it to Box64. Evidence and conditions were stored separately, so
attribution had to be *reconstructed* later — and reconstruction is guessing. Each run now
writes a manifest recording `runtime_requested` **and** `runtime_actual` (read from
`/proc/<pid>/exe`), the Proton, the container, the exe, and the load at start, alongside an
archived copy of that run's `proton.log` and `qconsole.log`.

If `runtime_actual` is `unknown`, **the run cannot be attributed to a JIT.** That is not a
formality: `PROTON_LOG` writes to `~/steam-<appid>.log` and the next run overwrites it,
which already destroyed the only record able to say which translator produced the original
id Tech 4 x87 crash. That question is now permanently unanswerable.

---

## 2. Checking a claim before you publish it

| Tool | Use it when |
|---|---|
| **`signature-check.sh '<log line>'`** | **Before citing any log line as a root cause.** Greps every Proton log, resolves each title's status from `README.md` itself, and refuses the claim if a *working* title emits the same line. |
| **`run-both.sh <cmd>`** | Any claim naming a runtime. Also `--which`, which says who binfmt would hand an x86 ELF to. |
| **`isa-probe.sh [filter]`** | Testing a CPU-semantics hypothesis. Freestanding probes whose correct answers come from the Intel SDM. |

**Why `signature-check.sh` exists.** `vkGetPhysicalDeviceDescriptorSizeEXT` was cited for
months as the root cause of three AAA titles. Cyberpunk 2077 emits it 16 times and runs
fine; Daikatana emits it 4 times and runs excellently. One `grep` against a working game's
log would have caught it on day one. Exit 1 = refuted, 2 = not found (*nothing to
conclude*, never a silent pass).

**Why both runtimes, always.** Different wrong answers ⇒ the translator is implicated.
*Identical* wrong answers ⇒ suspect the test — a hook test here once failed the same way
under both JITs because it clobbered its own jump target.

---

## 3. Diagnosing a failure

| Tool | Use it when |
|---|---|
| **`check-stack.sh`** | First thing when anything is wrong, and after any system change. 19 checks including traps invisible to the naive ones. |
| **`run-report.sh`** | A run failed and you want the known signatures checked for you. |
| **`wine-dll-loadtest.sh`** | A DLL fails to initialise. Reports the **owning module** of the fault, not just "it failed". |
| **`capture-hang.sh`** | A game is wedged. Note: under FEX the backtraces are unsymbolizable JIT addresses — the wchan census is the useful part. |
| **`find-logs.sh <appid>`** | You need the evidence and cannot remember where this engine puts it. Prints every log/dump/prefix path for a title, marking which exist — absence is itself diagnostic. See [`../docs/DIAGNOSTICS.md`](../docs/DIAGNOSTICS.md). |
| **`config-snapshot.sh save\|diff`** | Before and after any experiment. OptiScaler rewrites its ini on exit; Cyberpunk re-enables Frame Generation by itself. |
| **`dlssnr-control-run.sh <layer>`** | Bisecting a hang against an injection chain. Run `baseline` first — always. |

---

## 4. Building things

| Tool | Use it when |
|---|---|
| **`setup-mingw.sh`** | You need to build a Windows PE. `MINGW_ARCH=i686` for 32-bit. |
| **`setup-mangohud-x86.sh`** | You want frametime CSVs. The distro package is `mangohud:arm64` and **cannot** instrument a translated x86 game. |
| **`fex-build.sh`** | Building FEX from source. clang only; never installs over `/usr`; **gates the result on `isa-probe.sh`**. |
| **`make-launcher-shim.sh <launcher> <target>`** | The engine works but the launcher doesn't. Builds a ~10 KB stand-in that starts the real exe and waits. |
| **`fex-inject-tests.sh`** | Testing whether Windows-side injection survives translation. |
| **`build-optiscaler-nr.sh` / `build-dlssnr-addon.sh`** | The DLSS-5 Neural Rendering work. |

---

## 5. Planning and metadata

| Tool | Use it when |
|---|---|
| **`pick-test-game.sh <api>`** | **Before installing anything** to test a graphics hypothesis. Guessing from memory once cost 36 GB and 45 minutes, and pulled a native Linux depot useless for a Windows-side test. |
| **`save-workflow-report.sh <output.json>`** | A multi-agent workflow finished. Persists its synthesis into `notes/` with a provenance header (agents, tokens, tool calls), because those runs cost ~1-2M tokens each and otherwise vanish with the job. |
| **`appinfo.py <appid> --launch\|--name\|--json`** | Anything you need from Steam's own metadata: real download sizes, depots, and **launch entries** (this is how NBA 2K27's "without EAC (offline only)" entry was found). |

---

## 6. System

| Tool | Use it when |
|---|---|
| **`safe-proc.sh {list\|wait\|kill} <pattern>`** | **Any time you would reach for `pgrep -f` or `pkill -f`.** Those match your own shell, because the pattern is in its command line. That happened three times here, twice *after* a written rule forbade it. `MIN_THREADS=N` filters out wrappers. |
| **`sync-rootfs-nvidia.sh`** | After any `apt` run that touched the driver. A bump silently desyncs the RootFS's x86 NVIDIA libs and breaks DLSS/NGX in non-obvious ways. |
| **`fix-steam-launcher.sh`** | The Steam desktop icon does nothing. Valve's `bin_steam.sh` runs `FEXBash $0 "$@"`, so dash chokes on `[[`. `--undo` reverts. |

---

## 7. Probe sources

- **`tools/probes/wgl/`** — the WGL pixel-format probe that localised FEX's id Tech 4 blocker to
  `SetPixelFormat` in ~130 lines, with no game involved.
- **`tools/probes/`** — the hand-written probes (x87 tag word and EMMS/MMX, CPUID, the
  Wine-CRT loader harness, the original Cyberpunk launcher shim). These lived outside version
  control in `~/dgx-gaming-work/` until 2026-09-07, which caused a later session to
  **rebuild two of them from scratch** without knowing they existed. See
  [`probes/README.md`](probes/README.md).

- **`tools/isa-probe/`** — freestanding x86 assembly probes plus `.expect` files quoting the
  Intel SDM. Built with the x86 binutils *inside FEX's RootFS* (the ARM64 host has no x86
  assembler at all — a C version was tried first and silently compiled for aarch64).
  Adding a probe is ~40 lines and answers in seconds what a game install answers in 45
  minutes. See `tools/isa-probe/README.md`.
- **`tools/fex-tests/`** — the x87 tag-word and Wine-context probes that settled the id
  Tech 4 investigation, deliberately **our** sources rather than a third party's prebuilt
  binaries.

---

## Enforcement

Three hooks in `.claude/hooks/` block, at the tool call, the things this project keeps
doing to itself: a game launch wrapped in `timeout`, `pgrep -f`/`pkill -f`, a bare
`steam -applaunch`, writes to config files another program owns, and commits whose message
makes a result claim without naming an artifact. Escape hatch: append
`# HOOK_OVERRIDE: <reason>` — deliberate, visible, and it makes you say why.

Run `.claude/hooks/test-guards.sh` after editing any hook: 20 cases, every one a real
command this project runs or a real false positive that actually happened.

### `pick-runtime.py` — which JIT can run this title?

```
tools/pick-runtime.py <path-to-exe> [--gamedir DIR] [--quiet]
```

Answers the question this repo kept answering from memory, and getting wrong. The intuitive rule
— *Box64 for 32-bit, FEX for 64-bit* — is **false**: Half-Life 2 is 32-bit and runs smooth and
maxed at 5120x1440 under FEX, because DX9 goes through DXVK to Vulkan. What FEX cannot do is
**32-bit OpenGL**: it sets 0 of 320 pixel formats for any 32-bit Wine program, so no GL context is
possible (`tools/probes/wgl/wgl-formatsweep32.c`). The axis is the render API.

Two detection details, both learned by testing against titles whose answer we already knew:

- It scans **strings as well as import tables**. Quake-lineage engines call
  `LoadLibrary("opengl32.dll")` from inside `ref_gl.dll`, so nothing imports GL statically and an
  import-only scan reported Daikatana as "no OpenGL" — exactly backwards.
- It does **not** count `ddraw.dll` as a 3D renderer. Quake 4 and Prey both import DirectDraw for
  2D/video while being OpenGL-only; counting it routed two titles we know fail under FEX to FEX.

`game-run.sh` runs it on every launch, records the verdict in `run.json`, and warns when you ask
for the impossible combination. It warns rather than refuses — reproducing a known failure on
purpose is legitimate, and a tool that blocks it just gets bypassed.

**It says nothing about speed.** No FEX-vs-Box64 benchmark has ever been run here; every runtime
claim in this log is functional. For a performance statement use `tools/bench-ab.sh`.

## Late additions (2026-09-08/09)

| tool | what it is for |
|---|---|
| `build-box64-symfix.sh` | builds Box64 with this project's two patches. **Prey and Quake 4 do not reach gameplay on stock Box64.** |
| `box64-swap.sh` | swaps that build in/out of `/usr/local/bin`, which is the only path pressure-vessel's binfmt honours. Refuses to clobber a non-stock backup. |
| `wine-mouse-knobs.sh` | `GrabPointer` / `GrabFullscreen` / `MouseWarpOverride`, via `wine reg`. One at a time. |
| `mousefeel.sh` | measures the mouse path against an X-server control **outside Wine**. Includes the `SPIN-ONE-WAY` phase that finds confinement walls. |
| `x87-fuzz.py` | differential x87 fuzzer (FEX vs Box64) with an SDM occupancy model and minimisation. |
| `save-workflow-report.sh` | persists workflow output into `notes/` with provenance. |

**A rule the mouse work earned:** an instrument that reports success must be checked for having
actually produced an artifact. `mousefeel.sh` reported three confident findings from a control
that was never running, because Wine silently ignored the raw-input flags it registered with. It
now says `CONTROL DEAD` instead. Apply the same suspicion to any probe added here.
