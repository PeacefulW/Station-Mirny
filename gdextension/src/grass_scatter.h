#ifndef STATION_MIRNY_GRASS_SCATTER_H
#define STATION_MIRNY_GRASS_SCATTER_H

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cstdint>

namespace grass_scatter {

// Packed params layout (single authored source assembled by the runtime from
// the ground material sampling_params plus the grass material sampling_params;
// documented in docs/02_system_specs/meta/packet_schemas.md).
enum ParamIndex {
	PARAM_CHUNK_SIZE_TILES = 0,
	PARAM_TILE_SIZE_PX = 1,
	PARAM_PLAINS_TERRAIN_ID = 2,
	PARAM_CANDIDATE_GRID_SIDE = 3,
	PARAM_INSTANCE_CAP = 4,
	PARAM_GRASS_FIELD_SCALE_PX = 5,
	PARAM_GRASS_COVERAGE = 6,
	PARAM_ORANGE_FIELD_SCALE_PX = 7,
	PARAM_ORANGE_COVERAGE = 8,
	PARAM_ROCK_FIELD_SCALE_PX = 9,
	PARAM_ROCK_COVERAGE = 10,
	PARAM_TUFT_MIN_WIDTH_PX = 11,
	PARAM_TUFT_MAX_WIDTH_PX = 12,
	PARAM_TUFT_MIN_HEIGHT_PX = 13,
	PARAM_TUFT_MAX_HEIGHT_PX = 14,
	PARAM_HEIGHT_SCALE = 15,
	PARAM_DENSITY_SCALE = 16,
	PARAM_ORANGE_DENSITY_BOOST = 17,
	PARAM_DRY_FRAME_COUNT = 18,
	PARAM_BASE_TINT_MIN = 19,
	PARAM_BASE_TINT_MAX = 20,
	PARAM_ORANGE_TINT_BOOST = 21,
	PARAM_ALPHA_MIN = 22,
	PARAM_ALPHA_MAX = 23,
	PARAM_ORANGE_FRAME_BASE = 24,
	PARAM_ORANGE_FRAME_COUNT = 25,
	PARAM_ORANGE_BANK_LOW = 26,
	PARAM_ORANGE_BANK_HIGH = 27,
	PARAM_COUNT = 28,
};

// Builds a ready-to-assign MultiMesh buffer (TRANSFORM_2D + colors, 12 floats
// per instance: row0 = (x.x, y.x, 0, origin.x), row1 = (x.y, y.y, 0, origin.y),
// color = (frame/255, tint, phase, alpha)). Deterministic from inputs.
// Instances are importance-ordered (large tufts first, small detail last), so
// zoom LOD can trim the tail via MultiMesh.visible_instance_count without a
// rebuild. Tufts inside strong orange_region pick frames from the biofield
// atlas bank.
godot::Dictionary build_buffer(
		int64_t p_seed,
		int64_t p_chunk_x,
		int64_t p_chunk_y,
		const godot::PackedInt32Array &p_terrain_ids,
		const godot::PackedByteArray &p_lake_flags,
		const godot::PackedFloat32Array &p_params);

} // namespace grass_scatter

#endif // STATION_MIRNY_GRASS_SCATTER_H
