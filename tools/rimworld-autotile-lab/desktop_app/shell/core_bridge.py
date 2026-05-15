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
_SERVER: "_CoreServer | None" = None
_REQUEST_IDS = itertools.count(1)
_SOURCES_FRESH_FOR_BINARY: Path | None = None


def ensure_core_binary() -> Path:
    global _SOURCES_FRESH_FOR_BINARY
    if (
        _SOURCES_FRESH_FOR_BINARY is not None
        and _SOURCES_FRESH_FOR_BINARY.exists()
    ):
        return _SOURCES_FRESH_FOR_BINARY

    if RELEASE_EXE.exists() and not core_sources_newer_than(RELEASE_EXE):
        _SOURCES_FRESH_FOR_BINARY = RELEASE_EXE
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
        _SOURCES_FRESH_FOR_BINARY = RELEASE_EXE
        return RELEASE_EXE
    if DEBUG_EXE.exists():
        _SOURCES_FRESH_FOR_BINARY = DEBUG_EXE
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


class _CoreServer:
    """Long-lived `cliff_forge_core --serve` process with id-multiplexed responses."""

    def __init__(self, binary: Path) -> None:
        self.binary = binary
        self.process: subprocess.Popen[str] = subprocess.Popen(
            [str(binary), "--serve"],
            cwd=str(CORE_DIR),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
        )
        self._stdin_lock = threading.Lock()
        self._pending_lock = threading.Lock()
        self._pending: dict[int, queue.Queue[str]] = {}
        self._stopped = threading.Event()
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def _read_loop(self) -> None:
        stdout = self.process.stdout
        if stdout is None:
            self._stopped.set()
            return
        try:
            for line in stdout:
                if not line:
                    break
                stripped = line.strip()
                if not stripped:
                    continue
                response_id = self._extract_id(stripped)
                with self._pending_lock:
                    response_queue = self._pending.pop(response_id, None)
                if response_queue is not None:
                    response_queue.put(stripped)
                # else: response for a cancelled / unregistered id — drop it.
        except Exception:
            pass
        finally:
            self._stopped.set()
            with self._pending_lock:
                pending = list(self._pending.values())
                self._pending.clear()
            for response_queue in pending:
                try:
                    response_queue.put("")
                except Exception:
                    pass

    @staticmethod
    def _extract_id(line: str) -> int:
        try:
            parsed = json.loads(line)
        except Exception:
            return 0
        try:
            return int(parsed.get("id", 0))
        except (TypeError, ValueError):
            return 0

    def is_alive(self) -> bool:
        return (not self._stopped.is_set()) and self.process.poll() is None

    def submit(self, message_id: int, payload: dict[str, Any]) -> queue.Queue[str]:
        response_queue: queue.Queue[str] = queue.Queue(maxsize=1)
        with self._pending_lock:
            self._pending[message_id] = response_queue
        line = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
        stdin = self.process.stdin
        if stdin is None:
            with self._pending_lock:
                self._pending.pop(message_id, None)
            raise RuntimeError("Core server stdin is unavailable.")
        try:
            with self._stdin_lock:
                stdin.write(line + "\n")
                stdin.flush()
        except Exception:
            with self._pending_lock:
                self._pending.pop(message_id, None)
            raise
        return response_queue

    def unregister(self, message_id: int) -> None:
        with self._pending_lock:
            self._pending.pop(message_id, None)

    def drain_stderr(self) -> str:
        stderr = self.process.stderr
        if stderr is None:
            return ""
        try:
            return stderr.read() or ""
        except Exception:
            return ""

    def stop(self) -> None:
        self._stopped.set()
        if self.process.poll() is None:
            try:
                self.process.terminate()
            except Exception:
                pass
            try:
                self.process.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                try:
                    self.process.kill()
                except Exception:
                    pass
                try:
                    self.process.wait(timeout=1.0)
                except Exception:
                    pass
        with self._pending_lock:
            pending = list(self._pending.values())
            self._pending.clear()
        for response_queue in pending:
            try:
                response_queue.put("")
            except Exception:
                pass


def _ensure_core_server(binary: Path) -> _CoreServer:
    global _SERVER
    server = _SERVER
    if server is not None and server.is_alive() and server.binary == binary:
        return server
    if server is not None:
        server.stop()
    _SERVER = _CoreServer(binary)
    return _SERVER


def run_core(
    mode: str,
    request: dict[str, Any],
    output_dir: Path,
    cancel_event: threading.Event | None = None,
) -> dict[str, Any]:
    binary = ensure_core_binary()
    output_dir.mkdir(parents=True, exist_ok=True)

    with _SERVER_LOCK:
        server = _ensure_core_server(binary)

    message_id = next(_REQUEST_IDS)
    message = {
        "id": message_id,
        "mode": mode,
        "request": request,
        "output": str(output_dir),
        "inline_preview": mode == "draft",
        "transient": mode == "draft",
    }
    response_queue = server.submit(message_id, message)
    try:
        response_line = _wait_for_response(server, response_queue, cancel_event)
    finally:
        server.unregister(message_id)

    response = json.loads(response_line)
    if not response.get("ok"):
        raise RuntimeError(response.get("error") or "Core render failed")

    manifest = response["manifest"]
    files = manifest.get("files") or {}
    inline_preview = files.pop("preview_png_base64", None)
    if inline_preview:
        manifest["_preview_png_bytes"] = base64.b64decode(inline_preview)
    return manifest


def _wait_for_response(
    server: _CoreServer,
    response_queue: queue.Queue[str],
    cancel_event: threading.Event | None,
) -> str:
    while True:
        if cancel_event is not None and cancel_event.is_set():
            raise RenderCancelled("Рендер отменён из-за нового запроса.")
        try:
            line = response_queue.get(timeout=0.05)
        except queue.Empty:
            if not server.is_alive():
                stderr = server.drain_stderr()
                stop_core_server()
                raise RuntimeError(stderr.strip() or "Core server exited without a response.")
            continue
        if line:
            return line
        stderr = server.drain_stderr()
        stop_core_server()
        raise RuntimeError(stderr.strip() or "Core server exited without a response.")


def stop_core_server() -> None:
    global _SERVER
    server = _SERVER
    _SERVER = None
    if server is not None:
        server.stop()


atexit.register(stop_core_server)
