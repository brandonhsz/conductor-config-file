#!/usr/bin/env bash
# ============================================================================
# Toolchain de Android para compilar avena-mobile (React Native 0.85).
# Versiones tomadas de android/build.gradle y gradle-wrapper.properties del repo:
#   · JDK 17 (Amazon Corretto)              · Gradle 9.3.1 → lo baja el wrapper
#   · SDK Platform android-36               · build-tools 36.0.0
#   · NDK 27.1.12297006                     · Kotlin 2.1.20 (vía plugin gradle)
# iOS/CocoaPods NO aplica en Linux; se omite a propósito.
# Idempotente: si el SDK ya está, solo re-acepta licencias y actualiza env.
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/sdk}"
CMDLINE_TOOLS_ZIP="${CMDLINE_TOOLS_ZIP:-commandlinetools-linux-13114758_latest.zip}"
CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/${CMDLINE_TOOLS_ZIP}}"

# cmdline-tools NO va aquí: ya lo instalamos manualmente desde el zip en
# $ANDROID_HOME/cmdline-tools/latest. Pasarlo a sdkmanager crea un duplicado
# "latest-2" y ensucia el log con un warning.
SDK_PACKAGES=(
  "platform-tools"
  "platforms;android-36"
  "build-tools;36.0.0"
  "ndk;27.1.12297006"
)

# ── JDK 17 ─────────────────────────────────────────────────────────────────
log "Instalando JDK 17 (Amazon Corretto)…"
if command -v javac >/dev/null 2>&1 && javac -version 2>&1 | grep -q ' 17\.'; then
  log "JDK 17 ya presente; se conserva."
else
  sudo dnf install -y java-17-amazon-corretto-devel \
    || log "WARN: dnf no pudo instalar JDK 17; el build de Android fallará sin él."
fi
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac 2>/dev/null)")")" 2>/dev/null)"
log "JAVA_HOME=${JAVA_HOME:-<no resuelto>}"

# ── Android command-line tools ─────────────────────────────────────────────
mkdir -p "$ANDROID_HOME/cmdline-tools"
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
if [ -x "$SDKMANAGER" ]; then
  log "cmdline-tools ya presentes en $ANDROID_HOME."
else
  log "Descargando Android command-line tools…"
  TMP="$(mktemp -d)"
  curl -fSL "$CMDLINE_TOOLS_URL" -o "$TMP/cmdline-tools.zip"
  ( cd "$TMP" && unzip -q cmdline-tools.zip )   # crea $TMP/cmdline-tools/
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv "$TMP/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$TMP"
fi

# ── Paquetes del SDK + licencias ───────────────────────────────────────────
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME" JAVA_HOME
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

log "Aceptando licencias del SDK…"
yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true

log "Instalando paquetes del SDK: ${SDK_PACKAGES[*]}"
# Subshell con pipefail OFF: `yes` muere por SIGPIPE (141) cuando sdkmanager
# termina de leer, y con pipefail eso enmascararía el exit 0 real de sdkmanager.
( set +o pipefail; yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" "${SDK_PACKAGES[@]}" ) \
  || log "WARN: sdkmanager falló al instalar algún paquete."

log "Re-aceptando licencias tras la instalación…"
yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true

# ── Persistir env (idempotente) ────────────────────────────────────────────
log "Persistiendo env de Android/Java en ~/.bash_profile…"
PROFILE="$HOME/.bash_profile"; touch "$PROFILE"
grep -q '^export ANDROID_HOME='     "$PROFILE" || echo "export ANDROID_HOME=\"$ANDROID_HOME\""               >> "$PROFILE"
grep -q '^export ANDROID_SDK_ROOT=' "$PROFILE" || echo 'export ANDROID_SDK_ROOT="$ANDROID_HOME"'             >> "$PROFILE"
grep -q '^export JAVA_HOME='        "$PROFILE" || echo "export JAVA_HOME=\"$JAVA_HOME\""                      >> "$PROFILE"
grep -q 'cmdline-tools/latest/bin'  "$PROFILE" || echo 'export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"' >> "$PROFILE"

log "Toolchain de Android listo (SDK en $ANDROID_HOME)."
