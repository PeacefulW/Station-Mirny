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
constexpr int32_t RIVER_SEGMENT_RECORD_SIZE = 6;

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
	PackedByteArray bytes;
	bytes.resize(image_width * image_height * 4);
	for (int32_t y = 0; y < image_height; ++y) {
		for (int32_t x = 0; x < image_width; ++x) {
			const int32_t node_x = clamp_value(x / pixels_per_cell, 0, p_snapshot.grid_width - 1);
			const int32_t node_y = clamp_value(y / pixels_per_cell, 0, p_snapshot.grid_height - 1);
			const int32_t index = p_snapshot.index(node_x, node_y);
			const int32_t offset = (y * image_width + x) * 4;
			if (p_snapshot.ocean_sink_mask[static_cast<size_t>(index)] != 0U) {
				write_rgba(bytes, offset, 38, 89, 128);
				continue;
			}
			if (p_snapshot.mountain_exclusion_mask[static_cast<size_t>(index)] != 0U) {
				write_rgba(bytes, offset, 138, 134, 122);
				continue;
			}
			if (p_snapshot.river_node_mask.size() == static_cast<size_t>(p_snapshot.grid_width * p_snapshot.grid_height) &&
					p_snapshot.river_node_mask[static_cast<size_t>(index)] != 0U) {
				const uint8_t order = p_snapshot.river_stream_order.size() > static_cast<size_t>(index) ?
						p_snapshot.river_stream_order[static_cast<size_t>(index)] :
						1U;
				const uint8_t boost = static_cast<uint8_t>(std::min<int32_t>(70, static_cast<int32_t>(order) * 10));
				write_rgba(bytes, offset, 38, static_cast<uint8_t>(112 + boost), 190);
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
