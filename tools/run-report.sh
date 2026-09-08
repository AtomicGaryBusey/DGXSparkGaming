#!/usr/bin/env bash
# run-report.sh — say what a run actually did, from its own archived evidence.
#
# WHY THIS EXISTS
#   Every id Tech 4 test on 2026-09-07 ended with the same hand-typed pipeline:
#   read run.json, grep qconsole.log for the FPU assertion, grep it again for
#   SetPixelFormat, grep proton.log for steamclient_init, count access
#   violations. Ten times, slightly differently each time, which is how you get
#   an inconsistent results table. The failure signatures this project has
#   actually hit are a known, finite list; checking them should not be an act of
#   memory.
#
#   It reads ONLY files archived inside the run directory, so a report is
#   reproducible months later and cannot silently pick up a newer run's log --
#   which is exactly what destroyed the provenance of the original x87 crash.
#
# Usage:
#   tools/run-report.sh                  # the most recent run
#   tools/run-report.sh <rundir>
#   tools/run-report.sh --appid 2210     # most recent run of one title
#   tools/run-report.sh --all            # one line per run, oldest first
set -uo pipefail
OUT="${OUT:-$HOME/dgx-gaming-work/runs}"

pick() {
  case "${1:-}" in
    --appid) ls -dt "$OUT/$2-"* 2>/dev/null | head -1 ;;
    "")      ls -dt "$OUT"/*/  2>/dev/null | head -1 ;;
    *)       printf '%s' "$1" ;;
  esac
}

j() {  # crude JSON field read; the manifest is ours and flat
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" 2>/dev/null | head -1
}

report() {
  local RD="$1" q p n
  [ -d "$RD" ] || { echo "no such run: $RD"; return 1; }
  local M="$RD/run.json"
  printf '\n== %s ==\n' "$(basename "$RD")"
  if [ -f "$M" ]; then
    printf '  %-12s %s (%s)\n' "game"    "$(j "$M" name)" "$(j "$M" appid)"
    printf '  %-12s requested=%s  ACTUAL=%s\n' "runtime" "$(j "$M" runtime_requested)" "$(j "$M" runtime_actual)"
    [ "$(j "$M" runtime_actual)" = "unknown" ] && \
      printf '  %-12s \033[33mthis run cannot be attributed to a JIT\033[0m\n' ""
    printf '  %-12s %s   container=%s\n' "proton" "$(j "$M" proton)" "$(j "$M" runtime_container)"
    printf '  %-12s %s   option=%s\n' "exe" "$(j "$M" exe)" "$(j "$M" launch_option)"
    printf '  %-12s %s  load=%s\n' "when" "$(j "$M" date)" "$(j "$M" load_at_start)"
  else
    printf '  %-12s \033[33mNO MANIFEST — run predates run.json, conditions unknown\033[0m\n' "runtime"
  fi

  # --- engine-side evidence -------------------------------------------------
  q=$(ls "$RD"/*qconsole.log 2>/dev/null | head -1)
  if [ -n "$q" ]; then
    printf '  %-12s %s bytes\n' "qconsole" "$(wc -c < "$q")"
    while IFS='|' read -r label pat; do
      n=$(grep -c "$pat" "$q" 2>/dev/null); n=${n//[!0-9]/}
      [ "${n:-0}" -gt 0 ] && printf '     %-34s %s\n' "$label" "$n"
    done <<'SIGS'
x87 assertion (FPU stack not empty)|FPU stack is not empty
SetPixelFormat failed|SetPixelFormat failed
Unable to initialize OpenGL|Unable to initialize OpenGL
GL context created OK|creating GL context: succeeded
map loaded|Map Initialization
autosave written|Saved '
CalcFov FPU warning|CalcFov: FPU stack not empty
SIGS
    grep -m1 -E 'TAGS = ' "$q" 2>/dev/null | sed 's/^/     x87 tag word: /'
  else
    printf '  %-12s none — engine never reached its config\n' "qconsole"
  fi

  # --- Wine / Proton side ---------------------------------------------------
  p="$RD/proton.log"
  if [ -f "$p" ]; then
    printf '  %-12s %s lines\n' "proton.log" "$(wc -l < "$p")"
    while IFS='|' read -r label pat; do
      n=$(grep -ci "$pat" "$p" 2>/dev/null); n=${n//[!0-9]/}
      [ "${n:-0}" -gt 0 ] && printf '     %-34s %s\n' "$label" "$n"
    done <<'SIGS'
steamclient_init access violation|Access violation in steamclient_init
access violations (c0000005)|code=c0000005
FP invalid operation (c0000090)|code=c0000090
illegal instruction (c000001d)|code=c000001d
unimplemented function|unimplemented function
FEX unknown Vulkan function|Unknown Vulkan function
Box64 warnings|^\[BOX
SIGS
  fi

  # --- did instrumentation produce anything? --------------------------------
  [ -s "$RD/gpu.csv" ] && {
    local tot nz
    tot=$(( $(wc -l < "$RD/gpu.csv") - 1 ))
    nz=$(awk -F', ' 'NR>1{gsub(/ %/,"",$2); if($2+0>0) n++} END{print n+0}' "$RD/gpu.csv")
    printf '  %-12s %s samples, %s with GPU>0%s\n' "gpu" "$tot" "$nz" \
      "$([ "${nz:-0}" -eq 0 ] && echo '   <-- never rendered' || true)"
  }
}

case "${1:-}" in
  --all) for d in $(ls -dtr "$OUT"/*/ 2>/dev/null); do report "$d"; done ;;
  *)     report "$(pick "$@")" ;;
esac
