# Open questions, dead ends, and what to do next

The state of the investigation, as of **2026-09-08**. `README.md` records *results*; this
records *the work* — what is settled, what is open, what has been ruled out, and what the next
concrete step is for each.

Kept because the alternative is a session's task list, which dies with the session. Two probes
were rebuilt from scratch on 2026-09-07 because their existence was not written down anywhere.

---

## Settled, with evidence

| Finding | Evidence | Confidence |
|---|---|---|
| **Prey (2006) is PLAYABLE under Box64** — past the intro cutscene into gameplay, human-confirmed. Needs the four-symbol box32 fix plus one Steam-UI launch to provision the CD key | `evidence/2026-09-08-steamclient-init-box64/`, user-confirmed 2026-09-08 | high |
| **Quake 4 (id Tech 4) is playable under Box64** — menu, `game/airdefense1` loads, weapons work | `evidence/runs/2210-20260907-223229/`, human-confirmed | high |
| **The same title under FEX fails at `SetPixelFormat`** — no GL context, x87 assertion never fires | `evidence/runs/2210-20260907-225230/` | high |
| **Box64 writes the FSAVE tag word stack-relative, not physical.** Fixed by a rotate in `fpu_savenv`; verified `0xffc0`->`0x03ff`, 3- and 7-push cases, no regression on empty. **It does NOT explain the id Tech 4 crashes** — both games report `TOP=0`, where the rotation is a no-op | `evidence/2026-09-08-box64-x87-tagword/` | high for the bug; the id Tech 4 link was RETRACTED |
| **id Tech 4 crashes are genuine stranded x87 values** — 3 (Quake 4) and 7 (Prey) live registers at `TOP=0`, surviving the tag-word fix. Not one of the 16 classic leak patterns, all of which pass under both runtimes | `tools/probes/x87/leak.c`, Prey run with md5-verified fixed box64 | high — cause OPEN |
| **FEX 2607/2608 does not advertise CPUID leaf-1 DE/PSE**; fixed at fexsrc HEAD | `tools/isa-probe.sh` before/after a source build | high |
| **`vkGetPhysicalDeviceDescriptorSizeEXT` is not a failure signature** — emitted by working games | `tools/signature-check.sh 'DescriptorSizeEXT'` | high |
| **DOOM 3 / Prey `steamclient_init` AV is a Box64 bug — AND THE FIX IS VERIFIED (2026-09-08): 9→1 symbol errors, 2→0 Plt failures, 1→0 AVs** — four symbols missing from its box32 libc wrapper table (`arc4random`, `strfromf128`, `strtof128`, `strtold`) break `dlopen` of 32-bit `lsteamclient.so`, leaving `__wine_unixlib_handle=0` | `evidence/runs/3970-20260907-231525/`, box64 `2f130fab1` source, `notes/2026-09-08-ultracode-steamclient-init-dive.md` | high — every step re-verified locally |
| **SteamStub (`.bind` section with the EP inside it) is the discriminator, not the appinfo DRM key** — Prey/DOOM 3/RAGE have it, Quake 4 does not | PE headers, checked directly | high |
| **`game-run.sh` produced no telemetry for its entire life** — env never reached the game, and the distro MangoHud is arm64 | five runs, zero CSVs | high |

---

## Open, ranked by value

### 1. Which winex11 call inside `SetPixelFormat` fails under FEX?
**Narrowed 2026-09-08.** `tools/probes/wgl/wgl-pixelformat32.c` shows FEX enumerates all 320
formats and picks format 1 exactly as Box64 does, then `SetPixelFormat` returns FALSE **with
`GetLastError` unset**, and `wglCreateContext` reports `2000 ERROR_INVALID_PIXEL_FORMAT` as the
correct consequence. Driver, ICD, format selection and the X11 connection are all ruled out
because each step succeeds identically. Evidence:
`evidence/2026-09-08-setpixelformat-fex/`.

*Next step:* `WINEDEBUG=+wgl,+x11drv` under FEX with the same probe — it is seconds, not a game
launch. **Untested alternative that would change ownership entirely:** whether this also fails
on native x86-64 Linux with this Proton, which would make it a Wine bug rather than a FEX one.
No x86-64 Linux box here.

### 1b. Original framing (kept for the record)
**This, not x87, is FEX's actual id Tech 4 blocker.** Every title tested under FEX fails after
`PIXELFORMAT 1 selected`, and all the `wgl*ARB` entry points are missing
(`Couldn't find proc address for: wglChoosePixelFormatARB`).

*Next step:* a minimal 32-bit PE calling `ChoosePixelFormat`/`SetPixelFormat`/`wglCreateContext`,
reporting `GetLastError`, run under both JITs via `tools/run-both.sh --wine`. Cheaper than any
game launch, and it localises the fault to `opengl32`/`winex11` vs the thunk layer.

### 2. File the Box64 wrapper-table bug upstream, and test the fix
**Root-caused 2026-09-08 and narrow enough to fix:** four entries missing from
`src/wrapped32/wrappedlibc_private.h` in box64 v0.4.4. `strtold` is commented out at line 1754;
`arc4random`, `strfromf128` and `strtof128` are absent from `src/wrapped32/` entirely. All four
are present in the 64-bit table, and `strtold_l` *is* wrapped — which is why exactly four
symbols fail.

**RESOLVED 2026-09-08 — the fix works.** With the patched binary swapped into
`/usr/local/bin/box64` (the only path `binfmt_misc` uses inside the container), Prey's run went
from 9 symbol errors / 2 `libstdc++` Plt failures / 1 AV to **1 / 0 / 0** — the remaining one
being `closefrom` in `libgpg-error`, unrelated. Evidence:
`evidence/2026-09-08-steamclient-init-box64/verification-patched-box64-2026-09-08.txt`.
**Remaining work: file it upstream**, and note honestly that this unblocks the DRM layer rather
than the game — Prey still did not reach its engine config in 150 s under the patched build.

**The near-miss, kept because it is instructive.** The patched box64 was built
(`tools/build-box64-symfix.sh`) and Prey was run against it. The errors and the AV were
unchanged — but **that run tested nothing**: the game executes inside pressure-vessel, and once
that container namespace exists every exec goes through `binfmt_misc`, whose interpreter is
hard-wired to `/usr/local/bin/box64`, the *stock* build. `BOX64_BIN` only affects the first
process (`reaper`). Recorded here because a run like that looks exactly like a failed fix and
would be easy to mis-file as a refutation.

Isolating it outside the container fails too: the missing symbols are only fatal under
`dlopen(RTLD_NOW)`, which is what Wine does and what an ordinary program load does not. Loading
the container's i386 `libstdc++` directly under either build produces no errors at all.

*Next step, and it needs root:*
```
sudo cp /usr/local/bin/box64 /usr/local/bin/box64.stock-backup
sudo cp ~/dgx-gaming-work/box64-symfix/bin/box64 /usr/local/bin/box64
tools/ab-runtime.sh 3970 150 && tools/run-report.sh --appid 3970
# revert: sudo cp /usr/local/bin/box64.stock-backup /usr/local/bin/box64
```
PASS = zero `Symbol ... not found` and zero `steamclient_init` AV. FAIL = the chain is wrong and
the README entry must be corrected in place. Affects **any** 32-bit Steam title whose unix-side
helper pulls in `libstdc++`, which is a much wider set than id Tech 4.

*Also still worth testing:* the `NO_STEAM_API=1` bypass, as a workaround that needs no Box64
rebuild. Costs: no overlay, achievements, cloud saves or playtime.

### 2b. Does the `.bind` rule generalise past the 2004-2009 id titles?
The rule established on 2026-09-08 is: **entry point inside a `.bind` section ⇒ SteamStub ⇒ the
stub loads `Steam.dll` at runtime ⇒ Proton redirects to `lsteamclient` ⇒ Box64's missing symbols
kill it.** Confirmed for Prey, DOOM 3 and RoE; Quake 4 has no `.bind` and is unaffected.

**RAGE (9200) is the live test.** It is 32-bit with a `.bind` section and its EP inside it, but
has *no* `legacykey*` keys and statically imports `steam_api.dll`. Until it is run, scope
"EP in `.bind` ⇒ loads `Steam.dll`" to the legacy id titles. Still unknown: which instruction in
`.bind` calls `LoadLibrary`, and with what path string.

### 3. Which id Tech 4 titles work under Box64?
**Two for two so far.** Quake 4 plays; Prey now launches and initialises fully with the box32
fix in place. Note the fix is NOT in the packaged box64 — `/usr/local/bin/box64` was reverted to
stock after testing, so reproducing Prey needs the swap again until it lands upstream.
Quake 4 does. DOOM 3, RoE, Prey, BFG, Phobos, Wolfenstein 2009, Riddick, Brink and the two
dhewm3 forks (Quadrilateral Cowboy, Skin Deep) are installed and armed but untested.

*Next step:* `tools/ab-runtime.sh <appid> 150` per title. **Skin Deep is the only 64-bit member**
(`PE32+ x86-64`) and is therefore the sole test of whether any of this is 32-bit-specific —
DOOM 3 BFG was assumed to be 64-bit and is not.

### 4. The odd mouse behaviour in Prey and Quake 4 — STILL OPEN (the fault beside it is solved)
**Leading candidate, 2026-09-08, and it is our own fault:** the display is **5120x1440** and
`tools/idtech4-prep.sh` hardcoded `r_customWidth 2560`, so both games created a "fullscreen"
window over the **left half of the screen** (`...created window @ 0,0 (2560x1440)` in both
`qconsole.log`s). Wine decides whether a window is fullscreen by comparing its rect to the
monitor rect, so a half-width window is not fullscreen to Wine and the pointer is not confined
the way an exclusive-mode DirectInput game expects. The prep tool's own header warns that a
small window gets mistaken for broken mouse capture — and then created that condition.

`idtech4-prep.sh` now detects the display, picks the nearest id Tech 4 aspect, and refuses to
be quiet when the window does not match the screen. Both games re-armed at 5120x1440.
**NOT YET CONFIRMED as the fix** — it needs one launch and a human hand on the mouse.

If it is not the whole answer, the apparatus is now built rather than improvised:
`tools/mousefeel.sh` measures DirectInput (exclusive+relative+buffered, exactly what the engine
asks for) against Win32 raw input over the same movement, and `tools/wine-mouse-knobs.sh` A/Bs
`GrabPointer` / `GrabFullscreen` / `MouseWarpOverride`, all three of which are unset here.

A note on why the earlier probe missed this: it used `DISCL_NONEXCLUSIVE | DISCL_BACKGROUND`
and read the device once. id Tech 4 uses `DISCL_EXCLUSIVE | DISCL_FOREGROUND` with
`DIPROPAXISMODE_REL` and a 256-entry buffer. "DirectInput is clean" was a true statement about
code the games never execute.

**RESOLVED 2026-09-08 — the recurring fault, but NOT the mouse.** The `c0000005` faults that
sat next to this question are a Box64 bug with a 200-line reproducer and nothing to do with
input: `NtCreateFile` with `FILE_CREATE` returning `STATUS_OBJECT_NAME_COLLISION` faults under
box32 and the caught fault replaces the status, so the app gets `ERROR_NOACCESS`. FEX clean,
64-bit clean, stock v0.4.4 affected. See `notes/box64-bug-3-ntcreatefile-collision.md` and
`tools/probes/namedobj/`. The counts (Prey 276, Quake 4 124) are just how many file/directory
creations each game makes against paths that already exist.

**What is still open is the mouse itself**, and it now has *no* candidate explanation — both
the ones this entry carried are gone. History below, because the way it went wrong is the point.

**Mislabelled until 2026-09-08.** It was called an "input-path" fault because it first appears
near DirectInput initialisation and both games have odd mouse behaviour. `tools/probes/dinput/`
tested that directly and **refuted it**: a 32-bit PE that creates DirectInput 8, enumerates
`DI8DEVCLASS_ALL` three times, then creates/configures/acquires the mouse and keyboard and reads
both state and buffered data, returns `DI_OK` at every step and produces **zero** faults.

What is actually established:

| | |
|---|---|
| shared | same address in both games — `ntdll.so+0x71f0`, reading `0x7c` (null+0x7c) |
| counts | Prey 92, Quake 4 41 |
| shape | **periodic bursts** of 10–20, separated by 60–80 s — *not* per-frame, so not mouse polling |
| thread | the game's **main** thread, which does everything, so that narrows nothing |
| context | `info[0]=0` (a read), `eax=c0000035` (`STATUS_OBJECT_NAME_COLLISION`, a returned status), `edi=4` |

Both games ship **PunkBuster** (`pb/`: Prey 6 files, Quake 4 7 files) and PunkBuster scans
periodically, which fits the burst cadence. But Prey logs two Authenticode decode failures
(`CryptDecodeObjectEx` on `1.3.6.1.4.1.311.2.1.4`) and **Quake 4 logs none**, so that specific
link is not shared and the hypothesis is not established.

**Whether this fault relates to the mouse symptom at all is unknown.** They were correlated only
by appearing in the same sessions. The mouse behaviour may be an ordinary Wine relative-mouse or
cursor-clipping issue with no connection to these faults.

*Next step:* stop inferring from adjacency. Either bisect by moving `pb/` aside and re-running
(cheap, one launch, directly tests the PunkBuster hypothesis), or get a symbolised backtrace for
`ntdll.so+0x71f0` rather than guessing at the caller.

`ntdll.so + 0x71f0`, faulting address `0x7c` (null + 0x7c), on one thread, starting at input
init after repeated `hid.dll` load/unload, recurring for the whole session. Correlates with the
user reporting mouse movement confined to a narrow region.

### 5. NBA 2K27 without EAC
`appinfo.py` shows launch entry `[3]` = `NBA2K27.exe`, type `option1`, *"NBA 2K27 without EAC
(offline only)"* — publisher-supplied, 107 GB already installed, never attempted.
*Next step:* `LAUNCH_OPTION=option1 tools/game-run.sh 4356430`.

### 6. No Man's Sky, Halo Infinite, Elden Ring
**Undiagnosed.** Their previous root cause was retracted and no replacement is offered.
*Next step:* `PROTON_LOG=1 VKD3D_CONFIG=vk_debug VKD3D_DEBUG=warn
VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation` in the Steam launch options — vkd3d-proton's own
documented recipe — then read the real error.

---

## Dead ends — do not re-tread

| Idea | Why it is dead |
|---|---|
| `vkGetPhysicalDeviceDescriptorSizeEXT` as a root cause | Emitted 16× by Cyberpunk 2077 and 4× by Daikatana, both of which run fine. The driver *does* expose `VK_EXT_descriptor_buffer`. |
| "FEX fabricates the x87 tag word" | Refuted by three freestanding probes. FEX is correct in 32- and 64-bit, including the `FXSAVE` abridged→full reconstruction. |
| "Wine's CONTEXT conversion breaks id Tech 4" | `Quake4.exe` imports neither `AddVectoredExceptionHandler` nor `SetThreadContext`. |
| "The 828 `OutputDebugString` exceptions are the trigger" | The probe handles that exact call correctly; a `+seh` trace confirms the exceptions really dispatched. |
| Patching out id Tech 4's FPU assertion | The assertion does not fire under either JIT any more. Patching it would achieve nothing. |
| "Burnout fails because SSE2 isn't advertised" | FEX advertises `sse2`. It does not advertise `de`/`pse`, and upstream FEX PR #5807 reports Burnout reads the **DE** bit. |
| DOOM 3 BFG as the 64-bit discriminator | It is `PE32 / Intel 80386` — 32-bit. Use Skin Deep. |
| Cross-testing on another Spark | Identical silicon, driver and OS image; only disk capacity differs. Re-measures the same variables. |

---

## Corrections this project has published

Kept visible on purpose — the wrong version and *why* it was wrong is the most useful content
here.

1. **"3,983 evaluates, DLSS 5 NR running every frame"** — committed and pushed. The counter was
   the *generic* NGX evaluate hook carrying the game's own DLSS-SR. The NR-specific line occurred
   **twice**. Caught by a human toggling the feature and seeing an identical image.
2. **`descriptor_buffer` as the cause of three AAA crashes** — carried for months, refuted in one
   `grep` against a working game's log.
3. **A play session attributed to FEX that was Box64 throughout** — `binfmt` decides, and nothing
   recorded it. Now every run writes `runtime_actual`.
4. **DOOM 3 BFG recorded as 64-bit** — it is 32-bit.
5. **"Burnout's CPUID check doesn't detect SSE2"** — it does; DE/PSE are the missing bits.

The pattern in all five: **a real observation, interpreted without a control.** The mechanisms
now in place — `signature-check.sh`, `run-both.sh`, `run.json`, the `log-result` skill — exist to
make each specific mistake structurally hard to repeat.

---

---

## Deferred re-tests (the README's `TODO:` markers, indexed)

Fourteen `TODO:` markers are scattered through a 2,700-line `README.md`, which means nobody
sees them. None are stale; they are all genuine deferred work. Indexed here so they compete
for attention with everything else rather than hiding.

**Most are now cheaper than when they were written**, because `tools/game-run.sh` records
conditions in `run.json` and `tools/ab-runtime.sh` runs both translators in one command — so a
"re-test" is one command plus a `tools/run-report.sh`, not a manual session.

| README line | Title | Deferred work |
|---|---|---|
| `830` | — | ** check whether |
| `899` | — | ** re-run pinned to `proton_11` to confirm it |
| `944` | — | ** re-test properly with ReShade as `dxgi.dll` in a real DX12 title. |
| `1066` | — | ** re-run it as |
| `1204` | — | ** once a native ARM64 Steam client exists, redo this head-to-head on one CPU-bound title |
| `1224` | — | ** repeat on a second title (Esoteric Ebb |
| `1942` | Crysis 2: Game of the Year | ** Investigate audio issue. |
| `1944` | Crysis | ** Retest at 5120x1440 ultrawide. |
| `1946` | Far Cry 2 | ** Retest to find optimal settings balance. |
| `1959` | Left 4 Dead | ** Retest with lower settings to find optimal balance. |
| `1970` | PEAK | ** Retest with DX11/DX12 renderer — may be more stable via DXVK/VKD3D. |
| `1983` | Space Engineers | ** Retest with High preset instead of Photo/Extreme to find stable ceiling. |
| `2088` | Quake 4 | ** 104 recurring access violations at `ntdll.so + 0x71f0` (faulting address `0x7c`) begin at input init and run the whole session; the user reported m |
| `2650` | — | Iterate launch options:** |

Highest value of these, because it is a *correctness* question rather than a tuning one:
line 899 (re-run pinned to `proton_11` and read the compat tool from `config_info` rather than
trusting intent) and line 1224 (a second title before believing a one-data-point regression).

---

## Infrastructure still owed

- **`NO_STEAM_API=1`** in `game-run.sh` (blocks open question 2).
- **A `SetPixelFormat` probe** (blocks open question 1).
- **Frametime numbers for 32-bit/OpenGL titles.** Ubuntu ships no i386 MangoHud, so those titles
  currently have no CSV path at all — `com_showFPS` plus `tools/watch-run.sh` is the fallback.
- **The `CONTEXT` block in `workflows/*.js` goes stale.** Refresh from `tools/check-stack.sh`
  before re-running any of them.

### Does 32-bit OpenGL work under FEX? Daikatana says yes, measurement says no — OPEN

Flagged 2026-09-08. Two claims in this repo contradict each other and one of them is wrong:

- `tools/probes/wgl/wgl-formatsweep32.c` measures FEX setting **0 of 320** pixel formats for a
  32-bit Wine program (Box64: 320/320; a 64-bit build under FEX: 320/320). Confirmed with the
  window both **mapped and unmapped**, so it is not an artifact of the probe hiding its window.
  Quake 4 fails the same way in a real run.
- README records **Daikatana** — 32-bit, `ref_gl.dll`, which imports `SetPixelFormat` /
  `ChoosePixelFormat` / `wglCreateContext` — as running **excellently** "through FEX's 32-bit path".

The Daikatana runs (`~/dgx-gaming-work/runs/242980-*`) **predate `run.json`**, so they carry no
`runtime_actual` and no Proton log — only `gpu.csv` and `launch.log`. That is exactly the era in
which this log mis-attributed a Box64 run to FEX, which is why the row is now flagged rather than
trusted. It is also possible the run used a non-GL backend (the game ships `3dfxgl.dll` and
`pvrgl.dll` as well).

*Next step:* `tools/ab-runtime.sh 242980` — one command, runs it under both and records
`runtime_actual`. **Until that is done, do not use Daikatana as evidence either way**, and do not
weaken the 0/320 measurement on the strength of it.

### How much of this repo transfers to the RTX Spark? — OPEN, and the honest answer is "less than it looks"

Raised 2026-09-08 while planning the Spark Game Launcher. Windows-on-ARM runs x86-64 through
Microsoft's **Prism**, not FEX-Emu or Box64. Every translator finding in this log — the four
Box64 bugs, FEX's 32-bit GLX failure, the x87 tag-word work, the `a3`-store duplication — is a
fact about a translator that will not be running on that machine.

Expected to carry: the method, the per-title profile structure, GPU/driver-layer behaviour, and
`tools/isa-probe/` (whose expected answers come from the Intel SDM, so it is a valid test suite
for *any* x86 implementation — including Prism, on day one).

*Cheapest experiment when hardware exists:* run `tools/isa-probe/` under Prism. It needs no game,
no GPU and no install, and it would immediately say whether Prism shares any of the x87/CPUID
defects found here. Until then, do not write anything in this repo that implies the translator
findings apply to RTX Spark. See `docs/SPARK-PLATFORM.md`.

### id Tech 4 fullscreen at a wide native mode: ChangeDisplaySettings ACCESS-VIOLATES — CONFIRMED

Measured 2026-09-08, Prey (3970), Box64, Proton Experimental, 5120x1440 display.

Setting `r_customWidth 5120 / r_customHeight 1440 / r_fullscreen 1` makes the engine call
`ChangeDisplaySettings`, which fails:

```
...calling CDS: failed, unknown error -1073741819      <- 0xC0000005, access violation
...trying next higher resolution:
```

and the engine then spins forever in that fallback loop. **The mode is valid** — `xrandr` lists
`5120x1440` — so it is the CDS *call* that faults, not the mode. At 2560x1440 the same call
succeeds, which is why every earlier run worked.

Windowed avoids the call entirely but produces a **5128x1474** decorated window (borders + title
bar), *larger* than the 5120x1440 screen, which the window manager reports as unresponsive.

`tools/idtech4-prep.sh` now picks the largest mode id Tech 4 can express (4:3 / 16:9 / 16:10) that
*fits* the display, rather than the native one. `NATIVE=1` forces native and is expected to hang —
kept for retesting after a Wine or Box64 update.

*Not yet investigated:* whether this is a Wine bug, a Box64 bug, or a driver limit. `run-both.sh`
cannot answer it — FEX cannot run 32-bit OpenGL at all.

### Prey blocks in the Steam API handshake before engine init — INTERMITTENT, open

Observed twice on 2026-09-08. `prey.exe` starts, burns ~3.5 s of CPU, then parks on
`futex_do_wait` with **one thread**; a live id Tech 4 process has 10+. No `qconsole.log` is ever
created, so it never reached `autoexec.cfg`. Every Wine service around it is healthy
(`services.exe`, `winedevice.exe`, `rpcss.exe`, `explorer.exe`, `xalia.exe`), and Proton's
`steam.exe` stub sits in `futex_wait_multiple`.

Intermittent: a run 20 minutes earlier reached `--- Common Initialization Complete ---` with the
same binary and prefix. Launching from the Steam UI has always worked.

Likely related to pending work on `NO_STEAM_API` (bypassing the legacy Steam DRM path). **Not
root-caused, and deliberately not attributed to any of the geometry changes made that evening.**

### The mouse anomaly: the INPUT PATH IS EXONERATED — measured 2026-09-08

Settled with `tools/mousefeel.sh`, using an X-server control that bypasses Wine entirely.

| | travel \|x\| |
|---|---:|
| DirectInput, summed over all phases (exclusive + relative + buffered, exactly what id Tech 4 asks for) | **40,171** |
| X server, RAW device delta | **40,233** |
| X server, accelerated delta | 97,341 |

**DI / X-raw = 0.9985 — 0.15% apart.** DirectInput is delivering the raw device deltas faithfully.
(X is marginally higher because the X capture runs for the whole script including the gaps between
phases, while DI counts only during them.) Supporting readings, all clean:

- **STILL phase: 0 DI events** with the ball untouched → no spurious motion, so **warp feedback is
  ruled out**. This reading needs no control to be valid.
- `ovf 0`, `lost 0` in every phase → nothing dropped, no lost acquisitions.
- `max|dx|` 24–27 on flicks, consistent with raw deltas at a high poll rate → **no clamping**.

**Therefore all of these are dead**, and none should be revisited without new evidence: window
geometry / fullscreen heuristics, pointer confinement, warp feedback, DirectInput rescaling, and
any FEX/Box64 involvement. Four launches were spent on the geometry theory and it was wrong.

**What the measurement DID turn up.** The compositor applies **2.42x acceleration** to the desktop
pointer, while the game correctly receives **1:1 raw** motion. That is correct behaviour — games
want raw deltas — but it means moving from desktop to game is a 2.4x sensitivity discontinuity.
On a **trackball** (this machine's pointer is a CST Laser Trackball, whose profile is long fast
spins and abrupt stops) that is a plausible source of "feels odd" with no bug anywhere.

Also worth recording: `xinput list` shows **no physical trackball in X at all** — only
`xwayland-pointer` and `xwayland-relative-pointer`. Under Xwayland, mutter owns the device and
synthesises a pointer, so the chain is
`trackball → libinput → mutter (accel) → Xwayland → Wine → DirectInput → game`.

*Remaining candidates, in order:* engine-side `m_smooth 1` and `sensitivity 5` (both games are at
stock defaults); frame-timing interaction; and the desktop-vs-game acceleration discontinuity
above. **Cheapest next test:** set `m_smooth 0` in `autoexec.cfg` and play a minute — one variable,
no rebuild, instantly reversible.

*Note on the control:* Wine's own raw input is unusable as a control here. With `RIDEV_INPUTSINK`
it logs `NtUserRegisterRawInputDevices Unhandled flags 0x230` and delivers nothing; with `flags=0`
it still delivers nothing while DirectInput receives ~15,000 events. `mousefeel.sh` now uses
`xinput test-xi2 --root`, which reports both accelerated and raw deltas from outside Wine.

### How four launches failed to test this (kept, because the process failure is the lesson)

The 2026-09-08 session set out to test the "window narrower than display breaks pointer
confinement" hypothesis. It never did. Four launches, four unrelated failures: CDS access
violation (fullscreen native), oversized 5128x1474 window (windowed native), Steam handshake hang
(borderless native), Steam handshake hang again (**windowed 1920x1080** — a benign config, which
is what proves the last two were not geometry at all).

**The lesson is the point.** The hypothesis came from a single log line — `created window @ 0,0
(2560x1440)` — and was never measured. `tools/mousefeel.sh` was built *for this exact question*
days earlier and was not run, twice after explicitly saying it would be the next step.

*Next step, and it is not negotiable:* `tools/mousefeel.sh` on the restored working config, before
any further geometry change. It reads DirectInput in the game's exact mode against Win32 raw input
over the same movement; the DI/RAW ratio says whether the input path is at fault at all.
