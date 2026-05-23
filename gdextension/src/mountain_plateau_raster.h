#ifndef STATION_MIRNY_MOUNTAIN_PLATEAU_RASTER_H
#define STATION_MIRNY_MOUNTAIN_PLATEAU_RASTER_H

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace mountain_plateau_raster {

godot::Dictionary build_image(
	const godot::Array &p_packets,
	godot::Vector2i p_target_chunk,
	const godot::Dictionary &p_preset,
	const godot::Ref<godot::Image> &p_top_image,
	const godot::Ref<godot::Image> &p_face_image
);

} // namespace mountain_plateau_raster

#endif
