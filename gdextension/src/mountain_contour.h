#ifndef STATION_MIRNY_MOUNTAIN_CONTOUR_H
#define STATION_MIRNY_MOUNTAIN_CONTOUR_H

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace mountain_contour {

godot::Dictionary build_debug_mesh(
	const godot::PackedByteArray &p_solid_halo,
	int32_t p_chunk_size,
	int32_t p_tile_size_px
);

godot::Dictionary build_halo_mask(
	const godot::PackedByteArray &p_solid_halo,
	int32_t p_chunk_size,
	int32_t p_tile_size_px,
	int32_t p_pixels_per_tile,
	double p_origin_world_x,
	double p_origin_world_y,
	const godot::PackedByteArray &p_dug_halo
);

} // namespace mountain_contour

#endif
