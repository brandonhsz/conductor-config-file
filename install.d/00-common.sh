#!/usr/bin/env bash
# ============================================================================
# Config y helpers compartidos por todos los módulos del instalador.
# Idempotente y seguro de sourcear/ejecutar varias veces.
# ============================================================================
set -euo pipefail

# Marca para que los módulos sepan que el común ya se cargó.
_COMMON_LOADED=1

APP_DIR="${APP_DIR:-$HOME/playwright-video-server}"
VIDEOS_DIR="${VIDEOS_DIR:-$HOME/playwright-videos}"
FFMPEG_BIN="${FFMPEG_BIN:-$APP_DIR/ffmpeg}"
FFMPEG_URL="${FFMPEG_URL:-https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz}"

log(){ printf '==> %s\n' "$*"; }

mkdir -p "$APP_DIR" "$VIDEOS_DIR"
