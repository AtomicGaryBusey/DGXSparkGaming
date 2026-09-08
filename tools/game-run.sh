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
#   FOURTH + FIFTH BUGS, fixed 2026-09-07 (found by the Quake 4 run): game_pids()
#   matched `shadercache/<appid>`, which is Steam's OWN pre-launch shader work, not
#   the game. Quake 4 therefore reported "game is up (20 pids)" and then "game exited
#   on its own" at 19:56:18 -- the exact second Steam finally created the game process.
#   The match is now compatdata / AppId= / the install dir, gated on a thread count so
#   one-thread wrappers cannot pose as the game. Separately `USED` was only assigned
#   when a prefix already existed, so every FIRST run of a title died in teardown with
#   "line 146: USED: unbound variable".
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
#     WORKDIR=<dir>           launch cwd (default: the game dir). NOT a fix for
#                             Prey's CD key -- see the note by LAUNCHDIR below.
#     RUNTIME=auto|fex|box64  which JIT to run under. ALWAYS recorded in run.json;
#                             `auto` is Box64 here, because binfmt says so.
#     LAUNCH_OPTION=          pick a non-default launch entry (e.g. option1), or
#                             `dialog` to get Steam's chooser. See tools/appinfo.py.
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
USED=""   # must exist even with no prefix: cleanup() reads it under `set -u`
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
# MangoHud must be the X86-64 build. The distro package here is mangohud:arm64,
# which ships only an aarch64 layer and CANNOT be loaded into a translated x86
# game -- so this script advertised "mangohud: on" and produced zero CSVs for its
# entire life, while telling the reader to `apt install mangohud`, a package that
# was already installed and could never have helped.
MHLAYER="$HOME/dgx-gaming-work/mangohud-x86/root/usr/share/vulkan/implicit_layer.d"
if [ -d "$MHLAYER" ]; then
  ENVS+=("VK_ADD_LAYER_PATH=$MHLAYER" "MANGOHUD=1"
         "MANGOHUD_CONFIG=fps,frametime,gpu_stats,cpu_stats,output_folder=$RUNDIR,autostart_log=1,log_interval=100")
  note "mangohud: x86-64 layer (CSV -> $RUNDIR)"
  note "  note: Vulkan layer only — 64-bit DXVK/VKD3D titles. 32-bit or OpenGL"
  note "  titles (Quake 4, DOOM 3, Prey) get no CSV; use com_showFPS + watch-run.sh"
else
  warn "no x86-64 mangohud — no CSV frametimes. Run: tools/setup-mangohud-x86.sh"
  warn "  (the distro mangohud:arm64 package cannot instrument an x86 game)"
fi
note "logs: $RUNDIR"

# GPU telemetry alongside the run — answers GPU-bound vs CPU-bound, this project's core thesis
( nvidia-smi --query-gpu=timestamp,utilization.gpu,clocks.sm,power.draw,memory.used \
    --format=csv -l 1 > "$RUNDIR/gpu.csv" 2>/dev/null ) &
TELE=$!

# --- resolve the real launch chain -------------------------------------------
# LAUNCH_VIA=steam restores the old `steam -applaunch` path. It is NOT the
# default any more, because it does not work for instrumentation: -applaunch is
# an IPC request to the already-running Steam daemon, which then spawns the game
# with ITS environment. Everything in ENVS was silently dropped. Measured
# 2026-09-07: five runs produced gpu.csv (nvidia-smi, our own process) and ZERO
# MangoHud CSVs. game-run.sh's entire reason for existing -- "every run produces
# numbers instead of adjectives" -- was quietly false for its whole life.
#
# The default now replicates Steam's own chain, which we can read straight out of
# its console log:
#   reaper SteamLaunch AppId=N -- <runtime>/_v2-entry-point --verb=waitforexitandrun
#     -- <proton>/proton waitforexitandrun <game exe>
# Launching it ourselves means our env is the game's env.
GAMEDIR="$STEAM/steamapps/common/$(sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" | head -1)"

if [ "${LAUNCH_VIA:-proton}" = "steam" ]; then
  warn "LAUNCH_VIA=steam — env vars will NOT reach the game (no HUD, no MangoHud, no PROTON_LOG)"
  if [ -n "${LAUNCH_OPTION:-}" ]; then
    set -- "$STEAM/ubuntu12_32/steam" "steam://launch/$APPID/$LAUNCH_OPTION"
  else
    set -- "$STEAM/ubuntu12_32/steam" -applaunch "$APPID" "$@"
  fi
else
  # compat tool: the prefix's own record first, then $PROTON, then Experimental
  COMPAT="${USED:-}"
  [ -z "$COMPAT" ] && case "${PROTON:-}" in
    proton_11) COMPAT="Proton 11.0";; proton_10) COMPAT="Proton 10.0";; *) COMPAT="Proton - Experimental";;
  esac
  CT="$STEAM/steamapps/common/$COMPAT"
  [ -x "$CT/proton" ] || die "no proton at $CT/proton (set PROTON= or LAUNCH_VIA=steam)"

  # the runtime named by the compat tool itself, not a guess
  RT_APPID=$(sed -n 's/.*"require_tool_appid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$CT/toolmanifest.vdf" 2>/dev/null | head -1)
  RT_DIR=""
  if [ -n "$RT_APPID" ]; then
    RT_DIR=$(sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' \
             "$STEAM/steamapps/appmanifest_$RT_APPID.acf" 2>/dev/null | head -1)
  fi
  ENTRY="$STEAM/steamapps/common/$RT_DIR/_v2-entry-point"
  [ -x "$ENTRY" ] || die "runtime for $COMPAT (appid ${RT_APPID:-?}) not installed — steam://install/$RT_APPID"

  # the executable, from Steam's metadata rather than from a guess about the dir
  EXE=$(python3 "$(dirname "$0")/appinfo.py" "$APPID" --launch 2>/dev/null \
        | awk -F'\t' -v want="${LAUNCH_OPTION:-}" '
            want=="" && NR==1 {print $3; exit}
            want!="" && $2==want {print $3; exit}')
  [ -n "$EXE" ] || die "could not resolve an executable for $APPID (tools/appinfo.py $APPID --launch)"
  EXE=$(printf '%s' "$EXE" | tr '\\' '/')
  note "compat: $COMPAT   runtime: $RT_DIR"
  note "exe: $EXE${LAUNCH_OPTION:+  (launch option: $LAUNCH_OPTION)}"
  [ -f "$GAMEDIR/$EXE" ] || warn "$GAMEDIR/$EXE does not exist — launch will probably fail"

  # Proton creates pfx/ inside STEAM_COMPAT_DATA_PATH but NOT the directory
  # itself -- Steam normally does that. Launching directly, a title that has
  # never been run through Steam has no compatdata dir, and Proton dies with a
  # Python traceback ending in
  #   FileNotFoundError: .../compatdata/<appid>/pfx.lock
  # which reads like a lock-contention bug and is not one. Prey and Phobos both
  # hit it on 2026-09-07; the A/B tool duly reported "both runtimes behaved the
  # SAME", which was true and had nothing to do with either JIT.
  CDP="$STEAM/steamapps/compatdata/$APPID"
  [ -d "$CDP" ] || { mkdir -p "$CDP" && note "created compatdata/$APPID (first direct launch)"; }

  # Proton needs these; SteamAppId/SteamGameId are what the Steam API keys off.
  ENVS+=("STEAM_COMPAT_DATA_PATH=$STEAM/steamapps/compatdata/$APPID"
         "STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM"
         "STEAM_COMPAT_APP_ID=$APPID" "SteamAppId=$APPID" "SteamGameId=$APPID")
  # Now that env actually arrives, log every run. This is the corpus
  # tools/signature-check.sh needs: a claimed failure signature is worth nothing
  # until a WORKING title's log has been checked for it, and on 2026-09-07 only
  # three such logs existed in total.
  [ "${NO_PROTON_LOG:-0}" = 1 ] || ENVS+=("PROTON_LOG=1")
  set -- "$STEAM/ubuntu12_32/reaper" "SteamLaunch" "AppId=$APPID" -- \
         "$ENTRY" --verb=waitforexitandrun -- \
         "$CT/proton" waitforexitandrun "$GAMEDIR/$EXE" "$@"
fi

# RUNTIME picks the JIT ON PURPOSE. Leaving it to chance is how, on 2026-09-07,
# a Quake 4 session was written up as FEX when binfmt_misc had quietly handed the
# whole chain to Box64 -- and the two do NOT agree: with everything else held
# constant, Box64 played the game and FEX failed at SetPixelFormat before it
# could create a GL context. The JIT is the single biggest variable on this rig
# and it was the one thing no run recorded.
#   auto  (default) whatever binfmt does -- which is Box64 here. Recorded, not assumed.
#   fex             wrap the chain in FEXBash so every child stays inside FEX
#   box64           same as auto, stated explicitly
RUNTIME="${RUNTIME:-auto}"
case "$RUNTIME" in
  fex)
    command -v FEXBash >/dev/null 2>&1 || die "RUNTIME=fex but FEXBash is not installed"
    QUOTED=""; for a in "$@"; do QUOTED="$QUOTED $(printf '%q' "$a")"; done
    set -- FEXBash -c "cd $(printf '%q' "$GAMEDIR") &&$QUOTED"
    note "runtime: FEX (forced via FEXBash)" ;;
  box64)
    # BOX64_BIN points at a locally built box64 (see tools/build-box64-symfix.sh).
    # binfmt would otherwise always hand the chain to /usr/local/bin/box64, so a
    # patched build could never actually be tested against a game.
    if [ -n "${BOX64_BIN:-}" ]; then
      [ -x "$BOX64_BIN" ] || die "BOX64_BIN=$BOX64_BIN is not executable"
      set -- "$BOX64_BIN" "$@"
      note "runtime: Box64 from $BOX64_BIN (explicit, bypassing binfmt)"
    else
      note "runtime: box64 — binfmt hands x86 ELF to Box64"
    fi ;;
  auto)
    # box32 and box64 are two binfmt entries pointing at the same interpreter;
    # report the distinct set, not one line per registration.
    _bf=$(for f in /proc/sys/fs/binfmt_misc/*; do
            [ -f "$f" ] || continue
            grep -q '^enabled' "$f" 2>/dev/null || continue
            case "$(awk '/^interpreter/{print $2}' "$f")" in
              *box64*|*box86*) echo Box64 ;; *FEX*) echo FEX ;;
            esac
          done | sort -u | tr '\n' ' ')
    note "runtime: $RUNTIME — binfmt hands x86 ELF to ${_bf:-nothing}" ;;
  *) die "RUNTIME must be auto, fex or box64" ;;
esac

# WORKDIR overrides the launch directory, for engines that resolve data paths
# relative to the cwd.
#
# DO NOT use it to chase Prey's "Couldn't read ../base/preykey" -- that was tried
# on 2026-09-08 and is WRONG. id Tech 4 appends its mod directory to the cwd, so
# cwd=<game>/base makes the search path <game>/base/base: no .pk4 loads at all
# and the engine dies with "Couldn't load default.cfg". The key-path arithmetic
# looked right and the fix broke the thing that was already working.
LAUNCHDIR="${WORKDIR:-$GAMEDIR}"
[ -d "$LAUNCHDIR" ] || die "WORKDIR=$LAUNCHDIR does not exist"
[ "$LAUNCHDIR" != "$GAMEDIR" ] && note "cwd override: $LAUNCHDIR"

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo "== dry run: pre-flight only, nothing launched =="
  note "cwd:  ${LAUNCHDIR:-$GAMEDIR}"
  note "env:  ${ENVS[*]}"
  note "argv: $*"
  rmdir "$RUNDIR" 2>/dev/null
  exit 0
fi

# A scope left in `failed` state (killed run, crashed game) makes systemd-run
# refuse the same --unit name, and the launch then silently does nothing: 0-byte
# launch.log, no game, no error. Clear it first. Observed 2026-09-07 after an
# interrupted run left game-2210.scope failed.
if ! systemctl --user is-active "$SCOPE.scope" >/dev/null 2>&1; then
  systemctl --user reset-failed "$SCOPE.scope" >/dev/null 2>&1 || true
fi

echo "== launching in cgroup scope '$SCOPE' =="
( cd "$LAUNCHDIR" 2>/dev/null || cd "$HOME"
  systemd-run --user --scope --unit="$SCOPE" --quiet -- \
    env "${ENVS[@]}" "$@" >"$RUNDIR/launch.log" 2>&1 ) &
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
  # PRIMARY SOURCE: the cgroup scope. This became reliable only when the launch
  # moved off `steam -applaunch` -- that forwarded to the Steam daemon, which
  # started the game in ITS cgroup, so our scope held nothing but the forwarder.
  # With the direct Proton chain the game really is our descendant, so cgroup
  # membership answers "is this ours?" exactly, with no pattern matching at all.
  # Matching cmdlines was guesswork and got it wrong twice: it missed the game
  # because the cmdline names the WINE path, not the install dir, which left
  # run.json recording runtime_actual=unknown for runs that plainly worked.
  local cg cgfile
  cg=$(systemctl --user show -p ControlGroup --value "$SCOPE.scope" 2>/dev/null)
  cgfile="/sys/fs/cgroup${cg}/cgroup.procs"
  if [ -n "$cg" ] && [ -r "$cgfile" ]; then
    while read -r pid; do
      [ -n "$pid" ] || continue
      [ "$pid" = "$$" ] && continue
      pids="$pids $pid"
    done < "$cgfile"
  fi
  if [ -n "$pids" ]; then
    local out="" t
    for pid in $pids; do
      t=$(awk '/^Threads:/{print $2}' "/proc/$pid/status" 2>/dev/null)
      [ "${t:-0}" -ge "${MIN_GAME_THREADS:-4}" ] && out="$out $pid"
    done
    [ -n "$out" ] && { echo $out; return; }
  fi
  # FALLBACK: pattern match, for a game that escaped the scope somehow.
  instdir=$(sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' "$M" | head -1)
  for d in /proc/[0-9]*; do
    local pid=${d#/proc/} cl
    [ "$pid" = "$$" ] && continue
    [ -r "$d/cmdline" ] || continue
    cl=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
    case "$cl" in
      *"compatdata/$APPID"*|*"AppId=$APPID"*) pids="$pids $pid";;
      *)
        # The game's own cmdline is `.../Proton - Experimental/.../wine Z:\...\Quake4.exe`
        # -- it names the WINE path, not the install dir, so matching only
        # common/<installdir>/ missed it entirely and runtime detection never
        # ran (2026-09-07: run.json recorded runtime_actual=unknown for a run
        # that plainly worked). Match the executable's basename too.
        _hit=""
        [ -n "$instdir" ] && case "$cl" in *"common/$instdir/"*) _hit=1;; esac
        [ -z "$_hit" ] && [ -n "${EXE:-}" ] && case "$cl" in *"$(basename "${EXE//\\//}")"*) _hit=1;; esac
        [ -n "$_hit" ] && pids="$pids $pid"
      ;;
    esac
  done
  # Thread-count gate, the same trick watch-run.sh uses: a real game has many
  # threads, while Steam's launch wrappers and reaper have one or two. Without
  # this a 1-thread helper reads as "the game is up".
  local out="" t
  for pid in $pids; do
    t=$(awk '/^Threads:/{print $2}' "/proc/$pid/status" 2>/dev/null)
    [ "${t:-0}" -ge "${MIN_GAME_THREADS:-4}" ] && out="$out $pid"
  done
  pids="$out"
  echo $pids
}

# Read the JIT off a live process. Deliberately callable from ANY path: the
# first version lived only in the "game is up" branch, so a SECONDS_MAX run --
# which takes a different wait path -- recorded runtime_actual=unknown for a run
# that plainly worked. The field that exists to prevent misattribution must not
# depend on which branch the run happened to take.
ACTUAL_JIT="${ACTUAL_JIT:-unknown}"
detect_jit() {
  [ "$ACTUAL_JIT" != "unknown" ] && return 0
  local cg cgfile pid e
  cg=$(systemctl --user show -p ControlGroup --value "$SCOPE.scope" 2>/dev/null)
  cgfile="/sys/fs/cgroup${cg}/cgroup.procs"
  if [ -n "$cg" ] && [ -r "$cgfile" ]; then
    while read -r pid; do
      [ -n "$pid" ] || continue
      e=$(readlink "/proc/$pid/exe" 2>/dev/null) || continue
      case "$e" in
        *box64*|*box86*) ACTUAL_JIT="Box64"; return 0 ;;
        */FEX*)          ACTUAL_JIT="FEX";   return 0 ;;
      esac
    done < "$cgfile"
  fi
  for pid in $(game_pids); do
    e=$(readlink "/proc/$pid/exe" 2>/dev/null) || continue
    case "$e" in
      *box64*|*box86*) ACTUAL_JIT="Box64"; return 0 ;;
      */FEX*)          ACTUAL_JIT="FEX";   return 0 ;;
    esac
  done
  return 1
}

cleanup() {
  detect_jit || true
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
  # PROTON_LOG writes to ~/steam-<appid>.log and the NEXT run overwrites it. On
  # 2026-09-07 that destroyed the only record able to say which JIT produced the
  # id Tech 4 x87 crash, so the question is now permanently unanswerable. Archive
  # it into the run directory, where it belongs to this run alone.
  if [ -f "$HOME/steam-$APPID.log" ]; then
    cp -f "$HOME/steam-$APPID.log" "$RUNDIR/proton.log" 2>/dev/null \
      && note "archived proton log ($(wc -l < "$RUNDIR/proton.log") lines)"
  fi
  # Game-side logs worth keeping with the run rather than left to be overwritten.
  for _g in "$GAMEDIR"/*/qconsole.log; do
    [ -f "$_g" ] && cp -f "$_g" "$RUNDIR/$(basename "$(dirname "$_g")")-qconsole.log" 2>/dev/null
  done
  # A machine-readable record of the conditions, so a claim can be traced to them
  # instead of re-derived months later from memory.
  cat > "$RUNDIR/run.json" <<JSONEOF
{
  "appid": "$APPID",
  "name": "$NAME",
  "runtime_requested": "${RUNTIME:-auto}",
  "runtime_actual": "${ACTUAL_JIT:-unknown}",
  "proton": "${USED:-${COMPAT:-unknown}}",
  "runtime_container": "${RT_DIR:-none}",
  "exe": "${EXE:-unknown}",
  "launch_option": "${LAUNCH_OPTION:-default}",
  "launch_via": "${LAUNCH_VIA:-proton}",
  "date": "$(date -Iseconds)",
  "load_at_start": "$(cut -d' ' -f1 /proc/loadavg)",
  "kernel": "$(uname -r)",
  "note": "runtime_actual is read from /proc/<pid>/exe. If it is unknown, this run cannot be attributed to a JIT."
}
JSONEOF
  note "manifest: $RUNDIR/run.json  (runtime_actual=${ACTUAL_JIT:-unknown})"
  note "run dir: $RUNDIR"
}
trap cleanup EXIT INT TERM

if [ "$MAXS" -gt 0 ]; then
  note "will auto-stop after ${MAXS}s"
  # Poll instead of a bare sleep, so the JIT is sampled WHILE the game is alive.
  # detect_jit() at teardown only is too late for a title that dies early: Prey
  # (2026-09-07) exited in seconds and recorded runtime_actual=unknown, which is
  # exactly the run you most want attributed.
  _el=0; _ann=0
  while [ "$_el" -lt "$MAXS" ]; do
    if [ "$_ann" = 0 ] && detect_jit; then
      note "runtime ACTUALLY executing the game: $ACTUAL_JIT"; _ann=1
    fi
    sleep 3; _el=$((_el+3))
  done
  [ "$_ann" = 0 ] && warn "never saw a live process to read the JIT from — the game may have exited immediately"
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
  detect_jit || true
  note "runtime ACTUALLY executing the game: $ACTUAL_JIT"
  [ "$ACTUAL_JIT" = "unknown" ] && warn "could not determine the JIT — do NOT attribute this run to one"
    while [ -n "$(game_pids)" ]; do sleep 5; done
    note "game exited on its own"
  fi
fi
