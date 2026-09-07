#!/usr/bin/env bash
# dlssnr-control-run.sh — bisect the DLSS-5 NR injection chain against a game hang.
#
# WHY THIS EXISTS
#   On 2026-09-06 Cyberpunk 2077 deadlocked while loading a save with the full NR
#   chain injected: all 71 threads parked, 0% CPU over a 20 s sample, no log growth
#   for 11 minutes, no dma_fence wait, no Xid. It was tempting to write that up as
#   "the NR pass hangs the game". That would have been unfounded — the pass was
#   already DISABLED when it died, and nobody had ever loaded a save on this rig
#   with the chain absent. There was no baseline.
#
#   This runs the four layers of the chain so the hang can be attributed instead of
#   guessed at:
#
#     baseline  no ReShade at all        -> is it just Cyberpunk on this rig?
#     reshade   ReShade, no add-on       -> does injection alone do it?
#     probe     add-on loaded, pass off  -> do the NGX hooks alone do it?
#     nr        full chain, pass on      -> the configuration that hung
#
#   Run them in that order and STOP at the first one that hangs: that layer owns the
#   bug. If baseline hangs, none of this project's code is implicated.
#
#   Layer selection is by file, never by Steam launch options, because this rig's
#   Steam UI crashes when the game Properties dialog is opened (Chromium under FEX).
#
# WHY IT WATCHES INSTEAD OF ASKING
#   The hang presents to the user as a desktop "not responding" dialog offering
#   Force Quit / Wait, which says nothing about whether the game is working. The
#   measured signature is unambiguous and cheap: a live game holds >50% CPU, the
#   deadlocked one held 0.16 ticks/s. So this samples /proc/<pid>/stat directly.
#
# NO pgrep -f / pkill -f ANYWHERE. Process lookup goes through safe-proc.sh, which
# cannot match this script's own command line. See that tool's header for the three
# times that bit this project.
#
# Usage:
#   tools/dlssnr-control-run.sh <baseline|reshade|probe|nr>   # arm a layer, then watch
#   tools/dlssnr-control-run.sh status                        # what is armed right now
#   tools/dlssnr-control-run.sh restore                       # put every file back
#
set -u

APPID=1091500
GAME="$HOME/.local/share/Steam/steamapps/common/Cyberpunk 2077"
BIN="$GAME/bin/x64"
INI="$BIN/ReShade.ini"
LOG="$BIN/ReShade.log"
SPROC="$(dirname "$0")/safe-proc.sh"
RUNS="$HOME/dgx-gaming-work/runs"

# The game process, matched on the Windows-side path Proton gives it.
PAT='Cyberpunk2077.exe'

# --- hang thresholds: derived from the 2026-09-06 measurement, not guessed --------
SAMPLE=15          # seconds between samples
HANG_SAMPLES=8     # consecutive dead samples before calling it (=120 s)
DEAD_TICKS=40      # <40 ticks (0.4 s CPU) per sample is dead; the hang measured 0.16/s

say() { printf '%s\n' "$*"; }
hr()  { printf '%s\n' "------------------------------------------------------------"; }

# Find the real game process. safe-proc.sh guarantees we never match our OWN shell or its
# ancestors/descendants -- but it cannot exclude SIBLING shells from other tool invocations that
# happen to carry the pattern in their command line. That bit us on 2026-09-06: a listing showed
# three "Cyberpunk2077.exe" processes, two of which were 1-thread agent shells, and a sampler
# latched onto the wrong one and reported a bogus verdict. So filter on a property a shell cannot
# fake: the real game has a large thread count (it ran with 71).
MIN_THREADS=10
game_pid() {
  local pid cl t
  for pid in $(bash "$SPROC" list "$PAT" 2>/dev/null | awk '{print $1}'); do
    t=$(ls "/proc/$pid/task" 2>/dev/null | wc -l)
    [ "${t:-0}" -gt "$MIN_THREADS" ] && { printf '%s' "$pid"; return 0; }
  done
  return 1
}

running() { [ -n "$(game_pid)" ]; }

set_ini_enabled() { # $1 = 0|1
  [ -f "$INI" ] || : > "$INI"
  if grep -q '^\[ADDON_DLSSNR_LINUX\]' "$INI" 2>/dev/null; then
    if grep -q '^Enabled=' "$INI"; then
      sed -i "s/^Enabled=.*/Enabled=$1/" "$INI"
    else
      sed -i "/^\[ADDON_DLSSNR_LINUX\]/a Enabled=$1" "$INI"
    fi
  else
    printf '\n[ADDON_DLSSNR_LINUX]\nEnabled=%s\n' "$1" >> "$INI"
  fi
}

restore_all() {
  [ -f "$BIN/dxgi.dll.off" ] && mv -f "$BIN/dxgi.dll.off" "$BIN/dxgi.dll"
  [ -f "$BIN/dlssnr-linux.addon64.off" ] && mv -f "$BIN/dlssnr-linux.addon64.off" "$BIN/dlssnr-linux.addon64"
  set_ini_enabled 1
}

arm() {
  restore_all
  case "$1" in
    baseline) mv -f "$BIN/dxgi.dll" "$BIN/dxgi.dll.off"
              mv -f "$BIN/dlssnr-linux.addon64" "$BIN/dlssnr-linux.addon64.off" ;;
    reshade)  mv -f "$BIN/dlssnr-linux.addon64" "$BIN/dlssnr-linux.addon64.off" ;;
    probe)    set_ini_enabled 0 ;;
    nr)       set_ini_enabled 1 ;;
  esac
}

describe() {
  local dxgi="absent" addon="absent" en="n/a"
  [ -f "$BIN/dxgi.dll" ] && dxgi="present"
  [ -f "$BIN/dlssnr-linux.addon64" ] && addon="present"
  [ -f "$INI" ] && en="$(sed -n 's/^Enabled=\(.*\)/\1/p' "$INI" | head -1)"
  say "  ReShade (dxgi.dll) : $dxgi"
  say "  add-on             : $addon"
  say "  NR pass at startup : ${en:-1 (default on)}"
}

# --------------------------------------------------------------------------------
case "${1:-}" in
  status)  say "armed layer:"; describe; exit 0 ;;
  restore) restore_all; say "restored:"; describe; exit 0 ;;
  baseline|reshade|probe|nr) LAYER="$1" ;;
  *) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

if running; then
  say "REFUSING: Cyberpunk is already running. Shut it down first:"
  say "  \"\$STEAM/steamapps/common/Proton - Experimental/files/bin/wineserver\" -k"
  exit 1
fi

[ -d "$BIN" ] || { say "game not found: $BIN"; exit 1; }

arm "$LAYER"
mkdir -p "$RUNS"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$RUNS/control-$LAYER-$STAMP.txt"

hr; say "layer armed: $LAYER"; describe; hr
[ -f "$LOG" ] && { mv -f "$LOG" "$LOG.prev-$STAMP"; say "previous ReShade.log rotated"; }
say "NOW: launch Cyberpunk 2077 from Steam and load THE SAME SAVE each time."
say "Do not change graphics settings between layers — DLSS-SR must stay on."
say "Waiting for the game (Ctrl-C to abort)..."

# --- wait for the process, then sample it ---------------------------------------
PID=""
for _ in $(seq 1 120); do PID="$(game_pid)"; [ -n "$PID" ] && break; sleep 5; done
[ -n "$PID" ] || { say "game never appeared after 10 min; aborting."; exit 1; }
say "game pid $PID — sampling every ${SAMPLE}s"; hr

prev=$(awk '{print $14+$15}' /proc/$PID/stat 2>/dev/null); dead=0; n=0; verdict="UNKNOWN"
while [ -d "/proc/$PID" ]; do
  sleep "$SAMPLE"
  cur=$(awk '{print $14+$15}' /proc/$PID/stat 2>/dev/null) || break
  [ -n "${cur:-}" ] || break
  d=$((cur - prev)); prev=$cur; n=$((n+1))
  lsz=0; [ -f "$LOG" ] && lsz=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
  if [ "$d" -lt "$DEAD_TICKS" ]; then
    dead=$((dead+1))
    printf '  [%02d] cpu=%-6s ticks  DEAD %d/%d   log=%s\n' "$n" "$d" "$dead" "$HANG_SAMPLES" "$lsz"
  else
    dead=0
    printf '  [%02d] cpu=%-6s ticks  alive        log=%s\n' "$n" "$d" "$lsz"
  fi
  if [ "$dead" -ge "$HANG_SAMPLES" ]; then verdict="HUNG"; break; fi
done
[ "$verdict" = "UNKNOWN" ] && [ ! -d "/proc/$PID" ] && verdict="EXITED"

hr
{
  say "layer:   $LAYER"
  say "verdict: $verdict"
  say "samples: $n   sample=${SAMPLE}s   dead threshold=${DEAD_TICKS} ticks x ${HANG_SAMPLES}"
  say "date:    $(date -Is)"
  [ -f "$LOG" ] && say "reshade log: $LOG ($(stat -c%s "$LOG") bytes)"
} | tee "$REPORT"
hr
case "$verdict" in
  HUNG) say "This layer HANGS. It owns the bug — do not test further layers."
        say "Tear down (Force Quit leaves the Wine tree running):"
        say "  \"$GAME/../Proton - Experimental/files/bin/wineserver\" -k" ;;
  EXITED) say "Process exited. If you quit normally, this layer is CLEAN — move to the next." ;;
esac
say "report: $REPORT"
say "run 'tools/dlssnr-control-run.sh restore' when finished."
