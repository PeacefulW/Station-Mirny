#include "world_prepass.h"
#include "world_utils.h"

#include "third_party/FastNoiseLite.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <limits>
#include <queue>
#include <utility>
#include <vector>

#ifdef DEBUG_ENABLED
#include <godot_cpp/core/error_macros.hpp>
#endif

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;
using world_utils::splitmix64;
using world_utils::positive_mod;
using world_utils::clamp_value;
using world_utils::saturate;

namespace world_prepass {
namespace {

constexpr int64_t SPAWN_SAFE_PATCH_MIN_TILE = 12;
constexpr int64_t SPAWN_SAFE_PATCH_MAX_TILE = 20;
constexpr float WALL_BLOCK_THRESHOLD = 0.5f;
constexpr float SPAWN_MAX_WALL_DENSITY = 0.4f;
constexpr float SPAWN_MIN_VALLEY_SCORE = 0.45f;
constexpr float SPAWN_HYDRO_MIN = 0.28f;
constexpr float SPAWN_HYDRO_MAX = 0.74f;
constexpr float FLOW_SEA_THRESHOLD = 0.62f;
constexpr float CONTINENT_NOISE_THRESHOLD = 0.28f;
constexpr uint64_t SEED_SALT_CONTINENT = 0xd1b54a32d192ed03ULL;
constexpr uint64_t SEED_SALT_RELIEF = 0x8a5cd789635d2dffULL;
constexpr uint64_t SEED_SALT_SOURCE = 0x9e3779b185ebca87ULL;
constexpr uint64_t SEED_SALT_REGION = 0xc2b2ae3d27d4eb4fULL;
constexpr int64_t DRY_RIVER_OVERVIEW_VERSION = 14;
constexpr int32_t MAX_CHAIN_STEPS_MULTIPLIER = 2;

struct QueueEntry {
	float height = 0.0f;
	int32_t index = 0;
};

struct QueueEntryCompare {
	bool operator()(const QueueEntry &p_a, const QueueEntry &p_b) const {
		if (p_a.height != p_b.height) {
			return p_a.height > p_b.height;
		}
		return p_a.index > p_b.index;
	}
};

struct OverviewMasks {
	bool ocean_band = false;
	bool burning_band = false;
	bool continent = false;
};

struct LakeCandidateScore {
	int32_t index = 0;
	float score = 0.0f;
};

uint64_t mix_seed(int64_t p_seed, int64_t p_world_version, uint64_t p_salt) {
	return world_utils::mix_seed(p_seed, p_world_version, p_salt);
}

int make_noise_seed(uint64_t p_value) {
	return static_cast<int>(p_value & 0x7fffffffULL);
}

float smoothstep(float p_edge0, float p_edge1, float p_value) {
	if (p_edge0 == p_edge1) {
		return p_value < p_edge0 ? 0.0f : 1.0f;
	}
	const float t = saturate((p_value - p_edge0) / (p_edge1 - p_edge0));
	return t * t * (3.0f - 2.0f * t);
}

int64_t wrap_foundation_world_x(int64_t p_world_x, const FoundationSettings &p_foundation_settings) {
	return world_utils::wrap_foundation_world_x(p_world_x, p_foundation_settings.width_tiles, p_foundation_settings.enabled);
}

int64_t resolve_mountain_sample_x(
	int64_t p_world_x,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings
) {
	return world_utils::resolve_mountain_sample_x(p_world_x, p_world_version, p_foundation_settings.width_tiles, p_foundation_settings.enabled);
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

int32_t resolve_region_id(int64_t p_seed, int64_t p_world_version, int32_t p_x, int32_t p_y) {
	uint64_t mixed = mix_seed(p_seed, p_world_version, SEED_SALT_REGION);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_x / 4) * 0x165667b19e3779f9ULL);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_y / 4) * 0x94d049bb133111ebULL);
	return static_cast<int32_t>(mixed & 0x7fffffffULL);
}

float visible_flow_threshold(float p_river_amount) {
	if (p_river_amount <= 0.0f) {
		return std::numeric_limits<float>::infinity();
	}
	return clamp_value(0.34f - saturate(p_river_amount) * 0.24f, 0.035f, 0.34f);
}

bool is_blocked_for_routing(const Snapshot &p_snapshot, int32_t p_index) {
	return p_snapshot.coarse_wall_density[static_cast<size_t>(p_index)] > WALL_BLOCK_THRESHOLD;
}

void append_neighbours(
	const Snapshot &p_snapshot,
	int32_t p_x,
	int32_t p_y,
	std::vector<int32_t> &r_out
) {
	static constexpr int32_t dx[8] = { 1, 1, 0, -1, -1, -1, 0, 1 };
	static constexpr int32_t dy[8] = { 0, 1, 1, 1, 0, -1, -1, -1 };
	r_out.clear();
	for (int32_t direction = 0; direction < 8; ++direction) {
		const int32_t nx = static_cast<int32_t>(positive_mod(p_x + dx[direction], p_snapshot.grid_width));
		const int32_t ny = p_y + dy[direction];
		if (ny < 0 || ny >= p_snapshot.grid_height) {
			continue;
		}
		r_out.push_back(p_snapshot.index(nx, ny));
	}
}

void build_flow_graph(Snapshot &r_snapshot, float p_river_amount) {
	const int32_t node_count = r_snapshot.grid_width * r_snapshot.grid_height;
	std::vector<float> filled_height = r_snapshot.hydro_height;
	std::vector<uint8_t> visited(static_cast<size_t>(node_count), 0);
	std::vector<int32_t> visit_order;
	visit_order.reserve(static_cast<size_t>(node_count));
	std::priority_queue<QueueEntry, std::vector<QueueEntry>, QueueEntryCompare> queue;
	const bool uses_ocean_primary_routing = r_snapshot.world_version >= DRY_RIVER_OVERVIEW_VERSION;

	for (int32_t y = 0; y < r_snapshot.grid_height; ++y) {
		for (int32_t x = 0; x < r_snapshot.grid_width; ++x) {
			const int32_t index = r_snapshot.index(x, y);
			if (is_blocked_for_routing(r_snapshot, index)) {
				continue;
			}
			const bool is_outlet = r_snapshot.ocean_band_mask[static_cast<size_t>(index)] != 0 ||
					y == 0 ||
					(!uses_ocean_primary_routing &&
							(r_snapshot.continent_mask[static_cast<size_t>(index)] == 0 ||
									r_snapshot.burning_band_mask[static_cast<size_t>(index)] != 0 ||
									y == r_snapshot.grid_height - 1));
			if (!is_outlet) {
				continue;
			}
			visited[static_cast<size_t>(index)] = 1;
			r_snapshot.downstream_index[static_cast<size_t>(index)] = -1;
			queue.push(QueueEntry{ filled_height[static_cast<size_t>(index)], index });
		}
	}

	std::vector<int32_t> neighbours;
	while (!queue.empty()) {
		const QueueEntry current = queue.top();
		queue.pop();
		if (current.height != filled_height[static_cast<size_t>(current.index)]) {
			continue;
		}
		visit_order.push_back(current.index);
		const int32_t x = current.index % r_snapshot.grid_width;
		const int32_t y = current.index / r_snapshot.grid_width;
		append_neighbours(r_snapshot, x, y, neighbours);
		for (int32_t neighbour : neighbours) {
			if (visited[static_cast<size_t>(neighbour)] != 0 || is_blocked_for_routing(r_snapshot, neighbour)) {
				continue;
			}
			visited[static_cast<size_t>(neighbour)] = 1;
			filled_height[static_cast<size_t>(neighbour)] = std::max(
				r_snapshot.hydro_height[static_cast<size_t>(neighbour)],
				current.height
			);
			r_snapshot.downstream_index[static_cast<size_t>(neighbour)] = current.index;
			queue.push(QueueEntry{ filled_height[static_cast<size_t>(neighbour)], neighbour });
		}
	}

	for (int32_t index = 0; index < node_count; ++index) {
		if (visited[static_cast<size_t>(index)] == 0) {
			r_snapshot.downstream_index[static_cast<size_t>(index)] = -1;
			visit_order.push_back(index);
		}
	}

	std::vector<float> raw_flow = r_snapshot.source_score;
	for (auto iter = visit_order.rbegin(); iter != visit_order.rend(); ++iter) {
		const int32_t index = *iter;
		const int32_t downstream = r_snapshot.downstream_index[static_cast<size_t>(index)];
		if (downstream >= 0) {
			raw_flow[static_cast<size_t>(downstream)] += raw_flow[static_cast<size_t>(index)];
		}
	}

	float max_flow = 0.0f;
	for (float flow : raw_flow) {
		max_flow = std::max(max_flow, flow);
	}
	const float divisor = max_flow > 0.0f ? max_flow : 1.0f;
	for (int32_t index = 0; index < node_count; ++index) {
		r_snapshot.flow_accumulation[static_cast<size_t>(index)] = saturate(raw_flow[static_cast<size_t>(index)] / divisor);
	}

	const float trunk_threshold = visible_flow_threshold(p_river_amount);
	for (int32_t index = 0; index < node_count; ++index) {
		const bool visible = r_snapshot.flow_accumulation[static_cast<size_t>(index)] >= trunk_threshold &&
				r_snapshot.continent_mask[static_cast<size_t>(index)] != 0 &&
				r_snapshot.ocean_band_mask[static_cast<size_t>(index)] == 0 &&
				r_snapshot.burning_band_mask[static_cast<size_t>(index)] == 0 &&
				!is_blocked_for_routing(r_snapshot, index);
		r_snapshot.visible_trunk_mask[static_cast<size_t>(index)] = visible ? 1U : 0U;
		r_snapshot.strahler_order[static_cast<size_t>(index)] = visible ? 1 : 0;
	}

	// Strahler order: collect max upstream order and count of branches at that
	// max per downstream node, then apply rule: if two or more branches share
	// the max order, result = max + 1; otherwise result = max.
	std::vector<int32_t> strahler_max_upstream(static_cast<size_t>(node_count), 0);
	std::vector<int32_t> strahler_max_count(static_cast<size_t>(node_count), 0);
	for (auto iter = visit_order.rbegin(); iter != visit_order.rend(); ++iter) {
		const int32_t index = *iter;
		if (r_snapshot.visible_trunk_mask[static_cast<size_t>(index)] == 0) {
			continue;
		}
		const int32_t downstream = r_snapshot.downstream_index[static_cast<size_t>(index)];
		if (downstream < 0 || r_snapshot.visible_trunk_mask[static_cast<size_t>(downstream)] == 0) {
			continue;
		}
		const int32_t upstream_order = r_snapshot.strahler_order[static_cast<size_t>(index)];
		int32_t &max_order = strahler_max_upstream[static_cast<size_t>(downstream)];
		int32_t &max_count = strahler_max_count[static_cast<size_t>(downstream)];
		if (upstream_order > max_order) {
			max_order = upstream_order;
			max_count = 1;
		} else if (upstream_order == max_order) {
			max_count += 1;
		}
	}
	for (int32_t index = 0; index < node_count; ++index) {
		if (r_snapshot.visible_trunk_mask[static_cast<size_t>(index)] == 0) {
			continue;
		}
		if (strahler_max_upstream[static_cast<size_t>(index)] <= 0) {
			continue;
		}
		const int32_t max_order = strahler_max_upstream[static_cast<size_t>(index)];
		const int32_t max_count = strahler_max_count[static_cast<size_t>(index)];
		r_snapshot.strahler_order[static_cast<size_t>(index)] = std::min(8,
			max_count >= 2 ? max_order + 1 : max_order
		);
	}

	const int32_t max_lake_radius_cells = 1;
	r_snapshot.terminal_lake_near_node.assign(static_cast<size_t>(node_count), 0);
	std::vector<LakeCandidateScore> lake_candidates;
	lake_candidates.reserve(static_cast<size_t>(std::max(1, node_count / 16)));
	for (int32_t index = 0; index < node_count; ++index) {
		const bool is_legacy_terminal = r_snapshot.downstream_index[static_cast<size_t>(index)] < 0 &&
				r_snapshot.flow_accumulation[static_cast<size_t>(index)] >= FLOW_SEA_THRESHOLD;
		const bool is_ocean_primary_basin = uses_ocean_primary_routing &&
				r_snapshot.visible_trunk_mask[static_cast<size_t>(index)] != 0 &&
				r_snapshot.flow_accumulation[static_cast<size_t>(index)] >= 0.20f &&
				r_snapshot.coarse_wall_density[static_cast<size_t>(index)] <= 0.38f;
		if ((!is_legacy_terminal && !is_ocean_primary_basin) ||
				r_snapshot.ocean_band_mask[static_cast<size_t>(index)] != 0 ||
				r_snapshot.burning_band_mask[static_cast<size_t>(index)] != 0 ||
				r_snapshot.continent_mask[static_cast<size_t>(index)] == 0 ||
				is_blocked_for_routing(r_snapshot, index)) {
			continue;
		}
		const int32_t node_y = index / r_snapshot.grid_width;
		if (uses_ocean_primary_routing && (node_y <= 1 || node_y >= r_snapshot.grid_height - 2)) {
			continue;
		}
		const float flow = r_snapshot.flow_accumulation[static_cast<size_t>(index)];
		const float valley = r_snapshot.coarse_valley_score[static_cast<size_t>(index)];
		const float wall = r_snapshot.coarse_wall_density[static_cast<size_t>(index)];
		const float hydro = r_snapshot.hydro_height[static_cast<size_t>(index)];
		const float hydro_mid = 1.0f - saturate(std::abs(hydro - 0.50f) / 0.50f);
		const uint64_t jitter_hash = splitmix64(r_snapshot.signature ^ static_cast<uint64_t>(index) * 0x9e3779b185ebca87ULL);
		const float jitter = static_cast<float>(jitter_hash & 0x3ffULL) / 1023.0f;
		float score = flow * 1.20f + valley * 0.48f + hydro_mid * 0.22f - wall * 0.72f + jitter * 0.08f;
		if (!uses_ocean_primary_routing && is_legacy_terminal) {
			score += 0.75f;
		}
		if (score < (uses_ocean_primary_routing ? 0.74f : 0.0f)) {
			continue;
		}
		lake_candidates.push_back(LakeCandidateScore{ index, score });
	}
	std::sort(lake_candidates.begin(), lake_candidates.end(), [](const LakeCandidateScore &p_a, const LakeCandidateScore &p_b) {
		if (p_a.score != p_b.score) {
			return p_a.score > p_b.score;
		}
		return p_a.index < p_b.index;
	});

	auto is_lake_spacing_clear = [&](int32_t p_index, const std::vector<int32_t> &p_accepted) -> bool {
		constexpr int32_t spacing_radius_cells = 2;
		const int32_t x = p_index % r_snapshot.grid_width;
		const int32_t y = p_index / r_snapshot.grid_width;
		for (int32_t accepted : p_accepted) {
			const int32_t ax = accepted % r_snapshot.grid_width;
			const int32_t ay = accepted / r_snapshot.grid_width;
			const int32_t direct_dx = std::abs(x - ax);
			const int32_t wrapped_dx = std::min(direct_dx, r_snapshot.grid_width - direct_dx);
			const int32_t dy = std::abs(y - ay);
			if (wrapped_dx <= spacing_radius_cells && dy <= spacing_radius_cells) {
				return false;
			}
		}
		return true;
	};

	auto mark_lake = [&](int32_t p_index) {
		r_snapshot.is_terminal_lake_center[static_cast<size_t>(p_index)] = 1U;
		const int32_t cx = p_index % r_snapshot.grid_width;
		const int32_t cy = p_index / r_snapshot.grid_width;
		const int32_t min_y = std::max(0, cy - max_lake_radius_cells);
		const int32_t max_y = std::min(r_snapshot.grid_height - 1, cy + max_lake_radius_cells);
		for (int32_t ly = min_y; ly <= max_y; ++ly) {
			for (int32_t dx = -max_lake_radius_cells; dx <= max_lake_radius_cells; ++dx) {
				const int32_t lx = static_cast<int32_t>(positive_mod(cx + dx, r_snapshot.grid_width));
				r_snapshot.terminal_lake_near_node[static_cast<size_t>(r_snapshot.index(lx, ly))] = 1U;
			}
		}
		const int32_t poly_min_y = std::max(0, cy - max_lake_radius_cells);
		const int32_t poly_max_y = std::min(r_snapshot.grid_height - 1, cy + max_lake_radius_cells);
		const int32_t poly_min_x = static_cast<int32_t>(positive_mod(cx - max_lake_radius_cells, r_snapshot.grid_width));
		const int32_t poly_width = max_lake_radius_cells * 2 + 1;
		PackedVector2Array polygon;
		polygon.append(Vector2(poly_min_x * COARSE_CELL_SIZE_TILES, poly_min_y * COARSE_CELL_SIZE_TILES));
		polygon.append(Vector2((poly_min_x + poly_width) * COARSE_CELL_SIZE_TILES, poly_min_y * COARSE_CELL_SIZE_TILES));
		polygon.append(Vector2((poly_min_x + poly_width) * COARSE_CELL_SIZE_TILES, (poly_max_y + 1) * COARSE_CELL_SIZE_TILES));
		polygon.append(Vector2(poly_min_x * COARSE_CELL_SIZE_TILES, (poly_max_y + 1) * COARSE_CELL_SIZE_TILES));
		r_snapshot.terminal_lake_polygons.push_back(polygon);
	};

	const int32_t target_lake_count = uses_ocean_primary_routing ?
			clamp_value(node_count / 96 + 1, 1, 8) :
			node_count;
	std::vector<int32_t> accepted_lakes;
	accepted_lakes.reserve(static_cast<size_t>(target_lake_count));
	for (const LakeCandidateScore &candidate : lake_candidates) {
		if (static_cast<int32_t>(accepted_lakes.size()) >= target_lake_count) {
			break;
		}
		if (!is_lake_spacing_clear(candidate.index, accepted_lakes)) {
			continue;
		}
		accepted_lakes.push_back(candidate.index);
		mark_lake(candidate.index);
	}

	/*
	 * Older versions kept only true graph terminals. For ocean-primary routing,
	 * lake scars are selected above as sparse inline basins so accepted trunks
	 * still reach the ocean while leaving visible dry lake bowls.
	 */

#ifdef DEBUG_ENABLED
	// Cycle detection: walk every node's downstream chain and assert it terminates.
	r_snapshot.cycle_free = true;
	for (int32_t start = 0; start < node_count; ++start) {
		int32_t slow = start;
		int32_t fast = start;
		while (true) {
			if (r_snapshot.downstream_index[static_cast<size_t>(slow)] < 0) {
				break;
			}
			slow = r_snapshot.downstream_index[static_cast<size_t>(slow)];
			if (r_snapshot.downstream_index[static_cast<size_t>(fast)] < 0) {
				break;
			}
			fast = r_snapshot.downstream_index[static_cast<size_t>(fast)];
			if (r_snapshot.downstream_index[static_cast<size_t>(fast)] < 0) {
				break;
			}
			fast = r_snapshot.downstream_index[static_cast<size_t>(fast)];
			if (slow == fast) {
				r_snapshot.cycle_free = false;
				break;
			}
		}
		if (!r_snapshot.cycle_free) {
			break;
		}
	}
	DEV_ASSERT(r_snapshot.cycle_free && "WorldPrePass downstream graph contains a cycle");
#endif
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

double hash_to_unit(uint64_t p_hash) {
	return static_cast<double>(p_hash & 0xffffULL) / 65535.0;
}

double closest_wrapped_overview_x(double p_x, double p_reference_x, int32_t p_grid_width) {
	if (p_grid_width <= 0) {
		return p_x;
	}
	const double width = static_cast<double>(p_grid_width);
	return p_x - std::round((p_x - p_reference_x) / width) * width;
}

double distance_to_overview_segment(
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
	const double sx = p_ax + t * vx;
	const double sy = p_ay + t * vy;
	const double dx = p_x - sx;
	const double dy = p_y - sy;
	return std::sqrt(dx * dx + dy * dy);
}

std::vector<uint8_t> build_ocean_directed_trunk_mask(const Snapshot &p_snapshot) {
	const int32_t node_count = p_snapshot.grid_width * p_snapshot.grid_height;
	std::vector<uint8_t> result(static_cast<size_t>(node_count), 0);
	std::vector<uint8_t> resolved(static_cast<size_t>(node_count), 0);
	std::vector<uint8_t> reaches_ocean(static_cast<size_t>(node_count), 0);
	const int32_t max_steps = std::max(1, node_count * MAX_CHAIN_STEPS_MULTIPLIER);
	std::vector<int32_t> chain;
	chain.reserve(static_cast<size_t>(std::min(node_count, max_steps)));

	for (int32_t start = 0; start < node_count; ++start) {
		if (p_snapshot.visible_trunk_mask[static_cast<size_t>(start)] == 0) {
			continue;
		}
		chain.clear();
		int32_t current = start;
		bool success = false;
		for (int32_t step = 0; step < max_steps; ++step) {
			if (current < 0 || current >= node_count) {
				break;
			}
			if (resolved[static_cast<size_t>(current)] != 0) {
				success = reaches_ocean[static_cast<size_t>(current)] != 0;
				break;
			}
			chain.push_back(current);
			if (p_snapshot.ocean_band_mask[static_cast<size_t>(current)] != 0) {
				success = true;
				break;
			}
			if (p_snapshot.burning_band_mask[static_cast<size_t>(current)] != 0) {
				break;
			}
			current = p_snapshot.downstream_index[static_cast<size_t>(current)];
		}
		for (int32_t index : chain) {
			resolved[static_cast<size_t>(index)] = 1U;
			reaches_ocean[static_cast<size_t>(index)] = success ? 1U : 0U;
			if (success && p_snapshot.visible_trunk_mask[static_cast<size_t>(index)] != 0) {
				result[static_cast<size_t>(index)] = 1U;
			}
		}
	}

	return result;
}

int32_t resolve_dry_overview_overlay(
	const Snapshot &p_snapshot,
	const std::vector<uint8_t> &p_ocean_directed_trunk_mask,
	float p_coarse_x,
	float p_coarse_y
) {
	if (p_ocean_directed_trunk_mask.empty()) {
		return 0;
	}
	const int32_t node_count = p_snapshot.grid_width * p_snapshot.grid_height;
	int32_t overlay = 0;
	const int32_t center_x = static_cast<int32_t>(std::floor(p_coarse_x + 0.5f));
	const int32_t center_y = clamp_value(static_cast<int32_t>(std::floor(p_coarse_y + 0.5f)), 0, p_snapshot.grid_height - 1);
	for (int32_t dy = -1; dy <= 1; ++dy) {
		const int32_t node_y = center_y + dy;
		if (node_y < 0 || node_y >= p_snapshot.grid_height) {
			continue;
		}
		for (int32_t dx = -1; dx <= 1; ++dx) {
			const int32_t raw_x = center_x + dx;
			const int32_t node_x = static_cast<int32_t>(positive_mod(raw_x, p_snapshot.grid_width));
			const int32_t index = p_snapshot.index(node_x, node_y);
			if (p_snapshot.is_terminal_lake_center[static_cast<size_t>(index)] != 0) {
				const double lx = closest_wrapped_overview_x(static_cast<double>(raw_x), p_coarse_x, p_snapshot.grid_width);
				const double distance = std::sqrt(
					(static_cast<double>(p_coarse_x) - lx) * (static_cast<double>(p_coarse_x) - lx) +
					(static_cast<double>(p_coarse_y) - static_cast<double>(node_y)) *
							(static_cast<double>(p_coarse_y) - static_cast<double>(node_y))
				);
				if (distance <= 0.42) {
					overlay = std::max(overlay, 1);
				}
			}
			if (p_ocean_directed_trunk_mask[static_cast<size_t>(index)] == 0) {
				continue;
			}
			const int32_t downstream = p_snapshot.downstream_index[static_cast<size_t>(index)];
			if (downstream < 0 || downstream >= node_count) {
				continue;
			}
			const int32_t downstream_y = downstream / p_snapshot.grid_width;
			const int32_t downstream_x_wrapped = downstream % p_snapshot.grid_width;
			const double ax = closest_wrapped_overview_x(static_cast<double>(raw_x), p_coarse_x, p_snapshot.grid_width);
			const double bx = closest_wrapped_overview_x(static_cast<double>(downstream_x_wrapped), ax, p_snapshot.grid_width);
			const double ay = static_cast<double>(node_y);
			const double by = static_cast<double>(downstream_y);
			const double dx_segment = bx - ax;
			const double dy_segment = by - ay;
			const double length = std::sqrt(dx_segment * dx_segment + dy_segment * dy_segment);
			double distance = distance_to_overview_segment(
				static_cast<double>(p_coarse_x),
				static_cast<double>(p_coarse_y),
				ax,
				ay,
				bx,
				by
			);
			const float flow = saturate(p_snapshot.flow_accumulation[static_cast<size_t>(index)]);
			if (length > std::numeric_limits<double>::epsilon()) {
				const float valley = saturate(p_snapshot.coarse_valley_score[static_cast<size_t>(index)]);
				const uint64_t bend_hash = splitmix64(
					p_snapshot.signature ^
					static_cast<uint64_t>(index) * 0x9e3779b185ebca87ULL ^
					static_cast<uint64_t>(downstream) * 0xc2b2ae3d27d4eb4fULL
				);
				const double bend_sign = hash_to_unit(bend_hash) * 2.0 - 1.0;
				const double along_sign = hash_to_unit(splitmix64(bend_hash ^ 0x8a5cd789635d2dffULL)) * 2.0 - 1.0;
				const double bend_magnitude = std::min(length * 0.22, 0.10 + static_cast<double>(flow) * 0.24 + static_cast<double>(valley) * 0.16);
				const double along_magnitude = std::min(length * 0.10, 0.18);
				const double tx = dx_segment / length;
				const double ty = dy_segment / length;
				const double nx = -ty;
				const double ny = tx;
				const double mx = (ax + bx) * 0.5 + nx * bend_sign * bend_magnitude + tx * along_sign * along_magnitude;
				const double my = clamp_value(
					(ay + by) * 0.5 + ny * bend_sign * bend_magnitude + ty * along_sign * along_magnitude,
					0.0,
					static_cast<double>(std::max(0, p_snapshot.grid_height - 1))
				);
				const double distance_a = distance_to_overview_segment(
					static_cast<double>(p_coarse_x),
					static_cast<double>(p_coarse_y),
					ax,
					ay,
					mx,
					my
				);
				const double distance_b = distance_to_overview_segment(
					static_cast<double>(p_coarse_x),
					static_cast<double>(p_coarse_y),
					mx,
					my,
					bx,
					by
				);
				distance = std::min(distance_a, distance_b);
			}
			const double shallow_width = 0.22 + static_cast<double>(flow) * 0.16;
			const double deep_width = 0.10 + static_cast<double>(flow) * 0.08;
			if (distance <= deep_width) {
				return 3;
			}
			if (distance <= shallow_width) {
				overlay = std::max(overlay, 2);
			}
		}
	}
	return overlay;
}

} // namespace

int32_t Snapshot::index(int32_t p_x, int32_t p_y) const {
	return p_y * grid_width + p_x;
}

Vector2i Snapshot::node_to_tile_center(int32_t p_x, int32_t p_y) const {
	const int64_t x = std::min<int64_t>(width_tiles - 1, static_cast<int64_t>(p_x) * COARSE_CELL_SIZE_TILES + COARSE_CELL_SIZE_TILES / 2);
	const int64_t y = std::min<int64_t>(height_tiles - 1, static_cast<int64_t>(p_y) * COARSE_CELL_SIZE_TILES + COARSE_CELL_SIZE_TILES / 2);
	return Vector2i(static_cast<int32_t>(x), static_cast<int32_t>(y));
}

uint64_t make_signature(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Settings &p_mountain_settings,
	const FoundationSettings &p_foundation_settings
) {
	uint64_t signature = splitmix64(static_cast<uint64_t>(p_seed));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_world_version) * 0x9e3779b185ebca87ULL);
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.width_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.height_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.ocean_band_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.burning_band_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.pole_orientation));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround((p_foundation_settings.slope_bias + 1.0f) * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_foundation_settings.river_amount * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_mountain_settings.density * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_mountain_settings.scale * 1000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_mountain_settings.continuity * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_mountain_settings.ruggedness * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_mountain_settings.anchor_cell_size));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_mountain_settings.gravity_radius));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_mountain_settings.foot_band * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_mountain_settings.interior_margin));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround((p_mountain_settings.latitude_influence + 1.0f) * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_mountain_settings.world_wrap_width_tiles));
	return signature;
}

std::unique_ptr<Snapshot> build_snapshot(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_mountain_settings,
	const FoundationSettings &p_foundation_settings
) {
	auto started_at = std::chrono::high_resolution_clock::now();
	std::unique_ptr<Snapshot> snapshot = std::make_unique<Snapshot>();
	snapshot->valid = p_foundation_settings.enabled;
	snapshot->seed = p_seed;
	snapshot->world_version = p_world_version;
	snapshot->signature = make_signature(p_seed, p_world_version, p_mountain_settings, p_foundation_settings);
	snapshot->width_tiles = p_foundation_settings.width_tiles;
	snapshot->height_tiles = p_foundation_settings.height_tiles;
	snapshot->ocean_band_tiles = p_foundation_settings.ocean_band_tiles;
	snapshot->burning_band_tiles = p_foundation_settings.burning_band_tiles;
	snapshot->grid_width = std::max<int32_t>(1, static_cast<int32_t>((p_foundation_settings.width_tiles + COARSE_CELL_SIZE_TILES - 1) / COARSE_CELL_SIZE_TILES));
	snapshot->grid_height = std::max<int32_t>(1, static_cast<int32_t>((p_foundation_settings.height_tiles + COARSE_CELL_SIZE_TILES - 1) / COARSE_CELL_SIZE_TILES));

	const int32_t node_count = snapshot->grid_width * snapshot->grid_height;
	snapshot->latitude_t.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->ocean_band_mask.assign(static_cast<size_t>(node_count), 0);
	snapshot->burning_band_mask.assign(static_cast<size_t>(node_count), 0);
	snapshot->continent_mask.assign(static_cast<size_t>(node_count), 0);
	snapshot->hydro_height.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->coarse_wall_density.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->coarse_foot_density.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->coarse_valley_score.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->source_score.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->biome_region_id.assign(static_cast<size_t>(node_count), 0);
	snapshot->downstream_index.assign(static_cast<size_t>(node_count), -1);
	snapshot->flow_accumulation.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->visible_trunk_mask.assign(static_cast<size_t>(node_count), 0);
	snapshot->strahler_order.assign(static_cast<size_t>(node_count), 0);
	snapshot->is_terminal_lake_center.assign(static_cast<size_t>(node_count), 0);

	FastNoiseLite continent_noise = make_noise(mix_seed(p_seed, p_world_version, SEED_SALT_CONTINENT), 1.0f / 2048.0f, 4);
	FastNoiseLite relief_noise = make_noise(mix_seed(p_seed, p_world_version, SEED_SALT_RELIEF), 1.0f / 1536.0f, 3);
	FastNoiseLite source_noise = make_noise(mix_seed(p_seed, p_world_version, SEED_SALT_SOURCE), 1.0f / 1024.0f, 3);
	const mountain_field::Thresholds &thresholds = p_mountain_evaluator.get_thresholds();

	for (int32_t y = 0; y < snapshot->grid_height; ++y) {
		for (int32_t x = 0; x < snapshot->grid_width; ++x) {
			const int32_t index = snapshot->index(x, y);
			const int64_t center_x = snapshot->node_to_tile_center(x, y).x;
			const int64_t center_y = snapshot->node_to_tile_center(x, y).y;
			const float latitude = snapshot->height_tiles <= 1 ?
					0.0f :
					static_cast<float>(center_y) / static_cast<float>(snapshot->height_tiles - 1);
			const bool is_ocean_band = center_y < p_foundation_settings.ocean_band_tiles;
			const bool is_burning_band = center_y >= snapshot->height_tiles - p_foundation_settings.burning_band_tiles;
			const float continent_raw = saturate(
				(sample_cylindrical_noise(continent_noise, static_cast<float>(center_x), static_cast<float>(center_y), static_cast<float>(snapshot->width_tiles)) + 1.0f) * 0.5f
			);
			const bool is_continent = !is_ocean_band && !is_burning_band && continent_raw >= CONTINENT_NOISE_THRESHOLD;

			float elevation_sum = 0.0f;
			int32_t wall_count = 0;
			int32_t foot_count = 0;
			const int32_t sample_steps = 4;
			for (int32_t sample_y = 0; sample_y < sample_steps; ++sample_y) {
				for (int32_t sample_x = 0; sample_x < sample_steps; ++sample_x) {
					const int64_t world_x = static_cast<int64_t>(x) * COARSE_CELL_SIZE_TILES +
							((sample_x * 2 + 1) * COARSE_CELL_SIZE_TILES) / (sample_steps * 2);
					const int64_t world_y = std::min<int64_t>(
						snapshot->height_tiles - 1,
						static_cast<int64_t>(y) * COARSE_CELL_SIZE_TILES +
								((sample_y * 2 + 1) * COARSE_CELL_SIZE_TILES) / (sample_steps * 2)
					);
					const int64_t sample_world_x = resolve_mountain_sample_x(world_x, p_world_version, p_foundation_settings);
					const float elevation = p_mountain_evaluator.sample_elevation(sample_world_x, world_y);
					elevation_sum += elevation;
					if (elevation >= thresholds.t_wall) {
						wall_count += 1;
					} else if (elevation >= thresholds.t_edge) {
						foot_count += 1;
					}
				}
			}

			const float sample_count = static_cast<float>(sample_steps * sample_steps);
			const float mountain_average = elevation_sum / sample_count;
			const float relief = (sample_cylindrical_noise(relief_noise, static_cast<float>(center_x), static_cast<float>(center_y), static_cast<float>(snapshot->width_tiles)) + 1.0f) * 0.5f;
			const float slope = (latitude - 0.5f) * p_foundation_settings.slope_bias * 0.22f;
			const float wall_density = static_cast<float>(wall_count) / sample_count;
			const float foot_density = static_cast<float>(foot_count) / sample_count;
			const float valley = saturate(1.0f - wall_density - 0.5f * foot_density);
			const float hydro = saturate(mountain_average * 0.62f + relief * 0.32f + slope);
			const float source_raw = (sample_cylindrical_noise(source_noise, static_cast<float>(center_x), static_cast<float>(center_y), static_cast<float>(snapshot->width_tiles)) + 1.0f) * 0.5f;

			snapshot->latitude_t[static_cast<size_t>(index)] = latitude;
			snapshot->ocean_band_mask[static_cast<size_t>(index)] = is_ocean_band ? 1U : 0U;
			snapshot->burning_band_mask[static_cast<size_t>(index)] = is_burning_band ? 1U : 0U;
			snapshot->continent_mask[static_cast<size_t>(index)] = is_continent ? 1U : 0U;
			snapshot->hydro_height[static_cast<size_t>(index)] = hydro;
			snapshot->coarse_wall_density[static_cast<size_t>(index)] = wall_density;
			snapshot->coarse_foot_density[static_cast<size_t>(index)] = foot_density;
			snapshot->coarse_valley_score[static_cast<size_t>(index)] = valley;
			snapshot->source_score[static_cast<size_t>(index)] = is_continent ?
					source_raw * smoothstep(0.44f, 0.82f, hydro) * valley :
					0.0f;
			snapshot->biome_region_id[static_cast<size_t>(index)] = resolve_region_id(p_seed, p_world_version, x, y);
		}
	}

	build_flow_graph(*snapshot, p_foundation_settings.river_amount);
	auto finished_at = std::chrono::high_resolution_clock::now();
	snapshot->compute_time_ms = std::chrono::duration<double, std::milli>(finished_at - started_at).count();
	return snapshot;
}

Dictionary make_debug_snapshot(const Snapshot &p_snapshot, int64_t p_layer_mask, int64_t p_downscale_factor) {
	Dictionary result;
	if (!p_snapshot.valid) {
		return result;
	}
	result["grid_width"] = p_snapshot.grid_width;
	result["grid_height"] = p_snapshot.grid_height;
	result["coarse_cell_size_tiles"] = COARSE_CELL_SIZE_TILES;
	result["world_width_tiles"] = p_snapshot.width_tiles;
	result["world_height_tiles"] = p_snapshot.height_tiles;
	result["ocean_band_tiles"] = p_snapshot.ocean_band_tiles;
	result["burning_band_tiles"] = p_snapshot.burning_band_tiles;
	result["seed"] = p_snapshot.seed;
	result["world_version"] = p_snapshot.world_version;
	result["signature"] = static_cast<int64_t>(p_snapshot.signature & 0x7fffffffffffffffULL);
	result["compute_time_ms"] = p_snapshot.compute_time_ms;
	result["cycle_free"] = p_snapshot.cycle_free;
	result["layer_mask"] = p_layer_mask;
	result["downscale_factor"] = std::max<int64_t>(1, p_downscale_factor);
	result["latitude_t"] = make_float_array(p_snapshot.latitude_t);
	result["ocean_band_mask"] = make_byte_array(p_snapshot.ocean_band_mask);
	result["burning_band_mask"] = make_byte_array(p_snapshot.burning_band_mask);
	result["continent_mask"] = make_byte_array(p_snapshot.continent_mask);
	result["hydro_height"] = make_float_array(p_snapshot.hydro_height);
	result["coarse_wall_density"] = make_float_array(p_snapshot.coarse_wall_density);
	result["coarse_foot_density"] = make_float_array(p_snapshot.coarse_foot_density);
	result["coarse_valley_score"] = make_float_array(p_snapshot.coarse_valley_score);
	result["source_score"] = make_float_array(p_snapshot.source_score);
	result["biome_region_id"] = make_int_array(p_snapshot.biome_region_id);
	result["downstream_index"] = make_int_array(p_snapshot.downstream_index);
	result["flow_accumulation"] = make_float_array(p_snapshot.flow_accumulation);
	result["visible_trunk_mask"] = make_byte_array(p_snapshot.visible_trunk_mask);
	result["strahler_order"] = make_int_array(p_snapshot.strahler_order);
	result["is_terminal_lake_center"] = make_byte_array(p_snapshot.is_terminal_lake_center);
	result["terminal_lake_near_node"] = make_byte_array(p_snapshot.terminal_lake_near_node);
	Array polygons;
	for (const PackedVector2Array &polygon : p_snapshot.terminal_lake_polygons) {
		polygons.append(polygon);
	}
	result["terminal_lake_polygons"] = polygons;
	return result;
}

float sample_snapshot_float_bilinear(
	const std::vector<float> &p_values,
	const Snapshot &p_snapshot,
	float p_x,
	float p_y
) {
	if (p_values.empty() || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0) {
		return 0.0f;
	}
	const int32_t x0 = static_cast<int32_t>(std::floor(p_x));
	const int32_t y0 = clamp_value(static_cast<int32_t>(std::floor(p_y)), 0, p_snapshot.grid_height - 1);
	const int32_t x1 = x0 + 1;
	const int32_t y1 = clamp_value(y0 + 1, 0, p_snapshot.grid_height - 1);
	const float tx = p_x - static_cast<float>(std::floor(p_x));
	const float ty = p_y - static_cast<float>(std::floor(p_y));
	const int32_t wx0 = static_cast<int32_t>(positive_mod(x0, p_snapshot.grid_width));
	const int32_t wx1 = static_cast<int32_t>(positive_mod(x1, p_snapshot.grid_width));
	const float v00 = p_values[static_cast<size_t>(p_snapshot.index(wx0, y0))];
	const float v10 = p_values[static_cast<size_t>(p_snapshot.index(wx1, y0))];
	const float v01 = p_values[static_cast<size_t>(p_snapshot.index(wx0, y1))];
	const float v11 = p_values[static_cast<size_t>(p_snapshot.index(wx1, y1))];
	const float top = v00 + (v10 - v00) * tx;
	const float bottom = v01 + (v11 - v01) * tx;
	return top + (bottom - top) * ty;
}

OverviewMasks sample_overview_masks(
	const Snapshot &p_snapshot,
	FastNoiseLite &p_continent_noise,
	int64_t p_world_x,
	int64_t p_world_y
) {
	const int64_t world_x = positive_mod(p_world_x, p_snapshot.width_tiles);
	const int64_t world_y = clamp_value<int64_t>(p_world_y, 0, std::max<int64_t>(0, p_snapshot.height_tiles - 1));
	const bool is_ocean_band = world_y < p_snapshot.ocean_band_tiles;
	const bool is_burning_band = world_y >= p_snapshot.height_tiles - p_snapshot.burning_band_tiles;
	const float continent_raw = saturate(
		(sample_cylindrical_noise(
			p_continent_noise,
			static_cast<float>(world_x),
			static_cast<float>(world_y),
			static_cast<float>(p_snapshot.width_tiles)
		) + 1.0f) * 0.5f
	);
	return OverviewMasks{
		is_ocean_band,
		is_burning_band,
		!is_ocean_band && !is_burning_band && continent_raw >= CONTINENT_NOISE_THRESHOLD
	};
}

void write_overview_rgba(
	PackedByteArray &r_bytes,
	int32_t p_offset,
	const OverviewMasks &p_masks,
	float p_hydro,
	float p_wall
) {
	if (p_masks.ocean_band) {
		write_rgba(r_bytes, p_offset, 10, 72, 130);
		return;
	}
	if (p_masks.burning_band) {
		write_rgba(r_bytes, p_offset, 102, 36, 24);
		return;
	}
	if (!p_masks.continent) {
		write_rgba(r_bytes, p_offset, 24, 86, 126);
		return;
	}
	const float hydro = saturate(p_hydro);
	const float wall = saturate(p_wall);
	uint8_t base = static_cast<uint8_t>(clamp_value(72.0f + hydro * 96.0f, 0.0f, 255.0f));
	uint8_t red = static_cast<uint8_t>(std::min(255.0f, base + 24.0f));
	uint8_t green = static_cast<uint8_t>(std::min(255.0f, base + 14.0f));
	uint8_t blue = static_cast<uint8_t>(std::max(36.0f, base - 24.0f));
	if (wall > 0.45f) {
		red = green = blue = static_cast<uint8_t>(140 + std::min(80.0f, wall * 80.0f));
	}
	write_rgba(r_bytes, p_offset, red, green, blue);
}

Ref<Image> make_overview_image(
	const Snapshot &p_snapshot,
	const mountain_field::Evaluator &p_mountain_evaluator,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings,
	int64_t p_layer_mask,
	int64_t p_pixels_per_cell
) {
	(void)p_layer_mask;
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0) {
		return Ref<Image>();
	}
	const int32_t pixels_per_cell = clamp_value(static_cast<int32_t>(p_pixels_per_cell), 1, 8);
	const int32_t pixel_window_tiles = COARSE_CELL_SIZE_TILES / pixels_per_cell;
	constexpr int32_t pixel_sample_steps = 4;
	const mountain_field::Thresholds &thresholds = p_mountain_evaluator.get_thresholds();
	const int32_t image_width = p_snapshot.grid_width * pixels_per_cell;
	const int32_t image_height = p_snapshot.grid_height * pixels_per_cell;
	PackedByteArray bytes;
	bytes.resize(image_width * image_height * 4);
	FastNoiseLite continent_noise = make_noise(mix_seed(p_snapshot.seed, p_snapshot.world_version, SEED_SALT_CONTINENT), 1.0f / 2048.0f, 4);
	const std::vector<uint8_t> ocean_directed_trunk_mask = p_world_version >= DRY_RIVER_OVERVIEW_VERSION ?
			build_ocean_directed_trunk_mask(p_snapshot) :
			std::vector<uint8_t>();
	for (int32_t y = 0; y < image_height; ++y) {
		for (int32_t x = 0; x < image_width; ++x) {
			const float coarse_sample_x = (static_cast<float>(x) + 0.5f) / static_cast<float>(pixels_per_cell) - 0.5f;
			const float coarse_sample_y = (static_cast<float>(y) + 0.5f) / static_cast<float>(pixels_per_cell) - 0.5f;
			const int64_t mask_world_x = static_cast<int64_t>(std::floor(
				((static_cast<double>(x) + 0.5) * static_cast<double>(COARSE_CELL_SIZE_TILES)) /
				static_cast<double>(pixels_per_cell)
			));
			const int64_t mask_world_y = static_cast<int64_t>(std::floor(
				((static_cast<double>(y) + 0.5) * static_cast<double>(COARSE_CELL_SIZE_TILES)) /
				static_cast<double>(pixels_per_cell)
			));
			const int64_t pixel_origin_tile_x = static_cast<int64_t>(x) * pixel_window_tiles;
			const int64_t pixel_origin_tile_y = static_cast<int64_t>(y) * pixel_window_tiles;
			int32_t wall_count = 0;
			for (int32_t sample_y = 0; sample_y < pixel_sample_steps; ++sample_y) {
				for (int32_t sample_x = 0; sample_x < pixel_sample_steps; ++sample_x) {
					const int64_t world_x = pixel_origin_tile_x +
							((sample_x * 2 + 1) * pixel_window_tiles) / (pixel_sample_steps * 2);
					const int64_t world_y_raw = pixel_origin_tile_y +
							((sample_y * 2 + 1) * pixel_window_tiles) / (pixel_sample_steps * 2);
					const int64_t world_y = std::min<int64_t>(p_snapshot.height_tiles - 1, world_y_raw);
					const int64_t sample_world_x = resolve_mountain_sample_x(world_x, p_world_version, p_foundation_settings);
					const float elevation = p_mountain_evaluator.sample_elevation(sample_world_x, world_y);
					if (elevation >= thresholds.t_wall) {
						wall_count += 1;
					}
				}
			}
			const float pixel_wall_density = static_cast<float>(wall_count) /
					static_cast<float>(pixel_sample_steps * pixel_sample_steps);
			const OverviewMasks masks = sample_overview_masks(p_snapshot, continent_noise, mask_world_x, mask_world_y);
			write_overview_rgba(
				bytes,
				(y * image_width + x) * 4,
				masks,
				sample_snapshot_float_bilinear(p_snapshot.hydro_height, p_snapshot, coarse_sample_x, coarse_sample_y),
				pixel_wall_density
			);
			const int32_t offset = (y * image_width + x) * 4;
			if (masks.continent) {
				const int32_t dry_overlay = resolve_dry_overview_overlay(
					p_snapshot,
					ocean_directed_trunk_mask,
					coarse_sample_x,
					coarse_sample_y
				);
				if (dry_overlay == 3) {
					write_rgba(bytes, offset, 58, 45, 32);
				} else if (dry_overlay == 2) {
					write_rgba(bytes, offset, 118, 86, 50);
				} else if (dry_overlay == 1) {
					write_rgba(bytes, offset, 104, 78, 47);
				}
			}
		}
	}
	return Image::create_from_data(image_width, image_height, false, Image::FORMAT_RGBA8, bytes);
}

Dictionary resolve_spawn_tile(const Snapshot &p_snapshot) {
	Dictionary result;
	if (!p_snapshot.valid) {
		result["success"] = false;
		result["message"] = "WorldPrePass snapshot is not valid.";
		return result;
	}

	float best_score = -std::numeric_limits<float>::infinity();
	int32_t best_index = -1;
	for (int32_t index = 0; index < p_snapshot.grid_width * p_snapshot.grid_height; ++index) {
		if (p_snapshot.ocean_band_mask[static_cast<size_t>(index)] != 0 ||
				p_snapshot.burning_band_mask[static_cast<size_t>(index)] != 0 ||
				p_snapshot.continent_mask[static_cast<size_t>(index)] == 0 ||
				p_snapshot.coarse_wall_density[static_cast<size_t>(index)] >= SPAWN_MAX_WALL_DENSITY ||
				p_snapshot.visible_trunk_mask[static_cast<size_t>(index)] != 0 ||
				p_snapshot.is_terminal_lake_center[static_cast<size_t>(index)] != 0 ||
				p_snapshot.terminal_lake_near_node[static_cast<size_t>(index)] != 0) {
			continue;
		}
		const float valley = p_snapshot.coarse_valley_score[static_cast<size_t>(index)];
		const float hydro = p_snapshot.hydro_height[static_cast<size_t>(index)];
		const float hydro_mid = 1.0f - saturate(std::abs(hydro - 0.52f) / 0.52f);
		const float wall_penalty = p_snapshot.coarse_wall_density[static_cast<size_t>(index)] * 0.75f;
		const bool preferred_band = valley >= SPAWN_MIN_VALLEY_SCORE && hydro >= SPAWN_HYDRO_MIN && hydro <= SPAWN_HYDRO_MAX;
		const float score = valley * 1.8f + hydro_mid * 0.9f - wall_penalty + (preferred_band ? 0.65f : 0.0f);
		if (score > best_score) {
			best_score = score;
			best_index = index;
		}
	}

	if (best_index < 0) {
		result["success"] = false;
		result["message"] = "No valid foundation spawn node found.";
		return result;
	}

	const int32_t node_x = best_index % p_snapshot.grid_width;
	const int32_t node_y = best_index / p_snapshot.grid_width;
	const Vector2i spawn_tile = p_snapshot.node_to_tile_center(node_x, node_y);
	const int32_t patch_size = static_cast<int32_t>(SPAWN_SAFE_PATCH_MAX_TILE - SPAWN_SAFE_PATCH_MIN_TILE + 1);
	const int32_t rect_x = static_cast<int32_t>(clamp_value<int64_t>(
		static_cast<int64_t>(spawn_tile.x) - patch_size / 2,
		0,
		std::max<int64_t>(0, p_snapshot.width_tiles - patch_size)
	));
	const int32_t rect_y = static_cast<int32_t>(clamp_value<int64_t>(
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
	result["hydro_height"] = p_snapshot.hydro_height[static_cast<size_t>(best_index)];
	result["coarse_wall_density"] = p_snapshot.coarse_wall_density[static_cast<size_t>(best_index)];
	return result;
}

} // namespace world_prepass
