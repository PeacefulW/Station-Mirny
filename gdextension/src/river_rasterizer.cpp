#include "river_rasterizer.h"
#include "world_utils.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <vector>

using world_utils::clamp_value;
using world_utils::positive_mod;
using world_utils::saturate;
using world_utils::splitmix64;

namespace river_rasterizer {
namespace {

constexpr int32_t COARSE = world_prepass::COARSE_CELL_SIZE_TILES;
constexpr int32_t NODE_SEARCH_HALO_TILES = COARSE * 2;
constexpr int32_t MAX_CHAIN_STEPS_MULTIPLIER = 2;

struct RiverSegment {
	double ax = 0.0;
	double ay = 0.0;
	double bx = 0.0;
	double by = 0.0;
	float shallow_radius = 0.0f;
	float deep_radius = 0.0f;
	float flow = 0.0f;
	uint8_t flags = 0U;
};

struct LakeCandidate {
	double center_x = 0.0;
	double center_y = 0.0;
	float shallow_radius = 0.0f;
	float deep_radius = 0.0f;
};

int64_t floor_div(int64_t p_value, int64_t p_divisor) {
	int64_t quotient = p_value / p_divisor;
	const int64_t remainder = p_value % p_divisor;
	if (remainder != 0 && ((remainder < 0) != (p_divisor < 0))) {
		quotient -= 1;
	}
	return quotient;
}

double closest_wrapped_x(double p_x, double p_reference_x, int64_t p_width_tiles) {
	if (p_width_tiles <= 0) {
		return p_x;
	}
	const double width = static_cast<double>(p_width_tiles);
	return p_x - std::round((p_x - p_reference_x) / width) * width;
}

double distance_to_segment(
	double p_x,
	double p_y,
	double p_ax,
	double p_ay,
	double p_bx,
	double p_by
) {
	const double vx = p_bx - p_ax;
	const double vy = p_by - p_ay;
	const double wx = p_x - p_ax;
	const double wy = p_y - p_ay;
	const double length_sq = vx * vx + vy * vy;
	if (length_sq <= std::numeric_limits<double>::epsilon()) {
		const double dx = p_x - p_ax;
		const double dy = p_y - p_ay;
		return std::sqrt(dx * dx + dy * dy);
	}
	const double t = clamp_value((wx * vx + wy * vy) / length_sq, 0.0, 1.0);
	const double px = p_ax + t * vx;
	const double py = p_ay + t * vy;
	const double dx = p_x - px;
	const double dy = p_y - py;
	return std::sqrt(dx * dx + dy * dy);
}

double hash_to_unit(uint64_t p_hash) {
	return static_cast<double>(p_hash & 0xffffULL) / 65535.0;
}

void append_river_segment(
	std::vector<RiverSegment> &r_result,
	double p_ax,
	double p_ay,
	double p_bx,
	double p_by,
	float p_shallow_radius,
	float p_deep_radius,
	float p_flow,
	uint8_t p_flags
) {
	RiverSegment segment;
	segment.ax = p_ax;
	segment.ay = p_ay;
	segment.bx = p_bx;
	segment.by = p_by;
	segment.shallow_radius = p_shallow_radius;
	segment.deep_radius = p_deep_radius;
	segment.flow = p_flow;
	segment.flags = p_flags;
	r_result.push_back(segment);
}

bool chain_reaches_ocean(const world_prepass::Snapshot &p_snapshot, int32_t p_start_index) {
	const int32_t node_count = p_snapshot.grid_width * p_snapshot.grid_height;
	if (p_start_index < 0 || p_start_index >= node_count) {
		return false;
	}
	int32_t current = p_start_index;
	const int32_t max_steps = std::max(1, node_count * MAX_CHAIN_STEPS_MULTIPLIER);
	for (int32_t step = 0; step < max_steps && current >= 0 && current < node_count; ++step) {
		if (p_snapshot.ocean_band_mask[static_cast<size_t>(current)] != 0) {
			return true;
		}
		if (p_snapshot.burning_band_mask[static_cast<size_t>(current)] != 0) {
			return false;
		}
		current = p_snapshot.downstream_index[static_cast<size_t>(current)];
	}
	return false;
}

std::vector<int32_t> collect_nearby_nodes(
	const world_prepass::Snapshot &p_snapshot,
	int64_t p_origin_world_x,
	int64_t p_origin_world_y,
	int32_t p_width,
	int32_t p_height
) {
	std::vector<int32_t> result;
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0) {
		return result;
	}

	const int64_t min_tile_x = p_origin_world_x - NODE_SEARCH_HALO_TILES;
	const int64_t max_tile_x = p_origin_world_x + p_width + NODE_SEARCH_HALO_TILES;
	const int64_t min_tile_y = p_origin_world_y - NODE_SEARCH_HALO_TILES;
	const int64_t max_tile_y = p_origin_world_y + p_height + NODE_SEARCH_HALO_TILES;
	const int64_t min_node_x = floor_div(min_tile_x, COARSE);
	const int64_t max_node_x = floor_div(max_tile_x, COARSE);
	const int64_t min_node_y = std::max<int64_t>(0, floor_div(min_tile_y, COARSE));
	const int64_t max_node_y = std::min<int64_t>(p_snapshot.grid_height - 1, floor_div(max_tile_y, COARSE));
	const int64_t x_span = max_node_x - min_node_x + 1;
	std::vector<uint8_t> seen(static_cast<size_t>(p_snapshot.grid_width * p_snapshot.grid_height), 0);

	for (int64_t y = min_node_y; y <= max_node_y; ++y) {
		if (x_span >= p_snapshot.grid_width) {
			for (int32_t x = 0; x < p_snapshot.grid_width; ++x) {
				const int32_t index = p_snapshot.index(x, static_cast<int32_t>(y));
				if (seen[static_cast<size_t>(index)] == 0) {
					seen[static_cast<size_t>(index)] = 1U;
					result.push_back(index);
				}
			}
			continue;
		}
		for (int64_t x = min_node_x; x <= max_node_x; ++x) {
			const int32_t wrapped_x = static_cast<int32_t>(positive_mod(x, p_snapshot.grid_width));
			const int32_t index = p_snapshot.index(wrapped_x, static_cast<int32_t>(y));
			if (seen[static_cast<size_t>(index)] != 0) {
				continue;
			}
			seen[static_cast<size_t>(index)] = 1U;
			result.push_back(index);
		}
	}
	return result;
}

float resolve_shallow_radius(const world_prepass::Snapshot &p_snapshot, int32_t p_index) {
	const float flow = saturate(p_snapshot.flow_accumulation[static_cast<size_t>(p_index)]);
	const float valley = saturate(p_snapshot.coarse_valley_score[static_cast<size_t>(p_index)]);
	const float wall_pressure = saturate(p_snapshot.coarse_wall_density[static_cast<size_t>(p_index)]);
	const int32_t node_y = p_index / p_snapshot.grid_width;
	const float downstream_to_ocean = 1.0f - saturate(
		static_cast<float>(node_y * COARSE + COARSE / 2) /
		static_cast<float>(std::max<int64_t>(1, p_snapshot.height_tiles - 1))
	);
	const float order = static_cast<float>(std::min(6, std::max(1, p_snapshot.strahler_order[static_cast<size_t>(p_index)])));
	float radius = 0.65f + flow * 2.4f + order * 0.20f + downstream_to_ocean * 0.85f + valley * 0.25f;
	radius *= 1.0f - std::min(0.35f, wall_pressure * 0.45f);
	return clamp_value(radius, 0.75f, 3.75f);
}

std::vector<RiverSegment> build_river_segments(
	const world_prepass::Snapshot &p_snapshot,
	const std::vector<int32_t> &p_node_indices,
	int64_t p_seed,
	int64_t p_region_reference_x
) {
	std::vector<RiverSegment> result;
	const int32_t node_count = p_snapshot.grid_width * p_snapshot.grid_height;
	for (int32_t index : p_node_indices) {
		if (index < 0 || index >= node_count ||
				p_snapshot.visible_trunk_mask[static_cast<size_t>(index)] == 0 ||
				!chain_reaches_ocean(p_snapshot, index)) {
			continue;
		}
		const int32_t downstream = p_snapshot.downstream_index[static_cast<size_t>(index)];
		if (downstream < 0 || downstream >= node_count) {
			continue;
		}
		const godot::Vector2i a_center = p_snapshot.node_to_tile_center(index % p_snapshot.grid_width, index / p_snapshot.grid_width);
		const godot::Vector2i b_center = p_snapshot.node_to_tile_center(downstream % p_snapshot.grid_width, downstream / p_snapshot.grid_width);
		const double ax = closest_wrapped_x(static_cast<double>(a_center.x), static_cast<double>(p_region_reference_x), p_snapshot.width_tiles);
		const double bx = closest_wrapped_x(static_cast<double>(b_center.x), ax, p_snapshot.width_tiles);
		const float shallow_radius = resolve_shallow_radius(p_snapshot, index);
		const bool is_mouth = p_snapshot.ocean_band_mask[static_cast<size_t>(downstream)] != 0 ||
				a_center.y < p_snapshot.ocean_band_tiles + COARSE * 2;
		const double ay = static_cast<double>(a_center.y);
		const double by = static_cast<double>(b_center.y);
		const float resolved_shallow_radius = std::min(4.5f, shallow_radius + (is_mouth ? 0.75f : 0.0f));
		float resolved_deep_radius = std::max(0.30f, resolved_shallow_radius * 0.28f);
		if (resolved_shallow_radius >= 1.2f && resolved_shallow_radius - resolved_deep_radius < 0.65f) {
			resolved_deep_radius = std::max(0.30f, resolved_shallow_radius - 0.65f);
		}
		const float flow = saturate(p_snapshot.flow_accumulation[static_cast<size_t>(index)]);
		const uint8_t flags = static_cast<uint8_t>(FLAG_RIVERBED | FLAG_OCEAN_DIRECTED | (is_mouth ? FLAG_MOUTH_OR_DELTA : 0U));
		const double dx = bx - ax;
		const double dy = by - ay;
		const double length = std::sqrt(dx * dx + dy * dy);
		if (length <= std::numeric_limits<double>::epsilon()) {
			append_river_segment(result, ax, ay, bx, by, resolved_shallow_radius, resolved_deep_radius, flow, flags);
			continue;
		}

		const float valley = saturate(p_snapshot.coarse_valley_score[static_cast<size_t>(index)]);
		const uint64_t bend_hash = splitmix64(
			static_cast<uint64_t>(p_seed) ^
			p_snapshot.signature ^
			static_cast<uint64_t>(index) * 0x9e3779b185ebca87ULL ^
			static_cast<uint64_t>(downstream) * 0xc2b2ae3d27d4eb4fULL
		);
		const double bend_sign = hash_to_unit(bend_hash) * 2.0 - 1.0;
		const double along_sign = hash_to_unit(splitmix64(bend_hash ^ 0x8a5cd789635d2dffULL)) * 2.0 - 1.0;
		const double bend_magnitude = std::min(length * 0.22, 3.0 + static_cast<double>(flow) * 5.0 + static_cast<double>(valley) * 3.0);
		const double along_magnitude = std::min(length * 0.10, 4.0);
		const double tx = dx / length;
		const double ty = dy / length;
		const double nx = -ty;
		const double ny = tx;
		const double mx = (ax + bx) * 0.5 + nx * bend_sign * bend_magnitude + tx * along_sign * along_magnitude;
		const double my = clamp_value(
			(ay + by) * 0.5 + ny * bend_sign * bend_magnitude + ty * along_sign * along_magnitude,
			0.0,
			static_cast<double>(std::max<int64_t>(0, p_snapshot.height_tiles - 1))
		);
		append_river_segment(result, ax, ay, mx, my, resolved_shallow_radius, resolved_deep_radius, flow, flags);
		append_river_segment(result, mx, my, bx, by, resolved_shallow_radius, resolved_deep_radius, flow, flags);
	}
	return result;
}

std::vector<LakeCandidate> build_lake_candidates(
	const world_prepass::Snapshot &p_snapshot,
	const std::vector<int32_t> &p_node_indices,
	int64_t p_region_reference_x
) {
	std::vector<LakeCandidate> result;
	for (int32_t index : p_node_indices) {
		if (p_snapshot.is_terminal_lake_center[static_cast<size_t>(index)] == 0 ||
				p_snapshot.ocean_band_mask[static_cast<size_t>(index)] != 0 ||
				p_snapshot.burning_band_mask[static_cast<size_t>(index)] != 0) {
			continue;
		}
		const godot::Vector2i center = p_snapshot.node_to_tile_center(index % p_snapshot.grid_width, index / p_snapshot.grid_width);
		const float flow = saturate(p_snapshot.flow_accumulation[static_cast<size_t>(index)]);
		const float valley = saturate(p_snapshot.coarse_valley_score[static_cast<size_t>(index)]);
		const float shallow_radius = clamp_value(4.5f + flow * 7.5f + valley * 2.0f, 5.5f, 14.0f);
		LakeCandidate candidate;
		candidate.center_x = closest_wrapped_x(static_cast<double>(center.x), static_cast<double>(p_region_reference_x), p_snapshot.width_tiles);
		candidate.center_y = static_cast<double>(center.y);
		candidate.shallow_radius = shallow_radius;
		candidate.deep_radius = std::max(2.5f, shallow_radius * 0.42f);
		result.push_back(candidate);
	}
	return result;
}

void apply_candidate_to_cell(
	RasterizedRegion &r_region,
	int32_t p_index,
	uint8_t p_flags,
	float p_distance,
	float p_deep_radius,
	float p_shallow_radius
) {
	if (p_distance > p_shallow_radius) {
		return;
	}
	const uint8_t candidate_depth = p_distance <= p_deep_radius ? DEPTH_DEEP : DEPTH_SHALLOW;
	const uint8_t previous_depth = r_region.depth[static_cast<size_t>(p_index)];
	if (candidate_depth < previous_depth) {
		return;
	}
	r_region.depth[static_cast<size_t>(p_index)] = candidate_depth;
	r_region.flags[static_cast<size_t>(p_index)] = p_flags;
}

} // namespace

bool RasterizedRegion::is_valid() const {
	return width > 0 &&
			height > 0 &&
			flags.size() == static_cast<size_t>(width * height) &&
			depth.size() == static_cast<size_t>(width * height);
}

int32_t RasterizedRegion::index(int32_t p_x, int32_t p_y) const {
	return p_y * width + p_x;
}

bool is_enabled_for_version(int64_t p_world_version) {
	return p_world_version >= RIVER_GENERATION_VERSION;
}

RasterizedRegion rasterize_region(
	const world_prepass::Snapshot &p_snapshot,
	int64_t p_seed,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings,
	int64_t p_origin_world_x,
	int64_t p_origin_world_y,
	int32_t p_width,
	int32_t p_height
) {
	(void)p_world_version;
	(void)p_foundation_settings;
	RasterizedRegion region;
	region.width = std::max(0, p_width);
	region.height = std::max(0, p_height);
	region.flags.assign(static_cast<size_t>(region.width * region.height), 0U);
	region.depth.assign(static_cast<size_t>(region.width * region.height), DEPTH_NONE);
	if (!p_snapshot.valid || region.width <= 0 || region.height <= 0) {
		return region;
	}

	const std::vector<int32_t> nearby_nodes = collect_nearby_nodes(
		p_snapshot,
		p_origin_world_x,
		p_origin_world_y,
		p_width,
		p_height
	);
	const int64_t reference_x = p_origin_world_x + p_width / 2;
	const std::vector<RiverSegment> river_segments = build_river_segments(p_snapshot, nearby_nodes, p_seed, reference_x);
	const std::vector<LakeCandidate> lake_candidates = build_lake_candidates(p_snapshot, nearby_nodes, reference_x);

	for (int32_t y = 0; y < region.height; ++y) {
		const int64_t world_y = p_origin_world_y + y;
		if (world_y < 0 || world_y >= p_snapshot.height_tiles) {
			continue;
		}
		for (int32_t x = 0; x < region.width; ++x) {
			const int64_t raw_world_x = p_origin_world_x + x;
			const double px = static_cast<double>(raw_world_x) + 0.5;
			const double py = static_cast<double>(world_y) + 0.5;
			const int32_t cell_index = region.index(x, y);

			for (const RiverSegment &segment : river_segments) {
				const double ax = closest_wrapped_x(segment.ax, px, p_snapshot.width_tiles);
				const double bx = closest_wrapped_x(segment.bx, ax, p_snapshot.width_tiles);
				const double distance = distance_to_segment(px, py, ax, segment.ay, bx, segment.by);
				apply_candidate_to_cell(
					region,
					cell_index,
					segment.flags,
					static_cast<float>(distance),
					segment.deep_radius,
					segment.shallow_radius
				);
			}

			for (const LakeCandidate &lake : lake_candidates) {
				const double lake_x = closest_wrapped_x(lake.center_x, px, p_snapshot.width_tiles);
				const double dx = px - lake_x;
				const double dy = py - lake.center_y;
				const double distance = std::sqrt(dx * dx + dy * dy);
				apply_candidate_to_cell(
					region,
					cell_index,
					FLAG_LAKEBED,
					static_cast<float>(distance),
					lake.deep_radius,
					lake.shallow_radius
				);
			}
		}
	}

	return region;
}

} // namespace river_rasterizer
