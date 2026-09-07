#!/usr/bin/env bash
# capture-hang.sh — snapshot a deadlocked Proton/FEX game so the lock can be NAMED.
#
# WHY THIS EXISTS
#   On 2026-09-06 a ReShade-induced deadlock in Cyberpunk 2077 was diagnosed twice
#   from surface evidence, and the diagnosis was wrong both times:
#     1. "the NR pass hangs the game"  — refuted by a four-layer bisection; ReShade
#        alone hangs it with no NR code in the process at all.
#     2. "ReShade refuses to load PhysX, so the game waits forever" — refuted by
#        ReShade's own source: hook_manager.cpp calls the real LoadLibrary
#        unconditionally and returns its handle. Nothing is refused.
#   Both readings were plausible, cheap, and false. The missing evidence each time
#   was the same: WHAT ARE THE PARKED THREADS ACTUALLY WAITING ON. This captures
#   that, so the next claim is read off a stack instead of inferred from a log line.
#
# WHAT IT CAPTURES (all read-only; the process is left running)
#   - wchan census for every thread of the game AND of wineserver
#   - /proc/<pid>/status state + thread counts
#   - gdb "thread apply all bt" for both
#
# WHY WINESERVER TOO
#   The 2026-09-06 hang showed 62 of 71 game threads in `anon_pipe_read`. Wine
#   threads talk to wineserver over a socketpair and block reading the reply — so
#   a mass park in anon_pipe_read points at wineserver, not at the game. Capturing
#   only the game would have missed the actual holder.
#
# REQUIREMENT
#   ptrace_scope must be 0 to attach to a process Steam launched (it is not our
#   descendant). Check with:  cat /proc/sys/kernel/yama/ptrace_scope
#   Set with:                 sudo sysctl -w kernel.yama.ptrace_scope=0
#   Restore with:             sudo sysctl -w kernel.yama.ptrace_scope=1
#   Without it the wchan census still works; only the backtraces are skipped.
#
# STATUS: RUN 2026-09-07 on a stalled Cyberpunk process. PARTIALLY USEFUL, and the limitation
#   matters: gdb attached fine and captured all 78 threads, but **every frame was an
#   unsymbolizable FEX JIT address** -- zero resolved symbols. Under FEX this tool gives you
#   the wchan census (which is genuinely useful: 33 futex_wait_multiple + 33 futex_do_wait +
#   10 poll = a CPU-side stall, not a GPU wait) but it will NOT name the lock. Do not plan a
#   diagnosis around its backtraces on a translated process.
#
# Usage:  tools/capture-hang.sh [label]
#
set -u
LABEL="${1:-hang}"
OUT="$HOME/dgx-gaming-work/evidence"
mkdir -p "$OUT"
STAMP="$(date +%Y%m%d-%H%M%S)"
F="$OUT/stacks-$LABEL-$STAMP.txt"

# Find the game by THREAD COUNT, never by command line alone: this script's own
# arguments contain the pattern, and sibling agent shells match it too (that cost
# a bogus verdict on 2026-09-06).
find_game() {
  local d p c t
  for d in /proc/[0-9]*; do
    p=${d#/proc/}; [ -r "$d/cmdline" ] || continue
    c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$c" in
      *.exe*) t=$(ls "$d/task" 2>/dev/null | wc -l)
              [ "${t:-0}" -gt 20 ] && { printf '%s' "$p"; return 0; };;
    esac
  done
  return 1
}
find_wineserver() {
  local d p c
  for d in /proc/[0-9]*; do
    p=${d#/proc/}; [ -r "$d/cmdline" ] || continue
    c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$c" in *wineserver*) printf '%s' "$p"; return 0;; esac
  done
  return 1
}

dump_one() { # $1=pid $2=name
  local pid="$1" name="$2"
  [ -d "/proc/$pid" ] || { echo "== $name: not running =="; return; }
  echo "=================================================================="
  echo "== $name  pid=$pid  threads=$(ls /proc/$pid/task 2>/dev/null | wc -l)"
  echo "=================================================================="
  awk '/^(Name|State|Threads):/' "/proc/$pid/status" 2>/dev/null
  echo "-- cpu ticks (utime+stime): $(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null)"
  echo
  echo "-- wchan census (what every thread is blocked in):"
  for x in /proc/$pid/task/*; do cat "$x/wchan" 2>/dev/null; echo; done \
    | sort | uniq -c | sort -rn
  echo
  if [ "$PTRACE_OK" = "yes" ]; then
    echo "-- gdb thread apply all bt (host/ARM64 frames; FEX JIT frames will be bare addresses):"
    timeout 180 gdb -p "$pid" -batch -nx \
        -ex 'set pagination off' -ex 'set confirm off' \
        -ex 'thread apply all bt' -ex 'detach' 2>&1 | sed 's/^/   /'
  else
    echo "-- backtraces SKIPPED: ptrace_scope=$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null)"
    echo "   run: sudo sysctl -w kernel.yama.ptrace_scope=0   then re-run this script"
  fi
  echo
}

PS_SCOPE="$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo 1)"
[ "$PS_SCOPE" = "0" ] && PTRACE_OK=yes || PTRACE_OK=no

GAME="$(find_game || true)"
WS="$(find_wineserver || true)"
[ -z "$GAME" ] && { echo "No game process found (need >20 threads and a .exe cmdline)."; exit 1; }

{
  echo "capture: $LABEL"
  echo "date:    $(date -Is)"
  echo "ptrace:  scope=$PS_SCOPE  backtraces=$PTRACE_OK"
  echo "load:    $(uptime)"
  echo
  dump_one "$GAME" "GAME"
  [ -n "$WS" ] && dump_one "$WS" "WINESERVER" || echo "== wineserver: not found =="
} > "$F" 2>&1

echo "saved: $F"
echo
grep -A8 '^-- wchan census' "$F" | head -30
