#!/usr/bin/env bash
# Builds the minimal FFmpeg the app links for WMA / APE / WavPack / TTA:
# static libavformat + libavcodec + libavutil with only those demuxers and
# decoders, for every Android ABI the app ships.
#
#   tools/ffmpeg/build.sh <android-ndk-dir> [out-dir]
#
# Output: <out-dir>/<abi>/{include,lib} (default android/app/src/main/cpp/ffmpeg),
# which android/app/src/main/cpp/CMakeLists.txt links. Needs a Linux (or WSL)
# shell with make; CI caches the result keyed on this file.
set -euo pipefail

NDK="${1:?usage: build.sh <android-ndk-dir> [out-dir]}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${2:-$ROOT/android/app/src/main/cpp/ffmpeg}"
FFMPEG_VERSION=7.1.1
API=24
WORK="${FFMPEG_WORK:-$HOME/.cache/audifac-ffmpeg}"

TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
[ -x "$TC/bin/clang" ] || { echo "No NDK LLVM toolchain at $TC" >&2; exit 1; }

mkdir -p "$WORK"
SRC="$WORK/ffmpeg-$FFMPEG_VERSION"
if [ ! -d "$SRC" ]; then
  curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" -o "$WORK/ffmpeg.tar.xz"
  tar -xJf "$WORK/ffmpeg.tar.xz" -C "$WORK"
fi

build_abi() {
  local abi=$1 arch=$2 cpu=$3 triple=$4 extra=$5
  local prefix="$OUT/$abi" build="$WORK/build-$abi"
  rm -rf "$build" "$prefix"
  mkdir -p "$build"
  (
    cd "$build"
    "$SRC/configure" \
      --prefix="$prefix" \
      --target-os=android --enable-cross-compile \
      --arch="$arch" --cpu="$cpu" \
      --cc="$TC/bin/${triple}${API}-clang" \
      --cxx="$TC/bin/${triple}${API}-clang++" \
      --ar="$TC/bin/llvm-ar" --nm="$TC/bin/llvm-nm" \
      --ranlib="$TC/bin/llvm-ranlib" --strip="$TC/bin/llvm-strip" \
      --sysroot="$TC/sysroot" \
      --enable-static --disable-shared --enable-pic \
      --disable-programs --disable-doc --disable-autodetect --disable-network \
      --disable-avdevice --disable-avfilter --disable-swscale --disable-swresample --disable-postproc \
      --disable-everything \
      --enable-demuxer=asf,ape,wv,tta \
      --enable-decoder=wmav1,wmav2,wmapro,wmalossless,ape,wavpack,tta \
      --extra-cflags="-O2 -fPIC" \
      $extra >/dev/null
    make -j"$(nproc)" >/dev/null
    make install >/dev/null
  )
  rm -rf "$prefix/share" "$prefix/lib/pkgconfig"
  echo "$abi: $(du -sh "$prefix/lib" | cut -f1)"
}

build_abi arm64-v8a   aarch64 armv8-a aarch64-linux-android     ""
# 32-bit ARM and x86_64: plain C (no hand-written asm toolchain hassles; these
# decoders are cheap).
build_abi armeabi-v7a arm     armv7-a armv7a-linux-androideabi  "--disable-asm"
build_abi x86_64      x86_64  x86-64  x86_64-linux-android      "--disable-asm"
