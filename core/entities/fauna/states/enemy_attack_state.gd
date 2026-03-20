class_name EnemyAttackState
extends EntityState

func physics_update(_delta: float) -> void:
	var enemy: BasicEnemy = owner as BasicEnemy
	if not enemy:
		return
	if enemy.is_dead():
		machine.transition_to(&"dead")
		return
	if not enemy.has_attack_target():
		if enemy.has_target():
			machine.transition_to(&"investigate")
		else:
			machine.transition_to(&"idle")
		return
	enemy.move_to_target(1.2)
