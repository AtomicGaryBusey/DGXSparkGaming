#!/usr/bin/env bash
# run-both.sh — run one x86 command under FEX **and** under Box64, and compare.
#
# WHY THIS EXISTS
#   Two rules this project keeps relearning the hard way, made mechanical:
#
#   1. "When two independent implementations fail identically, suspect the TEST."
#      A hook test once failed the same way under FEX and Box64 — because a
#      12-byte patch clobbered its own jump target, not because translation was
#      broken. The same signature later saved a false ReShade verdict.
#
#   2. "You cannot reason about a runtime you have not confirmed you are running."
#      binfmt_misc here registers ONLY Box64 for x86 ELF; FEX is not registered
#      at all. So a binary run from a shell BY PATH is Box64, and only FEXBash /
#      FEXInterpreter (or a child of a process already inside FEX) is FEX. On
#      2026-09-07 a 32-bit PE result was about to be written up as FEX when a
#      stray `[BOX32]` banner on stderr gave it away. That is far too thin a
#      thread to hang attribution on.
#
#   Running both is also how the x87 investigation stayed honest: FEX and Box32
#   gave DIFFERENT wrong answers to the same Wine operation, which is what
#   licensed the conclusion that the translator was implicated at all.
#
# Usage:
#   tools/run-both.sh /tmp/probe                    # an x86-64 or x86-32 ELF
#   tools/run-both.sh --wine game.exe               # a Windows PE, via Proton
#   tools/run-both.sh --which /tmp/probe            # just say who would run it
#
# Exit: 0 = the two runtimes AGREE
#       1 = they DISAGREE (interesting — the JIT is implicated)
#       2 = could not run under one or both
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
STEAM="${STEAM_ROOT:-$HOME/.local/share/Steam}"
MODE=run; WINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --which) MODE=which; shift;;
    --wine)  WINE=1; shift;;
    --) shift; break;;
    *) break;;
  esac
done
[ $# -ge 1 ] || { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 3; }

note() { printf '  %s\n' "$*"; }
hr()   { printf '%s\n' "------------------------------------------------------------------"; }

# --- who does binfmt hand an x86 ELF to? ------------------------------------
BINFMT=""
for f in /proc/sys/fs/binfmt_misc/*; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in register|status) continue;; esac
  grep -q '^enabled' "$f" 2>/dev/null || continue
  i=$(awk '/^interpreter/{print $2}' "$f")
  case "$i" in *box64*|*box86*) BINFMT="Box64 ($(basename "$f"))";; *FEX*) BINFMT="FEX ($(basename "$f"))";; esac
done
if [ "$MODE" = which ]; then
  echo "binfmt_misc would hand an x86 ELF to: ${BINFMT:-nothing registered}"
  echo "  FEX registered in binfmt?  $(ls /proc/sys/fs/binfmt_misc/ 2>/dev/null | grep -ci fex)"
  echo "  -> a bare './prog' or '\$(which prog)' is ${BINFMT%% *}, NOT necessarily FEX."
  echo "  -> for FEX you must use FEXBash / FEXInterpreter explicitly."
  exit 0
fi

PROTON="$STEAM/steamapps/common/Proton - Experimental/files/bin/wine"
OUT="$(mktemp -d "${CLAUDE_JOB_DIR:-/tmp}/runboth.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

run_under() {   # $1 = fex|box64
  local who="$1"; shift
  if [ "$WINE" = 1 ]; then
    if [ "$who" = fex ]; then
      FEXBash -c "WINEDEBUG=${WINEDEBUG:--all} '$PROTON' $(printf "'%s' " "$@")" 2>&1
    else
      WINEDEBUG="${WINEDEBUG:--all}" "$PROTON" "$@" 2>&1
    fi
  else
    if [ "$who" = fex ]; then FEXInterpreter "$@" 2>&1
    else                      box64 "$@" 2>&1; fi
  fi
}

note "binfmt default for x86 ELF: ${BINFMT:-none}"
for who in fex box64; do
  run_under "$who" "$@" > "$OUT/$who.txt"; echo $? > "$OUT/$who.rc"
done
FRC=$(cat "$OUT/fex.rc"); BRC=$(cat "$OUT/box64.rc")

# Probes that emit raw bytes (an fnstenv image, say) are the norm here, not the
# exception -- a text diff on them is meaningless and `diff` just says "binary
# files differ", which tells the reader nothing.
show() {
  if LC_ALL=C grep -qP '[\x00-\x08\x0e-\x1f]' "$1" 2>/dev/null; then
    printf '  (binary, %s bytes)\n' "$(wc -c < "$1")"
    od -An -tx1 -v "$1" | sed 's/^/  /' | head -20
  else
    cat "$1"
  fi
}
hr; echo "FEX    (exit $FRC)"; hr; show "$OUT/fex.txt"
hr; echo "BOX64  (exit $BRC)"; hr; show "$OUT/box64.txt"
hr

# Box64 prints its own banners on stderr; they are not part of the result.
sed -E '/^\[?(BOX64|BOX32)\]?/d' "$OUT/box64.txt" > "$OUT/box64.clean"
sed -E '/^\[?(BOX64|BOX32)\]?/d' "$OUT/fex.txt"   > "$OUT/fex.clean"

if cmp -s "$OUT/fex.clean" "$OUT/box64.clean" && [ "$FRC" = "$BRC" ]; then
  echo "VERDICT: the two runtimes AGREE (exit $FRC)."
  echo "  If this output is CORRECT, both JITs are fine on this path."
  echo "  If it is WRONG, suspect the TEST before either translator — two"
  echo "  independent implementations rarely share a bug, and this project has"
  echo "  been burned by a self-clobbering test that failed identically on both."
  exit 0
fi
echo "VERDICT: the runtimes DISAGREE — the translator is implicated, not the test."
echo "  first difference:"
cmp "$OUT/fex.clean" "$OUT/box64.clean" 2>&1 | sed 's/^/    /'
if ! LC_ALL=C grep -qP '[\x00-\x08\x0e-\x1f]' "$OUT/fex.clean" 2>/dev/null; then
  diff "$OUT/fex.clean" "$OUT/box64.clean" | head -40 | sed 's/^/    /'
fi
exit 1
