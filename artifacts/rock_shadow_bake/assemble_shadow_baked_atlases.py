from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


FRAME_SIZE = 512
COLUMNS = 8
ROWS = 4
FRAME_COUNT = COLUMNS * ROWS
GROUND_COLOR = (96, 83, 67, 255)
CHECKER_A = (78, 70, 59, 255)
CHECKER_B = (112, 98, 79, 255)


ASSETS = [
    {
        "name": "rock_1",
        "frames": Path("artifacts/rock_shadow_bake/rock_1/frames_512"),
        "atlas": Path("assets/sprites/resources/atlases/plains_rock_1_atlas.png"),
    },
    {
        "name": "rock_2",
        "frames": Path("artifacts/rock_shadow_bake/rock_2/frames_512"),
        "atlas": Path("assets/sprites/resources/atlases/plains_rock_2_atlas.png"),
    },
    {
        "name": "volcanic_rock",
        "frames": Path("artifacts/rock_shadow_bake/volcanic_rock/frames_512"),
        "atlas": Path("assets/sprites/resources/atlases/plains_volcanic_rock_atlas.png"),
    },
]


def frame_path(frames_dir: Path, asset_name: str, index: int) -> Path:
    matches = sorted(frames_dir.glob(f"{asset_name}_rot_{index:02d}_*.png"))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one frame for {asset_name} #{index}, found {len(matches)}")
    return matches[0]


def make_checker(size: tuple[int, int], cell: int = 32) -> Image.Image:
    image = Image.new("RGBA", size, CHECKER_A)
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if ((x // cell) + (y // cell)) % 2 == 0:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=CHECKER_B)
    return image


def build_atlas(asset: dict[str, Path | str]) -> Image.Image:
    asset_name = str(asset["name"])
    frames_dir = Path(asset["frames"])
    atlas = Image.new("RGBA", (FRAME_SIZE * COLUMNS, FRAME_SIZE * ROWS), (0, 0, 0, 0))
    for index in range(FRAME_COUNT):
        frame = Image.open(frame_path(frames_dir, asset_name, index)).convert("RGBA")
        if frame.size != (FRAME_SIZE, FRAME_SIZE):
            raise RuntimeError(f"Unexpected frame size for {asset_name} #{index}: {frame.size}")
        x = (index % COLUMNS) * FRAME_SIZE
        y = (index // COLUMNS) * FRAME_SIZE
        atlas.alpha_composite(frame, (x, y))
    return atlas


def make_preview(atlas: Image.Image, asset_name: str, output_dir: Path) -> None:
    preview_size = (FRAME_SIZE * 3, FRAME_SIZE * 2)
    ground = Image.new("RGBA", preview_size, GROUND_COLOR)
    checker = make_checker(preview_size)
    positions = [
        (0, 0, 0),
        (1, FRAME_SIZE, 0),
        (2, FRAME_SIZE * 2, 0),
        (8, 0, FRAME_SIZE),
        (16, FRAME_SIZE, FRAME_SIZE),
        (24, FRAME_SIZE * 2, FRAME_SIZE),
    ]
    for frame_index, x, y in positions:
        crop = atlas.crop((
            (frame_index % COLUMNS) * FRAME_SIZE,
            (frame_index // COLUMNS) * FRAME_SIZE,
            (frame_index % COLUMNS + 1) * FRAME_SIZE,
            (frame_index // COLUMNS + 1) * FRAME_SIZE,
        ))
        ground.alpha_composite(crop, (x, y))
        checker.alpha_composite(crop, (x, y))
    ground.save(output_dir / f"{asset_name}_ground_preview.png")
    checker.save(output_dir / f"{asset_name}_checker_preview.png")


def main() -> None:
    output_dir = Path("artifacts/rock_shadow_bake/previews")
    output_dir.mkdir(parents=True, exist_ok=True)
    for asset in ASSETS:
        atlas = build_atlas(asset)
        atlas_path = Path(asset["atlas"])
        atlas_path.parent.mkdir(parents=True, exist_ok=True)
        atlas.save(atlas_path)
        make_preview(atlas, str(asset["name"]), output_dir)
        print(f"assembled {asset['name']} -> {atlas_path}")
    print(f"previews -> {output_dir}")


if __name__ == "__main__":
    main()
