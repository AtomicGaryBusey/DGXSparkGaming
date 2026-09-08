#!/usr/bin/env bash
# fex-build.sh — build FEX-Emu from source into a local prefix, and prove the
# build is better than the packaged one before trusting it.
#
# WHY THIS EXISTS
#   The PPA build (2607/2608) has measured defects this log now depends on:
#     * CPUID leaf 1 reports DE=0 and PSE=0. Every real x86 that advertises SSE2
#       also sets those, and games of the Burnout Paradise era commonly test a
#       MASK of leaf-1 EDX bits rather than SSE2 alone -- which is why "FEX
#       advertises SSE2" did not settle that title. Verified fixed at fexsrc HEAD:
#       FEXCore/Source/Interface/Core/CPUID.cpp sets (1<<2) and (1<<3).
#     * The whole x87 investigation would benefit from being able to test a patch
#       rather than only report a bug.
#
#   The point is not "build FEX". The point is that a build you cannot MEASURE is
#   worse than the package, because it silently changes every result afterwards.
#   So this ends by running tools/isa-probe.sh against the new binaries, where the
#   cpuid probe should flip from MISMATCH to OK. If it does not, the build did not
#   do what you think and the script says so.
#
# HARD-WON DETAILS (each one costs a full build cycle to rediscover)
#   * clang ONLY. CMakeLists.txt:72 does message(FATAL_ERROR "FEX doesn't support
#     GCC! Use Clang instead."). Verified in this tree.
#   * -DENABLE_LTO=False. It defaults TRUE, and clang + the system GNU ld without
#     an LLVMgold plugin fails at link.
#   * -DBUILD_TESTING=False, not -DBUILD_TESTS.
#   * Submodules are NOT initialised in ~/dgx-gaming-work/fexsrc. Init them, do
#     not re-clone -- the tree is already at a known commit.
#   * NEVER install over /usr. The system FEX stays the fallback; this prefix is
#     opt-in via FEX_BIN. A half-replaced system FEX with the desktop's Steam
#     running under it is not a situation you want.
#   * A FEXServer from the packaged build may already be running. The server and
#     interpreter must be the SAME build, so the test step starts its own.
#
# Usage:
#   tools/fex-build.sh                 # configure, build, then probe-test
#   tools/fex-build.sh --test-only     # just re-run the probes against the build
#   JOBS=8 tools/fex-build.sh
set -uo pipefail
SRC="${FEXSRC:-$HOME/dgx-gaming-work/fexsrc}"
PREFIX="${FEXPREFIX:-$HOME/dgx-gaming-work/fex-build}"
CLANGDIR="$HOME/dgx-gaming-work/addon-build/clang20/root/usr/bin"
JOBS="${JOBS:-$(nproc)}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

note() { printf '  %s\n' "$*"; }
die()  { printf '  \033[31mx %s\033[0m\n' "$*"; exit 1; }

probe_test() {
  echo "== regression gate: tools/isa-probe.sh against the new build =="
  [ -x "$PREFIX/bin/FEXInterpreter" ] || die "no FEXInterpreter at $PREFIX/bin"
  note "packaged FEX first, for comparison:"
  ( cd "$REPO" && tools/isa-probe.sh 2>&1 | sed 's/^/    /' ) || true
  echo
  note "the build under test:"
  ( cd "$REPO" && FEX_BIN="$PREFIX/bin" tools/isa-probe.sh 2>&1 | sed 's/^/    /' )
  rc=$?
  echo
  if [ $rc -eq 0 ]; then
    echo "  Every probe matches the SDM. Use it with:  FEX_BIN=$PREFIX/bin"
  else
    echo "  Probes still mismatch. Read the table above BEFORE using this build:"
    echo "  a mismatch that survives a source build is a different bug from the"
    echo "  one you set out to fix, and a build you cannot measure is worse than"
    echo "  the package."
  fi
  return $rc
}

[ "${1:-}" = "--test-only" ] && { probe_test; exit $?; }

echo "== pre-flight =="
[ -d "$SRC" ] || die "no FEX source at $SRC"
CXX="$CLANGDIR/clang++-20"; CC="$CLANGDIR/clang-20"
[ -x "$CXX" ] || { CXX=$(command -v clang++-20 || command -v clang++) || true; CC=$(command -v clang-20 || command -v clang) || true; }
[ -n "${CXX:-}" ] && [ -x "$CXX" ] || die "no clang++ — FEX's CMakeLists FATAL_ERRORs on GCC"
note "compiler: $($CXX --version | head -1)"
note "source:   $SRC ($(cd "$SRC" && git log --oneline -1))"
note "prefix:   $PREFIX   jobs=$JOBS"
command -v cmake >/dev/null || die "cmake not found"

echo "== submodules =="
( cd "$SRC" && git submodule update --init --recursive --depth 1 ) \
  || die "submodule init failed"
note "ok"

echo "== configure =="
BUILD="$SRC/build-local"
mkdir -p "$BUILD"
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DENABLE_LTO=False \
  -DBUILD_TESTING=False \
  -DENABLE_ASSERTIONS=False \
  > "$BUILD/configure.log" 2>&1 || { tail -25 "$BUILD/configure.log"; die "configure failed (full log: $BUILD/configure.log)"; }
note "ok"

echo "== build (this takes a while; log: $BUILD/build.log) =="
cmake --build "$BUILD" -j "$JOBS" > "$BUILD/build.log" 2>&1 \
  || { tail -30 "$BUILD/build.log"; die "build failed (full log: $BUILD/build.log)"; }
note "ok"

echo "== install to the LOCAL prefix (never /usr) =="
cmake --install "$BUILD" > "$BUILD/install.log" 2>&1 || { tail -20 "$BUILD/install.log"; die "install failed"; }
note "$PREFIX"
ls "$PREFIX/bin" 2>/dev/null | sed 's/^/    /'
echo
probe_test
