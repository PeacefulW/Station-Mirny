"""Compose all eight rust crown individuals into one comparison sheet.

Panels are aligned by each asset's authored anchor, not by its bounding box:
the runtime plants a tree by its anchor and draws every tree at the same fixed
frame scale (768 px frame x TREE_FIXED_FRAME_SCALE 0.64 = 491 world px), so
frame-relative size and anchor alignment together are exactly what the game
shows. Refitting each panel to its own content would invent differences the
runtime never produces.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

from compose_foliage_sheet import BAR, DIM, INK, ground_tile, load_font, wrap

REPO = Path(r"C:\Users\peaceful\Station Peaceful\Station Peaceful")
SCRATCH = Path(__file__).resolve().parent
SHIPPED = REPO / "artifacts" / "rust_crown_tree"
NEW = SCRATCH / "rust_crown_new"

TITLES = {
    "var_01": ("молодое раскрытое", "в игре"),
    "var_02": ("раскидистое старое", "в игре"),
    "var_03": ("склонённое ветром", "в игре"),
    "var_04": ("высокое узкое", "новое"),
    "var_05": ("приземистое плотное", "новое"),
    "var_06": ("редкое старое", "новое"),
    "var_07": ("молодое мелкое", "новое"),
    "var_08": ("раскидистое", "новое"),
}


def composite(asset_dir: Path) -> Image.Image:
    """shadow under trunk under foliage - the runtime's own layer order."""
    base = None
    for name in ("shadow.png", "trunk.png", "foliage.png"):
        layer = Image.open(asset_dir / name).convert("RGBA")
        base = layer if base is None else Image.alpha_composite(base, layer)
    return base


def load_variant(asset_dir: Path) -> dict:
    meta = json.loads((asset_dir / "meta.json").read_text(encoding="utf-8"))
    variation = json.loads((asset_dir / "variation.json").read_text(encoding="utf-8"))
    return {
        "image": composite(asset_dir),
        "anchor": tuple(meta["anchor"]),
        "variant": variation["variant"],
        "parts": variation["part_counts"],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=SCRATCH / "rust_crown_eight")
    args = parser.parse_args()

    ids = list(TITLES)
    variants = []
    for variant_id in ids:
        source = SHIPPED / variant_id if (SHIPPED / variant_id / "meta.json").is_file() else NEW / variant_id
        if not (source / "meta.json").is_file():
            raise SystemExit(f"missing bake for {variant_id}")
        variants.append(load_variant(source))

    # Align on the anchor: build a canvas big enough for every frame's offset.
    anchor_x = max(v["anchor"][0] for v in variants)
    anchor_y = max(v["anchor"][1] for v in variants)
    width = max(v["image"].width - v["anchor"][0] for v in variants) + anchor_x
    height = max(v["image"].height - v["anchor"][1] for v in variants) + anchor_y
    aligned = []
    for variant in variants:
        canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        canvas.paste(
            variant["image"],
            (anchor_x - variant["anchor"][0], anchor_y - variant["anchor"][1]),
            variant["image"],
        )
        aligned.append(canvas)

    boxes = [image.getbbox() for image in aligned]
    box = (
        max(0, min(b[0] for b in boxes) - 20),
        max(0, min(b[1] for b in boxes) - 18),
        min(width, max(b[2] for b in boxes) + 20),
        min(height, max(b[3] for b in boxes) + 24),
    )
    crops = [image.crop(box) for image in aligned]
    crop_w, crop_h = crops[0].size

    f_head = load_font(27, bold=True)
    f_sub = load_font(16)
    f_title = load_font(20, bold=True)
    f_note = load_font(15)
    f_tag = load_font(14, bold=True)

    cols, rows = 4, 2
    cell_w = 420
    cell_h = int(crop_h * (cell_w / crop_w))
    title_h, note_h, margin, header_h = 34, 44, 14, 68
    panel_h = title_h + cell_h + note_h

    sheet = Image.new(
        "RGB",
        (cols * cell_w + (cols + 1) * margin, header_h + rows * panel_h + (rows + 1) * margin),
        (18, 15, 13),
    )
    draw = ImageDraw.Draw(sheet)
    draw.text((margin + 6, 13), "Rust crown — восемь особей", font=f_head, fill=INK)
    draw.text(
        (margin + 6, 45),
        "канонический бейк, выровнено по якорю посадки; в игре все рисуются "
        "одним кадровым масштабом, так что относительные размеры здесь настоящие",
        font=f_sub, fill=DIM,
    )

    for index, (variant_id, crop, variant) in enumerate(zip(ids, crops, variants)):
        col, row = index % cols, index // cols
        x = margin + col * (cell_w + margin)
        y = header_h + margin + row * (panel_h + margin)
        name, origin = TITLES[variant_id]

        draw.rectangle([x, y, x + cell_w - 1, y + panel_h - 1], fill=BAR)
        draw.text((x + 12, y + 7), f"{variant_id} — {name}", font=f_title, fill=INK)
        tag_w = draw.textlength(origin, font=f_tag)
        draw.text(
            (x + cell_w - tag_w - 12, y + 11), origin, font=f_tag,
            fill=DIM if origin == "в игре" else (246, 178, 82),
        )

        art = ground_tile((cell_w, cell_h))
        scaled = crop.resize((cell_w, cell_h), Image.LANCZOS)
        art.paste(scaled, (0, 0), scaled)
        sheet.paste(art, (x, y + title_h))

        spec = variant["variant"]
        note = (
            f"seed {spec['seed']} · yaw {spec['yaw_degrees']:g}° · "
            f"высота {spec['height_scale']:g} · крона {spec['crown_scale']:g} · "
            f"листва {spec['blade_density']:g}"
        )
        note_y = y + title_h + cell_h + 5
        for line in wrap(draw, note, f_note, cell_w - 24)[:2]:
            draw.text((x + 12, note_y), line, font=f_note, fill=DIM)
            note_y += 19

    sheet.save(args.out.with_name(args.out.name + "_closeup.png"))

    # --- game size ------------------------------------------------------------
    target_h = 210
    small_w = max(1, int(crop_w * (target_h / crop_h)))
    cell = small_w + 40
    label_h, head2, pad = 32, 64, 12
    strip = Image.new(
        "RGB", (len(ids) * cell + pad * 2, head2 + label_h + target_h + pad * 2), (18, 15, 13)
    )
    draw2 = ImageDraw.Draw(strip)
    draw2.text((pad + 6, 12), "Восемь особей в размер игрового спрайта", font=f_head, fill=INK)
    draw2.text(
        (pad + 6, 44),
        "при ~25 деревьях в кадре каждая форма попадётся примерно трижды — "
        "здесь видно, различает ли их глаз",
        font=f_sub, fill=DIM,
    )
    strip.paste(ground_tile((strip.width, target_h + pad)), (0, head2 + label_h))

    f_letter = load_font(16, bold=True)
    for index, (variant_id, crop) in enumerate(zip(ids, crops)):
        cell_x = pad + index * cell
        if index:
            draw2.line(
                [(cell_x, head2 + label_h), (cell_x, head2 + label_h + target_h + pad)],
                fill=(0, 0, 0), width=1,
            )
        small = crop.resize((small_w, target_h), Image.LANCZOS)
        strip.paste(small, (cell_x + (cell - small_w) // 2, head2 + label_h), small)
        draw2.text((cell_x + 8, head2 + 7), variant_id, font=f_letter, fill=INK)
        draw2.text(
            (cell_x + 8, head2 + label_h - 2), TITLES[variant_id][0], font=f_note,
            fill=DIM if TITLES[variant_id][1] == "в игре" else (246, 178, 82),
        )

    strip.save(args.out.with_name(args.out.name + "_gamesize.png"))
    print("wrote", args.out.with_name(args.out.name + "_closeup.png").name,
          "and", args.out.with_name(args.out.name + "_gamesize.png").name)


if __name__ == "__main__":
    main()
