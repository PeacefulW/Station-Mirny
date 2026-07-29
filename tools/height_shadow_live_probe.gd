extends SceneTree

## Windowed production-scene proof for tall-caster material reception.
## Captures the same forest with receiver strength disabled/enabled and checks
## that pixels covered by the tree-shadow mask become darker.

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload(
	"res://core/systems/world/world_runtime_constants.gd"
)
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/height_shadow_live_probe"
const CAPTURE_HOUR: float = 15.5
const CAPTURE_ZOOM: float = 0.82
const MAX_SETTLE_FRAMES: int = 900

var _streamer: Node = null
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("height_shadow_live_probe requires a windowed GPU renderer")
		quit(2)
		return
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("artifacts/height_shadow_live_probe")
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	_streamer = scene.get_node_or_null("WorldStreamer")
	if _streamer != null:
		_streamer.enable_debug_visible_only_initial_loading()
	root.add_child(scene)
	await process_frame

	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	var field: WorldHeightShadowField = (
		scene.get_node_or_null("WorldHeightShadowField") as WorldHeightShadowField
	)
	_expect(_streamer != null and player != null and camera != null, "production world nodes")
	_expect(field != null, "production height-shadow field")
	if _failed:
		await _finish(scene)
		return

	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	_streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		MountainGenSettings.hard_coded_defaults(),
		bounds,
		FoundationGenSettings.for_bounds(bounds),
		LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict()),
	)
	var time_manager: Node = root.get_node_or_null("TimeManager")
	if time_manager != null:
		time_manager.call("restore_persisted_state", CAPTURE_HOUR, 1, 0)
		time_manager.call("set_paused", true)
	var wind_runtime: Node = root.get_node_or_null("WindRuntime")
	if wind_runtime != null:
		wind_runtime.set_process(false)
	RenderingServer.global_shader_parameter_set("wind_strength", 0.0)
	var cloud_field: CanvasItem = scene.get_node_or_null("CloudOccluderField") as CanvasItem
	if cloud_field != null:
		cloud_field.visible = false
	player.visible = false
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(CAPTURE_ZOOM, CAPTURE_ZOOM)
	camera.set("_target_zoom", CAPTURE_ZOOM)

	await _stream_until_stable()
	# This is an ablation probe, not a startup/readiness probe. Keep the honest
	# production gate running, but hide its already-present CanvasLayer so the
	# capture can inspect the ready forest portion underneath it.
	var loading_screen: CanvasLayer = (
		scene.get_node_or_null("InitialLoadingScreen") as CanvasLayer
	)
	if loading_screen != null:
		loading_screen.visible = false
	var target_chunk: Vector2i = _find_forest_chunk()
	_expect(
		target_chunk != Vector2i(2147483647, 2147483647),
		"loaded production envelope must contain a tree-and-grass chunk",
	)
	if _failed:
		await _finish(scene)
		return
	player.global_position = WorldRuntimeConstants.chunk_origin_px(target_chunk) + Vector2(
		WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX * 0.5,
		WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX * 0.5,
	)
	_streamer._update_player_chunk_coord()
	await _wait_frames(240)
	_streamer._sync_sun_lighting_from_time(true)
	camera.force_update_scroll()
	await _wait_frames(16)

	var grass_material: ShaderMaterial = _streamer._grass_scatter_material as ShaderMaterial
	var catalog: RefCounted = _streamer._layered_object_asset_catalog as RefCounted
	var rock_albedo: ShaderMaterial = catalog.call("get_rock_albedo_material") as ShaderMaterial
	var rock_snow: ShaderMaterial = catalog.call("get_rock_snow_material") as ShaderMaterial
	for material: ShaderMaterial in [grass_material, rock_albedo, rock_snow]:
		material.set_shader_parameter("height_shadow_strength", 0.0)
	await _wait_frames(8)
	var receiver_disabled: Image = await _capture()
	receiver_disabled.save_png("%s/01_receiver_disabled.png" % OUTPUT_DIR)

	_streamer.bind_height_shadow_field(field)
	await _wait_frames(8)
	var receiver_enabled: Image = await _capture()
	receiver_enabled.save_png("%s/02_receiver_enabled.png" % OUTPUT_DIR)
	_save_panel(
		[receiver_disabled, receiver_enabled],
		"%s/receiver_before_after.png" % OUTPUT_DIR,
	)

	var mask_texture: Texture2D = field.call("get_mask_texture") as Texture2D
	var mask_image: Image = mask_texture.get_image()
	var stats: Dictionary = _measure_receiver_delta(
		receiver_disabled,
		receiver_enabled,
		mask_image,
	)
	print("height_shadow_live_probe: target=%s stats=%s" % [target_chunk, stats])
	_expect(int(stats.get("mask_pixels", 0)) > 256, "visible tree-shadow mask coverage")
	_expect(int(stats.get("darkened_pixels", 0)) > 96, "grass/rock pixels darkened by mask")
	_expect(float(stats.get("max_luma_delta", 0.0)) > 0.025, "material reception luma delta")
	await _finish(scene)


func _find_forest_chunk() -> Vector2i:
	var best_coord := Vector2i(2147483647, 2147483647)
	var best_score: int = -1
	for chunk_coord_variant: Variant in _streamer._chunk_views.keys():
		var chunk_coord: Vector2i = chunk_coord_variant as Vector2i
		var packet: Dictionary = _streamer._chunk_packets.get(chunk_coord, { }) as Dictionary
		var kinds: PackedByteArray = packet.get("object_kind", PackedByteArray()) as PackedByteArray
		var tree_count: int = kinds.count(4)
		var chunk_view: Node = _streamer._chunk_views.get(chunk_coord) as Node
		var grass_state: Dictionary = chunk_view.get_grass_scatter_debug_state()
		var grass_count: int = int(grass_state.get("instance_count", 0))
		if tree_count <= 0 or grass_count <= 0:
			continue
		var score: int = tree_count * 10000 + grass_count
		if score > best_score:
			best_score = score
			best_coord = chunk_coord
	return best_coord


func _stream_until_stable() -> void:
	for _frame_index: int in range(MAX_SETTLE_FRAMES):
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


func _measure_receiver_delta(
		disabled: Image,
		enabled: Image,
		mask: Image,
) -> Dictionary:
	var mask_pixels: int = 0
	var darkened_pixels: int = 0
	var luma_delta_sum: float = 0.0
	var max_luma_delta: float = 0.0
	for y: int in range(disabled.get_height()):
		var mask_y: int = clampi(
			floori(float(y) * float(mask.get_height()) / float(disabled.get_height())),
			0,
			mask.get_height() - 1,
		)
		for x: int in range(disabled.get_width()):
			var mask_x: int = clampi(
				floori(float(x) * float(mask.get_width()) / float(disabled.get_width())),
				0,
				mask.get_width() - 1,
			)
			if mask.get_pixel(mask_x, mask_y).a < 0.08:
				continue
			mask_pixels += 1
			var delta: float = (
				disabled.get_pixel(x, y).get_luminance()
				- enabled.get_pixel(x, y).get_luminance()
			)
			if delta <= 0.008:
				continue
			darkened_pixels += 1
			luma_delta_sum += delta
			max_luma_delta = maxf(max_luma_delta, delta)
	return {
		"mask_pixels": mask_pixels,
		"darkened_pixels": darkened_pixels,
		"mean_darkened_luma_delta": (
			luma_delta_sum / float(darkened_pixels)
			if darkened_pixels > 0
			else 0.0
		),
		"max_luma_delta": max_luma_delta,
	}


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _wait_frames(count: int) -> void:
	for _frame_index: int in range(count):
		await process_frame


func _save_panel(frames: Array[Image], path: String) -> void:
	var size: Vector2i = frames[0].get_size()
	var panel := Image.create(size.x * frames.size() + 4, size.y, false, frames[0].get_format())
	panel.fill(Color.BLACK)
	for index: int in range(frames.size()):
		panel.blit_rect(
			frames[index],
			Rect2i(Vector2i.ZERO, size),
			Vector2i(index * (size.x + 4), 0),
		)
	panel.save_png(path)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("height_shadow_live_probe: %s" % label)


func _finish(scene: Node) -> void:
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	_release_player_state_cycle(scene.get_node_or_null("Player"))
	scene.queue_free()
	_streamer = null
	await process_frame
	await process_frame
	call_deferred("_complete")


## The production player state machine currently owns bidirectional RefCounted
## links. A standalone SceneTree probe must sever them before forced shutdown;
## the running game keeps the player alive and does not exercise this teardown.
func _release_player_state_cycle(player: Node) -> void:
	if player == null:
		return
	var machine: RefCounted = player.get("_state_machine") as RefCounted
	if machine == null:
		return
	var states: Dictionary = machine.get("_states") as Dictionary
	for state_variant: Variant in states.values():
		var state: RefCounted = state_variant as RefCounted
		if state == null:
			continue
		state.set("machine", null)
		state.set("owner", null)
	machine.set("_current_state", null)
	machine.set("_states", {})
	machine.set("_owner", null)
	player.set("_state_machine", null)


func _complete() -> void:
	if _failed:
		quit(1)
		return
	print("height_shadow_live_probe: PASS")
	quit(0)
