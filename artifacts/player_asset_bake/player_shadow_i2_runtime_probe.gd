extends SceneTree
## Isolated visual acceptance probe for Player Visual Presentation V1 / I2.
##
## It renders the real idle body and baked-shadow atlases through the live
## PlayerSunShadow component. Every column uses a different direction row; the
## two rows force noon (1.0x) and low-sun (1.85x) length. Yellow crosses mark the
## shared projected world origin and cyan arrows show the one fixed SE axis.
## A second transparent SubViewport renders only the six live shadow sprites.
## Its captured pixels are measured along that SE axis so shader compile failure
## or an unscaled fallback cannot accidentally report a passing probe.
##
## Run windowed (GPU capture is required):
##   godot --path . --rendering-method gl_compatibility \
##     --script artifacts/player_asset_bake/player_shadow_i2_runtime_probe.gd

const PlayerSunShadowScript = preload("res://core/entities/player/player_sun_shadow.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")

const IDLE_ALBEDO: Texture2D = preload(
	"res://assets/sprites/player/player_idle_16dir_16frames.png"
)
const RUN_FORWARD_ALBEDO: Texture2D = preload(
	"res://assets/sprites/player/player_run_forward_16dir_16frames.png"
)
const RUN_BACKWARD_ALBEDO: Texture2D = preload(
	"res://assets/sprites/player/player_run_backward_16dir_16frames.png"
)
const STRAFE_LEFT_ALBEDO: Texture2D = preload(
	"res://assets/sprites/player/player_strafe_left_16dir_16frames.png"
)
const STRAFE_RIGHT_ALBEDO: Texture2D = preload(
	"res://assets/sprites/player/player_strafe_right_16dir_16frames.png"
)

const IDLE_SHADOW: Texture2D = preload(
	"res://assets/sprites/player/player_idle_shadow_16dir_16frames.png"
)
const RUN_FORWARD_SHADOW: Texture2D = preload(
	"res://assets/sprites/player/player_run_forward_shadow_16dir_16frames.png"
)
const RUN_BACKWARD_SHADOW: Texture2D = preload(
	"res://assets/sprites/player/player_run_backward_shadow_16dir_16frames.png"
)
const STRAFE_LEFT_SHADOW: Texture2D = preload(
	"res://assets/sprites/player/player_strafe_left_shadow_16dir_16frames.png"
)
const STRAFE_RIGHT_SHADOW: Texture2D = preload(
	"res://assets/sprites/player/player_strafe_right_shadow_16dir_16frames.png"
)

const OUTPUT_PATH: String = \
	"res://artifacts/player_asset_bake/player_shadow_i2_runtime_probe.png"
const VIEWPORT_SIZE: Vector2i = Vector2i(1280, 860)
const VALIDATION_VIEWPORT_SIZE: Vector2i = Vector2i(1120, 380)
const ALBEDO_FRAME_SIZE: Vector2 = Vector2(208.0, 288.0)
const SHADOW_FRAME_SIZE: Vector2 = Vector2(76.0, 48.0)
const VISUAL_SCALE: Vector2 = Vector2(0.46, 0.46)
const VISUAL_OFFSET: Vector2 = Vector2(0.0, -16.0)
const ALBEDO_WORLD_ORIGIN_UV: Vector2 = Vector2(0.5, 0.806)
const SHADOW_ANCHOR_PX: Vector2 = Vector2(26.0, 14.0)
const DIRECTIONS: Array[Dictionary] = [
	{"row": 0, "label": "row 0 / NORTH"},
	{"row": 4, "label": "row 4 / EAST"},
	{"row": 8, "label": "row 8 / SOUTH"},
]
const LENGTH_STATES: Array[Dictionary] = [
	{"scale": 1.0, "softness": 0.75, "label": "BAKED LENGTH 1.00x"},
	{"scale": 1.85, "softness": 7.0, "label": "LOW-SUN LENGTH 1.85x"},
]
const CELL_ORIGINS_X: Array[float] = [170.0, 550.0, 930.0]
const CELL_ORIGINS_Y: Array[float] = [220.0, 610.0]
const VALIDATION_ANCHORS_X: Array[float] = [120.0, 470.0, 820.0]
const VALIDATION_ANCHORS_Y: Array[float] = [70.0, 245.0]
const CAST_SCAN_MIN_FORWARD_PX: float = 4.0
const CAST_SCAN_MAX_FORWARD_PX: float = 220.0
const CAST_SCAN_HALF_WIDTH_PX: float = 38.0
const CAST_ALPHA_THRESHOLD: float = 0.035
const CAST_MIN_PIXELS_PER_BIN: int = 2
const CAST_MIN_BASE_LENGTH_PX: float = 28.0
const CAST_MIN_STRETCH_DELTA_PX: float = 20.0
const EPSILON: float = 0.001

var _viewport: SubViewport = null
var _validation_viewport: SubViewport = null
var _failures: Array[String] = []
var _validation_anchors: Dictionary = {}
var _metric_labels: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("probe must run windowed; GPU capture is unavailable in headless mode")
		_finish(1)
		return
	DisplayServer.window_set_size(Vector2i(1280, 860))
	_build_viewport()
	_build_validation_viewport()
	_add_header()

	for state_index: int in LENGTH_STATES.size():
		_add_row_label(state_index)
		for direction_index: int in DIRECTIONS.size():
			_add_probe_cell(state_index, direction_index)

	for _frame: int in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var validation_image: Image = _validation_viewport.get_texture().get_image()
	if validation_image == null or validation_image.is_empty():
		_fail("transparent shadow-only capture returned an empty image")
	else:
		_validate_cast_lengths(validation_image)

	# The visible acceptance PNG includes the measured value in every cell.
	# Give the updated labels two frames before taking the final capture.
	for _frame: int in range(2):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("SubViewport capture returned an empty image")
	else:
		var save_error: Error = image.save_png(OUTPUT_PATH)
		if save_error != OK:
			_fail("save_png failed with error %d" % save_error)

	if _failures.is_empty():
		print("PLAYER_SHADOW_I2_RUNTIME_PROBE_OK")
		print("output=%s" % ProjectSettings.globalize_path(OUTPUT_PATH))
		_finish(0)
		return
	for failure: String in _failures:
		printerr("player_shadow_i2_runtime_probe: %s" % failure)
	_finish(1)


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PlayerShadowI2ProbeViewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	var background := ColorRect.new()
	background.color = Color(0.36, 0.40, 0.30, 1.0)
	background.size = Vector2(VIEWPORT_SIZE)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(background)

	for row_index: int in LENGTH_STATES.size():
		for column_index: int in DIRECTIONS.size():
			var panel := ColorRect.new()
			panel.position = Vector2(30.0 + column_index * 380.0, 102.0 + row_index * 390.0)
			panel.size = Vector2(350.0, 350.0)
			panel.color = Color(0.46, 0.47, 0.35, 0.52) \
				if (row_index + column_index) % 2 == 0 \
				else Color(0.42, 0.44, 0.33, 0.52)
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_viewport.add_child(panel)


func _build_validation_viewport() -> void:
	_validation_viewport = SubViewport.new()
	_validation_viewport.name = "PlayerShadowI2PixelValidationViewport"
	_validation_viewport.size = VALIDATION_VIEWPORT_SIZE
	_validation_viewport.transparent_bg = true
	_validation_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_validation_viewport)

	for state_index: int in LENGTH_STATES.size():
		for direction_index: int in DIRECTIONS.size():
			_add_validation_shadow(state_index, direction_index)


func _add_validation_shadow(state_index: int, direction_index: int) -> void:
	var direction_row: int = int(DIRECTIONS[direction_index]["row"])
	var length_scale: float = float(LENGTH_STATES[state_index]["scale"])
	var softness: float = float(LENGTH_STATES[state_index]["softness"])
	var anchor_global := Vector2(
		VALIDATION_ANCHORS_X[direction_index],
		VALIDATION_ANCHORS_Y[state_index],
	)
	var expected_anchor_local := Vector2(
		(ALBEDO_WORLD_ORIGIN_UV.x - 0.5) * ALBEDO_FRAME_SIZE.x + VISUAL_OFFSET.x,
		(ALBEDO_WORLD_ORIGIN_UV.y - 0.5) * ALBEDO_FRAME_SIZE.y + VISUAL_OFFSET.y,
	) * VISUAL_SCALE

	var container := Node2D.new()
	container.name = "ValidationState%dDirection%d" % [state_index, direction_row]
	container.position = anchor_global - expected_anchor_local
	_validation_viewport.add_child(container)

	# PlayerSunShadow still reads its real Visual peer and real idle atlas. The
	# peer is hidden only after frame sync, leaving a clean transparent capture
	# containing no body, cyan guide, yellow marker, panel, or label pixels.
	var visual := Sprite2D.new()
	visual.name = "Visual"
	visual.texture = IDLE_ALBEDO
	visual.centered = true
	visual.region_enabled = true
	visual.region_filter_clip_enabled = true
	visual.region_rect = Rect2(
		0.0,
		direction_row * ALBEDO_FRAME_SIZE.y,
		ALBEDO_FRAME_SIZE.x,
		ALBEDO_FRAME_SIZE.y,
	)
	visual.offset = VISUAL_OFFSET
	visual.scale = VISUAL_SCALE
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	container.add_child(visual)

	var shadow: PlayerSunShadow = PlayerSunShadowScript.new() as PlayerSunShadow
	shadow.name = "SunShadow"
	shadow.visual_node_path = ^"../Visual"
	_bind_shadow_atlases(shadow)
	container.add_child(shadow)
	shadow.set_physics_process(false)
	shadow._sync_visual_frame()
	visual.visible = false
	shadow.visible = true
	var shadow_material: ShaderMaterial = shadow.material as ShaderMaterial
	shadow_material.set_shader_parameter("shadow_length_scale", length_scale)
	shadow_material.set_shader_parameter("shadow_softness_texels", softness)
	shadow_material.set_shader_parameter("shadow_opacity", 0.82)

	var key: String = _metric_key(state_index, direction_index)
	_validation_anchors[key] = anchor_global


func _add_header() -> void:
	_add_label(
		"PLAYER BAKED SUN SHADOW I2 — live PlayerSunShadow runtime",
		Vector2(30.0, 18.0),
		Vector2(1220.0, 34.0),
		24,
		Color(0.97, 0.94, 0.78),
	)
	_add_label(
		"Yellow cross = shared world-origin anchor   |   cyan = fixed screen-SE axis   |   frame 0",
		Vector2(30.0, 52.0),
		Vector2(1220.0, 28.0),
		16,
		Color(0.83, 0.91, 0.93),
	)
	for column_index: int in DIRECTIONS.size():
		_add_label(
			str(DIRECTIONS[column_index]["label"]),
			Vector2(50.0 + column_index * 380.0, 78.0),
			Vector2(310.0, 26.0),
			17,
			Color(0.98, 0.91, 0.68),
			HORIZONTAL_ALIGNMENT_CENTER,
		)


func _add_row_label(row_index: int) -> void:
	_add_label(
		str(LENGTH_STATES[row_index]["label"]),
		Vector2(42.0, 112.0 + row_index * 390.0),
		Vector2(324.0, 25.0),
		16,
		Color(0.98, 0.96, 0.82),
	)


func _add_probe_cell(state_index: int, direction_index: int) -> void:
	var direction_row: int = int(DIRECTIONS[direction_index]["row"])
	var length_scale: float = float(LENGTH_STATES[state_index]["scale"])
	var softness: float = float(LENGTH_STATES[state_index]["softness"])
	var container := Node2D.new()
	container.name = "State%dDirection%d" % [state_index, direction_row]
	container.position = Vector2(CELL_ORIGINS_X[direction_index], CELL_ORIGINS_Y[state_index])
	_viewport.add_child(container)

	var visual := Sprite2D.new()
	visual.name = "Visual"
	visual.texture = IDLE_ALBEDO
	visual.centered = true
	visual.region_enabled = true
	visual.region_filter_clip_enabled = true
	visual.region_rect = Rect2(
		0.0,
		direction_row * ALBEDO_FRAME_SIZE.y,
		ALBEDO_FRAME_SIZE.x,
		ALBEDO_FRAME_SIZE.y,
	)
	visual.offset = VISUAL_OFFSET
	visual.scale = VISUAL_SCALE
	visual.z_as_relative = false
	visual.z_index = 30
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	container.add_child(visual)

	var shadow: PlayerSunShadow = PlayerSunShadowScript.new() as PlayerSunShadow
	shadow.name = "SunShadow"
	shadow.visual_node_path = ^"../Visual"
	_bind_shadow_atlases(shadow)
	container.add_child(shadow)
	shadow.set_physics_process(false)
	shadow._sync_visual_frame()
	shadow.visible = true
	var shadow_material: ShaderMaterial = shadow.material as ShaderMaterial
	shadow_material.set_shader_parameter("shadow_length_scale", length_scale)
	shadow_material.set_shader_parameter("shadow_softness_texels", softness)
	shadow_material.set_shader_parameter("shadow_opacity", 0.82)

	var expected_anchor_position: Vector2 = visual.transform * Vector2(
		(ALBEDO_WORLD_ORIGIN_UV.x - 0.5) * ALBEDO_FRAME_SIZE.x + visual.offset.x,
		(ALBEDO_WORLD_ORIGIN_UV.y - 0.5) * ALBEDO_FRAME_SIZE.y + visual.offset.y,
	)
	_expect(
		shadow.position.distance_to(expected_anchor_position) <= EPSILON,
		"state %d row %d anchor position %s != %s"
		% [state_index, direction_row, shadow.position, expected_anchor_position],
	)
	_expect(
		shadow.offset.distance_to(SHADOW_FRAME_SIZE * 0.5 - SHADOW_ANCHOR_PX) <= EPSILON,
		"state %d row %d shadow offset is %s" % [state_index, direction_row, shadow.offset],
	)
	_expect(
		shadow.scale.distance_to(visual.scale * 4.0) <= EPSILON,
		"state %d row %d quarter-resolution scale is %s" % [state_index, direction_row, shadow.scale],
	)
	_expect(
		shadow.region_rect == Rect2(
			0.0,
			direction_row * SHADOW_FRAME_SIZE.y,
			SHADOW_FRAME_SIZE.x,
			SHADOW_FRAME_SIZE.y,
		),
		"state %d row %d shadow region is %s" % [state_index, direction_row, shadow.region_rect],
	)
	var material_direction: Vector2 = shadow_material.get_shader_parameter("shadow_direction") as Vector2
	_expect(
		material_direction.distance_to(WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION) <= EPSILON,
		"state %d row %d shadow direction drifted to %s"
		% [state_index, direction_row, material_direction],
	)

	_add_direction_guide(container, expected_anchor_position)
	_add_anchor_cross(container, expected_anchor_position)
	_add_metric_label(container, state_index, direction_index)
	_add_cell_footer(container, direction_row, length_scale)


func _bind_shadow_atlases(shadow: PlayerSunShadow) -> void:
	shadow.idle_albedo_texture = IDLE_ALBEDO
	shadow.run_forward_albedo_texture = RUN_FORWARD_ALBEDO
	shadow.run_backward_albedo_texture = RUN_BACKWARD_ALBEDO
	shadow.strafe_left_albedo_texture = STRAFE_LEFT_ALBEDO
	shadow.strafe_right_albedo_texture = STRAFE_RIGHT_ALBEDO
	shadow.idle_shadow_texture = IDLE_SHADOW
	shadow.run_forward_shadow_texture = RUN_FORWARD_SHADOW
	shadow.run_backward_shadow_texture = RUN_BACKWARD_SHADOW
	shadow.strafe_left_shadow_texture = STRAFE_LEFT_SHADOW
	shadow.strafe_right_shadow_texture = STRAFE_RIGHT_SHADOW


func _metric_key(state_index: int, direction_index: int) -> String:
	return "%d:%d" % [state_index, direction_index]


func _add_metric_label(container: Node2D, state_index: int, direction_index: int) -> void:
	var label := Label.new()
	label.position = Vector2(-135.0, 119.0)
	label.size = Vector2(270.0, 22.0)
	label.text = "pixel cast: measuring..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.72, 0.90, 0.76))
	label.add_theme_color_override("font_shadow_color", Color(0.08, 0.07, 0.05, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 50
	container.add_child(label)
	_metric_labels[_metric_key(state_index, direction_index)] = label


func _validate_cast_lengths(image: Image) -> void:
	var measurements: Dictionary = {}
	for state_index: int in LENGTH_STATES.size():
		for direction_index: int in DIRECTIONS.size():
			var key: String = _metric_key(state_index, direction_index)
			var anchor: Vector2 = _validation_anchors.get(key, Vector2.INF) as Vector2
			if not anchor.is_finite():
				_fail("missing validation anchor for %s" % key)
				continue
			measurements[key] = _measure_cast_along_fixed_axis(image, anchor)

	for direction_index: int in DIRECTIONS.size():
		var direction_row: int = int(DIRECTIONS[direction_index]["row"])
		var base_key: String = _metric_key(0, direction_index)
		var stretched_key: String = _metric_key(1, direction_index)
		if not measurements.has(base_key) or not measurements.has(stretched_key):
			continue
		var base: Dictionary = measurements[base_key] as Dictionary
		var stretched: Dictionary = measurements[stretched_key] as Dictionary
		var base_length: float = float(base["length_px"])
		var stretched_length: float = float(stretched["length_px"])
		var delta: float = stretched_length - base_length
		var pair_passes: bool = (
			base_length >= CAST_MIN_BASE_LENGTH_PX
			and delta >= CAST_MIN_STRETCH_DELTA_PX
		)

		print(
			(
				"PLAYER_SHADOW_I2_CAST row=%02d base_px=%.1f stretched_px=%.1f delta_px=%.1f "
				+ "base_samples=%d stretched_samples=%d base_peak_alpha=%.3f stretched_peak_alpha=%.3f"
			) % [
				direction_row,
				base_length,
				stretched_length,
				delta,
				int(base["sample_pixels"]),
				int(stretched["sample_pixels"]),
				float(base["peak_alpha"]),
				float(stretched["peak_alpha"]),
			]
		)
		_expect(
			base_length >= CAST_MIN_BASE_LENGTH_PX,
			"row %d shadow-only base cast is %.1f px; expected at least %.1f px"
			% [direction_row, base_length, CAST_MIN_BASE_LENGTH_PX],
		)
		_expect(
			delta >= CAST_MIN_STRETCH_DELTA_PX,
			"row %d shader stretch/fallback check failed: %.1f -> %.1f px (delta %.1f, need >= %.1f)"
			% [
				direction_row,
				base_length,
				stretched_length,
				delta,
				CAST_MIN_STRETCH_DELTA_PX,
			],
		)
		_set_metric_label(0, direction_index, base_length, delta, pair_passes)
		_set_metric_label(1, direction_index, stretched_length, delta, pair_passes)


func _measure_cast_along_fixed_axis(image: Image, anchor: Vector2) -> Dictionary:
	var direction: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION.normalized()
	var transverse := Vector2(-direction.y, direction.x)
	var corners: Array[Vector2] = [
		anchor + direction * CAST_SCAN_MIN_FORWARD_PX + transverse * CAST_SCAN_HALF_WIDTH_PX,
		anchor + direction * CAST_SCAN_MIN_FORWARD_PX - transverse * CAST_SCAN_HALF_WIDTH_PX,
		anchor + direction * CAST_SCAN_MAX_FORWARD_PX + transverse * CAST_SCAN_HALF_WIDTH_PX,
		anchor + direction * CAST_SCAN_MAX_FORWARD_PX - transverse * CAST_SCAN_HALF_WIDTH_PX,
	]
	var min_x: float = corners[0].x
	var max_x: float = corners[0].x
	var min_y: float = corners[0].y
	var max_y: float = corners[0].y
	for corner: Vector2 in corners:
		min_x = minf(min_x, corner.x)
		max_x = maxf(max_x, corner.x)
		min_y = minf(min_y, corner.y)
		max_y = maxf(max_y, corner.y)

	var scan_min_x: int = clampi(floori(min_x) - 1, 0, image.get_width() - 1)
	var scan_max_x: int = clampi(ceili(max_x) + 1, 0, image.get_width() - 1)
	var scan_min_y: int = clampi(floori(min_y) - 1, 0, image.get_height() - 1)
	var scan_max_y: int = clampi(ceili(max_y) + 1, 0, image.get_height() - 1)
	var bin_counts := PackedInt32Array()
	bin_counts.resize(ceili(CAST_SCAN_MAX_FORWARD_PX) + 1)
	var peak_alpha: float = 0.0
	var sample_pixels: int = 0

	for y: int in range(scan_min_y, scan_max_y + 1):
		for x: int in range(scan_min_x, scan_max_x + 1):
			var sample: Color = image.get_pixel(x, y)
			if sample.a < CAST_ALPHA_THRESHOLD:
				continue
			var from_anchor := Vector2(float(x) + 0.5, float(y) + 0.5) - anchor
			var forward: float = from_anchor.dot(direction)
			if forward < CAST_SCAN_MIN_FORWARD_PX or forward > CAST_SCAN_MAX_FORWARD_PX:
				continue
			if absf(from_anchor.dot(transverse)) > CAST_SCAN_HALF_WIDTH_PX:
				continue
			var forward_bin: int = clampi(
				floori(forward),
				0,
				bin_counts.size() - 1,
			)
			bin_counts[forward_bin] += 1
			peak_alpha = maxf(peak_alpha, sample.a)
			sample_pixels += 1

	var cast_length: float = -1.0
	for forward_bin: int in range(bin_counts.size()):
		if bin_counts[forward_bin] >= CAST_MIN_PIXELS_PER_BIN:
			cast_length = float(forward_bin + 1)
	return {
		"length_px": cast_length,
		"sample_pixels": sample_pixels,
		"peak_alpha": peak_alpha,
	}


func _set_metric_label(
	state_index: int,
	direction_index: int,
	length_px: float,
	delta_px: float,
	pair_passes: bool,
) -> void:
	var key: String = _metric_key(state_index, direction_index)
	var label_variant: Variant = _metric_labels.get(key)
	if not (label_variant is Label):
		_fail("missing visible metric label for %s" % key)
		return
	var label: Label = label_variant as Label
	label.text = "pixel cast=%.0f px   pair Δ=%.0f px" % [length_px, delta_px]
	label.add_theme_color_override(
		"font_color",
		Color(0.66, 0.94, 0.71) if pair_passes else Color(1.0, 0.45, 0.38),
	)


func _add_direction_guide(container: Node2D, anchor_position: Vector2) -> void:
	var direction: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION.normalized()
	var guide := Line2D.new()
	guide.name = "FixedSouthEastGuide"
	guide.position = anchor_position
	guide.points = PackedVector2Array([Vector2.ZERO, direction * 105.0])
	guide.width = 1.5
	guide.default_color = Color(0.20, 0.88, 0.96, 0.62)
	guide.z_as_relative = false
	guide.z_index = 25
	container.add_child(guide)

	var arrow_head := Line2D.new()
	arrow_head.position = anchor_position + direction * 105.0
	var transverse := Vector2(-direction.y, direction.x)
	arrow_head.points = PackedVector2Array([
		direction * -13.0 + transverse * 6.0,
		Vector2.ZERO,
		direction * -13.0 - transverse * 6.0,
	])
	arrow_head.width = 1.5
	arrow_head.default_color = Color(0.20, 0.88, 0.96, 0.62)
	arrow_head.z_as_relative = false
	arrow_head.z_index = 25
	container.add_child(arrow_head)


func _add_anchor_cross(container: Node2D, anchor_position: Vector2) -> void:
	for points: PackedVector2Array in [
		PackedVector2Array([Vector2(-8.0, 0.0), Vector2(8.0, 0.0)]),
		PackedVector2Array([Vector2(0.0, -8.0), Vector2(0.0, 8.0)]),
	]:
		var line := Line2D.new()
		line.position = anchor_position
		line.points = points
		line.width = 2.0
		line.default_color = Color(1.0, 0.84, 0.16, 0.96)
		line.z_as_relative = false
		line.z_index = 42
		container.add_child(line)


func _add_cell_footer(container: Node2D, direction_row: int, length_scale: float) -> void:
	var label := Label.new()
	label.position = Vector2(-135.0, 145.0)
	label.size = Vector2(270.0, 24.0)
	label.text = "dir=%02d  frame=00  stretch=%.2f" % [direction_row, length_scale]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.94, 0.93, 0.80))
	label.add_theme_color_override("font_shadow_color", Color(0.08, 0.07, 0.05, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 50
	container.add_child(label)


func _add_label(
		text_value: String,
		position_value: Vector2,
		size_value: Vector2,
		font_size: int,
		font_color: Color,
		horizontal_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.size = size_value
	label.horizontal_alignment = horizontal_alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_shadow_color", Color(0.07, 0.06, 0.04, 0.90))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 80
	_viewport.add_child(label)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish(exit_code: int) -> void:
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _validation_viewport != null and is_instance_valid(_validation_viewport):
		_validation_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	quit(exit_code)
