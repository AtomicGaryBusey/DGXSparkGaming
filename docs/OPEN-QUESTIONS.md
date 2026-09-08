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
| **Prey (2006) LAUNCHES under Box64 with the four-symbol fix** — GL context created, session initialised, full engine init; only a CD-key *path* issue remains | `evidence/2026-09-08-steamclient-init-box64/prey-launch-milestones.txt` | high |
| **Quake 4 (id Tech 4) is playable under Box64** — menu, `game/airdefense1` loads, weapons work | `evidence/runs/2210-20260907-223229/`, human-confirmed | high |
| **The same title under FEX fails at `SetPixelFormat`** — no GL context, x87 assertion never fires | `evidence/runs/2210-20260907-225230/` | high |
| **Box64 writes the FSAVE tag word stack-relative, not physical** (`0xffc0` vs `0x03ff`); FEX is correct | `tools/isa-probe.sh`, reproducible in a bare 32-bit ELF | high |
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

### 4. Quake 4's 104 recurring access violations
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
