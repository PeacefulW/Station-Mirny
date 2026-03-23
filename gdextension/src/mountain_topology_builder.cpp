#include "mountain_topology_builder.h"

#include <deque>

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

MountainTopologyBuilder::MountainTopologyBuilder() {}
MountainTopologyBuilder::~MountainTopologyBuilder() {}

void MountainTopologyBuilder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("clear"), &MountainTopologyBuilder::clear);
    ClassDB::bind_method(D_METHOD("set_chunk", "chunk_coord", "terrain", "chunk_size"), &MountainTopologyBuilder::set_chunk);
    ClassDB::bind_method(D_METHOD("remove_chunk", "chunk_coord"), &MountainTopologyBuilder::remove_chunk);
    ClassDB::bind_method(D_METHOD("update_tile", "tile_pos", "terrain_type"), &MountainTopologyBuilder::update_tile);
    ClassDB::bind_method(D_METHOD("ensure_built"), &MountainTopologyBuilder::ensure_built);
    ClassDB::bind_method(D_METHOD("get_mountain_key_at_tile", "tile_pos"), &MountainTopologyBuilder::get_mountain_key_at_tile);
    ClassDB::bind_method(D_METHOD("get_mountain_tiles", "mountain_key"), &MountainTopologyBuilder::get_mountain_tiles);
    ClassDB::bind_method(D_METHOD("get_mountain_open_tiles", "mountain_key"), &MountainTopologyBuilder::get_mountain_open_tiles);
    ClassDB::bind_method(D_METHOD("get_mountain_tiles_by_chunk", "mountain_key"), &MountainTopologyBuilder::get_mountain_tiles_by_chunk);
    ClassDB::bind_method(D_METHOD("get_mountain_open_tiles_by_chunk", "mountain_key"), &MountainTopologyBuilder::get_mountain_open_tiles_by_chunk);
    ClassDB::bind_method(D_METHOD("get_mountain_chunk_coords", "mountain_key"), &MountainTopologyBuilder::get_mountain_chunk_coords);
    ClassDB::bind_method(D_METHOD("rebuild_topology", "chunk_terrain_by_coord", "chunk_size"), &MountainTopologyBuilder::rebuild_topology);
}

void MountainTopologyBuilder::clear() {
    chunk_map.clear();
    mountain_key_by_tile.clear();
    mountain_tiles_by_key.clear();
    mountain_open_tiles_by_key.clear();
    mountain_tiles_by_key_by_chunk.clear();
    mountain_open_tiles_by_key_by_chunk.clear();
    dirty = true;
}

void MountainTopologyBuilder::set_chunk(Vector2i p_chunk_coord, PackedByteArray p_terrain, int p_chunk_size) {
    chunk_size = p_chunk_size;
    ChunkData data;
    data.terrain = p_terrain;
    chunk_map[_from_vector2i(p_chunk_coord)] = data;
    dirty = true;
}

void MountainTopologyBuilder::remove_chunk(Vector2i p_chunk_coord) {
    chunk_map.erase(_from_vector2i(p_chunk_coord));
    dirty = true;
}

void MountainTopologyBuilder::update_tile(Vector2i p_tile_pos, int p_terrain_type) {
    TilePos tile_pos = _from_vector2i(p_tile_pos);
    TilePos chunk_coord;
    chunk_coord.x = _floor_div(tile_pos.x, chunk_size);
    chunk_coord.y = _floor_div(tile_pos.y, chunk_size);

    auto chunk_it = chunk_map.find(chunk_coord);
    if (chunk_it == chunk_map.end()) {
        return;
    }

    PackedByteArray &terrain = chunk_it->second.terrain;
    const int local_x = _positive_mod(tile_pos.x, chunk_size);
    const int local_y = _positive_mod(tile_pos.y, chunk_size);
    const int idx = local_y * chunk_size + local_x;
    if (idx < 0 || idx >= terrain.size()) {
        return;
    }

    const uint8_t old_type = static_cast<uint8_t>(terrain[idx]);
    const uint8_t new_type = static_cast<uint8_t>(p_terrain_type);
    terrain[idx] = new_type;

    const bool old_is_mountain = _is_mountain_topology_tile(old_type);
    const bool new_is_mountain = _is_mountain_topology_tile(new_type);
    if (dirty) {
        return;
    }

    if (!old_is_mountain || !new_is_mountain) {
        dirty = true;
        return;
    }

    const bool old_is_open = _is_open_tile(old_type);
    const bool new_is_open = _is_open_tile(new_type);
    if (old_is_open == new_is_open) {
        return;
    }

    const Vector2i invalid_key = Vector2i(999999, 999999);
    const Vector2i mountain_key = mountain_key_by_tile.get(p_tile_pos, invalid_key);
    if (mountain_key == invalid_key) {
        dirty = true;
        return;
    }

    Dictionary open_tiles = mountain_open_tiles_by_key.get(mountain_key, Dictionary());
    Dictionary open_tiles_by_chunk = mountain_open_tiles_by_key_by_chunk.get(mountain_key, Dictionary());
    Dictionary chunk_open_tiles = open_tiles_by_chunk.get(_to_vector2i(chunk_coord), Dictionary());

    if (new_is_open) {
        open_tiles[p_tile_pos] = true;
        chunk_open_tiles[_to_vector2i(tile_pos)] = true;
        open_tiles_by_chunk[_to_vector2i(chunk_coord)] = chunk_open_tiles;
    } else {
        open_tiles.erase(p_tile_pos);
        chunk_open_tiles.erase(_to_vector2i(tile_pos));
        if (chunk_open_tiles.is_empty()) {
            open_tiles_by_chunk.erase(_to_vector2i(chunk_coord));
        } else {
            open_tiles_by_chunk[_to_vector2i(chunk_coord)] = chunk_open_tiles;
        }
    }

    mountain_open_tiles_by_key[mountain_key] = open_tiles;
    mountain_open_tiles_by_key_by_chunk[mountain_key] = open_tiles_by_chunk;
}

void MountainTopologyBuilder::ensure_built() {
    if (!dirty) {
        return;
    }

    Dictionary rebuilt = _rebuild_topology_internal();
    mountain_key_by_tile = rebuilt["mountain_key_by_tile"];
    mountain_tiles_by_key = rebuilt["mountain_tiles_by_key"];
    mountain_open_tiles_by_key = rebuilt["mountain_open_tiles_by_key"];
    mountain_tiles_by_key_by_chunk = rebuilt["mountain_tiles_by_key_by_chunk"];
    mountain_open_tiles_by_key_by_chunk = rebuilt["mountain_open_tiles_by_key_by_chunk"];
    dirty = false;
}

Vector2i MountainTopologyBuilder::get_mountain_key_at_tile(Vector2i p_tile_pos) {
    ensure_built();
    return mountain_key_by_tile.get(p_tile_pos, Vector2i(999999, 999999));
}

Dictionary MountainTopologyBuilder::get_mountain_tiles(Vector2i p_mountain_key) {
    ensure_built();
    return mountain_tiles_by_key.get(p_mountain_key, Dictionary());
}

Dictionary MountainTopologyBuilder::get_mountain_open_tiles(Vector2i p_mountain_key) {
    ensure_built();
    return mountain_open_tiles_by_key.get(p_mountain_key, Dictionary());
}

Dictionary MountainTopologyBuilder::get_mountain_tiles_by_chunk(Vector2i p_mountain_key) {
    ensure_built();
    return mountain_tiles_by_key_by_chunk.get(p_mountain_key, Dictionary());
}

Dictionary MountainTopologyBuilder::get_mountain_open_tiles_by_chunk(Vector2i p_mountain_key) {
    ensure_built();
    return mountain_open_tiles_by_key_by_chunk.get(p_mountain_key, Dictionary());
}

Array MountainTopologyBuilder::get_mountain_chunk_coords(Vector2i p_mountain_key) {
    ensure_built();
    Array result;
    Dictionary by_chunk = mountain_tiles_by_key_by_chunk.get(p_mountain_key, Dictionary());
    Array keys = by_chunk.keys();
    for (int i = 0; i < keys.size(); i++) {
        result.append(keys[i]);
    }
    return result;
}

bool MountainTopologyBuilder::_is_mountain_topology_tile(uint8_t p_terrain_type) {
    return p_terrain_type == 1 || p_terrain_type == 5 || p_terrain_type == 6;
}

bool MountainTopologyBuilder::_is_open_tile(uint8_t p_terrain_type) {
    return p_terrain_type == 5 || p_terrain_type == 6;
}

int MountainTopologyBuilder::_floor_div(int value, int divisor) {
    int q = value / divisor;
    int r = value % divisor;
    if (r != 0 && value < 0) {
        q -= 1;
    }
    return q;
}

int MountainTopologyBuilder::_positive_mod(int value, int divisor) {
    int result = value % divisor;
    if (result < 0) {
        result += divisor;
    }
    return result;
}

Vector2i MountainTopologyBuilder::_to_vector2i(const TilePos &tile) {
    return Vector2i(tile.x, tile.y);
}

MountainTopologyBuilder::TilePos MountainTopologyBuilder::_from_vector2i(const Vector2i &tile) {
    TilePos result;
    result.x = tile.x;
    result.y = tile.y;
    return result;
}

bool MountainTopologyBuilder::_try_get_terrain(const ChunkTerrainMap &chunk_map, int chunk_size, const TilePos &tile_pos, uint8_t &out_terrain) const {
    TilePos chunk_coord;
    chunk_coord.x = _floor_div(tile_pos.x, chunk_size);
    chunk_coord.y = _floor_div(tile_pos.y, chunk_size);

    auto chunk_it = chunk_map.find(chunk_coord);
    if (chunk_it == chunk_map.end()) {
        return false;
    }

    const PackedByteArray &terrain = chunk_it->second.terrain;
    const int local_x = _positive_mod(tile_pos.x, chunk_size);
    const int local_y = _positive_mod(tile_pos.y, chunk_size);
    const int idx = local_y * chunk_size + local_x;
    if (idx < 0 || idx >= terrain.size()) {
        return false;
    }

    out_terrain = static_cast<uint8_t>(terrain[idx]);
    return true;
}

Dictionary MountainTopologyBuilder::_build_component_dictionary(const TileSet &tiles) const {
    Dictionary result;
    for (const TilePos &tile : tiles) {
        result[_to_vector2i(tile)] = true;
    }
    return result;
}

Dictionary MountainTopologyBuilder::_build_component_by_chunk_dictionary(const TilesByChunkMap &tiles_by_chunk) const {
    Dictionary result;
    for (const auto &entry : tiles_by_chunk) {
        result[_to_vector2i(entry.first)] = _build_component_dictionary(entry.second);
    }
    return result;
}

Dictionary MountainTopologyBuilder::rebuild_topology(Dictionary p_chunk_terrain_by_coord, int p_chunk_size) {
    chunk_size = p_chunk_size;
    chunk_map.clear();

    Array chunk_keys = p_chunk_terrain_by_coord.keys();
    for (int i = 0; i < chunk_keys.size(); i++) {
        Vector2i chunk_coord = chunk_keys[i];
        PackedByteArray terrain = p_chunk_terrain_by_coord[chunk_coord];
        ChunkData data;
        data.terrain = terrain;
        chunk_map[_from_vector2i(chunk_coord)] = data;
    }

    dirty = true;
    return _rebuild_topology_internal();
}

Dictionary MountainTopologyBuilder::_rebuild_topology_internal() {
    std::unordered_set<TilePos, TilePosHash> visited;
    Dictionary mountain_key_by_tile;
    Dictionary mountain_tiles_by_key;
    Dictionary mountain_open_tiles_by_key;
    Dictionary mountain_tiles_by_key_by_chunk;
    Dictionary mountain_open_tiles_by_key_by_chunk;

    for (const auto &chunk_entry : chunk_map) {
        const TilePos &chunk_coord = chunk_entry.first;
        const PackedByteArray &terrain = chunk_entry.second.terrain;

        for (int local_y = 0; local_y < chunk_size; local_y++) {
            for (int local_x = 0; local_x < chunk_size; local_x++) {
                const int idx = local_y * chunk_size + local_x;
                const uint8_t terrain_type = static_cast<uint8_t>(terrain[idx]);
                if (!_is_mountain_topology_tile(terrain_type)) {
                    continue;
                }

                TilePos global_tile;
                global_tile.x = chunk_coord.x * chunk_size + local_x;
                global_tile.y = chunk_coord.y * chunk_size + local_y;

                if (visited.find(global_tile) != visited.end()) {
                    continue;
                }

                std::deque<TilePos> queue;
                TileSet component_tiles;
                TileSet component_open_tiles;
                TilesByChunkMap component_tiles_by_chunk;
                TilesByChunkMap component_open_tiles_by_chunk;
                TilePos component_key = global_tile;

                queue.push_back(global_tile);
                visited.insert(global_tile);

                while (!queue.empty()) {
                    const TilePos current = queue.front();
                    queue.pop_front();

                    component_tiles.insert(current);
                    TilePos current_chunk_coord;
                    current_chunk_coord.x = _floor_div(current.x, chunk_size);
                    current_chunk_coord.y = _floor_div(current.y, chunk_size);
                    component_tiles_by_chunk[current_chunk_coord].insert(current);

                    if (current.y < component_key.y || (current.y == component_key.y && current.x < component_key.x)) {
                        component_key = current;
                    }

                    uint8_t current_type = 0;
                    if (_try_get_terrain(chunk_map, chunk_size, current, current_type) && _is_open_tile(current_type)) {
                        component_open_tiles.insert(current);
                        component_open_tiles_by_chunk[current_chunk_coord].insert(current);
                    }

                    static const int dirs[4][2] = {
                        {-1, 0},
                        {1, 0},
                        {0, -1},
                        {0, 1},
                    };
                    for (const auto &dir : dirs) {
                        TilePos next_tile;
                        next_tile.x = current.x + dir[0];
                        next_tile.y = current.y + dir[1];

                        if (visited.find(next_tile) != visited.end()) {
                            continue;
                        }

                        uint8_t next_type = 0;
                        if (!_try_get_terrain(chunk_map, chunk_size, next_tile, next_type)) {
                            continue;
                        }
                        if (!_is_mountain_topology_tile(next_type)) {
                            continue;
                        }

                        visited.insert(next_tile);
                        queue.push_back(next_tile);
                    }
                }

                const Vector2i component_key_v = _to_vector2i(component_key);
                for (const TilePos &tile : component_tiles) {
                    mountain_key_by_tile[_to_vector2i(tile)] = component_key_v;
                }
                mountain_tiles_by_key[component_key_v] = _build_component_dictionary(component_tiles);
                mountain_open_tiles_by_key[component_key_v] = _build_component_dictionary(component_open_tiles);
                mountain_tiles_by_key_by_chunk[component_key_v] = _build_component_by_chunk_dictionary(component_tiles_by_chunk);
                mountain_open_tiles_by_key_by_chunk[component_key_v] = _build_component_by_chunk_dictionary(component_open_tiles_by_chunk);
            }
        }
    }

    Dictionary result;
    result["mountain_key_by_tile"] = mountain_key_by_tile;
    result["mountain_tiles_by_key"] = mountain_tiles_by_key;
    result["mountain_open_tiles_by_key"] = mountain_open_tiles_by_key;
    result["mountain_tiles_by_key_by_chunk"] = mountain_tiles_by_key_by_chunk;
    result["mountain_open_tiles_by_key_by_chunk"] = mountain_open_tiles_by_key_by_chunk;
    return result;
}
