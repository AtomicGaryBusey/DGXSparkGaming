#!/usr/bin/env bash
# build-rtx-spark-kit.sh — build, on this box, the probes the RTX Spark needs on
# day one, as Windows PEs, into one folder you copy to the laptop.
#
# WHY THIS EXISTS
#   The RTX Spark runs x86 through Microsoft's Prism, not FEX or Box64, and has
#   no Wine in the picture. The cheapest way to learn whether any translator
#   finding here transfers is to ask Prism the same SDM questions, with no game,
#   GPU or install involved (notes/2026-11-12-rtx-spark-transfer-research.md).
#   But the isa-probes are Linux ELFs that end in `int $0x80`. The repo said
#   "run them under Prism on day one" for two months without noticing they could
#   not run there. This script fixes that.
#
#   How the isa-probes are ported: each probe's two syscalls (write, then exit)
#   are rewritten into calls to tools/isa-probe/win/pe-stub32.S, and NOTHING
#   ELSE changes. If a probe ever grows a third syscall, the rewrite refuses
#   rather than guessing. The same .expect files grade both platforms.
#
#   Everything is built with Ubuntu's mingw from tools/setup-mingw.sh. There is no
#   sudo and no third-party binary, consistent with the rest of tools/.
#
#   SMOKE=1 grades the PE port itself before it leaves this machine. It runs the
#   ported isa-probes under Proton's Wine hosted by FEX, and checks them against
#   the same .expect files. FEX passes all four ELF probes as of fex-emu 2611, so
#   any PE mismatch would mean the port broke something. Verified 2026-11-12:
#   every tag of the PE build matched the ELF build.
#   FEX only, deliberately: Proton's wine launched from this shell goes to Box64
#   through binfmt, outside pressure-vessel, and it dies with "Could not open
#   '/lib64/ld-linux-x86-64.so.2'". A Box64 column there would show only that.
#
# Usage:  tools/build-rtx-spark-kit.sh [outdir]   (default ~/dgx-gaming-work/rtx-spark-kit)
#         SMOKE=1 tools/build-rtx-spark-kit.sh
# Needs:  MINGW_ARCH=i686 tools/setup-mingw.sh  and  tools/setup-mingw.sh  (x86-64)
# Output: <outdir>/  plus <outdir>.zip if `zip` exists. Copy either to the laptop and
#         read README-KIT.txt there.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HOME/dgx-gaming-work/rtx-spark-kit}"
BIN="${MINGW_PREFIX:-$HOME/dgx-gaming-work/toolchain}/root/usr/bin"
CC32="$BIN/i686-w64-mingw32-gcc-win32"
CC64="$BIN/x86_64-w64-mingw32-gcc-win32"
[ -x "$CC32" ] || { echo "!! no i686 mingw: MINGW_ARCH=i686 tools/setup-mingw.sh"; exit 2; }
[ -x "$CC64" ] || { echo "!! no x86-64 mingw: tools/setup-mingw.sh"; exit 2; }

rm -rf "$OUT"; mkdir -p "$OUT/src"
fail=0
build() { # $1=label, rest=compiler command
  local label="$1"; shift
  if "$@" 2>"$OUT/src/$label.build.log"; then printf '  built %s\n' "$label"; rm -f "$OUT/src/$label.build.log"
  else printf '  !! FAILED %s\n' "$label"; sed 's/^/     /' "$OUT/src/$label.build.log" | head -6; fail=$((fail+1)); fi
}

echo "=== isa-probe suite -> PE32 (graded by Check-IsaProbe.ps1) ==="
for src in "$HERE"/isa-probe/*.32.S; do
  base=$(basename "$src" .S)
  [ -f "$HERE/isa-probe/$base.expect" ] || { echo "  skip $base (no .expect)"; continue; }
  awk 'BEGIN{n=0}
       /int[ \t]+\$0x80/ { n++
         if (n==1) sub(/int[ \t]+\$0x80/, "call    __probe_write  /* PE port: was int $0x80 write */")
         else if (n==2) sub(/int[ \t]+\$0x80/, "call    __probe_exit   /* PE port: was int $0x80 exit */") }
       { print }
       END { if (n != 2) exit 3 }' "$src" > "$OUT/src/$base.S"
  rc=$?
  if [ $rc -ne 0 ]; then echo "  !! $base has $( grep -c 'int *\$0x80' "$src" ) syscalls, expected exactly 2 -- refusing to guess"; fail=$((fail+1)); continue; fi
  build "$base.exe" "$CC32" -nostdlib -nostartfiles -Wl,-e,_start -o "$OUT/$base.exe" \
        "$OUT/src/$base.S" "$HERE/isa-probe/win/pe-stub32.S" -lkernel32
  cp "$HERE/isa-probe/$base.expect" "$OUT/"
done
cp "$HERE/isa-probe/win/Check-IsaProbe.ps1" "$OUT/"

echo "=== existing PE probes (each prints its own verdict) ==="
build cpuidprobe32.exe "$CC32" -O0 -o "$OUT/cpuidprobe32.exe" "$HERE/probes/cpuid/cpuidprobe.c"
build cpuidprobe64.exe "$CC64" -O0 -o "$OUT/cpuidprobe64.exe" "$HERE/probes/cpuid/cpuidprobe.c"
build wglpf32.exe      "$CC32" -O1 -o "$OUT/wglpf32.exe" "$HERE/probes/wgl/wgl-pixelformat32.c" -lopengl32 -lgdi32 -luser32
build fmt32.exe        "$CC32" -O1 -o "$OUT/fmt32.exe"   "$HERE/probes/wgl/wgl-formatsweep32.c" -lopengl32 -lgdi32 -luser32
build fmt64.exe        "$CC64" -O1 -o "$OUT/fmt64.exe"   "$HERE/probes/wgl/wgl-formatsweep32.c" -lopengl32 -lgdi32 -luser32
build x87ctx32.exe     "$CC32" -O0 -o "$OUT/x87ctx32.exe" "$HERE/fex-tests/x87-wine-context32.c"
build namedobj32.exe   "$CC32" -O1 -o "$OUT/namedobj32.exe" "$HERE/probes/namedobj/namedobj32.c"
build hook64.exe       "$CC64" -O0 -o "$OUT/hook64.exe" "$HERE/fex-tests/hook-inline-patch.c"

cat > "$OUT/README-KIT.txt" <<'TXT'
RTX Spark day-one probe kit, built by tools/build-rtx-spark-kit.sh in the DGXSparkGaming repo.
Every expected answer comes from the Intel SDM or from the probe's own source header,
never from whichever runtime ran first. No game, GPU or install is involved.

0. Record the machine first: Device Manager -> Display adapters -> Details -> Hardware Ids
   (2E03 or 2E06?), the NVIDIA app's GPU memory split, winver, power mode, on AC or battery.

1. isa-probe suite (x87 tag word, FINCSTP/FDECSTP, a3 store, CPUID):
     powershell -ExecutionPolicy Bypass -File .\Check-IsaProbe.ps1
   Then A/B ONE Prism setting at a time (Properties -> Compatibility -> Windows on Arm):
     .\Check-IsaProbe.ps1 -MakeVariant fp80   # set "Disable floating point optimization" on *-fp80.exe
     .\Check-IsaProbe.ps1 -Variant fp80
     .\Check-IsaProbe.ps1 -MakeVariant newcpu # set "Show newer emulated CPU features" on *-newcpu.exe
     .\Check-IsaProbe.ps1 -Variant newcpu
   results.tsv collects every run.

2. cpuidprobe32.exe and cpuidprobe64.exe: compare them. NVIDIA documents that 32-bit emulation
   reports fewer features (no XSAVE/OSXSAVE, and no AVX unless opted in).

3. wglpf32.exe, then fmt32.exe and fmt64.exe: how many pixel formats does 32-bit OpenGL get,
   and from which ICD? On DGX Spark: 0/320 under FEX, 320/320 under Box64. This is the id Tech 4
   precondition. A window opens briefly.

4. x87ctx32.exe: x87 state across exceptions and VEH under real WOW64. FEX zeroes it (CW=0x0000).

5. namedobj32.exe: a control. Box64 returns ERROR_NOACCESS on a file-exists collision; FEX is clean.

6. hook64.exe: inline hooking under Prism. NVIDIA's porting guide says not to patch OS libraries;
   ReShade and OptiScaler do exactly that. Run this before trying either.

Bring every output back to the repo verbatim. The probes' own source headers explain how to read them.
TXT

if [ "${SMOKE:-0}" = 1 ]; then
  echo "=== SMOKE: ported isa-probes under Proton Wine, FEX-hosted ==="
  STEAM="${STEAM_ROOT:-$HOME/.local/share/Steam}"
  PROTON="${PROTON_DIR:-$STEAM/steamapps/common/Proton 11.0}"
  [ -x "$PROTON/files/bin/wine" ] || { echo "!! Proton not found at $PROTON"; exit 2; }
  PFX="${SMOKE_PREFIX:-$HOME/dgx-gaming-work/rtx-spark-kit-pfx}"; mkdir -p "$PFX/fex"
  smoke_bad=0
  for exe in "$OUT"/*.32.exe; do
    base=$(basename "$exe" .exe)
    aa-exec -p steam -- env WINEPREFIX="$PFX/fex" WINEDEBUG=-all \
      FEXBash -c "cd '$OUT' && '$PROTON/files/bin/wine' '$base.exe'" >"$OUT/src/$base.fex.out" 2>/dev/null
    python3 - "$OUT/$base.expect" "$OUT/src/$base.fex.out" "$base" <<'PY' || smoke_bad=$((smoke_bad+1))
import struct, sys
exp, fex, base = sys.argv[1:]
def rec(p):
    d = open(p, 'rb').read()
    # Wine can prepend nothing to stdout, but a console banner would land here; trim to 8-byte records.
    if not d or len(d) % 8: return None
    return {d[i:i+4].decode('ascii','replace').strip(): struct.unpack_from('<I', d, i+4)[0] for i in range(0, len(d), 8)}
r = {'FEX': rec(fex)}
bad = 0
print(f"  {base}")
for line in open(exp):
    line = line.split('#')[0].split()
    if len(line) != 2: continue
    tag, spec = line
    cells = []
    for k in ('FEX',):
        v = None if r[k] is None else r[k].get(tag)
        if v is None: cells.append(f"{k}=----  <-- missing"); bad += 1; continue
        ok = spec == '*' or (spec == '!0' and v != 0) or (spec not in ('*', '!0') and v == int(spec, 0))
        bad += 0 if ok else 1
        cells.append(f"{k}=0x{v:04x}{'' if ok else ' <-- MISMATCH'}")
    print(f"    {tag:<6} expect {spec:<8} " + "  ".join(cells))
sys.exit(1 if bad else 0)
PY
  done
  if [ $smoke_bad -eq 0 ]; then echo "  SMOKE OK: the PE port matches the SDM under FEX on every probe"
  else echo "  !! SMOKE: $smoke_bad probe(s) wrong. Run tools/isa-probe.sh: if the ELF passes there, the PORT is broken"; fail=$((fail+1)); fi
fi

if command -v zip >/dev/null 2>&1; then
  (cd "$(dirname "$OUT")" && rm -f "$(basename "$OUT").zip" && zip -qr "$(basename "$OUT").zip" "$(basename "$OUT")") \
    && echo "kit: $OUT  ($OUT.zip)"
else
  echo "kit: $OUT  (no zip on PATH; copy the folder)"
fi
[ $fail -eq 0 ] || { echo "!! $fail build(s) failed"; exit 1; }
