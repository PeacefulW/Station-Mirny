#ifndef MOUNTAIN_TOPOLOGY_BUILDER_H
#define MOUNTAIN_TOPOLOGY_BUILDER_H

#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

class MountainTopologyBuilder : public RefCounted {
    GDCLASS(MountainTopologyBuilder, RefCounted)

public:
    MountainTopologyBuilder();
    ~MountainTopologyBuilder();

    void clear();
    void set_chunk(Vector2i p_chunk_coord, PackedByteArray p_terrain, int p_chunk_size);
    void remove_chunk(Vector2i p_chunk_coord);
    void update_tile(Vector2i p_tile_pos, int p_terrain_type);
    void ensure_built();
    Vector2i get_mountain_key_at_tile(Vector2i p_tile_pos);
    Dictionary get_mountain_tiles(Vector2i p_mountain_key);
    Dictionary get_mountain_open_tiles(Vector2i p_mountain_key);
    Dictionary get_mountain_tiles_by_chunk(Vector2i p_mountain_key);
    Dictionary get_mountain_open_tiles_by_chunk(Vector2i p_mountain_key);
    Array get_mountain_chunk_coords(Vector2i p_mountain_key);
    Dictionary rebuild_topology(Dictionary p_chunk_terrain_by_coord, int p_chunk_size);

protected:
    static void _bind_methods();

private:
    struct TilePos {
        int32_t x = 0;
        int32_t y = 0;

        bool operator==(const TilePos &other) const {
            return x == other.x && y == other.y;
        }
    };

    struct TilePosHash {
        std::size_t operator()(const TilePos &tile) const {
            const std::size_t hx = std::hash<int32_t>{}(tile.x);
            const std::size_t hy = std::hash<int32_t>{}(tile.y);
            return hx ^ (hy + 0x9e3779b9 + (hx << 6) + (hx >> 2));
        }
    };

    struct ChunkData {
        PackedByteArray terrain;
    };

    using TileSet = std::unordered_set<TilePos, TilePosHash>;
    using ChunkTerrainMap = std::unordered_map<TilePos, ChunkData, TilePosHash>;
    using TilesByChunkMap = std::unordered_map<TilePos, TileSet, TilePosHash>;

    int chunk_size = 64;
    bool dirty = true;
    ChunkTerrainMap chunk_map;
    Dictionary mountain_key_by_tile;
    Dictionary mountain_tiles_by_key;
    Dictionary mountain_open_tiles_by_key;
    Dictionary mountain_tiles_by_key_by_chunk;
    Dictionary mountain_open_tiles_by_key_by_chunk;

    static bool _is_mountain_topology_tile(uint8_t p_terrain_type);
    static bool _is_open_tile(uint8_t p_terrain_type);
    static int _floor_div(int value, int divisor);
    static int _positive_mod(int value, int divisor);
    static Vector2i _to_vector2i(const TilePos &tile);
    static TilePos _from_vector2i(const Vector2i &tile);

    bool _try_get_terrain(const ChunkTerrainMap &chunk_map, int chunk_size, const TilePos &tile_pos, uint8_t &out_terrain) const;
    Dictionary _build_component_dictionary(const TileSet &tiles) const;
    Dictionary _build_component_by_chunk_dictionary(const TilesByChunkMap &tiles_by_chunk) const;
    Dictionary _rebuild_topology_internal();
};

} // namespace godot

#endif // MOUNTAIN_TOPOLOGY_BUILDER_H
