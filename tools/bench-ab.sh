#!/usr/bin/env bash
# bench-ab.sh — A/B two Proton versions on one title and produce NUMBERS.
#
# WHY THIS EXISTS
#   The Half-Life 2 Proton 10-vs-11 finding in this log is real but recorded as
#   "smooth" vs "markedly choppier" — unfalsifiable, and not reproducible by anyone
#   else. This runs the comparison properly and emits frametime statistics.
#
#   It encodes the two method rules that were learned the hard way:
#     1. TAKE THE SECOND RUN of each version. Switching Proton empties
#        shadercache/<appid>/DXVK_state_cache/, so a first run measures shader
#        compilation, not the runtime. The first HL2 comparison was worthless for
#        exactly this reason (and Fossilize was saturating 20 cores at the time).
#     2. IDLE THE BOX. These are CPU-translated workloads on a machine whose Steam
#        UI also renders on the CPU; background load contaminates everything.
#
#   Requires mangohud for CSV output. Without it you get DXVK_HUD on screen only,
#   which is better than adjectives but not comparable across runs.
#
# Usage:  tools/bench-ab.sh <appid> <proton_a> <proton_b> [seconds_per_run]
#   e.g.  tools/bench-ab.sh 220 proton_10 proton_11 120
#
# NOTE: switching the compat tool requires Steam to be CLOSED (config.vdf is
# rewritten on exit). This script tells you when; it will not kill Steam for you.
set -uo pipefail
APPID="${1:-}"; A="${2:-}"; B="${3:-}"; SECS="${4:-120}"
[ -n "$APPID" ] && [ -n "$A" ] && [ -n "$B" ] || { echo "usage: $0 <appid> <proton_a> <proton_b> [seconds]"; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HOME/dgx-gaming-work/bench/$APPID-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"

command -v mangohud >/dev/null || echo "!! mangohud not installed — no CSV, results will not be comparable"
# asort() is a gawk extension; mawk (Ubuntu's other default) lacks it and would
# silently produce no statistics. Fail loudly instead.
AWK=$(command -v gawk || true)
[ -n "$AWK" ] || { echo "!! gawk required for frametime statistics (asort). sudo apt install gawk"; exit 2; }

cat <<EOF
This will run $APPID twice per Proton version ($A, $B), ${SECS}s each,
discarding the first run of each as cache-warming.

For each version you must, with STEAM CLOSED:
  1. set CompatToolMapping "$APPID" -> "name" "<version>" in
     ~/.local/share/Steam/config/config.vdf
  2. restart Steam
Then press Enter here to run the pair.
EOF

stats() { # $1 = mangohud csv
  [ -f "$1" ] || { echo "    (no csv)"; return; }
  "$AWK" -F, 'NR>3 && $2+0>0 { ft[n++]=$2+0; s+=$2 }
    END{ if(!n){print "    (no frames)";exit}
      asort(ft); printf "    frames=%d  avg=%.1f FPS  1%%low=%.1f FPS  median=%.2f ms  p99=%.2f ms\n",
        n, 1000/(s/n), 1000/ft[int(n*0.99)], ft[int(n*0.5)], ft[int(n*0.99)] }' "$1" 2>/dev/null \
  || echo "    (awk asort unavailable — raw csv at $1)"
}

for V in "$A" "$B"; do
  echo
  echo "=== $V ==="
  read -r -p "Set compat tool to '$V' (Steam closed), restart Steam, then press Enter... " _
  for RUN in 1 2; do
    label=$([ "$RUN" = 1 ] && echo "warm-up (DISCARDED)" || echo "MEASURED")
    echo "  run $RUN/2 — $label"
    OUT="$OUT" SECONDS_MAX="$SECS" "$HERE/game-run.sh" "$APPID" >/dev/null 2>&1
    sleep 5
  done
  csv=$(ls -t "$OUT"/*/*.csv 2>/dev/null | head -1)
  echo "  $V results:"; stats "$csv"
  cp "$csv" "$OUT/result-$V.csv" 2>/dev/null
done

echo
echo "=== summary ==="
for V in "$A" "$B"; do echo "  $V:"; stats "$OUT/result-$V.csv"; done
echo "  raw: $OUT"
echo
echo "Record the winner in README's Tested-by-AGB table WITH the Proton version."
