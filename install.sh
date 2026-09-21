#!/usr/bin/env bash
# ============================================================================
# Conductor · Cloud computer · Install script (build-time) · ORQUESTADOR
# ----------------------------------------------------------------------------
# Reconstruye TODO el tooling de grabación/publicación de videos en una imagen
# LIMPIA (no depende del snapshot). La lógica está modularizada en install.d/;
# este script solo carga el común y ejecuta cada módulo en orden.
#
#   install.d/00-common.sh      · vars compartidas + log() (se sourcea)
#   install.d/10-video-server.sh · package.json + publish/record .js + npm i
#   install.d/20-chromium.sh     · libs del SO (dnf) + browser de Playwright
#   install.d/30-ffmpeg.sh       · ffmpeg estático con libx264 (H.264)
#   install.d/40-env.sh          · env vars en ~/.bash_profile
#   install.d/50-claude-md.sh    · ~/CLAUDE.md (evidencias en video)
#   install.d/60-skill.sh        · skill validar-links-referido-mercadolibre
#   install.d/70-rtk.sh          · instala y configura rtk
#   install.d/80-node-toolchain.sh · corepack + yarn 3.6.4 (+ watchman opcional)
#   install.d/85-obsidian-headless.sh · cliente 'ob' + login/sync del second brain
#   install.d/90-android-sdk.sh  · JDK 17 + Android SDK 36 + NDK (build avena-mobile)
#   install.d/95-gentle-ai.sh    · gentle-ai (claude-code, full-gentleman, persona, SDD multi)
#   install.d/96-second-brain-feeder.sh · feeder Engram → vault Obsidian (hook SessionEnd; tras gentle-ai)
#
# Idempotente. VIDEO_API_TOKEN lo inyecta Conductor como secret en runtime.
# Cada módulo es ejecutable por sí solo (sourcea 00-common.sh si hace falta):
#   bash install.d/30-ffmpeg.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/install.d"

# Config y helpers compartidos (define log, APP_DIR, VIDEOS_DIR, FFMPEG_*).
source "$MODULES_DIR/00-common.sh"

MODULES=(
  10-video-server.sh
  20-chromium.sh
  30-ffmpeg.sh
  40-env.sh
  50-claude-md.sh
  60-skill.sh
  70-rtk.sh
  80-node-toolchain.sh
  85-obsidian-headless.sh
  90-android-sdk.sh
  95-gentle-ai.sh
  96-second-brain-feeder.sh
)

for m in "${MODULES[@]}"; do
  log "── módulo: $m ──"
  source "$MODULES_DIR/$m"
done

log "Instalación completa."
