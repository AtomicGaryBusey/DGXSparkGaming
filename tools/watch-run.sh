#!/usr/bin/env bash
# watch-run.sh — watch a running game: is it alive, is it hung, is the thing you
# care about actually happening?
#
# WHY THIS EXISTS
#   On 2026-09-07 this exact watcher was hand-written TEN times, once per launch,
#   and got it wrong twice:
#     * once it latched onto the agent's OWN shell, because the process pattern was
#       in that shell's command line (the safe-proc.sh problem, re-invented);
#     * once onto `steam-launch-wrapper` instead of the game — a 1-thread, 0% CPU
#       process that sat there looking alive while nothing happened.
#   It also repeatedly needed the same three lessons re-learned:
#     * `ps` %CPU is a LIFETIME AVERAGE. A hung process shows 228% and looks busy.
#       Only a delta of /proc/<pid>/stat utime+stime over a real interval is honest.
#     * The game is identified by THREAD COUNT, not by command line alone. Shells
#       and wrappers carry the same string; a real game here runs 70+ threads.
#     * "Is it hung" needs a measured floor, not a guess. Measured on this rig:
#       a live game holds 9,000-18,000 ticks per 15s sample; a deadlocked one held
#       10-23. Two orders of magnitude apart, so the threshold is not delicate.
#
# WHAT IT ADDS OVER `top`
#   Arbitrary --count probes: grep a log for a pattern and report the count each
#   sample. That is how you tell "the feature is running" from "the process is
#   alive", which is a distinction this project got publicly wrong once already:
#   3,483 NGX evaluates were reported as DLSS-5 Neural Rendering when they were the
#   game's own DLSS-SR. Count the SPECIFIC thing, and watch it move.
#
# Usage:
#   tools/watch-run.sh --appid 1091500 --name Cyberpunk2077.exe \
#       --log "$G/OptiScaler.log" \
#       --count 'NR=Dispatch DLSS-NR running' --count 'devlost=DEVICE_LOST'
#
#   --appid N            also match compatdata/N, shadercache/N, AppId=N
#   --name S             substring of the process cmdline (e.g. the exe name)
#   --min-threads N      thread floor for "this is the game" (default 20)
#   --log PATH           watch this file's size each sample
#   --count 'k=pat'      grep -c 'pat' in --log, reported as k (repeatable)
#   --interval N         seconds per sample (default 15)
#   --dead-ticks N       below this many CPU ticks per sample = dead (default 40)
#   --dead-samples N     consecutive dead samples before HUNG (default 6)
#   --appear-timeout N   seconds to wait for the process (default 600)
#   --report PATH        write a summary here (default under dgx-gaming-work/runs)
set -uo pipefail

APPID=""; NAME=""; MINTHREADS=20; LOG=""; INTERVAL=15
DEADTICKS=40; DEADSAMPLES=6; APPEAR=600; REPORT=""
declare -a CK=() CV=()
while [ $# -gt 0 ]; do
  case "$1" in
    --appid) APPID="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --min-threads) MINTHREADS="$2"; shift 2;;
    --log) LOG="$2"; shift 2;;
    --count) CK+=("${2%%=*}"); CV+=("${2#*=}"); shift 2;;
    --interval) INTERVAL="$2"; shift 2;;
    --dead-ticks) DEADTICKS="$2"; shift 2;;
    --dead-samples) DEADSAMPLES="$2"; shift 2;;
    --appear-timeout) APPEAR="$2"; shift 2;;
    --report) REPORT="$2"; shift 2;;
    -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -z "$APPID$NAME" ] && { echo "need --appid and/or --name" >&2; exit 2; }
[ -n "$REPORT" ] || { mkdir -p "$HOME/dgx-gaming-work/runs"; REPORT="$HOME/dgx-gaming-work/runs/watch-${APPID:-$NAME}-$(date +%Y%m%d-%H%M%S).txt"; }

# Find the game. Thread count is the discriminator: this script's own shell, and
# any sibling agent shell carrying the same pattern, has one thread.
find_pid() {
  local d pid cl t
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    [ "$pid" = "$$" ] && continue
    [ -r "$d/cmdline" ] || continue
    cl=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
    local hit=""
    [ -n "$NAME" ]  && case "$cl" in *"$NAME"*) hit=1;; esac
    [ -n "$APPID" ] && case "$cl" in *"compatdata/$APPID"*|*"shadercache/$APPID"*|*"AppId=$APPID"*) hit=1;; esac
    [ -z "$hit" ] && continue
    t=$(ls "$d/task" 2>/dev/null | wc -l)
    [ "${t:-0}" -ge "$MINTHREADS" ] && { printf '%s' "$pid"; return 0; }
  done
  return 1
}
ticks()  { awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null || echo 0; }
rss()    { awk '/VmRSS/{print $2}' "/proc/$1/status" 2>/dev/null || echo 0; }
logsz()  { [ -n "$LOG" ] && [ -f "$LOG" ] && stat -c%s "$LOG" 2>/dev/null || echo 0; }
# NOTE: `n=$(grep -c ... || echo 0)` is WRONG — grep prints "0" and exits 1 when
# there are no matches, so BOTH zeros land inside the substitution and the sample
# line comes out mangled across two rows. Assign, then default.
counts() {
  local i n out=""
  for i in "${!CK[@]}"; do
    n=0
    if [ -n "$LOG" ] && [ -f "$LOG" ]; then
      n=$(grep -c -- "${CV[$i]}" "$LOG" 2>/dev/null) || true
      n=${n//[!0-9]/}; n=${n:-0}
    fi
    out="$out ${CK[$i]}=$n"
  done
  printf '%s' "$out"
}

echo "waiting for process (appid='${APPID:-n/a}' name='${NAME:-n/a}' min-threads=$MINTHREADS, ${APPEAR}s)..."
PID=""; w=0
while [ "$w" -lt "$APPEAR" ]; do PID=$(find_pid) && break; sleep 3; w=$((w+3)); done
[ -z "$PID" ] && { echo "process never appeared within ${APPEAR}s"; echo "verdict: NOT-SEEN" > "$REPORT"; exit 1; }
echo "pid $PID  threads=$(ls /proc/$PID/task 2>/dev/null | wc -l)"
[ -n "$LOG" ] && echo "log: $LOG"

prev=$(ticks "$PID"); dead=0; n=0; verdict="UNKNOWN"; peak=0
: > "$REPORT"
while [ -d "/proc/$PID" ]; do
  sleep "$INTERVAL"
  cur=$(ticks "$PID"); [ "$cur" = "0" ] && [ ! -d "/proc/$PID" ] && break
  d=$((cur - prev)); prev=$cur; n=$((n+1))
  [ "$d" -gt "$peak" ] && peak=$d
  line=$(printf '[%02d] cpu=%-7s rss=%-9s log=%-9s%s' "$n" "$d" "$(rss "$PID")k" "$(logsz)" "$(counts)")
  if [ "$d" -lt "$DEADTICKS" ]; then dead=$((dead+1)); line="$line  DEAD $dead/$DEADSAMPLES"; else dead=0; fi
  echo "  $line" | tee -a "$REPORT" >/dev/null; echo "  $line"
  [ "$dead" -ge "$DEADSAMPLES" ] && { verdict="HUNG"; break; }
done
[ "$verdict" = "UNKNOWN" ] && verdict="EXITED"

{
  echo
  echo "verdict : $verdict"
  echo "pid     : $PID"
  echo "samples : $n   interval=${INTERVAL}s   dead<${DEADTICKS} ticks x${DEADSAMPLES}"
  echo "peak cpu: $peak ticks/sample"
  [ -n "$LOG" ] && echo "log     : $LOG ($(logsz) bytes)"
  [ ${#CK[@]} -gt 0 ] && echo "counters:$(counts)"
  echo "date    : $(date -Is)"
} | tee -a "$REPORT"
echo "report: $REPORT"
[ "$verdict" = "HUNG" ] && exit 3 || exit 0
