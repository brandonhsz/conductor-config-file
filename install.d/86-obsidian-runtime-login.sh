#!/usr/bin/env bash
# ============================================================================
# Obsidian Runtime Login — cablea el login/sync del vault para que ocurra en
# RUNTIME, en cada workspace.
#   · Copia assets/obsidian-ensure-login.sh a $HOME/.local/bin/.
#   · Registra un hook de SessionStart en ~/.claude/settings.json (idempotente,
#     mergeado con python3 — nunca con sed sobre JSON) que corre el ensure-login
#     en background para no bloquear el arranque de la sesion.
#
# Por que: 85-obsidian-headless.sh instala el cliente 'ob' en build-time, pero
# los secrets OBSIDIAN_* recien existen en runtime, asi que el login no puede
# ocurrir durante el build. Este hook lo resuelve en cada arranque de sesion.
#
# Best-effort: si algo falla, se loguea un WARN y se sigue; nunca se debe
# tumbar el build por esto.
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
ENSURE_SRC="$REPO_ROOT/assets/obsidian-ensure-login.sh"
ENSURE_DEST="$HOME/.local/bin/obsidian-ensure-login.sh"
ENSURE_STATE_DIR="$HOME/.local/state/obsidian-ensure"

log "Instalando obsidian-ensure-login.sh en ${ENSURE_DEST}…"
if [ -f "$ENSURE_SRC" ]; then
  mkdir -p "$(dirname "$ENSURE_DEST")"
  cp "$ENSURE_SRC" "$ENSURE_DEST"
  chmod 755 "$ENSURE_DEST"
  log "ensure-login copiado."
else
  log "WARN: no encontré ${ENSURE_SRC}; omito instalación del ensure-login."
  return 0 2>/dev/null || exit 0
fi

mkdir -p "$ENSURE_STATE_DIR"

log "Registrando hook de SessionStart en ~/.claude/settings.json…"
python3 - <<'PYEOF' || log "WARN: no pude registrar el hook de SessionStart."
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")
marker = "obsidian-ensure-login"
cmd = (
    'nohup bash "$HOME/.local/bin/obsidian-ensure-login.sh" '
    '>> "$HOME/.local/state/obsidian-ensure/ensure.log" 2>&1 & disown 2>/dev/null || true'
)

settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, "r") as f:
            raw = f.read().strip()
        settings = json.loads(raw) if raw else {}
    except Exception:
        print("WARN: settings.json existente es inválido; omito el merge para no pisarlo.")
        raise SystemExit(1)

hooks = settings.setdefault("hooks", {})
session_start = hooks.setdefault("SessionStart", [])
if not isinstance(session_start, list):
    print("WARN: hooks.SessionStart no es una lista; omito el merge para no pisarlo.")
    raise SystemExit(1)

already_present = any(
    marker in hook.get("command", "")
    for group in session_start
    if isinstance(group, dict)
    for hook in group.get("hooks", [])
    if isinstance(hook, dict)
)

if already_present:
    print("Hook de SessionStart ya presente; no se duplica.")
else:
    session_start.append({"hooks": [{"type": "command", "command": cmd}]})
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print("Hook de SessionStart agregado.")
PYEOF

log "Obsidian Runtime Login listo."
