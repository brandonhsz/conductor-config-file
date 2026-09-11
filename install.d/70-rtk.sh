#!/usr/bin/env bash
# ============================================================================
# Instala y configura rtk (al final del build).
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

log "Configurando rtk (al final del build)…"
mkdir -p "$HOME/.claude"   # rtk init -g writes ~/.claude/RTK.md; must exist on a clean build
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc  # or ~/.zshrc
rtk telemetry disable
rtk init -g --auto-patch --trust-filters
