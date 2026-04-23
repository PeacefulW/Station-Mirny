#include "world_core.h"
#include "autotile_47.h"
#include "mountain_field.h"

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

namespace {

constexpr int64_t CHUNK_SIZE = 32;
constexpr int64_t CELL_COUNT = CHUNK_SIZE * CHUNK_SIZE;

constexpr int64_t TERRAIN_PLAINS_GROUND = 0;
constexpr int64_t TERRAIN_MOUNTAIN_WALL = 3;
constexpr int64_t TERRAIN_MOUNTAIN_FOOT = 4;

constexpr int64_t SETTINGS_PACKED_LAYOUT_DENSITY = 0;
constexpr int64_t SETTINGS_PACKED_LAYOUT_SCALE = 1;
constexpr int64_t SETTINGS_PACKED_LAYOUT_CONTINUITY = 2;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RUGGEDNESS = 3;
constexpr int64_t SETTINGS_PACKED_LAYOUT_ANCHOR_CELL_SIZE = 4;
constexpr int64_t SETTINGS_PACKED_LAYOUT_GRAVITY_RADIUS = 5;
constexpr int64_t SETTINGS_PACKED_LAYOUT_FOOT_BAND = 6;
constexpr int64_t SETTINGS_PACKED_LAYOUT_INTERIOR_MARGIN = 7;
constexpr int64_t SETTINGS_PACKED_LAYOUT_LATITUDE_INFLUENCE = 8;
constexpr int64_t SETTINGS_PACKED_LAYOUT_FIELD_COUNT = 9;

constexpr uint8_t MOUNTAIN_FLAG_WALL = 1U << 1U;
constexpr uint8_t MOUNTAIN_FLAG_FOOT = 1U << 2U;
constexpr uint8_t MOUNTAIN_FLAG_INTERIOR = 1U << 0U;
constexpr uint8_t MOUNTAIN_FLAG_ANCHOR = 1U << 3U;
constexpr int64_t WORLD_WRAP_WIDTH_TILES = 65536;
constexpr size_t HIERARCHICAL_CACHE_LIMIT = 64;

uint64_t splitmix64(uint64_t x) {
	x += 0x9e3779b97f4a7c15ULL;
	x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
	x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
	return x ^ (x >> 31U);
}

int64_t wrap_world_x(int64_t p_world_x) {
	int64_t wrapped = p_world_x % WORLD_WRAP_WIDTH_TILES;
	if (wrapped < 0) {
		wrapped += WORLD_WRAP_WIDTH_TILES;
	}
	return wrapped;
}

int64_t floor_div(int64_t p_value, int64_t p_divisor) {
	int64_t quotient = p_value / p_divisor;
	const int64_t remainder = p_value % p_divisor;
	if (remainder != 0 && ((remainder < 0) != (p_divisor < 0))) {
		quotient -= 1;
	}
	return quotient;
}

int64_t resolve_macro_cell_x_for_world(int64_t p_world_x, int32_t p_macro_cell_size) {
	return floor_div(wrap_world_x(p_world_x), static_cast<int64_t>(p_macro_cell_size));
}

int64_t resolve_macro_cell_y_for_world(int64_t p_world_y, int32_t p_macro_cell_size) {
	return floor_div(p_world_y, static_cast<int64_t>(p_macro_cell_size));
}

int64_t resolve_base_ground_atlas_index(int64_t world_x, int64_t world_y, int64_t seed) {
	// TODO: switch plains-ground edge solving to water adjacency once water
	// terrain exists. For now, ground always uses solid atlas variants only.
	return autotile_47::resolve_atlas_index(
		true,
		true,
		true,
		true,
		true,
		true,
		true,
		true,
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

uint64_t make_cache_signature(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Settings &p_settings
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
}

WorldCore::WorldCore() :
		hierarchical_macro_cache_(std::make_unique<HierarchicalMacroCache>()) {}

WorldCore::~WorldCore() = default;

const mountain_field::HierarchicalMacroSolve &WorldCore::_get_or_build_hierarchical_macro_solve(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Settings &p_settings,
	int64_t p_macro_cell_x,
	int64_t p_macro_cell_y
) {
	HierarchicalMacroCache &cache = *hierarchical_macro_cache_;
	const uint64_t signature = make_cache_signature(p_seed, p_world_version, p_settings);
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

Dictionary WorldCore::_generate_chunk_packet(
	int64_t p_seed,
	Vector2i p_coord,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_effective_mountain_settings
) {
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
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(p_world_x, macro_cell_size);
		const int64_t macro_cell_y = resolve_macro_cell_y_for_world(p_world_y, macro_cell_size);
		if (cached_macro_solve == nullptr || macro_cell_x != cached_macro_cell_x || macro_cell_y != cached_macro_cell_y) {
			cached_macro_solve = &_get_or_build_hierarchical_macro_solve(
				p_seed,
				p_world_version,
				p_effective_mountain_settings,
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
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(p_world_x, macro_cell_size);
		const int64_t macro_cell_y = resolve_macro_cell_y_for_world(p_world_y, macro_cell_size);
		const mountain_field::HierarchicalMacroSolve &solve = _get_or_build_hierarchical_macro_solve(
			p_seed,
			p_world_version,
			p_effective_mountain_settings,
			macro_cell_x,
			macro_cell_y
		);
		return solve.is_representative_tile(p_world_x, p_world_y, p_mountain_id);
	};

	for (int64_t sample_y = 0; sample_y < mountain_grid_side; ++sample_y) {
		for (int64_t sample_x = 0; sample_x < mountain_grid_side; ++sample_x) {
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + sample_x - mountain_border;
			const int64_t world_y = static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + sample_y - mountain_border;
			const int64_t sample_index = sample_y * mountain_grid_side + sample_x;
			const float elevation = p_mountain_evaluator.sample_elevation(world_x, world_y);
			mountain_elevations[static_cast<size_t>(sample_index)] = elevation;
			mountain_ids[static_cast<size_t>(sample_index)] = resolve_mountain_id_at_world(world_x, world_y, elevation);
		}
	}

	for (int64_t local_y = 0; local_y < CHUNK_SIZE; ++local_y) {
		for (int64_t local_x = 0; local_x < CHUNK_SIZE; ++local_x) {
			const int64_t index = local_y * CHUNK_SIZE + local_x;
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + local_x;
			const int64_t world_y = static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + local_y;
			const int64_t grid_x = local_x + mountain_border;
			const int64_t grid_y = local_y + mountain_border;
			const int64_t grid_index = grid_y * mountain_grid_side + grid_x;

			const float elevation = mountain_elevations[static_cast<size_t>(grid_index)];
			const int32_t resolved_mountain_id = mountain_ids[static_cast<size_t>(grid_index)];
			uint8_t resolved_mountain_flags = 0U;
			int32_t resolved_mountain_atlas_index = 0;
			int64_t terrain_id = TERRAIN_PLAINS_GROUND;
			int64_t terrain_atlas_index = resolve_base_ground_atlas_index(world_x, world_y, p_seed);
			uint8_t walkable = 1U;

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
					if (is_component_representative_tile(world_x, world_y, resolved_mountain_id)) {
						resolved_mountain_flags = static_cast<uint8_t>(resolved_mountain_flags | MOUNTAIN_FLAG_ANCHOR);
					}
				}

				resolved_mountain_atlas_index = p_mountain_evaluator.resolve_mountain_atlas_index(
					world_x,
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
						world_x,
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
						world_x,
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

			terrain_ids.set(index, terrain_id);
			terrain_atlas_indices.set(index, terrain_atlas_index);
			walkable_flags.set(index, walkable);
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
	packet["mountain_id_per_tile"] = mountain_id_per_tile;
	packet["mountain_flags"] = mountain_flags;
	packet["mountain_atlas_indices"] = mountain_atlas_indices;
	return packet;
}

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

	ERR_FAIL_COND_V_MSG(
		p_settings_packed.size() != SETTINGS_PACKED_LAYOUT_FIELD_COUNT,
		Array{},
		"WorldCore.generate_chunk_packets_batch requires the full mountain settings payload."
	);
	ERR_FAIL_COND_V_MSG(
		!mountain_field::uses_hierarchical_labeling(p_world_version),
		Array{},
		"WorldCore.generate_chunk_packets_batch requires hierarchical mountain labeling (world_version >= 6)."
	);

	const mountain_field::Settings mountain_settings = unpack_mountain_settings(p_settings_packed);
	const mountain_field::Evaluator mountain_evaluator(p_seed, p_world_version, mountain_settings);
	const mountain_field::Settings &effective_mountain_settings = mountain_evaluator.get_settings();
	const int32_t macro_cell_size = mountain_field::get_hierarchical_macro_cell_size(p_world_version);

	std::vector<ChunkMacroGroup> macro_groups;
	std::unordered_map<uint64_t, int32_t> group_index_by_key;
	for (int32_t index = 0; index < p_coords.size(); ++index) {
		const Vector2 coord_value = p_coords[index];
		const Vector2i chunk_coord(
			static_cast<int32_t>(coord_value.x),
			static_cast<int32_t>(coord_value.y)
		);
		const int64_t chunk_origin_x = static_cast<int64_t>(chunk_coord.x) * CHUNK_SIZE;
		const int64_t chunk_origin_y = static_cast<int64_t>(chunk_coord.y) * CHUNK_SIZE;
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(chunk_origin_x, macro_cell_size);
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
			group.macro_cell_x,
			group.macro_cell_y
		);
		for (int32_t packet_index : group.chunk_indices) {
			const Vector2 coord_value = p_coords[packet_index];
			const Vector2i chunk_coord(
				static_cast<int32_t>(coord_value.x),
				static_cast<int32_t>(coord_value.y)
			);
			packets[packet_index] = _generate_chunk_packet(
				p_seed,
				chunk_coord,
				p_world_version,
				mountain_evaluator,
				effective_mountain_settings
			);
		}
	}
	return packets;
}
