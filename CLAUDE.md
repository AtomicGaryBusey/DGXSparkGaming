# CLAUDE.md

Guidance for working on this repo. Read this first when continuing DGX Spark gaming testing.

## What this project is

A **living compatibility log** for running Steam / x86-64 PC games on an **NVIDIA DGX Spark
(GB10 Grace-Blackwell, ARM64)**. The primary deliverable is **`README.md`** — most commits are
documentation edits recording a new test result, a diagnosis, or a system change.
Author/tester identity is **AGB** (AtomicGaryBusey).

**`tools/` holds supporting scripts, and writing new ones is in scope** (confirmed by the user
2026-09-05; this repo is no longer docs-only). Keep them POSIX-ish bash, no-sudo where possible,
idempotent, and safe to re-run. Every tool needs a header comment saying *why it exists* — the
failure it prevents — because that rationale is the point of this repo. Current tools:

- **`tools/check-stack.sh`** — runs the whole Prerequisites Checklist plus the traps that have
  actually bitten (RootFS driver drift, missing Proton runtimes). Read-only; exit 0 = all pass.
  Run this first when diagnosing anything, and after any system change.
- **`tools/sync-rootfs-nvidia.sh`** — re-syncs the FEX RootFS's x86 NVIDIA libs to the host driver
  after an apt bump, and prunes the superseded blobs. Idempotent, no sudo, `DRY_RUN=1` supported.
- **`tools/pick-test-game.sh`** — smallest owned game matching a render API, from Steam's own
  metadata. **Use this before installing anything to test a graphics hypothesis.** Guessing from
  memory once cost 36 GB and 45 minutes.
- **`tools/setup-mingw.sh`** — mingw-w64 from Ubuntu's archive into a local prefix. No sudo.
  `MINGW_ARCH=i686` for 32-bit, which the x87 work needs (every id Tech 4 game is 32-bit).
- **`tools/fex-tests/x87-*.S` + `x87-wine-context32.c`** — x87 tag-word fidelity probes, written
  for the id Tech 4 investigation. The `.S` files are freestanding (built with the x86 binutils
  *inside* FEX's RootFS, so no game, Wine, GPU or compiler is in the picture) and their correct
  answers come from the Intel SDM, not from opinion. The `.c` one is a 32-bit PE that runs the
  same checks across Win32 calls and exceptions. Run every one under **both** FEX and Box64 —
  they found two different genuine bugs, one per runtime.
- **`tools/fex-inject-tests.sh`** + **`tools/fex-tests/*.c`** — do Windows-side injection primitives
  survive FEX? (Answered 2026-09-06: inline hooking ✅, forwarder loading ✅, full ReShade D3D12
  injection ✅.) Sources are deliberately **ours**, not a third party's prebuilt binaries.
- **`tools/appinfo.py`** — binary VDF parser for Steam's `appinfo.vdf` (names, depots, real download
  sizes, launch options). Underpins `pick-test-game.sh`.
- **`tools/game-run.sh`** — **use this for every test launch; never launch a game by hand.** Runs the
  game in a systemd cgroup scope (atomic teardown — Wine cannot reparent out), enables `DXVK_HUD` +
  MangoHud CSV, logs GPU telemetry, and pre-flights compat tool / shader-cache warmth / machine load.
  `DRY_RUN=1` checks only. This replaces the hand-written hygiene rules with mechanism.
- **`tools/bench-ab.sh`** — A/B two Protons on one title, second-run-only, frametime stats. Use
  before any "X feels faster" claim reaches the results table.
- **`tools/watch-run.sh`** — the one correct game watcher: CPU **delta** (not `ps` %CPU, which is a
  lifetime average and shows 228% for a hung process), log growth, and `--count` probes for the
  specific thing you claim is happening. Finds the game by **thread count**, so it cannot latch
  onto your own shell or a wrapper. Written after hand-rolling it ten times in one day.
- **`tools/config-snapshot.sh`** — `save`/`diff` the config files other programs rewrite behind
  you (OptiScaler.ini, UserSettings.json, user.reg, localconfig.vdf, ReShade.ini). Pair it with
  the guard hook: the hook stops you editing blind, this shows what changed.
- **`tools/wine-dll-loadtest.sh`** — loads a Windows DLL under Wine/FEX and reports the faulting
  **module** + RVA, not just a failure. Use it the moment a DLL fails to initialise; guessing cost
  three wrong diagnoses and three 10-minute game launches on 2026-09-07.
- **`tools/fix-steam-launcher.sh`** — makes the Steam desktop icon work. Valve's own
  `bin_steam.sh` does `FEXBash $0 "$@"` (a script path, not `-c`), so dash fails on `[[` and
  `function` and Steam silently never starts. Installs a user-level `.desktop` override + a
  `steam-fex` wrapper; no sudo, survives apt overwriting the root-owned script. `--undo` reverts.
  **DISPLAY here is `:0`** (Wayland + Xwayland), not `:1`.
- **`tools/build-optiscaler-nr.sh`** — builds **OptiScaler + DLSS-5 NR** from source on ARM64 with
  clang-20 + xwin + lld-link (no MSBuild, no sudo, no third-party prebuilt DLL). Use it when you
  need an NR host that is **not** ReShade — upstream OptiScaler has zero NR support, so it builds
  a GPL-3.0 fork whose bundled libs were verified byte-identical to upstream first. Patches are
  idempotent; every one is a clang-vs-MSVC portability fix, documented in the script header.
  **Built 2026-09-07, never yet run in a game.**
- **`tools/experiment.sh`** — runs ONE controlled experiment end to end and makes its inputs part
  of its output: refuses to start if the game is running, snapshots foreign-owned config, applies
  `--set 'Section:Key=value'` showing old -> new, clears the evidence you name, watches, then diffs
  config against the **armed** baseline so drift means "what the game changed". Use it for any A/B.
- **`tools/capture-hang.sh`** — wchan census + gdb backtraces for a wedged game and for wineserver.
  **Under FEX the backtraces are unsymbolizable JIT addresses** — the wchan census is the useful part.
- **`tools/build-dlssnr-addon.sh`** — builds the ReShade NR add-on from source, no sudo. Four
  documented gotchas in its header, each of which cost a build cycle.
- **`tools/probes/`** — hand-written probes recovered from `~/dgx-gaming-work/` on 2026-09-07:
  x87 tag word / EMMS / MMX, a real-`cpuid`-instruction probe (which corrected the published
  Burnout claim and cites upstream FEX PR #5807 on the DE bit), the Wine-CRT loader harness,
  and the original Cyberpunk launcher shim. **Check here before writing a new probe** — a
  session rebuilt two of these from scratch because they were not in the repo.
- **`tools/find-logs.sh <appid>`** — every diagnostic artifact a title can produce, with the
  ones that are ABSENT shown too (no engine log = it never reached its config, a different
  failure from crashing later). The full map, per engine and per layer, is in
  `docs/DIAGNOSTICS.md`, which is written for strangers who find this repo.
- **`tools/run-report.sh [rundir]`** — after ANY run: reads only the evidence archived inside
  that run directory (so it cannot pick up a newer run's log) and checks every failure signature
  this project has hit, engine-side and Wine-side. Says outright when a run has no manifest or an
  unknown JIT. Replaces the six-greps-from-memory ritual that made the results table inconsistent.
- **`tools/ab-runtime.sh <appid> [secs]`** — run one title under BOTH JITs and print them side by
  side. Clears the engine log between sides, and flags the case where both fail IDENTICALLY, which
  means suspect the test rather than the translators. This is how Quake 4 was shown to play under
  Box64 and fail at `SetPixelFormat` under FEX.
- **`tools/signature-check.sh`** — **run this before citing ANY log line as a root cause.**
  Greps every Proton log, resolves each title's status from README.md itself, and refuses the
  claim if a title recorded as WORKING emits the same line. Reproduces the 2026-09-07
  descriptor_buffer retraction in one command. Exit 1 = refuted, 2 = not found ("nothing to
  conclude", never a silent pass).
- **`tools/run-both.sh`** — runs one x86 command under FEX **and** Box64 and compares.
  `--which` just names who binfmt would hand it to. Different wrong answers = the translator is
  implicated; identical wrong answers = suspect the test. Found the Box64 x87 bug in a bare ELF.
- **`tools/isa-probe.sh`** + **`tools/isa-probe/`** — freestanding probes that ask the translator
  a question whose answer the Intel SDM already fixes, built with the x86 binutils inside FEX's
  RootFS and run under both JITs. Seconds, no game, no GPU, no install. Two probes so far and both
  found a real bug (Box64 tag word; FEX CPUID DE/PSE). **Add a probe before installing a 100 GB
  game to test a CPU-semantics hypothesis.**
- **`tools/pick-runtime.py <exe> [--gamedir DIR]`** — reads a title's import tables *and* its
  binaries' strings (the Quake lineage `LoadLibrary`s its renderer, so an import scan alone calls
  Daikatana "no OpenGL") and says which JIT can actually run it. Prints `VERDICT=box64|fex|either`.
  `game-run.sh` calls it and warns on the one known-impossible combination, 32-bit GL under FEX.
  **It makes no performance claim** — FEX and Box64 have never been benchmarked against each other
  here. `ddraw.dll` is deliberately not treated as a 3D renderer: counting it sent Quake 4 and Prey,
  which are OpenGL-only, to FEX.
- **`tools/idtech4-prep.sh`** — arms any id Tech 4 title with the diagnostic config that answered
  the Quake 4 question on its first run (`logFile 2` flushes per write; `1` buffers and the crash
  eats the lines you need) plus a real resolution. Detects the mod dir from the `.pk4` files.
- **`tools/make-launcher-shim.sh`** — replaces a launcher with a ~10 KB PE that starts the real exe
  and **waits** (Steam tracks the process it launched). Matches the launcher's architecture,
  backs up as `<name>.orig`, `--undo`. For the cluster where the engine works and the wrapper does not.
- **`tools/setup-mangohud-x86.sh`** — the distro package is `mangohud:arm64` and **cannot** be
  loaded into a translated x86 game. This fetches the official amd64 `.deb` into a local prefix.
  No i386 build exists, so 32-bit/OpenGL titles still get no CSV — use `com_showFPS` + `watch-run.sh`.
- **`tools/fex-build.sh`** — builds FEX from source into a local prefix (clang only; CMake
  `FATAL_ERROR`s on GCC), never over `/usr`, and **gates the result on `isa-probe.sh`**. HEAD
  already fixes the CPUID DE/PSE gap, so the cpuid probe flipping to OK is the proof the build works.
- **`tools/appinfo.py <appid> --launch|--name|--json`** — now a CLI as well as a library. `--launch`
  lists every launch entry, which is how `game-run.sh` resolves the real exe instead of guessing,
  and how NBA 2K27's "without EAC (offline only)" entry was found.
- **`tools/dlssnr-control-run.sh`** — bisects the DLSS-5 NR injection chain against a game hang:
  arms one of four layers (`baseline`/`reshade`/`probe`/`nr`) by file, then samples CPU until it can
  say HUNG or EXITED. Run the layers in that order and **stop at the first that hangs** — that layer
  owns the bug. Exists because a deadlock was nearly attributed to the NR pass with no baseline.

### Enforced by hooks — not by your good intentions (added 2026-09-07)

`.claude/hooks/` now blocks, at the tool call, the things this project keeps doing to
itself. Registered in `.claude/settings.json`; both are tested (9 and 11 cases).

- **`guard-bash.sh`** blocks: a game launch wrapped in `timeout`; `pgrep -f` / `pkill -f`;
  a bare `steam -applaunch` outside `game-run.sh`. Every one of those is a documented
  self-inflicted failure here, and the `timeout` rule was violated on **2026-09-07**, hours
  after being read at session start.
- **`guard-foreign-files.sh`** blocks writes to config files another program owns —
  `OptiScaler.ini`, `UserSettings.json`, the prefix `user.reg`, `localconfig.vdf`,
  `ReShade.ini` — unless you Read the file *after* its last change on disk. OptiScaler
  rewrites its ini on exit, Cyberpunk rewrites `UserSettings.json`, Wine rewrites
  `user.reg`. Editing from a stale view silently contaminated two DLSS experiments.
  It catches Bash/python-heredoc writes too, which is how most edits here actually happen.

- **`commit-claim-guard.sh`** is a **git `commit-msg`** hook (install once:
  `ln -sf ../../.claude/hooks/commit-claim-guard.sh .git/hooks/commit-msg`). It must be
  `commit-msg`, not `pre-commit` — `pre-commit` runs before the message exists and will
  silently check the *previous* commit's text instead. A commit whose
  message makes a result claim must carry an `Evidence: <path>` line naming a file that
  exists — or an explicit `Evidence: none — <reason>`, which then lives in the history.
  **Be clear about what it cannot do:** it would not have caught the 2026-09-07 error, because
  "3,983 evaluates" was a real number in a real log and only the *interpretation* was wrong.
  It refuses claims with no artifact; the judgement lives in the `log-result` skill.

Escape hatch for the two PreToolUse hooks: append `# HOOK_OVERRIDE: <reason>` to the command.
Deliberate, visible in the transcript, and it makes you say why. There is no silent bypass.

**Skill: `log-result`** (`.claude/skills/log-result/`) — invoke it before adding any result to
README.md. It asks the six questions that would have prevented the worst claim in this log:
is the counter *specific* to the feature or a generic hook it rides on; what is the control;
if it should change pixels, did anyone look at the pixels; what would falsify it; where is the
artifact. A human A/B beat every counter being read that day.

### Measure the measurement (2026-09-07)

**`game-run.sh` produced no numbers for its entire life, and nobody checked.** Two independent
causes, either of which alone was fatal:

1. It set `DXVK_HUD`/`MANGOHUD`/`VKD3D_DEBUG` around **`steam -applaunch`**, which is only an IPC
   request to the running Steam daemon — the daemon spawns the game with *its* environment. Every
   variable was silently dropped. It now launches Proton directly (`LAUNCH_VIA=steam` restores the
   old path and warns).
2. The installed MangoHud is **`mangohud:arm64`**, which cannot be loaded into a translated x86
   process. The tool's own advice — "sudo apt install mangohud" — named a package that was already
   installed and could never have helped.

Five runs had produced `gpu.csv` (nvidia-smi, in *our* process) and **zero** MangoHud CSVs. That is
why the results table is full of adjectives. The lesson generalises past this tool: **when an
instrument reports success, check that it produced an artifact.** `ls` the output directory.

### Process hygiene when testing (all four of these bit us on 2026-09-05)

Testing here means launching Steam, Proton and games on the **user's live desktop**. Every one of
these caused a real, visible problem in one session. Obey them.

1. **Never wrap a Proton game launch in `timeout`.** Killing the launcher does *not* kill the game —
   Wine reparents the tree, and `<game>.exe` + `xalia.exe` + `wineserver` keep running and burning
   CPU after you think the test ended. On a box whose Steam UI renders in software, that makes the
   whole desktop crawl and looks to the user like Steam is broken. Shut a test down explicitly:
   ```bash
   "$STEAM/steamapps/common/<Proton>/files/bin/wineserver" -k
   kill -9 $(ps -eo pid,args | grep -E '<Proton>/files|<Game>.exe' | grep -v grep | awk '{print $1}')
   ```
2. **Never `pgrep -f` / `pkill -f` a pattern that appears in your own command line — use
   `tools/safe-proc.sh`.** The watcher or killer matches *itself*. Three occurrences here: two
   watchers that spun ~80 minutes each; a `pkill` that killed the replacement monitor it had just
   started; and a `pkill` that killed a shell mid-heredoc, destroying the script being written. The
   last two happened *after* this rule existed — which is why there is now a tool that makes it
   structurally impossible rather than a rule asking for discipline.
3. **Poll for a condition you have actually seen occur.** One watcher waited forever for
   `update finished` lines Steam never writes for compat tools. If you cannot point at a real
   example of the string, poll something else.
4. **`setsid` does not fully detach a launched Steam** — the launching bash stays its ancestor
   (`bash → FEX → exe → steam`). Check parentage with `ps -o ppid=` before killing any long-lived
   shell, and never process-group-kill one you did not verify.

**Cyberpunk 2077's REDprelauncher looks like it "dies" when it succeeds.** Its window closing is
the normal hand-off to `Cyberpunk2077.exe`. On 2026-09-06 that was reported as a failure while the
game was in fact already running and initialising DLSS. It *is* also genuinely flaky (2 real
failures in 5 launches) — so check for a >10-thread `Cyberpunk2077.exe` before concluding anything.

Related, from the same session: `kill -9` on Steam leaves `~/.steam/steam.pid` pointing at a dead
process, and the **next launch then silently does nothing** — `rm ~/.steam/steam.pid` first. And
`steam steam://…` is *not* a cheap call: it re-runs the whole `steam.sh` bootstrap under FEX (~60 s,
with zenity dialogs flashing over the user's screen). Warn the user before firing several.

### Which runtime are you ACTUALLY measuring? (2026-09-07)

`binfmt_misc` here registers **only Box64** for x86 ELF — FEX is not registered at all. So:

- launched from a shell **by path** → **Box64/Box32**
- launched via `FEXBash` / `FEXInterpreter`, or spawned by a process already inside FEX → **FEX**
- Steam's `exe` is `/usr/bin/FEX`, so **Steam and every game it launches are FEX-hosted**

This means any result gathered by running an x86 binary straight from the agent shell measured
**Box64 while being written up as FEX**. The only tell is a `[BOX32]`/`[BOX64]` banner on stderr,
and it was nearly missed on 2026-09-07 — a 32-bit PE test was about to be attributed to FEX when
the banner gave it away. **Check `readlink /proc/<pid>/exe` before naming a runtime.**
Running a test under BOTH remains the rule; now you can be sure which is which.

### Verifying claims (2026-09-06 — this is where the real mistakes were)

Five wrong conclusions were published in one session. Every one came from trusting an inference
over a check that was cheap and available. The rules that would have caught them:

1. **A negative from a query is only as good as the name you guessed.** "GB10 is pinned to driver
   580" was published twice — from `apt-cache madison nvidia-driver-610-open` returning nothing.
   NVIDIA renamed the metapackage to `nvidia-open` at R590; the repo carries 610.57.04. Cross-check
   a negative with `apt-cache search`, or list the repo.
2. **When two independent implementations fail identically, suspect the test.** A hook test failed
   the same way under FEX and Box64 — because a 12-byte patch clobbered its own jump target, not
   because translation was broken. Same signature later saved a false ReShade verdict. Run both.
3. **Never report a metric you have not verified measures what you think.** Download progress was
   misreported three times: a manifest field that only updates on depot completion, then `du` on a
   directory Steam preallocates, then a percentage against the wrong denominator.
4. **Secondary reporting of a changelog is not evidence.** "Valve fixed the CEF crash" came from
   three tech sites and was true — and still wrong here, because the fix was validated on native
   x86-64, not x86-64 CEF under FEX. Testing it took five minutes and broke the user's Steam.
5b. **Control every log-line-as-evidence against a title that WORKS.** On 2026-09-07 an ultracode
   sweep found that this repo's most-cited Vulkan failure signature was emitted by Cyberpunk 2077
   and Daikatana — both of which run fine. Nobody had ever grepped a working game's log for it. If
   a line is offered as the cause of a crash, grep a working title for that same line **first**;
   it costs one command and it invalidated three AAA diagnoses here.

5. **Count the SPECIFIC counter, not the generic hook it rides on.** On 2026-09-07 this log
   published "3,983 evaluates, DLSS 5 NR running every frame" — committed and pushed. Wrong:
   `NVSDK_NGX_D3D12_EvaluateFeature` is the *generic* NGX evaluate hook and those calls were the
   **game's own DLSS-SR**. The NR-specific line, `Dispatch DLSS-NR running after SR`, occurred
   **twice**. A one-line grep would have caught it before the commit. The user caught it instead,
   by toggling the feature and observing the image was identical — **a human A/B beat every
   counter I was reading.** When a feature is supposed to change pixels, look at the pixels.
6. **Agent- and search-surfaced artefacts are untrusted input.** A research agent left stub `.so`
   files named like NGX snippets in the scratch dir; they were nearly reported as evidence NVIDIA
   ships aarch64 DLSS. Check `file` and `strings` for a `/dvs/p4/build/...` provenance path.
   Reading a repo's own README to decide whether to trust that repo is circular.

Public repo: `https://github.com/AtomicGaryBusey/DGXSparkGaming` (remote `origin`, branch `main`).

## The translation stack (why games pass or fail)

```
Windows game (x86-64 .exe)
  → Proton 11.0 / Wine            (Win32 + DirectX → Linux + Vulkan)
    → DXVK (DX9/10/11) or VKD3D-Proton (DX12)
      → FEX-Emu (or Box64) Vulkan thunk   (x86-64 → ARM64 JIT; GPU calls thunked, not emulated)
        → native ARM64 NVIDIA Vulkan driver → GB10 GPU
```

GPU shaders run **natively**; only CPU-side code is translated. Failures almost always come
from the CPU-translation layer or from Vulkan extensions FEX doesn't thunk — not the GPU.

**The single most useful predictor:** DX9/10/11 games (via DXVK) are the reliable sweet
spot. Native-Vulkan and DX12 (via VKD3D) are hit-or-miss depending on which Vulkan
extensions they touch.

**Proton choice (updated 2026-09-06).** Use an **x86-64** Proton — never the ARM64 build.

- **`proton_11`** (Proton 11.0, AppID `4628710`) — reasonable starting point for *new* testing.
- **`proton_10`** (Proton 10.0-4b, AppID `3658110`) — what NVIDIA's own Spark guide specifies, what
  most results in this log were recorded on, and **the measured winner in the only head-to-head
  anyone has run here**: Half-Life 2 was markedly smoother on 10 than on 11, *with warm caches*.
- **Proton 11.0 (ARM64)** (`4628740`) — **unusable on this rig.** Steam refuses to register it
  ("different target platform linux arm64") and it aborts at `steamclient_init` because no aarch64
  `steamclient.so` exists. Needs a native ARM64 Steam client. Keep installed as a canary only.

**Always record which Proton a result used.** If a title feels wrong on 11, try 10 before concluding
anything about the title. **Method note:** after switching Proton versions, take the *second* run —
a version switch empties `shadercache/<appid>/DXVK_state_cache/`, so the first run measures shader
compilation, not the runtime. An earlier revision of this file said "default to Proton 11"
unqualified; that came from reasoning, not benchmarking. See the README's *Which Proton on ARM64*.

**The DGX Spark is a FIXED platform — every unit from every vendor is GB10 + 128 GB unified,
Linux-only on DGX OS. So a result measured here applies to every DGX Spark, which is a stronger
claim than a normal compatibility log can make.** Detect the platform from DMI `product_family`
(it reads `DGX Spark` even on an HP-badged box), never from the vendor string. The **RTX Spark
is NOT fixed** — varying RAM, possibly binned GB10 parts, Windows, and Microsoft's **Prism**
emulator instead of FEX/Box64, so the translator findings here are **not** expected to transfer.
Full taxonomy and what carries over: **`docs/PLATFORM-MATRIX.md`**. **Do not investigate the ZGX's missing Mellanox NIC** — it is present but inactive and invisible to `lspci`/`/sys/class/infiniband`; two agents have now burned time rediscovering that.

**Do not propose replicating a result on another Spark.** AGB has several units (this one is an
HP ZGX Nano G1n, 1 TB; the others are 4 TB DGX Sparks) but the **hardware is identical — only disk
capacity differs**. Same silicon, same driver, same OS image, so a cross-unit re-run re-measures the
same variables and validates nothing. The other units are useful for **capacity** (the 1 TB is the
binding constraint — NBA 2K27 alone is 102 GB) and for running something long while working
elsewhere. Those are logistics, not evidence.

## Recurring failure signatures (cite these when diagnosing)

- ~~**`vkGetPhysicalDeviceDescriptorSizeEXT` unthunked**~~ — **RETRACTED 2026-09-07. This was not a
  failure signature at all.** The line is emitted by games that WORK: Cyberpunk 2077 16x, Daikatana
  4x (`grep -c DescriptorSizeEXT ~/steam-*.log`). The driver *does* expose `VK_EXT_descriptor_buffer`
  (`vulkaninfo | grep descriptor_buffer` -> revision 1), and the function is not part of that
  extension anyway — it is absent from Vulkan headers at v282 entirely. FEX prints the line
  unconditionally on any function-table miss, and `nullptr` is the correct answer for an extension
  nobody implements. **No Man's Sky, Halo Infinite and Elden Ring are UNDIAGNOSED** — do not
  substitute a new guess. Same error class as "3,983 evaluates": a real log line read as evidence
  for something it does not measure, never controlled against a working title.
- **Box64 loses x87 tags across FINCSTP/FDECSTP** — found 2026-09-08. Box64 holds the tag array
  stack-relative and does not rotate it when TOP moves explicitly, so `fld1; fincstp` reports
  `0xfffc` where the SDM says `0x3fff`. FEX is correct. **This is the same root defect as the
  FSAVE write-out order and the `fpu_savenv` rotation fix does NOT cover it.** A `fincstp` paired
  with a `fdecstp` cancels out, which is why it hid for so long. Both id Tech 4 binaries contain
  these opcodes and `Sys_FPU_StackIsEmpty()` reads the tag word and nothing else — a plausible
  mechanism for the fatal error, **not yet proven to be it**. Gate: `tools/isa-probe/x87top.32.S`.
  Write-up: `notes/upstream/box64-issue-4-fincstp-tag-rotation.md`.
- **FEX cannot set ANY pixel format for 32-bit Wine programs** — measured 2026-09-08.
  `SetPixelFormat` fails on **0/320** formats under FEX-32 with `GetLastError()==0`, while the same
  source built 64-bit gets 320/320 under FEX and the 32-bit build gets 320/320 under Box64. So
  **every 32-bit OpenGL title is FEX-unrunnable** — which is the entire id Tech 4 family — and
  there is no format-selection workaround. Diverges inside winex11's `x11drv_surface_create` at the
  GLX drawable creation. Ruled out: missing 32-bit thunk (it IS loaded, with real NVIDIA GLX),
  missing `glXCreateWindow` export, format choice, and new WoW64 (every 32-bit PE segfaults under
  it on FEX). Probes: `tools/probes/wgl/`. Write-up:
  `notes/upstream/fex-issue-2-wgl-32bit-setpixelformat.md`.
- **id Tech 4 x87 FPU stack validation** — DOOM 3, BFG, Prey (2006), Quake 4. Matrix:
  id Tech 2 ✅ / 3 ✅ / 4 ❌ / 6+ ✅ (Daikatana runs excellently, so this is not general x87 breakage).
  **Measured 2026-09-07 via Quake 4, which prints its whole x87 environment one line before dying:**
  `CTRL=0000013f STAT=00000100 TAGS=0000ffc0`, all IP/DP fields 0, `num values on stack = 0`, `TOP=0`.
  `Sys_FPU_StackIsEmpty()` reads ONLY the tag word, and `0xffc0 ^ 0xffff != 0`, so it fatals.
  The image is self-inconsistent (`0xffc0` = R0/R1/R2 in use, but 3 pushes give TOP=5 / `0x03ff`)
  and `CTRL=0x013f` is impossible — precision-control `01` is a *reserved* encoding.
  **Three hypotheses were tested and killed**, so do not re-tread them: FEX does NOT fabricate the
  tag word (`tools/fex-tests/x87-tagword{32,64}.S` and `x87-fxsave-roundtrip32.S` all pass); Wine's
  CONTEXT conversion is not reached by this game (`Quake4.exe` does not import
  `AddVectoredExceptionHandler` or `SetThreadContext`); and the 828 `OutputDebugString` exceptions
  in a `+seh` trace are handled correctly. **Root cause is still OPEN.** Two real translator bugs
  were found on the way: Box32 emits the FSAVE tag word stack-relative instead of physical
  (`0xffc0` for `0x03ff`), and FEX zeroes the whole x87 state when a VEH returns
  `EXCEPTION_CONTINUE_EXECUTION` (`CW=0x0000`, impossible on hardware). Both are upstream-filable.
  **Cheapest open test:** the engine's own decoder says the stack is empty and only the tag word
  disagrees — so binary-patch out the assertion. If the stack is merely mis-tagged the game just
  works; if three values really are stranded per frame it produces NaN geometry within seconds.
- **Rockstar/FPU float exceptions** — RDR2 hits `EXCEPTION_FLT_INVALID_OPERATION` on world
  load. Watch whether other Rockstar/RAGE titles share it.
- **Ubisoft Connect launcher** — crashes outright; blocks all Far Cry titles even though the
  Dunia engine itself runs when the .exe is launched directly.
- **clang-built DLL + dynamic MSVC CRT → access violation in Wine's builtin `MSVCP140.dll`** —
  `err:module:loader_init "<name>.dll" failed to initialize, aborting`, or `LoadLibrary` returning
  `GetLastError=998 (ERROR_NOACCESS)`. Anything cross-compiled here with `-fms-runtime-lib=dll`
  hits it; the same source built `-fms-runtime-lib=static` loads fine. **The override is a trap:**
  a prefix can already say `"msvcp140"="native,builtin"` and still use Wine's builtin, because with
  no native file present Wine falls back silently. Fix = drop Microsoft's genuine CRT DLLs beside
  the exe (pull the package URL from the VS manifest in xwin's cache and verify its SHA-256).
  **Diagnose with `tools/wine-dll-loadtest.sh`, which names the faulting module** — do not guess.
- **ReShade-induced engine deadlock (mechanism unknown)** — the game wedges at **0% CPU** with
  every thread parked (no `dma_fence` wait, no Xid, no crash dump). Confirmed on Cyberpunk 2077,
  triggered by a character call putting a face on screen. Bisected 2026-09-06: ReShade **alone**
  reproduces it with no add-on loaded, and the identical scene is clean with ReShade absent — so
  ReShade's presence is *necessary*. Blocks any ReShade-dependent route (incl. the DLSS 5 NR
  add-on) over a real play session. **Do not attribute a hang to injected code before running
  `tools/dlssnr-control-run.sh baseline`.**
  *Marker, not mechanism:* `Ignoring LoadLibrary('PhysX3Common_x64.dll') call to avoid possible
  deadlock` appears in both hanging runs. It reads like a refused load and is **not** one — ReShade
  calls the real `LoadLibrary` unconditionally and returns its handle; only its own delayed-hook
  install is skipped on mutex contention (`source/hook_manager.cpp`). This log published the wrong
  reading before checking the source. Treat the line as evidence of hook-mutex contention only.
- **box32 `NtCreateFile` collision returns `ERROR_NOACCESS` (998)** — under **Box64 only**, a
  32-bit program creating a file or directory that already exists faults inside Wine's 32-bit
  syscall return (`c0000005` at `ntdll.so+0x71f0` reading null+0x7c, `eax=c0000035`), and the
  caught fault **replaces the status**, so the app gets `ERROR_NOACCESS` instead of
  `ERROR_FILE_EXISTS`/`ERROR_ALREADY_EXISTS`. FEX is clean; 64-bit under Box64 is clean; named
  *kernel* objects are clean. Reproducer: `tools/probes/namedobj/`. Write-up:
  `notes/box64-bug-3-ntcreatefile-collision.md`. Under `+seh` this shows up as hundreds of
  handled faults — **noise you can ignore when triaging a crash**, which is exactly the mistake
  it caused: they were logged as a "shared input-path bug" behind the id Tech 4 mouse anomaly.
- **FEX duplicates the instruction before a `mov %eax, moffs32` store (32-bit, `.data` present)** —
  found 2026-09-08. In a **32-bit** binary whose writable segment is file-backed (i.e. it has a
  `.data` section), the value-producing instruction before an `a3` store executes **twice**:
  `0x3800 >> 11` yields `0`, `inc` yields 2, `imul $3` multiplies by 9. Box64 is correct, x86-64
  is correct, and the same code with **`.bss` only** is correct. Idempotent ops (`and`, `or`) hide
  it. **Consequence for this repo: never give a freestanding probe a `.data` section** — put
  constants in `.bss` and write them at runtime. The existing `isa-probe` probes were safe only by
  accident. Regression gate: `tools/isa-probe/a3store.32.S`. Write-up:
  `notes/upstream/fex-issue-1-a3-store-duplicates-preceding-op.md`.
- **RTX Remix dual-process IPC** — HL2 RTX, any Remix title: 32-bit↔64-bit shared-memory
  bridge breaks under translation.
- **Wave64-only AMD shaders** — Black Myth: Wukong requires `WaveSize(64)`; NVIDIA is
  Wave32-only, VKD3D correctly rejects. Not an ARM issue.
- **Native Linux Vulkan ports** — often far slower than going through Proton (Shadow of the
  Tomb Raider: ~1 FPS native vs. great via VKD3D). Force Proton over native ports.

Harmless noise: pressure-vessel `nvidia_layers.json` warnings; Steam UI showing `llvmpipe`
(the UI runs under FEX; games see the real GPU via DXVK+NVAPI).

## How to add a test result (conventions)

`README.md` section order, roughly: Status → System Info → Architecture → Setup Steps →
Compatibility Guidelines → **Tested by AGB** → Community-Reported → Likely to Work → Known
Issues → Compatibility Test Plan → Installed-Not-Yet-Tested (grouped by API) → Downloading →
Known Not to Launch → other-clients / native-ARM64 / display / resources.

When a game is tested, **move it** from its "Installed — Not Yet Tested" / "Likely to Work"
list into the right destination:

- **Works** → add a row to the **Tested by AGB** table (keep it alphabetical by game name):
  `| **Game** | API | Performance | Notes |`
  - *API*: the actual render path used (DX11, DX12, Vulkan, DX9, OpenGL, KEX, DOS…).
  - *Performance*: terse verdict — e.g. "Smooth, maxed, 5120x1440" or "Playable, 25-30 FPS".
  - *Notes*: engine + translation path (e.g. "Source 2 via DXVK"), launch options, caveats.
    Prefix unresolved follow-ups with **`TODO:`** so they're greppable.
- **Fails** → add a row to **Known Issues** with the root-cause diagnosis, not just "crashes".
  Tie it to one of the failure signatures above when it matches.

Keep the prose terse and factual, matching existing rows. Record *why*, not just *what* —
the diagnostic narrative (which Vulkan call, which engine subsystem) is the point of this log.

## Reach for a tool BEFORE acting — trigger table

The failure mode here is not forgetting these exist; it is not thinking of them at the decision
moment. Every row below is a mistake that was actually made in this project. **Match the trigger,
run the tool, then act.**

| When you are about to… | Run this FIRST | Because |
|---|---|---|
| launch a game, for any reason | **`tools/game-run.sh <appid>`** | A hand-launch orphaned a Wine tree that burned ~55% CPU and crawled the desktop. Also the only way a run produces numbers instead of adjectives |
| install a game to test something | **`tools/pick-test-game.sh <api>`** | Guessing from memory cost 36 GB and 45 min, and pulled a *native Linux* depot that was useless for a Windows-side test |
| say "version X feels faster/slower" | **`tools/bench-ab.sh`** | "Smooth"/"choppy" is unfalsifiable in a performance log. Take the **second** run of each version |
| diagnose anything, or after any system change | **`tools/check-stack.sh`** | 19 checks incl. traps invisible to the naive ones (RootFS drift, missing Proton runtimes) |
| finish an `apt` run that touched the driver | **`tools/sync-rootfs-nvidia.sh`** | A driver bump silently desyncs the RootFS's x86 NVIDIA libs; DLSS/NGX then breaks in non-obvious ways |
| test whether something works under FEX | **`tools/fex-inject-tests.sh`** | Run it under **Box64 too** — identical failure across two JITs means the *test* is wrong |
| build anything Windows-side | **`tools/setup-mingw.sh`** | Ubuntu's own mingw into a local prefix. Never `sudo`-install a third party's toolchain script |
| ask "what does Steam think about X" | **`tools/appinfo.py`** | Names, depots, real download sizes, launch options — from Steam's own metadata, not guesswork |
| blame a hang on the injection chain | **`tools/dlssnr-control-run.sh baseline`** | The Cyberpunk deadlock was nearly published as "the NR pass hangs the game" — the pass was already *disabled* when it died, and nobody had ever loaded a save on this rig with the chain absent |
| watch a launch / decide if it is hung | **`tools/watch-run.sh`** | Hand-rolled ten times on 2026-09-07, wrong twice (own shell; the 1-thread launch wrapper). `ps` %CPU is a lifetime average — only a `/proc/<pid>/stat` delta is honest |
| start OR finish an experiment | **`tools/config-snapshot.sh save/diff`** | OptiScaler rewrites its own ini on exit; Cyberpunk re-enabled Frame Generation by itself. Two DLSS runs were contaminated by settings nobody knew were set |
| a DLL fails to initialise / `LoadLibrary` fails | **`tools/wine-dll-loadtest.sh`** | It reports the *owning module* of the fault. On 2026-09-07 that instantly showed the crash was inside **Wine's** `MSVCP140.dll`, not our code — after three confident wrong diagnoses |
| **kill or wait on processes by name** | **`MIN_THREADS=20 tools/safe-proc.sh {list\|wait\|kill} <pattern>`** | `pgrep -f` / `pkill -f` match **your own shell**, because the pattern is in its command line. This happened **three times** in two days — twice *after* a rule was written forbidding it. Never use bare `pkill -f`/`pgrep -f` here |
| go looking for a log | **`tools/find-logs.sh <appid>`** | id Tech 4 writes `qconsole.log` beside the `.pk4` files and nobody knew for months; a Proton traceback sat unread in `launch.log` for an hour |
| finish any test run | **`tools/run-report.sh`** | The failure signatures here are a known finite list; checking them from memory produced a different subset every time |
| ask "is it FEX or Box64?" | **`tools/ab-runtime.sh <appid>`** | The two JITs give OPPOSITE results on id Tech 4 — Box64 plays Quake 4, FEX cannot create a GL context |
| **cite a log line as a root cause** | **`tools/signature-check.sh '<line>'`** | The single most expensive recurring error here. "descriptor_buffer" survived months because nobody grepped a WORKING game; Cyberpunk and Daikatana both emit it and both run fine |
| write ANY freestanding probe | **put constants in `.bss`, never `.data`** | A `.data` section triggers an FEX bug that runs the instruction before an `a3` store twice. A fuzzer with `.data` "proved" FEX computes `0x3800 >> 11 = 0` and every finding it produced was that bug |
| test a CPU-semantics hypothesis | **`tools/isa-probe.sh`** | A 40-line probe answers in seconds what a game install answers in 45 minutes and 36 GB — and its expected value comes from the SDM, not from whichever runtime ran first |
| claim "FEX does X" | **`tools/run-both.sh --which`** | binfmt registers **only Box64** for x86 ELF. Run a binary by path and you measured Box64. Steam is FEX-hosted, so its games are FEX; almost nothing else you type is |
| wonder which JIT a title needs | **`tools/pick-runtime.py <exe>`** — `game-run.sh` runs it automatically | The rule is the RENDER API, not the word size. "Box64 for 32-bit" is wrong: Half-Life 2 is 32-bit and maxed at 5120x1440 on FEX via DXVK. What FEX cannot do is 32-bit **OpenGL** (0/320 pixel formats) |
| test any id Tech 4 title | **`tools/idtech4-prep.sh <appid>`** | The engine prints its whole x87 environment one line before dying, and this log went months without turning the log on |
| blame a game's launcher | **`tools/make-launcher-shim.sh`** | The engine usually works: Far Cry's Dunia renders fine when the exe is started directly, and Cyberpunk needed a 10 KB shim after ~10 failed hand-offs |
| edit a guard hook | **`.claude/hooks/test-guards.sh`** | 20 cases, every one a real command or a real false positive. Rule 3 once blocked an `echo` that merely CONTAINED `-applaunch` |

## Common requests & how to handle them

- **"Add a result for <game>"** — ask the user for the observed behavior (FPS, settings,
  resolution, launch options, crash point) unless they supplied it; identify engine + render
  path; place the row in the correct table; match an existing failure signature if it crashed.
- **"What should I test next?"** — the `:star:` entries in Installed-Not-Yet-Tested are
  high-priority (they probe a specific engine/API hypothesis). The id Tech family and
  Rockstar-FPU questions are the most scientifically interesting open threads.
- **"Add a result for <game>"** — if it is a *performance* claim, it needs numbers:
  `tools/game-run.sh` at minimum, `tools/bench-ab.sh` for any version comparison. Record which
  Proton was used — read it from the prefix's `config_info`, not from intent.
- **System changed** — run **`tools/check-stack.sh`** first, then keep the **Status**, **Stack
  Currency** and **System Info** sections current. Kernel, driver, Steam library, box64, FEX and the
  RootFS are all readable from the agent shell; **`sudo` is not** (it needs a password) — hand the
  user `! sudo ...` commands to run in-session. Note Claude Code runs *on* the test machine, so
  `sudo reboot` ends the session.
- **After any host driver bump** — run `tools/sync-rootfs-nvidia.sh`. An apt driver update silently
  desyncs the FEX RootFS's x86 NVIDIA libs from the host, which breaks DLSS/NGX in non-obvious ways.
- **Installing a Proton** — also install the runtime named in its `toolmanifest.vdf`
  `require_tool_appid`; Steam does not pull it automatically and the game just fails.
  `steam://install/<appid>` needs Steam **fully loaded** — URLs sent while the UI still says
  "Loading user data…" are silently dropped.

## Where everything lives (read this before rebuilding something)

| | |
|---|---|
| `README.md` | the compatibility log — results, per title |
| **`docs/OPEN-QUESTIONS.md`** | **what is settled / open / ruled out, each with its next step. Read FIRST when resuming work.** |
| `docs/DIAGNOSTICS.md` | where every log and dump lives, per engine and per layer |
| `tools/` | 29 scripts; `tools/README.md` indexes them by what you are trying to do |
| `tools/probes/` | hand-written probes — **check here before writing a new one** |
| `tools/isa-probe/` | freestanding SDK-answer probes + runner |
| `tools/patches/` | GPL-3.0 OptiScaler patches (the rest of the repo is MIT) |
| `workflows/` | multi-agent research scripts, re-runnable |
| `notes/` | their outputs, with provenance headers |
| `evidence/` | run manifests + engine logs behind published claims |
| `.claude/hooks/` | the guards, plus `test-guards.sh` (20 cases) |
| `.claude/skills/log-result/` | the six questions to answer before publishing a claim |

Not in git, on the machine: `~/dgx-gaming-work/runs/` (full Proton logs, GPU telemetry),
`~/dgx-gaming-work/evidence/` (large capture logs), build prefixes (`toolchain/`,
`mangohud-x86/`, `fex-build/`, `fexsrc/`). `tools/find-logs.sh <appid>` locates them.

**Two probes were rebuilt from scratch on 2026-09-07 because they lived outside the repo and
nobody knew.** If you are about to write a probe or a helper, grep `tools/` first.

## Git / committing

Commit only when asked. Match the existing terse, result-oriented message style, e.g.:
`Add <Game> — <one-line outcome>` or `Add <N> games, <what changed>`. Already on `main`;
this is a personal log, so committing directly to `main` is the established pattern. Push is
to a **public** GitHub repo — confirm before pushing.
