#!/usr/bin/env bash
# ============================================================================
# Conductor · Cloud computer · Install script (build-time)
# ----------------------------------------------------------------------------
# Reconstruye TODO el tooling de grabación/publicación de videos en una imagen
# LIMPIA (no depende del snapshot):
#   - ~/playwright-video-server/{package.json,publish-video.js,record-demo.js}
#   - deps de Node (playwright) + browser Chromium (libs del SO vía dnf)
#   - ffmpeg estático con libx264 (H.264) desde johnvansickle.com
#   - VIDEOS_DIR + env vars en ~/.bash_profile
#   - Generación de ~/CLAUDE.md con instrucciones de evidencias pre/post
# Idempotente. VIDEO_API_TOKEN lo inyecta Conductor como secret en runtime.
# ============================================================================
set -euo pipefail

APP_DIR="$HOME/playwright-video-server"
VIDEOS_DIR="$HOME/playwright-videos"
FFMPEG_BIN="$APP_DIR/ffmpeg"
FFMPEG_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
log(){ printf '==> %s\n' "$*"; }

mkdir -p "$APP_DIR" "$VIDEOS_DIR"

log "Escribiendo package.json…"
git config --global user.email brandonhszzz@gmail.com
git config --global user.name brandonhsz
cat > "$APP_DIR/package.json" <<'PKG_EOF'
{
  "name": "playwright-video-server",
  "version": "2.0.0",
  "private": true,
  "description": "Record an app with Playwright and publish an MP4 (H.264) to R2, returning a permanent publicUrl.",
  "type": "module",
  "bin": { "publish-video": "./publish-video.js" },
  "scripts": {
    "publish": "node publish-video.js",
    "demo": "node record-demo.js"
  },
  "devDependencies": { "playwright": "^1.62.1" }
}
PKG_EOF

log "Escribiendo publish-video.js…"
cat > "$APP_DIR/publish-video.js" <<'PUBLISH_JS_EOF'
#!/usr/bin/env node
// Record an app with Playwright, convert to MP4 (H.264), and publish it to R2
// via the videos API — printing a permanent `publicUrl` at the end.
//
// Usage:
//    node publish-video.js [URL] [name]
//    # e.g. node publish-video.js http://localhost:3005/ avena-panel-demo
//
// Env vars:
//    VIDEO_API_TOKEN  (required)  Bearer token for the videos API
//    VIDEO_API_BASE   default https://videos.brandonhsz.com
//    APP_URL          default http://localhost:3005/   (also arg 1)
//    VIDEOS_DIR       default ~/playwright-videos       (work dir for recordings)
//    FFMPEG           auto         Path to an ffmpeg with libx264 (H.264)

import { chromium } from "playwright";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const API_BASE = (process.env.VIDEO_API_BASE || "https://videos.brandonhsz.com").replace(/\/$/, "");
const TOKEN = process.env.VIDEO_API_TOKEN;
const VIDEOS_DIR = process.env.VIDEOS_DIR || path.join(os.homedir(), "playwright-videos");
const url = process.argv[2] || process.env.APP_URL || "http://localhost:3005/";
const rawName = process.argv[3] || "app-video";

if (!TOKEN) {
  console.error("[publish-video] ERROR: VIDEO_API_TOKEN is required (export it, ideally in ~/.bash_profile).");
  process.exit(1);
}

// Sanitize the requested name into a safe file stem.
const stem = rawName.replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "app-video";

function resolveFfmpeg() {
  const candidates = [
    process.env.FFMPEG,
    path.join(__dirname, "ffmpeg"),
    "/tmp/ffmpeg-static",
  ].filter(Boolean);
  for (const c of candidates) {
    try {
      fs.accessSync(c, fs.constants.X_OK);
      return c;
    } catch {
      /* keep looking */
    }
  }
  return "ffmpeg"; // fall back to PATH
}

const FFMPEG = resolveFfmpeg();

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ["ignore", "inherit", "inherit"] });
    p.on("error", reject);
    p.on("close", (code) =>
      code === 0 ? resolve() : reject(new Error(`${cmd} exited with code ${code}`))
    );
  });
}

async function record() {
  fs.mkdirSync(VIDEOS_DIR, { recursive: true });
  console.log(`[publish-video] recording ${url}`);
  const browser = await chromium.launch();
  const context = await browser.newContext({
    recordVideo: { dir: VIDEOS_DIR, size: { width: 1280, height: 720 } },
    viewport: { width: 1280, height: 720 },
  });
  const page = await context.newPage();
  try {
    await page.goto(url, { waitUntil: "load", timeout: 60000 });
  } catch (e) {
    console.warn(`[publish-video] WARN: navigation issue (${e.message}) — recording what rendered.`);
  }
  await page.waitForTimeout(1500);
  // A little interaction so the clip isn't static.
  await page.mouse.move(200, 200);
  await page.mouse.move(900, 500, { steps: 20 });
  await page.waitForTimeout(800);
  await page.mouse.wheel(0, 600);
  await page.waitForTimeout(800);
  await page.mouse.wheel(0, -600);
  await page.waitForTimeout(800);

  const video = page.video();
  // Video is flushed to disk on context close.
  await context.close();
  await browser.close();
  const webmPath = await video.path();
  console.log(`[publish-video] recorded ${webmPath}`);
  return webmPath;
}

async function toMp4(webmPath) {
  const mp4Path = path.join(VIDEOS_DIR, `${stem}.mp4`);
  console.log(`[publish-video] converting to MP4 (H.264) with ${FFMPEG}`);
  await run(FFMPEG, [
    "-y",
    "-i", webmPath,
    "-c:v", "libx264",
    "-pix_fmt", "yuv420p",
    "-preset", "veryfast",
    "-crf", "23",
    "-movflags", "+faststart",
    "-an",
    mp4Path,
  ]);
  const size = fs.statSync(mp4Path).size;
  console.log(`[publish-video] wrote ${mp4Path} (${(size / 1e6).toFixed(2)} MB)`);
  return mp4Path;
}

async function publish(mp4Path) {
  const filename = path.basename(mp4Path);

  // 1) ask for a presigned upload URL
  const res = await fetch(`${API_BASE}/api/videos/upload-url`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${TOKEN}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ filename, contentType: "video/mp4" }),
  });
  if (!res.ok) {
    throw new Error(`upload-url failed: ${res.status} ${res.statusText} — ${await res.text()}`);
  }
  const { uploadUrl, publicUrl, key } = await res.json();
  if (!uploadUrl || !publicUrl) {
    throw new Error(`upload-url response missing fields: ${JSON.stringify({ uploadUrl, publicUrl })}`);
  }

  // 2) PUT the file to R2
  const body = fs.readFileSync(mp4Path);
  const put = await fetch(uploadUrl, {
    method: "PUT",
    headers: { "content-type": "video/mp4" },
    body,
  });
  if (!put.ok) {
    throw new Error(`R2 upload failed: ${put.status} ${put.statusText} — ${await put.text()}`);
  }

  // 3) best-effort: tell the API the upload finished so it can send a push
  await notify(key);

  return publicUrl;
}

async function notify(key) {
  try {
    const res = await fetch(`${API_BASE}/api/videos/uploaded`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ key }),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) {
      console.warn(`[publish-video] notify skipped (${res.status})`);
    }
  } catch (e) {
    console.warn(`[publish-video] notify skipped: ${e.message || e}`);
  }
}

(async () => {
  const webmPath = await record();
  const mp4Path = await toMp4(webmPath);
  const publicUrl = await publish(mp4Path);
  // Final, machine-parseable line.
  console.log(`publicUrl: ${publicUrl}`);
})().catch((err) => {
  console.error(`[publish-video] FAILED: ${err.stack || err.message}`);
  process.exit(1);
});
PUBLISH_JS_EOF
chmod +x "$APP_DIR/publish-video.js"

log "Escribiendo record-demo.js…"
cat > "$APP_DIR/record-demo.js" <<'RECORD_JS_EOF'
#!/usr/bin/env node
import { chromium } from "playwright";
import path from "node:path";
import os from "node:os";

const VIDEOS_DIR =
  process.env.VIDEOS_DIR || path.join(os.homedir(), "playwright-videos");
const url = process.argv[2] || "https://example.com";

const browser = await chromium.launch();
const context = await browser.newContext({
  recordVideo: { dir: VIDEOS_DIR, size: { width: 1280, height: 720 } },
});
const page = await context.newPage();
await page.goto(url, { waitUntil: "load" });
await page.waitForTimeout(1500);
await page.mouse.move(200, 200);
await page.mouse.move(900, 500, { steps: 20 });
await page.waitForTimeout(1000);

await context.close();
await browser.close();

console.log(`[record-demo] wrote a video into ${VIDEOS_DIR}`);
RECORD_JS_EOF
chmod +x "$APP_DIR/record-demo.js"

log "Instalando deps de Node (playwright)…"
( cd "$APP_DIR" && npm install )

log "Instalando libs del SO para Chromium + xz (dnf)…"
sudo dnf install -y \
  nss nspr atk at-spi2-atk at-spi2-core cups-libs libdrm \
  libXcomposite libXdamage libXrandr libXext libXfixes libX11 libxcb \
  libxkbcommon mesa-libgbm pango cairo alsa-lib libXScrnSaver gtk3 libXtst xz \
  || log "WARN: dnf no pudo instalar algunas libs; sigo."

log "Descargando browser Chromium de Playwright…"
( cd "$APP_DIR" && npx playwright install chromium )

if [ -x "$FFMPEG_BIN" ] && "$FFMPEG_BIN" -version 2>/dev/null | grep -qi 'enable-libx264'; then
  log "ffmpeg con libx264 ya presente; se conserva."
else
  log "Descargando ffmpeg estático (libx264) desde johnvansickle.com…"
  TMP="$(mktemp -d)"
  curl -fSL "$FFMPEG_URL" -o "$TMP/ffmpeg.tar.xz"
  tar -xf "$TMP/ffmpeg.tar.xz" -C "$TMP"
  SRC="$(find "$TMP" -maxdepth 2 -type f -name ffmpeg | head -1)"
  install -m 0755 "$SRC" "$FFMPEG_BIN"
  rm -rf "$TMP"
fi
"$FFMPEG_BIN" -version 2>/dev/null | head -1 || log "WARN: ffmpeg no responde."

log "Persistiendo env vars en ~/.bash_profile…"
PROFILE="$HOME/.bash_profile"; touch "$PROFILE"
grep -q '^export VIDEOS_DIR='        "$PROFILE" || echo 'export VIDEOS_DIR="$HOME/playwright-videos"'            >> "$PROFILE"
grep -q '^export PW_VIDEO_APP_DIR=' "$PROFILE" || echo 'export PW_VIDEO_APP_DIR="$HOME/playwright-video-server"' >> "$PROFILE"

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

log "Creando skill global validar-links-referido-mercadolibre…"
SKILL_DIR="$HOME/.claude/skills/validar-links-referido-mercadolibre"
mkdir -p "$SKILL_DIR"
cat > "$SKILL_DIR/SKILL.md" <<'SKILL_EOF'
---
name: validar-links-referido-mercadolibre
description: "Revisar links de referido meli.la ya publicados: confirmar que sigan apuntando a un producto, detectar los rotos y comparar el precio actual de ML contra el guardado en la base."
---

# Validar links de referido de MercadoLibre

Para auditar links `meli.la` que ya están en producción. Responde tres preguntas por
producto: ¿el link sigue vivo?, ¿sigue llevando al producto correcto?, ¿el precio
guardado sigue siendo el de ML?

Entrada típica: un export con `_id`, `name`, `brand`, `price` y `productURL` apuntando
a `meli.la/...`.

## Cómo se ve un link vivo

Un `meli.la` de este programa **no abre la página del producto**: resuelve al perfil
social del afiliado, `mercadolibre.com.mx/social/<tag>`, con el producto enlazado
destacado hasta arriba y el resto de las recomendaciones abajo.

Eso da dos señales limpias:

| Resultado | Significa |
|---|---|
| `/social/<tag>` **con** `.rl-card-featured` | link vivo; la tarjeta destacada es el producto |
| `/social/<tag>/lists` **sin** `.rl-card-featured` | **link roto**: el producto ya no está en la lista de recomendaciones |

El segundo caso es el hallazgo que justifica la auditoría: el link responde 200 y no
parece fallado, pero el cliente aterriza en una lista genérica en lugar del producto
que pidió. No se detecta con un simple check de status HTTP.

## Extractor

```js
await new Promise(r=>setTimeout(r,4500));
const f=document.querySelector('.rl-card-featured');
if(!f){ JSON.stringify({ok:false,path:location.pathname,
  motivo:location.pathname.endsWith('/lists')
    ?'roto: el producto ya no esta en la lista de recomendaciones'
    :'sin tarjeta destacada'}) }
else {
  const t=f.querySelector('.poly-component__title');
  const fr=f.querySelector('.andes-money-amount__fraction');
  const ce=f.querySelector('.andes-money-amount__cents');
  const se=f.querySelector('.poly-component__seller');
  const a=f.querySelector('a[href*="MLM"]');
  JSON.stringify({ok:true,
    titulo:t&&t.textContent.trim(),
    precio:fr&&(fr.textContent.replace(/,/g,'')+(ce?'.'+ce.textContent.trim():'')),
    vendedor:se&&se.textContent.trim().replace(/^Por /,''),
    mlid:a&&(a.href.match(/MLM-?\d+/)||[null])[0]});
}
```

**La tarjeta destacada trae el `MLM` id.** Vale la pena guardarlo: si la base solo
almacena el `meli.la` (un link corto que no revela a qué apunta), esta auditoría es
la forma de reconstruir el mapeo producto → listing.

Usar espera activa, no `setTimeout` fijo, cuando se pueda. Batches de 3-4 links por
llamada: cada uno necesita ~4.5s porque hay dos redirecciones (`meli.la` → `/social/`).

## Qué comparar

1. **Vivo o roto** — la señal de arriba.
2. **Precio** — `precio` de ML contra `price` del registro. Marcar diferencias mayores
   a ~1%; las de centavos son ruido de redondeo (449 vs 449.09 no es un cambio real).
3. **Identidad** — comparar el título del listing contra `name` + `brand` del registro.
   Esto es lo que atrapa un mapeo mal hecho: un link vivo, con precio plausible, pero
   apuntando a otro producto. Revisar a ojo los que no compartan palabras clave.
4. **Vendedor** — guardarlo. Si cambió quien gana el buy box, suele explicar un salto
   de precio, y también si un link empieza o deja de generar comisión.
No asumir que precio igual = todo bien. Un producto puede seguir vivo y al mismo precio
pero haber cambiado de presentación.

## Trampas

- **`/gz/account-verification`**: ML pide verificación de cuenta y *toda* URL redirige
  ahí. Lo tiene que pasar el usuario; el agente no resuelve retos de verificación.
  Si aparece a media corrida, guardar el avance y pedirle que la pase.
- **reCAPTCHA**: igual.
- Si varios links seguidos dan el mismo resultado sospechoso, verificar primero que la
  sesión no esté bloqueada antes de marcar 50 productos como rotos.
- La validación depende de estar logueado en la cuenta de afiliado dueña de esos links.
## Entrega

Un CSV, con `_id` como primera columna:

```
_id, marca, nombre, productURL, estatus, precio_guardado, precio_ML, diff_pct,
vendedor_ML, mlid_detectado, titulo_en_ML, nota
```

`estatus`: `ok` / `precio_cambio` / `roto` / `revisar_identidad`

Al reportar, abrir con lo accionable, no con el conteo: cuántos rotos, cuántos con
precio desactualizado y de cuánto es la diferencia agregada. Los que están bien no
necesitan explicación.

Si el volumen es alto (200+), entregar avances parciales y guardar resultados a disco
conforme salen, para no perder el trabajo si la sesión se corta a medio camino.

## Cada cuándo

Tiene sentido correrla periódicamente: los precios de ML se mueven solos, el vendedor
del buy box cambia, y un producto puede salirse de la lista de recomendaciones sin
aviso. Ofrecer dejarla como tarea programada si el usuario la va a repetir.
SKILL_EOF

log "Configurando rtk (al final del build)…"
mkdir -p "$HOME/.claude"   # rtk init -g writes ~/.claude/RTK.md; must exist on a clean build
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc  # or ~/.zshrc
rtk telemetry disable
rtk init -g --auto-patch --trust-filters
