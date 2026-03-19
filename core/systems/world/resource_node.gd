class_name ResourceNode
extends StaticBody2D

## Добываемый ресурс в мире (рудная жила, дерево, камень, водный источник).
## Создаётся ChunkManager при загрузке чанка на основе TileGenData.

# --- Сигналы ---
signal harvested(drop_item_id: StringName, amount: int)
signal depleted()

# --- Публичные ---
## Данные этого типа ресурса.
var data: ResourceNodeData = null
## Координаты тайла в глобальной сетке.
var tile_pos: Vector2i = Vector2i.ZERO
## Сколько раз ещё можно добыть.
var remaining_harvests: int = 0

# --- Приватные ---
var _visual: ColorRect = null
var _is_depleted: bool = false

## Инициализировать ресурсную ноду.
## Вызывается Chunk при создании.
func setup(p_data: ResourceNodeData, p_tile_pos: Vector2i, world_pos: Vector2) -> void:
	data = p_data
	tile_pos = p_tile_pos
	global_position = world_pos
	remaining_harvests = data.harvest_count
	name = "%s_%d_%d" % [data.id, tile_pos.x, tile_pos.y]
	add_to_group("resource_nodes")
	_create_visual()
	_create_collision()

## Попытаться добыть ресурс. Возвращает true при успехе.
func try_harvest() -> bool:
	if _is_depleted or not data:
		return false
	var amount: int = randi_range(data.drop_amount_min, data.drop_amount_max)
	remaining_harvests -= 1
	harvested.emit(data.drop_item_id, amount)
	if remaining_harvests <= 0 and data.harvest_count > 0:
		_become_depleted()
	else:
		_flash_visual()
	return true

## Получить состояние для сохранения.
func save_state() -> Dictionary:
	return {
		"tile_x": tile_pos.x,
		"tile_y": tile_pos.y,
		"remaining": remaining_harvests,
		"depleted": _is_depleted,
	}

## Восстановить состояние из сохранения.
func load_state(state: Dictionary) -> void:
	remaining_harvests = state.get("remaining", remaining_harvests)
	_is_depleted = state.get("depleted", false)
	if _is_depleted:
		_become_depleted()

# --- Приватные методы ---

func _create_visual() -> void:
	_visual = ColorRect.new()
	_visual.size = data.placeholder_size
	_visual.position = -data.placeholder_size * 0.5
	_visual.color = data.placeholder_color
	add_child(_visual)

func _create_collision() -> void:
	if not data.is_solid:
		return
	collision_layer = 2
	collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = data.collision_radius
	collision.shape = shape
	add_child(collision)

func _become_depleted() -> void:
	_is_depleted = true
	if _visual:
		_visual.color = Color(_visual.color, 0.2)
	depleted.emit()
	EventBus.resource_node_depleted.emit(tile_pos, data.deposit_type)

func _flash_visual() -> void:
	if not _visual:
		return
	var original_color: Color = data.placeholder_color
	_visual.color = Color.WHITE
	get_tree().create_timer(0.1).timeout.connect(
		func() -> void:
			if is_instance_valid(_visual):
				_visual.color = original_color
	)
