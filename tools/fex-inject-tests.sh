#!/usr/bin/env bash
# fex-inject-tests.sh — does Windows-side code injection survive FEX on GB10?
#
# WHY THIS EXISTS
#   The only surviving route to DLSS 5 Neural Rendering on this hardware is a
#   ReShade add-on that hooks D3D12 and forwards into NVIDIA's NR snippet. That
#   whole route rests on injection primitives working under x86->ARM64 translation.
#   Rather than assume, these tests answer it directly and cheaply. Run them before
#   spending money or hours on anything downstream.
#
#   Results on GB10 / FEX-2607 / Proton 11.0-2c, 2026-09-05..06:  BOTH PASS.
#
# A trap worth remembering: an early version of the hook test patched 12 bytes over
# an 11-byte function whose jump destination sat 11 bytes away at -O0, clobbering its
# own target. It failed *identically under FEX and Box64* — which is what exposed it.
# When two unrelated JITs fail the same way, suspect the test, not the translator.
# Hence the in-test rel32 range assertion, and hence run-both-translators below.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${MINGW_PREFIX:-$HOME/dgx-gaming-work/toolchain}"
WORK="${WORK:-$HOME/dgx-gaming-work/fex-tests}"
STEAM="${STEAM_ROOT:-$HOME/.local/share/Steam}"
PROTON="${PROTON_DIR:-$STEAM/steamapps/common/Proton 11.0}"
CC="$PREFIX/root/usr/bin/x86_64-w64-mingw32-gcc-win32"

[ -x "$CC" ] || { echo "!! no mingw; run tools/setup-mingw.sh first"; exit 2; }
[ -x "$PROTON/files/bin/wine" ] || { echo "!! Proton not found at $PROTON"; exit 2; }
mkdir -p "$WORK"; export WINEPREFIX="$WORK/pfx"; mkdir -p "$WINEPREFIX"

run_under() { # $1=label $2=exe ; runs with FEX or Box64
  local label="$1" exe="$2"
  if [ "$label" = FEX ]; then
    DISPLAY="${DISPLAY:-:1}" WINEDEBUG=-all timeout 240 \
      aa-exec -p steam -- env WINEPREFIX="$WINEPREFIX" WINEDEBUG=-all \
      FEXBash -c "cd '$WORK' && '$PROTON/files/bin/wine' $exe" 2>/dev/null
  else
    DISPLAY="${DISPLAY:-:1}" WINEDEBUG=-all timeout 240 \
      aa-exec -p steam -- env WINEPREFIX="$WORK/pfxb" WINEDEBUG=-all \
      sh -c "cd '$WORK' && '$PROTON/files/bin/wine' $exe" 2>/dev/null
  fi
}

echo "=== building tests ==="
"$CC" -O0 -o "$WORK/hook.exe"     "$HERE/fex-tests/hook-inline-patch.c" || exit 1
"$CC" -O0 -o "$WORK/fwdload.exe"  "$HERE/fex-tests/load-forwarder.c"    || exit 1
echo "  ok"

echo "=== TEST: inline hooking (runtime code patching) ==="
for t in FEX Box64; do
  printf '  %-6s ' "$t"; run_under "$t" hook.exe | grep -m1 RESULT || echo "(no result)"
done

if [ -f "$WORK/nvngx.dll_nrfwd.dll" ]; then
  echo "=== TEST: NGX forwarder loads ==="
  for t in FEX Box64; do
    printf '  %-6s ' "$t"; run_under "$t" fwdload.exe | grep -m1 RESULT || echo "(no result)"
  done
else
  echo "=== TEST: NGX forwarder — SKIPPED (build nvngx.dll_nrfwd.dll into $WORK first) ==="
fi
echo
echo "Note: ReShade cannot be tested this way — it declines a standalone LoadLibrary"
echo "outside a Direct3D host (fails identically under FEX and Box64, which is the tell)."
echo "Test it by dropping ReShade as dxgi.dll into a real DX12 game; see README test E."
