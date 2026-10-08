#!/usr/bin/env bash
# ============================================================================
# Instala la skill global deploy-notify-slack en ~/.claude.
# Manda avisos de deploy por Slack y SIEMPRE pide/confirma el destinatario
# antes de enviar. Usa el MCP de Slack (slack_search_users + slack_send_message).
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

log "Creando skill global deploy-notify-slack…"
SKILL_DIR="$HOME/.claude/skills/deploy-notify-slack"
mkdir -p "$SKILL_DIR/assets"

cat > "$SKILL_DIR/SKILL.md" <<'SKILL_EOF'
---
name: deploy-notify-slack
description: "Trigger: avisar deploy, notificar deploy, avisar que se desplegó, mensaje de deploy a Slack, notify deploy on Slack. Send a deploy/change notice to a Slack recipient, always asking who first."
license: Apache-2.0
metadata:
  author: "Brandonhsz"
  version: "1.0"
---

## Activation Contract

Use when the user wants to tell a teammate on Slack that a change, ticket, or deploy
has shipped (e.g. "avísale a X que se desplegó", "notifica el deploy"). Requires the
Slack MCP (`mcp__slack__slack_search_users`, `mcp__slack__slack_send_message`).

## Hard Rules

- ALWAYS ask who the message goes to before sending — never infer or default the
  recipient, even when a name is given. This rule is the point of the skill.
- Resolve every recipient with `slack_search_users`; if the search returns zero or
  more than one match, ask the user to confirm before sending. Confirm with name +
  email when any ambiguity exists.
- Ask for the recipient one at a time, then STOP and wait for the answer.
- Never send without an explicitly confirmed recipient.
- Send the message in the conversation's language (team default: neutral Spanish).
- After sending, return the Slack message permalink.

## Execution Steps

1. Confirm the change being announced (what shipped). For a copy/text change,
   include both the old and new text so there is no ambiguity.
2. Ask who to notify. STOP and wait.
3. Run `slack_search_users` on the given name. On 0 or >1 matches, ask again.
4. Build the message from `assets/message-template.md`.
5. Send with `slack_send_message` using the recipient `user_id` as `channel_id`.
6. Report the permalink and the exact text sent.

## Output Contract

Return: the recipient (name + email), the exact message text, and the Slack permalink.

## References

- `assets/message-template.md` — deploy-notice message shape (old → new, deployed, ~5 min).
SKILL_EOF

cat > "$SKILL_DIR/assets/message-template.md" <<'TMPL_EOF'
# Deploy-notice message template

Neutral Spanish, warm but brief. Fill the placeholders and drop the lines that
do not apply.

## Copy / text change

> Hola {NOMBRE}, el cambio de copy en {UBICACIÓN} (de "{TEXTO_VIEJO}" a
> "{TEXTO_NUEVO}") ya quedó desplegado. Dale unos 5 minutos y ya lo deberías
> ver reflejado.

## Generic change / ticket

> Hola {NOMBRE}, el cambio de {QUÉ_CAMBIÓ} ya quedó desplegado. Dale unos 5
> minutos y ya lo deberías ver reflejado.

## Rules

- For a copy change, ALWAYS include both the old and the new text.
- Keep it to one or two sentences.
- Default wait hint is ~5 minutes; adjust only if the user gives another window.
- Do not invent ticket IDs, PR numbers, or URLs — include them only if provided.
TMPL_EOF

log "Skill deploy-notify-slack instalada en $SKILL_DIR"
