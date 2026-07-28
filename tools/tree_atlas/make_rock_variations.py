"""Drive the procedural rock run: Blender bake -> canonical postprocess -> proof sheets.

Usage (from repo root):

    python tools/tree_atlas/make_rock_variations.py \
        --out-dir artifacts/layered_rock_v1_variations

Unlike the tree driver this takes no `--glb`: every silhouette is generated from
its seed. The driver only sequences the runs and renders the human-facing
comparison sheets; bake settings stay owned by the layered asset bake contract.
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
DEFAULT_VARIATION_PROFILE = TOOL_DIR / "rock_variation_profiles.json"
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
    parser.add_argument("--variation-profile", type=Path, default=DEFAULT_VARIATION_PROFILE)
    parser.add_argument("--only", nargs="*", default=None, help="Bake only these variant ids.")
    parser.add_argument("--skip-bake", action="store_true", help="Reuse existing renders, redo postprocess and sheets.")
    parser.add_argument(
        "--promote",
        action="store_true",
        help="Copy finished layers into assets/ under each variant's asset_id.",
    )
    return parser.parse_args()


def run_blender_variant(blender: Path, out_dir: Path, variant_id: str, variation_profile: Path) -> None:
    command = [
        str(blender),
        "-b",
        "--factory-startup",
        "--python",
        str(TOOL_DIR / "blender_rock_variation_bake.py"),
        "--",
        "--out-dir",
        str(out_dir),
        "--variant-id",
        variant_id,
        "--variation-profile",
        str(variation_profile),
    ]
    started = time.time()
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    # Blender exits 0 even when the embedded script raises, so verify the contract outputs.
    expected = [
        out_dir / name
        for name in ("albedo.png", "snow_surface_raw.png", "shadow_raw.png", "classification.json", "variation.json")
    ]
    missing = [path.name for path in expected if not path.is_file()]
    if result.returncode != 0 or missing:
        sys.stderr.write(result.stdout[-6000:] + "\n" + result.stderr[-6000:] + "\n")
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


def variant_layers(asset_dir: Path, *, with_snow: bool) -> list[Image.Image]:
    layers = [
        POST.load_rgba(asset_dir / "shadow.png"),
        POST.load_rgba(asset_dir / "albedo.png"),
    ]
    if with_snow:
        layers.append(POST.load_rgba(asset_dir / "snow_overlay.png"))
    return layers


def composite_variant(asset_dir: Path, *, with_snow: bool) -> Image.Image:
    return POST.composite_on_ground(*variant_layers(asset_dir, with_snow=with_snow))


def flat_composite(asset_dir: Path, *, with_snow: bool) -> Image.Image:
    layers = variant_layers(asset_dir, with_snow=with_snow)
    canvas = Image.new("RGBA", layers[0].size, (0, 0, 0, 0))
    for layer in layers:
        canvas.alpha_composite(layer)
    return canvas


def read_framing(asset_dir: Path) -> tuple[float, tuple[int, int]]:
    with (asset_dir / "variation.json").open("r", encoding="utf-8") as fh:
        variation = json.load(fh)
    with (asset_dir / "classification.json").open("r", encoding="utf-8") as fh:
        classification = json.load(fh)
    anchor = classification["anchor"]
    return float(variation["framing"]["pixels_per_world_unit"]), (int(anchor[0]), int(anchor[1]))


def ground_cell(width: int, height: int, baseline_y: int) -> Image.Image:
    cell = Image.new("RGBA", (width, height), (43, 39, 33, 255))
    draw = ImageDraw.Draw(cell)
    for y in range(0, height, 28):
        color = (48 + (y // 28) % 2 * 5, 43, 35, 255)
        draw.rectangle((0, y, width, y + 14), fill=color)
    draw.line((0, baseline_y, width, baseline_y), fill=(72, 64, 54, 255), width=1)
    return cell


def build_world_scale_sheet(out_dir: Path, variants: list[dict], *, tile: int) -> Path:
    """One shared world scale for every variant, ground contact on one baseline.

    The canonical camera refits each asset to the same frame fraction, so the
    per-asset sheets cannot show that a gravel lump is smaller than a broad slab.
    This sheet undoes that refit using the recorded pixels-per-world-unit.
    """
    framings = {variant["id"]: read_framing(out_dir / variant["id"]) for variant in variants}
    reference_ppu = min(ppu for ppu, _ in framings.values())

    placed: dict[str, tuple[Image.Image, tuple[float, float]]] = {}
    above = below = half_width = 1
    for variant in variants:
        ppu, anchor = framings[variant["id"]]
        factor = reference_ppu / ppu
        for with_snow in (False, True):
            image = flat_composite(out_dir / variant["id"], with_snow=with_snow)
            size = (max(1, round(image.width * factor)), max(1, round(image.height * factor)))
            scaled = image.resize(size, Image.Resampling.LANCZOS)
            scaled_anchor = (anchor[0] * factor, anchor[1] * factor)
            bbox = scaled.getchannel("A").getbbox() or (0, 0, size[0], size[1])
            above = max(above, int(scaled_anchor[1] - bbox[1]))
            below = max(below, int(bbox[3] - scaled_anchor[1]))
            half_width = max(half_width, int(max(scaled_anchor[0] - bbox[0], bbox[2] - scaled_anchor[0])))
            placed[f"{variant['id']}:{int(with_snow)}"] = (scaled, scaled_anchor)

    cell_w = int(half_width * 2 + 60)
    cell_h = int(above + below + 60)
    baseline_y = int(above + 30)

    label_h = 46
    title_h = 54
    row_h = round(cell_h * tile / cell_w)
    canvas = Image.new("RGBA", (tile * len(variants), title_h + (label_h + row_h) * 2), (18, 18, 17, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text(
        (14, 14),
        "Процедурные камни — единый мировой масштаб (common world scale), контакт с землёй на одной линии",
        fill=(238, 230, 214, 255),
        font=load_font(28),
    )
    label_font = load_font(21)
    sub_font = load_font(16)

    for row, with_snow in enumerate((False, True)):
        row_y = title_h + row * (label_h + row_h)
        row_title = "со снегом (snow)" if with_snow else "без снега (no snow)"
        for index, variant in enumerate(variants):
            scaled, scaled_anchor = placed[f"{variant['id']}:{int(with_snow)}"]
            cell = ground_cell(cell_w, cell_h, baseline_y)
            cell.alpha_composite(
                scaled,
                (int(cell_w // 2 - scaled_anchor[0]), int(baseline_y - scaled_anchor[1])),
            )
            thumb = cell.resize((tile, row_h), Image.Resampling.LANCZOS)
            x = index * tile
            canvas.alpha_composite(thumb, (x, row_y + label_h))
            draw.text((x + 12, row_y + 6), f"{variant['id']} — {variant['title_ru']}", fill=(232, 222, 202, 255), font=label_font)
            draw.text((x + 12, row_y + 26), row_title, fill=(150, 145, 135, 255), font=sub_font)
            if index > 0:
                draw.line((x, row_y, x, row_y + label_h + row_h), fill=(52, 50, 46, 255), width=1)

    path = out_dir / "comparison_world_scale.png"
    canvas.convert("RGB").save(path)
    print(f"  wrote {path}")
    return path


def build_sheet(out_dir: Path, variants: list[dict], *, with_snow: bool, tile: int, title: str) -> Path:
    label_h = 46
    title_h = 54
    columns = len(variants)
    canvas = Image.new("RGBA", (tile * columns, title_h + label_h + tile), (18, 18, 17, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text((14, 14), title, fill=(238, 230, 214, 255), font=load_font(30))
    label_font = load_font(21)
    sub_font = load_font(16)

    for index, variant in enumerate(variants):
        image = composite_variant(out_dir / variant["id"], with_snow=with_snow)
        thumb = image.resize((tile, tile), Image.Resampling.LANCZOS)
        x = index * tile
        canvas.alpha_composite(thumb, (x, title_h + label_h))
        draw.text((x + 12, title_h + 6), f"{variant['id']} — {variant['title_ru']}", fill=(232, 222, 202, 255), font=label_font)
        draw.text(
            (x + 12, title_h + 26),
            f"flat {variant['flatten']:.2f}  elong {variant['elongation']:.2f}  facets {variant['facet_count']}"
            f"  chips {variant['chip_count']}  embed {variant['embed_fraction']:.2f}",
            fill=(150, 145, 135, 255),
            font=sub_font,
        )
        if index > 0:
            draw.line((x, title_h, x, canvas.height), fill=(52, 50, 46, 255), width=1)

    suffix = "snow" if with_snow else "no_snow"
    path = out_dir / f"comparison_{suffix}.png"
    canvas.convert("RGB").save(path)
    print(f"  wrote {path}")
    return path


def build_grid(out_dir: Path, no_snow: Path, snow: Path) -> Path:
    top = Image.open(no_snow).convert("RGB")
    bottom = Image.open(snow).convert("RGB")
    canvas = Image.new("RGB", (max(top.width, bottom.width), top.height + bottom.height + 8), (18, 18, 17))
    canvas.paste(top, (0, 0))
    canvas.paste(bottom, (0, top.height + 8))
    path = out_dir / "comparison_grid.png"
    canvas.save(path)
    print(f"  wrote {path}")
    return path


def main() -> None:
    args = parse_args()
    with args.variation_profile.open("r", encoding="utf-8") as fh:
        variation_profile = json.load(fh)
    variants = variation_profile["variants"]
    if args.only:
        wanted = set(args.only)
        variants = [variant for variant in variants if variant["id"] in wanted]
        if not variants:
            raise SystemExit(f"No variants matched {sorted(wanted)}")

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    bake_profile = POST.load_profile(TOOL_DIR / "layered_asset_bake_profile.json")

    for variant in variants:
        asset_dir = out_dir / variant["id"]
        if not args.skip_bake:
            print(f"baking {variant['id']} ({variant['title_ru']})")
            run_blender_variant(args.blender, asset_dir, variant["id"], args.variation_profile)
        promote_to = None
        if args.promote:
            if "asset_id" not in variant:
                raise SystemExit(f"{variant['id']} has no asset_id; cannot promote it into assets/")
            promote_to = ASSET_DIR / variant["asset_id"]
        POST.save_outputs(asset_dir, promote_to, bake_profile)
        print(f"  postprocessed {variant['id']}" + (f"  -> {variant['asset_id']}" if args.promote else ""))

    all_variants = variation_profile["variants"]
    ready = [variant for variant in all_variants if (out_dir / variant["id"] / "snow_overlay.png").is_file()]
    if len(ready) != len(all_variants):
        missing = sorted({v["id"] for v in all_variants} - {v["id"] for v in ready})
        print(f"  note: sheets built from {len(ready)}/{len(all_variants)} variants, missing {missing}")

    no_snow = build_sheet(
        out_dir,
        ready,
        with_snow=False,
        tile=560,
        title="Процедурные камни — без снега (no snow), покадровая подгонка камеры",
    )
    snow = build_sheet(
        out_dir,
        ready,
        with_snow=True,
        tile=560,
        title="Процедурные камни — со снегом (snow overlay), покадровая подгонка камеры",
    )
    build_grid(out_dir, no_snow, snow)
    build_world_scale_sheet(out_dir, ready, tile=560)


if __name__ == "__main__":
    main()
