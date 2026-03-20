class_name ZStairs
extends Area2D

## Лестница/люк для перехода между z-уровнями.
## Игрок наступает → автоматический переход с фейдом.

@export var target_z: int = -1
@export var stairs_type: StringName = &"stairs_down"
## Z-уровень, на котором расположена лестница.
@export var source_z: int = 0

var _cooldown: float = 0.0

func _ready() -> void:
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
	_cooldown = 1.0
	_trigger_transition()

## Запустить переход на целевой z-уровень.
func _trigger_transition() -> void:
	var game_world: Node = _find_game_world()
	if not game_world:
		return
	var z_manager: ZLevelManager = game_world.get_node_or_null("ZLevelManager") as ZLevelManager
	var overlay: ZTransitionOverlay = game_world.get_node_or_null("ZTransitionOverlay") as ZTransitionOverlay
	if not z_manager:
		return
	if overlay:
		overlay.do_transition(func() -> void: z_manager.change_level(target_z))
	else:
		z_manager.change_level(target_z)

func _find_game_world() -> Node:
	var node: Node = get_parent()
	while node:
		if node is GameWorld:
			return node
		node = node.get_parent()
	return null

func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	visible = (new_z == source_z)
	monitoring = (new_z == source_z)
	_cooldown = 0.5

func _create_collision() -> void:
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 10)
	col.shape = shape
	add_child(col)

func _create_visual() -> void:
	var cr := ColorRect.new()
	cr.size = Vector2(12, 12)
	cr.position = Vector2(-6, -6)
	if target_z < 0:
		cr.color = Color(0.6, 0.5, 0.2)
	else:
		cr.color = Color(0.3, 0.5, 0.8)
	add_child(cr)
