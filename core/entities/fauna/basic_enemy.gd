class_name BasicEnemy
extends CharacterBody2D

## Очиститель — слепое существо с гипертрофированным слухом.
## Реагирует на шум механизмов (NoiseComponent).
## НЕ видит игрока — атакует только при столкновении.
## Активнее ночью (больше радиус слуха).

# --- Состояния ---
enum State { IDLE, WANDER, INVESTIGATING, ATTACKING }

# --- Экспортируемые ---
@export var balance: EnemyBalance = null

# --- Приватные ---
var _state: State = State.IDLE
var _health_component: HealthComponent = null
var _attack_timer: float = 0.0
var _is_dead: bool = false

## Цель — позиция шума (не нода, а точка в мире).
var _target_pos: Vector2 = Vector2.ZERO
## Есть ли активная цель.
var _has_target: bool = false
## Таймер пересканирования шума.
var _scan_timer: float = 0.0
## Таймер смены направления при бродяжничестве.
var _wander_timer: float = 0.0
## Направление бродяжничества.
var _wander_dir: Vector2 = Vector2.ZERO
## Множитель слуха (ночью × 1.5).
var _hearing_multiplier: float = 1.0
## Базовый радиус слуха (в дополнение к noise_radius источника).
var _base_hearing: float = 50.0

const SCAN_INTERVAL: float = 1.5
const WANDER_INTERVAL: float = 3.0
const WANDER_SPEED_MULT: float = 0.4
const ARRIVAL_DISTANCE: float = 32.0
const PLAYER_DETECT_RADIUS: float = 60.0

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 | 2
	_health_component = get_node_or_null("HealthComponent")
	if _health_component:
		if balance:
			_health_component.max_health = balance.max_health
			_health_component.current_health = balance.max_health
		_health_component.died.connect(_on_died)
	_scan_timer = randf() * SCAN_INTERVAL
	_wander_timer = randf() * WANDER_INTERVAL
	_pick_wander_direction()
	# Подписка на ночь — активнее
	EventBus.time_of_day_changed.connect(_on_time_changed)

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_update_attack_timer(delta)
	_update_scan(delta)
	match _state:
		State.IDLE:
			_process_idle(delta)
		State.WANDER:
			_process_wander(delta)
		State.INVESTIGATING:
			_process_investigating(delta)
		State.ATTACKING:
			_process_attacking(delta)
	move_and_slide()
	_check_collisions()

# --- Состояния ---

func _process_idle(delta: float) -> void:
	velocity = Vector2.ZERO
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = WANDER_INTERVAL + randf() * 2.0
		_pick_wander_direction()
		_state = State.WANDER

func _process_wander(delta: float) -> void:
	if not balance:
		return
	velocity = _wander_dir * balance.move_speed * WANDER_SPEED_MULT
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_state = State.IDLE
		_wander_timer = 1.0 + randf() * 2.0

func _process_investigating(_delta: float) -> void:
	if not balance or not _has_target:
		_state = State.IDLE
		return
	var dir: Vector2 = (_target_pos - global_position)
	if dir.length() < ARRIVAL_DISTANCE:
		# Добрались до источника шума — бродим вокруг
		_has_target = false
		_state = State.WANDER
		_wander_timer = 2.0
		_pick_wander_direction()
		return
	velocity = dir.normalized() * balance.move_speed

func _process_attacking(_delta: float) -> void:
	if not balance or not _has_target:
		_state = State.IDLE
		return
	var dir: Vector2 = (_target_pos - global_position)
	velocity = dir.normalized() * balance.move_speed * 1.2

# --- Сканирование шума ---

func _update_scan(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = SCAN_INTERVAL

	var best_pos: Vector2 = Vector2.ZERO
	var best_priority: float = -1.0
	var found: bool = false

	# Сканируем все источники шума
	var sources: Array[Node] = get_tree().get_nodes_in_group("noise_sources")
	for node: Node in sources:
		var nc: NoiseComponent = node as NoiseComponent
		if not nc or not nc.is_active:
			continue
		var noise_pos: Vector2 = nc.get_noise_position()
		var dist: float = global_position.distance_to(noise_pos)
		var hear_range: float = (nc.noise_radius + _base_hearing) * _hearing_multiplier
		if dist > hear_range:
			continue
		# Приоритет: громкий и близкий шум — важнее
		var priority: float = nc.noise_level * (1.0 - dist / hear_range)
		if priority > best_priority:
			best_priority = priority
			best_pos = noise_pos
			found = true

	# Проверяем игрока — слышим только если ОЧЕНЬ близко
	# (шаги слышны на 60px, тогда как генератор на 250px)
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var player: Node2D = players[0] as Node2D
		var player_dist: float = global_position.distance_to(player.global_position)
		var player_hear: float = PLAYER_DETECT_RADIUS * _hearing_multiplier
		if player_dist < player_hear:
			var player_priority: float = 0.3 * (1.0 - player_dist / player_hear)
			if player_priority > best_priority:
				best_priority = player_priority
				best_pos = player.global_position
				found = true

	if found:
		_target_pos = best_pos
		_has_target = true
		_state = State.INVESTIGATING
	elif _state == State.INVESTIGATING and not _has_target:
		_state = State.IDLE

# --- Столкновения ---

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
		_target_pos = target_node.global_position
		_has_target = true
		_state = State.ATTACKING
	elif target_node.collision_layer & 2:
		health.take_damage(balance.damage_to_wall)

func _update_attack_timer(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta

# --- Утилиты ---

func _pick_wander_direction() -> void:
	var angle: float = randf() * TAU
	_wander_dir = Vector2.from_angle(angle)

func _on_time_changed(new_phase: int, _old_phase: int) -> void:
	# Ночью слышат в 1.5 раза дальше
	if new_phase == 3:  # NIGHT
		_hearing_multiplier = 1.5
	elif new_phase == 2:  # DUSK
		_hearing_multiplier = 1.2
	else:
		_hearing_multiplier = 1.0

func _on_died() -> void:
	_is_dead = true
	EventBus.enemy_killed.emit(global_position)
	_play_death()

func _play_death() -> void:
	var visual: Node2D = get_node_or_null("Visual") as Node2D
	if visual:
		var tween: Tween = create_tween()
		tween.tween_property(visual, "modulate:a", 0.0, 0.3)
		tween.tween_callback(queue_free)
	else:
		queue_free()
