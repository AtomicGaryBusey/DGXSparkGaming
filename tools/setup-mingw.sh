#!/usr/bin/env bash
# setup-mingw.sh — fetch a Windows cross-compiler WITHOUT touching the system.
#
# WHY THIS EXISTS
#   Testing whether Windows-side injection (ReShade, Detours-style hooks, NGX shims)
#   survives FEX requires building Windows PE binaries on this ARM64 box. The obvious
#   route — a third-party project's install-deps.sh — wanted `sudo apt install` plus
#   piping a remote script to root, to build one-day-old code. Unacceptable for a test.
#   This instead pulls mingw-w64 straight from Ubuntu's official archive and unpacks
#   it into a local prefix: no sudo, nothing installed system-wide, trivially deletable.
#
#   2026-09-07: extended to i686. The x87 tag-word investigation needs a 32-bit
#   Windows PE, because every id Tech 4 game is 32-bit and the suspect path is
#   Wine's 32<->64-bit CONTEXT conversion. A 64-bit-only toolchain cannot probe it.
#
# Usage:  ./tools/setup-mingw.sh [prefix]        (default ~/dgx-gaming-work/toolchain)
#         MINGW_ARCH=i686 ./tools/setup-mingw.sh # 32-bit instead of x86-64
#         export PATH="<prefix>/root/usr/bin:$PATH"
#         x86_64-w64-mingw32-gcc-win32 -o foo.exe foo.c
#         i686-w64-mingw32-gcc-win32   -o foo.exe foo.c
# Note the `-win32` suffix: Ubuntu ships the compilers under the threading-model
# suffix and relies on update-alternatives for the bare name, which a local unpack
# does not get. Call the suffixed binary directly.
set -euo pipefail
PREFIX="${1:-$HOME/dgx-gaming-work/toolchain}"
ARCH="${MINGW_ARCH:-x86-64}"
case "$ARCH" in
  x86-64) TRIPLE=x86_64-w64-mingw32; DEVPKG=mingw-w64-x86-64-dev; APKG=x86-64 ;;
  i686)   TRIPLE=i686-w64-mingw32;   DEVPKG=mingw-w64-i686-dev;   APKG=i686   ;;
  *) echo "!! MINGW_ARCH must be x86-64 or i686"; exit 2 ;;
esac
PKGS=(mingw-w64 mingw-w64-common "$DEVPKG" gcc-mingw-w64-base
      "gcc-mingw-w64-$APKG-win32" "gcc-mingw-w64-$APKG-win32-runtime"
      "g++-mingw-w64-$APKG-win32" "binutils-mingw-w64-$APKG")
mkdir -p "$PREFIX/debs" "$PREFIX/root"
if [ -x "$PREFIX/root/usr/bin/$TRIPLE-gcc-win32" ]; then
  echo "==> $ARCH already present at $PREFIX"; exit 0
fi
echo "==> downloading ${#PKGS[@]} packages ($ARCH) from Ubuntu's archive"
( cd "$PREFIX/debs" && apt-get download "${PKGS[@]}" >/dev/null 2>&1 )
echo "==> unpacking locally (no sudo, no system change)"
for f in "$PREFIX"/debs/*.deb; do dpkg -x "$f" "$PREFIX/root"; done
CC="$PREFIX/root/usr/bin/$TRIPLE-gcc-win32"
[ -x "$CC" ] || { echo "!! compiler missing after unpack"; exit 1; }
echo "==> $($CC --version | head -1)"
echo "==> export PATH=\"$PREFIX/root/usr/bin:\$PATH\""
