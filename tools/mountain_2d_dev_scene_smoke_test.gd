extends SceneTree

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_2d_dev_scene.tscn"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Mountain 2D dev scene must load.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	_assert(scene.has_method("get_debug_snapshot"), "Mountain 2D dev scene must expose debug snapshot.")
	_assert(scene.has_method("apply_raster_preset"), "Mountain 2D dev scene must expose raster preset apply.")
	_assert(scene.has_method("save_raster_preset"), "Mountain 2D dev scene must expose raster preset save.")
	_assert(scene.has_method("load_raster_preset"), "Mountain 2D dev scene must expose raster preset load.")
	_assert(scene.has_method("reset_raster_preset"), "Mountain 2D dev scene must expose raster preset reset.")
	var has_normal_preview_toggle: bool = scene.has_method("set_raster_normal_preview_enabled")
	_assert(has_normal_preview_toggle, "Mountain 2D dev scene must expose normal preview toggle.")
	var has_light_preview_toggle: bool = scene.has_method("set_raster_light_preview_enabled")
	_assert(has_light_preview_toggle, "Mountain 2D dev scene must expose light preview toggle.")
	var snapshot: Dictionary = scene.call("get_debug_snapshot") as Dictionary
	_assert(bool(snapshot.get("ready", false)), "Mountain 2D dev scene must become ready.")
	_assert(int(snapshot.get("displayed_chunk_count", 0)) > 0, "Mountain 2D dev scene must display chunk views.")
	_assert(int(snapshot.get("displayed_chunks_with_mountain", 0)) > 0, "Mountain 2D dev scene must display at least one mountain chunk.")
	_assert(int(snapshot.get("displayed_mountain_cells", 0)) > 0, "Mountain 2D dev scene must display mountain cells.")
	_assert(bool(snapshot.get("plateau_ready", false)), "Mountain 2D dev scene must build the plateau layer.")
	_assert(int(snapshot.get("plateau_mountain_tiles", 0)) > 0, "Plateau layer must consume mountain tiles.")
	_assert(int(snapshot.get("plateau_edge_tiles", 0)) > 0, "Plateau layer must identify edge tiles.")
	_assert(int(snapshot.get("plateau_connector_count", 0)) > 0, "Plateau layer must build organic connectors.")
	_assert(int(snapshot.get("plateau_facade_edges", 0)) > 0, "Plateau layer must build visible facade edges.")
	_assert(int(snapshot.get("plateau_rim_edges", 0)) > 0, "Plateau layer must build a separating rim.")
	var plateau: Dictionary = snapshot.get("plateau", {}) as Dictionary
	_assert(int(plateau.get("contour_count", 0)) > 0, "Plateau layer must build smoothed contour loops.")
	_assert(int(plateau.get("fill_contour_count", 0)) > 0, "Plateau layer must build filled top contours.")
	_assert(bool(snapshot.get("plateau_top_texture_loaded", false)), "Plateau layer must load the top texture.")
	_assert(bool(snapshot.get("plateau_face_texture_loaded", false)), "Plateau layer must load the face texture.")
	_assert(bool(snapshot.get("raster_ready", false)), "Mountain 2D dev scene must build the raster SDF layer.")
	_assert(bool(snapshot.get("raster_visible", false)), "Raster SDF layer must be visible by default.")
	_assert(int(snapshot.get("raster_mountain_tiles", 0)) > 0, "Raster SDF layer must consume mountain tiles.")
	_assert(int(snapshot.get("raster_top_pixels", 0)) > 0, "Raster SDF layer must draw top pixels.")
	_assert(int(snapshot.get("raster_face_pixels", 0)) > 0, "Raster SDF layer must draw facade pixels.")
	_assert(int(snapshot.get("raster_rim_pixels", 0)) > 0, "Raster SDF layer must draw separating rim pixels.")
	_assert(int(snapshot.get("raster_image_width", 0)) > 0, "Raster SDF layer must build a non-empty image width.")
	_assert(int(snapshot.get("raster_image_height", 0)) > 0, "Raster SDF layer must build a non-empty image height.")
	_assert(bool(snapshot.get("raster_normal_ready", false)), "Raster SDF layer must build a normal map.")
	_assert(int(snapshot.get("raster_normal_image_width", 0)) == int(snapshot.get("raster_image_width", 0)), "Raster normal map width must match albedo.")
	_assert(int(snapshot.get("raster_normal_image_height", 0)) == int(snapshot.get("raster_image_height", 0)), "Raster normal map height must match albedo.")
	_assert(int(snapshot.get("raster_normal_pixel_count", 0)) > 0, "Raster normal map must contain mountain normal pixels.")
	var raster: Dictionary = snapshot.get("raster", {}) as Dictionary
	_assert(float(raster.get("sample_step_px", 999.0)) <= 1.0, "Raster SDF layer must render at 1:1 pixel resolution for close visual review.")
	_assert(bool(raster.get("native", false)), "Raster SDF layer must use the native plateau raster builder.")
	_assert(str(raster.get("shape_field_mode", "")) == "center_blob_domain_warp", "Raster SDF layer must use center-blob organic shape mode.")
	_assert(float(raster.get("shape_blob_radius_px", 0.0)) > 32.0, "Raster SDF layer must build shape from half-tile center blobs.")
	_assert(raster.has("shape_domain_warp_px"), "Raster SDF layer must expose domain warp diagnostics.")
	_assert(raster.has("shape_lobe_px"), "Raster SDF layer must expose organic lobe diagnostics.")
	_assert(str(raster.get("normal_field_mode", "")) == "heightfield_world_noise", "Raster SDF layer must use world-space heightfield normals.")
	_assert(str(raster.get("normal_detail_mode", "")) == "organic_fbm_broad_strata", "Raster normal map must use non-repeating organic detail.")
	_assert(float(raster.get("normal_top_detail_strength", 0.0)) > 0.0, "Raster normal map must expose top detail strength.")
	_assert(float(raster.get("normal_face_detail_strength", 0.0)) > 0.0, "Raster normal map must expose face detail strength.")
	_assert(bool(raster.get("lit_texture_ready", false)), "Raster SDF layer must expose a lit CanvasTexture.")
	_assert(bool(raster.get("lit_split_surface_ready", false)), "Raster SDF layer must split ground and mountain lit surfaces.")
	_assert(bool(raster.get("ground_lit_texture_ready", false)), "Raster SDF layer must expose a lit ground CanvasTexture.")
	_assert(bool(raster.get("mountain_lit_texture_ready", false)), "Raster SDF layer must expose a lit mountain CanvasTexture.")
	_assert(int(raster.get("ground_normal_pixel_count", 0)) > 0, "Raster SDF layer must add a non-flat ground normal map.")
	_assert(bool(raster.get("light_occluder_ready", false)), "Raster SDF layer must expose a dev light occluder contour.")
	_assert(int(raster.get("light_occluder_point_count", 0)) >= 8, "Raster SDF light occluder contour must contain enough points.")
	if has_normal_preview_toggle:
		scene.call("set_raster_normal_preview_enabled", true)
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		_assert(bool(snapshot.get("raster_normal_preview", false)), "Mountain 2D dev scene must switch to normal preview.")
		scene.call("set_raster_normal_preview_enabled", false)
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		_assert(not bool(snapshot.get("raster_normal_preview", true)), "Mountain 2D dev scene must switch back to albedo preview.")
	if has_light_preview_toggle:
		scene.call("set_raster_light_preview_enabled", true)
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		_assert(bool(snapshot.get("raster_light_preview", false)), "Mountain 2D dev scene must switch to lighting preview.")
		_assert(bool(snapshot.get("raster_light_node_ready", false)), "Mountain 2D dev scene must create a Light2D probe.")
		_assert(bool(snapshot.get("raster_light_split_surface_ready", false)), "Mountain 2D dev scene must light split ground and mountain surfaces.")
		_assert(bool(snapshot.get("raster_light_occluder_ready", false)), "Mountain 2D dev scene must create a mountain silhouette light occluder.")
		var light: Dictionary = snapshot.get("raster_light", {}) as Dictionary
		_assert(str(light.get("kind", "")) == "directional_sun", "Mountain 2D dev scene light mode must use directional sun.")
		_assert(bool(light.get("shadow_enabled", false)), "Mountain 2D dev scene sun preview must cast shadows.")
		_assert(not bool(light.get("uses_light_texture", true)), "Mountain 2D dev scene sun preview must not be a circular texture light.")
		scene.call("set_raster_light_preview_enabled", false)
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		_assert(not bool(snapshot.get("raster_light_preview", true)), "Mountain 2D dev scene must switch back from lighting preview.")
	_assert(bool(snapshot.get("tuning_panel_ready", false)), "Mountain 2D dev scene must build the tuning panel.")
	_assert(str(snapshot.get("tuning_panel_locale", "")) == "ru", "Mountain 2D tuning panel must expose Russian labels.")
	_assert(bool(snapshot.get("tuning_has_ru_labels", false)), "Mountain 2D tuning panel must keep readable Russian labels.")
	_assert(float(snapshot.get("tuning_panel_width_px", 0.0)) >= 600.0, "Mountain 2D tuning panel must be wide enough for usable sliders.")
	_assert(int(snapshot.get("tuning_slider_count", 0)) >= 28, "Mountain 2D tuning panel must expose all raster sliders.")
	_assert(
		int(snapshot.get("tuning_numeric_input_count", 0)) == int(snapshot.get("tuning_slider_count", 0)),
		"Mountain 2D tuning panel must expose numeric inputs next to sliders."
	)
	_assert(str(snapshot.get("raster_preset_path", "")).ends_with("mountain_2d_raster_preset.json"), "Mountain 2D dev scene must expose the raster preset path.")
	var preset: Dictionary = snapshot.get("raster_preset", {}) as Dictionary
	_assert(preset.has("top_texture_scale"), "Raster preset must expose top texture scale.")
	_assert(preset.has("face_texture_scale"), "Raster preset must expose face texture scale.")
	_assert(preset.has("round_blur_radius_px"), "Raster preset must expose shape rounding radius.")
	_assert(preset.has("shape_blob_radius_px"), "Raster preset must expose half-tile shape radius.")
	_assert(preset.has("shape_domain_warp_px"), "Raster preset must expose organic domain warp strength.")
	_assert(preset.has("shape_domain_warp_scale_px"), "Raster preset must expose organic domain warp scale.")
	_assert(preset.has("shape_lobe_px"), "Raster preset must expose random contour lobe strength.")
	_assert(preset.has("shape_lobe_scale_px"), "Raster preset must expose random contour lobe scale.")
	_assert(preset.has("normal_strength"), "Raster preset must expose normal strength.")
	_assert(preset.has("normal_top_detail_strength"), "Raster preset must expose top normal detail strength.")
	_assert(preset.has("normal_face_detail_strength"), "Raster preset must expose face normal detail strength.")
	_assert(preset.has("normal_detail_scale_px"), "Raster preset must expose normal detail scale.")
	_assert(preset.has("normal_macro_scale_px"), "Raster preset must expose normal macro scale.")
	_assert(preset.has("edge_warp_px"), "Raster preset must expose edge warp.")
	_assert(preset.has("facade_height_px"), "Raster preset must expose facade height.")
	scene.queue_free()
	await process_frame
	if _failed:
		quit(1)
		return
	print("mountain_2d_dev_scene_smoke_test: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
