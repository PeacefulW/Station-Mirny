class_name PlayerAuthorityService
extends Node

## Single point of truth for "who is the local player?"
##
## Replaces scattered get_nodes_in_group("player")[0] calls throughout the codebase.
## Currently single-player: returns the only player.
## Future multiplayer (ADR-0004): will distinguish local player from remote peers.
##
## All systems that need a player reference MUST go through this service.
## Do NOT call get_tree().get_nodes_in_group("player")[0] directly.

var _local_player: Player = null

func _ready() -> void:
	name = "PlayerAuthority"

## Returns the local player, or null if not yet available.
func get_local_player() -> Player:
	if is_instance_valid(_local_player):
		return _local_player
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	_local_player = players[0] as Player
	return _local_player

## Returns all players in the game. Currently 1, future: N.
func get_all_players() -> Array[Player]:
	var result: Array[Player] = []
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p: Player = node as Player
		if p:
			result.append(p)
	return result

## Returns the local player's global position, or Vector2.ZERO if unavailable.
func get_local_player_position() -> Vector2:
	var p: Player = get_local_player()
	return p.global_position if p else Vector2.ZERO

## Clear cached reference (e.g., on scene change or player death/respawn).
func clear_cache() -> void:
	_local_player = null
