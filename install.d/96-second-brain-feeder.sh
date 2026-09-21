#!/usr/bin/env bash
# ============================================================================
# Second Brain Feeder — exporta observaciones de Engram a notas del vault de
# Obsidian al cerrar cada sesión de Claude Code.
#   · Copia assets/second-brain-feed.py a $HOME/.local/bin/.
#   · Registra un hook de SessionEnd en ~/.claude/settings.json (idempotente,
#     mergeado con python3 — nunca con sed sobre JSON).
#
# Best-effort: si algo falla, se loguea un WARN y se sigue; nunca se debe
# tumbar el build por esto.
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
FEEDER_SRC="$REPO_ROOT/assets/second-brain-feed.py"
FEEDER_DEST="$HOME/.local/bin/second-brain-feed.py"
FEEDER_STATE_DIR="$HOME/.local/state/second-brain-feeder"

log "Instalando second-brain-feed.py en ${FEEDER_DEST}…"
if [ -f "$FEEDER_SRC" ]; then
  mkdir -p "$(dirname "$FEEDER_DEST")"
  cp "$FEEDER_SRC" "$FEEDER_DEST"
  chmod 644 "$FEEDER_DEST"
  log "Feeder copiado."
else
  log "WARN: no encontré ${FEEDER_SRC}; omito instalación del feeder."
fi

mkdir -p "$FEEDER_STATE_DIR"

log "Registrando hook de SessionEnd en ~/.claude/settings.json…"
python3 - <<'PYEOF' || log "WARN: no pude registrar el hook de SessionEnd."
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")
marker = "second-brain-feed"
cmd = (
    'python3 "$HOME/.local/bin/second-brain-feed.py" '
    '>> "$HOME/.local/state/second-brain-feeder/feed.log" 2>&1 || true'
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
session_end = hooks.setdefault("SessionEnd", [])
if not isinstance(session_end, list):
    print("WARN: hooks.SessionEnd no es una lista; omito el merge para no pisarlo.")
    raise SystemExit(1)

already_present = any(
    marker in hook.get("command", "")
    for group in session_end
    if isinstance(group, dict)
    for hook in group.get("hooks", [])
    if isinstance(hook, dict)
)

if already_present:
    print("Hook de SessionEnd ya presente; no se duplica.")
else:
    session_end.append({"hooks": [{"type": "command", "command": cmd}]})
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print("Hook de SessionEnd agregado.")
PYEOF

log "Second Brain Feeder listo."
