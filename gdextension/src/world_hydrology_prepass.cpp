#include "world_hydrology_prepass.h"
#include "mountain_field.h"
#include "world_utils.h"

#include "third_party/FastNoiseLite.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <functional>
#include <limits>
#include <queue>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;
using world_utils::clamp_value;
using world_utils::positive_mod;
using world_utils::saturate;
using world_utils::splitmix64;

namespace world_hydrology_prepass {
namespace {

constexpr uint64_t SEED_SALT_COASTLINE = 0x6a09e667f3bcc909ULL;
constexpr uint8_t FLOW_DIR_NONE = FLOW_DIR_TERMINAL;
constexpr int32_t FLOW_DX[8] = { 0, 1, 1, 1, 0, -1, -1, -1 };
constexpr int32_t FLOW_DY[8] = { -1, -1, 0, 1, 1, 1, 0, -1 };
constexpr int64_t LAYER_MASK_FLOW_ACCUMULATION = 1LL << 0;
constexpr int64_t LAYER_MASK_FILLED_ELEVATION = 1LL << 1;
constexpr int64_t LAYER_MASK_TRANSPARENT_WATER_OVERLAY = 1LL << 6;
constexpr int32_t RIVER_SEGMENT_RECORD_SIZE = 6;
constexpr int64_t WORLD_LAKE_VERSION = 18;
constexpr int64_t WORLD_DELTA_VERSION = 19;
constexpr int64_t WORLD_ORGANIC_WATER_VERSION = 20;
constexpr int64_t WORLD_REFINED_RIVER_VERSION = 22;
constexpr int64_t WORLD_CURVATURE_RIVER_VERSION = 23;
constexpr int64_t WORLD_Y_CONFLUENCE_RIVER_VERSION = 24;
constexpr int64_t WORLD_BRAID_LOOP_RIVER_VERSION = 25;
constexpr int64_t WORLD_BASIN_CONTOUR_LAKE_VERSION = 26;
constexpr int64_t WORLD_ORGANIC_COASTLINE_VERSION = 27;
constexpr int64_t WORLD_HYDROLOGY_SHAPE_FIX_VERSION = 28;
constexpr int64_t WORLD_HEADLAND_COAST_VERSION = 29;
constexpr int32_t REFINED_RIVER_INDEX_CELL_SIZE_TILES = 64;
constexpr float REFINED_RIVER_INDEX_PADDING_TILES = 32.0f;
constexpr uint64_t SEED_SALT_LAKE_SELECTION = 0xbb67ae8584caa73bULL;
constexpr uint64_t SEED_SALT_LAKE_OUTLINE = 0x3c6ef372fe94f82bULL;
constexpr float PI = 3.14159265358979323846f;

struct QueueNode {
	float elevation = 0.0f;
	int32_t index = 0;

	bool operator>(const QueueNode &p_other) const {
		if (elevation == p_other.elevation) {
			return index > p_other.index;
		}
		return elevation > p_other.elevation;
	}
};

struct OverviewRiverEdge {
	float ax = 0.0f;
	float ay = 0.0f;
	float bx = 0.0f;
	float by = 0.0f;
	uint8_t stream_order = 1U;
	float radius_scale = 1.0f;
	float cumulative_start = 0.0f;
	float cumulative_end = 0.0f;
	float total_distance = 0.0f;
	float distance_at_source = 0.0f;
	float distance_to_terminal = 0.0f;
	uint64_t variation_seed = 0ULL;
	bool delta = false;
	bool braid_split = false;
	bool organic = false;
	bool shape_quality_v2_fix = false;
};

struct SegmentProjection {
	float distance = std::numeric_limits<float>::infinity();
	float t = 0.0f;
};

struct OverviewRiverSample {
	float distance = std::numeric_limits<float>::infinity();
	uint8_t stream_order = 1U;
	float radius_scale = 1.0f;
	bool delta = false;
	bool braid_split = false;
};

struct OceanOverviewSample {
	bool is_ocean = false;
	bool is_shore = false;
	bool is_shallow_shelf = false;
};

bool uses_hydrology_visual_v3(int64_t p_world_version) {
	return p_world_version >= mountain_field::WORLD_HYDROLOGY_VISUAL_V3_VERSION;
}

struct LakeBasinCandidate {
	std::vector<int32_t> nodes;
	int32_t outlet_node = -1;
	int32_t outlet_downstream_node = -1;
	uint8_t outlet_flow_dir = FLOW_DIR_NONE;
	float max_depth = 0.0f;
	float average_accumulation = 0.0f;
	float score = 0.0f;
	uint64_t stable_key = 0;
};

struct RiverCenterSample {
	float x = 0.0f;
	float y = 0.0f;
	float cumulative = 0.0f;
	int32_t node_index = -1;
	uint8_t stream_order = 1U;
	uint8_t flow_dir = FLOW_DIR_TERMINAL;
	float radius_scale = 1.0f;
	float curvature = 0.0f;
	float confluence_weight = 0.0f;
	float local_t = 0.0f;
	int32_t next_node_index = -1;
	bool source = false;
	bool delta = false;
	bool braid_split = false;
	bool confluence = false;
};

uint64_t mix_seed(int64_t p_seed, int64_t p_world_version, uint64_t p_salt) {
	return world_utils::mix_seed(p_seed, p_world_version, p_salt);
}

int make_noise_seed(uint64_t p_value) {
	return static_cast<int>(p_value & 0x7fffffffULL);
}

FastNoiseLite make_noise(uint64_t p_seed, float p_frequency, int p_octaves = 3) {
	FastNoiseLite noise(make_noise_seed(p_seed));
	noise.SetNoiseType(FastNoiseLite::NoiseType_OpenSimplex2);
	noise.SetFractalType(FastNoiseLite::FractalType_FBm);
	noise.SetFractalOctaves(p_octaves);
	noise.SetFractalLacunarity(2.0f);
	noise.SetFractalGain(0.5f);
	noise.SetFrequency(p_frequency);
	return noise;
}

float sample_cylindrical_noise(
	FastNoiseLite &p_noise,
	float p_world_x,
	float p_world_y,
	float p_width_tiles
) {
	constexpr float two_pi = 6.28318530717958647692f;
	const float wrapped_x = std::fmod(std::max(0.0f, p_world_x), std::max(1.0f, p_width_tiles));
	const float theta = (wrapped_x / std::max(1.0f, p_width_tiles)) * two_pi;
	const float radius = std::max(1.0f, p_width_tiles) / two_pi;
	return p_noise.GetNoise(std::cos(theta) * radius, std::sin(theta) * radius, p_world_y);
}

int32_t sample_foundation_index(const world_prepass::Snapshot &p_snapshot, int64_t p_world_x, int64_t p_world_y) {
	const int32_t x = static_cast<int32_t>(positive_mod(
		p_world_x / world_prepass::COARSE_CELL_SIZE_TILES,
		p_snapshot.grid_width
	));
	const int32_t y = clamp_value(
		static_cast<int32_t>(p_world_y / world_prepass::COARSE_CELL_SIZE_TILES),
		0,
		std::max<int32_t>(0, p_snapshot.grid_height - 1)
	);
	return p_snapshot.index(x, y);
}

int64_t resolve_mountain_sample_x(
	int64_t p_world_x,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings
) {
	return world_utils::resolve_mountain_sample_x(
		p_world_x,
		p_world_version,
		p_foundation_settings.width_tiles,
		p_foundation_settings.enabled
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

uint64_t make_macro_key(int64_t p_macro_x, int64_t p_macro_y) {
	uint64_t key = splitmix64(static_cast<uint64_t>(p_macro_x));
	key = splitmix64(key ^ static_cast<uint64_t>(p_macro_y) * 0x9e3779b185ebca87ULL);
	return key;
}

PackedFloat32Array make_float_array(const std::vector<float> &p_values) {
	PackedFloat32Array result;
	result.resize(static_cast<int32_t>(p_values.size()));
	for (int32_t index = 0; index < static_cast<int32_t>(p_values.size()); ++index) {
		result.set(index, p_values[static_cast<size_t>(index)]);
	}
	return result;
}

PackedInt32Array make_int_array(const std::vector<int32_t> &p_values) {
	PackedInt32Array result;
	result.resize(static_cast<int32_t>(p_values.size()));
	for (int32_t index = 0; index < static_cast<int32_t>(p_values.size()); ++index) {
		result.set(index, p_values[static_cast<size_t>(index)]);
	}
	return result;
}

PackedByteArray make_byte_array(const std::vector<uint8_t> &p_values) {
	PackedByteArray result;
	result.resize(static_cast<int32_t>(p_values.size()));
	for (int32_t index = 0; index < static_cast<int32_t>(p_values.size()); ++index) {
		result.set(index, p_values[static_cast<size_t>(index)]);
	}
	return result;
}

PackedFloat32Array make_refined_edge_points_array(const std::vector<RefinedRiverEdge> &p_edges) {
	PackedFloat32Array result;
	result.resize(static_cast<int32_t>(p_edges.size() * 4));
	int32_t offset = 0;
	for (const RefinedRiverEdge &edge : p_edges) {
		result.set(offset++, edge.ax);
		result.set(offset++, edge.ay);
		result.set(offset++, edge.bx);
		result.set(offset++, edge.by);
	}
	return result;
}

PackedFloat32Array make_refined_edge_tangents_array(const std::vector<RefinedRiverEdge> &p_edges) {
	PackedFloat32Array result;
	result.resize(static_cast<int32_t>(p_edges.size() * 4));
	int32_t offset = 0;
	for (const RefinedRiverEdge &edge : p_edges) {
		const float dx = edge.bx - edge.ax;
		const float dy = edge.by - edge.ay;
		const float length = std::max(0.0001f, std::sqrt(dx * dx + dy * dy));
		const float tx = dx / length;
		const float ty = dy / length;
		result.set(offset++, tx);
		result.set(offset++, ty);
		result.set(offset++, -ty);
		result.set(offset++, tx);
	}
	return result;
}

PackedFloat32Array make_refined_edge_shape_metrics_array(const std::vector<RefinedRiverEdge> &p_edges) {
	PackedFloat32Array result;
	result.resize(static_cast<int32_t>(p_edges.size() * 4));
	int32_t offset = 0;
	for (const RefinedRiverEdge &edge : p_edges) {
		result.set(offset++, edge.radius_scale);
		result.set(offset++, edge.curvature);
		result.set(offset++, edge.confluence_weight);
		result.set(offset++, edge.braid_loop_weight);
	}
	return result;
}

PackedInt32Array make_refined_edge_metadata_array(const std::vector<RefinedRiverEdge> &p_edges) {
	PackedInt32Array result;
	result.resize(static_cast<int32_t>(p_edges.size() * 4));
	int32_t offset = 0;
	for (const RefinedRiverEdge &edge : p_edges) {
		int32_t flags = 0;
		flags |= edge.source ? 1 : 0;
		flags |= edge.delta ? 2 : 0;
		flags |= edge.braid_split ? 4 : 0;
		flags |= edge.braid_loop ? 8 : 0;
		flags |= edge.confluence ? 16 : 0;
		flags |= edge.organic ? 32 : 0;
		result.set(offset++, edge.segment_id);
		result.set(offset++, static_cast<int32_t>(edge.stream_order));
		result.set(offset++, static_cast<int32_t>(edge.flow_dir));
		result.set(offset++, flags);
	}
	return result;
}

void write_rgba(PackedByteArray &r_bytes, int32_t p_offset, uint8_t p_r, uint8_t p_g, uint8_t p_b, uint8_t p_a = 255) {
	r_bytes.set(p_offset, p_r);
	r_bytes.set(p_offset + 1, p_g);
	r_bytes.set(p_offset + 2, p_b);
	r_bytes.set(p_offset + 3, p_a);
}

uint8_t direction_from_to(int32_t p_from_x, int32_t p_from_y, int32_t p_to_x, int32_t p_to_y, int32_t p_grid_width) {
	int32_t dx = p_to_x - p_from_x;
	if (p_grid_width > 1 && dx > 1) {
		dx = -1;
	} else if (p_grid_width > 1 && dx < -1) {
		dx = 1;
	}
	const int32_t dy = p_to_y - p_from_y;
	for (uint8_t direction = 0; direction < 8; ++direction) {
		if (FLOW_DX[direction] == dx && FLOW_DY[direction] == dy) {
			return direction;
		}
	}
	return FLOW_DIR_NONE;
}

float hash_to_unit_float(uint64_t p_hash) {
	return static_cast<float>(p_hash & 0x00ffffffULL) / static_cast<float>(0x00ffffffULL);
}

float smoothstep_unit(float p_value) {
	const float t = saturate(p_value);
	return t * t * (3.0f - 2.0f * t);
}

float lerp_float(float p_a, float p_b, float p_t) {
	return p_a + (p_b - p_a) * p_t;
}

float hash_grid_unit(uint64_t p_seed, int64_t p_x, int64_t p_y) {
	const uint64_t mixed = splitmix64(
		p_seed ^
		static_cast<uint64_t>(p_x) * 0x9e3779b185ebca87ULL ^
		static_cast<uint64_t>(p_y) * 0xc2b2ae3d27d4eb4fULL
	);
	return hash_to_unit_float(mixed);
}

float value_noise_2d(uint64_t p_seed, float p_x, float p_y) {
	const int64_t x0 = static_cast<int64_t>(std::floor(p_x));
	const int64_t y0 = static_cast<int64_t>(std::floor(p_y));
	const float tx = smoothstep_unit(p_x - static_cast<float>(x0));
	const float ty = smoothstep_unit(p_y - static_cast<float>(y0));
	const float v00 = hash_grid_unit(p_seed, x0, y0);
	const float v10 = hash_grid_unit(p_seed, x0 + 1, y0);
	const float v01 = hash_grid_unit(p_seed, x0, y0 + 1);
	const float v11 = hash_grid_unit(p_seed, x0 + 1, y0 + 1);
	const float vx0 = lerp_float(v00, v10, tx);
	const float vx1 = lerp_float(v01, v11, tx);
	return lerp_float(vx0, vx1, ty);
}

float signed_value_noise_2d(uint64_t p_seed, float p_x, float p_y) {
	return value_noise_2d(p_seed, p_x, p_y) * 2.0f - 1.0f;
}

float adjust_wrapped_x_near(float p_x, float p_anchor_x, float p_world_width) {
	if (p_world_width <= 1.0f) {
		return p_x;
	}
	float adjusted = p_x;
	const float half_width = p_world_width * 0.5f;
	while (adjusted - p_anchor_x > half_width) {
		adjusted -= p_world_width;
	}
	while (adjusted - p_anchor_x < -half_width) {
		adjusted += p_world_width;
	}
	return adjusted;
}

float catmull_rom(float p0, float p1, float p2, float p3, float p_t) {
	const float t2 = p_t * p_t;
	const float t3 = t2 * p_t;
	return 0.5f * (
		2.0f * p1 +
		(-p0 + p2) * p_t +
		(2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t2 +
		(-p0 + 3.0f * p1 - 3.0f * p2 + p3) * t3
	);
}

int32_t hydrology_node_for_tile(const Snapshot &p_snapshot, float p_world_x, float p_world_y) {
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0) {
		return -1;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(
		static_cast<int64_t>(std::floor(p_world_x)) / std::max<int32_t>(1, p_snapshot.cell_size_tiles),
		p_snapshot.grid_width
	));
	const int32_t node_y = clamp_value(
		static_cast<int32_t>(std::floor(p_world_y / static_cast<float>(std::max<int32_t>(1, p_snapshot.cell_size_tiles)))),
		0,
		p_snapshot.grid_height - 1
	);
	return p_snapshot.index(node_x, node_y);
}

float node_mountain_clearance_scale(const Snapshot &p_snapshot, int32_t p_node_index) {
	if (p_node_index < 0 || p_node_index >= p_snapshot.grid_width * p_snapshot.grid_height ||
			p_snapshot.mountain_exclusion_mask.empty()) {
		return 1.0f;
	}
	if (p_snapshot.mountain_exclusion_mask[static_cast<size_t>(p_node_index)] != 0U) {
		return 0.0f;
	}
	const int32_t node_x = p_node_index % p_snapshot.grid_width;
	const int32_t node_y = p_node_index / p_snapshot.grid_width;
	int32_t nearest_exclusion_distance = 99;
	for (int32_t dy = -2; dy <= 2; ++dy) {
		const int32_t y = node_y + dy;
		if (y < 0 || y >= p_snapshot.grid_height) {
			continue;
		}
		for (int32_t dx = -2; dx <= 2; ++dx) {
			const int32_t x = static_cast<int32_t>(positive_mod(node_x + dx, p_snapshot.grid_width));
			const int32_t neighbor = p_snapshot.index(x, y);
			if (neighbor < 0 || neighbor >= static_cast<int32_t>(p_snapshot.mountain_exclusion_mask.size()) ||
					p_snapshot.mountain_exclusion_mask[static_cast<size_t>(neighbor)] == 0U) {
				continue;
			}
			nearest_exclusion_distance = std::min(nearest_exclusion_distance, std::abs(dx) + std::abs(dy));
		}
	}
	if (nearest_exclusion_distance == 99) {
		return 1.0f;
	}
	if (nearest_exclusion_distance <= 1) {
		return 0.18f;
	}
	return 0.45f;
}

float node_slope_flatness(const Snapshot &p_snapshot, int32_t p_from_node, int32_t p_to_node) {
	if (p_from_node < 0 || p_to_node < 0 ||
			p_from_node >= static_cast<int32_t>(p_snapshot.filled_elevation.size()) ||
			p_to_node >= static_cast<int32_t>(p_snapshot.filled_elevation.size())) {
		return 0.6f;
	}
	const float slope = std::abs(
		p_snapshot.filled_elevation[static_cast<size_t>(p_from_node)] -
		p_snapshot.filled_elevation[static_cast<size_t>(p_to_node)]
	);
	return 1.0f - saturate(slope * 30.0f);
}

float node_floodplain_factor(const Snapshot &p_snapshot, int32_t p_node_index) {
	if (p_node_index < 0 || p_node_index >= static_cast<int32_t>(p_snapshot.floodplain_potential.size())) {
		return 0.0f;
	}
	return saturate(p_snapshot.floodplain_potential[static_cast<size_t>(p_node_index)]);
}

bool node_is_ocean(const Snapshot &p_snapshot, int32_t p_node_index);
bool node_is_lake(const Snapshot &p_snapshot, int32_t p_node_index);

int32_t river_upstream_count_for_node(const Snapshot &p_snapshot, int32_t p_node_index) {
	if (p_node_index < 0 || p_node_index >= p_snapshot.grid_width * p_snapshot.grid_height ||
			p_snapshot.river_node_mask.empty() || p_snapshot.flow_dir.empty()) {
		return 0;
	}
	const int32_t node_x = p_node_index % p_snapshot.grid_width;
	const int32_t node_y = p_node_index / p_snapshot.grid_width;
	int32_t upstream_count = 0;
	for (int32_t direction = 0; direction < 8; ++direction) {
		const int32_t source_x = static_cast<int32_t>(positive_mod(node_x - FLOW_DX[direction], p_snapshot.grid_width));
		const int32_t source_y = node_y - FLOW_DY[direction];
		if (source_y < 0 || source_y >= p_snapshot.grid_height) {
			continue;
		}
		const int32_t source_node = p_snapshot.index(source_x, source_y);
		if (source_node < 0 ||
				source_node >= static_cast<int32_t>(p_snapshot.river_node_mask.size()) ||
				source_node >= static_cast<int32_t>(p_snapshot.flow_dir.size()) ||
				p_snapshot.river_node_mask[static_cast<size_t>(source_node)] == 0U) {
			continue;
		}
		if (p_snapshot.flow_dir[static_cast<size_t>(source_node)] == static_cast<uint8_t>(direction)) {
			upstream_count += 1;
		}
	}
	return upstream_count;
}

int32_t downstream_node_for_node(const Snapshot &p_snapshot, int32_t p_node_index) {
	if (p_node_index < 0 || p_node_index >= p_snapshot.grid_width * p_snapshot.grid_height ||
			p_node_index >= static_cast<int32_t>(p_snapshot.flow_dir.size())) {
		return -1;
	}
	const int32_t direction = static_cast<int32_t>(p_snapshot.flow_dir[static_cast<size_t>(p_node_index)]);
	if (direction < 0 || direction >= 8) {
		return -1;
	}
	const int32_t node_x = p_node_index % p_snapshot.grid_width;
	const int32_t node_y = p_node_index / p_snapshot.grid_width;
	const int32_t next_x = static_cast<int32_t>(positive_mod(node_x + FLOW_DX[direction], p_snapshot.grid_width));
	const int32_t next_y = node_y + FLOW_DY[direction];
	if (next_y < 0 || next_y >= p_snapshot.grid_height) {
		return -1;
	}
	return p_snapshot.index(next_x, next_y);
}

bool node_has_y_confluence_zone(const Snapshot &p_snapshot, int32_t p_node_index) {
	if (p_snapshot.world_version < WORLD_Y_CONFLUENCE_RIVER_VERSION ||
			p_node_index < 0 ||
			p_node_index >= p_snapshot.grid_width * p_snapshot.grid_height ||
			p_node_index >= static_cast<int32_t>(p_snapshot.river_node_mask.size()) ||
			p_snapshot.river_node_mask[static_cast<size_t>(p_node_index)] == 0U ||
			node_is_lake(p_snapshot, p_node_index) ||
			node_is_ocean(p_snapshot, p_node_index)) {
		return false;
	}
	const int32_t downstream_node = downstream_node_for_node(p_snapshot, p_node_index);
	return downstream_node >= 0 &&
			downstream_node < static_cast<int32_t>(p_snapshot.river_node_mask.size()) &&
			p_snapshot.river_node_mask[static_cast<size_t>(downstream_node)] != 0U &&
			river_upstream_count_for_node(p_snapshot, p_node_index) >= 2;
}

float smoothstep_range(float p_value, float p_start, float p_end) {
	if (p_end <= p_start) {
		return p_value >= p_end ? 1.0f : 0.0f;
	}
	const float t = saturate((p_value - p_start) / (p_end - p_start));
	return t * t * (3.0f - 2.0f * t);
}

void sync_refined_edge_distance_fields(RefinedRiverEdge &r_edge, float p_total_distance) {
	r_edge.total_distance = std::max(0.0f, p_total_distance);
	r_edge.distance_at_source = std::max(0.0f, r_edge.cumulative_start);
	r_edge.distance_to_terminal = std::max(0.0f, r_edge.total_distance - r_edge.cumulative_end);
}

float y_confluence_weight_for_sample(const Snapshot &p_snapshot, const RiverCenterSample &p_sample) {
	if (p_snapshot.world_version < WORLD_Y_CONFLUENCE_RIVER_VERSION) {
		return river_upstream_count_for_node(p_snapshot, p_sample.node_index) >= 2 ? 1.0f : 0.0f;
	}
	float weight = 0.0f;
	if (node_has_y_confluence_zone(p_snapshot, p_sample.node_index)) {
		weight = std::max(weight, 1.0f - smoothstep_range(p_sample.local_t, 0.0f, 0.78f));
	}
	if (node_has_y_confluence_zone(p_snapshot, p_sample.next_node_index)) {
		weight = std::max(weight, smoothstep_range(p_sample.local_t, 0.22f, 1.0f));
	}
	return saturate(weight);
}

int32_t count_y_confluence_zones(const Snapshot &p_snapshot) {
	if (p_snapshot.world_version < WORLD_Y_CONFLUENCE_RIVER_VERSION ||
			p_snapshot.river_node_mask.empty()) {
		return 0;
	}
	int32_t count = 0;
	const int32_t node_count = p_snapshot.grid_width * p_snapshot.grid_height;
	for (int32_t node_index = 0; node_index < node_count; ++node_index) {
		if (node_has_y_confluence_zone(p_snapshot, node_index)) {
			count += 1;
		}
	}
	return count;
}

bool node_is_ocean(const Snapshot &p_snapshot, int32_t p_node_index) {
	return p_node_index >= 0 &&
			p_node_index < static_cast<int32_t>(p_snapshot.ocean_sink_mask.size()) &&
			p_snapshot.ocean_sink_mask[static_cast<size_t>(p_node_index)] != 0U;
}

bool node_is_lake(const Snapshot &p_snapshot, int32_t p_node_index) {
	return p_node_index >= 0 &&
			p_node_index < static_cast<int32_t>(p_snapshot.lake_id.size()) &&
			p_snapshot.lake_id[static_cast<size_t>(p_node_index)] > 0;
}

bool centerline_point_has_mountain_clearance(const Snapshot &p_snapshot, float p_x, float p_y) {
	const int32_t node_index = hydrology_node_for_tile(p_snapshot, p_x, p_y);
	if (node_index < 0 || node_index >= p_snapshot.grid_width * p_snapshot.grid_height) {
		return false;
	}
	return node_index >= static_cast<int32_t>(p_snapshot.mountain_exclusion_mask.size()) ||
			p_snapshot.mountain_exclusion_mask[static_cast<size_t>(node_index)] == 0U;
}

bool centerline_segment_has_mountain_clearance(
	const Snapshot &p_snapshot,
	float p_ax,
	float p_ay,
	float p_bx,
	float p_by,
	int32_t p_steps
) {
	const int32_t steps = std::max(1, p_steps);
	for (int32_t step = 0; step <= steps; ++step) {
		const float t = static_cast<float>(step) / static_cast<float>(steps);
		const float x = lerp_float(p_ax, p_bx, t);
		const float y = lerp_float(p_ay, p_by, t);
		if (!centerline_point_has_mountain_clearance(p_snapshot, x, y)) {
			return false;
		}
	}
	return true;
}

float refined_radius_scale_for_node(
	const Snapshot &p_snapshot,
	int32_t p_from_node,
	int32_t p_to_node,
	uint8_t p_stream_order,
	bool p_delta
) {
	const float flatness = node_slope_flatness(p_snapshot, p_from_node, p_to_node);
	const float floodplain = node_floodplain_factor(p_snapshot, p_from_node);
	const float clearance = node_mountain_clearance_scale(p_snapshot, p_from_node);
	const float order_t = saturate(static_cast<float>(p_stream_order) / 6.0f);
	float radius = 0.82f + flatness * 0.22f + floodplain * 0.18f + order_t * 0.16f;
	radius *= 0.72f + clearance * 0.38f;
	if (p_snapshot.world_version >= WORLD_CURVATURE_RIVER_VERSION) {
		const int32_t upstream_count = river_upstream_count_for_node(p_snapshot, p_from_node);
		if (upstream_count >= 2) {
			radius += clamp_value(0.14f * static_cast<float>(upstream_count - 1), 0.14f, 0.42f);
		}
	}
	if (node_is_lake(p_snapshot, p_to_node) || node_is_ocean(p_snapshot, p_to_node)) {
		radius += 0.22f;
	}
	if (p_delta) {
		radius += clamp_value(p_snapshot.river_settings.delta_scale, 0.0f, 2.0f) * 0.55f;
	}
	return clamp_value(radius, 0.54f, 2.2f);
}

float refined_meander_amplitude_for_node(
	const Snapshot &p_snapshot,
	int32_t p_from_node,
	int32_t p_to_node,
	uint8_t p_stream_order
) {
	const float flatness = node_slope_flatness(p_snapshot, p_from_node, p_to_node);
	const float floodplain = node_floodplain_factor(p_snapshot, p_from_node);
	const float clearance = node_mountain_clearance_scale(p_snapshot, p_from_node);
	const float order_t = saturate(static_cast<float>(p_stream_order) / 6.0f);
	float amplitude = static_cast<float>(p_snapshot.cell_size_tiles) *
			saturate(p_snapshot.river_settings.meander_strength) *
			(0.10f + flatness * 0.32f + floodplain * 0.18f) *
			(0.85f + order_t * 0.35f) *
			clearance;
	if (node_is_lake(p_snapshot, p_to_node) || node_is_ocean(p_snapshot, p_to_node)) {
		amplitude *= 0.45f;
	}
	return clamp_value(amplitude, 0.0f, static_cast<float>(p_snapshot.cell_size_tiles) * 0.55f);
}

float compute_refined_edge_curvature(const std::vector<RiverCenterSample> &p_samples, size_t p_edge_index) {
	if (p_samples.size() < 3 || p_edge_index + 1 >= p_samples.size()) {
		return 0.0f;
	}
	const size_t prev_index = p_edge_index > 0 ? p_edge_index - 1 : p_edge_index;
	const size_t from_index = p_edge_index;
	const size_t to_index = p_edge_index + 1;
	const size_t next_index = std::min(p_edge_index + 2, p_samples.size() - 1);
	const RiverCenterSample &prev = p_samples[prev_index];
	const RiverCenterSample &from = p_samples[from_index];
	const RiverCenterSample &to = p_samples[to_index];
	const RiverCenterSample &next = p_samples[next_index];
	const float ax = to.x - prev.x;
	const float ay = to.y - prev.y;
	const float bx = next.x - from.x;
	const float by = next.y - from.y;
	const float a_len = std::sqrt(ax * ax + ay * ay);
	const float b_len = std::sqrt(bx * bx + by * by);
	if (a_len <= 0.001f || b_len <= 0.001f) {
		return 0.0f;
	}
	const float anx = ax / a_len;
	const float any = ay / a_len;
	const float bnx = bx / b_len;
	const float bny = by / b_len;
	const float cross = anx * bny - any * bnx;
	const float dot = clamp_value(anx * bnx + any * bny, -1.0f, 1.0f);
	const float angle = std::atan2(cross, dot);
	return clamp_value(angle / (PI * 0.50f), -1.0f, 1.0f);
}

SegmentProjection project_to_overview_segment(
	float p_x,
	float p_y,
	const OverviewRiverEdge &p_edge,
	float p_world_width
) {
	const float px = adjust_wrapped_x_near(p_x, p_edge.ax, p_world_width);
	const float vx = p_edge.bx - p_edge.ax;
	const float vy = p_edge.by - p_edge.ay;
	const float wx = px - p_edge.ax;
	const float wy = p_y - p_edge.ay;
	const float length_sq = vx * vx + vy * vy;
	SegmentProjection projection;
	if (length_sq <= 0.0001f) {
		const float dx = px - p_edge.ax;
		const float dy = p_y - p_edge.ay;
		projection.distance = std::sqrt(dx * dx + dy * dy);
		return projection;
	}
	const float t = clamp_value((wx * vx + wy * vy) / length_sq, 0.0f, 1.0f);
	const float nearest_x = p_edge.ax + vx * t;
	const float nearest_y = p_edge.ay + vy * t;
	const float dx = px - nearest_x;
	const float dy = p_y - nearest_y;
	projection.distance = std::sqrt(dx * dx + dy * dy);
	projection.t = t;
	return projection;
}

float resolve_overview_radius_scale(const OverviewRiverEdge &p_edge, const SegmentProjection &p_projection) {
	if (!p_edge.organic) {
		return p_edge.radius_scale;
	}
	const float order_f = std::max(1.0f, static_cast<float>(p_edge.stream_order));
	if (p_edge.shape_quality_v2_fix && p_edge.cumulative_end > p_edge.cumulative_start + 0.001f) {
		const float river_distance = lerp_float(p_edge.cumulative_start, p_edge.cumulative_end, p_projection.t);
		float taper = 1.0f;
		if (p_edge.total_distance > 0.001f) {
			const float distance_t = clamp_value(river_distance / p_edge.total_distance, 0.0f, 1.0f);
			const float source_taper = smoothstep_range(distance_t, 0.04f, 0.18f);
			const float terminal_grow = lerp_float(1.0f, 1.45f, smoothstep_range(distance_t, 0.70f, 0.97f));
			taper = source_taper * terminal_grow;
		}
		const uint64_t river_seed = splitmix64(p_edge.variation_seed);
		const float phase_a = hash_grid_unit(river_seed, 0, 0) * PI * 2.0f;
		const float phase_b = hash_grid_unit(river_seed, 1, 0) * PI * 2.0f;
		const float wavelength_a = 34.0f + order_f * 8.0f;
		const float wavelength_b = wavelength_a * 2.45f;
		const float wave_a = std::sin(phase_a + river_distance / wavelength_a * PI * 2.0f);
		const float wave_b = std::sin(phase_b + river_distance / wavelength_b * PI * 2.0f);
		const float amplitude = clamp_value(0.045f + order_f * 0.006f, 0.045f, 0.08f);
		const float multiplier = 1.0f + wave_a * amplitude + wave_b * 0.025f;
		const float min_scale = std::max(0.72f, p_edge.radius_scale * 0.82f);
		const float max_scale = std::max(min_scale, p_edge.radius_scale * 1.20f);
		return clamp_value(p_edge.radius_scale * taper * multiplier, min_scale * taper, max_scale * std::max(1.0f, taper));
	}
	const float phase_a = hash_grid_unit(p_edge.variation_seed, 0, 0) * PI * 2.0f;
	const float phase_b = hash_grid_unit(p_edge.variation_seed, 1, 0) * PI * 2.0f;
	const float wave_a = std::sin(phase_a + p_projection.t * (2.2f + order_f * 0.22f) * PI);
	const float wave_b = std::sin(phase_b + p_projection.t * (5.0f + order_f * 0.13f) * PI);
	const float amplitude = clamp_value(0.16f + order_f * 0.018f, 0.16f, 0.34f);
	const float multiplier = 1.0f + wave_a * amplitude + wave_b * 0.08f;
	const float min_scale = std::max(0.58f, p_edge.radius_scale * 0.58f);
	const float max_scale = std::max(min_scale, p_edge.radius_scale * 1.70f);
	return clamp_value(p_edge.radius_scale * multiplier, min_scale, max_scale);
}

std::vector<OverviewRiverEdge> build_overview_river_edges(const Snapshot &p_snapshot, int32_t p_pixels_per_cell) {
	std::vector<OverviewRiverEdge> edges;
	if (!p_snapshot.valid || p_snapshot.river_segment_ranges.empty() ||
			p_snapshot.river_path_node_indices.empty() || p_pixels_per_cell <= 1) {
		return edges;
	}
	const bool enable_v1_r5 = p_snapshot.world_version >= WORLD_DELTA_VERSION;
	const bool enable_organic = p_snapshot.world_version >= WORLD_ORGANIC_WATER_VERSION;
	const float pixels_per_cell = static_cast<float>(std::max(1, p_pixels_per_cell));
	const float world_width_pixels = static_cast<float>(std::max(1, p_snapshot.grid_width * p_pixels_per_cell));
	const float braid_chance = saturate(p_snapshot.river_settings.braid_chance);
	const float delta_scale = clamp_value(p_snapshot.river_settings.delta_scale, 0.0f, 2.0f);
	auto node_center_pixel = [&](int32_t p_node) -> Vector2 {
		return Vector2(
			static_cast<float>(p_node % p_snapshot.grid_width) * pixels_per_cell + pixels_per_cell * 0.5f,
			static_cast<float>(p_node / p_snapshot.grid_width) * pixels_per_cell + pixels_per_cell * 0.5f
		);
	};
	auto push_edge = [&](std::vector<OverviewRiverEdge> &r_edges, const OverviewRiverEdge &p_edge) {
		OverviewRiverEdge adjusted = p_edge;
		adjusted.bx = adjust_wrapped_x_near(adjusted.bx, adjusted.ax, world_width_pixels);
		r_edges.push_back(adjusted);
	};
	auto push_meandered_edge = [&](std::vector<OverviewRiverEdge> &r_edges, const OverviewRiverEdge &p_edge) {
		if (!enable_organic || p_edge.delta || p_snapshot.river_settings.meander_strength <= 0.01f) {
			push_edge(r_edges, p_edge);
			return;
		}
		const float dx = p_edge.bx - p_edge.ax;
		const float dy = p_edge.by - p_edge.ay;
		const float length = std::sqrt(dx * dx + dy * dy);
		if (length <= 1.5f) {
			push_edge(r_edges, p_edge);
			return;
		}
		const float inv_length = 1.0f / length;
		const float nx = -dy * inv_length;
		const float ny = dx * inv_length;
		const float side = (p_edge.variation_seed & 1ULL) != 0ULL ? 1.0f : -1.0f;
		const float selector = hash_grid_unit(p_edge.variation_seed, 2, 0);
		const float order_f = std::max(1.0f, static_cast<float>(p_edge.stream_order));
		const float amplitude_limit = std::min(length * 0.32f, pixels_per_cell * (0.35f + order_f * 0.04f));
		const float amplitude = amplitude_limit * saturate(p_snapshot.river_settings.meander_strength) *
				(0.55f + selector * 0.45f) * side;
		const float mid_t = 0.42f + hash_grid_unit(p_edge.variation_seed, 3, 0) * 0.16f;
		const float mx = p_edge.ax + dx * mid_t + nx * amplitude;
		const float my = p_edge.ay + dy * mid_t + ny * amplitude;
		OverviewRiverEdge first = p_edge;
		first.bx = mx;
		first.by = my;
		OverviewRiverEdge second = p_edge;
		second.ax = mx;
		second.ay = my;
		push_edge(r_edges, first);
		push_edge(r_edges, second);
	};
	auto push_branch_edge = [&](std::vector<OverviewRiverEdge> &r_edges, const OverviewRiverEdge &p_template, float p_ax, float p_ay, float p_bx, float p_by) {
		OverviewRiverEdge branch = p_template;
		branch.ax = p_ax;
		branch.ay = p_ay;
		branch.bx = adjust_wrapped_x_near(p_bx, p_ax, world_width_pixels);
		branch.by = p_by;
		r_edges.push_back(branch);
	};

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
			const Vector2 from_center = node_center_pixel(from_node);
			const Vector2 to_center = node_center_pixel(to_node);
			OverviewRiverEdge edge;
			edge.ax = from_center.x;
			edge.ay = from_center.y;
			edge.bx = adjust_wrapped_x_near(to_center.x, edge.ax, world_width_pixels);
			edge.by = to_center.y;
			edge.stream_order = p_snapshot.river_stream_order.size() > static_cast<size_t>(from_node) ?
					p_snapshot.river_stream_order[static_cast<size_t>(from_node)] :
					1U;
			edge.variation_seed = splitmix64(
				static_cast<uint64_t>(p_snapshot.seed) ^
				(static_cast<uint64_t>(p_snapshot.world_version) << 32U) ^
				(static_cast<uint64_t>(segment_id) * 0x9e3779b185ebca87ULL) ^
				(static_cast<uint64_t>(from_node) << 16U) ^
				static_cast<uint64_t>(to_node)
			);
			edge.organic = enable_organic;
			const bool from_lake = p_snapshot.lake_id.size() > static_cast<size_t>(from_node) &&
					p_snapshot.lake_id[static_cast<size_t>(from_node)] > 0;
			const bool to_lake = p_snapshot.lake_id.size() > static_cast<size_t>(to_node) &&
					p_snapshot.lake_id[static_cast<size_t>(to_node)] > 0;
			const bool to_ocean = p_snapshot.ocean_sink_mask.size() > static_cast<size_t>(to_node) &&
					p_snapshot.ocean_sink_mask[static_cast<size_t>(to_node)] != 0U;
			if (enable_v1_r5 && to_ocean && delta_scale > 0.0f) {
				edge.delta = true;
				edge.radius_scale = 1.0f + delta_scale * 0.85f;
			}
			push_meandered_edge(edges, edge);

			if (!enable_v1_r5) {
				continue;
			}
			const float dx = edge.bx - edge.ax;
			const float dy = edge.by - edge.ay;
			const float length = std::sqrt(dx * dx + dy * dy);
			if (length <= 1.5f) {
				continue;
			}
			const float inv_length = 1.0f / length;
			const float nx = -dy * inv_length;
			const float ny = dx * inv_length;
			const uint64_t branch_hash = edge.variation_seed;
			const float branch_selector = hash_to_unit_float(branch_hash);
			const float side = (branch_hash & 0x01000000ULL) != 0ULL ? 1.0f : -1.0f;

			if (to_ocean && delta_scale > 0.0f) {
				const float fan_offset = pixels_per_cell * (0.45f + static_cast<float>(edge.stream_order) * 0.075f) *
						std::max(0.75f, p_snapshot.river_settings.width_scale) * delta_scale;
				for (int32_t branch_index = -1; branch_index <= 1; branch_index += 2) {
					OverviewRiverEdge delta_branch = edge;
					delta_branch.delta = true;
					delta_branch.braid_split = true;
					delta_branch.radius_scale = std::max(edge.radius_scale, 1.15f + delta_scale * 0.55f);
					const float branch_side = static_cast<float>(branch_index);
					push_branch_edge(
						edges,
						delta_branch,
						edge.ax + dx * 0.30f,
						edge.ay + dy * 0.30f,
						edge.bx + nx * fan_offset * branch_side,
						edge.by + ny * fan_offset * branch_side
					);
				}
				continue;
			}

			if (braid_chance <= 0.0f || branch_selector > braid_chance ||
					edge.stream_order < 3U || from_lake || to_lake || to_ocean) {
				continue;
			}
			OverviewRiverEdge split_branch = edge;
			split_branch.braid_split = true;
			split_branch.radius_scale = 0.72f;
			const float branch_offset = std::max(
				0.85f,
				pixels_per_cell * (0.45f + static_cast<float>(edge.stream_order) * 0.08f) *
						std::max(0.75f, p_snapshot.river_settings.width_scale)
			);
			const float sx = edge.ax + dx * 0.22f + nx * branch_offset * side;
			const float sy = edge.ay + dy * 0.22f + ny * branch_offset * side;
			const float ex = edge.ax + dx * 0.78f + nx * branch_offset * side;
			const float ey = edge.ay + dy * 0.78f + ny * branch_offset * side;
			push_branch_edge(edges, split_branch, edge.ax, edge.ay, sx, sy);
			push_branch_edge(edges, split_branch, sx, sy, ex, ey);
			push_branch_edge(edges, split_branch, ex, ey, edge.bx, edge.by);
		}
	}
	return edges;
}

std::vector<OverviewRiverEdge> build_overview_river_edges_from_refined(const Snapshot &p_snapshot, int32_t p_pixels_per_cell) {
	std::vector<OverviewRiverEdge> edges;
	if (p_snapshot.refined_river_edges.empty() || p_pixels_per_cell <= 1 || p_snapshot.cell_size_tiles <= 0) {
		return edges;
	}
	edges.reserve(p_snapshot.refined_river_edges.size());
	const float tile_to_pixel = static_cast<float>(p_pixels_per_cell) / static_cast<float>(p_snapshot.cell_size_tiles);
	const float world_width_pixels = static_cast<float>(std::max(1, p_snapshot.grid_width * p_pixels_per_cell));
	for (const RefinedRiverEdge &refined : p_snapshot.refined_river_edges) {
		OverviewRiverEdge edge;
		edge.ax = refined.ax * tile_to_pixel;
		edge.ay = refined.ay * tile_to_pixel;
		edge.bx = adjust_wrapped_x_near(refined.bx * tile_to_pixel, edge.ax, world_width_pixels);
		edge.by = refined.by * tile_to_pixel;
		edge.stream_order = refined.stream_order;
		edge.radius_scale = refined.radius_scale;
		edge.cumulative_start = refined.cumulative_start;
		edge.cumulative_end = refined.cumulative_end;
		edge.total_distance = refined.total_distance;
		edge.distance_at_source = refined.distance_at_source;
		edge.distance_to_terminal = refined.distance_to_terminal;
		edge.variation_seed = refined.variation_seed;
		edge.delta = refined.delta;
		edge.braid_split = refined.braid_split;
		edge.organic = refined.organic;
		edge.shape_quality_v2_fix = refined.shape_quality_v2_fix;
		edges.push_back(edge);
	}
	return edges;
}

float sample_overview_float_field_at_node(
	const Snapshot &p_snapshot,
	const std::vector<float> &p_values,
	int32_t p_node_x,
	int32_t p_node_y,
	float p_fallback
) {
	if (!p_snapshot.valid || p_node_y < 0 || p_node_y >= p_snapshot.grid_height ||
			p_values.empty()) {
		return p_fallback;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(p_node_x, p_snapshot.grid_width));
	const int32_t node_index = p_snapshot.index(node_x, p_node_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_values.size())) {
		return p_fallback;
	}
	return p_values[static_cast<size_t>(node_index)];
}

float sample_overview_float_field_bilinear(
	const Snapshot &p_snapshot,
	const std::vector<float> &p_values,
	float p_world_x,
	float p_world_y,
	float p_fallback
) {
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0 ||
			p_values.empty()) {
		return p_fallback;
	}
	const float cell_size = static_cast<float>(std::max(1, p_snapshot.cell_size_tiles));
	const float gx = p_world_x / cell_size - 0.5f;
	const float gy = p_world_y / cell_size - 0.5f;
	const int32_t x0_raw = static_cast<int32_t>(std::floor(gx));
	const int32_t y0_raw = static_cast<int32_t>(std::floor(gy));
	const float tx = smoothstep_unit(gx - static_cast<float>(x0_raw));
	const float ty = smoothstep_unit(gy - static_cast<float>(y0_raw));
	const int32_t y0 = clamp_value(y0_raw, 0, p_snapshot.grid_height - 1);
	const int32_t y1 = clamp_value(y0_raw + 1, 0, p_snapshot.grid_height - 1);
	const float v00 = sample_overview_float_field_at_node(p_snapshot, p_values, x0_raw, y0, p_fallback);
	const float v10 = sample_overview_float_field_at_node(p_snapshot, p_values, x0_raw + 1, y0, p_fallback);
	const float v01 = sample_overview_float_field_at_node(p_snapshot, p_values, x0_raw, y1, p_fallback);
	const float v11 = sample_overview_float_field_at_node(p_snapshot, p_values, x0_raw + 1, y1, p_fallback);
	const float vx0 = lerp_float(v00, v10, tx);
	const float vx1 = lerp_float(v01, v11, tx);
	return lerp_float(vx0, vx1, ty);
}

float sample_overview_organic_coast_distance_tiles(
	const Snapshot &p_snapshot,
	float p_world_x,
	float p_world_y
) {
	const float base_distance = sample_overview_float_field_bilinear(
		p_snapshot,
		p_snapshot.ocean_coast_distance_tiles,
		p_world_x,
		p_world_y,
		-1024.0f
	);
	const float cell_size = static_cast<float>(std::max(1, p_snapshot.cell_size_tiles));
	const bool headland_coast = p_snapshot.world_version >= WORLD_HEADLAND_COAST_VERSION;
	const float coast_band_width = headland_coast ? cell_size * 5.0f : cell_size * 2.35f;
	const float near_coast = 1.0f - saturate(std::abs(base_distance) / std::max(1.0f, coast_band_width));
	if (near_coast <= 0.0f) {
		return base_distance;
	}
	const float mouth_influence = saturate(sample_overview_float_field_bilinear(
		p_snapshot,
		p_snapshot.ocean_river_mouth_influence,
		p_world_x,
		p_world_y,
		0.0f
	));
	const uint64_t seed = mix_seed(
		p_snapshot.seed,
		WORLD_HYDROLOGY_SHAPE_FIX_VERSION,
		0x2f14f965916a6f19ULL
	);
	const float coarse_noise = signed_value_noise_2d(
		seed,
		p_world_x / std::max(8.0f, cell_size * 3.65f),
		p_world_y / std::max(8.0f, cell_size * 3.65f)
	);
	const float fine_noise = signed_value_noise_2d(
		seed ^ 0x9e3779b185ebca87ULL,
		p_world_x / std::max(4.0f, cell_size * 1.20f),
		p_world_y / std::max(4.0f, cell_size * 1.20f)
	);
	float coastline_offset = (coarse_noise * 0.72f + fine_noise * 0.28f) * cell_size * 0.46f * near_coast;
	if (headland_coast) {
		const float headland_noise = signed_value_noise_2d(
			seed ^ 0xa5b2c3d4e5f60718ULL,
			p_world_x / std::max(16.0f, cell_size * 8.0f),
			p_world_y / std::max(16.0f, cell_size * 8.0f)
		);
		const float headland_offset = headland_noise * cell_size * 1.50f * near_coast;
		coastline_offset = (
			headland_offset +
			(coarse_noise * 0.72f + fine_noise * 0.28f) * cell_size * 0.46f
		) * near_coast;
	}
	const float mouth_offset = mouth_influence * cell_size * 0.72f * near_coast;
	return base_distance + coastline_offset + mouth_offset;
}

OceanOverviewSample sample_ocean_overview_pixel(
	const Snapshot &p_snapshot,
	int32_t p_node_x,
	int32_t p_node_y,
	int32_t p_local_pixel_x,
	int32_t p_local_pixel_y,
	int32_t p_pixels_per_cell
) {
	OceanOverviewSample sample;
	const int32_t node_index = p_snapshot.index(p_node_x, p_node_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_snapshot.ocean_sink_mask.size())) {
		return sample;
	}
	if (p_snapshot.world_version < WORLD_HYDROLOGY_SHAPE_FIX_VERSION) {
		if (p_snapshot.ocean_sink_mask[static_cast<size_t>(node_index)] == 0U) {
			return sample;
		}
		const float shelf_ratio = p_snapshot.world_version >= WORLD_ORGANIC_COASTLINE_VERSION &&
						p_snapshot.ocean_shelf_depth_ratio.size() > static_cast<size_t>(node_index) ?
				saturate(p_snapshot.ocean_shelf_depth_ratio[static_cast<size_t>(node_index)]) :
				1.0f;
		sample.is_ocean = true;
		sample.is_shallow_shelf = shelf_ratio < 0.72f;
		return sample;
	}
	const float cell_size = static_cast<float>(std::max(1, p_snapshot.cell_size_tiles));
	const float pixel_scale = cell_size / static_cast<float>(std::max(1, p_pixels_per_cell));
	const float world_x = static_cast<float>(p_node_x * p_snapshot.cell_size_tiles) +
			(static_cast<float>(p_local_pixel_x) + 0.5f) * pixel_scale;
	const float world_y = static_cast<float>(p_node_y * p_snapshot.cell_size_tiles) +
			(static_cast<float>(p_local_pixel_y) + 0.5f) * pixel_scale;
	const float coast_distance = sample_overview_organic_coast_distance_tiles(p_snapshot, world_x, world_y);
	const float mouth_influence = saturate(sample_overview_float_field_bilinear(
		p_snapshot,
		p_snapshot.ocean_river_mouth_influence,
		world_x,
		world_y,
		0.0f
	));
	const float shore_width = clamp_value(
		static_cast<float>(clamp_value(p_snapshot.cell_size_tiles / 3, 3, 7)) + mouth_influence * cell_size * 0.22f,
		2.5f,
		cell_size * 0.72f
	);
	if (std::abs(coast_distance) <= shore_width) {
		sample.is_shore = true;
		return sample;
	}
	if (coast_distance <= shore_width) {
		return sample;
	}
	const float base_shelf_width = clamp_value(
		static_cast<float>(p_snapshot.ocean_band_tiles) * 0.22f,
		cell_size * 1.50f,
		cell_size * 2.75f
	);
	const float local_shelf_width = base_shelf_width * (1.0f + mouth_influence * 0.85f);
	const float shelf_ratio = saturate(
		(coast_distance - shore_width * 0.35f) / std::max(1.0f, local_shelf_width) -
		mouth_influence * 0.12f
	);
	sample.is_ocean = true;
	sample.is_shallow_shelf = shelf_ratio < 0.72f;
	return sample;
}

void add_refined_edge_to_index_bins(
	const Snapshot &p_snapshot,
	std::vector<std::vector<int32_t>> &r_bins,
	int32_t p_edge_index,
	float p_shift_x
) {
	if (p_snapshot.river_spatial_index_width <= 0 || p_snapshot.river_spatial_index_height <= 0 ||
			p_edge_index < 0 || p_edge_index >= static_cast<int32_t>(p_snapshot.refined_river_edges.size())) {
		return;
	}
	const RefinedRiverEdge &edge = p_snapshot.refined_river_edges[static_cast<size_t>(p_edge_index)];
	const float padding = REFINED_RIVER_INDEX_PADDING_TILES;
	const float min_x = std::min(edge.ax + p_shift_x, edge.bx + p_shift_x) - padding;
	const float max_x = std::max(edge.ax + p_shift_x, edge.bx + p_shift_x) + padding;
	const float min_y = std::min(edge.ay, edge.by) - padding;
	const float max_y = std::max(edge.ay, edge.by) + padding;
	if (max_x < 0.0f || min_x >= static_cast<float>(std::max<int64_t>(1, p_snapshot.width_tiles)) ||
			max_y < 0.0f || min_y >= static_cast<float>(std::max<int64_t>(1, p_snapshot.height_tiles))) {
		return;
	}
	const int32_t first_x = clamp_value(
		static_cast<int32_t>(std::floor(std::max(0.0f, min_x) / static_cast<float>(p_snapshot.river_spatial_index_cell_size_tiles))),
		0,
		p_snapshot.river_spatial_index_width - 1
	);
	const int32_t last_x = clamp_value(
		static_cast<int32_t>(std::floor(std::min(static_cast<float>(std::max<int64_t>(1, p_snapshot.width_tiles - 1)), max_x) /
				static_cast<float>(p_snapshot.river_spatial_index_cell_size_tiles))),
		0,
		p_snapshot.river_spatial_index_width - 1
	);
	const int32_t first_y = clamp_value(
		static_cast<int32_t>(std::floor(std::max(0.0f, min_y) / static_cast<float>(p_snapshot.river_spatial_index_cell_size_tiles))),
		0,
		p_snapshot.river_spatial_index_height - 1
	);
	const int32_t last_y = clamp_value(
		static_cast<int32_t>(std::floor(std::min(static_cast<float>(std::max<int64_t>(1, p_snapshot.height_tiles - 1)), max_y) /
				static_cast<float>(p_snapshot.river_spatial_index_cell_size_tiles))),
		0,
		p_snapshot.river_spatial_index_height - 1
	);
	for (int32_t y = first_y; y <= last_y; ++y) {
		for (int32_t x = first_x; x <= last_x; ++x) {
			r_bins[static_cast<size_t>(y * p_snapshot.river_spatial_index_width + x)].push_back(p_edge_index);
		}
	}
}

void build_refined_river_spatial_index(Snapshot &r_snapshot) {
	r_snapshot.river_spatial_index_cell_size_tiles = REFINED_RIVER_INDEX_CELL_SIZE_TILES;
	r_snapshot.river_spatial_index_width = std::max<int32_t>(
		1,
		static_cast<int32_t>((r_snapshot.width_tiles + r_snapshot.river_spatial_index_cell_size_tiles - 1) /
				r_snapshot.river_spatial_index_cell_size_tiles)
	);
	r_snapshot.river_spatial_index_height = std::max<int32_t>(
		1,
		static_cast<int32_t>((r_snapshot.height_tiles + r_snapshot.river_spatial_index_cell_size_tiles - 1) /
				r_snapshot.river_spatial_index_cell_size_tiles)
	);
	const int32_t bin_count = r_snapshot.river_spatial_index_width * r_snapshot.river_spatial_index_height;
	std::vector<std::vector<int32_t>> bins(static_cast<size_t>(bin_count));
	const float world_width = static_cast<float>(std::max<int64_t>(1, r_snapshot.width_tiles));
	for (int32_t edge_index = 0; edge_index < static_cast<int32_t>(r_snapshot.refined_river_edges.size()); ++edge_index) {
		add_refined_edge_to_index_bins(r_snapshot, bins, edge_index, 0.0f);
		add_refined_edge_to_index_bins(r_snapshot, bins, edge_index, -world_width);
		add_refined_edge_to_index_bins(r_snapshot, bins, edge_index, world_width);
	}
	r_snapshot.river_spatial_index_offsets.assign(static_cast<size_t>(bin_count + 1), 0);
	r_snapshot.river_spatial_index_edge_indices.clear();
	for (int32_t bin_index = 0; bin_index < bin_count; ++bin_index) {
		r_snapshot.river_spatial_index_offsets[static_cast<size_t>(bin_index)] =
				static_cast<int32_t>(r_snapshot.river_spatial_index_edge_indices.size());
		for (const int32_t edge_index : bins[static_cast<size_t>(bin_index)]) {
			r_snapshot.river_spatial_index_edge_indices.push_back(edge_index);
		}
	}
	r_snapshot.river_spatial_index_offsets[static_cast<size_t>(bin_count)] =
			static_cast<int32_t>(r_snapshot.river_spatial_index_edge_indices.size());
}

std::vector<RiverCenterSample> build_base_center_samples_for_path(
	const Snapshot &p_snapshot,
	int32_t p_segment_id,
	int32_t p_path_offset,
	int32_t p_path_length
) {
	std::vector<RiverCenterSample> controls;
	if (p_path_length < 2) {
		return controls;
	}
	controls.reserve(static_cast<size_t>(p_path_length));
	const float world_width = static_cast<float>(std::max<int64_t>(1, p_snapshot.width_tiles));
	float previous_x = 0.0f;
	for (int32_t offset = 0; offset < p_path_length; ++offset) {
		const int32_t node = p_snapshot.river_path_node_indices[static_cast<size_t>(p_path_offset + offset)];
		if (node < 0 || node >= p_snapshot.grid_width * p_snapshot.grid_height) {
			controls.clear();
			return controls;
		}
		const Vector2i center = p_snapshot.node_to_tile_center(node % p_snapshot.grid_width, node / p_snapshot.grid_width);
		RiverCenterSample sample;
		sample.x = static_cast<float>(center.x) + 0.5f;
		if (!controls.empty()) {
			sample.x = adjust_wrapped_x_near(sample.x, previous_x, world_width);
		}
		sample.y = static_cast<float>(center.y) + 0.5f;
		sample.node_index = node;
		sample.stream_order = p_snapshot.river_stream_order.size() > static_cast<size_t>(node) ?
				p_snapshot.river_stream_order[static_cast<size_t>(node)] :
				1U;
		sample.flow_dir = p_snapshot.flow_dir.size() > static_cast<size_t>(node) ?
				p_snapshot.flow_dir[static_cast<size_t>(node)] :
				FLOW_DIR_TERMINAL;
		if (!controls.empty()) {
			const RiverCenterSample &previous = controls.back();
			const float dx = sample.x - previous.x;
			const float dy = sample.y - previous.y;
			sample.cumulative = previous.cumulative + std::sqrt(dx * dx + dy * dy);
		}
		sample.source = offset == 0;
		controls.push_back(sample);
		previous_x = sample.x;
	}
	(void)p_segment_id;
	return controls;
}

RiverCenterSample interpolate_center_sample(
	const Snapshot &p_snapshot,
	const std::vector<RiverCenterSample> &p_controls,
	int32_t p_segment_index,
	float p_t
) {
	const int32_t count = static_cast<int32_t>(p_controls.size());
	const int32_t i0 = std::max(0, p_segment_index - 1);
	const int32_t i1 = p_segment_index;
	const int32_t i2 = std::min(count - 1, p_segment_index + 1);
	const int32_t i3 = std::min(count - 1, p_segment_index + 2);
	const RiverCenterSample &c0 = p_controls[static_cast<size_t>(i0)];
	const RiverCenterSample &c1 = p_controls[static_cast<size_t>(i1)];
	const RiverCenterSample &c2 = p_controls[static_cast<size_t>(i2)];
	const RiverCenterSample &c3 = p_controls[static_cast<size_t>(i3)];

	RiverCenterSample sample;
	sample.x = catmull_rom(c0.x, c1.x, c2.x, c3.x, p_t);
	sample.y = catmull_rom(c0.y, c1.y, c2.y, c3.y, p_t);
	sample.cumulative = lerp_float(c1.cumulative, c2.cumulative, p_t);
	sample.node_index = c1.node_index;
	sample.next_node_index = c2.node_index;
	sample.local_t = saturate(p_t);
	sample.stream_order = c1.stream_order;
	sample.flow_dir = c1.flow_dir;
	const bool to_lake = node_is_lake(p_snapshot, c2.node_index);
	const bool to_ocean = node_is_ocean(p_snapshot, c2.node_index);
	sample.delta = p_snapshot.world_version >= WORLD_DELTA_VERSION && to_ocean &&
			p_snapshot.river_settings.delta_scale > 0.0f;
	sample.radius_scale = refined_radius_scale_for_node(
		p_snapshot,
		c1.node_index,
		c2.node_index,
		sample.stream_order,
		sample.delta
	);
	if (to_lake) {
		sample.radius_scale = std::max(sample.radius_scale, 1.12f);
	}
	return sample;
}

RiverCenterSample interpolate_linear_center_sample(
	const Snapshot &p_snapshot,
	const std::vector<RiverCenterSample> &p_controls,
	int32_t p_segment_index,
	float p_t
) {
	const int32_t count = static_cast<int32_t>(p_controls.size());
	const int32_t i1 = clamp_value(p_segment_index, 0, count - 1);
	const int32_t i2 = clamp_value(p_segment_index + 1, 0, count - 1);
	const RiverCenterSample &c1 = p_controls[static_cast<size_t>(i1)];
	const RiverCenterSample &c2 = p_controls[static_cast<size_t>(i2)];

	RiverCenterSample sample;
	sample.x = lerp_float(c1.x, c2.x, p_t);
	sample.y = lerp_float(c1.y, c2.y, p_t);
	sample.cumulative = lerp_float(c1.cumulative, c2.cumulative, p_t);
	sample.node_index = c1.node_index;
	sample.next_node_index = c2.node_index;
	sample.local_t = saturate(p_t);
	sample.stream_order = c1.stream_order;
	sample.flow_dir = c1.flow_dir;
	const bool to_lake = node_is_lake(p_snapshot, c2.node_index);
	const bool to_ocean = node_is_ocean(p_snapshot, c2.node_index);
	sample.delta = p_snapshot.world_version >= WORLD_DELTA_VERSION && to_ocean &&
			p_snapshot.river_settings.delta_scale > 0.0f;
	sample.radius_scale = refined_radius_scale_for_node(
		p_snapshot,
		c1.node_index,
		c2.node_index,
		sample.stream_order,
		sample.delta
	);
	if (to_lake) {
		sample.radius_scale = std::max(sample.radius_scale, 1.12f);
	}
	return sample;
}

void apply_direction_memory_offsets(
	const Snapshot &p_snapshot,
	std::vector<RiverCenterSample> &r_samples,
	uint64_t p_segment_seed
) {
	if (r_samples.size() < 3 || p_snapshot.river_settings.meander_strength <= 0.01f) {
		return;
	}
	const float total_length = std::max(1.0f, r_samples.back().cumulative);
	const float phase_a = hash_to_unit_float(p_segment_seed) * PI * 2.0f;
	const float phase_b = hash_grid_unit(p_segment_seed, 4, 0) * PI * 2.0f;
	const float wavelength = static_cast<float>(p_snapshot.cell_size_tiles) *
			(5.0f + hash_grid_unit(p_segment_seed, 5, 0) * 4.0f);
	for (size_t index = 0; index < r_samples.size(); ++index) {
		RiverCenterSample &sample = r_samples[index];
		const RiverCenterSample &prev = r_samples[index == 0 ? 0 : index - 1];
		const RiverCenterSample &next = r_samples[std::min(index + 1, r_samples.size() - 1)];
		const float dx = next.x - prev.x;
		const float dy = next.y - prev.y;
		const float length = std::sqrt(dx * dx + dy * dy);
		if (length <= 0.001f) {
			continue;
		}
		const float nx = -dy / length;
		const float ny = dx / length;
		const float edge_taper = std::min(
			saturate(sample.cumulative / std::max(1.0f, static_cast<float>(p_snapshot.cell_size_tiles) * 1.5f)),
			saturate((total_length - sample.cumulative) / std::max(1.0f, static_cast<float>(p_snapshot.cell_size_tiles) * 1.5f))
		);
		const float wave_a = std::sin(phase_a + sample.cumulative / wavelength * PI * 2.0f);
		const float wave_b = std::sin(phase_b + sample.cumulative / (wavelength * 2.35f) * PI * 2.0f);
		const int32_t next_node = index + 1 < r_samples.size() ? r_samples[index + 1].node_index : sample.node_index;
		const float amplitude = refined_meander_amplitude_for_node(
			p_snapshot,
			sample.node_index,
			next_node,
			sample.stream_order
		);
		const float offset = amplitude * (wave_a * 0.78f + wave_b * 0.22f) * edge_taper;
		if (std::abs(offset) <= 0.001f) {
			continue;
		}
		const float candidate_x = sample.x + nx * offset;
		const float candidate_y = sample.y + ny * offset;
		if (!centerline_point_has_mountain_clearance(p_snapshot, candidate_x, candidate_y) ||
				!centerline_segment_has_mountain_clearance(p_snapshot, prev.x, prev.y, candidate_x, candidate_y, 3) ||
				!centerline_segment_has_mountain_clearance(p_snapshot, candidate_x, candidate_y, next.x, next.y, 3)) {
			continue;
		}
		sample.x = candidate_x;
		sample.y = candidate_y;
	}
}

void apply_y_confluence_geometry(
	const Snapshot &p_snapshot,
	std::vector<RiverCenterSample> &r_samples,
	uint64_t p_segment_seed
) {
	if (p_snapshot.world_version < WORLD_Y_CONFLUENCE_RIVER_VERSION || r_samples.size() < 3) {
		return;
	}
	const float cell_size = static_cast<float>(std::max(1, p_snapshot.cell_size_tiles));
	const float world_width = static_cast<float>(std::max<int64_t>(1, p_snapshot.width_tiles));
	for (size_t index = 0; index < r_samples.size(); ++index) {
		RiverCenterSample &sample = r_samples[index];
		const float weight = y_confluence_weight_for_sample(p_snapshot, sample);
		if (weight < 0.05f) {
			continue;
		}
		const bool from_join = node_has_y_confluence_zone(p_snapshot, sample.node_index);
		const bool to_join = node_has_y_confluence_zone(p_snapshot, sample.next_node_index);
		const int32_t join_node = from_join ? sample.node_index : (to_join ? sample.next_node_index : -1);
		const int32_t downstream_node = downstream_node_for_node(p_snapshot, join_node);
		if (join_node < 0 || downstream_node < 0) {
			continue;
		}
		const Vector2i join_center = p_snapshot.node_to_tile_center(join_node % p_snapshot.grid_width, join_node / p_snapshot.grid_width);
		const Vector2i down_center = p_snapshot.node_to_tile_center(downstream_node % p_snapshot.grid_width, downstream_node / p_snapshot.grid_width);
		const float join_x = adjust_wrapped_x_near(static_cast<float>(join_center.x) + 0.5f, sample.x, world_width);
		const float join_y = static_cast<float>(join_center.y) + 0.5f;
		const float down_x = adjust_wrapped_x_near(static_cast<float>(down_center.x) + 0.5f, join_x, world_width);
		const float down_y = static_cast<float>(down_center.y) + 0.5f;
		const float dx = down_x - join_x;
		const float dy = down_y - join_y;
		const float length = std::sqrt(dx * dx + dy * dy);
		if (length <= 0.001f) {
			continue;
		}
		const float tx = dx / length;
		const float ty = dy / length;
		const float nx = -ty;
		const float ny = tx;
		const uint64_t branch_hash = splitmix64(
			p_segment_seed ^
			(static_cast<uint64_t>(std::max(0, sample.node_index)) << 21U) ^
			static_cast<uint64_t>(std::max(0, sample.next_node_index))
		);
		const float branch_side = (branch_hash & 1ULL) != 0ULL ? 1.0f : -1.0f;
		float target_x = sample.x;
		float target_y = sample.y;
		if (to_join) {
			const float approach = 1.0f - saturate(sample.local_t);
			const float branch_separation = cell_size * 0.18f * approach;
			target_x = join_x - tx * cell_size * 0.72f * approach + nx * branch_separation * branch_side;
			target_y = join_y - ty * cell_size * 0.72f * approach + ny * branch_separation * branch_side;
		} else if (from_join) {
			const float downstream_t = saturate(sample.local_t);
			target_x = join_x + tx * cell_size * 0.88f * downstream_t;
			target_y = join_y + ty * cell_size * 0.88f * downstream_t;
		}
		const float pull = clamp_value(0.18f + weight * 0.34f, 0.0f, 0.52f);
		const float candidate_x = lerp_float(sample.x, target_x, pull);
		const float candidate_y = lerp_float(sample.y, target_y, pull);
		const RiverCenterSample &prev = r_samples[index == 0 ? 0 : index - 1];
		const RiverCenterSample &next = r_samples[std::min(index + 1, r_samples.size() - 1)];
		if (!centerline_point_has_mountain_clearance(p_snapshot, candidate_x, candidate_y) ||
				!centerline_segment_has_mountain_clearance(p_snapshot, prev.x, prev.y, candidate_x, candidate_y, 3) ||
				!centerline_segment_has_mountain_clearance(p_snapshot, candidate_x, candidate_y, next.x, next.y, 3)) {
			continue;
		}
		sample.x = candidate_x;
		sample.y = candidate_y;
		sample.confluence_weight = std::max(sample.confluence_weight, weight);
		sample.confluence = true;
	}
}

void push_refined_branch_edge(
	Snapshot &r_snapshot,
	const RefinedRiverEdge &p_template,
	float p_ax,
	float p_ay,
	float p_bx,
	float p_by
) {
	RefinedRiverEdge branch = p_template;
	branch.ax = p_ax;
	branch.ay = p_ay;
	branch.bx = adjust_wrapped_x_near(p_bx, p_ax, static_cast<float>(std::max<int64_t>(1, r_snapshot.width_tiles)));
	branch.by = p_by;
	if (p_template.shape_quality_v2_fix && p_template.cumulative_end > p_template.cumulative_start + 0.001f) {
		const float tx = p_template.bx - p_template.ax;
		const float ty = p_template.by - p_template.ay;
		const float length_sq = tx * tx + ty * ty;
		if (length_sq > 0.0001f) {
			auto projected_cumulative = [&](float p_x, float p_y) -> float {
				const float px = adjust_wrapped_x_near(p_x, p_template.ax, static_cast<float>(std::max<int64_t>(1, r_snapshot.width_tiles)));
				const float t = clamp_value(
					((px - p_template.ax) * tx + (p_y - p_template.ay) * ty) / length_sq,
					0.0f,
					1.0f
				);
				return lerp_float(p_template.cumulative_start, p_template.cumulative_end, t);
			};
			branch.cumulative_start = projected_cumulative(branch.ax, branch.ay);
			branch.cumulative_end = std::max(
				branch.cumulative_start + 0.001f,
				projected_cumulative(branch.bx, branch.by)
			);
		}
	}
	if (branch.total_distance > 0.001f) {
		sync_refined_edge_distance_fields(branch, branch.total_distance);
	}
	r_snapshot.refined_river_edges.push_back(branch);
}

bool refined_branch_point_is_clear(const Snapshot &p_snapshot, float p_x, float p_y, bool p_allow_ocean = false) {
	const int32_t node_index = hydrology_node_for_tile(p_snapshot, p_x, p_y);
	if (node_index < 0 || node_index >= p_snapshot.grid_width * p_snapshot.grid_height) {
		return false;
	}
	if (node_index < static_cast<int32_t>(p_snapshot.mountain_exclusion_mask.size()) &&
			p_snapshot.mountain_exclusion_mask[static_cast<size_t>(node_index)] != 0U) {
		return false;
	}
	if (node_is_lake(p_snapshot, node_index) || node_is_ocean(p_snapshot, node_index)) {
		return p_allow_ocean && node_is_ocean(p_snapshot, node_index);
	}
	return true;
}

bool refined_branch_polyline_is_clear(
	const Snapshot &p_snapshot,
	const std::vector<Vector2> &p_points,
	bool p_allow_ocean_terminal = false
) {
	if (p_points.size() < 2) {
		return false;
	}
	for (size_t index = 0; index < p_points.size(); ++index) {
		const bool allow_ocean_point = p_allow_ocean_terminal && index + 1 == p_points.size();
		if (!refined_branch_point_is_clear(p_snapshot, p_points[index].x, p_points[index].y, allow_ocean_point)) {
			return false;
		}
		if (index == 0) {
			continue;
		}
		const Vector2 &from = p_points[index - 1];
		const Vector2 &to = p_points[index];
		if (!refined_branch_point_is_clear(
					p_snapshot,
					(from.x + to.x) * 0.5f,
					(from.y + to.y) * 0.5f,
					p_allow_ocean_terminal && index + 1 == p_points.size()
				)) {
			return false;
		}
	}
	return true;
}

int32_t delta_fan_count_for_scale(float p_delta_scale) {
	if (p_delta_scale <= 0.0f) {
		return 0;
	}
	return clamp_value(static_cast<int32_t>(std::lround(2.0f + p_delta_scale * 3.0f)), 2, 6);
}

bool delta_fan_terminal_is_valid(const Snapshot &p_snapshot, const Vector2 &p_point) {
	const int32_t node_index = hydrology_node_for_tile(p_snapshot, p_point.x, p_point.y);
	if (node_index < 0 || node_index >= p_snapshot.grid_width * p_snapshot.grid_height) {
		return false;
	}
	if (node_index < static_cast<int32_t>(p_snapshot.mountain_exclusion_mask.size()) &&
			p_snapshot.mountain_exclusion_mask[static_cast<size_t>(node_index)] != 0U) {
		return false;
	}
	return node_is_ocean(p_snapshot, node_index);
}

int32_t append_refined_delta_fan_edges_for_ocean_step(
	Snapshot &r_snapshot,
	const RefinedRiverEdge &p_template,
	const RiverCenterSample &p_from,
	const RiverCenterSample &p_to,
	float p_dx,
	float p_dy,
	float p_length,
	float p_nx,
	float p_ny
) {
	const float delta_scale = clamp_value(r_snapshot.river_settings.delta_scale, 0.0f, 2.0f);
	const int32_t fan_count = delta_fan_count_for_scale(delta_scale);
	if (fan_count <= 0 || p_template.stream_order < 3U || p_length <= 8.0f) {
		return 0;
	}

	const float order_f = std::max(1.0f, static_cast<float>(p_template.stream_order));
	const float width_scale = std::max(0.75f, r_snapshot.river_settings.width_scale);
	const uint64_t fan_seed = splitmix64(p_template.variation_seed ^ 0xd1e7a5f0c3b2a491ULL);
	const size_t before_count = r_snapshot.refined_river_edges.size();

	for (int32_t branch_index = 0; branch_index < fan_count; ++branch_index) {
		const float spread = fan_count == 1 ?
				0.0f :
				-1.0f + 2.0f * static_cast<float>(branch_index) / static_cast<float>(fan_count - 1);
		const float abs_spread = std::abs(spread);
		const float side = spread < 0.0f ? -1.0f : 1.0f;
		const float jitter = (hash_grid_unit(fan_seed, branch_index, 0) - 0.5f) * 0.04f;
		const float start_t = clamp_value(0.10f + abs_spread * 0.10f + jitter, 0.08f, 0.28f);
		const float angle_degrees = abs_spread <= 0.001f ? 0.0f : 15.0f + abs_spread * 20.0f;
		const float angle_radians = angle_degrees * PI / 180.0f;
		const float run_length = p_length * (1.0f - start_t);
		const float angle_offset = std::tan(angle_radians) * run_length;
		const float minimum_offset = (5.0f + order_f * 1.5f) * width_scale * (0.75f + delta_scale * 0.75f);
		const float fan_offset = std::max(angle_offset, minimum_offset * abs_spread);

		const Vector2 start(
			p_from.x + p_dx * start_t,
			p_from.y + p_dy * start_t
		);
		const Vector2 end(
			p_to.x + p_nx * fan_offset * side,
			p_to.y + p_ny * fan_offset * side
		);
		const Vector2 mid(
			start.x + (end.x - start.x) * 0.38f,
			start.y + (end.y - start.y) * 0.38f
		);
		std::vector<Vector2> branch_points;
		branch_points.reserve(3);
		branch_points.push_back(start);
		branch_points.push_back(mid);
		branch_points.push_back(end);

		if (!delta_fan_terminal_is_valid(r_snapshot, end) ||
				!refined_branch_polyline_is_clear(r_snapshot, branch_points, true)) {
			continue;
		}

		for (size_t point_index = 0; point_index + 1 < branch_points.size(); ++point_index) {
			const float branch_t = (static_cast<float>(point_index) + 0.5f) /
					static_cast<float>(branch_points.size() - 1);
			RefinedRiverEdge delta_branch = p_template;
			delta_branch.delta = true;
			delta_branch.braid_split = true;
			delta_branch.source = false;
			delta_branch.confluence = false;
			delta_branch.confluence_weight = 0.0f;
			delta_branch.radius_scale = lerp_float(0.85f, 0.40f, saturate(branch_t));
			push_refined_branch_edge(
				r_snapshot,
				delta_branch,
				branch_points[point_index].x,
				branch_points[point_index].y,
				branch_points[point_index + 1].x,
				branch_points[point_index + 1].y
			);
		}
	}

	return static_cast<int32_t>(r_snapshot.refined_river_edges.size() - before_count);
}

float braid_loop_eligibility_score(
	const Snapshot &p_snapshot,
	int32_t p_from_node,
	int32_t p_to_node
) {
	const float flatness = node_slope_flatness(p_snapshot, p_from_node, p_to_node);
	const float floodplain = std::max(
		node_floodplain_factor(p_snapshot, p_from_node),
		node_floodplain_factor(p_snapshot, p_to_node)
	);
	const float clearance = std::min(
		node_mountain_clearance_scale(p_snapshot, p_from_node),
		node_mountain_clearance_scale(p_snapshot, p_to_node)
	);
	return saturate(flatness * 0.52f + floodplain * 0.34f + clearance * 0.14f);
}

void append_refined_braid_loop_edges_for_coarse_step(
	Snapshot &r_snapshot,
	const RefinedRiverEdge &p_template,
	const RiverCenterSample &p_from,
	const RiverCenterSample &p_to,
	float p_dx,
	float p_dy,
	float p_length,
	float p_nx,
	float p_ny,
	float p_side
) {
	if (r_snapshot.world_version < WORLD_BRAID_LOOP_RIVER_VERSION) {
		return;
	}
	const bool shape_quality_fix = r_snapshot.world_version >= WORLD_HYDROLOGY_SHAPE_FIX_VERSION;
	const float eligibility = braid_loop_eligibility_score(r_snapshot, p_from.node_index, p_to.node_index);
	if (eligibility < (shape_quality_fix ? 0.55f : 0.34f)) {
		return;
	}
	const float cell_size = static_cast<float>(std::max(1, r_snapshot.cell_size_tiles));
	if (shape_quality_fix) {
		const int32_t coarse_bucket = static_cast<int32_t>(std::floor(p_from.cumulative / std::max(1.0f, cell_size)));
		const int32_t cooldown_phase = clamp_value(
			static_cast<int32_t>(std::floor(hash_grid_unit(p_template.variation_seed, 7, 0) * 3.0f)),
			0,
			2
		);
		if ((coarse_bucket + cooldown_phase) % 3 != 0) {
			return;
		}
	}
	const float order_f = std::max(1.0f, static_cast<float>(p_template.stream_order));
	const float width_scale = std::max(0.75f, r_snapshot.river_settings.width_scale);
	const float branch_offset = std::max(
		4.25f,
		(2.55f + order_f * 0.72f) * width_scale * (0.72f + eligibility * 0.48f)
	);
	const uint64_t loop_hash = splitmix64(p_template.variation_seed ^ 0x6c8e9cf570932bd5ULL);
	const float t_start = 0.16f + hash_grid_unit(loop_hash, 0, 0) * 0.08f;
	const float t_end = 0.80f + hash_grid_unit(loop_hash, 1, 0) * 0.08f;
	const float t_mid = 0.47f + (hash_grid_unit(loop_hash, 2, 0) - 0.5f) * 0.12f;
	const float apex_offset = branch_offset * (1.42f + hash_grid_unit(loop_hash, 3, 0) * 0.34f);
	const float shoulder_a = branch_offset * (0.62f + hash_grid_unit(loop_hash, 4, 0) * 0.22f);
	const float shoulder_b = branch_offset * (0.78f + hash_grid_unit(loop_hash, 5, 0) * 0.22f);
	if (shape_quality_fix) {
		const float island_length = (t_end - t_start) * p_length;
		if (apex_offset < cell_size * 0.50f || branch_offset < cell_size * 0.34f ||
				island_length < cell_size * 1.15f) {
			return;
		}
	}
	const float tangent_jitter = (hash_grid_unit(loop_hash, 6, 0) - 0.5f) *
			std::min(p_length * 0.08f, static_cast<float>(r_snapshot.cell_size_tiles) * 0.34f);
	const float tx = p_dx / p_length;
	const float ty = p_dy / p_length;
	auto point_on_main = [&](float p_t) {
		return Vector2(
			p_from.x + p_dx * p_t,
			p_from.y + p_dy * p_t
		);
	};
	auto offset_point = [&](float p_t, float p_offset, float p_tangent_offset) {
		return Vector2(
			p_from.x + p_dx * p_t + p_nx * p_offset * p_side + tx * p_tangent_offset,
			p_from.y + p_dy * p_t + p_ny * p_offset * p_side + ty * p_tangent_offset
		);
	};
	std::vector<Vector2> loop_points;
	loop_points.reserve(5);
	loop_points.push_back(point_on_main(t_start));
	loop_points.push_back(offset_point(0.31f, shoulder_a, -tangent_jitter * 0.35f));
	loop_points.push_back(offset_point(t_mid, apex_offset, tangent_jitter));
	loop_points.push_back(offset_point(0.70f, shoulder_b, tangent_jitter * 0.28f));
	loop_points.push_back(point_on_main(t_end));
	if (!refined_branch_polyline_is_clear(r_snapshot, loop_points)) {
		return;
	}
	std::vector<Vector2> branch_points = loop_points;
	if (shape_quality_fix) {
		branch_points.clear();
		branch_points.reserve(18);
		for (size_t index = 0; index + 1 < loop_points.size(); ++index) {
			const Vector2 &p0 = loop_points[index == 0 ? index : index - 1];
			const Vector2 &p1 = loop_points[index];
			const Vector2 &p2 = loop_points[index + 1];
			const Vector2 &p3 = loop_points[std::min(index + 2, loop_points.size() - 1)];
			const int32_t steps = (index == 0 || index + 2 == loop_points.size()) ? 3 : 4;
			for (int32_t step = 0; step < steps; ++step) {
				if (!branch_points.empty() && step == 0) {
					continue;
				}
				const float t = static_cast<float>(step) / static_cast<float>(steps);
				branch_points.push_back(Vector2(
					catmull_rom(p0.x, p1.x, p2.x, p3.x, t),
					catmull_rom(p0.y, p1.y, p2.y, p3.y, t)
				));
			}
		}
		branch_points.push_back(loop_points.back());
		if (!refined_branch_polyline_is_clear(r_snapshot, branch_points)) {
			return;
		}
	}

	RefinedRiverEdge loop_branch = p_template;
	loop_branch.braid_split = true;
	loop_branch.braid_loop = true;
	loop_branch.braid_loop_weight = eligibility;
	loop_branch.source = false;
	loop_branch.radius_scale = clamp_value(0.52f + eligibility * 0.22f, 0.50f, 0.74f);
	loop_branch.confluence = false;
	loop_branch.confluence_weight = 0.0f;
	const size_t before_count = r_snapshot.refined_river_edges.size();
	for (size_t index = 0; index + 1 < branch_points.size(); ++index) {
		push_refined_branch_edge(
			r_snapshot,
			loop_branch,
			branch_points[index].x,
			branch_points[index].y,
			branch_points[index + 1].x,
			branch_points[index + 1].y
		);
	}
	const int32_t emitted_count = static_cast<int32_t>(r_snapshot.refined_river_edges.size() - before_count);
	if (emitted_count > 0) {
		r_snapshot.refined_river_braid_loop_candidate_count += 1;
		r_snapshot.refined_river_braid_loop_edge_count += emitted_count;
	}
}

void append_refined_branch_edges_for_coarse_step(
	Snapshot &r_snapshot,
	const RefinedRiverEdge &p_template,
	const RiverCenterSample &p_from,
	const RiverCenterSample &p_to,
	bool p_from_lake,
	bool p_to_lake,
	bool p_to_ocean
) {
	if (r_snapshot.world_version < WORLD_DELTA_VERSION) {
		return;
	}
	const float dx = p_to.x - p_from.x;
	const float dy = p_to.y - p_from.y;
	const float length = std::sqrt(dx * dx + dy * dy);
	if (length <= 8.0f) {
		return;
	}
	const float inv_length = 1.0f / length;
	const float nx = -dy * inv_length;
	const float ny = dx * inv_length;
	const uint64_t branch_hash = p_template.variation_seed;
	const float branch_selector = hash_to_unit_float(branch_hash);
	const float side = (branch_hash & 0x01000000ULL) != 0ULL ? 1.0f : -1.0f;

	if (p_to_ocean && r_snapshot.river_settings.delta_scale > 0.0f) {
		if (uses_hydrology_visual_v3(r_snapshot.world_version)) {
			if (p_template.stream_order >= 3U) {
				append_refined_delta_fan_edges_for_ocean_step(
					r_snapshot,
					p_template,
					p_from,
					p_to,
					dx,
					dy,
					length,
					nx,
					ny
				);
			}
			return;
		}
		const float fan_offset = (4.0f + static_cast<float>(p_template.stream_order) * 0.65f) *
				std::max(0.75f, r_snapshot.river_settings.width_scale) *
				clamp_value(r_snapshot.river_settings.delta_scale, 0.0f, 2.0f);
		for (int32_t branch_index = -1; branch_index <= 1; branch_index += 2) {
			RefinedRiverEdge delta_branch = p_template;
			delta_branch.delta = true;
			delta_branch.braid_split = true;
			delta_branch.source = false;
			delta_branch.radius_scale = std::max(p_template.radius_scale, 1.15f + r_snapshot.river_settings.delta_scale * 0.55f);
			const float branch_side = static_cast<float>(branch_index);
			push_refined_branch_edge(
				r_snapshot,
				delta_branch,
				p_from.x + dx * 0.30f,
				p_from.y + dy * 0.30f,
				p_to.x + nx * fan_offset * branch_side,
				p_to.y + ny * fan_offset * branch_side
			);
		}
		return;
	}

	const float braid_chance = saturate(r_snapshot.river_settings.braid_chance);
	if (braid_chance <= 0.0f || branch_selector > braid_chance ||
			p_template.stream_order < 3U || p_from_lake || p_to_lake || p_to_ocean) {
		return;
	}
	if (r_snapshot.world_version >= WORLD_BRAID_LOOP_RIVER_VERSION) {
		append_refined_braid_loop_edges_for_coarse_step(
			r_snapshot,
			p_template,
			p_from,
			p_to,
			dx,
			dy,
			length,
			nx,
			ny,
			side
		);
		return;
	}
	RefinedRiverEdge split_branch = p_template;
	split_branch.braid_split = true;
	split_branch.source = false;
	split_branch.radius_scale = 0.72f;
	const float branch_offset = std::max(2.5f, (1.75f + static_cast<float>(p_template.stream_order) * 0.45f) *
			std::max(0.75f, r_snapshot.river_settings.width_scale));
	const float sx = p_from.x + dx * 0.22f + nx * branch_offset * side;
	const float sy = p_from.y + dy * 0.22f + ny * branch_offset * side;
	const float ex = p_from.x + dx * 0.78f + nx * branch_offset * side;
	const float ey = p_from.y + dy * 0.78f + ny * branch_offset * side;
	push_refined_branch_edge(r_snapshot, split_branch, p_from.x, p_from.y, sx, sy);
	push_refined_branch_edge(r_snapshot, split_branch, sx, sy, ex, ey);
	push_refined_branch_edge(r_snapshot, split_branch, ex, ey, p_to.x, p_to.y);
}

void build_refined_river_geometry(Snapshot &r_snapshot) {
	r_snapshot.refined_river_edges.clear();
	r_snapshot.refined_river_curved_edge_count = 0;
	r_snapshot.refined_river_confluence_edge_count = 0;
	r_snapshot.refined_river_y_confluence_zone_count = 0;
	r_snapshot.refined_river_y_confluence_edge_count = 0;
	r_snapshot.refined_river_braid_loop_candidate_count = 0;
	r_snapshot.refined_river_braid_loop_edge_count = 0;
	r_snapshot.river_spatial_index_offsets.clear();
	r_snapshot.river_spatial_index_edge_indices.clear();
	if (!r_snapshot.valid || r_snapshot.world_version < WORLD_REFINED_RIVER_VERSION ||
			r_snapshot.river_segment_ranges.empty() || r_snapshot.river_path_node_indices.empty()) {
		build_refined_river_spatial_index(r_snapshot);
		return;
	}
	r_snapshot.refined_river_y_confluence_zone_count = count_y_confluence_zones(r_snapshot);
	for (size_t record_offset = 0; record_offset + RIVER_SEGMENT_RECORD_SIZE <= r_snapshot.river_segment_ranges.size(); record_offset += RIVER_SEGMENT_RECORD_SIZE) {
		const int32_t segment_id = r_snapshot.river_segment_ranges[record_offset];
		const int32_t path_offset = r_snapshot.river_segment_ranges[record_offset + 1];
		const int32_t path_length = r_snapshot.river_segment_ranges[record_offset + 2];
		if (segment_id <= 0 || path_offset < 0 || path_length < 2 ||
				path_offset + path_length > static_cast<int32_t>(r_snapshot.river_path_node_indices.size())) {
			continue;
		}
		std::vector<RiverCenterSample> controls = build_base_center_samples_for_path(
			r_snapshot,
			segment_id,
			path_offset,
			path_length
		);
		if (controls.size() < 2) {
			continue;
		}
		std::vector<RiverCenterSample> samples;
		samples.reserve(controls.size() * 4);
		for (int32_t segment_index = 0; segment_index < static_cast<int32_t>(controls.size()) - 1; ++segment_index) {
			const RiverCenterSample &from = controls[static_cast<size_t>(segment_index)];
			const RiverCenterSample &to = controls[static_cast<size_t>(segment_index + 1)];
			const float dx = to.x - from.x;
			const float dy = to.y - from.y;
			const float length = std::sqrt(dx * dx + dy * dy);
			const int32_t steps = clamp_value(
				static_cast<int32_t>(std::ceil(length / std::max(3.0f, static_cast<float>(r_snapshot.cell_size_tiles) * 0.32f))),
				1,
				8
			);
			for (int32_t step = 0; step <= steps; ++step) {
				if (!samples.empty() && step == 0) {
					continue;
				}
				const float t = static_cast<float>(step) / static_cast<float>(steps);
				RiverCenterSample sample = interpolate_center_sample(r_snapshot, controls, segment_index, t);
				if (!centerline_point_has_mountain_clearance(r_snapshot, sample.x, sample.y) ||
						!centerline_segment_has_mountain_clearance(r_snapshot, from.x, from.y, sample.x, sample.y, 3) ||
						!centerline_segment_has_mountain_clearance(r_snapshot, sample.x, sample.y, to.x, to.y, 3)) {
					sample = interpolate_linear_center_sample(r_snapshot, controls, segment_index, t);
				}
				if (!centerline_point_has_mountain_clearance(r_snapshot, sample.x, sample.y)) {
					sample = t < 0.5f ? from : to;
					sample.local_t = saturate(t);
				}
				samples.push_back(sample);
			}
		}
		const int64_t river_shape_seed_version = r_snapshot.world_version >= WORLD_ORGANIC_COASTLINE_VERSION ?
				WORLD_BASIN_CONTOUR_LAKE_VERSION :
				r_snapshot.world_version;
		const uint64_t segment_seed = splitmix64(
			static_cast<uint64_t>(r_snapshot.seed) ^
			(static_cast<uint64_t>(river_shape_seed_version) << 32U) ^
			(static_cast<uint64_t>(segment_id) * 0x9e3779b185ebca87ULL)
		);
		apply_direction_memory_offsets(r_snapshot, samples, segment_seed);
		apply_y_confluence_geometry(r_snapshot, samples, segment_seed);
		const float total_river_distance = uses_hydrology_visual_v3(r_snapshot.world_version) && !controls.empty() ?
				std::max(0.0f, controls.back().cumulative) :
				0.0f;

		for (size_t sample_index = 0; sample_index + 1 < samples.size(); ++sample_index) {
			const RiverCenterSample &from = samples[sample_index];
			const RiverCenterSample &to = samples[sample_index + 1];
			const float dx = to.x - from.x;
			const float dy = to.y - from.y;
			const float length = std::sqrt(dx * dx + dy * dy);
			if (length <= 0.5f ||
					!centerline_segment_has_mountain_clearance(r_snapshot, from.x, from.y, to.x, to.y, 4)) {
				continue;
			}
			RefinedRiverEdge edge;
			edge.ax = from.x;
			edge.ay = from.y;
			edge.bx = adjust_wrapped_x_near(to.x, from.x, static_cast<float>(std::max<int64_t>(1, r_snapshot.width_tiles)));
			edge.by = to.y;
			if (r_snapshot.world_version >= WORLD_HYDROLOGY_SHAPE_FIX_VERSION) {
				edge.cumulative_start = from.cumulative;
				edge.cumulative_end = to.cumulative;
				edge.shape_quality_v2_fix = true;
				if (uses_hydrology_visual_v3(r_snapshot.world_version)) {
					sync_refined_edge_distance_fields(edge, total_river_distance);
				}
			}
			edge.segment_id = segment_id;
			edge.stream_order = std::max<uint8_t>(1U, from.stream_order);
			edge.flow_dir = from.flow_dir;
			edge.radius_scale = clamp_value((from.radius_scale + to.radius_scale) * 0.5f, 0.5f, 2.4f);
			if (r_snapshot.world_version >= WORLD_CURVATURE_RIVER_VERSION) {
				edge.curvature = compute_refined_edge_curvature(samples, sample_index);
				edge.confluence_weight = std::max(
					y_confluence_weight_for_sample(r_snapshot, from),
					y_confluence_weight_for_sample(r_snapshot, to)
				);
				edge.confluence = edge.confluence_weight >= 0.18f;
				if (edge.confluence) {
					edge.radius_scale = std::min(2.8f, edge.radius_scale + 0.12f + edge.confluence_weight * 0.18f);
				}
				if (std::abs(edge.curvature) >= 0.08f) {
					r_snapshot.refined_river_curved_edge_count += 1;
				}
				if (edge.confluence) {
					r_snapshot.refined_river_confluence_edge_count += 1;
				}
				if (r_snapshot.world_version >= WORLD_Y_CONFLUENCE_RIVER_VERSION &&
						edge.confluence_weight >= 0.18f) {
					r_snapshot.refined_river_y_confluence_edge_count += 1;
				}
			}
			edge.variation_seed = r_snapshot.world_version >= WORLD_HYDROLOGY_SHAPE_FIX_VERSION ?
					segment_seed :
					splitmix64(segment_seed ^ static_cast<uint64_t>(sample_index) * 0xbf58476d1ce4e5b9ULL);
			edge.source = sample_index == 0 && from.source;
			edge.delta = from.delta || to.delta;
			edge.organic = true;
			r_snapshot.refined_river_edges.push_back(edge);
		}

		for (int32_t control_index = 0; control_index < static_cast<int32_t>(controls.size()) - 1; ++control_index) {
			const RiverCenterSample &from = controls[static_cast<size_t>(control_index)];
			const RiverCenterSample &to = controls[static_cast<size_t>(control_index + 1)];
			RefinedRiverEdge template_edge;
			template_edge.ax = from.x;
			template_edge.ay = from.y;
			template_edge.bx = adjust_wrapped_x_near(to.x, from.x, static_cast<float>(std::max<int64_t>(1, r_snapshot.width_tiles)));
			template_edge.by = to.y;
			if (r_snapshot.world_version >= WORLD_HYDROLOGY_SHAPE_FIX_VERSION) {
				template_edge.cumulative_start = from.cumulative;
				template_edge.cumulative_end = to.cumulative;
				template_edge.shape_quality_v2_fix = true;
				if (uses_hydrology_visual_v3(r_snapshot.world_version)) {
					sync_refined_edge_distance_fields(template_edge, total_river_distance);
				}
			}
			template_edge.segment_id = segment_id;
			template_edge.stream_order = std::max<uint8_t>(1U, from.stream_order);
			template_edge.flow_dir = from.flow_dir;
			template_edge.radius_scale = refined_radius_scale_for_node(
				r_snapshot,
				from.node_index,
				to.node_index,
				template_edge.stream_order,
				node_is_ocean(r_snapshot, to.node_index)
			);
			if (r_snapshot.world_version >= WORLD_CURVATURE_RIVER_VERSION) {
				const float from_weight = node_has_y_confluence_zone(r_snapshot, from.node_index) ? 0.72f : 0.0f;
				const float to_weight = node_has_y_confluence_zone(r_snapshot, to.node_index) ? 0.72f : 0.0f;
				template_edge.confluence_weight = r_snapshot.world_version >= WORLD_Y_CONFLUENCE_RIVER_VERSION ?
						std::max(from_weight, to_weight) :
						(river_upstream_count_for_node(r_snapshot, from.node_index) >= 2 ? 1.0f : 0.0f);
				template_edge.confluence = template_edge.confluence_weight >= 0.18f;
				if (template_edge.confluence) {
					template_edge.radius_scale = std::min(2.8f, template_edge.radius_scale + 0.12f + template_edge.confluence_weight * 0.18f);
				}
			}
			template_edge.variation_seed = splitmix64(
				segment_seed ^
				(static_cast<uint64_t>(from.node_index) << 16U) ^
				static_cast<uint64_t>(to.node_index)
			);
			template_edge.organic = true;
			append_refined_branch_edges_for_coarse_step(
				r_snapshot,
				template_edge,
				from,
				to,
				node_is_lake(r_snapshot, from.node_index),
				node_is_lake(r_snapshot, to.node_index),
				node_is_ocean(r_snapshot, to.node_index)
			);
		}
	}
	build_refined_river_spatial_index(r_snapshot);
}

void detect_oxbow_candidates(Snapshot &r_snapshot) {
	r_snapshot.oxbow_candidate_count = 0;
	r_snapshot.oxbow_lake_node_count = 0;
	if (r_snapshot.oxbow_lake_node_mask.size() !=
			static_cast<size_t>(std::max(0, r_snapshot.grid_width * r_snapshot.grid_height))) {
		r_snapshot.oxbow_lake_node_mask.assign(static_cast<size_t>(std::max(0, r_snapshot.grid_width * r_snapshot.grid_height)), 0U);
	} else {
		std::fill(r_snapshot.oxbow_lake_node_mask.begin(), r_snapshot.oxbow_lake_node_mask.end(), 0U);
	}
	if (r_snapshot.world_version < WORLD_BASIN_CONTOUR_LAKE_VERSION ||
			r_snapshot.refined_river_edges.empty()) {
		return;
	}
	const int32_t node_count = r_snapshot.grid_width * r_snapshot.grid_height;
	if (node_count <= 0) {
		return;
	}
	int32_t next_lake_id = 1;
	for (const int32_t lake_id : r_snapshot.lake_id) {
		next_lake_id = std::max(next_lake_id, lake_id + 1);
	}
	const int32_t max_oxbow_lakes = clamp_value(node_count / 1536, 1, 32);
	std::unordered_set<int32_t> used_nodes;
	auto node_is_eligible = [&](int32_t p_node) {
		return p_node >= 0 &&
				p_node < node_count &&
				p_node < static_cast<int32_t>(r_snapshot.mountain_exclusion_mask.size()) &&
				r_snapshot.mountain_exclusion_mask[static_cast<size_t>(p_node)] == 0U &&
				p_node < static_cast<int32_t>(r_snapshot.ocean_sink_mask.size()) &&
				r_snapshot.ocean_sink_mask[static_cast<size_t>(p_node)] == 0U &&
				p_node < static_cast<int32_t>(r_snapshot.lake_id.size()) &&
				r_snapshot.lake_id[static_cast<size_t>(p_node)] == 0 &&
				p_node < static_cast<int32_t>(r_snapshot.river_node_mask.size()) &&
				r_snapshot.river_node_mask[static_cast<size_t>(p_node)] == 0U &&
				used_nodes.find(p_node) == used_nodes.end();
	};
	auto push_unique_node = [&](std::vector<int32_t> &r_nodes, int32_t p_node) {
		if (!node_is_eligible(p_node)) {
			return;
		}
		for (const int32_t existing : r_nodes) {
			if (existing == p_node) {
				return;
			}
		}
		r_nodes.push_back(p_node);
	};
	for (const RefinedRiverEdge &edge : r_snapshot.refined_river_edges) {
		if (!edge.organic || edge.delta || edge.braid_split || edge.confluence ||
				edge.stream_order < 2U || std::abs(edge.curvature) < 0.115f) {
			continue;
		}
		if (r_snapshot.oxbow_candidate_count >= max_oxbow_lakes) {
			break;
		}
		const float mx = (edge.ax + edge.bx) * 0.5f;
		const float my = (edge.ay + edge.by) * 0.5f;
		const int32_t node_index = hydrology_node_for_tile(r_snapshot, mx, my);
		if (node_index < 0 ||
				node_index >= r_snapshot.grid_width * r_snapshot.grid_height ||
				node_index >= static_cast<int32_t>(r_snapshot.mountain_exclusion_mask.size()) ||
				r_snapshot.mountain_exclusion_mask[static_cast<size_t>(node_index)] != 0U ||
				node_is_lake(r_snapshot, node_index) ||
				node_is_ocean(r_snapshot, node_index)) {
			continue;
		}
		const float floodplain = node_floodplain_factor(r_snapshot, node_index);
		const int32_t downstream = downstream_node_for_node(r_snapshot, node_index);
		const float flatness = downstream >= 0 ? node_slope_flatness(r_snapshot, node_index, downstream) : 0.0f;
		if (floodplain < 0.08f || flatness < 0.18f) {
			continue;
		}
		const float dx = edge.bx - edge.ax;
		const float dy = edge.by - edge.ay;
		const float length = std::sqrt(dx * dx + dy * dy);
		if (length <= 0.001f) {
			continue;
		}
		const float tx = dx / length;
		const float ty = dy / length;
		const float nx = -ty;
		const float ny = tx;
		const float side = edge.curvature >= 0.0f ? 1.0f : -1.0f;
		const float cell_size = static_cast<float>(std::max(1, r_snapshot.cell_size_tiles));
		std::vector<int32_t> oxbow_nodes;
		oxbow_nodes.reserve(5);
		const float offset = cell_size * (0.72f + saturate(std::abs(edge.curvature)) * 0.55f);
		const float shoulder = cell_size * 0.42f;
		push_unique_node(
			oxbow_nodes,
			hydrology_node_for_tile(r_snapshot, mx + nx * offset * side, my + ny * offset * side)
		);
		push_unique_node(
			oxbow_nodes,
			hydrology_node_for_tile(r_snapshot, mx + nx * offset * 0.92f * side - tx * shoulder, my + ny * offset * 0.92f * side - ty * shoulder)
		);
		push_unique_node(
			oxbow_nodes,
			hydrology_node_for_tile(r_snapshot, mx + nx * offset * 0.92f * side + tx * shoulder, my + ny * offset * 0.92f * side + ty * shoulder)
		);
		if (oxbow_nodes.size() < 2) {
			const int32_t center_x = node_index % r_snapshot.grid_width;
			const int32_t center_y = node_index / r_snapshot.grid_width;
			for (int32_t radius = 1; radius <= 2 && oxbow_nodes.size() < 3; ++radius) {
				for (int32_t oy = -radius; oy <= radius && oxbow_nodes.size() < 3; ++oy) {
					const int32_t y = center_y + oy;
					if (y < 0 || y >= r_snapshot.grid_height) {
						continue;
					}
					for (int32_t ox = -radius; ox <= radius && oxbow_nodes.size() < 3; ++ox) {
						if (std::abs(ox) + std::abs(oy) != radius) {
							continue;
						}
						const int32_t x = static_cast<int32_t>(positive_mod(center_x + ox, r_snapshot.grid_width));
						push_unique_node(oxbow_nodes, r_snapshot.index(x, y));
					}
				}
			}
		}
		if (oxbow_nodes.empty()) {
			continue;
		}
		const int32_t lake_id = next_lake_id++;
		for (size_t index = 0; index < oxbow_nodes.size(); ++index) {
			const int32_t node = oxbow_nodes[index];
			r_snapshot.lake_id[static_cast<size_t>(node)] = lake_id;
			r_snapshot.lake_depth_ratio[static_cast<size_t>(node)] = index == 0 ? 0.74f : 0.50f;
			r_snapshot.oxbow_lake_node_mask[static_cast<size_t>(node)] = 1U;
			used_nodes.insert(node);
			r_snapshot.oxbow_lake_node_count += 1;
		}
		r_snapshot.oxbow_candidate_count += 1;
	}
}

void refresh_ocean_shelf_metrics(Snapshot &r_snapshot) {
	const int32_t node_count = r_snapshot.grid_width * r_snapshot.grid_height;
	if (node_count <= 0) {
		r_snapshot.ocean_coastline_node_count = 0;
		r_snapshot.ocean_shallow_shelf_node_count = 0;
		return;
	}
	if (r_snapshot.ocean_shelf_depth_ratio.size() != static_cast<size_t>(node_count)) {
		r_snapshot.ocean_shelf_depth_ratio.assign(static_cast<size_t>(node_count), 0.0f);
	}
	if (r_snapshot.ocean_river_mouth_influence.size() != static_cast<size_t>(node_count)) {
		r_snapshot.ocean_river_mouth_influence.assign(static_cast<size_t>(node_count), 0.0f);
	}
	r_snapshot.ocean_coastline_node_count = 0;
	r_snapshot.ocean_shallow_shelf_node_count = 0;
	if (r_snapshot.world_version < WORLD_ORGANIC_COASTLINE_VERSION ||
			r_snapshot.ocean_coast_distance_tiles.size() != static_cast<size_t>(node_count)) {
		return;
	}

	const float cell_size = static_cast<float>(std::max(1, r_snapshot.cell_size_tiles));
	const float coastline_band_tiles = cell_size * 0.80f;
	const float base_shelf_width_tiles = clamp_value(
		static_cast<float>(r_snapshot.ocean_band_tiles) * 0.22f,
		cell_size * 1.50f,
		cell_size * 2.75f
	);
	for (int32_t index = 0; index < node_count; ++index) {
		const float coast_distance = r_snapshot.ocean_coast_distance_tiles[static_cast<size_t>(index)];
		const bool ocean = r_snapshot.ocean_sink_mask.size() > static_cast<size_t>(index) &&
				r_snapshot.ocean_sink_mask[static_cast<size_t>(index)] != 0U;
		const float mouth_influence = saturate(r_snapshot.ocean_river_mouth_influence[static_cast<size_t>(index)]);
		if (std::abs(coast_distance) <= coastline_band_tiles) {
			r_snapshot.ocean_coastline_node_count += 1;
		}
		if (!ocean) {
			r_snapshot.ocean_shelf_depth_ratio[static_cast<size_t>(index)] = 0.0f;
			continue;
		}
		const float local_shelf_width = base_shelf_width_tiles * (1.0f + mouth_influence * 0.85f);
		float shelf_ratio = saturate(coast_distance / std::max(1.0f, local_shelf_width));
		shelf_ratio = saturate(shelf_ratio - mouth_influence * 0.16f);
		r_snapshot.ocean_shelf_depth_ratio[static_cast<size_t>(index)] = shelf_ratio;
		if (coast_distance > 0.0f && shelf_ratio > 0.02f && shelf_ratio < 0.72f) {
			r_snapshot.ocean_shallow_shelf_node_count += 1;
		}
	}
}

void apply_ocean_river_mouth_influence(Snapshot &r_snapshot) {
	r_snapshot.ocean_river_mouth_node_count = 0;
	if (r_snapshot.world_version < WORLD_ORGANIC_COASTLINE_VERSION) {
		refresh_ocean_shelf_metrics(r_snapshot);
		return;
	}
	const int32_t node_count = r_snapshot.grid_width * r_snapshot.grid_height;
	if (node_count <= 0) {
		refresh_ocean_shelf_metrics(r_snapshot);
		return;
	}
	r_snapshot.ocean_river_mouth_influence.assign(static_cast<size_t>(node_count), 0.0f);
	std::unordered_set<int32_t> mouth_nodes;
	for (int32_t index = 0; index < node_count; ++index) {
		if (r_snapshot.river_node_mask.size() <= static_cast<size_t>(index) ||
				r_snapshot.river_node_mask[static_cast<size_t>(index)] == 0U ||
				node_is_ocean(r_snapshot, index)) {
			continue;
		}
		const int32_t downstream = downstream_node_for_node(r_snapshot, index);
		if (!node_is_ocean(r_snapshot, downstream)) {
			continue;
		}
		mouth_nodes.insert(downstream);
		const uint8_t stream_order = r_snapshot.river_stream_order.size() > static_cast<size_t>(index) ?
				r_snapshot.river_stream_order[static_cast<size_t>(index)] :
				1U;
		const float order_t = saturate((static_cast<float>(stream_order) - 1.0f) / 5.0f);
		const float radius_f = 1.25f + order_t * 2.5f +
				clamp_value(r_snapshot.river_settings.delta_scale, 0.0f, 2.0f) * 0.55f;
		const int32_t radius = clamp_value(static_cast<int32_t>(std::ceil(radius_f)), 1, 5);
		const int32_t center_x = downstream % r_snapshot.grid_width;
		const int32_t center_y = downstream / r_snapshot.grid_width;
		for (int32_t oy = -radius; oy <= radius; ++oy) {
			const int32_t ny = center_y + oy;
			if (ny < 0 || ny >= r_snapshot.grid_height) {
				continue;
			}
			for (int32_t ox = -radius; ox <= radius; ++ox) {
				if (ox * ox + oy * oy > radius * radius) {
					continue;
				}
				const int32_t nx = static_cast<int32_t>(positive_mod(center_x + ox, r_snapshot.grid_width));
				const int32_t n_index = r_snapshot.index(nx, ny);
				if (n_index < 0 || n_index >= node_count ||
						node_is_lake(r_snapshot, n_index) ||
						(r_snapshot.mountain_exclusion_mask.size() > static_cast<size_t>(n_index) &&
								r_snapshot.mountain_exclusion_mask[static_cast<size_t>(n_index)] != 0U)) {
					continue;
				}
				const float distance = std::sqrt(static_cast<float>(ox * ox + oy * oy));
				const float falloff = 1.0f - saturate(distance / std::max(1.0f, static_cast<float>(radius)));
				const float influence = falloff * (0.58f + order_t * 0.32f);
				float &current = r_snapshot.ocean_river_mouth_influence[static_cast<size_t>(n_index)];
				current = std::max(current, influence);
			}
		}
	}
	r_snapshot.ocean_river_mouth_node_count = static_cast<int32_t>(mouth_nodes.size());
	refresh_ocean_shelf_metrics(r_snapshot);
}

OverviewRiverSample sample_overview_river_edges(
	const std::vector<OverviewRiverEdge> &p_edges,
	float p_x,
	float p_y,
	float p_world_width
) {
	OverviewRiverSample sample;
	for (const OverviewRiverEdge &edge : p_edges) {
		const SegmentProjection projection = project_to_overview_segment(p_x, p_y, edge, p_world_width);
		if (projection.distance >= sample.distance) {
			continue;
		}
		sample.distance = projection.distance;
		sample.stream_order = edge.stream_order;
		sample.radius_scale = resolve_overview_radius_scale(edge, projection);
		sample.delta = edge.delta;
		sample.braid_split = edge.braid_split;
	}
	return sample;
}

int32_t sample_lake_id_at_node(const Snapshot &p_snapshot, int32_t p_node_x, int32_t p_node_y) {
	if (!p_snapshot.valid || p_node_y < 0 || p_node_y >= p_snapshot.grid_height ||
			p_snapshot.lake_id.empty()) {
		return 0;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(p_node_x, p_snapshot.grid_width));
	const int32_t node_index = p_snapshot.index(node_x, p_node_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_snapshot.lake_id.size())) {
		return 0;
	}
	return p_snapshot.lake_id[static_cast<size_t>(node_index)];
}

bool is_lake_overview_pixel(
	const Snapshot &p_snapshot,
	int32_t p_node_x,
	int32_t p_node_y,
	int32_t p_local_pixel_x,
	int32_t p_local_pixel_y,
	int32_t p_pixels_per_cell
) {
	const int32_t node_index = p_snapshot.index(p_node_x, p_node_y);
	if (p_snapshot.lake_id.empty() || node_index < 0 ||
			node_index >= static_cast<int32_t>(p_snapshot.lake_id.size())) {
		return false;
	}
	const int32_t center_lake_id = p_snapshot.lake_id[static_cast<size_t>(node_index)];
	if (center_lake_id <= 0) {
		return false;
	}
	if (p_snapshot.world_version < WORLD_ORGANIC_WATER_VERSION) {
		return true;
	}
	const int32_t north_lake_id = sample_lake_id_at_node(p_snapshot, p_node_x, p_node_y - 1);
	const int32_t east_lake_id = sample_lake_id_at_node(p_snapshot, p_node_x + 1, p_node_y);
	const int32_t south_lake_id = sample_lake_id_at_node(p_snapshot, p_node_x, p_node_y + 1);
	const int32_t west_lake_id = sample_lake_id_at_node(p_snapshot, p_node_x - 1, p_node_y);
	const bool basin_contour = p_snapshot.world_version >= WORLD_BASIN_CONTOUR_LAKE_VERSION &&
			node_index < static_cast<int32_t>(p_snapshot.lake_depth_ratio.size());
	const float depth_ratio = basin_contour ?
			saturate(p_snapshot.lake_depth_ratio[static_cast<size_t>(node_index)]) :
			1.0f;
	if (north_lake_id == center_lake_id && east_lake_id == center_lake_id &&
			south_lake_id == center_lake_id && west_lake_id == center_lake_id) {
		return true;
	}
	const int32_t cell_size = std::max<int32_t>(1, p_snapshot.cell_size_tiles);
	const float local_x = (static_cast<float>(p_local_pixel_x) + 0.5f) /
			static_cast<float>(std::max(1, p_pixels_per_cell)) * static_cast<float>(cell_size);
	const float local_y = (static_cast<float>(p_local_pixel_y) + 0.5f) /
			static_cast<float>(std::max(1, p_pixels_per_cell)) * static_cast<float>(cell_size);
	float nearest_open_edge_distance = static_cast<float>(cell_size);
	if (north_lake_id != center_lake_id) {
		nearest_open_edge_distance = std::min(nearest_open_edge_distance, local_y);
	}
	if (east_lake_id != center_lake_id) {
		nearest_open_edge_distance = std::min(nearest_open_edge_distance, static_cast<float>(cell_size) - local_x);
	}
	if (south_lake_id != center_lake_id) {
		nearest_open_edge_distance = std::min(nearest_open_edge_distance, static_cast<float>(cell_size) - local_y);
	}
	if (west_lake_id != center_lake_id) {
		nearest_open_edge_distance = std::min(nearest_open_edge_distance, local_x);
	}
	const uint64_t seed = mix_seed(
		p_snapshot.seed,
		p_snapshot.world_version,
		SEED_SALT_LAKE_OUTLINE ^ static_cast<uint64_t>(center_lake_id)
	);
	const float world_x = static_cast<float>(p_node_x * cell_size) + local_x;
	const float world_y = static_cast<float>(p_node_y * cell_size) + local_y;
	const float scale = std::max(3.0f, static_cast<float>(cell_size) * 0.42f);
	const float roughness_tiles = clamp_value(static_cast<float>(cell_size) * 0.30f, 2.0f, 6.5f);
	const float lake_start = clamp_value(
		static_cast<float>(clamp_value(cell_size / 4, 2, 5)) *
				(basin_contour ? 0.50f + (1.0f - depth_ratio) * 0.42f : 0.65f) +
				(signed_value_noise_2d(seed, world_x / scale, world_y / scale) + 1.0f) * 0.5f * roughness_tiles,
		1.0f,
		static_cast<float>(cell_size) * 0.48f
	);
	return nearest_open_edge_distance >= lake_start;
}

void build_mountain_clearance(Snapshot &r_snapshot, const world_prepass::Snapshot &p_foundation_snapshot, int32_t p_clearance_tiles) {
	const int32_t node_count = r_snapshot.grid_width * r_snapshot.grid_height;
	std::vector<uint8_t> source_mask(static_cast<size_t>(node_count), 0U);
	for (int32_t y = 0; y < r_snapshot.grid_height; ++y) {
		for (int32_t x = 0; x < r_snapshot.grid_width; ++x) {
			const int32_t index = r_snapshot.index(x, y);
			const Vector2i center = r_snapshot.node_to_tile_center(x, y);
			const int32_t foundation_index = sample_foundation_index(p_foundation_snapshot, center.x, center.y);
			const bool mountain_like =
					p_foundation_snapshot.coarse_wall_density[static_cast<size_t>(foundation_index)] > 0.02f ||
					p_foundation_snapshot.coarse_foot_density[static_cast<size_t>(foundation_index)] > 0.08f;
			if (mountain_like && r_snapshot.ocean_sink_mask[static_cast<size_t>(index)] == 0U) {
				source_mask[static_cast<size_t>(index)] = 1U;
			}
		}
	}

	const int32_t radius = std::max<int32_t>(0, static_cast<int32_t>(
		std::ceil(static_cast<float>(p_clearance_tiles) / static_cast<float>(std::max(1, r_snapshot.cell_size_tiles)))
	));
	for (int32_t y = 0; y < r_snapshot.grid_height; ++y) {
		for (int32_t x = 0; x < r_snapshot.grid_width; ++x) {
			const int32_t index = r_snapshot.index(x, y);
			if (source_mask[static_cast<size_t>(index)] == 0U) {
				continue;
			}
			for (int32_t oy = -radius; oy <= radius; ++oy) {
				const int32_t ny = y + oy;
				if (ny < 0 || ny >= r_snapshot.grid_height) {
					continue;
				}
				for (int32_t ox = -radius; ox <= radius; ++ox) {
					if (ox * ox + oy * oy > radius * radius) {
						continue;
					}
					const int32_t nx = static_cast<int32_t>(positive_mod(x + ox, r_snapshot.grid_width));
					const int32_t n_index = r_snapshot.index(nx, ny);
					if (r_snapshot.ocean_sink_mask[static_cast<size_t>(n_index)] == 0U) {
						r_snapshot.mountain_exclusion_mask[static_cast<size_t>(n_index)] = 1U;
					}
				}
			}
		}
	}
}

void solve_priority_flood(Snapshot &r_snapshot) {
	const int32_t node_count = r_snapshot.grid_width * r_snapshot.grid_height;
	std::vector<uint8_t> visited(static_cast<size_t>(node_count), 0U);
	std::vector<int32_t> parent(static_cast<size_t>(node_count), -1);
	std::vector<int32_t> visit_order;
	visit_order.reserve(static_cast<size_t>(node_count));
	std::priority_queue<QueueNode, std::vector<QueueNode>, std::greater<QueueNode>> queue;

	int32_t watershed_seed = 1;
	for (int32_t y = 0; y < r_snapshot.grid_height; ++y) {
		for (int32_t x = 0; x < r_snapshot.grid_width; ++x) {
			const int32_t index = r_snapshot.index(x, y);
			if (r_snapshot.ocean_sink_mask[static_cast<size_t>(index)] == 0U) {
				continue;
			}
			visited[static_cast<size_t>(index)] = 1U;
			r_snapshot.filled_elevation[static_cast<size_t>(index)] = r_snapshot.hydro_elevation[static_cast<size_t>(index)];
			r_snapshot.flow_dir[static_cast<size_t>(index)] = FLOW_DIR_TERMINAL;
			r_snapshot.watershed_id[static_cast<size_t>(index)] = watershed_seed++;
			queue.push({ r_snapshot.filled_elevation[static_cast<size_t>(index)], index });
			visit_order.push_back(index);
		}
	}

	if (queue.empty()) {
		for (int32_t x = 0; x < r_snapshot.grid_width; ++x) {
			const int32_t index = r_snapshot.index(x, 0);
			visited[static_cast<size_t>(index)] = 1U;
			r_snapshot.filled_elevation[static_cast<size_t>(index)] = r_snapshot.hydro_elevation[static_cast<size_t>(index)];
			r_snapshot.flow_dir[static_cast<size_t>(index)] = FLOW_DIR_TERMINAL;
			r_snapshot.watershed_id[static_cast<size_t>(index)] = watershed_seed++;
			queue.push({ r_snapshot.filled_elevation[static_cast<size_t>(index)], index });
			visit_order.push_back(index);
		}
	}

	while (!queue.empty()) {
		const QueueNode current = queue.top();
		queue.pop();
		const int32_t current_x = current.index % r_snapshot.grid_width;
		const int32_t current_y = current.index / r_snapshot.grid_width;
		for (int32_t direction = 0; direction < 8; ++direction) {
			const int32_t nx = static_cast<int32_t>(positive_mod(current_x + FLOW_DX[direction], r_snapshot.grid_width));
			const int32_t ny = current_y + FLOW_DY[direction];
			if (ny < 0 || ny >= r_snapshot.grid_height) {
				continue;
			}
			const int32_t neighbor_index = r_snapshot.index(nx, ny);
			if (visited[static_cast<size_t>(neighbor_index)] != 0U) {
				continue;
			}
			visited[static_cast<size_t>(neighbor_index)] = 1U;
			parent[static_cast<size_t>(neighbor_index)] = current.index;
			const float filled = std::max(
				r_snapshot.hydro_elevation[static_cast<size_t>(neighbor_index)],
				r_snapshot.filled_elevation[static_cast<size_t>(current.index)]
			);
			r_snapshot.filled_elevation[static_cast<size_t>(neighbor_index)] = filled;
			r_snapshot.watershed_id[static_cast<size_t>(neighbor_index)] = r_snapshot.watershed_id[static_cast<size_t>(current.index)];
			queue.push({ filled, neighbor_index });
			visit_order.push_back(neighbor_index);
		}
	}

	for (int32_t y = 0; y < r_snapshot.grid_height; ++y) {
		for (int32_t x = 0; x < r_snapshot.grid_width; ++x) {
			const int32_t index = r_snapshot.index(x, y);
			const int32_t parent_index = parent[static_cast<size_t>(index)];
			if (parent_index < 0) {
				continue;
			}
			r_snapshot.flow_dir[static_cast<size_t>(index)] = direction_from_to(
				x,
				y,
				parent_index % r_snapshot.grid_width,
				parent_index / r_snapshot.grid_width,
				r_snapshot.grid_width
			);
		}
	}

	for (int32_t index = 0; index < node_count; ++index) {
		if (r_snapshot.ocean_sink_mask[static_cast<size_t>(index)] == 0U &&
				r_snapshot.mountain_exclusion_mask[static_cast<size_t>(index)] == 0U) {
			r_snapshot.flow_accumulation[static_cast<size_t>(index)] = 1.0f;
		}
	}
	for (auto iter = visit_order.rbegin(); iter != visit_order.rend(); ++iter) {
		const int32_t index = *iter;
		const int32_t parent_index = parent[static_cast<size_t>(index)];
		if (parent_index >= 0) {
			r_snapshot.flow_accumulation[static_cast<size_t>(parent_index)] += r_snapshot.flow_accumulation[static_cast<size_t>(index)];
		}
	}
}

int32_t resolve_downstream_index(const Snapshot &p_snapshot, int32_t p_index) {
	if (p_index < 0 || p_index >= p_snapshot.grid_width * p_snapshot.grid_height) {
		return -1;
	}
	const uint8_t direction = p_snapshot.flow_dir[static_cast<size_t>(p_index)];
	if (direction == FLOW_DIR_TERMINAL || direction >= 8U) {
		return -1;
	}
	const int32_t x = p_index % p_snapshot.grid_width;
	const int32_t y = p_index / p_snapshot.grid_width;
	const int32_t nx = static_cast<int32_t>(positive_mod(x + FLOW_DX[direction], p_snapshot.grid_width));
	const int32_t ny = y + FLOW_DY[direction];
	if (ny < 0 || ny >= p_snapshot.grid_height) {
		return -1;
	}
	return p_snapshot.index(nx, ny);
}

class LakeCandidateMountainSampler {
public:
	LakeCandidateMountainSampler(
		int64_t p_seed,
		int64_t p_world_version,
		const mountain_field::Evaluator &p_mountain_evaluator,
		const FoundationSettings &p_foundation_settings
	) :
			seed_(p_seed),
			world_version_(p_world_version),
			mountain_evaluator_(p_mountain_evaluator),
			mountain_settings_(p_mountain_evaluator.get_settings()),
			mountain_thresholds_(p_mountain_evaluator.get_thresholds()),
			foundation_settings_(p_foundation_settings),
			macro_cell_size_(mountain_field::get_hierarchical_macro_cell_size(p_world_version)) {}

	bool tile_is_wall_or_foot(int64_t p_world_x, int64_t p_world_y) {
		const int64_t sample_world_x = resolve_mountain_sample_x(p_world_x, world_version_, foundation_settings_);
		const float elevation = mountain_evaluator_.sample_elevation(sample_world_x, p_world_y);
		if (elevation < mountain_thresholds_.t_edge) {
			return false;
		}
		if (!mountain_field::uses_hierarchical_labeling(world_version_)) {
			return true;
		}
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(
			sample_world_x,
			macro_cell_size_,
			mountain_settings_.world_wrap_width_tiles
		);
		const int64_t macro_cell_y = resolve_macro_cell_y_for_world(p_world_y, macro_cell_size_);
		const mountain_field::HierarchicalMacroSolve &solve = get_macro_solve(macro_cell_x, macro_cell_y);
		return solve.resolve_mountain_id(sample_world_x, p_world_y, elevation, mountain_thresholds_.t_edge) > 0;
	}

private:
	const mountain_field::HierarchicalMacroSolve &get_macro_solve(int64_t p_macro_cell_x, int64_t p_macro_cell_y) {
		const uint64_t key = make_macro_key(p_macro_cell_x, p_macro_cell_y);
		auto found = macro_cache_.find(key);
		if (found != macro_cache_.end()) {
			return found->second;
		}
		mountain_field::HierarchicalMacroSolve solve = mountain_field::solve_hierarchical_macro(
			seed_,
			world_version_,
			p_macro_cell_x,
			p_macro_cell_y,
			mountain_settings_
		);
		auto inserted = macro_cache_.emplace(key, std::move(solve));
		return inserted.first->second;
	}

	int64_t seed_ = 0;
	int64_t world_version_ = 0;
	const mountain_field::Evaluator &mountain_evaluator_;
	const mountain_field::Settings mountain_settings_;
	const mountain_field::Thresholds mountain_thresholds_;
	const FoundationSettings foundation_settings_;
	int32_t macro_cell_size_ = 1;
	std::unordered_map<uint64_t, mountain_field::HierarchicalMacroSolve> macro_cache_;
};

bool lake_candidate_has_tile_mountain_conflict(
	const Snapshot &p_snapshot,
	int32_t p_node_index,
	LakeCandidateMountainSampler &r_mountain_sampler
) {
	if (!uses_hydrology_visual_v3(p_snapshot.world_version) || p_node_index < 0 ||
			p_node_index >= p_snapshot.grid_width * p_snapshot.grid_height) {
		return false;
	}
	const int32_t cell_size = std::max<int32_t>(1, p_snapshot.cell_size_tiles);
	const int32_t node_x = p_node_index % p_snapshot.grid_width;
	const int32_t node_y = p_node_index / p_snapshot.grid_width;
	for (int32_t sample_y = 0; sample_y < 2; ++sample_y) {
		for (int32_t sample_x = 0; sample_x < 2; ++sample_x) {
			const int64_t world_x = static_cast<int64_t>(node_x) * cell_size +
					((static_cast<int64_t>(sample_x) * 2 + 1) * cell_size) / 4;
			const int64_t world_y = std::min<int64_t>(
				std::max<int64_t>(0, p_snapshot.height_tiles - 1),
				static_cast<int64_t>(node_y) * cell_size +
						((static_cast<int64_t>(sample_y) * 2 + 1) * cell_size) / 4
			);
			if (r_mountain_sampler.tile_is_wall_or_foot(world_x, world_y)) {
				return true;
			}
		}
	}
	return false;
}

void select_lake_basins(
	Snapshot &r_snapshot,
	const RiverSettings &p_river_settings,
	const FoundationSettings &p_foundation_settings,
	const mountain_field::Evaluator &p_mountain_evaluator
) {
	if (r_snapshot.world_version < WORLD_LAKE_VERSION || p_river_settings.lake_chance <= 0.0f) {
		return;
	}
	const int32_t node_count = r_snapshot.grid_width * r_snapshot.grid_height;
	if (node_count <= 0) {
		return;
	}
	r_snapshot.basin_contour_lake_node_count = 0;
	r_snapshot.lake_spill_point_count = 0;
	r_snapshot.lake_outlet_connection_count = 0;
	r_snapshot.lake_outlet_node_by_id.clear();
	r_snapshot.lake_water_level_per_id.clear();

	const float chance = saturate(p_river_settings.lake_chance);
	const float depth_threshold = 0.010f + (1.0f - chance) * 0.020f;
	std::vector<uint8_t> candidate_mask(static_cast<size_t>(node_count), 0U);
	LakeCandidateMountainSampler lake_mountain_sampler(
		r_snapshot.seed,
		r_snapshot.world_version,
		p_mountain_evaluator,
		p_foundation_settings
	);
	for (int32_t index = 0; index < node_count; ++index) {
		if (r_snapshot.ocean_sink_mask[static_cast<size_t>(index)] != 0U ||
				r_snapshot.mountain_exclusion_mask[static_cast<size_t>(index)] != 0U ||
				lake_candidate_has_tile_mountain_conflict(r_snapshot, index, lake_mountain_sampler)) {
			continue;
		}
		const float depression_depth = r_snapshot.filled_elevation[static_cast<size_t>(index)] -
				r_snapshot.hydro_elevation[static_cast<size_t>(index)];
		if (depression_depth >= depth_threshold) {
			candidate_mask[static_cast<size_t>(index)] = 1U;
		}
	}

	std::vector<int32_t> component_id(static_cast<size_t>(node_count), -1);
	std::vector<LakeBasinCandidate> candidates;
	std::vector<int32_t> stack;
	const int32_t min_component_nodes = std::max<int32_t>(2, std::min<int32_t>(8, node_count / 4096));
	for (int32_t start = 0; start < node_count; ++start) {
		if (candidate_mask[static_cast<size_t>(start)] == 0U || component_id[static_cast<size_t>(start)] >= 0) {
			continue;
		}
		const int32_t component_index = static_cast<int32_t>(candidates.size());
		LakeBasinCandidate candidate;
		stack.clear();
		stack.push_back(start);
		component_id[static_cast<size_t>(start)] = component_index;
		while (!stack.empty()) {
			const int32_t current = stack.back();
			stack.pop_back();
			candidate.nodes.push_back(current);
			const int32_t x = current % r_snapshot.grid_width;
			const int32_t y = current / r_snapshot.grid_width;
			for (int32_t direction = 0; direction < 8; ++direction) {
				const int32_t nx = static_cast<int32_t>(positive_mod(x + FLOW_DX[direction], r_snapshot.grid_width));
				const int32_t ny = y + FLOW_DY[direction];
				if (ny < 0 || ny >= r_snapshot.grid_height) {
					continue;
				}
				const int32_t neighbor = r_snapshot.index(nx, ny);
				if (candidate_mask[static_cast<size_t>(neighbor)] == 0U ||
						component_id[static_cast<size_t>(neighbor)] >= 0) {
					continue;
				}
				component_id[static_cast<size_t>(neighbor)] = component_index;
				stack.push_back(neighbor);
			}
		}
		if (static_cast<int32_t>(candidate.nodes.size()) < min_component_nodes) {
			candidates.push_back(candidate);
			continue;
		}
		float accumulation_sum = 0.0f;
		for (const int32_t node : candidate.nodes) {
			const float depression_depth = r_snapshot.filled_elevation[static_cast<size_t>(node)] -
					r_snapshot.hydro_elevation[static_cast<size_t>(node)];
			candidate.max_depth = std::max(candidate.max_depth, depression_depth);
			accumulation_sum += r_snapshot.flow_accumulation[static_cast<size_t>(node)];
			const int32_t node_x = node % r_snapshot.grid_width;
			const int32_t node_y = node / r_snapshot.grid_width;
			auto consider_outlet = [&](int32_t p_downstream, uint8_t p_direction) {
				if (p_downstream < 0 ||
						p_downstream >= node_count ||
						component_id[static_cast<size_t>(p_downstream)] == component_index ||
						p_downstream >= static_cast<int32_t>(r_snapshot.mountain_exclusion_mask.size()) ||
						r_snapshot.mountain_exclusion_mask[static_cast<size_t>(p_downstream)] != 0U) {
					return;
				}
				const bool better_outlet = candidate.outlet_node < 0 ||
						r_snapshot.filled_elevation[static_cast<size_t>(node)] <
								r_snapshot.filled_elevation[static_cast<size_t>(candidate.outlet_node)] ||
						(r_snapshot.filled_elevation[static_cast<size_t>(node)] ==
										r_snapshot.filled_elevation[static_cast<size_t>(candidate.outlet_node)] &&
								r_snapshot.flow_accumulation[static_cast<size_t>(node)] >
										r_snapshot.flow_accumulation[static_cast<size_t>(candidate.outlet_node)]);
				if (better_outlet) {
					candidate.outlet_node = node;
					candidate.outlet_downstream_node = p_downstream;
					candidate.outlet_flow_dir = p_direction;
				}
			};
			const int32_t downstream = resolve_downstream_index(r_snapshot, node);
			const uint8_t natural_direction = node < static_cast<int32_t>(r_snapshot.flow_dir.size()) ?
					r_snapshot.flow_dir[static_cast<size_t>(node)] :
					FLOW_DIR_NONE;
			consider_outlet(downstream, natural_direction);
			for (uint8_t direction = 0; direction < 8U; ++direction) {
				const int32_t nx = static_cast<int32_t>(positive_mod(node_x + FLOW_DX[direction], r_snapshot.grid_width));
				const int32_t ny = node_y + FLOW_DY[direction];
				if (ny < 0 || ny >= r_snapshot.grid_height) {
					continue;
				}
				consider_outlet(r_snapshot.index(nx, ny), direction);
			}
		}
		if (candidate.outlet_node < 0 || candidate.max_depth <= 0.0f) {
			candidates.push_back(candidate);
			continue;
		}
		candidate.average_accumulation = accumulation_sum / std::max<float>(1.0f, static_cast<float>(candidate.nodes.size()));
		candidate.score = candidate.max_depth * std::sqrt(static_cast<float>(candidate.nodes.size())) +
				std::log1p(candidate.average_accumulation) * 0.05f;
		const int64_t lake_seed_version = r_snapshot.world_version >= WORLD_ORGANIC_COASTLINE_VERSION ?
				WORLD_BASIN_CONTOUR_LAKE_VERSION :
				r_snapshot.world_version;
		candidate.stable_key = splitmix64(
			mix_seed(r_snapshot.seed, lake_seed_version, SEED_SALT_LAKE_SELECTION) ^
			static_cast<uint64_t>(candidate.outlet_node) ^
			(static_cast<uint64_t>(candidate.nodes.size()) << 32U)
		);
		candidates.push_back(candidate);
	}

	std::vector<int32_t> ranked;
	for (int32_t index = 0; index < static_cast<int32_t>(candidates.size()); ++index) {
		if (candidates[static_cast<size_t>(index)].outlet_node >= 0 &&
				candidates[static_cast<size_t>(index)].score > 0.0f) {
			ranked.push_back(index);
		}
	}
	if (ranked.empty()) {
		return;
	}
	std::sort(ranked.begin(), ranked.end(), [&](int32_t p_a, int32_t p_b) {
		const LakeBasinCandidate &a = candidates[static_cast<size_t>(p_a)];
		const LakeBasinCandidate &b = candidates[static_cast<size_t>(p_b)];
		if (a.score == b.score) {
			return a.outlet_node < b.outlet_node;
		}
		return a.score > b.score;
	});

	const int32_t max_lake_count = clamp_value(
		static_cast<int32_t>(std::ceil(chance * static_cast<float>(node_count) / 4096.0f)),
		1,
		48
	);
	r_snapshot.lake_outlet_node_by_id.assign(static_cast<size_t>(max_lake_count + 1), -1);
	if (uses_hydrology_visual_v3(r_snapshot.world_version)) {
		r_snapshot.lake_water_level_per_id.assign(
			static_cast<size_t>(max_lake_count + 1),
			std::numeric_limits<float>::quiet_NaN()
		);
	}
	std::vector<int32_t> selected;
	for (const int32_t candidate_index : ranked) {
		if (static_cast<int32_t>(selected.size()) >= max_lake_count) {
			break;
		}
		const LakeBasinCandidate &candidate = candidates[static_cast<size_t>(candidate_index)];
		if (hash_to_unit_float(candidate.stable_key) <= chance || selected.empty()) {
			selected.push_back(candidate_index);
		}
	}

	int32_t next_lake_id = 1;
	for (const int32_t candidate_index : selected) {
		const LakeBasinCandidate &candidate = candidates[static_cast<size_t>(candidate_index)];
		const float inv_max_depth = candidate.max_depth > 0.000001f ? 1.0f / candidate.max_depth : 0.0f;
		if (uses_hydrology_visual_v3(r_snapshot.world_version) &&
				candidate.outlet_node >= 0 &&
				candidate.outlet_node < static_cast<int32_t>(r_snapshot.filled_elevation.size())) {
			if (next_lake_id >= static_cast<int32_t>(r_snapshot.lake_water_level_per_id.size())) {
				r_snapshot.lake_water_level_per_id.resize(
					static_cast<size_t>(next_lake_id + 1),
					std::numeric_limits<float>::quiet_NaN()
				);
			}
			r_snapshot.lake_water_level_per_id[static_cast<size_t>(next_lake_id)] =
					r_snapshot.filled_elevation[static_cast<size_t>(candidate.outlet_node)];
		}
		for (const int32_t node : candidate.nodes) {
			r_snapshot.lake_id[static_cast<size_t>(node)] = next_lake_id;
			if (r_snapshot.world_version >= WORLD_BASIN_CONTOUR_LAKE_VERSION &&
					node >= 0 && node < static_cast<int32_t>(r_snapshot.lake_depth_ratio.size())) {
				const float depression_depth = std::max(
					0.0f,
					r_snapshot.filled_elevation[static_cast<size_t>(node)] -
							r_snapshot.hydro_elevation[static_cast<size_t>(node)]
				);
				r_snapshot.lake_depth_ratio[static_cast<size_t>(node)] = saturate(depression_depth * inv_max_depth);
				r_snapshot.basin_contour_lake_node_count += 1;
			}
		}
		if (r_snapshot.world_version >= WORLD_BASIN_CONTOUR_LAKE_VERSION &&
				candidate.outlet_node >= 0 &&
				candidate.outlet_node < node_count) {
			if (candidate.outlet_flow_dir < 8U &&
					candidate.outlet_node < static_cast<int32_t>(r_snapshot.flow_dir.size())) {
				r_snapshot.flow_dir[static_cast<size_t>(candidate.outlet_node)] = candidate.outlet_flow_dir;
			}
			if (next_lake_id >= static_cast<int32_t>(r_snapshot.lake_outlet_node_by_id.size())) {
				r_snapshot.lake_outlet_node_by_id.resize(static_cast<size_t>(next_lake_id + 1), -1);
			}
			if (uses_hydrology_visual_v3(r_snapshot.world_version) &&
					next_lake_id >= static_cast<int32_t>(r_snapshot.lake_water_level_per_id.size())) {
				r_snapshot.lake_water_level_per_id.resize(
					static_cast<size_t>(next_lake_id + 1),
					std::numeric_limits<float>::quiet_NaN()
				);
			}
			r_snapshot.lake_outlet_node_by_id[static_cast<size_t>(next_lake_id)] = candidate.outlet_node;
			if (candidate.outlet_node < static_cast<int32_t>(r_snapshot.lake_spill_node_mask.size())) {
				r_snapshot.lake_spill_node_mask[static_cast<size_t>(candidate.outlet_node)] = 1U;
			}
			r_snapshot.lake_spill_point_count += 1;
			const int32_t downstream = resolve_downstream_index(r_snapshot, candidate.outlet_node);
			if (downstream >= 0 &&
					downstream < node_count &&
					r_snapshot.lake_id[static_cast<size_t>(downstream)] != next_lake_id) {
				r_snapshot.lake_outlet_connection_count += 1;
			}
		}
		next_lake_id += 1;
	}
}

uint8_t resolve_stream_order_bucket(float p_accumulation) {
	const int32_t bucket = static_cast<int32_t>(std::floor(std::log2(std::max(1.0f, p_accumulation)))) + 1;
	return static_cast<uint8_t>(clamp_value(bucket, 1, 255));
}

float resolve_river_accumulation_threshold(const Snapshot &p_snapshot, const RiverSettings &p_river_settings) {
	std::vector<float> candidates;
	candidates.reserve(static_cast<size_t>(p_snapshot.grid_width * p_snapshot.grid_height));
	for (int32_t index = 0; index < p_snapshot.grid_width * p_snapshot.grid_height; ++index) {
		if (p_snapshot.ocean_sink_mask[static_cast<size_t>(index)] != 0U ||
				p_snapshot.mountain_exclusion_mask[static_cast<size_t>(index)] != 0U) {
			continue;
		}
		const float accumulation = p_snapshot.flow_accumulation[static_cast<size_t>(index)];
		if (accumulation > 0.0f) {
			candidates.push_back(accumulation);
		}
	}
	if (candidates.empty()) {
		return std::numeric_limits<float>::infinity();
	}
	std::sort(candidates.begin(), candidates.end(), std::greater<float>());
	int32_t target_count = 0;
	if (p_river_settings.target_trunk_count > 0) {
		target_count = p_river_settings.target_trunk_count * std::max<int32_t>(4, p_snapshot.grid_height / 4);
	} else {
		const float river_fraction = 0.006f + saturate(p_river_settings.density) * 0.02f;
		target_count = static_cast<int32_t>(std::ceil(static_cast<float>(candidates.size()) * river_fraction));
	}
	target_count = clamp_value(target_count, 2, static_cast<int32_t>(candidates.size()));
	const float percentile_threshold = candidates[static_cast<size_t>(target_count - 1)];
	const float min_threshold = std::max(4.0f, static_cast<float>(p_snapshot.grid_height) * 0.25f);
	return std::max(percentile_threshold, min_threshold);
}

void build_river_network(Snapshot &r_snapshot, const RiverSettings &p_river_settings) {
	const int32_t node_count = r_snapshot.grid_width * r_snapshot.grid_height;
	r_snapshot.river_node_mask.assign(static_cast<size_t>(node_count), 0U);
	r_snapshot.river_segment_id.assign(static_cast<size_t>(node_count), 0);
	r_snapshot.river_stream_order.assign(static_cast<size_t>(node_count), 0U);
	r_snapshot.river_discharge.assign(static_cast<size_t>(node_count), 0.0f);
	r_snapshot.river_segment_ranges.clear();
	r_snapshot.river_path_node_indices.clear();
	r_snapshot.river_segment_count = 0;
	r_snapshot.river_source_count = 0;

	const float threshold = resolve_river_accumulation_threshold(r_snapshot, p_river_settings);
	int32_t strongest_index = -1;
	float strongest_accumulation = -1.0f;
	for (int32_t index = 0; index < node_count; ++index) {
		if (r_snapshot.ocean_sink_mask[static_cast<size_t>(index)] != 0U ||
				r_snapshot.mountain_exclusion_mask[static_cast<size_t>(index)] != 0U) {
			continue;
		}
		const float accumulation = r_snapshot.flow_accumulation[static_cast<size_t>(index)];
		if (accumulation > strongest_accumulation) {
			strongest_accumulation = accumulation;
			strongest_index = index;
		}
		if (accumulation < threshold) {
			continue;
		}
		r_snapshot.river_node_mask[static_cast<size_t>(index)] = 1U;
		r_snapshot.river_stream_order[static_cast<size_t>(index)] = resolve_stream_order_bucket(accumulation);
		r_snapshot.river_discharge[static_cast<size_t>(index)] = accumulation;
	}

	if (strongest_index >= 0 && strongest_accumulation > 0.0f) {
		r_snapshot.river_node_mask[static_cast<size_t>(strongest_index)] = 1U;
		r_snapshot.river_stream_order[static_cast<size_t>(strongest_index)] = resolve_stream_order_bucket(strongest_accumulation);
		r_snapshot.river_discharge[static_cast<size_t>(strongest_index)] = strongest_accumulation;
	}

	int32_t max_lake_id = 0;
	for (const int32_t lake_id : r_snapshot.lake_id) {
		max_lake_id = std::max(max_lake_id, lake_id);
	}
	if (max_lake_id > 0) {
		std::vector<int32_t> outlet_by_lake(static_cast<size_t>(max_lake_id + 1), -1);
		for (int32_t lake_id = 1; lake_id <= max_lake_id; ++lake_id) {
			if (lake_id >= static_cast<int32_t>(r_snapshot.lake_outlet_node_by_id.size())) {
				continue;
			}
			const int32_t outlet_node = r_snapshot.lake_outlet_node_by_id[static_cast<size_t>(lake_id)];
			if (outlet_node < 0 || outlet_node >= node_count ||
					r_snapshot.lake_id[static_cast<size_t>(outlet_node)] != lake_id) {
				continue;
			}
			const int32_t downstream = resolve_downstream_index(r_snapshot, outlet_node);
			if (downstream < 0 || downstream >= node_count ||
					r_snapshot.lake_id[static_cast<size_t>(downstream)] == lake_id) {
				continue;
			}
			outlet_by_lake[static_cast<size_t>(lake_id)] = outlet_node;
		}
		for (int32_t index = 0; index < node_count; ++index) {
			const int32_t lake_id = r_snapshot.lake_id[static_cast<size_t>(index)];
			if (lake_id <= 0) {
				continue;
			}
			if (outlet_by_lake[static_cast<size_t>(lake_id)] >= 0) {
				continue;
			}
			const int32_t downstream = resolve_downstream_index(r_snapshot, index);
			if (downstream < 0 || r_snapshot.lake_id[static_cast<size_t>(downstream)] == lake_id) {
				continue;
			}
			const int32_t current_outlet = outlet_by_lake[static_cast<size_t>(lake_id)];
			if (current_outlet < 0 ||
					r_snapshot.flow_accumulation[static_cast<size_t>(index)] >
							r_snapshot.flow_accumulation[static_cast<size_t>(current_outlet)]) {
				outlet_by_lake[static_cast<size_t>(lake_id)] = index;
			}
		}
		for (int32_t lake_id = 1; lake_id <= max_lake_id; ++lake_id) {
			int32_t current = outlet_by_lake[static_cast<size_t>(lake_id)];
			int32_t guard = 0;
			while (current >= 0 && guard++ < node_count) {
				if (r_snapshot.mountain_exclusion_mask[static_cast<size_t>(current)] != 0U) {
					break;
				}
				r_snapshot.river_node_mask[static_cast<size_t>(current)] = 1U;
				r_snapshot.river_stream_order[static_cast<size_t>(current)] = std::max<uint8_t>(
					r_snapshot.river_stream_order[static_cast<size_t>(current)],
					resolve_stream_order_bucket(r_snapshot.flow_accumulation[static_cast<size_t>(current)])
				);
				r_snapshot.river_discharge[static_cast<size_t>(current)] = std::max(
					r_snapshot.river_discharge[static_cast<size_t>(current)],
					r_snapshot.flow_accumulation[static_cast<size_t>(current)]
				);
				if (r_snapshot.ocean_sink_mask[static_cast<size_t>(current)] != 0U) {
					break;
				}
				const int32_t downstream = resolve_downstream_index(r_snapshot, current);
				if (downstream < 0) {
					break;
				}
				if (r_snapshot.lake_id[static_cast<size_t>(current)] == 0 &&
						r_snapshot.river_node_mask[static_cast<size_t>(downstream)] != 0U) {
					break;
				}
				current = downstream;
			}
		}
	}

	std::vector<int32_t> upstream_selected_count(static_cast<size_t>(node_count), 0);
	for (int32_t index = 0; index < node_count; ++index) {
		if (r_snapshot.river_node_mask[static_cast<size_t>(index)] == 0U ||
				r_snapshot.ocean_sink_mask[static_cast<size_t>(index)] != 0U) {
			continue;
		}
		const int32_t downstream = resolve_downstream_index(r_snapshot, index);
		if (downstream < 0) {
			continue;
		}
		if (r_snapshot.ocean_sink_mask[static_cast<size_t>(downstream)] != 0U) {
			r_snapshot.river_node_mask[static_cast<size_t>(downstream)] = 1U;
			r_snapshot.river_stream_order[static_cast<size_t>(downstream)] = std::max<uint8_t>(
				r_snapshot.river_stream_order[static_cast<size_t>(downstream)],
				r_snapshot.river_stream_order[static_cast<size_t>(index)]
			);
			r_snapshot.river_discharge[static_cast<size_t>(downstream)] = std::max(
				r_snapshot.river_discharge[static_cast<size_t>(downstream)],
				r_snapshot.flow_accumulation[static_cast<size_t>(index)]
			);
		}
		if (r_snapshot.river_node_mask[static_cast<size_t>(downstream)] != 0U) {
			upstream_selected_count[static_cast<size_t>(downstream)] += 1;
		}
	}

	std::vector<int32_t> sources;
	for (int32_t index = 0; index < node_count; ++index) {
		if (r_snapshot.river_node_mask[static_cast<size_t>(index)] == 0U ||
				r_snapshot.ocean_sink_mask[static_cast<size_t>(index)] != 0U) {
			continue;
		}
		if (upstream_selected_count[static_cast<size_t>(index)] == 0) {
			sources.push_back(index);
		}
	}
	std::sort(sources.begin(), sources.end(), [&](int32_t p_a, int32_t p_b) {
		const float accum_a = r_snapshot.flow_accumulation[static_cast<size_t>(p_a)];
		const float accum_b = r_snapshot.flow_accumulation[static_cast<size_t>(p_b)];
		if (accum_a == accum_b) {
			return p_a < p_b;
		}
		return accum_a > accum_b;
	});
	r_snapshot.river_source_count = static_cast<int32_t>(sources.size());

	int32_t next_segment_id = 1;
	for (const int32_t source : sources) {
		std::vector<int32_t> path;
		path.reserve(64);
		int32_t current = source;
		int32_t guard = 0;
		while (current >= 0 && guard++ < node_count) {
			if (r_snapshot.river_node_mask[static_cast<size_t>(current)] == 0U) {
				break;
			}
			path.push_back(current);
			const int32_t downstream = resolve_downstream_index(r_snapshot, current);
			if (downstream < 0) {
				break;
			}
			if (r_snapshot.river_node_mask[static_cast<size_t>(downstream)] == 0U) {
				break;
			}
			if (r_snapshot.river_segment_id[static_cast<size_t>(downstream)] > 0) {
				path.push_back(downstream);
				break;
			}
			current = downstream;
		}
		if (path.size() < 2) {
			continue;
		}

		const int32_t offset = static_cast<int32_t>(r_snapshot.river_path_node_indices.size());
		uint8_t max_order = 1U;
		for (const int32_t node : path) {
			r_snapshot.river_path_node_indices.push_back(node);
			max_order = std::max(max_order, r_snapshot.river_stream_order[static_cast<size_t>(node)]);
			if (r_snapshot.river_segment_id[static_cast<size_t>(node)] == 0) {
				r_snapshot.river_segment_id[static_cast<size_t>(node)] = next_segment_id;
			}
		}
		r_snapshot.river_segment_ranges.push_back(next_segment_id);
		r_snapshot.river_segment_ranges.push_back(offset);
		r_snapshot.river_segment_ranges.push_back(static_cast<int32_t>(path.size()));
		r_snapshot.river_segment_ranges.push_back(path.front());
		r_snapshot.river_segment_ranges.push_back(path.back());
		r_snapshot.river_segment_ranges.push_back(static_cast<int32_t>(max_order));
		next_segment_id += 1;
	}
	r_snapshot.river_segment_count = static_cast<int32_t>(r_snapshot.river_segment_ranges.size() / RIVER_SEGMENT_RECORD_SIZE);
}

} // namespace

int32_t Snapshot::index(int32_t p_x, int32_t p_y) const {
	return p_y * grid_width + p_x;
}

Vector2i Snapshot::node_to_tile_center(int32_t p_x, int32_t p_y) const {
	const int64_t x = std::min<int64_t>(width_tiles - 1, static_cast<int64_t>(p_x) * cell_size_tiles + cell_size_tiles / 2);
	const int64_t y = std::min<int64_t>(height_tiles - 1, static_cast<int64_t>(p_y) * cell_size_tiles + cell_size_tiles / 2);
	return Vector2i(static_cast<int32_t>(x), static_cast<int32_t>(y));
}

uint64_t make_signature(
	int64_t p_seed,
	int64_t p_world_version,
	uint64_t p_foundation_signature,
	const FoundationSettings &p_foundation_settings,
	const RiverSettings &p_river_settings
) {
	uint64_t signature = splitmix64(static_cast<uint64_t>(p_seed));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_world_version) * 0x9e3779b185ebca87ULL);
	signature = splitmix64(signature ^ p_foundation_signature);
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.width_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.height_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.ocean_band_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.burning_band_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.pole_orientation));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround((p_foundation_settings.slope_bias + 1.0f) * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_river_settings.enabled ? 1U : 0U));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_river_settings.target_trunk_count));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_river_settings.density * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_river_settings.width_scale * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_river_settings.lake_chance * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_river_settings.meander_strength * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_river_settings.braid_chance * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_river_settings.shallow_crossing_frequency * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_river_settings.mountain_clearance_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_river_settings.delta_scale * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_river_settings.north_drainage_bias * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_river_settings.hydrology_cell_size_tiles));
	return signature;
}

std::unique_ptr<Snapshot> build_snapshot(
	int64_t p_seed,
	int64_t p_world_version,
	const world_prepass::Snapshot &p_foundation_snapshot,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const FoundationSettings &p_foundation_settings,
	const RiverSettings &p_river_settings
) {
	auto started_at = std::chrono::high_resolution_clock::now();
	std::unique_ptr<Snapshot> snapshot = std::make_unique<Snapshot>();
	snapshot->valid = p_foundation_snapshot.valid && p_river_settings.enabled;
	snapshot->seed = p_seed;
	snapshot->world_version = p_world_version;
	snapshot->cell_size_tiles = clamp_value(p_river_settings.hydrology_cell_size_tiles, 8, 64);
	snapshot->width_tiles = p_foundation_snapshot.width_tiles;
	snapshot->height_tiles = p_foundation_snapshot.height_tiles;
	snapshot->ocean_band_tiles = p_foundation_snapshot.ocean_band_tiles;
	snapshot->river_settings = p_river_settings;
	snapshot->signature = make_signature(
		p_seed,
		p_world_version,
		p_foundation_snapshot.signature,
		p_foundation_settings,
		p_river_settings
	);

	if (!snapshot->valid) {
		return snapshot;
	}

	snapshot->grid_width = std::max<int32_t>(1, static_cast<int32_t>((snapshot->width_tiles + snapshot->cell_size_tiles - 1) / snapshot->cell_size_tiles));
	snapshot->grid_height = std::max<int32_t>(1, static_cast<int32_t>((snapshot->height_tiles + snapshot->cell_size_tiles - 1) / snapshot->cell_size_tiles));
	const int32_t node_count = snapshot->grid_width * snapshot->grid_height;
	snapshot->hydro_elevation.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->filled_elevation.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->flow_dir.assign(static_cast<size_t>(node_count), FLOW_DIR_NONE);
	snapshot->flow_accumulation.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->watershed_id.assign(static_cast<size_t>(node_count), 0);
	snapshot->lake_id.assign(static_cast<size_t>(node_count), 0);
	snapshot->lake_depth_ratio.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->lake_spill_node_mask.assign(static_cast<size_t>(node_count), 0U);
	snapshot->oxbow_lake_node_mask.assign(static_cast<size_t>(node_count), 0U);
	snapshot->ocean_sink_mask.assign(static_cast<size_t>(node_count), 0U);
	snapshot->ocean_coast_distance_tiles.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->ocean_shelf_depth_ratio.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->ocean_river_mouth_influence.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->mountain_exclusion_mask.assign(static_cast<size_t>(node_count), 0U);
	snapshot->floodplain_potential.assign(static_cast<size_t>(node_count), 0.0f);

	const int64_t coastline_seed_version = p_world_version >= WORLD_ORGANIC_COASTLINE_VERSION ?
			WORLD_BASIN_CONTOUR_LAKE_VERSION :
			p_world_version;
	FastNoiseLite coastline_noise = make_noise(mix_seed(p_seed, coastline_seed_version, SEED_SALT_COASTLINE), 1.0f / 768.0f, 3);
	for (int32_t y = 0; y < snapshot->grid_height; ++y) {
		for (int32_t x = 0; x < snapshot->grid_width; ++x) {
			const int32_t index = snapshot->index(x, y);
			const Vector2i center = snapshot->node_to_tile_center(x, y);
			const int32_t foundation_index = sample_foundation_index(p_foundation_snapshot, center.x, center.y);
			const float y_t = snapshot->height_tiles <= 1 ?
					0.0f :
					static_cast<float>(center.y) / static_cast<float>(snapshot->height_tiles - 1);
			const float coastline_noise_value = (sample_cylindrical_noise(
														 coastline_noise,
														 static_cast<float>(center.x),
														 0.0f,
														 static_cast<float>(snapshot->width_tiles)
												 ) +
												 1.0f) *
					0.5f;
			const float coastline_extra = (coastline_noise_value - 0.5f) * std::max<float>(16.0f, static_cast<float>(snapshot->ocean_band_tiles) * 0.65f);
			const float coastline_y = std::max<float>(static_cast<float>(snapshot->cell_size_tiles), static_cast<float>(snapshot->ocean_band_tiles) + coastline_extra);
			const float coast_distance_tiles = coastline_y - static_cast<float>(center.y);
			const bool is_ocean = coast_distance_tiles >= 0.0f || y == 0;
			const float base_hydro = p_foundation_snapshot.hydro_height[static_cast<size_t>(foundation_index)];
			const float north_bias = y_t * p_river_settings.north_drainage_bias * 0.34f;
			const float mountain_cost =
					p_foundation_snapshot.coarse_wall_density[static_cast<size_t>(foundation_index)] * 1.2f +
					p_foundation_snapshot.coarse_foot_density[static_cast<size_t>(foundation_index)] * 0.65f;
			snapshot->ocean_sink_mask[static_cast<size_t>(index)] = is_ocean ? 1U : 0U;
			snapshot->ocean_coast_distance_tiles[static_cast<size_t>(index)] = coast_distance_tiles;
			snapshot->hydro_elevation[static_cast<size_t>(index)] = saturate(base_hydro + north_bias) + mountain_cost;
		}
	}
	refresh_ocean_shelf_metrics(*snapshot);

	build_mountain_clearance(*snapshot, p_foundation_snapshot, p_river_settings.mountain_clearance_tiles);
	for (int32_t index = 0; index < node_count; ++index) {
		if (snapshot->mountain_exclusion_mask[static_cast<size_t>(index)] != 0U) {
			snapshot->hydro_elevation[static_cast<size_t>(index)] += 2.0f;
		}
	}
	solve_priority_flood(*snapshot);
	select_lake_basins(*snapshot, p_river_settings, p_foundation_settings, p_mountain_evaluator);

	float max_accumulation = 1.0f;
	for (float value : snapshot->flow_accumulation) {
		max_accumulation = std::max(max_accumulation, value);
	}
	const float max_log = std::max(1.0f, std::log1p(max_accumulation));
	for (int32_t y = 0; y < snapshot->grid_height; ++y) {
		for (int32_t x = 0; x < snapshot->grid_width; ++x) {
			const int32_t index = snapshot->index(x, y);
			if (snapshot->ocean_sink_mask[static_cast<size_t>(index)] != 0U ||
					snapshot->mountain_exclusion_mask[static_cast<size_t>(index)] != 0U) {
				continue;
			}
			const Vector2i center = snapshot->node_to_tile_center(x, y);
			const int32_t foundation_index = sample_foundation_index(p_foundation_snapshot, center.x, center.y);
			const float valley = saturate(1.0f -
					p_foundation_snapshot.coarse_wall_density[static_cast<size_t>(foundation_index)] -
					p_foundation_snapshot.coarse_foot_density[static_cast<size_t>(foundation_index)] * 0.5f);
			const float accum_t = std::log1p(snapshot->flow_accumulation[static_cast<size_t>(index)]) / max_log;
			snapshot->floodplain_potential[static_cast<size_t>(index)] = saturate(accum_t * valley);
		}
	}
	build_river_network(*snapshot, p_river_settings);
	build_refined_river_geometry(*snapshot);
	detect_oxbow_candidates(*snapshot);
	apply_ocean_river_mouth_influence(*snapshot);

	auto finished_at = std::chrono::high_resolution_clock::now();
	snapshot->compute_time_ms = std::chrono::duration<double, std::milli>(finished_at - started_at).count();
	return snapshot;
}

Dictionary make_build_result(const Snapshot &p_snapshot, bool p_cache_hit) {
	Dictionary result;
	result["success"] = p_snapshot.valid;
	result["cache_hit"] = p_cache_hit;
	result["grid_width"] = p_snapshot.grid_width;
	result["grid_height"] = p_snapshot.grid_height;
	result["cell_size_tiles"] = p_snapshot.cell_size_tiles;
	result["signature"] = static_cast<int64_t>(p_snapshot.signature & 0x7fffffffffffffffULL);
	result["compute_time_ms"] = p_snapshot.compute_time_ms;
	result["river_segment_count"] = p_snapshot.river_segment_count;
	result["river_source_count"] = p_snapshot.river_source_count;
	result["refined_river_edge_count"] = static_cast<int32_t>(p_snapshot.refined_river_edges.size());
	result["curvature_refined_river_edge_count"] = p_snapshot.refined_river_curved_edge_count;
	result["confluence_refined_river_edge_count"] = p_snapshot.refined_river_confluence_edge_count;
	result["y_confluence_zone_count"] = p_snapshot.refined_river_y_confluence_zone_count;
	result["y_confluence_refined_river_edge_count"] = p_snapshot.refined_river_y_confluence_edge_count;
	result["braid_loop_candidate_count"] = p_snapshot.refined_river_braid_loop_candidate_count;
	result["braid_loop_refined_river_edge_count"] = p_snapshot.refined_river_braid_loop_edge_count;
	result["basin_contour_lake_node_count"] = p_snapshot.basin_contour_lake_node_count;
	result["lake_spill_point_count"] = p_snapshot.lake_spill_point_count;
	result["lake_outlet_connection_count"] = p_snapshot.lake_outlet_connection_count;
	result["oxbow_candidate_count"] = p_snapshot.oxbow_candidate_count;
	result["oxbow_lake_node_count"] = p_snapshot.oxbow_lake_node_count;
	result["ocean_coastline_node_count"] = p_snapshot.ocean_coastline_node_count;
	result["ocean_shallow_shelf_node_count"] = p_snapshot.ocean_shallow_shelf_node_count;
	result["ocean_river_mouth_node_count"] = p_snapshot.ocean_river_mouth_node_count;
	result["river_spatial_index_cell_count"] = p_snapshot.river_spatial_index_width * p_snapshot.river_spatial_index_height;
	return result;
}

Dictionary make_debug_snapshot(const Snapshot &p_snapshot, int64_t p_layer_mask, int64_t p_downscale_factor) {
	Dictionary result;
	if (!p_snapshot.valid) {
		return result;
	}
	result["grid_width"] = p_snapshot.grid_width;
	result["grid_height"] = p_snapshot.grid_height;
	result["cell_size_tiles"] = p_snapshot.cell_size_tiles;
	result["world_width_tiles"] = p_snapshot.width_tiles;
	result["world_height_tiles"] = p_snapshot.height_tiles;
	result["ocean_band_tiles"] = p_snapshot.ocean_band_tiles;
	result["seed"] = p_snapshot.seed;
	result["world_version"] = p_snapshot.world_version;
	result["signature"] = static_cast<int64_t>(p_snapshot.signature & 0x7fffffffffffffffULL);
	result["compute_time_ms"] = p_snapshot.compute_time_ms;
	result["cycle_free"] = true;
	result["layer_mask"] = p_layer_mask;
	result["downscale_factor"] = std::max<int64_t>(1, p_downscale_factor);
	result["hydro_elevation"] = make_float_array(p_snapshot.hydro_elevation);
	result["filled_elevation"] = make_float_array(p_snapshot.filled_elevation);
	result["flow_dir"] = make_byte_array(p_snapshot.flow_dir);
	result["flow_accumulation"] = make_float_array(p_snapshot.flow_accumulation);
	result["watershed_id"] = make_int_array(p_snapshot.watershed_id);
	result["lake_id"] = make_int_array(p_snapshot.lake_id);
	result["lake_depth_ratio"] = make_float_array(p_snapshot.lake_depth_ratio);
	result["lake_spill_node_mask"] = make_byte_array(p_snapshot.lake_spill_node_mask);
	result["lake_outlet_node_by_id"] = make_int_array(p_snapshot.lake_outlet_node_by_id);
	result["oxbow_lake_node_mask"] = make_byte_array(p_snapshot.oxbow_lake_node_mask);
	result["ocean_sink_mask"] = make_byte_array(p_snapshot.ocean_sink_mask);
	result["ocean_coast_distance_tiles"] = make_float_array(p_snapshot.ocean_coast_distance_tiles);
	result["ocean_shelf_depth_ratio"] = make_float_array(p_snapshot.ocean_shelf_depth_ratio);
	result["ocean_river_mouth_influence"] = make_float_array(p_snapshot.ocean_river_mouth_influence);
	result["mountain_exclusion_mask"] = make_byte_array(p_snapshot.mountain_exclusion_mask);
	result["floodplain_potential"] = make_float_array(p_snapshot.floodplain_potential);
	result["river_segment_count"] = p_snapshot.river_segment_count;
	result["river_source_count"] = p_snapshot.river_source_count;
	result["river_node_mask"] = make_byte_array(p_snapshot.river_node_mask);
	result["river_segment_id"] = make_int_array(p_snapshot.river_segment_id);
	result["river_stream_order"] = make_byte_array(p_snapshot.river_stream_order);
	result["river_discharge"] = make_float_array(p_snapshot.river_discharge);
	result["river_segment_ranges"] = make_int_array(p_snapshot.river_segment_ranges);
	result["river_path_node_indices"] = make_int_array(p_snapshot.river_path_node_indices);
	result["refined_river_edge_count"] = static_cast<int32_t>(p_snapshot.refined_river_edges.size());
	result["refined_river_edge_points"] = make_refined_edge_points_array(p_snapshot.refined_river_edges);
	result["refined_river_edge_tangents"] = make_refined_edge_tangents_array(p_snapshot.refined_river_edges);
	result["refined_river_edge_shape_metrics"] = make_refined_edge_shape_metrics_array(p_snapshot.refined_river_edges);
	result["refined_river_edge_metadata"] = make_refined_edge_metadata_array(p_snapshot.refined_river_edges);
	result["curvature_refined_river_edge_count"] = p_snapshot.refined_river_curved_edge_count;
	result["confluence_refined_river_edge_count"] = p_snapshot.refined_river_confluence_edge_count;
	result["y_confluence_zone_count"] = p_snapshot.refined_river_y_confluence_zone_count;
	result["y_confluence_refined_river_edge_count"] = p_snapshot.refined_river_y_confluence_edge_count;
	result["braid_loop_candidate_count"] = p_snapshot.refined_river_braid_loop_candidate_count;
	result["braid_loop_refined_river_edge_count"] = p_snapshot.refined_river_braid_loop_edge_count;
	result["basin_contour_lake_node_count"] = p_snapshot.basin_contour_lake_node_count;
	result["lake_spill_point_count"] = p_snapshot.lake_spill_point_count;
	result["lake_outlet_connection_count"] = p_snapshot.lake_outlet_connection_count;
	result["oxbow_candidate_count"] = p_snapshot.oxbow_candidate_count;
	result["oxbow_lake_node_count"] = p_snapshot.oxbow_lake_node_count;
	result["ocean_coastline_node_count"] = p_snapshot.ocean_coastline_node_count;
	result["ocean_shallow_shelf_node_count"] = p_snapshot.ocean_shallow_shelf_node_count;
	result["ocean_river_mouth_node_count"] = p_snapshot.ocean_river_mouth_node_count;
	result["river_spatial_index_cell_size_tiles"] = p_snapshot.river_spatial_index_cell_size_tiles;
	result["river_spatial_index_width"] = p_snapshot.river_spatial_index_width;
	result["river_spatial_index_height"] = p_snapshot.river_spatial_index_height;
	return result;
}

std::vector<RefinedRiverEdge> query_refined_river_edges(
	const Snapshot &p_snapshot,
	int64_t p_min_x,
	int64_t p_min_y,
	int64_t p_max_x,
	int64_t p_max_y,
	float p_padding_tiles
) {
	std::vector<RefinedRiverEdge> edges;
	if (!p_snapshot.valid || p_snapshot.refined_river_edges.empty() ||
			p_snapshot.river_spatial_index_width <= 0 || p_snapshot.river_spatial_index_height <= 0 ||
			p_snapshot.river_spatial_index_offsets.empty() || p_snapshot.river_spatial_index_edge_indices.empty()) {
		return edges;
	}
	const int32_t cell_size = std::max(1, p_snapshot.river_spatial_index_cell_size_tiles);
	const int64_t min_x = p_min_x - static_cast<int64_t>(std::ceil(p_padding_tiles));
	const int64_t max_x = p_max_x + static_cast<int64_t>(std::ceil(p_padding_tiles));
	const int64_t min_y = std::max<int64_t>(0, p_min_y - static_cast<int64_t>(std::ceil(p_padding_tiles)));
	const int64_t max_y = std::min<int64_t>(
		std::max<int64_t>(0, p_snapshot.height_tiles - 1),
		p_max_y + static_cast<int64_t>(std::ceil(p_padding_tiles))
	);
	if (max_y < min_y) {
		return edges;
	}
	const int64_t first_bin_x = static_cast<int64_t>(std::floor(static_cast<double>(min_x) / static_cast<double>(cell_size)));
	const int64_t last_bin_x = static_cast<int64_t>(std::floor(static_cast<double>(max_x) / static_cast<double>(cell_size)));
	const int32_t first_bin_y = clamp_value(
		static_cast<int32_t>(std::floor(static_cast<double>(min_y) / static_cast<double>(cell_size))),
		0,
		p_snapshot.river_spatial_index_height - 1
	);
	const int32_t last_bin_y = clamp_value(
		static_cast<int32_t>(std::floor(static_cast<double>(max_y) / static_cast<double>(cell_size))),
		0,
		p_snapshot.river_spatial_index_height - 1
	);
	std::unordered_set<int32_t> seen;
	for (int32_t bin_y = first_bin_y; bin_y <= last_bin_y; ++bin_y) {
		for (int64_t raw_bin_x = first_bin_x; raw_bin_x <= last_bin_x; ++raw_bin_x) {
			const int32_t bin_x = static_cast<int32_t>(positive_mod(raw_bin_x, p_snapshot.river_spatial_index_width));
			const int32_t bin_index = bin_y * p_snapshot.river_spatial_index_width + bin_x;
			if (bin_index < 0 || bin_index + 1 >= static_cast<int32_t>(p_snapshot.river_spatial_index_offsets.size())) {
				continue;
			}
			const int32_t begin = p_snapshot.river_spatial_index_offsets[static_cast<size_t>(bin_index)];
			const int32_t end = p_snapshot.river_spatial_index_offsets[static_cast<size_t>(bin_index + 1)];
			for (int32_t offset = begin; offset < end; ++offset) {
				if (offset < 0 || offset >= static_cast<int32_t>(p_snapshot.river_spatial_index_edge_indices.size())) {
					continue;
				}
				const int32_t edge_index = p_snapshot.river_spatial_index_edge_indices[static_cast<size_t>(offset)];
				if (edge_index < 0 || edge_index >= static_cast<int32_t>(p_snapshot.refined_river_edges.size()) ||
						seen.find(edge_index) != seen.end()) {
					continue;
				}
				seen.insert(edge_index);
				edges.push_back(p_snapshot.refined_river_edges[static_cast<size_t>(edge_index)]);
			}
		}
	}
	return edges;
}

Ref<Image> make_overview_image(const Snapshot &p_snapshot, int64_t p_layer_mask, int64_t p_pixels_per_cell) {
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0) {
		return Ref<Image>();
	}
	const int32_t pixels_per_cell = clamp_value(static_cast<int32_t>(p_pixels_per_cell), 1, 8);
	const int32_t image_width = p_snapshot.grid_width * pixels_per_cell;
	const int32_t image_height = p_snapshot.grid_height * pixels_per_cell;
	const bool transparent_water_overlay = (p_layer_mask & LAYER_MASK_TRANSPARENT_WATER_OVERLAY) != 0;
	const bool use_organic_river_overview =
			p_snapshot.world_version >= WORLD_ORGANIC_WATER_VERSION && pixels_per_cell > 1;
	const std::vector<OverviewRiverEdge> overview_river_edges = use_organic_river_overview ?
			(!p_snapshot.refined_river_edges.empty() ?
					build_overview_river_edges_from_refined(p_snapshot, pixels_per_cell) :
					build_overview_river_edges(p_snapshot, pixels_per_cell)) :
			std::vector<OverviewRiverEdge>();
	const float overview_width_pixels = static_cast<float>(std::max(1, image_width));
	PackedByteArray bytes;
	bytes.resize(image_width * image_height * 4);
	for (int32_t y = 0; y < image_height; ++y) {
		for (int32_t x = 0; x < image_width; ++x) {
			const int32_t node_x = clamp_value(x / pixels_per_cell, 0, p_snapshot.grid_width - 1);
			const int32_t node_y = clamp_value(y / pixels_per_cell, 0, p_snapshot.grid_height - 1);
			const int32_t index = p_snapshot.index(node_x, node_y);
			const int32_t offset = (y * image_width + x) * 4;
			const int32_t local_pixel_x = x % pixels_per_cell;
			const int32_t local_pixel_y = y % pixels_per_cell;
			const OceanOverviewSample ocean_sample = sample_ocean_overview_pixel(
				p_snapshot,
				node_x,
				node_y,
				local_pixel_x,
				local_pixel_y,
				pixels_per_cell
			);
			if (ocean_sample.is_ocean) {
				if (ocean_sample.is_shallow_shelf) {
					write_rgba(bytes, offset, 52, 116, 148, transparent_water_overlay ? 220 : 255);
				} else {
					write_rgba(bytes, offset, 38, 89, 128, transparent_water_overlay ? 230 : 255);
				}
				continue;
			}
			if (ocean_sample.is_shore) {
				write_rgba(bytes, offset, 58, 132, 152, transparent_water_overlay ? 190 : 255);
				continue;
			}
			if (p_snapshot.lake_id.size() == static_cast<size_t>(p_snapshot.grid_width * p_snapshot.grid_height) &&
					is_lake_overview_pixel(p_snapshot, node_x, node_y, local_pixel_x, local_pixel_y, pixels_per_cell)) {
				write_rgba(bytes, offset, 45, 126, 160, transparent_water_overlay ? 225 : 255);
				continue;
			}
			if (p_snapshot.mountain_exclusion_mask[static_cast<size_t>(index)] != 0U) {
				if (transparent_water_overlay) {
					write_rgba(bytes, offset, 0, 0, 0, 0);
				} else {
					write_rgba(bytes, offset, 138, 134, 122);
				}
				continue;
			}
			if (use_organic_river_overview && !overview_river_edges.empty()) {
				const OverviewRiverSample sample = sample_overview_river_edges(
					overview_river_edges,
					static_cast<float>(x) + 0.5f,
					static_cast<float>(y) + 0.5f,
					overview_width_pixels
				);
				const float order_f = std::max(1.0f, static_cast<float>(sample.stream_order));
				const float radius = std::max(
					0.62f,
					(0.34f + order_f * 0.085f) *
							std::max(0.25f, p_snapshot.river_settings.width_scale) *
							std::max(0.25f, sample.radius_scale)
				);
				if (sample.distance <= radius) {
					const uint8_t boost = static_cast<uint8_t>(std::min<int32_t>(70, static_cast<int32_t>(sample.stream_order) * 10));
					const uint8_t red = sample.braid_split ? 46U : 38U;
					write_rgba(bytes, offset, red, static_cast<uint8_t>(112 + boost), 190, transparent_water_overlay ? 240 : 255);
					continue;
				}
			}
			if ((!use_organic_river_overview || overview_river_edges.empty()) &&
					p_snapshot.river_node_mask.size() == static_cast<size_t>(p_snapshot.grid_width * p_snapshot.grid_height) &&
					p_snapshot.river_node_mask[static_cast<size_t>(index)] != 0U) {
				const uint8_t order = p_snapshot.river_stream_order.size() > static_cast<size_t>(index) ?
						p_snapshot.river_stream_order[static_cast<size_t>(index)] :
						1U;
				const uint8_t boost = static_cast<uint8_t>(std::min<int32_t>(70, static_cast<int32_t>(order) * 10));
				write_rgba(bytes, offset, 38, static_cast<uint8_t>(112 + boost), 190, transparent_water_overlay ? 240 : 255);
				continue;
			}
			if (transparent_water_overlay) {
				write_rgba(bytes, offset, 0, 0, 0, 0);
				continue;
			}
			float t = 0.0f;
			if ((p_layer_mask & LAYER_MASK_FLOW_ACCUMULATION) != 0) {
				t = saturate(std::log1p(p_snapshot.flow_accumulation[static_cast<size_t>(index)]) / 8.0f);
				write_rgba(bytes, offset, static_cast<uint8_t>(24 + t * 20), static_cast<uint8_t>(68 + t * 70), static_cast<uint8_t>(94 + t * 120));
				continue;
			}
			if ((p_layer_mask & LAYER_MASK_FILLED_ELEVATION) != 0) {
				t = saturate(p_snapshot.filled_elevation[static_cast<size_t>(index)]);
			} else {
				t = saturate(p_snapshot.hydro_elevation[static_cast<size_t>(index)]);
			}
			write_rgba(
				bytes,
				offset,
				static_cast<uint8_t>(40 + t * 76),
				static_cast<uint8_t>(70 + t * 70),
				static_cast<uint8_t>(56 + t * 54)
			);
		}
	}
	return Image::create_from_data(image_width, image_height, false, Image::FORMAT_RGBA8, bytes);
}

} // namespace world_hydrology_prepass
