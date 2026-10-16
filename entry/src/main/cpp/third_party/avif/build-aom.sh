#!/usr/bin/env bash
# ============================================================================
# One-click rebuild of the prebuilt libaom binaries (AV1 decoder-only) for
# the vendored libavif in this directory. macOS / Linux (also works in Git
# Bash on Windows).
#
# Usage:
#   ./build-aom.sh            rebuild arm64-v8a + x86_64
#   ./build-aom.sh arm64      rebuild arm64-v8a only
#   ./build-aom.sh x64        rebuild x86_64 only
#
# The OHOS native SDK is located via the standard DevEco conventions, in this
# order (no machine-specific paths):
#   1. OHOS_SDK        - native SDK dir (contains build/cmake/ohos.toolchain.cmake)
#   2. DEVECO_SDK_HOME - DevEco Studio SDK root (contains default/openharmony)
#   3. OHOS_SDK_HOME   - same layout as DEVECO_SDK_HOME
#   4. Standard install: /Applications/DevEco Studio.app/Contents/sdk (macOS)
#
# Requirements:
#   - perl (preinstalled on macOS; Git Bash ships one)
#   - nasm on PATH for the x64 target (macOS: brew install nasm)
#
# Outputs are copied to: prebuilt/<abi>/libaom.a
# See README.md in this directory for full provenance.
# ============================================================================
set -euo pipefail

VENDORDIR="$(cd "$(dirname "$0")" && pwd)"
WORK="${TMPDIR:-/tmp}/mihon-aom"
SRC="$VENDORDIR/aom"
TARGET="${1:-all}"

EXE=""
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) EXE=".exe" ;;
esac

# ---------------------------------------------------------------------------
# Locate the OHOS native SDK
resolve_sdk() {
  # $1: candidate root; prints the resolved native SDK dir, or fails
  local root="$1"
  if [ -f "$root/build/cmake/ohos.toolchain.cmake" ]; then
    printf '%s\n' "$root"
    return 0
  fi
  if [ -f "$root/default/openharmony/native/build/cmake/ohos.toolchain.cmake" ]; then
    printf '%s\n' "$root/default/openharmony/native"
    return 0
  fi
  return 1
}

SDK=""
for cand in "${OHOS_SDK:-}" "${DEVECO_SDK_HOME:-}" "${OHOS_SDK_HOME:-}" \
            "/Applications/DevEco Studio.app/Contents/sdk"; do
  [ -z "$cand" ] && continue
  if SDK="$(resolve_sdk "$cand")"; then
    break
  fi
  SDK=""
done
if [ -z "$SDK" ]; then
  echo "ERROR: OHOS native SDK not found." >&2
  echo "Set DEVECO_SDK_HOME to the DevEco Studio SDK root, or OHOS_SDK to" >&2
  echo "the native SDK dir (contains build/cmake/ohos.toolchain.cmake)." >&2
  exit 1
fi
# cmake-safe form: forward slashes (backslashes break CMakeASMCompiler.cmake)
SDK="${SDK//\\//}"
echo "Using SDK: $SDK"

CMAKE="$SDK/build-tools/cmake/bin/cmake$EXE"
NINJA="$SDK/build-tools/cmake/bin/ninja$EXE"
if [ ! -f "$CMAKE" ]; then
  echo "ERROR: cmake not found at $CMAKE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# libaom source (git submodule)
if [ ! -f "$SRC/CMakeLists.txt" ]; then
  echo "ERROR: libaom source not found at $SRC" >&2
  echo "       Run: git submodule update --init" >&2
  exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
  echo "ERROR: perl not found (required by the aom build)." >&2
  exit 1
fi
PERL="$(command -v perl)"

case "$TARGET" in
  arm64|x64|all) ;;
  *) echo "usage: build-aom.sh [arm64|x64|all]" >&2; exit 2 ;;
esac

if [ "$TARGET" = "x64" ] || [ "$TARGET" = "all" ]; then
  if ! command -v nasm >/dev/null 2>&1; then
    echo "ERROR: nasm not found (required for x86_64 assembly)." >&2
    echo "       macOS: brew install nasm" >&2
    exit 1
  fi
fi

mkdir -p "$WORK"

# ---------------------------------------------------------------------------
build_abi() {
  local label="$1" arch="$2" dir="$3"
  local bdir="$WORK/build/aom-$label"
  rm -rf "$bdir"
  echo ""
  echo "=== libaom $label ($arch) ==="
  "$CMAKE" -G Ninja -S "$SRC" -B "$bdir" \
    -DCMAKE_TOOLCHAIN_FILE="$SDK/build/cmake/ohos.toolchain.cmake" \
    -DOHOS_ARCH="$arch" -DOHOS_PLATFORM=OHOS \
    -DCMAKE_BUILD_TYPE=Release \
    -DCONFIG_AV1_ENCODER=0 -DCONFIG_AV1_DECODER=1 \
    -DCMAKE_ASM_COMPILER="$SDK/llvm/bin/clang$EXE" \
    -DCMAKE_MAKE_PROGRAM="$NINJA" \
    -DPERL_EXECUTABLE="$PERL" \
    -DCMAKE_C_FLAGS_RELEASE="-Oz -DNDEBUG -flax-vector-conversions=none" \
    -DCMAKE_ASM_FLAGS_RELEASE="-Oz -DNDEBUG"
  "$NINJA" -C "$bdir"
  if [ ! -f "$bdir/libaom.a" ]; then
    echo "ERROR: $bdir/libaom.a not produced" >&2
    exit 1
  fi
  cp -f "$bdir/libaom.a" "$VENDORDIR/prebuilt/$dir/libaom.a"
  echo "-> prebuilt/$dir/libaom.a  $(wc -c < "$VENDORDIR/prebuilt/$dir/libaom.a") bytes"
}

case "$TARGET" in
  arm64) build_abi arm64 arm64-v8a arm64-v8a ;;
  x64)   build_abi x64 x86_64 x86_64 ;;
  all)
    build_abi arm64 arm64-v8a arm64-v8a
    build_abi x64 x86_64 x86_64
    ;;
esac

echo ""
echo "Done. Updated prebuilt libaom.a for target(s): $TARGET"
echo "Rebuild the HAP to pick up the new binaries."
