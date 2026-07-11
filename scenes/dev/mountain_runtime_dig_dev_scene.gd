extends Node2D
## Dev-сцена production construction roof. Она инстанцирует настоящий
## world_runtime_v0, выбирает детерминированный южный вход и копает реальную
## T-полость публичным путём try_harvest_at_world.
##
## Ни маска, ни Sprite2D здесь не синтезируются: BASE/ROOF/active-floor
## берутся из ChunkView. OUTSIDE/INSIDE меняется только переносом
## настоящего Player; MountainResolver сам выбирает connected cavity.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const WORLD_SCENE: PackedScene = preload("res://scenes/world/world_runtime_v0.tscn")
const MAX_SCAN_RADIUS_CHUNKS: int = 18
const MAX_SPAWN_WAIT_FRAMES: int = 1800
const PROTOTYPE_DIG_DELAY_FRAMES: int = 20

# Mouth, three tiles north to the junction, then one tile left/right: six real
# dug tiles. Every offset and its required retaining wall fit in one chunk.
const PROTOTYPE_T_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(0, -1),
	Vector2i(0, -2),
	Vector2i(0, -3),
	Vector2i(-1, -3),
	Vector2i(1, -3),
]
const PROTOTYPE_RETAINING_WALL_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, -1), Vector2i(1, -1),
	Vector2i(-1, -2), Vector2i(1, -2),
	Vector2i(0, -4),
	Vector2i(-1, -4), Vector2i(1, -4),
	Vector2i(-2, -3), Vector2i(2, -3),
]
const PROTOTYPE_PHASE_IDLE: StringName = &"idle"
const PROTOTYPE_PHASE_WAITING_CAPTURE: StringName = &"waiting_production_masks"
const PROTOTYPE_PHASE_CAPTURED: StringName = &"captured"
const PROTOTYPE_PHASE_DIGGING: StringName = &"digging"
const PROTOTYPE_PHASE_WAITING_NATIVE: StringName = &"waiting_native"
const PROTOTYPE_PHASE_READY: StringName = &"ready"
const PROTOTYPE_PHASE_FAILED: StringName = &"failed"

enum DevState { WAITING_SPAWN, READY, FAILED }

var _state: DevState = DevState.WAITING_SPAWN
var _streamer: WorldStreamer = null
var _player: Node2D = null
var _hud_label: Label = null
var _wait_frames: int = 0
var _dig_target: Dictionary = { }
var _fail_reason: String = ""

var _prototype_phase: StringName = PROTOTYPE_PHASE_IDLE
var _prototype_error: String = ""
var _prototype_initial_base_mask_hash: int = 0
var _prototype_initial_closed_mask_hash: int = 0
var _prototype_closed_mask_hash: int = 0
var _prototype_open_mask_hash: int = 0
var _prototype_roof_texture_id: int = 0
var _prototype_roof_sprite_id: int = 0
var _prototype_roof_material_id: int = 0
var _prototype_base_sprite_id: int = 0
var _prototype_base_texture_id: int = 0
var _prototype_base_material_id: int = 0
var _prototype_requested_inside: bool = false
var _prototype_next_dig_index: int = 0
var _prototype_dig_delay_frames: int = 0
var _prototype_roof_wait_frames: int = 0
var _prototype_dig_results: Array[Dictionary] = []
var _prototype_state_signature: String = ""
var _prototype_last_toggle_preserved_state: bool = true


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
	_tick_roof_prototype()
	_validate_prototype_lifecycle()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if _state != DevState.READY or _streamer == null or _player == null:
		return
	match key_event.keycode:
		KEY_T:
			if _prototype_phase == PROTOTYPE_PHASE_IDLE:
				_teleport_to_nearest_mountain()
				get_viewport().set_input_as_handled()
		KEY_P:
			debug_start_roof_prototype()
			get_viewport().set_input_as_handled()
		KEY_V:
			debug_place_player_for_prototype(not _prototype_requested_inside)
			get_viewport().set_input_as_handled()


## Полный снимок для smoke/render probe. Вложенный prototype выводит
## только production-состояние ChunkView/WorldStreamer.
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
		"prototype_dig_tiles": _dig_target.get("prototype_dig_tiles", []),
		"prototype_retaining_wall_tiles": _dig_target.get("retaining_wall_tiles", []),
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
		"chunk_visibility_waiting_for_roof_count": int(debug.get("chunk_visibility_waiting_for_roof_count", 0)),
		"native_mask_visual_upload_elapsed_ms_last": float(debug.get("native_mask_visual_upload_elapsed_ms_last", 0.0)),
		"native_mask_visual_upload_elapsed_ms_max_total": float(debug.get("native_mask_visual_upload_elapsed_ms_max_total", 0.0)),
	}
	var chunk_view: ChunkView = _target_chunk_view()
	var source: Sprite2D = _target_mountain_mask_sprite()
	var roof: Sprite2D = _target_production_roof_sprite()
	var chunk_debug: Dictionary = (
		chunk_view.get_mountain_native_mask_debug_state() if chunk_view != null else { }
	)
	var current_mask_hash: int = _current_base_mask_hash()
	var closed_mask_hash: int = _current_closed_roof_mask_hash()
	var reveal_halo_hash: int = _current_reveal_halo_hash()
	var outside_mouth_halo_hash: int = _current_outside_mouth_halo_hash()
	var current_sprite_id: int = source.get_instance_id() if source != null else 0
	var current_texture_id: int = source.texture.get_instance_id() if source != null and source.texture != null else 0
	var current_material_id: int = source.material.get_instance_id() if source != null and source.material != null else 0
	var current_roof_sprite_id: int = roof.get_instance_id() if roof != null else 0
	var current_roof_texture_id: int = roof.texture.get_instance_id() if roof != null and roof.texture != null else 0
	var current_roof_material_id: int = roof.material.get_instance_id() if roof != null and roof.material != null else 0
	var tile_states: Array[Dictionary] = _prototype_tile_states()
	var inside: bool = _is_production_inside()
	var resolver_debug: Dictionary = { }
	var resolver_object: Object = _player.get("_mountain_resolver") as Object if _player != null else null
	if resolver_object != null and resolver_object.has_method("get_debug_snapshot"):
		resolver_debug = resolver_object.call("get_debug_snapshot") as Dictionary
	snapshot["prototype"] = {
		"phase": String(_prototype_phase),
		"failed": _prototype_phase == PROTOTYPE_PHASE_FAILED,
		"error": _prototype_error,
		"target_mask_sprite_ready": source != null,
		"captured": _prototype_initial_closed_mask_hash != 0,
		"ready": _prototype_phase == PROTOTYPE_PHASE_READY,
		"inside": inside,
		"requested_inside": _prototype_requested_inside,
		"overlay_visible": roof != null and roof.visible,
		"dual_mask_ready": _production_dual_masks_ready(),
		"initial_base_mask_hash": _prototype_initial_base_mask_hash,
		"initial_closed_mask_hash": _prototype_initial_closed_mask_hash,
		"closed_mask_hash": closed_mask_hash,
		"native_open_mask_hash": _prototype_open_mask_hash,
		"open_mask_hash": _prototype_open_mask_hash,
		"remaining_mask_hash": current_mask_hash,
		"current_mask_hash": current_mask_hash,
		"dug_halo_hash": _current_dug_halo_hash(),
		"reveal_halo_hash": reveal_halo_hash,
		"outside_mouth_halo_hash": outside_mouth_halo_hash,
		"outside_mouth_direction_or": _current_outside_mouth_direction_or(),
		"outside_mouth_direction_codes": _current_outside_mouth_direction_codes(),
		"roof_texture_id": _prototype_roof_texture_id,
		"roof_sprite_id_stable": _prototype_roof_sprite_id == 0 \
			or current_roof_sprite_id == _prototype_roof_sprite_id,
		"roof_texture_id_stable": _prototype_roof_texture_id == 0 \
			or current_roof_texture_id == _prototype_roof_texture_id,
		"roof_material_id_stable": _prototype_roof_material_id == 0 \
			or current_roof_material_id == _prototype_roof_material_id,
		"base_sprite_id_stable": _prototype_base_sprite_id == 0 \
			or current_sprite_id == _prototype_base_sprite_id,
		"base_texture_id_stable": _prototype_base_texture_id == 0 \
			or current_texture_id == _prototype_base_texture_id,
		"base_material_id_stable": _prototype_base_material_id == 0 \
			or current_material_id == _prototype_base_material_id,
		"dig_count": _prototype_dig_results.size(),
		"expected_dig_count": PROTOTYPE_T_OFFSETS.size(),
		"dug_floor_count": _count_dug_floor_tiles(tile_states),
		"mask_walkable_count": _count_mask_walkable_tiles(tile_states),
		"remaining_mask_open_count": _count_remaining_mask_open_tiles(tile_states),
		"tile_states": tile_states,
		"prototype_state_signature": _current_prototype_state_signature(),
		"finalized_prototype_state_signature": _prototype_state_signature,
		"effective_roof_signature": _current_effective_roof_signature(),
		"last_toggle_preserved_state": _prototype_last_toggle_preserved_state,
		"mountain_id": int(_dig_target.get("mountain_id", 0)),
		"chunk_coord": _dig_target.get("prototype_chunk_coord", Vector2i.ZERO),
		"active_mountain_id": _streamer._active_cover_mountain_id,
		"active_component_id": _streamer._active_cover_component_id,
		"roof_reveal_active": bool(chunk_debug.get("roof_reveal_active", false)),
		"active_floor_reveal_active": int(chunk_debug.get("active_floor_halo_tile_count", 0)) > 0,
		"active_floor_halo_tile_count": int(chunk_debug.get("active_floor_halo_tile_count", 0)),
		"outside_mouth_halo_tile_count": int(chunk_debug.get("outside_mouth_halo_tile_count", 0)),
		"dug_halo_tile_count": int(chunk_debug.get("dug_halo_tile_count", 0)),
		"remaining_mask_byte_count": int(chunk_debug.get("remaining_mask_byte_count", 0)),
		"closed_roof_mask_byte_count": int(chunk_debug.get("closed_roof_mask_byte_count", 0)),
		"remaining_texture_ready": chunk_view != null and chunk_view._mountain_top_mask_texture != null,
		"closed_texture_ready": chunk_view != null and chunk_view._mountain_closed_roof_mask_texture != null,
		"selector_texture_ready": chunk_view != null and chunk_view._mountain_active_floor_halo_texture != null,
		"closed_visual_dirty": chunk_view != null and chunk_view._mountain_closed_roof_mask_visual_dirty,
		"selector_visual_dirty": chunk_view != null and chunk_view._mountain_active_floor_halo_visual_dirty,
		"dug_visual_dirty": chunk_view != null and chunk_view._mountain_dug_halo_visual_dirty,
		"mask_size": Vector2i(
			chunk_view._mountain_top_mask_width if chunk_view != null else 0,
			chunk_view._mountain_top_mask_height if chunk_view != null else 0,
		),
		"active_halo_side": chunk_view._mountain_active_floor_halo_side if chunk_view != null else 0,
		"mouth_halo_side": chunk_view._mountain_outside_mouth_halo_side if chunk_view != null else 0,
		"dug_halo_side": chunk_view._mountain_dug_halo_side if chunk_view != null else 0,
		"resolver": resolver_debug,
	}
	return snapshot


## Фиксирует хэши/instance id production dual-mask до копания.
## Ни байты, ни Sprite2D сцена не создаёт.
func debug_capture_prototype_closed_roof() -> Dictionary:
	if _state != DevState.READY or _streamer == null:
		return { "success": false, "error": "not_ready" }
	if _prototype_initial_closed_mask_hash != 0:
		return { "success": true, "already_captured": true }
	var chunk_view: ChunkView = _target_chunk_view()
	var source: Sprite2D = _target_mountain_mask_sprite()
	if chunk_view == null or source == null or not _production_dual_masks_ready():
		return { "success": false, "error": "target_production_dual_masks_not_ready" }
	_prototype_initial_base_mask_hash = _current_base_mask_hash()
	_prototype_initial_closed_mask_hash = _current_closed_roof_mask_hash()
	_prototype_closed_mask_hash = _prototype_initial_closed_mask_hash
	_prototype_base_sprite_id = source.get_instance_id()
	_prototype_base_texture_id = source.texture.get_instance_id()
	_prototype_base_material_id = source.material.get_instance_id()
	_prototype_phase = PROTOTYPE_PHASE_CAPTURED
	return {
		"success": true,
		"initial_base_mask_hash": _prototype_initial_base_mask_hash,
		"closed_mask_hash": _prototype_initial_closed_mask_hash,
		"byte_count": chunk_view._mountain_closed_roof_mask_bytes.size(),
		"roof_texture_id": _prototype_roof_texture_id,
	}


## Запускает автоматический dev-only сценарий: capture -> шесть публичных
## копков -> ожидание native rebuild -> OUTSIDE. P вызывает именно этот путь.
func debug_start_roof_prototype() -> Dictionary:
	if _prototype_phase == PROTOTYPE_PHASE_READY:
		return { "success": true, "already_ready": true }
	if _prototype_phase == PROTOTYPE_PHASE_DIGGING \
			or _prototype_phase == PROTOTYPE_PHASE_WAITING_NATIVE \
			or _prototype_phase == PROTOTYPE_PHASE_WAITING_CAPTURE:
		return { "success": true, "already_running": true }
	if _prototype_phase == PROTOTYPE_PHASE_FAILED:
		return { "success": false, "error": _prototype_error }
	var capture: Dictionary = debug_capture_prototype_closed_roof()
	if not bool(capture.get("success", false)):
		if str(capture.get("error", "")) == "target_production_dual_masks_not_ready":
			_prototype_phase = PROTOTYPE_PHASE_WAITING_CAPTURE
			return { "success": true, "pending_capture": true }
		_fail_prototype("capture failed: %s" % str(capture))
		return capture
	_begin_prototype_digging()
	return { "success": true, "phase": String(_prototype_phase) }


## Один элемент T публичным gameplay-путём. Метод оставлен отдельным, чтобы
## smoke мог доказать точный requested/actual tile без прямой записи diff.
func debug_dig_prototype_tile(index: int) -> Dictionary:
	var dig_tiles: Array = _dig_target.get("prototype_dig_tiles", []) as Array
	if _state != DevState.READY or _streamer == null:
		return { "success": false, "error": "not_ready" }
	if index < 0 or index >= dig_tiles.size():
		return { "success": false, "error": "dig_index_out_of_range", "index": index }
	var requested_tile: Vector2i = dig_tiles[index] as Vector2i
	var tile_origin: Vector2 = Vector2(
		float(requested_tile.x * WorldRuntimeConstants.TILE_SIZE_PX),
		float(requested_tile.y * WorldRuntimeConstants.TILE_SIZE_PX),
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
		if not bool(result.get("success", false)):
			continue
		# Mining chips are unrelated to the roof experiment and Godot's headless
		# renderer noisily rejects their tiny transient polygons.
		if _streamer._mining_feedback_layer != null:
			_streamer._mining_feedback_layer.clear_feedback()
		var actual_tile: Vector2i = (
			result.get("chunk_coord", Vector2i.ZERO) as Vector2i
		) * WorldRuntimeConstants.CHUNK_SIZE + (
			result.get("local_coord", Vector2i.ZERO) as Vector2i
		)
		result["requested_tile"] = requested_tile
		result["actual_tile"] = actual_tile
		if actual_tile != requested_tile:
			result["success"] = false
			result["error"] = "harvest_resolved_to_wrong_tile"
			return result
		var state: Dictionary = _prototype_tile_state(requested_tile)
		result["terrain_after"] = int(state.get("terrain_id", -1))
		result["terrain_walkable_after"] = bool(state.get("terrain_walkable", false))
		result["walkable_after"] = bool(state.get("mask_walkable", false))
		return result
	return {
		"success": false,
		"error": "no_diggable_sample_in_prototype_tile",
		"requested_tile": requested_tile,
	}


## Старое имя сохраняем для небольших внешних dev-скриптов: теперь оно копает
## строго mouth прототипа.
func debug_dig_target_once() -> Dictionary:
	return debug_dig_prototype_tile(0)


## Вызывается после worker reconcile и production visual upload.
func debug_finalize_prototype_after_dig() -> Dictionary:
	var roof: Sprite2D = _target_production_roof_sprite()
	if not _production_dual_masks_ready() or roof == null:
		return { "success": false, "error": "production_dual_masks_missing" }
	if _prototype_roof_sprite_id == 0:
		_prototype_roof_sprite_id = roof.get_instance_id()
		_prototype_roof_texture_id = roof.texture.get_instance_id()
		_prototype_roof_material_id = roof.material.get_instance_id() if roof.material != null else 0
	var tile_states: Array[Dictionary] = _prototype_tile_states()
	if _count_dug_floor_tiles(tile_states) != PROTOTYPE_T_OFFSETS.size():
		return {
			"success": false,
			"error": "prototype_t_not_fully_dug",
			"tile_states": tile_states,
		}
	var remaining_hash: int = _current_base_mask_hash()
	var closed_hash: int = _current_closed_roof_mask_hash()
	if remaining_hash == 0 or remaining_hash == _prototype_initial_base_mask_hash:
		return {
			"success": false,
			"error": "remaining_mass_not_rebuilt",
			"initial_base_hash": _prototype_initial_base_mask_hash,
			"current_hash": remaining_hash,
		}
	if closed_hash != _prototype_initial_closed_mask_hash:
		return {
			"success": false,
			"error": "closed_roof_changed_after_dig",
			"initial_closed_hash": _prototype_initial_closed_mask_hash,
			"current_closed_hash": closed_hash,
		}
	if _count_remaining_mask_open_tiles(tile_states) != PROTOTYPE_T_OFFSETS.size():
		return {
			"success": false,
			"error": "remaining_mass_kept_dug_tile_solid",
			"tile_states": tile_states,
		}
	if not _production_selector_settled(false):
		return { "success": false, "error": "outside_selector_not_settled" }
	_prototype_closed_mask_hash = closed_hash
	_prototype_open_mask_hash = remaining_hash
	_prototype_state_signature = _current_prototype_state_signature()
	_prototype_last_toggle_preserved_state = true
	_prototype_phase = PROTOTYPE_PHASE_READY
	return {
		"success": true,
		"closed_mask_hash": closed_hash,
		"open_mask_hash": _prototype_open_mask_hash,
		"outside": true,
	}


## Совместимое dev-имя. Ничего не меняет в ChunkView: только
## переносит Player, после чего MountainResolver срабатывает в physics tick.
func debug_set_prototype_inside(inside: bool) -> bool:
	return debug_place_player_for_prototype(inside)


func debug_place_player_for_prototype(inside: bool) -> bool:
	if _state != DevState.READY or _player == null:
		return false
	var tile: Vector2i = (
		_dig_target.get("junction_tile", Vector2i.ZERO) as Vector2i
	) if inside else (
		_dig_target.get("stand_tile", Vector2i.ZERO) as Vector2i
	)
	var before: String = _current_prototype_state_signature()
	_prototype_requested_inside = inside
	_player.global_position = WorldRuntimeConstants.tile_to_world_center(tile)
	var camera: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()
		camera.force_update_scroll()
	var after: String = _current_prototype_state_signature()
	_prototype_last_toggle_preserved_state = before == after \
		and (_prototype_state_signature.is_empty() or after == _prototype_state_signature)
	return true


func debug_place_player_at_world(world_position: Vector2) -> bool:
	if _prototype_phase != PROTOTYPE_PHASE_READY or _player == null:
		return false
	var before: String = _current_prototype_state_signature()
	_prototype_requested_inside = true
	_player.global_position = world_position
	var camera: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()
		camera.force_update_scroll()
	var after: String = _current_prototype_state_signature()
	_prototype_last_toggle_preserved_state = before == after \
		and after == _prototype_state_signature
	return true


## Finds a real organic C-solid/S-open fringe that belongs visually and
## physically to the active cave while its exact authored tile is not DUG.
## This is the regression for the roof-closes-at-an-organic-corner bug.
func debug_find_prototype_organic_fringe_candidate() -> Dictionary:
	if _prototype_phase != PROTOTYPE_PHASE_READY or _streamer == null or _player == null:
		return { "success": false, "error": "prototype_not_ready" }
	var active_component_id: int = _streamer._active_cover_component_id
	if active_component_id <= 0:
		return { "success": false, "error": "active_component_missing" }
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null:
		return { "success": false, "error": "target_chunk_missing" }
	var dig_tiles: Array = _dig_target.get("prototype_dig_tiles", []) as Array
	if dig_tiles.is_empty():
		return { "success": false, "error": "dig_tiles_missing" }
	var tile_min: Vector2i = dig_tiles[0] as Vector2i
	var tile_max: Vector2i = tile_min
	for tile_variant: Variant in dig_tiles:
		var tile: Vector2i = tile_variant as Vector2i
		tile_min.x = mini(tile_min.x, tile.x)
		tile_min.y = mini(tile_min.y, tile.y)
		tile_max.x = maxi(tile_max.x, tile.x)
		tile_max.y = maxi(tile_max.y, tile.y)
	var tile_size: int = WorldRuntimeConstants.TILE_SIZE_PX
	var search_min: Vector2i = (tile_min - Vector2i.ONE) * tile_size
	var search_max: Vector2i = (tile_max + Vector2i(2, 2)) * tile_size
	var target_mountain_id: int = int(_dig_target.get("mountain_id", 0))
	for world_y: int in range(search_min.y + 2, search_max.y, 2):
		for world_x: int in range(search_min.x + 2, search_max.x, 2):
			var world_position := Vector2(float(world_x), float(world_y))
			var exact_tile: Vector2i = WorldRuntimeConstants.world_to_tile(world_position)
			var exact_cover: Dictionary = _streamer.get_mountain_cover_sample(exact_tile)
			if not bool(exact_cover.get("ready", false)) \
					or int(exact_cover.get("component_id", 0)) != 0 \
					or int(exact_cover.get("mountain_id", 0)) != target_mountain_id:
				continue
			var tile_data: Dictionary = _streamer._get_tile_data(world_position)
			if int(tile_data.get("terrain_id", -1)) == WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
				continue
			var closed_value: int = _sample_target_mask_value_at_world(
				chunk_view._mountain_closed_roof_mask_bytes,
				world_position,
			)
			var remaining_value: int = _sample_target_mask_value_at_world(
				chunk_view._mountain_top_mask_bytes,
				world_position,
			)
			if closed_value <= ChunkView.MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD \
					or remaining_value > ChunkView.MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD:
				continue
			if not bool(_player.call("_can_occupy_world", world_position)):
				continue
			var resolved: Dictionary = _streamer.resolve_mountain_cover_at_world(
				world_position,
				active_component_id,
			)
			return {
				"success": true,
				"world_position": world_position,
				"tile": exact_tile,
				"active_component_id": active_component_id,
				"closed_value": closed_value,
				"remaining_value": remaining_value,
				"terrain_id": int(tile_data.get("terrain_id", -1)),
				"resolved": resolved,
			}
	return {
		"success": false,
		"error": "walkable_organic_fringe_not_found",
		"active_component_id": active_component_id,
		"search_tile_min": tile_min - Vector2i.ONE,
		"search_tile_max": tile_max + Vector2i.ONE,
	}


## CPU proof that OUTSIDE publishes a direction code, not a full active-floor
## selector byte. The shader turns this code into the sub-tile aperture.
func debug_get_prototype_mouth_aperture_state() -> Dictionary:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null:
		return { "ready": false }
	var mouth_tile: Vector2i = _dig_target.get("mountain_tile", Vector2i.ZERO) as Vector2i
	var direction_code: int = _sample_target_tile_halo_value(
		chunk_view._mountain_outside_mouth_halo_bytes,
		mouth_tile,
	)
	var active_value: int = _sample_target_tile_halo_value(
		chunk_view._mountain_active_floor_halo_bytes,
		mouth_tile,
	)
	var mouth_nonzero_count: int = 0
	var active_nonzero_count: int = 0
	for value: int in chunk_view._mountain_outside_mouth_halo_bytes:
		if value > 0:
			mouth_nonzero_count += 1
	for value: int in chunk_view._mountain_active_floor_halo_bytes:
		if value > 0:
			active_nonzero_count += 1
	return {
		"ready": true,
		"direction_code": direction_code,
		"active_value": active_value,
		"mouth_nonzero_count": mouth_nonzero_count,
		"active_nonzero_count": active_nonzero_count,
	}


## Проверяет тот же девятиточечный footprint, которым Player блокирует реальное
## движение, с шагом 4 px: снаружи -> mouth -> junction -> обе ветки T.
func debug_probe_prototype_player_traversal() -> Dictionary:
	if _prototype_phase != PROTOTYPE_PHASE_READY or _player == null:
		return { "success": false, "error": "prototype_not_ready" }
	var chunk_manager: Node = _player.call("_get_chunk_manager") as Node
	if chunk_manager == null:
		return { "success": false, "error": "player_chunk_manager_not_ready" }
	var dig_tiles: Array = _dig_target.get("prototype_dig_tiles", []) as Array
	if dig_tiles.size() != PROTOTYPE_T_OFFSETS.size():
		return { "success": false, "error": "prototype_footprint_missing" }
	var path_tiles: Array[Vector2i] = [
		_dig_target.get("stand_tile", Vector2i.ZERO) as Vector2i,
		_dig_target.get("junction_tile", Vector2i.ZERO) as Vector2i,
		dig_tiles[4] as Vector2i,
		_dig_target.get("junction_tile", Vector2i.ZERO) as Vector2i,
		dig_tiles[5] as Vector2i,
	]
	var checked_position_count: int = 0
	var min_footprint_sample_count: int = 999
	var native_open_sample_count: int = 0
	for segment_index: int in range(path_tiles.size() - 1):
		var from_world: Vector2 = WorldRuntimeConstants.tile_to_world_center(path_tiles[segment_index])
		var to_world: Vector2 = WorldRuntimeConstants.tile_to_world_center(path_tiles[segment_index + 1])
		var step_count: int = maxi(1, ceili(from_world.distance_to(to_world) / 4.0))
		for step_index: int in range(step_count + 1):
			var sample_position: Vector2 = from_world.lerp(to_world, float(step_index) / float(step_count))
			var footprint_samples: Array = _player.call("_build_occupancy_sample_points", sample_position) as Array
			min_footprint_sample_count = mini(min_footprint_sample_count, footprint_samples.size())
			checked_position_count += 1
			if not bool(_player.call("_can_occupy_world", sample_position)):
				return {
					"success": false,
					"error": "player_footprint_blocked",
					"blocked_position": sample_position,
					"checked_position_count": checked_position_count,
					"footprint_sample_count": footprint_samples.size(),
					"footprint_debug": _build_footprint_debug(footprint_samples),
				}
			for footprint_variant: Variant in footprint_samples:
				var footprint_point: Vector2 = footprint_variant as Vector2
				var footprint_tile: Vector2i = WorldRuntimeConstants.world_to_tile(footprint_point)
				var footprint_data: Dictionary = _streamer._get_tile_data(footprint_point)
				if int(footprint_data.get("terrain_id", -1)) \
						!= WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
					continue
				var native_hit: Dictionary = _streamer._sample_mountain_mask_hit(footprint_point)
				if not bool(native_hit.get("ready", false)):
					return {
						"success": false,
						"error": "remaining_mask_sample_not_ready",
						"tile": footprint_tile,
						"sample_position": footprint_point,
					}
				if bool(native_hit.get("solid", false)):
					return {
						"success": false,
						"error": "remaining_mask_residual_blocks_footprint",
						"tile": footprint_tile,
						"sample_position": footprint_point,
					}
				native_open_sample_count += 1
	return {
		"success": min_footprint_sample_count >= 9 and native_open_sample_count > 0,
		"checked_position_count": checked_position_count,
		"min_footprint_sample_count": min_footprint_sample_count,
		"native_open_sample_count": native_open_sample_count,
		"path_tile_count": path_tiles.size(),
	}


func _build_footprint_debug(footprint_samples: Array) -> Array[Dictionary]:
	var debug: Array[Dictionary] = []
	for point_variant: Variant in footprint_samples:
		var point: Vector2 = point_variant as Vector2
		var tile_data: Dictionary = _streamer._get_tile_data(point)
		var native_hit: Dictionary = _streamer._sample_mountain_mask_hit(point)
		debug.append({
			"point": point,
			"tile": WorldRuntimeConstants.world_to_tile(point),
			"walkable": _streamer.is_walkable_at_world(point),
			"terrain_id": int(tile_data.get("terrain_id", -1)),
			"terrain_walkable": bool(tile_data.get("walkable", false)),
			"native_ready": bool(native_hit.get("ready", false)),
			"native_solid": bool(native_hit.get("solid", false)),
		})
	return debug


func debug_get_prototype_retaining_wall_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	if _streamer == null:
		return states
	var retaining_tiles: Array = _dig_target.get("retaining_wall_tiles", []) as Array
	for tile_variant: Variant in retaining_tiles:
		var tile: Vector2i = tile_variant as Vector2i
		var state: Dictionary = _prototype_tile_state(tile)
		state["resource_bearing"] = _streamer.has_resource_at_world(
			WorldRuntimeConstants.tile_to_world_center(tile),
		)
		states.append(state)
	return states


func _tick_roof_prototype() -> void:
	if _prototype_phase == PROTOTYPE_PHASE_WAITING_CAPTURE:
		var capture: Dictionary = debug_capture_prototype_closed_roof()
		if bool(capture.get("success", false)):
			_begin_prototype_digging()
			return
		if str(capture.get("error", "")) != "target_production_dual_masks_not_ready":
			_fail_prototype("deferred capture failed: %s" % str(capture))
		return
	if _prototype_phase == PROTOTYPE_PHASE_DIGGING:
		if _prototype_dig_delay_frames > 0:
			_prototype_dig_delay_frames -= 1
			return
		var dig_tiles: Array = _dig_target.get("prototype_dig_tiles", []) as Array
		if _prototype_next_dig_index >= dig_tiles.size():
			_prototype_phase = PROTOTYPE_PHASE_WAITING_NATIVE
			debug_place_player_for_prototype(false)
			return
		var result: Dictionary = debug_dig_prototype_tile(_prototype_next_dig_index)
		if not bool(result.get("success", false)) \
				or int(result.get("terrain_after", -1)) != WorldRuntimeConstants.TERRAIN_PLAINS_DUG \
				or not bool(result.get("terrain_walkable_after", false)):
			_fail_prototype("dig %d failed: %s" % [_prototype_next_dig_index, str(result)])
			return
		_prototype_dig_results.append(result.duplicate(true))
		_prototype_next_dig_index += 1
		_prototype_dig_delay_frames = PROTOTYPE_DIG_DELAY_FRAMES
		return
	if _prototype_phase == PROTOTYPE_PHASE_WAITING_NATIVE \
			and _native_masks_settled_for_prototype() \
			and _production_selector_settled(false):
		if _target_production_roof_sprite() == null:
			_prototype_roof_wait_frames += 1
			if _prototype_roof_wait_frames > 180:
				_fail_prototype("production roof visual did not appear after settled dual masks")
			return
		var finalized: Dictionary = debug_finalize_prototype_after_dig()
		if not bool(finalized.get("success", false)):
			_fail_prototype("finalize failed: %s" % str(finalized))


func _begin_prototype_digging() -> void:
	_prototype_requested_inside = false
	_prototype_roof_wait_frames = 0
	_prototype_next_dig_index = 0
	_prototype_dig_delay_frames = 0
	_prototype_dig_results.clear()
	_prototype_phase = PROTOTYPE_PHASE_DIGGING


func _validate_prototype_lifecycle() -> void:
	if _prototype_phase == PROTOTYPE_PHASE_IDLE \
			or _prototype_phase == PROTOTYPE_PHASE_WAITING_CAPTURE \
			or _prototype_phase == PROTOTYPE_PHASE_FAILED \
			or _prototype_initial_closed_mask_hash == 0:
		return
	var chunk_view: ChunkView = _target_chunk_view()
	var roof: Sprite2D = _target_production_roof_sprite()
	if chunk_view == null:
		_fail_prototype("target chunk was unloaded; restart the dev scene")
		return
	# Untouched chunks intentionally do not instantiate the optimized overlay.
	# Once the six-tile cutout is finalized it becomes a required production
	# visual and must remain attached to this exact ChunkView.
	if _prototype_phase == PROTOTYPE_PHASE_READY \
			and (roof == null or roof.get_parent() != chunk_view):
		_fail_prototype("production roof disappeared after excavation")
		return
	if _current_closed_roof_mask_hash() != _prototype_initial_closed_mask_hash:
		_fail_prototype("production CLOSED mask changed after baseline capture")
		return
	if _prototype_phase == PROTOTYPE_PHASE_READY and (
		_current_base_mask_hash() != _prototype_open_mask_hash \
		or _current_prototype_state_signature() != _prototype_state_signature
	):
		_fail_prototype("production BASE/terrain state changed after final reconcile")


func _native_masks_settled_for_prototype() -> bool:
	if _streamer == null:
		return false
	# Streaming may legitimately keep unrelated visible chunks pending while the
	# deterministic remote fixture is complete. Its own ChunkView dirty flags,
	# bytes and texture instances are the scoped settle boundary.
	if not _production_dual_masks_ready():
		return false
	if _current_base_mask_hash() == 0 \
			or _current_base_mask_hash() == _prototype_initial_base_mask_hash:
		return false
	var tile_states: Array[Dictionary] = _prototype_tile_states()
	return _count_dug_floor_tiles(tile_states) == PROTOTYPE_T_OFFSETS.size() \
		and _count_remaining_mask_open_tiles(tile_states) == PROTOTYPE_T_OFFSETS.size()


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
			_fail("южная T-цель не найдена в радиусе %d чанков от чанка %s" % [
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


## Кольцевой scan через WorldCore с теми же generation-входами, что у
## стримера. Выбор жёстко south-facing и полностью внутри одного chunk.
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


func _find_dig_spot_in_packet(packet: Dictionary) -> Dictionary:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var foot_count: int = 0
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		if int(terrain_ids[index]) == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			foot_count += 1
	var result: Dictionary = { "foot_tile_count": foot_count }
	if terrain_ids.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or walkable_flags.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or mountain_ids.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or mountain_flags.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return result
	# Prefer the southernmost valid facade in the first deterministic packet.
	for local_y: int in range(WorldRuntimeConstants.CHUNK_SIZE - 2, 3, -1):
		for local_x: int in range(2, WorldRuntimeConstants.CHUNK_SIZE - 2):
			var mouth: Vector2i = Vector2i(local_x, local_y)
			var mouth_index: int = WorldRuntimeConstants.local_to_index(mouth)
			if not _is_solid_mountain_index(mouth_index, terrain_ids, walkable_flags, mountain_flags):
				continue
			var mountain_id: int = int(mountain_ids[mouth_index])
			if mountain_id <= 0:
				continue
			var stand: Vector2i = mouth + Vector2i.DOWN
			var stand_index: int = WorldRuntimeConstants.local_to_index(stand)
			if int(walkable_flags[stand_index]) == 0:
				continue
			if not _pattern_is_same_solid_mountain(
				mouth,
				PROTOTYPE_T_OFFSETS,
				mountain_id,
				terrain_ids,
				walkable_flags,
				mountain_ids,
				mountain_flags,
			):
				continue
			if not _pattern_is_same_solid_mountain(
				mouth,
				PROTOTYPE_RETAINING_WALL_OFFSETS,
				mountain_id,
				terrain_ids,
				walkable_flags,
				mountain_ids,
				mountain_flags,
			):
				continue
			var world_mouth: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + mouth
			var dig_tiles: Array[Vector2i] = []
			for offset: Vector2i in PROTOTYPE_T_OFFSETS:
				dig_tiles.append(world_mouth + offset)
			var retaining_wall_tiles: Array[Vector2i] = []
			for offset: Vector2i in PROTOTYPE_RETAINING_WALL_OFFSETS:
				retaining_wall_tiles.append(world_mouth + offset)
			result.merge({
				"mountain_tile": world_mouth,
				"stand_tile": chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + stand,
				"junction_tile": world_mouth + Vector2i(0, -3),
				"target_terrain_id": int(terrain_ids[mouth_index]),
				"mountain_id": mountain_id,
				"prototype_chunk_coord": chunk_coord,
				"prototype_dig_tiles": dig_tiles,
				"retaining_wall_tiles": retaining_wall_tiles,
			}, true)
			return result
	return result


func _pattern_is_same_solid_mountain(
		origin: Vector2i,
		offsets: Array[Vector2i],
		mountain_id: int,
		terrain_ids: PackedInt32Array,
		walkable_flags: PackedByteArray,
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
) -> bool:
	for offset: Vector2i in offsets:
		var local: Vector2i = origin + offset
		if local.x < 0 or local.y < 0 \
				or local.x >= WorldRuntimeConstants.CHUNK_SIZE \
				or local.y >= WorldRuntimeConstants.CHUNK_SIZE:
			return false
		var index: int = WorldRuntimeConstants.local_to_index(local)
		if not _is_solid_mountain_index(index, terrain_ids, walkable_flags, mountain_flags):
			return false
		if int(mountain_ids[index]) != mountain_id:
			return false
	return true


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


func _target_chunk_view() -> ChunkView:
	if _streamer == null or not _dig_target.has("prototype_chunk_coord"):
		return null
	return _streamer._chunk_views.get(
		_dig_target.get("prototype_chunk_coord", Vector2i.ZERO) as Vector2i,
		null,
	) as ChunkView


func _target_mountain_mask_sprite() -> Sprite2D:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null:
		return null
	var sprite: Sprite2D = chunk_view._mountain_top_mask_sprite
	if sprite == null or not is_instance_valid(sprite) or not sprite.visible:
		return null
	return sprite


func _target_production_roof_sprite() -> Sprite2D:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null:
		return null
	var sprite: Sprite2D = chunk_view._mountain_closed_roof_mask_sprite
	if sprite == null or not is_instance_valid(sprite) or not sprite.visible \
			or sprite.texture == null or sprite.material == null:
		return null
	return sprite


func _current_base_mask_hash() -> int:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null or chunk_view._mountain_top_mask_bytes.is_empty():
		return 0
	return hash(chunk_view._mountain_top_mask_bytes)


func _sample_target_mask_value_at_world(mask_bytes: PackedByteArray, world_position: Vector2) -> int:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null \
			or chunk_view._mountain_top_mask_width <= 0 \
			or chunk_view._mountain_top_mask_height <= 0 \
			or chunk_view._mountain_top_mask_step_px <= 0.0:
		return -1
	var pixel_x: int = floori(
		(world_position.x - chunk_view._mountain_top_mask_origin_world.x) \
				/ chunk_view._mountain_top_mask_step_px,
	)
	var pixel_y: int = floori(
		(world_position.y - chunk_view._mountain_top_mask_origin_world.y) \
				/ chunk_view._mountain_top_mask_step_px,
	)
	if pixel_x < 0 or pixel_y < 0 \
			or pixel_x >= chunk_view._mountain_top_mask_width \
			or pixel_y >= chunk_view._mountain_top_mask_height:
		return -1
	var index: int = pixel_y * chunk_view._mountain_top_mask_width + pixel_x
	return int(mask_bytes[index]) if index >= 0 and index < mask_bytes.size() else -1


func _sample_target_tile_halo_value(halo_bytes: PackedByteArray, world_tile: Vector2i) -> int:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null or chunk_view._mountain_dug_halo_side <= 0:
		return 0
	var halo_side: int = chunk_view._mountain_dug_halo_side
	var halo_radius: int = (halo_side - WorldRuntimeConstants.CHUNK_SIZE) / 2
	var local: Vector2i = world_tile \
		- chunk_view.chunk_coord * WorldRuntimeConstants.CHUNK_SIZE \
		+ Vector2i.ONE * halo_radius
	if local.x < 0 or local.y < 0 or local.x >= halo_side or local.y >= halo_side:
		return 0
	var index: int = local.y * halo_side + local.x
	return int(halo_bytes[index]) if index >= 0 and index < halo_bytes.size() else 0


func _current_closed_roof_mask_hash() -> int:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null or chunk_view._mountain_closed_roof_mask_bytes.is_empty():
		return 0
	return hash(chunk_view._mountain_closed_roof_mask_bytes)


func _current_dug_halo_hash() -> int:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null or chunk_view._mountain_dug_halo_bytes.is_empty():
		return 0
	return hash(chunk_view._mountain_dug_halo_bytes)


func _current_reveal_halo_hash() -> int:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null or chunk_view._mountain_active_floor_halo_bytes.is_empty():
		return 0
	return hash(chunk_view._mountain_active_floor_halo_bytes)


func _current_outside_mouth_halo_hash() -> int:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null or chunk_view._mountain_outside_mouth_halo_bytes.is_empty():
		return 0
	return hash(chunk_view._mountain_outside_mouth_halo_bytes)


func _current_outside_mouth_direction_or() -> int:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null:
		return 0
	var combined: int = 0
	for value: int in chunk_view._mountain_outside_mouth_halo_bytes:
		combined |= value
	return combined


func _current_outside_mouth_direction_codes() -> PackedInt32Array:
	var codes := PackedInt32Array()
	var seen: Dictionary = { }
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null:
		return codes
	for value: int in chunk_view._mountain_outside_mouth_halo_bytes:
		if value <= 0 or seen.has(value):
			continue
		seen[value] = true
		codes.append(value)
	codes.sort()
	return codes


func _production_dual_masks_ready() -> bool:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null:
		return false
	var expected_size: int = chunk_view._mountain_top_mask_width * chunk_view._mountain_top_mask_height
	return expected_size > 0 \
		and chunk_view._mountain_top_mask_bytes.size() == expected_size \
		and chunk_view._mountain_closed_roof_mask_bytes.size() == expected_size \
		and not chunk_view._mountain_dug_halo_bytes.is_empty() \
		and not chunk_view._mountain_active_floor_halo_bytes.is_empty() \
		and not chunk_view._mountain_outside_mouth_halo_bytes.is_empty() \
		and not chunk_view._mountain_top_mask_visual_dirty \
		and not chunk_view._mountain_closed_roof_mask_visual_dirty \
		and not chunk_view._mountain_dug_halo_visual_dirty \
		and not chunk_view._mountain_active_floor_halo_visual_dirty \
		and not bool(chunk_view.get_mountain_native_mask_debug_state().get(
			"roof_overlay_visual_pending",
			false,
		))


func _is_production_inside() -> bool:
	if _streamer == null or _player == null:
		return false
	var cover: Dictionary = _streamer.resolve_mountain_cover_at_world(
		_player.global_position,
		_streamer._active_cover_component_id,
	)
	var component_id: int = int(cover.get("component_id", 0))
	return component_id > 0 \
		and component_id == _streamer._active_cover_component_id \
		and int(cover.get("mountain_id", 0)) == _streamer._active_cover_mountain_id


func _production_selector_settled(expected_inside: bool) -> bool:
	var chunk_view: ChunkView = _target_chunk_view()
	if chunk_view == null or not _production_dual_masks_ready():
		return false
	var inside: bool = _is_production_inside()
	var reveal_count: int = 0
	for value: int in chunk_view._mountain_active_floor_halo_bytes:
		if value > 0:
			reveal_count += 1
	if expected_inside:
		return inside \
			and _streamer._active_cover_component_id > 0 \
			and reveal_count >= PROTOTYPE_T_OFFSETS.size()
	return not inside \
		and _streamer._active_cover_component_id == 0 \
		and reveal_count == 0


func _prototype_tile_state(tile: Vector2i) -> Dictionary:
	if _streamer == null:
		return { "tile": tile, "ready": false }
	var world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(tile)
	var data: Dictionary = _streamer._get_tile_data(world_pos)
	var native_hit: Dictionary = _streamer._sample_mountain_mask_hit(world_pos)
	return {
		"tile": tile,
		"ready": bool(data.get("ready", false)),
		"terrain_id": int(data.get("terrain_id", -1)),
		"terrain_walkable": bool(data.get("walkable", false)),
		"mask_walkable": _streamer.is_walkable_at_world(world_pos),
		"remaining_mask_ready": bool(native_hit.get("ready", false)),
		"remaining_mask_solid": bool(native_hit.get("solid", false)),
	}


func _prototype_tile_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	var dig_tiles: Array = _dig_target.get("prototype_dig_tiles", []) as Array
	for tile_variant: Variant in dig_tiles:
		states.append(_prototype_tile_state(tile_variant as Vector2i))
	return states


func _count_dug_floor_tiles(states: Array[Dictionary]) -> int:
	var count: int = 0
	for state: Dictionary in states:
		if bool(state.get("ready", false)) \
				and int(state.get("terrain_id", -1)) == WorldRuntimeConstants.TERRAIN_PLAINS_DUG \
				and bool(state.get("terrain_walkable", false)):
			count += 1
	return count


func _count_mask_walkable_tiles(states: Array[Dictionary]) -> int:
	var count: int = 0
	for state: Dictionary in states:
		if bool(state.get("mask_walkable", false)):
			count += 1
	return count


func _count_remaining_mask_open_tiles(states: Array[Dictionary]) -> int:
	var count: int = 0
	for state: Dictionary in states:
		if bool(state.get("remaining_mask_ready", false)) \
				and not bool(state.get("remaining_mask_solid", true)):
			count += 1
	return count


func _current_prototype_state_signature() -> String:
	var parts: PackedStringArray = PackedStringArray([
		str(_current_base_mask_hash()),
		str(_current_closed_roof_mask_hash()),
		str(_current_dug_halo_hash()),
		"mountain:%d" % int(_dig_target.get("mountain_id", 0)),
	])
	for state: Dictionary in _prototype_tile_states():
		parts.append("%s:%d:%d" % [
			str(state.get("tile", Vector2i.ZERO)),
			int(state.get("terrain_id", -1)),
			1 if bool(state.get("terrain_walkable", false)) else 0,
		])
	return "|".join(parts)


func _current_effective_roof_signature() -> String:
	return "%s|reveal:%d|mouth:%d|active:%d|inside:%d" % [
		_current_prototype_state_signature(),
		_current_reveal_halo_hash(),
		_current_outside_mouth_halo_hash(),
		_streamer._active_cover_component_id if _streamer != null else 0,
		1 if _is_production_inside() else 0,
	]


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


func _fail_prototype(reason: String) -> void:
	_prototype_error = reason
	_prototype_phase = PROTOTYPE_PHASE_FAILED
	push_error("mountain_roof_prototype: %s" % reason)


func _build_hud() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "DevHud"
	add_child(canvas)
	_hud_label = Label.new()
	_hud_label.name = "InfoLabel"
	_hud_label.anchor_top = 1.0
	_hud_label.anchor_bottom = 1.0
	_hud_label.offset_left = 16.0
	_hud_label.offset_right = 1040.0
	_hud_label.offset_top = -210.0
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
			_hud_label.text = "Конструкция горы: ждём spawn мира… (%d кадров)" % _wait_frames
		DevState.FAILED:
			_hud_label.text = "Конструкция горы: ОШИБКА — %s" % _fail_reason
		DevState.READY:
			var player_tile: Vector2i = WorldRuntimeConstants.world_to_tile(_player.global_position)
			var roof_state: String = "INSIDE (active cavity)" if _is_production_inside() else "OUTSIDE (closed roof)"
			_hud_label.text = "\n".join([
				"Production construction roof: mouth %s, mountain_id %d, игрок %s" % [
					str(_dig_target.get("mountain_tile", Vector2i.ZERO)),
					int(_dig_target.get("mountain_id", 0)),
					str(player_tile),
				],
				"P — выкопать T | V — перенести Player: %s | T — новая цель до запуска" % roof_state,
				"phase=%s, dug=%d/%d. BASE/CLOSED/reveal — production; видимость решает MountainResolver." % [
					String(_prototype_phase),
					_prototype_dig_results.size(),
					PROTOTYPE_T_OFFSETS.size(),
				],
				"WASD — движение | E — обычное копание | F7 маска | F10 контур | F11 коллайдеры",
			])
