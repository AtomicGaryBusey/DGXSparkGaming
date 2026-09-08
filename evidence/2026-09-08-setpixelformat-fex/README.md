# `SetPixelFormat` fails under FEX — evidence

Backs the FEX half of the id Tech 4 entries in [`../../README.md`](../../README.md).

**This, not the x87 assertion, is FEX's actual id Tech 4 blocker.** In every controlled run the
assertion never fires; the engine dies earlier, at WGL pixel-format selection, and never creates
a GL context.

Documented to the `log-result` convention.

---

## 1. What was observed, without interpretation?

`tools/probes/wgl/wgl-pixelformat32.c`, a 32-bit Windows PE, replicating id Tech 4's WGL
sequence. Same Proton build, same prefix, same driver; only the translator differs.

| Step | Box64 | FEX |
|---|---|---|
| `RegisterClassA` / `CreateWindowExA` / `GetDC` | ok | ok |
| formats available | 320 | **320** |
| format 1 descriptor | `flags=0x00008025 cColorBits=32 cDepthBits=24` | **identical** |
| `ChoosePixelFormat` | → 1, ok | **→ 1, ok** |
| **`SetPixelFormat(chosen)`** | **ok** | **FAIL, `GetLastError=0`** |
| `wglCreateContext` | ok | FAIL, `2000` = `ERROR_INVALID_PIXEL_FORMAT` |
| `GL_VERSION` | `4.6.0 NVIDIA 580.173.02` | — never reached |
| `GL_RENDERER` | `NVIDIA GB10/PCIe` | — never reached |
| `SetPixelFormat(format 1)` on a fresh DC | ok | FAIL, `GetLastError=0` |

## 2. Does the thing measured belong to the claim?

Yes, and unusually tightly: this probe issues the *same calls in the same order* as the engine,
and the engine's own log says `PIXELFORMAT 1 selected` → `SetPixelFormat failed`. The probe
reproduces that exact pair, including on a fresh DC with format 1 explicitly.

Three things this rules out, each because the step **succeeded identically under FEX**:

- **Not the driver or ICD.** Both runtimes enumerate 320 formats with byte-identical
  descriptors for format 1.
- **Not format selection.** `ChoosePixelFormat` returns 1 under both.
- **Not the X11 connection.** FEX opens its host-side X11 display twice in this run and window
  and DC creation both succeed.

The failure is `SetPixelFormat` itself — where winex11 binds a GLX/EGL config to the window —
and `wglCreateContext`'s `ERROR_INVALID_PIXEL_FORMAT` is the correct downstream consequence of
no format having been set, not a second independent fault.

`GetLastError` being **0** on the failing call is itself informative: winex11 returns FALSE on
this path without calling `SetLastError`, which is why the engine can only report "failed".

## 3. What is the control?

**Box64, everything else held constant** — same probe binary, Proton, prefix, driver, display.
It completes the whole sequence and reports a real GL 4.6.0 context on `NVIDIA GB10/PCIe`.

The two runtimes **differ**, so by this project's two-runtime rule the translator is implicated
rather than the test. Had they failed identically, the probe would be the first suspect.

## 4. If it should change pixels, did anyone look?

Not applicable — the failure is before any rendering. Box64's side does prove a real context is
obtainable on this hardware, which is the relevant positive.

## 5. What would falsify this?

- The probe failing under **Box64 too** — that would make it a probe or environment bug.
- `SetPixelFormat` succeeding under FEX with a *different* format index, which would make it a
  format-specific issue rather than a path issue.
- The same failure appearing on **native x86-64 Linux** with this Proton, which would make it a
  Wine bug rather than a FEX one. **Not yet tested — no x86-64 Linux box here.** This is the
  most important untested alternative and the claim is scoped accordingly.

## 6. Evidence

| File | What it is |
|---|---|
| `wgl-probe-both-runtimes.txt` | Full output under FEX and Box64, back to back. |
| `../../tools/probes/wgl/wgl-pixelformat32.c` | The probe. Rebuild: `i686-w64-mingw32-gcc-win32 -O1 -o wglpf.exe wgl-pixelformat32.c -lopengl32 -lgdi32` |
| `../runs/2210-20260907-225230/` | Quake 4 under FEX hitting this in the wild (`SetPixelFormat failed` ×2). |
| `../runs/2210-20260907-223229/` | Quake 4 under Box64 getting a context and playing. |

## What this is good for

A ~130-line PE with no game, no Steam and no 100 GB install, reproducing in seconds what
previously took a ten-minute game launch to observe and could not be attributed. It is a
filable FEX reproducer as-is.

**Open:** which winex11 call inside `SetPixelFormat` fails, and why. `WINEDEBUG=+wgl,+x11drv`
under FEX is the next step and has not been run.
