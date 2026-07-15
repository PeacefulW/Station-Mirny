extends SceneTree

const CHUNK_SIZE: int = 16
const CELL_COUNT: int = CHUNK_SIZE * CHUNK_SIZE
const HALO_RADIUS: int = 8
const HALO_SIDE: int = CHUNK_SIZE + HALO_RADIUS * 2

const TERRAIN_PLAINS_GROUND: int = 0
const TERRAIN_PLAINS_DUG: int = 2
const TERRAIN_MOUNTAIN_WALL: int = 3
const TERRAIN_MOUNTAIN_FOOT: int = 4
const TERRAIN_LAKE_BED_SHALLOW: int = 5
const MOUNTAIN_FLAG_WALL: int = 1 << 1
const MOUNTAIN_FLAG_FOOT: int = 1 << 2
const LAKE_FLAG_WATER_PRESENT: int = 1 << 0

var _failed: bool = false


func _init() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available.")
	if world_core == null:
		_finish()
		return
	_assert(
		world_core.has_method("build_chunk_halo_fields"),
		"WorldCore must bind build_chunk_halo_fields().",
	)
	if not world_core.has_method("build_chunk_halo_fields"):
		_finish()
		return

	var packets: Array[Dictionary] = []
	for _packet_index: int in range(9):
		packets.append(_make_plain_packet())

	# Centre packet: one remaining mountain tile, one excavated owned tile,
	# and one visible-water tile for terrain-edge shoreline detection.
	_set_mountain_tile(packets[4], Vector2i(0, 0), TERRAIN_MOUNTAIN_WALL, false, MOUNTAIN_FLAG_WALL)
	_set_mountain_tile(packets[4], Vector2i(1, 0), TERRAIN_PLAINS_DUG, true, MOUNTAIN_FLAG_FOOT)
	_set_visible_water_tile(packets[4], Vector2i(2, 0))
	# Bottom-right cell of the (-1,-1) packet maps to local (-1,-1).
	_set_mountain_tile(packets[0], Vector2i(15, 15), TERRAIN_MOUNTAIN_FOOT, false, MOUNTAIN_FLAG_FOOT)

	var result: Dictionary = world_core.call("build_chunk_halo_fields", packets, HALO_RADIUS) as Dictionary
	_assert(bool(result.get("success", false)), "Valid 3x3 packet input must succeed.")
	_assert(int(result.get("halo_side", -1)) == HALO_SIDE, "Halo side contract.")
	_assert(int(result.get("halo_cell_count", -1)) == HALO_SIDE * HALO_SIDE, "Halo cell-count contract.")
	_assert(int(result.get("remaining_count", -1)) == 2, "Remaining mountain count.")
	_assert(int(result.get("closed_count", -1)) == 3, "Closed roof count.")
	_assert(int(result.get("dug_count", -1)) == 1, "Excavated ownership count.")
	_assert(int(result.get("terrain_edge_solid_count", -1)) == HALO_SIDE * HALO_SIDE - 1, "Terrain solid count.")
	_assert(int(result.get("terrain_edge_open_count", -1)) == 1, "Terrain open-water count.")
	_assert(bool(result.get("has_any", false)), "Remaining mountain flag.")
	_assert(bool(result.get("has_closed", false)), "Closed roof flag.")
	_assert(bool(result.get("has_dug", false)), "Excavated ownership flag.")
	_assert(bool(result.get("has_terrain_edge_solid", false)), "Terrain-edge solid flag.")
	_assert(bool(result.get("has_terrain_edge_open", false)), "Terrain-edge open flag.")
	_assert(bool(result.get("has_shoreline", false)), "Shoreline flag.")

	var remaining: PackedByteArray = result.get("remaining_halo", PackedByteArray()) as PackedByteArray
	var closed: PackedByteArray = result.get("closed_halo", PackedByteArray()) as PackedByteArray
	var dug: PackedByteArray = result.get("dug_halo", PackedByteArray()) as PackedByteArray
	var terrain: PackedByteArray = result.get("terrain_edge_solid_halo", PackedByteArray()) as PackedByteArray
	_assert(remaining.size() == HALO_SIDE * HALO_SIDE, "Remaining halo shape.")
	_assert(closed.size() == HALO_SIDE * HALO_SIDE, "Closed halo shape.")
	_assert(dug.size() == HALO_SIDE * HALO_SIDE, "Dug halo shape.")
	_assert(terrain.size() == HALO_SIDE * HALO_SIDE, "Terrain-edge halo shape.")
	_assert(_at(remaining, Vector2i(8, 8)) == 1, "Centre remaining tile mapping.")
	_assert(_at(closed, Vector2i(8, 8)) == 1, "Centre closed tile mapping.")
	_assert(_at(dug, Vector2i(9, 8)) == 1, "Centre excavated tile mapping.")
	_assert(_at(closed, Vector2i(9, 8)) == 1, "Excavated tile remains closed-roof ownership.")
	_assert(_at(remaining, Vector2i(7, 7)) == 1, "North-west packet mapping.")
	_assert(_at(terrain, Vector2i(10, 8)) == 0, "Visible lake water remains terrain-edge open.")

	var malformed_packets: Array = packets.duplicate()
	var malformed_packet: Dictionary = (malformed_packets[0] as Dictionary).duplicate()
	malformed_packet["lake_flags"] = PackedByteArray([0])
	malformed_packets[0] = malformed_packet
	var malformed_result: Dictionary = world_core.call(
		"build_chunk_halo_fields",
		malformed_packets,
		HALO_RADIUS,
	) as Dictionary
	_assert(not bool(malformed_result.get("success", true)), "Malformed packet arrays must be rejected.")
	var radius_result: Dictionary = world_core.call("build_chunk_halo_fields", packets, CHUNK_SIZE + 1) as Dictionary
	_assert(not bool(radius_result.get("success", true)), "A 3x3 packet window must reject an uncovered halo radius.")
	_assert_void_boundary_source_parity(world_core, packets)
	_assert_randomized_reference_parity(world_core)
	_finish()


func _make_plain_packet() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(CELL_COUNT)
	terrain_ids.fill(TERRAIN_PLAINS_GROUND)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(CELL_COUNT)
	walkable_flags.fill(1)
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(CELL_COUNT)
	var mountain_flags := PackedByteArray()
	mountain_flags.resize(CELL_COUNT)
	var lake_flags := PackedByteArray()
	lake_flags.resize(CELL_COUNT)
	return {
		"terrain_ids": terrain_ids,
		"walkable_flags": walkable_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"lake_flags": lake_flags,
	}


func _set_mountain_tile(
	packet: Dictionary,
	local: Vector2i,
	terrain_id: int,
	walkable: bool,
	mountain_flag: int,
) -> void:
	var index: int = local.y * CHUNK_SIZE + local.x
	var terrain_ids: PackedInt32Array = packet["terrain_ids"] as PackedInt32Array
	var walkable_flags: PackedByteArray = packet["walkable_flags"] as PackedByteArray
	var mountain_ids: PackedInt32Array = packet["mountain_id_per_tile"] as PackedInt32Array
	var mountain_flags: PackedByteArray = packet["mountain_flags"] as PackedByteArray
	terrain_ids[index] = terrain_id
	walkable_flags[index] = 1 if walkable else 0
	mountain_ids[index] = 101
	mountain_flags[index] = mountain_flag
	packet["terrain_ids"] = terrain_ids
	packet["walkable_flags"] = walkable_flags
	packet["mountain_id_per_tile"] = mountain_ids
	packet["mountain_flags"] = mountain_flags


func _set_visible_water_tile(packet: Dictionary, local: Vector2i) -> void:
	var index: int = local.y * CHUNK_SIZE + local.x
	var terrain_ids: PackedInt32Array = packet["terrain_ids"] as PackedInt32Array
	var lake_flags: PackedByteArray = packet["lake_flags"] as PackedByteArray
	terrain_ids[index] = TERRAIN_LAKE_BED_SHALLOW
	lake_flags[index] = LAKE_FLAG_WATER_PRESENT
	packet["terrain_ids"] = terrain_ids
	packet["lake_flags"] = lake_flags


func _assert_randomized_reference_parity(world_core: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EEDC0DE
	var packets: Array[Dictionary] = []
	for _packet_index: int in range(9):
		var terrain_ids := PackedInt32Array()
		terrain_ids.resize(CELL_COUNT)
		var walkable_flags := PackedByteArray()
		walkable_flags.resize(CELL_COUNT)
		var mountain_ids := PackedInt32Array()
		mountain_ids.resize(CELL_COUNT)
		var mountain_flags := PackedByteArray()
		mountain_flags.resize(CELL_COUNT)
		var lake_flags := PackedByteArray()
		lake_flags.resize(CELL_COUNT)
		for index: int in range(CELL_COUNT):
			terrain_ids[index] = rng.randi_range(0, 6)
			walkable_flags[index] = rng.randi_range(0, 1)
			mountain_ids[index] = 0 if rng.randi_range(0, 3) == 0 else rng.randi_range(1, 9)
			mountain_flags[index] = rng.randi_range(0, 15)
			lake_flags[index] = rng.randi_range(0, 3)
		packets.append({
			"terrain_ids": terrain_ids,
			"walkable_flags": walkable_flags,
			"mountain_id_per_tile": mountain_ids,
			"mountain_flags": mountain_flags,
			"lake_flags": lake_flags,
		})

	for radius: int in [1, 8, 16]:
		var native: Dictionary = world_core.call("build_chunk_halo_fields", packets, radius) as Dictionary
		var reference: Dictionary = _build_reference_halos(packets, radius)
		_assert(bool(native.get("success", false)), "Randomized native solve must succeed at radius %d." % radius)
		for field: String in ["remaining_halo", "closed_halo", "dug_halo", "terrain_edge_solid_halo"]:
			_assert(
				(native.get(field, PackedByteArray()) as PackedByteArray) \
						== (reference.get(field, PackedByteArray()) as PackedByteArray),
				"Randomized %s parity at radius %d." % [field, radius],
			)
		for field: String in [
			"remaining_count",
			"closed_count",
			"dug_count",
			"terrain_edge_solid_count",
			"terrain_edge_open_count",
		]:
			_assert(
				int(native.get(field, -1)) == int(reference.get(field, -2)),
				"Randomized %s metadata parity at radius %d." % [field, radius],
			)


func _assert_void_boundary_source_parity(world_core: Object, packets: Array[Dictionary]) -> void:
	var boundary_packets: Array[Dictionary] = packets.duplicate()
	for packet_index: int in range(3):
		boundary_packets[packet_index] = { "halo_source_present": false }
	var native: Dictionary = world_core.call(
		"build_chunk_halo_fields",
		boundary_packets,
		HALO_RADIUS,
	) as Dictionary
	var reference: Dictionary = _build_reference_halos(boundary_packets, HALO_RADIUS)
	_assert(bool(native.get("success", false)), "Explicit finite-boundary void sources must succeed.")
	for field: String in ["remaining_halo", "closed_halo", "dug_halo", "terrain_edge_solid_halo"]:
		_assert(
			(native.get(field, PackedByteArray()) as PackedByteArray) \
					== (reference.get(field, PackedByteArray()) as PackedByteArray),
			"Finite-boundary void %s parity." % field,
		)
	for field: String in [
		"remaining_count",
		"closed_count",
		"dug_count",
		"terrain_edge_solid_count",
		"terrain_edge_open_count",
	]:
		_assert(
			int(native.get(field, -1)) == int(reference.get(field, -2)),
			"Finite-boundary void %s metadata parity." % field,
		)


func _build_reference_halos(packets: Array[Dictionary], radius: int) -> Dictionary:
	var halo_side: int = CHUNK_SIZE + radius * 2
	var remaining := PackedByteArray()
	remaining.resize(halo_side * halo_side)
	var closed := PackedByteArray()
	closed.resize(halo_side * halo_side)
	var dug := PackedByteArray()
	dug.resize(halo_side * halo_side)
	var terrain_edge := PackedByteArray()
	terrain_edge.resize(halo_side * halo_side)
	var local_min: int = -radius
	var local_max: int = CHUNK_SIZE + radius
	for source_offset_y: int in range(-1, 2):
		var from_local_y: int = maxi(local_min, source_offset_y * CHUNK_SIZE)
		var to_local_y: int = mini(local_max, (source_offset_y + 1) * CHUNK_SIZE)
		for source_offset_x: int in range(-1, 2):
			var from_local_x: int = maxi(local_min, source_offset_x * CHUNK_SIZE)
			var to_local_x: int = mini(local_max, (source_offset_x + 1) * CHUNK_SIZE)
			var packet: Dictionary = packets[(source_offset_y + 1) * 3 + source_offset_x + 1]
			if not bool(packet.get("halo_source_present", true)):
				continue
			var terrain_ids: PackedInt32Array = packet["terrain_ids"] as PackedInt32Array
			var walkable_flags: PackedByteArray = packet["walkable_flags"] as PackedByteArray
			var mountain_ids: PackedInt32Array = packet["mountain_id_per_tile"] as PackedInt32Array
			var mountain_flags: PackedByteArray = packet["mountain_flags"] as PackedByteArray
			var lake_flags: PackedByteArray = packet["lake_flags"] as PackedByteArray
			for local_y: int in range(from_local_y, to_local_y):
				var source_y: int = local_y - source_offset_y * CHUNK_SIZE
				for local_x: int in range(from_local_x, to_local_x):
					var source_x: int = local_x - source_offset_x * CHUNK_SIZE
					var source_index: int = source_y * CHUNK_SIZE + source_x
					var halo_index: int = (local_y + radius) * halo_side + local_x + radius
					var terrain_id: int = terrain_ids[source_index]
					var water_present: bool = (int(lake_flags[source_index]) & LAKE_FLAG_WATER_PRESENT) != 0
					if not water_present \
							or (terrain_id != TERRAIN_LAKE_BED_SHALLOW and terrain_id != 6):
						terrain_edge[halo_index] = 1
					if mountain_ids[source_index] <= 0:
						continue
					var flags: int = mountain_flags[source_index]
					if (flags & (MOUNTAIN_FLAG_WALL | MOUNTAIN_FLAG_FOOT)) == 0:
						continue
					var walkable: bool = walkable_flags[source_index] != 0
					if not walkable \
							and (terrain_id == TERRAIN_MOUNTAIN_WALL or terrain_id == TERRAIN_MOUNTAIN_FOOT):
						remaining[halo_index] = 1
						closed[halo_index] = 1
					elif walkable and terrain_id == TERRAIN_PLAINS_DUG:
						dug[halo_index] = 1
						closed[halo_index] = 1
	var remaining_count: int = _count_ones(remaining)
	var closed_count: int = _count_ones(closed)
	var dug_count: int = _count_ones(dug)
	var terrain_count: int = _count_ones(terrain_edge)
	return {
		"remaining_halo": remaining,
		"closed_halo": closed,
		"dug_halo": dug,
		"terrain_edge_solid_halo": terrain_edge,
		"remaining_count": remaining_count,
		"closed_count": closed_count,
		"dug_count": dug_count,
		"terrain_edge_solid_count": terrain_count,
		"terrain_edge_open_count": halo_side * halo_side - terrain_count,
	}


func _count_ones(values: PackedByteArray) -> int:
	var count: int = 0
	for value: int in values:
		count += 1 if value != 0 else 0
	return count


func _at(values: PackedByteArray, position: Vector2i) -> int:
	var index: int = position.y * HALO_SIDE + position.x
	return int(values[index]) if index >= 0 and index < values.size() else -1


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[world_core_combined_halo_contract] %s" % message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("world_core_combined_halo_contract_smoke_test: PASS")
	quit(0)
