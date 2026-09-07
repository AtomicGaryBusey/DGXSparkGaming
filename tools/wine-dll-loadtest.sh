#!/usr/bin/env bash
# wine-dll-loadtest.sh — load a Windows DLL under Wine/FEX and report EXACTLY where it faults.
#
# WHY THIS EXISTS
#   On 2026-09-07 a DLL that crashed during initialisation cost three failed game launches and
#   three confident wrong diagnoses (a self-import, a proxy-name collision, my own build patches).
#   Each guess cost ~10 minutes of Steam + launcher + shader cache. This answers the same question
#   in seconds, offline, and it answers it with an address instead of a theory.
#
#   It found the real cause immediately: the fault was in *Wine's builtin MSVCP140.dll*, at an
#   address BELOW our DLL's base -- so it was never our code. A 30-line control DLL then isolated
#   it completely: clang-built DLLs linking the DYNAMIC MSVC CRT (-fms-runtime-lib=dll) fault
#   inside Wine's builtin msvcp140; the same DLL built with the static CRT loads fine, and so does
#   the dynamic one once Microsoft's genuine CRT DLLs are present and overridden to native.
#
# WHAT IT DOES
#   Builds a tiny harness exe (clang-20 + xwin) that calls LoadLibrary inside __try/__except,
#   then runs it under Proton's wine via FEX. On a fault it prints the exception code, the
#   absolute address, the owning MODULE and the RVA -- enough to identify the culprit without
#   a debugger. GetLastError 998 (ERROR_NOACCESS) means the loader swallowed an AV in DllMain.
#
#   Run it inside the target game's directory with that game's WINEPREFIX: dependency resolution
#   and DLL overrides both matter, and a bare prefix gives a misleading ERROR_MOD_NOT_FOUND (126).
#
# Usage:
#   tools/wine-dll-loadtest.sh <dll> [game-dir] [wineprefix]
#   tools/wine-dll-loadtest.sh winmm.dll "$STEAM/steamapps/common/Cyberpunk 2077/bin/x64" \
#       "$STEAM/steamapps/compatdata/1091500/pfx"
#
set -uo pipefail
DLL="${1:-}"
[ -z "$DLL" ] && { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
DIR="${2:-$PWD}"
PFX="${3:-$HOME/dgx-gaming-work/opti-harness/pfx}"
AB="$HOME/dgx-gaming-work/addon-build"
CLANGXX="$AB/clang20/root/usr/bin/clang++-20"
XWIN="$AB/xwin-sdk"
PROTON="$HOME/.local/share/Steam/steamapps/common/Proton - Experimental"
H="$HOME/dgx-gaming-work/opti-harness"
mkdir -p "$H" "$PFX"

[ -x "$CLANGXX" ] || { echo "missing clang-20 — run tools/build-dlssnr-addon.sh first"; exit 1; }
[ -x "$PROTON/files/bin/wine" ] || { echo "missing Proton at $PROTON"; exit 1; }

if [ ! -x "$H/loadtest.exe" ] || [ "$0" -nt "$H/loadtest.exe" ]; then
  cat > "$H/loadtest.c" <<'EOF'
#include <windows.h>
#include <stdio.h>
static char g_mod[MAX_PATH]="?"; static unsigned long long g_rva,g_addr,g_code;
static LONG WINAPI filt(EXCEPTION_POINTERS*ep){
  g_code=ep->ExceptionRecord->ExceptionCode; g_addr=(unsigned long long)ep->ExceptionRecord->ExceptionAddress;
  HMODULE m=NULL;
  if(GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
     (LPCSTR)(uintptr_t)g_addr,&m)&&m){GetModuleFileNameA(m,g_mod,MAX_PATH); g_rva=g_addr-(unsigned long long)m;}
  return EXCEPTION_EXECUTE_HANDLER;
}
int main(int argc,char**argv){
  if(argc<2){printf("usage: loadtest <dll>\n");return 2;}
  printf("loadtest: loading %s\n",argv[1]); fflush(stdout);
  HMODULE h=NULL; DWORD err=0;
  __try { h=LoadLibraryA(argv[1]); err=GetLastError(); }
  __except(filt(GetExceptionInformation())){
    printf("FAULT   code=0x%llx\n        address=0x%llx\n        module=%s\n        RVA=0x%llx\n",
           g_code,g_addr,g_mod,g_rva); fflush(stdout); return 3; }
  if(h){printf("OK      loaded at %p\n",(void*)h); fflush(stdout); return 0;}
  printf("FAILED  LoadLibrary returned NULL, GetLastError=%lu%s\n",err,
         err==998?"  (ERROR_NOACCESS: AV inside DllMain)":err==126?"  (ERROR_MOD_NOT_FOUND: missing dependency)":"");
  fflush(stdout); return 1;
}
EOF
  R="$("$CLANGXX" -print-resource-dir)"
  "$CLANGXX" -target x86_64-pc-windows-msvc -O1 -fms-runtime-lib=static -D_CRT_SECURE_NO_WARNINGS -x c++ \
    -isystem "$R/include" -isystem "$XWIN/crt/include" -isystem "$XWIN/sdk/include/ucrt" \
    -isystem "$XWIN/sdk/include/um" -isystem "$XWIN/sdk/include/shared" \
    -L "$XWIN/crt/lib/x86_64" -L "$XWIN/sdk/lib/um/x86_64" -L "$XWIN/sdk/lib/ucrt/x86_64" -fuse-ld=lld \
    "$H/loadtest.c" -o "$H/loadtest.exe" -lkernel32 2>&1 | grep -E 'error' | head -5
  # static CRT on purpose: the harness must not itself depend on the thing it is testing
  [ -x "$H/loadtest.exe" ] || { echo "harness build failed"; exit 1; }
fi

cp -f "$H/loadtest.exe" "$DIR/loadtest.exe" 2>/dev/null || { echo "cannot write to $DIR"; exit 1; }
echo "dll=$DLL  dir=$DIR"
echo "prefix=$PFX"
timeout 300 aa-exec -p steam -- env WINEPREFIX="$PFX" WINEDEBUG=-all \
  FEXBash -c "cd '$DIR' && '$PROTON/files/bin/wine' loadtest.exe '$DLL'" 2>&1 \
  | grep -E '^loadtest:|^OK|^FAULT|^FAILED|^ +(code|address|module|RVA)=' | sed 's/^/  /'
rm -f "$DIR/loadtest.exe"
