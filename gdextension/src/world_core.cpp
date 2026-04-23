#include "world_core.h"
#include "autotile_47.h"
#include "mountain_field.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <deque>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

using namespace godot;

namespace {

constexpr int64_t CHUNK_SIZE = 32;
constexpr int64_t CELL_COUNT = CHUNK_SIZE * CHUNK_SIZE;

constexpr int64_t TERRAIN_PLAINS_GROUND = 0;
constexpr int64_t TERRAIN_LEGACY_BLOCKED = 1;
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
[[maybe_unused]] constexpr size_t HIERARCHICAL_CACHE_LIMIT = 12;

uint64_t splitmix64(uint64_t x) {
	x += 0x9e3779b97f4a7c15ULL;
	x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
	x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
	return x ^ (x >> 31U);
}

uint64_t tile_hash(int64_t seed, int64_t world_version, int64_t world_x, int64_t world_y) {
	uint64_t h = splitmix64(static_cast<uint64_t>(seed));
	h = splitmix64(h ^ static_cast<uint64_t>(world_version) * 0x9e3779b185ebca87ULL);
	h = splitmix64(h ^ static_cast<uint64_t>(world_x) * 0xc2b2ae3d27d4eb4fULL);
	h = splitmix64(h ^ static_cast<uint64_t>(world_y) * 0x165667b19e3779f9ULL);
	return h;
}

int64_t wrap_world_x(int64_t p_world_x) {
	int64_t wrapped = p_world_x % WORLD_WRAP_WIDTH_TILES;
	if (wrapped < 0) {
		wrapped += WORLD_WRAP_WIDTH_TILES;
	}
	return wrapped;
}

[[maybe_unused]] int64_t floor_div(int64_t p_value, int64_t p_divisor) {
	int64_t quotient = p_value / p_divisor;
	const int64_t remainder = p_value % p_divisor;
	if (remainder != 0 && ((remainder < 0) != (p_divisor < 0))) {
		quotient -= 1;
	}
	return quotient;
}

bool is_base_legacy_blocked_at_world(int64_t seed, int64_t world_version, int64_t world_x, int64_t world_y) {
	if (world_version >= 4) {
		return false;
	}
	if (mountain_field::is_spawn_safety_area_at_world(world_version, world_x, world_y)) {
		return false;
	}
	const uint64_t h = tile_hash(seed, world_version, world_x, world_y);
	return (h % 29ULL) == 0ULL;
}

int64_t resolve_base_terrain_id_at_world(int64_t seed, int64_t world_version, int64_t world_x, int64_t world_y) {
	if (is_base_legacy_blocked_at_world(seed, world_version, world_x, world_y)) {
		return TERRAIN_LEGACY_BLOCKED;
	}
	return TERRAIN_PLAINS_GROUND;
}

bool is_base_legacy_blocked_neighbor_at_world(int64_t seed, int64_t world_version, int64_t world_x, int64_t world_y) {
	return resolve_base_terrain_id_at_world(seed, world_version, world_x, world_y) == TERRAIN_LEGACY_BLOCKED;
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

int64_t resolve_base_legacy_blocked_atlas_index(
	int64_t seed,
	int64_t world_version,
	int64_t world_x,
	int64_t world_y
) {
	const bool north = is_base_legacy_blocked_neighbor_at_world(seed, world_version, world_x, world_y - 1);
	const bool north_east = is_base_legacy_blocked_neighbor_at_world(seed, world_version, world_x + 1, world_y - 1);
	const bool east = is_base_legacy_blocked_neighbor_at_world(seed, world_version, world_x + 1, world_y);
	const bool south_east = is_base_legacy_blocked_neighbor_at_world(seed, world_version, world_x + 1, world_y + 1);
	const bool south = is_base_legacy_blocked_neighbor_at_world(seed, world_version, world_x, world_y + 1);
	const bool south_west = is_base_legacy_blocked_neighbor_at_world(seed, world_version, world_x - 1, world_y + 1);
	const bool west = is_base_legacy_blocked_neighbor_at_world(seed, world_version, world_x - 1, world_y);
	const bool north_west = is_base_legacy_blocked_neighbor_at_world(seed, world_version, world_x - 1, world_y - 1);
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

[[maybe_unused]] uint64_t make_cache_signature(
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

[[maybe_unused]] uint64_t make_macro_key(int64_t p_macro_x, int64_t p_macro_y) {
	uint64_t key = splitmix64(static_cast<uint64_t>(p_macro_x));
	key = splitmix64(key ^ static_cast<uint64_t>(p_macro_y) * 0x9e3779b185ebca87ULL);
	return key;
}

struct MountainTileKey {
	int64_t x = 0;
	int64_t y = 0;

	bool operator==(const MountainTileKey &p_other) const {
		return x == p_other.x && y == p_other.y;
	}
};

struct MountainTileKeyHash {
	size_t operator()(const MountainTileKey &p_key) const {
		uint64_t mixed = splitmix64(static_cast<uint64_t>(p_key.x));
		mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_key.y) * 0x9e3779b185ebca87ULL);
		return static_cast<size_t>(mixed);
	}
};

int32_t make_component_mountain_id(
	int64_t p_seed,
	int64_t p_world_version,
	const MountainTileKey &p_representative
) {
	uint64_t mixed = splitmix64(static_cast<uint64_t>(p_seed));
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_world_version) * 0x9e3779b185ebca87ULL);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_representative.x) * 0xc2b2ae3d27d4eb4fULL);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_representative.y) * 0x165667b19e3779f9ULL);
	const int32_t id = static_cast<int32_t>(mixed & 0x7fffffffULL);
	return id == 0 ? 1 : id;
}

class PacketMountainComponentSolver {
public:
	PacketMountainComponentSolver(
		int64_t p_seed,
		int64_t p_world_version,
		const mountain_field::Evaluator &p_evaluator,
		const mountain_field::Thresholds &p_thresholds
	) :
			seed_(p_seed),
			world_version_(p_world_version),
			evaluator_(p_evaluator),
			thresholds_(p_thresholds) {}

	int32_t resolve_mountain_id(int64_t p_world_x, int64_t p_world_y, float p_elevation) {
		if (p_elevation < thresholds_.t_edge) {
			return 0;
		}

		const MountainTileKey key{ wrap_world_x(p_world_x), p_world_y };
		const auto found = mountain_id_by_tile_.find(key);
		if (found != mountain_id_by_tile_.end()) {
			return found->second;
		}

		solve_component(key);
		const auto resolved = mountain_id_by_tile_.find(key);
		return resolved != mountain_id_by_tile_.end() ? resolved->second : 0;
	}

	bool is_representative_tile(int64_t p_world_x, int64_t p_world_y, int32_t p_mountain_id) const {
		if (p_mountain_id <= 0) {
			return false;
		}
		const auto found = representative_by_mountain_id_.find(p_mountain_id);
		return found != representative_by_mountain_id_.end() &&
				found->second.x == wrap_world_x(p_world_x) &&
				found->second.y == p_world_y;
	}

private:
	static bool is_better_representative(
		const MountainTileKey &p_candidate,
		float p_candidate_elevation,
		const MountainTileKey &p_current,
		float p_current_elevation
	) {
		if (p_candidate_elevation != p_current_elevation) {
			return p_candidate_elevation > p_current_elevation;
		}
		return p_candidate.x < p_current.x ||
				(p_candidate.x == p_current.x && p_candidate.y < p_current.y);
	}

	float sample_elevation_cached(const MountainTileKey &p_tile) {
		const auto found = elevation_by_tile_.find(p_tile);
		if (found != elevation_by_tile_.end()) {
			return found->second;
		}
		const float elevation = evaluator_.sample_elevation(p_tile.x, p_tile.y);
		elevation_by_tile_.emplace(p_tile, elevation);
		return elevation;
	}

	void assign_known_component(
		const std::vector<MountainTileKey> &p_tiles,
		int32_t p_mountain_id
	) {
		for (const MountainTileKey &tile : p_tiles) {
			mountain_id_by_tile_[tile] = p_mountain_id;
		}
	}

	void solve_component(const MountainTileKey &p_seed) {
		std::deque<MountainTileKey> queue;
		std::unordered_set<MountainTileKey, MountainTileKeyHash> visited;
		std::vector<MountainTileKey> discovered_tiles;

		queue.push_back(p_seed);
		visited.insert(p_seed);
		discovered_tiles.push_back(p_seed);

		MountainTileKey representative = p_seed;
		float representative_elevation = sample_elevation_cached(p_seed);

		while (!queue.empty()) {
			const MountainTileKey current = queue.front();
			queue.pop_front();

			const float current_elevation = sample_elevation_cached(current);
			if (current_elevation < thresholds_.t_edge) {
				continue;
			}
			if (is_better_representative(current, current_elevation, representative, representative_elevation)) {
				representative = current;
				representative_elevation = current_elevation;
			}

			for (const MountainTileKey &offset : {
					MountainTileKey{ -1, 0 },
					MountainTileKey{ 1, 0 },
					MountainTileKey{ 0, -1 },
					MountainTileKey{ 0, 1 },
				}) {
				const MountainTileKey neighbor{
					wrap_world_x(current.x + offset.x),
					current.y + offset.y,
				};
				if (visited.find(neighbor) != visited.end()) {
					continue;
				}

				const auto cached_component = mountain_id_by_tile_.find(neighbor);
				if (cached_component != mountain_id_by_tile_.end()) {
					assign_known_component(discovered_tiles, cached_component->second);
					return;
				}

				const float neighbor_elevation = sample_elevation_cached(neighbor);
				if (neighbor_elevation < thresholds_.t_edge) {
					continue;
				}

				visited.insert(neighbor);
				queue.push_back(neighbor);
				discovered_tiles.push_back(neighbor);
			}
		}

		const int32_t mountain_id = make_component_mountain_id(seed_, world_version_, representative);
		representative_by_mountain_id_[mountain_id] = representative;
		assign_known_component(discovered_tiles, mountain_id);
	}

	int64_t seed_ = 0;
	int64_t world_version_ = 0;
	const mountain_field::Evaluator &evaluator_;
	const mountain_field::Thresholds &thresholds_;
	std::unordered_map<MountainTileKey, float, MountainTileKeyHash> elevation_by_tile_;
	std::unordered_map<MountainTileKey, int32_t, MountainTileKeyHash> mountain_id_by_tile_;
	std::unordered_map<int32_t, MountainTileKey> representative_by_mountain_id_;
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
	ClassDB::bind_method(D_METHOD("generate_chunk_packet", "seed", "coord", "world_version", "settings_packed"), &WorldCore::generate_chunk_packet);
}

WorldCore::WorldCore() :
		hierarchical_macro_cache_(std::make_unique<HierarchicalMacroCache>()) {}

WorldCore::~WorldCore() = default;

Dictionary WorldCore::generate_chunk_packet(int64_t p_seed, Vector2i p_coord, int64_t p_world_version, PackedFloat32Array p_settings_packed) {
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

	const bool mountains_enabled = p_settings_packed.size() >= SETTINGS_PACKED_LAYOUT_FIELD_COUNT;
	mountain_field::Settings mountain_settings;
	mountain_field::Evaluator mountain_evaluator(p_seed, p_world_version, mountain_settings);
	mountain_field::Settings effective_mountain_settings = mountain_evaluator.get_settings();
	int64_t mountain_border = 1;
	int64_t mountain_grid_side = CHUNK_SIZE + 2;
	std::vector<float> mountain_elevations;
	std::vector<int32_t> mountain_ids;

	if (mountains_enabled) {
		mountain_settings = unpack_mountain_settings(p_settings_packed);
		mountain_evaluator = mountain_field::Evaluator(p_seed, p_world_version, mountain_settings);
		effective_mountain_settings = mountain_evaluator.get_settings();
		mountain_border = std::max<int64_t>(1, effective_mountain_settings.interior_margin);
		mountain_grid_side = CHUNK_SIZE + mountain_border * 2;
		mountain_elevations.resize(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0.0f);
		mountain_ids.resize(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0);
	}

	const mountain_field::Thresholds &mountain_thresholds = mountain_evaluator.get_thresholds();
	PacketMountainComponentSolver component_solver(
		p_seed,
		p_world_version,
		mountain_evaluator,
		mountain_thresholds
	);

	auto resolve_mountain_id_at_world = [&](int64_t p_world_x, int64_t p_world_y, float p_elevation) -> int32_t {
		return component_solver.resolve_mountain_id(p_world_x, p_world_y, p_elevation);
	};

	auto is_component_representative_tile = [&](int64_t p_world_x, int64_t p_world_y, int32_t p_mountain_id) -> bool {
		return component_solver.is_representative_tile(p_world_x, p_world_y, p_mountain_id);
	};

	if (mountains_enabled) {
		for (int64_t sample_y = 0; sample_y < mountain_grid_side; ++sample_y) {
			for (int64_t sample_x = 0; sample_x < mountain_grid_side; ++sample_x) {
				const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + sample_x - mountain_border;
				const int64_t world_y = static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + sample_y - mountain_border;
				const int64_t sample_index = sample_y * mountain_grid_side + sample_x;
				const float elevation = mountain_evaluator.sample_elevation(world_x, world_y);
				mountain_elevations[static_cast<size_t>(sample_index)] = elevation;
				mountain_ids[static_cast<size_t>(sample_index)] = resolve_mountain_id_at_world(world_x, world_y, elevation);
			}
		}
	}

	for (int64_t local_y = 0; local_y < CHUNK_SIZE; local_y++) {
		for (int64_t local_x = 0; local_x < CHUNK_SIZE; local_x++) {
			const int64_t index = local_y * CHUNK_SIZE + local_x;
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + local_x;
			const int64_t world_y = static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + local_y;

			int64_t terrain_id = resolve_base_terrain_id_at_world(p_seed, p_world_version, world_x, world_y);
			int64_t terrain_atlas_index = 0;
			uint8_t walkable = terrain_id == TERRAIN_LEGACY_BLOCKED ? 0U : 1U;
			int32_t resolved_mountain_id = 0;
			uint8_t resolved_mountain_flags = 0U;
			int32_t resolved_mountain_atlas_index = 0;

			if (mountains_enabled) {
				const int64_t grid_x = local_x + mountain_border;
				const int64_t grid_y = local_y + mountain_border;
				const int64_t grid_index = grid_y * mountain_grid_side + grid_x;

				const float elevation = mountain_elevations[static_cast<size_t>(grid_index)];
				resolved_mountain_id = mountain_ids[static_cast<size_t>(grid_index)];
				if (resolved_mountain_id > 0 || p_world_version < 3) {
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
						bool is_interior = effective_mountain_settings.interior_margin == 0;
						if (effective_mountain_settings.interior_margin > 0) {
							is_interior = true;
							for (int32_t distance = 1; distance <= effective_mountain_settings.interior_margin; ++distance) {
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
					resolved_mountain_atlas_index = mountain_evaluator.resolve_mountain_atlas_index(
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

					if ((resolved_mountain_flags & MOUNTAIN_FLAG_WALL) != 0U) {
						const bool north_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)] >= mountain_thresholds.t_edge;
						const bool north_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
						const bool east_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
						const bool south_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
						const bool south_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)] >= mountain_thresholds.t_edge;
						const bool south_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;
						const bool west_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;
						const bool north_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;

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
						const bool north_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)] >= mountain_thresholds.t_edge;
						const bool north_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
						const bool east_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
						const bool south_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
						const bool south_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)] >= mountain_thresholds.t_edge;
						const bool south_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;
						const bool west_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;
						const bool north_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;

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
				} else if (p_world_version == 3 && elevation >= mountain_thresholds.t_edge) {
					terrain_id = TERRAIN_LEGACY_BLOCKED;
					walkable = 0U;
				}
			}

			if (!mountains_enabled || ((resolved_mountain_flags & (MOUNTAIN_FLAG_WALL | MOUNTAIN_FLAG_FOOT)) == 0U)) {
				if (terrain_id == TERRAIN_PLAINS_GROUND) {
					terrain_atlas_index = resolve_base_ground_atlas_index(world_x, world_y, p_seed);
				} else if (terrain_id == TERRAIN_LEGACY_BLOCKED) {
					terrain_atlas_index = resolve_base_legacy_blocked_atlas_index(
						p_seed,
						p_world_version,
						world_x,
						world_y
					);
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
