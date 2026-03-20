class_name EnemyWanderState
extends EntityState

func enter(_data: Dictionary = {}) -> void:
	var enemy: BasicEnemy = owner as BasicEnemy
	if enemy:
		enemy.begin_wander()

func physics_update(delta: float) -> void:
	var enemy: BasicEnemy = owner as BasicEnemy
	if not enemy:
		return
	if enemy.is_dead():
		machine.transition_to(&"dead")
		return
	if enemy.should_start_investigating():
		machine.transition_to(&"investigate")
		return
	enemy.tick_wander(delta)
	if enemy.is_wander_timer_finished():
		machine.transition_to(&"idle")
