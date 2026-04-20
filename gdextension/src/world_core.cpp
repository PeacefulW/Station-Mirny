#include "world_core.h"
#include "autotile_47.h"
#include "mountain_field.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
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
constexpr int64_t TERRAIN_PLAINS_ROCK = 1;
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

bool is_spawn_safety_area_at_world(int64_t world_x, int64_t world_y) {
	return world_x >= 12 && world_x <= 20 && world_y >= 12 && world_y <= 20;
}

bool is_base_rock_at_world(int64_t seed, int64_t world_version, int64_t world_x, int64_t world_y) {
	if (is_spawn_safety_area_at_world(world_x, world_y)) {
		return false;
	}
	const uint64_t h = tile_hash(seed, world_version, world_x, world_y);
	return (h % 29ULL) == 0ULL;
}

int64_t resolve_base_terrain_id_at_world(int64_t seed, int64_t world_version, int64_t world_x, int64_t world_y) {
	if (is_base_rock_at_world(seed, world_version, world_x, world_y)) {
		return TERRAIN_PLAINS_ROCK;
	}
	return TERRAIN_PLAINS_GROUND;
}

bool is_base_rock_neighbor_at_world(int64_t seed, int64_t world_version, int64_t world_x, int64_t world_y) {
	return resolve_base_terrain_id_at_world(seed, world_version, world_x, world_y) == TERRAIN_PLAINS_ROCK;
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

int64_t resolve_base_rock_atlas_index(
	int64_t seed,
	int64_t world_version,
	int64_t world_x,
	int64_t world_y
) {
	const bool north = is_base_rock_neighbor_at_world(seed, world_version, world_x, world_y - 1);
	const bool north_east = is_base_rock_neighbor_at_world(seed, world_version, world_x + 1, world_y - 1);
	const bool east = is_base_rock_neighbor_at_world(seed, world_version, world_x + 1, world_y);
	const bool south_east = is_base_rock_neighbor_at_world(seed, world_version, world_x + 1, world_y + 1);
	const bool south = is_base_rock_neighbor_at_world(seed, world_version, world_x, world_y + 1);
	const bool south_west = is_base_rock_neighbor_at_world(seed, world_version, world_x - 1, world_y + 1);
	const bool west = is_base_rock_neighbor_at_world(seed, world_version, world_x - 1, world_y);
	const bool north_west = is_base_rock_neighbor_at_world(seed, world_version, world_x - 1, world_y - 1);
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

} // namespace

void WorldCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate_chunk_packet", "seed", "coord", "world_version", "settings_packed"), &WorldCore::generate_chunk_packet);
}

Dictionary WorldCore::generate_chunk_packet(int64_t p_seed, Vector2i p_coord, int64_t p_world_version, PackedFloat32Array p_settings_packed) const {
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
	int64_t mountain_border = 1;
	int64_t mountain_grid_side = CHUNK_SIZE + 2;
	std::vector<float> mountain_elevations;
	std::vector<int32_t> mountain_ids;

	if (mountains_enabled) {
		mountain_settings = unpack_mountain_settings(p_settings_packed);
		mountain_evaluator = mountain_field::Evaluator(p_seed, p_world_version, mountain_settings);
		mountain_border = std::max<int64_t>(1, mountain_settings.interior_margin);
		mountain_grid_side = CHUNK_SIZE + mountain_border * 2;
		mountain_elevations.resize(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0.0f);
		mountain_ids.resize(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0);

		for (int64_t sample_y = 0; sample_y < mountain_grid_side; ++sample_y) {
			for (int64_t sample_x = 0; sample_x < mountain_grid_side; ++sample_x) {
				const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + sample_x - mountain_border;
				const int64_t world_y = static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + sample_y - mountain_border;
				const int64_t sample_index = sample_y * mountain_grid_side + sample_x;
				const float elevation = mountain_evaluator.sample_elevation(world_x, world_y);
				mountain_elevations[static_cast<size_t>(sample_index)] = elevation;
				mountain_ids[static_cast<size_t>(sample_index)] = mountain_evaluator.resolve_mountain_id(world_x, world_y, elevation);
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
			uint8_t walkable = terrain_id == TERRAIN_PLAINS_ROCK ? 0U : 1U;
			int32_t resolved_mountain_id = 0;
			uint8_t resolved_mountain_flags = 0U;
			int32_t resolved_mountain_atlas_index = 0;

			if (mountains_enabled) {
				const int64_t grid_x = local_x + mountain_border;
				const int64_t grid_y = local_y + mountain_border;
				const int64_t grid_index = grid_y * mountain_grid_side + grid_x;

				const float elevation = mountain_elevations[static_cast<size_t>(grid_index)];
				resolved_mountain_id = mountain_ids[static_cast<size_t>(grid_index)];
				const int32_t north_id = mountain_ids[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)];
				const int32_t north_east_id = mountain_ids[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))];
				const int32_t east_id = mountain_ids[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))];
				const int32_t south_east_id = mountain_ids[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))];
				const int32_t south_id = mountain_ids[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)];
				const int32_t south_west_id = mountain_ids[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))];
				const int32_t west_id = mountain_ids[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))];
				const int32_t north_west_id = mountain_ids[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))];

				resolved_mountain_flags = mountain_evaluator.resolve_mountain_flags(
					world_x,
					world_y,
					elevation,
					resolved_mountain_id,
					north_id,
					east_id,
					south_id,
					west_id
				);
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
					const mountain_field::Thresholds &thresholds = mountain_evaluator.get_thresholds();
					const bool north_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)] >= thresholds.t_edge;
					const bool north_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))] >= thresholds.t_edge;
					const bool east_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))] >= thresholds.t_edge;
					const bool south_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))] >= thresholds.t_edge;
					const bool south_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)] >= thresholds.t_edge;
					const bool south_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))] >= thresholds.t_edge;
					const bool west_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))] >= thresholds.t_edge;
					const bool north_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))] >= thresholds.t_edge;

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
					const mountain_field::Thresholds &thresholds = mountain_evaluator.get_thresholds();
					const bool north_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)] >= thresholds.t_edge;
					const bool north_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))] >= thresholds.t_edge;
					const bool east_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))] >= thresholds.t_edge;
					const bool south_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))] >= thresholds.t_edge;
					const bool south_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)] >= thresholds.t_edge;
					const bool south_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))] >= thresholds.t_edge;
					const bool west_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))] >= thresholds.t_edge;
					const bool north_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))] >= thresholds.t_edge;

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

			if (!mountains_enabled || ((resolved_mountain_flags & (MOUNTAIN_FLAG_WALL | MOUNTAIN_FLAG_FOOT)) == 0U)) {
				if (terrain_id == TERRAIN_PLAINS_GROUND) {
					terrain_atlas_index = resolve_base_ground_atlas_index(world_x, world_y, p_seed);
				} else if (terrain_id == TERRAIN_PLAINS_ROCK) {
					terrain_atlas_index = resolve_base_rock_atlas_index(
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
