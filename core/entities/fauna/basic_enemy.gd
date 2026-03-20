class_name BasicEnemy
extends CharacterBody2D

## Очиститель — слепое существо с гипертрофированным слухом.
## Реагирует на шум механизмов (NoiseComponent).
## НЕ видит игрока — атакует только при столкновении.
## Активнее ночью (больше радиус слуха).

# --- Экспортируемые ---
@export var balance: EnemyBalance = null

# --- Приватные ---
var _health_component: HealthComponent = null
var _attack_timer: float = 0.0
var _is_dead: bool = false
var _state_machine: StateMachine = StateMachine.new()

## Цель — позиция шума (не нода, а точка в мире).
var _target_pos: Vector2 = Vector2.ZERO
## Есть ли активная цель.
var _has_target: bool = false
var _attack_target: Node2D = null
## Таймер пересканирования шума.
var _scan_timer: float = 0.0
## Таймер смены направления при бродяжничестве.
var _wander_timer: float = 0.0
## Направление бродяжничества.
var _wander_dir: Vector2 = Vector2.ZERO
## Множитель слуха (ночью × 1.5).
var _hearing_multiplier: float = 1.0

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
	_scan_timer = randf() * balance.scan_interval
	_wander_timer = randf() * balance.wander_interval
	_pick_wander_direction()
	_setup_state_machine()
	# Подписка на ночь — активнее
	EventBus.time_of_day_changed.connect(_on_time_changed)

func _physics_process(delta: float) -> void:
	_update_attack_timer(delta)
	_update_scan(delta)
	_state_machine.physics_update(delta)
	move_and_slide()
	if not _is_dead:
		_check_collisions()

# --- Сканирование шума ---

func _update_scan(delta: float) -> void:
	if _is_dead:
		return
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = balance.scan_interval

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
		var hear_range: float = (nc.noise_radius + balance.base_hearing) * _hearing_multiplier
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
		var player_hear: float = balance.player_detect_radius * _hearing_multiplier
		if player_dist < player_hear:
			var player_priority: float = 0.3 * (1.0 - player_dist / player_hear)
			if player_priority > best_priority:
				best_priority = player_priority
				best_pos = player.global_position
				found = true

	if found:
		_target_pos = best_pos
		_has_target = true
		if not has_attack_target():
			_state_machine.transition_to(&"investigate")

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
		_attack_target = target_node
		_state_machine.transition_to(&"attack")
	elif target_node.collision_layer & 2:
		health.take_damage(balance.damage_to_wall)
		if target_node.has_meta("grid_pos"):
			EventBus.enemy_reached_wall.emit(target_node.get_meta("grid_pos"))

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
	_attack_target = null
	_has_target = false
	_state_machine.transition_to(&"dead")

func handle_death() -> void:
	velocity = Vector2.ZERO
	EventBus.enemy_killed.emit(global_position)
	var visual: Node2D = get_node_or_null("Visual") as Node2D
	if visual:
		var tween: Tween = create_tween()
		tween.tween_property(visual, "modulate:a", 0.0, 0.3)
		tween.tween_callback(queue_free)
	else:
		queue_free()

func stop_movement() -> void:
	velocity = Vector2.ZERO

func begin_wander() -> void:
	_pick_wander_direction()
	_wander_timer = balance.wander_interval + randf() * 2.0

func tick_wander(delta: float) -> void:
	if not balance:
		return
	velocity = _wander_dir * balance.move_speed * balance.wander_speed_mult
	_wander_timer -= delta

func tick_wander_timer(delta: float) -> void:
	_wander_timer -= delta

func is_wander_timer_finished() -> bool:
	return _wander_timer <= 0.0

func should_start_investigating() -> bool:
	return _has_target and not _is_dead

func has_target() -> bool:
	return _has_target

func has_attack_target() -> bool:
	return is_instance_valid(_attack_target)

func reached_target() -> bool:
	return global_position.distance_to(_target_pos) < balance.arrival_distance

func clear_target() -> void:
	_has_target = false
	_attack_target = null
	_wander_timer = 2.0
	_pick_wander_direction()

func move_to_target(speed_mult: float) -> void:
	if not balance or not _has_target:
		stop_movement()
		return
	if has_attack_target():
		_target_pos = _attack_target.global_position
	var dir: Vector2 = _target_pos - global_position
	if dir.length() <= 0.001:
		stop_movement()
		return
	velocity = dir.normalized() * balance.move_speed * speed_mult

func is_dead() -> bool:
	return _is_dead

func _setup_state_machine() -> void:
	_state_machine.setup(self)
	_state_machine.add_state(&"idle", EnemyIdleState.new())
	_state_machine.add_state(&"wander", EnemyWanderState.new())
	_state_machine.add_state(&"investigate", EnemyInvestigateState.new())
	_state_machine.add_state(&"attack", EnemyAttackState.new())
	_state_machine.add_state(&"dead", EnemyDeadState.new())
	_state_machine.transition_to(&"idle")
