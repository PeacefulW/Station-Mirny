class_name BasicEnemy
extends CharacterBody2D

## Очиститель (базовый враг). Движется к игроку,
## атакует стены на пути и наносит урон при контакте.

# --- Экспортируемые ---
@export var balance: EnemyBalance = null

# --- Приватные ---
var _target: Node2D = null
var _health_component: HealthComponent = null
var _attack_timer: float = 0.0
var _is_dead: bool = false

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4   # Слой врагов
	collision_mask = 1 | 2  # Игрок + стены
	_health_component = get_node_or_null("HealthComponent")
	if _health_component:
		if balance:
			_health_component.max_health = balance.max_health
			_health_component.current_health = balance.max_health
		_health_component.died.connect(_on_died)
	# Найти игрока
	_find_target()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_update_attack_timer(delta)
	_move_toward_target()
	move_and_slide()
	_check_collisions()

# --- Приватные методы ---

func _find_target() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_target = players[0] as Node2D

func _move_toward_target() -> void:
	if not _target or not balance:
		velocity = Vector2.ZERO
		return
	var direction: Vector2 = (_target.global_position - global_position).normalized()
	velocity = direction * balance.move_speed

func _check_collisions() -> void:
	if not balance or _attack_timer > 0.0:
		return
	for i: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider is Node2D:
			_try_attack_target(collider as Node2D)

func _try_attack_target(target_node: Node2D) -> void:
	if not balance or _attack_timer > 0.0:
		return
	var health: HealthComponent = target_node.get_node_or_null("HealthComponent")
	if not health:
		return
	_attack_timer = balance.attack_cooldown
	if target_node.is_in_group("player"):
		health.take_damage(balance.damage_to_player)
	elif target_node.collision_layer & 2:  # Стена
		health.take_damage(balance.damage_to_wall)

func _update_attack_timer(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta

func _on_died() -> void:
	_is_dead = true
	# Дроп скрапа
	if balance:
		var drop: int = randi_range(balance.scrap_drop_min, balance.scrap_drop_max)
		EventBus.enemy_killed.emit(global_position)
		# Спавн пикапов обработает game_world
	_play_death()

func _play_death() -> void:
	var visual: ColorRect = get_node_or_null("Visual")
	if visual:
		var tween: Tween = create_tween()
		tween.tween_property(visual, "modulate:a", 0.0, 0.3)
		tween.tween_callback(queue_free)
	else:
		queue_free()
