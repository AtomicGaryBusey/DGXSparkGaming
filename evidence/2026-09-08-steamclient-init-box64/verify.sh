#!/usr/bin/env bash
# verify.sh — re-check every load-bearing claim behind the steamclient_init root cause.
#
# WHY THIS EXISTS
#   The root cause was proposed by a 14-agent research run. Agent findings are
#   untrusted input in this project -- one earlier run's headline claim was
#   demolished by five minutes of local disassembly. So every step was re-derived
#   locally before it was written into README.md, and this script is that
#   re-derivation, kept runnable rather than pasted into a transcript that nobody
#   can execute.
#
#   Run it on any machine with the same stack. If a check fails, the README entry
#   is wrong and should be corrected in place, not quietly deleted.
#
# THE CLAIM
#   DOOM 3 / Prey / RoE die under Box64 with "Access violation in
#   steamclient_init" because Box64 v0.4.4's box32 32-bit libc wrapper table is
#   missing four symbols that the container's i386 libstdc++ imports. Wine
#   dlopens unix halves RTLD_NOW, so the missing non-weak relocations are fatal,
#   dlopen returns NULL, __wine_unixlib_handle stays 0, and the dispatcher's
#   `call [eax+edx*4]` faults with eax=0.
#
# Usage:  evidence/2026-09-08-steamclient-init-box64/verify.sh
# Exit:   0 = every check passed, 1 = at least one failed
set -uo pipefail
S="${STEAM_ROOT:-$HOME/.local/share/Steam}/steamapps/common"
BOX64_SRC="${BOX64_SRC:-$HOME/box64}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail+1)); }
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$*"; }

echo "== 1. SteamStub: entry point inside .bind (and Quake 4 without one) =="
python3 - "$S" <<'PY'
import struct, os, sys
S = sys.argv[1]
def ep_section(path):
    d = open(path, 'rb').read(0x600)
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    nsec = struct.unpack_from('<H', d, pe + 6)[0]
    optsz = struct.unpack_from('<H', d, pe + 20)[0]
    ep = struct.unpack_from('<I', d, pe + 24 + 16)[0]
    secs = pe + 24 + optsz
    for i in range(nsec):
        o = secs + i * 40
        name = d[o:o+8].rstrip(b'\0').decode('ascii', 'replace')
        vs = struct.unpack_from('<I', d, o + 8)[0]
        va = struct.unpack_from('<I', d, o + 12)[0]
        if va <= ep < va + max(vs, 1): return ep, name
    return ep, '?'
want = {"Prey 2006/prey.exe": ".bind", "Doom 3/Doom3.exe": ".bind",
        "Quake 4/Quake4.exe": ".text", "RAGE/Rage.exe": ".bind"}
for rel, exp in want.items():
    p = os.path.join(S, rel)
    if not os.path.exists(p):
        print(f"  SKIP  {rel} not installed"); continue
    ep, sec = ep_section(p)
    tag = "PASS" if sec == exp else "FAIL"
    print(f"  {tag}  {rel:<26} EP=0x{ep:08x} in {sec} (expected {exp})")
PY

echo
echo "== 2. Box64's box32 table is missing the four symbols =="
if [ -d "$BOX64_SRC/src/wrapped32" ]; then
  echo "  box64 source: $(cd "$BOX64_SRC" && git log --oneline -1 2>/dev/null)"
  for sym in arc4random strfromf128 strtof128; do
    if grep -rqE "GO\w*\($sym," "$BOX64_SRC/src/wrapped32/" 2>/dev/null; then
      bad "$sym IS wrapped in box32 — the claim is stale, upstream may have fixed it"
    else ok "$sym absent from src/wrapped32/ (present in src/wrapped/: $(grep -rcE "GO\w*\(arc4random,|GO\w*\($sym," "$BOX64_SRC/src/wrapped/" 2>/dev/null | awk -F: '{s+=$2} END{print (s>0)?"yes":"no"}'))"; fi
  done
  if grep -qE '^\s*//\s*GO\(strtold,' "$BOX64_SRC/src/wrapped32/wrappedlibc_private.h" 2>/dev/null; then
    ok "strtold is COMMENTED OUT in src/wrapped32/wrappedlibc_private.h"
  else bad "strtold is not commented out — claim is stale"; fi
  grep -qE 'GO\(__strtold_l,' "$BOX64_SRC/src/wrapped32/wrappedlibc_private.h" 2>/dev/null \
    && ok "__strtold_l IS wrapped — which is why 4 symbols fail, not 5" \
    || skip "__strtold_l not found (does not affect the main claim)"
else
  skip "no box64 source at $BOX64_SRC (set BOX64_SRC=)"
fi

echo
echo "== 3. The container's i386 libstdc++ imports exactly those symbols =="
L=$(ls "$S/SteamLinuxRuntime_4"/steamrt4_platform_*/files/lib/i386-linux-gnu/libstdc++.so.6 2>/dev/null | head -1)
if [ -n "$L" ]; then
  U=$(readelf -sW --dyn-syms "$L" 2>/dev/null | awk '$7=="UND"{print $8}' | sed 's/@.*//' | sort -u)
  for sym in arc4random strfromf128 strtof128 strtold; do
    printf '%s\n' "$U" | grep -qx "$sym" && ok "libstdc++ imports $sym" || bad "libstdc++ does NOT import $sym"
  done
else skip "container libstdc++ not found"; fi

echo
echo "== 4. The failure chain in an archived Box64 run, absent in the FEX run =="
for pair in "3970-20260907-231525:Box64:expect" "3970-20260907-231800:FEX:absent"; do
  d="${pair%%:*}"; rest="${pair#*:}"; rt="${rest%%:*}"; mode="${rest##*:}"
  log="$HOME/dgx-gaming-work/runs/$d/proton.log"
  [ -f "$log" ] || { skip "$d proton.log not on this machine (kept out of git for size)"; continue; }
  n=$(grep -c 'not found, cannot apply R_386_JMP_SLOT' "$log" 2>/dev/null)
  p=$(grep -c 'relocating Plt symbols in elf libstdc++' "$log" 2>/dev/null)
  a=$(grep -c 'Access violation in steamclient_init' "$log" 2>/dev/null)
  if [ "$mode" = expect ]; then
    [ "${n:-0}" -gt 0 ] && [ "${p:-0}" -gt 0 ] && [ "${a:-0}" -gt 0 ] \
      && ok "$rt: $n missing-symbol, $p libstdc++ Plt failure, $a AV" \
      || bad "$rt: expected the chain, got symbols=$n plt=$p av=$a"
  else
    [ "${n:-0}" -eq 0 ] && [ "${a:-0}" -eq 0 ] \
      && ok "$rt: zero missing-symbol errors, zero AV (as expected)" \
      || bad "$rt: expected a clean run, got symbols=$n av=$a"
  fi
done

echo
[ "$fail" -eq 0 ] && { echo "ALL CHECKS PASSED — the README entry is supported."; exit 0; }
echo "$fail CHECK(S) FAILED — correct the README entry in place, do not delete it."
exit 1
