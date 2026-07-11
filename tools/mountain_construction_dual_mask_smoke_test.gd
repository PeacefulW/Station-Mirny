extends SceneTree

const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")

const CHUNK_SIZE: int = 16
const TILE_SIZE_PX: int = 64
const HALO_RADIUS_TILES: int = 8
const HALO_SIDE: int = CHUNK_SIZE + HALO_RADIUS_TILES * 2
const PIXELS_PER_TILE: int = 8
const MASK_SIDE: int = HALO_SIDE * PIXELS_PER_TILE
const CORE_SAMPLE_COUNT: int = CHUNK_SIZE * CHUNK_SIZE

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var core := WorldCore.new()
	_assert(
		core.has_method("build_mountain_halo_mask"),
		"WorldCore.build_mountain_halo_mask is required; rebuild the GDExtension."
	)
	if not core.has_method("build_mountain_halo_mask"):
		_finish()
		return

	var closed_halo := PackedByteArray()
	closed_halo.resize(HALO_SIDE * HALO_SIDE)
	closed_halo.fill(1)
	var legacy_result: Dictionary = _build_legacy_mask(core, closed_halo)
	var explicit_empty_result: Dictionary = _build_mask(core, closed_halo, PackedByteArray())
	_assert_mask_shape(legacy_result, "legacy closed mask")
	_assert_mask_shape(explicit_empty_result, "explicit-empty closed mask")
	_assert(
		(legacy_result.get("mask", PackedByteArray()) as PackedByteArray) \
			== (explicit_empty_result.get("mask", PackedByteArray()) as PackedByteArray),
		"the legacy call and the optional empty dug-halo call must be byte-identical"
	)
	_assert(
		int(legacy_result.get("solid_sample_count", -1)) == CORE_SAMPLE_COUNT,
		"the fully closed 16x16 core must report 256 solid samples"
	)

	var scenarios: Array[Dictionary] = [
		{
			"name": "one_tile",
			"tiles": [Vector2i(8, 6)],
		},
		{
			"name": "one_tile_mouth",
			"tiles": [Vector2i(8, 15)],
			"open_south": true,
			"mouth_tile": Vector2i(8, 15),
			"mouth_direction": Vector2i.DOWN,
		},
		{
			"name": "wide",
			"tiles": [
				Vector2i(5, 7),
				Vector2i(6, 7),
				Vector2i(7, 7),
				Vector2i(8, 7),
				Vector2i(9, 7),
				Vector2i(10, 7),
			],
		},
		{
			"name": "three_tile_mouth",
			"tiles": [Vector2i(7, 15), Vector2i(8, 15), Vector2i(9, 15)],
			"open_south": true,
			"wide_mouth_tiles": [Vector2i(7, 15), Vector2i(8, 15), Vector2i(9, 15)],
		},
		{
			"name": "t_shape",
			"tiles": [
				Vector2i(8, 4),
				Vector2i(8, 5),
				Vector2i(8, 6),
				Vector2i(8, 7),
				Vector2i(6, 8),
				Vector2i(7, 8),
				Vector2i(8, 8),
				Vector2i(9, 8),
				Vector2i(10, 8),
			],
		},
		{
			"name": "retaining_island",
			"tiles": _build_dug_ring(Vector2i(8, 8), 2),
			"retaining_tile": Vector2i(8, 8),
		},
	]
	for scenario: Dictionary in scenarios:
		var scenario_closed_halo: PackedByteArray = closed_halo
		var scenario_legacy_result: Dictionary = legacy_result
		if bool(scenario.get("open_south", false)):
			scenario_closed_halo = _build_closed_halo(true)
			scenario_legacy_result = _build_legacy_mask(core, scenario_closed_halo)
		_assert_dual_scenario(core, scenario_closed_halo, scenario_legacy_result, scenario)
	await _assert_threaded_backend(closed_halo, legacy_result)

	_finish()

func _assert_dual_scenario(
	core: Object,
	closed_halo: PackedByteArray,
	legacy_result: Dictionary,
	scenario: Dictionary,
) -> void:
	var scenario_name: String = str(scenario.get("name", "unnamed"))
	var dug_tiles: Array = scenario.get("tiles", []) as Array
	var dug_halo: PackedByteArray = _build_dug_halo(dug_tiles)
	var dual_result: Dictionary = _build_mask(core, closed_halo, dug_halo)
	_assert_mask_shape(dual_result, "%s dual mask" % scenario_name)

	var legacy_mask: PackedByteArray = legacy_result.get("mask", PackedByteArray()) as PackedByteArray
	var closed_roof_mask: PackedByteArray = dual_result.get("closed_roof_mask", PackedByteArray()) as PackedByteArray
	var remaining_mass_mask: PackedByteArray = dual_result.get("remaining_mass_mask", PackedByteArray()) as PackedByteArray
	var visual_remaining_mass_mask: PackedByteArray = dual_result.get(
		"visual_remaining_mass_mask",
		PackedByteArray(),
	) as PackedByteArray
	var primary_mask: PackedByteArray = dual_result.get("mask", PackedByteArray()) as PackedByteArray
	_assert(closed_roof_mask.size() == MASK_SIDE * MASK_SIDE, "%s must return a full closed-roof mask" % scenario_name)
	_assert(remaining_mass_mask.size() == MASK_SIDE * MASK_SIDE, "%s must return a full remaining-mass mask" % scenario_name)
	_assert(
		visual_remaining_mass_mask.size() == MASK_SIDE * MASK_SIDE,
		"%s must return a full visual remaining-mass mask" % scenario_name,
	)
	_assert(closed_roof_mask == legacy_mask, "%s closed roof must stay byte-identical to the legacy closed mask" % scenario_name)
	_assert(primary_mask == remaining_mass_mask, "%s primary mask must remain the gameplay remaining-mass mask" % scenario_name)
	_assert(int(dual_result.get("closed_sample_count", -1)) == CORE_SAMPLE_COUNT, "%s must keep the closed core sample count" % scenario_name)
	_assert(int(dual_result.get("dug_sample_count", -1)) == dug_tiles.size(), "%s must report every dug source tile" % scenario_name)
	_assert(
		int(dual_result.get("solid_sample_count", -1)) == CORE_SAMPLE_COUNT - dug_tiles.size(),
		"%s remaining solid count must equal closed minus dug" % scenario_name
	)

	if closed_roof_mask.size() == remaining_mass_mask.size():
		for index: int in range(closed_roof_mask.size()):
			_assert(
				int(remaining_mass_mask[index]) <= int(closed_roof_mask[index]),
				"%s remaining mass must never exceed the closed roof at pixel %d" % [scenario_name, index]
			)
	if closed_roof_mask.size() == visual_remaining_mass_mask.size():
		for index: int in range(closed_roof_mask.size()):
			_assert(
				int(visual_remaining_mass_mask[index]) <= int(closed_roof_mask[index]),
				"%s visual remaining mass must never exceed the closed roof at pixel %d" \
					% [scenario_name, index]
			)

	for tile_variant: Variant in dug_tiles:
		var local_tile: Vector2i = tile_variant as Vector2i
		_assert_dug_tile_is_fully_zero(remaining_mass_mask, local_tile, scenario_name)
		_assert_visual_tile_topology_core_and_arms(
			visual_remaining_mass_mask,
			closed_halo,
			dug_halo,
			local_tile,
			scenario_name,
		)

	var retaining_tile: Vector2i = scenario.get("retaining_tile", Vector2i(12, 12)) as Vector2i
	_assert(not dug_tiles.has(retaining_tile), "%s test fixture must retain its control tile" % scenario_name)
	_assert_retaining_tile_is_solid(remaining_mass_mask, retaining_tile, scenario_name)
	if scenario.has("retaining_tile"):
		_assert_visual_retaining_tile_is_substantially_solid(
			visual_remaining_mass_mask,
			closed_roof_mask,
			retaining_tile,
			scenario_name,
		)
	if scenario.has("mouth_tile"):
		_assert_visual_mouth_shoulders_remain(
			visual_remaining_mass_mask,
			closed_roof_mask,
			scenario.get("mouth_tile", Vector2i.ZERO) as Vector2i,
			scenario.get("mouth_direction", Vector2i.ZERO) as Vector2i,
			scenario_name,
		)
	if scenario.has("wide_mouth_tiles"):
		_assert_visual_wide_mouth_has_no_inner_posts(
			visual_remaining_mass_mask,
			scenario.get("wide_mouth_tiles", []) as Array,
			scenario_name,
		)

func _build_mask(
	core: Object,
	closed_halo: PackedByteArray,
	dug_halo: PackedByteArray,
) -> Dictionary:
	return core.call(
		"build_mountain_halo_mask",
		closed_halo,
		CHUNK_SIZE,
		TILE_SIZE_PX,
		PIXELS_PER_TILE,
		-512.0,
		-512.0,
		dug_halo,
	) as Dictionary

func _build_legacy_mask(core: Object, closed_halo: PackedByteArray) -> Dictionary:
	return core.call(
		"build_mountain_halo_mask",
		closed_halo,
		CHUNK_SIZE,
		TILE_SIZE_PX,
		PIXELS_PER_TILE,
		-512.0,
		-512.0,
	) as Dictionary

func _build_closed_halo(open_south: bool) -> PackedByteArray:
	var closed_halo := PackedByteArray()
	closed_halo.resize(HALO_SIDE * HALO_SIDE)
	closed_halo.fill(1)
	if open_south:
		for y: int in range(HALO_RADIUS_TILES + CHUNK_SIZE, HALO_SIDE):
			for x: int in range(HALO_SIDE):
				closed_halo[y * HALO_SIDE + x] = 0
	return closed_halo

func _build_dug_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var tile := Vector2i(x, y)
			if tile != center:
				result.append(tile)
	return result

func _build_dug_halo(local_tiles: Array) -> PackedByteArray:
	var dug_halo := PackedByteArray()
	dug_halo.resize(HALO_SIDE * HALO_SIDE)
	for tile_variant: Variant in local_tiles:
		var local_tile: Vector2i = tile_variant as Vector2i
		_assert(
			local_tile.x >= 0 and local_tile.y >= 0 \
				and local_tile.x < CHUNK_SIZE and local_tile.y < CHUNK_SIZE,
			"dug fixture tile %s must be inside the target chunk" % str(local_tile)
		)
		var halo_tile: Vector2i = local_tile + Vector2i.ONE * HALO_RADIUS_TILES
		dug_halo[halo_tile.y * HALO_SIDE + halo_tile.x] = 1
	return dug_halo

func _assert_mask_shape(result: Dictionary, label: String) -> void:
	var mask: PackedByteArray = result.get("mask", PackedByteArray()) as PackedByteArray
	_assert(int(result.get("width", 0)) == MASK_SIDE, "%s width must be %d" % [label, MASK_SIDE])
	_assert(int(result.get("height", 0)) == MASK_SIDE, "%s height must be %d" % [label, MASK_SIDE])
	_assert(mask.size() == MASK_SIDE * MASK_SIDE, "%s byte count must match its dimensions" % label)
	_assert(is_equal_approx(float(result.get("step_px", 0.0)), 8.0), "%s sample step must be 8 world pixels" % label)
	_assert(int(result.get("halo_side", 0)) == HALO_SIDE, "%s must preserve the 32x32 source halo" % label)
	_assert(int(result.get("halo_radius_tiles", 0)) == HALO_RADIUS_TILES, "%s must report the 8-tile halo radius" % label)
	_assert(int(result.get("pixels_per_tile", 0)) == PIXELS_PER_TILE, "%s must preserve 8 pixels per tile" % label)

func _assert_dug_tile_is_fully_zero(
	remaining_mask: PackedByteArray,
	local_tile: Vector2i,
	scenario_name: String,
) -> void:
	if remaining_mask.size() != MASK_SIDE * MASK_SIDE:
		return
	var halo_tile: Vector2i = local_tile + Vector2i.ONE * HALO_RADIUS_TILES
	var pixel_origin: Vector2i = halo_tile * PIXELS_PER_TILE
	for y: int in range(pixel_origin.y, pixel_origin.y + PIXELS_PER_TILE):
		for x: int in range(pixel_origin.x, pixel_origin.x + PIXELS_PER_TILE):
			_assert(
				remaining_mask[y * MASK_SIDE + x] == 0,
				"%s dug tile %s must stay zero across its full 8x8 source core" \
					% [scenario_name, str(local_tile)]
			)

func _assert_retaining_tile_is_solid(
	remaining_mask: PackedByteArray,
	local_tile: Vector2i,
	scenario_name: String,
) -> void:
	if remaining_mask.size() != MASK_SIDE * MASK_SIDE:
		return
	var halo_tile: Vector2i = local_tile + Vector2i.ONE * HALO_RADIUS_TILES
	var center_pixel: Vector2i = halo_tile * PIXELS_PER_TILE + Vector2i.ONE * (PIXELS_PER_TILE / 2)
	_assert(
		remaining_mask[center_pixel.y * MASK_SIDE + center_pixel.x] >= 128,
		"%s must keep the undug retaining control tile solid" % scenario_name
	)

func _assert_visual_tile_topology_core_and_arms(
	visual_mask: PackedByteArray,
	closed_halo: PackedByteArray,
	dug_halo: PackedByteArray,
	local_tile: Vector2i,
	scenario_name: String,
) -> void:
	if visual_mask.size() != MASK_SIDE * MASK_SIDE:
		return
	var halo_tile: Vector2i = local_tile + Vector2i.ONE * HALO_RADIUS_TILES
	var pixel_origin: Vector2i = halo_tile * PIXELS_PER_TILE
	var core_min: int = PIXELS_PER_TILE / 4
	var core_max: int = PIXELS_PER_TILE - core_min
	_assert_visual_rect_is_clear(
		visual_mask,
		Rect2i(
			pixel_origin + Vector2i(core_min, core_min),
			Vector2i(core_max - core_min, core_max - core_min),
		),
		"%s dug tile %s visual topology core" % [scenario_name, str(local_tile)],
	)

	var directions: Array[Vector2i] = [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]
	for direction: Vector2i in directions:
		var neighbour: Vector2i = halo_tile + direction
		if neighbour.x < 0 or neighbour.y < 0 \
				or neighbour.x >= HALO_SIDE or neighbour.y >= HALO_SIDE:
			continue
		var neighbour_index: int = neighbour.y * HALO_SIDE + neighbour.x
		var opens_to_neighbour: bool = dug_halo[neighbour_index] != 0 \
				or closed_halo[neighbour_index] == 0
		if not opens_to_neighbour:
			continue
		var arm_rect := Rect2i()
		if direction == Vector2i.LEFT:
			arm_rect = Rect2i(
				pixel_origin + Vector2i(0, core_min),
				Vector2i(core_min, core_max - core_min),
			)
		elif direction == Vector2i.RIGHT:
			arm_rect = Rect2i(
				pixel_origin + Vector2i(core_max, core_min),
				Vector2i(PIXELS_PER_TILE - core_max, core_max - core_min),
			)
		elif direction == Vector2i.UP:
			arm_rect = Rect2i(
				pixel_origin + Vector2i(core_min, 0),
				Vector2i(core_max - core_min, core_min),
			)
		else:
			arm_rect = Rect2i(
				pixel_origin + Vector2i(core_min, core_max),
				Vector2i(core_max - core_min, PIXELS_PER_TILE - core_max),
			)
		_assert_visual_rect_is_clear(
			visual_mask,
			arm_rect,
			"%s dug tile %s visual arm toward %s" \
				% [scenario_name, str(local_tile), str(direction)],
		)

func _assert_visual_rect_is_clear(
	visual_mask: PackedByteArray,
	rect: Rect2i,
	label: String,
) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if visual_mask[y * MASK_SIDE + x] != 0:
				_assert(false, "%s must be fully clear at pixel (%d, %d)" % [label, x, y])
				return

func _assert_visual_retaining_tile_is_substantially_solid(
	visual_mask: PackedByteArray,
	closed_mask: PackedByteArray,
	local_tile: Vector2i,
	scenario_name: String,
) -> void:
	if visual_mask.size() != MASK_SIDE * MASK_SIDE \
			or closed_mask.size() != MASK_SIDE * MASK_SIDE:
		return
	var halo_tile: Vector2i = local_tile + Vector2i.ONE * HALO_RADIUS_TILES
	var pixel_origin: Vector2i = halo_tile * PIXELS_PER_TILE
	var solidity_sum: float = 0.0
	var sample_count: int = 0
	for y: int in range(pixel_origin.y, pixel_origin.y + PIXELS_PER_TILE):
		for x: int in range(pixel_origin.x, pixel_origin.x + PIXELS_PER_TILE):
			var index: int = y * MASK_SIDE + x
			var closed_value: int = int(closed_mask[index])
			if closed_value < 8:
				continue
			solidity_sum += float(visual_mask[index]) / float(closed_value)
			sample_count += 1
	_assert(sample_count > 0, "%s retaining island must overlap the closed mask" % scenario_name)
	if sample_count == 0:
		return
	var mean_solidity: float = solidity_sum / float(sample_count)
	_assert(
		mean_solidity >= 0.55,
		"%s visual retaining island must stay at least 55%% solid (actual %.3f)" \
			% [scenario_name, mean_solidity],
	)
	var center_pixel: Vector2i = pixel_origin + Vector2i.ONE * (PIXELS_PER_TILE / 2)
	var center_index: int = center_pixel.y * MASK_SIDE + center_pixel.x
	var center_closed: int = int(closed_mask[center_index])
	_assert(
		center_closed > 0 \
				and float(visual_mask[center_index]) / float(center_closed) >= 0.5,
		"%s visual retaining island center must remain recognizably solid" % scenario_name,
	)

func _assert_visual_mouth_shoulders_remain(
	visual_mask: PackedByteArray,
	closed_mask: PackedByteArray,
	local_tile: Vector2i,
	direction: Vector2i,
	scenario_name: String,
) -> void:
	if visual_mask.size() != MASK_SIDE * MASK_SIDE \
			or closed_mask.size() != MASK_SIDE * MASK_SIDE:
		return
	_assert(direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN], \
		"%s mouth direction must be cardinal" % scenario_name)
	var halo_tile: Vector2i = local_tile + Vector2i.ONE * HALO_RADIUS_TILES
	var pixel_origin: Vector2i = halo_tile * PIXELS_PER_TILE
	var core_min: int = PIXELS_PER_TILE / 4
	var core_max: int = PIXELS_PER_TILE - core_min
	var shoulder_points: Array[Vector2i] = []
	for depth: int in range(core_max, PIXELS_PER_TILE):
		for lateral: int in range(0, core_min):
			if direction == Vector2i.DOWN:
				shoulder_points.append(pixel_origin + Vector2i(lateral, depth))
				shoulder_points.append(pixel_origin + Vector2i(PIXELS_PER_TILE - 1 - lateral, depth))
			elif direction == Vector2i.UP:
				shoulder_points.append(pixel_origin + Vector2i(lateral, PIXELS_PER_TILE - 1 - depth))
				shoulder_points.append(pixel_origin + Vector2i(PIXELS_PER_TILE - 1 - lateral, PIXELS_PER_TILE - 1 - depth))
			elif direction == Vector2i.RIGHT:
				shoulder_points.append(pixel_origin + Vector2i(depth, lateral))
				shoulder_points.append(pixel_origin + Vector2i(depth, PIXELS_PER_TILE - 1 - lateral))
			else:
				shoulder_points.append(pixel_origin + Vector2i(PIXELS_PER_TILE - 1 - depth, lateral))
				shoulder_points.append(pixel_origin + Vector2i(PIXELS_PER_TILE - 1 - depth, PIXELS_PER_TILE - 1 - lateral))
	var solidity_sum: float = 0.0
	var sample_count: int = 0
	var visibly_solid_count: int = 0
	for point: Vector2i in shoulder_points:
		var index: int = point.y * MASK_SIDE + point.x
		var closed_value: int = int(closed_mask[index])
		if closed_value < 8:
			continue
		var solidity: float = float(visual_mask[index]) / float(closed_value)
		solidity_sum += solidity
		sample_count += 1
		if solidity >= 0.25:
			visibly_solid_count += 1
	_assert(sample_count > 0, "%s mouth shoulders must overlap the closed mask" % scenario_name)
	if sample_count == 0:
		return
	var mean_solidity: float = solidity_sum / float(sample_count)
	_assert(
		mean_solidity >= 0.20 and visibly_solid_count >= maxi(2, sample_count / 4),
		"%s mouth must retain side shoulders (mean %.3f, solid samples %d/%d)" \
			% [scenario_name, mean_solidity, visibly_solid_count, sample_count],
	)


func _assert_visual_wide_mouth_has_no_inner_posts(
	visual_mask: PackedByteArray,
	mouth_tiles: Array,
	scenario_name: String,
) -> void:
	if visual_mask.size() != MASK_SIDE * MASK_SIDE or mouth_tiles.size() < 2:
		return
	var ordered_tiles: Array[Vector2i] = []
	for tile_variant: Variant in mouth_tiles:
		ordered_tiles.append(tile_variant as Vector2i)
	ordered_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var outward_y0: int = (
		ordered_tiles[0].y + HALO_RADIUS_TILES
	) * PIXELS_PER_TILE + PIXELS_PER_TILE / 2
	var outward_y1: int = outward_y0 + PIXELS_PER_TILE / 2
	for mouth_index: int in range(1, ordered_tiles.size()):
		var seam_x: int = (
			ordered_tiles[mouth_index].x + HALO_RADIUS_TILES
		) * PIXELS_PER_TILE
		for y: int in range(outward_y0, outward_y1):
			_assert(
				visual_mask[y * MASK_SIDE + seam_x - 1] == 0 \
						and visual_mask[y * MASK_SIDE + seam_x] == 0,
				"%s wide mouth must not grow an inner post at x=%d" \
						% [scenario_name, seam_x],
			)

func _assert_threaded_backend(
	closed_halo: PackedByteArray,
	legacy_result: Dictionary,
) -> void:
	var backend := WorldChunkPacketBackend.new()
	backend.start(1)
	var dug_tiles: Array = [Vector2i(8, 6)]
	var dug_halo: PackedByteArray = _build_dug_halo(dug_tiles)
	backend.queue_mountain_halo_mask_request(
		closed_halo,
		Vector2i(3, -2),
		Vector2(-512.0, -512.0),
		CHUNK_SIZE,
		TILE_SIZE_PX,
		PIXELS_PER_TILE,
		41,
		17,
		&"dual_mask_smoke",
		&"mountain",
		dug_halo,
	)
	backend.queue_mountain_halo_mask_request(
		closed_halo,
		Vector2i(4, -2),
		Vector2(-512.0, -512.0),
		CHUNK_SIZE,
		TILE_SIZE_PX,
		PIXELS_PER_TILE,
		42,
		18,
		&"terrain_edge_compatibility",
		&"terrain_edge",
		dug_halo,
	)

	var completed: Array[Dictionary] = []
	var wait_started_msec: int = Time.get_ticks_msec()
	while completed.size() < 2 and Time.get_ticks_msec() - wait_started_msec < 5000:
		completed.append_array(backend.drain_completed_mountain_halo_masks(2 - completed.size()))
		if completed.size() < 2:
			await process_frame
	backend.stop()
	_assert(completed.size() == 2, "threaded backend must complete both mountain and terrain-edge requests")

	var mountain_result: Dictionary = {}
	var terrain_edge_result: Dictionary = {}
	for result: Dictionary in completed:
		var purpose: StringName = result.get("mask_purpose", &"") as StringName
		if purpose == &"mountain":
			mountain_result = result
		elif purpose == &"terrain_edge":
			terrain_edge_result = result
	_assert(not mountain_result.is_empty(), "threaded backend must preserve the mountain request purpose")
	_assert(not terrain_edge_result.is_empty(), "threaded backend must preserve the terrain-edge request purpose")
	if not mountain_result.is_empty():
		_assert(bool(mountain_result.get("success", false)), "threaded mountain dual-mask request must succeed")
		_assert(int(mountain_result.get("epoch", -1)) == 41, "threaded mountain result must preserve epoch")
		_assert(int(mountain_result.get("revision", -1)) == 17, "threaded mountain result must preserve revision")
		_assert((mountain_result.get("target_chunk", Vector2i.ZERO) as Vector2i) == Vector2i(3, -2), "threaded mountain result must preserve target chunk")
		var threaded_closed: PackedByteArray = mountain_result.get("closed_roof_mask", PackedByteArray()) as PackedByteArray
		var threaded_remaining: PackedByteArray = mountain_result.get("remaining_mass_mask", PackedByteArray()) as PackedByteArray
		var threaded_visual: PackedByteArray = mountain_result.get(
			"visual_remaining_mass_mask",
			PackedByteArray(),
		) as PackedByteArray
		_assert(threaded_closed == (legacy_result.get("mask", PackedByteArray()) as PackedByteArray), "threaded mountain closed roof must equal the legacy mask")
		_assert(threaded_remaining == (mountain_result.get("mask", PackedByteArray()) as PackedByteArray), "threaded mountain primary mask must equal remaining mass")
		_assert(
			threaded_visual.size() == MASK_SIDE * MASK_SIDE,
			"threaded mountain result must preserve the full visual remaining-mass mask",
		)
		_assert_dug_tile_is_fully_zero(threaded_remaining, Vector2i(8, 6), "threaded_mountain")
		_assert_visual_tile_topology_core_and_arms(
			threaded_visual,
			closed_halo,
			dug_halo,
			Vector2i(8, 6),
			"threaded_mountain",
		)
	if not terrain_edge_result.is_empty():
		_assert(bool(terrain_edge_result.get("success", false)), "threaded terrain-edge compatibility request must succeed")
		_assert(int(terrain_edge_result.get("epoch", -1)) == 42, "threaded terrain-edge result must preserve epoch")
		_assert(int(terrain_edge_result.get("revision", -1)) == 18, "threaded terrain-edge result must preserve revision")
		_assert(
			(terrain_edge_result.get("mask", PackedByteArray()) as PackedByteArray) \
				== (legacy_result.get("mask", PackedByteArray()) as PackedByteArray),
			"terrain-edge purpose must retain the legacy single-mask output even when a dug halo is supplied"
		)
		_assert(not terrain_edge_result.has("closed_roof_mask"), "terrain-edge compatibility result must not expose mountain dual-mask payload")

func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("mountain_construction_dual_mask_smoke_test: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
