#include "chunk_generator.h"
#include <cmath>
#include <algorithm>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

using namespace godot;

// ============================================================
// Lifecycle
// ============================================================

ChunkGenerator::ChunkGenerator() {}
ChunkGenerator::~ChunkGenerator() {}

void ChunkGenerator::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize", "seed", "params"), &ChunkGenerator::initialize);
    ClassDB::bind_method(D_METHOD("generate_chunk", "chunk_coord", "spawn_tile"), &ChunkGenerator::generate_chunk);
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

    // --- Structure sampler params ---
    mountain_density = (float)(double)p_params.get("mountain_density", 0.3);
    mountain_chaininess = (float)(double)p_params.get("mountain_chaininess", 0.6);
    ridge_spacing_tiles = (float)(double)p_params.get("ridge_spacing_tiles", 640.0);
    ridge_core_width_tiles = (float)(double)p_params.get("ridge_core_width_tiles", 104.0);
    ridge_feather_tiles = (float)(double)p_params.get("ridge_feather_tiles", 224.0);
    ridge_warp_amplitude_tiles = (float)(double)p_params.get("ridge_warp_amplitude_tiles", 260.0);
    ridge_secondary_warp_frequency = (float)(double)p_params.get("ridge_secondary_warp_frequency", 0.0014);
    ridge_secondary_warp_amplitude_tiles = (float)(double)p_params.get("ridge_secondary_warp_amplitude_tiles", 0.0);
    ridge_secondary_spacing_tiles = (float)(double)p_params.get("ridge_secondary_spacing_tiles", 0.0);
    ridge_secondary_core_width_tiles = (float)(double)p_params.get("ridge_secondary_core_width_tiles", 0.0);
    ridge_secondary_feather_tiles = (float)(double)p_params.get("ridge_secondary_feather_tiles", 0.0);
    ridge_secondary_weight = (float)(double)p_params.get("ridge_secondary_weight", 0.0);
    river_spacing_tiles = (float)(double)p_params.get("river_spacing_tiles", 480.0);
    river_core_width_tiles = (float)(double)p_params.get("river_core_width_tiles", 42.0);
    river_floodplain_width_tiles = (float)(double)p_params.get("river_floodplain_width_tiles", 224.0);
    river_warp_amplitude_tiles = (float)(double)p_params.get("river_warp_amplitude_tiles", 300.0);

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
    hot_evaporation_rate = (float)(double)p_params.get("hot_evaporation_rate", 0.25);
    // Pre-compute mountain weights (matches surface_terrain_resolver.gd lines 24-32)
    float chain = clampf(mountain_chaininess, 0.0f, 1.0f);
    mountain_threshold_value = clampf(mountain_base_threshold - mountain_density, 0.0f, 1.0f);
    ridge_backbone_weight = lerpf(0.76f, 0.92f, chain);
    massif_fill_weight = lerpf(0.30f, 0.38f, chain);
    core_bonus_weight = lerpf(0.16f, 0.28f, chain);

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
    float ridge_warp_freq = (float)(double)p_params.get("ridge_warp_frequency", 0.0018);
    float ridge_cluster_freq = (float)(double)p_params.get("ridge_cluster_frequency", 0.00075);
    float river_warp_freq = (float)(double)p_params.get("river_warp_frequency", 0.0016);
    float local_var_freq = (float)(double)p_params.get("local_variation_frequency", 0.018);
    int local_var_oct = (int)p_params.get("local_variation_octaves", 2);

    // --- Configure 12 noise instances (spec table) ---
    setup_noise(noise_height,                  seed + 11,  height_freq, height_oct);
    setup_noise(noise_temperature,             seed + 101, temperature_freq, temperature_oct);
    setup_noise(noise_moisture,                seed + 131, moisture_freq, moisture_oct);
    setup_noise(noise_ruggedness,              seed + 151, ruggedness_freq, ruggedness_oct);
    setup_noise(noise_flora_density,           seed + 181, flora_density_freq, flora_density_oct);
    setup_noise(noise_ridge_warp,              seed + 211, ridge_warp_freq, 2);
    setup_noise(noise_ridge_secondary_warp,    seed + 217, ridge_secondary_warp_frequency, 2);
    setup_noise(noise_ridge_cluster,           seed + 223, ridge_cluster_freq, 3);
    setup_noise(noise_river_warp,              seed + 241, river_warp_freq, 2);
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

    // --- Parse flora/decor set definitions ---
    flora_sets.clear();
    decor_sets.clear();
    biome_flora_configs.clear();
    Array flora_sets_arr = p_params.get("flora_sets", Array());
    for (int i = 0; i < flora_sets_arr.size(); i++) {
        Dictionary fsd = flora_sets_arr[i];
        FloraSetDef fs;
        fs.id = (StringName)fsd.get("id", StringName());
        fs.base_density = (float)(double)fsd.get("base_density", 0.10);
        fs.flora_channel_weight = (float)(double)fsd.get("flora_channel_weight", 1.0);
        fs.flora_modulation_weight = (float)(double)fsd.get("flora_modulation_weight", 0.5);
        Array sf = fsd.get("subzone_filters", Array());
        for (int j = 0; j < sf.size(); j++) fs.subzone_filters.push_back((StringName)sf[j]);
        Array es = fsd.get("excluded_subzones", Array());
        for (int j = 0; j < es.size(); j++) fs.excluded_subzones.push_back((StringName)es[j]);
        Array entries_arr = fsd.get("entries", Array());
        for (int j = 0; j < entries_arr.size(); j++) {
            Dictionary ed = entries_arr[j];
            FloraEntryDef fe;
            fe.id = (StringName)ed.get("id", StringName());
            fe.color = (Color)ed.get("color", Color(0.3f, 0.5f, 0.2f, 1.0f));
            fe.size = (Vector2i)ed.get("size", Vector2i(12, 24));
            fe.z_offset = (int)ed.get("z_offset", 0);
            fe.weight = (float)(double)ed.get("weight", 1.0);
            fe.min_density_threshold = (float)(double)ed.get("min_density_threshold", 0.0);
            fe.max_density_threshold = (float)(double)ed.get("max_density_threshold", 1.0);
            fs.entries.push_back(fe);
        }
        flora_sets.push_back(fs);
    }
    Array decor_sets_arr = p_params.get("decor_sets", Array());
    for (int i = 0; i < decor_sets_arr.size(); i++) {
        Dictionary dsd = decor_sets_arr[i];
        DecorSetDef ds;
        ds.id = (StringName)dsd.get("id", StringName());
        ds.base_density = (float)(double)dsd.get("base_density", 0.06);
        Array entries_arr = dsd.get("entries", Array());
        for (int j = 0; j < entries_arr.size(); j++) {
            Dictionary ed = entries_arr[j];
            DecorEntryDef de;
            de.id = (StringName)ed.get("id", StringName());
            de.color = (Color)ed.get("color", Color(0.4f, 0.35f, 0.3f, 1.0f));
            de.size = (Vector2i)ed.get("size", Vector2i(10, 10));
            de.z_offset = (int)ed.get("z_offset", -1);
            de.weight = (float)(double)ed.get("weight", 1.0);
            ds.entries.push_back(de);
        }
        Dictionary sdm = dsd.get("subzone_density_modifiers", Dictionary());
        Array sdm_keys = sdm.keys();
        for (int j = 0; j < sdm_keys.size(); j++) {
            ds.subzone_density_modifiers.push_back({(StringName)sdm_keys[j], (float)(double)sdm[sdm_keys[j]]});
        }
        decor_sets.push_back(ds);
    }
    // Per-biome flora/decor config (maps biome → set indices by id)
    biome_flora_configs.resize(biomes.size());
    for (int bi = 0; bi < (int)biomes.size(); bi++) {
        // Flora set IDs are passed per-biome in biome def
        Dictionary bd_flora = biome_array.size() > 0 ? (Dictionary)biome_array[0] : Dictionary(); // need per-biome
    }
    // Actually, biome flora/decor set ids are in biome definitions. Parse them:
    for (int i = 0; i < biome_array.size(); i++) {
        Dictionary bd = biome_array[i];
        // Find which biome index this maps to after sorting
        StringName bid = (StringName)bd.get("id", StringName());
        int palette_idx = (int)bd.get("palette_index", i);
        // Build flora config for this biome
        BiomeFloraConfig bfc;
        Array fids = bd.get("flora_set_ids", Array());
        for (int j = 0; j < fids.size(); j++) {
            StringName fsid = (StringName)fids[j];
            for (int k = 0; k < (int)flora_sets.size(); k++) {
                if (flora_sets[k].id == fsid) { bfc.flora_set_indices.push_back(k); break; }
            }
        }
        Array dids = bd.get("decor_set_ids", Array());
        for (int j = 0; j < dids.size(); j++) {
            StringName dsid = (StringName)dids[j];
            for (int k = 0; k < (int)decor_sets.size(); k++) {
                if (decor_sets[k].id == dsid) { bfc.decor_set_indices.push_back(k); break; }
            }
        }
        // Store by palette_index for direct lookup from biome_arr byte
        if (palette_idx >= (int)biome_flora_configs.size())
            biome_flora_configs.resize(palette_idx + 1);
        biome_flora_configs[palette_idx] = bfc;
    }

    // Normalize direction vectors (matches GDScript .normalized())
    {
        float raw_ridge[] = { 0.82f, 0.53f, 0.21f };
        float raw_ridge_sec[] = { 0.35f, -0.48f, 0.80f };
        float raw_river[] = { -0.31f, 0.90f, 0.30f };
        normalize_vec3(raw_ridge, ridge_dir);
        normalize_vec3(raw_ridge_sec, ridge_secondary_dir);
        normalize_vec3(raw_river, river_dir);
    }

    initialized = true;
}

void ChunkGenerator::normalize_vec3(const float in[3], float out[3]) {
    float len = sqrtf(in[0] * in[0] + in[1] * in[1] + in[2] * in[2]);
    if (len < 1e-9f) { out[0] = out[1] = out[2] = 0.0f; return; }
    out[0] = in[0] / len;
    out[1] = in[1] / len;
    out[2] = in[2] / len;
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
// StructureSampler — sample_structure()  (matches large_structure_sampler.gd)
// ============================================================

float ChunkGenerator::directed_coordinate(int wx, int wy, const float dir[3]) const {
    // Cylindrical point (matches _cylindrical_point)
    int wrapped = wrap_x(wx, wrap_width);
    float angle = TAU_F * (float)wrapped / (float)std::max(1, wrap_width);
    float radius = std::max(1.0f, (float)wrap_width / TAU_F);
    float px = cosf(angle) * radius;
    float py = (float)wy;
    float pz = sinf(angle) * radius;
    return px * dir[0] + py * dir[1] + pz * dir[2];
}

float ChunkGenerator::repeating_band(float coord, float spacing, float core_half_width, float feather_width) {
    if (spacing <= 0.001f) return 0.0f;
    float wrapped = fmodf(coord + spacing * 0.5f, spacing);
    if (wrapped < 0.0f) wrapped += spacing;
    wrapped -= spacing * 0.5f;
    float dist = fabsf(wrapped);
    if (dist <= core_half_width) return 1.0f;
    if (feather_width <= 0.001f) return 0.0f;
    return clampf(1.0f - ((dist - core_half_width) / feather_width), 0.0f, 1.0f);
}

ChunkGenerator::StructureContext ChunkGenerator::sample_structure(int wx, int wy, const Channels& ch) const {
    StructureContext sc;
    float h = ch.height;
    float r = ch.ruggedness;
    float m = ch.moisture;

    // --- Mountain mass (matches _sample_mountain_mass) ---
    float cluster_noise = sample_noise_01(const_cast<FastNoiseLite&>(noise_ridge_cluster), wx, wy);
    float density_floor = clampf(0.44f - mountain_density * 0.30f, 0.20f, 0.38f);
    float cluster_gate = clampf((cluster_noise - density_floor) / 0.44f, 0.0f, 1.0f);
    float terrain_gate_mm = clampf(h * 0.58f + r * 0.92f - 0.24f, 0.0f, 1.0f);
    sc.mountain_mass = clampf(cluster_gate * terrain_gate_mm, 0.0f, 1.0f);

    // --- Ridge strength (matches _sample_ridge_strength) ---
    float ridge_coord = directed_coordinate(wx, wy, ridge_dir);
    ridge_coord += sample_noise_signed(const_cast<FastNoiseLite&>(noise_ridge_warp), wx, wy) * ridge_warp_amplitude_tiles;
    float band = repeating_band(ridge_coord, ridge_spacing_tiles, ridge_core_width_tiles, ridge_feather_tiles);

    // Secondary cross-ridge
    if (ridge_secondary_weight > 0.001f) {
        float sec_coord = directed_coordinate(wx, wy, ridge_secondary_dir);
        sec_coord += sample_noise_signed(const_cast<FastNoiseLite&>(noise_ridge_secondary_warp), wx, wy) * ridge_secondary_warp_amplitude_tiles;
        float sec_band = repeating_band(sec_coord, ridge_secondary_spacing_tiles,
                                        ridge_secondary_core_width_tiles, ridge_secondary_feather_tiles);
        band = std::max(band, sec_band * ridge_secondary_weight);
    }

    float band_profile = smoothstep(band);
    float cluster_support = clampf(cluster_noise * 1.15f - 0.18f, 0.0f, 1.0f);
    float chain = clampf(mountain_chaininess, 0.0f, 1.0f);
    float terrain_gate_rs = clampf(h * 0.50f + r * 1.02f - 0.18f, 0.08f, 1.0f);
    float mass_floor = lerpf(0.24f, 0.46f, chain);
    float mass_gate = lerpf(mass_floor, 1.0f, sc.mountain_mass);
    float ridge_bias = lerpf(0.94f, 1.14f, chain);
    float ridge_backbone = std::max(band_profile, band * cluster_support);
    float massif_fill = sc.mountain_mass * lerpf(0.18f, 0.30f, chain);
    float core_bonus = std::max(0.0f, band_profile - 0.72f) * lerpf(0.18f, 0.28f, chain);
    sc.ridge_strength = clampf((ridge_backbone * ridge_bias + massif_fill + core_bonus) * terrain_gate_rs * mass_gate, 0.0f, 1.0f);

    // --- River strength (matches _sample_river_strength) ---
    float river_coord = directed_coordinate(wx, wy, river_dir);
    river_coord += sample_noise_signed(const_cast<FastNoiseLite&>(noise_river_warp), wx, wy) * river_warp_amplitude_tiles;
    float river_band = repeating_band(river_coord, river_spacing_tiles,
                                      river_core_width_tiles, river_floodplain_width_tiles * 0.70f);
    float river_profile = smoothstep(river_band);
    float lowland_gate_rv = clampf(1.0f - (h * 0.70f + r * 0.42f), 0.08f, 1.0f);
    float moisture_gate_rv = clampf(0.58f + m * 0.42f, 0.0f, 1.0f);
    float valley_gate = clampf(1.0f - (h * 0.62f + r * 0.48f + sc.ridge_strength * 0.22f), 0.0f, 1.0f);
    float mountain_penalty_rv = clampf(1.0f - sc.ridge_strength * 0.34f - sc.mountain_mass * 0.18f, 0.22f, 1.0f);
    float drainage_bonus = std::max(0.0f, m - 0.42f) * 0.12f;
    sc.river_strength = clampf(
        (river_profile * lowland_gate_rv * moisture_gate_rv * mountain_penalty_rv)
        + (river_band * valley_gate * drainage_bonus), 0.0f, 1.0f);

    // --- Floodplain strength (matches _sample_floodplain_strength) ---
    // Re-uses river_coord (same directed coordinate + warp)
    float fp_band = repeating_band(river_coord, river_spacing_tiles,
                                   river_core_width_tiles * 2.5f, river_floodplain_width_tiles);
    float fp_profile = smoothstep(fp_band);
    float lowland_gate_fp = clampf(1.0f - (h * 0.60f + r * 0.25f), 0.10f, 1.0f);
    float moisture_gate_fp = clampf(0.45f + m * 0.55f, 0.0f, 1.0f);
    float mountain_penalty_fp = clampf(1.0f - sc.mountain_mass * 0.36f, 0.28f, 1.0f);
    float river_support = std::max(sc.river_strength * 0.82f, fp_band * 0.46f);
    sc.floodplain_strength = clampf(
        std::max(river_support, fp_profile * lowland_gate_fp * moisture_gate_fp * mountain_penalty_fp),
        0.0f, 1.0f);

    return sc;
}

// ============================================================
// BiomeResolver (matches biome_resolver.gd + biome_data.gd)
// ============================================================

float ChunkGenerator::score_range(float value, float min_v, float max_v, bool soft) {
    float lo = std::min(min_v, max_v);
    float hi = std::max(min_v, max_v);
    constexpr float EPS = 0.00001f;
    if (fabsf(hi - lo) < EPS) {
        if (fabsf(value - lo) < EPS) return 1.0f;
        if (!soft) return 0.0f;
        return 1.0f / (1.0f + fabsf(value - lo) * 8.0f);
    }
    if (value < lo) {
        if (!soft) return 0.0f;
        return 1.0f / (1.0f + ((lo - value) / std::max(hi - lo, EPS)) * 4.0f);
    }
    if (value > hi) {
        if (!soft) return 0.0f;
        return 1.0f / (1.0f + ((value - hi) / std::max(hi - lo, EPS)) * 4.0f);
    }
    float center = (lo + hi) * 0.5f;
    float half = std::max((hi - lo) * 0.5f, EPS);
    return clampf(1.0f - fabsf(value - center) / half, 0.0f, 1.0f);
}

bool ChunkGenerator::biome_matches(const BiomeDef& b, const Channels& ch, const StructureContext& sc) const {
    constexpr float E = 0.00001f;
    auto in_range = [E](float v, float lo, float hi) {
        float l = std::min(lo, hi), u = std::max(lo, hi);
        return v >= l - E && v <= u + E;
    };
    return in_range(ch.height, b.min_height, b.max_height)
        && in_range(ch.temperature, b.min_temperature, b.max_temperature)
        && in_range(ch.moisture, b.min_moisture, b.max_moisture)
        && in_range(ch.ruggedness, b.min_ruggedness, b.max_ruggedness)
        && in_range(ch.flora_density, b.min_flora_density, b.max_flora_density)
        && in_range(ch.latitude, b.min_latitude, b.max_latitude)
        && in_range(sc.ridge_strength, b.min_ridge_strength, b.max_ridge_strength)
        && in_range(sc.river_strength, b.min_river_strength, b.max_river_strength)
        && in_range(sc.floodplain_strength, b.min_floodplain_strength, b.max_floodplain_strength);
}

float ChunkGenerator::biome_weighted_score(const BiomeDef& b, const Channels& ch,
                                           const StructureContext& sc, bool soft) const {
    float tw = 0.0f, ts = 0.0f;
    auto add = [&](float w, float val, float lo, float hi) {
        if (w <= 0.0f) return;
        tw += w;
        ts += score_range(val, lo, hi, soft) * w;
    };
    add(b.height_weight, ch.height, b.min_height, b.max_height);
    add(b.temperature_weight, ch.temperature, b.min_temperature, b.max_temperature);
    add(b.moisture_weight, ch.moisture, b.min_moisture, b.max_moisture);
    add(b.ruggedness_weight, ch.ruggedness, b.min_ruggedness, b.max_ruggedness);
    add(b.flora_density_weight, ch.flora_density, b.min_flora_density, b.max_flora_density);
    add(b.latitude_weight, ch.latitude, b.min_latitude, b.max_latitude);
    add(b.ridge_strength_weight, sc.ridge_strength, b.min_ridge_strength, b.max_ridge_strength);
    add(b.river_strength_weight, sc.river_strength, b.min_river_strength, b.max_river_strength);
    add(b.floodplain_strength_weight, sc.floodplain_strength, b.min_floodplain_strength, b.max_floodplain_strength);
    return tw > 0.0f ? ts / tw : 0.0f;
}

int ChunkGenerator::resolve_biome(const Channels& ch, const StructureContext& sc) const {
    constexpr float SCORE_EPS = 0.0001f;
    int best_valid_idx = -1;
    float best_valid_score = -1.0f;
    int best_fallback_idx = -1;
    float best_fallback_score = -1.0f;
    for (int i = 0; i < (int)biomes.size(); i++) {
        const BiomeDef& b = biomes[i];
        bool valid = biome_matches(b, ch, sc);
        if (valid) {
            float s = biome_weighted_score(b, ch, sc, false);
            bool better = (best_valid_idx < 0) || (s > best_valid_score + SCORE_EPS)
                || (s >= best_valid_score - SCORE_EPS && b.priority > biomes[best_valid_idx].priority)
                || (s >= best_valid_score - SCORE_EPS && b.priority == biomes[best_valid_idx].priority
                    && String(b.id) < String(biomes[best_valid_idx].id));
            if (better) { best_valid_idx = i; best_valid_score = s; }
        }
        if (best_valid_idx < 0) {
            float fs = biome_weighted_score(b, ch, sc, true);
            bool fb_better = (best_fallback_idx < 0) || (fs > best_fallback_score + SCORE_EPS)
                || (fs >= best_fallback_score - SCORE_EPS && b.priority > biomes[best_fallback_idx].priority)
                || (fs >= best_fallback_score - SCORE_EPS && b.priority == biomes[best_fallback_idx].priority
                    && String(b.id) < String(biomes[best_fallback_idx].id));
            if (fb_better) { best_fallback_idx = i; best_fallback_score = fs; }
        }
    }
    int idx = best_valid_idx >= 0 ? best_valid_idx : best_fallback_idx;
    return idx >= 0 ? biomes[idx].palette_index : 0;
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
        const BiomeDef* biome) const {
    VariationResult vr;
    vr.kind = VAR_NONE; vr.score = 0.0f;
    vr.flora_mod = vr.wetness_mod = vr.rockiness_mod = vr.openness_mod = 0.0f;

    int cwx = wrap_x(wx, wrap_width);
    float ln = sample_noise_01(const_cast<FastNoiseLite&>(noise_field), cwx, wy);
    float pn = sample_noise_01(const_cast<FastNoiseLite&>(noise_patch), cwx, wy);
    float dn = sample_noise_01(const_cast<FastNoiseLite&>(noise_detail), cwx, wy);

    float fd = ch.flora_density, mo = ch.moisture, ru = ch.ruggedness;
    float rs = sc.ridge_strength, rv = sc.river_strength, fp = sc.floodplain_strength, mm = sc.mountain_mass;
    const std::vector<StringName>& tags = biome ? biome->tags : std::vector<StringName>();

    auto blend = [](float a, float b, float w) { return a * w + b * (1.0f - w); };
    auto norm = [](float v) { return clampf(v - 0.18f, 0.0f, 1.0f); };

    // Score 5 variation types (matches GDScript scoring functions)
    float scores[5];
    // sparse_flora
    { float bs = (1.0f-fd)*0.42f + (1.0f-mo)*0.18f + ru*0.12f + (1.0f-fp)*0.10f + (1.0f-rv)*0.08f + mm*0.10f;
      float ns = blend(band_score(ln,0.24f,0.24f), band_score(pn,0.34f,0.20f), 0.65f);
      StringName p[] = {StringName("dry"),StringName("upland"),StringName("mountain"),StringName("cold")};
      StringName n[] = {StringName("wet"),StringName("lowland")};
      scores[0] = norm(bs*0.74f + ns*0.18f + tag_bias(tags,p,4,n,2)); }
    // dense_flora
    { float bs = fd*0.42f + mo*0.24f + fp*0.12f + (1.0f-ru)*0.08f + (1.0f-rs)*0.08f + (1.0f-mm)*0.06f;
      float ns = blend(band_score(ln,0.78f,0.22f), band_score(dn,0.62f,0.20f), 0.70f);
      StringName p[] = {StringName("wet"),StringName("temperate"),StringName("baseline"),StringName("lowland")};
      StringName n[] = {StringName("dry"),StringName("mountain")};
      scores[1] = norm(bs*0.74f + ns*0.18f + tag_bias(tags,p,4,n,2)); }
    // clearing
    { float vg = clampf(fd*1.35f - 0.18f, 0.0f, 1.0f);
      float bs = fd*0.28f + mo*0.10f + (1.0f-ru)*0.18f + (1.0f-rs)*0.08f + (1.0f-rv)*0.06f;
      float ns = blend(band_score(ln,0.50f,0.16f), band_score(pn,0.48f,0.14f), 0.55f);
      StringName p[] = {StringName("temperate"),StringName("baseline"),StringName("wet")};
      StringName n[] = {StringName("mountain"),StringName("dry")};
      scores[2] = norm(vg * (bs*0.72f + ns*0.22f + tag_bias(tags,p,3,n,2))); }
    // rocky_patch
    { float bs = ru*0.38f + rs*0.22f + mm*0.18f + (1.0f-fd)*0.10f + (1.0f-mo)*0.06f + (1.0f-fp)*0.06f;
      float ns = blend(band_score(ln,0.86f,0.18f), band_score(dn,0.82f,0.18f), 0.65f);
      StringName p[] = {StringName("mountain"),StringName("highland"),StringName("upland")};
      StringName n[] = {StringName("wet"),StringName("lowland")};
      scores[3] = norm(bs*0.76f + ns*0.16f + tag_bias(tags,p,3,n,2)); }
    // wet_patch
    { float bs = mo*0.34f + fp*0.26f + rv*0.18f + (1.0f-ru)*0.08f + fd*0.06f + (1.0f-mm)*0.04f;
      float ns = blend(band_score(ln,0.12f,0.18f), band_score(pn,0.70f,0.20f), 0.70f);
      StringName p[] = {StringName("wet"),StringName("lowland"),StringName("temperate")};
      StringName n[] = {StringName("dry"),StringName("mountain"),StringName("highland")};
      scores[4] = norm(bs*0.76f + ns*0.16f + tag_bias(tags,p,3,n,3)); }

    // Best selection (matches GDScript kind order)
    constexpr float VAR_EPS = 0.00001f;
    VarKind kinds[] = { VAR_SPARSE_FLORA, VAR_DENSE_FLORA, VAR_CLEARING, VAR_ROCKY_PATCH, VAR_WET_PATCH };
    for (int i = 0; i < 5; i++) {
        if (scores[i] > vr.score + VAR_EPS) { vr.kind = kinds[i]; vr.score = scores[i]; }
    }
    if (vr.score < local_variation_min_score) { vr.kind = VAR_NONE; vr.score = 0.0f; }
    if (vr.kind == VAR_NONE) return vr;

    // Modulations (matches _apply_modulations)
    float in_ = vr.score;
    switch (vr.kind) {
        case VAR_SPARSE_FLORA:
            vr.flora_mod = -(0.16f + in_*0.34f);
            vr.wetness_mod = -(0.06f + in_*0.14f) + (0.04f - mo*0.04f);
            vr.rockiness_mod = 0.06f + in_*0.18f + ru*0.08f;
            vr.openness_mod = 0.16f + in_*0.34f;
            break;
        case VAR_DENSE_FLORA:
            vr.flora_mod = 0.18f + in_*0.38f;
            vr.wetness_mod = 0.06f + in_*0.16f + fp*0.08f;
            vr.rockiness_mod = -(0.04f + in_*0.16f);
            vr.openness_mod = -(0.10f + in_*0.30f);
            break;
        case VAR_CLEARING:
            vr.flora_mod = -(0.10f + in_*0.26f);
            vr.wetness_mod = -(0.02f + in_*0.08f);
            vr.rockiness_mod = -(0.04f + in_*0.08f);
            vr.openness_mod = 0.18f + in_*0.40f;
            break;
        case VAR_ROCKY_PATCH:
            vr.flora_mod = -(0.08f + in_*0.22f);
            vr.wetness_mod = -(0.04f + in_*0.14f);
            vr.rockiness_mod = 0.18f + in_*0.42f + rs*0.10f + ru*0.08f;
            vr.openness_mod = 0.06f + in_*0.16f;
            break;
        case VAR_WET_PATCH:
            vr.flora_mod = 0.04f + in_*0.16f;
            vr.wetness_mod = 0.18f + in_*0.40f + std::max(fp, rv)*0.10f;
            vr.rockiness_mod = -(0.06f + in_*0.12f);
            vr.openness_mod = -(0.04f + in_*0.12f);
            break;
        default: break;
    }
    return vr;
}

// ============================================================
// TerrainResolver (matches surface_terrain_resolver.gd)
// ============================================================

ChunkGenerator::TerrainType ChunkGenerator::resolve_terrain(
        float dist_sq, const Channels& ch, const StructureContext& sc,
        const VariationResult& vr) const {
    float safe_sq = (float)(safe_zone_radius * safe_zone_radius);
    float land_sq = (float)(land_guarantee_radius * land_guarantee_radius);

    // Safe zone
    if (dist_sq <= safe_sq) return GROUND;

    // River
    if (dist_sq > land_sq) {
        float wb = vr.wetness_mod, rb = vr.rockiness_mod;
        float eff_rv = sc.river_strength + wb * 0.10f - rb * 0.05f;
        if (eff_rv >= river_min_strength
            && sc.ridge_strength <= river_ridge_exclusion
            && ch.height <= river_max_height + wb * 0.05f) {
            return WATER;
        }
    }

    // River bank
    if (dist_sq > land_sq) {
        float wb = vr.wetness_mod;
        float eff_fp = sc.floodplain_strength + wb * 0.10f;
        float eff_rv = sc.river_strength + wb * 0.08f;
        // Not a river tile (already checked above)
        if (eff_fp >= bank_min_floodplain && sc.ridge_strength <= bank_ridge_exclusion) {
            if (eff_rv >= bank_min_river) return SAND;
            if (ch.moisture + wb * 0.10f > bank_min_moisture
                && ch.height - wb * 0.04f < bank_max_height) return SAND;
        }
    }

    // Mountain
    if (dist_sq > land_sq) {
        float terrain_gate = clampf(ch.height * 0.42f + ch.ruggedness * 1.08f - 0.16f, 0.22f, 1.0f);
        float ruggedness_gate = clampf(ch.ruggedness * 0.72f + ch.height * 0.28f, 0.0f, 1.0f);
        float rb = sc.ridge_strength * ridge_backbone_weight;
        float mf = sc.mountain_mass * massif_fill_weight;
        float cb = std::max(0.0f, sc.ridge_strength - 0.58f) * core_bonus_weight;
        float fs = ruggedness_gate * 0.10f + std::max(0.0f, sc.mountain_mass - 0.36f) * 0.10f;
        float rc = std::max(0.0f, sc.river_strength - 0.22f) * 0.20f + sc.floodplain_strength * 0.08f;
        float vs = vr.rockiness_mod * 0.08f - vr.wetness_mod * 0.04f - vr.openness_mod * 0.05f;
        float combined = (rb + mf + cb + fs - rc + vs) * terrain_gate;
        if (combined >= mountain_threshold_value) return ROCK;
    }

    return GROUND;
}

void ChunkGenerator::apply_polar_surface_modifiers(
        TerrainType terrain, const Channels& ch, const StructureContext& sc,
        int& io_variation_id, float& io_height, float& io_flora_density) const {
    if (terrain == ROCK) return;

    float cold_factor = resolve_cold_factor(ch.temperature);
    float hot_factor = resolve_hot_factor(ch.temperature);
    if (cold_factor <= 0.0f && hot_factor <= 0.0f) return;

    int overlay_id = io_variation_id;
    bool flat_surface = is_flat_polar_surface(ch);
    float evaporation_strength = hot_factor * std::max(0.0f, hot_evaporation_rate);

    if (terrain == WATER) {
        if (ch.temperature < prepass_frozen_river_threshold && cold_factor > 0.0f) {
            overlay_id = VAR_ICE;
        } else if (evaporation_strength >= 0.125f) {
            overlay_id = VAR_DRY_RIVERBED;
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

bool ChunkGenerator::is_flat_polar_surface(const Channels& ch) const {
    return ch.ruggedness <= 0.28f;
}

// ============================================================
// Flora computation (matches chunk_flora_builder.gd)
// ============================================================

float ChunkGenerator::tile_hash(int wx, int wy, int channel) const {
    // Must use 64-bit arithmetic to match GDScript int (which is 64-bit)
    int64_t h = (int64_t)seed * 374761393LL;
    h = h + (int64_t)wx * 668265263LL;
    h = h + (int64_t)wy * 2147483647LL;
    h = h + (int64_t)channel * 1013904223LL;
    h = (h ^ (h >> 13)) * 1274126177LL;
    h = h ^ (h >> 16);
    int64_t m = h % 100000LL;
    if (m < 0) m = -m;
    return (float)m * 0.00001f;
}

bool ChunkGenerator::flora_set_allowed_in_subzone(const FloraSetDef& fs, int var_id) const {
    // Map var_id to StringName for comparison
    static const StringName VAR_NAMES[] = {
        StringName("none"), StringName("sparse_flora"), StringName("dense_flora"),
        StringName("clearing"), StringName("rocky_patch"), StringName("wet_patch"),
        StringName("polar_ice"), StringName("polar_scorched"), StringName("polar_salt_flat"),
        StringName("polar_dry_riverbed")
    };
    constexpr int VAR_NAME_COUNT = sizeof(VAR_NAMES) / sizeof(VAR_NAMES[0]);
    StringName sz = (var_id >= 0 && var_id < VAR_NAME_COUNT) ? VAR_NAMES[var_id] : VAR_NAMES[0];
    if (!fs.excluded_subzones.empty()) {
        for (const auto& e : fs.excluded_subzones) { if (e == sz) return false; }
    }
    if (!fs.subzone_filters.empty()) {
        bool found = false;
        for (const auto& f : fs.subzone_filters) { if (f == sz) { found = true; break; } }
        if (!found) return false;
    }
    return true;
}

float ChunkGenerator::decor_set_subzone_density(const DecorSetDef& ds, int var_id) const {
    static const StringName VAR_NAMES[] = {
        StringName("none"), StringName("sparse_flora"), StringName("dense_flora"),
        StringName("clearing"), StringName("rocky_patch"), StringName("wet_patch"),
        StringName("polar_ice"), StringName("polar_scorched"), StringName("polar_salt_flat"),
        StringName("polar_dry_riverbed")
    };
    constexpr int VAR_NAME_COUNT = sizeof(VAR_NAMES) / sizeof(VAR_NAMES[0]);
    StringName sz = (var_id >= 0 && var_id < VAR_NAME_COUNT) ? VAR_NAMES[var_id] : VAR_NAMES[0];
    for (const auto& p : ds.subzone_density_modifiers) {
        if (p.first == sz) return ds.base_density * p.second;
    }
    return ds.base_density;
}

struct FloraZoneCache {
    std::vector<int> flora_indices;
    std::vector<int> decor_indices;
    std::vector<float> decor_densities;
};

Array ChunkGenerator::compute_flora_placements(int cs, int base_x, int base_y,
        const uint8_t* terrain_p, const uint8_t* biome_p, const uint8_t* variation_p,
        const float* flora_dens_p, const float* flora_mod_p) const {
    Array placements;
    std::unordered_map<int, FloraZoneCache> zone_cache;

    for (int ly = 0; ly < cs; ly++) {
        int wy = base_y + ly;
        for (int lx = 0; lx < cs; lx++) {
            int idx = ly * cs + lx;
            if (terrain_p[idx] != 0) continue; // GROUND only
            int biome_idx = biome_p[idx];
            int var_id = variation_p[idx];
            if (biome_idx >= (int)biome_flora_configs.size()) continue;
            int zone_key = biome_idx * 16 + var_id;

            auto it = zone_cache.find(zone_key);
            if (it == zone_cache.end()) {
                FloraZoneCache zc;
                const BiomeFloraConfig& bfc = biome_flora_configs[biome_idx];
                for (int fi : bfc.flora_set_indices) {
                    if (fi < (int)flora_sets.size() && flora_set_allowed_in_subzone(flora_sets[fi], var_id))
                        zc.flora_indices.push_back(fi);
                }
                for (int di : bfc.decor_set_indices) {
                    if (di < (int)decor_sets.size()) {
                        zc.decor_indices.push_back(di);
                        zc.decor_densities.push_back(decor_set_subzone_density(decor_sets[di], var_id));
                    }
                }
                it = zone_cache.insert({zone_key, zc}).first;
            }
            const FloraZoneCache& zc = it->second;
            int wx = base_x + lx;
            float h1 = tile_hash(wx, wy, 0);
            float h2 = tile_hash(wx, wy, 1);
            float h3 = tile_hash(wx, wy, 2);
            float fd = flora_dens_p[idx];
            float fm = flora_mod_p[idx];
            bool placed = false;

            // Try flora sets
            for (int fi : zc.flora_indices) {
                const FloraSetDef& fs = flora_sets[fi];
                float eff = fs.base_density * (1.0f + fd * fs.flora_channel_weight) * (1.0f + fm * fs.flora_modulation_weight);
                eff = clampf(eff, 0.0f, 0.6f);
                if (h1 >= eff) continue;
                // Pick entry (weighted by density threshold)
                float tw = 0.0f;
                int best_entry = -1;
                for (int ei = 0; ei < (int)fs.entries.size(); ei++) {
                    const FloraEntryDef& fe = fs.entries[ei];
                    if (fd >= fe.min_density_threshold && fd <= fe.max_density_threshold)
                        tw += fe.weight;
                }
                if (tw <= 0.0f) continue;
                float target = h2 * tw;
                float acc = 0.0f;
                for (int ei = 0; ei < (int)fs.entries.size(); ei++) {
                    const FloraEntryDef& fe = fs.entries[ei];
                    if (fd >= fe.min_density_threshold && fd <= fe.max_density_threshold) {
                        acc += fe.weight;
                        if (target <= acc) { best_entry = ei; break; }
                    }
                }
                if (best_entry < 0) best_entry = (int)fs.entries.size() - 1;
                const FloraEntryDef& chosen = fs.entries[best_entry];
                Dictionary p;
                p["local_pos"] = Vector2i(lx, ly);
                p["entry_id"] = chosen.id;
                p["is_flora"] = true;
                p["color"] = chosen.color;
                p["size"] = chosen.size;
                p["z_offset"] = chosen.z_offset;
                placements.append(p);
                placed = true;
                break;
            }
            if (placed) continue;

            // Try decor sets
            for (int di = 0; di < (int)zc.decor_indices.size(); di++) {
                float density = zc.decor_densities[di];
                if (h1 >= density) continue;
                const DecorSetDef& ds = decor_sets[zc.decor_indices[di]];
                if (ds.entries.empty()) continue;
                float tw = 0.0f;
                for (const auto& de : ds.entries) tw += de.weight;
                if (tw <= 0.0f) continue;
                float target = h3 * tw;
                float acc = 0.0f;
                int best = (int)ds.entries.size() - 1;
                for (int ei = 0; ei < (int)ds.entries.size(); ei++) {
                    acc += ds.entries[ei].weight;
                    if (target <= acc) { best = ei; break; }
                }
                const DecorEntryDef& chosen = ds.entries[best];
                Dictionary p;
                p["local_pos"] = Vector2i(lx, ly);
                p["entry_id"] = chosen.id;
                p["is_flora"] = false;
                p["color"] = chosen.color;
                p["size"] = chosen.size;
                p["z_offset"] = chosen.z_offset;
                placements.append(p);
                break;
            }
        }
    }
    return placements;
}

// ============================================================
// generate_chunk() — full pipeline
// ============================================================

Dictionary ChunkGenerator::generate_chunk(Vector2i chunk_coord, Vector2i spawn_tile) {
    if (!initialized) return Dictionary();

    int cs = chunk_size;
    int total = cs * cs;

    // Canonical chunk coord (wrap x)
    int canonical_cx = wrap_x(chunk_coord.x, wrap_width / std::max(cs, 1));
    int base_x = canonical_cx * cs;
    int base_y = chunk_coord.y * cs;

    // Output arrays
    PackedByteArray terrain;
    terrain.resize(total);
    PackedFloat32Array height_arr;
    height_arr.resize(total);
    PackedByteArray variation;
    variation.resize(total);
    PackedByteArray biome_arr;
    biome_arr.resize(total);
    PackedFloat32Array flora_density_values;
    flora_density_values.resize(total);
    PackedFloat32Array flora_modulation_values;
    flora_modulation_values.resize(total);

    // Distance from spawn helper
    float spawn_x = (float)spawn_tile.x;
    float spawn_y = (float)spawn_tile.y;

    // Full per-tile pipeline: channels → structure → biome → variation → terrain
    for (int ly = 0; ly < cs; ly++) {
        for (int lx = 0; lx < cs; lx++) {
            int wx = base_x + lx;
            int wy = base_y + ly;
            int idx = ly * cs + lx;

            // 1. Planet channels
            Channels ch = sample_channels(wx, wy);

            // 2. Structure context
            StructureContext sc = sample_structure(wx, wy, ch);

            // 3. Biome (returns palette_index)
            int biome_idx = resolve_biome(ch, sc);
            const BiomeDef* biome_ptr = nullptr;
            for (int bi = 0; bi < (int)biomes.size(); bi++) {
                if (biomes[bi].palette_index == biome_idx) { biome_ptr = &biomes[bi]; break; }
            }

            // 4. Local variation
            VariationResult vr = resolve_variation(wx, wy, ch, sc, biome_ptr);

            // 5. Terrain type
            float dx_s = (float)(wrap_x(wx, wrap_width) - wrap_x((int)spawn_x, wrap_width));
            // Handle wrap distance
            if (wrap_width > 0) {
                if (dx_s > wrap_width / 2) dx_s -= wrap_width;
                else if (dx_s < -wrap_width / 2) dx_s += wrap_width;
            }
            float dy_s = (float)(wy - (int)spawn_y);
            float dist_sq = dx_s * dx_s + dy_s * dy_s;
            TerrainType tt = resolve_terrain(dist_sq, ch, sc, vr);
            int variation_id = (int)vr.kind;
            float height_value = ch.height;
            float flora_density_value = ch.flora_density;
            apply_polar_surface_modifiers(tt, ch, sc, variation_id, height_value, flora_density_value);

            // Pack output
            terrain[idx] = (uint8_t)tt;
            height_arr[idx] = height_value;
            variation[idx] = (uint8_t)variation_id;
            biome_arr[idx] = (uint8_t)biome_idx;
            flora_density_values[idx] = flora_density_value;
            flora_modulation_values[idx] = vr.flora_mod;
        }
    }

    // Flora computation pass
    Array flora_placements = compute_flora_placements(
        cs, base_x, base_y,
        terrain.ptr(), biome_arr.ptr(), variation.ptr(),
        flora_density_values.ptr(), flora_modulation_values.ptr()
    );

    Dictionary result;
    result["chunk_coord"] = chunk_coord;
    result["canonical_chunk_coord"] = Vector2i(canonical_cx, chunk_coord.y);
    result["base_tile"] = Vector2i(base_x, base_y);
    result["chunk_size"] = cs;
    result["terrain"] = terrain;
    result["height"] = height_arr;
    result["variation"] = variation;
    result["biome"] = biome_arr;
    result["flora_density_values"] = flora_density_values;
    result["flora_modulation_values"] = flora_modulation_values;
    result["flora_placements"] = flora_placements;
    return result;
}
