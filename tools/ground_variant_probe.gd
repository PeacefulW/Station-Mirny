extends SceneTree

# Ground look variant probe: renders the SAME deterministic spawn plains with
# several distinct ground "art directions" (grass / biofield / rock balance),
# at close, mid and far zoom, then assembles before|after|after... comparison
# panels so art direction can be picked. Each frame carries an on-screen label
# baked into the capture. Pure cosmetic: only ground_hybrid material uniforms
# are overridden live (no chunk rebuild, no streaming churn).
#
# Windowed (viewport capture needs a GPU). Run:
#   <godot> --path . -s tools/ground_variant_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/ground_variant_probe"
const CAPTURE_HOUR: float = 12.0
const ZOOM_LEVELS: Array[float] = [1.0, 0.45, 0.22]
const MAX_SETTLE_FRAMES: int = 600
const PANEL_DIVIDER_PX: int = 6
const PLAINS_GROUND_TERRAIN_ID: int = 0

# Shader uniform keys shared with TerrainMaterialSet.sampling_params. Every
# variant sets the FULL set so there is no leakage between captures.
const TUNED_KEYS: Array[String] = [
	"grass_coverage",
	"grass_field_scale_px",
	"grass_dissolve",
	"orange_coverage",
	"orange_field_scale_px",
	"rock_coverage",
	"rock_field_scale_px",
	"soil_field_scale_px",
	"macro_drift_strength",
]

# First entry mirrors the current plains_ground_material_set.tres (the "before").
const VARIANTS: Array[Dictionary] = [
	{
		"name": "v0_current",
		"title": "СЕЙЧАС (baseline)",
		"grass_coverage": 0.38,
		"grass_field_scale_px": 1050.0,
		"grass_dissolve": 0.22,
		"orange_coverage": 0.16,
		"orange_field_scale_px": 820.0,
		"rock_coverage": 0.26,
		"rock_field_scale_px": 1900.0,
		"soil_field_scale_px": 1500.0,
		"macro_drift_strength": 0.08,
	},
	{
		"name": "v1_meadow",
		"title": "A: ЛУГ (густая трава)",
		"grass_coverage": 0.66,
		"grass_field_scale_px": 1300.0,
		"grass_dissolve": 0.26,
		"orange_coverage": 0.10,
		"orange_field_scale_px": 900.0,
		"rock_coverage": 0.10,
		"rock_field_scale_px": 2200.0,
		"soil_field_scale_px": 1500.0,
		"macro_drift_strength": 0.07,
	},
	{
		"name": "v2_steppe",
		"title": "B: СТЕПЬ (сухо, камни)",
		"grass_coverage": 0.20,
		"grass_field_scale_px": 950.0,
		"grass_dissolve": 0.20,
		"orange_coverage": 0.06,
		"orange_field_scale_px": 820.0,
		"rock_coverage": 0.42,
		"rock_field_scale_px": 1500.0,
		"soil_field_scale_px": 1400.0,
		"macro_drift_strength": 0.10,
	},
	{
		"name": "v3_biofield",
		"title": "C: БИОПОЛЕ (оранжевое)",
		"grass_coverage": 0.34,
		"grass_field_scale_px": 1100.0,
		"grass_dissolve": 0.24,
		"orange_coverage": 0.40,
		"orange_field_scale_px": 680.0,
		"rock_coverage": 0.14,
		"rock_field_scale_px": 2000.0,
		"soil_field_scale_px": 1500.0,
		"macro_drift_strength": 0.09,
	},
	{
		"name": "v4_mosaic",
		"title": "D: МОЗАИКА (пёстро)",
		"grass_coverage": 0.46,
		"grass_field_scale_px": 720.0,
		"grass_dissolve": 0.30,
		"orange_coverage": 0.22,
		"orange_field_scale_px": 560.0,
		"rock_coverage": 0.22,
		"rock_field_scale_px": 1200.0,
		"soil_field_scale_px": 1000.0,
		"macro_drift_strength": 0.12,
	},
]

var _streamer: Node = null
var _label: Label = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ground_variant_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	_streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		mountain,
		bounds,
		foundation,
		lakes,
	)
	if time_manager != null:
		time_manager.call("set_paused", true)
		time_manager.call("restore_persisted_state", CAPTURE_HOUR, 1, 0)
		time_manager.call("set_paused", true)
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.set_process(false)
	DirAccess.open("res://").make_dir_recursive("artifacts/ground_variant_probe")

	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	await _stream_until_stable()
	var home: Vector2 = player.global_position

	var ground_material: ShaderMaterial = _resolve_ground_material()
	if ground_material == null:
		print("ground_variant_probe: FAIL could not resolve plains ground material")
		quit(1)
		return

	_build_overlay()

	for zoom: float in ZOOM_LEVELS:
		camera.zoom = Vector2(zoom, zoom)
		camera.set("_target_zoom", zoom)
		player.global_position = home
		_streamer._update_player_chunk_coord()
		await _stream_until_stable()
		_streamer._sync_sun_lighting_from_time(true)
		camera.force_update_scroll()
		var frames: Array[Image] = []
		for variant: Dictionary in VARIANTS:
			_apply_variant(ground_material, variant)
			_label.text = "%s\ngrass %.2f  orange %.2f  rock %.2f" % [
				str(variant.get("title", variant.get("name"))),
				float(variant.get("grass_coverage", 0.0)),
				float(variant.get("orange_coverage", 0.0)),
				float(variant.get("rock_coverage", 0.0)),
			]
			await _wait_frames(8)
			var img: Image = await _capture()
			if img == null:
				print("ground_variant_probe: capture FAILED %s z%.2f" % [str(variant.get("name")), zoom])
				continue
			var single_path: String = "%s/%s_z%03d.png" % [OUTPUT_DIR, str(variant.get("name")), int(zoom * 100.0)]
			img.save_png(single_path)
			frames.append(img)
			print("ground_variant_probe: saved %s" % ProjectSettings.globalize_path(single_path))
		_save_panel(frames, "%s/panel_z%03d.png" % [OUTPUT_DIR, int(zoom * 100.0)])

	print("ground_variant_probe: DONE")
	scene.queue_free()
	await process_frame
	quit(0)


func _resolve_ground_material() -> ShaderMaterial:
	# Read the live material off the rendered tile data: it is the exact shared
	# ShaderMaterial instance the GPU uses, so mutating its uniforms repaints
	# every ground tile immediately.
	var tile_set: TileSet = WorldTileSetFactory.get_base_tile_set()
	if tile_set == null:
		return null
	var source_id: int = WorldTileSetFactory.get_source_id(PLAINS_GROUND_TERRAIN_ID)
	var source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return null
	for index: int in range(source.get_tiles_count()):
		var coords: Vector2i = source.get_tile_id(index)
		var tile_data: TileData = source.get_tile_data(coords, 0)
		if tile_data != null and tile_data.material is ShaderMaterial:
			return tile_data.material as ShaderMaterial
	return null


func _apply_variant(material: ShaderMaterial, variant: Dictionary) -> void:
	for key: String in TUNED_KEYS:
		assert(variant.has(key), "variant %s missing key %s" % [str(variant.get("name")), key])
		material.set_shader_parameter(key, variant[key])


func _build_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	root.add_child(overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.position = Vector2(18.0, 18.0)
	bg.size = Vector2(620.0, 120.0)
	overlay.add_child(bg)
	_label = Label.new()
	_label.position = Vector2(34.0, 30.0)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	overlay.add_child(_label)


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame


func _save_panel(frames: Array[Image], path: String) -> void:
	if frames.is_empty():
		return
	var frame_size: Vector2i = frames[0].get_size()
	var panel := Image.create(
		frame_size.x * frames.size() + PANEL_DIVIDER_PX * (frames.size() - 1),
		frame_size.y,
		false,
		frames[0].get_format(),
	)
	panel.fill(Color.BLACK)
	for index: int in range(frames.size()):
		panel.blit_rect(
			frames[index],
			Rect2i(Vector2i.ZERO, frame_size),
			Vector2i(index * (frame_size.x + PANEL_DIVIDER_PX), 0),
		)
	panel.save_png(path)
	print("ground_variant_probe: panel saved %s" % ProjectSettings.globalize_path(path))


func _stream_until_stable() -> void:
	for _tick: int in range(MAX_SETTLE_FRAMES):
		_streamer._streaming_tick()
		if _streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			_streamer._mountain_native_mask_visual_apply_tick()
		await process_frame
		var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
		if _streamer._requested_chunks.is_empty() \
				and int(debug.get("native_mask_inflight_count", 0)) == 0 \
				and int(debug.get("native_mask_visual_upload_queue_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_inflight_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_visual_upload_queue_count", 0)) == 0 \
				and not _streamer._has_pending_streaming_work():
			return
