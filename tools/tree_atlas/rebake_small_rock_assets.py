"""Re-bake the shipped small rock family onto the current bake profile revision.

Usage (from repo root):

    python tools/tree_atlas/rebake_small_rock_assets.py \
        --out-dir artifacts/small_rock_sun_migration

    # after checking the before/after sheet:
    python tools/tree_atlas/rebake_small_rock_assets.py \
        --out-dir artifacts/small_rock_sun_migration --skip-bake --promote

The rocks were baked against profile revision 1, whose sun sat at azimuth 315
and threw shadows to screen north-east. Trees are on revision 4: azimuth 225,
shadows to screen south-east. Two sun directions in one frame is a visible
defect, so the contract requires the family to migrate all at once.

Baking writes to `--out-dir`; `--promote` is what actually replaces the assets.
Keeping those separate is what makes the before/after sheet meaningful: until
promotion runs, `assets/` still holds the old bake to compare against.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parents[1]
DEFAULT_BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.0\blender.exe")
DEFAULT_MANIFEST = TOOL_DIR / "small_rock_source_manifest.json"
ASSET_DIR = REPO_ROOT / "assets" / "sprites" / "decor" / "plains" / "layered_small_rocks"


def load_postprocess_module():
    path = TOOL_DIR / "postprocess_layered_rock_asset.py"
    spec = importlib.util.spec_from_file_location("postprocess_layered_rock_asset", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load postprocess module at {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


POST = load_postprocess_module()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--blender", type=Path, default=DEFAULT_BLENDER)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--glb-dir", type=Path, default=None, help="Overrides the manifest's default_glb_dir.")
    parser.add_argument("--only", nargs="*", default=None, help="Bake only these asset ids.")
    parser.add_argument("--skip-bake", action="store_true", help="Reuse existing renders, redo postprocess and sheets.")
    parser.add_argument("--promote", action="store_true", help="Copy the finished layers over the shipped assets.")
    return parser.parse_args()


def run_blender_asset(blender: Path, glb: Path, out_dir: Path) -> None:
    command = [
        str(blender),
        "-b",
        "--factory-startup",
        "--python",
        str(TOOL_DIR / "blender_layered_rock_asset_bake.py"),
        "--",
        "--glb",
        str(glb),
        "--out-dir",
        str(out_dir),
    ]
    started = time.time()
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    # Blender exits 0 even when the embedded script raises, so verify the contract outputs.
    expected = [out_dir / name for name in ("albedo.png", "snow_surface_raw.png", "shadow_raw.png", "classification.json")]
    missing = [path.name for path in expected if not path.is_file()]
    if result.returncode != 0 or missing:
        sys.stderr.write(result.stdout[-6000:] + "\n" + result.stderr[-6000:] + "\n")
        raise SystemExit(f"Blender bake failed for {out_dir.name} (exit {result.returncode}, missing {missing})")
    print(f"  baked {out_dir.name} in {time.time() - started:.1f}s")


def load_font(size: int) -> ImageFont.ImageFont:
    for name in ("seguisb.ttf", "arialbd.ttf", "segoeui.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    print("  warning: no TrueType font found, falling back to bitmap labels")
    return ImageFont.load_default()


def composite(asset_dir: Path) -> Image.Image:
    return POST.composite_on_ground(
        POST.load_rgba(asset_dir / "shadow.png"),
        POST.load_rgba(asset_dir / "albedo.png"),
    )


def build_before_after_sheet(out_dir: Path, assets: list[dict], *, tile: int) -> Path:
    """Old bake on top, new bake below, same column - the shadow must flip side."""
    label_h = 40
    title_h = 58
    columns = len(assets)
    canvas = Image.new("RGBA", (tile * columns, title_h + (label_h + tile) * 2), (18, 18, 17, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text(
        (14, 14),
        "Миграция солнца камней — сверху ревизия 1 (тень на северо-восток), снизу ревизия 4 (тень на юго-восток)",
        fill=(238, 230, 214, 255),
        font=load_font(30),
    )
    label_font = load_font(20)

    rows = [
        (ASSET_DIR, "было — ревизия 1 (before)"),
        (out_dir, "стало — ревизия 4 (after)"),
    ]
    for row, (source_root, row_title) in enumerate(rows):
        row_y = title_h + row * (label_h + tile)
        for index, asset in enumerate(assets):
            asset_dir = source_root / asset["id"]
            x = index * tile
            if (asset_dir / "albedo.png").is_file():
                thumb = composite(asset_dir).resize((tile, tile), Image.Resampling.LANCZOS)
                canvas.alpha_composite(thumb, (x, row_y + label_h))
            draw.text((x + 12, row_y + 6), f"{asset['id']} — {row_title}", fill=(232, 222, 202, 255), font=label_font)
            if index > 0:
                draw.line((x, row_y, x, row_y + label_h + tile), fill=(52, 50, 46, 255), width=1)

    path = out_dir / "comparison_sun_migration.png"
    canvas.convert("RGB").save(path)
    print(f"  wrote {path}")
    return path


def main() -> None:
    args = parse_args()
    with args.manifest.open("r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    assets = manifest["assets"]
    if args.only:
        wanted = set(args.only)
        assets = [asset for asset in assets if asset["id"] in wanted]
        if not assets:
            raise SystemExit(f"No assets matched {sorted(wanted)}")

    glb_dir = args.glb_dir if args.glb_dir is not None else Path(manifest["default_glb_dir"])
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    bake_profile = POST.load_profile(TOOL_DIR / "layered_asset_bake_profile.json")

    for asset in assets:
        asset_out = out_dir / asset["id"]
        if not args.skip_bake:
            glb = glb_dir / asset["glb"]
            if not glb.is_file():
                raise SystemExit(f"Source model missing: {glb}")
            print(f"baking {asset['id']} from {asset['glb']}")
            run_blender_asset(args.blender, glb, asset_out)
        promote_to = ASSET_DIR / asset["id"] if args.promote else None
        POST.save_outputs(asset_out, promote_to, bake_profile)
        print(f"  postprocessed {asset['id']}" + ("  -> promoted" if args.promote else ""))

    if not args.promote:
        build_before_after_sheet(out_dir, manifest["assets"], tile=460)
    else:
        print("  promoted into assets/ - rebuild the channel atlases before running the game")


if __name__ == "__main__":
    main()
