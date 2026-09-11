#!/usr/bin/env bash
# ============================================================================
# ffmpeg estático con libx264 (H.264) desde johnvansickle.com. Se conserva si
# ya está presente y soporta libx264.
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

if [ -x "$FFMPEG_BIN" ] && "$FFMPEG_BIN" -version 2>/dev/null | grep -qi 'enable-libx264'; then
  log "ffmpeg con libx264 ya presente; se conserva."
else
  log "Descargando ffmpeg estático (libx264) desde johnvansickle.com…"
  TMP="$(mktemp -d)"
  curl -fSL "$FFMPEG_URL" -o "$TMP/ffmpeg.tar.xz"
  tar -xf "$TMP/ffmpeg.tar.xz" -C "$TMP"
  SRC="$(find "$TMP" -maxdepth 2 -type f -name ffmpeg | head -1)"
  install -m 0755 "$SRC" "$FFMPEG_BIN"
  rm -rf "$TMP"
fi
"$FFMPEG_BIN" -version 2>/dev/null | head -1 || log "WARN: ffmpeg no responde."
