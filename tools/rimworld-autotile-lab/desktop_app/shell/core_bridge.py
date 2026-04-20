from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path
from typing import Any


DESKTOP_APP_DIR = Path(__file__).resolve().parents[1]
CORE_DIR = DESKTOP_APP_DIR / "core"
BUILD_SCRIPT = DESKTOP_APP_DIR / "build_core.cmd"
RELEASE_EXE = CORE_DIR / "target" / "release" / "cliff_forge_core.exe"
DEBUG_EXE = CORE_DIR / "target" / "debug" / "cliff_forge_core.exe"


def ensure_core_binary() -> Path:
    if RELEASE_EXE.exists():
        return RELEASE_EXE
    if not BUILD_SCRIPT.exists():
        raise FileNotFoundError(f"Build script not found: {BUILD_SCRIPT}")

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


def run_core(mode: str, request: dict[str, Any], output_dir: Path) -> dict[str, Any]:
    binary = ensure_core_binary()
    output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as handle:
        json.dump(request, handle, indent=2)
        request_path = Path(handle.name)

    try:
        completed = subprocess.run(
            [
                str(binary),
                "--mode",
                mode,
                "--request",
                str(request_path),
                "--output",
                str(output_dir),
            ],
            cwd=str(CORE_DIR),
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        return json.loads(completed.stdout)
    finally:
        request_path.unlink(missing_ok=True)
