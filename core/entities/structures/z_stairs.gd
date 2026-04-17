class_name ZStairs
extends Area2D

## Лестница/люк для перехода между z-уровнями.
## Игрок наступает → автоматический переход с фейдом.

@export var target_z: int = -1
@export var stairs_type: StringName = &"stairs_down"
## Z-уровень, на котором расположена лестница.
@export var source_z: int = 0
## Баланс z-уровней (загружается из .tres).
@export var balance: ZLevelBalance = null

var _cooldown: float = 0.0

func _ready() -> void:
	if not balance:
		balance = load("res://data/balance/z_level_balance.tres") as ZLevelBalance
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	_create_collision()
	_create_visual()
	body_entered.connect(_on_body_entered)
	EventBus.z_level_changed.connect(_on_z_level_changed)
	visible = (source_z == 0)
	monitoring = (source_z == 0)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

func _on_body_entered(body: Node2D) -> void:
	if _cooldown > 0.0:
		return
	if not body.is_in_group("player"):
		return
	_cooldown = balance.stairs_cooldown if balance else 1.0
	_trigger_transition()

## Запустить переход на целевой z-уровень.
func _trigger_transition() -> void:
	var game_world: Node = _find_game_world()
	if not game_world:
		return
	if not game_world.has_method("request_z_transition"):
		return
	game_world.request_z_transition(target_z)

func _find_game_world() -> Node:
	var node: Node = get_parent()
	while node:
		if node.has_method("request_z_transition"):
			return node
		node = node.get_parent()
	return null

func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	visible = (new_z == source_z)
	monitoring = (new_z == source_z)
	_cooldown = balance.stairs_post_transition_cooldown if balance else 0.5

func _create_collision() -> void:
	var ts: int = _get_tile_size()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(ts - 2, ts - 2)
	col.shape = shape
	add_child(col)

func _create_visual() -> void:
	var ts: int = _get_tile_size()
	var half: float = ts * 0.5
	var cr := ColorRect.new()
	cr.size = Vector2(ts, ts)
	cr.position = Vector2(-half, -half)
	if balance:
		cr.color = balance.stairs_down_color if target_z < 0 else balance.stairs_up_color
	else:
		cr.color = Color(0.6, 0.5, 0.2) if target_z < 0 else Color(0.3, 0.5, 0.8)
	add_child(cr)

func _get_tile_size() -> int:
	return 12
