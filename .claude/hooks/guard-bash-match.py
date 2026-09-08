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
CMDPOS = r"(?:^|[;&|(){}]|\$\(|&&|\|\||\bthen\b|\bdo\b|\belse\b)\s*(?:sudo\s+)?"


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
    c = strip_heredocs(cmd)

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
    if re.search(r"-applaunch\b", c) and not re.search(r"game-run\.sh", c):
        print("applaunch")
        return


if __name__ == "__main__":
    main()
