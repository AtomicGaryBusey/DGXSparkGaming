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
#   THIRD BUG, fixed 2026-09-07: this script used to wait on the cgroup scope
#   (`while systemctl --user is-active ...`). That is wrong whenever Steam is
#   ALREADY RUNNING, which is the normal case: `steam -applaunch` merely forwards a
#   request to the Steam daemon and exits, so the scope went inactive within seconds
#   while the game was still starting — and the EXIT trap then tore down the game
#   this script had just launched. Daikatana died that way twice in a row before
#   anyone noticed Steam had never even logged the app start. It now waits for
#   game_pids() to become non-empty (up to APPEAR_TIMEOUT), then waits for it to
#   empty again. The scope is still used for teardown, which is what it is good at.
#
# Usage:
#   tools/game-run.sh <appid> [-- extra game args]
#     PROTON=proton_11        compat tool to expect (warn if different)
#     SECONDS_MAX=0           auto-stop after N seconds (0 = run until you quit)
#     APPEAR_TIMEOUT=300      how long to wait for the game to show up (Proton prefix
#                             upgrades and cold shader caches can take minutes)
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

# Everything belonging to this game, however it was started. The cgroup scope is
# NOT sufficient: `steam -applaunch` forwards a request to the already-running
# Steam daemon, which starts the game in ITS OWN cgroup — our scope only ever
# held the short-lived forwarding process. And matching `compatdata/<appid>`
# alone misses the game binary itself, whose cmdline is the install path.
# Both bugs together once reported "no orphaned processes" while the game ran
# for 1h46m at 501% CPU and had to be killed by hand.
game_pids() {
  local instdir pids=""
  instdir=$(sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" | head -1)
  for d in /proc/[0-9]*; do
    local pid=${d#/proc/} cl
    [ "$pid" = "$$" ] && continue
    [ -r "$d/cmdline" ] || continue
    cl=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
    case "$cl" in
      *"compatdata/$APPID"*|*"shadercache/$APPID"*|*"AppId=$APPID"*) pids="$pids $pid";;
      *) [ -n "$instdir" ] && case "$cl" in *"common/$instdir/"*) pids="$pids $pid";; esac;;
    esac
  done
  echo $pids
}

cleanup() {
  echo
  echo "== teardown =="
  systemctl --user stop "$SCOPE.scope" >/dev/null 2>&1 && note "scope stopped"
  kill "$TELE" 2>/dev/null
  # Proton games reparent freely; ask Wine to shut its prefix down first.
  local ws="$STEAM/steamapps/common/$USED/files/bin/wineserver"
  [ -x "$ws" ] && WINEPREFIX="$STEAM/steamapps/compatdata/$APPID/pfx" "$ws" -k 2>/dev/null
  sleep 2
  local p
  p=$(game_pids)
  if [ -n "$p" ]; then
    warn "still running after wineserver -k: $(echo $p | wc -w) proc(s) — terminating"
    kill $p 2>/dev/null; sleep 3
    p=$(game_pids)
    [ -n "$p" ] && { warn "forcing: $(echo $p | wc -w)"; kill -9 $p 2>/dev/null; sleep 2; p=$(game_pids); }
  fi
  if [ -z "$p" ]; then note "no game processes remain (verified by install dir AND appid)"
  else warn "$(echo $p | wc -w) SURVIVED: $p"; warn "  inspect: tools/safe-proc.sh list '$APPID'"; fi
  # did instrumentation actually produce data? (MangoHud's x86-64 layer lives in the FEX
  # RootFS; whether it loads for an x86-64 game under FEX was never confirmed by probing —
  # vulkaninfo yields no stdout in the guest — so the first real run is the test.)
  local csv
  csv=$(ls "$RUNDIR"/*.csv 2>/dev/null | head -1)
  if [ -n "$csv" ] && [ "$(wc -l < "$csv")" -gt 3 ]; then
    note "mangohud CSV: $(wc -l < "$csv") samples -> $csv"
  elif command -v mangohud >/dev/null 2>&1; then
    warn "mangohud produced no CSV."
    warn "  NOT necessarily a FEX problem. This script printed \"the x86-64 layer likely did"
    warn "  not load under FEX\" for weeks and that was WRONG: it was tearing down before"
    warn "  anything could be sampled (the wait-on-cgroup-scope bug, fixed 2026-09-07). With"
    warn "  the fix, a normal run captures ~44 samples."
    warn "  Real causes, in order: the game exited almost immediately; it is an OpenGL title"
    warn "  (Daikatana) where the Vulkan/DXVK layer never loads; or MANGOHUD_CONFIG did not"
    warn "  reach the game because Steam launched it (env set here does not follow an"
    warn "  -applaunch handoff). Fall back to DXVK_HUD on-screen numbers if it persists."
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
  # Wait for the GAME, not for the cgroup scope.
  #
  # `steam -applaunch` only forwards a request to the already-running Steam daemon and
  # then exits, so the scope goes inactive within seconds while the game is still
  # starting. Waiting on the scope therefore fell straight through to teardown and this
  # script killed the game it had just launched — observed twice on Daikatana
  # (2026-09-07): both runs died instantly and Steam never even logged the app start.
  # game_pids() already knows how to find the game however it was started, so use it.
  APPEAR_TIMEOUT="${APPEAR_TIMEOUT:-300}"
  appeared=0
  waited=0
  while [ "$waited" -lt "$APPEAR_TIMEOUT" ]; do
    [ -n "$(game_pids)" ] && { appeared=1; break; }
    sleep 2; waited=$((waited + 2))
  done
  if [ "$appeared" -eq 0 ]; then
    note "game never appeared within ${APPEAR_TIMEOUT}s — nothing to wait on"
    note "  (Steam may still be starting it; check 'logs/console-linux.txt' for the appid)"
  else
    note "game is up (pids:$(game_pids) ) — waiting for it to exit"
    while [ -n "$(game_pids)" ]; do sleep 5; done
    note "game exited on its own"
  fi
fi
