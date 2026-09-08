#!/usr/bin/env bash
# find-logs.sh — locate every diagnostic artifact a game can produce on this stack.
#
# WHY THIS EXISTS
#   Debugging a title here means reading up to eight different files scattered
#   across four directory trees, and which ones exist depends on the engine, the
#   launcher and how far the game got. Rediscovering that map for each game is
#   how a diagnosis gets skipped: on 2026-09-07 a Proton Python traceback sat in
#   launch.log for an hour while the wrong two logs were being read, and the
#   engine's own x87 dump went unread for MONTHS because nobody knew id Tech 4
#   writes qconsole.log next to the .pk4 files.
#
#   It is also the answer to "where do I look?" for anyone who finds this repo.
#   Other people's logs made this project possible; this is the reciprocal.
#
# Usage:
#   tools/find-logs.sh <appid>          # everything for one title
#   tools/find-logs.sh <appid> --paths  # bare paths only (for scripting)
#
# Prints every location whether or not it exists, because "this file is absent"
# is itself diagnostic — no qconsole.log means the engine never reached its
# config, which is a different failure from a crash after startup.
set -uo pipefail
APPID="${1:-}"
[ -n "$APPID" ] || { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
BARE=0; [ "${2:-}" = "--paths" ] && BARE=1
STEAM="${STEAM_ROOT:-$HOME/.local/share/Steam}"
RUNS="${OUT:-$HOME/dgx-gaming-work/runs}"

M="$STEAM/steamapps/appmanifest_$APPID.acf"
NAME=$(sed -n 's/.*"name"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" 2>/dev/null | head -1)
INST=$(sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" 2>/dev/null | head -1)
GAME="$STEAM/steamapps/common/$INST"
PFX="$STEAM/steamapps/compatdata/$APPID/pfx"

show() {  # show <label> <path> <note>
  local label="$1" p="$2" note="${3:-}"
  if [ "$BARE" = 1 ]; then [ -e "$p" ] && printf '%s\n' "$p"; return; fi
  if [ -e "$p" ]; then
    local sz mt
    if [ -d "$p" ]; then sz="$(ls -1 "$p" 2>/dev/null | wc -l) entries"
    else sz="$(wc -c < "$p" 2>/dev/null) bytes"; fi
    mt=$(date -r "$p" '+%m-%d %H:%M' 2>/dev/null)
    printf '  \033[32m*\033[0m %-30s %s\n      %s   (%s, %s)\n' "$label" "" "$p" "$sz" "$mt"
  else
    printf '  \033[90m-\033[0m %-30s %s\n' "$label" ""
    printf '      \033[90m%s\033[0m%s\n' "$p" "${note:+   <- $note}"
  fi
}

[ "$BARE" = 1 ] || {
  echo "=================================================================="
  echo " ${NAME:-appid $APPID}  ($APPID)"
  echo "=================================================================="
  echo
  echo "-- our own run archives (self-contained, one dir per run) --"
}
if [ "$BARE" = 1 ]; then
  ls -dt "$RUNS/$APPID-"*/ 2>/dev/null | head -20
else
  n=$(ls -dt "$RUNS/$APPID-"*/ 2>/dev/null | wc -l)
  if [ "$n" -gt 0 ]; then
    printf '  \033[32m*\033[0m %s run(s) under %s/%s-*\n' "$n" "$RUNS" "$APPID"
    printf '      newest: %s\n' "$(ls -dt "$RUNS/$APPID-"*/ 2>/dev/null | head -1)"
    printf '      each contains: run.json (conditions incl. the JIT that ran it),\n'
    printf '      proton.log, <mod>-qconsole.log, launch.log, gpu.csv\n'
    printf '      read with: tools/run-report.sh --appid %s\n' "$APPID"
  else
    printf '  \033[90m-\033[0m no runs yet — tools/game-run.sh %s\n' "$APPID"
  fi
  echo
  echo "-- Proton / Wine --"
fi
show "PROTON_LOG (live, OVERWRITTEN)" "$HOME/steam-$APPID.log" \
     "needs PROTON_LOG=1; game-run.sh archives a copy per run"
show "prefix root"                    "$STEAM/steamapps/compatdata/$APPID"
show "prefix drive_c"                 "$PFX/drive_c"
show "prefix registry (user.reg)"     "$PFX/user.reg" "Wine rewrites this; never edit blind"
show "compat tool actually used"      "$STEAM/steamapps/compatdata/$APPID/config_info"

[ "$BARE" = 1 ] || echo; [ "$BARE" = 1 ] || echo "-- engine-side logs (inside the prefix's fake Windows) --"
show "My Documents"        "$PFX/drive_c/users/steamuser/Documents"
show "AppData/Local"       "$PFX/drive_c/users/steamuser/AppData/Local"
show "AppData/Roaming"     "$PFX/drive_c/users/steamuser/AppData/Roaming"
show "Temp (crash dumps land here)" "$PFX/drive_c/users/steamuser/Temp"

[ "$BARE" = 1 ] || echo; [ "$BARE" = 1 ] || echo "-- engine-side logs (in the GAME directory) --"
if [ -d "$GAME" ]; then
  # id Tech 4 writes qconsole.log beside the .pk4/.resources archives
  found=0
  while IFS= read -r f; do found=1; show "engine log" "$f"; done < <(
    find "$GAME" -maxdepth 3 -iname 'qconsole.log' -o -maxdepth 3 -iname '*.log' 2>/dev/null | head -8)
  [ "$found" = 0 ] && [ "$BARE" = 0 ] && printf '  \033[90m-\033[0m none found under %s\n' "$GAME"
  while IFS= read -r f; do show "crash dump" "$f"; done < <(
    find "$GAME" -maxdepth 3 \( -iname '*.dmp' -o -iname '*.mdmp' -o -iname 'crash*' \) 2>/dev/null | head -6)
else
  [ "$BARE" = 0 ] && printf '  \033[90m-\033[0m game not installed (%s)\n' "$GAME"
fi

[ "$BARE" = 1 ] || {
  echo
  echo "-- Steam client side --"
}
show "Steam console log"   "$STEAM/logs/console_log.txt" "why a launch did/didn't happen"
show "Steam content log"   "$STEAM/logs/content_log.txt" "download/install state"
show "shader cache"        "$STEAM/steamapps/shadercache/$APPID" "empty = first run measures compilation"
show "app manifest"        "$M"

[ "$BARE" = 1 ] || {
  echo
  echo "-- system-wide (not per-game) --"
  show "FEX config"    "$HOME/.fex-emu/Config.json"
  show "FEX RootFS"    "$HOME/.fex-emu/RootFS"
  show "kernel ring (Xid, OOM)" "/dev/kmsg" "sudo dmesg -T | grep -iE 'xid|oom|segfault'"
  echo
  echo "TIP: absence is evidence. No qconsole.log means the engine never reached"
  echo "     its config; a header-only proton.log means Wine never traced anything."
}
