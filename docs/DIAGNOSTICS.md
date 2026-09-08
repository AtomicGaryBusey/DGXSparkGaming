# Where the logs are, and how to make a game tell you why it died

Running x86-64 Windows games on ARM64 means a failure can come from any of six layers, and
each one writes its evidence somewhere different. This is the map. Most of it applies to
**any** Proton-on-ARM64 setup (Asahi, Snapdragon X, Ampere, Orange Pi), not just a DGX Spark.

If you take one thing from this page: **absence is evidence.** No engine log means the game
never reached its own config parser, which is a completely different failure from a crash
after startup — and it tells you which layer to look at next.

```
Windows game (x86-64 .exe)
  └─ Proton / Wine            → ~/steam-<appid>.log        (needs PROTON_LOG=1)
      └─ DXVK / VKD3D-Proton  → same log, "info:" / "warn:" lines
          └─ FEX or Box64     → stderr; Box64 prints [BOX64]/[BOX32] banners
              └─ native driver → dmesg (Xid), vulkaninfo
   the game itself            → its OWN log, wherever that engine puts it
   the launcher chain         → launch.log (pressure-vessel + proton stderr)
```

`tools/find-logs.sh <appid>` prints every one of these paths for a given title, marking
which exist. Start there.

---

## 1. The launcher chain — `launch.log`

**The most-missed file.** It holds pressure-vessel's and Proton's own stderr, *before* the
game exists. If Proton itself fails, this is the only place that says so.

We lost an hour to a Python traceback sitting in here while two other logs were being read:

```
FileNotFoundError: [Errno 2] No such file or directory:
  '.../steamapps/compatdata/<appid>/pfx.lock'
```

That is **not** lock contention. Proton creates `pfx/` inside `STEAM_COMPAT_DATA_PATH` but
not the directory itself — Steam normally does that. Launch Proton directly for a title
Steam has never run and you get this. Create the directory first.

Also expect harmless noise here: `pressure-vessel-wrap ... Internal error: <layer>.json is
not in /usr/lib/pressure-vessel/overrides/...` for every Vulkan layer on the host. Cosmetic.

## 2. Proton / Wine — `~/steam-<appid>.log`

Requires `PROTON_LOG=1`. **The next run of the same appid overwrites it**, so copy it
somewhere per-run or you will lose the ability to attribute a result. We did exactly that
and permanently lost the provenance of our most important crash.

Useful `WINEDEBUG` channels (comma-separated, `+` to enable):

| Channel | Shows |
|---|---|
| `+seh` | every exception dispatched, with registers and a backtrace |
| `+loaddll` | every DLL loaded, native vs builtin — how you spot a DRM wrapper |
| `+unwind` | SEH unwinding |
| `+debugstr` | `OutputDebugString` output from the game |
| `+steamclient` | Steam API shim |

`PROTON_LOG=1` enables a reasonable default set. Be aware `+seh` is verbose: 3,000+ lines
for a startup.

**A header-only log (≈16 lines, ending at `======`) means Wine never traced anything** — the
process died before or during Wine init. Look at `launch.log` instead.

## 3. Which translator actually ran it — the trap that cost us most

`binfmt_misc` decides who executes an x86 ELF. On our box **only Box64 is registered**;
FEX is not registered at all. So:

- launched from a shell **by path** → **Box64**
- launched via `FEXBash` / `FEXInterpreter`, or as a child of a process already inside FEX
  → **FEX**

Check it, never assume it:

```bash
readlink /proc/<pid>/exe          # /usr/bin/FEX or /usr/local/bin/box64
ls /proc/sys/fs/binfmt_misc/      # who is registered at all
```

Box64 announces itself with `[BOX64]` / `[BOX32]` lines on stderr; FEX's Vulkan thunk prints
`Linking address ...` and `Unknown Vulkan function ...`. Those banners are the only
incidental tell, and they are far too thin a thread to hang attribution on.

**We wrote up a whole play session as FEX when it had been Box64 throughout.** With
everything else held constant the two runtimes gave *opposite* results on the same game. If
your report does not name the translator, it is not a result.

## 4. The game's own log — by engine

This is the one people forget, and it is usually the most informative, because the engine
knows what it was doing.

| Engine | Log location | How to enable |
|---|---|---|
| **id Tech 4** (DOOM 3, Quake 4, Prey 2006, RoE, BFG, and licensee builds) | `<game>/<moddir>/qconsole.log` — beside the `.pk4` / `.resources` files, e.g. `base/`, `q4base/`, `preybase/`, `d3xp/` | `seta logFile "2"` in `<moddir>/autoexec.cfg`. **`2`, not `1`** — `1` buffers, and the crash eats exactly the lines you need. |
| **id Tech 3** (Quake III) | `<game>/baseq3/qconsole.log` | `+set logfile 2` |
| **Source** | `<game>/<mod>/console.log` | `-condebug` launch option |
| **Unreal 3/4/5** | `<game>/Saved/Logs/<Game>.log` inside the prefix or game dir | on by default; `-log` for a console window |
| **Unity** | `<prefix>/drive_c/users/steamuser/AppData/LocalLow/<Company>/<Game>/Player.log` | on by default |
| **RAGE / id Tech 5+** | varies | `+set logFile 2` where supported |

id Tech 4 in particular prints its **entire x87 FPU environment** one line before it dies —
control word, status word, tag word, instruction pointer, all eight ST registers, and a
decoded stack depth. This log went years without anyone turning that on. `tools/idtech4-prep.sh`
does it for you.

## 5. Crash dumps

- `<prefix>/drive_c/users/steamuser/Temp/` — Wine and most games drop `.dmp` here
- `<game dir>` — some engines write dumps beside the executable
- Wine tries `winedbg --auto` on an unhandled exception; if it can't start, you'll see
  `err:seh:start_debugger Couldn't start debugger` and only the `+seh` backtrace survives
- **Under FEX/Box64 a backtrace is often unsymbolizable JIT addresses.** The wchan census
  (`cat /proc/<pid>/wchan` per thread) is more useful for a hang than any backtrace.

## 6. GPU and kernel

```bash
sudo dmesg -T | grep -iE 'xid|oom|segfault'   # Xid = a real GPU fault
nvidia-smi --query-gpu=utilization.gpu,clocks.sm,power.draw --format=csv -l 1
vulkaninfo | grep -i <extension>              # is the extension even exposed?
```

GPU utilisation at **0% for a whole run** means it never rendered — which distinguishes
"crashed before the renderer" from "rendered then died". Be careful reading nonzero values:
a desktop compositor keeps the GPU busy, so nonzero alone does not prove the *game* rendered.

---

## Failure signatures we have actually hit

Each is a real, reproduced failure with the log line that identifies it. `tools/run-report.sh`
checks all of these automatically against a run's archived logs.

| Signature | Where | What it means |
|---|---|---|
| `Access violation in steamclient_init` | proton.log | The game uses the **legacy `Steam.dll` DRM wrapper**, which loads the *native* `steamclient.dll` instead of Proton's `lsteamclient.dll`. Seen on DOOM 3 and Prey (2006). Titles that use only `lsteamclient` are unaffected. |
| `SetPixelFormat failed` → `Unable to initialize OpenGL` | engine log | WGL pixel-format selection fails, so no GL context is ever created. Every id Tech 4 title we tested under **FEX** hits this; the same titles get a context under Box64. Accompanied by `Couldn't find proc address for: wglChoosePixelFormatARB` and friends. |
| `the FPU stack is not empty at the end of the frame` | engine log | id Tech 4's per-frame x87 check. **Read the tag word printed just above it** — `Sys_FPU_StackIsEmpty()` reads *only* that field. A tag word of `0xffc0` where hardware gives `0x03ff` is the same three registers written in stack-relative rather than physical order. |
| `Unknown Vulkan function ...` | stderr / proton.log | **Benign.** The Vulkan loader probing names it knows; `nullptr` is the correct answer for an unimplemented extension. Games that work fine emit it. Do not cite it as a cause — check a *working* title's log first (`tools/signature-check.sh`). |
| `EXCEPTION_FLT_INVALID_OPERATION` (`c0000090`) | proton.log | Unmasked FP exception. Seen on RDR2 during world load. |
| `This machine does not support the SSE2 Command Set` | game dialog | A CPUID probe rejecting the answer. Note the translator may well advertise SSE2 — check individual leaf-1 EDX bits, not just bit 26. |
| `Required WaveSize range [64, 64]` | proton.log (VKD3D) | AMD-only wave64 shaders. Not an ARM issue; fails on any NVIDIA GPU. |
| `Trying to join task from its thread would deadlock` | proton.log | GStreamer deadlock in Wine's media pipeline, usually an intro video. |
| header-only proton.log + traceback in launch.log | launch.log | Proton itself failed. Usually environment, not the game. |

---

## Reading a result honestly

Two rules that cost us published retractions before we adopted them:

1. **Before citing a log line as a cause, grep a title that WORKS for the same line.** Our
   most-cited Vulkan "failure signature" turned out to be emitted 16× by a game that runs
   perfectly. One command would have caught it at any point.
2. **Two runtimes are a truth oracle.** Different wrong answers ⇒ the translator is
   implicated. *Identical* wrong answers ⇒ suspect your test — two independent JITs rarely
   share a bug. (Ours once failed identically because the test clobbered its own jump
   target, and again because a missing directory killed both.)

Our runs record their own conditions in a `run.json` beside the archived logs —
`runtime_requested` vs `runtime_actual`, Proton version, container, executable, load at
start — so a claim can be traced to conditions rather than re-derived from memory later.
See [`tools/README.md`](../tools/README.md).
