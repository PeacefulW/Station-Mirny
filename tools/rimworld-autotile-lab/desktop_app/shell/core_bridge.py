from __future__ import annotations

import atexit
import base64
import itertools
import json
import queue
import subprocess
import threading
from pathlib import Path
from typing import Any


DESKTOP_APP_DIR = Path(__file__).resolve().parents[1]
CORE_DIR = DESKTOP_APP_DIR / "core"
BUILD_SCRIPT = DESKTOP_APP_DIR / "build_core.cmd"
RELEASE_EXE = CORE_DIR / "target" / "release" / "cliff_forge_core.exe"
DEBUG_EXE = CORE_DIR / "target" / "debug" / "cliff_forge_core.exe"


class RenderCancelled(RuntimeError):
    pass


_SERVER_LOCK = threading.Lock()
_SERVER_PROCESS: subprocess.Popen[str] | None = None
_SERVER_BINARY: Path | None = None
_REQUEST_IDS = itertools.count(1)


def ensure_core_binary() -> Path:
    if RELEASE_EXE.exists() and not core_sources_newer_than(RELEASE_EXE):
        return RELEASE_EXE
    if not BUILD_SCRIPT.exists():
        raise FileNotFoundError(f"Build script not found: {BUILD_SCRIPT}")

    stop_core_server()
    subprocess.run(
        ["cmd", "/c", str(BUILD_SCRIPT)],
        cwd=str(DESKTOP_APP_DIR),
        check=True,
    )

    if RELEASE_EXE.exists():
        return RELEASE_EXE
    if DEBUG_EXE.exists():
        return DEBUG_EXE
    raise FileNotFoundError("Rust core did not produce an executable.")


def core_sources_newer_than(binary: Path) -> bool:
    if not binary.exists():
        return True

    binary_mtime = binary.stat().st_mtime
    watched = [BUILD_SCRIPT]
    watched.extend(CORE_DIR.glob("src/*.rs"))
    watched.append(CORE_DIR / "Cargo.toml")

    for path in watched:
        if path.exists() and path.stat().st_mtime > binary_mtime:
            return True
    return False


def run_core(
    mode: str,
    request: dict[str, Any],
    output_dir: Path,
    cancel_event: threading.Event | None = None,
) -> dict[str, Any]:
    binary = ensure_core_binary()
    output_dir.mkdir(parents=True, exist_ok=True)

    with _SERVER_LOCK:
        process = _ensure_core_server(binary)
        message_id = next(_REQUEST_IDS)
        message = {
            "id": message_id,
            "mode": mode,
            "request": request,
            "output": str(output_dir),
            "inline_preview": mode == "draft",
            "transient": mode == "draft",
        }
        line = json.dumps(message, separators=(",", ":"), ensure_ascii=False)
        assert process.stdin is not None
        process.stdin.write(line + "\n")
        process.stdin.flush()

        response_line = _read_server_response(process, cancel_event)
        response = json.loads(response_line)
        if response.get("id") != message_id:
            stop_core_server()
            raise RuntimeError(
                f"Core server response id mismatch: expected {message_id}, got {response.get('id')}"
            )
        if not response.get("ok"):
            raise RuntimeError(response.get("error") or "Core render failed")

        manifest = response["manifest"]
        files = manifest.get("files") or {}
        inline_preview = files.pop("preview_png_base64", None)
        if inline_preview:
            manifest["_preview_png_bytes"] = base64.b64decode(inline_preview)
        return manifest


def _ensure_core_server(binary: Path) -> subprocess.Popen[str]:
    global _SERVER_PROCESS, _SERVER_BINARY
    if _SERVER_PROCESS is not None and _SERVER_PROCESS.poll() is None and _SERVER_BINARY == binary:
        return _SERVER_PROCESS

    stop_core_server()
    _SERVER_PROCESS = subprocess.Popen(
        [str(binary), "--serve"],
        cwd=str(CORE_DIR),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    _SERVER_BINARY = binary
    return _SERVER_PROCESS


def _read_server_response(
    process: subprocess.Popen[str],
    cancel_event: threading.Event | None,
) -> str:
    response_queue: queue.Queue[str] = queue.Queue(maxsize=1)

    def reader() -> None:
        assert process.stdout is not None
        response_queue.put(process.stdout.readline())

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()

    while True:
        if cancel_event is not None and cancel_event.is_set():
            stop_core_server()
            raise RenderCancelled("Рендер отменён из-за нового запроса.")
        try:
            line = response_queue.get(timeout=0.05)
            break
        except queue.Empty:
            if process.poll() is not None:
                thread.join(timeout=0.2)
                line = _drain_queue(response_queue)
                break

    if line:
        return line

    stderr = ""
    if process.stderr is not None:
        try:
            stderr = process.stderr.read()
        except Exception:
            stderr = ""
    stop_core_server()
    raise RuntimeError(stderr.strip() or "Core server exited without a response.")


def _drain_queue(response_queue: queue.Queue[str]) -> str:
    try:
        return response_queue.get_nowait()
    except queue.Empty:
        return ""


def stop_core_server() -> None:
    global _SERVER_PROCESS, _SERVER_BINARY
    process = _SERVER_PROCESS
    _SERVER_PROCESS = None
    _SERVER_BINARY = None
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=1.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=1.0)


atexit.register(stop_core_server)
