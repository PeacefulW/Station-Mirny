#include "lake_field.h"

#include "world_utils.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

namespace lake_field {
namespace {

constexpr uint64_t k_seed_salt_lake_acceptance = 0x2f894d5c71b3a6e9ULL;
constexpr uint64_t k_seed_salt_lake_id = 0x96e8f43d2b51c7a5ULL;
constexpr uint64_t k_seed_salt_lake_shore = 0x58f79c3d49a6e215ULL;
constexpr int32_t k_lake_id_salt_sweep_limit = 1024;

struct BasinShape {
	int32_t seed_search_radius = 3;
	int32_t min_basin_cells = 2;
	int32_t max_basin_cells = 64;
};

struct Candidate {
	int32_t x = 0;
	int32_t y = 0;
};

struct FrontierCell {
	int32_t index = -1;
	float height = 0.0f;
};

LakeSettings sanitize_settings(const LakeSettings &p_settings) {
	LakeSettings settings = p_settings;
	settings.density = world_utils::clamp_value(settings.density, 0.0f, 1.0f);
	settings.scale = world_utils::clamp_value(settings.scale, 64.0f, 2048.0f);
	settings.shore_warp_amplitude = world_utils::clamp_value(settings.shore_warp_amplitude, 0.0f, 2.0f);
	settings.shore_warp_scale = world_utils::clamp_value(settings.shore_warp_scale, 8.0f, 64.0f);
	settings.deep_threshold = world_utils::clamp_value(settings.deep_threshold, 0.05f, 0.5f);
	settings.mountain_clearance = world_utils::clamp_value(settings.mountain_clearance, 0.0f, 0.5f);
	return settings;
}

BasinShape derive_basin_shape(const LakeSettings &p_settings) {
	const float coarse_diameter = p_settings.scale / static_cast<float>(world_prepass::COARSE_CELL_SIZE_TILES);
	BasinShape shape;
	// Mapping is intentionally monotonic and coarse-grid-local:
	// scale=512 produces the spec defaults radius=3, min=2, max=64.
	shape.seed_search_radius = world_utils::clamp_value(
		static_cast<int32_t>(std::lround(coarse_diameter / 2.5f)),
		1,
		8
	);
	shape.max_basin_cells = world_utils::clamp_value(
		static_cast<int32_t>(std::lround(coarse_diameter * coarse_diameter)),
		4,
		256
	);
	shape.min_basin_cells = world_utils::clamp_value(shape.max_basin_cells / 32, 2, 16);
	return shape;
}

int32_t wrap_x(int32_t p_x, int32_t p_grid_width) {
	return static_cast<int32_t>(world_utils::positive_mod(p_x, p_grid_width));
}

bool is_y_in_bounds(int32_t p_y, int32_t p_grid_height) {
	return p_y >= 0 && p_y < p_grid_height;
}

bool is_reject_cell(const world_prepass::Snapshot &p_snapshot, const LakeSettings &p_settings, int32_t p_index) {
	if (p_snapshot.ocean_band_mask[static_cast<size_t>(p_index)] != 0 ||
			p_snapshot.burning_band_mask[static_cast<size_t>(p_index)] != 0 ||
			p_snapshot.continent_mask[static_cast<size_t>(p_index)] == 0) {
		return true;
	}
	if (p_snapshot.coarse_wall_density[static_cast<size_t>(p_index)] >= p_settings.mountain_clearance) {
		return true;
	}
	if (p_snapshot.coarse_foot_density[static_cast<size_t>(p_index)] >= p_settings.mountain_clearance * 1.5f) {
		return true;
	}
	return false;
}

float hash_unit(int64_t p_seed, int64_t p_world_version, int32_t p_x, int32_t p_y) {
	uint64_t mixed = world_utils::mix_seed(p_seed, p_world_version, k_seed_salt_lake_acceptance);
	mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_x) * 0xc2b2ae3d27d4eb4fULL);
	mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_y) * 0x165667b19e3779f9ULL);
	const uint32_t low_bits = static_cast<uint32_t>(mixed & 0xffffffffULL);
	return static_cast<float>(low_bits) / static_cast<float>(std::numeric_limits<uint32_t>::max());
}

float hash_signed_noise(
	int64_t p_seed,
	int64_t p_world_version,
	int64_t p_x,
	int64_t p_y,
	int32_t p_octave
) {
	uint64_t mixed = world_utils::mix_seed(p_seed, p_world_version, k_seed_salt_lake_shore);
	mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_x) * 0xc2b2ae3d27d4eb4fULL);
	mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_y) * 0x165667b19e3779f9ULL);
	mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_octave) * 0x94d049bb133111ebULL);
	const uint32_t low_bits = static_cast<uint32_t>(mixed & 0xffffffffULL);
	const float unit = static_cast<float>(low_bits) / static_cast<float>(std::numeric_limits<uint32_t>::max());
	return unit * 2.0f - 1.0f;
}

float smoothstep(float p_value) {
	const float t = world_utils::clamp_value(p_value, 0.0f, 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

float lerp(float p_a, float p_b, float p_t) {
	return p_a + (p_b - p_a) * p_t;
}

float sample_value_noise(
	int64_t p_seed,
	int64_t p_world_version,
	float p_x,
	float p_y,
	int32_t p_octave
) {
	const int64_t x0 = static_cast<int64_t>(std::floor(p_x));
	const int64_t y0 = static_cast<int64_t>(std::floor(p_y));
	const int64_t x1 = x0 + 1;
	const int64_t y1 = y0 + 1;
	const float tx = smoothstep(p_x - static_cast<float>(x0));
	const float ty = smoothstep(p_y - static_cast<float>(y0));
	const float v00 = hash_signed_noise(p_seed, p_world_version, x0, y0, p_octave);
	const float v10 = hash_signed_noise(p_seed, p_world_version, x1, y0, p_octave);
	const float v01 = hash_signed_noise(p_seed, p_world_version, x0, y1, p_octave);
	const float v11 = hash_signed_noise(p_seed, p_world_version, x1, y1, p_octave);
	return lerp(lerp(v00, v10, tx), lerp(v01, v11, tx), ty);
}

bool is_strict_local_minimum(
	const world_prepass::Snapshot &p_snapshot,
	int32_t p_x,
	int32_t p_y,
	int32_t p_search_radius
) {
	const int32_t center_index = p_snapshot.index(p_x, p_y);
	const float center_height = p_snapshot.foundation_height[static_cast<size_t>(center_index)];
	for (int32_t dy = -p_search_radius; dy <= p_search_radius; ++dy) {
		const int32_t ny = p_y + dy;
		if (!is_y_in_bounds(ny, p_snapshot.grid_height)) {
			continue;
		}
		for (int32_t dx = -p_search_radius; dx <= p_search_radius; ++dx) {
			const int32_t nx = wrap_x(p_x + dx, p_snapshot.grid_width);
			const int32_t neighbor_index = p_snapshot.index(nx, ny);
			if (neighbor_index == center_index) {
				continue;
			}
			if (p_snapshot.foundation_height[static_cast<size_t>(neighbor_index)] <= center_height) {
				return false;
			}
		}
	}
	return true;
}

std::vector<Candidate> collect_candidates(
	const world_prepass::Snapshot &p_snapshot,
	const LakeSettings &p_settings,
	const BasinShape &p_shape,
	int64_t p_seed,
	int64_t p_world_version
) {
	std::vector<Candidate> candidates;
	for (int32_t y = 0; y < p_snapshot.grid_height; ++y) {
		for (int32_t x = 0; x < p_snapshot.grid_width; ++x) {
			const int32_t index = p_snapshot.index(x, y);
			if (is_reject_cell(p_snapshot, p_settings, index)) {
				continue;
			}
			if (hash_unit(p_seed, p_world_version, x, y) > p_settings.density) {
				continue;
			}
			if (!is_strict_local_minimum(p_snapshot, x, y, p_shape.seed_search_radius)) {
				continue;
			}
			candidates.push_back({ x, y });
		}
	}
	std::sort(candidates.begin(), candidates.end(), [](const Candidate &p_a, const Candidate &p_b) {
		return p_a.y < p_b.y || (p_a.y == p_b.y && p_a.x < p_b.x);
	});
	return candidates;
}

bool contains_id(const std::vector<int32_t> &p_used_ids, int32_t p_id) {
	return std::find(p_used_ids.begin(), p_used_ids.end(), p_id) != p_used_ids.end();
}

bool frontier_less(const FrontierCell &p_a, const FrontierCell &p_b, int32_t p_grid_width) {
	if (p_a.height != p_b.height) {
		return p_a.height < p_b.height;
	}
	const int32_t ay = p_a.index / p_grid_width;
	const int32_t by = p_b.index / p_grid_width;
	if (ay != by) {
		return ay < by;
	}
	return (p_a.index % p_grid_width) < (p_b.index % p_grid_width);
}

int32_t pop_lowest_frontier(std::vector<FrontierCell> &r_frontier, int32_t p_grid_width) {
	if (r_frontier.empty()) {
		return -1;
	}
	int32_t best_position = 0;
	for (int32_t position = 1; position < static_cast<int32_t>(r_frontier.size()); ++position) {
		if (frontier_less(r_frontier[static_cast<size_t>(position)], r_frontier[static_cast<size_t>(best_position)], p_grid_width)) {
			best_position = position;
		}
	}
	const int32_t best_index = r_frontier[static_cast<size_t>(best_position)].index;
	r_frontier.erase(r_frontier.begin() + best_position);
	return best_index;
}

bool add_frontier_cell(
	const world_prepass::Snapshot &p_snapshot,
	const LakeSettings &p_settings,
	int32_t p_index,
	const std::vector<uint8_t> &p_accepted,
	std::vector<uint8_t> &r_frontier_seen,
	std::vector<FrontierCell> &r_frontier
) {
	if (p_index < 0 ||
			p_index >= static_cast<int32_t>(p_accepted.size()) ||
			p_accepted[static_cast<size_t>(p_index)] != 0U ||
			r_frontier_seen[static_cast<size_t>(p_index)] != 0U) {
		return true;
	}
	if (is_reject_cell(p_snapshot, p_settings, p_index)) {
		return false;
	}
	r_frontier_seen[static_cast<size_t>(p_index)] = 1U;
	r_frontier.push_back({ p_index, p_snapshot.foundation_height[static_cast<size_t>(p_index)] });
	return true;
}

bool queue_frontier_neighbours(
	const world_prepass::Snapshot &p_snapshot,
	const LakeSettings &p_settings,
	int32_t p_index,
	const std::vector<uint8_t> &p_accepted,
	std::vector<uint8_t> &r_frontier_seen,
	std::vector<FrontierCell> &r_frontier
) {
	const int32_t current_x = p_index % p_snapshot.grid_width;
	const int32_t current_y = p_index / p_snapshot.grid_width;
	const int32_t dx[4] = { 0, 1, 0, -1 };
	const int32_t dy[4] = { -1, 0, 1, 0 };
	for (int32_t dir = 0; dir < 4; ++dir) {
		const int32_t nx = wrap_x(current_x + dx[dir], p_snapshot.grid_width);
		const int32_t ny = current_y + dy[dir];
		if (!is_y_in_bounds(ny, p_snapshot.grid_height)) {
			return false;
		}
		const int32_t neighbor_index = p_snapshot.index(nx, ny);
		if (!add_frontier_cell(p_snapshot, p_settings, neighbor_index, p_accepted, r_frontier_seen, r_frontier)) {
			return false;
		}
	}
	return true;
}

bool has_lower_unaccepted_neighbour(
	const world_prepass::Snapshot &p_snapshot,
	const LakeSettings &p_settings,
	int32_t p_index,
	const std::vector<uint8_t> &p_accepted
) {
	const float current_height = p_snapshot.foundation_height[static_cast<size_t>(p_index)];
	const int32_t current_x = p_index % p_snapshot.grid_width;
	const int32_t current_y = p_index / p_snapshot.grid_width;
	const int32_t dx[4] = { 0, 1, 0, -1 };
	const int32_t dy[4] = { -1, 0, 1, 0 };
	for (int32_t dir = 0; dir < 4; ++dir) {
		const int32_t nx = wrap_x(current_x + dx[dir], p_snapshot.grid_width);
		const int32_t ny = current_y + dy[dir];
		if (!is_y_in_bounds(ny, p_snapshot.grid_height)) {
			return true;
		}
		const int32_t neighbor_index = p_snapshot.index(nx, ny);
		if (p_accepted[static_cast<size_t>(neighbor_index)] != 0U) {
			continue;
		}
		if (is_reject_cell(p_snapshot, p_settings, neighbor_index)) {
			return true;
		}
		const float neighbor_height = p_snapshot.foundation_height[static_cast<size_t>(neighbor_index)];
		if (neighbor_height < current_height - 0.00001f) {
			return true;
		}
	}
	return false;
}

int32_t make_lake_id(
	int64_t p_seed,
	int64_t p_world_version,
	const Candidate &p_root,
	int32_t p_basin_cell_count,
	const std::vector<int32_t> &p_used_ids
) {
	for (int32_t salt = 0; salt < k_lake_id_salt_sweep_limit; ++salt) {
		uint64_t mixed = world_utils::mix_seed(p_seed, p_world_version, k_seed_salt_lake_id);
		mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_root.x) * 0xc2b2ae3d27d4eb4fULL);
		mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_root.y) * 0x165667b19e3779f9ULL);
		mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_basin_cell_count) * 0x94d049bb133111ebULL);
		mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(salt) * 0x9e3779b185ebca87ULL);
		const int32_t lake_id = static_cast<int32_t>(mixed & 0x7fffffffULL);
		if (lake_id != 0 && !contains_id(p_used_ids, lake_id)) {
			return lake_id;
		}
	}
	assert(false && "Lake id collision salt sweep exhausted.");
	return 0;
}

bool build_basin(
	world_prepass::Snapshot &r_snapshot,
	const LakeSettings &p_settings,
	const BasinShape &p_shape,
	const Candidate &p_candidate,
	std::vector<int32_t> &r_basin_cells,
	float &r_rim_height
) {
	const int32_t node_count = r_snapshot.grid_width * r_snapshot.grid_height;
	std::vector<uint8_t> accepted(static_cast<size_t>(node_count), 0);
	std::vector<uint8_t> frontier_seen(static_cast<size_t>(node_count), 0);
	std::vector<FrontierCell> frontier;
	frontier.reserve(static_cast<size_t>(p_shape.max_basin_cells + 4));

	const int32_t root_index = r_snapshot.index(p_candidate.x, p_candidate.y);
	accepted[static_cast<size_t>(root_index)] = 1U;
	r_basin_cells.clear();
	r_basin_cells.push_back(root_index);
	if (!queue_frontier_neighbours(r_snapshot, p_settings, root_index, accepted, frontier_seen, frontier)) {
		return false;
	}

	float rim_height_so_far = std::numeric_limits<float>::infinity();
	while (!frontier.empty()) {
		const int32_t current_index = pop_lowest_frontier(frontier, r_snapshot.grid_width);
		if (current_index < 0 || accepted[static_cast<size_t>(current_index)] != 0U) {
			continue;
		}
		const float current_height = r_snapshot.foundation_height[static_cast<size_t>(current_index)];
		if (has_lower_unaccepted_neighbour(r_snapshot, p_settings, current_index, accepted)) {
			rim_height_so_far = current_height;
			break;
		}
		if (static_cast<int32_t>(r_basin_cells.size()) + 1 > p_shape.max_basin_cells) {
			return false;
		}
		accepted[static_cast<size_t>(current_index)] = 1U;
		r_basin_cells.push_back(current_index);
		if (!queue_frontier_neighbours(r_snapshot, p_settings, current_index, accepted, frontier_seen, frontier)) {
			return false;
		}
	}

	if (!std::isfinite(rim_height_so_far) ||
			static_cast<int32_t>(r_basin_cells.size()) < p_shape.min_basin_cells) {
		return false;
	}

	float max_basin_height = -std::numeric_limits<float>::infinity();
	for (int32_t basin_index : r_basin_cells) {
		if (r_snapshot.lake_id[static_cast<size_t>(basin_index)] != 0) {
			return false;
		}
		max_basin_height = std::max(max_basin_height, r_snapshot.foundation_height[static_cast<size_t>(basin_index)]);
	}

	if (rim_height_so_far <= max_basin_height + 0.00001f) {
		return false;
	}

	r_rim_height = rim_height_so_far;
	return true;
}

} // namespace

void solve_lake_basins(
	world_prepass::Snapshot &r_snapshot,
	const LakeSettings &p_lake_settings,
	int64_t p_seed,
	int64_t p_world_version
) {
	if (!r_snapshot.valid || r_snapshot.grid_width <= 0 || r_snapshot.grid_height <= 0) {
		return;
	}
	const LakeSettings settings = sanitize_settings(p_lake_settings);
	if (!settings.enabled || settings.density <= 0.0f) {
		return;
	}

	const BasinShape shape = derive_basin_shape(settings);
	const std::vector<Candidate> candidates = collect_candidates(r_snapshot, settings, shape, p_seed, p_world_version);
	std::vector<int32_t> used_lake_ids;
	used_lake_ids.reserve(candidates.size());

	for (const Candidate &candidate : candidates) {
		std::vector<int32_t> basin_cells;
		float rim_height = 0.0f;
		if (!build_basin(r_snapshot, settings, shape, candidate, basin_cells, rim_height)) {
			continue;
		}
		const int32_t lake_id = make_lake_id(
			p_seed,
			p_world_version,
			candidate,
			static_cast<int32_t>(basin_cells.size()),
			used_lake_ids
		);
		if (lake_id == 0) {
			continue;
		}
		used_lake_ids.push_back(lake_id);
		const int32_t water_level_q16 = static_cast<int32_t>(std::lround(
			world_utils::clamp_value(rim_height, 0.0f, 1.0f) * 65536.0f
		));
		for (int32_t basin_index : basin_cells) {
			r_snapshot.lake_id[static_cast<size_t>(basin_index)] = lake_id;
			r_snapshot.lake_water_level_q16[static_cast<size_t>(basin_index)] = water_level_q16;
		}
	}
}

BasinMinElevationLookup build_basin_min_elevation_lookup(const world_prepass::Snapshot &p_snapshot) {
	BasinMinElevationLookup lookup;
	const int32_t node_count = p_snapshot.grid_width * p_snapshot.grid_height;
	if (!p_snapshot.valid ||
			node_count <= 0 ||
			static_cast<int32_t>(p_snapshot.lake_id.size()) < node_count ||
			static_cast<int32_t>(p_snapshot.foundation_height.size()) < node_count) {
		return lookup;
	}
	for (int32_t index = 0; index < node_count; ++index) {
		const int32_t lake_id = p_snapshot.lake_id[static_cast<size_t>(index)];
		if (lake_id <= 0) {
			continue;
		}
		const float elevation = p_snapshot.foundation_height[static_cast<size_t>(index)];
		auto found = lookup.find(lake_id);
		if (found == lookup.end()) {
			lookup.emplace(lake_id, elevation);
		} else {
			found->second = std::min(found->second, elevation);
		}
	}
	return lookup;
}

float resolve_basin_min_elevation(
	const BasinMinElevationLookup &p_lookup,
	int32_t p_lake_id,
	float p_fallback
) {
	auto found = p_lookup.find(p_lake_id);
	return found == p_lookup.end() ? p_fallback : found->second;
}

float fbm_shore(
	int64_t p_world_x,
	int64_t p_world_y,
	int64_t p_seed,
	int64_t p_world_version,
	float p_scale,
	float p_amplitude
) {
	const float safe_scale = std::max(1.0f, p_scale);
	const float x = static_cast<float>(p_world_x) / safe_scale;
	const float y = static_cast<float>(p_world_y) / safe_scale;
	const float octave0 = sample_value_noise(p_seed, p_world_version, x, y, 0);
	const float octave1 = sample_value_noise(p_seed, p_world_version, x * 2.0f, y * 2.0f, 1);
	const float fbm = octave0 * 0.6666667f + octave1 * 0.3333333f;
	return world_utils::clamp_value(fbm, -1.0f, 1.0f) * std::max(0.0f, p_amplitude);
}

} // namespace lake_field
