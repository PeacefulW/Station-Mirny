#ifndef STATION_MIRNY_WORLD_RENDER_BUFFER_H
#define STATION_MIRNY_WORLD_RENDER_BUFFER_H

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace world_render_buffer {

// Builds the complete visible static-world snapshot. Storage remains chunked,
// but the returned GPU buffers are deliberately independent of chunks,
// families and depth stripes. Each instance uses Godot's 2D transform + color
// + custom-data layout (16 floats).
godot::Dictionary build_snapshot(
		const godot::PackedVector2Array &p_chunk_origins,
		const godot::Array &p_object_results,
		const godot::Array &p_grass_results,
		const godot::Array &p_source_bindings,
		float p_grass_lod_fraction);

// Merges the small interactive actor set into the immutable static pages.
// Static page buffers stay worker-built; only pages which contain an actor are
// copied/repacked, and the returned actor-shadow stream is one shared buffer.
godot::Dictionary compose_actor_snapshot(
		const godot::Dictionary &p_static_snapshot,
		const godot::Array &p_actor_records);

// Stitches worker-prepared, border-sharing RGBA8 field tiles into three shared
// world-space textures. This is a storage-to-render transform only: no field
// formula is evaluated on the main thread.
godot::Dictionary build_ground_field_snapshot(
		const godot::PackedVector2Array &p_chunk_origins,
		const godot::Array &p_grass_results);

// Builds a seamless cosmetic wind field. Unlike placement/world fields this
// texture is intentionally periodic: its very large period is a bounded GPU
// resource, and wind scroll may run forever without a visible seam.
godot::PackedByteArray build_periodic_gradient_noise_texture(
		int32_t p_size,
		int32_t p_texels_per_cell);

} // namespace world_render_buffer

#endif // STATION_MIRNY_WORLD_RENDER_BUFFER_H
