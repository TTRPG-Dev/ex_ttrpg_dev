#!/usr/bin/env bash
# Build ttrpg_dev_cli as a standalone Burrito binary for local testing.
#
# Usage:
#   ./scripts/build_cli.sh          # build for the current platform only
#   ./scripts/build_cli.sh all      # cross-compile all release targets
#   ./scripts/build_cli.sh linux    # build a specific target by name
#
# Targets: linux | macos | macos_arm | windows
#
# Requirements: Zig must be on your PATH. https://ziglang.org/download/

set -euo pipefail

# ---- Detect current platform ----------------------------------------
detect_target() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)

  case "$os" in
    Linux)  echo "linux" ;;
    Darwin)
      if [ "$arch" = "arm64" ]; then echo "macos_arm"; else echo "macos"; fi ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)
      echo "ERROR: unsupported OS '$os'" >&2
      exit 1 ;;
  esac
}

# ---- Resolve target argument ----------------------------------------
ARG="${1:-}"

if [ -z "$ARG" ]; then
  TARGET=$(detect_target)
  echo "No target specified — building for current platform: $TARGET"
elif [ "$ARG" = "all" ]; then
  TARGET="linux,macos,macos_arm,windows"
  echo "Building all targets: $TARGET"
else
  TARGET="$ARG"
  echo "Building target: $TARGET"
fi

# ---- Preflight checks -----------------------------------------------
if ! command -v zig &>/dev/null; then
  echo ""
  echo "ERROR: Zig is required by Burrito but was not found on PATH."
  echo "Install it from https://ziglang.org/download/ or via your package manager."
  exit 1
fi

if ! command -v mix &>/dev/null; then
  echo "ERROR: mix not found. Make sure Elixir is installed and on PATH."
  exit 1
fi

# ---- Build ----------------------------------------------------------
echo ""
echo "Fetching prod dependencies..."
mix deps.get --only prod

echo ""
echo "Building Burrito release..."
BURRITO_TARGET="$TARGET" MIX_ENV=prod mix release

# ---- Summary --------------------------------------------------------
echo ""
echo "Done. Binaries written to burrito_out/:"
ls burrito_out/
