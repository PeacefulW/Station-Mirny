"""Compose the branch-structure renders into close-up and game-size sheets.

Shares the ground patch, fonts and layout helpers with the foliage sheet so the
two explorations are directly comparable.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

from compose_foliage_sheet import (
    BAR, DIM, INK, ground_tile, load_font, union_alpha_box, wrap,
)

SCRATCH = Path(__file__).resolve().parent
RENDERS = SCRATCH / "branch_structure"

SHORT = {
    "s0_baseline": "как сейчас",
    "s1_two_low": "две низкие",
    "s2_stepped": "ступенями",
    "s3_many_short": "много коротких",
    "s4_stepped_stubs": "ступени + сучья",
    "s5_tall_trunk": "высокий ствол",
    "s6_tall_small_top": "малый верх",
}


def main() -> None:
    manifest = json.loads((RENDERS / "options.json").read_text(encoding="utf-8"))
    options = manifest["options"]
    images = [Image.open(RENDERS / f"{o['id']}.png").convert("RGBA") for o in options]

    left, top, right, bottom = union_alpha_box(images)
    pad_x, pad_y = 24, 20
    box = (
        max(0, left - pad_x), max(0, top - pad_y),
        min(images[0].width, right + pad_x), min(images[0].height, bottom + pad_y),
    )
    crops = [image.crop(box) for image in images]
    crop_w, crop_h = crops[0].size

    cols, rows = 4, 2
    cell_w = 430
    scale = cell_w / crop_w
    cell_h = int(crop_h * scale)
    title_h, note_h = 34, 46
    panel_h = title_h + cell_h + note_h
    margin = 14
    header_h = 68

    sheet = Image.new(
        "RGB",
        (cols * cell_w + (cols + 1) * margin, header_h + rows * panel_h + (rows + 1) * margin),
        (18, 15, 13),
    )
    draw = ImageDraw.Draw(sheet)

    f_head = load_font(27, bold=True)
    f_sub = load_font(16)
    f_title = load_font(20, bold=True)
    f_note = load_font(15)
    f_tag = load_font(14, bold=True)

    draw.text((margin + 6, 13), "Структура веток — листва не только на верхушке", font=f_head, fill=INK)
    draw.text(
        (margin + 6, 45),
        f"var_01, seed {manifest['seed']}, одна камера и канонический свет; "
        f"листва везде текущая, меняется только каркас",
        font=f_sub, fill=DIM,
    )

    for index, (option, crop) in enumerate(zip(options, crops)):
        col, row = index % cols, index // cols
        x = margin + col * (cell_w + margin)
        y = header_h + margin + row * (panel_h + margin)

        draw.rectangle([x, y, x + cell_w - 1, y + panel_h - 1], fill=BAR)
        draw.text((x + 12, y + 7), option["title"], font=f_title, fill=INK)

        art = ground_tile((cell_w, cell_h))
        scaled = crop.resize((cell_w, cell_h), Image.LANCZOS)
        art.paste(scaled, (0, 0), scaled)
        sheet.paste(art, (x, y + title_h))

        tags = []
        if option["laterals"]:
            tags.append(f"боковых: {option['laterals']}")
        if option["stubs"]:
            tags.append(f"сучьев: {option['stubs']}")
        if not option["trunk_matches_baseline"]:
            tags.append("ствол изменён")
        if tags:
            text = "  ·  ".join(tags)
            tw = draw.textlength(text, font=f_tag)
            draw.rectangle([x + 8, y + title_h + 8, x + 8 + tw + 16, y + title_h + 32], fill=(0, 0, 0))
            colour = (246, 178, 82) if option["trunk_matches_baseline"] else (240, 120, 90)
            draw.text((x + 16, y + title_h + 12), text, font=f_tag, fill=colour)

        note_y = y + title_h + cell_h + 6
        for line in wrap(draw, option["note"], f_note, cell_w - 24)[:2]:
            draw.text((x + 12, note_y), line, font=f_note, fill=DIM)
            note_y += 19

    sheet.save(SCRATCH / "branch_structure_closeup.png")

    # --- game size ------------------------------------------------------------
    # Unlike the close-up grid, this strip crops every option to its OWN alpha
    # box and scales each to the same height. That is what actually ships: the
    # canonical bake refits the camera per asset, so a taller tree does not draw
    # taller in game - it draws at the same sprite height with a thinner trunk.
    # Keeping the shared crop here would make the short options look tiny for a
    # reason the runtime never reproduces.
    target_h = 200
    own = []
    for image in images:
        cropped = image.crop(image.getbbox())
        width = max(1, int(cropped.width * (target_h / cropped.height)))
        own.append(cropped.resize((width, target_h), Image.LANCZOS))
    cell = max(image.width for image in own) + 44
    label_h, head2, pad = 32, 64, 12

    strip = Image.new(
        "RGB", (len(options) * cell + pad * 2, head2 + label_h + target_h + pad * 2), (18, 15, 13)
    )
    draw2 = ImageDraw.Draw(strip)
    draw2.text((pad + 6, 12), "Те же каркасы в размер игрового спрайта", font=f_head, fill=INK)
    draw2.text(
        (pad + 6, 44),
        "каждый подогнан под свой кадр, как это делает бейк — боковые клумпы должны "
        "ломать силуэт, а не слипаться со стволом",
        font=f_sub, fill=DIM,
    )
    strip.paste(ground_tile((strip.width, target_h + pad)), (0, head2 + label_h))

    f_letter = load_font(18, bold=True)
    for index, (option, small) in enumerate(zip(options, own)):
        cell_x = pad + index * cell
        if index:
            draw2.line(
                [(cell_x, head2 + label_h), (cell_x, head2 + label_h + target_h + pad)],
                fill=(0, 0, 0), width=1,
            )
        strip.paste(small, (cell_x + (cell - small.width) // 2, head2 + label_h), small)
        draw2.text((cell_x + 8, head2 + 6), option["title"].split(" - ")[0], font=f_letter, fill=INK)
        draw2.text((cell_x + 34, head2 + 8), SHORT[option["id"]], font=f_note, fill=DIM)

    strip.save(SCRATCH / "branch_structure_gamesize.png")
    print("wrote branch_structure_closeup.png and branch_structure_gamesize.png")


if __name__ == "__main__":
    main()
