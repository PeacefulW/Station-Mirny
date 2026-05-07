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

} // namespace mountain_contour

#endif
