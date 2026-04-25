#ifndef STATION_MIRNY_LAKE_FOOTPRINT_H
#define STATION_MIRNY_LAKE_FOOTPRINT_H

#include <cstdint>

#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace lake_footprint {

constexpr uint8_t CLASS_NONE = 0U;
constexpr uint8_t CLASS_SHALLOW = 1U;
constexpr uint8_t CLASS_DEEP = 2U;

struct LakeShape {
	double center_x_tiles = 0.0;
	double center_y_tiles = 0.0;
	float shallow_radius_tiles = 0.0f;
	float deep_radius_tiles = 0.0f;
	uint64_t shape_signature = 0;
};

LakeShape make_shape(
	double p_center_x_tiles,
	double p_center_y_tiles,
	float p_flow_accumulation,
	float p_valley,
	uint64_t p_shape_signature,
	float p_lake_radius_scale
);

uint8_t classify_tile(const LakeShape &p_shape, double p_world_x, double p_world_y, int64_t p_width_tiles);

godot::PackedVector2Array build_polygon(const LakeShape &p_shape, int64_t p_width_tiles);

} // namespace lake_footprint

#endif
