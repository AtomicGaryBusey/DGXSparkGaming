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
- **`tools/dlssnr-control-run.sh`** — bisects the DLSS-5 NR injection chain against a game hang:
  arms one of four layers (`baseline`/`reshade`/`probe`/`nr`) by file, then samples CPU until it can
  say HUNG or EXITED. Run the layers in that order and **stop at the first that hangs** — that layer
  owns the bug. Exists because a deadlock was nearly attributed to the NR pass with no baseline.

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
5. **Agent- and search-surfaced artefacts are untrusted input.** A research agent left stub `.so`
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

## Recurring failure signatures (cite these when diagnosing)

- **`vkGetPhysicalDeviceDescriptorSizeEXT` unthunked** — `VK_EXT_descriptor_buffer` gap in
  FEX. Crashes at/just after launch. Seen in No Man's Sky, Halo Infinite, Elden Ring.
- **id Tech 4 x87 FPU stack validation** — DOOM 3, BFG, Prey (2006) crash on map load
  ("FPU stack is not empty"). All id Tech 4 broken under FEX. id Tech 3 and 6+ are fine.
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
| a DLL fails to initialise / `LoadLibrary` fails | **`tools/wine-dll-loadtest.sh`** | It reports the *owning module* of the fault. On 2026-09-07 that instantly showed the crash was inside **Wine's** `MSVCP140.dll`, not our code — after three confident wrong diagnoses |
| **kill or wait on processes by name** | **`tools/safe-proc.sh {list\|wait\|kill} <pattern>`** | `pgrep -f` / `pkill -f` match **your own shell**, because the pattern is in its command line. This happened **three times** in two days — twice *after* a rule was written forbidding it. Never use bare `pkill -f`/`pgrep -f` here |

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

## Git / committing

Commit only when asked. Match the existing terse, result-oriented message style, e.g.:
`Add <Game> — <one-line outcome>` or `Add <N> games, <what changed>`. Already on `main`;
this is a personal log, so committing directly to `main` is the established pattern. Push is
to a **public** GitHub repo — confirm before pushing.
