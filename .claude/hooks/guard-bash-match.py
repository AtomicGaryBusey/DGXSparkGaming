#!/usr/bin/env python3
"""Decide whether a Bash command should be blocked. Reads the command on stdin,
prints a rule id (or nothing) and exits 0.

Split out of guard-bash.sh because the first version matched plain substrings and
fired on its OWN documentation: a command that WROTE the words "pgrep -f" into a
README row was blocked as if it were running them. A hook that cries wolf gets
switched off, which is worse than no hook.

Two rules make the matching honest:
  1. heredoc bodies are stripped  — that is where docs, scripts and commit
     messages live, and none of it is a command being run
  2. a tool only counts at a COMMAND POSITION — start of line, or after one of
     ; & | ( ) { } && || $( then do else
"""
import re
import sys

HEREDOC = re.compile(r"<<-?\s*[\"']?([A-Za-z_][A-Za-z0-9_]*)[\"']?")
CMDPOS = r"(?:^|[;&|(){}]|\$\(|&&|\|\||\bthen\b|\bdo\b|\belse\b)\s*(?:sudo\s+)?[\"']?"


def mask_quoted(s: str) -> str:
    """Blank out quoted text that is DATA, keeping quoted text that is a COMMAND.

    Needed because bash command separators occur inside ordinary prose. On
    2026-09-07 the string

        echo "=== control run (steam -applaunch, warm prefix) ==="

    was blocked, because the "(" inside the message is a real command position
    (a subshell) as far as a regex is concerned. Prose is not a command.

    But a quoted string CAN be the command:

        "$STEAM/ubuntu12_32/steam" -applaunch 2210

    so quotes are only blanked when the opening quote is NOT itself at a command
    position. Length is preserved so that offsets and CMDPOS anchors still line
    up with the original text.
    """
    out = list(s)
    i, n = 0, len(s)
    while i < n:
        ch = s[i]
        if ch not in "\"'":
            i += 1
            continue
        # is this opening quote in command position? look back over blanks
        j = i - 1
        while j >= 0 and s[j] in " \t":
            j -= 1
        at_cmd = j < 0 or s[j] in ";&|(){}\n" or s[max(0, j - 1):j + 1] in ("&&", "||")
        k = s.find(ch, i + 1)
        if k < 0:
            break
        if not at_cmd:
            for m in range(i + 1, k):
                if s[m] not in " \t\n":
                    out[m] = "_"
        i = k + 1
    return "".join(out)


def strip_heredocs(s: str) -> str:
    out, lines, i = [], s.split("\n"), 0
    while i < len(lines):
        m = HEREDOC.search(lines[i])
        out.append(lines[i])
        if m:
            term = m.group(1)
            i += 1
            while i < len(lines) and lines[i].strip() != term:
                i += 1
        i += 1
    return "\n".join(out)


def main() -> None:
    cmd = sys.stdin.read()
    if "HOOK_OVERRIDE:" in cmd:
        return
    c = mask_quoted(strip_heredocs(cmd))

    # 1. pgrep -f / pkill -f: matches the invoking shell, because the pattern is in
    #    that shell's own command line. Three occurrences in this project, twice
    #    after a written rule forbade it.
    if re.search(CMDPOS + r"(?:pgrep|pkill)\b[^;&|\n]*\s-\w*f\b", c, re.M):
        print("procmatch")
        return

    # 2. `timeout` around a game launch. Killing the launcher does not kill the
    #    game: Wine reparents and the tree keeps burning CPU. Narrow on purpose —
    #    timeout around gdb, curl or the wine harnesses is legitimate and common.
    if re.search(CMDPOS + r"timeout\b", c, re.M) and re.search(
        r"game-run\.sh|-applaunch|steam\.sh", c
    ):
        print("timeout-launch")
        return

    # 3. Hand-launching a game: no cgroup scope, no telemetry, no pre-flight.
    #    This rule USED to be a bare substring match for "-applaunch", with no
    #    command-position requirement -- unlike rules 1 and 2. On 2026-09-07 it
    #    duly blocked `echo "=== control run (steam -applaunch, warm prefix) ==="`,
    #    i.e. a string being PRINTED, which is the exact "hook cries wolf, gets
    #    switched off" failure this file's header warns about. It now requires an
    #    actual steam command at a command position with -applaunch as its
    #    argument, so writing about the flag is fine and running it is not.
    if re.search(CMDPOS + r"(?:\S*/)?steam(?:\.sh)?[\"']?\s[^;&|\n]*?-applaunch\b", c, re.M) \
            and not re.search(r"game-run\.sh", c):
        print("applaunch")
        return


if __name__ == "__main__":
    main()
