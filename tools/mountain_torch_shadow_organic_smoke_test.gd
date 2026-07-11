extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const HALO_RADIUS_TILES: int = 8
const HALO_SIDE_TILES: int = WorldRuntimeConstants.CHUNK_SIZE + HALO_RADIUS_TILES * 2
const PIXELS_PER_TILE: int = 8
const MASK_SIDE: int = HALO_SIDE_TILES * PIXELS_PER_TILE
const STEP_PX: float = float(WorldRuntimeConstants.TILE_SIZE_PX) / float(PIXELS_PER_TILE)
const CHUNK_SIDE_SAMPLES: int = WorldRuntimeConstants.CHUNK_SIZE * PIXELS_PER_TILE
const CLOSED_VALUE: int = 255

var _failed: bool = false


func _init() -> void:
	# Direct --script entrypoints are parsed before named autoload globals are
	# registered. Defer the WorldStreamer load by one turn so this smoke uses the
	# real Godot 4.7 project compilation context.
	call_deferred("_run")


func _run() -> void:
	var world_streamer_script: Script = load("res://core/systems/world/world_streamer.gd")
	_assert(world_streamer_script != null, "WorldStreamer must compile under Godot 4.7")
	if world_streamer_script == null or not world_streamer_script.can_instantiate():
		_assert(false, "WorldStreamer must remain instantiable")
		_finish()
		return
	var streamer: Node = world_streamer_script.new() as Node
	_assert(streamer != null, "WorldStreamer fixture must instantiate")
	if streamer == null:
		_finish()
		return

	_assert_active_cavity_selects_exact_organic_fringe(streamer)
	_assert_foreign_adjacency_fails_closed(streamer)
	_assert_owner_chunk_seam_uses_halo_seed(streamer)
	_assert_wrapped_owner_seam_uses_canonical_halo_seed(streamer)
	streamer.free()
	_finish()


func _assert_active_cavity_selects_exact_organic_fringe(streamer: Node) -> void:
	var active_tile := Vector2i(5, 5)
	var fixture: Dictionary = _make_fixture(Vector2i.ZERO, active_tile)
	var remaining: PackedByteArray = fixture.get("remaining", PackedByteArray()) as PackedByteArray
	var active_halo: PackedByteArray = fixture.get("active_halo", PackedByteArray()) as PackedByteArray

	# These samples deliberately extend into non-floor neighbour tiles. They are
	# the organic C-S feather of the active excavation, not extra square tiles.
	var fringe_values: Dictionary = {
		Vector2i(6 * PIXELS_PER_TILE + 0, 5 * PIXELS_PER_TILE + 3): 24,
		Vector2i(6 * PIXELS_PER_TILE + 1, 5 * PIXELS_PER_TILE + 4): 88,
		Vector2i(5 * PIXELS_PER_TILE + 3, 6 * PIXELS_PER_TILE + 0): 40,
		Vector2i(5 * PIXELS_PER_TILE + 4, 6 * PIXELS_PER_TILE + 1): 112,
		Vector2i(6 * PIXELS_PER_TILE + 0, 6 * PIXELS_PER_TILE + 0): 72,
	}
	for owner_sample_variant: Variant in fringe_values.keys():
		var owner_sample: Vector2i = owner_sample_variant as Vector2i
		remaining = _set_owner_sample(remaining, owner_sample, int(fringe_values[owner_sample]))
	fixture["remaining"] = remaining

	# A disconnected C-S island represents a foreign cavity. It must stay under
	# CLOSED while the first component is active.
	var foreign_tile := Vector2i(10, 5)
	_mark_dug_tile(fixture, foreign_tile, false)
	var foreign_sample: Vector2i = foreign_tile * PIXELS_PER_TILE + Vector2i(3, 3)

	var support_halo: PackedByteArray = _build_support_halo(streamer, fixture)
	_assert(_halo_tile_value(fixture, support_halo, active_tile) == 255, "active floor must keep ACTIVE=255 support code")
	_assert(_halo_tile_value(fixture, support_halo, active_tile + Vector2i.RIGHT) == 64, "clean cardinal organic support must use SUPPORT=64")
	_assert(_halo_tile_value(fixture, support_halo, active_tile + Vector2i(1, 1)) == 64, "clean diagonal organic support must use SUPPORT=64")
	_assert(_halo_tile_value(fixture, support_halo, foreign_tile) == 0, "foreign dug tile must never enter active support")

	var output: PackedByteArray = _blit_owner_chunk(streamer, fixture, Vector2i.ZERO)
	_assert(output.size() == CHUNK_SIDE_SAMPLES * CHUNK_SIDE_SAMPLES, "organic fixture must produce one owner-chunk shadow page")
	_assert(_owner_output_sample(output, active_tile * PIXELS_PER_TILE + Vector2i(4, 4)) == 0, "active floor core must use remaining mass S")
	for owner_sample_variant: Variant in fringe_values.keys():
		var owner_sample: Vector2i = owner_sample_variant as Vector2i
		_assert(
			_owner_output_sample(output, owner_sample) == int(fringe_values[owner_sample]),
			"active organic fringe %s must preserve its exact S byte instead of square CLOSED" % str(owner_sample),
		)
	_assert(
		_owner_output_sample(output, foreign_sample) == CLOSED_VALUE,
		"disconnected foreign C-S island must remain CLOSED",
	)
	_assert(
		_owner_output_sample(output, Vector2i(2, 2)) == CLOSED_VALUE,
		"untouched mountain sample must remain CLOSED",
	)
	_assert(active_halo.size() == HALO_SIDE_TILES * HALO_SIDE_TILES, "active selector must keep the complete native halo")


func _assert_foreign_adjacency_fails_closed(streamer: Node) -> void:
	var active_tile := Vector2i(5, 5)
	var foreign_tile := Vector2i(7, 5)
	var ambiguous_cardinal := Vector2i(6, 5)
	var ambiguous_diagonal := Vector2i(6, 6)
	var clean_support := Vector2i(5, 6)
	var fixture: Dictionary = _make_fixture(Vector2i.ZERO, active_tile)
	_mark_dug_tile(fixture, foreign_tile, false)
	var remaining: PackedByteArray = fixture.get("remaining", PackedByteArray()) as PackedByteArray
	for tile: Vector2i in [ambiguous_cardinal, ambiguous_diagonal, clean_support]:
		remaining = _set_owner_sample(remaining, tile * PIXELS_PER_TILE + Vector2i(3, 3), 0)
	fixture["remaining"] = remaining

	var support_halo: PackedByteArray = _build_support_halo(streamer, fixture)
	_assert(_halo_tile_value(fixture, support_halo, active_tile) == 255, "active tile must stay selected even beside a foreign dig")
	_assert(_halo_tile_value(fixture, support_halo, foreign_tile) == 0, "foreign dug tile must stay unselected")
	_assert(_halo_tile_value(fixture, support_halo, ambiguous_cardinal) == 0, "support adjacent to active and foreign dug must fail closed")
	_assert(_halo_tile_value(fixture, support_halo, ambiguous_diagonal) == 0, "diagonal support shared with foreign dug must fail closed")
	_assert(_halo_tile_value(fixture, support_halo, clean_support) == 64, "unambiguous diagonal/cardinal support must remain organic")

	var output: PackedByteArray = _blit_owner_chunk(streamer, fixture, Vector2i.ZERO)
	_assert(_owner_output_sample(output, ambiguous_cardinal * PIXELS_PER_TILE + Vector2i(3, 3)) == CLOSED_VALUE, "ambiguous cardinal C-S fringe must render CLOSED")
	_assert(_owner_output_sample(output, ambiguous_diagonal * PIXELS_PER_TILE + Vector2i(3, 3)) == CLOSED_VALUE, "ambiguous diagonal C-S fringe must render CLOSED")
	_assert(_owner_output_sample(output, clean_support * PIXELS_PER_TILE + Vector2i(3, 3)) == 0, "clean organic support must render exact S")


func _assert_owner_chunk_seam_uses_halo_seed(streamer: Node) -> void:
	# The active dug tile is in chunk 0, but its organic cutout feather spills
	# into chunk 1. Chunk 1's owner copy must still find the seed in its left
	# native halo; otherwise the torch shadow exposes a square chunk seam.
	var owner_chunk := Vector2i(1, 0)
	var active_tile := Vector2i(15, 6)
	var fixture: Dictionary = _make_fixture(owner_chunk, active_tile)
	var remaining: PackedByteArray = fixture.get("remaining", PackedByteArray()) as PackedByteArray
	var seam_samples: Dictionary = {
		Vector2i(16 * PIXELS_PER_TILE + 0, 6 * PIXELS_PER_TILE + 3): 18,
		Vector2i(16 * PIXELS_PER_TILE + 1, 6 * PIXELS_PER_TILE + 4): 94,
	}
	for world_sample_variant: Variant in seam_samples.keys():
		var world_sample: Vector2i = world_sample_variant as Vector2i
		remaining = _set_world_sample(fixture, remaining, world_sample, int(seam_samples[world_sample]))
	fixture["remaining"] = remaining

	var output: PackedByteArray = _blit_owner_chunk(streamer, fixture, owner_chunk)
	for world_sample_variant: Variant in seam_samples.keys():
		var world_sample: Vector2i = world_sample_variant as Vector2i
		var owner_sample := Vector2i(
			world_sample.x - owner_chunk.x * CHUNK_SIDE_SAMPLES,
			world_sample.y,
		)
		_assert(
			_owner_output_sample(output, owner_sample) == int(seam_samples[world_sample]),
			"cross-chunk organic fringe %s must use halo-seeded S" % str(world_sample),
		)


func _assert_wrapped_owner_seam_uses_canonical_halo_seed(streamer: Node) -> void:
	# For canonical chunk 0, logical tile -1 in the left halo is the last world
	# tile. Its organic fringe crosses the cylindrical X seam into tile 0.
	var owner_chunk := Vector2i.ZERO
	var logical_active_tile := Vector2i(-1, 7)
	var fixture: Dictionary = _make_fixture(owner_chunk, logical_active_tile)
	var remaining: PackedByteArray = fixture.get("remaining", PackedByteArray()) as PackedByteArray
	var wrapped_fringe: Dictionary = {
		Vector2i(0, 7 * PIXELS_PER_TILE + 3): 12,
		Vector2i(1, 7 * PIXELS_PER_TILE + 4): 84,
	}
	for world_sample_variant: Variant in wrapped_fringe.keys():
		var world_sample: Vector2i = world_sample_variant as Vector2i
		remaining = _set_world_sample(fixture, remaining, world_sample, int(wrapped_fringe[world_sample]))
	fixture["remaining"] = remaining

	var output: PackedByteArray = _blit_owner_chunk(streamer, fixture, owner_chunk)
	for owner_sample_variant: Variant in wrapped_fringe.keys():
		var owner_sample: Vector2i = owner_sample_variant as Vector2i
		_assert(
			_owner_output_sample(output, owner_sample) == int(wrapped_fringe[owner_sample]),
			"wrapped organic fringe %s must use the canonical last-tile halo seed" % str(owner_sample),
		)


func _make_fixture(owner_chunk: Vector2i, active_world_tile: Vector2i) -> Dictionary:
	var closed := PackedByteArray()
	closed.resize(MASK_SIDE * MASK_SIDE)
	closed.fill(CLOSED_VALUE)
	var remaining: PackedByteArray = closed.duplicate()
	var active_halo := PackedByteArray()
	active_halo.resize(HALO_SIDE_TILES * HALO_SIDE_TILES)
	var dug_halo := PackedByteArray()
	dug_halo.resize(HALO_SIDE_TILES * HALO_SIDE_TILES)
	var source_origin_tile := owner_chunk * WorldRuntimeConstants.CHUNK_SIZE - Vector2i.ONE * HALO_RADIUS_TILES
	var active_halo_tile: Vector2i = active_world_tile - source_origin_tile
	_assert(
		active_halo_tile.x >= 0 and active_halo_tile.y >= 0 \
			and active_halo_tile.x < HALO_SIDE_TILES and active_halo_tile.y < HALO_SIDE_TILES,
		"active tile %s must lie inside owner %s native halo" % [str(active_world_tile), str(owner_chunk)],
	)
	if active_halo_tile.x >= 0 and active_halo_tile.y >= 0 \
			and active_halo_tile.x < HALO_SIDE_TILES and active_halo_tile.y < HALO_SIDE_TILES:
		# Production cavity/dug halos are binary bytes (1), not normalized GPU
		# selector bytes. The shared helper performs that normalization itself.
		active_halo[active_halo_tile.y * HALO_SIDE_TILES + active_halo_tile.x] = 1
		dug_halo[active_halo_tile.y * HALO_SIDE_TILES + active_halo_tile.x] = 1
		remaining = _set_halo_tile(remaining, active_halo_tile, 0)
	return {
		"owner_chunk": owner_chunk,
		"source_origin_tile": source_origin_tile,
		"closed": closed,
		"remaining": remaining,
		"active_halo": active_halo,
		"dug_halo": dug_halo,
	}


func _blit_owner_chunk(streamer: Node, fixture: Dictionary, owner_chunk: Vector2i) -> PackedByteArray:
	var chunk_origin: Vector2 = WorldRuntimeConstants.chunk_origin_px(owner_chunk)
	var source_origin_tile: Vector2i = fixture.get("source_origin_tile", Vector2i.ZERO) as Vector2i
	var result: Dictionary = {
		"mask": fixture.get("remaining", PackedByteArray()) as PackedByteArray,
		"remaining_mass_mask": fixture.get("remaining", PackedByteArray()) as PackedByteArray,
		"closed_roof_mask": fixture.get("closed", PackedByteArray()) as PackedByteArray,
		"width": MASK_SIDE,
		"height": MASK_SIDE,
		"step_px": STEP_PX,
		"pixels_per_tile": PIXELS_PER_TILE,
		"halo_side": HALO_SIDE_TILES,
		"dug_halo": fixture.get("dug_halo", PackedByteArray()) as PackedByteArray,
		"mask_origin_world": Vector2(source_origin_tile * WorldRuntimeConstants.TILE_SIZE_PX),
	}
	var output := PackedByteArray()
	output.resize(CHUNK_SIDE_SAMPLES * CHUNK_SIDE_SAMPLES)
	streamer.call(
		"_blit_mountain_native_mask_result_to_shadow_field",
		result,
		chunk_origin,
		CHUNK_SIDE_SAMPLES,
		CHUNK_SIDE_SAMPLES,
		STEP_PX,
		chunk_origin,
		chunk_origin + Vector2.ONE * float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX),
		output,
		fixture.get("active_halo", PackedByteArray()) as PackedByteArray,
	)
	return output


func _build_support_halo(streamer: Node, fixture: Dictionary) -> PackedByteArray:
	_assert(
		streamer.has_method("_build_mountain_torch_component_support_halo"),
		"WorldStreamer must expose the internal torch component support helper",
	)
	if not streamer.has_method("_build_mountain_torch_component_support_halo"):
		return PackedByteArray()
	return streamer.call(
		"_build_mountain_torch_component_support_halo",
		fixture.get("active_halo", PackedByteArray()) as PackedByteArray,
		fixture.get("dug_halo", PackedByteArray()) as PackedByteArray,
		HALO_SIDE_TILES,
	) as PackedByteArray


func _mark_dug_tile(fixture: Dictionary, world_tile: Vector2i, active: bool) -> void:
	var source_origin_tile: Vector2i = fixture.get("source_origin_tile", Vector2i.ZERO) as Vector2i
	var halo_tile: Vector2i = world_tile - source_origin_tile
	_assert(halo_tile.x >= 0 and halo_tile.y >= 0 and halo_tile.x < HALO_SIDE_TILES and halo_tile.y < HALO_SIDE_TILES, "dug fixture tile must lie inside native halo")
	if halo_tile.x < 0 or halo_tile.y < 0 or halo_tile.x >= HALO_SIDE_TILES or halo_tile.y >= HALO_SIDE_TILES:
		return
	var index: int = halo_tile.y * HALO_SIDE_TILES + halo_tile.x
	var dug_halo: PackedByteArray = fixture.get("dug_halo", PackedByteArray()) as PackedByteArray
	dug_halo[index] = 255
	fixture["dug_halo"] = dug_halo
	if active:
		var active_halo: PackedByteArray = fixture.get("active_halo", PackedByteArray()) as PackedByteArray
		active_halo[index] = 1
		fixture["active_halo"] = active_halo
	var remaining: PackedByteArray = fixture.get("remaining", PackedByteArray()) as PackedByteArray
	fixture["remaining"] = _set_halo_tile(remaining, halo_tile, 0)


func _halo_tile_value(fixture: Dictionary, halo: PackedByteArray, world_tile: Vector2i) -> int:
	var source_origin_tile: Vector2i = fixture.get("source_origin_tile", Vector2i.ZERO) as Vector2i
	var halo_tile: Vector2i = world_tile - source_origin_tile
	if halo_tile.x < 0 or halo_tile.y < 0 or halo_tile.x >= HALO_SIDE_TILES or halo_tile.y >= HALO_SIDE_TILES:
		return -1
	var index: int = halo_tile.y * HALO_SIDE_TILES + halo_tile.x
	return int(halo[index]) if index >= 0 and index < halo.size() else -1


func _set_owner_sample(bytes: PackedByteArray, owner_sample: Vector2i, value: int) -> PackedByteArray:
	var halo_sample: Vector2i = owner_sample + Vector2i.ONE * HALO_RADIUS_TILES * PIXELS_PER_TILE
	return _set_halo_sample(bytes, halo_sample, value)


func _set_world_sample(fixture: Dictionary, bytes: PackedByteArray, world_sample: Vector2i, value: int) -> PackedByteArray:
	var source_origin_tile: Vector2i = fixture.get("source_origin_tile", Vector2i.ZERO) as Vector2i
	var halo_sample: Vector2i = world_sample - source_origin_tile * PIXELS_PER_TILE
	return _set_halo_sample(bytes, halo_sample, value)


func _set_halo_tile(bytes: PackedByteArray, halo_tile: Vector2i, value: int) -> PackedByteArray:
	for py: int in range(PIXELS_PER_TILE):
		for px: int in range(PIXELS_PER_TILE):
			bytes = _set_halo_sample(bytes, halo_tile * PIXELS_PER_TILE + Vector2i(px, py), value)
	return bytes


func _set_halo_sample(bytes: PackedByteArray, halo_sample: Vector2i, value: int) -> PackedByteArray:
	_assert(halo_sample.x >= 0 and halo_sample.y >= 0 and halo_sample.x < MASK_SIDE and halo_sample.y < MASK_SIDE, "fixture sample must lie inside native halo")
	if halo_sample.x < 0 or halo_sample.y < 0 or halo_sample.x >= MASK_SIDE or halo_sample.y >= MASK_SIDE:
		return bytes
	bytes[halo_sample.y * MASK_SIDE + halo_sample.x] = clampi(value, 0, 255)
	return bytes


func _owner_output_sample(bytes: PackedByteArray, owner_sample: Vector2i) -> int:
	if owner_sample.x < 0 or owner_sample.y < 0 \
			or owner_sample.x >= CHUNK_SIDE_SAMPLES or owner_sample.y >= CHUNK_SIDE_SAMPLES:
		return -1
	return int(bytes[owner_sample.y * CHUNK_SIDE_SAMPLES + owner_sample.x])


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("mountain_torch_shadow_organic_smoke_test: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
