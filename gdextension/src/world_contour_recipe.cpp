#include "world_contour_recipe.h"

#include <algorithm>

#include <godot_cpp/variant/variant.hpp>

namespace world_contour_recipe {
namespace {

constexpr const char *RUNTIME_SDF_RECIPE_SCHEMA = "station_peaceful.runtime_sdf_contour_recipe.v1";

float dict_float(const godot::Dictionary &p_dict, const char *p_key, float p_default) {
	return static_cast<float>(p_dict.get(p_key, p_default));
}

int32_t dict_int(const godot::Dictionary &p_dict, const char *p_key, int32_t p_default) {
	return static_cast<int32_t>(static_cast<int64_t>(p_dict.get(p_key, p_default)));
}

bool dict_bool(const godot::Dictionary &p_dict, const char *p_key, bool p_default) {
	return static_cast<bool>(p_dict.get(p_key, p_default));
}

godot::String dict_string(const godot::Dictionary &p_dict, const char *p_key, const godot::String &p_default = godot::String()) {
	return static_cast<godot::String>(p_dict.get(p_key, p_default));
}

godot::Dictionary dict_subdict(const godot::Dictionary &p_dict, const char *p_key) {
	const godot::Variant value = p_dict.get(p_key, godot::Dictionary());
	if (value.get_type() == godot::Variant::DICTIONARY) {
		return static_cast<godot::Dictionary>(value);
	}
	return godot::Dictionary();
}

void fail(ContourRecipeV1 &r_recipe, const godot::String &p_error) {
	r_recipe.valid = false;
	r_recipe.error = p_error;
}

} // namespace

ContourRecipeV1 parse_recipe_v1(const godot::Dictionary &p_recipe, godot::StringName p_recipe_id) {
	ContourRecipeV1 recipe;
	if (p_recipe.is_empty()) {
		fail(recipe, "ContourRecipeV1 recipe dictionary is empty.");
		return recipe;
	}

	recipe.schema = dict_string(p_recipe, "schema");
	if (recipe.schema != RUNTIME_SDF_RECIPE_SCHEMA) {
		fail(recipe, "ContourRecipeV1 schema is not station_peaceful.runtime_sdf_contour_recipe.v1.");
		return recipe;
	}

	recipe.asset_name = dict_string(p_recipe, "asset_name");
	recipe.preset = dict_string(p_recipe, "preset");
	recipe.solid_class = dict_string(p_recipe, "solid_class");
	recipe.recipe_id = p_recipe_id == godot::StringName() ?
			godot::StringName(recipe.asset_name) :
			p_recipe_id;
	recipe.tile_size_px = std::max(1, dict_int(p_recipe, "tile_size_px", 64));
	recipe.chunk_size_tiles = std::max(1, dict_int(p_recipe, "chunk_size_tiles", 16));

	const godot::Dictionary geometry = dict_subdict(p_recipe, "geometry");
	recipe.south_height_px = std::max(0.0f, dict_float(geometry, "south_height_px", 0.0f));
	recipe.north_height_px = std::max(0.0f, dict_float(geometry, "north_height_px", 0.0f));
	recipe.side_height_px = std::max(0.0f, dict_float(geometry, "side_height_px", 0.0f));
	recipe.roughness_px = std::max(0.0f, dict_float(geometry, "roughness_px", 0.0f));
	recipe.edge_width_px = std::max(0.0f, dict_float(geometry, "edge_width_px", 0.0f));
	recipe.face_power = std::max(0.01f, dict_float(geometry, "face_power", 1.0f));
	recipe.back_drop = std::max(0.0f, dict_float(geometry, "back_drop", 0.0f));
	recipe.crown_bevel_px = std::max(0.0f, dict_float(geometry, "crown_bevel_px", 0.0f));
	recipe.outer_corner_radius_px = std::max(0.0f, dict_float(geometry, "outer_corner_radius_px", 0.0f));
	recipe.inner_corner_radius_px = std::max(0.0f, dict_float(geometry, "inner_corner_radius_px", 0.0f));
	recipe.corner_round_px = std::max(0.0f, dict_float(geometry, "corner_round_px", 0.0f));
	recipe.diagonal_smooth_px = std::max(0.0f, dict_float(geometry, "diagonal_smooth_px", 0.0f));
	recipe.contour_relax = dict_float(geometry, "contour_relax", 0.0f);
	recipe.contour_warp_px = std::max(0.0f, dict_float(geometry, "contour_warp_px", 0.0f));
	recipe.corner_variation = std::max(0.0f, dict_float(geometry, "corner_variation", 0.0f));
	recipe.rim_width_px = std::max(0.0f, dict_float(geometry, "rim_width_px", 0.0f));
	recipe.outline_enabled = dict_bool(geometry, "outline_enabled", false);
	recipe.outline_width_px = std::max(0.0f, dict_float(geometry, "outline_width_px", 0.0f));
	recipe.edge_debris = std::max(0.0f, dict_float(geometry, "edge_debris", 0.0f));
	recipe.edge_color_strength = std::max(0.0f, dict_float(geometry, "edge_color_strength", 0.0f));
	recipe.geometry_variance = std::max(0.0f, dict_float(geometry, "geometry_variance", 0.0f));
	recipe.shape_supersampling = std::max(1, dict_int(geometry, "shape_supersampling", 1));

	const godot::Dictionary materials = dict_subdict(p_recipe, "materials");
	recipe.top_albedo = dict_string(materials, "top_albedo");
	recipe.face_albedo = dict_string(materials, "face_albedo");
	recipe.base_albedo = dict_string(materials, "base_albedo");
	recipe.top_modulation = dict_string(materials, "top_modulation");
	recipe.face_modulation = dict_string(materials, "face_modulation");
	recipe.top_normal = dict_string(materials, "top_normal");
	recipe.face_normal = dict_string(materials, "face_normal");
	recipe.texture_scale = std::max(0.0001f, dict_float(materials, "texture_scale", 1.0f));
	recipe.normal_strength = std::max(0.0f, dict_float(materials, "normal_strength", 1.0f));
	recipe.normal_detail_strength = std::max(0.0f, dict_float(materials, "normal_detail_strength", 0.0f));

	const godot::Dictionary collision = dict_subdict(p_recipe, "collision");
	recipe.collision_threshold = dict_float(collision, "threshold", 0.0f);
	recipe.collision_threshold_px = dict_float(collision, "threshold_px", 0.0f);
	recipe.collision_sampling_px = std::max(1, dict_int(collision, "sampling_px", 4));
	recipe.collision_blocks_inside = dict_bool(collision, "blocks_inside", true);

	const godot::Dictionary determinism = dict_subdict(p_recipe, "determinism");
	recipe.seed = static_cast<uint32_t>(std::max<int64_t>(0, static_cast<int64_t>(determinism.get("seed", 0))));
	recipe.variant_count = std::max(1, dict_int(determinism, "variant_count", 1));
	recipe.forced_variant = std::max(0, dict_int(determinism, "forced_variant", 0));

	recipe.valid = true;
	return recipe;
}

} // namespace world_contour_recipe
