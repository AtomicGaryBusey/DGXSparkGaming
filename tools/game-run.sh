#!/usr/bin/env bash
# game-run.sh — launch a Steam game for TESTING, with instrumentation and
# guaranteed teardown.
#
# WHY THIS EXISTS
#   Two of this project's worst self-inflicted failures came from launching games
#   by hand:
#     * A `timeout`-wrapped launch killed the launcher but not the game. Wine
#       reparented the tree; <game>.exe + xalia.exe + wineserver kept burning ~55%
#       CPU for minutes, and on a box whose Steam UI renders in software that made
#       the whole desktop crawl.
#     * Results were recorded as "smooth" / "choppy" — unfalsifiable adjectives in
#       a log whose entire purpose is performance comparison.
#   Written rules did not prevent either. This does it mechanically:
#     - the game runs inside a systemd --user scope, so killing the scope kills
#       every descendant atomically. Wine cannot reparent out of a cgroup.
#     - DXVK_HUD (and MangoHud CSV, when present) are on by default, so every run
#       produces numbers.
#     - pre-flight checks catch the traps that have actually cost time here:
#       wrong/absent compat tool, missing Proton runtime, cold shader cache,
#       and a busy machine.
#
# Usage:
#   tools/game-run.sh <appid> [-- extra game args]
#     PROTON=proton_11        compat tool to expect (warn if different)
#     SECONDS_MAX=0           auto-stop after N seconds (0 = run until you quit)
#     NO_HUD=1                disable DXVK_HUD
#     DRY_RUN=1               run pre-flight checks only, launch nothing
#     OUT=<dir>               where to write logs (default ~/dgx-gaming-work/runs)
#
# Stop a run early from another shell:  systemctl --user stop game-<appid>.scope
set -uo pipefail

APPID="${1:-}"; [ -n "$APPID" ] || { echo "usage: $0 <appid> [-- args]"; exit 2; }; shift || true
[ "${1:-}" = "--" ] && shift
STEAM="${STEAM_ROOT:-$HOME/.local/share/Steam}"
OUT="${OUT:-$HOME/dgx-gaming-work/runs}"
SCOPE="game-$APPID"
MAXS="${SECONDS_MAX:-0}"
M="$STEAM/steamapps/appmanifest_$APPID.acf"
STAMP=$(date +%Y%m%d-%H%M%S)
RUNDIR="$OUT/$APPID-$STAMP"; mkdir -p "$RUNDIR"

note() { printf '  %s\n' "$*"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$*"; }
die()  { printf '  \033[31mx %s\033[0m\n' "$*"; exit 1; }

echo "== pre-flight =="
[ -f "$M" ] || die "appid $APPID is not installed (no appmanifest)"
NAME=$(sed -n 's/.*"name"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" | head -1)
grep -q '"StateFlags"[[:space:]]*"4"' "$M" || warn "StateFlags != 4 — install may be incomplete"
note "game: $NAME ($APPID)"

# compat tool actually in use (from the prefix Proton wrote, not from config.vdf)
CI="$STEAM/steamapps/compatdata/$APPID/config_info"
if [ -f "$CI" ]; then
  USED=$(sed -n '2p' "$CI" | sed 's|.*/common/||; s|/files/.*||')
  note "proton (from prefix): ${USED:-unknown}"
  [ -n "${PROTON:-}" ] && [[ "$USED" != *"${PROTON#proton_}"* ]] && warn "expected $PROTON, prefix says $USED"
else
  warn "no compatdata prefix yet — first run, or the game is running natively (NOT what you want for Windows-side tests)"
fi

# shader cache warmth — a cold cache measures shader compilation, not the runtime
SC="$STEAM/steamapps/shadercache/$APPID/DXVK_state_cache"
if [ -d "$SC" ] && [ -n "$(ls -A "$SC" 2>/dev/null)" ]; then
  note "DXVK state cache: warm ($(ls "$SC" | wc -l) entries)"
else
  warn "DXVK state cache COLD — this run measures shader compilation. Take the SECOND run for any comparison."
fi

# machine quiet enough to measure?
LOAD=$(awk '{print $1}' /proc/loadavg)
awk -v l="$LOAD" 'BEGIN{exit !(l>2.0)}' && warn "load average $LOAD — results will be noisy; idle the box first" || note "load average $LOAD"

# instrumentation
ENVS=()
[ "${NO_HUD:-0}" = 1 ] || ENVS+=("DXVK_HUD=fps,frametimes,gpuload,version" "VKD3D_DEBUG=none")
if command -v mangohud >/dev/null 2>&1; then
  ENVS+=("MANGOHUD=1" "MANGOHUD_CONFIG=fps,frametime,gpu_stats,cpu_stats,output_folder=$RUNDIR,autostart_log=1,log_interval=100")
  note "mangohud: on (CSV -> $RUNDIR)"
else
  warn "mangohud not installed — no CSV frametimes. sudo apt install mangohud"
fi
note "logs: $RUNDIR"

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo "== dry run: pre-flight only, nothing launched =="
  note "would launch in scope '$SCOPE' with: ${ENVS[*]}"
  rmdir "$RUNDIR" 2>/dev/null
  exit 0
fi

# GPU telemetry alongside the run — answers GPU-bound vs CPU-bound, this project's core thesis
( nvidia-smi --query-gpu=timestamp,utilization.gpu,clocks.sm,power.draw,memory.used \
    --format=csv -l 1 > "$RUNDIR/gpu.csv" 2>/dev/null ) &
TELE=$!

echo "== launching in cgroup scope '$SCOPE' =="
systemd-run --user --scope --unit="$SCOPE" --quiet -- \
  env "${ENVS[@]}" \
  "$STEAM/ubuntu12_32/steam" -applaunch "$APPID" "$@" >"$RUNDIR/launch.log" 2>&1 &
LAUNCH=$!

cleanup() {
  echo
  echo "== teardown =="
  systemctl --user stop "$SCOPE.scope" >/dev/null 2>&1 && note "scope stopped (all descendants killed)"
  kill "$TELE" 2>/dev/null
  # belt and braces: anything Wine left outside the scope
  pkill -f "compatdata/$APPID" 2>/dev/null
  sleep 1
  local left
  left=$(ps -eo args | grep -c "[c]ompatdata/$APPID")
  [ "$left" -eq 0 ] && note "no orphaned processes" || warn "$left processes still alive — inspect manually"
  # did instrumentation actually produce data? (MangoHud's x86-64 layer lives in the FEX
  # RootFS; whether it loads for an x86-64 game under FEX was never confirmed by probing —
  # vulkaninfo yields no stdout in the guest — so the first real run is the test.)
  local csv
  csv=$(ls "$RUNDIR"/*.csv 2>/dev/null | head -1)
  if [ -n "$csv" ] && [ "$(wc -l < "$csv")" -gt 3 ]; then
    note "mangohud CSV: $(wc -l < "$csv") samples -> $csv"
  elif command -v mangohud >/dev/null 2>&1; then
    warn "mangohud produced no CSV — the x86-64 layer likely did not load under FEX."
    warn "  check: MANGOHUD_CONFIG had output_folder set, and the RootFS carries"
    warn "  /usr/lib/x86_64-linux-gnu/mangohud/libMangoHud.so (it does). If this persists,"
    warn "  fall back to DXVK_HUD on-screen numbers and record them manually."
  fi
  [ -s "$RUNDIR/gpu.csv" ] && note "gpu telemetry: $(wc -l < "$RUNDIR/gpu.csv") samples"
  note "run dir: $RUNDIR"
}
trap cleanup EXIT INT TERM

if [ "$MAXS" -gt 0 ]; then
  note "will auto-stop after ${MAXS}s"
  sleep "$MAXS"
else
  note "running — press Ctrl-C here to stop the game and tear down cleanly"
  while systemctl --user is-active --quiet "$SCOPE.scope"; do sleep 5; done
fi
