#ifndef STATION_MIRNY_TERRAIN_VISUAL_SOLVER_H
#define STATION_MIRNY_TERRAIN_VISUAL_SOLVER_H

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

class TerrainVisualSolver : public Object {
	GDCLASS(TerrainVisualSolver, Object)

protected:
	static void _bind_methods();

public:
	Dictionary build_editor_preview_packet(
		const PackedByteArray &p_solid_mask,
		int64_t p_width_tiles,
		int64_t p_height_tiles,
		const Dictionary &p_recipe_payload,
		Vector2i p_preview_origin_tile,
		int64_t p_seed
	) const;

	Dictionary build_chunk_visual_packet(
		const PackedByteArray &p_solid_mask,
		int64_t p_width_tiles,
		int64_t p_height_tiles,
		const Dictionary &p_recipe_payload,
		Vector2i p_world_origin_tile,
		Vector2i p_chunk_coord,
		int64_t p_seed
	) const;
};

} // namespace godot

#endif
