#include "chunk_generator.h"
#include <cmath>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

ChunkGenerator::ChunkGenerator() {}
ChunkGenerator::~ChunkGenerator() {}

void ChunkGenerator::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize", "seed", "params"), &ChunkGenerator::initialize);
    ClassDB::bind_method(D_METHOD("generate_chunk", "chunk_coord", "spawn_tile"), &ChunkGenerator::generate_chunk);
}

void ChunkGenerator::setup_noise(FastNoiseLite& n, int s, float freq, int octaves) {
    n.SetSeed(s);
    n.SetNoiseType(FastNoiseLite::NoiseType_OpenSimplex2S);
    n.SetFrequency(freq);
    n.SetFractalType(FastNoiseLite::FractalType_FBm);
    n.SetFractalOctaves(octaves);
    n.SetFractalLacunarity(2.0f);
    n.SetFractalGain(0.5f);
}

void ChunkGenerator::initialize(int p_seed, Dictionary p_params) {
    seed = p_seed;
    chunk_size = p_params.get("chunk_size", 64);
    rock_threshold = p_params.get("rock_threshold", 0.73f);
    warp_strength = p_params.get("warp_strength", 25.0f);
    ridge_weight = p_params.get("ridge_weight", 0.30f);
    continental_weight = p_params.get("continental_weight", 0.20f);
    safe_zone_radius = p_params.get("safe_zone_radius", 12);
    land_guarantee_radius = p_params.get("land_guarantee_radius", 24);
    float height_freq = p_params.get("height_frequency", 0.01f);
    int height_oct = p_params.get("height_octaves", 4);
    float warp_freq = p_params.get("warp_frequency", 0.008f);
    float ridge_freq = p_params.get("ridge_frequency", 0.012f);
    float cont_freq = p_params.get("continental_frequency", 0.003f);

    setup_noise(noise_height, seed, height_freq, height_oct);
    setup_noise(noise_warp_x, seed + 500, warp_freq, 2);
    setup_noise(noise_warp_y, seed + 800, warp_freq, 2);
    setup_noise(noise_ridge, seed + 3000, ridge_freq, 3);
    setup_noise(noise_continental, seed + 7000, cont_freq, 2);

    initialized = true;
}

float ChunkGenerator::sample_normalized(FastNoiseLite& n, float x, float y) {
    return (n.GetNoise(x, y) + 1.0f) * 0.5f;
}

float ChunkGenerator::sample_ridged(float x, float y) {
    float n1 = noise_ridge.GetNoise(x, y);
    n1 = 1.0f - std::abs(n1);
    n1 *= n1;
    float n2 = noise_ridge.GetNoise(x * 2.1f, y * 2.1f);
    n2 = 1.0f - std::abs(n2);
    n2 *= n2;
    return (n1 + n2 * 0.45f) / 1.45f;
}

float ChunkGenerator::calc_raw_height(float x, float y, float cached_continental) {
    float wx = x + sample_normalized(noise_warp_x, x, y) * warp_strength;
    float wy = y + sample_normalized(noise_warp_y, x, y) * warp_strength;
    float base = sample_normalized(noise_height, wx, wy);
    float ridged = sample_ridged(x, y);
    float cont = cached_continental;
    float base_w = 1.0f - ridge_weight - continental_weight;
    return base * base_w + ridged * ridge_weight + cont * continental_weight;
}

float ChunkGenerator::tile_hashf(int x, int y, int s) {
    int h = s ^ (x * 374761393) ^ (y * 668265263);
    h = (h ^ (h >> 13)) * 1274126177;
    return (float)(std::abs(h) % 10000) / 10000.0f;
}

Dictionary ChunkGenerator::generate_chunk(Vector2i chunk_coord, Vector2i spawn) {
    if (!initialized) return Dictionary();

    int cs = chunk_size;
    int total = cs * cs;
    int start_x = chunk_coord.x * cs;
    int start_y = chunk_coord.y * cs;

    // Continental noise — one sample per chunk (low freq)
    float center_x = (float)(start_x + cs / 2) * 0.4f;
    float center_y = (float)(start_y + cs / 2) * 0.4f;
    float continental = sample_normalized(noise_continental, center_x, center_y);

    // --- Output arrays ---
    PackedByteArray terrain;
    terrain.resize(total);
    PackedFloat32Array height_arr;
    height_arr.resize(total);

    for (int ly = 0; ly < cs; ly++) {
        for (int lx = 0; lx < cs; lx++) {
            int gx = start_x + lx;
            int gy = start_y + ly;
            int idx = ly * cs + lx;

            // Distance from spawn
            float dx = (float)(gx - spawn.x);
            float dy = (float)(gy - spawn.y);
            float dist = std::sqrt(dx * dx + dy * dy);

            // Height calculation
            float h = calc_raw_height((float)gx, (float)gy, continental);
            if (dist < (float)land_guarantee_radius) {
                float factor = 1.0f - (dist / (float)land_guarantee_radius);
                h = h * (1.0f - factor * 0.7f) + 0.5f * factor * 0.7f;
            }
            height_arr[idx] = h;

            terrain[idx] = 0;
        }
    }

    Dictionary result;
    result["terrain"] = terrain;
    result["height"] = height_arr;
    result["chunk_size"] = cs;
    return result;
}
