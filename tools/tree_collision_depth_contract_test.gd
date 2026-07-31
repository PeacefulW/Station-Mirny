extends SceneTree

const AssetCatalog = preload(
	"res://core/systems/world/world_layered_object_asset_catalog.gd"
)
const WorldRuntimeConstants = preload(
	"res://core/systems/world/world_runtime_constants.gd"
)

const TREE_KIND: int = 4
const CONTACT_GAP_PX: float = 0.0
const PLAYER_VISUAL_FEET_OFFSET_PX: float = 41.0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: WorldLayeredObjectAssetCatalog = AssetCatalog.new()
	_expect(catalog.is_ready(), "tree asset catalog must be ready")
	_expect(catalog.get_catalog_generation() == 8, "tree collision metric ABI generation")
	var native_params: PackedFloat32Array = catalog.get_native_params()
	_expect(
		native_params.size() == 20,
		"native params must retain the 20-float presentation ABI",
	)
	if native_params.size() != 20:
		_finish()
		return
	_expect(
		is_equal_approx(native_params[3], 1.0),
		"native params must use a 1.0 tree collision width multiplier",
	)
	_expect(
		is_equal_approx(native_params[4], 1.0),
		"native params must use a 1.0 tree collision depth multiplier",
	)
	_expect(
		is_equal_approx(native_params[5], 34.0),
		"native params must preserve visual-feet sorting at rear collision contact",
	)
	_expect(
		AssetCatalog.TREE_SOURCE_DIRS.size() == 8,
		"production tree catalog must contain all eight variants",
	)
	_expect(AssetCatalog.TREE_METRIC_STRIDE == 8, "tree metric ABI must use stride 8")
	var tree_metrics: PackedFloat32Array = catalog.get_tree_native_metrics()
	_expect(
		tree_metrics.size()
		== AssetCatalog.TREE_SOURCE_DIRS.size() * AssetCatalog.TREE_METRIC_STRIDE,
		"tree metric payload must contain one stride-8 record per variant",
	)
	if tree_metrics.size() \
			!= AssetCatalog.TREE_SOURCE_DIRS.size() * AssetCatalog.TREE_METRIC_STRIDE:
		_finish()
		return
	var player_scene: PackedScene = load("res://scenes/player/player.tscn") as PackedScene
	_expect(player_scene != null, "player scene must load after autoload initialization")
	if player_scene == null:
		_finish()
		return
	var player: CharacterBody2D = player_scene.instantiate() as CharacterBody2D
	_expect(player != null, "player scene must instantiate")
	if player == null:
		_finish()
		return
	var player_shape: CollisionShape2D = player.get_node_or_null(
		"CollisionShape2D",
	) as CollisionShape2D
	_expect(player_shape != null, "player body collision must exist")
	_expect(
		player_shape != null and player_shape.shape is RectangleShape2D,
		"player body collision must remain a rectangle",
	)
	if player_shape == null or not player_shape.shape is RectangleShape2D:
		player.free()
		_finish()
		return
	var player_shape_size := Vector2.ZERO
	player_shape_size = (player_shape.shape as RectangleShape2D).size
	var player_top_local: float = player_shape.position.y - player_shape_size.y * 0.5
	var player_bottom_local: float = player_shape.position.y + player_shape_size.y * 0.5
	var player_source: String = FileAccess.get_file_as_string(
		"res://core/entities/player/player.gd",
	)
	_expect(
		player_source.contains("const PLAYER_FEET_OFFSET_PX: float = 41.0"),
		"player must retain its grass-safe visual-feet depth anchor",
	)
	_expect(
		native_params[5]
		>= PLAYER_VISUAL_FEET_OFFSET_PX
		- player_bottom_local
		+ float(WorldRuntimeConstants.DEPTH_STRIPE_PX),
		"tree depth must bridge player collider-to-visual-feet clearance plus one stripe",
	)

	var world_core: Object = ClassDB.instantiate("WorldCore")
	_expect(
		world_core != null and world_core.has_method("build_object_presentation_buffers"),
		"WorldCore native object presentation API must exist",
	)
	if world_core == null:
		_finish()
		return
	var variants := PackedByteArray()
	var q4_xs := PackedByteArray()
	var q4_ys := PackedByteArray()
	var ascending_sizes := PackedByteArray()
	var descending_sizes := PackedByteArray()
	for variant: int in range(AssetCatalog.TREE_SOURCE_DIRS.size()):
		variants.append(variant)
		q4_xs.append(20)
		q4_ys.append(variant % 4)
		ascending_sizes.append(120 + variant * 16)
		descending_sizes.append(248 - variant * 16)
	var first_result: Dictionary = _build_native_result(
		world_core,
		catalog,
		variants,
		q4_xs,
		q4_ys,
		ascending_sizes,
	)
	var second_result: Dictionary = _build_native_result(
		world_core,
		catalog,
		variants,
		q4_xs,
		q4_ys,
		descending_sizes,
	)
	var first_records: PackedFloat32Array = first_result.get(
		"tree_collision_records",
		PackedFloat32Array(),
	) as PackedFloat32Array
	var second_records: PackedFloat32Array = second_result.get(
		"tree_collision_records",
		PackedFloat32Array(),
	) as PackedFloat32Array
	var variant_count: int = AssetCatalog.TREE_SOURCE_DIRS.size()
	_expect(
		first_records.size() == variant_count * 4,
		"first native result must contain eight stride-4 colliders",
	)
	_expect(
		second_records.size() == variant_count * 4,
		"second native result must contain eight stride-4 colliders",
	)
	if first_records.size() == variant_count * 4 \
			and second_records.size() == variant_count * 4:
		for variant: int in range(variant_count):
			var offset: int = variant * 4
			var root_x: float = (float(q4_xs[variant]) + 0.5) \
					* AssetCatalog.OBJECT_POSITION_QUANTIZATION_PX
			var root_y: float = (float(q4_ys[variant]) + 0.5) \
					* AssetCatalog.OBJECT_POSITION_QUANTIZATION_PX
			var center_x: float = first_records[offset]
			var center_y: float = first_records[offset + 1]
			var collision_size := Vector2(
				first_records[offset + 2],
				first_records[offset + 3],
			)
			var authored_footprint: Rect2 = catalog.get_tree_collision_footprint_for_variant(
				variant,
			)
			var authored_center_x: float = (
				root_x + authored_footprint.position.x + authored_footprint.size.x * 0.5
			)
			_verify_metric_profile_matches_metadata(tree_metrics, variant)
			_expect(
				is_equal_approx(center_x, authored_center_x),
				"tree %02d collider X must include its authored base offset"
				% (variant + 1),
			)
			_expect(
				is_equal_approx(center_y + collision_size.y * 0.5, root_y),
				"tree %02d collider south edge must equal its root" % (variant + 1),
			)
			_expect(
				collision_size.is_equal_approx(authored_footprint.size),
				"tree %02d rectangle size must come from authored metadata and visual scale"
				% (variant + 1),
			)
			_expect(
				collision_size.y >= native_params[5],
				"tree %02d rectangle depth must preserve rear-contact ordering"
				% (variant + 1),
			)
			var second_size := Vector2(
				second_records[offset + 2],
				second_records[offset + 3],
			)
			_expect(
				is_equal_approx(center_x, second_records[offset])
				and is_equal_approx(center_y, second_records[offset + 1])
				and collision_size.is_equal_approx(second_size),
				"tree %02d footprint must not depend on packet size tier"
				% (variant + 1),
			)
			var collision_shape: Shape2D = catalog.get_tree_collision_shape(collision_size)
			_expect(
				collision_shape is RectangleShape2D
				and (collision_shape as RectangleShape2D).size.is_equal_approx(
					collision_size,
				),
				"tree %02d catalog shape must be the exact authored rectangle"
				% (variant + 1),
			)
			_verify_rear_and_front_depth(
				variant,
				root_y,
				center_y,
				collision_size.y,
				player_top_local,
				player_bottom_local,
			)
	player.free()
	_finish()


func _build_native_result(
		world_core: Object,
		catalog: WorldLayeredObjectAssetCatalog,
		variants: PackedByteArray,
		q4_xs: PackedByteArray,
		q4_ys: PackedByteArray,
		sizes: PackedByteArray,
) -> Dictionary:
	var count: int = variants.size()
	var result_variant: Variant = world_core.call(
		"build_object_presentation_buffers",
		_filled_bytes(count, TREE_KIND),
		q4_xs,
		q4_ys,
		sizes,
		_filled_bytes(count, 0),
		variants,
		_filled_bytes(count, 0),
		_filled_bytes(count, 235),
		_filled_bytes(count, 64),
		catalog.get_tree_native_metrics(),
		catalog.get_rock_native_metrics(),
		catalog.get_bush_native_metrics(),
		catalog.get_native_params(),
	)
	_expect(result_variant is Dictionary, "native tree result must be a Dictionary")
	if not result_variant is Dictionary:
		return { }
	var result: Dictionary = result_variant as Dictionary
	_expect(not result.has("error"), str(result.get("error", "native tree build failed")))
	return result


func _verify_metric_profile_matches_metadata(
		tree_metrics: PackedFloat32Array,
		variant: int,
) -> void:
	var source_dir: String = AssetCatalog.TREE_SOURCE_DIRS[variant]
	var metadata_variant: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("%s/meta.json" % source_dir),
	)
	_expect(
		metadata_variant is Dictionary,
		"tree %02d metadata must parse" % (variant + 1),
	)
	if not metadata_variant is Dictionary:
		return
	var metadata: Dictionary = metadata_variant as Dictionary
	var footprint_variant: Variant = metadata.get("collision_footprint", null)
	_expect(
		footprint_variant is Dictionary,
		"tree %02d metadata must author collision_footprint" % (variant + 1),
	)
	if not footprint_variant is Dictionary:
		return
	var footprint: Dictionary = footprint_variant as Dictionary
	for key: String in ["offset_x_px", "width_px", "depth_px"]:
		_expect(
			footprint.has(key),
			"tree %02d metadata footprint must include %s" % [variant + 1, key],
		)
		if not footprint.has(key):
			return
	var metric_offset: int = variant * AssetCatalog.TREE_METRIC_STRIDE
	_expect(
		is_equal_approx(
			tree_metrics[metric_offset + AssetCatalog.TREE_METRIC_COLLISION_CENTER_X_OFFSET],
			float(footprint["offset_x_px"]),
		),
		"tree %02d metric offset must match authored metadata" % (variant + 1),
	)
	_expect(
		is_equal_approx(
			tree_metrics[metric_offset + AssetCatalog.TREE_METRIC_COLLISION_WIDTH],
			float(footprint["width_px"]),
		),
		"tree %02d metric width must match authored metadata" % (variant + 1),
	)
	_expect(
		is_equal_approx(
			tree_metrics[metric_offset + AssetCatalog.TREE_METRIC_COLLISION_DEPTH],
			float(footprint["depth_px"]),
		),
		"tree %02d metric depth must match authored metadata" % (variant + 1),
	)


func _verify_rear_and_front_depth(
		variant: int,
		root_y: float,
		center_y: float,
		collision_height: float,
		player_top_local: float,
		player_bottom_local: float,
) -> void:
	var center_from_root_y: float = center_y - root_y
	for phase: int in range(WorldRuntimeConstants.DEPTH_STRIPE_PX):
		var phased_root_y: float = float(phase)
		var phased_center_y: float = phased_root_y + center_from_root_y
		var tree_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(
			phased_root_y,
		)
		var rear_player_origin_y: float = phased_center_y - collision_height * 0.5 \
				- player_bottom_local - CONTACT_GAP_PX
		var rear_anchor_y: float = rear_player_origin_y + PLAYER_VISUAL_FEET_OFFSET_PX
		var rear_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(
			rear_anchor_y,
		)
		var rear_player_z: int = WorldRuntimeConstants.z_for_stripe_vs_anchor(
			rear_stripe,
			rear_stripe,
			true,
		)
		var rear_tree_z: int = WorldRuntimeConstants.z_for_stripe_vs_anchor(
			tree_stripe,
			rear_stripe,
			false,
		) + WorldRuntimeConstants.DEPTH_CHANNEL_OBJECT_BASE_OFFSET
		_expect(
			rear_tree_z > rear_player_z,
			"tree %02d must cover rear-contact player at depth phase %d"
			% [variant + 1, phase],
		)

		var front_player_origin_y: float = phased_center_y + collision_height * 0.5 \
				- player_top_local + CONTACT_GAP_PX
		var front_anchor_y: float = front_player_origin_y + PLAYER_VISUAL_FEET_OFFSET_PX
		var front_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(
			front_anchor_y,
		)
		var front_player_z: int = WorldRuntimeConstants.z_for_stripe_vs_anchor(
			front_stripe,
			front_stripe,
			true,
		)
		var front_tree_z: int = WorldRuntimeConstants.z_for_stripe_vs_anchor(
			tree_stripe,
			front_stripe,
			false,
		) + WorldRuntimeConstants.DEPTH_CHANNEL_OBJECT_BASE_OFFSET
		_expect(
			front_player_z > front_tree_z,
			"player must cover tree %02d at front-contact phase %d"
			% [variant + 1, phase],
		)


func _filled_bytes(count: int, value: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(count)
	result.fill(value)
	return result


func _finish() -> void:
	if _failures.is_empty():
		print("tree_collision_depth_contract_test: PASS variants=8")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
