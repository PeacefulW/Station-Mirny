#include "world_core.h"

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

bool is_spawn_safety_area(const Vector2i &coord, int64_t local_x, int64_t local_y) {
	if (coord.x != 0 || coord.y != 0) {
		return false;
	}
	return local_x >= 12 && local_x <= 20 && local_y >= 12 && local_y <= 20;
}

} // namespace

void WorldCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate_chunk_packet", "seed", "coord", "world_version"), &WorldCore::generate_chunk_packet);
}

Dictionary WorldCore::generate_chunk_packet(int64_t p_seed, Vector2i p_coord, int64_t p_world_version) const {
	PackedInt32Array terrain_ids;
	terrain_ids.resize(CELL_COUNT);
	PackedByteArray walkable_flags;
	walkable_flags.resize(CELL_COUNT);

	for (int64_t local_y = 0; local_y < CHUNK_SIZE; local_y++) {
		for (int64_t local_x = 0; local_x < CHUNK_SIZE; local_x++) {
			const int64_t index = local_y * CHUNK_SIZE + local_x;
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + local_x;
			const int64_t world_y = static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + local_y;

			int64_t terrain_id = TERRAIN_PLAINS_GROUND;
			uint8_t walkable = 1U;

			if (!is_spawn_safety_area(p_coord, local_x, local_y)) {
				const uint64_t h = tile_hash(p_seed, p_world_version, world_x, world_y);
				if ((h % 29ULL) == 0ULL) {
					terrain_id = TERRAIN_PLAINS_ROCK;
					walkable = 0U;
				}
			}

			terrain_ids.set(index, terrain_id);
			walkable_flags.set(index, walkable);
		}
	}

	Dictionary packet;
	packet["chunk_coord"] = p_coord;
	packet["world_seed"] = p_seed;
	packet["world_version"] = p_world_version;
	packet["terrain_ids"] = terrain_ids;
	packet["walkable_flags"] = walkable_flags;
	return packet;
}
