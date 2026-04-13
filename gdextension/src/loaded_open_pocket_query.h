#ifndef LOADED_OPEN_POCKET_QUERY_H
#define LOADED_OPEN_POCKET_QUERY_H

#include <cstdint>
#include <unordered_map>
#include <unordered_set>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

class LoadedOpenPocketQuery : public RefCounted {
    GDCLASS(LoadedOpenPocketQuery, RefCounted)

public:
    LoadedOpenPocketQuery();
    ~LoadedOpenPocketQuery();

    void clear();
    void set_chunk(Vector2i p_chunk_coord, PackedByteArray p_terrain, int p_chunk_size);
    void remove_chunk(Vector2i p_chunk_coord);
    void update_tile(Vector2i p_tile_pos, int p_terrain_type);
    Dictionary query_open_pocket(Vector2i p_seed_tile, int p_max_tiles, int p_wrap_width_tiles) const;

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

    int chunk_size = 64;
    ChunkTerrainMap chunk_map;

    static bool _is_open_tile(uint8_t p_terrain_type);
    static int _floor_div(int value, int divisor);
    static int _positive_mod(int value, int divisor);
    static int _canonicalize_tile_x(int tile_x, int wrap_width_tiles);
    static Vector2i _to_vector2i(const TilePos &tile);
    static TilePos _from_vector2i(const Vector2i &tile);

    bool _try_get_terrain(const TilePos &tile_pos, uint8_t &out_terrain) const;
};

} // namespace godot

#endif // LOADED_OPEN_POCKET_QUERY_H
