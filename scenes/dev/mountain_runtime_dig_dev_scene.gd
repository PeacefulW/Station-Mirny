extends Node2D
## Dev-сцена «копаем рантайм-гору»: инстанцирует настоящую world_runtime_v0
## (стример, игрок, земля ground_hybrid, гора с футом, добыча) и телепортирует
## игрока к ближайшему краю горы. Сцена ничем не владеет и ничего не
## подменяет — презентация горы/фута/земли под горой и путь копания
## на 100% рантаймовые, потому что это буквально рантайм-сцена.
## Скан цели использует worldgen-настройки самого стримера (тот же seed,
## version и settings packed), поэтому найденная гора всегда совпадает
## с реально сгенерированной.
## Скан — dev/boot-класс работы: один синхронный проход по кольцам чанков
## на старте или по хоткею T, с ранним выходом; в интерактивный путь игры
## не входит (GDScript допустим по LAW 1 «debug and dev tools»).

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const WORLD_SCENE: PackedScene = preload("res://scenes/world/world_runtime_v0.tscn")
const MAX_SCAN_RADIUS_CHUNKS: int = 18
const MAX_SPAWN_WAIT_FRAMES: int = 1800
const NEIGHBOR_OFFSETS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

enum DevState { WAITING_SPAWN, READY, FAILED }

var _state: DevState = DevState.WAITING_SPAWN
var _streamer: WorldStreamer = null
var _player: Node2D = null
var _hud_label: Label = null
var _wait_frames: int = 0
var _dig_target: Dictionary = { }
var _fail_reason: String = ""


func _ready() -> void:
	var world: Node2D = WORLD_SCENE.instantiate() as Node2D
	add_child(world)
	_streamer = world.get_node_or_null("WorldStreamer") as WorldStreamer
	_player = world.get_node_or_null("Player") as Node2D
	_build_hud()
	if _streamer == null or _player == null:
		_fail("world_runtime_v0 не дал WorldStreamer/Player")


func _process(_delta: float) -> void:
	if _state == DevState.WAITING_SPAWN:
		_tick_waiting_spawn()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_T:
		return
	if _state == DevState.WAITING_SPAWN or _streamer == null or _player == null:
		return
	_teleport_to_nearest_mountain()
	get_viewport().set_input_as_handled()


## Снимок состояния для smoke-теста: цель копания + рантайм-готовность масок.
func get_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = {
		"ready": _state == DevState.READY,
		"failed": _state == DevState.FAILED,
		"fail_reason": _fail_reason,
		"world_seed": _streamer.get_world_seed() if _streamer != null else 0,
		"mountain_tile": _dig_target.get("mountain_tile", Vector2i.ZERO),
		"stand_tile": _dig_target.get("stand_tile", Vector2i.ZERO),
		"target_terrain_id": int(_dig_target.get("target_terrain_id", -1)),
		"scanned_foot_tile_count": int(_dig_target.get("scanned_foot_tile_count", 0)),
	}
	if _state != DevState.READY or _streamer == null:
		return snapshot
	var stand_world: Vector2 = WorldRuntimeConstants.tile_to_world_center(
		_dig_target.get("stand_tile", Vector2i.ZERO) as Vector2i,
	)
	snapshot["stand_walkable"] = _streamer.is_walkable_at_world(stand_world)
	var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
	snapshot["native"] = {
		"native_mask_runtime_enabled": bool(debug.get("native_mask_runtime_enabled", false)),
		"ready_native_mask_chunk_count": int(debug.get("ready_native_mask_chunk_count", 0)),
		"missing_mountain_chunk_count": int(debug.get("missing_mountain_chunk_count", 0)),
		"dirty": bool(debug.get("dirty", false)),
		"request_in_flight": bool(debug.get("request_in_flight", false)),
		"native_mask_visual_upload_queue_count": int(debug.get("native_mask_visual_upload_queue_count", 0)),
		"native_mask_visual_pending_count": int(debug.get("native_mask_visual_pending_count", 0)),
	}
	return snapshot


## Копок цели для smoke-теста тем же публичным путём, что и игрок
## (try_harvest_at_world). Пробует несколько точек внутри тайла-цели,
## потому что скруглённые углы маски могут «съесть» отдельные пиксели.
func debug_dig_target_once() -> Dictionary:
	if _state != DevState.READY or _streamer == null:
		return { "success": false, "error": "not_ready" }
	var mountain_tile: Vector2i = _dig_target.get("mountain_tile", Vector2i.ZERO) as Vector2i
	var tile_origin: Vector2 = Vector2(
		float(mountain_tile.x * WorldRuntimeConstants.TILE_SIZE_PX),
		float(mountain_tile.y * WorldRuntimeConstants.TILE_SIZE_PX),
	)
	var sample_offsets: Array[Vector2] = [
		Vector2(0.50, 0.50),
		Vector2(0.25, 0.25),
		Vector2(0.75, 0.25),
		Vector2(0.25, 0.75),
		Vector2(0.75, 0.75),
	]
	for offset: Vector2 in sample_offsets:
		var world_pos: Vector2 = tile_origin + offset * float(WorldRuntimeConstants.TILE_SIZE_PX)
		if not _streamer.has_resource_at_world(world_pos):
			continue
		var result: Dictionary = _streamer.try_harvest_at_world(world_pos)
		result["walkable_after"] = _streamer.is_walkable_at_world(
			WorldRuntimeConstants.tile_to_world_center(mountain_tile),
		)
		return result
	return { "success": false, "error": "no_diggable_sample_in_target_tile" }


func _tick_waiting_spawn() -> void:
	if _streamer == null or _player == null:
		return
	_wait_frames += 1
	if _streamer._new_game_spawn_failed:
		_fail("рантайм не смог разрешить spawn")
		return
	if _streamer._awaiting_new_game_spawn_result:
		if _wait_frames > MAX_SPAWN_WAIT_FRAMES:
			_fail("spawn не разрешился за %d кадров" % MAX_SPAWN_WAIT_FRAMES)
		return
	_teleport_to_nearest_mountain()


func _teleport_to_nearest_mountain() -> void:
	var player_tile: Vector2i = WorldRuntimeConstants.world_to_tile(_player.global_position)
	var center_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(player_tile)
	var spot: Dictionary = _find_mountain_dig_spot(center_chunk)
	if spot.is_empty():
		if _state != DevState.FAILED:
			_fail("гора не найдена в радиусе %d чанков от чанка %s" % [
				MAX_SCAN_RADIUS_CHUNKS,
				str(center_chunk),
			])
		return
	_dig_target = spot
	_player.global_position = WorldRuntimeConstants.tile_to_world_center(
		spot.get("stand_tile", Vector2i.ZERO) as Vector2i,
	)
	var camera: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()
		camera.force_update_scroll()
	_state = DevState.READY


## Кольцевой скан чанков через WorldCore с теми же generation-входами, что
## у стримера: пакеты идентичны опубликованным чанкам (чистая функция, LAW 3).
func _find_mountain_dig_spot(center_chunk: Vector2i) -> Dictionary:
	var core: Object = ClassDB.instantiate("WorldCore")
	if core == null:
		_fail("WorldCore GDExtension недоступен — собери native, fallback запрещён")
		return { }
	var settings_packed: PackedFloat32Array = _streamer._worldgen_settings_packed
	if settings_packed.is_empty():
		_fail("worldgen settings packed пуст — мир не инициализирован")
		return { }
	var seed_value: int = _streamer.get_world_seed()
	var version: int = _streamer.get_world_version()
	var foot_tile_count: int = 0
	for radius: int in range(0, MAX_SCAN_RADIUS_CHUNKS + 1):
		var coords: PackedVector2Array = _chunk_ring(center_chunk, radius)
		var packets: Array = core.call(
			"generate_chunk_packets_batch",
			seed_value,
			coords,
			version,
			settings_packed,
		) as Array
		var best: Dictionary = { }
		for packet_variant: Variant in packets:
			var packet: Dictionary = packet_variant as Dictionary
			var found: Dictionary = _find_dig_spot_in_packet(packet)
			foot_tile_count += int(found.get("foot_tile_count", 0))
			if best.is_empty() and found.has("mountain_tile"):
				best = found
		if not best.is_empty():
			best["scanned_foot_tile_count"] = foot_tile_count
			return best
	return { }


## Ищет в пакете солидный горный тайл (стена/фут) с проходимым соседом
## в том же чанке: сосед — точка стояния, горный тайл — цель копания.
func _find_dig_spot_in_packet(packet: Dictionary) -> Dictionary:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var result: Dictionary = { }
	var foot_count: int = 0
	var limit: int = mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(limit):
		if int(terrain_ids[index]) == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			foot_count += 1
		if result.has("mountain_tile"):
			continue
		if not _is_solid_mountain_index(index, terrain_ids, walkable_flags, mountain_flags):
			continue
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		for offset: Vector2i in NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = local_coord + offset
			if neighbor.x < 0 or neighbor.y < 0 \
					or neighbor.x >= WorldRuntimeConstants.CHUNK_SIZE \
					or neighbor.y >= WorldRuntimeConstants.CHUNK_SIZE:
				continue
			var neighbor_index: int = WorldRuntimeConstants.local_to_index(neighbor)
			if neighbor_index >= walkable_flags.size() or int(walkable_flags[neighbor_index]) == 0:
				continue
			result = {
				"mountain_tile": chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local_coord,
				"stand_tile": chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + neighbor,
				"target_terrain_id": int(terrain_ids[index]),
			}
			break
	result["foot_tile_count"] = foot_count
	return result


func _is_solid_mountain_index(
		index: int,
		terrain_ids: PackedInt32Array,
		walkable_flags: PackedByteArray,
		mountain_flags: PackedByteArray,
) -> bool:
	if index < 0 or index >= terrain_ids.size():
		return false
	var terrain_id: int = int(terrain_ids[index])
	if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return false
	if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
		return false
	if index < mountain_flags.size():
		var flags: int = int(mountain_flags[index])
		if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
			return false
	return true


func _chunk_ring(center_chunk: Vector2i, radius: int) -> PackedVector2Array:
	var coords: PackedVector2Array = PackedVector2Array()
	for chunk_y: int in range(center_chunk.y - radius, center_chunk.y + radius + 1):
		for chunk_x: int in range(center_chunk.x - radius, center_chunk.x + radius + 1):
			if maxi(absi(chunk_x - center_chunk.x), absi(chunk_y - center_chunk.y)) != radius:
				continue
			coords.append(Vector2(float(chunk_x), float(chunk_y)))
	return coords


func _fail(reason: String) -> void:
	_fail_reason = reason
	_state = DevState.FAILED
	push_error("mountain_runtime_dig_dev_scene: %s" % reason)


func _build_hud() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "DevHud"
	add_child(canvas)
	_hud_label = Label.new()
	_hud_label.name = "InfoLabel"
	_hud_label.anchor_top = 1.0
	_hud_label.anchor_bottom = 1.0
	_hud_label.offset_left = 16.0
	_hud_label.offset_right = 900.0
	_hud_label.offset_top = -190.0
	_hud_label.offset_bottom = -16.0
	_hud_label.add_theme_font_size_override("font_size", 15)
	_hud_label.add_theme_color_override("font_color", Color(0.84, 0.92, 0.86, 1.0))
	_hud_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	_hud_label.add_theme_constant_override("shadow_offset_x", 2)
	_hud_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(_hud_label)


func _update_hud() -> void:
	if _hud_label == null:
		return
	match _state:
		DevState.WAITING_SPAWN:
			_hud_label.text = "Рантайм-гора: ждём spawn мира… (%d кадров)" % _wait_frames
		DevState.FAILED:
			_hud_label.text = "Рантайм-гора: ОШИБКА — %s" % _fail_reason
		DevState.READY:
			var player_tile: Vector2i = WorldRuntimeConstants.world_to_tile(_player.global_position)
			_hud_label.text = "\n".join([
				"Рантайм-гора (world_runtime_v0, seed %d): цель %s (%s), стоим %s, игрок %s" % [
					_streamer.get_world_seed(),
					str(_dig_target.get("mountain_tile", Vector2i.ZERO)),
					_terrain_name(int(_dig_target.get("target_terrain_id", -1))),
					str(_dig_target.get("stand_tile", Vector2i.ZERO)),
					str(player_tile),
				],
				"WASD — движение | E — копать в сторону курсора | Space — атака | T — телепорт к ближайшей горе",
				"G — тайл под игроком | F6 сетка | F7 маска горы | F10 контур | F11 коллайдеры | K — погода",
				"F5/F9 — сейв/лоад | Esc — меню. Земля под горой открывается копанием — это рантайм-путь 1:1.",
			])


func _terrain_name(terrain_id: int) -> String:
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL:
		return "стена"
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return "фут"
	return "terrain %d" % terrain_id
