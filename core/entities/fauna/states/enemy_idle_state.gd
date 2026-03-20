class_name EnemyIdleState
extends EntityState

func enter(_data: Dictionary = {}) -> void:
	var enemy: BasicEnemy = owner as BasicEnemy
	if enemy:
		enemy.stop_movement()

func physics_update(delta: float) -> void:
	var enemy: BasicEnemy = owner as BasicEnemy
	if not enemy:
		return
	enemy.stop_movement()
	enemy.tick_wander_timer(delta)
	if enemy.is_dead():
		machine.transition_to(&"dead")
	elif enemy.should_start_investigating():
		machine.transition_to(&"investigate")
	elif enemy.is_wander_timer_finished():
		machine.transition_to(&"wander")
