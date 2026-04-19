#include "world_core.h"
#include "autotile_47.h"

#include <cstdint>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

using namespace godot;

namespace {

constexpr int64_t CHUNK_SIZE = 32;
constexpr int64_t CELL_COUNT = CHUNK_SIZE * CHUNK_SIZE;

constexpr int64_t TERRAIN_PLAINS_GROUND = 0;
constexpr int64_t TERRAIN_PLAINS_ROCK = 1;

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

} // namespace

void WorldCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate_chunk_packet", "seed", "coord", "world_version"), &WorldCore::generate_chunk_packet);
}

Dictionary WorldCore::generate_chunk_packet(int64_t p_seed, Vector2i p_coord, int64_t p_world_version) const {
	PackedInt32Array terrain_ids;
	terrain_ids.resize(CELL_COUNT);
	PackedInt32Array terrain_atlas_indices;
	terrain_atlas_indices.resize(CELL_COUNT);
	PackedByteArray walkable_flags;
	walkable_flags.resize(CELL_COUNT);

	for (int64_t local_y = 0; local_y < CHUNK_SIZE; local_y++) {
		for (int64_t local_x = 0; local_x < CHUNK_SIZE; local_x++) {
			const int64_t index = local_y * CHUNK_SIZE + local_x;
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + local_x;
			const int64_t world_y = static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + local_y;

			const int64_t terrain_id = resolve_base_terrain_id_at_world(p_seed, p_world_version, world_x, world_y);
			int64_t terrain_atlas_index = 0;
			uint8_t walkable = terrain_id == TERRAIN_PLAINS_ROCK ? 0U : 1U;

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

			terrain_ids.set(index, terrain_id);
			terrain_atlas_indices.set(index, terrain_atlas_index);
			walkable_flags.set(index, walkable);
		}
	}

	Dictionary packet;
	packet["chunk_coord"] = p_coord;
	packet["world_seed"] = p_seed;
	packet["world_version"] = p_world_version;
	packet["terrain_ids"] = terrain_ids;
	packet["terrain_atlas_indices"] = terrain_atlas_indices;
	packet["walkable_flags"] = walkable_flags;
	return packet;
}
