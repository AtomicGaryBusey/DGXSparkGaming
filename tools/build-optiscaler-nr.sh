#!/usr/bin/env bash
# build-optiscaler-nr.sh — build OptiScaler-with-DLSS5-Neural-Rendering on Linux/ARM64, no sudo.
#
# WHY THIS EXISTS
#   The DLSS 5 NR add-on this project already builds is a *ReShade* add-on, and on 2026-09-06 a
#   four-layer bisection proved ReShade ALONE deadlocks Cyberpunk 2077 on this rig (same save and
#   scene run clean without it). So the add-on's host is the blocker, not DLSS. OptiScaler is a
#   different injector -- it proxies dxgi/winmm/version/d3d12 directly and never loads ReShade.
#
#   Upstream OptiScaler has NO neural-rendering support (`grep -ri dlssnr` over the official tree
#   returns nothing; its only DLSS-5 mentions are jokes in the menu strings). NR lives in community
#   forks. This builds one of them FROM SOURCE rather than running a stranger's prebuilt DLL:
#     https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass   (GPL-3.0)
#   Verified before use: its OptiScaler base files are byte-identical to upstream, and all 28
#   bundled FidelityFX/d3dx .lib blobs match upstream byte-for-byte (the other 2 are NVIDIA's own
#   nvapi libs from NVIDIA/nvapi). It bundles no NR model -- you supply that yourself.
#
#   THE MODEL IS NOT SHIPPED AND MUST NOT BE DOWNLOADED FROM A DISCORD. Use the retail
#   `nvngx_dlssnr.dll` (310.8.0.0) from an owned copy of NBA 2K27:
#     steamapps/common/NBA 2K27/data/streamline/nvngx_dlssnr.dll
#
# WHY IT IS NOT JUST "RUN MSBUILD"
#   OptiScaler is an MSVC v143 solution with no CMake, and its CI is windows-latest + msbuild.
#   There is no Linux build path upstream. This replaces MSBuild with clang-20 + xwin (the same
#   toolchain tools/build-dlssnr-addon.sh already sets up) and lld-link. 199 sources compile with
#   ZERO changes to OptiScaler's own logic; everything below is a portability fix, each one a
#   place where MSVC is lax and clang follows the standard.
#
# THE EIGHT FIXES (each cost a build cycle to find)
#   1. -std=c++latest is MSVC syntax -> use -std=c++23.
#   2. clang's OWN intrinsic headers must precede xwin's crt/include. MSVC declares _mm_* as
#      extern functions (its compiler implements them), so MSVC's xmmintrin.h makes clang emit
#      calls to _mm_rsqrt_ss that exist in no import library. This one only bites code using SSE.
#   3. Case sensitivity, twice. Windows does not care; Linux does. `Config.h` vs `config.h`,
#      `Dxgi_Proxy.h` vs `DXGI_Proxy.h`, `bcds_*.h` vs `BCDS_*.h`, and lowercase SDK libs
#      (dbghelp.lib, version.lib). Fixed with symlink shims, NOT by editing their source.
#      Relative includes need shims next to the including file, not just on the include path.
#   4. -DUNICODE -D_UNICODE: the code passes L"..." to GetModuleHandle/LoadLibrary, which resolve
#      to the ANSI variants otherwise. MSVC projects set these by default.
#   5. -D_CRT_USE_BUILTIN_OFFSETOF: the UCRT's offsetof uses reinterpret_cast, which is not a
#      constant expression, so imgui's IM_STATIC_ASSERT(offsetof(...)) fails.
#   6. -fms-runtime-lib=dll: the bundled FidelityFX libs are MD_DynamicRelease; without this
#      clang defaults to MT and lld rejects the RuntimeLibrary mismatch.
#   7. NVIDIA's sl_pcl.h has a latent bug: under `#if __cplusplus == 202302L` it does
#      `using to_underlying = std::to_underlying;` -- a type alias to a FUNCTION TEMPLATE, invalid
#      C++. MSVC never reaches it because MSVC reports __cplusplus == 199711L unless
#      /Zc:__cplusplus is passed (it gates its C++23 STL on _MSVC_LANG instead). Clang reports
#      202302L honestly and hits it.
#   8. Four linkage/lookup issues MSVC tolerates: an in-class `inline static` of a nested type
#      (evaluates the nested type's initialisers while the enclosing class is incomplete);
#      `static` definitions that follow an `extern` declaration (from a header, or from the
#      VALIDATE_HOOK macro) which therefore do NOT get internal linkage and collide at link time;
#      a constexpr HMODULE built by casting an integer (a reinterpret_cast, not constant); and
#      `_version = {}` being ambiguous between implicit copy-assign and a user operator=.
#
#   The .rc is UTF-16LE, which llvm-rc refuses; it is converted to UTF-8 first.
#
# All patches are applied by this script and are IDEMPOTENT, so a clean clone reproduces the build.
# Every patch is marked "PATCHED FOR CLANG (local build only)" in the source with its reason.
#
# Usage:  tools/build-optiscaler-nr.sh [--clean]
# Output: ~/dgx-gaming-work/optiscaler-build/package/{OptiScaler.dll,nvngx.dll_dlssnr.dll,OptiScaler.ini}
#
set -uo pipefail

FORK_URL="https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass.git"
WORK="$HOME/dgx-gaming-work"
SRC="$WORK/optiscaler-nr"
B="$WORK/optiscaler-build"
AB="$WORK/addon-build"                 # toolchain from tools/build-dlssnr-addon.sh
CLANGXX="$AB/clang20/root/usr/bin/clang++-20"
LLD="$AB/clang20/root/usr/bin/lld-link-20"
RC="$AB/clang20/root/usr/bin/llvm-rc-20"
LIBTOOL="$AB/clang20/root/usr/bin/llvm-lib-20"
XWIN="$AB/xwin-sdk"
NGX="$AB/renodx/external/DLSS/include"
DETOURS_SRC="$AB/renodx/external/Detours/src"
OBJ="$B/obj"; SHIM="$B/caseshim"; PKG="$B/package"

[ "${1:-}" = "--clean" ] && rm -rf "$OBJ" "$SHIM"
for t in "$CLANGXX" "$LLD" "$RC" "$LIBTOOL"; do
  [ -x "$t" ] || { echo "MISSING $t — run tools/build-dlssnr-addon.sh first (it installs clang-20 + xwin)"; exit 1; }
done
[ -d "$XWIN/crt/include" ] || { echo "MISSING xwin SDK at $XWIN"; exit 1; }
CLANG_RES="$("$CLANGXX" -print-resource-dir)"
mkdir -p "$OBJ" "$SHIM" "$PKG"

echo "=== [1/7] source ==="
if [ ! -d "$SRC/.git" ]; then git clone --depth 1 -q "$FORK_URL" "$SRC" || exit 1; fi
cd "$SRC" || exit 1
echo "  $(git log -1 --format='%h %ai')"
git submodule update --init --depth 1 \
  external/spdlog external/simpleini external/magic_enum external/unordered_dense \
  external/vulkan external/nvapi external/xess external/RTX40MFG-Unlock \
  external/FidelityFX-SDK external/FidelityFX-SDK-v2 >/dev/null 2>&1
echo "  submodules ready"

echo "=== [2/7] source patches (idempotent) ==="
# The source patches live in tools/patches/ because they embed excerpts of
# GPL-3.0 OptiScaler source and therefore carry GPL-3.0, unlike the MIT-licensed
# rest of this repository. See tools/patches/README.md.
python3 "$(cd "$(dirname "$0")" && pwd)/patches/optiscaler-clang-portability.py" || exit 1

echo "=== [3/7] case-sensitivity shims ==="
# (a) includes resolvable from a root, incl. the Windows SDK (Softpub.h, Windows.UI.Xaml.Hosting.h)
grep -rhoE '#include[[:space:]]*[<"][^">]+[">]' OptiScaler --include=*.cpp --include=*.h --include=*.hpp 2>/dev/null \
 | sed -E 's/#include[[:space:]]*[<"]//; s/[">]$//' | sort -u > "$B/incs.txt"
ROOTS=(OptiScaler OptiScaler/include external external/freetype "$XWIN/sdk/include/um" "$XWIN/sdk/include/shared" "$XWIN/sdk/include/winrt" "$XWIN/sdk/include/ucrt" "$XWIN/crt/include")
a=0
while read -r inc; do
  f=""; for r in "${ROOTS[@]}"; do [ -e "$r/$inc" ] && { f=1; break; }; done
  [ -n "$f" ] && continue; [ -e "$SHIM/$inc" ] && continue
  for r in "${ROOTS[@]}"; do
    real=$(find "$r" -ipath "$r/$inc" -print -quit 2>/dev/null)
    [ -n "$real" ] && { mkdir -p "$SHIM/$(dirname "$inc")"; ln -sf "$(readlink -f "$real")" "$SHIM/$inc" && a=$((a+1)); break; }
  done
done < "$B/incs.txt"
# (b) quoted includes resolved RELATIVE to the including file (bcds_*.h, xess_dbg.h, d3dx11*.h)
b=0
while read -r src; do
  d=$(dirname "$src")
  grep -oE '#include[[:space:]]*"[^"]+"' "$src" 2>/dev/null | sed -E 's/#include[[:space:]]*"//; s/"$//' | while read -r inc; do
    [ -e "$d/$inc" ] && continue
    real=$(find "$d" -ipath "$d/$inc" -print -quit 2>/dev/null); [ -z "$real" ] && continue
    mkdir -p "$d/$(dirname "$inc")"; ln -sf "$(basename "$real")" "$d/$inc" 2>/dev/null && echo x
  done
done < <(find OptiScaler \( -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) 2>/dev/null) | wc -l > "$B/relshim.count"
echo "  path shims: $a   relative shims: $(cat "$B/relshim.count")"

echo "=== [4/7] generated headers + UTF-8 resources ==="
printf '#define VER_BUILD_DATE "%s"\n' "$(date +%Y%m%d_%H%M%S)" > OptiScaler/resource_build_date.h
printf '#define VER_BUILD_COMMIT "%s"\n' "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" > OptiScaler/resource_build_commit.h
iconv -f UTF-16LE -t UTF-8 OptiScaler/OptiScaler.rc | sed 's/\r$//; 1s/^\xEF\xBB\xBF//' > OptiScaler/OptiScaler_utf8.rc
echo "  ok"

echo "=== [5/7] detours.lib ==="
mkdir -p "$B/detours"
if [ ! -f "$B/detours/detours.lib" ]; then
  for s in detours disasm modules creatwth; do
    "$CLANGXX" -target x86_64-pc-windows-msvc -O2 -c "$DETOURS_SRC/$s.cpp" -o "$B/detours/$s.obj" \
      -fms-runtime-lib=$CRT_MODE -I "$DETOURS_SRC" -isystem "$CLANG_RES/include" \
      -isystem "$XWIN/crt/include" -isystem "$XWIN/sdk/include/ucrt" -isystem "$XWIN/sdk/include/um" \
      -isystem "$XWIN/sdk/include/shared" -Wno-everything 2>/dev/null || echo "  FAIL $s"
  done
  "$LIBTOOL" /OUT:"$B/detours/detours.lib" "$B/detours"/*.obj >/dev/null 2>&1
fi
echo "  $(ls -la "$B/detours/detours.lib" 2>/dev/null | awk '{print $5" bytes"}')"

INCS=(-I "$SHIM" -I OptiScaler -I OptiScaler/include -I external -I external/freetype
 -I external/simpleini -I external/nvngx_dlss_sdk -I external/unordered_dense/include
 -I external/vulkan/include -I external/xess/inc/xess -I external/xess/inc -I external/xess/inc/xell
 -I external/xess/inc/xess_fg -I external/FidelityFX-SDK/ffx-api/include/ffx_api
 -I external/FidelityFX-SDK/ffx-api/include -I external/FidelityFX-SDK-v2/ffx-api/include/ffx_api
 -I external/AntiLag2-SDK -I external/latencyflex -I external/streamline -I external/streamline1
 -I external/spdlog/include -I external/magic_enum/include/magic_enum -I external/nvapi
 -I external/nlohmann -I external/RTX40MFG-Unlock -I "$NGX")
CRT_MODE="${CRT_MODE:-static}"
CFLAGS=(-target x86_64-pc-windows-msvc -std=c++23 -O2 -DNDEBUG -fms-runtime-lib=$CRT_MODE
 -DUNICODE -D_UNICODE -DWIN32 -D_WINDOWS -D_USRDLL -D_HAS_CXX23=1 -D_CRT_USE_BUILTIN_OFFSETOF
 -Wno-microsoft-string-literal-from-predefined -Wno-microsoft-cast -Wno-ignored-attributes
 -Wno-unknown-pragmas -Wno-nonportable-include-path
 -isystem "$CLANG_RES/include"
 -isystem "$XWIN/crt/include" -isystem "$XWIN/sdk/include/ucrt"
 -isystem "$XWIN/sdk/include/um" -isystem "$XWIN/sdk/include/shared" -isystem "$XWIN/sdk/include/winrt")

echo "=== [6/7] compile ==="
grep -oE '<ClCompile Include="[^"]*"' OptiScaler/OptiScaler.vcxproj | sed 's/<ClCompile Include="//; s/"$//' \
 | tr '\\' '/' | sed 's|^|OptiScaler/|' | sort -u > "$B/srcs.txt"
: > "$B/compile.log"
NPROC=$(nproc 2>/dev/null || echo 4); [ "$NPROC" -gt 8 ] && NPROC=8
while read -r f; do
  o="$OBJ/$(echo "$f" | tr '/' '_').obj"
  if [ -f "$o" ] && [ "$o" -nt "$f" ]; then echo "OK $f" >> "$B/compile.log"; continue; fi
  ( "$CLANGXX" "${CFLAGS[@]}" "${INCS[@]}" -c "$f" -o "$o" > "$o.log" 2>&1 && echo "OK $f" || echo "FAIL $f" ) >> "$B/compile.log" &
  while [ "$(jobs -rp | wc -l)" -ge "$NPROC" ]; do wait -n 2>/dev/null || break; done
done < "$B/srcs.txt"
wait
echo "  compiled $(grep -c '^OK' "$B/compile.log") / $(wc -l < "$B/srcs.txt")   failed: $(grep -c '^FAIL' "$B/compile.log")"
grep '^FAIL' "$B/compile.log" | head -5
[ "$(grep -c '^FAIL' "$B/compile.log")" -gt 0 ] && { echo "compile failures — see $OBJ/*.log"; exit 1; }
"$RC" /I OptiScaler /I "$XWIN/sdk/include/um" /I "$XWIN/sdk/include/shared" \
      /FO "$OBJ/OptiScaler.res" OptiScaler/OptiScaler_utf8.rc >/dev/null 2>&1

echo "=== [7/7] link ==="
rm -f "$B/OptiScaler.dll" "$B/nvngx.dll_dlssnr.dll" "$PKG/OptiScaler.dll" "$PKG/nvngx.dll_dlssnr.dll"
mapfile -t OBJS < <(find "$OBJ" -name '*.obj' | sort)
[ -f "$OBJ/OptiScaler.res" ] && OBJS+=("$OBJ/OptiScaler.res")
"$LLD" /DLL /OUT:"$B/OptiScaler.dll" /MACHINE:X64 /NOLOGO /DEF:OptiScaler/Source.def \
  /LIBPATH:"$XWIN/crt/lib/x86_64" /LIBPATH:"$XWIN/sdk/lib/um/x86_64" /LIBPATH:"$XWIN/sdk/lib/ucrt/x86_64" \
  /LIBPATH:OptiScaler/library/fsr2 /LIBPATH:OptiScaler/library/fsr2_212 /LIBPATH:OptiScaler/library/fsr31 \
  /LIBPATH:OptiScaler/library/vulkan /LIBPATH:OptiScaler/library/d3dx /LIBPATH:external/freetype \
  /LIBPATH:external/nvapi/amd64 /LIBPATH:"$B/detours" \
  "${OBJS[@]}" \
  winhttp.lib dbghelp.lib version.lib detours.lib windowsapp.lib runtimeobject.lib dxgi.lib d3d11.lib \
  d3d12.lib vulkan-1.lib dxguid.lib freetype.lib d3dcompiler.lib \
  ffx_fsr2_api_x64.lib ffx_fsr2_api_dx11_x64.lib ffx_fsr2_api_dx12_x64.lib ffx_fsr2_api_vk_x64.lib \
  ffx_fsr2_212_api_dx12_x64.lib ffx_fsr2_212_api_vk_x64.lib ffx_fsr2_212_api_x64.lib \
  ffx_backend_dx11_x64.lib ffx_fsr3_x64.lib ffx_fsr3upscaler_x64.lib ffx_opticalflow_x64.lib \
  ffx_frameinterpolation_x64.lib \
  user32.lib kernel32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib shlwapi.lib gdi32.lib \
  2>&1 | grep -E 'error|warning: ' | head -10

"$CLANGXX" "${CFLAGS[@]}" -shared -fuse-ld=lld -I OptiScaler -I OptiScaler/include -I external \
  -I "$NGX" -I external/spdlog/include \
  -L "$XWIN/crt/lib/x86_64" -L "$XWIN/sdk/lib/um/x86_64" -L "$XWIN/sdk/lib/ucrt/x86_64" \
  OptiScaler/dlssnr/forwarder/dlssnr_forwarder.cpp -o "$B/nvngx.dll_dlssnr.dll" 2>&1 | head -5

cp -f "$B/OptiScaler.dll" "$B/nvngx.dll_dlssnr.dll" "$PKG/" 2>/dev/null
cp -f OptiScaler.ini INSTALL-DLSSNR.md "$PKG/" 2>/dev/null
cp -f OptiScaler/dlssnr/README.md "$PKG/DLSSNR-README.md" 2>/dev/null

if [ ! -f "$B/OptiScaler.dll" ]; then echo "LINK FAILED — no OptiScaler.dll produced"; exit 1; fi
echo "=== result ==="
for f in "$PKG/OptiScaler.dll" "$PKG/nvngx.dll_dlssnr.dll"; do
  [ -f "$f" ] && echo "  $(basename "$f")  $(stat -c%s "$f") bytes  $(file -b "$f" | cut -d, -f1)" || echo "  MISSING $(basename "$f")"
done
echo
echo "Install: copy the package into the game's exe directory, rename OptiScaler.dll to one of"
echo "dxgi.dll / winmm.dll / version.dll / dbghelp.dll / d3d12.dll, add a Wine override for that"
echo "name (WINEDLLOVERRIDES=\"<name>=n,b\"), and place your OWN retail nvngx_dlssnr.dll beside it."
echo "Overlay key: Insert.  Do NOT install ReShade alongside — see the deadlock note in README.md."
