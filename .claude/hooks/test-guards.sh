#!/usr/bin/env bash
# test-guards.sh — the guard hooks' own regression suite.
#
# WHY THIS EXISTS
#   These hooks were tested by hand when written, and the cases were not kept.
#   On 2026-09-07 rule 3 of guard-bash-match.py — the only rule without a
#   command-position requirement — blocked a plain `echo` that merely CONTAINED
#   the words it guards against. That is the "hook cries wolf, gets switched off"
#   failure the matcher's own header warns about, and it shipped because nothing
#   re-ran the cases after an edit.
#
#   Every case below is either a real command this project runs or a real
#   false positive that actually happened. Run after ANY hook edit:
#       .claude/hooks/test-guards.sh
set -uo pipefail
cd "$(dirname "$0")"
pass=0; fail=0

# want = the rule id expected on stdout, or "" for "must be allowed"
check() {
  local want="$1" desc="$2" cmd="$3" got
  got=$(printf '%s' "$cmd" | python3 guard-bash-match.py 2>/dev/null)
  if [ "$got" = "$want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf '  FAIL  %s\n        want=%-14s got=%-14s\n        cmd: %s\n' \
      "$desc" "${want:-<allow>}" "${got:-<allow>}" "$cmd"
  fi
}

echo "== must BLOCK =="
check procmatch      "pgrep -f"                      'pgrep -f Cyberpunk2077.exe'
check procmatch      "pkill -f"                      'pkill -f wineserver'
check procmatch      "pkill -9 -f"                   'pkill -9 -f foo'
check procmatch      "pgrep after &&"                'true && pgrep -f foo'
check timeout-launch "timeout + game-run.sh"         'timeout 300 tools/game-run.sh 2210'
check timeout-launch "timeout + steam.sh"            'timeout 60 ./steam.sh'
check applaunch      "bare steam -applaunch"         'steam -applaunch 2210'
check applaunch      "full path steam -applaunch"    '"$STEAM/ubuntu12_32/steam" -applaunch 2210'
check applaunch      "steam -applaunch after &&"     'cd /tmp && steam -applaunch 220'

echo "== must ALLOW =="
check "" "echo mentioning -applaunch (the 2026-09-07 false positive)" \
      'echo "=== control run (steam -applaunch, warm prefix) ==="'
check "" "documenting pgrep -f in a heredoc" \
      "cat > README.md <<'X'
never use pgrep -f here
X"
check "" "writing about pkill -f in an echo" \
      'echo "rule 2: never pkill -f a pattern in your own cmdline"'
check "" "game-run.sh itself (contains -applaunch internally)" \
      'bash tools/game-run.sh 2210'
check "" "LAUNCH_VIA=steam through game-run.sh" \
      'SECONDS_MAX=200 LAUNCH_VIA=steam tools/game-run.sh 2210'
check "" "timeout around a non-game command" \
      'timeout 40 gdb -p 1234 -batch -ex bt'
check "" "timeout around curl" \
      'timeout 30 curl -sSL https://example.com'
check "" "safe-proc.sh, the sanctioned replacement" \
      'MIN_THREADS=20 tools/safe-proc.sh list Quake4.exe'
check "" "grep -f is not pgrep -f" \
      'grep -f patterns.txt input.txt'
check "" "explicit override" \
      'pkill -f something  # HOOK_OVERRIDE: tearing down a wedged test harness'
check "" "a variable named applaunch in prose" \
      'echo "steam://launch is not the same as applaunch"'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "all guard cases pass"
