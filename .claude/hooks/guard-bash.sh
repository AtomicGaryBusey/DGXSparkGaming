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
# CONTRACT
#   stdin: JSON with .tool_name and .tool_input.command
#   exit 0 -> allow.  exit 2 -> BLOCK, and stderr is shown to the model.
#
# ESCAPE HATCH
#   Append  # HOOK_OVERRIDE: <reason>  to the command. Deliberate, visible in the
#   transcript, and requires stating why -- which is the point. Silent bypass is
#   not available.
set -uo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    if d.get("tool_name")!="Bash": print("");
    else: print(d.get("tool_input",{}).get("command",""))
except Exception: print("")' 2>/dev/null)"

[ -z "$CMD" ] && exit 0
case "$CMD" in *"HOOK_OVERRIDE:"*) exit 0;; esac

block() {
  printf 'BLOCKED by .claude/hooks/guard-bash.sh\n\n%s\n\n' "$1" >&2
  printf 'Use instead: %s\n' "$2" >&2
  printf 'If this is genuinely a special case, append:  # HOOK_OVERRIDE: <reason>\n' >&2
  exit 2
}

# 1. `timeout` wrapping a game launch. Killing the launcher does NOT kill the game:
#    Wine reparents and the tree keeps burning CPU. Only matches unambiguous game
#    launches, so `timeout` around gdb/curl/wine-harnesses stays allowed.
case "$CMD" in
  *timeout*)
    case "$CMD" in
      *game-run.sh*|*-applaunch*|*steam.sh*)
        block "A game launch is wrapped in \`timeout\`. Rule #1: killing the launcher does not kill the game — Wine reparents the tree and <game>.exe + wineserver keep running. This orphaned a Wine tree for 1h46m at 501% CPU once." \
              "tools/game-run.sh <appid>  (it tears down via a cgroup scope), or SECONDS_MAX=<n> for a time-boxed run" ;;
    esac ;;
esac

# 2. pgrep -f / pkill -f — matches the invoking shell, because the pattern is IN
#    that shell's command line. Three occurrences in this project.
case "$CMD" in
  *"pkill -f"*|*"pkill  -f"*|*"pgrep -f"*|*"pgrep  -f"*)
    block "\`pgrep -f\` / \`pkill -f\` match your own shell — the pattern appears in its command line. This happened 3x here, twice after a written rule forbade it, killing a monitor and a shell mid-heredoc." \
          "tools/safe-proc.sh {list|wait|kill} <pattern>  (excludes self, ancestors and descendants by construction)" ;;
esac

# 3. Hand-launching a game. game-run.sh gives cgroup teardown, telemetry and
#    pre-flight; a bare applaunch gives none of it and orphans on failure.
case "$CMD" in
  *-applaunch*)
    case "$CMD" in
      *game-run.sh*) ;;
      *)
        block "Hand-launching a game with \`steam -applaunch\`. No cgroup scope (so no atomic teardown), no telemetry, no pre-flight — and this is exactly how the 1h46m orphan happened." \
              "tools/game-run.sh <appid>" ;;
    esac ;;
esac

exit 0
