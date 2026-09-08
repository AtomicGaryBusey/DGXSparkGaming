#!/usr/bin/env bash
# ab-runtime.sh — run one title under BOTH JITs and put the results side by side.
#
# WHY THIS EXISTS
#   On 2026-09-07 the two translators were found to disagree completely on an
#   id Tech 4 title: with Proton, container, prefix and config identical, Box64
#   played Quake 4 (menu, map load, weapons) while FEX failed at SetPixelFormat
#   before it could create a GL context. Nothing in this log had ever recorded
#   which JIT ran a game, so every historical id Tech 4 result is of unknown
#   provenance.
#
#   Doing that comparison by hand took ~12 commands per title and produced two
#   impatient misreads. This does it in one, and each side leaves a run.json
#   naming the JIT that actually executed it.
#
#   It also enforces the rule the comparison exists to serve: if BOTH runtimes
#   fail IDENTICALLY, suspect the TEST before the translators. Two independent
#   JITs rarely share a bug — a hook test here once failed the same way under
#   both because it clobbered its own jump target.
#
# Usage:
#   tools/ab-runtime.sh <appid> [seconds]     (default 100s per side)
#   ORDER='fex box64' tools/ab-runtime.sh 2210
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APPID="${1:-}"; SECS="${2:-100}"
[ -n "$APPID" ] || { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
ORDER="${ORDER:-box64 fex}"
OUT="${OUT:-$HOME/dgx-gaming-work/runs}"

declare -A DIR
for rt in $ORDER; do
  echo "############################################################"
  echo "### $APPID under $rt (${SECS}s)"
  echo "############################################################"
  systemctl --user reset-failed "game-$APPID.scope" >/dev/null 2>&1 || true
  # Clear the engine log so the report cannot read a PREVIOUS run's output --
  # exactly the mistake that lost the provenance of the original x87 crash.
  M="$HOME/.local/share/Steam/steamapps/appmanifest_$APPID.acf"
  INST=$(sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" 2>/dev/null | head -1)
  [ -n "$INST" ] && find "$HOME/.local/share/Steam/steamapps/common/$INST" \
        -maxdepth 3 -iname 'qconsole.log' -delete 2>/dev/null
  SECONDS_MAX="$SECS" RUNTIME="$rt" "$REPO/tools/game-run.sh" "$APPID" 2>&1 \
    | grep -E 'runtime:|runtime ACTUALLY|manifest:|never saw a live|game is up' | sed 's/^/  /'
  DIR[$rt]=$(ls -dt "$OUT/$APPID-"* 2>/dev/null | head -1)
done

echo
echo "############################################################"
echo "### COMPARISON"
echo "############################################################"
for rt in $ORDER; do "$REPO/tools/run-report.sh" "${DIR[$rt]}"; done

# Same-failure check: the whole point of running both.
same=1; first=""
for rt in $ORDER; do
  q=$(ls "${DIR[$rt]}"/*qconsole.log 2>/dev/null | head -1)
  if [ -n "$q" ]; then
    sig=$(grep -cE 'FPU stack is not empty|SetPixelFormat failed|Unable to initialize OpenGL' "$q" 2>/dev/null)
  else
    sig="nolog"
  fi
  [ -z "$first" ] && first="$sig"
  [ "$sig" != "$first" ] && same=0
done
echo
if [ "$same" = 1 ]; then
  echo "NOTE: both runtimes behaved the SAME. Two independent JITs rarely share a"
  echo "bug — suspect the TEST, the game, or the environment before the translators."
else
  echo "NOTE: the runtimes DIFFER. The translator is implicated, not the test."
  echo "Quote runtime_actual from run.json in any README entry for this title."
fi
