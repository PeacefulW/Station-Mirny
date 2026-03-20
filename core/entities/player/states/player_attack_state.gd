class_name PlayerAttackState
extends EntityState

func enter(_data: Dictionary = {}) -> void:
	var player: Player = owner as Player
	if player:
		player.perform_attack()

func physics_update(delta: float) -> void:
	var player: Player = owner as Player
	if not player:
		return
	if player.is_dead():
		machine.transition_to(&"dead")
		return
	player.tick_attack_cooldown(delta)
	player.stop_movement()
	if not player.is_attack_busy():
		if player.has_move_input():
			machine.transition_to(&"move")
		else:
			machine.transition_to(&"idle")
