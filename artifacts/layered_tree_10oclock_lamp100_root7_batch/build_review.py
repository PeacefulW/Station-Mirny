"""Build a labelled review sheet for the accepted six-tree lighting profile."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
BATCH = Path(__file__).resolve().parent
TREE_ONE = ROOT / "artifacts" / "layered_tree_10oclock_lamp100_root7" / "tree_01_sun10_lamp100_root7_visible_root_shadow_v4_cycles.png"
OUTPUT = BATCH / "all_trees_sun10_lamp100_root7_visible_root_shadows_review.png"


def tree_path(index: int) -> Path:
    if index == 1:
        return TREE_ONE
    return BATCH / f"tree_{index:02d}_sun10_lamp100_root7_visible_root_shadow_cycles.png"


def main() -> None:
    cell_w, cell_h = 560, 560
    sheet = Image.new("RGBA", (cell_w * 3, cell_h * 2 + 70), (22, 23, 25, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    draw.text(
        (20, 18),
        "SUN 10:00 | LAMP 100 | ROOT EMBED 7% | VISIBLE-ROOT CYCLES SHADOW",
        font=font,
        fill=(238, 233, 223, 255),
    )
    draw.text(
        (20, 40),
        "tree_01..05 yaw 90 deg | tree_06 yaw 180 deg | buried caster geometry clipped at ground",
        font=font,
        fill=(154, 162, 170, 255),
    )

    for index in range(1, 7):
        image = Image.open(tree_path(index)).convert("RGBA")
        crop = image.crop((64, 64, image.width - 64, image.height - 64))
        crop.thumbnail((cell_w - 20, cell_h - 48), Image.Resampling.LANCZOS)
        col = (index - 1) % 3
        row = (index - 1) // 3
        x0 = col * cell_w
        y0 = 70 + row * cell_h
        draw.rectangle((x0 + 5, y0 + 5, x0 + cell_w - 6, y0 + cell_h - 6), outline=(67, 70, 75, 255), width=1)
        draw.text(
            (x0 + 16, y0 + 14),
            f"TREE {index:02d} | yaw {180 if index == 6 else 90} deg",
            font=font,
            fill=(222, 217, 207, 255),
        )
        sheet.alpha_composite(crop, (x0 + (cell_w - crop.width) // 2, y0 + 38))

    sheet.save(OUTPUT)
    print(f"Wrote review sheet to {OUTPUT}")


if __name__ == "__main__":
    main()
