#!/usr/bin/env bash
# Build ttrpg_dev_cli as a standalone Burrito binary for local testing.
#
# Usage:
#   ./scripts/build_cli.sh          # build for the current platform
#   ./scripts/build_cli.sh all      # cross-compile all production release targets
#   ./scripts/build_cli.sh linux    # build a specific named target
#
# By default the binary is built in production mode (quiet startup).
# Set TTRPG_DEV_DEBUG=true to bake verbose Burrito startup output into the binary:
#
#   TTRPG_DEV_DEBUG=true ./scripts/build_cli.sh
#
# For single-target builds the script clears the Burrito install cache before
# building so the newly built binary is always used on next run, even when the
# version number has not changed.
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

# ---- Clear Burrito install cache ------------------------------------
# Uses the existing binary's `maintenance directory` command (Zig-only, no
# BEAM startup) to locate and delete the cached install directory.  Running
# this before rebuilding ensures the next invocation always extracts fresh.
clear_install_cache() {
  local binary="$1"
  if [ ! -f "$binary" ]; then
    return 0
  fi
  local install_dir
  install_dir=$("$binary" maintenance directory 2>/dev/null || true)
  if [ -n "$install_dir" ] && [ -d "$install_dir" ]; then
    rm -rf "$install_dir"
    echo "Cleared install cache: $install_dir"
  fi
}

# ---- Resolve target argument ----------------------------------------
ARG="${1:-}"

if [ -z "$ARG" ]; then
  TARGET=$(detect_target)
  echo "No target specified — building for current platform: $TARGET"
elif [ "$ARG" = "all" ]; then
  TARGET="linux,macos,macos_arm,windows"
  echo "Building all production targets: $TARGET"
else
  TARGET="$ARG"
  echo "Building target: $TARGET"
fi

# ---- Clear install cache before building ----------------------------
# Skip for multi-target builds since binary paths are ambiguous.
if [ "$TARGET" != "linux,macos,macos_arm,windows" ]; then
  clear_install_cache "./burrito_out/ttrpg_dev_cli_${TARGET}"
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
BURRITO_TARGET="$TARGET" MIX_ENV=prod mix release --overwrite

# ---- Summary --------------------------------------------------------
echo ""
echo "Done. Binaries written to burrito_out/:"
ls burrito_out/
