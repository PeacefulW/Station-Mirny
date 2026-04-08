#ifndef CHUNK_GENERATOR_H
#define CHUNK_GENERATOR_H

#include <vector>
#include <unordered_map>
#include <cmath>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include "FastNoiseLite.h"

namespace godot {

// --- Per-biome definition passed from GDScript ---
struct BiomeDef {
    StringName id;
    int priority = 0;
    int palette_index = 0;
    // Channel ranges
    float min_height = 0.0f, max_height = 1.0f;
    float min_temperature = 0.0f, max_temperature = 1.0f;
    float min_moisture = 0.0f, max_moisture = 1.0f;
    float min_ruggedness = 0.0f, max_ruggedness = 1.0f;
    float min_flora_density = 0.0f, max_flora_density = 1.0f;
    float min_latitude = -1.0f, max_latitude = 1.0f;
    float min_drainage = 0.0f, max_drainage = 1.0f;
    float min_slope = 0.0f, max_slope = 1.0f;
    float min_rain_shadow = 0.0f, max_rain_shadow = 1.0f;
    float min_continentalness = 0.0f, max_continentalness = 1.0f;
    // Structure ranges
    float min_ridge_strength = 0.0f, max_ridge_strength = 1.0f;
    float min_river_strength = 0.0f, max_river_strength = 1.0f;
    float min_floodplain_strength = 0.0f, max_floodplain_strength = 1.0f;
    // Channel weights
    float height_weight = 1.0f;
    float temperature_weight = 1.0f;
    float moisture_weight = 1.0f;
    float ruggedness_weight = 1.0f;
    float flora_density_weight = 0.6f;
    float latitude_weight = 0.6f;
    float drainage_weight = 0.0f;
    float slope_weight = 0.0f;
    float rain_shadow_weight = 0.0f;
    float continentalness_weight = 0.0f;
    // Structure weights
    float ridge_strength_weight = 1.0f;
    float river_strength_weight = 1.0f;
    float floodplain_strength_weight = 1.0f;
    // Tags (stored as flat list for C++ scoring)
    std::vector<StringName> tags;
};

struct BiomePrePassSample {
    float drainage = 0.0f;
    float slope = 0.0f;
    float rain_shadow = 0.0f;
    float continentalness = 0.0f;
    float ridge_strength = 0.0f;
    float river_width = 0.0f;
    float river_distance = 0.0f;
    float floodplain_strength = 0.0f;
    float mountain_mass = 0.0f;
};

class ChunkGenerator : public RefCounted {
    GDCLASS(ChunkGenerator, RefCounted)

public:
    ChunkGenerator();
    ~ChunkGenerator();

    void initialize(int p_seed, Dictionary p_params);
    Dictionary generate_chunk(Vector2i chunk_coord, Vector2i spawn_tile);
    /// Fast single-tile sample: returns {terrain: int, biome: int}. No array allocations.
    Dictionary sample_tile(Vector2i world_pos, Vector2i spawn_tile);

protected:
    static void _bind_methods();

private:
    int seed = 0;
    int chunk_size = 64;
    int wrap_width = 4096;
    bool initialized = false;

    // --- Planet sampler params ---
    int equator_tile_y = 0;
    int latitude_half_span_tiles = 4096;
    float temperature_noise_amplitude = 0.18f;
    float temperature_latitude_weight = 0.72f;
    float latitude_temperature_curve = 1.35f;

    // --- Structure sampler params ---
    float mountain_density = 0.3f;
    float mountain_chaininess = 0.6f;
    float ridge_spacing_tiles = 640.0f;
    float ridge_core_width_tiles = 104.0f;
    float ridge_feather_tiles = 224.0f;
    float ridge_warp_amplitude_tiles = 260.0f;
    float ridge_secondary_warp_frequency = 0.0014f;
    float ridge_secondary_warp_amplitude_tiles = 0.0f;
    float ridge_secondary_spacing_tiles = 0.0f;
    float ridge_secondary_core_width_tiles = 0.0f;
    float ridge_secondary_feather_tiles = 0.0f;
    float ridge_secondary_weight = 0.0f;
    float river_spacing_tiles = 480.0f;
    float river_core_width_tiles = 42.0f;
    float river_floodplain_width_tiles = 224.0f;
    float river_warp_amplitude_tiles = 300.0f;

    // --- Terrain resolver params ---
    int safe_zone_radius = 12;
    int land_guarantee_radius = 24;
    float mountain_base_threshold = 0.74f;
    float river_min_strength = 0.40f;
    float river_ridge_exclusion = 0.70f;
    float river_max_height = 0.74f;
    float bank_min_floodplain = 0.32f;
    float bank_ridge_exclusion = 0.64f;
    float bank_min_river = 0.16f;
    float bank_min_moisture = 0.54f;
    float bank_max_height = 0.60f;
    float prepass_frozen_river_threshold = 0.18f;
    float cold_pole_temperature = 0.20f;
    float cold_pole_transition_width = 0.12f;
    float ice_cap_height_bonus = 0.10f;
    float ice_cap_max_height = 0.55f;
    float hot_pole_temperature = 0.82f;
    float hot_pole_transition_width = 0.15f;
    float hot_evaporation_rate = 0.25f;
    float biome_continental_drying_factor = 0.35f;
    float biome_drainage_moisture_bonus = 0.28f;
    // Pre-computed from balance
    float mountain_threshold_value = 0.0f;
    float ridge_backbone_weight = 0.76f;
    float massif_fill_weight = 0.30f;
    float core_bonus_weight = 0.16f;

    // --- Pre-pass-backed biome sampling params ---
    int prepass_grid_width = 0;
    int prepass_grid_height = 0;
    int prepass_min_y = 0;
    int prepass_max_y = 0;
    float prepass_grid_span_x = 1.0f;
    float prepass_grid_span_y = 1.0f;
    bool has_biome_prepass = false;
    PackedFloat32Array prepass_drainage_grid;
    PackedFloat32Array prepass_slope_grid;
    PackedFloat32Array prepass_rain_shadow_grid;
    PackedFloat32Array prepass_continentalness_grid;
    PackedFloat32Array prepass_ridge_strength_grid;
    PackedFloat32Array prepass_river_width_grid;
    PackedFloat32Array prepass_river_distance_grid;
    PackedFloat32Array prepass_floodplain_strength_grid;
    PackedFloat32Array prepass_mountain_mass_grid;

    // --- Local variation params ---
    float local_variation_min_score = 0.22f;

    // --- 12 noise instances (spec table) ---
    FastNoiseLite noise_height;           // +11
    FastNoiseLite noise_temperature;      // +101
    FastNoiseLite noise_moisture;         // +131
    FastNoiseLite noise_ruggedness;       // +151
    FastNoiseLite noise_flora_density;    // +181
    FastNoiseLite noise_ridge_warp;       // +211
    FastNoiseLite noise_ridge_secondary_warp; // +217
    FastNoiseLite noise_ridge_cluster;    // +223
    FastNoiseLite noise_river_warp;       // +241
    FastNoiseLite noise_field;            // +311
    FastNoiseLite noise_patch;            // +353
    FastNoiseLite noise_detail;           // +389

    // --- Biome definitions ---
    std::vector<BiomeDef> biomes; // sorted by priority desc, then id asc

    // --- Flora entry (for weighted selection) ---
    struct FloraEntryDef {
        StringName id;
        Color color;
        Vector2i size;
        int z_offset = 0;
        float weight = 1.0f;
        float min_density_threshold = 0.0f;
        float max_density_threshold = 1.0f;
    };
    struct DecorEntryDef {
        StringName id;
        Color color;
        Vector2i size;
        int z_offset = -1;
        float weight = 1.0f;
    };
    struct FloraSetDef {
        StringName id;
        float base_density = 0.10f;
        float flora_channel_weight = 1.0f;
        float flora_modulation_weight = 0.5f;
        std::vector<StringName> subzone_filters;
        std::vector<StringName> excluded_subzones;
        std::vector<FloraEntryDef> entries;
        // Pre-computed cumulative weights for each entry (optimization)
    };
    struct DecorSetDef {
        StringName id;
        float base_density = 0.06f;
        std::vector<DecorEntryDef> entries;
        // subzone_kind → density modifier
        std::vector<std::pair<StringName, float>> subzone_density_modifiers;
    };
    // Per-biome flora/decor set indices
    struct BiomeFloraConfig {
        std::vector<int> flora_set_indices; // into flora_sets
        std::vector<int> decor_set_indices; // into decor_sets
    };
    std::vector<FloraSetDef> flora_sets;
    std::vector<DecorSetDef> decor_sets;
    std::vector<BiomeFloraConfig> biome_flora_configs; // parallel to biomes

    // --- Terrain types (matches TileGenData.TerrainType) ---
    enum TerrainType { GROUND = 0, ROCK = 1, WATER = 2, SAND = 3 };
    // --- Variation kinds ---
    enum VarKind { VAR_NONE = 0, VAR_SPARSE_FLORA = 1, VAR_DENSE_FLORA = 2,
                   VAR_CLEARING = 3, VAR_ROCKY_PATCH = 4, VAR_WET_PATCH = 5,
                   VAR_ICE = 6, VAR_SCORCHED = 7, VAR_SALT_FLAT = 8, VAR_DRY_RIVERBED = 9 };

    // --- Per-tile intermediate data ---
    struct Channels {
        float latitude, height, temperature, moisture, ruggedness, flora_density;
    };
    struct StructureContext {
        float mountain_mass, ridge_strength, river_strength, floodplain_strength;
    };
    struct VariationResult {
        VarKind kind;
        float score;
        float flora_mod, wetness_mod, rockiness_mod, openness_mod;
    };

    // --- Noise helpers ---
    static constexpr float FRACTAL_GAIN = 0.55f;
    static constexpr float FRACTAL_LACUNARITY = 2.1f;
    static constexpr float TAU_F = 6.283185307179586f;

    // Direction vectors for structure sampling (normalized at init)
    float ridge_dir[3];
    float ridge_secondary_dir[3];
    float river_dir[3];

    void setup_noise(FastNoiseLite& n, int s, float freq, int octaves);
    float sample_noise_01(FastNoiseLite& n, int world_x, int world_y) const;
    float sample_noise_signed(FastNoiseLite& n, int world_x, int world_y) const;

    // Planet sampler
    Channels sample_channels(int wx, int wy) const;
    // Structure sampler
    StructureContext sample_structure(int wx, int wy, const Channels& ch) const;

    // Structure helpers
    float directed_coordinate(int wx, int wy, const float dir[3]) const;
    static float repeating_band(float coord, float spacing, float core_half_width, float feather_width);

    // Biome resolver
    int resolve_biome(int wx, int wy, const Channels& ch, const StructureContext& fallback_sc) const;
    static float score_range(float value, float min_v, float max_v, bool soft);
    float biome_weighted_score(
        const BiomeDef& b,
        const Channels& ch,
        const StructureContext& sc,
        const BiomePrePassSample* prepass,
        float effective_moisture,
        bool soft
    ) const;
    bool biome_matches(
        const BiomeDef& b,
        const Channels& ch,
        const StructureContext& sc,
        const BiomePrePassSample* prepass
    ) const;
    float sample_prepass_grid(const PackedFloat32Array& grid, int world_x, int world_y) const;
    BiomePrePassSample sample_biome_prepass(int wx, int wy) const;
    float derive_river_strength_from_prepass(float river_width, float river_distance) const;
    bool biome_uses_causal_moisture(const BiomeDef& b) const;
    bool matches_weighted_range(float value, float min_v, float max_v, float weight) const;
    bool is_better_biome_candidate(float score, const BiomeDef& biome, int incumbent_idx, float incumbent_score) const;

    // Variation resolver
    VariationResult resolve_variation(int wx, int wy, const Channels& ch,
                                      const StructureContext& sc, const BiomeDef* biome) const;
    static float band_score(float value, float center, float half_width);
    static float tag_bias(const std::vector<StringName>& tags,
                          const StringName* pos, int pos_count,
                          const StringName* neg, int neg_count);

    // Terrain resolver
    TerrainType resolve_terrain(float dist_sq, const Channels& ch, const StructureContext& sc,
                                const VariationResult& var_r) const;
    void apply_polar_surface_modifiers(TerrainType terrain, const Channels& ch, const StructureContext& sc,
                                       int& io_variation_id, float& io_height, float& io_flora_density) const;
    float resolve_cold_factor(float temperature) const;
    float resolve_hot_factor(float temperature) const;
    bool is_flat_polar_surface(const Channels& ch) const;

    // Flora computation
    Array compute_flora_placements(int cs, int base_x, int base_y,
        const uint8_t* terrain, const uint8_t* biome_arr, const uint8_t* variation,
        const float* flora_density, const float* flora_mod) const;
    float tile_hash(int wx, int wy, int channel) const;
    bool flora_set_allowed_in_subzone(const FloraSetDef& fs, int var_id) const;
    float decor_set_subzone_density(const DecorSetDef& ds, int var_id) const;

    // Math
    static float clampf(float v, float lo, float hi);
    static float lerpf(float a, float b, float t);
    static float smoothstep(float t);
    static int wrap_x(int world_x, int w);
    static void normalize_vec3(const float in[3], float out[3]);
};

} // namespace godot

#endif // CHUNK_GENERATOR_H
