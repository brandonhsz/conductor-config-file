#!/usr/bin/env bash
# ============================================================================
# Obsidian ensure-login — asegura login + sync-setup + sync del vault en RUNTIME.
#
# Por qué existe: install.d/85-obsidian-headless.sh corre en build-time, cuando
# los secrets OBSIDIAN_* todavia NO estan en env (Conductor los inyecta en
# runtime). Por eso el build solo instala el cliente 'ob' y omite el login.
# Este script se ejecuta en cada arranque de sesion (hook SessionStart) para
# dejar la cuenta logueada y el vault sincronizado en cada workspace.
#
# Idempotente y best-effort: si ya hay sesion y vault configurado, solo hace un
# 'ob sync'; nunca debe tumbar el arranque de la sesion.
#
# Env vars (secrets de Conductor en runtime):
#   OBSIDIAN_EMAIL, OBSIDIAN_PASSWORD  -> login de la cuenta
#   OBSIDIAN_ENCRYPTION_PASSWORD       -> password de cifrado E2E del vault
#   OBSIDIAN_VAULT                     -> id o nombre del vault remoto
#   OBSIDIAN_VAULT_PATH (opcional)     -> ruta local del vault (default ~/second-brain)
# ============================================================================
set -uo pipefail

VP="${OBSIDIAN_VAULT_PATH:-$HOME/second-brain}"

log() { printf '[obsidian-ensure] %s\n' "$*"; }

# Cliente disponible?
if ! command -v ob >/dev/null 2>&1; then
  log "cliente 'ob' no instalado; nada que hacer."
  exit 0
fi

# Ya logueado? sync-list-remote falla sin sesion activa.
if ! ob sync-list-remote </dev/null >/dev/null 2>&1; then
  if [ -z "${OBSIDIAN_EMAIL:-}" ] || [ -z "${OBSIDIAN_PASSWORD:-}" ]; then
    log "sin OBSIDIAN_EMAIL/OBSIDIAN_PASSWORD en env; omito login."
    exit 0
  fi
  log "sin sesion; login como ${OBSIDIAN_EMAIL}..."
  if printf '%s\n' "$OBSIDIAN_PASSWORD" | ob login --email "$OBSIDIAN_EMAIL" >/dev/null 2>&1; then
    log "login OK."
  else
    log "WARN: login fallo (credenciales o red); se reintenta en el proximo arranque."
    exit 0
  fi
fi

# Vault configurado localmente en este path?
if ! ob sync-list-local </dev/null 2>&1 | grep -Fq "$VP"; then
  if [ -z "${OBSIDIAN_VAULT:-}" ] || [ -z "${OBSIDIAN_ENCRYPTION_PASSWORD:-}" ]; then
    log "sin OBSIDIAN_VAULT/OBSIDIAN_ENCRYPTION_PASSWORD en env; omito sync-setup."
    exit 0
  fi
  mkdir -p "$VP"
  log "configurando sync del vault '${OBSIDIAN_VAULT}' -> ${VP}..."
  if printf '%s\n' "$OBSIDIAN_ENCRYPTION_PASSWORD" | ob sync-setup \
        --vault "$OBSIDIAN_VAULT" \
        --path "$VP" \
        --device-name "conductor-cloud" >/dev/null 2>&1; then
    log "sync-setup OK."
  else
    log "WARN: sync-setup fallo (vault o encryption password); se reintenta luego."
    exit 0
  fi
fi

log "sincronizando vault..."
if ob sync --path "$VP" </dev/null >/dev/null 2>&1; then
  log "vault sincronizado en ${VP}."
else
  log "WARN: sync fallo; se reintenta en el proximo arranque."
fi
