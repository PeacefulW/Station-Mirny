class_name UndergroundFogState
extends RefCounted

## Lightweight fog-of-war state for underground Z-levels.
## Tracks which tiles the player has ever revealed and which are currently visible.
## Fog of War MVP — Iteration 1.

const REVEAL_RADIUS: int = 5

## All tiles the player has ever seen. Persists for the session.
var _revealed_tiles: Dictionary = {}
## Tiles currently within the reveal radius (subset of _revealed_tiles).
var _visible_tiles: Dictionary = {}
## Last player tile used for update — skip if unchanged.
var _last_player_tile: Vector2i = Vector2i(999999, 999999)

## Compute the set of tiles visible within radius of center.
func compute_visible_circle(center: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	var r_sq: int = REVEAL_RADIUS * REVEAL_RADIUS
	for dy: int in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
		for dx: int in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
			if dx * dx + dy * dy <= r_sq:
				result[Vector2i(center.x + dx, center.y + dy)] = true
	return result

## Update fog state based on new player position.
## Returns { "newly_visible": Dictionary, "newly_discovered": Dictionary }
## - newly_visible: tiles that just became VISIBLE (need fog erased)
## - newly_discovered: tiles that left VISIBLE → DISCOVERED (need dim fog tile)
func update(player_tile: Vector2i) -> Dictionary:
	if player_tile == _last_player_tile:
		return {"newly_visible": {}, "newly_discovered": {}}
	_last_player_tile = player_tile
	var new_visible: Dictionary = compute_visible_circle(player_tile)
	var newly_visible: Dictionary = {}
	var newly_discovered: Dictionary = {}
	# Tiles leaving visible → discovered
	for tile: Vector2i in _visible_tiles:
		if not new_visible.has(tile):
			newly_discovered[tile] = true
	# Tiles entering visible
	for tile: Vector2i in new_visible:
		if not _visible_tiles.has(tile):
			newly_visible[tile] = true
			_revealed_tiles[tile] = true
	_visible_tiles = new_visible
	return {"newly_visible": newly_visible, "newly_discovered": newly_discovered}

## Check if a tile has ever been revealed.
func is_revealed(tile: Vector2i) -> bool:
	return _revealed_tiles.has(tile)

## Check if a tile is currently visible.
func is_visible(tile: Vector2i) -> bool:
	return _visible_tiles.has(tile)

## Force-reveal tiles (e.g., after excavation). Marks as revealed + visible.
func force_reveal(tiles: Array) -> void:
	for tile: Variant in tiles:
		var t: Vector2i = tile as Vector2i
		_revealed_tiles[t] = true
		_visible_tiles[t] = true

## Clear all state (e.g., on level change or new game).
func clear() -> void:
	_revealed_tiles.clear()
	_visible_tiles.clear()
	_last_player_tile = Vector2i(999999, 999999)
