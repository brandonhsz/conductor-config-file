#!/usr/bin/env bash
# ============================================================================
# Persiste las env vars del tooling de video en ~/.bash_profile (idempotente).
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

log "Persistiendo env vars en ~/.bash_profile…"
PROFILE="$HOME/.bash_profile"; touch "$PROFILE"
grep -q '^export VIDEOS_DIR='        "$PROFILE" || echo 'export VIDEOS_DIR="$HOME/playwright-videos"'            >> "$PROFILE"
grep -q '^export PW_VIDEO_APP_DIR=' "$PROFILE" || echo 'export PW_VIDEO_APP_DIR="$HOME/playwright-video-server"' >> "$PROFILE"
