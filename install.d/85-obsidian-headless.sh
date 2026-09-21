#!/usr/bin/env bash
# ============================================================================
# Obsidian Headless — cliente oficial `ob` para alimentar el "second brain".
#   · Instala obsidian-headless global vía npm (idempotente).
#   · Si las credenciales están en env (secrets del computer de Conductor),
#     deja la cuenta logueada y el vault con sync configurado + un pull inicial,
#     de modo que el snapshot arranque listo para `ob sync`.
#
# Env vars (secrets de Conductor — NUNCA hardcodeadas aquí):
#   OBSIDIAN_EMAIL, OBSIDIAN_PASSWORD  → login de la cuenta
#   OBSIDIAN_ENCRYPTION_PASSWORD       → password de cifrado E2E del vault (Sync)
#   OBSIDIAN_VAULT                     → id o nombre del vault remoto
#   OBSIDIAN_VAULT_PATH (opcional)     → ruta local del vault (default ~/second-brain)
#
# Best-effort: igual que watchman en 80-node-toolchain.sh, este módulo NO tumba
# el build si algo opcional falla (login/sync dependen de red y credenciales).
# El login no interactivo requiere una cuenta SIN MFA (validado 2026-09-21).
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

OBSIDIAN_VAULT_PATH="${OBSIDIAN_VAULT_PATH:-$HOME/second-brain}"

log "Node: $(node -v 2>/dev/null || echo 'NO ENCONTRADO') (obsidian-headless requiere >=22)"

log "Instalando obsidian-headless (cliente oficial 'ob')…"
if npm install -g obsidian-headless >/dev/null 2>&1; then
  log "obsidian-headless instalado ($(ob --version 2>/dev/null || echo '?'))."
else
  log "WARN: no pude instalar obsidian-headless; se omite el resto del módulo."
  return 0 2>/dev/null || exit 0
fi

# --- Login + sync-setup solo si hay credenciales (el build es NO interactivo) ---
if [ -n "${OBSIDIAN_EMAIL:-}" ] && [ -n "${OBSIDIAN_PASSWORD:-}" ]; then
  log "Login en Obsidian como ${OBSIDIAN_EMAIL}…"
  if ob login --email "$OBSIDIAN_EMAIL" --password "$OBSIDIAN_PASSWORD" </dev/null >/dev/null 2>&1; then
    log "Login OK."
    if [ -n "${OBSIDIAN_VAULT:-}" ] && [ -n "${OBSIDIAN_ENCRYPTION_PASSWORD:-}" ]; then
      mkdir -p "$OBSIDIAN_VAULT_PATH"
      log "Configurando sync del vault '${OBSIDIAN_VAULT}' → ${OBSIDIAN_VAULT_PATH}…"
      if ob sync-setup \
            --vault "$OBSIDIAN_VAULT" \
            --path "$OBSIDIAN_VAULT_PATH" \
            --password "$OBSIDIAN_ENCRYPTION_PASSWORD" \
            --device-name "conductor-cloud" </dev/null >/dev/null 2>&1; then
        log "Sync configurado; pull inicial…"
        ob sync --path "$OBSIDIAN_VAULT_PATH" </dev/null >/dev/null 2>&1 \
          && log "Vault sincronizado en ${OBSIDIAN_VAULT_PATH}." \
          || log "WARN: pull inicial falló; se reintenta en runtime con 'ob sync'."
      else
        log "WARN: sync-setup falló (¿vault o encryption password?). Cliente instalado igual."
      fi
    else
      log "Sin OBSIDIAN_VAULT / OBSIDIAN_ENCRYPTION_PASSWORD: omito sync-setup."
    fi
  else
    log "WARN: login falló (¿MFA activo o credenciales?). Cliente instalado; login manual con 'ob login'."
  fi
else
  log "Sin OBSIDIAN_EMAIL/OBSIDIAN_PASSWORD en env: instalo el cliente y omito login (hacerlo con 'ob login')."
fi

log "Obsidian Headless listo."
