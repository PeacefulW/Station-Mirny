#!/usr/bin/env python3
"""Convert Cliff Forge recipe + PNG exports into Godot .tres resources."""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


AUTOTILE_CASE_COUNT = 47
DEFAULT_TILE_SIZE = 64
DEFAULT_VARIANT_COUNT = 6
DECAL_COLUMNS = 4
DECAL_ROWS = 4

SHAPE_SET_SCRIPT = "res://data/terrain/terrain_shape_set.gd"
MATERIAL_SET_SCRIPT = "res://data/terrain/terrain_material_set.gd"
DEFAULT_SHADER_FAMILY_ID = "terrain.ground_hybrid"

SNAKE_CASE_RE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")


class BridgeError(RuntimeError):
    pass


@dataclass(frozen=True)
class BridgeOutput:
    path: Path
    content: str


@dataclass(frozen=True)
class BridgeContext:
    recipe_path: Path
    asset_dir: Path
    target_dir: Path
    project_root: Path
    recipe: dict[str, Any]
    request: dict[str, Any]
    asset_name: str
    mode: str
    tile_size_px: int
    variant_count: int
    shader_family_id: str


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert a Cliff Forge recipe and exported PNGs into Godot .tres resources."
    )
    parser.add_argument("recipe", type=Path, help="Path to the exported *_recipe.json file.")
    parser.add_argument(
        "--asset-dir",
        type=Path,
        default=None,
        help="Folder containing the exported PNG/metadata set. Defaults to the recipe folder.",
    )
    parser.add_argument(
        "--target",
        type=Path,
        required=True,
        help="Target data/terrain folder. Outputs are written into shape_sets/, material_sets/, decals/, or silhouettes/.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path.cwd(),
        help="Godot project root used to convert texture paths into res:// paths. Defaults to cwd.",
    )
    parser.add_argument(
        "--mode",
        default="auto",
        help="Override recipe mode: auto, Full47, BaseVariantsOnly, MaskOnly, Decals, or Silhouettes.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned .tres resources without writing files.",
    )

    args = parser.parse_args(argv)
    try:
        context = load_context(args)
        outputs = plan_outputs(context)
        if args.dry_run:
            print_dry_run(outputs)
        else:
            write_outputs(outputs)
    except BridgeError as exc:
        print(f"recipe_to_tres error: {exc}", file=sys.stderr)
        return 1
    return 0


def load_context(args: argparse.Namespace) -> BridgeContext:
    recipe_path = args.recipe.resolve()
    if not recipe_path.exists():
        raise BridgeError(f"missing recipe file: {recipe_path}")

    try:
        recipe = json.loads(recipe_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise BridgeError(f"invalid JSON in {recipe_path}: {exc}") from exc

    if not isinstance(recipe, dict):
        raise BridgeError(f"recipe root must be a JSON object: {recipe_path}")

    request = recipe.get("request")
    if not isinstance(request, dict):
        request = recipe

    asset_dir = (args.asset_dir or recipe_path.parent).resolve()
    if not asset_dir.exists():
        raise BridgeError(f"missing asset folder: {asset_dir}")

    project_root = args.project_root.resolve()
    target_dir = args.target.resolve()

    asset_name = string_field(recipe, request, "asset_name")
    if not asset_name:
        asset_name = derive_asset_name_from_recipe(recipe_path)
    validate_asset_name(asset_name)

    mode = normalize_mode(args.mode)
    if mode == "auto":
        mode = normalize_mode(string_field(recipe, request, "export_mode") or "Full47")

    tile_size_px = int_field(recipe, request, ("tile_size_px", "tile_size"), DEFAULT_TILE_SIZE)
    variant_count = int_field(
        recipe,
        request,
        ("variant_count", "variants", "autotile_variant_count"),
        DEFAULT_VARIANT_COUNT,
    )
    shader_family_id = (
        string_field(recipe, request, "shader_family_id") or DEFAULT_SHADER_FAMILY_ID
    )

    if tile_size_px <= 0:
        raise BridgeError(f"tile_size_px must be positive, got {tile_size_px}")
    if variant_count <= 0:
        raise BridgeError(f"variant_count must be positive, got {variant_count}")

    return BridgeContext(
        recipe_path=recipe_path,
        asset_dir=asset_dir,
        target_dir=target_dir,
        project_root=project_root,
        recipe=recipe,
        request=request,
        asset_name=asset_name,
        mode=mode,
        tile_size_px=tile_size_px,
        variant_count=variant_count,
        shader_family_id=shader_family_id,
    )


def normalize_mode(mode: str) -> str:
    key = mode.strip().lower().replace("-", "").replace("_", "")
    aliases = {
        "auto": "auto",
        "full47": "Full47",
        "basevariantsonly": "BaseVariantsOnly",
        "basevariants": "BaseVariantsOnly",
        "maskonly": "MaskOnly",
        "mask": "MaskOnly",
        "decal": "Decals",
        "decals": "Decals",
        "terraindecalatlas": "Decals",
        "silhouette": "Silhouettes",
        "silhouettes": "Silhouettes",
        "mountainsilhouette": "Silhouettes",
    }
    try:
        return aliases[key]
    except KeyError as exc:
        raise BridgeError(
            f"unsupported mode '{mode}'. Expected auto, Full47, BaseVariantsOnly, MaskOnly, Decals, or Silhouettes."
        ) from exc


def plan_outputs(context: BridgeContext) -> list[BridgeOutput]:
    if context.mode == "Full47":
        return [
            build_shape_set(context, require_shape_normal=True),
            build_material_set(context, require_full_material=True, prefer_base_atlas=False),
        ]
    if context.mode == "BaseVariantsOnly":
        return [
            build_material_set(context, require_full_material=False, prefer_base_atlas=True),
        ]
    if context.mode == "MaskOnly":
        return [
            build_shape_set(context, require_shape_normal=False),
        ]
    if context.mode == "Decals":
        return [build_decal_atlas(context)]
    if context.mode == "Silhouettes":
        return [build_silhouette_set(context)]
    raise BridgeError(f"unsupported normalized mode: {context.mode}")


def build_shape_set(context: BridgeContext, require_shape_normal: bool) -> BridgeOutput:
    mask_path = find_png(context, ("atlas_mask", "mask_atlas"), "mask atlas")
    validate_png_dimensions(
        mask_path,
        AUTOTILE_CASE_COUNT * context.tile_size_px,
        context.variant_count * context.tile_size_px,
        "autotile_47 mask atlas",
    )

    if require_shape_normal:
        normal_path = find_png(
            context,
            ("atlas_normal", "atlas_shape_normal", "shape_normal_atlas"),
            "shape normal atlas",
        )
        validate_png_dimensions(
            normal_path,
            AUTOTILE_CASE_COUNT * context.tile_size_px,
            context.variant_count * context.tile_size_px,
            "autotile_47 shape normal atlas",
        )
    else:
        normal_path = mask_path

    ext_resources = [
        ("Script", SHAPE_SET_SCRIPT),
        ("Texture2D", to_res_path(mask_path, context.project_root)),
    ]
    normal_id = "2"
    if normal_path != mask_path:
        ext_resources.append(("Texture2D", to_res_path(normal_path, context.project_root)))
        normal_id = "3"

    content = "\n".join(
        [
            gd_header("TerrainShapeSet", len(ext_resources)),
            render_ext_resources(ext_resources),
            "[resource]",
            'script = ExtResource("1")',
            f"id = {gd_string_name(f'terrain:{context.asset_name}_shape_set')}",
            'topology_family_id = &"autotile_47"',
            'mask_atlas = ExtResource("2")',
            f'shape_normal_atlas = ExtResource("{normal_id}")',
            f"tile_size_px = {context.tile_size_px}",
            f"case_count = {AUTOTILE_CASE_COUNT}",
            f"variant_count = {context.variant_count}",
            "",
        ]
    )
    return BridgeOutput(
        context.target_dir / "shape_sets" / f"{context.asset_name}_shape_set.tres",
        content,
    )


def build_material_set(
    context: BridgeContext,
    *,
    require_full_material: bool,
    prefer_base_atlas: bool,
) -> BridgeOutput:
    texture_paths = collect_material_textures(
        context,
        require_full_material=require_full_material,
        prefer_base_atlas=prefer_base_atlas,
    )

    if prefer_base_atlas:
        base_atlas = texture_paths.get("top_albedo")
        if base_atlas is not None and base_atlas.name.endswith("atlas_albedo.png"):
            validate_png_dimensions(
                base_atlas,
                context.tile_size_px,
                context.variant_count * context.tile_size_px,
                "base variant atlas",
            )

    ext_resources: list[tuple[str, str]] = [("Script", MATERIAL_SET_SCRIPT)]
    slot_resource_ids: dict[str, str] = {}
    for slot in (
        "top_albedo",
        "face_albedo",
        "top_modulation",
        "face_modulation",
        "top_normal",
        "face_normal",
    ):
        path = texture_paths.get(slot)
        if path is None:
            continue
        ext_resources.append(("Texture2D", to_res_path(path, context.project_root)))
        slot_resource_ids[slot] = str(len(ext_resources))

    resource_lines = [
        "[resource]",
        'script = ExtResource("1")',
        f"id = {gd_string_name(f'terrain:{context.asset_name}_material_set')}",
        f"shader_family_id = {gd_string_name(context.shader_family_id)}",
    ]
    for slot in (
        "top_albedo",
        "face_albedo",
        "top_modulation",
        "face_modulation",
        "top_normal",
        "face_normal",
    ):
        resource_id = slot_resource_ids.get(slot)
        if resource_id is not None:
            resource_lines.append(f'{slot} = ExtResource("{resource_id}")')

    sampling_params = dict_field(context.recipe, context.request, "sampling_params")
    resource_lines.append(f"sampling_params = {format_dictionary(sampling_params)}")
    resource_lines.append("")

    content = "\n".join(
        [
            gd_header("TerrainMaterialSet", len(ext_resources)),
            render_ext_resources(ext_resources),
            *resource_lines,
        ]
    )
    return BridgeOutput(
        context.target_dir / "material_sets" / f"{context.asset_name}_material_set.tres",
        content,
    )


def collect_material_textures(
    context: BridgeContext,
    *,
    require_full_material: bool,
    prefer_base_atlas: bool,
) -> dict[str, Path | None]:
    top_albedo_aliases = (
        ("atlas_albedo", "base_albedo", "top_albedo")
        if prefer_base_atlas
        else ("top_albedo", "atlas_albedo", "base_albedo")
    )
    aliases_by_slot: dict[str, tuple[str, ...]] = {
        "top_albedo": top_albedo_aliases,
        "face_albedo": ("face_albedo", "atlas_albedo", "base_albedo"),
        "top_modulation": ("top_modulation", "atlas_modulation"),
        "face_modulation": ("face_modulation", "top_modulation", "atlas_modulation"),
        "top_normal": ("top_normal",),
        "face_normal": ("face_normal", "top_normal"),
    }

    texture_paths: dict[str, Path | None] = {}
    missing: list[str] = []
    for slot, aliases in aliases_by_slot.items():
        path = find_png(context, aliases, slot, required=False)
        texture_paths[slot] = path
        if path is None and (require_full_material or slot == "top_albedo"):
            missing.append(slot)

    if missing:
        raise BridgeError(
            "missing required material texture(s): "
            + ", ".join(missing)
            + f" for asset '{context.asset_name}' in {context.asset_dir}"
        )

    return texture_paths


def build_decal_atlas(context: BridgeContext) -> BridgeOutput:
    atlas_path = find_png(context, ("decal_atlas",), "decal atlas")
    metadata_path = find_json(context, "decal_metadata", "decal metadata")
    metadata = load_json_object(metadata_path, "decal metadata")

    columns = int(metadata.get("atlas_columns", DECAL_COLUMNS))
    rows = int(metadata.get("atlas_rows", DECAL_ROWS))
    cell_size_px = int(metadata.get("cell_size_px", 0))
    cells = metadata.get("cells")
    if columns != DECAL_COLUMNS or rows != DECAL_ROWS:
        raise BridgeError(
            f"{metadata_path.name} must describe a 4 x 4 decal atlas, got {columns} x {rows}"
        )
    if not isinstance(cells, list) or len(cells) != DECAL_COLUMNS * DECAL_ROWS:
        actual = len(cells) if isinstance(cells, list) else "missing"
        raise BridgeError(
            f"{metadata_path.name} must contain 16 decal cells, got {actual}"
        )

    width, height = png_dimensions(atlas_path)
    if cell_size_px <= 0:
        if width % columns != 0 or height % rows != 0:
            raise BridgeError(
                f"{atlas_path.name} atlas dimensions {width}x{height} cannot infer a regular 4 x 4 cell size"
            )
        cell_size_px = width // columns
    validate_png_dimensions(
        atlas_path,
        columns * cell_size_px,
        rows * cell_size_px,
        "4 x 4 decal atlas",
    )

    texture_res_path = to_res_path(atlas_path, context.project_root)
    content = "\n".join(
        [
            '[gd_resource type="Resource" load_steps=2 format=3]',
            "",
            f'[ext_resource type="Texture2D" path={gd_quote(texture_res_path)} id="1"]',
            "",
            "[resource]",
            f'resource_name = {gd_quote(f"{context.asset_name}_terrain_decal_atlas")}',
            'metadata/resource_class = "TerrainDecalAtlas"',
            'metadata/texture = ExtResource("1")',
            f"metadata/texture_path = {gd_quote(texture_res_path)}",
            f"metadata/atlas_columns = {columns}",
            f"metadata/atlas_rows = {rows}",
            f"metadata/cell_size_px = {cell_size_px}",
            "metadata/cells = " + format_decal_cells(cells),
            "",
        ]
    )
    return BridgeOutput(
        context.target_dir / "decals" / f"{context.asset_name}_atlas.tres",
        content,
    )


def build_silhouette_set(context: BridgeContext) -> BridgeOutput:
    atlas_path = find_png(context, ("silhouette_atlas",), "silhouette atlas")
    metadata_path = find_json(context, "silhouette_metadata", "silhouette metadata")
    metadata = load_json_object(metadata_path, "silhouette metadata")

    tile_size_px = int(metadata.get("tile_size_px", context.tile_size_px))
    silhouette_height_px = int(
        metadata.get("silhouette_height_px", metadata.get("sprite_height_px", 96))
    )
    variant_count = int(metadata.get("variant_count", metadata.get("variants", 3)))
    directions = metadata.get("directions")
    if not isinstance(directions, list) or not directions:
        has_corner_sprites = bool(metadata.get("has_corner_sprites", True))
        directions = (
            ["N", "E", "S", "W", "NE", "SE", "SW", "NW"]
            if has_corner_sprites
            else ["N", "E", "S", "W"]
        )
    else:
        directions = [str(direction) for direction in directions]
        has_corner_sprites = bool(
            metadata.get(
                "has_corner_sprites",
                any(direction in {"NE", "SE", "SW", "NW"} for direction in directions),
            )
        )

    if tile_size_px <= 0 or silhouette_height_px <= 0 or variant_count <= 0:
        raise BridgeError(f"{metadata_path.name} has invalid silhouette layout values")

    case_count = len(directions)
    expected_width = variant_count * tile_size_px
    expected_height = case_count * silhouette_height_px
    validate_png_dimensions(
        atlas_path,
        expected_width,
        expected_height,
        "mountain silhouette atlas",
    )

    topology_family_id = (
        "mountain_silhouette_cardinal_corner"
        if has_corner_sprites
        else "mountain_silhouette_cardinal"
    )
    texture_res_path = to_res_path(atlas_path, context.project_root)
    ext_resources = [
        ("Script", SHAPE_SET_SCRIPT),
        ("Texture2D", texture_res_path),
    ]
    content = "\n".join(
        [
            gd_header("TerrainShapeSet", len(ext_resources)),
            render_ext_resources(ext_resources),
            "[resource]",
            'script = ExtResource("1")',
            f"id = {gd_string_name(f'terrain:{context.asset_name}_silhouette')}",
            f"topology_family_id = {gd_string_name(topology_family_id)}",
            'mask_atlas = ExtResource("2")',
            f"tile_size_px = {tile_size_px}",
            f"case_count = {case_count}",
            f"variant_count = {variant_count}",
            f"metadata/texture_path = {gd_quote(texture_res_path)}",
            f"metadata/silhouette_height_px = {silhouette_height_px}",
            f"metadata/has_corner_sprites = {format_bool(has_corner_sprites)}",
            "metadata/directions = " + format_array([str(direction) for direction in directions]),
            "",
        ]
    )
    return BridgeOutput(
        context.target_dir / "silhouettes" / f"{context.asset_name}.tres",
        content,
    )


def find_png(
    context: BridgeContext,
    aliases: tuple[str, ...],
    label: str,
    *,
    required: bool = True,
) -> Path | None:
    tried: list[Path] = []
    for alias in aliases:
        for name in (f"{context.asset_name}_{alias}.png", f"{alias}.png"):
            candidate = context.asset_dir / name
            tried.append(candidate)
            if candidate.exists():
                return candidate
    if required:
        tried_text = ", ".join(path.name for path in tried)
        raise BridgeError(
            f"missing required {label} for asset '{context.asset_name}' in {context.asset_dir}; tried {tried_text}"
        )
    return None


def find_json(context: BridgeContext, alias: str, label: str) -> Path:
    tried = [
        context.asset_dir / f"{context.asset_name}_{alias}.json",
        context.asset_dir / f"{alias}.json",
    ]
    for candidate in tried:
        if candidate.exists():
            return candidate
    tried_text = ", ".join(path.name for path in tried)
    raise BridgeError(
        f"missing required {label} for asset '{context.asset_name}' in {context.asset_dir}; tried {tried_text}"
    )


def validate_png_dimensions(path: Path, expected_width: int, expected_height: int, label: str) -> None:
    width, height = png_dimensions(path)
    if width != expected_width or height != expected_height:
        raise BridgeError(
            f"{path.name} atlas dimensions are {width}x{height}; expected "
            f"{expected_width}x{expected_height} for {label}"
        )


def png_dimensions(path: Path) -> tuple[int, int]:
    if not path.exists():
        raise BridgeError(f"missing PNG file: {path}")
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise BridgeError(f"{path.name} is not a valid PNG file")
    return struct.unpack(">II", header[16:24])


def to_res_path(path: Path, project_root: Path) -> str:
    resolved_path = path.resolve()
    resolved_root = project_root.resolve()
    try:
        relative = resolved_path.relative_to(resolved_root)
    except ValueError as exc:
        raise BridgeError(
            f"{resolved_path} is outside project root {resolved_root}; cannot write res:// path"
        ) from exc
    return "res://" + relative.as_posix()


def gd_header(script_class: str, ext_resource_count: int) -> str:
    load_steps = ext_resource_count + 1
    return f'[gd_resource type="Resource" script_class="{script_class}" load_steps={load_steps} format=3]\n'


def render_ext_resources(ext_resources: list[tuple[str, str]]) -> str:
    lines = []
    for index, (resource_type, path) in enumerate(ext_resources, start=1):
        lines.append(
            f'[ext_resource type="{resource_type}" path={gd_quote(path)} id="{index}"]'
        )
    lines.append("")
    return "\n".join(lines)


def gd_quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def gd_string_name(value: str) -> str:
    return "&" + gd_quote(value)


def format_dictionary(value: dict[str, Any]) -> str:
    if not value:
        return "{}"
    lines = ["{"]
    items = list(value.items())
    for index, (key, item) in enumerate(items):
        comma = "," if index < len(items) - 1 else ""
        lines.append(f"{gd_quote(str(key))}: {format_value(item)}{comma}")
    lines.append("}")
    return "\n".join(lines)


def format_array(values: list[Any]) -> str:
    return "[" + ", ".join(format_value(value) for value in values) + "]"


def format_value(value: Any) -> str:
    if isinstance(value, bool):
        return format_bool(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return format_float(value)
    if isinstance(value, str):
        return gd_quote(value)
    if isinstance(value, list):
        return format_array(value)
    if isinstance(value, dict):
        return format_dictionary(value)
    if value is None:
        return "null"
    return gd_quote(str(value))


def format_bool(value: bool) -> str:
    return "true" if value else "false"


def format_float(value: float) -> str:
    text = f"{value:.6f}".rstrip("0").rstrip(".")
    return text if text else "0"


def format_vector2(x: float, y: float) -> str:
    return f"Vector2({format_float(x)}, {format_float(y)})"


def format_decal_cells(cells: list[Any]) -> str:
    rendered_cells: list[str] = []
    for index, cell in enumerate(cells):
        if not isinstance(cell, dict):
            raise BridgeError(f"decal cell {index} must be an object")
        cell_index = int(cell.get("index", index))
        size_class = cell.get("size_class", "small")
        pivot_x, pivot_y = normalize_pivot(cell.get("pivot", [0.5, 0.5]))

        lines = [
            "{",
            f"{gd_quote('index')}: {cell_index},",
            f"{gd_quote('size_class')}: {gd_quote(str(size_class))},",
            f"{gd_quote('pivot')}: {format_vector2(pivot_x, pivot_y)}",
        ]
        if "source_recipe_summary" in cell:
            lines[-1] += ","
            lines.append(
                f"{gd_quote('source_recipe_summary')}: {format_value(cell['source_recipe_summary'])}"
            )
        rendered_cells.append("\n".join(lines + ["}"]))
    return "[" + ", ".join(rendered_cells) + "]"


def normalize_pivot(value: Any) -> tuple[float, float]:
    if isinstance(value, list) and len(value) == 2:
        return float(value[0]), float(value[1])
    if isinstance(value, tuple) and len(value) == 2:
        return float(value[0]), float(value[1])
    if isinstance(value, dict):
        if "x" in value and "y" in value:
            return float(value["x"]), float(value["y"])
        if "0" in value and "1" in value:
            return float(value["0"]), float(value["1"])
    if isinstance(value, str):
        key = value.strip().lower().replace("-", "_").replace(" ", "_")
        named = {
            "center": (0.5, 0.5),
            "centre": (0.5, 0.5),
            "bottom_center": (0.5, 1.0),
            "bottom_centre": (0.5, 1.0),
            "top_center": (0.5, 0.0),
            "top_centre": (0.5, 0.0),
        }
        if key in named:
            return named[key]
    raise BridgeError(f"unsupported pivot value: {value!r}")


def print_dry_run(outputs: list[BridgeOutput]) -> None:
    for output in outputs:
        print(f"--- {output.path} ---")
        print(output.content, end="" if output.content.endswith("\n") else "\n")


def write_outputs(outputs: list[BridgeOutput]) -> None:
    for output in outputs:
        output.path.parent.mkdir(parents=True, exist_ok=True)
        output.path.write_text(output.content, encoding="utf-8", newline="\n")
        print(f"Wrote {output.path}")


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise BridgeError(f"invalid JSON in {label} file {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise BridgeError(f"{label} file must contain a JSON object: {path}")
    return value


def string_field(recipe: dict[str, Any], request: dict[str, Any], name: str) -> str:
    for source in (request, recipe):
        value = source.get(name)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def int_field(
    recipe: dict[str, Any],
    request: dict[str, Any],
    names: tuple[str, ...],
    default: int,
) -> int:
    for source in (request, recipe):
        for name in names:
            value = source.get(name)
            if value is None:
                continue
            try:
                return int(value)
            except (TypeError, ValueError) as exc:
                raise BridgeError(f"{name} must be an integer, got {value!r}") from exc
    return default


def dict_field(recipe: dict[str, Any], request: dict[str, Any], name: str) -> dict[str, Any]:
    for source in (request, recipe):
        value = source.get(name)
        if isinstance(value, dict):
            return value
    return {}


def derive_asset_name_from_recipe(recipe_path: Path) -> str:
    stem = recipe_path.stem
    if stem.endswith("_recipe"):
        stem = stem[: -len("_recipe")]
    return stem


def validate_asset_name(asset_name: str) -> None:
    if not SNAKE_CASE_RE.match(asset_name):
        raise BridgeError(
            f"asset_name must be non-empty snake_case, got {asset_name!r}"
        )


if __name__ == "__main__":
    raise SystemExit(main())
