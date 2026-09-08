# [32-bit] SetPixelFormat fails for every pixel format under Wine — no OpenGL context possible

**Repo:** FEX-Emu/FEX
**Version:** `fex-emu-armv8.4` 2607-1~n, `fex-emu-wine` 2608~1-3~n (Ubuntu PPA)
**Host:** NVIDIA GB10 (Grace-Blackwell), ARM64, Ubuntu, kernel 6.17, NVIDIA 580.173.02, Xwayland
**Guest:** Proton Experimental (`experimental-11.0-20260903b`), old WoW64 (`i386-unix` present)

## Summary

Under FEX, a **32-bit** Windows program running on Wine cannot set **any** pixel format, so it can
never create an OpenGL context. `SetPixelFormat` returns FALSE with `GetLastError() == 0`.

The same probe **built 64-bit works perfectly under FEX**, and the **32-bit build works under
Box64** on the same machine, same Wine, same prefix, same driver. So it is specific to FEX's
32-bit path.

## Measurement

`tools/probes/wgl/wgl-formatsweep32.c` in <https://github.com/AtomicGaryBusey/DGXSparkGaming>
enumerates the driver's formats and tries `SetPixelFormat` on each, using a fresh window per
format (the call is once-per-window):

| build | runtime | `SetPixelFormat` succeeded | `wglCreateContext` succeeded |
|---|---|---:|---:|
| 32-bit PE | **FEX** | **0 / 320** | **0** |
| 32-bit PE | Box64 | 320 / 320 | 320 |
| 64-bit PE | FEX | 320 / 320 | 320 |

So it is not a bad choice of format, and there is no format-selection workaround.

Everything *before* the failure is fine under FEX-32: 320 formats are enumerated,
`DescribePixelFormat(1)` returns `flags=0x00008025 cColorBits=32 cDepthBits=24` — byte-identical
to the working cases — and `ChoosePixelFormat` returns 1.

## Where it fails

With `WINEDEBUG=+wgl,+x11drv`, the working (Box64) and failing (FEX) traces diverge at exactly one
line inside winex11's `x11drv_surface_create`:

```
  both:  x11drv:create_client_window            0x2004e xwin 4e00003/480000d
  both:  x11drv:x11drv_client_surface_create    Created 0x2004e/... for client window 480000d
  both:  wgl:opengl_drawable_create             created 0x2004e/... (format 1)
  Box64: wgl:x11drv_surface_create              Created drawable ... with client window 4800011   <-- FEX never gets here
  FEX:   wgl:win32u_wgl_context_reset           ... No pixel format.
```

The client window and the `opengl_drawable` are both created; the step between that and the
success trace is the GLX drawable creation (`glXCreateWindow`). Wine returns FALSE without calling
`SetLastError`, which is why `GetLastError()` is 0. No X error, no `err:`/`fixme:` is logged.

## Things ruled out

- **Missing 32-bit GL thunk.** It is loaded. `/proc/<pid>/maps` of the failing 32-bit process
  contains `fex-emu/HostThunks_32/libGL-host.so`, `fex-emu/GuestThunks_32/libGL-guest.so`,
  and the real `libGLX_nvidia.so.580.173.02` / `libnvidia-glcore.so`. FEX derives the `_32`
  paths correctly even though `Config.json` names only the 64-bit directories.
- **Missing entry point.** `GuestThunks_32/libGL-guest.so` exports `glXCreateWindow`,
  `glXChooseFBConfig`, `glXGetFBConfigs`, `glXCreateContext`, `glXMakeContextCurrent`. It has 136
  `glX*` exports vs the 64-bit thunk's 140; the four extras are
  `glXEnumerateVideoCaptureDevicesNV`, `glXGetTransparentIndexSUN`, `glXGetVideoInfoNV`,
  `glXSendPbufferToVideoNV` — none reachable from this path.
- **A specific pixel format.** All 320 fail.
- **FEX's own GL-thunk workaround.** FEX ships `AppConfig/steamwebhelper.json` containing
  `"ThunksDB": {"GL": 0}` — *"Bypasses libGL's glX and instead sends GLX requests directly via
  xcb"* — for what looks like the same class of problem. Applying the same to `wine` **does not
  help**: still 0/320. The config demonstrably took effect (`libGL-guest.so` no longer appears in
  the process's `/proc/<pid>/maps`), and the 64-bit case still reached NVIDIA 4.6.0 through the
  xcb path, so 32-bit fails both *with* the libGL thunk and *without* it. Worth noting: with the
  thunk off the failing 32-bit process maps **no GL library at all**, even though the RootFS
  carries a full i386 NVIDIA stack (`libGLX_nvidia.so.580.173.02`, `libnvidia-glcore.so`, matching
  the host driver).
- **New WoW64 as a workaround.** With `WINEARCH=wow64` (which would route GL through the 64-bit
  thunk that works), **every** 32-bit PE segfaults immediately under FEX — including a pure Win32
  one that touches no GL — while a 64-bit PE in the same prefix runs fine. That looks like a
  separate FEX limitation and is why no workaround is offered here.

## Relationship to FEX-Emu/FEX#4645

This is almost certainly an instance of the open mega-issue
[#4645, "32-Bit X11 OpenGL thunking incompatibilities"](https://github.com/FEX-Emu/FEX/issues/4645),
which catalogues ~30 broken 32-bit GL titles. That issue collects per-game pass/fail on i3wm and
offers no reproducer or workaround. What is added here is a **game-free, deterministic measurement
of the Wine-side symptom** (0/320 vs 320/320), the exact winex11 trace line where it diverges, and
four eliminated hypotheses — on Xwayland/GNOME rather than i3, which that issue flags as
potentially significant.

## Impact

Every 32-bit OpenGL Windows game is unrunnable under FEX. Concretely: the whole id Tech 4 family
(DOOM 3, DOOM 3 BFG, Quake 4, Prey 2006) is 32-bit and OpenGL-only. Those titles log
`...PIXELFORMAT 1 selected` then `...SetPixelFormat failed` and abort. They run under Box64 on this
same machine, which is how the difference was isolated.

## Reproducer

`tools/probes/wgl/wgl-pixelformat32.c` (single format, verbose per-step `GetLastError`) and
`wgl-formatsweep32.c` (all formats). Both build with mingw-w64 and need no game:

```
i686-w64-mingw32-gcc-win32 -O1 -o fmt32.exe wgl-formatsweep32.c -lopengl32 -lgdi32 -luser32
FEXBash -c "WINEDEBUG=-all <proton>/files/bin/wine $PWD/fmt32.exe"
```

Neither shows a window, so they can be run on a machine someone is using.
