#ifndef CHUNK_VISUAL_KERNELS_H
#define CHUNK_VISUAL_KERNELS_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/tile_map_layer.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class ChunkVisualKernels : public RefCounted {
	GDCLASS(ChunkVisualKernels, RefCounted)

public:
	ChunkVisualKernels();
	~ChunkVisualKernels();

	static Dictionary build_prebaked_visual_payload_static(Dictionary p_request);
	Dictionary build_prebaked_visual_payload(Dictionary p_request) const;
	Dictionary build_interior_macro_overlay(Dictionary p_request) const;
	Dictionary compute_visual_batch(Dictionary p_request) const;
	int32_t apply_chunk_visual_buffers(
		TileMapLayer *p_terrain_layer,
		const PackedInt32Array &p_terrain_buffer,
		TileMapLayer *p_ground_face_layer,
		const PackedInt32Array &p_ground_face_buffer,
		TileMapLayer *p_rock_layer,
		const PackedInt32Array &p_rock_buffer,
		TileMapLayer *p_cover_layer,
		const PackedInt32Array &p_cover_buffer,
		TileMapLayer *p_cliff_layer,
		const PackedInt32Array &p_cliff_buffer,
		int32_t p_buffer_stride = 7
	) const;

protected:
	static void _bind_methods();
};

} // namespace godot

#endif // CHUNK_VISUAL_KERNELS_H
