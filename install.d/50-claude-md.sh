#!/usr/bin/env bash
# ============================================================================
# Genera ~/CLAUDE.md con las instrucciones de evidencias en video (pre/post).
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

log "Creando ~/CLAUDE.md con instrucciones de evidencias en video…"
cat > "$HOME/CLAUDE.md" <<'CLAUDE_EOF'
# Instrucciones de Trabajo y Evidencia en Video

Para cada tarea asignada, es **obligatorio** documentar el cambio visual mediante dos videos utilizando la herramienta de Playwright instalada en `~/playwright-video-server/publish-video.js`.

### 🚨 REGLAS ESTRICTAS DE AUTONOMÍA 🚨
1. **NO me pidas permiso:** Realiza todo este proceso de grabación de forma automática sin preguntarme si debes o no grabar el video. Es parte implícita de tu flujo de trabajo.
2. **SIEMPRE levanta la aplicación:** Antes de ejecutar el script de grabación, debes asegurarte de que la aplicación esté corriendo (por ejemplo, en un proceso en segundo plano).
3. **Inspecciona si no sabes cómo:** Si no estás seguro de cómo arrancar el proyecto en el que estamos, es TU responsabilidad revisar los archivos del entorno (`package.json`, `README.md`, `Makefile`, `docker-compose.yml`, etc.) para descubrir el comando correcto y levantar el entorno antes de grabar. Asegúrate de esperar a que el puerto responda antes de iniciar la grabación.
4. **Manejo de Login:** Si la página que debes grabar requiere estar autenticado, es TU responsabilidad inyectar el estado de autenticación o hacer que el script navegue y realice el login primero. Utiliza siempre las credenciales de las variables de entorno:
   - **Usuario:** `USERNAME_TEST=coach@avena.coach`
   - **Contraseña:** `DEBUG_PASSWORD=asbestos-lloyd-displays-liters`
   *(Siéntete libre de modificar temporalmente `publish-video.js` u orquestar un script de Playwright personalizado para cumplir con el login antes de generar el video final si la situación lo amerita).*
5. **NUNCA INVENTES UI (Cero Mocks):** La grabación **SIEMPRE** debe ser sobre la aplicación y el entorno real. Tienes **estrictamente prohibido** inventar código HTML estático, simular interfaces, o crear UIs falsas solo para grabar el video. El video debe mostrar el proyecto real funcionando.

---

## Flujo de Grabación Obligatorio

### 1. Estado Previo (Antes de los cambios)
- Levanta la aplicación.
- Toma un video del estado actual del sistema ANTES de modificar el código:
```bash
node ~/playwright-video-server/publish-video.js [URL_APP] [nombre_tarea]-antes
# Ejemplo:
# node ~/playwright-video-server/publish-video.js http://localhost:3005/ fix-login-antes
CLAUDE_EOF
