extends SceneTree

const MountainContourStyle = preload("res://core/systems/world/mountain_contour_style.gd")
const MountainContourStyleRegistry = preload("res://core/systems/world/mountain_contour_style_registry.gd")
const MountainContourVisualLayer = preload("res://core/systems/world/mountain_contour_visual_layer.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const OUTPUT_DIR: String = "res://artifacts/mountain_contour_visual_probe"
const SCREENSHOT_PATH: String = "%s/mountain_contour_visual_probe.png" % OUTPUT_DIR
const VIEWPORT_SIZE: Vector2i = Vector2i(1280, 960)
const BACKGROUND_COLOR: Color = Color(0.055, 0.064, 0.05, 1.0)

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = VIEWPORT_SIZE
	_prepare_output_dir()
	_assert_static_contract()

	var registry := MountainContourStyleRegistry.new()
	_assert(registry.load_default_styles(), "Probe must load the canonical mountain contour style.")
	var style: MountainContourStyle = registry.require_style(StringName("mountain"))
	_assert(style != null, "Probe requires the canonical mountain style.")
	if style == null:
		quit(1)
		return

	var result: Dictionary = _build_runtime_result(style)
	_assert(bool(result.get("ready", false)), "Native production contour result must be ready for visual probe.")
	_assert_surface_payload(result, "visual_top")
	_assert_surface_payload(result, "visual_face")
	_assert_surface_payload(result, "visual_rim")
	_assert_surface_payload(result, "visual_outline")
	_assert_bottom_outline_is_lower_contact(result)
	_assert_materials_are_distinct(style)

	var background := ColorRect.new()
	background.color = BACKGROUND_COLOR
	background.size = Vector2(VIEWPORT_SIZE)
	root.add_child(background)

	var scene_root := Node2D.new()
	scene_root.name = "MountainContourVisualProbe"
	root.add_child(scene_root)
	current_scene = scene_root

	var layer := MountainContourVisualLayer.new()
	layer.name = "MountainContourVisualLayer"
	layer.position = Vector2(96.0, 64.0)
	scene_root.add_child(layer)
	layer.configure(Vector2i.ZERO, style)
	_assert(layer.apply_runtime_result(result), "Visual layer must accept the native runtime result.")

	await _settle_frames(12)
	var layer_stats: Dictionary = layer.get_debug_stats()
	_assert(bool(layer_stats.get("material_ready", false)), "Visual layer materials must be ready.")
	_assert(int(layer_stats.get("top_vertex_count", 0)) > 0, "Visual layer must render top vertices.")
	_assert(int(layer_stats.get("face_vertex_count", 0)) > 0, "Visual layer must render face vertices.")
	_assert(int(layer_stats.get("rim_vertex_count", 0)) > 0, "Visual layer must render rim vertices.")
	_assert(int(layer_stats.get("outline_vertex_count", 0)) > 0, "Visual layer must render bottom outline vertices.")
	_assert(int(layer_stats.get("total_triangle_count", 0)) > 0, "Visual layer must render triangles.")

	_capture_viewport(SCREENSHOT_PATH)
	var screenshot_stats: Dictionary = _sample_image_stats(SCREENSHOT_PATH)
	_assert(bool(screenshot_stats.get("loaded", false)), "Probe screenshot must be readable.")
	_assert(int(screenshot_stats.get("non_background_samples", 0)) > 64, "Probe screenshot must contain rendered contour pixels.")
	_assert(int(screenshot_stats.get("cyan_debug_samples", 0)) == 0, "Probe must not render cyan debug contour output.")

	var report := {
		"ready": not _failed,
		"screenshot_path": SCREENSHOT_PATH,
		"result": {
			"solid_sample_count": int(result.get("solid_sample_count", 0)),
			"boundary_edge_count": int(result.get("boundary_edge_count", 0)),
			"compute_time_usec": int(result.get("compute_time_usec", 0)),
		},
		"layer": layer_stats,
		"screenshot": screenshot_stats,
	}
	print(JSON.stringify(report, "\t"))
	quit(1 if _failed else 0)

func _assert_static_contract() -> void:
	_assert(FileAccess.file_exists("res://core/systems/world/mountain_contour_visual_layer.gd"), "MountainContourVisualLayer script must exist.")
	_assert(FileAccess.file_exists("res://assets/shaders/mountain_contour_runtime.gdshader"), "Mountain contour runtime shader must exist.")
	var layer_source: String = FileAccess.get_file_as_string("res://core/systems/world/mountain_contour_visual_layer.gd")
	var shader_source: String = FileAccess.get_file_as_string("res://assets/shaders/mountain_contour_runtime.gdshader")
	_assert(layer_source.contains("MeshInstance2D"), "Visual layer must use mesh instances, not TileMap cells.")
	_assert(layer_source.contains("ArrayMesh"), "Visual layer must build ArrayMesh surfaces from runtime result arrays.")
	_assert(layer_source.contains("ShaderMaterial"), "Visual layer must bind shader materials.")
	_assert(not layer_source.contains("TileMapLayer"), "Visual layer must not render square TileMap cells.")
	_assert(not layer_source.contains("ImageTexture.create_from_image"), "Visual layer must not create per-chunk runtime textures.")
	_assert(shader_source.contains("top_albedo_tex"), "Shader must expose top albedo texture uniform.")
	_assert(shader_source.contains("face_albedo_tex"), "Shader must expose face albedo texture uniform.")
	_assert(shader_source.contains("base_albedo_tex"), "Shader must expose base albedo texture uniform.")
	_assert(shader_source.contains("top_normal_tex"), "Shader must expose top normal texture uniform.")
	_assert(shader_source.contains("face_normal_tex"), "Shader must expose face normal texture uniform.")
	_assert(shader_source.contains("edge_profile_lut"), "Shader must expose edge profile LUT uniform.")
	_assert(shader_source.contains("height_profile_lut"), "Shader must expose height profile LUT uniform.")
	_assert(shader_source.contains("NORMAL_MAP"), "Shader must write a blended normal map.")
	_assert(not shader_source.contains("mask_rgba8"), "Shader must not consume a generated mask texture.")
	_assert(not shader_source.contains("height_r16"), "Shader must not consume a generated height texture.")
	_assert(not shader_source.contains("normal_rgba8"), "Shader must not consume a generated normal texture.")
	_assert(_source_excludes_live_cutover(), "Task 4 probe must not wire MountainContourVisualLayer into live world rendering.")

func _source_excludes_live_cutover() -> bool:
	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	var world_streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	return not chunk_view_source.contains("MountainContourVisualLayer") \
		and not chunk_view_source.contains("mountain_contour_visual_layer") \
		and not world_streamer_source.contains("MountainContourVisualLayer") \
		and not world_streamer_source.contains("mountain_contour_visual_layer")

func _build_runtime_result(style: MountainContourStyle) -> Dictionary:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for mountain contour visual probe.")
	if world_core == null:
		return {}
	_assert(world_core.has_method("build_mountain_contour_runtime"), "WorldCore must expose build_mountain_contour_runtime().")
	if not world_core.has_method("build_mountain_contour_runtime"):
		return {}
	var result_variant: Variant = world_core.call(
		"build_mountain_contour_runtime",
		_build_probe_halo(),
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		_style_params(style)
	)
	_assert(result_variant is Dictionary, "build_mountain_contour_runtime() must return Dictionary.")
	if result_variant is Dictionary:
		return result_variant as Dictionary
	return {}

func _style_params(style: MountainContourStyle) -> Dictionary:
	return {
		"south_height_px": style.south_height_px,
		"side_height_px": style.side_height_px,
		"rim_width_px": style.rim_width_px,
		"mountain_outline_enabled": style.mountain_outline_enabled,
		"mountain_outline_width_px": style.mountain_outline_width_px,
	}

func _build_probe_halo() -> PackedByteArray:
	var side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(side * side)
	for index: int in solid_halo.size():
		solid_halo[index] = 0
	for y: int in range(3, 11):
		for x: int in range(3, 13):
			if (x == 7 and y >= 6 and y <= 8) or (x == 11 and y == 4):
				continue
			_set_local_cell(solid_halo, x, y, 1)
	for y: int in range(5, 9):
		_set_local_cell(solid_halo, 2, y, 1)
	for x: int in range(5, 10):
		_set_local_cell(solid_halo, x, 11, 1)
	return solid_halo

func _set_local_cell(solid_halo: PackedByteArray, local_x: int, local_y: int, value: int) -> void:
	var side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	solid_halo[(local_y + 1) * side + local_x + 1] = value

func _assert_surface_payload(result: Dictionary, prefix: String) -> void:
	var vertices: PackedVector2Array = result.get("%s_vertices" % [prefix], PackedVector2Array()) as PackedVector2Array
	var indices: PackedInt32Array = result.get("%s_indices" % [prefix], PackedInt32Array()) as PackedInt32Array
	var attributes: PackedFloat32Array = result.get("%s_attributes" % [prefix], PackedFloat32Array()) as PackedFloat32Array
	_assert(vertices.size() > 0, "%s must have vertices." % [prefix])
	_assert(indices.size() >= 3 and indices.size() % 3 == 0, "%s must have triangle indices." % [prefix])
	_assert(attributes.size() == vertices.size() * 6, "%s must have six custom floats per vertex." % [prefix])

func _assert_bottom_outline_is_lower_contact(result: Dictionary) -> void:
	var outline_indices: PackedInt32Array = result.get("visual_outline_indices", PackedInt32Array()) as PackedInt32Array
	var rim_indices: PackedInt32Array = result.get("visual_rim_indices", PackedInt32Array()) as PackedInt32Array
	_assert(outline_indices.size() > 0, "Bottom outline must be present in the probe fixture.")
	_assert(outline_indices.size() < rim_indices.size(), "Bottom outline must cover fewer edges than the full rim.")

func _assert_materials_are_distinct(style: MountainContourStyle) -> void:
	_assert(style.top_albedo != style.face_albedo, "Top and face albedo textures must be distinct resources.")
	_assert(style.top_normal != style.face_normal, "Top and face normal textures must be distinct resources.")
	_assert(style.top_albedo is Texture2D, "Top albedo must be loaded as Texture2D.")
	_assert(style.face_albedo is Texture2D, "Face albedo must be loaded as Texture2D.")
	_assert(style.top_normal is Texture2D, "Top normal must be loaded as Texture2D.")
	_assert(style.face_normal is Texture2D, "Face normal must be loaded as Texture2D.")

func _prepare_output_dir() -> void:
	var absolute_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR).replace("\\", "/")
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK:
		_fail("Failed to create probe output directory %s: %d" % [absolute_dir, err])

func _capture_viewport(path: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null:
		_fail("Viewport image is null.")
		return
	var absolute_path: String = ProjectSettings.globalize_path(path).replace("\\", "/")
	var png_bytes: PackedByteArray = image.save_png_to_buffer()
	if png_bytes.is_empty():
		_fail("Failed to encode viewport capture %s." % [absolute_path])
		return
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_fail("Failed to open viewport capture %s: %d" % [absolute_path, FileAccess.get_open_error()])
		return
	file.store_buffer(png_bytes)
	file.close()

func _sample_image_stats(path: String) -> Dictionary:
	var image := Image.new()
	var absolute_path: String = ProjectSettings.globalize_path(path).replace("\\", "/")
	var err: Error = image.load(absolute_path)
	if err != OK:
		return {"loaded": false, "error": err}
	var sample_count: int = 0
	var non_background_samples: int = 0
	var cyan_debug_samples: int = 0
	for y: int in range(0, image.get_height(), 8):
		for x: int in range(0, image.get_width(), 8):
			var color: Color = image.get_pixel(x, y)
			sample_count += 1
			if color.g > 0.55 and color.b > 0.55 and color.r < 0.2:
				cyan_debug_samples += 1
			if absf(color.r - BACKGROUND_COLOR.r) > 0.035 \
					or absf(color.g - BACKGROUND_COLOR.g) > 0.035 \
					or absf(color.b - BACKGROUND_COLOR.b) > 0.035:
				non_background_samples += 1
	return {
		"loaded": true,
		"width": image.get_width(),
		"height": image.get_height(),
		"samples": sample_count,
		"non_background_samples": non_background_samples,
		"cyan_debug_samples": cyan_debug_samples,
	}

func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)

func _fail(message: String) -> void:
	push_error(message)
	_failed = true
