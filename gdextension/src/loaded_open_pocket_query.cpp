#include "loaded_open_pocket_query.h"

#include <algorithm>
#include <deque>
#include <vector>

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

LoadedOpenPocketQuery::LoadedOpenPocketQuery() {}
LoadedOpenPocketQuery::~LoadedOpenPocketQuery() {}

void LoadedOpenPocketQuery::_bind_methods() {
    ClassDB::bind_method(D_METHOD("clear"), &LoadedOpenPocketQuery::clear);
    ClassDB::bind_method(D_METHOD("set_chunk", "chunk_coord", "terrain", "chunk_size"), &LoadedOpenPocketQuery::set_chunk);
    ClassDB::bind_method(D_METHOD("remove_chunk", "chunk_coord"), &LoadedOpenPocketQuery::remove_chunk);
    ClassDB::bind_method(D_METHOD("update_tile", "tile_pos", "terrain_type"), &LoadedOpenPocketQuery::update_tile);
    ClassDB::bind_method(
        D_METHOD("query_open_pocket", "seed_tile", "max_tiles", "wrap_width_tiles"),
        &LoadedOpenPocketQuery::query_open_pocket
    );
}

void LoadedOpenPocketQuery::clear() {
    chunk_map.clear();
}

void LoadedOpenPocketQuery::set_chunk(Vector2i p_chunk_coord, PackedByteArray p_terrain, int p_chunk_size) {
    chunk_size = p_chunk_size;
    ChunkData data;
    data.terrain = p_terrain;
    chunk_map[_from_vector2i(p_chunk_coord)] = data;
}

void LoadedOpenPocketQuery::remove_chunk(Vector2i p_chunk_coord) {
    chunk_map.erase(_from_vector2i(p_chunk_coord));
}

void LoadedOpenPocketQuery::update_tile(Vector2i p_tile_pos, int p_terrain_type) {
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

    terrain[idx] = static_cast<uint8_t>(p_terrain_type);
}

Dictionary LoadedOpenPocketQuery::query_open_pocket(Vector2i p_seed_tile, int p_max_tiles, int p_wrap_width_tiles) const {
    Dictionary empty_result;
    if (chunk_size <= 0 || p_max_tiles <= 0 || chunk_map.empty()) {
        return empty_result;
    }

    TilePos seed_tile = _from_vector2i(p_seed_tile);
    seed_tile.x = _canonicalize_tile_x(seed_tile.x, p_wrap_width_tiles);

    uint8_t seed_terrain = 0;
    if (!_try_get_terrain(seed_tile, seed_terrain) || !_is_open_tile(seed_terrain)) {
        return empty_result;
    }

    std::deque<TilePos> queue;
    TileSet visited;
    TileSet zone_tiles;
    TileSet zone_chunk_coords;
    bool truncated = false;

    queue.push_back(seed_tile);
    visited.insert(seed_tile);

    static const int dirs[4][2] = {
        {-1, 0},
        {1, 0},
        {0, -1},
        {0, 1},
    };

    while (!queue.empty()) {
        const TilePos current = queue.front();
        queue.pop_front();

        zone_tiles.insert(current);
        TilePos current_chunk_coord;
        current_chunk_coord.x = _floor_div(current.x, chunk_size);
        current_chunk_coord.y = _floor_div(current.y, chunk_size);
        zone_chunk_coords.insert(current_chunk_coord);

        for (const auto &dir : dirs) {
            TilePos next_tile;
            next_tile.x = _canonicalize_tile_x(current.x + dir[0], p_wrap_width_tiles);
            next_tile.y = current.y + dir[1];

            if (visited.find(next_tile) != visited.end()) {
                continue;
            }

            uint8_t next_terrain = 0;
            if (!_try_get_terrain(next_tile, next_terrain)) {
                truncated = true;
                continue;
            }
            if (!_is_open_tile(next_terrain)) {
                continue;
            }
            if (static_cast<int>(visited.size()) >= p_max_tiles) {
                truncated = true;
                continue;
            }

            visited.insert(next_tile);
            queue.push_back(next_tile);
        }
    }

    Dictionary zone_tile_dict;
    for (const TilePos &tile : zone_tiles) {
        zone_tile_dict[_to_vector2i(tile)] = true;
    }

    std::vector<Vector2i> sorted_chunk_coords;
    sorted_chunk_coords.reserve(zone_chunk_coords.size());
    for (const TilePos &chunk_coord : zone_chunk_coords) {
        sorted_chunk_coords.push_back(_to_vector2i(chunk_coord));
    }
    std::sort(
        sorted_chunk_coords.begin(),
        sorted_chunk_coords.end(),
        [](const Vector2i &left, const Vector2i &right) {
            if (left.y != right.y) {
                return left.y < right.y;
            }
            return left.x < right.x;
        }
    );

    Array chunk_coord_array;
    for (const Vector2i &chunk_coord : sorted_chunk_coords) {
        chunk_coord_array.append(chunk_coord);
    }

    Dictionary result;
    result["tiles"] = zone_tile_dict;
    result["chunk_coords"] = chunk_coord_array;
    result["truncated"] = truncated;
    return result;
}

bool LoadedOpenPocketQuery::_is_open_tile(uint8_t p_terrain_type) {
    return p_terrain_type == 5 || p_terrain_type == 6;
}

int LoadedOpenPocketQuery::_floor_div(int value, int divisor) {
    int q = value / divisor;
    int r = value % divisor;
    if (r != 0 && value < 0) {
        q -= 1;
    }
    return q;
}

int LoadedOpenPocketQuery::_positive_mod(int value, int divisor) {
    int result = value % divisor;
    if (result < 0) {
        result += divisor;
    }
    return result;
}

int LoadedOpenPocketQuery::_canonicalize_tile_x(int tile_x, int wrap_width_tiles) {
    if (wrap_width_tiles <= 0) {
        return tile_x;
    }
    int result = tile_x % wrap_width_tiles;
    if (result < 0) {
        result += wrap_width_tiles;
    }
    return result;
}

Vector2i LoadedOpenPocketQuery::_to_vector2i(const TilePos &tile) {
    return Vector2i(tile.x, tile.y);
}

LoadedOpenPocketQuery::TilePos LoadedOpenPocketQuery::_from_vector2i(const Vector2i &tile) {
    TilePos result;
    result.x = tile.x;
    result.y = tile.y;
    return result;
}

bool LoadedOpenPocketQuery::_try_get_terrain(const TilePos &tile_pos, uint8_t &out_terrain) const {
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
