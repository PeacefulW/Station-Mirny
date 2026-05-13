#ifndef STATION_MIRNY_WORLD_CONTOUR_FIELD_H
#define STATION_MIRNY_WORLD_CONTOUR_FIELD_H

#include <cstdint>

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include "world_contour_recipe.h"

namespace world_contour_field {

struct ContourChunkInputV1 {
	godot::Vector2i chunk_coord = godot::Vector2i();
	int64_t world_seed = 0;
	int64_t world_version = 0;
	int32_t tile_size_px = 64;
	int32_t render_tile_size_px = 32;
	int32_t chunk_size_tiles = 16;
	int32_t halo_tiles = 1;
	godot::StringName recipe_id;
	world_contour_recipe::ContourRecipeV1 recipe;
	godot::PackedByteArray solid_mask_with_halo;
	godot::PackedByteArray contour_class_mask_with_halo;
	godot::PackedInt32Array mountain_id_with_halo;
	int64_t diff_revision = 0;
	bool valid = false;
	godot::String error;
};

godot::Dictionary build_contour_chunk(const godot::Dictionary &p_input);

} // namespace world_contour_field

#endif
