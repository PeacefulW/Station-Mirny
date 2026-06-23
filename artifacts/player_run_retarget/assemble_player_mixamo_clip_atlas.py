import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops


FRAME_PATTERN = re.compile(r"dir_(\d+)_(\d+)deg_frame_(\d+)\.png$")


def checkerboard(size: tuple[int, int], cell: int = 32) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    pixels = image.load()
    for y in range(size[1]):
        for x in range(size[0]):
            shade = 216 if ((x // cell) + (y // cell)) % 2 == 0 else 178
            pixels[x, y] = (shade, shade, shade, 255)
    return image


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    return image.getchannel("A").getbbox()


def bbox_size(bbox: tuple[int, int, int, int] | None) -> tuple[int, int]:
    if bbox is None:
        return (0, 0)
    return (bbox[2] - bbox[0], bbox[3] - bbox[1])


def motion_score(previous: Image.Image, current: Image.Image) -> int:
    diff = ImageChops.difference(previous.convert("L"), current.convert("L"))
    bbox = diff.getbbox()
    if bbox is None:
        return 0
    return int(diff.crop(bbox).resize((1, 1)).getpixel((0, 0)) * bbox_size(bbox)[0] * bbox_size(bbox)[1])


def collect_frames(frames_dir: Path, clip_id: str, rows: int, columns: int) -> list[list[Path]]:
    result: list[list[Path]] = [[] for _ in range(rows)]
    for path in sorted(frames_dir.glob(f"dir_*/*{clip_id}_dir_*_frame_*.png")):
        match = FRAME_PATTERN.search(path.name)
        if not match:
            continue
        direction = int(match.group(1))
        frame = int(match.group(3))
        if direction >= rows or frame >= columns:
            continue
        result[direction].append(path)
    for direction, paths in enumerate(result):
        paths.sort(key=lambda p: int(FRAME_PATTERN.search(p.name).group(3)))
        if len(paths) != columns:
            raise RuntimeError(f"Expected {columns} frames for direction {direction}, found {len(paths)} in {frames_dir}")
    return result


def save_preview(sheet: Image.Image, output_path: Path, checker: bool) -> None:
    preview = sheet.copy()
    preview.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
    if checker:
        checked = checkerboard(preview.size)
        checked.alpha_composite(preview)
        checked.save(output_path)
    else:
        preview.save(output_path)


def main() -> None:
    if len(sys.argv) != 10:
        raise SystemExit(
            "Usage: python assemble_player_mixamo_clip_atlas.py "
            "<clip_id> <source_fbx> <frames_dir> <artifact_sheet_512> "
            "<asset_sheet_256> <asset_json> <columns> <rows> <asset_frame_size>"
        )
    clip_id = sys.argv[1]
    source_fbx = Path(sys.argv[2])
    frames_dir = Path(sys.argv[3])
    artifact_sheet = Path(sys.argv[4])
    asset_sheet = Path(sys.argv[5])
    asset_json = Path(sys.argv[6])
    columns = int(sys.argv[7])
    rows = int(sys.argv[8])
    asset_frame_size = int(sys.argv[9])

    frame_paths = collect_frames(frames_dir, clip_id, rows, columns)
    first = Image.open(frame_paths[0][0]).convert("RGBA")
    render_frame_size = first.size[0]
    if first.size[0] != first.size[1]:
        raise RuntimeError(f"Expected square frames, got {first.size}")

    artifact = Image.new("RGBA", (columns * render_frame_size, rows * render_frame_size), (0, 0, 0, 0))
    asset = Image.new("RGBA", (columns * asset_frame_size, rows * asset_frame_size), (0, 0, 0, 0))

    frames = []
    direction_summaries = []
    all_bbox_widths = []
    all_bbox_heights = []
    total_nonempty = 0
    motion_scores = []
    # Per-frame feet contact line (UV) for the sun-shadow re-grounding.
    # dir-major: idx = direction * columns + frame; uv = bottom-of-alpha / frame_size.
    frame_contact_uv = []
    for direction, paths in enumerate(frame_paths):
        previous = None
        direction_nonempty = 0
        direction_motion_scores = []
        for frame_index, path in enumerate(paths):
            image = Image.open(path).convert("RGBA")
            if image.size != first.size:
                raise RuntimeError(f"Frame size mismatch: {path} is {image.size}, expected {first.size}")
            resized = image.resize((asset_frame_size, asset_frame_size), Image.Resampling.LANCZOS)
            bbox = alpha_bbox(resized)
            bbox_w, bbox_h = bbox_size(bbox)
            if bbox is not None:
                total_nonempty += 1
                direction_nonempty += 1
                all_bbox_widths.append(bbox_w)
                all_bbox_heights.append(bbox_h)
            if previous is not None:
                score = motion_score(previous, image)
                motion_scores.append(score)
                direction_motion_scores.append(score)
            previous = image

            artifact_x = frame_index * render_frame_size
            artifact_y = direction * render_frame_size
            artifact.paste(image, (artifact_x, artifact_y), image)

            asset_x = frame_index * asset_frame_size
            asset_y = direction * asset_frame_size
            asset.paste(resized, (asset_x, asset_y), resized)

            frames.append(
                {
                    "direction": direction,
                    "frame": frame_index,
                    "source_file": str(path),
                    "artifact_rect": [artifact_x, artifact_y, render_frame_size, render_frame_size],
                    "asset_rect": [asset_x, asset_y, asset_frame_size, asset_frame_size],
                    "alpha_bbox": list(bbox) if bbox else None,
                }
            )
            frame_contact_uv.append(
                round((bbox[3] if bbox else asset_frame_size) / asset_frame_size, 4)
            )
        direction_summaries.append(
            {
                "direction": direction,
                "nonempty_frames": direction_nonempty,
                "min_motion_score_between_adjacent_frames": min(direction_motion_scores) if direction_motion_scores else 0,
                "max_motion_score_between_adjacent_frames": max(direction_motion_scores) if direction_motion_scores else 0,
            }
        )

    artifact_sheet.parent.mkdir(parents=True, exist_ok=True)
    asset_sheet.parent.mkdir(parents=True, exist_ok=True)
    asset_json.parent.mkdir(parents=True, exist_ok=True)
    artifact.save(artifact_sheet)
    asset.save(asset_sheet)

    preview = artifact_sheet.with_name(artifact_sheet.stem + "_preview_2048.png")
    checker_preview = artifact_sheet.with_name(artifact_sheet.stem + "_checker_preview_2048.png")
    save_preview(artifact, preview, False)
    save_preview(artifact, checker_preview, True)

    metadata = {
        "clip_id": clip_id,
        "source": str(source_fbx),
        "artifact_sheet": str(artifact_sheet),
        "artifact_preview_2048": str(preview),
        "artifact_checker_preview_2048": str(checker_preview),
        "atlas": str(asset_sheet),
        "columns": columns,
        "rows": rows,
        "directions": rows,
        "frames_per_direction": columns,
        "frame_size_px": asset_frame_size,
        "render_frame_size_px": render_frame_size,
        "total_frames": rows * columns,
        "nonempty_frames": total_nonempty,
        "average_alpha_bbox_px": [
            round(sum(all_bbox_widths) / len(all_bbox_widths), 2) if all_bbox_widths else 0.0,
            round(sum(all_bbox_heights) / len(all_bbox_heights), 2) if all_bbox_heights else 0.0,
        ],
        "max_alpha_bbox_px": [max(all_bbox_widths) if all_bbox_widths else 0, max(all_bbox_heights) if all_bbox_heights else 0],
        "motion_adjacent_pairs_checked": len(motion_scores),
        "min_motion_score_between_adjacent_frames": min(motion_scores) if motion_scores else 0,
        "max_motion_score_between_adjacent_frames": max(motion_scores) if motion_scores else 0,
        "direction_summaries": direction_summaries,
        "frame_contact_uv": frame_contact_uv,
        "frame_contact_index": "dir-major: idx = direction*16 + frame; uv = bottom-of-alpha / frame_size",
        "frames": frames,
        "usage": "Player visual-only Mixamo clip atlas generated offline for Station Mirny.",
    }
    asset_json.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    artifact_sheet.with_suffix(".json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    print("PLAYER_MIXAMO_CLIP_ATLAS_ASSEMBLED")
    print(json.dumps({k: v for k, v in metadata.items() if k not in ("frames", "direction_summaries")}, indent=2))


if __name__ == "__main__":
    main()
