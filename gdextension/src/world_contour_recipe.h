#ifndef STATION_MIRNY_WORLD_CONTOUR_RECIPE_H
#define STATION_MIRNY_WORLD_CONTOUR_RECIPE_H

#include <cstdint>

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace world_contour_recipe {

struct ContourRecipeV1 {
	godot::String schema;
	godot::String asset_name;
	godot::String preset;
	godot::String solid_class;
	godot::StringName recipe_id;

	int32_t tile_size_px = 64;
	int32_t chunk_size_tiles = 16;

	float south_height_px = 0.0f;
	float north_height_px = 0.0f;
	float side_height_px = 0.0f;
	float roughness_px = 0.0f;
	float edge_width_px = 0.0f;
	float face_power = 1.0f;
	float back_drop = 0.0f;
	float crown_bevel_px = 0.0f;
	float outer_corner_radius_px = 0.0f;
	float inner_corner_radius_px = 0.0f;
	float corner_round_px = 0.0f;
	float diagonal_smooth_px = 0.0f;
	float contour_relax = 0.0f;
	float contour_warp_px = 0.0f;
	float corner_variation = 0.0f;
	float rim_width_px = 0.0f;
	bool outline_enabled = false;
	float outline_width_px = 0.0f;
	float edge_debris = 0.0f;
	float edge_color_strength = 0.0f;
	float geometry_variance = 0.0f;
	int32_t shape_supersampling = 1;

	godot::String top_albedo;
	godot::String face_albedo;
	godot::String base_albedo;
	godot::String top_modulation;
	godot::String face_modulation;
	godot::String top_normal;
	godot::String face_normal;
	float texture_scale = 1.0f;
	float normal_strength = 1.0f;
	float normal_detail_strength = 0.0f;

	float collision_threshold = 0.0f;
	float collision_threshold_px = 0.0f;
	int32_t collision_sampling_px = 4;
	bool collision_blocks_inside = true;

	uint32_t seed = 0U;
	int32_t variant_count = 1;
	int32_t forced_variant = 0;

	bool valid = false;
	godot::String error;
};

ContourRecipeV1 parse_recipe_v1(const godot::Dictionary &p_recipe, godot::StringName p_recipe_id);

} // namespace world_contour_recipe

#endif
