#ifndef STATION_MIRNY_ROCK_MARCHING_SQUARES_H
#define STATION_MIRNY_ROCK_MARCHING_SQUARES_H

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class RockMarchingSquares : public Object {
	GDCLASS(RockMarchingSquares, Object)

protected:
	static void _bind_methods();

public:
	Array extract_polylines(
		const PackedInt32Array &p_terrain_ids,
		int64_t p_width,
		int64_t p_height,
		int64_t p_rock_terrain_id
	) const;
};

} // namespace godot

#endif
