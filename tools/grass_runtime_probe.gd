extends SceneTree

# Рендер-проба Итерации 2 спеки wind_and_grass_scatter_presentation: трава в
# рантайм-мире. Артефакты:
# - spawn_zoom_*.png — спавн на трёх зумах (соответствие травы полям земли)
# - dense_zoom_*.png — самый густой загруженный чанк (оранжевое биополе)
# - grass_ablation_panel.png — спавн без травы / с травой (before/after)
# - лог: счётчики инстансов по чанкам, суммарный объём.
# Windowed (захват вьюпорта требует GPU). Запуск:
#   Godot_v4.6.2-stable_win64_console.exe --path . -s tools/grass_runtime_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/grass_runtime_probe"
const CAPTURE_HOUR: float = 12.0
const ZOOM_LEVELS: Array[float] = [1.0, 0.45, 0.22]
const MAX_SETTLE_FRAMES: int = 600
const PANEL_DIVIDER_PX: int = 4

var _streamer: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("grass_runtime_probe: must run windowed")
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
	DirAccess.open("res://").make_dir_recursive("artifacts/grass_runtime_probe")

	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	var home: Vector2 = player.global_position
	await _stream_until_stable()

	# --- счётчики травы по загруженным чанкам ---
	var total_instances: int = 0
	var grass_chunk_count: int = 0
	var densest_chunk: Vector2i = Vector2i(2147483647, 2147483647)
	var densest_count: int = -1
	for chunk_coord_variant: Variant in _streamer._chunk_views.keys():
		var chunk_coord: Vector2i = chunk_coord_variant as Vector2i
		var chunk_view: Node = _streamer._chunk_views[chunk_coord] as Node
		var state: Dictionary = chunk_view.get_grass_scatter_debug_state()
		var count: int = int(state.get("instance_count", 0))
		total_instances += count
		if count > 0:
			grass_chunk_count += 1
		if count > densest_count:
			densest_count = count
			densest_chunk = chunk_coord
	print(
		"grass_runtime_probe: chunks_with_grass=%d total_instances=%d densest=%s count=%d" % [
			grass_chunk_count,
			total_instances,
			str(densest_chunk),
			densest_count,
		],
	)
	if total_instances <= 0:
		print("grass_runtime_probe: FAIL no grass instances in runtime world")
		quit(1)
		return

	# --- спавн: серия зумов ---
	for zoom: float in ZOOM_LEVELS:
		camera.zoom = Vector2(zoom, zoom)
		camera.set("_target_zoom", zoom)
		await _stream_until_stable()
		_streamer._sync_sun_lighting_from_time(true)
		camera.force_update_scroll()
		await _wait_frames(10)
		var img: Image = await _capture()
		img.save_png("%s/spawn_zoom_%03d.png" % [OUTPUT_DIR, int(zoom * 100.0)])
		print("grass_runtime_probe: saved spawn_zoom_%03d.png" % int(zoom * 100.0))

	# --- ablation на спавне: без травы / с травой ---
	camera.zoom = Vector2(0.45, 0.45)
	camera.set("_target_zoom", 0.45)
	camera.force_update_scroll()
	await _wait_frames(8)
	var hidden_layers: Array[MultiMeshInstance2D] = []
	for chunk_view_variant: Variant in _streamer._chunk_views.values():
		var chunk_view: Node = chunk_view_variant as Node
		var layer: MultiMeshInstance2D = chunk_view.get_node_or_null("GrassScatterBatch") as MultiMeshInstance2D
		if layer != null and layer.visible:
			layer.visible = false
			hidden_layers.append(layer)
	await _wait_frames(4)
	var without_grass: Image = await _capture()
	for layer: MultiMeshInstance2D in hidden_layers:
		# Стример живёт своей жизнью: чанк мог выселиться между кадрами.
		if is_instance_valid(layer):
			layer.visible = true
	await _wait_frames(4)
	var with_grass: Image = await _capture()
	var ablation_frames: Array[Image] = [without_grass, with_grass]
	_save_panel(ablation_frames, "%s/grass_ablation_panel.png" % OUTPUT_DIR)

	# --- самый густой чанк (оранжевое биополе) ---
	var densest_center: Vector2 = WorldRuntimeConstants.chunk_origin_px(densest_chunk) \
			+ Vector2.ONE * float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX) * 0.5
	player.global_position = densest_center
	_streamer._update_player_chunk_coord()
	for zoom: float in [1.0, 0.45]:
		camera.zoom = Vector2(zoom, zoom)
		camera.set("_target_zoom", zoom)
		await _stream_until_stable()
		_streamer._sync_sun_lighting_from_time(true)
		camera.force_update_scroll()
		await _wait_frames(10)
		var img: Image = await _capture()
		img.save_png("%s/dense_zoom_%03d.png" % [OUTPUT_DIR, int(zoom * 100.0)])
		print("grass_runtime_probe: saved dense_zoom_%03d.png" % int(zoom * 100.0))

	# --- zoom-LOD: на дальнем зуме хвост мелких пучков скрыт без пересборки ---
	player.global_position = home
	_streamer._update_player_chunk_coord()
	camera.zoom = Vector2(0.22, 0.22)
	camera.set("_target_zoom", 0.22)
	camera.force_update_scroll()
	await _stream_until_stable()
	_streamer._update_player_chunk_coord()
	await _wait_frames(4)
	var lod_total: int = 0
	var lod_visible: int = 0
	for chunk_view_variant: Variant in _streamer._chunk_views.values():
		var chunk_view: Node = chunk_view_variant as Node
		var state: Dictionary = chunk_view.get_grass_scatter_debug_state()
		lod_total += int(state.get("instance_count", 0))
		lod_visible += int(state.get("visible_instance_count", 0))
	var lod_fraction: float = float(lod_visible) / maxf(float(lod_total), 1.0)
	var lod_min_fraction: float = float(_streamer._grass_lod_min_fraction)
	print(
		"grass_runtime_probe: lod@0.22 visible=%d/%d fraction=%.2f (authored min %.2f)" % [
			lod_visible,
			lod_total,
			lod_fraction,
			lod_min_fraction,
		],
	)
	if lod_min_fraction >= 0.99:
		# LOD отключён авторскими данными: резать ничего не должно.
		if lod_total > 0 and lod_visible < lod_total:
			print("grass_runtime_probe: FAIL LOD disabled by data but instances are trimmed")
			quit(1)
			return
	elif lod_total > 0 and lod_fraction >= 0.99:
		print("grass_runtime_probe: FAIL zoom LOD did not trim far-zoom instances")
		quit(1)
		return

	print("grass_runtime_probe: DONE")
	scene.queue_free()
	await process_frame
	quit(0)


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame


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
				and int(debug.get("grass_scatter_visual_upload_queue_count", 0)) == 0 \
				and not _streamer._has_pending_streaming_work():
			return


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
	print("grass_runtime_probe: panel saved %s" % ProjectSettings.globalize_path(path))
