#!/usr/bin/env bash
# ============================================================================
# Libs del SO para Chromium (vía dnf) + descarga del browser de Playwright.
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

log "Instalando libs del SO para Chromium + xz (dnf)…"
sudo dnf install -y \
  nss nspr atk at-spi2-atk at-spi2-core cups-libs libdrm \
  libXcomposite libXdamage libXrandr libXext libXfixes libX11 libxcb \
  libxkbcommon mesa-libgbm pango cairo alsa-lib libXScrnSaver gtk3 libXtst xz \
  || log "WARN: dnf no pudo instalar algunas libs; sigo."

log "Descargando browser Chromium de Playwright…"
( cd "$APP_DIR" && npx playwright install chromium )
