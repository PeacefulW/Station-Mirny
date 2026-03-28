class_name BuildingSystem
extends Node2D

## Фасад системы строительства.
## Делегирует размещение, indoor-расчет и persistence профильным сервисам.

# --- Экспортируемые ---
@export var balance: BuildingBalance = null
@export var wall_container: Node2D = null

# --- Публичные ---
var is_build_mode: bool = false
## Все постройки на сетке: Vector2i -> Node2D.
var _walls: Dictionary = {}
## Ячейки внутри замкнутых комнат: Vector2i -> true.
var indoor_cells: Dictionary = {}

# --- Приватные ---
var _player_scrap: int = 0
var _player: Player = null
var _placement_service: BuildingPlacementService = BuildingPlacementService.new()
var _indoor_solver: IndoorSolver = IndoorSolver.new()
var _persistence: BuildingPersistence = BuildingPersistence.new()
var _command_executor: CommandExecutor = null
var _chunk_manager: ChunkManager = null
var _z_level_manager: ZLevelManager = null
var _dirty_room_regions: Array[Dictionary] = []
var _full_room_rebuild_state: Dictionary = {}
var _room_job_id: StringName = &""

# --- Встроенные ---

func _ready() -> void:
	add_to_group("building_system")
	if not wall_container:
		wall_container = get_node_or_null("../WallContainer") as Node2D
	if not wall_container:
		push_error(Localization.t("SYSTEM_BUILD_WALL_CONTAINER_MISSING"))
		return
	_player = _find_player()
	_chunk_manager = _find_chunk_manager()
	_z_level_manager = _find_z_level_manager()
	_placement_service.setup(balance, wall_container)
	_walls = _placement_service.walls
	indoor_cells = _indoor_solver.indoor_cells
	_command_executor = _find_command_executor()
	EventBus.scrap_collected.connect(_on_scrap_collected)
	EventBus.scrap_spent.connect(func(_a: int, remaining: int) -> void: _player_scrap = remaining)
	_room_job_id = FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_TOPOLOGY,
		1.5,
		_room_recompute_tick,
		&"building.room_recompute",
		RuntimeWorkTypes.CadenceKind.NEAR_PLAYER,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		false,
		"Room indoor recompute"
	)
	call_deferred("_connect_build_menu")

func _exit_tree() -> void:
	if _room_job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_room_job_id)

func _process(_delta: float) -> void:
	if is_build_mode:
		queue_redraw()

func _draw() -> void:
	for cell_pos: Vector2i in indoor_cells:
		var world_pos: Vector2 = grid_to_world(cell_pos)
		var half_grid: Vector2 = _placement_service.get_half_grid()
		var grid_size: int = _placement_service.get_grid_size()
		var rect := Rect2(world_pos - half_grid, Vector2(grid_size, grid_size))
		draw_rect(rect, Color(0.1, 0.25, 0.12, 0.35))
	if not is_build_mode:
		return
	var selected: BuildingData = _placement_service.get_selected_building()
	if not selected:
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	var grid_pos: Vector2i = world_to_grid(mouse_world)
	var grid_size: int = _placement_service.get_grid_size()
	var origin_world := Vector2(grid_pos.x * grid_size, grid_pos.y * grid_size)
	var full_size := Vector2(selected.size_x * grid_size, selected.size_y * grid_size)
	var can_place: bool = can_place_selected_building_at(mouse_world)
	var ghost_color: Color
	if can_place:
		ghost_color = Color(selected.placeholder_color, 0.55)
	else:
		ghost_color = Color(0.9, 0.2, 0.2, 0.35)
	draw_rect(Rect2(origin_world, full_size), ghost_color)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build_mode"):
		_toggle_build_mode()
	elif is_build_mode and event.is_action_pressed("primary_action"):
		_execute_place_command()
	elif is_build_mode and event.is_action_pressed("secondary_action"):
		_execute_remove_command()

# --- Публичные методы ---

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return _placement_service.world_to_grid(world_pos)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return _placement_service.grid_to_world(grid_pos)

func is_cell_indoor(grid_pos: Vector2i) -> bool:
	return indoor_cells.has(grid_pos)

func get_grid_size() -> int:
	return _placement_service.get_grid_size()

func has_pending_room_recompute() -> bool:
	return not _dirty_room_regions.is_empty() or not _full_room_rebuild_state.is_empty()

func has_building_at(grid_pos: Vector2i) -> bool:
	return _walls.has(grid_pos)

func get_building_node_at(grid_pos: Vector2i) -> Node2D:
	return _walls.get(grid_pos) as Node2D

func can_place_selected_building_at(world_pos: Vector2) -> bool:
	var grid_pos: Vector2i = world_to_grid(world_pos)
	var selected_building: BuildingData = _placement_service.get_selected_building()
	if not selected_building:
		return false
	if not _is_building_placement_allowed_on_active_z():
		return false
	if not _placement_service.can_place_at(grid_pos, _player_scrap):
		return false
	for dx: int in range(selected_building.size_x):
		for dy: int in range(selected_building.size_y):
			var cell: Vector2i = Vector2i(grid_pos.x + dx, grid_pos.y + dy)
			if not _is_buildable_grid_cell(cell):
				return false
	return true

## Задать выбранную постройку (делегирование в placement-сервис).
func set_selected_building(building: BuildingData) -> void:
	_placement_service.set_selected_building(building)

## Сохранить состояние системы строительства.
func save_state() -> Dictionary:
	return _persistence.save_state(_walls)

## Восстановить состояние системы строительства.
func load_state(data: Dictionary) -> void:
	_persistence.load_state(data, _create_building_from_persistence, _clear_buildings_for_persistence)
	_dirty_room_regions.clear()
	_full_room_rebuild_state.clear()
	# Boot/load path: sync full rebuild is acceptable behind loading screen (ADR-0001).
	indoor_cells = _indoor_solver.recalculate(_walls)
	EventBus.rooms_recalculated.emit(indoor_cells)
	queue_redraw()

# --- Приватные ---

func _connect_build_menu() -> void:
	var menus: Array[Node] = get_tree().get_nodes_in_group("build_menu")
	if menus.is_empty():
		return
	var menu: Node = menus[0]
	if menu.has_signal("building_selected") and not menu.building_selected.is_connected(_on_menu_selection):
		menu.building_selected.connect(_on_menu_selection)

func _on_menu_selection(building: BuildingData) -> void:
	set_selected_building(building)

func _toggle_build_mode() -> void:
	is_build_mode = not is_build_mode
	if not is_build_mode:
		queue_redraw()
	EventBus.build_mode_changed.emit(is_build_mode)

func place_selected_building_at(world_pos: Vector2) -> Dictionary:
	var _t: int = WorldPerfProbe.begin()
	var grid_pos: Vector2i = world_to_grid(world_pos)
	var selected_building: BuildingData = _placement_service.get_selected_building()
	if not selected_building:
		return {"success": false, "message_key": "SYSTEM_BUILD_NOT_SELECTED"}
	if not can_place_selected_building_at(world_pos):
		return {"success": false, "message_key": "SYSTEM_BUILD_CANNOT_PLACE"}
	var cost: int = _placement_service.get_selected_building_cost()
	if not _player and not _find_player():
		return {"success": false, "message_key": "SYSTEM_PLAYER_NOT_FOUND"}
	if not _player.spend_scrap(cost):
		return {"success": false, "message_key": "SYSTEM_BUILD_NOT_ENOUGH_SCRAP"}
	_player_scrap = _player.get_scrap_count()
	var placed_pos: Vector2i = _placement_service.place_selected_at(world_pos)
	if placed_pos == Vector2i(2147483647, 2147483647):
		_player.collect_scrap(cost)
		_player_scrap = _player.get_scrap_count()
		return {"success": false, "message_key": "SYSTEM_BUILD_CREATE_FAILED"}
	var building_node: Node2D = _walls.get(placed_pos)
	if not building_node:
		_player.collect_scrap(cost)
		_player_scrap = _player.get_scrap_count()
		return {"success": false, "message_key": "SYSTEM_BUILD_CREATE_FAILED"}
	EventBus.scrap_spent.emit(cost, _player_scrap)
	_bind_building_health(building_node, placed_pos)
	_mark_rooms_dirty(_get_node_footprint(building_node, placed_pos), &"place")
	EventBus.building_placed.emit(placed_pos)
	WorldPerfProbe.end("BuildingSystem.place_building", _t)
	return {
		"success": true,
		"message_key": "SYSTEM_BUILD_PLACED",
		"message_args": {
			"building": selected_building.get_display_name(),
		},
		"grid_pos": placed_pos,
		"building_id": str(selected_building.id),
	}

func remove_building_at(world_pos: Vector2) -> Dictionary:
	var _t: int = WorldPerfProbe.begin()
	var removal_result: Dictionary = _placement_service.remove_at(world_pos)
	if removal_result.is_empty():
		return {"success": false, "message_key": "SYSTEM_BUILD_NOT_FOUND"}
	var removed_pos: Vector2i = removal_result.get("grid_pos", Vector2i.ZERO)
	var building_id: String = str(removal_result.get("building_id", ""))
	var refund_amount: int = 1
	var dirty_size := Vector2i.ONE
	var building_data: BuildingData = _placement_service.get_building_data_by_id(building_id)
	if building_data:
		refund_amount = maxi(building_data.scrap_cost, 0)
		dirty_size = Vector2i(maxi(building_data.size_x, 1), maxi(building_data.size_y, 1))
	if _player or _find_player():
		_player.collect_scrap(refund_amount)
	_mark_rooms_dirty(_make_building_footprint(removed_pos, dirty_size), &"remove")
	EventBus.building_removed.emit(removed_pos)
	WorldPerfProbe.end("BuildingSystem.remove_building", _t)
	return {
		"success": true,
		"message_key": "SYSTEM_BUILD_REMOVED",
		"message_args": {
			"amount": refund_amount,
		},
		"grid_pos": removed_pos,
		"refund_amount": refund_amount,
	}

func _on_building_destroyed(grid_pos: Vector2i) -> void:
	var _t: int = WorldPerfProbe.begin()
	if not _walls.has(grid_pos):
		return
	var node: Node2D = _walls[grid_pos]
	var footprint: Rect2i = _get_node_footprint(node, grid_pos)
	var origin: Vector2i = node.get_meta("grid_origin", grid_pos) as Vector2i
	var sx: int = int(node.get_meta("size_x", 1))
	var sy: int = int(node.get_meta("size_y", 1))
	for dx: int in range(sx):
		for dy: int in range(sy):
			_walls.erase(Vector2i(origin.x + dx, origin.y + dy))
	node.queue_free()
	_mark_rooms_dirty(footprint, &"destroy")
	EventBus.building_removed.emit(origin)
	WorldPerfProbe.end("BuildingSystem.destroy_building", _t)

func _mark_rooms_dirty(footprint: Rect2i, reason: StringName) -> void:
	_enqueue_room_dirty_region(footprint, reason)

func _room_recompute_tick() -> bool:
	if not _full_room_rebuild_state.is_empty():
		return _advance_full_room_rebuild()
	if _dirty_room_regions.is_empty():
		return false
	var region: Dictionary = _dirty_room_regions.pop_front()
	var proof_bounds: Rect2i = region.get("padded_bounds", Rect2i())
	var patch: Dictionary = _indoor_solver.solve_local_patch(_walls, indoor_cells, proof_bounds)
	if not bool(patch.get("proof_succeeded", false)):
		var current_padding: int = int(region.get("proof_padding", _get_room_patch_padding()))
		var max_padding: int = _get_room_patch_max_padding()
		if current_padding < max_padding:
			var next_padding: int = mini(max_padding, current_padding + _get_room_patch_padding())
			_enqueue_room_dirty_region(region.get("footprint", Rect2i()), region.get("reason", StringName()), next_padding)
			return not _dirty_room_regions.is_empty()
		push_warning("[BuildingSystem] room patch exceeded local proof bounds; switching to staged full rebuild")
		_begin_full_room_rebuild()
		return true
	if _apply_room_patch(patch):
		_indoor_solver.indoor_cells = indoor_cells
		EventBus.rooms_recalculated.emit(indoor_cells)
		queue_redraw()
	return not _dirty_room_regions.is_empty()

func _begin_full_room_rebuild() -> void:
	_dirty_room_regions.clear()
	_full_room_rebuild_state = _indoor_solver.begin_recalculate_state(_walls)

func _advance_full_room_rebuild() -> bool:
	if _full_room_rebuild_state.is_empty():
		return false
	if not _dirty_room_regions.is_empty():
		_begin_full_room_rebuild()
	var is_complete: bool = _indoor_solver.advance_recalculate_state(
		_full_room_rebuild_state,
		_walls,
		_get_room_full_rebuild_flood_budget(),
		_get_room_full_rebuild_scan_budget()
	)
	if not is_complete:
		return true
	indoor_cells = _indoor_solver.finish_recalculate_state(_full_room_rebuild_state)
	_full_room_rebuild_state.clear()
	EventBus.rooms_recalculated.emit(indoor_cells)
	queue_redraw()
	return false

func _apply_room_patch(patch: Dictionary) -> bool:
	var changed: bool = false
	var removed_cells: Dictionary = patch.get("removed_cells", {})
	for cell: Vector2i in removed_cells:
		if indoor_cells.has(cell):
			indoor_cells.erase(cell)
			changed = true
	var added_cells: Dictionary = patch.get("added_cells", {})
	for cell: Vector2i in added_cells:
		if not indoor_cells.has(cell):
			indoor_cells[cell] = true
			changed = true
	return changed

func _enqueue_room_dirty_region(footprint: Rect2i, reason: StringName, preferred_padding: int = -1) -> void:
	var merged_region: Dictionary = _make_room_dirty_region(footprint, reason, preferred_padding)
	var merge_indices: Array[int] = []
	for index: int in range(_dirty_room_regions.size()):
		var existing: Dictionary = _dirty_room_regions[index]
		if _room_regions_overlap(existing, merged_region):
			merge_indices.append(index)
			merged_region = _merge_room_dirty_regions(existing, merged_region)
	if merge_indices.is_empty():
		_dirty_room_regions.append(merged_region)
		return
	_dirty_room_regions[merge_indices[0]] = merged_region
	for idx: int in range(merge_indices.size() - 1, 0, -1):
		_dirty_room_regions.remove_at(merge_indices[idx])

func _make_room_dirty_region(footprint: Rect2i, reason: StringName, preferred_padding: int = -1) -> Dictionary:
	var padding: int = preferred_padding
	if padding < 0:
		padding = _get_room_patch_padding()
	padding = clampi(padding, _get_room_patch_padding(), _get_room_patch_max_padding())
	return {
		"footprint": footprint,
		"padded_bounds": _grow_rect(footprint, padding),
		"reason": reason,
		"proof_padding": padding,
	}

func _merge_room_dirty_regions(lhs: Dictionary, rhs: Dictionary) -> Dictionary:
	var merged_footprint: Rect2i = _merge_rects(lhs.get("footprint", Rect2i()), rhs.get("footprint", Rect2i()))
	var merged_padding: int = maxi(int(lhs.get("proof_padding", _get_room_patch_padding())), int(rhs.get("proof_padding", _get_room_patch_padding())))
	var lhs_reason: StringName = lhs.get("reason", StringName())
	var rhs_reason: StringName = rhs.get("reason", StringName())
	var merged_reason: StringName = lhs_reason if lhs_reason == rhs_reason else &"mixed"
	return {
		"footprint": merged_footprint,
		"padded_bounds": _grow_rect(merged_footprint, merged_padding),
		"reason": merged_reason,
		"proof_padding": merged_padding,
	}

func _room_regions_overlap(lhs: Dictionary, rhs: Dictionary) -> bool:
	var gap: int = _get_room_patch_merge_gap()
	return _rects_intersect(_grow_rect(lhs.get("padded_bounds", Rect2i()), gap), _grow_rect(rhs.get("padded_bounds", Rect2i()), gap))

func _make_building_footprint(origin: Vector2i, size: Vector2i) -> Rect2i:
	return Rect2i(origin, Vector2i(maxi(size.x, 1), maxi(size.y, 1)))

func _get_node_footprint(node: Node2D, fallback_origin: Vector2i) -> Rect2i:
	var origin: Vector2i = node.get_meta("grid_origin", fallback_origin) as Vector2i
	var sx: int = int(node.get_meta("size_x", 1))
	var sy: int = int(node.get_meta("size_y", 1))
	return _make_building_footprint(origin, Vector2i(sx, sy))

func _grow_rect(rect: Rect2i, amount: int) -> Rect2i:
	var grow_by: int = maxi(amount, 0)
	var grow_vec := Vector2i(grow_by, grow_by)
	return Rect2i(rect.position - grow_vec, rect.size + grow_vec * 2)

func _merge_rects(lhs: Rect2i, rhs: Rect2i) -> Rect2i:
	var min_x: int = mini(lhs.position.x, rhs.position.x)
	var min_y: int = mini(lhs.position.y, rhs.position.y)
	var max_x: int = maxi(lhs.position.x + lhs.size.x, rhs.position.x + rhs.size.x)
	var max_y: int = maxi(lhs.position.y + lhs.size.y, rhs.position.y + rhs.size.y)
	return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x, max_y - min_y))

func _rects_intersect(lhs: Rect2i, rhs: Rect2i) -> bool:
	return lhs.position.x < rhs.position.x + rhs.size.x \
		and rhs.position.x < lhs.position.x + lhs.size.x \
		and lhs.position.y < rhs.position.y + rhs.size.y \
		and rhs.position.y < lhs.position.y + lhs.size.y

func _get_room_patch_padding() -> int:
	if balance:
		return maxi(balance.room_patch_padding, 1)
	return 6

func _get_room_patch_max_padding() -> int:
	if balance:
		return maxi(balance.room_patch_max_padding, _get_room_patch_padding())
	return 32

func _get_room_patch_merge_gap() -> int:
	if balance:
		return maxi(balance.room_patch_merge_gap, 0)
	return 2

func _get_room_full_rebuild_flood_budget() -> int:
	if balance:
		return maxi(balance.room_full_rebuild_flood_budget, 64)
	return 192

func _get_room_full_rebuild_scan_budget() -> int:
	if balance:
		return maxi(balance.room_full_rebuild_scan_budget, 64)
	return 256

func _on_scrap_collected(total: int) -> void:
	_player_scrap = total

func _find_player() -> Player:
	_player = PlayerAuthority.get_local_player()
	return _player

func _find_command_executor() -> CommandExecutor:
	var executors: Array[Node] = get_tree().get_nodes_in_group("command_executor")
	if executors.is_empty():
		return null
	return executors[0] as CommandExecutor

func _find_chunk_manager() -> ChunkManager:
	var managers: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if managers.is_empty():
		return null
	return managers[0] as ChunkManager

func _find_z_level_manager() -> ZLevelManager:
	var managers: Array[Node] = get_tree().get_nodes_in_group("z_level_manager")
	if managers.is_empty():
		return null
	return managers[0] as ZLevelManager

func _is_building_placement_allowed_on_active_z() -> bool:
	if not _z_level_manager:
		_z_level_manager = _find_z_level_manager()
	if not _z_level_manager:
		return true
	return _z_level_manager.get_current_z() == 0

func _is_buildable_grid_cell(grid_pos: Vector2i) -> bool:
	if not _chunk_manager:
		_chunk_manager = _find_chunk_manager()
	if not _chunk_manager:
		return true
	var world_pos: Vector2 = grid_to_world(grid_pos)
	if not _chunk_manager.is_walkable_at_world(world_pos):
		return false
	if not WorldGenerator:
		return true
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(world_pos)
	var terrain_type: int = _chunk_manager.get_terrain_type_at_global(tile_pos)
	return terrain_type != TileGenData.TerrainType.ROCK and terrain_type != TileGenData.TerrainType.WATER

func _execute_place_command() -> void:
	if not _command_executor:
		_command_executor = _find_command_executor()
	if not _command_executor:
		place_selected_building_at(get_global_mouse_position())
		return
	var command := PlaceBuildingCommand.new().setup(self, get_global_mouse_position())
	_command_executor.execute(command)

func _execute_remove_command() -> void:
	if not _command_executor:
		_command_executor = _find_command_executor()
	if not _command_executor:
		remove_building_at(get_global_mouse_position())
		return
	var command := RemoveBuildingCommand.new().setup(self, get_global_mouse_position())
	_command_executor.execute(command)

func _bind_building_health(node: Node2D, grid_pos: Vector2i) -> void:
	if not node:
		return
	var health: HealthComponent = node.get_node_or_null("HealthComponent")
	if health and not health.died.is_connected(_on_building_destroyed.bind(grid_pos)):
		health.died.connect(_on_building_destroyed.bind(grid_pos))

func _create_building_from_persistence(grid_pos: Vector2i, building_id: String) -> Node2D:
	var node: Node2D = _placement_service.create_building_by_id(grid_pos, building_id)
	_bind_building_health(node, grid_pos)
	return node

func _clear_buildings_for_persistence() -> void:
	_dirty_room_regions.clear()
	_full_room_rebuild_state.clear()
	_placement_service.clear_all_buildings()
	_indoor_solver.indoor_cells.clear()
	indoor_cells = _indoor_solver.indoor_cells
