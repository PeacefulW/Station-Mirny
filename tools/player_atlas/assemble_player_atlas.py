"""Pack one baked player clip into a single atlas PNG plus its metadata JSON.

Layout follows the direction contract the runtime already uses:
    row    = direction index, 0 = screen north,
             rows advance clockwise: N=0, E=4, S=8, W=12
    column = frame index within the clip

The metadata carries both the projected ground anchor and the measured foot
contact line, so the runtime never has to guess where the feet are or read
pixels to find out.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageStat

TOOL_DIR = Path(__file__).resolve().parent
DEFAULT_PROFILE = TOOL_DIR / "player_bake_profile.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("clip_id")
    parser.add_argument("frames_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE)
    parser.add_argument("--preview-width", type=int, default=2048)
    # Previews are review material, not game content. Writing them next to the
    # atlas would make Godot import them as real textures and pay VRAM for them.
    parser.add_argument("--preview-dir", type=Path, default=None)
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def visual_rgba(image: Image.Image) -> Image.Image:
    """Premultiply RGB so invisible pixels cannot create fake seam noise."""
    red, green, blue, alpha = image.convert("RGBA").split()
    return Image.merge(
        "RGBA",
        (
            ImageChops.multiply(red, alpha),
            ImageChops.multiply(green, alpha),
            ImageChops.multiply(blue, alpha),
            alpha,
        ),
    )


def frame_delta(first: Image.Image, second: Image.Image) -> float:
    difference = ImageChops.difference(first, second)
    channel_means = ImageStat.Stat(difference).mean
    return sum(channel_means) / (len(channel_means) * 255.0)


def loop_seam_report(direction_frames: dict[int, list[Image.Image]]) -> dict:
    internal_steps = []
    seam_steps = []
    direction_ratios = []
    for direction in sorted(direction_frames):
        frames = [visual_rgba(frame) for frame in direction_frames[direction]]
        direction_internal = [frame_delta(frames[index], frames[index + 1]) for index in range(len(frames) - 1)]
        seam = frame_delta(frames[-1], frames[0])
        internal_median = statistics.median(direction_internal)
        ratio = seam / internal_median if internal_median > 0.0 else (0.0 if seam == 0.0 else math.inf)
        internal_steps.extend(direction_internal)
        seam_steps.append(seam)
        direction_ratios.append(ratio)

    internal_median = statistics.median(internal_steps)
    seam_median = statistics.median(seam_steps)
    return {
        "internal_step_median": round(internal_median, 8),
        "internal_step_max": round(max(internal_steps), 8),
        "seam_median": round(seam_median, 8),
        "seam_max": round(max(seam_steps), 8),
        "median_seam_to_internal_median": round(
            seam_median / internal_median if internal_median > 0.0 else math.inf,
            5,
        ),
        "direction_seam_ratio_median": round(statistics.median(direction_ratios), 5),
        "direction_seam_ratio_max": round(max(direction_ratios), 5),
        "worst_direction": int(max(range(len(direction_ratios)), key=direction_ratios.__getitem__)),
    }


def write_cardinal_loop_preview(
    path: Path,
    cardinal_frames: dict[int, list[Image.Image]],
    frames_per_direction: int,
    frame_w: int,
    frame_h: int,
) -> None:
    labels = ((0, "N / row 0"), (4, "E / row 4"), (8, "S / row 8"), (12, "W / row 12"))
    header_h = 24
    animation_frames = []
    for frame_index in range(frames_per_direction):
        sheet = Image.new("RGB", (frame_w * len(labels), frame_h + header_h), (74, 58, 42))
        draw = ImageDraw.Draw(sheet)
        for column, (direction, label) in enumerate(labels):
            x = column * frame_w
            tile = cardinal_frames[direction][frame_index]
            backdrop = Image.new("RGBA", tile.size, (74, 58, 42, 255))
            composed = Image.alpha_composite(backdrop, tile).convert("RGB")
            sheet.paste(composed, (x, header_h))
            draw.text((x + 6, 5), label, fill=(245, 235, 215))
        animation_frames.append(sheet)
    animation_frames[0].save(
        path,
        save_all=True,
        append_images=animation_frames[1:],
        duration=125,
        loop=0,
        disposal=2,
    )


def main() -> None:
    args = parse_args()
    profile = load_json(args.profile)
    frames_dir = args.frames_dir.resolve()
    summary_path = frames_dir / f"{args.clip_id}_render_summary.json"
    if not summary_path.exists():
        raise SystemExit(f"Missing bake summary: {summary_path}")
    summary = load_json(summary_path)

    clip = next((item for item in profile["clips"] if item["clip_id"] == args.clip_id), None)
    if clip is None:
        raise SystemExit(f"Clip id '{args.clip_id}' is not declared in {args.profile}")
    for key in ("direction_zero", "direction_order"):
        if summary.get(key) != profile["grid"][key]:
            raise SystemExit(
                f"Bake summary {key}={summary.get(key)!r}, profile requires {profile['grid'][key]!r}"
            )

    directions = int(summary["directions"])
    frames_per_direction = int(summary["frames_per_direction"])
    frame_w = int(summary["frame_width_px"])
    frame_h = int(summary["frame_height_px"])

    atlas = Image.new("RGBA", (frame_w * frames_per_direction, frame_h * directions), (0, 0, 0, 0))
    missing: list[str] = []
    direction_frames: dict[int, list[Image.Image]] = {}
    for direction in range(directions):
        frames = []
        for frame_index in range(frames_per_direction):
            name = f"{args.clip_id}_dir{direction:02d}_frame{frame_index:02d}.png"
            path = frames_dir / name
            if not path.exists():
                missing.append(name)
                continue
            with Image.open(path) as source_image:
                tile = source_image.convert("RGBA")
            if tile.size != (frame_w, frame_h):
                raise SystemExit(f"{name} is {tile.size}, expected {(frame_w, frame_h)}")
            atlas.paste(tile, (frame_index * frame_w, direction * frame_h))
            frames.append(tile)
        direction_frames[direction] = frames
    if missing:
        # A hole in the grid becomes an invisible player on one facing. Fail.
        raise SystemExit(f"Bake is incomplete, {len(missing)} frames missing, first: {missing[:3]}")

    loop_report = None
    if bool(clip.get("loop", False)):
        loop_report = loop_seam_report(direction_frames)
        validation = profile["loop_validation"]
        direction_limit = float(validation["pixel_seam_to_direction_median_max"])
        median_limit = float(validation["pixel_median_seam_to_internal_median_max"])
        if loop_report["direction_seam_ratio_max"] > direction_limit:
            raise SystemExit(
                f"{args.clip_id} loop seam ratio {loop_report['direction_seam_ratio_max']:.3f} "
                f"at row {loop_report['worst_direction']} exceeds {direction_limit:.3f}"
            )
        if loop_report["median_seam_to_internal_median"] > median_limit:
            raise SystemExit(
                f"{args.clip_id} median loop seam ratio "
                f"{loop_report['median_seam_to_internal_median']:.3f} exceeds {median_limit:.3f}"
            )

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    stem = f"player_{args.clip_id}_{directions}dir_{frames_per_direction}frames"
    atlas_path = output_dir / f"{stem}.png"
    atlas.save(atlas_path)

    metadata = {
        "clip_id": args.clip_id,
        "spec": profile["spec"],
        "atlas": atlas_path.name,
        "directions": directions,
        "frames_per_direction": frames_per_direction,
        "frame_width_px": frame_w,
        "frame_height_px": frame_h,
        "atlas_width_px": atlas.width,
        "atlas_height_px": atlas.height,
        "direction_zero": profile["grid"]["direction_zero"],
        "direction_order": profile["grid"]["direction_order"],
        "direction_yaw_degrees": summary["direction_yaw_degrees"],
        "foot_anchor_uv": summary["foot_anchor_uv"],
        "ground_anchor_y_fraction": profile["frame"]["ground_anchor_y_fraction"],
        "figure_height_fraction": profile["frame"]["figure_height_fraction"],
        "ortho_scale": summary["ortho_scale"],
        "camera_elevation_degrees": summary["camera_elevation_degrees"],
        "sun_azimuth_degrees": summary["sun_azimuth_degrees"],
        "reference_clip": summary["reference_clip"],
        "reference_height_m": summary["reference_height_m"],
        "source_clip": summary["source_clip"],
        "source_frame_start": summary["source_frame_start"],
        "source_frame_end": summary["source_frame_end"],
        "sampled_source_frames": summary["sampled_source_frames"],
        "source_fps": summary["source_fps"],
        "source_cycle_duration_seconds": summary["source_cycle_duration_seconds"],
        "loop": summary["loop"],
        "loop_endpoint_pose": summary["loop_endpoint_pose"],
        "loop_pixel_seam": loop_report,
        "horizontal_travel_cancelled": summary["horizontal_travel_cancelled"],
        "foot_contact_uv_median": summary["foot_contact_uv_median"],
        "foot_contact_uv_max": summary["foot_contact_uv_max"],
    }
    (output_dir / f"{stem}.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    if args.preview_width > 0:
        preview_dir = (args.preview_dir or frames_dir).resolve()
        preview_dir.mkdir(parents=True, exist_ok=True)
        scale = args.preview_width / atlas.width
        preview = atlas.resize((args.preview_width, max(1, int(atlas.height * scale))), Image.LANCZOS)
        backdrop = Image.new("RGBA", preview.size, (74, 58, 42, 255))
        Image.alpha_composite(backdrop, preview).convert("RGB").save(preview_dir / f"{stem}_preview.png")
        if loop_report is not None and directions >= 13:
            cardinal_frames = {direction: direction_frames[direction] for direction in (0, 4, 8, 12)}
            write_cardinal_loop_preview(
                preview_dir / f"{stem}_cardinal_loop.gif",
                cardinal_frames,
                frames_per_direction,
                frame_w,
                frame_h,
            )

    print("PLAYER_ATLAS_ASSEMBLED")
    print(json.dumps({k: v for k, v in metadata.items() if k != "spec"}, indent=2))


if __name__ == "__main__":
    main()
