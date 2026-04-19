from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SPRITES_DIR = ROOT / "assets" / "sprites" / "terrain"
TEXTURES_DIR = ROOT / "assets" / "textures" / "terrain"

TILE_SIZE = 32
CASE_COUNT = 47
VARIANT_COUNT = 6
ATLAS_COLUMNS = 8
ATLAS_ROWS = math.ceil((CASE_COUNT * VARIANT_COUNT) / ATLAS_COLUMNS)
MASK_ATLAS_NAME = "plain_rock_mask_atlas.png"
SHAPE_NORMAL_ATLAS_NAME = "plain_rock_shape_normal_atlas.png"
TOP_MOD_NAME = "rock_top_modulation.png"
FACE_MOD_NAME = "rock_face_modulation.png"
TOP_NORMAL_NAME = "rock_top_normal.png"
FACE_NORMAL_NAME = "rock_face_normal.png"


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge0 == edge1:
        return 0.0
    t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def splitmix64(value: int) -> int:
    value = (value + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9 & 0xFFFFFFFFFFFFFFFF
    value = (value ^ (value >> 27)) * 0x94D049BB133111EB & 0xFFFFFFFFFFFFFFFF
    return (value ^ (value >> 31)) & 0xFFFFFFFFFFFFFFFF


def hash2d(x: int, y: int, seed: int) -> float:
    value = splitmix64(seed)
    value = splitmix64(value ^ (x * 0x9E3779B185EBCA87))
    value = splitmix64(value ^ (y * 0xC2B2AE3D27D4EB4F))
    return (value & 0xFFFFFFFF) / 0xFFFFFFFF


def value_noise(x: float, y: float, seed: int) -> float:
    x0 = math.floor(x)
    y0 = math.floor(y)
    tx = x - x0
    ty = y - y0
    sx = tx * tx * (3.0 - 2.0 * tx)
    sy = ty * ty * (3.0 - 2.0 * ty)
    n00 = hash2d(x0, y0, seed)
    n10 = hash2d(x0 + 1, y0, seed)
    n01 = hash2d(x0, y0 + 1, seed)
    n11 = hash2d(x0 + 1, y0 + 1, seed)
    ix0 = n00 + (n10 - n00) * sx
    ix1 = n01 + (n11 - n01) * sx
    return ix0 + (ix1 - ix0) * sy


def value_noise_periodic(x: float, y: float, seed: int, period_x: int, period_y: int) -> float:
    safe_period_x = max(1, period_x)
    safe_period_y = max(1, period_y)
    x0 = math.floor(x)
    y0 = math.floor(y)
    tx = x - x0
    ty = y - y0
    sx = tx * tx * (3.0 - 2.0 * tx)
    sy = ty * ty * (3.0 - 2.0 * ty)
    wx0 = x0 % safe_period_x
    wy0 = y0 % safe_period_y
    wx1 = (x0 + 1) % safe_period_x
    wy1 = (y0 + 1) % safe_period_y
    n00 = hash2d(wx0, wy0, seed)
    n10 = hash2d(wx1, wy0, seed)
    n01 = hash2d(wx0, wy1, seed)
    n11 = hash2d(wx1, wy1, seed)
    ix0 = n00 + (n10 - n00) * sx
    ix1 = n01 + (n11 - n01) * sx
    return ix0 + (ix1 - ix0) * sy


def fbm(x: float, y: float, octaves: int, seed: int) -> float:
    amplitude = 0.5
    frequency = 1.0
    total = 0.0
    norm = 0.0
    for octave in range(octaves):
        total += value_noise(x * frequency, y * frequency, seed + octave * 101) * amplitude
        norm += amplitude
        amplitude *= 0.5
        frequency *= 2.0
    return total / max(norm, 1e-6)


def fbm_periodic(x: float, y: float, octaves: int, seed: int, period_x: int, period_y: int) -> float:
    amplitude = 0.5
    frequency = 1.0
    total = 0.0
    norm = 0.0
    for octave in range(octaves):
        total += value_noise_periodic(
            x * frequency,
            y * frequency,
            seed + octave * 101,
            max(1, round(period_x * frequency)),
            max(1, round(period_y * frequency)),
        ) * amplitude
        norm += amplitude
        amplitude *= 0.5
        frequency *= 2.0
    return total / max(norm, 1e-6)


def ridge_noise(x: float, y: float, octaves: int, seed: int) -> float:
    value = fbm(x, y, octaves, seed)
    return 1.0 - abs(value * 2.0 - 1.0)


def ridge_noise_periodic(x: float, y: float, octaves: int, seed: int, period_x: int, period_y: int) -> float:
    value = fbm_periodic(x, y, octaves, seed, period_x, period_y)
    return 1.0 - abs(value * 2.0 - 1.0)


def count_bits(value: int) -> int:
    count = 0
    bits = value
    while bits:
        count += bits & 1
        bits >>= 1
    return count


def build_signature_code(n: bool, ne: bool, e: bool, se: bool, s: bool, sw: bool, w: bool, nw: bool) -> int:
    open_n = 0 if n else 1
    open_e = 0 if e else 1
    open_s = 0 if s else 1
    open_w = 0 if w else 1
    notch_ne = 1 if n and e and not ne else 0
    notch_se = 1 if s and e and not se else 0
    notch_sw = 1 if s and w and not sw else 0
    notch_nw = 1 if n and w and not nw else 0
    return (
        (open_n << 7)
        | (open_e << 6)
        | (open_s << 5)
        | (open_w << 4)
        | (notch_ne << 3)
        | (notch_se << 2)
        | (notch_sw << 1)
        | notch_nw
    )


def build_catalog() -> list[int]:
    seen: set[int] = set()
    entries: list[tuple[int, int, int]] = []
    for mask in range(256):
        code = build_signature_code(
            bool(mask & 1),
            bool(mask & 2),
            bool(mask & 4),
            bool(mask & 8),
            bool(mask & 16),
            bool(mask & 32),
            bool(mask & 64),
            bool(mask & 128),
        )
        if code in seen:
            continue
        seen.add(code)
        entries.append((code, count_bits((code >> 4) & 0x0F), count_bits(code & 0x0F)))
    entries.sort(key=lambda item: (item[1], item[2], item[0]))
    catalog = [code for code, _edges, _notches in entries]
    if len(catalog) != CASE_COUNT:
        raise RuntimeError(f"Expected {CASE_COUNT} catalog entries, got {len(catalog)}")
    return catalog


@dataclass(frozen=True)
class Signature:
    code: int
    open_n: bool
    open_e: bool
    open_s: bool
    open_w: bool
    notch_ne: bool
    notch_se: bool
    notch_sw: bool
    notch_nw: bool


@dataclass(frozen=True)
class Sample:
    zone: str
    left: float
    right: float
    top: float
    bottom: float


@dataclass(frozen=True)
class Overlay:
    kind: str
    width: int
    height: int


def decode_signature(code: int) -> Signature:
    return Signature(
        code=code,
        open_n=bool((code >> 7) & 1),
        open_e=bool((code >> 6) & 1),
        open_s=bool((code >> 5) & 1),
        open_w=bool((code >> 4) & 1),
        notch_ne=bool((code >> 3) & 1),
        notch_se=bool((code >> 2) & 1),
        notch_sw=bool((code >> 1) & 1),
        notch_nw=bool(code & 1),
    )


def smooth_array(values: np.ndarray) -> None:
    copy = values.copy()
    for i in range(1, len(values) - 1):
        values[i] = (copy[i - 1] + copy[i] * 2.0 + copy[i + 1]) / 4.0


def back_rim_thickness(lip: int) -> int:
    return max(1, round(max(1, lip) * 0.5))


def build_profiles(sig: Signature, variant_seed: int, size: int = TILE_SIZE, lip: int = 4, height: int = 9, roughness: float = 0.58) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    profile_scale = 2.7
    drift_strength = roughness * profile_scale
    back_lip = back_rim_thickness(lip)
    north = np.zeros(size, dtype=np.float32)
    south = np.zeros(size, dtype=np.float32)
    west = np.zeros(size, dtype=np.float32)
    east = np.zeros(size, dtype=np.float32)
    for index in range(size):
        t = index / size
        north_noise = (fbm(t * 2.2 + 1.3, 1.4, 3, variant_seed + 17) - 0.5) * 2.0
        south_noise = (fbm(t * 2.0 + 2.9, 3.1, 3, variant_seed + 23) - 0.5) * 2.0
        west_noise = (fbm(4.2, t * 2.1 + 0.9, 3, variant_seed + 31) - 0.5) * 2.0
        east_noise = (fbm(6.8, t * 2.3 + 1.7, 3, variant_seed + 43) - 0.5) * 2.0
        north[index] = clamp(back_lip + north_noise * drift_strength, 0.0, size * 0.18) if sig.open_n else 0.0
        south[index] = clamp(height + south_noise * drift_strength * 1.2, 2.0, size * 0.45) if sig.open_s else 0.0
        west[index] = clamp(lip + west_noise * drift_strength, 0.0, size * 0.24) if sig.open_w else 0.0
        east[index] = clamp(lip + east_noise * drift_strength, 0.0, size * 0.24) if sig.open_e else 0.0
    for _ in range(2):
        smooth_array(north)
        smooth_array(south)
        smooth_array(west)
        smooth_array(east)
    min_span = max(8, round(size * 0.22))
    for index in range(size):
        if size - north[index] - south[index] < min_span:
            south[index] = max(2.0, size - north[index] - min_span)
        if size - west[index] - east[index] < min_span:
            east[index] = max(0.0, size - west[index] - min_span)
    return north, south, west, east


def inside_corner_box(x: int, y: int, anchor_x: float, anchor_y: float, width: int, height: int, corner: str) -> bool:
    if corner == "NE":
        return x > anchor_x - width and y < anchor_y + height
    if corner == "SE":
        return x > anchor_x - width and y > anchor_y - height
    if corner == "SW":
        return x < anchor_x + width and y > anchor_y - height
    return x < anchor_x + width and y < anchor_y + height


def classify_pixel(sig: Signature, profiles: tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray], x: int, y: int, size: int = TILE_SIZE) -> Sample:
    north, south, west, east = profiles
    left = float(west[y])
    right = float(size - 1 - east[y])
    top = float(north[x])
    bottom = float(size - 1 - south[x])
    on_top = x >= left and x <= right and y >= top and y <= bottom
    if on_top:
        return Sample("top", left, right, top, bottom)
    if sig.open_n and y < top and x >= left and x <= right:
        return Sample("northFace", left, right, top, bottom)
    if sig.open_n and sig.open_e and x > right and y < top:
        return Sample("northCornerFace", left, right, top, bottom)
    if sig.open_n and sig.open_w and x < left and y < top:
        return Sample("northCornerFace", left, right, top, bottom)
    if sig.open_s and y > bottom and x >= left and x <= right:
        return Sample("southFace", left, right, top, bottom)
    if sig.open_e and x > right and y >= top and y <= bottom:
        return Sample("eastFace", left, right, top, bottom)
    if sig.open_w and x < left and y >= top and y <= bottom:
        return Sample("westFace", left, right, top, bottom)
    if sig.open_s and sig.open_e and x > right and y > bottom:
        return Sample("cornerFace", left, right, top, bottom)
    if sig.open_s and sig.open_w and x < left and y > bottom:
        return Sample("cornerFace", left, right, top, bottom)
    return Sample("empty", left, right, top, bottom)


def jagged_size(base_size: int, axis_coord: int, cross_coord: float, roughness: float, seed: int, max_size: int = TILE_SIZE) -> int:
    amplitude = max(0, round(max(1, base_size * 0.45) * roughness))
    if amplitude == 0:
        return base_size
    n = fbm(axis_coord * 0.21 + seed * 0.07, cross_coord * 0.13 + seed * 0.11, 3, 1907 + seed * 101)
    return int(clamp(base_size + round((n - 0.5) * 2.0 * amplitude), 1, max_size))


def classify_notch_overlay(sig: Signature, sample: Sample, x: int, y: int, lip: int = 4, height: int = 9, roughness: float = 0.58) -> Overlay | None:
    rim_width_base = max(1, min(lip, TILE_SIZE))
    top_cap_height_base = max(1, min(back_rim_thickness(lip), TILE_SIZE))
    bottom_cap_height_base = max(1, min(height, TILE_SIZE))
    if sig.notch_ne:
        width = jagged_size(rim_width_base, y, sample.right, roughness, 31)
        cap_height = jagged_size(top_cap_height_base, x, sample.top, roughness, 37)
        if inside_corner_box(x, y, sample.right, sample.top, width, cap_height, "NE"):
            return Overlay("topCapNE", width, cap_height)
    if sig.notch_nw:
        width = jagged_size(rim_width_base, y, sample.left, roughness, 41)
        cap_height = jagged_size(top_cap_height_base, x, sample.top, roughness, 43)
        if inside_corner_box(x, y, sample.left, sample.top, width, cap_height, "NW"):
            return Overlay("topCapNW", width, cap_height)
    if sig.notch_se:
        width = jagged_size(rim_width_base, y, sample.right, roughness, 47)
        cap_height = jagged_size(bottom_cap_height_base, x, sample.bottom, roughness, 53)
        if inside_corner_box(x, y, sample.right, sample.bottom, width, cap_height, "SE"):
            return Overlay("bottomCapSE", width, cap_height)
    if sig.notch_sw:
        width = jagged_size(rim_width_base, y, sample.left, roughness, 59)
        cap_height = jagged_size(bottom_cap_height_base, x, sample.bottom, roughness, 61)
        if inside_corner_box(x, y, sample.left, sample.bottom, width, cap_height, "SW"):
            return Overlay("bottomCapSW", width, cap_height)
    return None


def compute_pixel_height(sample: Sample, notch: Overlay | None, x: int, y: int) -> float:
    if sample.zone == "empty":
        return 0.0
    if sample.zone == "top" and notch is None:
        return 1.0
    if notch is not None:
        width = max(1, notch.width)
        height = max(1, notch.height)
        if notch.kind == "topCapNE":
            progress_x = clamp((x - (sample.right - width + 1)) / max(1, width - 1), 0.0, 1.0)
            progress_y = clamp((y - sample.top) / max(1, height - 1), 0.0, 1.0)
            return clamp(max(1.0 - progress_x, progress_y), 0.0, 1.0)
        if notch.kind == "topCapNW":
            progress_x = clamp((x - sample.left) / max(1, width - 1), 0.0, 1.0)
            progress_y = clamp((y - sample.top) / max(1, height - 1), 0.0, 1.0)
            return clamp(max(progress_x, progress_y), 0.0, 1.0)
        if notch.kind == "bottomCapSE":
            progress_x = clamp((x - (sample.right - width + 1)) / max(1, width - 1), 0.0, 1.0)
            progress_y = clamp((y - (sample.bottom - height + 1)) / max(1, height - 1), 0.0, 1.0)
            return clamp(max(1.0 - progress_x, 1.0 - progress_y), 0.0, 1.0)
        progress_x = clamp((x - sample.left) / max(1, width - 1), 0.0, 1.0)
        progress_y = clamp((y - (sample.bottom - height + 1)) / max(1, height - 1), 0.0, 1.0)
        return clamp(max(progress_x, 1.0 - progress_y), 0.0, 1.0)
    if sample.zone == "southFace":
        progress = clamp((y - sample.bottom) / max(1.0, TILE_SIZE - 1 - sample.bottom), 0.0, 1.0)
        return 1.0 - progress
    if sample.zone == "northFace":
        progress = clamp((sample.top - y) / max(1.0, sample.top), 0.0, 1.0)
        return 1.0 - progress
    if sample.zone == "eastFace":
        progress = clamp((x - sample.right) / max(1.0, TILE_SIZE - 1 - sample.right), 0.0, 1.0)
        return 1.0 - progress
    if sample.zone == "westFace":
        progress = clamp((sample.left - x) / max(1.0, sample.left), 0.0, 1.0)
        return 1.0 - progress
    if sample.zone == "northCornerFace":
        progress_y = clamp((sample.top - y) / max(1.0, sample.top), 0.0, 1.0)
        progress_x = clamp((x - sample.right) / max(1.0, TILE_SIZE - 1 - sample.right), 0.0, 1.0) if x > sample.right else clamp((sample.left - x) / max(1.0, sample.left), 0.0, 1.0)
        return 1.0 - max(progress_x, progress_y)
    if sample.zone == "cornerFace":
        progress_y = clamp((y - sample.bottom) / max(1.0, TILE_SIZE - 1 - sample.bottom), 0.0, 1.0)
        progress_x = clamp((x - sample.right) / max(1.0, TILE_SIZE - 1 - sample.right), 0.0, 1.0) if x > sample.right else clamp((sample.left - x) / max(1.0, sample.left), 0.0, 1.0)
        return 1.0 - max(progress_x, progress_y)
    return 0.0


def build_tile_masks(sig: Signature, variant_index: int) -> tuple[np.ndarray, np.ndarray]:
    variant_seed = 240518 + variant_index * 97 + sig.code * 131
    profiles = build_profiles(sig, variant_seed)
    rgba = np.zeros((TILE_SIZE, TILE_SIZE, 4), dtype=np.uint8)
    height_map = np.zeros((TILE_SIZE, TILE_SIZE), dtype=np.float32)
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            sample = classify_pixel(sig, profiles, x, y)
            notch = classify_notch_overlay(sig, sample, x, y) if sample.zone != "empty" else None
            if sample.zone == "empty":
                continue
            top_mask = 0
            face_mask = 0
            back_mask = 0
            if sample.zone == "top" and notch is None:
                top_mask = 255
            elif notch is not None:
                if notch.kind.startswith("topCap"):
                    back_mask = 255
                else:
                    face_mask = 255
            elif sample.zone in {"northFace", "northCornerFace"}:
                back_mask = 255
            else:
                face_mask = 255
            rgba[y, x, 0] = top_mask
            rgba[y, x, 1] = face_mask
            rgba[y, x, 2] = back_mask
            rgba[y, x, 3] = 255
            height_map[y, x] = compute_pixel_height(sample, notch, x, y)
    normals = build_normal_map(height_map, rgba[:, :, 3], strength=1.65)
    return rgba, normals


def build_normal_map(height_map: np.ndarray, alpha: np.ndarray, strength: float) -> np.ndarray:
    h, w = height_map.shape
    result = np.zeros((h, w, 4), dtype=np.uint8)
    for y in range(h):
        for x in range(w):
            if alpha[y, x] == 0:
                continue
            left = height_map[y, x - 1] if x > 0 else height_map[y, x]
            right = height_map[y, x + 1] if x < w - 1 else height_map[y, x]
            up = height_map[y - 1, x] if y > 0 else height_map[y, x]
            down = height_map[y + 1, x] if y < h - 1 else height_map[y, x]
            nx = (left - right) * strength
            ny = (up - down) * strength
            nz = 1.0
            length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            nx /= length
            ny /= length
            nz /= length
            result[y, x, 0] = int(clamp(round((nx * 0.5 + 0.5) * 255.0), 0, 255))
            result[y, x, 1] = int(clamp(round((ny * 0.5 + 0.5) * 255.0), 0, 255))
            result[y, x, 2] = int(clamp(round((nz * 0.5 + 0.5) * 255.0), 0, 255))
            result[y, x, 3] = int(alpha[y, x])
    return result


def generate_top_height(size: int = 256) -> np.ndarray:
    height = np.zeros((size, size), dtype=np.float32)
    cell = 12
    cells_x = math.ceil(size / cell)
    cells_y = math.ceil(size / cell)
    for y in range(size):
        for x in range(size):
            nx = x / size
            ny = y / size
            macro = fbm_periodic(nx * 3.0, ny * 3.0, 4, 701, 3, 3)
            medium = ridge_noise_periodic(nx * 12.0, ny * 12.0, 3, 911, 12, 12)
            micro = fbm_periodic(nx * 22.0 + 7.3, ny * 22.0 + 1.9, 3, 1187, 22, 22)
            stones = 0.0
            cx = x // cell
            cy = y // cell
            for oy in range(-1, 2):
                for ox in range(-1, 2):
                    wrapped_cx = (cx + ox) % cells_x
                    wrapped_cy = (cy + oy) % cells_y
                    px = wrapped_cx * cell + hash2d(wrapped_cx, wrapped_cy, 1301) * cell
                    py = wrapped_cy * cell + hash2d(wrapped_cx, wrapped_cy, 1307) * cell
                    radius = 1.4 + hash2d(wrapped_cx, wrapped_cy, 1319) * 2.3
                    dx = abs(x - px)
                    dy = abs(y - py)
                    dx = min(dx, size - dx)
                    dy = min(dy, size - dy)
                    dist = math.hypot(dx, dy)
                    stones = max(stones, 1.0 - smoothstep(radius, radius + 2.6, dist))
            value = macro * 0.42 + medium * 0.28 + micro * 0.15 + stones * 0.25
            height[y, x] = clamp(value, 0.0, 1.0)
    return height


def generate_face_height(size: int = 256) -> np.ndarray:
    height = np.zeros((size, size), dtype=np.float32)
    for y in range(size):
        for x in range(size):
            nx = x / size
            ny = y / size
            strata_noise = fbm_periodic(nx * 2.0, ny * 1.5, 3, 1701, 2, 2)
            strata = 0.5 + 0.5 * math.sin((ny * 18.0 + strata_noise * 3.2) * math.pi)
            fracture = ridge_noise_periodic(nx * 18.0 + 4.1, ny * 5.0 + 1.7, 3, 1723, 18, 5)
            chips = fbm_periodic(nx * 16.0 + 8.0, ny * 30.0 + 1.1, 3, 1759, 16, 30)
            vertical = fbm_periodic(nx * 9.0 + 2.0, ny * 2.0 + 5.0, 3, 1789, 9, 2)
            value = strata * 0.30 + fracture * 0.28 + chips * 0.18 + vertical * 0.24
            height[y, x] = clamp(value, 0.0, 1.0)
    return height


def save_gray(path: Path, values: np.ndarray) -> None:
    image = np.clip(values * 255.0, 0, 255).astype(np.uint8)
    Image.fromarray(image, mode="L").save(path)


def main() -> None:
    SPRITES_DIR.mkdir(parents=True, exist_ok=True)
    TEXTURES_DIR.mkdir(parents=True, exist_ok=True)

    catalog = build_catalog()
    atlas = np.zeros((ATLAS_ROWS * TILE_SIZE, ATLAS_COLUMNS * TILE_SIZE, 4), dtype=np.uint8)
    normal_atlas = np.zeros_like(atlas)

    for variant_index in range(VARIANT_COUNT):
        for case_index, code in enumerate(catalog):
            sig = decode_signature(code)
            mask_tile, normal_tile = build_tile_masks(sig, variant_index)
            atlas_index = variant_index * CASE_COUNT + case_index
            col = atlas_index % ATLAS_COLUMNS
            row = atlas_index // ATLAS_COLUMNS
            x0 = col * TILE_SIZE
            y0 = row * TILE_SIZE
            atlas[y0:y0 + TILE_SIZE, x0:x0 + TILE_SIZE] = mask_tile
            normal_atlas[y0:y0 + TILE_SIZE, x0:x0 + TILE_SIZE] = normal_tile

    Image.fromarray(atlas, mode="RGBA").save(SPRITES_DIR / MASK_ATLAS_NAME)
    Image.fromarray(normal_atlas, mode="RGBA").save(SPRITES_DIR / SHAPE_NORMAL_ATLAS_NAME)

    top_height = generate_top_height()
    face_height = generate_face_height()
    top_alpha = np.full_like(top_height, 255, dtype=np.uint8)
    face_alpha = np.full_like(face_height, 255, dtype=np.uint8)
    top_normal = build_normal_map(top_height, top_alpha, strength=2.2)
    face_normal = build_normal_map(face_height, face_alpha, strength=2.4)
    save_gray(TEXTURES_DIR / TOP_MOD_NAME, top_height)
    save_gray(TEXTURES_DIR / FACE_MOD_NAME, face_height)
    Image.fromarray(top_normal, mode="RGBA").save(TEXTURES_DIR / TOP_NORMAL_NAME)
    Image.fromarray(face_normal, mode="RGBA").save(TEXTURES_DIR / FACE_NORMAL_NAME)
    print("Generated rock shader assets:")
    for path in [
        SPRITES_DIR / MASK_ATLAS_NAME,
        SPRITES_DIR / SHAPE_NORMAL_ATLAS_NAME,
        TEXTURES_DIR / TOP_MOD_NAME,
        TEXTURES_DIR / FACE_MOD_NAME,
        TEXTURES_DIR / TOP_NORMAL_NAME,
        TEXTURES_DIR / FACE_NORMAL_NAME,
    ]:
        print(path)


if __name__ == "__main__":
    main()
