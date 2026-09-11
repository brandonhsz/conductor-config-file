#!/usr/bin/env bash
# ============================================================================
# Toolchain de JavaScript para avena-mobile (React Native 0.85).
#   · corepack habilitado + yarn 3.6.4 pre-cacheado (packageManager del repo)
#   · watchman (best-effort; Metro corre sin él, solo lo usa para file-watching)
# El `yarn install` del repo NO va aquí (es per-workspace): vive en
#   avena-mobile/.conductor/settings.toml → [scripts].setup
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

YARN_VERSION="${YARN_VERSION:-3.6.4}"

log "Node: $(node -v 2>/dev/null || echo 'NO ENCONTRADO')"

log "Habilitando corepack y pre-cacheando yarn ${YARN_VERSION}…"
if command -v corepack >/dev/null 2>&1; then
  sudo corepack enable 2>/dev/null || corepack enable || log "WARN: no pude 'corepack enable'."
  # Pre-descarga yarn 3.6.4 al cache de corepack para que el setup del workspace
  # sea offline/rápido. El repo lo activa vía su campo packageManager igualmente.
  corepack prepare "yarn@${YARN_VERSION}" --activate \
    || log "WARN: no pude pre-cachear yarn@${YARN_VERSION}; corepack lo bajará on-demand."
else
  log "WARN: corepack no está disponible; Node debería traerlo (>=16.10)."
fi
corepack yarn --version 2>/dev/null | sed 's/^/==> yarn /' || true

log "watchman (best-effort)…"
if command -v watchman >/dev/null 2>&1; then
  log "watchman ya presente; se conserva."
else
  # No hay paquete oficial de watchman en Amazon Linux 2023 y compilarlo desde
  # fuente es frágil. Metro funciona sin watchman (usa el file-watching de Node),
  # así que NO fallamos el build si no está: solo lo intentamos vía dnf.
  sudo dnf install -y watchman >/dev/null 2>&1 \
    && log "watchman instalado vía dnf." \
    || log "watchman no disponible vía dnf; se omite (Metro corre sin él)."
fi

log "Toolchain JS listo."
