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
	PARAM_SHADOW_SIZE_SCALE = 28,    // width of contact-shadow blob vs tuft width
	PARAM_SHADOW_ALPHA = 29,         // base contact-shadow opacity
	PARAM_SHADOW_MIN_SIZE_UNIT = 30, // only tufts at/above this size cast a blob
	PARAM_SPORE_ORANGE_THRESHOLD = 31, // orange_region above which spores can spawn
	PARAM_SPORE_CHANCE = 32,         // per-candidate spore probability inside field
	PARAM_SPORE_SIZE_PX = 33,        // spore mote diameter
	PARAM_COUNT = 34,
};

// Depth ladder contract: tufts are split by the ABSOLUTE chunk-local depth
// stripe of their root (DEPTH_STRIPE_PX tall, DEPTH_STRIPES_PER_CHUNK per
// chunk, no wrap-around). The consumer assigns each stripe a z relative to
// the player's stripe (clamped player-relative ladder), so there is no
// periodic class wrap that could flip overlap order anywhere on screen.
constexpr int32_t DEPTH_STRIPE_PX = 16;
constexpr int32_t DEPTH_STRIPES_PER_CHUNK = 64;

// Builds ready-to-assign MultiMesh buffers (TRANSFORM_2D + colors, 12 floats
// per instance: row0 = (x.x, y.x, 0, origin.x), row1 = (x.y, y.y, 0, origin.y),
// color = (frame/255, tint, phase, alpha)). Deterministic from inputs.
// Result key "bucket_buffers" is an Array of DEPTH_STRIPES_PER_CHUNK
// PackedFloat32Array entries (one per chunk-local depth stripe). Inside each
// stripe instances are importance-ordered (large tufts first, small detail
// last), so zoom LOD can trim each stripe's tail via visible_instance_count
// without a rebuild. Tufts inside strong orange_region pick frames from the
// biofield atlas bank.
// Also returns "shadow_buffer" (one flat contact-shadow blob per large tuft,
// rendered below the grass ladder) and "spore_buffer" (sparse glowing motes
// above strong orange_region cores, drifting on the wind globals). Both are
// 12-float MultiMesh layouts; spore color packs (phase, drift_seed, _, alpha).
godot::Dictionary build_buffer(
		int64_t p_seed,
		int64_t p_chunk_x,
		int64_t p_chunk_y,
		const godot::PackedInt32Array &p_terrain_ids,
		const godot::PackedByteArray &p_lake_flags,
		const godot::PackedFloat32Array &p_params);

// Плотность травы поля в мировой точке (та же формула sample_fields, что красит
// землю и сеет пучки). Деревья растут только где земля «трава» (см. world_core).
float sample_grass_density(
		double p_world_x,
		double p_world_y,
		float p_grass_field_scale_px,
		float p_grass_coverage,
		float p_rock_field_scale_px,
		float p_rock_coverage);

} // namespace grass_scatter

#endif // STATION_MIRNY_GRASS_SCATTER_H
