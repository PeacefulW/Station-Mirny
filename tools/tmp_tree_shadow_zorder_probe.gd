extends SceneTree
# Разовая проверка: тень дерева (v1, солнечная, силуэт-шейдер) поверх травы/
# камней/игрока после переноса z на WorldRuntimeConstants.Z_CAST_SHADOW.
# Временный файл, удалить после проверки. Запуск:
#   godot --path . -s tools/tmp_tree_shadow_zorder_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/tmp_tree_shadow_zorder_probe"
const MAX_SETTLE_FRAMES: int = 600


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("must run windowed")
		quit(1)
		return
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var streamer: Node = scene.get_node_or_null("WorldStreamer")
	var daylight: CanvasModulate = scene.get_node_or_null("Daylight") as CanvasModulate
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	streamer.initialize_new_world(WorldRuntimeConstants.DEFAULT_WORLD_SEED, mountain, bounds, foundation, lakes)
	time_manager.call("set_paused", true)
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.set_process(false)
	camera.zoom = Vector2(0.7, 0.7)
	camera.set("_target_zoom", 0.7)
	DirAccess.open("res://").make_dir_recursive("artifacts/tmp_tree_shadow_zorder_probe")
	await _stream_until_stable(streamer)
	# Низкое утреннее солнце: длинная, хорошо читаемая тень.
	time_manager.call("restore_persisted_state", 8.0, 1, 0)
	time_manager.call("set_paused", true)
	daylight._sync_from_current_context(true)
	streamer._sync_sun_lighting_from_time(true)
	camera.force_update_scroll()
	for _f: int in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/morning_zoomed_out.png" % OUTPUT_DIR)

	# Крупный план вокруг игрока (тень должна лечь и на него, и на траву рядом).
	camera.zoom = Vector2(2.2, 2.2)
	camera.set("_target_zoom", 2.2)
	camera.force_update_scroll()
	for _f: int in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var img2: Image = root.get_texture().get_image()
	img2.save_png("%s/morning_player_closeup.png" % OUTPUT_DIR)

	# Диагностика: найти слои теней деревьев, распечатать состояние, взвинтить
	# непрозрачность/длину до предела и снять кадр.
	var shadow_layers: Array[Node] = scene.find_children("TreeSilhouetteShadowLayer", "MultiMeshInstance2D", true, false)
	print("tmp_tree_shadow_zorder_probe: found %d TreeSilhouetteShadowLayer nodes" % shadow_layers.size())
	for layer_variant: Node in shadow_layers:
		var layer := layer_variant as MultiMeshInstance2D
		var mm: MultiMesh = layer.multimesh
		var material: ShaderMaterial = layer.material as ShaderMaterial
		print("  layer=%s visible=%s z_index=%s z_as_relative=%s texture=%s multimesh_instances=%s" % [
			layer.get_path(), layer.visible, layer.z_index, layer.z_as_relative,
			layer.texture, (mm.instance_count if mm != null else -1),
		])
		if material != null:
			print("    shader_params: shadow_dir=%s foreshorten=%s opacity=%s" % [
				material.get_shader_parameter("shadow_dir"),
				material.get_shader_parameter("shadow_foreshorten"),
				material.get_shader_parameter("shadow_opacity"),
			])
			material.set_shader_parameter("shadow_opacity", 1.0)
			material.set_shader_parameter("shadow_foreshorten", 1.5)
	for _f: int in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var img3: Image = root.get_texture().get_image()
	img3.save_png("%s/morning_boosted.png" % OUTPUT_DIR)

	print("tmp_tree_shadow_zorder_probe: saved captures to %s" % OUTPUT_DIR)
	quit(0)


func _stream_until_stable(streamer: Node) -> void:
	for _tick: int in range(MAX_SETTLE_FRAMES):
		streamer._streaming_tick()
		if streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			streamer._mountain_native_mask_visual_apply_tick()
		await process_frame
		var debug: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
		if streamer._requested_chunks.is_empty() \
				and int(debug.get("native_mask_inflight_count", 0)) == 0 \
				and int(debug.get("native_mask_visual_upload_queue_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_inflight_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_visual_upload_queue_count", 0)) == 0 \
				and int(debug.get("grass_scatter_visual_upload_queue_count", 0)) == 0 \
				and not streamer._has_pending_streaming_work():
			return
