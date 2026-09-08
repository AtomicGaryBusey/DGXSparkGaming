#!/usr/bin/env bash
# cpuid-probe.sh — ask FEX and Box64 what x86 CPU they claim to be, using a REAL
# `cpuid` instruction, not /proc/cpuinfo and not a guess.
#
# WHY THIS EXISTS
#   2026-09-07: this log had published "Burnout Paradise's CPUID check doesn't detect
#   SSE2 under FEX". Wrong. SSE2 *is* advertised (leaf 1 EDX bit 26 = 1). What is NOT
#   advertised on FEX-2607 is leaf 1 EDX bit 2 (DE) and bit 3 (PSE) — and upstream FEX
#   PR #5807 says Burnout reads the DE bit as its SSE2 flag. Nobody had ever executed a
#   cpuid instruction on this box to check; there is no x86 compiler here, so the probe
#   is hand-assembled with mingw's `as` and wrapped in a hand-built ELF.
#   Box64 is run too because "identical failure across two JITs means the TEST is wrong".
#
# Usage: ./cpuid-probe.sh
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
TC="${MINGW_PREFIX:-$HOME/dgx-gaming-work/toolchain}/root/usr/bin"
AS="$TC/x86_64-w64-mingw32-as"; OC="$TC/x86_64-w64-mingw32-objcopy"
[ -x "$AS" ] || { echo "need mingw: run tools/setup-mingw.sh" >&2; exit 1; }
"$AS" -o "$D/cpuid.o" "$D/cpuid.S"
"$OC" -O binary --only-section=.text "$D/cpuid.o" "$D/cpuid.bin"
python3 - "$D/cpuid.bin" "$D/cpuid.elf" <<'PY'
import struct,sys
code=open(sys.argv[1],'rb').read(); BASE=0x400000; OFF=120
h=b'\x7fELF\x02\x01\x01\x00'+b'\x00'*8
h+=struct.pack('<HHIQQQIHHHHHH',2,0x3e,1,BASE+OFF,64,0,0,64,56,1,64,0,0)
h+=struct.pack('<IIQQQQQQ',1,5,0,BASE,BASE,OFF+len(code),OFF+len(code),0x1000)
open(sys.argv[2],'wb').write(h+code)
PY
chmod +x "$D/cpuid.elf"
decode(){ python3 "$D/decode.py"; }

for rt in FEX BOX64; do
  echo "=== $rt ==="
  case $rt in
    FEX)   out=$(FEXInterpreter "$D/cpuid.elf" 2>/dev/null);;
    BOX64) out=$(box64 "$D/cpuid.elf" 2>/dev/null | grep -E '^[0-9a-f]{8} ');;
  esac
  echo "$out"; echo "$out" | decode
done
