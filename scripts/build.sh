#!/usr/bin/env bash
# Build ttrpg-dev (Rust frontend) and ttrpg-dev-engine (Elixir/Burrito backend).
#
# Both binaries are placed in build_out/ for local testing. Run build_out/ttrpg-dev
# to use the full CLI; ttrpg-dev-engine must sit alongside it (the Rust binary
# locates it relative to its own path).
#
# Usage:
#   ./scripts/build.sh          # build for the current platform
#   ./scripts/build.sh all      # cross-compile engine for all targets (Rust: current only)
#   ./scripts/build.sh linux    # build engine for a specific named target
#
# The Rust binary is always built for the current platform. Cross-compiling the
# Rust frontend for other targets is handled by CI, not this script.
#
# Set TTRPG_DEV_DEBUG=true to bake verbose Burrito startup output into the engine:
#   TTRPG_DEV_DEBUG=true ./scripts/build.sh
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
  echo "No target specified — building engine for current platform: $TARGET"
elif [ "$ARG" = "all" ]; then
  TARGET="linux,macos,macos_arm,windows"
  echo "Building engine for all production targets: $TARGET"
else
  TARGET="$ARG"
  echo "Building engine for target: $TARGET"
fi

# ---- Clear install cache before building ----------------------------
if [ "$TARGET" != "linux,macos,macos_arm,windows" ]; then
  clear_install_cache "./build_out/ttrpg-dev-engine"
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

if ! command -v cargo &>/dev/null; then
  echo "ERROR: cargo not found. Make sure Rust is installed and on PATH."
  exit 1
fi

# ---- Build Rust frontend --------------------------------------------
echo ""
echo "Building Rust frontend (ttrpg-dev)..."
cargo build --release --manifest-path cli/Cargo.toml

# ---- Build Burrito engine -------------------------------------------
echo ""
echo "Fetching prod dependencies..."
mix deps.get --only prod

echo ""
echo "Building Burrito engine (ttrpg-dev-engine)..."
BURRITO_TARGET="$TARGET" MIX_ENV=prod mix release ttrpg_dev_engine --overwrite

# ---- Assemble build_out/ --------------------------------------------
echo ""
echo "Assembling build_out/..."
mkdir -p build_out

# Rust binary (current platform only)
if [ -f "cli/target/release/ttrpg-dev" ]; then
  cp cli/target/release/ttrpg-dev build_out/ttrpg-dev
  chmod +x build_out/ttrpg-dev
elif [ -f "cli/target/release/ttrpg-dev.exe" ]; then
  cp cli/target/release/ttrpg-dev.exe build_out/ttrpg-dev.exe
fi

# Engine binary for single-target builds
if [ "$TARGET" != "linux,macos,macos_arm,windows" ]; then
  engine="burrito_out/ttrpg_dev_engine_${TARGET}"
  if [ -f "$engine" ]; then
    cp "$engine" build_out/ttrpg-dev-engine
    chmod +x build_out/ttrpg-dev-engine
  fi
fi

# ---- Summary --------------------------------------------------------
echo ""
echo "Done. build_out/:"
ls build_out/
echo ""
echo "Run: ./build_out/ttrpg-dev"
