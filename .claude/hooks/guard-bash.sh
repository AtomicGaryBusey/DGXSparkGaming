#!/usr/bin/env bash
# guard-bash.sh — PreToolUse hook. Blocks the Bash commands this project has
# repeatedly harmed itself with, BY CONSTRUCTION rather than by asking nicely.
#
# WHY THIS EXISTS
#   CLAUDE.md already says it: "Rules did not work; this does, by construction."
#   That was written about safe-proc.sh, after `pgrep -f`/`pkill -f` self-matched
#   THREE times -- twice AFTER a written rule forbade it. On 2026-09-07 the agent
#   then wrapped a game launch in `timeout`, violating rule #1, the first line of
#   the process-hygiene section it had read at session start.
#
#   Prose in a context window is not an enforcement mechanism. This is.
#
# MATCHING LIVES IN guard-bash-match.py
#   The first version matched plain substrings and fired on its OWN documentation:
#   a command that WROTE the words "pgrep -f" into a README row was blocked as if
#   it were running them. A hook that cries wolf gets switched off, which is worse
#   than no hook. The matcher now strips heredoc bodies (docs, scripts and commit
#   messages live there) and requires a real command position.
#
# CONTRACT
#   stdin: JSON with .tool_name and .tool_input.command
#   exit 0 -> allow.  exit 2 -> BLOCK, and stderr is shown to the model.
#
# ESCAPE HATCH
#   Append  # HOOK_OVERRIDE: <reason>  to the command. Deliberate, visible in the
#   transcript, and requires stating why -- which is the point. Silent bypass is
#   not available.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get("tool_input",{}).get("command","") if d.get("tool_name")=="Bash" else "")
except Exception: print("")' 2>/dev/null)"
[ -z "$CMD" ] && exit 0

RULE="$(printf '%s' "$CMD" | python3 "$HERE/guard-bash-match.py" 2>/dev/null)"
[ -z "$RULE" ] && exit 0

block() {
  printf 'BLOCKED by .claude/hooks/guard-bash.sh\n\n%s\n\n' "$1" >&2
  printf 'Use instead: %s\n' "$2" >&2
  printf 'If this is genuinely a special case, append:  # HOOK_OVERRIDE: <reason>\n' >&2
  exit 2
}

case "$RULE" in
  procmatch)
    block "A process match by full command line matches YOUR OWN shell — the pattern appears in its command line. This happened 3x here, twice after a written rule forbade it, killing a monitor and a shell mid-heredoc." \
          "tools/safe-proc.sh {list|wait|kill} <pattern>  (excludes self, ancestors and descendants by construction)" ;;
  timeout-launch)
    block "A game launch is wrapped in \`timeout\`. Rule #1: killing the launcher does not kill the game — Wine reparents the tree and <game>.exe + wineserver keep running. This orphaned a Wine tree for 1h46m at 501% CPU once." \
          "tools/game-run.sh <appid>  (cgroup scope teardown), or SECONDS_MAX=<n> for a time-boxed run" ;;
  applaunch)
    block "Hand-launching a game with \`steam -applaunch\`. No cgroup scope (so no atomic teardown), no telemetry, no pre-flight — and this is exactly how the 1h46m orphan happened." \
          "tools/game-run.sh <appid>" ;;
esac
exit 0
