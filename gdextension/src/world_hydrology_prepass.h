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

struct RefinedRiverEdge {
	float ax = 0.0f;
	float ay = 0.0f;
	float bx = 0.0f;
	float by = 0.0f;
	int32_t segment_id = 0;
	uint8_t stream_order = 0U;
	uint8_t flow_dir = FLOW_DIR_TERMINAL;
	float radius_scale = 1.0f;
	float curvature = 0.0f;
	float confluence_weight = 0.0f;
	float braid_loop_weight = 0.0f;
	float cumulative_start = 0.0f;
	float cumulative_end = 0.0f;
	float total_distance = 0.0f;
	float distance_at_source = 0.0f;
	float distance_to_terminal = 0.0f;
	uint64_t variation_seed = 0ULL;
	bool source = false;
	bool delta = false;
	bool braid_split = false;
	bool braid_loop = false;
	bool confluence = false;
	bool organic = false;
	bool shape_quality_v2_fix = false;
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
	RiverSettings river_settings;

	std::vector<float> hydro_elevation;
	std::vector<float> filled_elevation;
	std::vector<uint8_t> flow_dir;
	std::vector<float> flow_accumulation;
	std::vector<int32_t> watershed_id;
	std::vector<int32_t> lake_id;
	std::vector<float> lake_depth_ratio;
	std::vector<uint8_t> lake_spill_node_mask;
	std::vector<int32_t> lake_outlet_node_by_id;
	std::vector<float> lake_water_level_per_id;
	std::vector<uint8_t> oxbow_lake_node_mask;
	std::vector<uint8_t> ocean_sink_mask;
	std::vector<float> ocean_coast_distance_tiles;
	std::vector<float> ocean_shelf_depth_ratio;
	std::vector<float> ocean_river_mouth_influence;
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
	std::vector<RefinedRiverEdge> refined_river_edges;
	int32_t refined_river_curved_edge_count = 0;
	int32_t refined_river_confluence_edge_count = 0;
	int32_t refined_river_y_confluence_zone_count = 0;
	int32_t refined_river_y_confluence_edge_count = 0;
	int32_t refined_river_braid_loop_candidate_count = 0;
	int32_t refined_river_braid_loop_edge_count = 0;
	int32_t basin_contour_lake_node_count = 0;
	int32_t lake_spill_point_count = 0;
	int32_t lake_outlet_connection_count = 0;
	int32_t oxbow_candidate_count = 0;
	int32_t oxbow_lake_node_count = 0;
	int32_t ocean_coastline_node_count = 0;
	int32_t ocean_shallow_shelf_node_count = 0;
	int32_t ocean_river_mouth_node_count = 0;
	int32_t river_spatial_index_cell_size_tiles = 64;
	int32_t river_spatial_index_width = 0;
	int32_t river_spatial_index_height = 0;
	std::vector<int32_t> river_spatial_index_offsets;
	std::vector<int32_t> river_spatial_index_edge_indices;

	int32_t index(int32_t p_x, int32_t p_y) const;
	godot::Vector2i node_to_tile_center(int32_t p_x, int32_t p_y) const;
};

uint64_t make_signature(
	int64_t p_seed,
	int64_t p_world_version,
	uint64_t p_foundation_signature,
	const FoundationSettings &p_foundation_settings,
	const RiverSettings &p_river_settings
);

std::unique_ptr<Snapshot> build_snapshot(
	int64_t p_seed,
	int64_t p_world_version,
	const world_prepass::Snapshot &p_foundation_snapshot,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const FoundationSettings &p_foundation_settings,
	const RiverSettings &p_river_settings
);

godot::Dictionary make_build_result(const Snapshot &p_snapshot, bool p_cache_hit);
godot::Dictionary make_debug_snapshot(const Snapshot &p_snapshot, int64_t p_layer_mask, int64_t p_downscale_factor);
godot::Ref<godot::Image> make_overview_image(const Snapshot &p_snapshot, int64_t p_layer_mask, int64_t p_pixels_per_cell);
std::vector<RefinedRiverEdge> query_refined_river_edges(
	const Snapshot &p_snapshot,
	int64_t p_min_x,
	int64_t p_min_y,
	int64_t p_max_x,
	int64_t p_max_y,
	float p_padding_tiles
);

} // namespace world_hydrology_prepass

#endif
