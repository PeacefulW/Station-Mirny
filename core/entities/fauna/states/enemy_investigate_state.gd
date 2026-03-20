class_name EnemyInvestigateState
extends EntityState

func physics_update(_delta: float) -> void:
	var enemy: BasicEnemy = owner as BasicEnemy
	if not enemy:
		return
	if enemy.is_dead():
		machine.transition_to(&"dead")
		return
	if not enemy.has_target():
		machine.transition_to(&"idle")
		return
	if enemy.has_attack_target():
		machine.transition_to(&"attack")
		return
	if enemy.reached_target():
		enemy.clear_target()
		machine.transition_to(&"wander")
		return
	enemy.move_to_target(1.0)
