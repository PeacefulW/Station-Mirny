#include "chunk_generator.h"
#include <cmath>
#include <algorithm>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

// ============================================================
// Lifecycle
// ============================================================

ChunkGenerator::ChunkGenerator() {}
ChunkGenerator::~ChunkGenerator() {}

void ChunkGenerator::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize", "seed", "params"), &ChunkGenerator::initialize);
    ClassDB::bind_method(D_METHOD("generate_chunk", "chunk_coord", "spawn_tile", "generation_request"), &ChunkGenerator::generate_chunk);
    ClassDB::bind_method(D_METHOD("sample_tile", "world_pos", "spawn_tile"), &ChunkGenerator::sample_tile);
}

// ============================================================
// Noise setup — matches WorldNoiseUtils.setup_noise_instance()
// ============================================================

void ChunkGenerator::setup_noise(FastNoiseLite& n, int s, float freq, int octaves) {
    n.SetSeed(s);
    n.SetNoiseType(FastNoiseLite::NoiseType_OpenSimplex2);  // matches Godot TYPE_SIMPLEX
    n.SetFrequency(freq);
    // Phase 0: FBM is now enabled in both GDScript and native paths.
    // The remaining octave/gain/lacunarity settings are now active because fractal_type is FBM.
    // This restores the intended multi-octave detail on the native generation path.
    // Keep native setup semantically aligned with the shared GDScript helper.
    n.SetFractalType(FastNoiseLite::FractalType_FBm);
    n.SetFractalOctaves(octaves);
    n.SetFractalGain(FRACTAL_GAIN);
    n.SetFractalLacunarity(FRACTAL_LACUNARITY);
}

// ============================================================
// Cylindrical noise sampling — matches WorldNoiseUtils.sample_periodic_noise01()
// ============================================================

float ChunkGenerator::sample_noise_01(FastNoiseLite& n, int world_x, int world_y) const {
    if (wrap_width <= 0) {
        return n.GetNoise((float)world_x, (float)world_y) * 0.5f + 0.5f;
    }
    int wrapped_x = wrap_x(world_x, wrap_width);
    float angle = 6.283185307179586f * (float)wrapped_x / (float)wrap_width; // TAU
    float ring_radius = (float)wrap_width / 6.283185307179586f;
    float sx = cosf(angle) * ring_radius;
    float sy = (float)world_y;
    float sz = sinf(angle) * ring_radius;
    return n.GetNoise(sx, sy, sz) * 0.5f + 0.5f;
}

float ChunkGenerator::sample_noise_signed(FastNoiseLite& n, int world_x, int world_y) const {
    return sample_noise_01(n, world_x, world_y) * 2.0f - 1.0f;
}

// ============================================================
// Static helpers
// ============================================================

float ChunkGenerator::clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

float ChunkGenerator::lerpf(float a, float b, float t) {
    return a + (b - a) * t;
}

float ChunkGenerator::smoothstep(float t) {
    return t * t * (3.0f - 2.0f * t);
}

int ChunkGenerator::wrap_x(int world_x, int w) {
    if (w <= 0) return world_x;
    int r = world_x % w;
    return r < 0 ? r + w : r;
}

// ============================================================
// initialize() — full config, 12 noise instances, biome defs
// ============================================================

void ChunkGenerator::initialize(int p_seed, Dictionary p_params) {
    seed = p_seed;

    // --- Core ---
    chunk_size = (int)p_params.get("chunk_size", 64);
    wrap_width = (int)p_params.get("wrap_width", 4096);

    // --- Planet sampler params ---
    equator_tile_y = (int)p_params.get("equator_tile_y", 0);
    latitude_half_span_tiles = (int)p_params.get("latitude_half_span_tiles", 4096);
    temperature_noise_amplitude = (float)(double)p_params.get("temperature_noise_amplitude", 0.18);
    temperature_latitude_weight = (float)(double)p_params.get("temperature_latitude_weight", 0.72);
    latitude_temperature_curve = (float)(double)p_params.get("latitude_temperature_curve", 1.35);

    mountain_density = (float)(double)p_params.get("mountain_density", 0.3);
    mountain_chaininess = (float)(double)p_params.get("mountain_chaininess", 0.6);

    // --- Terrain resolver params ---
    safe_zone_radius = (int)p_params.get("safe_zone_radius", 12);
    land_guarantee_radius = (int)p_params.get("land_guarantee_radius", 24);

    // --- Terrain resolver params (river, bank, mountain thresholds) ---
    mountain_base_threshold = (float)(double)p_params.get("mountain_base_threshold", 0.74);
    river_min_strength = (float)(double)p_params.get("river_min_strength", 0.40);
    river_ridge_exclusion = (float)(double)p_params.get("river_ridge_exclusion", 0.70);
    river_max_height = (float)(double)p_params.get("river_max_height", 0.74);
    bank_min_floodplain = (float)(double)p_params.get("bank_min_floodplain", 0.32);
    bank_ridge_exclusion = (float)(double)p_params.get("bank_ridge_exclusion", 0.64);
    bank_min_river = (float)(double)p_params.get("bank_min_river", 0.16);
    bank_min_moisture = (float)(double)p_params.get("bank_min_moisture", 0.54);
    bank_max_height = (float)(double)p_params.get("bank_max_height", 0.60);
    prepass_frozen_river_threshold = (float)(double)p_params.get("prepass_frozen_river_threshold", 0.18);
    cold_pole_temperature = (float)(double)p_params.get("cold_pole_temperature", 0.20);
    cold_pole_transition_width = (float)(double)p_params.get("cold_pole_transition_width", 0.12);
    ice_cap_height_bonus = (float)(double)p_params.get("ice_cap_height_bonus", 0.10);
    ice_cap_max_height = (float)(double)p_params.get("ice_cap_max_height", 0.55);
    hot_pole_temperature = (float)(double)p_params.get("hot_pole_temperature", 0.82);
    hot_pole_transition_width = (float)(double)p_params.get("hot_pole_transition_width", 0.15);
    biome_continental_drying_factor = (float)(double)p_params.get("biome_continental_drying_factor", 0.35);
    biome_drainage_moisture_bonus = (float)(double)p_params.get("biome_drainage_moisture_bonus", 0.28);
    // Pre-compute mountain weights (matches surface_terrain_resolver.gd lines 24-32)
    float chain = clampf(mountain_chaininess, 0.0f, 1.0f);
    mountain_threshold_value = clampf(mountain_base_threshold - mountain_density, 0.0f, 1.0f);
    ridge_backbone_weight = lerpf(0.76f, 0.92f, chain);
    massif_fill_weight = lerpf(0.30f, 0.38f, chain);
    core_bonus_weight = lerpf(0.16f, 0.28f, chain);

    // --- Pre-pass-backed biome sampling config ---
    prepass_grid_width = (int)p_params.get("prepass_grid_width", 0);
    prepass_grid_height = (int)p_params.get("prepass_grid_height", 0);
    prepass_min_y = (int)p_params.get("prepass_min_y", 0);
    prepass_max_y = (int)p_params.get("prepass_max_y", 0);
    prepass_grid_span_x = (float)(double)p_params.get("prepass_grid_span_x", 1.0);
    prepass_grid_span_y = (float)(double)p_params.get("prepass_grid_span_y", 1.0);
    String snapshot_kind = p_params.get("prepass_snapshot_kind", String());
    int snapshot_seed = (int)p_params.get("prepass_seed", p_seed);
    prepass_drainage_grid = p_params.get("prepass_drainage_grid", PackedFloat32Array());
    prepass_slope_grid = p_params.get("prepass_slope_grid", PackedFloat32Array());
    prepass_rain_shadow_grid = p_params.get("prepass_rain_shadow_grid", PackedFloat32Array());
    prepass_continentalness_grid = p_params.get("prepass_continentalness_grid", PackedFloat32Array());
    prepass_ridge_strength_grid = p_params.get("prepass_ridge_strength_grid", PackedFloat32Array());
    prepass_river_width_grid = p_params.get("prepass_river_width_grid", PackedFloat32Array());
    prepass_river_distance_grid = p_params.get("prepass_river_distance_grid", PackedFloat32Array());
    prepass_floodplain_strength_grid = p_params.get("prepass_floodplain_strength_grid", PackedFloat32Array());
    prepass_mountain_mass_grid = p_params.get("prepass_mountain_mass_grid", PackedFloat32Array());
    int expected_prepass_size = prepass_grid_width * prepass_grid_height;
    has_authoritative_prepass = snapshot_kind == "world_pre_pass_chunk_generator_v2"
        && snapshot_seed == p_seed
        && expected_prepass_size > 0
        && prepass_grid_span_x > 0.0f
        && prepass_grid_span_y > 0.0f
        && prepass_drainage_grid.size() == expected_prepass_size
        && prepass_slope_grid.size() == expected_prepass_size
        && prepass_rain_shadow_grid.size() == expected_prepass_size
        && prepass_continentalness_grid.size() == expected_prepass_size
        && prepass_ridge_strength_grid.size() == expected_prepass_size
        && prepass_river_width_grid.size() == expected_prepass_size
        && prepass_river_distance_grid.size() == expected_prepass_size
        && prepass_floodplain_strength_grid.size() == expected_prepass_size
        && prepass_mountain_mass_grid.size() == expected_prepass_size;
    if (!has_authoritative_prepass) {
        UtilityFunctions::push_error(
            "[ChunkGenerator] initialize requires a valid authoritative WorldPrePass snapshot; native generation will not fall back to legacy structure formulas."
        );
        initialized = false;
        return;
    }

    // --- Local variation params ---
    local_variation_min_score = (float)(double)p_params.get("local_variation_min_score", 0.22);

    // --- Noise frequencies & octaves from balance ---
    float height_freq = (float)(double)p_params.get("height_frequency", 0.01);
    int height_oct = (int)p_params.get("height_octaves", 3);
    float temperature_freq = (float)(double)p_params.get("temperature_frequency", 0.0035);
    int temperature_oct = (int)p_params.get("temperature_octaves", 2);
    float moisture_freq = (float)(double)p_params.get("moisture_frequency", 0.0055);
    int moisture_oct = (int)p_params.get("moisture_octaves", 2);
    float ruggedness_freq = (float)(double)p_params.get("ruggedness_frequency", 0.014);
    int ruggedness_oct = (int)p_params.get("ruggedness_octaves", 2);
    float flora_density_freq = (float)(double)p_params.get("flora_density_frequency", 0.02);
    int flora_density_oct = (int)p_params.get("flora_density_octaves", 2);
    float local_var_freq = (float)(double)p_params.get("local_variation_frequency", 0.018);
    int local_var_oct = (int)p_params.get("local_variation_octaves", 2);

    // --- Configure native noise instances ---
    setup_noise(noise_height,                  seed + 11,  height_freq, height_oct);
    setup_noise(noise_temperature,             seed + 101, temperature_freq, temperature_oct);
    setup_noise(noise_moisture,                seed + 131, moisture_freq, moisture_oct);
    setup_noise(noise_ruggedness,              seed + 151, ruggedness_freq, ruggedness_oct);
    setup_noise(noise_flora_density,           seed + 181, flora_density_freq, flora_density_oct);
    setup_noise(noise_field,                   seed + 311, local_var_freq, local_var_oct);
    setup_noise(noise_patch,                   seed + 353, local_var_freq * 1.85f,
                std::min(local_var_oct + 1, 6));
    setup_noise(noise_detail,                  seed + 389, local_var_freq * 3.2f,
                std::min(local_var_oct + 1, 6));

    // --- Parse biome definitions ---
    biomes.clear();
    Array biome_array = p_params.get("biomes", Array());
    for (int i = 0; i < biome_array.size(); i++) {
        Dictionary bd = biome_array[i];
        BiomeDef def;
        def.id = (StringName)bd.get("id", StringName());
        def.priority = (int)bd.get("priority", 0);
        def.palette_index = (int)bd.get("palette_index", i);
        // Channel ranges
        def.min_height = (float)(double)bd.get("min_height", 0.0);
        def.max_height = (float)(double)bd.get("max_height", 1.0);
        def.min_temperature = (float)(double)bd.get("min_temperature", 0.0);
        def.max_temperature = (float)(double)bd.get("max_temperature", 1.0);
        def.min_moisture = (float)(double)bd.get("min_moisture", 0.0);
        def.max_moisture = (float)(double)bd.get("max_moisture", 1.0);
        def.min_ruggedness = (float)(double)bd.get("min_ruggedness", 0.0);
        def.max_ruggedness = (float)(double)bd.get("max_ruggedness", 1.0);
        def.min_flora_density = (float)(double)bd.get("min_flora_density", 0.0);
        def.max_flora_density = (float)(double)bd.get("max_flora_density", 1.0);
        def.min_latitude = (float)(double)bd.get("min_latitude", -1.0);
        def.max_latitude = (float)(double)bd.get("max_latitude", 1.0);
        def.min_drainage = (float)(double)bd.get("min_drainage", 0.0);
        def.max_drainage = (float)(double)bd.get("max_drainage", 1.0);
        def.min_slope = (float)(double)bd.get("min_slope", 0.0);
        def.max_slope = (float)(double)bd.get("max_slope", 1.0);
        def.min_rain_shadow = (float)(double)bd.get("min_rain_shadow", 0.0);
        def.max_rain_shadow = (float)(double)bd.get("max_rain_shadow", 1.0);
        def.min_continentalness = (float)(double)bd.get("min_continentalness", 0.0);
        def.max_continentalness = (float)(double)bd.get("max_continentalness", 1.0);
        // Structure ranges
        def.min_ridge_strength = (float)(double)bd.get("min_ridge_strength", 0.0);
        def.max_ridge_strength = (float)(double)bd.get("max_ridge_strength", 1.0);
        def.min_river_strength = (float)(double)bd.get("min_river_strength", 0.0);
        def.max_river_strength = (float)(double)bd.get("max_river_strength", 1.0);
        def.min_floodplain_strength = (float)(double)bd.get("min_floodplain_strength", 0.0);
        def.max_floodplain_strength = (float)(double)bd.get("max_floodplain_strength", 1.0);
        // Channel weights
        def.height_weight = (float)(double)bd.get("height_weight", 1.0);
        def.temperature_weight = (float)(double)bd.get("temperature_weight", 1.0);
        def.moisture_weight = (float)(double)bd.get("moisture_weight", 1.0);
        def.ruggedness_weight = (float)(double)bd.get("ruggedness_weight", 1.0);
        def.flora_density_weight = (float)(double)bd.get("flora_density_weight", 0.6);
        def.latitude_weight = (float)(double)bd.get("latitude_weight", 0.6);
        def.drainage_weight = (float)(double)bd.get("drainage_weight", 0.0);
        def.slope_weight = (float)(double)bd.get("slope_weight", 0.0);
        def.rain_shadow_weight = (float)(double)bd.get("rain_shadow_weight", 0.0);
        def.continentalness_weight = (float)(double)bd.get("continentalness_weight", 0.0);
        // Structure weights
        def.ridge_strength_weight = (float)(double)bd.get("ridge_strength_weight", 1.0);
        def.river_strength_weight = (float)(double)bd.get("river_strength_weight", 1.0);
        def.floodplain_strength_weight = (float)(double)bd.get("floodplain_strength_weight", 1.0);
        // Tags
        Array tag_array = bd.get("tags", Array());
        def.tags.clear();
        for (int t = 0; t < tag_array.size(); t++) {
            def.tags.push_back((StringName)tag_array[t]);
        }
        biomes.push_back(def);
    }

    // Sort biomes: priority DESC, then id ASC (matches GDScript BiomeResolver)
    std::sort(biomes.begin(), biomes.end(), [](const BiomeDef& a, const BiomeDef& b) {
        if (a.priority != b.priority) return a.priority > b.priority;
        return String(a.id) < String(b.id);
    });

    initialized = true;
}

// ============================================================
// PlanetSampler — sample_channels()  (matches planet_sampler.gd)
// ============================================================

ChunkGenerator::Channels ChunkGenerator::sample_channels(int wx, int wy) const {
    Channels ch;

    // Latitude (matches sample_latitude)
    int half_span = std::max(256, latitude_half_span_tiles);
    ch.latitude = clampf(fabsf((float)(wy - equator_tile_y)) / (float)half_span, 0.0f, 1.0f);

    // Height (direct noise)
    ch.height = sample_noise_01(const_cast<FastNoiseLite&>(noise_height), wx, wy);

    // Temperature (matches _sample_temperature)
    float climate_noise = sample_noise_01(const_cast<FastNoiseLite&>(noise_temperature), wx, wy);
    float climate_offset = (climate_noise - 0.5f) * clampf(temperature_noise_amplitude, 0.0f, 0.5f) * 2.0f;
    float lat_curve = std::max(0.5f, latitude_temperature_curve);
    float latitude_temperature = 1.0f - powf(ch.latitude, lat_curve);
    float temp_lat_w = clampf(temperature_latitude_weight, 0.0f, 1.0f);
    ch.temperature = clampf(
        lerpf(latitude_temperature + climate_offset, climate_noise, 1.0f - temp_lat_w),
        0.0f, 1.0f);

    // Moisture (direct noise)
    ch.moisture = sample_noise_01(const_cast<FastNoiseLite&>(noise_moisture), wx, wy);

    // Ruggedness (direct noise)
    ch.ruggedness = sample_noise_01(const_cast<FastNoiseLite&>(noise_ruggedness), wx, wy);

    // Flora density (matches _sample_flora_density)
    float flora_noise = sample_noise_01(const_cast<FastNoiseLite&>(noise_flora_density), wx, wy);
    ch.flora_density = clampf(lerpf(flora_noise, ch.moisture, 0.35f), 0.0f, 1.0f);

    return ch;
}

// ============================================================
// Authoritative structure context — derived only from WorldPrePass snapshot
// ============================================================

ChunkGenerator::StructureContext ChunkGenerator::build_structure_context_from_prepass(const BiomePrePassSample& prepass) const {
    StructureContext sc{};
    sc.mountain_mass = clampf(prepass.mountain_mass, 0.0f, 1.0f);
    sc.ridge_strength = clampf(prepass.ridge_strength, 0.0f, 1.0f);
    sc.floodplain_strength = clampf(prepass.floodplain_strength, 0.0f, 1.0f);
    sc.river_distance = std::max(0.0f, prepass.river_distance);
    sc.river_width = std::max(0.0f, prepass.river_width);
    sc.river_strength = derive_river_strength_from_prepass(sc.river_width, sc.river_distance);
    return sc;
}

// ============================================================
// BiomeResolver (matches biome_resolver.gd + biome_data.gd)
// ============================================================

float ChunkGenerator::score_range(float value, float min_v, float max_v, bool soft) {
    constexpr float EPS = 0.00001f;
    float lo = std::min(min_v, max_v);
    float hi = std::max(min_v, max_v);
    if (fabsf(hi - lo) < EPS) {
        if (fabsf(value - lo) < EPS) return 1.0f;
        if (!soft) return 0.0f;
        return 1.0f / (1.0f + fabsf(value - lo) * 8.0f);
    }
    if (value < lo - EPS) {
        if (!soft) return 0.0f;
        return 1.0f / (1.0f + ((lo - value) / std::max(hi - lo, EPS)) * 4.0f);
    }
    if (value > hi + EPS) {
        if (!soft) return 0.0f;
        return 1.0f / (1.0f + ((value - hi) / std::max(hi - lo, EPS)) * 4.0f);
    }
    float center = (lo + hi) * 0.5f;
    float half = std::max((hi - lo) * 0.5f, EPS);
    return clampf(1.0f - fabsf(value - center) / half, 0.0f, 1.0f);
}

float ChunkGenerator::sample_prepass_grid(const PackedFloat32Array& grid, int world_x, int world_y) const {
    if (!has_authoritative_prepass || grid.is_empty() || prepass_grid_width <= 0 || prepass_grid_height <= 0) {
        return 0.0f;
    }

    int wrapped_x = wrap_x(world_x, wrap_width);
    int x0 = 0;
    int x1 = 0;
    float tx = 0.0f;
    if (prepass_grid_width > 1) {
        float x_coord = (float)wrapped_x / prepass_grid_span_x;
        int x_floor = (int)std::floor(x_coord);
        x0 = wrap_x(x_floor, prepass_grid_width);
        x1 = wrap_x(x0 + 1, prepass_grid_width);
        tx = x_coord - (float)x_floor;
    }

    int y0 = 0;
    int y1 = 0;
    float ty = 0.0f;
    if (prepass_grid_height > 1) {
        if (world_y <= prepass_min_y) {
            y0 = 0;
            y1 = 0;
        } else if (world_y >= prepass_max_y) {
            y0 = prepass_grid_height - 1;
            y1 = y0;
        } else {
            float y_coord = (float)(world_y - prepass_min_y) / prepass_grid_span_y;
            int y_floor = (int)std::floor(y_coord);
            y0 = std::clamp(y_floor, 0, prepass_grid_height - 1);
            if (y0 >= prepass_grid_height - 1) {
                y1 = y0;
            } else {
                y1 = y0 + 1;
                ty = y_coord - (float)y_floor;
            }
        }
    }

    auto flat_index = [this](int gx, int gy) {
        return gy * prepass_grid_width + gx;
    };

    float v00 = grid[flat_index(x0, y0)];
    if (x0 == x1 && y0 == y1) {
        return v00;
    }
    float v10 = grid[flat_index(x1, y0)];
    float v01 = grid[flat_index(x0, y1)];
    float v11 = grid[flat_index(x1, y1)];
    float top = lerpf(v00, v10, tx);
    float bottom = lerpf(v01, v11, tx);
    return lerpf(top, bottom, ty);
}

BiomePrePassSample ChunkGenerator::sample_biome_prepass(int wx, int wy) const {
    BiomePrePassSample sample;
    if (!has_authoritative_prepass) {
        return sample;
    }
    sample.drainage = clampf(sample_prepass_grid(prepass_drainage_grid, wx, wy), 0.0f, 1.0f);
    sample.slope = clampf(sample_prepass_grid(prepass_slope_grid, wx, wy), 0.0f, 1.0f);
    sample.rain_shadow = clampf(sample_prepass_grid(prepass_rain_shadow_grid, wx, wy), 0.0f, 1.0f);
    sample.continentalness = clampf(sample_prepass_grid(prepass_continentalness_grid, wx, wy), 0.0f, 1.0f);
    sample.ridge_strength = clampf(sample_prepass_grid(prepass_ridge_strength_grid, wx, wy), 0.0f, 1.0f);
    sample.river_width = std::max(0.0f, sample_prepass_grid(prepass_river_width_grid, wx, wy));
    sample.river_distance = std::max(0.0f, sample_prepass_grid(prepass_river_distance_grid, wx, wy));
    sample.floodplain_strength = clampf(sample_prepass_grid(prepass_floodplain_strength_grid, wx, wy), 0.0f, 1.0f);
    sample.mountain_mass = clampf(sample_prepass_grid(prepass_mountain_mass_grid, wx, wy), 0.0f, 1.0f);
    return sample;
}

float ChunkGenerator::derive_river_strength_from_prepass(float river_width, float river_distance) const {
    float resolved_width = std::max(0.0f, river_width);
    if (resolved_width <= 0.001f) {
        return 0.0f;
    }
    float width_presence = clampf(resolved_width, 0.0f, 1.0f);
    float width_strength = clampf(resolved_width / 4.0f, 0.0f, 1.0f);
    float core_radius = std::max(1.0f, resolved_width * 0.55f);
    float bank_radius = core_radius + std::max(1.25f, resolved_width * 0.85f);
    float distance_to_river = std::max(0.0f, river_distance);
    float proximity = clampf(1.0f - distance_to_river / bank_radius, 0.0f, 1.0f);
    proximity = proximity * proximity * (3.0f - 2.0f * proximity);
    float core_proximity = clampf(1.0f - distance_to_river / core_radius, 0.0f, 1.0f);
    core_proximity = core_proximity * core_proximity * (3.0f - 2.0f * core_proximity);
    float combined_strength = width_strength * (0.10f + proximity * 0.70f);
    combined_strength += proximity * 0.18f;
    combined_strength += core_proximity * 0.12f;
    return clampf(combined_strength * width_presence, 0.0f, 1.0f);
}

bool ChunkGenerator::biome_uses_causal_moisture(const BiomeDef& b) const {
    return b.drainage_weight > 0.0f || b.rain_shadow_weight > 0.0f || b.continentalness_weight > 0.0f;
}

bool ChunkGenerator::matches_weighted_range(float value, float min_v, float max_v, float weight) const {
    if (weight <= 0.0f) {
        return true;
    }
    constexpr float E = 0.00001f;
    float lo = std::min(min_v, max_v);
    float hi = std::max(min_v, max_v);
    return value >= lo - E && value <= hi + E;
}

bool ChunkGenerator::biome_matches(
        const BiomeDef& b,
        const Channels& ch,
        const StructureContext& sc,
        const BiomePrePassSample* prepass) const {
    constexpr float E = 0.00001f;
    auto in_range = [E](float v, float lo, float hi) {
        float l = std::min(lo, hi);
        float u = std::max(lo, hi);
        return v >= l - E && v <= u + E;
    };
    bool matches = in_range(ch.height, b.min_height, b.max_height)
        && in_range(ch.temperature, b.min_temperature, b.max_temperature)
        && in_range(ch.moisture, b.min_moisture, b.max_moisture)
        && in_range(ch.ruggedness, b.min_ruggedness, b.max_ruggedness)
        && in_range(ch.flora_density, b.min_flora_density, b.max_flora_density)
        && in_range(ch.latitude, b.min_latitude, b.max_latitude)
        && in_range(sc.ridge_strength, b.min_ridge_strength, b.max_ridge_strength)
        && in_range(sc.river_strength, b.min_river_strength, b.max_river_strength)
        && in_range(sc.floodplain_strength, b.min_floodplain_strength, b.max_floodplain_strength);
    if (!matches || prepass == nullptr) {
        return matches;
    }
    return matches_weighted_range(prepass->drainage, b.min_drainage, b.max_drainage, b.drainage_weight)
        && matches_weighted_range(prepass->slope, b.min_slope, b.max_slope, b.slope_weight)
        && matches_weighted_range(prepass->rain_shadow, b.min_rain_shadow, b.max_rain_shadow, b.rain_shadow_weight)
        && matches_weighted_range(prepass->continentalness, b.min_continentalness, b.max_continentalness, b.continentalness_weight);
}

float ChunkGenerator::biome_weighted_score(
        const BiomeDef& b,
        const Channels& ch,
        const StructureContext& sc,
        const BiomePrePassSample* prepass,
        float effective_moisture,
        bool soft) const {
    float tw = 0.0f, ts = 0.0f;
    auto add = [&](float w, float val, float lo, float hi) {
        if (w <= 0.0f) return;
        tw += w;
        ts += score_range(val, lo, hi, soft) * w;
    };
    add(b.height_weight, ch.height, b.min_height, b.max_height);
    add(b.temperature_weight, ch.temperature, b.min_temperature, b.max_temperature);
    add(
        b.moisture_weight,
        (prepass != nullptr && biome_uses_causal_moisture(b)) ? effective_moisture : ch.moisture,
        b.min_moisture,
        b.max_moisture
    );
    add(b.ruggedness_weight, ch.ruggedness, b.min_ruggedness, b.max_ruggedness);
    add(b.flora_density_weight, ch.flora_density, b.min_flora_density, b.max_flora_density);
    add(b.latitude_weight, ch.latitude, b.min_latitude, b.max_latitude);
    add(b.ridge_strength_weight, sc.ridge_strength, b.min_ridge_strength, b.max_ridge_strength);
    add(b.river_strength_weight, sc.river_strength, b.min_river_strength, b.max_river_strength);
    add(b.floodplain_strength_weight, sc.floodplain_strength, b.min_floodplain_strength, b.max_floodplain_strength);
    if (prepass != nullptr) {
        add(b.drainage_weight, prepass->drainage, b.min_drainage, b.max_drainage);
        add(b.slope_weight, prepass->slope, b.min_slope, b.max_slope);
        add(b.rain_shadow_weight, prepass->rain_shadow, b.min_rain_shadow, b.max_rain_shadow);
        add(b.continentalness_weight, prepass->continentalness, b.min_continentalness, b.max_continentalness);
    }
    return tw > 0.0f ? ts / tw : 0.0f;
}

bool ChunkGenerator::is_better_biome_candidate(
        float score,
        const BiomeDef& biome,
        int incumbent_idx,
        float incumbent_score) const {
    constexpr float SCORE_EPS = 0.0001f;
    if (incumbent_idx < 0) {
        return true;
    }
    if (score > incumbent_score + SCORE_EPS) {
        return true;
    }
    if (score < incumbent_score - SCORE_EPS) {
        return false;
    }
    const BiomeDef& incumbent = biomes[incumbent_idx];
    if (biome.priority != incumbent.priority) {
        return biome.priority > incumbent.priority;
    }
    return String(biome.id) < String(incumbent.id);
}

ChunkGenerator::BiomeSelection ChunkGenerator::resolve_biome_selection(
        int wx, int wy, const Channels& ch, const StructureContext& sc, const BiomePrePassSample& prepass) const {
    BiomeSelection resolved;
    const BiomePrePassSample* prepass_ptr = has_authoritative_prepass ? &prepass : nullptr;
    StructureContext biome_sc = sc;
    float effective_moisture = clampf(ch.moisture, 0.0f, 1.0f);
    if (prepass_ptr != nullptr) {
        float moisture_retention = clampf(1.0f - prepass.rain_shadow, 0.0f, 1.0f);
        float continental_retention = clampf(
            1.0f - prepass.continentalness * biome_continental_drying_factor,
            0.0f,
            1.0f
        );
        effective_moisture = clampf(
            effective_moisture * moisture_retention * continental_retention
                + prepass.drainage * biome_drainage_moisture_bonus,
            0.0f,
            1.0f
        );
    }

    int best_valid_idx = -1;
    float best_valid_score = -1.0f;
    int second_valid_idx = -1;
    float second_valid_score = -1.0f;
    int best_fallback_idx = -1;
    float best_fallback_score = -1.0f;
    int second_fallback_idx = -1;
    float second_fallback_score = -1.0f;
    auto insert_ranked_candidate = [&](int candidate_idx, float candidate_score, int& best_idx, float& best_score, int& second_idx, float& second_score) {
        const BiomeDef& candidate = biomes[candidate_idx];
        if (is_better_biome_candidate(candidate_score, candidate, best_idx, best_score)) {
            if (best_idx >= 0 && biomes[best_idx].id != candidate.id) {
                second_idx = best_idx;
                second_score = best_score;
            }
            best_idx = candidate_idx;
            best_score = candidate_score;
            return;
        }
        if (best_idx >= 0 && biomes[best_idx].id == candidate.id) {
            return;
        }
        if (second_idx < 0 || is_better_biome_candidate(candidate_score, candidate, second_idx, second_score)) {
            second_idx = candidate_idx;
            second_score = candidate_score;
        }
    };
    for (int i = 0; i < (int)biomes.size(); i++) {
        const BiomeDef& b = biomes[i];
        bool valid = biome_matches(b, ch, biome_sc, prepass_ptr);
        if (valid) {
            float s = biome_weighted_score(b, ch, biome_sc, prepass_ptr, effective_moisture, false);
            insert_ranked_candidate(i, s, best_valid_idx, best_valid_score, second_valid_idx, second_valid_score);
        }
        float fs = biome_weighted_score(b, ch, biome_sc, prepass_ptr, effective_moisture, true);
        insert_ranked_candidate(i, fs, best_fallback_idx, best_fallback_score, second_fallback_idx, second_fallback_score);
    }

    int primary_idx = best_valid_idx >= 0 ? best_valid_idx : best_fallback_idx;
    if (primary_idx < 0) {
        return resolved;
    }
    resolved.primary = &biomes[primary_idx];
    resolved.primary_palette_index = biomes[primary_idx].palette_index;
    resolved.secondary_palette_index = resolved.primary_palette_index;
    resolved.primary_score = best_valid_idx >= 0 ? best_valid_score : best_fallback_score;

    int secondary_idx = -1;
    float secondary_score = 0.0f;
    auto try_select_secondary = [&](int candidate_idx, float candidate_score) -> bool {
        if (candidate_idx < 0 || candidate_idx == primary_idx) {
            return false;
        }
        secondary_idx = candidate_idx;
        secondary_score = candidate_score;
        return true;
    };
    if (best_valid_idx >= 0) {
        if (!try_select_secondary(second_valid_idx, second_valid_score)) {
            if (!try_select_secondary(best_fallback_idx, best_fallback_score)) {
                try_select_secondary(second_fallback_idx, second_fallback_score);
            }
        }
    } else {
        try_select_secondary(second_fallback_idx, second_fallback_score);
    }
    if (secondary_idx >= 0) {
        resolved.secondary = &biomes[secondary_idx];
        resolved.secondary_palette_index = biomes[secondary_idx].palette_index;
        resolved.secondary_score = secondary_score;
        float score_gap = clampf(resolved.primary_score - resolved.secondary_score, 0.0f, 1.0f);
        resolved.dominance = score_gap;
        resolved.ecotone_factor = clampf(1.0f - score_gap, 0.0f, 1.0f);
    }
    return resolved;
}

// ============================================================
// LocalVariationResolver (matches local_variation_resolver.gd)
// ============================================================

float ChunkGenerator::band_score(float value, float center, float half_width) {
    if (half_width <= 0.00001f) return 0.0f;
    return clampf(1.0f - fabsf(value - center) / half_width, 0.0f, 1.0f);
}

float ChunkGenerator::tag_bias(const std::vector<StringName>& tags,
                               const StringName* pos, int pos_count,
                               const StringName* neg, int neg_count) {
    float bias = 0.0f;
    for (int i = 0; i < pos_count; i++) {
        for (const auto& t : tags) { if (t == pos[i]) { bias += 0.035f; break; } }
    }
    for (int i = 0; i < neg_count; i++) {
        for (const auto& t : tags) { if (t == neg[i]) { bias -= 0.04f; break; } }
    }
    return clampf(bias, -0.12f, 0.12f);
}

ChunkGenerator::VariationResult ChunkGenerator::resolve_variation(
        int wx, int wy, const Channels& ch, const StructureContext& sc,
        const BiomeDef* biome, const BiomeDef* secondary_biome, float ecotone_factor) const {
    VariationResult vr;
    vr.kind = VAR_NONE; vr.score = 0.0f;
    vr.flora_mod = vr.wetness_mod = vr.rockiness_mod = vr.openness_mod = 0.0f;

    int cwx = wrap_x(wx, wrap_width);
    float ln = sample_noise_01(const_cast<FastNoiseLite&>(noise_field), cwx, wy);
    float pn = sample_noise_01(const_cast<FastNoiseLite&>(noise_patch), cwx, wy);
    float dn = sample_noise_01(const_cast<FastNoiseLite&>(noise_detail), cwx, wy);

    float fd = ch.flora_density, mo = ch.moisture, ru = ch.ruggedness;
    float rs = sc.ridge_strength, rv = sc.river_strength, fp = sc.floodplain_strength, mm = sc.mountain_mass;
    const std::vector<StringName>& primary_tags = biome ? biome->tags : std::vector<StringName>();
    const std::vector<StringName>* secondary_tags = secondary_biome ? &secondary_biome->tags : nullptr;

    auto blend = [](float a, float b, float w) { return a * w + b * (1.0f - w); };
    auto norm = [](float v) { return clampf(v - 0.18f, 0.0f, 1.0f); };
    auto blended_tag_bias = [&](const StringName* pos, int pos_count, const StringName* neg, int neg_count) {
        float primary_bias = tag_bias(primary_tags, pos, pos_count, neg, neg_count);
        if (secondary_tags == nullptr || secondary_tags->empty()) {
            return primary_bias;
        }
        float secondary_bias = tag_bias(*secondary_tags, pos, pos_count, neg, neg_count);
        float secondary_weight = clampf(ecotone_factor * 0.65f, 0.0f, 0.55f);
        return clampf(
            primary_bias * (1.0f - secondary_weight) + secondary_bias * secondary_weight,
            -0.12f,
            0.12f
        );
    };

    // Score 5 variation types (matches GDScript scoring functions)
    float scores[5];
    // sparse_flora
    { float bs = (1.0f-fd)*0.42f + (1.0f-mo)*0.18f + ru*0.12f + (1.0f-fp)*0.10f + (1.0f-rv)*0.08f + mm*0.10f;
      float ns = blend(band_score(ln,0.24f,0.24f), band_score(pn,0.34f,0.20f), 0.65f);
      StringName p[] = {StringName("dry"),StringName("upland"),StringName("mountain"),StringName("cold")};
      StringName n[] = {StringName("wet"),StringName("lowland")};
      scores[0] = norm(bs*0.74f + ns*0.18f + blended_tag_bias(p,4,n,2)); }
    // dense_flora
    { float bs = fd*0.42f + mo*0.24f + fp*0.12f + (1.0f-ru)*0.08f + (1.0f-rs)*0.08f + (1.0f-mm)*0.06f;
      float ns = blend(band_score(ln,0.78f,0.22f), band_score(dn,0.62f,0.20f), 0.70f);
      StringName p[] = {StringName("wet"),StringName("temperate"),StringName("baseline"),StringName("lowland")};
      StringName n[] = {StringName("dry"),StringName("mountain")};
      scores[1] = norm(bs*0.74f + ns*0.18f + blended_tag_bias(p,4,n,2)); }
    // clearing
    { float vg = clampf(fd*1.35f - 0.18f, 0.0f, 1.0f);
      float bs = fd*0.28f + mo*0.10f + (1.0f-ru)*0.18f + (1.0f-rs)*0.08f + (1.0f-rv)*0.06f;
      float ns = blend(band_score(ln,0.50f,0.16f), band_score(pn,0.48f,0.14f), 0.55f);
      StringName p[] = {StringName("temperate"),StringName("baseline"),StringName("wet")};
      StringName n[] = {StringName("mountain"),StringName("dry")};
      scores[2] = norm(vg * (bs*0.72f + ns*0.22f + blended_tag_bias(p,3,n,2))); }
    // rocky_patch
    { float bs = ru*0.38f + rs*0.22f + mm*0.18f + (1.0f-fd)*0.10f + (1.0f-mo)*0.06f + (1.0f-fp)*0.06f;
      float ns = blend(band_score(ln,0.86f,0.18f), band_score(dn,0.82f,0.18f), 0.65f);
      StringName p[] = {StringName("mountain"),StringName("highland"),StringName("upland")};
      StringName n[] = {StringName("wet"),StringName("lowland")};
      scores[3] = norm(bs*0.76f + ns*0.16f + blended_tag_bias(p,3,n,2)); }
    // wet_patch
    { float bs = mo*0.34f + fp*0.26f + rv*0.18f + (1.0f-ru)*0.08f + fd*0.06f + (1.0f-mm)*0.04f;
      float ns = blend(band_score(ln,0.12f,0.18f), band_score(pn,0.70f,0.20f), 0.70f);
      StringName p[] = {StringName("wet"),StringName("lowland"),StringName("temperate")};
      StringName n[] = {StringName("dry"),StringName("mountain"),StringName("highland")};
      scores[4] = norm(bs*0.76f + ns*0.16f + blended_tag_bias(p,3,n,3)); }

    // Best selection (matches GDScript kind order)
    constexpr float VAR_EPS = 0.00001f;
    VarKind kinds[] = { VAR_SPARSE_FLORA, VAR_DENSE_FLORA, VAR_CLEARING, VAR_ROCKY_PATCH, VAR_WET_PATCH };
    for (int i = 0; i < 5; i++) {
        if (scores[i] > vr.score + VAR_EPS) { vr.kind = kinds[i]; vr.score = scores[i]; }
    }
    if (vr.score < local_variation_min_score) { vr.kind = VAR_NONE; vr.score = 0.0f; }
    if (vr.kind == VAR_NONE) return vr;

    // Modulations (matches _apply_modulations)
    float intensity = vr.score * lerpf(1.0f, 0.72f, clampf(ecotone_factor, 0.0f, 1.0f));
    float neutral_pull = clampf(ecotone_factor, 0.0f, 1.0f) * 0.28f;
    switch (vr.kind) {
        case VAR_SPARSE_FLORA:
            vr.flora_mod = -(0.16f + intensity*0.34f);
            vr.wetness_mod = -(0.06f + intensity*0.14f) + (0.04f - mo*0.04f);
            vr.rockiness_mod = 0.06f + intensity*0.18f + ru*0.08f;
            vr.openness_mod = 0.16f + intensity*0.34f;
            break;
        case VAR_DENSE_FLORA:
            vr.flora_mod = 0.18f + intensity*0.38f;
            vr.wetness_mod = 0.06f + intensity*0.16f + fp*0.08f;
            vr.rockiness_mod = -(0.04f + intensity*0.16f);
            vr.openness_mod = -(0.10f + intensity*0.30f);
            break;
        case VAR_CLEARING:
            vr.flora_mod = -(0.10f + intensity*0.26f);
            vr.wetness_mod = -(0.02f + intensity*0.08f);
            vr.rockiness_mod = -(0.04f + intensity*0.08f);
            vr.openness_mod = 0.18f + intensity*0.40f;
            break;
        case VAR_ROCKY_PATCH:
            vr.flora_mod = -(0.08f + intensity*0.22f);
            vr.wetness_mod = -(0.04f + intensity*0.14f);
            vr.rockiness_mod = 0.18f + intensity*0.42f + rs*0.10f + ru*0.08f;
            vr.openness_mod = 0.06f + intensity*0.16f;
            break;
        case VAR_WET_PATCH:
            vr.flora_mod = 0.04f + intensity*0.16f;
            vr.wetness_mod = 0.18f + intensity*0.40f + std::max(fp, rv)*0.10f;
            vr.rockiness_mod = -(0.06f + intensity*0.12f);
            vr.openness_mod = -(0.04f + intensity*0.12f);
            break;
        default: break;
    }
    if (neutral_pull > 0.0f) {
        vr.flora_mod = lerpf(vr.flora_mod, 0.0f, neutral_pull);
        vr.wetness_mod = lerpf(vr.wetness_mod, 0.0f, neutral_pull);
        vr.rockiness_mod = lerpf(vr.rockiness_mod, 0.0f, neutral_pull);
        vr.openness_mod = lerpf(vr.openness_mod, 0.0f, neutral_pull);
    }
    return vr;
}

// ============================================================
// TerrainResolver (matches surface_terrain_resolver.gd)
// ============================================================

ChunkGenerator::TerrainType ChunkGenerator::resolve_terrain(
        float dist_sq, const Channels& ch, const StructureContext& sc,
        const BiomePrePassSample& prepass, const VariationResult& vr) const {
    float safe_sq = (float)(safe_zone_radius * safe_zone_radius);
    float land_sq = (float)(land_guarantee_radius * land_guarantee_radius);
    float slope_value = clampf(prepass.slope, 0.0f, 1.0f);
    auto river_core_radius = [&]() {
        if (sc.river_width <= 0.0f) {
            return 0.0f;
        }
        float width_scale = lerpf(0.70f, 0.44f, slope_value);
        return std::max(1.2f, sc.river_width * width_scale);
    };
    auto bank_outer_radius = [&]() {
        if (sc.river_width <= 0.0f && sc.floodplain_strength <= 0.0f) {
            return 0.0f;
        }
        float river_radius = river_core_radius();
        float bank_reach = std::max(
            1.6f,
            sc.river_width * 0.72f + sc.floodplain_strength * lerpf(5.2f, 2.4f, slope_value)
        );
        return river_radius + bank_reach;
    };
    auto valley_carve_pressure = [&]() {
        if (sc.river_width <= 0.0f && sc.floodplain_strength <= 0.0f) {
            return 0.0f;
        }
        float carve_radius = std::max(
            2.0f,
            sc.river_width * lerpf(1.0f, 1.45f, slope_value)
                + sc.floodplain_strength * lerpf(2.6f, 1.8f, slope_value)
        );
        float t = clampf(1.0f - sc.river_distance / carve_radius, 0.0f, 1.0f);
        float proximity_pressure = t * t * (3.0f - 2.0f * t);
        return std::max(proximity_pressure, sc.floodplain_strength * 0.85f);
    };

    // Safe zone
    if (dist_sq <= safe_sq) return GROUND;

    // River
    if (dist_sq > land_sq) {
        float river_radius = river_core_radius();
        float effective_river_strength = sc.river_strength + sc.floodplain_strength * 0.10f
            + vr.wetness_mod * 0.10f - vr.rockiness_mod * 0.04f;
        float visible_radius = river_radius
            + std::max(0.0f, effective_river_strength - river_min_strength * 0.75f) * 3.0f
            + std::max(0.0f, sc.floodplain_strength - 0.30f) * 1.6f;
        float allowed_height = river_max_height + sc.river_width * 0.09f + (1.0f - slope_value) * 0.10f
            + sc.river_strength * 0.10f + sc.floodplain_strength * 0.05f;
        if (visible_radius > 0.0f
            && sc.river_distance <= visible_radius
            && effective_river_strength >= river_min_strength * 0.75f
            && ch.height <= allowed_height) {
            return WATER;
        }
    }

    // River bank
    if (dist_sq > land_sq) {
        float outer_radius = bank_outer_radius();
        float effective_floodplain = sc.floodplain_strength + vr.wetness_mod * 0.08f - vr.rockiness_mod * 0.02f;
        float effective_river_strength = sc.river_strength + vr.wetness_mod * 0.08f;
        bool semantic_bank_override = effective_floodplain >= 0.18f && effective_river_strength >= 0.10f;
        float visible_bank_radius = outer_radius
            + std::max(0.0f, effective_floodplain - bank_min_floodplain * 0.55f) * 4.0f
            + std::max(0.0f, effective_river_strength - bank_min_river * 0.75f) * 2.0f;
        visible_bank_radius += std::max(0.0f, effective_floodplain - 0.18f) * 10.0f
            + std::max(0.0f, effective_river_strength - 0.10f) * 6.0f;
        float allowed_height = bank_max_height + sc.river_width * 0.06f + (1.0f - slope_value) * 0.08f
            + effective_floodplain * 0.10f
            + effective_river_strength * 0.10f
            + std::max(0.0f, effective_floodplain - 0.18f) * 0.18f;
        if ((semantic_bank_override || (visible_bank_radius > 0.0f && sc.river_distance <= visible_bank_radius))
            && effective_floodplain >= bank_min_floodplain * 0.55f
            && !(sc.ridge_strength > (bank_ridge_exclusion + 0.16f)
                && slope_value > 0.60f
                && effective_floodplain < 0.45f
                && !semantic_bank_override)
            && (ch.height <= allowed_height || (semantic_bank_override && ch.height <= allowed_height + 0.16f))
            && (
                effective_river_strength >= bank_min_river * 0.75f
                || ch.moisture + vr.wetness_mod * 0.10f > bank_min_moisture * 0.90f
            )
            && sc.river_distance > river_core_radius()) {
            return SAND;
        }
    }

    // Mountain core
    if (dist_sq > land_sq) {
        if (!(sc.ridge_strength < 0.18f && sc.mountain_mass < 0.16f)) {
            float ruggedness_gate = clampf(ch.ruggedness * 0.52f + slope_value * 0.48f, 0.0f, 1.0f);
            float terrain_gate = clampf(ch.height * 0.32f + ruggedness_gate * 0.40f + slope_value * 0.28f, 0.22f, 1.0f);
            float combined = sc.ridge_strength * ridge_backbone_weight;
            combined += sc.mountain_mass * (massif_fill_weight + 0.20f);
            combined += std::max(0.0f, sc.ridge_strength - 0.50f) * (core_bonus_weight * 0.92f);
            combined += std::max(0.0f, sc.mountain_mass - 0.32f) * 0.16f;
            combined += std::max(0.0f, slope_value - 0.28f) * 0.20f;
            combined += ruggedness_gate * 0.12f;
            combined -= valley_carve_pressure() * 0.24f;
            combined -= sc.floodplain_strength * 0.06f;
            combined += vr.rockiness_mod * 0.08f;
            combined -= vr.wetness_mod * 0.05f;
            combined -= vr.openness_mod * 0.05f;
            float terrain_support = lerpf(0.70f, 1.0f, terrain_gate);
            combined *= terrain_support;
            if (combined >= mountain_threshold_value * 0.94f) return ROCK;
        }
    }

    // Foothills
    if (dist_sq > land_sq) {
        float primary_mass = std::max(sc.ridge_strength * 0.68f, sc.mountain_mass);
        if (!(primary_mass < 0.16f && slope_value < 0.28f)) {
            float ruggedness_gate = clampf(ch.ruggedness * 0.58f + slope_value * 0.42f, 0.0f, 1.0f);
            float combined = sc.ridge_strength * 0.22f;
            combined += sc.mountain_mass * 0.38f;
            combined += std::max(0.0f, sc.mountain_mass - 0.24f) * 0.12f;
            combined += slope_value * 0.24f;
            combined += ruggedness_gate * 0.14f;
            combined += std::max(0.0f, ch.height - 0.36f) * 0.14f;
            combined -= valley_carve_pressure() * 0.28f;
            combined -= sc.floodplain_strength * 0.08f;
            combined += vr.rockiness_mod * 0.06f;
            combined -= vr.wetness_mod * 0.03f;
            combined -= vr.openness_mod * 0.05f;
            if (combined >= mountain_threshold_value * 0.62f) return ROCK;
        }
    }

    return GROUND;
}

void ChunkGenerator::apply_polar_surface_modifiers(
        TerrainType terrain, const Channels& ch, const StructureContext& sc,
        const BiomePrePassSample& prepass,
        int& io_variation_id, float& io_height, float& io_flora_density) const {
    if (terrain == ROCK) return;

    float cold_factor = resolve_cold_factor(ch.temperature);
    float hot_factor = resolve_hot_factor(ch.temperature);
    if (cold_factor <= 0.0f && hot_factor <= 0.0f) return;

    int overlay_id = io_variation_id;
    bool flat_surface = is_flat_polar_surface(prepass);

    if (terrain == WATER) {
        if (ch.temperature < prepass_frozen_river_threshold && cold_factor > 0.0f) {
            overlay_id = VAR_ICE;
        }
    } else if (flat_surface) {
        if (cold_factor > 0.0f && io_height < ice_cap_max_height) {
            overlay_id = VAR_ICE;
            io_height = clampf(io_height + cold_factor * ice_cap_height_bonus, 0.0f, 1.0f);
        } else if (hot_factor > 0.70f && terrain == SAND && sc.floodplain_strength >= bank_min_floodplain) {
            overlay_id = VAR_SALT_FLAT;
        } else if (hot_factor > 0.0f) {
            overlay_id = VAR_SCORCHED;
        }
    }

    io_variation_id = overlay_id;
    float cold_suppression = std::max(0.0f, 1.0f - cold_factor * 0.9f);
    float hot_suppression = std::max(0.0f, 1.0f - hot_factor * 0.95f);
    io_flora_density = clampf(io_flora_density * cold_suppression * hot_suppression, 0.0f, 1.0f);
    if (overlay_id == VAR_SALT_FLAT || overlay_id == VAR_DRY_RIVERBED) {
        io_flora_density = std::min(io_flora_density, 0.03f);
    }
}

float ChunkGenerator::resolve_cold_factor(float temperature) const {
    return clampf(
        (cold_pole_temperature - temperature) / std::max(0.001f, cold_pole_transition_width),
        0.0f,
        1.0f
    );
}

float ChunkGenerator::resolve_hot_factor(float temperature) const {
    return clampf(
        (temperature - hot_pole_temperature) / std::max(0.001f, hot_pole_transition_width),
        0.0f,
        1.0f
    );
}

bool ChunkGenerator::is_flat_polar_surface(const BiomePrePassSample& prepass) const {
    return clampf(prepass.slope, 0.0f, 1.0f) <= 0.15f;
}

// ============================================================
// generate_chunk() — authoritative pre-pass-backed pipeline
// ============================================================

Dictionary ChunkGenerator::generate_chunk(Vector2i chunk_coord, Vector2i spawn_tile, Dictionary generation_request) {
    if (!initialized || !has_authoritative_prepass) return Dictionary();

    int cs = chunk_size;
    int total = cs * cs;

    int canonical_cx = wrap_x(chunk_coord.x, wrap_width / std::max(cs, 1));
    int base_x = canonical_cx * cs;
    int base_y = chunk_coord.y * cs;

    String snapshot_kind = generation_request.get("snapshot_kind", String());
    int snapshot_chunk_size = (int)generation_request.get("chunk_size", 0);
    bool valid_native_request = snapshot_kind == "native_chunk_generation_request_v1"
        && snapshot_chunk_size == cs;
    PackedFloat32Array height_inputs;
    PackedFloat32Array temperature_inputs;
    PackedFloat32Array moisture_inputs;
    PackedFloat32Array ruggedness_inputs;
    PackedFloat32Array flora_density_inputs;
    PackedFloat32Array latitude_inputs;
    PackedFloat32Array drainage_inputs;
    PackedFloat32Array slope_inputs;
    PackedFloat32Array rain_shadow_inputs;
    PackedFloat32Array continentalness_inputs;
    PackedFloat32Array ridge_strength_inputs;
    PackedFloat32Array river_width_inputs;
    PackedFloat32Array river_distance_inputs;
    PackedFloat32Array floodplain_strength_inputs;
    PackedFloat32Array mountain_mass_inputs;
    bool valid_authoritative_inputs = false;
    if (!valid_native_request) {
        height_inputs = generation_request.get("height_values", PackedFloat32Array());
        temperature_inputs = generation_request.get("temperature_values", PackedFloat32Array());
        moisture_inputs = generation_request.get("moisture_values", PackedFloat32Array());
        ruggedness_inputs = generation_request.get("ruggedness_values", PackedFloat32Array());
        flora_density_inputs = generation_request.get("flora_density_values", PackedFloat32Array());
        latitude_inputs = generation_request.get("latitude_values", PackedFloat32Array());
        drainage_inputs = generation_request.get("drainage_values", PackedFloat32Array());
        slope_inputs = generation_request.get("slope_values", PackedFloat32Array());
        rain_shadow_inputs = generation_request.get("rain_shadow_values", PackedFloat32Array());
        continentalness_inputs = generation_request.get("continentalness_values", PackedFloat32Array());
        ridge_strength_inputs = generation_request.get("ridge_strength_values", PackedFloat32Array());
        river_width_inputs = generation_request.get("river_width_values", PackedFloat32Array());
        river_distance_inputs = generation_request.get("river_distance_values", PackedFloat32Array());
        floodplain_strength_inputs = generation_request.get("floodplain_strength_values", PackedFloat32Array());
        mountain_mass_inputs = generation_request.get("mountain_mass_values", PackedFloat32Array());
        valid_authoritative_inputs = snapshot_kind == "world_chunk_authoritative_inputs_v1"
            && snapshot_chunk_size == cs
            && height_inputs.size() == total
            && temperature_inputs.size() == total
            && moisture_inputs.size() == total
            && ruggedness_inputs.size() == total
            && flora_density_inputs.size() == total
            && latitude_inputs.size() == total
            && drainage_inputs.size() == total
            && slope_inputs.size() == total
            && rain_shadow_inputs.size() == total
            && continentalness_inputs.size() == total
            && ridge_strength_inputs.size() == total
            && river_width_inputs.size() == total
            && river_distance_inputs.size() == total
            && floodplain_strength_inputs.size() == total
            && mountain_mass_inputs.size() == total;
    }
    if (!valid_authoritative_inputs && !valid_native_request) {
        UtilityFunctions::push_error(
            "[ChunkGenerator] generate_chunk requires native_chunk_generation_request_v1 or legacy authoritative chunk inputs; native generation samples channels from its authoritative WorldPrePass snapshot."
        );
        return Dictionary();
    }

    PackedByteArray terrain;
    terrain.resize(total);
    PackedFloat32Array height_arr;
    height_arr.resize(total);
    PackedByteArray variation;
    variation.resize(total);
    PackedByteArray biome_arr;
    biome_arr.resize(total);
    PackedByteArray secondary_biome_arr;
    secondary_biome_arr.resize(total);
    PackedFloat32Array ecotone_values;
    ecotone_values.resize(total);
    PackedFloat32Array flora_density_values;
    flora_density_values.resize(total);
    PackedFloat32Array flora_modulation_values;
    flora_modulation_values.resize(total);

    float spawn_x = (float)spawn_tile.x;
    float spawn_y = (float)spawn_tile.y;

    for (int ly = 0; ly < cs; ly++) {
        for (int lx = 0; lx < cs; lx++) {
            int wx = base_x + lx;
            int wy = base_y + ly;
            int idx = ly * cs + lx;

            BiomePrePassSample prepass{};
            Channels ch{};
            if (valid_authoritative_inputs) {
                ch.height = clampf(height_inputs[idx], 0.0f, 1.0f);
                ch.temperature = clampf(temperature_inputs[idx], 0.0f, 1.0f);
                ch.moisture = clampf(moisture_inputs[idx], 0.0f, 1.0f);
                ch.ruggedness = clampf(ruggedness_inputs[idx], 0.0f, 1.0f);
                ch.flora_density = clampf(flora_density_inputs[idx], 0.0f, 1.0f);
                ch.latitude = clampf(latitude_inputs[idx], 0.0f, 1.0f);
                prepass.drainage = clampf(drainage_inputs[idx], 0.0f, 1.0f);
                prepass.slope = clampf(slope_inputs[idx], 0.0f, 1.0f);
                prepass.rain_shadow = clampf(rain_shadow_inputs[idx], 0.0f, 1.0f);
                prepass.continentalness = clampf(continentalness_inputs[idx], 0.0f, 1.0f);
                prepass.ridge_strength = clampf(ridge_strength_inputs[idx], 0.0f, 1.0f);
                prepass.river_width = std::max(0.0f, river_width_inputs[idx]);
                prepass.river_distance = std::max(0.0f, river_distance_inputs[idx]);
                prepass.floodplain_strength = clampf(floodplain_strength_inputs[idx], 0.0f, 1.0f);
                prepass.mountain_mass = clampf(mountain_mass_inputs[idx], 0.0f, 1.0f);
            } else {
                ch = sample_channels(wx, wy);
                prepass = sample_biome_prepass(wx, wy);
            }
            StructureContext sc = build_structure_context_from_prepass(prepass);
            BiomeSelection biome_selection = resolve_biome_selection(wx, wy, ch, sc, prepass);
            VariationResult vr = resolve_variation(
                wx,
                wy,
                ch,
                sc,
                biome_selection.primary,
                biome_selection.secondary,
                biome_selection.ecotone_factor
            );

            float dx_s = (float)(wrap_x(wx, wrap_width) - wrap_x((int)spawn_x, wrap_width));
            if (wrap_width > 0) {
                if (dx_s > wrap_width / 2) dx_s -= wrap_width;
                else if (dx_s < -wrap_width / 2) dx_s += wrap_width;
            }
            float dy_s = (float)(wy - (int)spawn_y);
            float dist_sq = dx_s * dx_s + dy_s * dy_s;
            TerrainType tt = resolve_terrain(dist_sq, ch, sc, prepass, vr);

            int variation_id = 0;
            float flora_modulation_value = 0.0f;
            if (tt == GROUND && vr.kind != VAR_NONE) {
                variation_id = (int)vr.kind;
                flora_modulation_value = vr.flora_mod;
            }

            float height_value = ch.height;
            float flora_density_value = ch.flora_density;
            apply_polar_surface_modifiers(
                tt,
                ch,
                sc,
                prepass,
                variation_id,
                height_value,
                flora_density_value
            );
            if (variation_id == VAR_ICE || variation_id == VAR_SCORCHED || variation_id == VAR_SALT_FLAT) {
                flora_modulation_value = 0.0f;
            }

            int primary_biome_idx = std::max(0, biome_selection.primary_palette_index);
            int secondary_biome_idx = primary_biome_idx;
            float ecotone_value = 0.0f;
            if (biome_selection.secondary != nullptr && biome_selection.secondary_palette_index != primary_biome_idx) {
                secondary_biome_idx = std::max(0, biome_selection.secondary_palette_index);
                ecotone_value = clampf(biome_selection.ecotone_factor, 0.0f, 1.0f);
            }

            terrain[idx] = (uint8_t)tt;
            height_arr[idx] = height_value;
            variation[idx] = (uint8_t)variation_id;
            biome_arr[idx] = (uint8_t)primary_biome_idx;
            secondary_biome_arr[idx] = (uint8_t)secondary_biome_idx;
            ecotone_values[idx] = ecotone_value;
            flora_density_values[idx] = flora_density_value;
            flora_modulation_values[idx] = flora_modulation_value;
        }
    }

    Dictionary result;
    result["chunk_coord"] = chunk_coord;
    result["canonical_chunk_coord"] = Vector2i(canonical_cx, chunk_coord.y);
    result["base_tile"] = Vector2i(base_x, base_y);
    result["chunk_size"] = cs;
    result["terrain"] = terrain;
    result["height"] = height_arr;
    result["variation"] = variation;
    result["biome"] = biome_arr;
    result["secondary_biome"] = secondary_biome_arr;
    result["ecotone_values"] = ecotone_values;
    result["flora_density_values"] = flora_density_values;
    result["flora_modulation_values"] = flora_modulation_values;
    return result;
}

Dictionary ChunkGenerator::sample_tile(Vector2i world_pos, Vector2i spawn_tile) {
    if (!initialized || !has_authoritative_prepass) {
        return Dictionary();
    }

    int wx = wrap_x(world_pos.x, wrap_width);
    int wy = world_pos.y;
    Channels ch = sample_channels(wx, wy);
    BiomePrePassSample prepass = sample_biome_prepass(wx, wy);
    StructureContext sc = build_structure_context_from_prepass(prepass);
    BiomeSelection biome_selection = resolve_biome_selection(wx, wy, ch, sc, prepass);
    VariationResult vr = resolve_variation(
        wx,
        wy,
        ch,
        sc,
        biome_selection.primary,
        biome_selection.secondary,
        biome_selection.ecotone_factor
    );

    float dx_s = (float)(wrap_x(wx, wrap_width) - wrap_x(spawn_tile.x, wrap_width));
    if (wrap_width > 0) {
        if (dx_s > wrap_width / 2) dx_s -= wrap_width;
        else if (dx_s < -wrap_width / 2) dx_s += wrap_width;
    }
    float dy_s = (float)(wy - spawn_tile.y);
    float dist_sq = dx_s * dx_s + dy_s * dy_s;
    TerrainType tt = resolve_terrain(dist_sq, ch, sc, prepass, vr);

    int variation_id = 0;
    float flora_modulation_value = 0.0f;
    if (tt == GROUND && vr.kind != VAR_NONE) {
        variation_id = (int)vr.kind;
        flora_modulation_value = vr.flora_mod;
    }

    float height_value = ch.height;
    float flora_density_value = ch.flora_density;
    apply_polar_surface_modifiers(
        tt,
        ch,
        sc,
        prepass,
        variation_id,
        height_value,
        flora_density_value
    );
    if (variation_id == VAR_ICE || variation_id == VAR_SCORCHED || variation_id == VAR_SALT_FLAT) {
        flora_modulation_value = 0.0f;
    }

    Dictionary result;
    result["world_pos"] = Vector2i(wx, wy);
    result["terrain"] = (int)tt;
    result["height"] = height_value;
    result["variation"] = variation_id;
    result["biome"] = std::max(0, biome_selection.primary_palette_index);
    result["secondary_biome"] = biome_selection.secondary != nullptr
        ? std::max(0, biome_selection.secondary_palette_index)
        : std::max(0, biome_selection.primary_palette_index);
    result["primary_biome_id"] = biome_selection.primary != nullptr ? String(biome_selection.primary->id) : String();
    result["secondary_biome_id"] = biome_selection.secondary != nullptr
        ? String(biome_selection.secondary->id)
        : (biome_selection.primary != nullptr ? String(biome_selection.primary->id) : String());
    result["primary_score"] = biome_selection.primary_score;
    result["secondary_score"] = biome_selection.secondary_score;
    result["dominance"] = biome_selection.dominance;
    result["ecotone_factor"] = biome_selection.ecotone_factor;
    result["flora_density"] = flora_density_value;
    result["flora_modulation"] = flora_modulation_value;
    result["channel_height"] = ch.height;
    result["channel_temperature"] = ch.temperature;
    result["channel_moisture"] = ch.moisture;
    result["channel_ruggedness"] = ch.ruggedness;
    result["channel_flora_density"] = ch.flora_density;
    result["channel_latitude"] = ch.latitude;
    result["ridge_strength"] = sc.ridge_strength;
    result["river_strength"] = sc.river_strength;
    result["floodplain_strength"] = sc.floodplain_strength;
    result["mountain_mass"] = sc.mountain_mass;
    result["river_distance"] = sc.river_distance;
    result["river_width"] = sc.river_width;
    result["drainage"] = prepass.drainage;
    result["slope"] = prepass.slope;
    result["rain_shadow"] = prepass.rain_shadow;
    result["continentalness"] = prepass.continentalness;
    return result;
}
