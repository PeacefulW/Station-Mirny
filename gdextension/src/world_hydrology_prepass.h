#ifndef STATION_MIRNY_WORLD_HYDROLOGY_PREPASS_H
#define STATION_MIRNY_WORLD_HYDROLOGY_PREPASS_H

#include "world_prepass.h"

#include <cstdint>
#include <memory>
#include <vector>

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace world_hydrology_prepass {

constexpr int32_t DEFAULT_CELL_SIZE_TILES = 16;
constexpr uint8_t FLOW_DIR_TERMINAL = 255U;

struct RiverSettings {
	bool enabled = true;
	int32_t target_trunk_count = 0;
	float density = 0.55f;
	float width_scale = 1.0f;
	float lake_chance = 0.22f;
	float meander_strength = 0.65f;
	float braid_chance = 0.18f;
	float shallow_crossing_frequency = 0.22f;
	int32_t mountain_clearance_tiles = 3;
	float delta_scale = 1.0f;
	float north_drainage_bias = 0.75f;
	int32_t hydrology_cell_size_tiles = DEFAULT_CELL_SIZE_TILES;
};

struct Snapshot {
	bool valid = false;
	uint64_t signature = 0;
	double compute_time_ms = 0.0;
	int64_t seed = 0;
	int64_t world_version = 0;
	int32_t grid_width = 0;
	int32_t grid_height = 0;
	int32_t cell_size_tiles = DEFAULT_CELL_SIZE_TILES;
	int64_t width_tiles = 0;
	int64_t height_tiles = 0;
	int64_t ocean_band_tiles = 0;

	std::vector<float> hydro_elevation;
	std::vector<float> filled_elevation;
	std::vector<uint8_t> flow_dir;
	std::vector<float> flow_accumulation;
	std::vector<int32_t> watershed_id;
	std::vector<int32_t> lake_id;
	std::vector<uint8_t> ocean_sink_mask;
	std::vector<uint8_t> mountain_exclusion_mask;
	std::vector<float> floodplain_potential;
	int32_t river_segment_count = 0;
	int32_t river_source_count = 0;
	std::vector<uint8_t> river_node_mask;
	std::vector<int32_t> river_segment_id;
	std::vector<uint8_t> river_stream_order;
	std::vector<float> river_discharge;
	std::vector<int32_t> river_segment_ranges;
	std::vector<int32_t> river_path_node_indices;

	int32_t index(int32_t p_x, int32_t p_y) const;
	godot::Vector2i node_to_tile_center(int32_t p_x, int32_t p_y) const;
};

uint64_t make_signature(
	int64_t p_seed,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings,
	const RiverSettings &p_river_settings
);

std::unique_ptr<Snapshot> build_snapshot(
	int64_t p_seed,
	int64_t p_world_version,
	const world_prepass::Snapshot &p_foundation_snapshot,
	const FoundationSettings &p_foundation_settings,
	const RiverSettings &p_river_settings
);

godot::Dictionary make_build_result(const Snapshot &p_snapshot, bool p_cache_hit);
godot::Dictionary make_debug_snapshot(const Snapshot &p_snapshot, int64_t p_layer_mask, int64_t p_downscale_factor);
godot::Ref<godot::Image> make_overview_image(const Snapshot &p_snapshot, int64_t p_layer_mask, int64_t p_pixels_per_cell);

} // namespace world_hydrology_prepass

#endif
