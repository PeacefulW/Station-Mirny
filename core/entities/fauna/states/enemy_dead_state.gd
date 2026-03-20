class_name EnemyDeadState
extends EntityState

func enter(_data: Dictionary = {}) -> void:
	var enemy: BasicEnemy = owner as BasicEnemy
	if enemy:
		enemy.handle_death()

func physics_update(_delta: float) -> void:
	var enemy: BasicEnemy = owner as BasicEnemy
	if enemy:
		enemy.stop_movement()
