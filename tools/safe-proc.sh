#!/usr/bin/env bash
# safe-proc.sh — list / wait-for / kill processes by pattern, WITHOUT ever
# matching yourself.
#
# WHY THIS EXISTS
#   `pgrep -f foo` and `pkill -f foo` match any process whose command line
#   contains "foo" — including the shell that is running the command, because
#   the pattern is *in* that command line. Consequences seen in this project:
#     * `until ! pgrep -f 'child-update-ui'; do sleep 10; done` never exited.
#       Two such watchers spun for ~80 minutes each.
#     * `pkill -f 'appmanifest_750920.acf'` killed the replacement monitor it
#       had just started, along with the one it meant to kill.
#     * `pkill -f 'xwin --accept-license'` killed the shell mid-heredoc,
#       destroying the script being written.
#   That is three occurrences, twice AFTER writing a rule saying not to do it.
#   Rules did not work; this does, by construction:
#     - matches are read from /proc/<pid>/cmdline, then filtered by PID
#     - this script, its shell, and its ENTIRE ancestor chain are excluded
#     - so the pattern appearing in our own command line cannot match us
#
#   Two bugs this tool's own self-test caught, both worth knowing:
#     1. Excluding ancestors is NOT enough. `x=$(matches)` forks a subshell that
#        inherits our command line but has a new pid — so descendants must be
#        excluded too.
#     2. /proc/<pid>/stat field 4 is not reliably ppid: comm can contain spaces
#        and parens ("(Compositor Event)"), shifting every later field. Use
#        /proc/<pid>/status PPid: instead.
#
# Usage:
#   tools/safe-proc.sh list <pattern>
#   tools/safe-proc.sh wait <pattern>          # blocks until none remain
#   tools/safe-proc.sh kill <pattern> [-9]     # DRY_RUN=1 to preview
set -uo pipefail
CMD="${1:-}"; PAT="${2:-}"; SIG="${3:--TERM}"
[ -n "$CMD" ] && [ -n "$PAT" ] || { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

# Every PID we must never touch: self, our shell, and all ancestors up to init.
# NOTE: ancestors alone are NOT enough. `x=$(matches)` forks a subshell that
# inherits our command line (so it matches the pattern) but has a NEW pid that
# is not an ancestor. Found by this tool's own self-test. We therefore also
# reject any candidate whose ancestry passes through us — i.e. our descendants.
build_exclusions() {
  local p=$$ guard=0
  SELF=$$
  EXCL=" $$ $PPID "
  while [ "$p" -gt 1 ] && [ "$guard" -lt 40 ]; do
    p=$(awk '/^PPid:/{print $2}' "/proc/$p/status" 2>/dev/null) || break
    [ -z "$p" ] && break
    EXCL="$EXCL $p "
    guard=$((guard+1))
  done
}
build_exclusions

# Is $1 us, an ancestor of ours, or a descendant of ours?
is_ours() {
  local p="$1" guard=0
  # (a) exactly us, or one of our direct ancestors
  case "$EXCL" in *" $p "*) return 0;; esac
  # (b) a DESCENDANT of us (catches $(subshells) that inherit our cmdline).
  #     Only stop at SELF — checking EXCL here would also exclude our SIBLINGS,
  #     i.e. anything launched from the same shell, which is exactly what we
  #     usually want to kill. (Caught by the self-test: the tool found nothing.)
  while [ "${p:-0}" -gt 1 ] 2>/dev/null && [ "$guard" -lt 40 ]; do
    p=$(awk '/^PPid:/{print $2}' "/proc/$p/status" 2>/dev/null) || return 1
    [ -z "$p" ] && return 1
    [ "$p" = "$SELF" ] && return 0
    guard=$((guard+1))
  done
  return 1
}

# Match on /proc/<pid>/cmdline, excluding our own lineage AND descendants.
matches() {
  local pid cl
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    is_ours "$pid" && continue
    [ -r "$d/cmdline" ] || continue
    cl=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
    [ -z "$cl" ] && continue
    case "$cl" in *"$PAT"*) printf '%s\t%s\n' "$pid" "${cl:0:110}";; esac
  done
}

case "$CMD" in
  list) matches ;;
  wait)
    while [ -n "$(matches)" ]; do sleep 5; done
    echo "none matching '$PAT' remain" ;;
  kill)
    found=$(matches)
    [ -z "$found" ] && { echo "nothing matches '$PAT'"; exit 0; }
    echo "$found" | sed 's/^/  would kill: /'
    if [ "${DRY_RUN:-0}" = 1 ]; then echo "  (DRY_RUN=1, nothing killed)"; exit 0; fi
    echo "$found" | cut -f1 | xargs -r kill "$SIG" 2>/dev/null
    sleep 2
    left=$(matches)
    if [ -n "$left" ]; then
      echo "$left" | sed 's/^/  survived: /'
      [ "$SIG" = "-9" ] || echo "  (re-run with -9 to force)"
      exit 1
    fi
    echo "  all matching processes gone; this shell survived" ;;
  *) echo "unknown command: $CMD"; exit 2 ;;
esac
