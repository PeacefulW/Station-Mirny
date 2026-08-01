"""Bake and pack every clip declared in the player bake profile.

Run from the repository root:
    python tools/player_atlas/bake_all_player_clips.py --blender "<path to blender.exe>"

Use ``--render-pass shadow`` after an accepted albedo bake.  The shadow pass
reads the checked bake summary, so it reuses the exact direction yaws and
fractional source phases rather than inventing a second animation schedule.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parent.parent
DEFAULT_PROFILE = TOOL_DIR / "player_bake_profile.json"
DEFAULT_BLENDER = r"C:/Program Files/Blender Foundation/Blender 5.0/blender.exe"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE)
    parser.add_argument("--blender", default=DEFAULT_BLENDER)
    parser.add_argument("--frames-root", type=Path, default=REPO_ROOT / "artifacts" / "player_asset_bake")
    parser.add_argument("--atlas-out", type=Path, default=REPO_ROOT / "assets" / "sprites" / "player")
    parser.add_argument("--only", nargs="*", default=None, help="Limit to these clip ids")
    parser.add_argument(
        "--render-pass",
        choices=("all", "albedo", "shadow"),
        default="all",
        help="Render both passes, albedo only, or shadows against an existing accepted albedo bake",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    profile = json.loads(args.profile.read_text(encoding="utf-8"))
    clips = [c["clip_id"] for c in profile["clips"]]
    if args.only:
        clips = [c for c in clips if c in args.only]

    results = []
    for clip_id in clips:
        frames_dir = args.frames_root / clip_id
        started = time.time()
        if args.render_pass in ("all", "albedo"):
            print(f"[albedo bake] {clip_id} -> {frames_dir}", flush=True)
            bake = subprocess.run(
                [
                    args.blender, "-b", "--factory-startup",
                    "--python", str(TOOL_DIR / "blender_player_clip_bake.py"),
                    "--", clip_id, str(frames_dir), "--profile", str(args.profile),
                ],
                capture_output=True, text=True,
            )
            if "PLAYER_CLIP_BAKE_COMPLETE" not in bake.stdout:
                sys.stderr.write(bake.stdout[-4000:])
                sys.stderr.write(bake.stderr[-4000:])
                raise SystemExit(f"Albedo bake failed for clip '{clip_id}'")

            print(f"[albedo pack] {clip_id}", flush=True)
            pack = subprocess.run(
                [
                    sys.executable, str(TOOL_DIR / "assemble_player_atlas.py"),
                    clip_id, str(frames_dir), str(args.atlas_out),
                    "--profile", str(args.profile),
                ],
                capture_output=True, text=True,
            )
            if "PLAYER_ATLAS_ASSEMBLED" not in pack.stdout:
                sys.stderr.write(pack.stdout[-4000:])
                sys.stderr.write(pack.stderr[-4000:])
                raise SystemExit(f"Albedo atlas assembly failed for clip '{clip_id}'")

        if args.render_pass in ("all", "shadow"):
            summary_path = frames_dir / f"{clip_id}_render_summary.json"
            if not summary_path.is_file():
                raise SystemExit(
                    f"Shadow pass requires the accepted albedo bake summary: {summary_path}"
                )
            shadow_frames_dir = frames_dir / "shadow_frames"
            print(f"[shadow bake] {clip_id} -> {shadow_frames_dir}", flush=True)
            shadow_bake = subprocess.run(
                [
                    args.blender, "-b", "--factory-startup",
                    "--python", str(TOOL_DIR / "blender_player_shadow_bake.py"),
                    "--", clip_id, str(frames_dir), str(shadow_frames_dir),
                    "--profile", str(args.profile),
                ],
                capture_output=True, text=True,
            )
            if "PLAYER_SHADOW_BAKE_COMPLETE" not in shadow_bake.stdout:
                sys.stderr.write(shadow_bake.stdout[-4000:])
                sys.stderr.write(shadow_bake.stderr[-4000:])
                raise SystemExit(f"Physical shadow bake failed for clip '{clip_id}'")

            print(f"[shadow pack] {clip_id}", flush=True)
            shadow_pack = subprocess.run(
                [
                    sys.executable, str(TOOL_DIR / "assemble_player_shadow_atlas.py"),
                    clip_id, str(shadow_frames_dir), str(args.atlas_out),
                    "--profile", str(args.profile),
                    "--preview-dir", str(frames_dir),
                ],
                capture_output=True, text=True,
            )
            if "PLAYER_SHADOW_ATLAS_ASSEMBLED" not in shadow_pack.stdout:
                sys.stderr.write(shadow_pack.stdout[-4000:])
                sys.stderr.write(shadow_pack.stderr[-4000:])
                raise SystemExit(f"Shadow atlas assembly failed for clip '{clip_id}'")

        elapsed = time.time() - started
        results.append({"clip_id": clip_id, "render_pass": args.render_pass, "seconds": round(elapsed, 1)})
        print(f"[done] {clip_id} in {elapsed:.0f}s", flush=True)

    print("PLAYER_CLIP_PIPELINE_COMPLETE")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
