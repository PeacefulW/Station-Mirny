"""Compose the foliage-option renders into two comparison sheets.

Sheet 1 - close range, so the leaf biology is legible.
Sheet 2 - at roughly the size a tree occupies on screen in game, which is the
          only size that decides whether an option actually works.

Every option is cropped with the SAME box, so a bigger crown reads as bigger.
The ground is a real patch lifted out of the runtime screenshot rather than an
invented backdrop, so the colours are judged in the context they ship in.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

SCRATCH = Path(__file__).resolve().parent
RENDERS = SCRATCH / "foliage_options"
REPO = Path(r"C:\Users\peaceful\Station Peaceful\Station Peaceful")
GROUND_SOURCE = REPO / "artifacts" / "rust_crown_tree" / "runtime_after_crop.png"

## Short labels for the game-size strip: at that scale a panel is ~165 px wide
## and the full titles collide with their neighbours.
SHORT = {
    "a_current": "колючие пучки",
    "b_broadleaf": "широкий лист",
    "c_weeping": "плакучая",
    "d_needle": "хвойная щётка",
    "e_frond": "перистая вайя",
    "f_ribbon": "ленты",
    "g_pad": "округлые пластины",
}

INK = (238, 231, 221)
DIM = (176, 165, 154)
BAR = (26, 22, 19)


def load_font(size: int, bold: bool = False):
    for name in (
        r"C:\Windows\Fonts\segoeuib.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


_GROUND_CACHE: dict[tuple[int, int], Image.Image] = {}


def ground_tile(size: tuple[int, int]) -> Image.Image:
    """A bare-dirt patch from the runtime shot, mirror-tiled to fill `size`.

    Mirror rather than straight repeat, plus a light blur: a visible tiling grid
    behind the trees competes with the very silhouettes the sheet exists to
    compare. The patch is the flattest 260 px region in the screenshot, so it is
    real in-game ground rather than an invented backdrop.
    """
    cached = _GROUND_CACHE.get(size)
    if cached is not None:
        return cached.copy()
    source = Image.open(GROUND_SOURCE).convert("RGB")
    patch = source.crop((0, 300, 260, 560)).filter(ImageFilter.GaussianBlur(1.4))
    patch = ImageEnhance.Brightness(patch).enhance(0.88)
    flipped_x = patch.transpose(Image.FLIP_LEFT_RIGHT)
    flipped_y = patch.transpose(Image.FLIP_TOP_BOTTOM)
    flipped_xy = flipped_x.transpose(Image.FLIP_TOP_BOTTOM)
    block = Image.new("RGB", (patch.width * 2, patch.height * 2))
    block.paste(patch, (0, 0))
    block.paste(flipped_x, (patch.width, 0))
    block.paste(flipped_y, (0, patch.height))
    block.paste(flipped_xy, (patch.width, patch.height))
    tile = Image.new("RGB", size)
    for y in range(0, size[1], block.height):
        for x in range(0, size[0], block.width):
            tile.paste(block, (x, y))
    _GROUND_CACHE[size] = tile
    return tile.copy()


def union_alpha_box(images: list[Image.Image]) -> tuple[int, int, int, int]:
    boxes = [image.getbbox() for image in images]
    return (
        min(b[0] for b in boxes),
        min(b[1] for b in boxes),
        max(b[2] for b in boxes),
        max(b[3] for b in boxes),
    )


def wrap(draw: ImageDraw.ImageDraw, text: str, font, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        probe = f"{current} {word}".strip()
        if draw.textlength(probe, font=font) <= max_width or not current:
            current = probe
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def main() -> None:
    manifest = json.loads((RENDERS / "options.json").read_text(encoding="utf-8"))
    options = manifest["options"]
    images = [Image.open(RENDERS / f"{o['id']}.png").convert("RGBA") for o in options]

    left, top, right, bottom = union_alpha_box(images)
    pad_x, pad_y = 26, 22
    box = (
        max(0, left - pad_x),
        max(0, top - pad_y),
        min(images[0].width, right + pad_x),
        min(images[0].height, bottom + pad_y),
    )
    crops = [image.crop(box) for image in images]
    crop_w, crop_h = crops[0].size

    # --- sheet 1: close range, 4 x 2 grid -------------------------------------
    cols, rows = 4, 2
    cell_w = 430
    scale = cell_w / crop_w
    cell_h = int(crop_h * scale)
    title_h, note_h = 34, 46
    panel_h = title_h + cell_h + note_h
    margin = 14
    header_h = 66

    sheet_w = cols * cell_w + (cols + 1) * margin
    sheet_h = header_h + rows * panel_h + (rows + 1) * margin
    sheet = Image.new("RGB", (sheet_w, sheet_h), (18, 15, 13))
    draw = ImageDraw.Draw(sheet)

    f_head = load_font(27, bold=True)
    f_sub = load_font(16)
    f_title = load_font(20, bold=True)
    f_note = load_font(15)
    f_tag = load_font(14, bold=True)

    draw.text((margin + 6, 14), "Варианты листвы — крупно", font=f_head, fill=INK)
    draw.text(
        (margin + 6, 44),
        f"один и тот же ствол (seed {manifest['seed']}, var_01), одна камера, "
        f"канонические свет и солнце — меняется только крона",
        font=f_sub, fill=DIM,
    )

    for index, (option, crop) in enumerate(zip(options, crops)):
        col, row = index % cols, index // cols
        x = margin + col * (cell_w + margin)
        y = header_h + margin + row * (panel_h + margin)

        draw.rectangle([x, y, x + cell_w - 1, y + panel_h - 1], fill=BAR)
        draw.text((x + 12, y + 7), option["title"], font=f_title, fill=INK)

        art = ground_tile((cell_w, cell_h))
        art.paste(
            crop.resize((cell_w, cell_h), Image.LANCZOS),
            (0, 0),
            crop.resize((cell_w, cell_h), Image.LANCZOS),
        )
        sheet.paste(art, (x, y + title_h))

        tags = []
        if option["custom_mesh"]:
            tags.append("новая геометрия листа")
        if option["gravity_aligned"]:
            tags.append("ориентация по гравитации")
        if tags:
            tag_text = "  ·  ".join(tags)
            tw = draw.textlength(tag_text, font=f_tag)
            draw.rectangle(
                [x + 8, y + title_h + 8, x + 8 + tw + 16, y + title_h + 32],
                fill=(0, 0, 0),
            )
            draw.text((x + 16, y + title_h + 12), tag_text, font=f_tag, fill=(246, 178, 82))

        count = f"{option['foliage_parts']} листовых мешей"
        cw = draw.textlength(count, font=f_tag)
        draw.rectangle(
            [x + cell_w - cw - 24, y + title_h + cell_h - 32, x + cell_w - 8, y + title_h + cell_h - 8],
            fill=(0, 0, 0),
        )
        draw.text(
            (x + cell_w - cw - 16, y + title_h + cell_h - 28), count, font=f_tag, fill=DIM
        )

        note_y = y + title_h + cell_h + 6
        for line in wrap(draw, option["note"], f_note, cell_w - 24)[:2]:
            draw.text((x + 12, note_y), line, font=f_note, fill=DIM)
            note_y += 19

    sheet.save(SCRATCH / "foliage_options_closeup.png")

    # --- sheet 2: at in-game reading size -------------------------------------
    # A shipped tree occupies roughly 200 px of screen height at the default
    # camera; below that the crown stops being a shape and becomes a texture,
    # which is where most of these options either work or die.
    target_h = 200
    small_scale = target_h / crop_h
    small_w = max(1, int(crop_w * small_scale))
    small_h = target_h
    cell = small_w + 54
    label_h = 32
    head2 = 64
    pad = 12

    strip_w = len(options) * cell + pad * 2
    strip_h = head2 + label_h + small_h + pad * 2
    strip = Image.new("RGB", (strip_w, strip_h), (18, 15, 13))
    draw2 = ImageDraw.Draw(strip)
    draw2.text((pad + 6, 12), "Те же варианты в размер игрового спрайта", font=f_head, fill=INK)
    draw2.text(
        (pad + 6, 44),
        "здесь решается, читается ли крона силуэтом или схлопывается в одно пятно",
        font=f_sub, fill=DIM,
    )

    f_letter = load_font(18, bold=True)
    ground = ground_tile((strip_w, small_h + pad))
    strip.paste(ground, (0, head2 + label_h))

    for index, (option, crop) in enumerate(zip(options, crops)):
        cell_x = pad + index * cell
        if index:
            draw2.line(
                [(cell_x, head2 + label_h), (cell_x, head2 + label_h + small_h + pad)],
                fill=(0, 0, 0), width=1,
            )
        x = cell_x + (cell - small_w) // 2
        small = crop.resize((small_w, small_h), Image.LANCZOS)
        strip.paste(small, (x, head2 + label_h), small)
        letter = option["title"].split(" - ")[0]
        draw2.text((cell_x + 8, head2 + 6), letter, font=f_letter, fill=INK)
        draw2.text((cell_x + 28, head2 + 8), SHORT[option["id"]], font=f_note, fill=DIM)

    strip.save(SCRATCH / "foliage_options_gamesize.png")
    print("wrote foliage_options_closeup.png and foliage_options_gamesize.png")


if __name__ == "__main__":
    main()
