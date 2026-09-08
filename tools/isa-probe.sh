#!/usr/bin/env bash
# isa-probe.sh — ask the translators a question whose correct answer is already
# known, and report who gets it wrong.
#
# WHY THIS EXISTS
#   The best hour this project ever spent was 2026-09-07, when three ~40-line
#   assembly probes settled an id Tech 4 question that had been open for months
#   and killed three of the investigator's own hypotheses on the way. A probe
#   costs seconds; the game launch it replaces costs ten minutes, a 100 GB
#   install, and an interpretation nobody can check.
#
#   Three properties make a probe trustworthy, and all three are enforced here:
#     1. FREESTANDING — no libc, no compiler, no Wine, no GPU, no Steam. Built
#        with the x86 binutils inside FEX's own RootFS, because the ARM64 host
#        has no x86 assembler at all. (A C version was tried first and silently
#        compiled for aarch64.)
#     2. THE ANSWER IS EXTERNAL — it lives in a .expect file quoting the Intel
#        SDM, so a probe can never be "passed" by agreeing with a bug.
#     3. BOTH RUNTIMES, ALWAYS — different wrong answers means the translator is
#        implicated; IDENTICAL wrong answers means suspect the probe. A hook test
#        here once failed the same way under FEX and Box64 because it clobbered
#        its own jump target.
#
#   Remember binfmt_misc registers ONLY Box64 for x86 ELF on this box. Running a
#   probe by path is Box64, never FEX. This script is explicit about both.
#
# Usage:
#   tools/isa-probe.sh                 # run every probe under both runtimes
#   tools/isa-probe.sh x87tags         # just the ones whose name matches
#   KEEP=1 tools/isa-probe.sh          # leave built binaries in place
#
# Exit: 0 = both runtimes match the SDM everywhere
#       1 = at least one real mismatch (informational `*` tags never fail)
#       2 = a probe could not be built or run
set -uo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
DIR="$REPO/isa-probe"
FILTER="${1:-}"
WORK="$(mktemp -d "${CLAUDE_JOB_DIR:-/tmp}/isaprobe.XXXXXX")"
[ "${KEEP:-0}" = 1 ] || trap 'rm -rf "$WORK"' EXIT

command -v FEXBash >/dev/null 2>&1 || { echo "!! FEXBash not found"; exit 2; }
# FEX_BIN=<prefix>/bin points the RUN step at a locally built FEX while still
# building the probes with the system FEXBash (which supplies the RootFS).
if [ -n "${FEX_BIN:-}" ]; then
  FEX_INTERP="$FEX_BIN/FEXInterpreter"
  [ -x "$FEX_INTERP" ] || { echo "!! no FEXInterpreter at $FEX_INTERP"; exit 2; }
  echo "  using FEX build: $FEX_INTERP"
  export FEX_INTERP
fi
command -v box64   >/dev/null 2>&1 || echo "  ! box64 not found — FEX only, so no cross-check"

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; OFF=$'\033[0m'
fail_total=0; ran=0

for src in "$DIR"/*.S; do
  [ -e "$src" ] || continue
  base=$(basename "$src" .S)                 # e.g. x87tags.32
  name=${base%.*}; bits=${base##*.}
  [ -n "$FILTER" ] && case "$name" in *"$FILTER"*) ;; *) continue;; esac
  exp="$DIR/$base.expect"
  [ -f "$exp" ] || { echo "${YEL}skip $base — no .expect (a probe with no external answer proves nothing)${OFF}"; continue; }

  echo "== $base =="
  if [ "$bits" = 32 ]; then AS="as --32"; LD="ld -m elf_i386"; else AS="as"; LD="ld"; fi
  if ! FEXBash -c "$AS -o '$WORK/$base.o' '$src' && $LD -o '$WORK/$base' '$WORK/$base.o'" >"$WORK/$base.build" 2>&1; then
    echo "${RED}  BUILD FAILED${OFF}"; sed 's/^/    /' "$WORK/$base.build" | head -8; fail_total=$((fail_total+1)); continue
  fi
  ran=$((ran+1))

  # Probes are static binaries, so FEXInterpreter can run them directly -- and
  # that makes FEX_BIN able to point at a locally BUILT FEX, which is how a
  # source build gets gated on this suite instead of on hope.
  "${FEX_INTERP:-FEXInterpreter}" "$WORK/$base" >"$WORK/$base.fex" 2>/dev/null
  if command -v box64 >/dev/null 2>&1; then
    box64 "$WORK/$base" >"$WORK/$base.box64" 2>/dev/null
  else
    : > "$WORK/$base.box64"
  fi

  EXPECT="$exp" FEX="$WORK/$base.fex" BOX="$WORK/$base.box64" python3 - <<'PY'
import os, struct, sys
def records(path):
    try: d = open(path,'rb').read()
    except OSError: return None
    if len(d) % 8: return None
    out = {}
    for i in range(0, len(d), 8):
        tag = d[i:i+4].decode('ascii','replace').strip()
        out[tag] = struct.unpack_from('<I', d, i+4)[0]
    return out

want = []
for line in open(os.environ['EXPECT']):
    line = line.split('#')[0].strip()
    if not line: continue
    parts = line.split()
    if len(parts) == 2: want.append((parts[0], parts[1]))

runs = {'FEX': records(os.environ['FEX']), 'Box64': records(os.environ['BOX'])}
bad = 0
for tag, spec in want:
    cells = []
    for rt in ('FEX','Box64'):
        r = runs[rt]
        if r is None: cells.append((rt, None, 'no output')); continue
        if tag not in r: cells.append((rt, None, 'missing')); continue
        v = r[tag]
        if spec == '*':          ok = True
        elif spec == '!0':       ok = (v != 0)
        else:                    ok = (v == int(spec, 0))
        cells.append((rt, v, 'ok' if ok else 'MISMATCH'))
    line = f"  {tag:<6} expect {spec:<8}"
    for rt, v, st in cells:
        vs = '----' if v is None else f'0x{v:04x}'
        mark = '' if st in ('ok',) else ('  <-- '+st)
        line += f"  {rt}={vs}{mark}"
        if st == 'MISMATCH' or (st not in ('ok',) and spec != '*'): bad += 1
    print(line)
print(f"  -> {'all match' if bad==0 else str(bad)+' mismatch(es)'}")
sys.exit(1 if bad else 0)
PY
  [ $? -ne 0 ] && fail_total=$((fail_total+1))
  echo
done

echo "=================================================================="
echo "probes run: $ran   probes with mismatches: $fail_total"
if [ "$fail_total" -gt 0 ]; then
  echo "A mismatch on ONE runtime = that translator is implicated."
  echo "A mismatch on BOTH, identically = suspect the probe before the JITs."
  exit 1
fi
echo "${GRN}Every probe matches the SDM under both runtimes.${OFF}"
exit 0
