#include "world_hydrology_prepass.h"
#include "world_utils.h"

#include "third_party/FastNoiseLite.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <functional>
#include <limits>
#include <queue>
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
	uint64_t variation_seed = 0ULL;
	bool delta = false;
	bool braid_split = false;
	bool organic = false;
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

struct LakeBasinCandidate {
	std::vector<int32_t> nodes;
	int32_t outlet_node = -1;
	float max_depth = 0.0f;
	float average_accumulation = 0.0f;
	float score = 0.0f;
	uint64_t stable_key = 0;
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
		static_cast<float>(clamp_value(cell_size / 4, 2, 5)) * 0.65f +
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

void select_lake_basins(Snapshot &r_snapshot, const RiverSettings &p_river_settings) {
	if (r_snapshot.world_version < WORLD_LAKE_VERSION || p_river_settings.lake_chance <= 0.0f) {
		return;
	}
	const int32_t node_count = r_snapshot.grid_width * r_snapshot.grid_height;
	if (node_count <= 0) {
		return;
	}

	const float chance = saturate(p_river_settings.lake_chance);
	const float depth_threshold = 0.010f + (1.0f - chance) * 0.020f;
	std::vector<uint8_t> candidate_mask(static_cast<size_t>(node_count), 0U);
	for (int32_t index = 0; index < node_count; ++index) {
		if (r_snapshot.ocean_sink_mask[static_cast<size_t>(index)] != 0U ||
				r_snapshot.mountain_exclusion_mask[static_cast<size_t>(index)] != 0U) {
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
			const int32_t downstream = resolve_downstream_index(r_snapshot, node);
			if (downstream < 0 || component_id[static_cast<size_t>(downstream)] == component_index) {
				continue;
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
			}
		}
		if (candidate.outlet_node < 0 || candidate.max_depth <= 0.0f) {
			candidates.push_back(candidate);
			continue;
		}
		candidate.average_accumulation = accumulation_sum / std::max<float>(1.0f, static_cast<float>(candidate.nodes.size()));
		candidate.score = candidate.max_depth * std::sqrt(static_cast<float>(candidate.nodes.size())) +
				std::log1p(candidate.average_accumulation) * 0.05f;
		candidate.stable_key = splitmix64(
			mix_seed(r_snapshot.seed, r_snapshot.world_version, SEED_SALT_LAKE_SELECTION) ^
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
		for (const int32_t node : candidate.nodes) {
			r_snapshot.lake_id[static_cast<size_t>(node)] = next_lake_id;
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
		for (int32_t index = 0; index < node_count; ++index) {
			const int32_t lake_id = r_snapshot.lake_id[static_cast<size_t>(index)];
			if (lake_id <= 0) {
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
	const FoundationSettings &p_foundation_settings,
	const RiverSettings &p_river_settings
) {
	uint64_t signature = splitmix64(static_cast<uint64_t>(p_seed));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_world_version) * 0x9e3779b185ebca87ULL);
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
	snapshot->ocean_sink_mask.assign(static_cast<size_t>(node_count), 0U);
	snapshot->mountain_exclusion_mask.assign(static_cast<size_t>(node_count), 0U);
	snapshot->floodplain_potential.assign(static_cast<size_t>(node_count), 0.0f);

	FastNoiseLite coastline_noise = make_noise(mix_seed(p_seed, p_world_version, SEED_SALT_COASTLINE), 1.0f / 768.0f, 3);
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
			const bool is_ocean = center.y <= coastline_y || y == 0;
			const float base_hydro = p_foundation_snapshot.hydro_height[static_cast<size_t>(foundation_index)];
			const float north_bias = y_t * p_river_settings.north_drainage_bias * 0.34f;
			const float mountain_cost =
					p_foundation_snapshot.coarse_wall_density[static_cast<size_t>(foundation_index)] * 1.2f +
					p_foundation_snapshot.coarse_foot_density[static_cast<size_t>(foundation_index)] * 0.65f;
			snapshot->ocean_sink_mask[static_cast<size_t>(index)] = is_ocean ? 1U : 0U;
			snapshot->hydro_elevation[static_cast<size_t>(index)] = saturate(base_hydro + north_bias) + mountain_cost;
		}
	}

	build_mountain_clearance(*snapshot, p_foundation_snapshot, p_river_settings.mountain_clearance_tiles);
	for (int32_t index = 0; index < node_count; ++index) {
		if (snapshot->mountain_exclusion_mask[static_cast<size_t>(index)] != 0U) {
			snapshot->hydro_elevation[static_cast<size_t>(index)] += 2.0f;
		}
	}
	solve_priority_flood(*snapshot);
	select_lake_basins(*snapshot, p_river_settings);

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
	result["ocean_sink_mask"] = make_byte_array(p_snapshot.ocean_sink_mask);
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
	return result;
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
			build_overview_river_edges(p_snapshot, pixels_per_cell) :
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
			if (p_snapshot.ocean_sink_mask[static_cast<size_t>(index)] != 0U) {
				write_rgba(bytes, offset, 38, 89, 128, transparent_water_overlay ? 230 : 255);
				continue;
			}
			const int32_t local_pixel_x = x % pixels_per_cell;
			const int32_t local_pixel_y = y % pixels_per_cell;
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
