extends SceneTree

const DepthLadderBandRoot = preload("res://core/systems/world/depth_ladder_band_root.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failures: int = 0
var _exact_z_checks: int = 0
var _max_root_z_writes: int = 0
var _max_boundary_migrations: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var owner := Node2D.new()
	root.add_child(owner)
	var mountain := Node2D.new()
	mountain.z_as_relative = false
	mountain.z_index = WorldRuntimeConstants.Z_MOUNTAIN_TOP
	owner.add_child(mountain)

	var ladder: DepthLadderBandRoot = DepthLadderBandRoot.new()
	owner.add_child(ladder)
	ladder.set_world_origin_y(0.0)
	var grass_items: Array[Node2D] = []
	for stripe_index: int in range(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK):
		var item := Node2D.new()
		item.name = "GrassStripe%d" % stripe_index
		ladder.register_item(item, stripe_index, 0)
		grass_items.append(item)
	_assert(
		int(ladder.get_debug_state().get("canvas_item_count", -1)) == 4,
		"ladder accounting includes its root and three prepared band roots",
	)

	for anchor_stripe: int in range(-96, 97):
		ladder.update_anchor(anchor_stripe)
		_assert_exact_z(ladder, grass_items, 0, anchor_stripe, 0)
		_assert(
			mountain.z_index == WorldRuntimeConstants.Z_MOUNTAIN_TOP,
			"depth rebase must not mutate mountain z",
		)
		if anchor_stripe > -96:
			var stats: Dictionary = ladder.get_debug_state()
			_max_root_z_writes = maxi(
				_max_root_z_writes,
				int(stats.get("last_root_z_writes", 0)),
			)
			_max_boundary_migrations = maxi(
				_max_boundary_migrations,
				int(stats.get("last_boundary_migrations", 0)),
			)
			_assert(
				int(stats.get("last_root_z_writes", 99)) <= 1,
				"one-stripe anchor move must write at most one band-root z",
			)
			_assert(
				int(stats.get("last_boundary_migrations", 99)) <= 2,
				"one-stripe anchor move must migrate at most two clamp-boundary items",
			)

	# Chunk origins can be negative or very far from zero. Rebasing must stay
	# exact without sending an empty linear root outside Godot's z range.
	for chunk_stripe_base: int in [-2048, -64, 64, 4096]:
		ladder.set_world_origin_y(
			float(chunk_stripe_base * WorldRuntimeConstants.DEPTH_STRIPE_PX),
		)
		for anchor_stripe: int in [
			chunk_stripe_base - 160,
			chunk_stripe_base - 17,
			chunk_stripe_base + 31,
			chunk_stripe_base + 144,
		]:
			ladder.update_anchor(anchor_stripe)
			_assert_exact_z(ladder, grass_items, chunk_stripe_base, anchor_stripe, 0)

	# The helper must preserve the object parity and authored channel offsets,
	# including after a transport-sized multi-stripe jump.
	ladder.set_world_origin_y(0.0)
	var object_item := Node2D.new()
	ladder.register_item(object_item, 31, 3)
	for anchor_stripe: int in [-320, -17, 0, 63, 411]:
		ladder.update_anchor(anchor_stripe)
		_assert_exact_item_z(ladder, object_item, 31, anchor_stripe, 3)

	ladder.unregister_item(object_item)
	_assert(
		int(ladder.get_debug_state().get("registered_item_count", -1)) == 64,
		"unregistered pooled item must leave the active rebase registry",
	)

	owner.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"depth_ladder_band_root_contract_test: PASS checks=%d max_root_z_writes=%d max_boundary_migrations=%d"
			% [_exact_z_checks, _max_root_z_writes, _max_boundary_migrations],
		)
		quit(0)
	else:
		push_error("depth_ladder_band_root_contract_test: FAIL %d" % _failures)
		quit(1)


func _assert_exact_z(
		ladder: DepthLadderBandRoot,
		items: Array[Node2D],
		chunk_stripe_base: int,
		anchor_stripe: int,
		offset: int,
) -> void:
	for stripe_index: int in range(items.size()):
		_exact_z_checks += 1
		var expected: int = WorldRuntimeConstants.z_for_stripe_vs_anchor(
			chunk_stripe_base + stripe_index,
			anchor_stripe,
			false,
		) + offset
		_assert(
			_effective_z(items[stripe_index], ladder) == expected,
			"stripe %d anchor %d expected z=%d got=%d" % [
				stripe_index,
				anchor_stripe,
				expected,
				_effective_z(items[stripe_index], ladder),
			],
		)


func _assert_exact_item_z(
		ladder: DepthLadderBandRoot,
		item: Node2D,
		stripe_index: int,
		anchor_stripe: int,
		offset: int,
) -> void:
	var expected: int = WorldRuntimeConstants.z_for_stripe_vs_anchor(
		stripe_index,
		anchor_stripe,
		false,
	) + offset
	_exact_z_checks += 1
	_assert(
		_effective_z(item, ladder) == expected,
		"offset item anchor %d expected z=%d got=%d" % [
			anchor_stripe,
			expected,
			_effective_z(item, ladder),
		],
	)


static func _effective_z(item: CanvasItem, ladder: CanvasItem) -> int:
	var result: int = item.z_index
	var parent: Node = item.get_parent()
	while parent != null and parent != ladder:
		if parent is CanvasItem:
			result += (parent as CanvasItem).z_index
		parent = parent.get_parent()
	return result


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
