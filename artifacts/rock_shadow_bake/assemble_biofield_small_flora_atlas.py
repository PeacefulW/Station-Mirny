from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from assemble_4_variant_shadow_baked_atlases import (
    FRAME_SIZE,
    UNIQUE_VARIANTS,
    composite_two_pass,
    frame_paths,
    make_preview,
)


SOURCE_ASSET_NAME = "rare_rock"
OUTPUT_ASSET_NAME = "brown_seaweed_static_biofield"
SOURCE_PATH = "M:/Downloads/brown+seaweed+3d+model.glb"
FRAMES_DIR = Path("artifacts/rock_shadow_bake/rare_rock/frames_512_4variant")
ATLAS_PATH = Path("assets/sprites/flora/atlases/brown_seaweed_static_biofield_4x512.png")
METADATA_PATH = Path("assets/sprites/flora/atlases/brown_seaweed_static_biofield_4x512.json")
PREVIEW_DIR = Path("artifacts/rock_shadow_bake/previews")
COLUMNS = 4
ROWS = 1
FRAME_COUNT = COLUMNS * ROWS


def load_frames() -> list[Image.Image]:
    frames: list[Image.Image] = []
    for unique_index in range(UNIQUE_VARIANTS):
        final_path, object_path, shadow_path = frame_paths(FRAMES_DIR, SOURCE_ASSET_NAME, unique_index)
        if object_path.exists() and shadow_path.exists():
            frame = composite_two_pass(Image.open(object_path), Image.open(shadow_path))
            frame.save(final_path)
        elif final_path.exists():
            frame = Image.open(final_path).convert("RGBA")
        else:
            raise FileNotFoundError(final_path)
        if frame.size != (FRAME_SIZE, FRAME_SIZE):
            raise RuntimeError(f"Unexpected frame size for {final_path}: {frame.size}")
        frames.append(frame)
    return frames


def main() -> None:
    frames = load_frames()
    atlas = Image.new("RGBA", (FRAME_SIZE * COLUMNS, FRAME_SIZE * ROWS), (0, 0, 0, 0))
    frame_records: list[dict[str, int]] = []
    for index, frame in enumerate(frames):
        x = index * FRAME_SIZE
        atlas.alpha_composite(frame, (x, 0))
        frame_records.append({
            "index": index,
            "angle_degrees": index * 90,
            "x": x,
            "y": 0,
            "width": FRAME_SIZE,
            "height": FRAME_SIZE,
        })

    ATLAS_PATH.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(ATLAS_PATH)

    METADATA_PATH.write_text(json.dumps({
        "source": SOURCE_PATH,
        "sprite_sheet": ATLAS_PATH.name,
        "frame_count": FRAME_COUNT,
        "unique_variant_count": UNIQUE_VARIANTS,
        "columns": COLUMNS,
        "rows": ROWS,
        "frame_width": FRAME_SIZE,
        "frame_height": FRAME_SIZE,
        "camera": "orthographic top-front, 63 degree elevation, no side yaw",
        "shadows": "cycles two-pass render; real ground shadow pass composited under sprite",
        "postprocess": "two-pass object/shadow composite; slight bottom darken applied to object pixels",
        "native_packet_compatibility": "static biofield flora atlas index 1; four variants selected by object_variant",
        "frames": frame_records,
    }, indent=2), encoding="utf-8")

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    make_preview(atlas, OUTPUT_ASSET_NAME, PREVIEW_DIR)
    print(f"assembled {OUTPUT_ASSET_NAME} -> {ATLAS_PATH}")
    print(f"metadata -> {METADATA_PATH}")
    print(f"previews -> {PREVIEW_DIR}")


if __name__ == "__main__":
    main()
