#!/usr/bin/env bash
# ============================================================================
# Servidor de video con Playwright: escribe package.json, publish-video.js,
# record-demo.js e instala las deps de Node.
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

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
//    VIDEO_API_BASE   default: try https://videos.brandonhsz.com, then fall
//                     back to https://development-videos-viewer.vercel.app
//                     (set it to force a single base and skip the fallback)
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

// Publish targets, tried in order. An explicit VIDEO_API_BASE wins and skips
// the fallback; otherwise try the custom domain first, then the vercel.app URL.
const API_BASES = (
  process.env.VIDEO_API_BASE
    ? [process.env.VIDEO_API_BASE]
    : ["https://videos.brandonhsz.com", "https://development-videos-viewer.vercel.app"]
).map((b) => b.replace(/\/+$/, ""));
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

// Publish against one base: ask for a presigned URL, PUT the file, then notify.
async function publishTo(base, mp4Path, filename, body) {
  // 1) ask for a presigned upload URL
  const res = await fetch(`${base}/api/videos/upload-url`, {
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
  const put = await fetch(uploadUrl, {
    method: "PUT",
    headers: { "content-type": "video/mp4" },
    body,
  });
  if (!put.ok) {
    throw new Error(`R2 upload failed: ${put.status} ${put.statusText} — ${await put.text()}`);
  }

  // 3) best-effort: tell the API the upload finished so it can send a push
  await notify(base, key);

  return publicUrl;
}

// Try each base in order; return on the first that publishes successfully.
async function publish(mp4Path) {
  const filename = path.basename(mp4Path);
  const body = fs.readFileSync(mp4Path);
  let lastError;
  for (const base of API_BASES) {
    try {
      console.log(`[publish-video] publishing via ${base}`);
      return await publishTo(base, mp4Path, filename, body);
    } catch (e) {
      lastError = e;
      console.warn(`[publish-video] ${base} failed: ${e.message || e}`);
    }
  }
  throw lastError ?? new Error("no VIDEO_API_BASE succeeded");
}

async function notify(base, key) {
  try {
    const res = await fetch(`${base}/api/videos/uploaded`, {
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
