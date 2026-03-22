#ifndef CHUNK_GENERATOR_H
#define CHUNK_GENERATOR_H

#include <vector>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include "FastNoiseLite.h"

namespace godot {

class ChunkGenerator : public RefCounted {
    GDCLASS(ChunkGenerator, RefCounted)

public:
    ChunkGenerator();
    ~ChunkGenerator();

    void initialize(int p_seed, Dictionary p_params);
    Dictionary generate_chunk(Vector2i chunk_coord, Vector2i spawn_tile);

protected:
    static void _bind_methods();

private:
    int seed = 0;
    int chunk_size = 64;
    bool initialized = false;

    // --- Terrain thresholds ---
    float rock_threshold = 0.73f;
    float warp_strength = 25.0f;
    float ridge_weight = 0.30f;
    float continental_weight = 0.20f;
    int safe_zone_radius = 12;
    int land_guarantee_radius = 24;

    // --- Mountain formations ---
    // --- Noise layers ---
    FastNoiseLite noise_height;
    FastNoiseLite noise_warp_x;
    FastNoiseLite noise_warp_y;
    FastNoiseLite noise_ridge;
    FastNoiseLite noise_continental;

    // --- Helpers ---
    void setup_noise(FastNoiseLite& n, int s, float freq, int octaves);
    float sample_normalized(FastNoiseLite& n, float x, float y);
    float sample_ridged(float x, float y);
    float calc_raw_height(float x, float y, float cached_continental);
    float tile_hashf(int x, int y, int s);
};

} // namespace godot

#endif // CHUNK_GENERATOR_H
