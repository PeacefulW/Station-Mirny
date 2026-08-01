extends SceneTree
## Contract test for Player Visual Presentation V1, including baked shadows (I2).
##
## The test intentionally reads metadata and source PNG pixels. Import success
## alone cannot prove that every 76x48 tile has a transparent gutter, the tree
## shadow colour, or the same animation phase as its albedo counterpart.
## Spec: docs/02_system_specs/progression/player_visual_presentation_v1.md

const ATLAS_DIR: String = "res://assets/sprites/player"
const PLAYER_SCRIPT_PATH: String = "res://core/entities/player/player.gd"
const SHADOW_SCRIPT_PATH: String = "res://core/entities/player/player_sun_shadow.gd"
const SHADOW_SHADER_PATH: String = "res://assets/shaders/player_silhouette_shadow.gdshader"
const SCENE_PATH: String = "res://scenes/player/player.tscn"
const PROFILE_PATH: String = "res://tools/player_atlas/player_bake_profile.json"
const TREE_PROFILE_PATH: String = "res://tools/tree_atlas/layered_asset_bake_profile.json"
const TREE_PROFILE_RESOURCE_PATH: String = "tools/tree_atlas/layered_asset_bake_profile.json"

const CLIP_IDS: Array[String] = [
	"idle",
	"run_forward",
	"run_backward",
	"strafe_left",
	"strafe_right",
]
const EXPECTED_DIRECTIONS: int = 16
const EXPECTED_FRAMES_PER_DIRECTION: int = 16
const EXPECTED_FRAME_COUNT: int = EXPECTED_DIRECTIONS * EXPECTED_FRAMES_PER_DIRECTION
const EXPECTED_DIRECTION_ZERO: String = "screen_north"
const EXPECTED_DIRECTION_ORDER: String = "clockwise"

const EXPECTED_ALBEDO_FRAME_SIZE: Vector2i = Vector2i(208, 288)
const EXPECTED_SHADOW_FRAME_SIZE: Vector2i = Vector2i(76, 48)
const EXPECTED_SHADOW_ATLAS_SIZE: Vector2i = Vector2i(1216, 768)
const EXPECTED_ALBEDO_ANCHOR_UV: Vector2 = Vector2(0.5, 0.806)
const EXPECTED_SHADOW_ANCHOR_PX: Vector2 = Vector2(26.0, 14.0)
const EXPECTED_SHADOW_DOWNSAMPLE: float = 4.0

## Shared layered-tree bake canon.
const CANON_CAMERA_ELEVATION_DEGREES: float = 28.07
const CANON_SUN_AZIMUTH_DEGREES: float = 225.0
const CANON_SHADOW_SUN_ELEVATION_DEGREES: float = 42.0
const CANON_SHADOW_SUN_ENERGY: float = 3.5
const CANON_CYCLES_SAMPLES: int = 64
const CANON_SHADOW_DIRECTION_NAME: String = "screen_south_east"
const CANON_SHADOW_DIRECTION: Vector2 = Vector2(0.887216, 0.461354)
const CANON_SHADOW_RGB: Vector3i = Vector3i(15, 11, 7)

const STRONG_ALPHA_THRESHOLD: int = 8
const MIN_SHADOW_MARGIN_PX: int = 2
const MAX_PROCESSED_SHADOW_ALPHA: int = 215
const LOOP_DIRECTION_SEAM_RATIO_MAX: float = 1.75
const LOOP_MEDIAN_SEAM_RATIO_MAX: float = 1.50
const SOURCE_ENDPOINT_POSE_RMS_MAX: float = 0.015
const PROJECTED_CLIP_COUNT: int = 8
## RGBA8 without mipmaps; accepted by the user on 2026-07-31.
const VRAM_BUDGET_MIB: float = 581.0

const ANGLE_EPSILON: float = 0.05
const METADATA_EPSILON: float = 0.00001
const VECTOR_EPSILON: float = 0.00001

var _failures: Array[String] = []
var _player_profile: Dictionary = {}
var _tree_profile: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_player_profile = _load_metadata(PROFILE_PATH)
	_tree_profile = _load_metadata(TREE_PROFILE_PATH)
	_verify_profile_contract()

	var runtime_frame_width: int = _read_int_constant(
		PLAYER_SCRIPT_PATH,
		"PLAYER_ATLAS_FRAME_WIDTH_PX",
	)
	var runtime_frame_height: int = _read_int_constant(
		PLAYER_SCRIPT_PATH,
		"PLAYER_ATLAS_FRAME_HEIGHT_PX",
	)
	if Vector2i(runtime_frame_width, runtime_frame_height) != EXPECTED_ALBEDO_FRAME_SIZE:
		_failures.append(
			"Player albedo frame is %sx%s, expected %s"
			% [runtime_frame_width, runtime_frame_height, EXPECTED_ALBEDO_FRAME_SIZE]
		)

	var active_albedo_mib: float = 0.0
	var active_shadow_mib: float = 0.0
	for clip_id: String in CLIP_IDS:
		var sizes: Dictionary = _verify_clip_pair(clip_id)
		active_albedo_mib += float(sizes.get("albedo_mib", 0.0))
		active_shadow_mib += float(sizes.get("shadow_mib", 0.0))

	var expected_per_clip_mib: float = (
		float(EXPECTED_ALBEDO_FRAME_SIZE.x * EXPECTED_FRAMES_PER_DIRECTION)
		* float(EXPECTED_ALBEDO_FRAME_SIZE.y * EXPECTED_DIRECTIONS)
		* 4.0
		+ float(EXPECTED_SHADOW_ATLAS_SIZE.x * EXPECTED_SHADOW_ATLAS_SIZE.y) * 4.0
	) / 1048576.0
	var projected_eight_clip_mib: float = expected_per_clip_mib * PROJECTED_CLIP_COUNT
	if projected_eight_clip_mib > VRAM_BUDGET_MIB:
		_failures.append(
			"Projected %d-clip albedo+shadow cost %.3f MiB exceeds %.1f MiB"
			% [PROJECTED_CLIP_COUNT, projected_eight_clip_mib, VRAM_BUDGET_MIB]
		)

	_verify_scene_contract()
	_verify_runtime_direction_contract()
	_verify_baked_shadow_runtime_contract()

	if _failures.is_empty():
		print(
			(
				"Player I2 atlases: %.3f MiB active (%.3f albedo + %.3f shadow); "
						+ "projected 8 clips %.3f MiB of %.1f MiB budget"
			)
			% [
				active_albedo_mib + active_shadow_mib,
				active_albedo_mib,
				active_shadow_mib,
				projected_eight_clip_mib,
				VRAM_BUDGET_MIB,
			]
		)
		print("PLAYER_VISUAL_PRESENTATION_CONTRACT_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("PLAYER_VISUAL_PRESENTATION_CONTRACT_FAILED: %d" % _failures.size())
	quit(1)


func _verify_profile_contract() -> void:
	if _player_profile.is_empty() or _tree_profile.is_empty():
		return
	if str(_player_profile.get("inherits_bake_profile", "")) != TREE_PROFILE_RESOURCE_PATH:
		_failures.append("Player bake profile must inherit the layered-tree bake profile")

	var shadow_profile: Dictionary = _player_profile.get("shadow", {}) as Dictionary
	_expect_int(shadow_profile, "source_width_px", 304, "player shadow profile")
	_expect_int(shadow_profile, "source_height_px", 192, "player shadow profile")
	_expect_int(shadow_profile, "output_width_px", EXPECTED_SHADOW_FRAME_SIZE.x, "player shadow profile")
	_expect_int(shadow_profile, "output_height_px", EXPECTED_SHADOW_FRAME_SIZE.y, "player shadow profile")
	_expect_int(shadow_profile, "downsample_factor", int(EXPECTED_SHADOW_DOWNSAMPLE), "player shadow profile")
	_verify_vector2_value(
		"player shadow source anchor",
		shadow_profile.get("source_anchor_px", []),
		EXPECTED_SHADOW_ANCHOR_PX * EXPECTED_SHADOW_DOWNSAMPLE,
		METADATA_EPSILON,
	)

	var lighting: Dictionary = _tree_profile.get("lighting", {}) as Dictionary
	var render: Dictionary = _tree_profile.get("render", {}) as Dictionary
	var postprocess: Dictionary = _tree_profile.get("postprocess", {}) as Dictionary
	_expect_close(
		"tree sun azimuth",
		float(lighting.get("sun_azimuth_degrees", -1.0)),
		CANON_SUN_AZIMUTH_DEGREES,
		METADATA_EPSILON,
	)
	_expect_close(
		"tree shadow sun elevation",
		float(lighting.get("shadow_sun_elevation_degrees", -1.0)),
		CANON_SHADOW_SUN_ELEVATION_DEGREES,
		METADATA_EPSILON,
	)
	_expect_close(
		"tree shadow sun energy",
		float(lighting.get("shadow_sun_energy", -1.0)),
		CANON_SHADOW_SUN_ENERGY,
		METADATA_EPSILON,
	)
	if str(lighting.get("fixed_shadow_direction", "")) != CANON_SHADOW_DIRECTION_NAME:
		_failures.append("Tree profile fixed shadow direction must be screen_south_east")
	if str(render.get("shadow_engine", "")) != "CYCLES":
		_failures.append("Tree profile shadow engine must be CYCLES")
	if int(render.get("samples", 0)) != CANON_CYCLES_SAMPLES:
		_failures.append("Tree profile must render shadows with %d samples" % CANON_CYCLES_SAMPLES)
	if not bool(render.get("use_denoising", false)):
		_failures.append("Tree profile must enable Cycles denoising")
	_verify_vector3i_value("tree shadow RGB", postprocess.get("shadow_rgb", []), CANON_SHADOW_RGB)

	var validation: Dictionary = _player_profile.get("loop_validation", {}) as Dictionary
	_expect_close(
		"profile per-direction loop threshold",
		float(validation.get("pixel_seam_to_direction_median_max", -1.0)),
		LOOP_DIRECTION_SEAM_RATIO_MAX,
		METADATA_EPSILON,
	)
	_expect_close(
		"profile median loop threshold",
		float(validation.get("pixel_median_seam_to_internal_median_max", -1.0)),
		LOOP_MEDIAN_SEAM_RATIO_MAX,
		METADATA_EPSILON,
	)


func _verify_clip_pair(clip_id: String) -> Dictionary:
	var albedo_stem: String = _albedo_atlas_stem(clip_id)
	var shadow_stem: String = _shadow_atlas_stem(clip_id)
	var albedo_path: String = "%s/%s.png" % [ATLAS_DIR, albedo_stem]
	var shadow_path: String = "%s/%s.png" % [ATLAS_DIR, shadow_stem]
	var albedo_metadata: Dictionary = _load_metadata("%s/%s.json" % [ATLAS_DIR, albedo_stem])
	var shadow_metadata: Dictionary = _load_metadata("%s/%s.json" % [ATLAS_DIR, shadow_stem])

	var albedo_image: Image = _load_png(albedo_path)
	var shadow_image: Image = _load_png(shadow_path)
	var albedo_mib: float = _verify_albedo_atlas(clip_id, albedo_image, albedo_metadata)
	var shadow_mib: float = _verify_shadow_atlas_pixels(clip_id, shadow_image, shadow_metadata)

	if not albedo_metadata.is_empty() and not shadow_metadata.is_empty():
		_verify_shadow_metadata(clip_id, shadow_metadata)
		_verify_pair_metadata(clip_id, albedo_metadata, shadow_metadata)
		_verify_loop_sampling(clip_id, albedo_metadata, true, "albedo")
		_verify_loop_sampling(clip_id, shadow_metadata, false, "shadow")

	return {"albedo_mib": albedo_mib, "shadow_mib": shadow_mib}


func _verify_albedo_atlas(clip_id: String, image: Image, metadata: Dictionary) -> float:
	if image.is_empty() or metadata.is_empty():
		return 0.0
	var expected_atlas_size := Vector2i(
		EXPECTED_ALBEDO_FRAME_SIZE.x * EXPECTED_FRAMES_PER_DIRECTION,
		EXPECTED_ALBEDO_FRAME_SIZE.y * EXPECTED_DIRECTIONS,
	)
	if image.get_size() != expected_atlas_size:
		_failures.append(
			"%s albedo atlas is %s, expected %s"
			% [clip_id, image.get_size(), expected_atlas_size]
		)
	_expect_int(metadata, "frame_width_px", EXPECTED_ALBEDO_FRAME_SIZE.x, "%s albedo" % clip_id)
	_expect_int(metadata, "frame_height_px", EXPECTED_ALBEDO_FRAME_SIZE.y, "%s albedo" % clip_id)
	_verify_grid_metadata("%s albedo" % clip_id, metadata)
	_verify_direction_yaws("%s albedo" % clip_id, metadata)
	_verify_vector2_value(
		"%s albedo projected world-origin anchor" % clip_id,
		metadata.get("foot_anchor_uv", []),
		EXPECTED_ALBEDO_ANCHOR_UV,
		METADATA_EPSILON,
	)
	_expect_close(
		"%s albedo camera elevation" % clip_id,
		float(metadata.get("camera_elevation_degrees", -1.0)),
		CANON_CAMERA_ELEVATION_DEGREES,
		ANGLE_EPSILON,
	)
	_expect_close(
		"%s albedo sun azimuth" % clip_id,
		float(metadata.get("sun_azimuth_degrees", -1.0)),
		CANON_SUN_AZIMUTH_DEGREES,
		ANGLE_EPSILON,
	)
	return float(image.get_width() * image.get_height() * 4) / 1048576.0


func _verify_shadow_metadata(clip_id: String, metadata: Dictionary) -> void:
	var label: String = "%s shadow" % clip_id
	if str(metadata.get("asset_kind", "")) != "baked_player_sun_shadow":
		_failures.append("%s metadata asset_kind is not baked_player_sun_shadow" % label)
	if str(metadata.get("render_mode", "")) != "cycles_shadow_catcher":
		_failures.append("%s was not rendered as a Cycles shadow catcher" % label)
	if str(metadata.get("inherits_bake_profile", "")) != TREE_PROFILE_RESOURCE_PATH:
		_failures.append("%s does not inherit the tree bake profile" % label)
	_expect_int(metadata, "frame_width_px", EXPECTED_SHADOW_FRAME_SIZE.x, label)
	_expect_int(metadata, "frame_height_px", EXPECTED_SHADOW_FRAME_SIZE.y, label)
	_expect_int(metadata, "atlas_width_px", EXPECTED_SHADOW_ATLAS_SIZE.x, label)
	_expect_int(metadata, "atlas_height_px", EXPECTED_SHADOW_ATLAS_SIZE.y, label)
	_expect_int(metadata, "downsample_factor", int(EXPECTED_SHADOW_DOWNSAMPLE), label)
	_expect_int(metadata, "frames_rendered", EXPECTED_FRAME_COUNT, label)
	_verify_grid_metadata(label, metadata)
	_verify_direction_yaws(label, metadata)
	_verify_vector2_value(
		"%s anchor" % label,
		metadata.get("shadow_anchor_px", []),
		EXPECTED_SHADOW_ANCHOR_PX,
		METADATA_EPSILON,
	)
	_verify_vector2_value(
		"%s anchor UV" % label,
		metadata.get("shadow_anchor_uv", []),
		Vector2(
			EXPECTED_SHADOW_ANCHOR_PX.x / EXPECTED_SHADOW_FRAME_SIZE.x,
			EXPECTED_SHADOW_ANCHOR_PX.y / EXPECTED_SHADOW_FRAME_SIZE.y,
		),
		0.000001,
	)
	_expect_close(
		"%s camera elevation" % label,
		float(metadata.get("camera_elevation_degrees", -1.0)),
		CANON_CAMERA_ELEVATION_DEGREES,
		ANGLE_EPSILON,
	)
	_expect_close(
		"%s sun azimuth" % label,
		float(metadata.get("sun_azimuth_degrees", -1.0)),
		CANON_SUN_AZIMUTH_DEGREES,
		ANGLE_EPSILON,
	)
	_expect_close(
		"%s shadow sun elevation" % label,
		float(metadata.get("shadow_sun_elevation_degrees", -1.0)),
		CANON_SHADOW_SUN_ELEVATION_DEGREES,
		METADATA_EPSILON,
	)
	_expect_close(
		"%s shadow sun energy" % label,
		float(metadata.get("shadow_sun_energy", -1.0)),
		CANON_SHADOW_SUN_ENERGY,
		METADATA_EPSILON,
	)
	_expect_int(metadata, "cycles_samples", CANON_CYCLES_SAMPLES, label)
	if not bool(metadata.get("denoising", false)):
		_failures.append("%s must record Cycles denoising" % label)
	if str(metadata.get("fixed_shadow_direction", "")) != CANON_SHADOW_DIRECTION_NAME:
		_failures.append("%s fixed direction is not screen_south_east" % label)
	_verify_vector2_value(
		"%s fixed direction vector" % label,
		metadata.get("fixed_shadow_direction_vector", []),
		CANON_SHADOW_DIRECTION,
		VECTOR_EPSILON,
	)
	_verify_vector3i_value("%s RGB" % label, metadata.get("shadow_rgb", []), CANON_SHADOW_RGB)
	if int(metadata.get("border_alpha_max", -1)) != 0:
		_failures.append("%s metadata reports alpha on a tile border" % label)
	if int(metadata.get("alpha_max", 0)) > MAX_PROCESSED_SHADOW_ALPHA:
		_failures.append(
			"%s alpha max %s exceeds tree-pipeline cap %d"
			% [label, metadata.get("alpha_max"), MAX_PROCESSED_SHADOW_ALPHA]
		)
	var margins_raw: Variant = metadata.get("min_margins_px", [])
	if not (margins_raw is Array) or (margins_raw as Array).size() != 4:
		_failures.append("%s has no four-sided min_margins_px proof" % label)
	else:
		for margin: Variant in margins_raw as Array:
			if int(margin) < MIN_SHADOW_MARGIN_PX:
				_failures.append(
					"%s metadata margin %s is below %d px"
					% [label, margin, MIN_SHADOW_MARGIN_PX]
				)
				break


func _verify_pair_metadata(
		clip_id: String,
		albedo: Dictionary,
		shadow: Dictionary,
) -> void:
	if str(shadow.get("albedo_atlas", "")) != "%s.png" % _albedo_atlas_stem(clip_id):
		_failures.append("%s shadow metadata points at the wrong albedo atlas" % clip_id)
	_verify_vector2_value(
		"%s shadow albedo_anchor_uv" % clip_id,
		shadow.get("albedo_anchor_uv", []),
		_variant_to_vector2(albedo.get("foot_anchor_uv", [])),
		METADATA_EPSILON,
	)
	_verify_numeric_array_match(
		"%s direction yaws" % clip_id,
		albedo.get("direction_yaw_degrees", []),
		shadow.get("direction_yaw_degrees", []),
		METADATA_EPSILON,
	)
	_verify_numeric_array_match(
		"%s sampled source phases" % clip_id,
		albedo.get("sampled_source_frames", []),
		shadow.get("sampled_source_frames", []),
		METADATA_EPSILON,
	)
	_expect_close(
		"%s source frame start parity" % clip_id,
		float(shadow.get("source_frame_start", -1.0)),
		float(albedo.get("source_frame_start", -2.0)),
		METADATA_EPSILON,
	)
	_expect_close(
		"%s source frame end parity" % clip_id,
		float(shadow.get("source_frame_end", -1.0)),
		float(albedo.get("source_frame_end", -2.0)),
		METADATA_EPSILON,
	)
	if bool(shadow.get("loop", false)) != bool(albedo.get("loop", false)):
		_failures.append("%s albedo/shadow loop declarations differ" % clip_id)


func _verify_shadow_atlas_pixels(clip_id: String, image: Image, metadata: Dictionary) -> float:
	if image.is_empty():
		return 0.0
	if image.get_size() != EXPECTED_SHADOW_ATLAS_SIZE:
		_failures.append(
			"%s shadow atlas is %s, expected %s"
			% [clip_id, image.get_size(), EXPECTED_SHADOW_ATLAS_SIZE]
		)
		return float(image.get_width() * image.get_height() * 4) / 1048576.0

	var atlas_alpha_max: int = 0
	var atlas_border_alpha_max: int = 0
	var actual_min_margins: Array[int] = [
		EXPECTED_SHADOW_FRAME_SIZE.x,
		EXPECTED_SHADOW_FRAME_SIZE.y,
		EXPECTED_SHADOW_FRAME_SIZE.x,
		EXPECTED_SHADOW_FRAME_SIZE.y,
	]
	var rgb_failure_reported: bool = false
	for direction: int in range(EXPECTED_DIRECTIONS):
		for frame_index: int in range(EXPECTED_FRAMES_PER_DIRECTION):
			var tile_origin := Vector2i(
				frame_index * EXPECTED_SHADOW_FRAME_SIZE.x,
				direction * EXPECTED_SHADOW_FRAME_SIZE.y,
			)
			var min_x: int = EXPECTED_SHADOW_FRAME_SIZE.x
			var min_y: int = EXPECTED_SHADOW_FRAME_SIZE.y
			var max_x: int = -1
			var max_y: int = -1
			for local_y: int in range(EXPECTED_SHADOW_FRAME_SIZE.y):
				for local_x: int in range(EXPECTED_SHADOW_FRAME_SIZE.x):
					var color: Color = image.get_pixel(tile_origin.x + local_x, tile_origin.y + local_y)
					var alpha: int = roundi(color.a * 255.0)
					atlas_alpha_max = maxi(atlas_alpha_max, alpha)
					if local_x == 0 \
							or local_y == 0 \
							or local_x == EXPECTED_SHADOW_FRAME_SIZE.x - 1 \
							or local_y == EXPECTED_SHADOW_FRAME_SIZE.y - 1:
						atlas_border_alpha_max = maxi(atlas_border_alpha_max, alpha)
					if alpha > 0 and not rgb_failure_reported:
						var rgb := Vector3i(
							roundi(color.r * 255.0),
							roundi(color.g * 255.0),
							roundi(color.b * 255.0),
						)
						if rgb != CANON_SHADOW_RGB:
							rgb_failure_reported = true
							_failures.append(
								"%s shadow pixel RGB is %s, tree canon is %s"
								% [clip_id, rgb, CANON_SHADOW_RGB]
							)
					if alpha > STRONG_ALPHA_THRESHOLD:
						min_x = mini(min_x, local_x)
						min_y = mini(min_y, local_y)
						max_x = maxi(max_x, local_x)
						max_y = maxi(max_y, local_y)
			if max_x < 0 or max_y < 0:
				_failures.append(
					"%s shadow row %d frame %d has no alpha above %d"
					% [clip_id, direction, frame_index, STRONG_ALPHA_THRESHOLD]
				)
				continue
			var margins: Array[int] = [
				min_x,
				min_y,
				EXPECTED_SHADOW_FRAME_SIZE.x - 1 - max_x,
				EXPECTED_SHADOW_FRAME_SIZE.y - 1 - max_y,
			]
			for side: int in range(4):
				actual_min_margins[side] = mini(actual_min_margins[side], margins[side])
				if margins[side] < MIN_SHADOW_MARGIN_PX:
					_failures.append(
						"%s shadow row %d frame %d margin side %d is %d px; minimum %d"
						% [
							clip_id,
							direction,
							frame_index,
							side,
							margins[side],
							MIN_SHADOW_MARGIN_PX,
						]
					)

	if atlas_border_alpha_max != 0:
		_failures.append(
			"%s shadow atlas leaks alpha %d onto a tile border"
			% [clip_id, atlas_border_alpha_max]
		)
	if atlas_alpha_max <= 0 or atlas_alpha_max > MAX_PROCESSED_SHADOW_ALPHA:
		_failures.append(
			"%s shadow alpha max %d is outside 1..%d"
			% [clip_id, atlas_alpha_max, MAX_PROCESSED_SHADOW_ALPHA]
		)
	if not metadata.is_empty():
		if int(metadata.get("alpha_max", -1)) != atlas_alpha_max:
			_failures.append(
				"%s shadow metadata alpha_max %s differs from PNG %d"
				% [clip_id, metadata.get("alpha_max"), atlas_alpha_max]
			)
		if int(metadata.get("border_alpha_max", -1)) != atlas_border_alpha_max:
			_failures.append(
				"%s shadow metadata border_alpha_max differs from PNG"
			)
		var recorded_margins: Variant = metadata.get("min_margins_px", [])
		if recorded_margins is Array and (recorded_margins as Array).size() == 4:
			for side: int in range(4):
				if int((recorded_margins as Array)[side]) != actual_min_margins[side]:
					_failures.append(
						"%s shadow metadata margin side %d is %s, PNG is %d"
						% [clip_id, side, (recorded_margins as Array)[side], actual_min_margins[side]]
					)
	return float(image.get_width() * image.get_height() * 4) / 1048576.0


func _verify_grid_metadata(label: String, metadata: Dictionary) -> void:
	_expect_int(metadata, "directions", EXPECTED_DIRECTIONS, label)
	_expect_int(metadata, "frames_per_direction", EXPECTED_FRAMES_PER_DIRECTION, label)
	if str(metadata.get("direction_zero", "")) != EXPECTED_DIRECTION_ZERO:
		_failures.append("%s direction_zero must be screen_north" % label)
	if str(metadata.get("direction_order", "")) != EXPECTED_DIRECTION_ORDER:
		_failures.append("%s direction_order must be clockwise" % label)


func _verify_direction_yaws(label: String, metadata: Dictionary) -> void:
	var raw: Variant = metadata.get("direction_yaw_degrees", [])
	if not (raw is Array) or (raw as Array).size() != EXPECTED_DIRECTIONS:
		_failures.append("%s has no %d-row direction_yaw_degrees proof" % [label, EXPECTED_DIRECTIONS])
		return
	var yaws: Array = raw as Array
	var expected_cardinals: Dictionary = {0: 180.0, 4: 90.0, 8: 0.0, 12: 270.0}
	for row: int in expected_cardinals:
		if absf(float(yaws[row]) - float(expected_cardinals[row])) > ANGLE_EPSILON:
			_failures.append(
				"%s row %d yaw is %s, expected %s for N/E/S/W"
				% [label, row, yaws[row], expected_cardinals[row]]
			)


func _verify_loop_sampling(
		clip_id: String,
		metadata: Dictionary,
		require_endpoint_pose: bool,
		channel: String,
) -> void:
	if not bool(metadata.get("loop", false)):
		return
	var label: String = "%s %s" % [clip_id, channel]
	var sampled_raw: Variant = metadata.get("sampled_source_frames", [])
	if not (sampled_raw is Array) or (sampled_raw as Array).size() != EXPECTED_FRAMES_PER_DIRECTION:
		_failures.append("%s has no complete sampled_source_frames proof" % label)
		return
	var sampled: Array = sampled_raw as Array
	var source_start: float = float(metadata.get("source_frame_start", 0.0))
	var source_end: float = float(metadata.get("source_frame_end", 0.0))
	var expected_step: float = (source_end - source_start) / EXPECTED_FRAMES_PER_DIRECTION
	for frame_index: int in range(sampled.size()):
		var expected: float = source_start + frame_index * expected_step
		if absf(float(sampled[frame_index]) - expected) > 0.0001:
			_failures.append(
				"%s source phase %d is %s, expected %.5f"
				% [label, frame_index, sampled[frame_index], expected]
			)
			break
	if require_endpoint_pose:
		var pose: Variant = metadata.get("loop_endpoint_pose", {})
		if not (pose is Dictionary) or not (pose as Dictionary).has("rms"):
			_failures.append("%s has no loop endpoint pose proof" % label)
		elif float((pose as Dictionary).get("rms", INF)) > SOURCE_ENDPOINT_POSE_RMS_MAX:
			_failures.append(
				"%s endpoint pose RMS %.6f exceeds %.6f"
				% [label, float((pose as Dictionary).get("rms")), SOURCE_ENDPOINT_POSE_RMS_MAX]
			)
	var seam: Variant = metadata.get("loop_pixel_seam", {})
	if not (seam is Dictionary):
		_failures.append("%s has no rendered pixel loop-seam proof" % label)
		return
	var seam_report: Dictionary = seam as Dictionary
	var direction_ratio: float = float(seam_report.get("direction_seam_ratio_max", INF))
	var median_ratio: float = float(seam_report.get("median_seam_to_internal_median", INF))
	if direction_ratio > LOOP_DIRECTION_SEAM_RATIO_MAX:
		_failures.append(
			"%s worst direction loop seam %.3f exceeds %.3f"
			% [label, direction_ratio, LOOP_DIRECTION_SEAM_RATIO_MAX]
		)
	if median_ratio > LOOP_MEDIAN_SEAM_RATIO_MAX:
		_failures.append(
			"%s median loop seam %.3f exceeds %.3f"
			% [label, median_ratio, LOOP_MEDIAN_SEAM_RATIO_MAX]
		)


func _verify_scene_contract() -> void:
	var scene_text: String = _read_source(SCENE_PATH)
	if scene_text.is_empty():
		return
	var albedo_region: String = "region_rect = Rect2(0, 0, %d, %d)" % [
		EXPECTED_ALBEDO_FRAME_SIZE.x,
		EXPECTED_ALBEDO_FRAME_SIZE.y,
	]
	var shadow_region: String = "region_rect = Rect2(0, 0, %d, %d)" % [
		EXPECTED_SHADOW_FRAME_SIZE.x,
		EXPECTED_SHADOW_FRAME_SIZE.y,
	]
	if not scene_text.contains(albedo_region):
		_failures.append("Player scene has no %s albedo region" % albedo_region)
	if not scene_text.contains(shadow_region):
		_failures.append("Player scene has no %s baked-shadow region" % shadow_region)
	if not scene_text.contains("region_filter_clip_enabled = true"):
		_failures.append("Player shadow region must clip linear filtering to its atlas tile")
	for clip_id: String in CLIP_IDS:
		var shadow_path: String = "%s/%s.png" % [ATLAS_DIR, _shadow_atlas_stem(clip_id)]
		if not scene_text.contains(shadow_path):
			_failures.append("Player scene has no shadow atlas reference: %s" % shadow_path)
		var property_name: String = "%s_shadow_texture = ExtResource" % clip_id
		if not scene_text.contains(property_name):
			_failures.append("Player scene has no explicit %s mapping" % property_name)
	if scene_text.contains("_mixamo_16dir_16frames_256.png"):
		_failures.append("Player scene still references a superseded Mixamo-era atlas")


func _verify_runtime_direction_contract() -> void:
	var source: String = _read_source(PLAYER_SCRIPT_PATH)
	if source.is_empty():
		return
	if not source.contains("var _visual_facing: Vector2 = Vector2.UP"):
		_failures.append("Player default visual facing must be Vector2.UP for row 0")
	var mapper_regex := RegEx.new()
	mapper_regex.compile(
		"rad_to_deg\\(direction\\.angle\\(\\)\\)\\s*\\+\\s*PLAYER_RUN_ATLAS_DIRECTION_OFFSET_DEGREES"
	)
	if mapper_regex.search(source) == null:
		_failures.append("Player direction mapper must advance clockwise from screen north")
	var offset_degrees: float = _read_float_constant(
		PLAYER_SCRIPT_PATH,
		"PLAYER_RUN_ATLAS_DIRECTION_OFFSET_DEGREES",
	)
	var step_degrees: float = _read_float_constant(
		PLAYER_SCRIPT_PATH,
		"PLAYER_RUN_ATLAS_DIRECTION_STEP_DEGREES",
	)
	var rows: int = _read_int_constant(PLAYER_SCRIPT_PATH, "PLAYER_RUN_ATLAS_ROWS")
	var cardinals: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var expected_rows: Array[int] = [0, 4, 8, 12]
	for index: int in range(cardinals.size()):
		var angle_degrees: float = fposmod(
			rad_to_deg(cardinals[index].angle()) + offset_degrees,
			360.0,
		)
		var actual_row: int = int(floor(angle_degrees / step_degrees + 0.5)) % rows
		if actual_row != expected_rows[index]:
			_failures.append(
				"Player cardinal %s maps to row %d, expected %d"
				% [cardinals[index], actual_row, expected_rows[index]]
			)


func _verify_baked_shadow_runtime_contract() -> void:
	var source: String = _read_source(SHADOW_SCRIPT_PATH)
	var shader: String = _read_source(SHADOW_SHADER_PATH)
	if source.is_empty() or shader.is_empty():
		return

	var downsample: float = _read_float_constant(SHADOW_SCRIPT_PATH, "SHADOW_DOWNSAMPLE_FACTOR")
	_expect_close(
		"PlayerSunShadow runtime scale factor",
		downsample,
		EXPECTED_SHADOW_DOWNSAMPLE,
		METADATA_EPSILON,
	)
	_verify_vector2_value(
		"PlayerSunShadow albedo origin",
		_read_vector2_constant(SHADOW_SCRIPT_PATH, "ALBEDO_WORLD_ORIGIN_UV"),
		EXPECTED_ALBEDO_ANCHOR_UV,
		METADATA_EPSILON,
	)
	_verify_vector2_value(
		"PlayerSunShadow baked anchor",
		_read_vector2_constant(SHADOW_SCRIPT_PATH, "SHADOW_WORLD_ORIGIN_PX"),
		EXPECTED_SHADOW_ANCHOR_PX,
		METADATA_EPSILON,
	)
	if not source.contains("WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION"):
		_failures.append("PlayerSunShadow must use the shared fixed shadow direction")
	if not source.contains("_visual.scale * SHADOW_DOWNSAMPLE_FACTOR"):
		_failures.append("PlayerSunShadow must display the quarter-resolution atlas at 4x scale")
	if not source.contains("texture = shadow_texture"):
		_failures.append("PlayerSunShadow must select a separate baked shadow texture")
	if source.contains("texture = _visual.texture"):
		_failures.append("PlayerSunShadow still mirrors the albedo texture")
	for clip_id: String in CLIP_IDS:
		if not source.contains("%s_shadow_texture" % clip_id):
			_failures.append("PlayerSunShadow has no %s baked-atlas mapping" % clip_id)

	var forbidden_script_tokens: Array[String] = [
		"_contact_pool",
		"func _build_contact_pool",
		"func _update_contact_pool",
		"func _apply_contact_uv",
		"func _contact_table_for",
		"func _load_contact_table",
		"GradientTexture2D.new",
		"set_shader_parameter(\"contact_uv_y\"",
		"has_method(\"get_sun_angle\")",
		"call(\"get_sun_angle\")",
	]
	for token: String in forbidden_script_tokens:
		if source.contains(token):
			_failures.append("PlayerSunShadow retains forbidden I1 token: %s" % token)
	var forbidden_shader_tokens: Array[String] = [
		"uniform float contact_uv_y",
		"uniform float ground_uv_y",
		"uniform float sprite_height_px",
		"height_above",
		"shadow_projection",
	]
	for token: String in forbidden_shader_tokens:
		if shader.contains(token):
			_failures.append("Player baked-shadow shader retains forbidden I1 token: %s" % token)
	for required_shader_token: String in [
		"shadow_direction",
		"shadow_length_scale",
		"uniform vec2 shadow_frame_size_px",
		"uniform vec2 shadow_anchor_px",
		"if (forward_distance > 0.0)",
		"1.0 - 1.0 / safe_scale",
		"REGION_RECT",
		"texture(TEXTURE",
	]:
		if not shader.contains(required_shader_token):
			_failures.append("Player baked-shadow shader lacks %s" % required_shader_token)


func _read_source(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		_failures.append("Cannot read source: %s" % path)
	return text


func _load_metadata(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		_failures.append("Missing JSON metadata: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_failures.append("JSON metadata is not an object: %s" % path)
		return {}
	return parsed as Dictionary


func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		_failures.append("Missing PNG: %s" % path)
		return Image.new()
	var image := Image.new()
	var error: Error = image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		_failures.append("Missing or unreadable PNG: %s (%s)" % [path, error_string(error)])
		return Image.new()
	return image


func _read_int_constant(path: String, constant_name: String) -> int:
	return int(_read_float_constant(path, constant_name))


func _read_float_constant(path: String, constant_name: String) -> float:
	var source: String = _read_source(path)
	if source.is_empty():
		return -1.0
	var regex := RegEx.new()
	regex.compile("const\\s+%s\\s*:\\s*\\w+\\s*=\\s*([-0-9.]+)" % constant_name)
	var found: RegExMatch = regex.search(source)
	if found == null:
		_failures.append("Constant %s not found in %s" % [constant_name, path])
		return -1.0
	return float(found.get_string(1))


func _read_vector2_constant(path: String, constant_name: String) -> Vector2:
	var source: String = _read_source(path)
	if source.is_empty():
		return Vector2.INF
	var regex := RegEx.new()
	regex.compile(
		"const\\s+%s\\s*:\\s*Vector2\\s*=\\s*Vector2\\(\\s*([-0-9.]+)\\s*,\\s*([-0-9.]+)\\s*\\)"
		% constant_name
	)
	var found: RegExMatch = regex.search(source)
	if found == null:
		_failures.append("Vector2 constant %s not found in %s" % [constant_name, path])
		return Vector2.INF
	return Vector2(float(found.get_string(1)), float(found.get_string(2)))


func _expect_int(metadata: Dictionary, key: String, expected: int, label: String) -> void:
	if int(metadata.get(key, -1)) != expected:
		_failures.append(
			"%s %s is %s, expected %d" % [label, key, metadata.get(key), expected]
		)


func _expect_close(label: String, actual: float, expected: float, epsilon: float) -> void:
	if absf(actual - expected) > epsilon:
		_failures.append("%s is %.6f, expected %.6f" % [label, actual, expected])


func _variant_to_vector2(raw: Variant) -> Vector2:
	if raw is Vector2:
		return raw as Vector2
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return Vector2.INF


func _verify_vector2_value(
		label: String,
		raw: Variant,
		expected: Vector2,
		epsilon: float,
) -> void:
	var actual: Vector2 = _variant_to_vector2(raw)
	if not actual.is_finite() or actual.distance_to(expected) > epsilon:
		_failures.append("%s is %s, expected %s" % [label, actual, expected])


func _verify_vector3i_value(label: String, raw: Variant, expected: Vector3i) -> void:
	if not (raw is Array) or (raw as Array).size() < 3:
		_failures.append("%s is missing, expected %s" % [label, expected])
		return
	var values: Array = raw as Array
	var actual := Vector3i(int(values[0]), int(values[1]), int(values[2]))
	if actual != expected:
		_failures.append("%s is %s, expected %s" % [label, actual, expected])


func _verify_numeric_array_match(
		label: String,
		expected_raw: Variant,
		actual_raw: Variant,
		epsilon: float,
) -> void:
	if not (expected_raw is Array) or not (actual_raw is Array):
		_failures.append("%s arrays are missing" % label)
		return
	var expected: Array = expected_raw as Array
	var actual: Array = actual_raw as Array
	if expected.size() != actual.size():
		_failures.append("%s array sizes differ: %d vs %d" % [label, expected.size(), actual.size()])
		return
	for index: int in range(expected.size()):
		if absf(float(expected[index]) - float(actual[index])) > epsilon:
			_failures.append(
				"%s differs at %d: %s vs %s"
				% [label, index, expected[index], actual[index]]
			)
			return


func _albedo_atlas_stem(clip_id: String) -> String:
	return "player_%s_%ddir_%dframes" % [clip_id, EXPECTED_DIRECTIONS, EXPECTED_FRAMES_PER_DIRECTION]


func _shadow_atlas_stem(clip_id: String) -> String:
	return "player_%s_shadow_%ddir_%dframes" % [clip_id, EXPECTED_DIRECTIONS, EXPECTED_FRAMES_PER_DIRECTION]
