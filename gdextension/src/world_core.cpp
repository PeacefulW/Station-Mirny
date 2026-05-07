#include "world_core.h"
#include "autotile_47.h"
#include "lake_field.h"
#include "mountain_contour.h"
#include "mountain_field.h"
#include "world_utils.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <unordered_map>
#include <utility>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>

using namespace godot;
using world_utils::splitmix64;
using world_utils::positive_mod;

namespace {

constexpr int64_t CHUNK_SIZE = 16;
constexpr int64_t CELL_COUNT = CHUNK_SIZE * CHUNK_SIZE;

constexpr int64_t TERRAIN_PLAINS_GROUND = 0;
constexpr int64_t TERRAIN_MOUNTAIN_WALL = 3;
constexpr int64_t TERRAIN_MOUNTAIN_FOOT = 4;
constexpr int64_t TERRAIN_LAKE_BED_SHALLOW = 5;
constexpr int64_t TERRAIN_LAKE_BED_DEEP = 6;

constexpr int64_t SETTINGS_PACKED_LAYOUT_DENSITY = 0;
constexpr int64_t SETTINGS_PACKED_LAYOUT_SCALE = 1;
constexpr int64_t SETTINGS_PACKED_LAYOUT_CONTINUITY = 2;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RUGGEDNESS = 3;
constexpr int64_t SETTINGS_PACKED_LAYOUT_ANCHOR_CELL_SIZE = 4;
constexpr int64_t SETTINGS_PACKED_LAYOUT_GRAVITY_RADIUS = 5;
constexpr int64_t SETTINGS_PACKED_LAYOUT_FOOT_BAND = 6;
constexpr int64_t SETTINGS_PACKED_LAYOUT_INTERIOR_MARGIN = 7;
constexpr int64_t SETTINGS_PACKED_LAYOUT_LATITUDE_INFLUENCE = 8;
constexpr int64_t SETTINGS_PACKED_LAYOUT_MOUNTAIN_FIELD_COUNT = 9;
constexpr int64_t SETTINGS_PACKED_LAYOUT_WORLD_WIDTH_TILES = 9;
constexpr int64_t SETTINGS_PACKED_LAYOUT_WORLD_HEIGHT_TILES = 10;
constexpr int64_t SETTINGS_PACKED_LAYOUT_OCEAN_BAND_TILES = 11;
constexpr int64_t SETTINGS_PACKED_LAYOUT_BURNING_BAND_TILES = 12;
constexpr int64_t SETTINGS_PACKED_LAYOUT_POLE_ORIENTATION = 13;
constexpr int64_t SETTINGS_PACKED_LAYOUT_FOUNDATION_SLOPE_BIAS = 14;
constexpr int64_t SETTINGS_PACKED_LAYOUT_LAKE_DENSITY = 15;
constexpr int64_t SETTINGS_PACKED_LAYOUT_LAKE_SCALE = 16;
constexpr int64_t SETTINGS_PACKED_LAYOUT_LAKE_SHORE_WARP_AMPLITUDE = 17;
constexpr int64_t SETTINGS_PACKED_LAYOUT_LAKE_SHORE_WARP_SCALE = 18;
constexpr int64_t SETTINGS_PACKED_LAYOUT_LAKE_DEEP_THRESHOLD = 19;
constexpr int64_t SETTINGS_PACKED_LAYOUT_LAKE_MOUNTAIN_CLEARANCE = 20;
constexpr int64_t SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY = 21;
constexpr int64_t SETTINGS_PACKED_LAYOUT_FIELD_COUNT = 22;

constexpr uint8_t MOUNTAIN_FLAG_WALL = 1U << 1U;
constexpr uint8_t MOUNTAIN_FLAG_FOOT = 1U << 2U;
constexpr uint8_t MOUNTAIN_FLAG_INTERIOR = 1U << 0U;
constexpr uint8_t MOUNTAIN_FLAG_ANCHOR = 1U << 3U;
constexpr uint8_t LAKE_FLAG_WATER_PRESENT = 1U << 0U;
constexpr int64_t LEGACY_WORLD_WRAP_WIDTH_TILES = world_utils::LEGACY_WORLD_WRAP_WIDTH_TILES;
constexpr int64_t WORLD_FOUNDATION_VERSION = 9;
constexpr int64_t LAKE_PACKET_VERSION = 38;
constexpr int64_t MOUNTAIN_FINITE_WIDTH_VERSION = world_utils::MOUNTAIN_FINITE_WIDTH_VERSION;
constexpr int64_t FOUNDATION_CHUNK_SIZE = CHUNK_SIZE;
constexpr int64_t SPAWN_SAFE_PATCH_MIN_TILE = 12;
constexpr int64_t SPAWN_SAFE_PATCH_MAX_TILE = 20;
constexpr float SPAWN_MAX_WALL_DENSITY = 0.4f;
constexpr float SPAWN_MIN_VALLEY_SCORE = 0.45f;
constexpr float SPAWN_HEIGHT_MIN = 0.28f;
constexpr float SPAWN_HEIGHT_MAX = 0.74f;
constexpr size_t HIERARCHICAL_CACHE_LIMIT = 64;
constexpr int32_t PREVIEW_MIPMAP_LEVELS = 6;

enum class PreviewPatchMode {
	Terrain,
	MountainId,
	MountainClassification
};

struct Rgba8 {
	uint8_t r = 0U;
	uint8_t g = 0U;
	uint8_t b = 0U;
	uint8_t a = 255U;
};

struct NeighbourLake {
	int32_t lake_id = 0;
	int32_t water_level_q16 = 0;
};

struct LakeNeighbourOffset {
	int32_t x = 0;
	int32_t y = 0;
};

constexpr LakeNeighbourOffset k_lake_neighbour_priority[] = {
	{ 0, 0 },
	{ 0, -1 },
	{ 1, 0 },
	{ 0, 1 },
	{ -1, 0 },
	{ -1, -1 },
	{ 1, -1 },
	{ 1, 1 },
	{ -1, 1 },
};

constexpr Rgba8 PREVIEW_COLOR_GROUND = { 46U, 59U, 46U, 255U };
constexpr Rgba8 PREVIEW_COLOR_MOUNTAIN_FOOT = { 106U, 98U, 74U, 255U };
constexpr Rgba8 PREVIEW_COLOR_MOUNTAIN_WALL = { 164U, 160U, 146U, 255U };
constexpr Rgba8 PREVIEW_COLOR_LAKE_BED_SHALLOW = { 120U, 168U, 196U, 255U };
constexpr Rgba8 PREVIEW_COLOR_LAKE_BED_DEEP = { 48U, 84U, 124U, 255U };
constexpr Rgba8 PREVIEW_COLOR_CLASSIFICATION_GROUND = { 33U, 41U, 33U, 255U };
constexpr Rgba8 PREVIEW_COLOR_CLASSIFICATION_FOOT = { 214U, 143U, 51U, 255U };
constexpr Rgba8 PREVIEW_COLOR_CLASSIFICATION_WALL = { 59U, 171U, 224U, 255U };
constexpr Rgba8 PREVIEW_COLOR_CLASSIFICATION_INTERIOR = { 235U, 74U, 140U, 255U };
constexpr Rgba8 PREVIEW_COLOR_UNKNOWN = { 18U, 23U, 26U, 255U };

void write_rgba8(PackedByteArray &r_bytes, int32_t p_offset, Rgba8 p_color) {
	r_bytes.set(p_offset, p_color.r);
	r_bytes.set(p_offset + 1, p_color.g);
	r_bytes.set(p_offset + 2, p_color.b);
	r_bytes.set(p_offset + 3, p_color.a);
}

Rgba8 read_rgba8(const PackedByteArray &p_bytes, int32_t p_offset) {
	Rgba8 color;
	if (p_offset < 0 || p_offset + 3 >= p_bytes.size()) {
		return color;
	}
	color.r = p_bytes[p_offset];
	color.g = p_bytes[p_offset + 1];
	color.b = p_bytes[p_offset + 2];
	color.a = p_bytes[p_offset + 3];
	return color;
}

bool rgba8_equal(Rgba8 p_a, Rgba8 p_b) {
	return p_a.r == p_b.r && p_a.g == p_b.g && p_a.b == p_b.b && p_a.a == p_b.a;
}

PreviewPatchMode resolve_preview_patch_mode(StringName p_render_mode) {
	if (p_render_mode == StringName("mountain_id")) {
		return PreviewPatchMode::MountainId;
	}
	if (p_render_mode == StringName("mountain_classification")) {
		return PreviewPatchMode::MountainClassification;
	}
	return PreviewPatchMode::Terrain;
}

Rgba8 hsv_to_rgb8(float p_h, float p_s, float p_v) {
	const float h = p_h - std::floor(p_h);
	const float s = world_utils::clamp_value(p_s, 0.0f, 1.0f);
	const float v = world_utils::clamp_value(p_v, 0.0f, 1.0f);
	const float scaled_h = h * 6.0f;
	const int32_t sector = static_cast<int32_t>(std::floor(scaled_h));
	const float f = scaled_h - static_cast<float>(sector);
	const float p = v * (1.0f - s);
	const float q = v * (1.0f - s * f);
	const float t = v * (1.0f - s * (1.0f - f));
	float r = v;
	float g = t;
	float b = p;
	switch (positive_mod(sector, 6)) {
		case 0:
			r = v;
			g = t;
			b = p;
			break;
		case 1:
			r = q;
			g = v;
			b = p;
			break;
		case 2:
			r = p;
			g = v;
			b = t;
			break;
		case 3:
			r = p;
			g = q;
			b = v;
			break;
		case 4:
			r = t;
			g = p;
			b = v;
			break;
		default:
			r = v;
			g = p;
			b = q;
			break;
	}
	return {
		static_cast<uint8_t>(world_utils::clamp_value(static_cast<int32_t>(std::lround(r * 255.0f)), 0, 255)),
		static_cast<uint8_t>(world_utils::clamp_value(static_cast<int32_t>(std::lround(g * 255.0f)), 0, 255)),
		static_cast<uint8_t>(world_utils::clamp_value(static_cast<int32_t>(std::lround(b * 255.0f)), 0, 255)),
		255U
	};
}

int32_t read_int32_at(const PackedInt32Array &p_values, int32_t p_index, int32_t p_fallback = 0) {
	return p_index >= 0 && p_index < p_values.size() ? p_values[p_index] : p_fallback;
}

int32_t read_byte_at(const PackedByteArray &p_values, int32_t p_index, int32_t p_fallback = 0) {
	return p_index >= 0 && p_index < p_values.size() ? static_cast<int32_t>(p_values[p_index]) : p_fallback;
}

bool is_lake_bed_terrain(int64_t p_terrain_id) {
	return p_terrain_id == TERRAIN_LAKE_BED_SHALLOW || p_terrain_id == TERRAIN_LAKE_BED_DEEP;
}

Rgba8 resolve_preview_terrain_color(int32_t p_terrain_id) {
	switch (p_terrain_id) {
		case TERRAIN_MOUNTAIN_WALL:
			return PREVIEW_COLOR_MOUNTAIN_WALL;
		case TERRAIN_MOUNTAIN_FOOT:
			return PREVIEW_COLOR_MOUNTAIN_FOOT;
		case TERRAIN_LAKE_BED_SHALLOW:
			return PREVIEW_COLOR_LAKE_BED_SHALLOW;
		case TERRAIN_LAKE_BED_DEEP:
			return PREVIEW_COLOR_LAKE_BED_DEEP;
		case TERRAIN_PLAINS_GROUND:
			return PREVIEW_COLOR_GROUND;
		default:
			return PREVIEW_COLOR_UNKNOWN;
	}
}

Rgba8 resolve_preview_classification_color(int32_t p_mountain_flags) {
	if ((p_mountain_flags & MOUNTAIN_FLAG_INTERIOR) != 0) {
		return PREVIEW_COLOR_CLASSIFICATION_INTERIOR;
	}
	if ((p_mountain_flags & MOUNTAIN_FLAG_WALL) != 0) {
		return PREVIEW_COLOR_CLASSIFICATION_WALL;
	}
	if ((p_mountain_flags & MOUNTAIN_FLAG_FOOT) != 0) {
		return PREVIEW_COLOR_CLASSIFICATION_FOOT;
	}
	return PREVIEW_COLOR_CLASSIFICATION_GROUND;
}

Rgba8 resolve_preview_mountain_id_color(int32_t p_mountain_id, int32_t p_mountain_flags) {
	if (p_mountain_id <= 0) {
		return PREVIEW_COLOR_CLASSIFICATION_GROUND;
	}
	uint32_t hashed_id = static_cast<uint32_t>(p_mountain_id & 0x7fffffff);
	hashed_id = hashed_id ^ (hashed_id >> 16U);
	hashed_id *= 224682251U;
	hashed_id = hashed_id ^ (hashed_id >> 13U);
	const float hue = static_cast<float>(hashed_id & 1023U) / 1023.0f;
	const float saturation = std::min(0.92f, 0.58f + static_cast<float>((hashed_id >> 10U) & 63U) / 210.0f);
	float value = 0.72f;
	if ((p_mountain_flags & MOUNTAIN_FLAG_INTERIOR) != 0) {
		value = 0.84f;
	} else if ((p_mountain_flags & MOUNTAIN_FLAG_WALL) != 0) {
		value = 0.92f;
	}
	return hsv_to_rgb8(hue, saturation, value);
}

Rgba8 resolve_preview_patch_color(
	PreviewPatchMode p_mode,
	int32_t p_terrain_id,
	int32_t p_mountain_id,
	int32_t p_mountain_flags
) {
	switch (p_mode) {
		case PreviewPatchMode::MountainId:
			return resolve_preview_mountain_id_color(p_mountain_id, p_mountain_flags);
		case PreviewPatchMode::MountainClassification:
			return resolve_preview_classification_color(p_mountain_flags);
		case PreviewPatchMode::Terrain:
		default:
			return resolve_preview_terrain_color(p_terrain_id);
	}
}

PackedByteArray downsample_preview_mipmap(
	const PackedByteArray &p_src,
	int32_t p_src_width,
	int32_t p_src_height,
	Rgba8 p_ground_color
) {
	const int32_t dst_width = std::max(1, p_src_width / 2);
	const int32_t dst_height = std::max(1, p_src_height / 2);
	PackedByteArray dst;
	dst.resize(dst_width * dst_height * 4);
	for (int32_t y = 0; y < dst_height; ++y) {
		for (int32_t x = 0; x < dst_width; ++x) {
			const int32_t sx = x * 2;
			const int32_t sy = y * 2;
			const int32_t sx1 = std::min(sx + 1, p_src_width - 1);
			const int32_t sy1 = std::min(sy + 1, p_src_height - 1);
			const int32_t offsets[4] = {
				(sy * p_src_width + sx) * 4,
				(sy * p_src_width + sx1) * 4,
				(sy1 * p_src_width + sx) * 4,
				(sy1 * p_src_width + sx1) * 4
			};
			Rgba8 picked = p_ground_color;
			for (int32_t i = 0; i < 4; ++i) {
				const Rgba8 sample = read_rgba8(p_src, offsets[i]);
				if (!rgba8_equal(sample, p_ground_color)) {
					picked = sample;
					break;
				}
			}
			write_rgba8(dst, (y * dst_width + x) * 4, picked);
		}
	}
	return dst;
}

int64_t wrap_foundation_world_x(int64_t p_world_x, const FoundationSettings &p_foundation_settings) {
	return world_utils::wrap_foundation_world_x(p_world_x, p_foundation_settings.width_tiles, p_foundation_settings.enabled);
}

int64_t clamp_foundation_world_y(int64_t p_world_y, const FoundationSettings &p_foundation_settings) {
	return world_utils::clamp_foundation_world_y(p_world_y, p_foundation_settings.height_tiles, p_foundation_settings.enabled);
}

int64_t resolve_mountain_sample_x(
	int64_t p_world_x,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings
) {
	return world_utils::resolve_mountain_sample_x(p_world_x, p_world_version, p_foundation_settings.width_tiles, p_foundation_settings.enabled);
}

Vector2i canonicalize_chunk_coord(Vector2i p_coord, const FoundationSettings &p_foundation_settings) {
	if (!p_foundation_settings.enabled) {
		return p_coord;
	}
	const int64_t width_chunks = std::max<int64_t>(1, p_foundation_settings.width_tiles / FOUNDATION_CHUNK_SIZE);
	const int64_t height_chunks = std::max<int64_t>(1, p_foundation_settings.height_tiles / FOUNDATION_CHUNK_SIZE);
	return Vector2i(
		static_cast<int32_t>(positive_mod(p_coord.x, width_chunks)),
		static_cast<int32_t>(std::max<int64_t>(0, std::min<int64_t>(p_coord.y, height_chunks - 1)))
	);
}

int64_t floor_div(int64_t p_value, int64_t p_divisor) {
	int64_t quotient = p_value / p_divisor;
	const int64_t remainder = p_value % p_divisor;
	if (remainder != 0 && ((remainder < 0) != (p_divisor < 0))) {
		quotient -= 1;
	}
	return quotient;
}

int64_t resolve_macro_cell_x_for_world(
	int64_t p_world_x,
	int32_t p_macro_cell_size,
	int64_t p_world_wrap_width_tiles
) {
	return floor_div(
		positive_mod(p_world_x, p_world_wrap_width_tiles),
		static_cast<int64_t>(p_macro_cell_size)
	);
}

int64_t resolve_macro_cell_y_for_world(int64_t p_world_y, int32_t p_macro_cell_size) {
	return floor_div(p_world_y, static_cast<int64_t>(p_macro_cell_size));
}

int64_t resolve_base_ground_atlas_index(
	int64_t world_x,
	int64_t world_y,
	int64_t seed,
	bool north,
	bool north_east,
	bool east,
	bool south_east,
	bool south,
	bool south_west,
	bool west,
	bool north_west
) {
	return autotile_47::resolve_atlas_index(
		north,
		north_east,
		east,
		south_east,
		south,
		south_west,
		west,
		north_west,
		world_x,
		world_y,
		seed
	);
}

int64_t resolve_mountain_base_atlas_index(
	int64_t seed,
	int64_t world_x,
	int64_t world_y,
	bool north,
	bool north_east,
	bool east,
	bool south_east,
	bool south,
	bool south_west,
	bool west,
	bool north_west
) {
	return autotile_47::resolve_atlas_index(
		north,
		north_east,
		east,
		south_east,
		south,
		south_west,
		west,
		north_west,
		world_x,
		world_y,
		seed
	);
}

int64_t resolve_lake_bed_atlas_index(
	int64_t seed,
	int64_t world_x,
	int64_t world_y,
	bool north,
	bool north_east,
	bool east,
	bool south_east,
	bool south,
	bool south_west,
	bool west,
	bool north_west
) {
	return autotile_47::resolve_atlas_index(
		north,
		north_east,
		east,
		south_east,
		south,
		south_west,
		west,
		north_west,
		world_x,
		world_y,
		seed
	);
}

bool is_better_neighbour_lake(const NeighbourLake &candidate, const NeighbourLake &best) {
	if (candidate.water_level_q16 > best.water_level_q16) {
		return true;
	}
	return candidate.water_level_q16 == best.water_level_q16 &&
			(best.lake_id <= 0 || candidate.lake_id < best.lake_id);
}

NeighbourLake resolve_best_neighbour_lake(
	const world_prepass::Snapshot &p_snapshot,
	int64_t p_world_x,
	int64_t p_world_y,
	const FoundationSettings &p_foundation_settings
) {
	NeighbourLake best;
	if (!p_snapshot.valid ||
			p_snapshot.grid_width <= 0 ||
			p_snapshot.grid_height <= 0 ||
			p_snapshot.lake_id.empty() ||
			p_snapshot.lake_water_level_q16.empty()) {
		return best;
	}

	const int64_t wrapped_x = wrap_foundation_world_x(p_world_x, p_foundation_settings);
	const int64_t clamped_y = clamp_foundation_world_y(p_world_y, p_foundation_settings);
	const int32_t coarse_x = static_cast<int32_t>(world_utils::clamp_value<int64_t>(
		wrapped_x / world_prepass::COARSE_CELL_SIZE_TILES,
		0,
		p_snapshot.grid_width - 1
	));
	const int32_t coarse_y = static_cast<int32_t>(world_utils::clamp_value<int64_t>(
		clamped_y / world_prepass::COARSE_CELL_SIZE_TILES,
		0,
		p_snapshot.grid_height - 1
	));

	for (const LakeNeighbourOffset &offset : k_lake_neighbour_priority) {
		const int32_t neighbour_x = static_cast<int32_t>(positive_mod(
			static_cast<int64_t>(coarse_x) + offset.x,
			p_snapshot.grid_width
		));
		const int32_t neighbour_y = static_cast<int32_t>(world_utils::clamp_value<int64_t>(
			static_cast<int64_t>(coarse_y) + offset.y,
			0,
			p_snapshot.grid_height - 1
		));
		const int32_t snapshot_index = p_snapshot.index(neighbour_x, neighbour_y);
		if (snapshot_index < 0 ||
				snapshot_index >= static_cast<int32_t>(p_snapshot.lake_id.size()) ||
				snapshot_index >= static_cast<int32_t>(p_snapshot.lake_water_level_q16.size())) {
			continue;
		}
		const NeighbourLake candidate = {
			p_snapshot.lake_id[static_cast<size_t>(snapshot_index)],
			p_snapshot.lake_water_level_q16[static_cast<size_t>(snapshot_index)],
		};
		if (candidate.lake_id <= 0 || candidate.water_level_q16 <= 0) {
			continue;
		}
		if (is_better_neighbour_lake(candidate, best)) {
			best = candidate;
		}
	}
	return best;
}

float sample_foundation_height_bilinear(
	const world_prepass::Snapshot &p_snapshot,
	int64_t p_world_x,
	int64_t p_world_y,
	const FoundationSettings &p_foundation_settings
) {
	const int64_t wrapped_x = wrap_foundation_world_x(p_world_x, p_foundation_settings);
	const int64_t clamped_y = clamp_foundation_world_y(p_world_y, p_foundation_settings);
	const float coarse_sample_x = (static_cast<float>(wrapped_x) + 0.5f) /
					static_cast<float>(world_prepass::COARSE_CELL_SIZE_TILES) -
			0.5f;
	const float coarse_sample_y = (static_cast<float>(clamped_y) + 0.5f) /
					static_cast<float>(world_prepass::COARSE_CELL_SIZE_TILES) -
			0.5f;
	return world_prepass::sample_snapshot_float_bilinear(
		p_snapshot.foundation_height,
		p_snapshot,
		coarse_sample_x,
		coarse_sample_y
	);
}

bool is_water_at_world_from_neighbour_lake(
	const world_prepass::Snapshot &p_snapshot,
	int64_t p_world_x,
	int64_t p_world_y,
	int64_t p_seed,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings,
	const LakeSettings &p_lake_settings,
	const lake_field::BasinMinElevationLookup &p_lake_basin_min_elevation
) {
	const NeighbourLake neighbour_lake = resolve_best_neighbour_lake(
		p_snapshot,
		p_world_x,
		p_world_y,
		p_foundation_settings
	);
	if (neighbour_lake.lake_id <= 0 || neighbour_lake.water_level_q16 <= 0) {
		return false;
	}
	const float water_level = static_cast<float>(neighbour_lake.water_level_q16) / 65536.0f;
	const int64_t lake_world_x = wrap_foundation_world_x(p_world_x, p_foundation_settings);
	const int64_t lake_world_y = clamp_foundation_world_y(p_world_y, p_foundation_settings);
	const float foundation_height = sample_foundation_height_bilinear(
		p_snapshot,
		p_world_x,
		p_world_y,
		p_foundation_settings
	);
	const float basin_min_elevation = lake_field::resolve_basin_min_elevation(
		p_lake_basin_min_elevation,
		neighbour_lake.lake_id,
		foundation_height
	);
	const float basin_depth = std::max(0.0001f, water_level - basin_min_elevation);
	const float fbm_unit = lake_field::fbm_shore(
		lake_world_x,
		lake_world_y,
		p_seed,
		p_world_version,
		p_lake_settings.shore_warp_scale
	);
	const float shore_warp = fbm_unit * p_lake_settings.shore_warp_amplitude * basin_depth;
	const float effective_elevation = foundation_height + shore_warp;
	return effective_elevation < water_level;
}

Dictionary resolve_world_foundation_spawn_tile_l6(
	const world_prepass::Snapshot &p_snapshot,
	int64_t p_seed,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings,
	const LakeSettings &p_lake_settings,
	const lake_field::BasinMinElevationLookup &p_lake_basin_min_elevation
) {
	Dictionary result;
	if (!p_snapshot.valid) {
		result["success"] = false;
		result["message"] = "WorldPrePass snapshot is not valid.";
		return result;
	}

	float best_score = -std::numeric_limits<float>::infinity();
	int32_t best_index = -1;
	const int32_t node_count = p_snapshot.grid_width * p_snapshot.grid_height;
	for (int32_t index = 0; index < node_count; ++index) {
		if (p_snapshot.ocean_band_mask[static_cast<size_t>(index)] != 0 ||
				p_snapshot.burning_band_mask[static_cast<size_t>(index)] != 0 ||
				p_snapshot.continent_mask[static_cast<size_t>(index)] == 0 ||
				p_snapshot.coarse_wall_density[static_cast<size_t>(index)] >= SPAWN_MAX_WALL_DENSITY) {
			continue;
		}

		const int32_t node_x = index % p_snapshot.grid_width;
		const int32_t node_y = index / p_snapshot.grid_width;
		const Vector2i candidate_tile = p_snapshot.node_to_tile_center(node_x, node_y);
		if (is_water_at_world_from_neighbour_lake(
					p_snapshot,
					candidate_tile.x,
					candidate_tile.y,
					p_seed,
					p_world_version,
					p_foundation_settings,
					p_lake_settings,
					p_lake_basin_min_elevation)) {
			continue;
		}

		const float valley = p_snapshot.coarse_valley_score[static_cast<size_t>(index)];
		const float foundation_height = p_snapshot.foundation_height[static_cast<size_t>(index)];
		const float height_mid = 1.0f - world_utils::saturate(std::abs(foundation_height - 0.52f) / 0.52f);
		const float wall_penalty = p_snapshot.coarse_wall_density[static_cast<size_t>(index)] * 0.75f;
		const bool preferred_band = valley >= SPAWN_MIN_VALLEY_SCORE &&
				foundation_height >= SPAWN_HEIGHT_MIN &&
				foundation_height <= SPAWN_HEIGHT_MAX;
		const float score = valley * 1.8f + height_mid * 0.9f - wall_penalty + (preferred_band ? 0.65f : 0.0f);
		if (score > best_score) {
			best_score = score;
			best_index = index;
		}
	}

	if (best_index < 0) {
		result["success"] = false;
		result["message"] = "No valid foundation spawn node found outside hard bands, reserved massing, mountain massifs, and lakes.";
		return result;
	}

	const int32_t node_x = best_index % p_snapshot.grid_width;
	const int32_t node_y = best_index / p_snapshot.grid_width;
	const Vector2i spawn_tile = p_snapshot.node_to_tile_center(node_x, node_y);
	const int32_t patch_size = static_cast<int32_t>(SPAWN_SAFE_PATCH_MAX_TILE - SPAWN_SAFE_PATCH_MIN_TILE + 1);
	const int32_t rect_x = static_cast<int32_t>(world_utils::clamp_value<int64_t>(
		static_cast<int64_t>(spawn_tile.x) - patch_size / 2,
		0,
		std::max<int64_t>(0, p_snapshot.width_tiles - patch_size)
	));
	const int32_t rect_y = static_cast<int32_t>(world_utils::clamp_value<int64_t>(
		static_cast<int64_t>(spawn_tile.y) - patch_size / 2,
		0,
		std::max<int64_t>(0, p_snapshot.height_tiles - patch_size)
	));

	result["success"] = true;
	result["spawn_tile"] = spawn_tile;
	result["spawn_safe_patch_rect"] = Rect2i(Vector2i(rect_x, rect_y), Vector2i(patch_size, patch_size));
	result["node_coord"] = Vector2i(node_x, node_y);
	result["score"] = best_score;
	result["coarse_valley_score"] = p_snapshot.coarse_valley_score[static_cast<size_t>(best_index)];
	result["foundation_height"] = p_snapshot.foundation_height[static_cast<size_t>(best_index)];
	result["coarse_wall_density"] = p_snapshot.coarse_wall_density[static_cast<size_t>(best_index)];
	return result;
}

mountain_field::Settings unpack_mountain_settings(const PackedFloat32Array &p_settings_packed) {
	mountain_field::Settings settings;
	settings.density = p_settings_packed[SETTINGS_PACKED_LAYOUT_DENSITY];
	settings.scale = p_settings_packed[SETTINGS_PACKED_LAYOUT_SCALE];
	settings.continuity = p_settings_packed[SETTINGS_PACKED_LAYOUT_CONTINUITY];
	settings.ruggedness = p_settings_packed[SETTINGS_PACKED_LAYOUT_RUGGEDNESS];
	settings.anchor_cell_size = static_cast<int32_t>(std::lround(p_settings_packed[SETTINGS_PACKED_LAYOUT_ANCHOR_CELL_SIZE]));
	settings.gravity_radius = static_cast<int32_t>(std::lround(p_settings_packed[SETTINGS_PACKED_LAYOUT_GRAVITY_RADIUS]));
	settings.foot_band = p_settings_packed[SETTINGS_PACKED_LAYOUT_FOOT_BAND];
	settings.interior_margin = static_cast<int32_t>(std::lround(p_settings_packed[SETTINGS_PACKED_LAYOUT_INTERIOR_MARGIN]));
	settings.latitude_influence = p_settings_packed[SETTINGS_PACKED_LAYOUT_LATITUDE_INFLUENCE];
	return settings;
}

mountain_field::Settings make_effective_mountain_settings(
	int64_t p_world_version,
	mountain_field::Settings p_settings,
	const FoundationSettings &p_foundation_settings
) {
	if (p_foundation_settings.enabled && p_world_version >= MOUNTAIN_FINITE_WIDTH_VERSION) {
		p_settings.world_wrap_width_tiles = p_foundation_settings.width_tiles;
	} else {
		p_settings.world_wrap_width_tiles = LEGACY_WORLD_WRAP_WIDTH_TILES;
	}
	return p_settings;
}

FoundationSettings unpack_foundation_settings(int64_t p_world_version, const PackedFloat32Array &p_settings_packed) {
	FoundationSettings settings;
	if (p_world_version < WORLD_FOUNDATION_VERSION) {
		return settings;
	}
	settings.enabled = true;
	settings.width_tiles = std::max<int64_t>(
		FOUNDATION_CHUNK_SIZE,
		static_cast<int64_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_WORLD_WIDTH_TILES]))
	);
	settings.height_tiles = std::max<int64_t>(
		FOUNDATION_CHUNK_SIZE,
		static_cast<int64_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_WORLD_HEIGHT_TILES]))
	);
	settings.ocean_band_tiles = std::max<int64_t>(
		0,
		static_cast<int64_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_OCEAN_BAND_TILES]))
	);
	settings.burning_band_tiles = std::max<int64_t>(
		0,
		static_cast<int64_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_BURNING_BAND_TILES]))
	);
	settings.pole_orientation = static_cast<int64_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_POLE_ORIENTATION]));
	settings.slope_bias = p_settings_packed[SETTINGS_PACKED_LAYOUT_FOUNDATION_SLOPE_BIAS];
	return settings;
}

LakeSettings unpack_lake_settings(int64_t p_world_version, const PackedFloat32Array &p_settings_packed) {
	LakeSettings settings;
	if (p_world_version < WORLD_FOUNDATION_VERSION) {
		return settings;
	}
	settings.enabled = true;
	settings.density = world_utils::clamp_value(
		p_settings_packed[SETTINGS_PACKED_LAYOUT_LAKE_DENSITY],
		0.0f,
		1.0f
	);
	settings.scale = world_utils::clamp_value(
		p_settings_packed[SETTINGS_PACKED_LAYOUT_LAKE_SCALE],
		64.0f,
		2048.0f
	);
	settings.shore_warp_amplitude = world_utils::clamp_value(
		p_settings_packed[SETTINGS_PACKED_LAYOUT_LAKE_SHORE_WARP_AMPLITUDE],
		0.0f,
		1.0f
	);
	settings.shore_warp_scale = world_utils::clamp_value(
		p_settings_packed[SETTINGS_PACKED_LAYOUT_LAKE_SHORE_WARP_SCALE],
		8.0f,
		64.0f
	);
	settings.deep_threshold = world_utils::clamp_value(
		p_settings_packed[SETTINGS_PACKED_LAYOUT_LAKE_DEEP_THRESHOLD],
		0.05f,
		0.5f
	);
	settings.mountain_clearance = world_utils::clamp_value(
		p_settings_packed[SETTINGS_PACKED_LAYOUT_LAKE_MOUNTAIN_CLEARANCE],
		0.0f,
		0.5f
	);
	settings.connectivity = world_utils::clamp_value(
		p_settings_packed[SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY],
		0.0f,
		1.0f
	);
	return settings;
}

int64_t expected_settings_count_for_version(int64_t p_world_version) {
	return p_world_version >= WORLD_FOUNDATION_VERSION ?
			SETTINGS_PACKED_LAYOUT_FIELD_COUNT :
			SETTINGS_PACKED_LAYOUT_MOUNTAIN_FIELD_COUNT;
}

Dictionary make_failure_result(const char *p_message) {
	Dictionary result;
	result["success"] = false;
	result["message"] = p_message;
	return result;
}

bool is_foundation_spawn_safety_area_at_world(
	int64_t p_world_x,
	int64_t p_world_y,
	const FoundationSettings &p_foundation_settings
) {
	if (!p_foundation_settings.enabled) {
		return false;
	}
	const int64_t safe_patch_size = SPAWN_SAFE_PATCH_MAX_TILE - SPAWN_SAFE_PATCH_MIN_TILE + 1;
	const int64_t habitable_min_y = p_foundation_settings.ocean_band_tiles;
	const int64_t habitable_max_y = p_foundation_settings.height_tiles - p_foundation_settings.burning_band_tiles;
	const int64_t habitable_height = std::max<int64_t>(safe_patch_size, habitable_max_y - habitable_min_y);
	const int64_t start_x = std::max<int64_t>(0, p_foundation_settings.width_tiles / 2 - safe_patch_size / 2);
	const int64_t start_y = habitable_min_y + std::max<int64_t>(0, (habitable_height - safe_patch_size) / 2);
	const int64_t canonical_x = wrap_foundation_world_x(p_world_x, p_foundation_settings);
	return canonical_x >= start_x && canonical_x < start_x + safe_patch_size &&
			p_world_y >= start_y && p_world_y < start_y + safe_patch_size;
}

uint64_t make_cache_signature(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Settings &p_settings,
	const FoundationSettings &p_foundation_settings
) {
	uint64_t signature = splitmix64(static_cast<uint64_t>(p_seed));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_world_version) * 0x9e3779b185ebca87ULL);
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_settings.density * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_settings.scale * 1000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_settings.continuity * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_settings.ruggedness * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_settings.anchor_cell_size));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_settings.gravity_radius));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_settings.foot_band * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_settings.interior_margin));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround((p_settings.latitude_influence + 1.0f) * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_settings.world_wrap_width_tiles));
	if (p_foundation_settings.enabled) {
		signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.width_tiles));
		signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.height_tiles));
		signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.ocean_band_tiles));
		signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.burning_band_tiles));
		signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.pole_orientation));
		signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround((p_foundation_settings.slope_bias + 1.0f) * 1000000.0f)));
	}
	return signature;
}

uint64_t make_macro_key(int64_t p_macro_x, int64_t p_macro_y) {
	uint64_t key = splitmix64(static_cast<uint64_t>(p_macro_x));
	key = splitmix64(key ^ static_cast<uint64_t>(p_macro_y) * 0x9e3779b185ebca87ULL);
	return key;
}

struct ChunkMacroGroup {
	int64_t macro_cell_x = 0;
	int64_t macro_cell_y = 0;
	std::vector<int32_t> chunk_indices;
};

} // namespace

struct WorldCore::HierarchicalMacroCache {
	struct Entry {
		uint64_t last_used_tick = 0;
		mountain_field::HierarchicalMacroSolve solve;
	};

	uint64_t signature = 0;
	uint64_t tick = 0;
	std::unordered_map<uint64_t, Entry> entries;
};

void WorldCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate_chunk_packets_batch", "seed", "coords", "world_version", "settings_packed"), &WorldCore::generate_chunk_packets_batch);
	ClassDB::bind_method(D_METHOD("make_world_preview_patch_image", "packet", "render_mode"), &WorldCore::make_world_preview_patch_image);
	ClassDB::bind_method(D_METHOD("build_mountain_contour_debug", "solid_halo", "chunk_size", "tile_size_px"), &WorldCore::build_mountain_contour_debug);
	ClassDB::bind_method(D_METHOD("resolve_world_foundation_spawn_tile", "seed", "world_version", "settings_packed"), &WorldCore::resolve_world_foundation_spawn_tile);
#ifdef DEBUG_ENABLED
	ClassDB::bind_method(D_METHOD("get_world_foundation_snapshot", "layer_mask", "downscale_factor"), &WorldCore::get_world_foundation_snapshot);
	ClassDB::bind_method(D_METHOD("get_world_foundation_overview", "layer_mask", "pixels_per_cell"), &WorldCore::get_world_foundation_overview, DEFVAL(1));
#endif
}

WorldCore::WorldCore() :
		hierarchical_macro_cache_(std::make_unique<HierarchicalMacroCache>()),
		world_prepass_snapshot_(std::make_unique<world_prepass::Snapshot>()) {}

WorldCore::~WorldCore() = default;

Ref<Image> WorldCore::make_world_preview_patch_image(Dictionary p_packet, StringName p_render_mode) {
	const PreviewPatchMode mode = resolve_preview_patch_mode(p_render_mode);
	const PackedInt32Array terrain_ids = p_packet.get("terrain_ids", PackedInt32Array());
	const PackedInt32Array mountain_ids = p_packet.get("mountain_id_per_tile", PackedInt32Array());
	const PackedByteArray mountain_flags = p_packet.get("mountain_flags", PackedByteArray());
	const Rgba8 ground_color = mode == PreviewPatchMode::Terrain ?
			PREVIEW_COLOR_GROUND :
			PREVIEW_COLOR_CLASSIFICATION_GROUND;

	PackedByteArray base_level;
	base_level.resize(static_cast<int32_t>(CELL_COUNT * 4));
	for (int32_t index = 0; index < static_cast<int32_t>(CELL_COUNT); ++index) {
		const Rgba8 color = index < terrain_ids.size() ?
				resolve_preview_patch_color(
					mode,
					read_int32_at(terrain_ids, index),
					read_int32_at(mountain_ids, index),
					read_byte_at(mountain_flags, index)
				) :
				PREVIEW_COLOR_UNKNOWN;
		write_rgba8(base_level, index * 4, color);
	}

	std::vector<PackedByteArray> levels;
	levels.reserve(PREVIEW_MIPMAP_LEVELS);
	levels.push_back(base_level);
	int32_t current_width = static_cast<int32_t>(CHUNK_SIZE);
	int32_t current_height = static_cast<int32_t>(CHUNK_SIZE);
	while ((current_width > 1 || current_height > 1) &&
			static_cast<int32_t>(levels.size()) < PREVIEW_MIPMAP_LEVELS) {
		const PackedByteArray next = downsample_preview_mipmap(levels.back(), current_width, current_height, ground_color);
		levels.push_back(next);
		current_width = std::max(1, current_width / 2);
		current_height = std::max(1, current_height / 2);
	}

	PackedByteArray combined_bytes;
	for (const PackedByteArray &level : levels) {
		combined_bytes.append_array(level);
	}
	return Image::create_from_data(
		static_cast<int32_t>(CHUNK_SIZE),
		static_cast<int32_t>(CHUNK_SIZE),
		true,
		Image::FORMAT_RGBA8,
		combined_bytes
	);
}

const mountain_field::HierarchicalMacroSolve &WorldCore::_get_or_build_hierarchical_macro_solve(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Settings &p_settings,
	const FoundationSettings &p_foundation_settings,
	int64_t p_macro_cell_x,
	int64_t p_macro_cell_y
) {
	HierarchicalMacroCache &cache = *hierarchical_macro_cache_;
	const uint64_t signature = make_cache_signature(p_seed, p_world_version, p_settings, p_foundation_settings);
	if (cache.signature != signature) {
		cache.signature = signature;
		cache.tick = 0;
		cache.entries.clear();
	}

	cache.tick += 1;
	const uint64_t key = make_macro_key(p_macro_cell_x, p_macro_cell_y);
	auto found = cache.entries.find(key);
	if (found != cache.entries.end()) {
		found->second.last_used_tick = cache.tick;
		return found->second.solve;
	}

	HierarchicalMacroCache::Entry entry;
	entry.last_used_tick = cache.tick;
	entry.solve = mountain_field::solve_hierarchical_macro(
		p_seed,
		p_world_version,
		p_macro_cell_x,
		p_macro_cell_y,
		p_settings
	);
	auto insert_result = cache.entries.emplace(key, std::move(entry));
	auto inserted = insert_result.first;

	if (cache.entries.size() > HIERARCHICAL_CACHE_LIMIT) {
		auto lru = cache.entries.end();
		for (auto iter = cache.entries.begin(); iter != cache.entries.end(); ++iter) {
			if (iter == inserted) {
				continue;
			}
			if (lru == cache.entries.end() || iter->second.last_used_tick < lru->second.last_used_tick) {
				lru = iter;
			}
		}
		if (lru != cache.entries.end()) {
			cache.entries.erase(lru);
		}
	}

	return inserted->second.solve;
}

const world_prepass::Snapshot &WorldCore::_get_or_build_world_prepass(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_effective_mountain_settings,
	const FoundationSettings &p_foundation_settings,
	const LakeSettings &p_lake_settings
) {
	const uint64_t signature = world_prepass::make_signature(
		p_seed,
		p_world_version,
		p_effective_mountain_settings,
		p_foundation_settings,
		p_lake_settings
	);
	const bool needs_rebuild = world_prepass_snapshot_ == nullptr ||
			!world_prepass_snapshot_->valid ||
			world_prepass_snapshot_->cache_signature != signature;
	if (needs_rebuild) {
		world_prepass_snapshot_ = world_prepass::build_snapshot(
			p_seed,
			p_world_version,
			p_mountain_evaluator,
			p_effective_mountain_settings,
			p_foundation_settings,
			p_lake_settings
		);
		world_prepass_lake_basin_min_elevation_ = lake_field::build_basin_min_elevation_lookup(*world_prepass_snapshot_);
	}
	world_prepass_effective_mountain_settings_ = p_effective_mountain_settings;
	world_prepass_foundation_settings_ = p_foundation_settings;
	world_prepass_lake_settings_ = p_lake_settings;
	return *world_prepass_snapshot_;
}

Dictionary WorldCore::build_mountain_contour_debug(
	PackedByteArray p_solid_halo,
	int64_t p_chunk_size,
	int64_t p_tile_size_px
) {
	return mountain_contour::build_debug_mesh(
		p_solid_halo,
		static_cast<int32_t>(p_chunk_size),
		static_cast<int32_t>(p_tile_size_px)
	);
}

Dictionary WorldCore::_generate_chunk_packet(
	int64_t p_seed,
	Vector2i p_coord,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_effective_mountain_settings,
	const FoundationSettings &p_foundation_settings,
	const LakeSettings &p_lake_settings
) {
	p_coord = canonicalize_chunk_coord(p_coord, p_foundation_settings);
	PackedInt32Array terrain_ids;
	terrain_ids.resize(CELL_COUNT);
	PackedInt32Array terrain_atlas_indices;
	terrain_atlas_indices.resize(CELL_COUNT);
	PackedByteArray walkable_flags;
	walkable_flags.resize(CELL_COUNT);
	PackedByteArray lake_flags;
	lake_flags.resize(CELL_COUNT);
	PackedInt32Array mountain_id_per_tile;
	mountain_id_per_tile.resize(CELL_COUNT);
	PackedByteArray mountain_flags;
	mountain_flags.resize(CELL_COUNT);
	PackedInt32Array mountain_atlas_indices;
	mountain_atlas_indices.resize(CELL_COUNT);

	const mountain_field::Thresholds &mountain_thresholds = p_mountain_evaluator.get_thresholds();
	const int32_t macro_cell_size = mountain_field::get_hierarchical_macro_cell_size(p_world_version);
	const int64_t mountain_border = std::max<int64_t>(1, p_effective_mountain_settings.interior_margin);
	const int64_t mountain_grid_side = CHUNK_SIZE + mountain_border * 2;
	std::vector<float> mountain_elevations(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0.0f);
	std::vector<int32_t> mountain_ids(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0);
	std::vector<uint8_t> lake_flag_grid(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0U);

	const world_prepass::Snapshot *lake_snapshot = nullptr;
	if (p_world_version >= LAKE_PACKET_VERSION &&
			p_lake_settings.enabled &&
			p_lake_settings.density > 0.0f &&
			p_foundation_settings.enabled) {
		const world_prepass::Snapshot &snapshot = _get_or_build_world_prepass(
			p_seed,
			p_world_version,
			p_mountain_evaluator,
			p_effective_mountain_settings,
			p_foundation_settings,
			p_lake_settings
		);
		if (snapshot.valid) {
			lake_snapshot = &snapshot;
		}
	}

	const mountain_field::HierarchicalMacroSolve *cached_macro_solve = nullptr;
	int64_t cached_macro_cell_x = std::numeric_limits<int64_t>::min();
	int64_t cached_macro_cell_y = std::numeric_limits<int64_t>::min();

	auto resolve_mountain_id_at_world = [&](int64_t p_world_x, int64_t p_world_y, float p_elevation) -> int32_t {
		if (p_elevation < mountain_thresholds.t_edge) {
			return 0;
		}
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(
			p_world_x,
			macro_cell_size,
			p_effective_mountain_settings.world_wrap_width_tiles
		);
		const int64_t macro_cell_y = resolve_macro_cell_y_for_world(p_world_y, macro_cell_size);
		if (cached_macro_solve == nullptr || macro_cell_x != cached_macro_cell_x || macro_cell_y != cached_macro_cell_y) {
			cached_macro_solve = &_get_or_build_hierarchical_macro_solve(
				p_seed,
				p_world_version,
				p_effective_mountain_settings,
				p_foundation_settings,
				macro_cell_x,
				macro_cell_y
			);
			cached_macro_cell_x = macro_cell_x;
			cached_macro_cell_y = macro_cell_y;
		}
		return cached_macro_solve->resolve_mountain_id(
			p_world_x,
			p_world_y,
			p_elevation,
			mountain_thresholds.t_edge
		);
	};

	auto is_component_representative_tile = [&](int64_t p_world_x, int64_t p_world_y, int32_t p_mountain_id) -> bool {
		if (p_mountain_id <= 0) {
			return false;
		}
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(
			p_world_x,
			macro_cell_size,
			p_effective_mountain_settings.world_wrap_width_tiles
		);
		const int64_t macro_cell_y = resolve_macro_cell_y_for_world(p_world_y, macro_cell_size);
		const mountain_field::HierarchicalMacroSolve &solve = _get_or_build_hierarchical_macro_solve(
			p_seed,
			p_world_version,
			p_effective_mountain_settings,
			p_foundation_settings,
			macro_cell_x,
			macro_cell_y
		);
		return solve.is_representative_tile(p_world_x, p_world_y, p_mountain_id);
	};

	for (int64_t sample_y = 0; sample_y < mountain_grid_side; ++sample_y) {
		for (int64_t sample_x = 0; sample_x < mountain_grid_side; ++sample_x) {
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + sample_x - mountain_border;
			const int64_t world_y = clamp_foundation_world_y(
				static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + sample_y - mountain_border,
				p_foundation_settings
			);
			const int64_t sample_world_x = resolve_mountain_sample_x(world_x, p_world_version, p_foundation_settings);
			const int64_t sample_index = sample_y * mountain_grid_side + sample_x;
			float elevation = p_mountain_evaluator.sample_elevation(sample_world_x, world_y);
			if (is_foundation_spawn_safety_area_at_world(world_x, world_y, p_foundation_settings)) {
				elevation = 0.0f;
			}
			mountain_elevations[static_cast<size_t>(sample_index)] = elevation;
			mountain_ids[static_cast<size_t>(sample_index)] = resolve_mountain_id_at_world(sample_world_x, world_y, elevation);
		}
	}

	std::vector<int64_t> terrain_id_grid(static_cast<size_t>(mountain_grid_side * mountain_grid_side), TERRAIN_PLAINS_GROUND);
	for (int64_t sample_y = 0; sample_y < mountain_grid_side; ++sample_y) {
		for (int64_t sample_x = 0; sample_x < mountain_grid_side; ++sample_x) {
			const int64_t sample_index = sample_y * mountain_grid_side + sample_x;
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + sample_x - mountain_border;
			const int64_t world_y = clamp_foundation_world_y(
				static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + sample_y - mountain_border,
				p_foundation_settings
			);
			const float elevation = mountain_elevations[static_cast<size_t>(sample_index)];
			const int32_t mountain_id = mountain_ids[static_cast<size_t>(sample_index)];
			int64_t terrain_id = TERRAIN_PLAINS_GROUND;
			if (mountain_id > 0 && elevation >= mountain_thresholds.t_wall) {
				terrain_id = TERRAIN_MOUNTAIN_WALL;
			} else if (mountain_id > 0 && elevation >= mountain_thresholds.t_edge) {
				terrain_id = TERRAIN_MOUNTAIN_FOOT;
			}
			terrain_id_grid[static_cast<size_t>(sample_index)] = terrain_id;
		}
	}

	if (lake_snapshot != nullptr) {
		for (int64_t sample_y = 0; sample_y < mountain_grid_side; ++sample_y) {
			for (int64_t sample_x = 0; sample_x < mountain_grid_side; ++sample_x) {
				const int64_t sample_index = sample_y * mountain_grid_side + sample_x;
				if (terrain_id_grid[static_cast<size_t>(sample_index)] != TERRAIN_PLAINS_GROUND) {
					continue;
				}
				const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + sample_x - mountain_border;
				const int64_t world_y = clamp_foundation_world_y(
					static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + sample_y - mountain_border,
					p_foundation_settings
				);
				const NeighbourLake neighbour_lake = resolve_best_neighbour_lake(
					*lake_snapshot,
					world_x,
					world_y,
					p_foundation_settings
				);
				const int32_t lake_id = neighbour_lake.lake_id;
				const int32_t water_level_q16 = neighbour_lake.water_level_q16;
				if (lake_id <= 0 || water_level_q16 <= 0) {
					continue;
				}
				const float water_level = static_cast<float>(water_level_q16) / 65536.0f;
				const int64_t lake_world_x = wrap_foundation_world_x(world_x, p_foundation_settings);
				const float foundation_height = sample_foundation_height_bilinear(
					*lake_snapshot,
					world_x,
					world_y,
					p_foundation_settings
				);
				const float basin_min_elevation = lake_field::resolve_basin_min_elevation(
					world_prepass_lake_basin_min_elevation_,
					lake_id,
					foundation_height
				);
				const float basin_depth = std::max(0.0001f, water_level - basin_min_elevation);
				const float fbm_unit = lake_field::fbm_shore(
					lake_world_x,
					world_y,
					p_seed,
					p_world_version,
					p_lake_settings.shore_warp_scale
				);
				const float shore_warp = fbm_unit * p_lake_settings.shore_warp_amplitude * basin_depth;
				const float effective_elevation = foundation_height + shore_warp;
				if (effective_elevation >= water_level) {
					continue;
				}
				const float relative_depth = (water_level - effective_elevation) / basin_depth;
				terrain_id_grid[static_cast<size_t>(sample_index)] =
						relative_depth >= p_lake_settings.deep_threshold ?
						TERRAIN_LAKE_BED_DEEP :
						TERRAIN_LAKE_BED_SHALLOW;
				lake_flag_grid[static_cast<size_t>(sample_index)] = LAKE_FLAG_WATER_PRESENT;
			}
		}
	}

	for (int64_t local_y = 0; local_y < CHUNK_SIZE; ++local_y) {
		for (int64_t local_x = 0; local_x < CHUNK_SIZE; ++local_x) {
			const int64_t index = local_y * CHUNK_SIZE + local_x;
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + local_x;
			const int64_t world_y = clamp_foundation_world_y(
				static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + local_y,
				p_foundation_settings
			);
			const int64_t sample_world_x = resolve_mountain_sample_x(world_x, p_world_version, p_foundation_settings);
			const int64_t grid_x = local_x + mountain_border;
			const int64_t grid_y = local_y + mountain_border;
			const int64_t grid_index = grid_y * mountain_grid_side + grid_x;

			const float elevation = mountain_elevations[static_cast<size_t>(grid_index)];
			const int32_t resolved_mountain_id = mountain_ids[static_cast<size_t>(grid_index)];
			uint8_t resolved_mountain_flags = 0U;
			int32_t resolved_mountain_atlas_index = 0;
			int64_t terrain_id = terrain_id_grid[static_cast<size_t>(grid_index)];
			int64_t terrain_atlas_index = 0;
			uint8_t walkable = terrain_id == TERRAIN_MOUNTAIN_WALL || terrain_id == TERRAIN_MOUNTAIN_FOOT ? 0U : 1U;
			uint8_t lake_flag = lake_flag_grid[static_cast<size_t>(grid_index)];

			if (terrain_id == TERRAIN_PLAINS_GROUND) {
				const bool north_is_water = is_lake_bed_terrain(terrain_id_grid[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)]);
				const bool north_east_is_water = is_lake_bed_terrain(terrain_id_grid[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))]);
				const bool east_is_water = is_lake_bed_terrain(terrain_id_grid[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))]);
				const bool south_east_is_water = is_lake_bed_terrain(terrain_id_grid[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))]);
				const bool south_is_water = is_lake_bed_terrain(terrain_id_grid[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)]);
				const bool south_west_is_water = is_lake_bed_terrain(terrain_id_grid[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))]);
				const bool west_is_water = is_lake_bed_terrain(terrain_id_grid[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))]);
				const bool north_west_is_water = is_lake_bed_terrain(terrain_id_grid[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))]);
				terrain_atlas_index = resolve_base_ground_atlas_index(
					world_x,
					world_y,
					p_seed,
					!north_is_water,
					!north_east_is_water,
					!east_is_water,
					!south_east_is_water,
					!south_is_water,
					!south_west_is_water,
					!west_is_water,
					!north_west_is_water
				);
			} else if (terrain_id == TERRAIN_LAKE_BED_SHALLOW || terrain_id == TERRAIN_LAKE_BED_DEEP) {
				terrain_atlas_index = resolve_lake_bed_atlas_index(
					p_seed,
					wrap_foundation_world_x(world_x, p_foundation_settings),
					world_y,
					terrain_id_grid[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)] == terrain_id,
					terrain_id_grid[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))] == terrain_id,
					terrain_id_grid[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))] == terrain_id,
					terrain_id_grid[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))] == terrain_id,
					terrain_id_grid[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)] == terrain_id,
					terrain_id_grid[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))] == terrain_id,
					terrain_id_grid[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))] == terrain_id,
					terrain_id_grid[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))] == terrain_id
				);
				walkable = terrain_id == TERRAIN_LAKE_BED_SHALLOW ? 1U : 0U;
			}

			if (resolved_mountain_id > 0) {
				const int32_t north_id = mountain_ids[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)];
				const int32_t north_east_id = mountain_ids[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))];
				const int32_t east_id = mountain_ids[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))];
				const int32_t south_east_id = mountain_ids[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))];
				const int32_t south_id = mountain_ids[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)];
				const int32_t south_west_id = mountain_ids[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))];
				const int32_t west_id = mountain_ids[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))];
				const int32_t north_west_id = mountain_ids[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))];

				const bool is_wall = elevation >= mountain_thresholds.t_wall;
				const bool is_foot = elevation >= mountain_thresholds.t_edge && elevation < mountain_thresholds.t_wall;
				if (is_wall) {
					resolved_mountain_flags = static_cast<uint8_t>(resolved_mountain_flags | MOUNTAIN_FLAG_WALL);
				}
				if (is_foot) {
					resolved_mountain_flags = static_cast<uint8_t>(resolved_mountain_flags | MOUNTAIN_FLAG_FOOT);
				}
				if (is_wall) {
					bool is_interior = p_effective_mountain_settings.interior_margin == 0;
					if (p_effective_mountain_settings.interior_margin > 0) {
						is_interior = true;
						for (int32_t distance = 1; distance <= p_effective_mountain_settings.interior_margin; ++distance) {
							const int32_t north_check_id = mountain_ids[static_cast<size_t>((grid_y - distance) * mountain_grid_side + grid_x)];
							const int32_t east_check_id = mountain_ids[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + distance))];
							const int32_t south_check_id = mountain_ids[static_cast<size_t>((grid_y + distance) * mountain_grid_side + grid_x)];
							const int32_t west_check_id = mountain_ids[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - distance))];
							if (north_check_id != resolved_mountain_id ||
									east_check_id != resolved_mountain_id ||
									south_check_id != resolved_mountain_id ||
									west_check_id != resolved_mountain_id) {
								is_interior = false;
								break;
							}
							if (mountain_elevations[static_cast<size_t>((grid_y - distance) * mountain_grid_side + grid_x)] < mountain_thresholds.t_wall ||
									mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + distance))] < mountain_thresholds.t_wall ||
									mountain_elevations[static_cast<size_t>((grid_y + distance) * mountain_grid_side + grid_x)] < mountain_thresholds.t_wall ||
									mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - distance))] < mountain_thresholds.t_wall) {
								is_interior = false;
								break;
							}
						}
					}
					if (is_interior) {
						resolved_mountain_flags = static_cast<uint8_t>(resolved_mountain_flags | MOUNTAIN_FLAG_INTERIOR);
					}
					if (is_component_representative_tile(sample_world_x, world_y, resolved_mountain_id)) {
						resolved_mountain_flags = static_cast<uint8_t>(resolved_mountain_flags | MOUNTAIN_FLAG_ANCHOR);
					}
				}

				resolved_mountain_atlas_index = p_mountain_evaluator.resolve_mountain_atlas_index(
					sample_world_x,
					world_y,
					resolved_mountain_id,
					north_id,
					north_east_id,
					east_id,
					south_east_id,
					south_id,
					south_west_id,
					west_id,
					north_west_id
				);

				const bool north_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)] >= mountain_thresholds.t_edge;
				const bool north_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
				const bool east_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
				const bool south_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
				const bool south_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)] >= mountain_thresholds.t_edge;
				const bool south_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;
				const bool west_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;
				const bool north_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;

				if ((resolved_mountain_flags & MOUNTAIN_FLAG_WALL) != 0U) {
					terrain_id = TERRAIN_MOUNTAIN_WALL;
					terrain_atlas_index = resolve_mountain_base_atlas_index(
						p_seed,
						sample_world_x,
						world_y,
						north_is_mountain,
						north_east_is_mountain,
						east_is_mountain,
						south_east_is_mountain,
						south_is_mountain,
						south_west_is_mountain,
						west_is_mountain,
						north_west_is_mountain
					);
					walkable = 0U;
				} else if ((resolved_mountain_flags & MOUNTAIN_FLAG_FOOT) != 0U) {
					terrain_id = TERRAIN_MOUNTAIN_FOOT;
					terrain_atlas_index = resolve_mountain_base_atlas_index(
						p_seed,
						sample_world_x,
						world_y,
						north_is_mountain,
						north_east_is_mountain,
						east_is_mountain,
						south_east_is_mountain,
						south_is_mountain,
						south_west_is_mountain,
						west_is_mountain,
						north_west_is_mountain
					);
					walkable = 0U;
				}
			}

#ifdef DEBUG_ENABLED
			ERR_FAIL_COND_V_MSG(
				resolved_mountain_id > 0 &&
						is_lake_bed_terrain(terrain_id),
				Dictionary(),
				"Lake classification violated mountain-wins invariant inside WorldCore::_generate_chunk_packet."
			);
#endif
			if (!is_lake_bed_terrain(terrain_id)) {
				lake_flag = 0U;
			}

			terrain_ids.set(index, terrain_id);
			terrain_atlas_indices.set(index, terrain_atlas_index);
			walkable_flags.set(index, walkable);
			lake_flags.set(index, lake_flag);
			mountain_id_per_tile.set(index, resolved_mountain_id);
			mountain_flags.set(index, resolved_mountain_flags);
			mountain_atlas_indices.set(index, resolved_mountain_atlas_index);
		}
	}

	Dictionary packet;
	packet["chunk_coord"] = p_coord;
	packet["world_seed"] = p_seed;
	packet["world_version"] = p_world_version;
	packet["terrain_ids"] = terrain_ids;
	packet["terrain_atlas_indices"] = terrain_atlas_indices;
	packet["walkable_flags"] = walkable_flags;
	packet["lake_flags"] = lake_flags;
	packet["mountain_id_per_tile"] = mountain_id_per_tile;
	packet["mountain_flags"] = mountain_flags;
	packet["mountain_atlas_indices"] = mountain_atlas_indices;
	return packet;
}

Dictionary WorldCore::resolve_world_foundation_spawn_tile(
	int64_t p_seed,
	int64_t p_world_version,
	PackedFloat32Array p_settings_packed
) {
	if (p_world_version < WORLD_FOUNDATION_VERSION) {
		return make_failure_result("World foundation spawn resolution requires world foundation version.");
	}
	const int64_t expected_settings_count = expected_settings_count_for_version(p_world_version);
	if (p_settings_packed.size() != expected_settings_count) {
		return make_failure_result("World foundation spawn resolution received an invalid settings payload size.");
	}
	if (!mountain_field::uses_hierarchical_labeling(p_world_version)) {
		return make_failure_result("World foundation spawn resolution requires hierarchical mountain labeling.");
	}

	const FoundationSettings foundation_settings = unpack_foundation_settings(p_world_version, p_settings_packed);
	const LakeSettings lake_settings = unpack_lake_settings(p_world_version, p_settings_packed);
	const mountain_field::Settings mountain_settings = make_effective_mountain_settings(
		p_world_version,
		unpack_mountain_settings(p_settings_packed),
		foundation_settings
	);
	if (!foundation_settings.enabled) {
		return make_failure_result("World foundation settings are disabled.");
	}

	const mountain_field::Evaluator mountain_evaluator(p_seed, p_world_version, mountain_settings);
	const mountain_field::Settings &effective_mountain_settings = mountain_evaluator.get_settings();
	const world_prepass::Snapshot &snapshot = _get_or_build_world_prepass(
		p_seed,
		p_world_version,
		mountain_evaluator,
		effective_mountain_settings,
		foundation_settings,
		lake_settings
	);
	Dictionary result = resolve_world_foundation_spawn_tile_l6(
		snapshot,
		p_seed,
		p_world_version,
		foundation_settings,
		lake_settings,
		world_prepass_lake_basin_min_elevation_
	);
	result["grid_width"] = snapshot.grid_width;
	result["grid_height"] = snapshot.grid_height;
	result["coarse_cell_size_tiles"] = world_prepass::COARSE_CELL_SIZE_TILES;
	result["compute_time_ms"] = snapshot.compute_time_ms;
	return result;
}

#ifdef DEBUG_ENABLED
Dictionary WorldCore::get_world_foundation_snapshot(int64_t p_layer_mask, int64_t p_downscale_factor) {
	if (world_prepass_snapshot_ == nullptr || !world_prepass_snapshot_->valid) {
		return Dictionary();
	}
	return world_prepass::make_debug_snapshot(*world_prepass_snapshot_, p_layer_mask, p_downscale_factor);
}

Ref<Image> WorldCore::get_world_foundation_overview(int64_t p_layer_mask, int64_t p_pixels_per_cell) {
	if (world_prepass_snapshot_ == nullptr || !world_prepass_snapshot_->valid) {
		return Ref<Image>();
	}
	const mountain_field::Evaluator mountain_evaluator(
		world_prepass_snapshot_->seed,
		world_prepass_snapshot_->world_version,
		world_prepass_effective_mountain_settings_
	);
	return world_prepass::make_overview_image(
		*world_prepass_snapshot_,
		mountain_evaluator,
		world_prepass_snapshot_->world_version,
		world_prepass_foundation_settings_,
		world_prepass_lake_settings_,
		p_layer_mask,
		p_pixels_per_cell
	);
}
#endif

Array WorldCore::generate_chunk_packets_batch(
	int64_t p_seed,
	PackedVector2Array p_coords,
	int64_t p_world_version,
	PackedFloat32Array p_settings_packed
) {
	Array packets;
	packets.resize(p_coords.size());
	if (p_coords.is_empty()) {
		return packets;
	}

	const int64_t expected_settings_count = expected_settings_count_for_version(p_world_version);
	ERR_FAIL_COND_V_MSG(
		p_settings_packed.size() != expected_settings_count,
		Array{},
		"WorldCore.generate_chunk_packets_batch received an invalid settings payload size."
	);
	ERR_FAIL_COND_V_MSG(
		!mountain_field::uses_hierarchical_labeling(p_world_version),
		Array{},
		"WorldCore.generate_chunk_packets_batch requires hierarchical mountain labeling (world_version >= 6)."
	);

	const FoundationSettings foundation_settings = unpack_foundation_settings(p_world_version, p_settings_packed);
	const LakeSettings lake_settings = unpack_lake_settings(p_world_version, p_settings_packed);
	const mountain_field::Settings mountain_settings = make_effective_mountain_settings(
		p_world_version,
		unpack_mountain_settings(p_settings_packed),
		foundation_settings
	);
	const mountain_field::Evaluator mountain_evaluator(p_seed, p_world_version, mountain_settings);
	const mountain_field::Settings &effective_mountain_settings = mountain_evaluator.get_settings();
	const int32_t macro_cell_size = mountain_field::get_hierarchical_macro_cell_size(p_world_version);

	std::vector<ChunkMacroGroup> macro_groups;
	std::unordered_map<uint64_t, int32_t> group_index_by_key;
	for (int32_t index = 0; index < p_coords.size(); ++index) {
		const Vector2 coord_value = p_coords[index];
		const Vector2i chunk_coord = canonicalize_chunk_coord(Vector2i(
			static_cast<int32_t>(coord_value.x),
			static_cast<int32_t>(coord_value.y)
		), foundation_settings);
		const int64_t chunk_origin_x = resolve_mountain_sample_x(
			static_cast<int64_t>(chunk_coord.x) * CHUNK_SIZE,
			p_world_version,
			foundation_settings
		);
		const int64_t chunk_origin_y = clamp_foundation_world_y(
			static_cast<int64_t>(chunk_coord.y) * CHUNK_SIZE,
			foundation_settings
		);
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(
			chunk_origin_x,
			macro_cell_size,
			effective_mountain_settings.world_wrap_width_tiles
		);
		const int64_t macro_cell_y = resolve_macro_cell_y_for_world(chunk_origin_y, macro_cell_size);
		const uint64_t macro_key = make_macro_key(macro_cell_x, macro_cell_y);

		auto found = group_index_by_key.find(macro_key);
		if (found == group_index_by_key.end()) {
			ChunkMacroGroup group;
			group.macro_cell_x = macro_cell_x;
			group.macro_cell_y = macro_cell_y;
			macro_groups.push_back(std::move(group));
			const int32_t group_index = static_cast<int32_t>(macro_groups.size() - 1);
			group_index_by_key.emplace(macro_key, group_index);
			found = group_index_by_key.find(macro_key);
		}

		macro_groups[static_cast<size_t>(found->second)].chunk_indices.push_back(index);
	}

	for (const ChunkMacroGroup &group : macro_groups) {
		_get_or_build_hierarchical_macro_solve(
			p_seed,
			p_world_version,
			effective_mountain_settings,
			foundation_settings,
			group.macro_cell_x,
			group.macro_cell_y
		);
		for (int32_t packet_index : group.chunk_indices) {
			const Vector2 coord_value = p_coords[packet_index];
			const Vector2i chunk_coord = canonicalize_chunk_coord(Vector2i(
				static_cast<int32_t>(coord_value.x),
				static_cast<int32_t>(coord_value.y)
			), foundation_settings);
			packets[packet_index] = _generate_chunk_packet(
				p_seed,
				chunk_coord,
				p_world_version,
				mountain_evaluator,
				effective_mountain_settings,
				foundation_settings,
				lake_settings
			);
		}
	}
	return packets;
}
