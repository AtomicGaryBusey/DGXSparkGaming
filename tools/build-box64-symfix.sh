#!/usr/bin/env bash
# build-box64-symfix.sh — add the four missing box32 libc wrappers, build, and
# TEST whether that actually fixes the steamclient_init access violation.
#
# WHY THIS EXISTS
#   DOOM 3, Prey (2006) and RoE die under Box64 with
#       err:steamclient:steamclient_call Access violation in steamclient_init
#   Root-caused 2026-09-08 (see evidence/2026-09-08-steamclient-init-box64/):
#   Box64 v0.4.4's box32 32-bit libc wrapper table is missing four symbols that
#   the Steam runtime's i386 libstdc++.so.6 imports. Wine dlopens unix halves
#   RTLD_NOW, so missing non-weak R_386_JMP_SLOT relocations are fatal
#   (src/elfs/elfloader32.c:583-591, and `return bindnow?ret_ok:0` at :696),
#   dlopen returns NULL, __wine_unixlib_handle stays 0, and the dispatcher's
#   `call dword ptr [eax+edx*4]` faults with eax=0.
#
#   Every step of that was verified locally. The ONE thing that was not is
#   whether fixing it fixes the game. That is what this script is for. It is a
#   FALSIFICATION TEST, not a claimed fix: if the access violation survives, the
#   chain is wrong somewhere and the README entry must be corrected in place.
#
# WHAT THE PATCH DOES, AND WHAT IT DOES NOT
#   All four symbols ARE exported by the host glibc (2.39 here), so the wrappers
#   forward to the native implementations:
#       arc4random    uEv        uint32_t arc4random(void)                  -- exact
#       strtold       DEpBp_     long double strtold(const char*, char**)
#       strtof128     DEpBp_     _Float128 strtof128(const char*, char**)
#       strfromf128   iEpLpD     int strfromf128(char*, size_t, const char*, _Float128)
#   Letters per rebuild_wrappers.py:1111 -- u=uint32, D=long double, i=int32,
#   L=uintptr_t, p=void*, E=emu, and Bp_ is the bridged out-pointer the 32-bit
#   table already uses for the char** of strtod (`GO(strtod, dEpBp_)`).
#
#   BE HONEST ABOUT THE LONG DOUBLE. Upstream commented `strtold` out under
#   HAVE_LD80BITS deliberately: the x86-32 guest's long double is 80-bit while
#   the ARM64 host's is 128-bit, so values crossing that boundary are converted,
#   not copied. The 64-bit table sidesteps it by redirecting to strtod
#   (`GOD(strtold, DFpp, strtod)`), losing precision on purpose. Our concern here
#   is only that the RELOCATION RESOLVES so dlopen succeeds -- libstdc++ imports
#   these symbols but this path is not known to call them. Precision-sensitive
#   use of long double under box32 remains an open upstream question and this
#   patch does not settle it. Say that if you file it.
#
#   NEVER installs over /usr/local/bin/box64. The packaged build stays the
#   default; the new one is opt-in via BOX64_BIN.
#
# Usage:
#   tools/build-box64-symfix.sh              # patch, build, then test
#   tools/build-box64-symfix.sh --test-only  # just re-run the game test
#   tools/build-box64-symfix.sh --revert     # undo the source patch
set -uo pipefail
SRC="${BOX64_SRC:-$HOME/box64}"
PREFIX="${BOX64_PREFIX:-$HOME/dgx-gaming-work/box64-symfix}"
JOBS="${JOBS:-$(nproc)}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HDR="$SRC/src/wrapped32/wrappedlibc_private.h"
MARK="// DGXSparkGaming: symbols i386 libstdc++ imports"

note() { printf '  %s\n' "$*"; }
die()  { printf '  \033[31mx %s\033[0m\n' "$*"; exit 1; }

[ -f "$HDR" ] || die "no box64 source at $SRC (set BOX64_SRC=)"

if [ "${1:-}" = "--revert" ]; then
  ( cd "$SRC" && git checkout -- src/wrapped32/wrappedlibc_private.h ) \
    && note "reverted $HDR" || die "revert failed"
  exit 0
fi

test_it() {
  echo "== falsification test: does the AV survive the fix? =="
  local bin="$PREFIX/bin/box64"
  [ -x "$bin" ] || die "no box64 at $bin"
  note "built box64: $("$bin" --version 2>&1 | head -1)"
  note "packaged   : $(box64 --version 2>&1 | head -1)"
  echo
  note "Run the game against the new binary and compare:"
  note "  BOX64_BIN=$PREFIX/bin/box64 tools/ab-runtime.sh 3970 150"
  note "Then: tools/run-report.sh --appid 3970"
  note "PASS = zero 'Symbol ... not found' and zero 'Access violation in steamclient_init'."
  note "FAIL = the AV survives; the chain is wrong and README must be corrected."
  echo
  # Check the GENERATED table, not `strings` on the binary. The first version of
  # this check used `strings | grep -qx` and reported all four ABSENT while the
  # patch had in fact applied -- `strtod`, which is definitely wrapped, also
  # showed 0, because these names mostly appear inside longer strings. A check
  # that fails on a known-good control is not a check.
  # Symbol names live in the _private.h table and end up as string literals in
  # the binary; the generated/ files only carry SIGNATURE wrappers, keyed by type
  # rather than name. Two earlier versions of this check were wrong -- `grep -qx`
  # on strings (whole-line, so `strtod` showed 0) and then grepping generated/
  # (which never contains names). Both were caught by the strtod control, which
  # is why the control is here.
  # NO USEFUL STATIC CHECK EXISTS HERE, and three attempts proved it:
  #   1. `strings | grep -qx` -- whole-line match, so even strtod showed 0
  #   2. grepping src/wrapped32/generated/ -- those files carry SIGNATURE
  #      wrappers keyed by type, never symbol names
  #   3. comparing string counts against the stock binary -- confounded, because
  #      arc4random/strfromf128/strtof128 are ALSO in the 64-bit table, so both
  #      binaries contain them regardless of the box32 patch
  # Each wrong version was caught by keeping a known-good control (strtod) in the
  # check. The only honest verdict is the runtime one.
  note "no static check can distinguish box32 from box64 table membership here."
  echo
  note "TESTING THIS IS BLOCKED, and the blocker is worth understanding:"
  note "  The game runs inside pressure-vessel. Once that container namespace"
  note "  exists, every exec goes through binfmt_misc, whose interpreter is"
  note "  hard-wired to /usr/local/bin/box64 -- the STOCK build. Passing"
  note "  BOX64_BIN only affects the first process (reaper); the game itself is"
  note "  still run by the stock binary. A run done that way tests NOTHING, and"
  note "  will look exactly like a failed fix."
  note "  Isolating it outside the container does not work either: the missing"
  note "  symbols are only fatal under dlopen(RTLD_NOW), which is what Wine does"
  note "  and what an ordinary program load does not."
  echo
  note "The only way to settle it needs root, so it is yours to run:"
  note "  sudo cp /usr/local/bin/box64 /usr/local/bin/box64.stock-backup"
  note "  sudo cp $PREFIX/bin/box64 /usr/local/bin/box64"
  note "  tools/ab-runtime.sh 3970 150 && tools/run-report.sh --appid 3970"
  note "  # revert:  sudo cp /usr/local/bin/box64.stock-backup /usr/local/bin/box64"
  note "PASS = zero 'Symbol ... not found' and zero 'steamclient_init' AV."
  note "FAIL = the AV survives; the chain is wrong and README must be corrected"
  note "       IN PLACE, not deleted."
}

[ "${1:-}" = "--test-only" ] && { test_it; exit $?; }

echo "== pre-flight =="
note "source: $SRC ($(cd "$SRC" && git log --oneline -1 2>/dev/null))"
note "prefix: $PREFIX   jobs=$JOBS"
command -v cmake >/dev/null || die "cmake not found"

echo "== patch (idempotent) =="
if grep -qF "$MARK" "$HDR"; then
  note "already applied"
else
  python3 - "$HDR" "$MARK" <<'PY'
import sys
hdr, mark = sys.argv[1], sys.argv[2]
s = open(hdr).read()
# Anchor on a stable, unique line rather than a line number: upstream moves.
anchor = "GO(strtod, dEpBp_)\n"
if anchor not in s:
    print("  !! ANCHOR NOT FOUND — upstream changed; re-derive the patch"); sys.exit(1)
add = anchor + f"""{mark} but box32 does not wrap.
// See evidence/2026-09-08-steamclient-init-box64/ in the DGXSparkGaming repo:
// their absence makes dlopen of the 32-bit lsteamclient.so fail under bind-now,
// which leaves __wine_unixlib_handle NULL and faults steamclient_init.
// All four are exported by host glibc, so these forward to the native versions.
// CAVEAT: the guest's long double is 80-bit and the host's is 128-bit; the
// 64-bit table sidesteps this by redirecting strtold to strtod. Precision-
// sensitive long-double use under box32 is NOT settled by this.
GO(arc4random, uEv)
GO(strtof128, DEpBp_)
GO(strfromf128, iEpLpD)
"""
s = s.replace(anchor, add, 1)

# strtold is NOT added here: upstream already carries commented-out entries in
# BOTH #ifdef HAVE_LD80BITS branches, and adding a third makes the generator
# reject the file with "The symbol strtold is duplicated!". Uncomment upstream's
# own instead, respecting their signatures (DEpp / KEpp) rather than inventing one.
before = s
s = s.replace("//GO(strtold, DEpp)", "GO(strtold, DEpp)", 1)
s = s.replace("//GO(strtold, KEpp)", "GO2(strtold, KEpp, strtod)", 1)
if s == before:
    print("  !! neither strtold anchor found — upstream changed"); sys.exit(1)
open(hdr, "w").write(s)
print("  + arc4random/strtof128/strfromf128 added; upstream strtold uncommented")
PY
  [ $? -eq 0 ] || die "patch failed"
fi
grep -c 'GO(arc4random, uEv)' "$HDR" | sed 's/^/  arc4random entries: /'

echo "== build (log: $PREFIX/build.log) =="
mkdir -p "$PREFIX/build"
cmake -S "$SRC" -B "$PREFIX/build" -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DBOX32=ON -DBOX32_BINFMT=OFF -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      > "$PREFIX/configure.log" 2>&1 || { tail -25 "$PREFIX/configure.log"; die "configure failed"; }
note "configured"
cmake --build "$PREFIX/build" -j "$JOBS" > "$PREFIX/build.log" 2>&1 \
  || { tail -30 "$PREFIX/build.log"; die "build failed (full log: $PREFIX/build.log)"; }
mkdir -p "$PREFIX/bin"
cp "$PREFIX/build/box64" "$PREFIX/bin/box64" 2>/dev/null || die "no box64 binary produced"
note "$PREFIX/bin/box64"
echo
test_it
