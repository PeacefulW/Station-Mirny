extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var view: ChunkView = ChunkView.new()
	root.add_child(view)
	var zero_halo := PackedByteArray()
	zero_halo.resize(32 * 32)
	_assert(
		not view.apply_mountain_roof_reveal_halo(zero_halo, zero_halo),
		"Plain ChunkView must ignore roof selectors before paired native state.",
	)
	_assert(
		not bool(view.get_mountain_native_mask_debug_state().get(
			"native_mask_visual_pending",
			false,
		)),
		"Plain ChunkView must never enter the first-visible roof gate.",
	)

	var width: int = 32
	var closed := PackedByteArray()
	closed.resize(width * width)
	closed.fill(255)
	var remaining: PackedByteArray = closed.duplicate()
	var dual_result: Dictionary = _dual_result(width, remaining, closed, zero_halo)
	_assert(
		view.apply_mountain_native_mask_data(dual_result, Vector2.ZERO, 1.0),
		"Untouched paired native mask must apply.",
	)
	var texture: ImageTexture = _solid_texture()
	_assert(
		view.apply_pending_mountain_native_mask_visual(texture),
		"Untouched BASE visual must upload.",
	)
	var untouched_debug: Dictionary = view.get_mountain_native_mask_debug_state()
	_assert(
		not bool(untouched_debug.get("roof_overlay_visible", true)),
		"Zero-dug chunk must keep the optimized roof overlay absent.",
	)
	_assert(
		not bool(untouched_debug.get("closed_roof_texture_ready", true)),
		"Zero-dug chunk must not allocate a CLOSED GPU texture.",
	)

	var mouth_index: int = 16 * 32 + 16
	var dug: PackedByteArray = zero_halo.duplicate()
	dug[mouth_index] = 1
	remaining = closed.duplicate()
	remaining[mouth_index] = 0
	var aperture := PackedByteArray()
	aperture.resize(width * width)
	aperture[mouth_index] = 255
	dual_result = _dual_result(width, remaining, closed, dug, aperture)
	_assert(
		view.apply_mountain_native_mask_data(dual_result, Vector2.ZERO, 1.0),
		"Excavated paired native mask must apply.",
	)
	var mouth := PackedByteArray()
	mouth.resize(32 * 32)
	mouth[mouth_index] = 4 # south-facing physical mouth
	_assert(
		view.apply_mountain_roof_reveal_halo(zero_halo, mouth),
		"Directional outside mouth must dirty the selector.",
	)
	_assert(
		view.apply_pending_mountain_native_mask_visual(texture),
		"First excavation must lazily create the production roof resources.",
	)
	var outside_debug: Dictionary = view.get_mountain_native_mask_debug_state()
	_assert(bool(outside_debug.get("roof_overlay_visible", false)), "Roof overlay must exist after dig.")
	_assert(bool(outside_debug.get("closed_roof_texture_ready", false)), "CLOSED texture must exist after dig.")
	_assert(bool(outside_debug.get("reveal_texture_ready", false)), "Reveal texture must exist after dig.")
	_assert(bool(outside_debug.get("dug_texture_ready", false)), "Dug guard texture must exist after dig.")
	_assert(
		bool(outside_debug.get("physical_mouth_aperture_texture_ready", false)),
		"Canonical full-resolution aperture must upload for BASE.",
	)
	_assert(
		view._mountain_physical_mouth_aperture_image.get_data() == aperture,
		"BASE aperture texture must preserve the native L8 raster byte-for-byte.",
	)
	_assert(
		view._mountain_active_floor_halo_image.get_data()[mouth_index] == 0,
		"Outside combined roof selector must remain zero despite mouth metadata.",
	)
	_assert(
		_all_zero(view.call("_build_mountain_roof_reveal_mask") as PackedByteArray),
		"Outside roof reveal mask must be exactly empty so ROOF remains CLOSED.",
	)
	var physical_mouth_bytes: PackedByteArray = view._mountain_outside_mouth_halo_image.get_data()
	_assert(
		physical_mouth_bytes[mouth_index] == 4,
		"Physical selector must preserve the real source mouth code.",
	)
	_assert(
		physical_mouth_bytes[mouth_index + 32] == (4 | 64),
		"Physical selector must project the south mouth through exactly one exterior cell.",
	)
	_assert(
		physical_mouth_bytes[mouth_index - 32] == 0,
		"Physical selector must not add decoration behind the source mouth.",
	)
	_assert(
		physical_mouth_bytes[mouth_index - 64] == 0,
		"Physical selector must stay empty two cells behind the source mouth.",
	)
	var base_material: ShaderMaterial = view._mountain_top_mask_sprite.material as ShaderMaterial
	var roof_material: ShaderMaterial = view._mountain_closed_roof_mask_material
	_assert(base_material != null, "BASE material must exist after upload.")
	_assert(roof_material != null, "ROOF material must exist after upload.")
	if base_material != null:
		_assert(
			base_material.get_shader_parameter("base_visual_mask_texture") \
					== view._mountain_top_mask_texture,
			"BASE must bind its current V texture as the facade reference.",
		)
		_assert(
			float(base_material.get_shader_parameter("physical_mouth_aperture_enabled")) > 0.5,
			"Only BASE must enable native aperture unwarp.",
		)
		_assert(
			float(base_material.get_shader_parameter("physical_mouth_direction_enabled")) > 0.5,
			"BASE must receive N/E/S/W metadata for local facade ownership.",
		)
		_assert(
			is_zero_approx(float(base_material.get_shader_parameter("component_reveal_blend"))),
			"BASE must never receive roof reveal blending.",
		)
	if roof_material != null:
		_assert(
			roof_material.get_shader_parameter("base_visual_mask_texture") \
					== view._mountain_top_mask_texture,
			"ROOF must read V only as auxiliary internal-facade ownership.",
		)
		_assert(
			roof_material.get_shader_parameter("closed_mask_texture") \
					== view._mountain_closed_roof_mask_texture,
			"ROOF geometry must still bind immutable CLOSED independently from V.",
		)
		_assert(
			is_zero_approx(float(roof_material.get_shader_parameter("physical_mouth_aperture_enabled"))),
			"ROOF must ignore the physical aperture.",
		)
		_assert(
			float(roof_material.get_shader_parameter("physical_mouth_direction_enabled")) > 0.5,
			"ROOF may use direction metadata only to relinquish the matching facade band.",
		)
		_assert(
			is_zero_approx(float(roof_material.get_shader_parameter("component_reveal_blend"))),
			"Outside ROOF starts fully CLOSED at blend zero.",
		)
	view.set_mountain_roof_reveal_blend(1.0)
	if roof_material != null:
		_assert(
			is_equal_approx(float(roof_material.get_shader_parameter("component_reveal_blend")), 1.0),
			"ChunkView must update only the ROOF blend uniform without rebuilding masks.",
		)
	_assert(
		_all_zero(view.call("_build_mountain_roof_reveal_mask") as PackedByteArray),
		"Blend one with an outside zero selector must still leave ROOF fully CLOSED.",
	)

	var active: PackedByteArray = zero_halo.duplicate()
	active[mouth_index] = 1
	_assert(
		view.apply_mountain_roof_reveal_halo(active, mouth),
		"Entering the cavity must dirty the active selector.",
	)
	_assert(view.apply_pending_mountain_native_mask_visual(texture), "Inside selector must upload.")
	_assert(
		view._mountain_active_floor_halo_image.get_data()[mouth_index] == 255,
		"Active cavity ownership must be binary and independent from mouth metadata.",
	)
	_assert(
		(view.call("_build_mountain_roof_reveal_mask") as PackedByteArray)[mouth_index] == 255,
		"Inside roof selector must contain only the displayed connected component.",
	)

	view.queue_free()
	await process_frame
	if not _failed:
		print("mountain_construction_chunk_view_smoke_test: OK")
	quit(1 if _failed else 0)


func _dual_result(
		width: int,
		remaining: PackedByteArray,
		closed: PackedByteArray,
		dug: PackedByteArray,
		aperture: PackedByteArray = PackedByteArray(),
) -> Dictionary:
	return {
		"mask": remaining,
		"remaining_mass_mask": remaining,
		"visual_remaining_mass_mask": remaining,
		"closed_roof_mask": closed,
		"physical_mouth_aperture_mask": aperture,
		"dug_halo": dug,
		"width": width,
		"height": width,
		"step_px": 8.0,
		"pixels_per_tile": 1,
		"solid_sample_count": 1,
		"closed_sample_count": 1,
		"dug_sample_count": 1 if dug[mouth_index_or_zero(dug)] != 0 else 0,
	}


func _all_zero(bytes: PackedByteArray) -> bool:
	for value: int in bytes:
		if value != 0:
			return false
	return true


func mouth_index_or_zero(bytes: PackedByteArray) -> int:
	var index: int = 16 * 32 + 16
	return index if index < bytes.size() else 0


func _solid_texture() -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
