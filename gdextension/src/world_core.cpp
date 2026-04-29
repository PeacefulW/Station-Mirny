#include "world_core.h"
#include "autotile_47.h"
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

using namespace godot;
using world_utils::splitmix64;
using world_utils::positive_mod;

namespace {

constexpr int64_t CHUNK_SIZE = 32;
constexpr int64_t CELL_COUNT = CHUNK_SIZE * CHUNK_SIZE;

constexpr int64_t TERRAIN_PLAINS_GROUND = 0;
constexpr int64_t TERRAIN_MOUNTAIN_WALL = 3;
constexpr int64_t TERRAIN_MOUNTAIN_FOOT = 4;
constexpr int64_t TERRAIN_RIVERBED_SHALLOW = 5;
constexpr int64_t TERRAIN_RIVERBED_DEEP = 6;
constexpr int64_t TERRAIN_OCEAN_FLOOR = 8;
constexpr int64_t TERRAIN_SHORE = 9;
constexpr int64_t TERRAIN_FLOODPLAIN = 10;

constexpr uint8_t WATER_CLASS_NONE = 0U;
constexpr uint8_t WATER_CLASS_SHALLOW = 1U;
constexpr uint8_t WATER_CLASS_DEEP = 2U;
constexpr uint8_t WATER_CLASS_OCEAN = 3U;

constexpr int32_t HYDROLOGY_FLAG_RIVERBED = 1 << 0;
constexpr int32_t HYDROLOGY_FLAG_SHORE = 1 << 2;
constexpr int32_t HYDROLOGY_FLAG_BANK = 1 << 3;
constexpr int32_t HYDROLOGY_FLAG_FLOODPLAIN = 1 << 4;
constexpr int32_t HYDROLOGY_FLAG_SOURCE = 1 << 8;

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
constexpr int64_t SETTINGS_PACKED_LAYOUT_FIELD_COUNT = 15;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_ENABLED = 15;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_TARGET_TRUNK_COUNT = 16;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_DENSITY = 17;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_WIDTH_SCALE = 18;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_LAKE_CHANCE = 19;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_MEANDER_STRENGTH = 20;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_BRAID_CHANCE = 21;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_SHALLOW_CROSSING_FREQUENCY = 22;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_MOUNTAIN_CLEARANCE_TILES = 23;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_DELTA_SCALE = 24;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_NORTH_DRAINAGE_BIAS = 25;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_HYDROLOGY_CELL_SIZE_TILES = 26;
constexpr int64_t SETTINGS_PACKED_LAYOUT_FIELD_COUNT_WITH_RIVERS = 27;

constexpr uint8_t MOUNTAIN_FLAG_WALL = 1U << 1U;
constexpr uint8_t MOUNTAIN_FLAG_FOOT = 1U << 2U;
constexpr uint8_t MOUNTAIN_FLAG_INTERIOR = 1U << 0U;
constexpr uint8_t MOUNTAIN_FLAG_ANCHOR = 1U << 3U;
constexpr int64_t LEGACY_WORLD_WRAP_WIDTH_TILES = world_utils::LEGACY_WORLD_WRAP_WIDTH_TILES;
constexpr int64_t WORLD_FOUNDATION_VERSION = 9;
constexpr int64_t WORLD_RIVER_VERSION = 17;
constexpr int64_t MOUNTAIN_FINITE_WIDTH_VERSION = world_utils::MOUNTAIN_FINITE_WIDTH_VERSION;
constexpr int64_t FOUNDATION_CHUNK_SIZE = 32;
constexpr int64_t SPAWN_SAFE_PATCH_MIN_TILE = 12;
constexpr int64_t SPAWN_SAFE_PATCH_MAX_TILE = 20;
constexpr size_t HIERARCHICAL_CACHE_LIMIT = 64;
constexpr int32_t RIVER_SEGMENT_RECORD_SIZE = 6;

struct RiverRasterEdge {
	float ax = 0.0f;
	float ay = 0.0f;
	float bx = 0.0f;
	float by = 0.0f;
	int32_t segment_id = 0;
	uint8_t stream_order = 0U;
	uint8_t flow_dir = world_hydrology_prepass::FLOW_DIR_TERMINAL;
	bool source = false;
};

struct RiverRasterSample {
	float distance = std::numeric_limits<float>::infinity();
	int32_t segment_id = 0;
	uint8_t stream_order = 0U;
	uint8_t flow_dir = world_hydrology_prepass::FLOW_DIR_TERMINAL;
	bool source = false;
};

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

bool uses_river_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_RIVER_VERSION;
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

float adjust_wrapped_x_near(float p_x, float p_anchor_x, float p_world_width_tiles) {
	if (p_world_width_tiles <= 1.0f) {
		return p_x;
	}
	float adjusted = p_x;
	const float half_width = p_world_width_tiles * 0.5f;
	while (adjusted - p_anchor_x > half_width) {
		adjusted -= p_world_width_tiles;
	}
	while (adjusted - p_anchor_x < -half_width) {
		adjusted += p_world_width_tiles;
	}
	return adjusted;
}

float distance_to_segment(float p_x, float p_y, const RiverRasterEdge &p_edge, float p_world_width_tiles) {
	const float px = adjust_wrapped_x_near(p_x, p_edge.ax, p_world_width_tiles);
	const float vx = p_edge.bx - p_edge.ax;
	const float vy = p_edge.by - p_edge.ay;
	const float wx = px - p_edge.ax;
	const float wy = p_y - p_edge.ay;
	const float length_sq = vx * vx + vy * vy;
	if (length_sq <= 0.0001f) {
		const float dx = px - p_edge.ax;
		const float dy = p_y - p_edge.ay;
		return std::sqrt(dx * dx + dy * dy);
	}
	const float t = world_utils::clamp_value((wx * vx + wy * vy) / length_sq, 0.0f, 1.0f);
	const float nearest_x = p_edge.ax + vx * t;
	const float nearest_y = p_edge.ay + vy * t;
	const float dx = px - nearest_x;
	const float dy = p_y - nearest_y;
	return std::sqrt(dx * dx + dy * dy);
}

RiverRasterSample sample_river_edges(
	const std::vector<RiverRasterEdge> &p_edges,
	float p_world_x,
	float p_world_y,
	float p_world_width_tiles
) {
	RiverRasterSample sample;
	for (const RiverRasterEdge &edge : p_edges) {
		const float distance = distance_to_segment(p_world_x, p_world_y, edge, p_world_width_tiles);
		if (distance >= sample.distance) {
			continue;
		}
		sample.distance = distance;
		sample.segment_id = edge.segment_id;
		sample.stream_order = edge.stream_order;
		sample.flow_dir = edge.flow_dir;
		sample.source = edge.source;
	}
	return sample;
}

std::vector<RiverRasterEdge> filter_river_edges_for_chunk(
	const std::vector<RiverRasterEdge> &p_edges,
	int64_t p_chunk_origin_x,
	int64_t p_chunk_origin_y,
	float p_world_width_tiles,
	float p_max_radius_tiles
) {
	std::vector<RiverRasterEdge> filtered;
	filtered.reserve(std::min<size_t>(p_edges.size(), 64));
	const float chunk_min_x = static_cast<float>(p_chunk_origin_x) - p_max_radius_tiles;
	const float chunk_max_x = static_cast<float>(p_chunk_origin_x + CHUNK_SIZE) + p_max_radius_tiles;
	const float chunk_min_y = static_cast<float>(p_chunk_origin_y) - p_max_radius_tiles;
	const float chunk_max_y = static_cast<float>(p_chunk_origin_y + CHUNK_SIZE) + p_max_radius_tiles;
	const float chunk_anchor_x = (chunk_min_x + chunk_max_x) * 0.5f;
	for (const RiverRasterEdge &edge : p_edges) {
		RiverRasterEdge adjusted = edge;
		adjusted.ax = adjust_wrapped_x_near(adjusted.ax, chunk_anchor_x, p_world_width_tiles);
		adjusted.bx = adjust_wrapped_x_near(adjusted.bx, adjusted.ax, p_world_width_tiles);
		const float min_x = std::min(adjusted.ax, adjusted.bx);
		const float max_x = std::max(adjusted.ax, adjusted.bx);
		const float min_y = std::min(adjusted.ay, adjusted.by);
		const float max_y = std::max(adjusted.ay, adjusted.by);
		if (max_x < chunk_min_x || min_x > chunk_max_x || max_y < chunk_min_y || min_y > chunk_max_y) {
			continue;
		}
		filtered.push_back(adjusted);
	}
	return filtered;
}

std::vector<RiverRasterEdge> build_river_raster_edges(const world_hydrology_prepass::Snapshot &p_snapshot) {
	std::vector<RiverRasterEdge> edges;
	if (!p_snapshot.valid || p_snapshot.river_segment_ranges.empty() || p_snapshot.river_path_node_indices.empty()) {
		return edges;
	}
	for (size_t record_offset = 0; record_offset + RIVER_SEGMENT_RECORD_SIZE <= p_snapshot.river_segment_ranges.size(); record_offset += RIVER_SEGMENT_RECORD_SIZE) {
		const int32_t segment_id = p_snapshot.river_segment_ranges[record_offset];
		const int32_t path_offset = p_snapshot.river_segment_ranges[record_offset + 1];
		const int32_t path_length = p_snapshot.river_segment_ranges[record_offset + 2];
		if (segment_id <= 0 || path_offset < 0 || path_length < 2) {
			continue;
		}
		const int32_t path_end = path_offset + path_length;
		if (path_end > static_cast<int32_t>(p_snapshot.river_path_node_indices.size())) {
			continue;
		}
		for (int32_t path_index = path_offset; path_index < path_end - 1; ++path_index) {
			const int32_t from_node = p_snapshot.river_path_node_indices[static_cast<size_t>(path_index)];
			const int32_t to_node = p_snapshot.river_path_node_indices[static_cast<size_t>(path_index + 1)];
			if (from_node < 0 || to_node < 0 ||
					from_node >= p_snapshot.grid_width * p_snapshot.grid_height ||
					to_node >= p_snapshot.grid_width * p_snapshot.grid_height) {
				continue;
			}
			const Vector2i from_center = p_snapshot.node_to_tile_center(from_node % p_snapshot.grid_width, from_node / p_snapshot.grid_width);
			const Vector2i to_center = p_snapshot.node_to_tile_center(to_node % p_snapshot.grid_width, to_node / p_snapshot.grid_width);
			RiverRasterEdge edge;
			edge.ax = static_cast<float>(from_center.x) + 0.5f;
			edge.ay = static_cast<float>(from_center.y) + 0.5f;
			edge.bx = adjust_wrapped_x_near(static_cast<float>(to_center.x) + 0.5f, edge.ax, static_cast<float>(std::max<int64_t>(1, p_snapshot.width_tiles)));
			edge.by = static_cast<float>(to_center.y) + 0.5f;
			edge.segment_id = segment_id;
			edge.stream_order = p_snapshot.river_stream_order.size() > static_cast<size_t>(from_node) ?
					p_snapshot.river_stream_order[static_cast<size_t>(from_node)] :
					1U;
			edge.flow_dir = p_snapshot.flow_dir.size() > static_cast<size_t>(from_node) ?
					p_snapshot.flow_dir[static_cast<size_t>(from_node)] :
					world_hydrology_prepass::FLOW_DIR_TERMINAL;
			edge.source = path_index == path_offset;
			edges.push_back(edge);
		}
	}
	return edges;
}

int32_t sample_hydrology_node_index(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int64_t p_world_x,
	int64_t p_world_y
) {
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0) {
		return -1;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(
		p_world_x / std::max<int32_t>(1, p_snapshot.cell_size_tiles),
		p_snapshot.grid_width
	));
	const int32_t node_y = world_utils::clamp_value(
		static_cast<int32_t>(p_world_y / std::max<int32_t>(1, p_snapshot.cell_size_tiles)),
		0,
		p_snapshot.grid_height - 1
	);
	return p_snapshot.index(node_x, node_y);
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

world_hydrology_prepass::RiverSettings unpack_river_settings(const PackedFloat32Array &p_settings_packed) {
	world_hydrology_prepass::RiverSettings settings;
	settings.enabled = p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_ENABLED] >= 0.5f;
	settings.target_trunk_count = std::max<int32_t>(
		0,
		static_cast<int32_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_TARGET_TRUNK_COUNT]))
	);
	settings.density = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_DENSITY]);
	settings.width_scale = world_utils::clamp_value(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_WIDTH_SCALE], 0.25f, 4.0f);
	settings.lake_chance = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_LAKE_CHANCE]);
	settings.meander_strength = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_MEANDER_STRENGTH]);
	settings.braid_chance = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_BRAID_CHANCE]);
	settings.shallow_crossing_frequency = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_SHALLOW_CROSSING_FREQUENCY]);
	settings.mountain_clearance_tiles = world_utils::clamp_value(
		static_cast<int32_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_MOUNTAIN_CLEARANCE_TILES])),
		1,
		16
	);
	settings.delta_scale = world_utils::clamp_value(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_DELTA_SCALE], 0.0f, 2.0f);
	settings.north_drainage_bias = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_NORTH_DRAINAGE_BIAS]);
	settings.hydrology_cell_size_tiles = world_utils::clamp_value(
		static_cast<int32_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_HYDROLOGY_CELL_SIZE_TILES])),
		8,
		64
	);
	return settings;
}

int64_t expected_settings_count_for_version(int64_t p_world_version) {
	if (uses_river_generation(p_world_version)) {
		return SETTINGS_PACKED_LAYOUT_FIELD_COUNT_WITH_RIVERS;
	}
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
	ClassDB::bind_method(D_METHOD("resolve_world_foundation_spawn_tile", "seed", "world_version", "settings_packed"), &WorldCore::resolve_world_foundation_spawn_tile);
	ClassDB::bind_method(D_METHOD("build_world_hydrology_prepass", "seed", "world_version", "settings_packed"), &WorldCore::build_world_hydrology_prepass);
#ifdef DEBUG_ENABLED
	ClassDB::bind_method(D_METHOD("get_world_foundation_snapshot", "layer_mask", "downscale_factor"), &WorldCore::get_world_foundation_snapshot);
	ClassDB::bind_method(D_METHOD("get_world_foundation_overview", "layer_mask", "pixels_per_cell"), &WorldCore::get_world_foundation_overview, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("get_world_hydrology_snapshot", "layer_mask", "downscale_factor"), &WorldCore::get_world_hydrology_snapshot);
	ClassDB::bind_method(D_METHOD("get_world_hydrology_overview", "layer_mask", "pixels_per_cell"), &WorldCore::get_world_hydrology_overview, DEFVAL(1));
#endif
}

WorldCore::WorldCore() :
		hierarchical_macro_cache_(std::make_unique<HierarchicalMacroCache>()),
		world_prepass_snapshot_(std::make_unique<world_prepass::Snapshot>()),
		world_hydrology_prepass_snapshot_(std::make_unique<world_hydrology_prepass::Snapshot>()) {}

WorldCore::~WorldCore() = default;

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
	const FoundationSettings &p_foundation_settings
) {
	const uint64_t signature = world_prepass::make_signature(
		p_seed,
		p_world_version,
		p_effective_mountain_settings,
		p_foundation_settings
	);
	if (world_prepass_snapshot_ == nullptr ||
			!world_prepass_snapshot_->valid ||
			world_prepass_snapshot_->signature != signature) {
		world_prepass_snapshot_ = world_prepass::build_snapshot(
			p_seed,
			p_world_version,
			p_mountain_evaluator,
			p_effective_mountain_settings,
			p_foundation_settings
		);
	}
	world_prepass_effective_mountain_settings_ = p_effective_mountain_settings;
	world_prepass_foundation_settings_ = p_foundation_settings;
	return *world_prepass_snapshot_;
}

const world_hydrology_prepass::Snapshot &WorldCore::_get_or_build_world_hydrology_prepass(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_effective_mountain_settings,
	const FoundationSettings &p_foundation_settings,
	const world_hydrology_prepass::RiverSettings &p_river_settings,
	bool &r_cache_hit
) {
	const world_prepass::Snapshot &foundation_snapshot = _get_or_build_world_prepass(
		p_seed,
		p_world_version,
		p_mountain_evaluator,
		p_effective_mountain_settings,
		p_foundation_settings
	);
	const uint64_t signature = world_hydrology_prepass::make_signature(
		p_seed,
		p_world_version,
		p_foundation_settings,
		p_river_settings
	);
	r_cache_hit = world_hydrology_prepass_snapshot_ != nullptr &&
			world_hydrology_prepass_snapshot_->valid &&
			world_hydrology_prepass_snapshot_->signature == signature;
	if (!r_cache_hit) {
		world_hydrology_prepass_snapshot_ = world_hydrology_prepass::build_snapshot(
			p_seed,
			p_world_version,
			foundation_snapshot,
			p_foundation_settings,
			p_river_settings
		);
	}
	return *world_hydrology_prepass_snapshot_;
}

Dictionary WorldCore::_generate_chunk_packet(
	int64_t p_seed,
	Vector2i p_coord,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_effective_mountain_settings,
	const FoundationSettings &p_foundation_settings,
	const world_hydrology_prepass::Snapshot *p_hydrology_snapshot,
	const world_hydrology_prepass::RiverSettings *p_river_settings
) {
	p_coord = canonicalize_chunk_coord(p_coord, p_foundation_settings);
	PackedInt32Array terrain_ids;
	terrain_ids.resize(CELL_COUNT);
	PackedInt32Array terrain_atlas_indices;
	terrain_atlas_indices.resize(CELL_COUNT);
	PackedByteArray walkable_flags;
	walkable_flags.resize(CELL_COUNT);
	PackedInt32Array mountain_id_per_tile;
	mountain_id_per_tile.resize(CELL_COUNT);
	PackedByteArray mountain_flags;
	mountain_flags.resize(CELL_COUNT);
	PackedInt32Array mountain_atlas_indices;
	mountain_atlas_indices.resize(CELL_COUNT);
	const bool has_hydrology = p_hydrology_snapshot != nullptr &&
			p_hydrology_snapshot->valid &&
			p_river_settings != nullptr &&
			p_river_settings->enabled;
	PackedInt32Array hydrology_id_per_tile;
	PackedInt32Array hydrology_flags;
	PackedByteArray floodplain_strength;
	PackedByteArray water_class;
	PackedByteArray flow_dir_quantized;
	PackedByteArray stream_order;
	PackedInt32Array water_atlas_indices;
	if (has_hydrology) {
		hydrology_id_per_tile.resize(CELL_COUNT);
		hydrology_flags.resize(CELL_COUNT);
		floodplain_strength.resize(CELL_COUNT);
		water_class.resize(CELL_COUNT);
		flow_dir_quantized.resize(CELL_COUNT);
		stream_order.resize(CELL_COUNT);
		water_atlas_indices.resize(CELL_COUNT);
	}
	const float river_width_scale = has_hydrology ? p_river_settings->width_scale : 1.0f;
	const float max_river_radius = std::max(6.0f, 4.0f + river_width_scale * 4.0f);
	std::vector<RiverRasterEdge> river_edges;
	if (has_hydrology) {
		const std::vector<RiverRasterEdge> all_edges = build_river_raster_edges(*p_hydrology_snapshot);
		river_edges = filter_river_edges_for_chunk(
			all_edges,
			static_cast<int64_t>(p_coord.x) * CHUNK_SIZE,
			clamp_foundation_world_y(static_cast<int64_t>(p_coord.y) * CHUNK_SIZE, p_foundation_settings),
			static_cast<float>(std::max<int64_t>(1, p_hydrology_snapshot->width_tiles)),
			max_river_radius
		);
	}

	const mountain_field::Thresholds &mountain_thresholds = p_mountain_evaluator.get_thresholds();
	const int32_t macro_cell_size = mountain_field::get_hierarchical_macro_cell_size(p_world_version);
	const int64_t mountain_border = std::max<int64_t>(1, p_effective_mountain_settings.interior_margin);
	const int64_t mountain_grid_side = CHUNK_SIZE + mountain_border * 2;
	std::vector<float> mountain_elevations(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0.0f);
	std::vector<int32_t> mountain_ids(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0);

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
			int32_t resolved_hydrology_id = 0;
			int32_t resolved_hydrology_flags = 0;
			uint8_t resolved_floodplain_strength = 0U;
			uint8_t resolved_water_class = WATER_CLASS_NONE;
			uint8_t resolved_flow_dir = world_hydrology_prepass::FLOW_DIR_TERMINAL;
			uint8_t resolved_stream_order = 0U;
			int32_t resolved_water_atlas_index = 0;

			if (terrain_id == TERRAIN_PLAINS_GROUND) {
				terrain_atlas_index = resolve_base_ground_atlas_index(
					world_x,
					world_y,
					p_seed,
					true,
					true,
					true,
					true,
					true,
					true,
					true,
					true
				);
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

			const bool hydrology_blocked =
					(resolved_mountain_flags & (MOUNTAIN_FLAG_WALL | MOUNTAIN_FLAG_FOOT)) != 0U;
			if (has_hydrology && !hydrology_blocked) {
				const int32_t hydrology_node_index = sample_hydrology_node_index(
					*p_hydrology_snapshot,
					world_x,
					world_y
				);
				if (hydrology_node_index >= 0) {
					const size_t node_index = static_cast<size_t>(hydrology_node_index);
					if (node_index < p_hydrology_snapshot->ocean_sink_mask.size() &&
							p_hydrology_snapshot->ocean_sink_mask[node_index] != 0U) {
						terrain_id = TERRAIN_OCEAN_FLOOR;
						terrain_atlas_index = 0;
						walkable = 0U;
						resolved_water_class = WATER_CLASS_OCEAN;
						resolved_water_atlas_index = static_cast<int32_t>(WATER_CLASS_OCEAN) * 16;
					} else {
						const RiverRasterSample river_sample = sample_river_edges(
							river_edges,
							static_cast<float>(world_x) + 0.5f,
							static_cast<float>(world_y) + 0.5f,
							static_cast<float>(std::max<int64_t>(1, p_hydrology_snapshot->width_tiles))
						);
						if (river_sample.segment_id > 0) {
							const float order_f = std::max(1.0f, static_cast<float>(river_sample.stream_order));
							const float deep_radius = std::max(0.55f, (0.35f + order_f * 0.16f) * river_width_scale);
							const float bed_radius = std::max(1.25f, deep_radius + 0.9f + river_width_scale * 0.25f);
							const float bank_radius = bed_radius + 1.5f;
							if (river_sample.distance <= bed_radius) {
								const uint64_t crossing_noise = splitmix64(
									static_cast<uint64_t>(p_seed) ^
									(static_cast<uint64_t>(river_sample.segment_id) << 32U) ^
									static_cast<uint64_t>(world_x * 73856093LL) ^
									static_cast<uint64_t>(world_y * 19349663LL)
								);
								const float crossing_threshold = world_utils::saturate(
									p_river_settings->shallow_crossing_frequency
								) * 0.18f;
								const bool shallow_crossing =
										static_cast<float>(crossing_noise & 1023ULL) / 1023.0f < crossing_threshold;
								const bool deep_water = order_f >= 4.0f &&
										river_sample.distance <= deep_radius &&
										!shallow_crossing;
								terrain_id = deep_water ? TERRAIN_RIVERBED_DEEP : TERRAIN_RIVERBED_SHALLOW;
								terrain_atlas_index = 0;
								walkable = deep_water ? 0U : 1U;
								resolved_hydrology_id = river_sample.segment_id;
								resolved_hydrology_flags = HYDROLOGY_FLAG_RIVERBED |
										(river_sample.source ? HYDROLOGY_FLAG_SOURCE : 0);
								resolved_water_class = deep_water ? WATER_CLASS_DEEP : WATER_CLASS_SHALLOW;
								resolved_flow_dir = river_sample.flow_dir;
								resolved_stream_order = static_cast<uint8_t>(world_utils::clamp_value(
									static_cast<int32_t>(river_sample.stream_order),
									1,
									255
								));
								resolved_water_atlas_index = static_cast<int32_t>(resolved_water_class) * 16 +
										(river_sample.flow_dir < 8U ? static_cast<int32_t>(river_sample.flow_dir) : 0);
							} else if (river_sample.distance <= bank_radius) {
								terrain_id = TERRAIN_SHORE;
								terrain_atlas_index = 0;
								resolved_hydrology_id = river_sample.segment_id;
								resolved_hydrology_flags = HYDROLOGY_FLAG_SHORE | HYDROLOGY_FLAG_BANK;
								resolved_flow_dir = river_sample.flow_dir;
								resolved_stream_order = static_cast<uint8_t>(world_utils::clamp_value(
									static_cast<int32_t>(river_sample.stream_order),
									1,
									255
								));
								const float bank_t = 1.0f - world_utils::saturate(
									(river_sample.distance - bed_radius) / std::max(0.01f, bank_radius - bed_radius)
								);
								resolved_floodplain_strength = static_cast<uint8_t>(world_utils::clamp_value(
									static_cast<int32_t>(std::lround(bank_t * 255.0f)),
									0,
									255
								));
							}
						} else if (node_index < p_hydrology_snapshot->floodplain_potential.size()) {
							const float floodplain = p_hydrology_snapshot->floodplain_potential[node_index];
							if (floodplain > 0.62f) {
								terrain_id = TERRAIN_FLOODPLAIN;
								terrain_atlas_index = 0;
								resolved_hydrology_flags = HYDROLOGY_FLAG_FLOODPLAIN;
								resolved_floodplain_strength = static_cast<uint8_t>(world_utils::clamp_value(
									static_cast<int32_t>(std::lround(floodplain * 255.0f)),
									0,
									255
								));
							}
						}
					}
				}
			}

			terrain_ids.set(index, terrain_id);
			terrain_atlas_indices.set(index, terrain_atlas_index);
			walkable_flags.set(index, walkable);
			mountain_id_per_tile.set(index, resolved_mountain_id);
			mountain_flags.set(index, resolved_mountain_flags);
			mountain_atlas_indices.set(index, resolved_mountain_atlas_index);
			if (has_hydrology) {
				hydrology_id_per_tile.set(index, resolved_hydrology_id);
				hydrology_flags.set(index, resolved_hydrology_flags);
				floodplain_strength.set(index, resolved_floodplain_strength);
				water_class.set(index, resolved_water_class);
				flow_dir_quantized.set(index, resolved_flow_dir);
				stream_order.set(index, resolved_stream_order);
				water_atlas_indices.set(index, resolved_water_atlas_index);
			}
		}
	}

	Dictionary packet;
	packet["chunk_coord"] = p_coord;
	packet["world_seed"] = p_seed;
	packet["world_version"] = p_world_version;
	packet["terrain_ids"] = terrain_ids;
	packet["terrain_atlas_indices"] = terrain_atlas_indices;
	packet["walkable_flags"] = walkable_flags;
	packet["mountain_id_per_tile"] = mountain_id_per_tile;
	packet["mountain_flags"] = mountain_flags;
	packet["mountain_atlas_indices"] = mountain_atlas_indices;
	if (has_hydrology) {
		packet["hydrology_id_per_tile"] = hydrology_id_per_tile;
		packet["hydrology_flags"] = hydrology_flags;
		packet["floodplain_strength"] = floodplain_strength;
		packet["water_class"] = water_class;
		packet["flow_dir_quantized"] = flow_dir_quantized;
		packet["stream_order"] = stream_order;
		packet["water_atlas_indices"] = water_atlas_indices;
	}
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
		foundation_settings
	);
	Dictionary result = world_prepass::resolve_spawn_tile(snapshot);
	result["grid_width"] = snapshot.grid_width;
	result["grid_height"] = snapshot.grid_height;
	result["coarse_cell_size_tiles"] = world_prepass::COARSE_CELL_SIZE_TILES;
	result["compute_time_ms"] = snapshot.compute_time_ms;
	return result;
}

Dictionary WorldCore::build_world_hydrology_prepass(
	int64_t p_seed,
	int64_t p_world_version,
	PackedFloat32Array p_settings_packed
) {
	if (p_world_version < WORLD_FOUNDATION_VERSION) {
		return make_failure_result("World hydrology prepass requires world foundation version.");
	}
	if (p_settings_packed.size() != SETTINGS_PACKED_LAYOUT_FIELD_COUNT_WITH_RIVERS) {
		return make_failure_result("World hydrology prepass received an invalid settings payload size.");
	}
	if (!mountain_field::uses_hierarchical_labeling(p_world_version)) {
		return make_failure_result("World hydrology prepass requires hierarchical mountain labeling.");
	}

	const FoundationSettings foundation_settings = unpack_foundation_settings(p_world_version, p_settings_packed);
	const mountain_field::Settings mountain_settings = make_effective_mountain_settings(
		p_world_version,
		unpack_mountain_settings(p_settings_packed),
		foundation_settings
	);
	const world_hydrology_prepass::RiverSettings river_settings = unpack_river_settings(p_settings_packed);
	if (!foundation_settings.enabled) {
		return make_failure_result("World foundation settings are disabled.");
	}
	if (!river_settings.enabled) {
		return make_failure_result("River settings are disabled.");
	}

	const mountain_field::Evaluator mountain_evaluator(p_seed, p_world_version, mountain_settings);
	const mountain_field::Settings &effective_mountain_settings = mountain_evaluator.get_settings();
	bool cache_hit = false;
	const world_hydrology_prepass::Snapshot &snapshot = _get_or_build_world_hydrology_prepass(
		p_seed,
		p_world_version,
		mountain_evaluator,
		effective_mountain_settings,
		foundation_settings,
		river_settings,
		cache_hit
	);
	return world_hydrology_prepass::make_build_result(snapshot, cache_hit);
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
		p_layer_mask,
		p_pixels_per_cell
	);
}

Dictionary WorldCore::get_world_hydrology_snapshot(int64_t p_layer_mask, int64_t p_downscale_factor) {
	if (world_hydrology_prepass_snapshot_ == nullptr || !world_hydrology_prepass_snapshot_->valid) {
		return Dictionary();
	}
	return world_hydrology_prepass::make_debug_snapshot(*world_hydrology_prepass_snapshot_, p_layer_mask, p_downscale_factor);
}

Ref<Image> WorldCore::get_world_hydrology_overview(int64_t p_layer_mask, int64_t p_pixels_per_cell) {
	if (world_hydrology_prepass_snapshot_ == nullptr || !world_hydrology_prepass_snapshot_->valid) {
		return Ref<Image>();
	}
	return world_hydrology_prepass::make_overview_image(
		*world_hydrology_prepass_snapshot_,
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
	const mountain_field::Settings mountain_settings = make_effective_mountain_settings(
		p_world_version,
		unpack_mountain_settings(p_settings_packed),
		foundation_settings
	);
	const mountain_field::Evaluator mountain_evaluator(p_seed, p_world_version, mountain_settings);
	const mountain_field::Settings &effective_mountain_settings = mountain_evaluator.get_settings();
	const int32_t macro_cell_size = mountain_field::get_hierarchical_macro_cell_size(p_world_version);
	world_hydrology_prepass::RiverSettings river_settings;
	const world_hydrology_prepass::Snapshot *hydrology_snapshot = nullptr;
	if (uses_river_generation(p_world_version)) {
		river_settings = unpack_river_settings(p_settings_packed);
		ERR_FAIL_COND_V_MSG(
			!foundation_settings.enabled,
			Array{},
			"WorldCore.generate_chunk_packets_batch requires world foundation settings for river generation."
		);
		ERR_FAIL_COND_V_MSG(
			!river_settings.enabled,
			Array{},
			"WorldCore.generate_chunk_packets_batch requires enabled river settings for river generation."
		);
		bool hydrology_cache_hit = false;
		hydrology_snapshot = &_get_or_build_world_hydrology_prepass(
			p_seed,
			p_world_version,
			mountain_evaluator,
			effective_mountain_settings,
			foundation_settings,
			river_settings,
			hydrology_cache_hit
		);
		ERR_FAIL_COND_V_MSG(
			hydrology_snapshot == nullptr || !hydrology_snapshot->valid,
			Array{},
			"WorldCore.generate_chunk_packets_batch failed to build world hydrology prepass."
		);
	}

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
				hydrology_snapshot,
				uses_river_generation(p_world_version) ? &river_settings : nullptr
			);
		}
	}
	return packets;
}
