#ifndef STATION_MIRNY_OBJECT_PRESENTATION_BUFFER_H
#define STATION_MIRNY_OBJECT_PRESENTATION_BUFFER_H

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace object_presentation {

// Each metric record belongs to one prepared presentation variant. The native
// builder never resolves files or Resources; boot-prepared asset metadata is
// the only input it needs to reproduce the Sprite2D transform off-thread.
enum MetricIndex {
	METRIC_FRAME_WIDTH_PX = 0,
	METRIC_FRAME_HEIGHT_PX = 1,
	METRIC_ANCHOR_X_PX = 2,
	METRIC_ANCHOR_Y_PX = 3,
	// Tree: authored fixed frame scale. Rock and bush: alpha-bbox visible width.
	METRIC_SCALE_OR_VISIBLE_WIDTH = 4,
	BASE_METRIC_STRIDE = 5,
	// Tree-only authored rectangular trunk footprint before the fixed visual
	// scale is applied. X is relative to the visual/depth root; Y is forced by
	// the builder so the footprint's southern edge remains exactly at root_y.
	METRIC_TREE_COLLISION_CENTER_X_OFFSET_PX = 5,
	METRIC_TREE_COLLISION_WIDTH_PX = 6,
	METRIC_TREE_COLLISION_DEPTH_PX = 7,
	TREE_METRIC_STRIDE = 8,
};

// Presentation tuning is supplied by the script-side catalog/contract rather
// than duplicated as magic values in native code.
enum ParamIndex {
	PARAM_LOCAL_PX_QUANTUM = 0,
	PARAM_DEPTH_STRIPE_PX = 1,
	PARAM_DEPTH_STRIPE_COUNT = 2,
	PARAM_TREE_COLLISION_WIDTH_MULTIPLIER = 3,
	PARAM_TREE_COLLISION_DEPTH_MULTIPLIER = 4,
	PARAM_TREE_COLLISION_MIN_DEPTH_PX = 5,
	// Classic atlas-decor contract. These values are authored script-side so
	// the worker reproduces the legacy presentation exactly without embedding
	// a second, drifting copy of visual tuning in native code.
	PARAM_DECOR_DEPTH_ANCHOR_Y_SCALE = 6,
	PARAM_SPIKY_ATLAS_BANK_COUNT = 7,
	PARAM_LIVING_ALPHA = 8,
	PARAM_SPIKY_ALPHA = 9,
	PARAM_LIVING_SHADOW_WIDTH_SCALE = 10,
	PARAM_LIVING_SHADOW_HEIGHT_SCALE = 11,
	PARAM_LIVING_SHADOW_CENTER_Y_SCALE = 12,
	PARAM_LIVING_SHADOW_MIN_WIDTH_PX = 13,
	PARAM_LIVING_SHADOW_MIN_HEIGHT_PX = 14,
	PARAM_LIVING_SHADOW_ALPHA = 15,
	PARAM_LIVING_SHADOW_SIZE_DIVISOR = 16,
	PARAM_LIVING_SHADOW_MIN_SCALE = 17,
	PARAM_LIVING_PRESENTATION_ENABLED = 18,
	PARAM_SPIKY_PRESENTATION_ENABLED = 19,
	PARAM_COUNT = 20,
};

// Pure worker-safe conversion of the canonical byte-packed object section to
// ready MultiMesh TRANSFORM_2D + color buffers. Every instance occupies 12
// floats: row0, row1, then color = (resolved atlas frame / 255, tint, phase,
// alpha). Tree/rock frames are packet_variant modulo prepared metric count;
// classic living/spiky flora retain their packet frame byte exactly. Stripe-
// only buffers target boot-prepared family atlases without duplicating the
// instance payload. Living flora additionally returns one flat raw contact-
// shadow buffer. Optional flora arrays stay empty when the family count is zero
// so disabled families add no 64/128-empty-array warm-cache overhead.
godot::Dictionary build_buffers(
		const godot::PackedByteArray &p_object_kind,
		const godot::PackedByteArray &p_object_local_x_px_q4,
		const godot::PackedByteArray &p_object_local_y_px_q4,
		const godot::PackedByteArray &p_object_size_px,
		const godot::PackedByteArray &p_object_atlas_index,
		const godot::PackedByteArray &p_object_variant,
		const godot::PackedByteArray &p_object_flags,
		const godot::PackedByteArray &p_object_tint,
		const godot::PackedByteArray &p_object_phase,
		const godot::PackedFloat32Array &p_tree_metrics,
		const godot::PackedFloat32Array &p_rock_metrics,
		const godot::PackedFloat32Array &p_bush_metrics,
		const godot::PackedFloat32Array &p_params);

} // namespace object_presentation

#endif // STATION_MIRNY_OBJECT_PRESENTATION_BUFFER_H
