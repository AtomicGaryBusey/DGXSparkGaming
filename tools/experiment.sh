#!/usr/bin/env bash
# experiment.sh — run one controlled experiment end to end, so its inputs are
# recorded rather than remembered.
#
# WHY THIS EXISTS
#   On 2026-09-07 the same five steps were done by hand for every DLSS run — set
#   config, clear old evidence, launch, watch, collect — with small variations each
#   time. Two consequences, both real:
#     * Two runs were contaminated by settings OptiScaler had persisted from the
#       user's overlay session (Style=1, WhitePointSource=2, an empty ScanAnchors).
#       Nobody knew they were set, so neither run could be attributed to its
#       intended variable. A clean re-run was needed to establish anything.
#     * A headline result was published from a counter that measured the wrong
#       thing, because "what was configured" and "what was observed" lived only in
#       a chat log, never side by side in one artifact.
#   This makes the inputs part of the output: config diff before, verdict after,
#   both in the same directory as the logs.
#
# WHAT IT DOES
#   1. refuses to start if the game is already running
#   2. snapshots every foreign-owned config file  (config-snapshot.sh)
#   3. applies --set edits to an ini, showing old -> new for each
#   4. clears the evidence paths you name, so nothing stale is read as fresh
#   5. waits for you to launch, then watches  (watch-run.sh)
#   6. diffs the config again — catches what the game rewrote DURING the run
#   7. writes everything to evidence/<name>-<stamp>/ with a report
#
# Usage:
#   tools/experiment.sh <name> \
#     --ini "$G/OptiScaler.ini" --set 'DlssNr:Enabled=true' --set 'DlssNr:RunBeforeSR=true' \
#     --clear "$G/OptiScaler.log" --clear "$G/dlssnr-capture" \
#     --log "$G/OptiScaler.log" --count 'NR=DLSS-NR running' --count 'devlost=DEVICE_LOST'
#
#   --dry-run    do everything except wait for the game (for testing this script)
set -uo pipefail
NAME="${1:-}"; shift || true
[ -z "$NAME" ] && { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

APPID=1091500; INI=""; LOG=""; DRY=0
declare -a SETS=() CLEARS=() COUNTS=() WATCHARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --appid) APPID="$2"; shift 2;;
    --ini) INI="$2"; shift 2;;
    --set) SETS+=("$2"); shift 2;;
    --clear) CLEARS+=("$2"); shift 2;;
    --log) LOG="$2"; shift 2;;
    --count) COUNTS+=("$2"); shift 2;;
    --dry-run) DRY=1; shift;;
    --interval|--dead-ticks|--dead-samples|--appear-timeout|--name|--min-threads) WATCHARGS+=("$1" "$2"); shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/dgx-gaming-work/evidence/$NAME-$STAMP"; mkdir -p "$OUT"
REPORT="$OUT/report.txt"
say(){ echo "$@" | tee -a "$REPORT"; }

# 1 — refuse to start on top of a running game; the ini would be rewritten on exit.
running() { local d pid cl t
  for d in /proc/[0-9]*; do pid=${d#/proc/}; [ "$pid" = "$$" ] && continue
    [ -r "$d/cmdline" ] || continue; cl=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
    case "$cl" in *"compatdata/$APPID"*|*"AppId=$APPID"*)
      t=$(ls "$d/task" 2>/dev/null | wc -l); [ "${t:-0}" -ge 20 ] && return 0;; esac
  done; return 1; }
if running; then echo "REFUSING: appid $APPID is already running — it rewrites its config on exit."; exit 1; fi

say "experiment: $NAME"
say "appid     : $APPID"
say "date      : $(date -Is)"
say ""

# 2 — snapshot config BEFORE
bash "$HERE/config-snapshot.sh" save "exp-$NAME" "$APPID" > "$OUT/config-before.txt" 2>&1
say "config snapshot saved ($(grep -c '^  /' "$OUT/config-before.txt" 2>/dev/null) files)"

# 3 — apply --set (Section:Key=Value). Re-reads the file first, by construction.
if [ ${#SETS[@]} -gt 0 ]; then
  [ -f "$INI" ] || { say "ERROR: --set given but --ini '$INI' is not a file"; exit 2; }
  say ""; say "config applied:"
  for s in "${SETS[@]}"; do
    SEC="${s%%:*}"; rest="${s#*:}"; KEY="${rest%%=*}"; VAL="${rest#*=}"
    OLDNEW=$(INI="$INI" SEC="$SEC" KEY="$KEY" VAL="$VAL" python3 - <<'PY'
import os,re
p=os.environ["INI"]; sec=os.environ["SEC"]; key=os.environ["KEY"]; val=os.environ["VAL"]
lines=open(p,encoding="utf-8",errors="replace").read().split("\n")
try: s=next(i for i,l in enumerate(lines) if l.strip()=="["+sec+"]")
except StopIteration: print("!! no section ["+sec+"]"); raise SystemExit
e=next((i for i in range(s+1,len(lines)) if lines[i].startswith("[")), len(lines))
for i in range(s+1,e):
    m=re.match(r'^\s*'+re.escape(key)+r'\s*=\s*(.*)$', lines[i])
    if m:
        print(f"{sec}:{key}  {m.group(1).strip()} -> {val}")
        lines[i]=f"{key} = {val}"
        open(p,"w",encoding="utf-8").write("\n".join(lines)); raise SystemExit
print(f"!! {sec}:{key} not found")
PY
)
    say "  $OLDNEW"
  done
fi

# 3b — snapshot again AFTER our edits. This is the intended baseline; diffing the
#      pre-edit one at the end would report our own --set changes as "drift", which
#      hides the thing we actually care about: what the GAME changed during the run.
bash "$HERE/config-snapshot.sh" save "exp-$NAME-armed" "$APPID" > "$OUT/config-armed.txt" 2>&1

# 4 — clear stale evidence. Reading a stale log as if it were fresh produced a
#     confidently wrong conclusion on 2026-09-07 ("OptiScaler was unloaded").
if [ ${#CLEARS[@]} -gt 0 ]; then
  say ""; say "cleared:"
  for c in "${CLEARS[@]}"; do rm -rf "$c" 2>/dev/null; say "  $c"; done
fi

# 5/6 — launch + watch
say ""
if [ "$DRY" = "1" ]; then
  say "[dry-run] skipping launch/watch"
  VERDICT="DRY-RUN"; RC=0
else
  say "NOW: launch appid $APPID from Steam. Do not touch the in-game overlay —"
  say "     overlay changes are persisted to the ini and will contaminate this run."
  say ""
  WA=( --appid "$APPID" )
  [ -n "$LOG" ] && WA+=( --log "$LOG" )
  for c in "${COUNTS[@]}"; do WA+=( --count "$c" ); done
  WA+=( "${WATCHARGS[@]+"${WATCHARGS[@]}"}" --report "$OUT/watch.txt" )
  bash "$HERE/watch-run.sh" "${WA[@]}" 2>&1 | tee -a "$REPORT"; RC=${PIPESTATUS[0]}
  VERDICT=$(grep -m1 '^verdict' "$OUT/watch.txt" 2>/dev/null | awk '{print $3}')
fi

# 7 — what changed DURING the run, and collect
say ""
say "config drift during the run:"
bash "$HERE/config-snapshot.sh" diff "exp-$NAME-armed" "$APPID" 2>&1 | tee "$OUT/config-drift.txt" | sed 's/^/  /' | tee -a "$REPORT"
[ -n "$LOG" ] && [ -f "$LOG" ] && cp "$LOG" "$OUT/$(basename "$LOG")" 2>/dev/null

say ""
say "verdict : ${VERDICT:-UNKNOWN}"
say "evidence: $OUT"
exit "${RC:-0}"
