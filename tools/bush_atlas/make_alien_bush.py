"""Drive the alien bush run: Blender source bake -> canonical postprocess -> proof sheet.

Usage (from repo root):

    python tools/bush_atlas/make_alien_bush.py --out-dir artifacts/alien_bush_v1

The bake and the postprocess are the shipped tree path
(`tools/tree_atlas/blender_layered_tree_asset_bake.py`,
`postprocess_layered_tree_asset.py`, `layered_asset_bake_profile.json`); this
driver only sequences the runs and renders the human-facing proof.

The proof sheet answers the two questions a new flora asset has to answer:
does the shadow read, and is the plant actually small next to a tree. The
second one needs the recorded world framing, because the canonical camera
refits every asset to the same frame fraction.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import random
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parents[1]
TREE_TOOL_DIR = REPO_ROOT / "tools" / "tree_atlas"
DEFAULT_BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.0\blender.exe")
DEFAULT_BUSH_PROFILE = TOOL_DIR / "alien_bush_profiles.json"
BAKE_PROFILE_PATH = TREE_TOOL_DIR / "layered_asset_bake_profile.json"
REFERENCE_TREE_DIR = REPO_ROOT / "assets" / "sprites" / "flora" / "layered_trees" / "tree_01"


def load_postprocess_module():
    path = TREE_TOOL_DIR / "postprocess_layered_tree_asset.py"
    spec = importlib.util.spec_from_file_location("postprocess_layered_tree_asset", path)
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
    parser.add_argument("--bush-profile", type=Path, default=DEFAULT_BUSH_PROFILE)
    parser.add_argument("--only", nargs="*", default=None, help="Bake only these variant ids.")
    parser.add_argument("--skip-bake", action="store_true", help="Reuse existing renders, redo postprocess and sheet.")
    return parser.parse_args()


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def run_blender_variant(blender: Path, out_dir: Path, variant_id: str, bush_profile: Path) -> None:
    command = [
        str(blender),
        "-b",
        "--factory-startup",
        "--python",
        str(TOOL_DIR / "blender_alien_bush_bake.py"),
        "--",
        "--out-dir",
        str(out_dir),
        "--variant-id",
        variant_id,
        "--bush-profile",
        str(bush_profile),
    ]
    started = time.time()
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    # Blender exits 0 even when the embedded script raises, so verify the contract outputs.
    expected = [
        out_dir / name
        for name in ("albedo.png", "trunk.png", "foliage.png", "shadow_raw.png", "classification.json", "variation.json")
    ]
    missing = [path.name for path in expected if not path.is_file()]
    if result.returncode != 0 or missing:
        sys.stderr.write(result.stdout[-8000:] + "\n" + result.stderr[-8000:] + "\n")
        raise SystemExit(f"Blender bake failed for {variant_id} (exit {result.returncode}, missing {missing})")
    print(f"  baked {variant_id} in {time.time() - started:.1f}s")


def load_font(size: int) -> ImageFont.ImageFont:
    for name in ("seguisb.ttf", "arialbd.ttf", "segoeui.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    print("  warning: no TrueType font found, falling back to bitmap labels")
    return ImageFont.load_default()


def biome_ground(width: int, height: int, seed: int) -> Image.Image:
    """A stand-in for the plains floor from the reference frame.

    Only the proof sheet uses it. Judging an orange-world plant on the neutral
    studio ground is how a colour that disappears into the biofield gets
    approved.
    """
    rng = random.Random(seed)
    ground = Image.new("RGBA", (width, height), (108, 76, 56, 255))
    draw = ImageDraw.Draw(ground)
    for _ in range(2600):
        x = rng.randrange(width)
        y = rng.randrange(height)
        radius = rng.randint(2, 9)
        tone = rng.randint(-22, 24)
        draw.ellipse(
            (x - radius, y - radius * 0.6, x + radius, y + radius * 0.6),
            fill=(108 + tone, 76 + int(tone * 0.7), 56 + int(tone * 0.5), 255),
        )
    for _ in range(240):
        x = rng.randrange(width)
        y = rng.randrange(height)
        length = rng.randint(14, 46)
        angle = rng.uniform(-1.35, -0.35)
        warm = rng.randint(-24, 26)
        draw.line(
            (x, y, x + math.cos(angle) * length, y + math.sin(angle) * length),
            fill=(190 + warm, 92 + int(warm * 0.6), 30 + int(warm * 0.4), 255),
            width=rng.randint(2, 5),
        )
    for _ in range(90):
        x = rng.randrange(width)
        y = rng.randrange(height)
        radius = rng.randint(2, 5)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(96, 88, 82, 255))
    return ground


def layered_composite(asset_dir: Path, background: Image.Image) -> Image.Image:
    canvas = background.copy()
    for name in ("shadow.png", "trunk.png", "foliage.png"):
        canvas.alpha_composite(POST.load_rgba(asset_dir / name))
    return canvas


def flat_layers(asset_dir: Path, names: tuple[str, ...]) -> Image.Image:
    layers = [POST.load_rgba(asset_dir / name) for name in names]
    canvas = Image.new("RGBA", layers[0].size, (0, 0, 0, 0))
    for layer in layers:
        canvas.alpha_composite(layer)
    return canvas


def reference_tree_framing() -> tuple[float, tuple[int, int]]:
    meta = load_json(REFERENCE_TREE_DIR / "meta.json")
    framing = meta["variation"]["framing"]
    anchor = meta["anchor"]
    return float(framing["pixels_per_world_unit"]), (int(anchor[0]), int(anchor[1]))


def build_scale_row(asset_dir: Path, tile_height: int) -> tuple[Image.Image, float, float]:
    """Bush and shipped tree at one world scale, roots on one baseline."""
    tree_ppu, tree_anchor = reference_tree_framing()
    bush_variation = load_json(asset_dir / "variation.json")
    bush_ppu = float(bush_variation["framing"]["pixels_per_world_unit"])
    bush_height = float(bush_variation["framing"]["world_height"])
    tree_height = float(load_json(REFERENCE_TREE_DIR / "meta.json")["variation"]["framing"]["world_height"])

    reference_ppu = min(tree_ppu, bush_ppu)
    entries = []
    above = below = half_width = 1
    for source_dir, ppu, anchor, label in (
        (REFERENCE_TREE_DIR, tree_ppu, tree_anchor, f"дерево tree_01 — {tree_height:.2f} ед."),
        (
            asset_dir,
            bush_ppu,
            tuple(load_json(asset_dir / "classification.json")["anchor"]),
            f"куст {asset_dir.name} — {bush_height:.2f} ед.",
        ),
    ):
        factor = reference_ppu / ppu
        image = flat_layers(source_dir, ("shadow.png", "trunk.png", "foliage.png"))
        size = (max(1, round(image.width * factor)), max(1, round(image.height * factor)))
        scaled = image.resize(size, Image.Resampling.LANCZOS)
        scaled_anchor = (anchor[0] * factor, anchor[1] * factor)
        bbox = scaled.getchannel("A").getbbox() or (0, 0, size[0], size[1])
        above = max(above, int(scaled_anchor[1] - bbox[1]))
        below = max(below, int(bbox[3] - scaled_anchor[1]))
        half_width = max(half_width, int(max(scaled_anchor[0] - bbox[0], bbox[2] - scaled_anchor[0])))
        entries.append((scaled, scaled_anchor, label))

    cell_w = int(half_width * 2 + 90)
    cell_h = int(above + below + 70)
    baseline_y = int(above + 35)
    row = biome_ground(cell_w * len(entries), cell_h, 4242)
    draw = ImageDraw.Draw(row)
    label_font = load_font(20)
    for index, (scaled, scaled_anchor, label) in enumerate(entries):
        origin_x = index * cell_w + cell_w // 2
        row.alpha_composite(scaled, (int(origin_x - scaled_anchor[0]), int(baseline_y - scaled_anchor[1])))
        draw.text((index * cell_w + 14, cell_h - 30), label, fill=(240, 232, 216, 255), font=label_font)
    draw.line((0, baseline_y, row.width, baseline_y), fill=(60, 44, 34, 200), width=1)

    scale_factor = tile_height / row.height
    row = row.resize((max(1, int(row.width * scale_factor)), tile_height), Image.Resampling.LANCZOS)
    return row, bush_height, tree_height


def build_ingame_row(asset_dir: Path, tree_pixel_height: int, bush_count: int) -> Image.Image:
    """The same two assets at the size the game actually draws them.

    A 768 px studio render flatters details that vanish at ~90 px on screen.
    Thin pod stalks in particular either survive this row or they are not worth
    baking.
    """
    tree_ppu, tree_anchor = reference_tree_framing()
    tree_meta = load_json(REFERENCE_TREE_DIR / "meta.json")
    tree_height = float(tree_meta["variation"]["framing"]["world_height"])
    bush_variation = load_json(asset_dir / "variation.json")
    bush_ppu = float(bush_variation["framing"]["pixels_per_world_unit"])
    bush_anchor = tuple(load_json(asset_dir / "classification.json")["anchor"])

    # One shared px-per-world-unit derived from the requested tree size.
    target_ppu = tree_pixel_height / tree_height
    placements = []
    for source_dir, ppu, anchor in ((REFERENCE_TREE_DIR, tree_ppu, tree_anchor), (asset_dir, bush_ppu, bush_anchor)):
        factor = target_ppu / ppu
        image = flat_layers(source_dir, ("shadow.png", "trunk.png", "foliage.png"))
        size = (max(1, round(image.width * factor)), max(1, round(image.height * factor)))
        placements.append((image.resize(size, Image.Resampling.LANCZOS), (anchor[0] * factor, anchor[1] * factor)))

    tree_image, tree_scaled_anchor = placements[0]
    bush_image, bush_scaled_anchor = placements[1]
    height = int(tree_pixel_height * 1.7)
    width = int(tree_image.width + bush_image.width * bush_count * 0.8 + 120)
    row = biome_ground(width, height, 907)
    baseline_y = int(height * 0.72)
    row.alpha_composite(tree_image, (60 - int(tree_scaled_anchor[0]) + tree_image.width // 2, baseline_y - int(tree_scaled_anchor[1])))
    for index in range(bush_count):
        x = int(tree_image.width + 90 + index * bush_image.width * 0.78)
        offset_y = baseline_y + (index - 1) * int(tree_pixel_height * 0.06)
        row.alpha_composite(bush_image, (x - int(bush_scaled_anchor[0]), offset_y - int(bush_scaled_anchor[1])))
    return row


def build_proof_sheet(out_dir: Path, asset_dir: Path, variant: dict) -> Path:
    albedo = POST.load_rgba(asset_dir / "albedo.png")
    tile = 460
    studio_ground = POST.composite_on_ground(Image.new("RGBA", albedo.size, (0, 0, 0, 0)))
    biome = biome_ground(albedo.width, albedo.height, int(variant["seed"]))

    panels = [
        ("альбедо (albedo)", POST.composite_on_ground(albedo)),
        ("слои + тень (layered + shadow)", layered_composite(asset_dir, studio_ground)),
        ("на грунте биома (biome ground)", layered_composite(asset_dir, biome)),
        ("только тень (shadow only)", POST.composite_on_ground(POST.load_rgba(asset_dir / "shadow.png"))),
        ("маска ветра (wind mask)", POST.load_rgba(asset_dir / "wind_mask.png")),
    ]

    title_h = 60
    label_h = 30
    scale_label_h = 34
    scale_row, bush_height, tree_height = build_scale_row(asset_dir, tile)
    ingame_row = build_ingame_row(asset_dir, tree_pixel_height=250, bush_count=3)
    width = max(tile * len(panels), scale_row.width, ingame_row.width)
    canvas = Image.new(
        "RGBA",
        (width, title_h + label_h + tile + (scale_label_h + scale_row.height) + (scale_label_h + ingame_row.height)),
        (20, 19, 18, 255),
    )
    draw = ImageDraw.Draw(canvas)
    draw.text(
        (16, 14),
        f"Инопланетный куст {variant['id']} — канонический бейк деревьев "
        f"(layered asset bake v4, солнце 225°, тень на юго-восток)",
        fill=(238, 230, 214, 255),
        font=load_font(28),
    )

    label_font = load_font(20)
    for index, (label, image) in enumerate(panels):
        thumb = image.convert("RGBA").resize((tile, tile), Image.Resampling.LANCZOS)
        x = index * tile
        canvas.alpha_composite(thumb, (x, title_h + label_h))
        draw.text((x + 12, title_h + 6), label, fill=(232, 222, 202, 255), font=label_font)
        if index > 0:
            draw.line((x, title_h, x, title_h + label_h + tile), fill=(52, 50, 46, 255), width=1)

    scale_y = title_h + label_h + tile
    draw.text(
        (16, scale_y + 7),
        f"единый мировой масштаб (common world scale): куст {bush_height:.2f} ед. против дерева {tree_height:.2f} ед.",
        fill=(232, 222, 202, 255),
        font=label_font,
    )
    canvas.alpha_composite(scale_row, (0, scale_y + scale_label_h))

    ingame_y = scale_y + scale_label_h + scale_row.height
    draw.text(
        (16, ingame_y + 7),
        "в игровом размере (in-game size): дерево ≈ 250 px, куст — тем же мировым масштабом",
        fill=(232, 222, 202, 255),
        font=label_font,
    )
    canvas.alpha_composite(ingame_row, (0, ingame_y + scale_label_h))

    path = out_dir / f"proof_{variant['id']}.png"
    canvas.convert("RGB").save(path)
    print(f"  wrote {path}")
    return path


def main() -> None:
    args = parse_args()
    bush_profile = load_json(args.bush_profile)
    variants = bush_profile["variants"]
    if args.only:
        wanted = set(args.only)
        variants = [variant for variant in variants if variant["id"] in wanted]
        if not variants:
            raise SystemExit(f"No variants matched {sorted(wanted)}")

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    bake_profile = POST.load_profile(BAKE_PROFILE_PATH)

    for variant in variants:
        asset_dir = out_dir / variant["id"]
        if not args.skip_bake:
            print(f"baking {variant['id']} ({variant['title_ru']})")
            run_blender_variant(args.blender, asset_dir, variant["id"], args.bush_profile)
        POST.save_outputs(asset_dir, None, bake_profile)
        print(f"  postprocessed {variant['id']}")
        build_proof_sheet(out_dir, asset_dir, variant)


if __name__ == "__main__":
    main()
