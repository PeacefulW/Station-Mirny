#ifndef STATION_MIRNY_WORLD_PREPASS_H
#define STATION_MIRNY_WORLD_PREPASS_H

#include "mountain_field.h"

#include <cstdint>
#include <memory>
#include <vector>

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

struct FoundationSettings {
	bool enabled = false;
	int64_t width_tiles = 65536;
	int64_t height_tiles = 0;
	int64_t ocean_band_tiles = 0;
	int64_t burning_band_tiles = 0;
	int64_t pole_orientation = 0;
	float slope_bias = 0.0f;
};

namespace world_prepass {

constexpr int32_t COARSE_CELL_SIZE_TILES = 64;

struct Snapshot {
	bool valid = false;
	uint64_t signature = 0;
	double compute_time_ms = 0.0;
	int64_t seed = 0;
	int64_t world_version = 0;
	int32_t grid_width = 0;
	int32_t grid_height = 0;
	int64_t width_tiles = 0;
	int64_t height_tiles = 0;
	int64_t ocean_band_tiles = 0;
	int64_t burning_band_tiles = 0;

	std::vector<float> latitude_t;
	std::vector<uint8_t> ocean_band_mask;
	std::vector<uint8_t> burning_band_mask;
	std::vector<uint8_t> continent_mask;
	std::vector<float> foundation_height;
	std::vector<float> coarse_wall_density;
	std::vector<float> coarse_foot_density;
	std::vector<float> coarse_valley_score;
	std::vector<int32_t> biome_region_id;

	int32_t index(int32_t p_x, int32_t p_y) const;
	godot::Vector2i node_to_tile_center(int32_t p_x, int32_t p_y) const;
};

uint64_t make_signature(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Settings &p_mountain_settings,
	const FoundationSettings &p_foundation_settings
);

std::unique_ptr<Snapshot> build_snapshot(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_mountain_settings,
	const FoundationSettings &p_foundation_settings
);

godot::Dictionary make_debug_snapshot(const Snapshot &p_snapshot, int64_t p_layer_mask, int64_t p_downscale_factor);
godot::Ref<godot::Image> make_overview_image(
	const Snapshot &p_snapshot,
	const mountain_field::Evaluator &p_mountain_evaluator,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings,
	int64_t p_layer_mask,
	int64_t p_pixels_per_cell
);
godot::Dictionary resolve_spawn_tile(const Snapshot &p_snapshot);

} // namespace world_prepass

#endif
