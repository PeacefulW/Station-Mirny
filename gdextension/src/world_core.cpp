#include "world_core.h"
#include "autotile_47.h"
#include "grass_scatter.h"
#include "lake_field.h"
#include "mountain_contour.h"
#include "mountain_field.h"
#include "mountain_plateau_raster.h"
#include "world_utils.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <unordered_map>
#include <unordered_set>
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
constexpr int64_t MOUNTAIN_SATELLITE_OUTCROP_CLUSTER_VERSION = 47;
constexpr int64_t MOUNTAIN_PASSAGE_OUTCROP_REFINEMENT_VERSION = 48;
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
constexpr int32_t SATELLITE_OUTCROP_ANCHOR_CELL_SIZE = 16;
constexpr int32_t SATELLITE_OUTCROP_SCAN_MARGIN_TILES = 32;
constexpr int32_t SATELLITE_OUTCROP_MIN_MAIN_DISTANCE_TILES = 2;
constexpr int32_t SATELLITE_OUTCROP_MAX_MAIN_DISTANCE_TILES = 14;
constexpr int32_t SATELLITE_OUTCROP_MIN_CELLS = 3;
constexpr int32_t SATELLITE_OUTCROP_MAX_CELLS = 18;
constexpr int32_t SATELLITE_OUTCROP_CLUSTER_MIN_COUNT = 2;
constexpr int32_t SATELLITE_OUTCROP_CLUSTER_MAX_COUNT = 20;
constexpr int32_t SATELLITE_OUTCROP_CLUSTER_ATTEMPTS = 52;
constexpr int32_t SATELLITE_OUTCROP_REFINED_CLUSTER_ATTEMPTS = 72;
constexpr int32_t SATELLITE_OUTCROP_CLUSTER_SPREAD_TILES = 15;
constexpr int32_t SATELLITE_OUTCROP_REFINED_CLUSTER_SPREAD_TILES = 21;
constexpr int32_t SATELLITE_OUTCROP_ID_BASE = 0x60000000;
constexpr int32_t SATELLITE_OUTCROP_ID_MASK = 0x0fffffff;
constexpr float SATELLITE_OUTCROP_BASE_CHANCE = 0.018f;
constexpr float SATELLITE_OUTCROP_DENSITY_CHANCE = 0.13f;
constexpr float SATELLITE_OUTCROP_REFINED_DENSITY_CHANCE = 0.17f;
constexpr uint64_t SATELLITE_OUTCROP_HASH_SALT = 0x4d51d1b8f6a4c3e9ULL;
constexpr int32_t MOUNTAIN_PASSAGE_ANCHOR_CELL_SIZE = 32;
constexpr float MOUNTAIN_PASSAGE_BASE_CHANCE = 0.026f;
constexpr float MOUNTAIN_PASSAGE_DENSITY_CHANCE = 0.092f;
constexpr float MOUNTAIN_PASSAGE_TAU = 6.2831853071795864769f;
constexpr uint64_t MOUNTAIN_PASSAGE_HASH_SALT = 0xb71c8e5d4f39a602ULL;

constexpr int32_t TILE_SIZE_PX = 64;
constexpr int32_t CHUNK_SIZE_PX = static_cast<int32_t>(CHUNK_SIZE) * TILE_SIZE_PX;
constexpr uint8_t OBJECT_KIND_ROCK = 1U;
constexpr uint8_t OBJECT_KIND_LIVING_FLORA = 2U;
constexpr uint8_t OBJECT_KIND_SPIKY_FLORA = 3U;
constexpr uint8_t OBJECT_KIND_TREE = 4U;
constexpr uint8_t OBJECT_FLAG_COLLIDER = 1U << 0U;
constexpr int32_t OBJECT_LOCAL_PX_QUANTUM = 4;
constexpr float OBJECT_MOUNTAIN_CLEARANCE_PX = 64.0f;

constexpr int32_t ROCK_FRAME_COUNT = 32;
constexpr int32_t ROCK_ATLAS_COUNT = 4;
constexpr int32_t ROCK_SCATTER_GRID_SIDE = 8;
constexpr float ROCK_PRIMARY_DENSITY = 0.23f;
constexpr float ROCK_SATELLITE_DENSITY = 0.18f;
constexpr float ROCK_VOLCANIC_CHANCE = 0.08f;
constexpr float ROCK_EDGE_PADDING_PX = 18.0f;
constexpr float ROCK_VISUAL_SCALE = 0.5f;
constexpr float ROCK_LARGE_COLLISION_MIN_SIZE_PX = 42.0f;
constexpr uint8_t RARE_ROCK_FORMATION_ATLAS_INDEX = 3U;
constexpr int32_t RARE_ROCK_FORMATION_VARIANT_COUNT = 8;
constexpr float RARE_ROCK_FORMATION_PATCH_CELL_PX = 1280.0f;
constexpr float RARE_ROCK_FORMATION_PATCH_DENSITY = 0.54f;
constexpr float RARE_ROCK_FORMATION_PATCH_THRESHOLD = 0.62f;
constexpr float RARE_ROCK_FORMATION_PATCH_CLEARANCE_THRESHOLD = 0.30f;
constexpr float RARE_ROCK_FORMATION_PLACEMENT_CELL_PX = 2048.0f;
constexpr int32_t RARE_ROCK_FORMATION_MAX_PER_CHUNK = 1;
constexpr float RARE_ROCK_FORMATION_EDGE_PADDING_PX = 112.0f;
constexpr float RARE_ROCK_FORMATION_TERRAIN_CLEARANCE_PX = 96.0f;
constexpr float RARE_ROCK_FORMATION_PATCH_CLEARANCE_PX = 96.0f;
constexpr float RARE_ROCK_FORMATION_MIN_SIZE_PX = 214.0f;
constexpr float RARE_ROCK_FORMATION_MAX_SIZE_PX = 255.0f;

constexpr int32_t LIVING_FLORA_SCATTER_GRID_SIDE = 10;
constexpr float LIVING_FLORA_PRIMARY_DENSITY = 0.42f;
constexpr int32_t LIVING_FLORA_MAX_PER_CHUNK = 18;
constexpr float LIVING_FLORA_EDGE_PADDING_PX = 24.0f;
constexpr float LIVING_FLORA_MIN_SIZE_PX = 84.0f;
constexpr float LIVING_FLORA_MAX_SIZE_PX = 112.0f;
constexpr float LIVING_FLORA_PATCH_CELL_PX = 1850.0f;
constexpr float LIVING_FLORA_PATCH_DENSITY = 0.54f;
constexpr float LIVING_FLORA_PATCH_THRESHOLD = 0.50f;

constexpr int32_t SPIKY_FLORA_CANDIDATE_COUNT = 48;
constexpr int32_t SPIKY_FLORA_MAX_PER_CHUNK = 2;
constexpr uint8_t SPIKY_FLORA_ATLAS_SPIKY_PLANT = 0U;
constexpr uint8_t SPIKY_FLORA_ATLAS_BROWN_SEAWEED = 1U;
constexpr float SPIKY_FLORA_EDGE_PADDING_PX = 36.0f;
constexpr float SPIKY_FLORA_MIN_SIZE_PX = 58.0f;
constexpr float SPIKY_FLORA_MAX_SIZE_PX = 220.0f;
constexpr float SPIKY_FLORA_SIZE_EXPONENT = 1.65f;
constexpr float SPIKY_FLORA_MIN_DISTANCE_PX = 158.0f;
constexpr float SPIKY_FLORA_PATCH_CELL_PX = 2750.0f;
constexpr float SPIKY_FLORA_PATCH_DENSITY = 0.72f;
constexpr float SPIKY_FLORA_PLACEMENT_THRESHOLD = 0.36f;
constexpr float SPIKY_FLORA_MIN_DENSITY = 0.01f;
constexpr float SPIKY_FLORA_MAX_DENSITY = 0.06f;
constexpr int32_t BIOFIELD_SEAWEED_CANDIDATE_COUNT = 96;
constexpr int32_t BIOFIELD_SEAWEED_MAX_PER_CHUNK = 5;
constexpr float BIOFIELD_SEAWEED_EDGE_PADDING_PX = 34.0f;
constexpr float BIOFIELD_SEAWEED_MIN_SIZE_PX = 42.0f;
constexpr float BIOFIELD_SEAWEED_MAX_SIZE_PX = 84.0f;
constexpr float BIOFIELD_SEAWEED_SIZE_EXPONENT = 1.24f;
constexpr float BIOFIELD_SEAWEED_MIN_DISTANCE_PX = 92.0f;
constexpr float BIOFIELD_SEAWEED_MIN_DENSITY = 0.025f;
constexpr float BIOFIELD_SEAWEED_MAX_DENSITY = 0.14f;

// Деревья равнины (docs/02_system_specs/world/plains_trees_presentation.md):
// прореженный «проходимый» лес. size_px <= 254 (байтовый квант пакета); крупные
// деревья ограничиваются клампом, без расширения пакета (Open Question спеки).
constexpr int32_t TREE_ATLAS_VARIANT_COUNT = 16;
constexpr int32_t TREE_SCATTER_GRID_SIDE = 6;
constexpr float TREE_PRIMARY_DENSITY = 0.62f;
constexpr float TREE_EDGE_PADDING_PX = 40.0f;
constexpr float TREE_MIN_DISTANCE_PX = 88.0f;
constexpr float TREE_MIN_SIZE_PX = 150.0f;
constexpr float TREE_MAX_SIZE_PX = 244.0f;
constexpr float TREE_SMALL_CHANCE = 0.20f;
constexpr float TREE_SMALL_SIZE_PX = 120.0f;
constexpr float TREE_HERO_CHANCE = 0.10f;
constexpr float TREE_HERO_SIZE_PX = 252.0f;

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

struct SatelliteOutcropCandidate {
	int64_t anchor_cell_x = 0;
	int64_t anchor_cell_y = 0;
	int64_t center_x = 0;
	int64_t center_y = 0;
	float radius_x = 1.5f;
	float radius_y = 1.5f;
	float wobble = 0.0f;
	int32_t shape_mode = 0;
	int32_t shape_orientation = 0;
	int32_t mountain_id = 0;
};

struct SatelliteOutcropHit {
	bool active = false;
	int32_t mountain_id = 0;
	float elevation = 0.0f;
};

struct WorldObjectPacketBuffers {
	std::vector<uint8_t> kind;
	std::vector<uint8_t> local_x_px_q4;
	std::vector<uint8_t> local_y_px_q4;
	std::vector<uint8_t> size_px;
	std::vector<uint8_t> atlas_index;
	std::vector<uint8_t> variant;
	std::vector<uint8_t> flags;
	std::vector<uint8_t> tint;
	std::vector<uint8_t> phase;
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

uint64_t hash_satellite_outcrop_anchor(
	int64_t p_seed,
	int64_t p_world_version,
	int64_t p_anchor_cell_x,
	int64_t p_anchor_cell_y,
	int64_t p_world_wrap_width_tiles
) {
	const int64_t anchor_cells_per_wrap = std::max<int64_t>(
		1,
		(p_world_wrap_width_tiles + SATELLITE_OUTCROP_ANCHOR_CELL_SIZE - 1) / SATELLITE_OUTCROP_ANCHOR_CELL_SIZE
	);
	const int64_t wrapped_anchor_x = positive_mod(p_anchor_cell_x, anchor_cells_per_wrap);
	uint64_t mixed = world_utils::mix_seed(p_seed, p_world_version, SATELLITE_OUTCROP_HASH_SALT);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(wrapped_anchor_x) * 0x9e3779b185ebca87ULL);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_anchor_cell_y) * 0xc2b2ae3d27d4eb4fULL);
	return mixed;
}

uint64_t hash_mountain_passage_anchor(
	int64_t p_seed,
	int64_t p_world_version,
	int64_t p_anchor_cell_x,
	int64_t p_anchor_cell_y,
	int64_t p_world_wrap_width_tiles
) {
	const int64_t anchor_cells_per_wrap = std::max<int64_t>(
		1,
		(p_world_wrap_width_tiles + MOUNTAIN_PASSAGE_ANCHOR_CELL_SIZE - 1) / MOUNTAIN_PASSAGE_ANCHOR_CELL_SIZE
	);
	const int64_t wrapped_anchor_x = positive_mod(p_anchor_cell_x, anchor_cells_per_wrap);
	uint64_t mixed = world_utils::mix_seed(p_seed, p_world_version, MOUNTAIN_PASSAGE_HASH_SALT);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(wrapped_anchor_x) * 0x94d049bb133111ebULL);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_anchor_cell_y) * 0xd2b74407b1ce6e93ULL);
	return mixed;
}

float hash_unit_float(uint64_t p_hash, uint32_t p_shift) {
	return static_cast<float>((p_hash >> p_shift) & 0xffffU) / 65535.0f;
}

float smoothstep01(float p_edge0, float p_edge1, float p_value) {
	const float t = world_utils::clamp_value((p_value - p_edge0) / std::max(0.0001f, p_edge1 - p_edge0), 0.0f, 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

float fract_float(float p_value) {
	return p_value - std::floor(p_value);
}

float lerp_float(float p_a, float p_b, float p_t) {
	return p_a + (p_b - p_a) * p_t;
}

uint8_t quantize_byte(float p_value) {
	return static_cast<uint8_t>(world_utils::clamp_value(static_cast<int32_t>(std::lround(p_value)), 0, 255));
}

uint8_t quantize_local_px_q4(float p_value) {
	return quantize_byte(p_value / static_cast<float>(OBJECT_LOCAL_PX_QUANTUM));
}

uint64_t object_hash4(int64_t p_a, int64_t p_b, int64_t p_c, int64_t p_d) {
	uint64_t value = splitmix64(static_cast<uint64_t>(p_a) * 0x9e3779b185ebca87ULL);
	value = splitmix64(value ^ static_cast<uint64_t>(p_b) * 0xc2b2ae3d27d4eb4fULL);
	value = splitmix64(value ^ static_cast<uint64_t>(p_c) * 0x165667b19e3779f9ULL);
	value = splitmix64(value ^ static_cast<uint64_t>(p_d) * 0x85ebca77c2b2ae63ULL);
	return value;
}

float object_unit(uint64_t p_hash, uint64_t p_salt) {
	return hash_unit_float(splitmix64(p_hash ^ p_salt), 0U);
}

float object_hash12(float p_x, float p_y) {
	float p3x = fract_float(p_x * 0.1031f);
	float p3y = fract_float(p_y * 0.1031f);
	float p3z = fract_float(p_x * 0.1031f);
	const float d = p3x * (p3y + 33.33f) + p3y * (p3z + 33.33f) + p3z * (p3x + 33.33f);
	p3x += d;
	p3y += d;
	p3z += d;
	return fract_float((p3x + p3y) * p3z);
}

float object_value_noise(float p_x, float p_y) {
	const float ix = std::floor(p_x);
	const float iy = std::floor(p_y);
	const float fx = p_x - ix;
	const float fy = p_y - iy;
	const float ux = fx * fx * (3.0f - 2.0f * fx);
	const float uy = fy * fy * (3.0f - 2.0f * fy);
	const float a = object_hash12(ix, iy);
	const float b = object_hash12(ix + 1.0f, iy);
	const float c = object_hash12(ix, iy + 1.0f);
	const float d = object_hash12(ix + 1.0f, iy + 1.0f);
	return lerp_float(lerp_float(a, b, ux), lerp_float(c, d, ux), uy);
}

float object_fbm2(float p_x, float p_y) {
	float x = p_x;
	float y = p_y;
	float value = 0.0f;
	float amplitude = 0.56f;
	float total = 0.0f;
	for (int32_t index = 0; index < 3; ++index) {
		value += object_value_noise(x, y) * amplitude;
		total += amplitude;
		x = x * 2.03f + 19.7f;
		y = y * 2.03f - 11.2f;
		amplitude *= 0.48f;
	}
	return value / std::max(total, 0.0001f);
}

float object_rock_patch_fbm2(float p_x, float p_y) {
	float x = p_x;
	float y = p_y;
	float value = 0.0f;
	float amplitude = 0.56f;
	float total = 0.0f;
	for (int32_t index = 0; index < 4; ++index) {
		value += object_value_noise(x, y) * amplitude;
		total += amplitude;
		x = x * 2.03f + 19.7f;
		y = y * 2.03f - 11.2f;
		amplitude *= 0.48f;
	}
	return value / std::max(total, 0.0001f);
}

float object_organic_region_mask(float p_world_px_x, float p_world_px_y, float p_cell_px, float p_density) {
	const float px = p_world_px_x / std::max(p_cell_px, 1.0f);
	const float py = p_world_px_y / std::max(p_cell_px, 1.0f);
	const float broad_warp_x = object_fbm2(px * 0.72f + 13.4f, py * 0.72f - 8.9f) - 0.5f;
	const float broad_warp_y = object_fbm2(px * 0.69f - 31.7f, py * 0.69f + 24.1f) - 0.5f;
	const float local_warp_x = object_fbm2(px * 1.86f + 71.0f, py * 1.86f + 9.5f) - 0.5f;
	const float local_warp_y = object_fbm2(px * 1.61f - 44.6f, py * 1.61f + 58.2f) - 0.5f;
	const float wx = px + broad_warp_x * 1.55f + local_warp_x * 0.42f;
	const float wy = py + broad_warp_y * 1.55f + local_warp_y * 0.42f;
	const float large_regions = object_fbm2(wx * 0.94f + 5.1f, wy * 0.94f + 17.3f);
	const float medium_cut = object_fbm2(wx * 2.15f - 19.0f, wy * 2.15f + 41.0f);
	const float edge_breakup = object_fbm2(wx * 5.8f + 62.0f, wy * 5.8f - 27.0f);
	float field = large_regions * 0.70f + medium_cut * 0.22f + edge_breakup * 0.08f;
	field += (edge_breakup - 0.5f) * 0.10f;
	const float threshold = lerp_float(0.76f, 0.43f, world_utils::clamp_value(p_density, 0.0f, 1.0f));
	float region = smoothstep01(threshold - 0.065f, threshold + 0.085f, field);
	const float erosion = object_fbm2(wx * 8.5f - 3.0f, wy * 8.5f + 103.0f);
	region = world_utils::clamp_value(region + (erosion - 0.52f) * 0.18f, 0.0f, 1.0f);
	return smoothstep01(0.16f, 0.86f, region);
}

float object_rock_patch_mask(float p_world_px_x, float p_world_px_y, float p_cell_px, float p_density) {
	const float px = p_world_px_x / std::max(p_cell_px, 1.0f);
	const float py = p_world_px_y / std::max(p_cell_px, 1.0f);
	const float broad_warp_x = object_rock_patch_fbm2(px * 0.56f - 18.0f, py * 0.56f + 42.0f) - 0.5f;
	const float broad_warp_y = object_rock_patch_fbm2(px * 0.61f + 73.0f, py * 0.61f - 15.0f) - 0.5f;
	const float local_warp_x = object_rock_patch_fbm2(px * 1.73f + 9.0f, py * 1.73f + 84.0f) - 0.5f;
	const float local_warp_y = object_rock_patch_fbm2(px * 1.58f - 61.0f, py * 1.58f + 23.0f) - 0.5f;
	const float wx = px + broad_warp_x * 1.65f + local_warp_x * 0.50f;
	const float wy = py + broad_warp_y * 1.65f + local_warp_y * 0.50f;

	const float large_regions = object_rock_patch_fbm2(wx * 0.82f + 14.0f, wy * 0.82f - 37.0f);
	const float medium_cut = object_rock_patch_fbm2(wx * 2.75f - 41.0f, wy * 2.75f + 18.0f);
	const float edge_breakup = object_rock_patch_fbm2(wx * 6.8f + 87.0f, wy * 6.8f + 36.0f);
	float field = large_regions * 0.76f + medium_cut * 0.16f + edge_breakup * 0.08f;
	field += (edge_breakup - 0.5f) * 0.13f;

	const float threshold = lerp_float(0.82f, 0.50f, world_utils::clamp_value(p_density, 0.0f, 1.0f));
	float region = smoothstep01(threshold - 0.055f, threshold + 0.095f, field);
	const float erosion = object_rock_patch_fbm2(wx * 9.6f + 51.0f, wy * 9.6f - 103.0f);
	region = world_utils::clamp_value(region + (erosion - 0.54f) * 0.16f, 0.0f, 1.0f);
	return smoothstep01(0.20f, 0.92f, region);
}

PackedByteArray make_packed_byte_array(const std::vector<uint8_t> &p_values) {
	PackedByteArray result;
	result.resize(static_cast<int32_t>(p_values.size()));
	for (int32_t index = 0; index < static_cast<int32_t>(p_values.size()); ++index) {
		result.set(index, p_values[static_cast<size_t>(index)]);
	}
	return result;
}

void append_object_record(
	WorldObjectPacketBuffers &r_buffers,
	uint8_t p_kind,
	float p_local_x_px,
	float p_local_y_px,
	float p_size_px,
	uint8_t p_atlas_index,
	uint8_t p_variant,
	uint8_t p_flags,
	float p_tint,
	float p_phase
) {
	r_buffers.kind.push_back(p_kind);
	r_buffers.local_x_px_q4.push_back(quantize_local_px_q4(p_local_x_px));
	r_buffers.local_y_px_q4.push_back(quantize_local_px_q4(p_local_y_px));
	r_buffers.size_px.push_back(quantize_byte(p_size_px));
	r_buffers.atlas_index.push_back(p_atlas_index);
	r_buffers.variant.push_back(p_variant);
	r_buffers.flags.push_back(p_flags);
	r_buffers.tint.push_back(quantize_byte(world_utils::clamp_value(p_tint, 0.0f, 1.0f) * 255.0f));
	r_buffers.phase.push_back(quantize_byte(world_utils::clamp_value(p_phase, 0.0f, 1.0f) * 255.0f));
}

bool object_position_is_plain(
	float p_local_x_px,
	float p_local_y_px,
	const PackedInt32Array &p_terrain_ids,
	const PackedByteArray &p_lake_flags
) {
	if (p_local_x_px < 0.0f || p_local_y_px < 0.0f || p_local_x_px >= static_cast<float>(CHUNK_SIZE_PX) || p_local_y_px >= static_cast<float>(CHUNK_SIZE_PX)) {
		return false;
	}
	const int32_t local_x = static_cast<int32_t>(std::floor(p_local_x_px / static_cast<float>(TILE_SIZE_PX)));
	const int32_t local_y = static_cast<int32_t>(std::floor(p_local_y_px / static_cast<float>(TILE_SIZE_PX)));
	if (local_x < 0 || local_y < 0 || local_x >= CHUNK_SIZE || local_y >= CHUNK_SIZE) {
		return false;
	}
	const int32_t index = local_y * static_cast<int32_t>(CHUNK_SIZE) + local_x;
	if (read_int32_at(p_terrain_ids, index, TERRAIN_MOUNTAIN_WALL) != TERRAIN_PLAINS_GROUND) {
		return false;
	}
	return (read_byte_at(p_lake_flags, index, 0) & LAKE_FLAG_WATER_PRESENT) == 0;
}

bool object_position_is_mountain_surface(
	float p_local_x_px,
	float p_local_y_px,
	const PackedInt32Array &p_terrain_ids
) {
	if (p_local_x_px < 0.0f || p_local_y_px < 0.0f || p_local_x_px >= static_cast<float>(CHUNK_SIZE_PX) || p_local_y_px >= static_cast<float>(CHUNK_SIZE_PX)) {
		return false;
	}
	const int32_t local_x = static_cast<int32_t>(std::floor(p_local_x_px / static_cast<float>(TILE_SIZE_PX)));
	const int32_t local_y = static_cast<int32_t>(std::floor(p_local_y_px / static_cast<float>(TILE_SIZE_PX)));
	if (local_x < 0 || local_y < 0 || local_x >= CHUNK_SIZE || local_y >= CHUNK_SIZE) {
		return false;
	}
	const int32_t index = local_y * static_cast<int32_t>(CHUNK_SIZE) + local_x;
	const int32_t terrain_id = read_int32_at(p_terrain_ids, index, TERRAIN_MOUNTAIN_WALL);
	return terrain_id == TERRAIN_MOUNTAIN_WALL || terrain_id == TERRAIN_MOUNTAIN_FOOT;
}

bool object_position_has_mountain_clearance(
	float p_local_x_px,
	float p_local_y_px,
	const PackedInt32Array &p_terrain_ids,
	float p_clearance_px
) {
	if (object_position_is_mountain_surface(p_local_x_px, p_local_y_px, p_terrain_ids)) {
		return false;
	}
	const float diagonal_clearance = p_clearance_px * 0.72f;
	return !object_position_is_mountain_surface(p_local_x_px + p_clearance_px, p_local_y_px, p_terrain_ids) &&
			!object_position_is_mountain_surface(p_local_x_px - p_clearance_px, p_local_y_px, p_terrain_ids) &&
			!object_position_is_mountain_surface(p_local_x_px, p_local_y_px + p_clearance_px, p_terrain_ids) &&
			!object_position_is_mountain_surface(p_local_x_px, p_local_y_px - p_clearance_px, p_terrain_ids) &&
			!object_position_is_mountain_surface(p_local_x_px + diagonal_clearance, p_local_y_px + diagonal_clearance, p_terrain_ids) &&
			!object_position_is_mountain_surface(p_local_x_px - diagonal_clearance, p_local_y_px + diagonal_clearance, p_terrain_ids) &&
			!object_position_is_mountain_surface(p_local_x_px + diagonal_clearance, p_local_y_px - diagonal_clearance, p_terrain_ids) &&
			!object_position_is_mountain_surface(p_local_x_px - diagonal_clearance, p_local_y_px - diagonal_clearance, p_terrain_ids);
}

bool object_position_is_plain_with_clearance(
	float p_local_x_px,
	float p_local_y_px,
	const PackedInt32Array &p_terrain_ids,
	const PackedByteArray &p_lake_flags,
	float p_clearance_px
) {
	if (!object_position_is_plain(p_local_x_px, p_local_y_px, p_terrain_ids, p_lake_flags)) {
		return false;
	}
	const float diagonal_clearance = p_clearance_px * 0.72f;
	return object_position_is_plain(p_local_x_px + p_clearance_px, p_local_y_px, p_terrain_ids, p_lake_flags) &&
			object_position_is_plain(p_local_x_px - p_clearance_px, p_local_y_px, p_terrain_ids, p_lake_flags) &&
			object_position_is_plain(p_local_x_px, p_local_y_px + p_clearance_px, p_terrain_ids, p_lake_flags) &&
			object_position_is_plain(p_local_x_px, p_local_y_px - p_clearance_px, p_terrain_ids, p_lake_flags) &&
			object_position_is_plain(p_local_x_px + diagonal_clearance, p_local_y_px + diagonal_clearance, p_terrain_ids, p_lake_flags) &&
			object_position_is_plain(p_local_x_px - diagonal_clearance, p_local_y_px + diagonal_clearance, p_terrain_ids, p_lake_flags) &&
			object_position_is_plain(p_local_x_px + diagonal_clearance, p_local_y_px - diagonal_clearance, p_terrain_ids, p_lake_flags) &&
			object_position_is_plain(p_local_x_px - diagonal_clearance, p_local_y_px - diagonal_clearance, p_terrain_ids, p_lake_flags);
}

bool object_rare_rock_patch_has_clearance(float p_world_px_x, float p_world_px_y) {
	if (object_rock_patch_mask(
				p_world_px_x,
				p_world_px_y,
				RARE_ROCK_FORMATION_PATCH_CELL_PX,
				RARE_ROCK_FORMATION_PATCH_DENSITY) < RARE_ROCK_FORMATION_PATCH_THRESHOLD) {
		return false;
	}
	const float clearance = RARE_ROCK_FORMATION_PATCH_CLEARANCE_PX;
	const float diagonal_clearance = clearance * 0.72f;
	return object_rock_patch_mask(p_world_px_x + clearance, p_world_px_y, RARE_ROCK_FORMATION_PATCH_CELL_PX, RARE_ROCK_FORMATION_PATCH_DENSITY) >= RARE_ROCK_FORMATION_PATCH_CLEARANCE_THRESHOLD &&
			object_rock_patch_mask(p_world_px_x - clearance, p_world_px_y, RARE_ROCK_FORMATION_PATCH_CELL_PX, RARE_ROCK_FORMATION_PATCH_DENSITY) >= RARE_ROCK_FORMATION_PATCH_CLEARANCE_THRESHOLD &&
			object_rock_patch_mask(p_world_px_x, p_world_px_y + clearance, RARE_ROCK_FORMATION_PATCH_CELL_PX, RARE_ROCK_FORMATION_PATCH_DENSITY) >= RARE_ROCK_FORMATION_PATCH_CLEARANCE_THRESHOLD &&
			object_rock_patch_mask(p_world_px_x, p_world_px_y - clearance, RARE_ROCK_FORMATION_PATCH_CELL_PX, RARE_ROCK_FORMATION_PATCH_DENSITY) >= RARE_ROCK_FORMATION_PATCH_CLEARANCE_THRESHOLD &&
			object_rock_patch_mask(p_world_px_x + diagonal_clearance, p_world_px_y + diagonal_clearance, RARE_ROCK_FORMATION_PATCH_CELL_PX, RARE_ROCK_FORMATION_PATCH_DENSITY) >= RARE_ROCK_FORMATION_PATCH_CLEARANCE_THRESHOLD &&
			object_rock_patch_mask(p_world_px_x - diagonal_clearance, p_world_px_y + diagonal_clearance, RARE_ROCK_FORMATION_PATCH_CELL_PX, RARE_ROCK_FORMATION_PATCH_DENSITY) >= RARE_ROCK_FORMATION_PATCH_CLEARANCE_THRESHOLD &&
			object_rock_patch_mask(p_world_px_x + diagonal_clearance, p_world_px_y - diagonal_clearance, RARE_ROCK_FORMATION_PATCH_CELL_PX, RARE_ROCK_FORMATION_PATCH_DENSITY) >= RARE_ROCK_FORMATION_PATCH_CLEARANCE_THRESHOLD &&
			object_rock_patch_mask(p_world_px_x - diagonal_clearance, p_world_px_y - diagonal_clearance, RARE_ROCK_FORMATION_PATCH_CELL_PX, RARE_ROCK_FORMATION_PATCH_DENSITY) >= RARE_ROCK_FORMATION_PATCH_CLEARANCE_THRESHOLD;
}

void append_native_rock_object(
	WorldObjectPacketBuffers &r_buffers,
	Vector2i p_coord,
	int64_t p_seed,
	int64_t p_world_version,
	const PackedInt32Array &p_terrain_ids,
	const PackedByteArray &p_lake_flags,
	float p_local_x_px,
	float p_local_y_px,
	uint64_t p_salt,
	bool p_is_satellite,
	bool p_used_variants[ROCK_ATLAS_COUNT][ROCK_FRAME_COUNT]
) {
	if (p_local_x_px < ROCK_EDGE_PADDING_PX ||
			p_local_y_px < ROCK_EDGE_PADDING_PX ||
			p_local_x_px > static_cast<float>(CHUNK_SIZE_PX) - ROCK_EDGE_PADDING_PX ||
			p_local_y_px > static_cast<float>(CHUNK_SIZE_PX) - ROCK_EDGE_PADDING_PX ||
			!object_position_is_plain(p_local_x_px, p_local_y_px, p_terrain_ids, p_lake_flags) ||
			!object_position_has_mountain_clearance(p_local_x_px, p_local_y_px, p_terrain_ids, OBJECT_MOUNTAIN_CLEARANCE_PX)) {
		return;
	}
	const float atlas_roll = object_unit(p_salt, 0x79ULL);
	uint8_t atlas_index = 0U;
	if (atlas_roll < ROCK_VOLCANIC_CHANCE) {
		atlas_index = 2U;
	} else if (atlas_roll >= 0.54f) {
		atlas_index = 1U;
	}
	int32_t frame_index = static_cast<int32_t>(std::floor(object_unit(p_salt, 0x97ULL) * ROCK_FRAME_COUNT)) % ROCK_FRAME_COUNT;
	for (int32_t offset = 0; offset < ROCK_FRAME_COUNT; ++offset) {
		const int32_t candidate = (frame_index + offset * 7) % ROCK_FRAME_COUNT;
		if (p_used_variants[atlas_index][candidate]) {
			continue;
		}
		p_used_variants[atlas_index][candidate] = true;
		frame_index = candidate;
		break;
	}
	float size_px = lerp_float(42.0f, 76.0f, object_unit(p_salt, 0x107ULL));
	if (p_is_satellite) {
		size_px *= lerp_float(0.64f, 0.84f, object_unit(p_salt, 0x127ULL));
	}
	if (atlas_index == 2U) {
		size_px *= 0.88f;
	}
	if (object_unit(p_salt, 0x139ULL) < 0.10f && !p_is_satellite) {
		size_px *= 1.22f;
	}
	size_px = world_utils::clamp_value(size_px * ROCK_VISUAL_SCALE, 14.0f, 48.0f);
	const float tint = lerp_float(0.88f, 1.0f, object_unit(p_salt, 0x67ULL));
	const float phase = object_unit(p_salt, 0x157ULL);
	const uint8_t flags = size_px >= ROCK_LARGE_COLLISION_MIN_SIZE_PX ? OBJECT_FLAG_COLLIDER : 0U;
	append_object_record(r_buffers, OBJECT_KIND_ROCK, p_local_x_px, p_local_y_px, size_px, atlas_index, static_cast<uint8_t>(frame_index), flags, tint, phase);
}

bool append_native_rare_rock_formation_object(
	WorldObjectPacketBuffers &r_buffers,
	Vector2i p_coord,
	const PackedInt32Array &p_terrain_ids,
	const PackedByteArray &p_lake_flags,
	float p_local_x_px,
	float p_local_y_px,
	uint64_t p_salt
) {
	if (p_local_x_px < RARE_ROCK_FORMATION_EDGE_PADDING_PX ||
			p_local_y_px < RARE_ROCK_FORMATION_EDGE_PADDING_PX ||
			p_local_x_px > static_cast<float>(CHUNK_SIZE_PX) - RARE_ROCK_FORMATION_EDGE_PADDING_PX ||
			p_local_y_px > static_cast<float>(CHUNK_SIZE_PX) - RARE_ROCK_FORMATION_EDGE_PADDING_PX ||
			!object_position_is_plain_with_clearance(
					p_local_x_px,
					p_local_y_px,
					p_terrain_ids,
					p_lake_flags,
					RARE_ROCK_FORMATION_TERRAIN_CLEARANCE_PX)) {
		return false;
	}
	const float world_px_x = static_cast<float>(static_cast<int64_t>(p_coord.x) * CHUNK_SIZE_PX) + p_local_x_px;
	const float world_px_y = static_cast<float>(static_cast<int64_t>(p_coord.y) * CHUNK_SIZE_PX) + p_local_y_px;
	if (!object_rare_rock_patch_has_clearance(world_px_x, world_px_y)) {
		return false;
	}

	const float patch_score = object_rock_patch_mask(
		world_px_x,
		world_px_y,
		RARE_ROCK_FORMATION_PATCH_CELL_PX,
		RARE_ROCK_FORMATION_PATCH_DENSITY
	);
	float size_px = lerp_float(RARE_ROCK_FORMATION_MIN_SIZE_PX, RARE_ROCK_FORMATION_MAX_SIZE_PX, object_unit(p_salt, 0x107ULL));
	size_px *= lerp_float(0.96f, 1.04f, world_utils::clamp_value(patch_score, 0.0f, 1.0f));
	size_px = world_utils::clamp_value(size_px, RARE_ROCK_FORMATION_MIN_SIZE_PX, RARE_ROCK_FORMATION_MAX_SIZE_PX);
	const int32_t frame_index = static_cast<int32_t>(std::floor(object_unit(p_salt, 0x97ULL) * static_cast<float>(RARE_ROCK_FORMATION_VARIANT_COUNT))) % RARE_ROCK_FORMATION_VARIANT_COUNT;
	const float tint = lerp_float(0.90f, 1.0f, object_unit(p_salt, 0x67ULL));
	const float phase = object_unit(p_salt, 0x157ULL);
	append_object_record(
		r_buffers,
		OBJECT_KIND_ROCK,
		p_local_x_px,
		p_local_y_px,
		size_px,
		RARE_ROCK_FORMATION_ATLAS_INDEX,
		static_cast<uint8_t>(frame_index),
		OBJECT_FLAG_COLLIDER,
		tint,
		phase
	);
	return true;
}

void append_native_rare_rock_formation_placements(
	WorldObjectPacketBuffers &r_buffers,
	int64_t p_seed,
	Vector2i p_coord,
	int64_t p_world_version,
	const PackedInt32Array &p_terrain_ids,
	const PackedByteArray &p_lake_flags
) {
	const float chunk_min_world_x = static_cast<float>(static_cast<int64_t>(p_coord.x) * CHUNK_SIZE_PX);
	const float chunk_min_world_y = static_cast<float>(static_cast<int64_t>(p_coord.y) * CHUNK_SIZE_PX);
	const float chunk_max_world_x = chunk_min_world_x + static_cast<float>(CHUNK_SIZE_PX);
	const float chunk_max_world_y = chunk_min_world_y + static_cast<float>(CHUNK_SIZE_PX);
	const float jitter_margin = RARE_ROCK_FORMATION_PLACEMENT_CELL_PX * 0.36f;
	const int64_t min_cell_x = static_cast<int64_t>(std::floor((chunk_min_world_x - jitter_margin) / RARE_ROCK_FORMATION_PLACEMENT_CELL_PX));
	const int64_t min_cell_y = static_cast<int64_t>(std::floor((chunk_min_world_y - jitter_margin) / RARE_ROCK_FORMATION_PLACEMENT_CELL_PX));
	const int64_t max_cell_x = static_cast<int64_t>(std::floor((chunk_max_world_x + jitter_margin) / RARE_ROCK_FORMATION_PLACEMENT_CELL_PX));
	const int64_t max_cell_y = static_cast<int64_t>(std::floor((chunk_max_world_y + jitter_margin) / RARE_ROCK_FORMATION_PLACEMENT_CELL_PX));
	int32_t placed_count = 0;
	for (int64_t cell_y = min_cell_y; cell_y <= max_cell_y && placed_count < RARE_ROCK_FORMATION_MAX_PER_CHUNK; ++cell_y) {
		for (int64_t cell_x = min_cell_x; cell_x <= max_cell_x && placed_count < RARE_ROCK_FORMATION_MAX_PER_CHUNK; ++cell_x) {
			const uint64_t cell_hash = object_hash4(cell_x, cell_y, p_seed, p_world_version ^ static_cast<int64_t>(0x517d4b36ULL));
			const float world_px_x = (static_cast<float>(cell_x) + 0.5f + (object_unit(cell_hash, 0x41ULL) - 0.5f) * 0.72f) * RARE_ROCK_FORMATION_PLACEMENT_CELL_PX;
			const float world_px_y = (static_cast<float>(cell_y) + 0.5f + (object_unit(cell_hash, 0x53ULL) - 0.5f) * 0.72f) * RARE_ROCK_FORMATION_PLACEMENT_CELL_PX;
			if (world_px_x < chunk_min_world_x ||
					world_px_y < chunk_min_world_y ||
					world_px_x >= chunk_max_world_x ||
					world_px_y >= chunk_max_world_y) {
				continue;
			}
			if (append_native_rare_rock_formation_object(
					r_buffers,
					p_coord,
					p_terrain_ids,
					p_lake_flags,
					world_px_x - chunk_min_world_x,
					world_px_y - chunk_min_world_y,
					cell_hash)) {
				++placed_count;
			}
		}
	}
}

void append_native_tree_placements(
	WorldObjectPacketBuffers &r_buffers,
	int64_t p_seed,
	Vector2i p_coord,
	int64_t p_world_version,
	const PackedInt32Array &p_terrain_ids,
	const PackedByteArray &p_lake_flags
) {
	std::vector<std::pair<float, float>> placed_positions;
	const float cell_size_px = static_cast<float>(CHUNK_SIZE_PX) / static_cast<float>(TREE_SCATTER_GRID_SIDE);
	const float min_distance_sq = TREE_MIN_DISTANCE_PX * TREE_MIN_DISTANCE_PX;
	for (int32_t grid_y = 0; grid_y < TREE_SCATTER_GRID_SIDE; ++grid_y) {
		for (int32_t grid_x = 0; grid_x < TREE_SCATTER_GRID_SIDE; ++grid_x) {
			const uint64_t cell_hash = object_hash4(p_coord.x, p_coord.y, grid_x + grid_y * TREE_SCATTER_GRID_SIDE, p_seed ^ (p_world_version * 89));
			if (hash_unit_float(cell_hash, 0U) > TREE_PRIMARY_DENSITY) {
				continue;
			}
			const float jitter_x = (object_unit(cell_hash, 0x41ULL) - 0.5f) * std::max(8.0f, cell_size_px - TREE_EDGE_PADDING_PX * 2.0f);
			const float jitter_y = (object_unit(cell_hash, 0x53ULL) - 0.5f) * std::max(8.0f, cell_size_px - TREE_EDGE_PADDING_PX * 2.0f);
			const float local_x = (static_cast<float>(grid_x) + 0.5f) * cell_size_px + jitter_x;
			const float local_y = (static_cast<float>(grid_y) + 0.5f) * cell_size_px + jitter_y;
			if (local_x < TREE_EDGE_PADDING_PX ||
					local_y < TREE_EDGE_PADDING_PX ||
					local_x > static_cast<float>(CHUNK_SIZE_PX) - TREE_EDGE_PADDING_PX ||
					local_y > static_cast<float>(CHUNK_SIZE_PX) - TREE_EDGE_PADDING_PX ||
					!object_position_is_plain(local_x, local_y, p_terrain_ids, p_lake_flags) ||
					!object_position_has_mountain_clearance(local_x, local_y, p_terrain_ids, OBJECT_MOUNTAIN_CLEARANCE_PX)) {
				continue;
			}
			bool too_close = false;
			for (const std::pair<float, float> &existing : placed_positions) {
				const float dx = local_x - existing.first;
				const float dy = local_y - existing.second;
				if (dx * dx + dy * dy < min_distance_sq) {
					too_close = true;
					break;
				}
			}
			if (too_close) {
				continue;
			}
			const uint8_t variant = static_cast<uint8_t>(static_cast<int32_t>(std::floor(object_unit(cell_hash, 0x97ULL) * static_cast<float>(TREE_ATLAS_VARIANT_COUNT))) % TREE_ATLAS_VARIANT_COUNT);
			const float tier_roll = object_unit(cell_hash, 0x6bULL);
			const float size_roll = object_unit(cell_hash, 0x71ULL);
			float size_px;
			if (tier_roll < TREE_HERO_CHANCE) {
				size_px = lerp_float(TREE_MAX_SIZE_PX, TREE_HERO_SIZE_PX, size_roll);
			} else if (tier_roll < TREE_HERO_CHANCE + TREE_SMALL_CHANCE) {
				size_px = lerp_float(TREE_SMALL_SIZE_PX * 0.9f, TREE_SMALL_SIZE_PX, size_roll);
			} else {
				size_px = lerp_float(TREE_MIN_SIZE_PX, TREE_MAX_SIZE_PX, size_roll);
			}
			const float tint = lerp_float(0.90f, 1.0f, object_unit(cell_hash, 0x67ULL));
			const float phase = object_unit(cell_hash, 0x157ULL);
			append_object_record(r_buffers, OBJECT_KIND_TREE, local_x, local_y, size_px, 0U, variant, 0U, tint, phase);
			placed_positions.push_back({ local_x, local_y });
		}
	}
}

void append_native_object_placements(
	WorldObjectPacketBuffers &r_buffers,
	int64_t p_seed,
	Vector2i p_coord,
	int64_t p_world_version,
	const PackedInt32Array &p_terrain_ids,
	const PackedByteArray &p_lake_flags
) {
	bool used_rock_variants[ROCK_ATLAS_COUNT][ROCK_FRAME_COUNT] = {};
	const float rock_cell_size_px = static_cast<float>(CHUNK_SIZE_PX) / static_cast<float>(ROCK_SCATTER_GRID_SIDE);
	for (int32_t grid_y = 0; grid_y < ROCK_SCATTER_GRID_SIDE; ++grid_y) {
		for (int32_t grid_x = 0; grid_x < ROCK_SCATTER_GRID_SIDE; ++grid_x) {
			const uint64_t cell_hash = object_hash4(p_coord.x, p_coord.y, grid_x + grid_y * ROCK_SCATTER_GRID_SIDE, p_seed ^ (p_world_version * 31));
			if (hash_unit_float(cell_hash, 0U) > ROCK_PRIMARY_DENSITY) {
				continue;
			}
			const float jitter_x = (object_unit(cell_hash, 0x41ULL) - 0.5f) * std::max(8.0f, rock_cell_size_px - ROCK_EDGE_PADDING_PX * 2.0f);
			const float jitter_y = (object_unit(cell_hash, 0x53ULL) - 0.5f) * std::max(8.0f, rock_cell_size_px - ROCK_EDGE_PADDING_PX * 2.0f);
			const float local_x = (static_cast<float>(grid_x) + 0.5f) * rock_cell_size_px + jitter_x;
			const float local_y = (static_cast<float>(grid_y) + 0.5f) * rock_cell_size_px + jitter_y;
			append_native_rock_object(r_buffers, p_coord, p_seed, p_world_version, p_terrain_ids, p_lake_flags, local_x, local_y, cell_hash, false, used_rock_variants);
			if (object_unit(cell_hash, 0x17ULL) <= ROCK_SATELLITE_DENSITY) {
				const float angle = object_unit(cell_hash, 0x03ULL) * MOUNTAIN_PASSAGE_TAU;
				const float distance_px = lerp_float(26.0f, 72.0f, object_unit(cell_hash, 0x11ULL));
				const uint64_t satellite_hash = splitmix64(cell_hash ^ 0x293137ULL);
				append_native_rock_object(
					r_buffers,
					p_coord,
					p_seed,
					p_world_version,
					p_terrain_ids,
					p_lake_flags,
					local_x + std::cos(angle) * distance_px,
					local_y + std::sin(angle) * distance_px,
					satellite_hash,
					true,
					used_rock_variants
				);
			}
		}
	}
	append_native_rare_rock_formation_placements(r_buffers, p_seed, p_coord, p_world_version, p_terrain_ids, p_lake_flags);

	int32_t living_count = 0;
	const float living_cell_size_px = static_cast<float>(CHUNK_SIZE_PX) / static_cast<float>(LIVING_FLORA_SCATTER_GRID_SIDE);
	for (int32_t grid_y = 0; grid_y < LIVING_FLORA_SCATTER_GRID_SIDE && living_count < LIVING_FLORA_MAX_PER_CHUNK; ++grid_y) {
		for (int32_t grid_x = 0; grid_x < LIVING_FLORA_SCATTER_GRID_SIDE && living_count < LIVING_FLORA_MAX_PER_CHUNK; ++grid_x) {
			const uint64_t cell_hash = object_hash4(p_coord.x, p_coord.y, grid_x + grid_y * LIVING_FLORA_SCATTER_GRID_SIDE, p_seed ^ (p_world_version * 53));
			if (hash_unit_float(cell_hash, 0U) > LIVING_FLORA_PRIMARY_DENSITY) {
				continue;
			}
			const float jitter_x = (object_unit(cell_hash, 0x41ULL) - 0.5f) * std::max(8.0f, living_cell_size_px - LIVING_FLORA_EDGE_PADDING_PX * 2.0f);
			const float jitter_y = (object_unit(cell_hash, 0x53ULL) - 0.5f) * std::max(8.0f, living_cell_size_px - LIVING_FLORA_EDGE_PADDING_PX * 2.0f);
			const float local_x = (static_cast<float>(grid_x) + 0.5f) * living_cell_size_px + jitter_x;
			const float local_y = (static_cast<float>(grid_y) + 0.5f) * living_cell_size_px + jitter_y;
			if (local_x < LIVING_FLORA_EDGE_PADDING_PX ||
					local_y < LIVING_FLORA_EDGE_PADDING_PX ||
					local_x > static_cast<float>(CHUNK_SIZE_PX) - LIVING_FLORA_EDGE_PADDING_PX ||
					local_y > static_cast<float>(CHUNK_SIZE_PX) - LIVING_FLORA_EDGE_PADDING_PX ||
					!object_position_is_plain(local_x, local_y, p_terrain_ids, p_lake_flags) ||
					!object_position_has_mountain_clearance(local_x, local_y, p_terrain_ids, OBJECT_MOUNTAIN_CLEARANCE_PX)) {
				continue;
			}
			const float world_px_x = static_cast<float>(p_coord.x * CHUNK_SIZE_PX) + local_x;
			const float world_px_y = static_cast<float>(p_coord.y * CHUNK_SIZE_PX) + local_y;
			if (object_organic_region_mask(world_px_x, world_px_y, LIVING_FLORA_PATCH_CELL_PX, LIVING_FLORA_PATCH_DENSITY) < LIVING_FLORA_PATCH_THRESHOLD) {
				continue;
			}
			const float size_px = lerp_float(LIVING_FLORA_MIN_SIZE_PX, LIVING_FLORA_MAX_SIZE_PX, object_unit(cell_hash, 0x101ULL));
			const float tint = lerp_float(0.86f, 1.0f, object_unit(cell_hash, 0x109ULL));
			const float phase = object_unit(cell_hash, 0x131ULL);
			append_object_record(r_buffers, OBJECT_KIND_LIVING_FLORA, local_x, local_y, size_px, 0U, 0U, 0U, tint, phase);
			++living_count;
		}
	}

	std::vector<std::pair<float, float>> placed_spiky_positions;
	for (int32_t candidate_index = 0; candidate_index < SPIKY_FLORA_CANDIDATE_COUNT && static_cast<int32_t>(placed_spiky_positions.size()) < SPIKY_FLORA_MAX_PER_CHUNK; ++candidate_index) {
		const uint64_t candidate_hash = object_hash4(p_coord.x, p_coord.y, candidate_index, p_seed ^ (p_world_version * 67));
		const float density_roll = object_unit(candidate_hash, 0x181ULL);
		if (density_roll > SPIKY_FLORA_MAX_DENSITY) {
			continue;
		}
		const float local_x = lerp_float(SPIKY_FLORA_EDGE_PADDING_PX, static_cast<float>(CHUNK_SIZE_PX) - SPIKY_FLORA_EDGE_PADDING_PX, object_unit(candidate_hash, 0x41ULL));
		const float local_y = lerp_float(SPIKY_FLORA_EDGE_PADDING_PX, static_cast<float>(CHUNK_SIZE_PX) - SPIKY_FLORA_EDGE_PADDING_PX, object_unit(candidate_hash, 0x53ULL));
		if (!object_position_is_plain(local_x, local_y, p_terrain_ids, p_lake_flags) ||
				!object_position_has_mountain_clearance(local_x, local_y, p_terrain_ids, OBJECT_MOUNTAIN_CLEARANCE_PX)) {
			continue;
		}
		const float world_px_x = static_cast<float>(p_coord.x * CHUNK_SIZE_PX) + local_x;
		const float world_px_y = static_cast<float>(p_coord.y * CHUNK_SIZE_PX) + local_y;
		const float biofield_score = object_organic_region_mask(world_px_x, world_px_y, SPIKY_FLORA_PATCH_CELL_PX, SPIKY_FLORA_PATCH_DENSITY);
		if (biofield_score < SPIKY_FLORA_PLACEMENT_THRESHOLD) {
			continue;
		}
		const float chance = lerp_float(
			SPIKY_FLORA_MIN_DENSITY,
			SPIKY_FLORA_MAX_DENSITY,
			smoothstep01(SPIKY_FLORA_PLACEMENT_THRESHOLD, 0.86f, biofield_score)
		);
		if (density_roll > chance) {
			continue;
		}
		bool too_close = false;
		const float min_distance_sq = SPIKY_FLORA_MIN_DISTANCE_PX * SPIKY_FLORA_MIN_DISTANCE_PX;
		for (const std::pair<float, float> &existing : placed_spiky_positions) {
			const float dx = local_x - existing.first;
			const float dy = local_y - existing.second;
			if (dx * dx + dy * dy < min_distance_sq) {
				too_close = true;
				break;
			}
		}
		if (too_close) {
			continue;
		}
		const float size_roll = std::pow(object_unit(candidate_hash, 0x107ULL), SPIKY_FLORA_SIZE_EXPONENT);
		float size_px = lerp_float(SPIKY_FLORA_MIN_SIZE_PX, SPIKY_FLORA_MAX_SIZE_PX, size_roll);
		size_px *= lerp_float(0.94f, 1.10f, world_utils::clamp_value(biofield_score, 0.0f, 1.0f));
		const float tint = lerp_float(0.92f, 1.0f, object_unit(candidate_hash, 0x127ULL));
		const float phase = object_unit(candidate_hash, 0x139ULL);
		append_object_record(r_buffers, OBJECT_KIND_SPIKY_FLORA, local_x, local_y, size_px, SPIKY_FLORA_ATLAS_SPIKY_PLANT, 0U, 0U, tint, phase);
		placed_spiky_positions.push_back({ local_x, local_y });
	}

	int32_t biofield_seaweed_count = 0;
	for (int32_t candidate_index = 0; candidate_index < BIOFIELD_SEAWEED_CANDIDATE_COUNT && biofield_seaweed_count < BIOFIELD_SEAWEED_MAX_PER_CHUNK; ++candidate_index) {
		const uint64_t candidate_hash = object_hash4(p_coord.x, p_coord.y, candidate_index, p_seed ^ (p_world_version * 71));
		const float density_roll = object_unit(candidate_hash, 0x181ULL);
		if (density_roll > BIOFIELD_SEAWEED_MAX_DENSITY) {
			continue;
		}
		const float local_x = lerp_float(BIOFIELD_SEAWEED_EDGE_PADDING_PX, static_cast<float>(CHUNK_SIZE_PX) - BIOFIELD_SEAWEED_EDGE_PADDING_PX, object_unit(candidate_hash, 0x41ULL));
		const float local_y = lerp_float(BIOFIELD_SEAWEED_EDGE_PADDING_PX, static_cast<float>(CHUNK_SIZE_PX) - BIOFIELD_SEAWEED_EDGE_PADDING_PX, object_unit(candidate_hash, 0x53ULL));
		if (!object_position_is_plain(local_x, local_y, p_terrain_ids, p_lake_flags) ||
				!object_position_has_mountain_clearance(local_x, local_y, p_terrain_ids, OBJECT_MOUNTAIN_CLEARANCE_PX)) {
			continue;
		}
		const float world_px_x = static_cast<float>(p_coord.x * CHUNK_SIZE_PX) + local_x;
		const float world_px_y = static_cast<float>(p_coord.y * CHUNK_SIZE_PX) + local_y;
		const float biofield_score = object_organic_region_mask(world_px_x, world_px_y, SPIKY_FLORA_PATCH_CELL_PX, SPIKY_FLORA_PATCH_DENSITY);
		if (biofield_score < SPIKY_FLORA_PLACEMENT_THRESHOLD) {
			continue;
		}
		const float chance = lerp_float(
			BIOFIELD_SEAWEED_MIN_DENSITY,
			BIOFIELD_SEAWEED_MAX_DENSITY,
			smoothstep01(SPIKY_FLORA_PLACEMENT_THRESHOLD, 0.86f, biofield_score)
		);
		if (density_roll > chance) {
			continue;
		}
		bool too_close = false;
		const float min_distance_sq = BIOFIELD_SEAWEED_MIN_DISTANCE_PX * BIOFIELD_SEAWEED_MIN_DISTANCE_PX;
		for (const std::pair<float, float> &existing : placed_spiky_positions) {
			const float dx = local_x - existing.first;
			const float dy = local_y - existing.second;
			if (dx * dx + dy * dy < min_distance_sq) {
				too_close = true;
				break;
			}
		}
		if (too_close) {
			continue;
		}
		const float size_roll = std::pow(object_unit(candidate_hash, 0x107ULL), BIOFIELD_SEAWEED_SIZE_EXPONENT);
		float size_px = lerp_float(BIOFIELD_SEAWEED_MIN_SIZE_PX, BIOFIELD_SEAWEED_MAX_SIZE_PX, size_roll);
		size_px *= lerp_float(0.92f, 1.08f, world_utils::clamp_value(biofield_score, 0.0f, 1.0f));
		const int32_t frame_index = static_cast<int32_t>(std::floor(object_unit(candidate_hash, 0x151ULL) * 4.0f)) % 4;
		const float tint = lerp_float(0.90f, 1.0f, object_unit(candidate_hash, 0x127ULL));
		const float phase = object_unit(candidate_hash, 0x139ULL);
		append_object_record(
			r_buffers,
			OBJECT_KIND_SPIKY_FLORA,
			local_x,
			local_y,
			size_px,
			SPIKY_FLORA_ATLAS_BROWN_SEAWEED,
			static_cast<uint8_t>(frame_index),
			0U,
			tint,
			phase
		);
		placed_spiky_positions.push_back({ local_x, local_y });
		++biofield_seaweed_count;
	}

	append_native_tree_placements(r_buffers, p_seed, p_coord, p_world_version, p_terrain_ids, p_lake_flags);
}

int32_t make_satellite_outcrop_mountain_id(uint64_t p_hash) {
	return SATELLITE_OUTCROP_ID_BASE |
			static_cast<int32_t>(splitmix64(p_hash ^ 0x7f4a7c159e3779b9ULL) & SATELLITE_OUTCROP_ID_MASK);
}

int64_t signed_wrapped_delta_x(int64_t p_from_x, int64_t p_to_x, int64_t p_world_wrap_width_tiles) {
	const int64_t width = std::max<int64_t>(1, p_world_wrap_width_tiles);
	int64_t delta = positive_mod(p_to_x - p_from_x, width);
	if (delta > width / 2) {
		delta -= width;
	}
	return delta;
}

float satellite_outcrop_shape_distance(
	const SatelliteOutcropCandidate &p_candidate,
	int64_t p_world_x,
	int64_t p_world_y,
	int64_t p_world_wrap_width_tiles,
	uint64_t p_tile_hash
) {
	float local_x = static_cast<float>(signed_wrapped_delta_x(p_candidate.center_x, p_world_x, p_world_wrap_width_tiles));
	float local_y = static_cast<float>(p_world_y - p_candidate.center_y);
	switch (positive_mod(p_candidate.shape_orientation, 4)) {
		case 1: {
			const float tmp = local_x;
			local_x = -local_y;
			local_y = tmp;
		} break;
		case 2:
			local_x = -local_x;
			local_y = -local_y;
			break;
		case 3: {
			const float tmp = local_x;
			local_x = local_y;
			local_y = -tmp;
		} break;
		default:
			break;
	}
	const float organic_breakup = (hash_unit_float(p_tile_hash, 6U) - 0.5f) * p_candidate.wobble;
	const float radius_x = std::max(0.1f, p_candidate.radius_x);
	const float radius_y = std::max(0.1f, p_candidate.radius_y);
	const int32_t shape_mode = positive_mod(p_candidate.shape_mode, 4);
	if (shape_mode == 1) {
		const float normalized_x = local_x / (radius_x * 1.35f);
		const float normalized_y = local_y / (radius_y * 0.78f);
		return normalized_x * normalized_x + normalized_y * normalized_y + organic_breakup;
	}
	if (shape_mode == 2) {
		const float arm_a_x = local_x / (radius_x * 0.68f);
		const float arm_a_y = (local_y + radius_y * 0.25f) / (radius_y * 1.10f);
		const float arm_b_x = (local_x - radius_x * 0.42f) / (radius_x * 1.12f);
		const float arm_b_y = (local_y - radius_y * 0.42f) / (radius_y * 0.62f);
		const float arm_a = arm_a_x * arm_a_x + arm_a_y * arm_a_y;
		const float arm_b = arm_b_x * arm_b_x + arm_b_y * arm_b_y;
		return std::min(arm_a, arm_b) + organic_breakup;
	}
	if (shape_mode == 3) {
		const float normalized_y = local_y / radius_y;
		const float taper = world_utils::clamp_value(1.0f - (normalized_y + 0.85f) * 0.42f, 0.32f, 1.25f);
		const float normalized_x = local_x / (radius_x * taper);
		return normalized_x * normalized_x + normalized_y * normalized_y * 0.72f + organic_breakup;
	}
	const float normalized_x = local_x / radius_x;
	const float normalized_y = local_y / radius_y;
	return normalized_x * normalized_x + normalized_y * normalized_y + organic_breakup;
}

int32_t satellite_outcrop_candidate_extent(const SatelliteOutcropCandidate &p_candidate) {
	const float largest_radius = std::max(p_candidate.radius_x, p_candidate.radius_y);
	return std::max<int32_t>(4, static_cast<int32_t>(std::ceil(largest_radius * 2.25f + 4.0f)));
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
	ClassDB::bind_method(D_METHOD("build_mountain_halo_mask", "solid_halo", "chunk_size", "tile_size_px", "pixels_per_tile", "origin_world_x", "origin_world_y"), &WorldCore::build_mountain_halo_mask);
	ClassDB::bind_method(D_METHOD("build_grass_scatter_buffer", "seed", "chunk_coord", "terrain_ids", "lake_flags", "params"), &WorldCore::build_grass_scatter_buffer);
	ClassDB::bind_method(D_METHOD("build_mountain_plateau_raster_image", "packets", "target_chunk", "preset", "top_image", "face_image"), &WorldCore::build_mountain_plateau_raster_image);
	ClassDB::bind_method(D_METHOD("resolve_world_foundation_spawn_tile", "seed", "world_version", "settings_packed"), &WorldCore::resolve_world_foundation_spawn_tile);
#ifdef DEBUG_ENABLED
	ClassDB::bind_method(D_METHOD("get_world_foundation_snapshot", "layer_mask", "downscale_factor"), &WorldCore::get_world_foundation_snapshot);
	ClassDB::bind_method(D_METHOD("get_world_foundation_overview", "layer_mask", "pixels_per_cell"), &WorldCore::get_world_foundation_overview, DEFVAL(1));
#endif
}

Dictionary WorldCore::build_grass_scatter_buffer(int64_t p_seed, Vector2i p_chunk_coord, PackedInt32Array p_terrain_ids, PackedByteArray p_lake_flags, PackedFloat32Array p_params) {
	return grass_scatter::build_buffer(p_seed, p_chunk_coord.x, p_chunk_coord.y, p_terrain_ids, p_lake_flags, p_params);
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

Dictionary WorldCore::build_mountain_plateau_raster_image(
	Array p_packets,
	Vector2i p_target_chunk,
	Dictionary p_preset,
	Ref<Image> p_top_image,
	Ref<Image> p_face_image
) {
	return mountain_plateau_raster::build_image(p_packets, p_target_chunk, p_preset, p_top_image, p_face_image);
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

Dictionary WorldCore::build_mountain_halo_mask(
	PackedByteArray p_solid_halo,
	int64_t p_chunk_size,
	int64_t p_tile_size_px,
	int64_t p_pixels_per_tile,
	double p_origin_world_x,
	double p_origin_world_y
) {
	return mountain_contour::build_halo_mask(
		p_solid_halo,
		static_cast<int32_t>(p_chunk_size),
		static_cast<int32_t>(p_tile_size_px),
		static_cast<int32_t>(p_pixels_per_tile),
		p_origin_world_x,
		p_origin_world_y
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

	auto base_mountain_id_at_world = [&](int64_t p_sample_world_x, int64_t p_world_y) -> int32_t {
		const float elevation = p_mountain_evaluator.sample_elevation(p_sample_world_x, p_world_y);
		return resolve_mountain_id_at_world(p_sample_world_x, p_world_y, elevation);
	};
	auto candidate_touches_base_mountain = [&](int64_t p_sample_world_x, int64_t p_world_y) -> bool {
		const int32_t separation_offsets[][2] = {
			{ 0, 0 },
			{ 1, 0 },
			{ -1, 0 },
			{ 0, 1 },
			{ 0, -1 },
			{ 1, 1 },
			{ -1, 1 },
			{ 1, -1 },
			{ -1, -1 },
		};
		for (const auto &offset : separation_offsets) {
			const int64_t neighbour_x = positive_mod(
				p_sample_world_x + static_cast<int64_t>(offset[0]),
				p_effective_mountain_settings.world_wrap_width_tiles
			);
			const int64_t raw_neighbour_y = p_world_y + static_cast<int64_t>(offset[1]);
			if (p_foundation_settings.enabled &&
					(raw_neighbour_y < 0 || raw_neighbour_y >= p_foundation_settings.height_tiles)) {
				continue;
			}
			const int64_t neighbour_y = clamp_foundation_world_y(raw_neighbour_y, p_foundation_settings);
			if (base_mountain_id_at_world(neighbour_x, neighbour_y) > 0) {
				return true;
			}
		}
		return false;
	};

	const bool use_passage_outcrop_refinement = p_world_version >= MOUNTAIN_PASSAGE_OUTCROP_REFINEMENT_VERSION;
	std::vector<SatelliteOutcropCandidate> satellite_outcrop_candidates;
	if (p_world_version >= MOUNTAIN_SATELLITE_OUTCROP_CLUSTER_VERSION && p_effective_mountain_settings.density > 0.05f) {
		auto anchor_is_near_main_mountain = [&](int64_t p_center_x, int64_t p_center_y) -> bool {
			const int32_t near_offsets[][2] = {
				{ 1, 0 },
				{ -1, 0 },
				{ 0, 1 },
				{ 0, -1 },
				{ 1, 1 },
				{ -1, 1 },
				{ 1, -1 },
				{ -1, -1 },
			};
			for (int32_t distance = 1; distance <= SATELLITE_OUTCROP_MIN_MAIN_DISTANCE_TILES; ++distance) {
				for (const auto &offset : near_offsets) {
					const int64_t sample_x = positive_mod(
						p_center_x + static_cast<int64_t>(offset[0]) * static_cast<int64_t>(distance),
						p_effective_mountain_settings.world_wrap_width_tiles
					);
					const int64_t sample_y = clamp_foundation_world_y(
						p_center_y + static_cast<int64_t>(offset[1]) * static_cast<int64_t>(distance),
						p_foundation_settings
					);
					if (base_mountain_id_at_world(sample_x, sample_y) > 0) {
						return false;
					}
				}
			}
			const int32_t ring_distances[] = { 3, 5, 8, SATELLITE_OUTCROP_MAX_MAIN_DISTANCE_TILES };
			for (int32_t distance : ring_distances) {
				for (const auto &offset : near_offsets) {
					const int64_t sample_x = positive_mod(
						p_center_x + static_cast<int64_t>(offset[0]) * static_cast<int64_t>(distance),
						p_effective_mountain_settings.world_wrap_width_tiles
					);
					const int64_t sample_y = clamp_foundation_world_y(
						p_center_y + static_cast<int64_t>(offset[1]) * static_cast<int64_t>(distance),
						p_foundation_settings
					);
					if (base_mountain_id_at_world(sample_x, sample_y) > 0) {
						return true;
					}
				}
			}
			return false;
		};
		auto make_outcrop_tile_key = [&](int64_t p_sample_x, int64_t p_sample_y) -> int64_t {
			return p_sample_y * p_effective_mountain_settings.world_wrap_width_tiles + p_sample_x;
		};
		auto collect_candidate_solid_tiles = [&](const SatelliteOutcropCandidate &p_candidate) -> std::vector<int64_t> {
			std::vector<int64_t> solid_tiles;
			const int32_t candidate_extent = satellite_outcrop_candidate_extent(p_candidate);
			for (int64_t offset_y = -candidate_extent; offset_y <= candidate_extent; ++offset_y) {
				const int64_t raw_sample_y = p_candidate.center_y + offset_y;
				if (p_foundation_settings.enabled &&
						(raw_sample_y < 0 || raw_sample_y >= p_foundation_settings.height_tiles)) {
					continue;
				}
				const int64_t sample_y = clamp_foundation_world_y(raw_sample_y, p_foundation_settings);
				for (int64_t offset_x = -candidate_extent; offset_x <= candidate_extent; ++offset_x) {
					const int64_t sample_x = positive_mod(
						p_candidate.center_x + offset_x,
						p_effective_mountain_settings.world_wrap_width_tiles
					);
					const float base_elevation = p_mountain_evaluator.sample_elevation(sample_x, sample_y);
					if (base_elevation >= mountain_thresholds.t_edge) {
						continue;
					}
					if (candidate_touches_base_mountain(sample_x, sample_y)) {
						continue;
					}
					const uint64_t tile_hash = splitmix64(
						hash_satellite_outcrop_anchor(
							p_seed,
							p_world_version,
							p_candidate.anchor_cell_x,
							p_candidate.anchor_cell_y,
							p_effective_mountain_settings.world_wrap_width_tiles
						) ^
						static_cast<uint64_t>(sample_x) * 0x9e3779b185ebca87ULL ^
						static_cast<uint64_t>(sample_y) * 0xc2b2ae3d27d4eb4fULL
					);
					if (satellite_outcrop_shape_distance(
						p_candidate,
						sample_x,
						sample_y,
						p_effective_mountain_settings.world_wrap_width_tiles,
						tile_hash
					) <= 1.0f) {
						solid_tiles.push_back(make_outcrop_tile_key(sample_x, sample_y));
					}
				}
			}
			return solid_tiles;
		};

		const int64_t chunk_origin_sample_x = resolve_mountain_sample_x(
			static_cast<int64_t>(p_coord.x) * CHUNK_SIZE,
			p_world_version,
			p_foundation_settings
		);
		const int64_t chunk_origin_y = clamp_foundation_world_y(
			static_cast<int64_t>(p_coord.y) * CHUNK_SIZE,
			p_foundation_settings
		);
		const int64_t anchor_min_x = floor_div(
			chunk_origin_sample_x - mountain_border - SATELLITE_OUTCROP_SCAN_MARGIN_TILES,
			static_cast<int64_t>(SATELLITE_OUTCROP_ANCHOR_CELL_SIZE)
		);
		const int64_t anchor_max_x = floor_div(
			chunk_origin_sample_x + CHUNK_SIZE - 1 + mountain_border + SATELLITE_OUTCROP_SCAN_MARGIN_TILES,
			static_cast<int64_t>(SATELLITE_OUTCROP_ANCHOR_CELL_SIZE)
		);
		const int64_t anchor_min_y = floor_div(
			chunk_origin_y - mountain_border - SATELLITE_OUTCROP_SCAN_MARGIN_TILES,
			static_cast<int64_t>(SATELLITE_OUTCROP_ANCHOR_CELL_SIZE)
		);
		const int64_t anchor_max_y = floor_div(
			chunk_origin_y + CHUNK_SIZE - 1 + mountain_border + SATELLITE_OUTCROP_SCAN_MARGIN_TILES,
			static_cast<int64_t>(SATELLITE_OUTCROP_ANCHOR_CELL_SIZE)
		);
		const int64_t anchor_cells_per_wrap = std::max<int64_t>(
			1,
			(p_effective_mountain_settings.world_wrap_width_tiles + SATELLITE_OUTCROP_ANCHOR_CELL_SIZE - 1) /
					SATELLITE_OUTCROP_ANCHOR_CELL_SIZE
		);
		const float spawn_chance = world_utils::clamp_value(
			SATELLITE_OUTCROP_BASE_CHANCE +
					p_effective_mountain_settings.density *
							(use_passage_outcrop_refinement ? SATELLITE_OUTCROP_REFINED_DENSITY_CHANCE : SATELLITE_OUTCROP_DENSITY_CHANCE),
			0.0f,
			use_passage_outcrop_refinement ? 0.18f : 0.14f
		);
		for (int64_t anchor_y = anchor_min_y; anchor_y <= anchor_max_y; ++anchor_y) {
			if (p_foundation_settings.enabled) {
				const int64_t anchor_origin_y = anchor_y * SATELLITE_OUTCROP_ANCHOR_CELL_SIZE;
				if (anchor_origin_y >= p_foundation_settings.height_tiles ||
						anchor_origin_y + SATELLITE_OUTCROP_ANCHOR_CELL_SIZE - 1 < 0) {
					continue;
				}
			}
			for (int64_t anchor_x = anchor_min_x; anchor_x <= anchor_max_x; ++anchor_x) {
				const int64_t canonical_anchor_x = positive_mod(anchor_x, anchor_cells_per_wrap);
				const uint64_t anchor_hash = hash_satellite_outcrop_anchor(
					p_seed,
					p_world_version,
					canonical_anchor_x,
					anchor_y,
					p_effective_mountain_settings.world_wrap_width_tiles
				);
				if (hash_unit_float(anchor_hash, 0U) > spawn_chance) {
					continue;
				}
				bool suppressed_by_nearby_anchor = false;
				for (int32_t neighbour_y = -2; neighbour_y <= 2; ++neighbour_y) {
					for (int32_t neighbour_x = -2; neighbour_x <= 2; ++neighbour_x) {
						if (neighbour_x == 0 && neighbour_y == 0) {
							continue;
						}
						const int64_t neighbour_anchor_y = anchor_y + neighbour_y;
						if (p_foundation_settings.enabled) {
							const int64_t neighbour_origin_y = neighbour_anchor_y * SATELLITE_OUTCROP_ANCHOR_CELL_SIZE;
							if (neighbour_origin_y >= p_foundation_settings.height_tiles ||
									neighbour_origin_y + SATELLITE_OUTCROP_ANCHOR_CELL_SIZE - 1 < 0) {
								continue;
							}
						}
						const int64_t neighbour_anchor_x = positive_mod(canonical_anchor_x + neighbour_x, anchor_cells_per_wrap);
						const uint64_t neighbour_hash = hash_satellite_outcrop_anchor(
							p_seed,
							p_world_version,
							neighbour_anchor_x,
							neighbour_anchor_y,
							p_effective_mountain_settings.world_wrap_width_tiles
						);
						if (hash_unit_float(neighbour_hash, 0U) <= spawn_chance && neighbour_hash < anchor_hash) {
							suppressed_by_nearby_anchor = true;
							break;
						}
					}
					if (suppressed_by_nearby_anchor) {
						break;
					}
				}
				if (suppressed_by_nearby_anchor) {
					continue;
				}

				const int64_t anchor_origin_x = canonical_anchor_x * SATELLITE_OUTCROP_ANCHOR_CELL_SIZE;
				const int64_t anchor_origin_y = anchor_y * SATELLITE_OUTCROP_ANCHOR_CELL_SIZE;
				const int64_t cluster_center_x = positive_mod(
					anchor_origin_x +
							(use_passage_outcrop_refinement ? 2 : 4) +
							static_cast<int64_t>(std::floor(
								hash_unit_float(anchor_hash, 16U) * (use_passage_outcrop_refinement ? 12.0f : 8.0f)
							)),
					p_effective_mountain_settings.world_wrap_width_tiles
				);
				const int64_t cluster_center_y =
					anchor_origin_y +
					(use_passage_outcrop_refinement ? 2 : 4) +
					static_cast<int64_t>(std::floor(hash_unit_float(anchor_hash, 32U) * (use_passage_outcrop_refinement ? 12.0f : 8.0f)));
				if (p_foundation_settings.enabled && (cluster_center_y < 0 || cluster_center_y >= p_foundation_settings.height_tiles)) {
					continue;
				}
				if (mountain_field::is_spawn_safety_area_at_world(p_world_version, cluster_center_x, cluster_center_y) ||
						is_foundation_spawn_safety_area_at_world(cluster_center_x, cluster_center_y, p_foundation_settings)) {
					continue;
				}
				const float cluster_center_elevation = p_mountain_evaluator.sample_elevation(cluster_center_x, cluster_center_y);
				if (cluster_center_elevation >= mountain_thresholds.t_edge ||
						resolve_mountain_id_at_world(cluster_center_x, cluster_center_y, cluster_center_elevation) > 0) {
					continue;
				}
				if (!anchor_is_near_main_mountain(cluster_center_x, cluster_center_y)) {
					continue;
				}

				const uint64_t cluster_hash = splitmix64(anchor_hash ^ 0xa73e2d9b4c6f1825ULL);
				const float count_roll = hash_unit_float(cluster_hash, 0U);
				const int32_t raw_desired_count = use_passage_outcrop_refinement ?
						(count_roll < 0.16f ?
										2 + static_cast<int32_t>(std::floor(hash_unit_float(cluster_hash, 16U) * 8.0f)) :
										10 + static_cast<int32_t>(std::floor(hash_unit_float(cluster_hash, 16U) * 11.0f))) :
						(count_roll < 0.25f ?
										2 + static_cast<int32_t>(std::floor(hash_unit_float(cluster_hash, 16U) * 8.0f)) :
										10 + static_cast<int32_t>(std::floor(hash_unit_float(cluster_hash, 16U) * 11.0f)));
				const int32_t desired_count = world_utils::clamp_value(
					raw_desired_count,
					SATELLITE_OUTCROP_CLUSTER_MIN_COUNT,
					SATELLITE_OUTCROP_CLUSTER_MAX_COUNT
				);
				const int32_t cluster_offsets[][2] = {
					{ 0, 0 },
					{ 5, 0 },
					{ -5, 0 },
					{ 0, 5 },
					{ 0, -5 },
					{ 5, 5 },
					{ -5, 5 },
					{ 5, -5 },
					{ -5, -5 },
					{ 10, 0 },
					{ -10, 0 },
					{ 0, 10 },
					{ 0, -10 },
					{ 10, 5 },
					{ -10, 5 },
					{ 10, -5 },
					{ -10, -5 },
					{ 5, 10 },
					{ -5, 10 },
					{ 5, -10 },
					{ -5, -10 },
					{ 12, 12 },
					{ -12, 12 },
					{ 12, -12 },
					{ -12, -12 },
					{ 15, 0 },
					{ -15, 0 },
					{ 0, 15 },
					{ 0, -15 },
					{ 15, 8 },
					{ -15, 8 },
					{ 15, -8 },
					{ -15, -8 },
					{ 8, 15 },
					{ -8, 15 },
					{ 8, -15 },
					{ -8, -15 },
					{ 18, 3 },
					{ -18, -3 },
					{ 3, 18 },
					{ -3, -18 },
				};
				std::vector<SatelliteOutcropCandidate> pending_cluster;
				std::unordered_set<int64_t> pending_cluster_occupied_tiles;
				const int32_t cluster_attempts = use_passage_outcrop_refinement ?
						SATELLITE_OUTCROP_REFINED_CLUSTER_ATTEMPTS :
						SATELLITE_OUTCROP_CLUSTER_ATTEMPTS;
				const int32_t cluster_spread_tiles = use_passage_outcrop_refinement ?
						SATELLITE_OUTCROP_REFINED_CLUSTER_SPREAD_TILES :
						SATELLITE_OUTCROP_CLUSTER_SPREAD_TILES;
				for (int32_t attempt = 0; attempt < cluster_attempts; ++attempt) {
					if (static_cast<int32_t>(pending_cluster.size()) >= desired_count) {
						break;
					}
					const uint64_t child_hash = splitmix64(
						cluster_hash ^
						static_cast<uint64_t>(attempt + 1) * 0x9e3779b185ebca87ULL
					);
					const int32_t offset_index = attempt % (sizeof(cluster_offsets) / sizeof(cluster_offsets[0]));
					const float jitter_span = use_passage_outcrop_refinement ? 7.0f : 5.0f;
					const int64_t jitter_offset = use_passage_outcrop_refinement ? 3 : 2;
					const int64_t jitter_x = static_cast<int64_t>(std::floor(hash_unit_float(child_hash, 8U) * jitter_span)) - jitter_offset;
					const int64_t jitter_y = static_cast<int64_t>(std::floor(hash_unit_float(child_hash, 24U) * jitter_span)) - jitter_offset;
					const int64_t child_x = positive_mod(
						cluster_center_x +
							static_cast<int64_t>(cluster_offsets[offset_index][0]) +
							jitter_x,
						p_effective_mountain_settings.world_wrap_width_tiles
					);
					const int64_t child_y = cluster_center_y +
						static_cast<int64_t>(cluster_offsets[offset_index][1]) +
						jitter_y;
					if (p_foundation_settings.enabled && (child_y < 0 || child_y >= p_foundation_settings.height_tiles)) {
						continue;
					}
					if (std::abs(child_y - cluster_center_y) > cluster_spread_tiles ||
							std::abs(signed_wrapped_delta_x(cluster_center_x, child_x, p_effective_mountain_settings.world_wrap_width_tiles)) >
									cluster_spread_tiles) {
						continue;
					}
					if (mountain_field::is_spawn_safety_area_at_world(p_world_version, child_x, child_y) ||
							is_foundation_spawn_safety_area_at_world(child_x, child_y, p_foundation_settings)) {
						continue;
					}
					const float child_elevation = p_mountain_evaluator.sample_elevation(child_x, child_y);
					if (child_elevation >= mountain_thresholds.t_edge ||
							resolve_mountain_id_at_world(child_x, child_y, child_elevation) > 0) {
						continue;
					}

					SatelliteOutcropCandidate candidate;
					candidate.anchor_cell_x = canonical_anchor_x;
					candidate.anchor_cell_y = anchor_y;
					candidate.center_x = child_x;
					candidate.center_y = child_y;
					candidate.shape_mode = static_cast<int32_t>(child_hash & 3ULL);
					candidate.shape_orientation = static_cast<int32_t>((child_hash >> 2U) & 3ULL);
					const float compact_radius_x = 0.95f + hash_unit_float(child_hash, 16U) * 0.44f;
					const float compact_radius_y = 0.92f + hash_unit_float(child_hash, 32U) * 0.42f;
					if (candidate.shape_mode == 1) {
						candidate.radius_x = 1.22f + hash_unit_float(child_hash, 40U) * 0.58f;
						candidate.radius_y = 0.72f + hash_unit_float(child_hash, 48U) * 0.26f;
					} else if (candidate.shape_mode == 2) {
						candidate.radius_x = 0.92f + hash_unit_float(child_hash, 40U) * 0.34f;
						candidate.radius_y = 0.92f + hash_unit_float(child_hash, 48U) * 0.34f;
					} else if (candidate.shape_mode == 3) {
						candidate.radius_x = 1.02f + hash_unit_float(child_hash, 40U) * 0.46f;
						candidate.radius_y = 1.02f + hash_unit_float(child_hash, 48U) * 0.44f;
					} else {
						candidate.radius_x = compact_radius_x;
						candidate.radius_y = compact_radius_y;
					}
					const float large_roll = hash_unit_float(splitmix64(child_hash ^ 0x9f47baf219a4d6c3ULL), 0U);
					if (large_roll > (use_passage_outcrop_refinement ? 0.58f : 0.72f)) {
						const float size_scale = use_passage_outcrop_refinement ?
								1.22f + hash_unit_float(splitmix64(child_hash ^ 0x3b2e8c1f7a56d409ULL), 0U) * 0.50f :
								1.18f + hash_unit_float(splitmix64(child_hash ^ 0x3b2e8c1f7a56d409ULL), 0U) * 0.42f;
						candidate.radius_x *= size_scale;
						candidate.radius_y *= size_scale;
					}
					candidate.wobble = 0.06f + hash_unit_float(splitmix64(child_hash ^ 0x5d7b8f3a6e4c2910ULL), 0U) * 0.16f;
					candidate.mountain_id = make_satellite_outcrop_mountain_id(child_hash);
					const std::vector<int64_t> solid_tiles = collect_candidate_solid_tiles(candidate);
					if (solid_tiles.size() < SATELLITE_OUTCROP_MIN_CELLS || solid_tiles.size() > SATELLITE_OUTCROP_MAX_CELLS) {
						continue;
					}
					bool overlaps_cluster = false;
					for (const int64_t tile_key : solid_tiles) {
						if (pending_cluster_occupied_tiles.find(tile_key) != pending_cluster_occupied_tiles.end()) {
							overlaps_cluster = true;
							break;
						}
					}
					if (overlaps_cluster) {
						continue;
					}
					pending_cluster.push_back(candidate);
					for (const int64_t tile_key : solid_tiles) {
						pending_cluster_occupied_tiles.insert(tile_key);
					}
				}
				if (static_cast<int32_t>(pending_cluster.size()) >= SATELLITE_OUTCROP_CLUSTER_MIN_COUNT) {
					satellite_outcrop_candidates.insert(
						satellite_outcrop_candidates.end(),
						pending_cluster.begin(),
						pending_cluster.end()
					);
				}
			}
		}
	}

	auto resolve_satellite_outcrop_hit = [&](int64_t p_sample_world_x, int64_t p_world_y, float p_base_elevation) -> SatelliteOutcropHit {
		SatelliteOutcropHit hit;
		if (p_base_elevation >= mountain_thresholds.t_edge || satellite_outcrop_candidates.empty()) {
			return hit;
		}
		for (const SatelliteOutcropCandidate &candidate : satellite_outcrop_candidates) {
			const int32_t candidate_extent = satellite_outcrop_candidate_extent(candidate);
			if (std::abs(p_world_y - candidate.center_y) > candidate_extent) {
				continue;
			}
			if (std::abs(signed_wrapped_delta_x(candidate.center_x, p_sample_world_x, p_effective_mountain_settings.world_wrap_width_tiles)) >
					candidate_extent) {
				continue;
			}
			const uint64_t tile_hash = splitmix64(
				hash_satellite_outcrop_anchor(
					p_seed,
					p_world_version,
					candidate.anchor_cell_x,
					candidate.anchor_cell_y,
					p_effective_mountain_settings.world_wrap_width_tiles
				) ^
				static_cast<uint64_t>(positive_mod(p_sample_world_x, p_effective_mountain_settings.world_wrap_width_tiles)) *
						0x9e3779b185ebca87ULL ^
				static_cast<uint64_t>(p_world_y) * 0xc2b2ae3d27d4eb4fULL
			);
			const float shape_distance = satellite_outcrop_shape_distance(
				candidate,
				p_sample_world_x,
				p_world_y,
				p_effective_mountain_settings.world_wrap_width_tiles,
				tile_hash
			);
			if (shape_distance > 1.0f) {
				continue;
			}
			if (candidate_touches_base_mountain(p_sample_world_x, p_world_y)) {
				continue;
			}
			hit.active = true;
			hit.mountain_id = candidate.mountain_id;
			const float wall_cut = 0.58f + (hash_unit_float(tile_hash, 24U) - 0.5f) * 0.12f;
			hit.elevation = shape_distance <= wall_cut ?
					std::min(1.0f, mountain_thresholds.t_wall + 0.08f) :
					std::min(mountain_thresholds.t_wall - 0.001f, mountain_thresholds.t_edge + p_effective_mountain_settings.foot_band * 0.55f);
			return hit;
		}
		return hit;
	};

	auto mountain_passage_carve_open = [&](
		int64_t p_sample_world_x,
		int64_t p_world_y,
		float p_elevation,
		int32_t p_mountain_id
	) -> bool {
		if (!use_passage_outcrop_refinement || p_mountain_id <= 0 || p_elevation < mountain_thresholds.t_edge) {
			return false;
		}
		const int64_t world_width = std::max<int64_t>(1, p_effective_mountain_settings.world_wrap_width_tiles);
		const int64_t anchor_cells_per_wrap = std::max<int64_t>(
			1,
			(world_width + MOUNTAIN_PASSAGE_ANCHOR_CELL_SIZE - 1) / MOUNTAIN_PASSAGE_ANCHOR_CELL_SIZE
		);
		const int64_t sample_anchor_x = floor_div(
			positive_mod(p_sample_world_x, world_width),
			static_cast<int64_t>(MOUNTAIN_PASSAGE_ANCHOR_CELL_SIZE)
		);
		const int64_t sample_anchor_y = floor_div(
			p_world_y,
			static_cast<int64_t>(MOUNTAIN_PASSAGE_ANCHOR_CELL_SIZE)
		);
		const float passage_chance = world_utils::clamp_value(
			MOUNTAIN_PASSAGE_BASE_CHANCE + p_effective_mountain_settings.density * MOUNTAIN_PASSAGE_DENSITY_CHANCE,
			0.0f,
			0.12f
		);
		for (int32_t anchor_offset_y = -1; anchor_offset_y <= 1; ++anchor_offset_y) {
			const int64_t anchor_y = sample_anchor_y + anchor_offset_y;
			const int64_t anchor_origin_y = anchor_y * MOUNTAIN_PASSAGE_ANCHOR_CELL_SIZE;
			if (p_foundation_settings.enabled &&
					(anchor_origin_y >= p_foundation_settings.height_tiles ||
							anchor_origin_y + MOUNTAIN_PASSAGE_ANCHOR_CELL_SIZE - 1 < 0)) {
				continue;
			}
			for (int32_t anchor_offset_x = -1; anchor_offset_x <= 1; ++anchor_offset_x) {
				const int64_t canonical_anchor_x = positive_mod(sample_anchor_x + anchor_offset_x, anchor_cells_per_wrap);
				const uint64_t anchor_hash = hash_mountain_passage_anchor(
					p_seed,
					p_world_version,
					canonical_anchor_x,
					anchor_y,
					world_width
				);
				if (hash_unit_float(anchor_hash, 0U) > passage_chance) {
					continue;
				}
				const int64_t anchor_origin_x = canonical_anchor_x * MOUNTAIN_PASSAGE_ANCHOR_CELL_SIZE;
				const int64_t center_x = positive_mod(
					anchor_origin_x + 4 + static_cast<int64_t>(std::floor(hash_unit_float(anchor_hash, 16U) * 24.0f)),
					world_width
				);
				const int64_t center_y =
					anchor_origin_y +
					4 +
					static_cast<int64_t>(std::floor(hash_unit_float(anchor_hash, 32U) * 24.0f));
				if (p_foundation_settings.enabled && (center_y < 0 || center_y >= p_foundation_settings.height_tiles)) {
					continue;
				}
				if (mountain_field::is_spawn_safety_area_at_world(p_world_version, center_x, center_y) ||
						is_foundation_spawn_safety_area_at_world(center_x, center_y, p_foundation_settings)) {
					continue;
				}

				const float mode_roll = hash_unit_float(anchor_hash, 48U);
				const bool is_pocket = mode_roll >= 0.58f && mode_roll < 0.80f;
				const bool is_gorge = mode_roll >= 0.80f;
				const float angle = hash_unit_float(splitmix64(anchor_hash ^ 0x5bf03635f4a3e1c7ULL), 0U) * MOUNTAIN_PASSAGE_TAU;
				const float cos_angle = std::cos(angle);
				const float sin_angle = std::sin(angle);
				const float delta_x = static_cast<float>(signed_wrapped_delta_x(center_x, p_sample_world_x, world_width));
				const float delta_y = static_cast<float>(p_world_y - center_y);
				const float local_x = delta_x * cos_angle + delta_y * sin_angle;
				const float local_y = -delta_x * sin_angle + delta_y * cos_angle;
				const uint64_t tile_hash = splitmix64(
					anchor_hash ^
					static_cast<uint64_t>(positive_mod(p_sample_world_x, world_width)) * 0x9e3779b185ebca87ULL ^
					static_cast<uint64_t>(p_world_y) * 0xc2b2ae3d27d4eb4fULL
				);
				if (is_pocket) {
					const float radius_x = 3.2f + hash_unit_float(tile_hash, 8U) * 4.3f;
					const float radius_y = 2.2f + hash_unit_float(tile_hash, 24U) * 3.1f;
					const float normalized_x = local_x / radius_x;
					const float normalized_y = local_y / radius_y;
					const float breakup = (hash_unit_float(tile_hash, 40U) - 0.5f) * 0.10f;
					if (normalized_x * normalized_x + normalized_y * normalized_y + breakup <= 1.0f) {
						return true;
					}
					continue;
				}

				const float half_length = is_gorge ?
						11.0f + hash_unit_float(tile_hash, 8U) * 13.0f :
						7.0f + hash_unit_float(tile_hash, 8U) * 11.0f;
				const float half_width = is_gorge ?
						2.1f + hash_unit_float(tile_hash, 24U) * 1.4f :
						1.25f + hash_unit_float(tile_hash, 24U) * 1.05f;
				const float wave_phase = hash_unit_float(tile_hash, 40U) * MOUNTAIN_PASSAGE_TAU;
				const float wave_scale = 0.22f + hash_unit_float(tile_hash, 52U) * 0.12f;
				const float wave_offset = std::sin(local_x * wave_scale + wave_phase) * half_width * (is_gorge ? 0.30f : 0.22f);
				const float adjusted_y = local_y - wave_offset;
				const float abs_x = std::fabs(local_x);
				const float end_distance = std::max(0.0f, abs_x - half_length);
				const float length_t = world_utils::clamp_value(abs_x / std::max(1.0f, half_length), 0.0f, 1.0f);
				const float tapered_width = std::max(0.35f, half_width * (1.0f - length_t * (is_gorge ? 0.10f : 0.18f)));
				const float breakup = (hash_unit_float(tile_hash, 4U) - 0.5f) * 0.08f;
				const float score = (end_distance * end_distance + adjusted_y * adjusted_y) / (tapered_width * tapered_width) + breakup;
				if (score <= 1.0f) {
					return true;
				}
			}
		}
		return false;
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
			int32_t mountain_id = resolve_mountain_id_at_world(sample_world_x, world_y, elevation);
			if (mountain_passage_carve_open(sample_world_x, world_y, elevation, mountain_id)) {
				elevation = 0.0f;
				mountain_id = 0;
			}
			if (mountain_id == 0) {
				const SatelliteOutcropHit outcrop_hit = resolve_satellite_outcrop_hit(sample_world_x, world_y, elevation);
				if (outcrop_hit.active) {
					elevation = outcrop_hit.elevation;
					mountain_id = outcrop_hit.mountain_id;
				}
			}
			mountain_elevations[static_cast<size_t>(sample_index)] = elevation;
			mountain_ids[static_cast<size_t>(sample_index)] = mountain_id;
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

	WorldObjectPacketBuffers object_buffers;
	append_native_object_placements(
		object_buffers,
		p_seed,
		p_coord,
		p_world_version,
		terrain_ids,
		lake_flags
	);

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
	packet["object_kind"] = make_packed_byte_array(object_buffers.kind);
	packet["object_local_x_px_q4"] = make_packed_byte_array(object_buffers.local_x_px_q4);
	packet["object_local_y_px_q4"] = make_packed_byte_array(object_buffers.local_y_px_q4);
	packet["object_size_px"] = make_packed_byte_array(object_buffers.size_px);
	packet["object_atlas_index"] = make_packed_byte_array(object_buffers.atlas_index);
	packet["object_variant"] = make_packed_byte_array(object_buffers.variant);
	packet["object_flags"] = make_packed_byte_array(object_buffers.flags);
	packet["object_tint"] = make_packed_byte_array(object_buffers.tint);
	packet["object_phase"] = make_packed_byte_array(object_buffers.phase);
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
