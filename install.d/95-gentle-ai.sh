#!/usr/bin/env bash
# ============================================================================
# Gentle-AI: entorno determinista para el agente (Claude Code) en la imagen.
#   https://github.com/Gentleman-Programming/gentle-ai
#
# Instala el binario `gentle-ai` (método binario, sin Go) y aplica la config
# elegida de forma NO-INTERACTIVA para que quede horneada en la imagen:
#   · agent  : claude-code   (el agente que corre en Conductor)
#   · preset : full-gentleman (Engram, SDD, skills, context7, permissions, tema)
#   · persona: gentleman      (mentor docente; se inyecta en ~/.claude/CLAUDE.md)
#   · sdd    : multi          (orquestador SDD multi-fase)
#   · scope  : global         (~/.claude → aplica a todos los workspaces)
#
# Deja binarios en /usr/local/bin (gentle-ai, gga, engram) y registra los MCP
# `engram` + `context7` en ~/.claude.json. `engram` viene como binario estático
# (NO requiere Go). gentle-ai hace snapshot de cada config antes de escribir
# (~/.gentle-ai/backups → `gentle-ai restore`).
#
# ORDEN: corre DESPUÉS de 70-rtk.sh a propósito. rtk deja el include `@RTK.md`
# en ~/.claude/CLAUDE.md; gentle-ai lo detecta y agrega la persona a
# continuación, preservándolo. No toca ~/CLAUDE.md (evidencias en video).
# Idempotente: re-ejecutar re-descarga el binario y re-aplica la config.
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

GENTLE_AI_AGENT="${GENTLE_AI_AGENT:-claude-code}"
GENTLE_AI_PRESET="${GENTLE_AI_PRESET:-full-gentleman}"
GENTLE_AI_PERSONA="${GENTLE_AI_PERSONA:-gentleman}"
GENTLE_AI_SDD_MODE="${GENTLE_AI_SDD_MODE:-multi}"
GENTLE_AI_SCOPE="${GENTLE_AI_SCOPE:-global}"

log "Instalando binario gentle-ai (método binario, canal stable)…"
mkdir -p "$HOME/.claude"   # scope global escribe aquí; debe existir en build limpio
curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh \
  | bash -s -- --method binary

# El instalador deja gentle-ai en /usr/local/bin (o ~/.local/bin como fallback).
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

log "gentle-ai: $(gentle-ai version 2>/dev/null || echo 'NO ENCONTRADO')"

log "Aplicando config no-interactiva (agent=$GENTLE_AI_AGENT preset=$GENTLE_AI_PRESET persona=$GENTLE_AI_PERSONA sdd=$GENTLE_AI_SDD_MODE scope=$GENTLE_AI_SCOPE)…"
gentle-ai install \
  --agent   "$GENTLE_AI_AGENT" \
  --preset  "$GENTLE_AI_PRESET" \
  --persona "$GENTLE_AI_PERSONA" \
  --sdd-mode "$GENTLE_AI_SDD_MODE" \
  --scope   "$GENTLE_AI_SCOPE"

# Telemetría anónima opt-out (coherente con rtk telemetry disable).
gentle-ai telemetry disable >/dev/null 2>&1 || log "WARN: no pude desactivar telemetría de gentle-ai."

# ── Resolución de conflictos persona gentleman ↔ entorno ──────────────────────
# La persona choca en 2 puntos con este entorno. Decisión del usuario:
#   · Atribución en commits → gana la persona (conventional commits, SIN
#     Co-Authored-By / atribución de IA); anula el requerimiento del entorno.
#   · Herramientas de shell → gana el entorno (usar cat/grep/find/sed/ls; en la
#     imagen NO están bat/rg/fd/sd/eza).
# Insertamos un bloque FUERA de los markers `gentle-ai:*` (sobrevive a
# `gentle-ai sync`) justo tras @RTK.md. Idempotente vía marcador env-overrides:start.
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
if [ -f "$CLAUDE_MD" ] && ! grep -q 'env-overrides:start' "$CLAUDE_MD"; then
  log "Insertando resolución de conflictos persona↔entorno en CLAUDE.md…"
  OVERRIDE_TMP="$(mktemp)"
  cat > "$OVERRIDE_TMP" <<'EOF'

<!-- env-overrides:start -->
## Resolución de conflictos: persona gentleman ↔ entorno

Cuando la persona `gentleman` (bloque `gentle-ai:persona` de abajo) choca con las
reglas del entorno del workspace, resolvé así:

- **Atribución en commits → gana la persona gentleman**: NO agregar
  `Co-Authored-By` ni atribución de IA; usar conventional commits únicamente.
  Esto anula el requerimiento de atribución del entorno.
- **Herramientas de shell → gana el entorno**: usar las herramientas estándar
  (`cat`, `grep`, `find`, `sed`, `ls`, etc.). En esta imagen NO están instaladas
  `bat`/`rg`/`fd`/`sd`/`eza`, así que NO aplica la regla de la persona que las exige,
  ni instalar nada vía brew para reemplazarlas.
<!-- env-overrides:end -->
EOF
  if grep -q '^@RTK\.md$' "$CLAUDE_MD"; then
    sed -i "/^@RTK\.md$/r $OVERRIDE_TMP" "$CLAUDE_MD"   # inserta tras la línea @RTK.md
  else
    cat "$OVERRIDE_TMP" "$CLAUDE_MD" > "$CLAUDE_MD.new" && mv "$CLAUDE_MD.new" "$CLAUDE_MD"
  fi
  rm -f "$OVERRIDE_TMP"
else
  log "Overrides del entorno ya presentes (o CLAUDE.md ausente); no se modifica."
fi

log "Verificando (gentle-ai doctor)…"
gentle-ai doctor 2>&1 | tail -3 || log "WARN: doctor reportó problemas; revisar arriba."

log "Gentle-AI listo."
