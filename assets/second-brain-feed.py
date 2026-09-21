#!/usr/bin/env python3
"""
second-brain-feed.py — "Second brain feeder" para Claude Code.

Se ejecuta como hook de SessionEnd: exporta las observaciones de Engram del
proyecto actual, renderiza las que son NUEVAS (id > marker) como una nota
Markdown dentro del vault de Obsidian, y dispara `ob sync`.

Diseño: robusto y best-effort. Cualquier fallo se reporta por stdout y el
proceso SIEMPRE termina con exit code 0 — nunca debe bloquear el cierre de
la sesión de Claude Code.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

PREFIX = "[second-brain-feed]"


def log(msg: str) -> None:
    print(f"{PREFIX} {msg}", flush=True)


def resolve_vault_path() -> Path | None:
    vault = os.environ.get("OBSIDIAN_VAULT_PATH") or str(Path.home() / "second-brain")
    vault_path = Path(vault)
    if not vault_path.exists():
        log(f"vault no encontrado en {vault_path}; nada que hacer.")
        return None
    return vault_path


def run_git(cwd: str, *args: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", cwd, *args],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return None
        out = result.stdout.strip()
        return out or None
    except Exception:
        return None


def resolve_project_name(cwd: str) -> str | None:
    remote_url = run_git(cwd, "remote", "get-url", "origin")
    if remote_url:
        name = os.path.basename(remote_url.rstrip("/"))
        if name.endswith(".git"):
            name = name[: -len(".git")]
        if name:
            return name

    toplevel = run_git(cwd, "rev-parse", "--show-toplevel")
    if toplevel:
        name = os.path.basename(toplevel.rstrip("/"))
        if name:
            return name

    return None


def state_dir() -> Path:
    d = Path.home() / ".local" / "state" / "second-brain-feeder"
    d.mkdir(parents=True, exist_ok=True)
    return d


def read_last_id(marker_path: Path) -> int:
    if not marker_path.exists():
        return 0
    try:
        content = marker_path.read_text().strip()
        return int(content) if content else 0
    except Exception:
        return 0


def write_last_id(marker_path: Path, last_id: int) -> None:
    marker_path.write_text(str(last_id))


def export_observations(project: str) -> dict:
    with tempfile.NamedTemporaryFile(
        prefix="engram-export-", suffix=".json", delete=False
    ) as tmp:
        tmp_path = tmp.name
    try:
        subprocess.run(
            ["engram", "export", "--project", project, tmp_path],
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        )
        with open(tmp_path, "r") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def _run_ob(args: list[str], stdin_text: str | None = None, timeout: int = 90):
    return subprocess.run(
        ["ob", *args],
        input=(stdin_text + "\n") if stdin_text is not None else None,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def ensure_ob_ready(vault_path: Path) -> bool:
    """Best-effort: garantiza que `ob` esté logueado y con sync configurado para
    vault_path usando las env vars de runtime (Conductor las inyecta en el
    workspace, NO en el build sandbox). Los secretos van por STDIN, nunca por
    argv. Idempotente: si el vault ya está configurado, no hace nada."""
    try:
        listed = _run_ob(["sync-list-local"], timeout=30)
        if listed.returncode == 0 and str(vault_path) in (listed.stdout or ""):
            return True
    except Exception:
        pass  # seguimos e intentamos configurar

    email = os.environ.get("OBSIDIAN_EMAIL")
    password = os.environ.get("OBSIDIAN_PASSWORD")
    if not email or not password:
        log("WARN: sin OBSIDIAN_EMAIL/OBSIDIAN_PASSWORD en runtime; no autoconfiguro 'ob' (la nota igual se escribe).")
        return False

    log("configurando 'ob' para este workspace (login + sync-setup)…")
    try:
        login = _run_ob(["login", "--email", email], stdin_text=password)
        if login.returncode != 0:
            log(f"WARN: 'ob login' falló (código {login.returncode}): {(login.stderr or '').strip()[:200]}")
            return False
    except Exception as exc:
        log(f"WARN: 'ob login' falló: {exc}")
        return False

    vault = os.environ.get("OBSIDIAN_VAULT")
    enc = os.environ.get("OBSIDIAN_ENCRYPTION_PASSWORD")
    if not vault or not enc:
        log("WARN: sin OBSIDIAN_VAULT/OBSIDIAN_ENCRYPTION_PASSWORD; login OK pero no configuro sync.")
        return False

    try:
        setup = _run_ob(
            [
                "sync-setup",
                "--vault", vault,
                "--path", str(vault_path),
                "--device-name", "conductor-cloud",
            ],
            stdin_text=enc,
        )
        if setup.returncode != 0:
            log(f"WARN: 'ob sync-setup' falló (código {setup.returncode}): {(setup.stderr or '').strip()[:200]}")
            return False
    except Exception as exc:
        log(f"WARN: 'ob sync-setup' falló: {exc}")
        return False

    log("'ob' configurado para este workspace.")
    return True


def main() -> int:
    vault_path = resolve_vault_path()
    if vault_path is None:
        return 0

    cwd = os.getcwd()
    project = resolve_project_name(cwd)
    if not project:
        log("no se pudo resolver el nombre del proyecto (no es un repo git); omito.")
        return 0

    marker_path = state_dir() / f"{project}.lastid"
    last_id = read_last_id(marker_path)

    log(f"exportando observaciones de Engram para proyecto '{project}'…")
    data = export_observations(project)
    observations = data.get("observations") or []

    new_obs = []
    for obs in observations:
        try:
            obs_id = int(obs.get("id"))
        except (TypeError, ValueError):
            continue
        if obs_id > last_id:
            new_obs.append((obs_id, obs))

    if not new_obs:
        log("sin observaciones nuevas; nada que escribir ni sincronizar.")
        return 0

    new_obs.sort(key=lambda pair: pair[0])

    today = datetime.now().strftime("%Y-%m-%d")
    now_time = datetime.now().strftime("%H:%M")
    note_dir = vault_path / "Conductor" / project
    note_dir.mkdir(parents=True, exist_ok=True)
    note_path = note_dir / f"{today}.md"

    if not note_path.exists():
        header = (
            f"# {project}\n\n"
            "> Auto-fed from Conductor / Engram. Do not edit above the sessions.\n"
        )
        note_path.write_text(header)

    newest_id, newest_obs = new_obs[-1]
    newest_session_id = newest_obs.get("session_id") or "unknown"
    session_short = str(newest_session_id)[:8] if newest_session_id != "unknown" else "unknown"

    lines = [f"\n## Session {session_short} — {now_time}\n"]
    for obs_id, obs in new_obs:
        obs_type = obs.get("type", "")
        title = obs.get("title", "")
        created_at = obs.get("created_at", "")
        content = obs.get("content", "")
        lines.append(f"\n### [{obs_type}] {title}\n{created_at} · id {obs_id}\n\n{content}\n")

    with open(note_path, "a") as f:
        f.write("".join(lines))

    write_last_id(marker_path, newest_id)
    log(f"escritas {len(new_obs)} observaciones nuevas en {note_path}; marker actualizado a {newest_id}.")

    ensure_ob_ready(vault_path)

    log(f"sincronizando vault con 'ob sync --path {vault_path}'…")
    try:
        result = subprocess.run(
            ["ob", "sync", "--path", str(vault_path)],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode == 0:
            log(f"ob sync OK: {result.stdout.strip()}")
        else:
            log(f"WARN: ob sync devolvió código {result.returncode}: {result.stderr.strip()}")
    except Exception as exc:
        log(f"WARN: ob sync falló: {exc}")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        log(f"WARN: fallo inesperado: {exc}")
        sys.exit(0)
