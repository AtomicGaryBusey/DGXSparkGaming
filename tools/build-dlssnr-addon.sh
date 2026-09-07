#!/usr/bin/env bash
# build-dlssnr-addon.sh — build dlssnr-linux.addon64 from source, no sudo.
#
# WHY THIS EXISTS
#   The DLSS-5 Neural Rendering add-on is the only piece of Path A that cannot be
#   hand-rolled: it encodes the NR creation/evaluate parameter protocol, which is
#   undocumented (no public NR SDK exists — Streamline tops out at 2.12.0). A
#   hand-written harness got as far as loading the snippet and then stalled on
#   0xBAD00005 forever, because guessing ~61 parameters does not converge.
#
#   The upstream project's install-deps.sh wants `sudo apt-get install` plus
#   piping https://apt.llvm.org/llvm.sh to root, to build a repo that was days
#   old. Declined. This fetches everything from official archives into a local
#   prefix instead. Nothing is installed system-wide.
#
#   Four gotchas, each of which cost a build cycle:
#     1. clang-18 CANNOT build it — MSVC's STL hard-errors with
#        "STL1000: expected Clang 19.0.0 or newer". clang-20 is in Ubuntu's own
#        archive; use it rather than the _ALLOW_COMPILER_AND_STL_VERSION_MISMATCH
#        escape hatch.
#     2. `xwin splat` alone does nothing — it only processes already-downloaded
#        packages. The sequence is download -> unpack -> splat.
#     3. ReShade bundles the exact ImGui it demands (external/reshade/deps/imgui);
#        reshade_overlay.hpp hard-errors on IMGUI_VERSION_NUM != 19250.
#     4. The generated shader headers must land in <src>/build/shaders/, which is
#        where the sources #include them from.
#
#   Verified output: 242,176 bytes — byte-identical in size to the upstream
#   release, corroborating that their binary matches their published source.
#
# Prereqs: tools/setup-mingw.sh (for objdump), box64, gh, git, python3.
# Layout is under ~/dgx-gaming-work/addon-build by default.
# Build dlssnr-linux.addon64 with locally-unpacked toolchain. No sudo.
set -uo pipefail
W="$HOME/dgx-gaming-work/addon-build"
SRC="$W/src"; OUT="$W/out"; mkdir -p "$OUT/shaders" "$OUT/detours-obj"
CLANGXX="$W/clang20/root/usr/bin/clang++-20"
XWIN="$W/xwin-sdk"
RENODX="$W/renodx"
RESHADE_INC="$RENODX/external/reshade/include"
NGX_INC="$RENODX/external/DLSS/include"
DETOURS_SRC="$RENODX/external/Detours/src"
DXC=$(find "$W/dxc" -name dxc -type f | head -1)
DXCLIB="$(dirname "$(dirname "$DXC")")/lib"

CFLAGS=(-target x86_64-pc-windows-msvc -fuse-ld=lld -O2
  -isystem "$XWIN/crt/include" -isystem "$XWIN/sdk/include/ucrt"
  -isystem "$XWIN/sdk/include/um" -isystem "$XWIN/sdk/include/shared")
LDFLAGS=(-L "$XWIN/crt/lib/x86_64" -L "$XWIN/sdk/lib/um/x86_64" -L "$XWIN/sdk/lib/ucrt/x86_64")

echo "=== [1/3] shaders (dxc via box64) ==="
for sh in nr_encode nr_resolve nr_lum1 nr_lum2; do
  hlsl="$SRC/src/shaders/$sh.hlsl"
  [ -f "$hlsl" ] || { echo "  MISSING $hlsl"; continue; }
  LD_LIBRARY_PATH="$DXCLIB" box64 "$DXC" -T cs_6_0 -E main -O3 \
      -Fo "$OUT/shaders/${sh}_dxil" "$hlsl" 2>&1 | head -3
  if [ -s "$OUT/shaders/${sh}_dxil" ]; then
    python3 -c "
d=open('$OUT/shaders/${sh}_dxil','rb').read()
open('$OUT/shaders/${sh}_dxil.h','w').write('unsigned char ${sh}_dxil[] = {'+','.join(str(b) for b in d)+'};\n')"
    echo "  $sh -> $(stat -c%s "$OUT/shaders/${sh}_dxil") bytes DXIL"
  else echo "  $sh FAILED"; fi
done

echo "=== [2/3] detours ==="
for tu in detours modules disasm; do
  [ -f "$OUT/detours-obj/$tu.obj" ] && { echo "  $tu cached"; continue; }
  "$CLANGXX" -c -std=c++17 "${CFLAGS[@]}" -w -D_CRT_SECURE_NO_WARNINGS \
    -I "$DETOURS_SRC" -o "$OUT/detours-obj/$tu.obj" "$DETOURS_SRC/$tu.cpp" 2>&1 | head -5
  [ -f "$OUT/detours-obj/$tu.obj" ] && echo "  $tu ok" || echo "  $tu FAILED"
done

echo "=== [3/3] addon ==="
"$CLANGXX" -std=c++20 "${CFLAGS[@]}" -shared -o "$OUT/dlssnr-linux.addon64" \
  -I "$SRC/src" -I "$OUT/shaders" -I "$RESHADE_INC" -I "$RENODX/external/reshade/deps/imgui" -I "$NGX_INC" -I "$DETOURS_SRC" \
  "$SRC/src/addon.cpp" "$OUT/detours-obj"/*.obj \
  "${LDFLAGS[@]}" -luser32 -lkernel32 -lgdi32 -ld3d12 -ldxgi -ldxguid 2>&1 | head -25
echo "=== result ==="
ls -la "$OUT/dlssnr-linux.addon64" 2>/dev/null || echo "  BUILD FAILED"
