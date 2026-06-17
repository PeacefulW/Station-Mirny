extends SceneTree

# Авто-инвариант player-relative depth-лесенки: для всех видимых mid-полос
# (трава + объектный декор) в зоне точности — «севернее ног игрока => под
# игроком, южнее => над». Прогоняется на трёх позициях игрока (включая
# перемещения). Windowed. Запуск:
#   Godot_v4.6.2-stable_win64_console.exe --path . -s tools/grass_ladder_check.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = (load("res://scenes/world/world_runtime_v0.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var streamer: Node = scene.get_node("WorldStreamer")
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		MountainGenSettings.hard_coded_defaults(),
		bounds,
		FoundationGenSettings.for_bounds(bounds),
		LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict()),
	)
	await _settle(streamer)
	var player: Node2D = scene.get_node("Player")
	var failures: int = 0
	var checked: int = 0
	for shift: float in [0.0, 200.0, -333.0]:
		player.global_position.y += shift
		streamer._update_player_chunk_coord()
		for _i: int in range(30):
			streamer._streaming_tick()
			streamer._mountain_native_mask_visual_apply_tick()
			await process_frame
		var anchor: int = WorldRuntimeConstants.depth_stripe_for_world_y(
			player.global_position.y + 41.0,
		)
		var player_z: int = player.z_index
		for k: Variant in streamer._chunk_views.keys():
			var cv: Node2D = streamer._chunk_views[k]
			var base: int = floori(cv.position.y / 16.0)
			for child: Node in cv.get_children():
				if not str(child.name).begins_with("GrassScatterBatchB"):
					continue
				var item: CanvasItem = child as MultiMeshInstance2D
				if item == null or not item.visible:
					continue
				var stripe: int = int(str(child.name).trim_prefix("GrassScatterBatchB"))
				var rel: int = stripe + base - anchor
				if absi(rel) >= WorldRuntimeConstants.DEPTH_LADDER_HALF_RANGE_STRIPES:
					continue
				checked += 1
				if rel < 0 and item.z_index >= player_z:
					failures += 1
				elif rel > 0 and item.z_index <= player_z:
					failures += 1
			var opl: Node = cv.get("_object_packet_layer")
			if opl == null:
				continue
			for batch_name: String in ["_rock_batch_layer", "_living_flora_batch_layer", "_spiky_flora_batch_layer"]:
				var batch: Node = opl.get(batch_name)
				if batch == null:
					continue
				for group: Array in batch.get("_sprite_layers_by_atlas"):
					for layer_variant: Variant in group:
						var layer: CanvasItem = layer_variant as MultiMeshInstance2D
						if layer == null or not layer.visible:
							continue
						var stripe2: int = int(str(layer.name).split("Stripe")[1])
						var rel2: int = stripe2 + base - anchor
						if absi(rel2) >= WorldRuntimeConstants.DEPTH_LADDER_HALF_RANGE_STRIPES:
							continue
						checked += 1
						if rel2 < 0 and layer.z_index >= player_z:
							failures += 1
						elif rel2 > 0 and layer.z_index <= player_z:
							failures += 1
		print(
			"grass_ladder_check: shift=%.0f anchor=%d player_z=%d checked=%d failures=%d" % [
				shift,
				anchor,
				player_z,
				checked,
				failures,
			],
		)
	scene.queue_free()
	await process_frame
	if failures == 0:
		print("grass_ladder_check: PASS no overlap-order violations vs player")
		quit(0)
	else:
		print("grass_ladder_check: FAIL %d violations" % failures)
		quit(1)


func _settle(s: Node) -> void:
	for _i: int in range(500):
		s._streaming_tick()
		s._mountain_native_mask_visual_apply_tick()
		await process_frame
		if s._requested_chunks.is_empty() and not s._has_pending_streaming_work():
			return
