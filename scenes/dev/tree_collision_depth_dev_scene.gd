extends Node2D

const AssetCatalog = preload(
	"res://core/systems/world/world_layered_object_asset_catalog.gd"
)
const WorldObjectPacketLayer = preload(
	"res://core/systems/world/world_object_packet_layer.gd"
)
const WorldRuntimeConstants = preload(
	"res://core/systems/world/world_runtime_constants.gd"
)
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

const TREE_KIND: int = 4
const PAIR_COLUMNS: int = 4
const PAIR_X_SPACING_PX: float = 560.0
const PAIR_ROW_ORIGINS_Y: Array[float] = [352.0, 944.0]
const ROOT_LOCAL_X_PX: float = 2.0
const CONTACT_GAP_PX: float = 0.75
const PLAYER_VISUAL_FEET_OFFSET_PX: float = 41.0
const PLAYER_MOVE_SPEED_PX: float = 150.0
const TREE_COLLISION_FILL := Color(1.0, 0.20, 0.12, 0.24)
const TREE_COLLISION_LINE := Color(1.0, 0.28, 0.16, 0.96)
const PLAYER_COLLISION_FILL := Color(0.10, 0.78, 1.0, 0.25)
const PLAYER_COLLISION_LINE := Color(0.18, 0.88, 1.0, 1.0)
const ROOT_LINE_COLOR := Color(1.0, 0.32, 0.82, 1.0)

var _catalog: WorldLayeredObjectAssetCatalog = null
var _world_core: Object = null
var _tree_layers: Array[WorldObjectPacketLayer] = []
var _players: Array[CharacterBody2D] = []
var _player_collision_shapes: Array[CollisionShape2D] = []
var _tree_roots_world: Array[Vector2] = []
var _tree_collision_centers_world: Array[Vector2] = []
var _tree_collision_sizes: Array[Vector2] = []
var _native_build_ok: bool = false
var _tree_overlay_count: int = 0
var _player_overlay_count: int = 0

@onready var _title_label: Label = %TitleLabel
@onready var _hint_label: Label = %HintLabel
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	_title_label.text = Localization.t("UI_TREE_COLLISION_LAB_TITLE")
	_hint_label.text = Localization.t("UI_TREE_COLLISION_LAB_HINT")
	_status_label.text = Localization.t("UI_TREE_COLLISION_LAB_LOADING")
	_add_pair_backdrops()
	if not ClassDB.class_exists("WorldCore"):
		_fail_lab("WorldCore class is unavailable")
		return
	_world_core = ClassDB.instantiate("WorldCore")
	_catalog = AssetCatalog.new()
	if _world_core == null or _catalog == null or not _catalog.is_ready():
		_fail_lab("production asset catalog is unavailable")
		return
	for variant: int in range(AssetCatalog.TREE_SOURCE_DIRS.size()):
		if not _build_tree_pair(variant):
			return
	_native_build_ok = _tree_layers.size() == AssetCatalog.TREE_SOURCE_DIRS.size()
	reset_players_behind_trees()
	_status_label.text = Localization.t(
		"UI_TREE_COLLISION_LAB_READY",
		{
			"count": AssetCatalog.TREE_SOURCE_DIRS.size(),
			"scale": "%.2f" % AssetCatalog.TREE_FIXED_FRAME_SCALE,
		},
	)


func _physics_process(_delta: float) -> void:
	if not _native_build_ok:
		return
	var direction: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down",
	)
	for pair_index: int in range(_players.size()):
		var player: CharacterBody2D = _players[pair_index]
		player.velocity = direction * PLAYER_MOVE_SPEED_PX
		player.move_and_slide()
		_sync_pair_depth(pair_index)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_R:
			reset_players_behind_trees()
			get_viewport().set_input_as_handled()


func reset_players_behind_trees() -> void:
	for pair_index: int in range(_players.size()):
		var player: CharacterBody2D = _players[pair_index]
		var shape_node: CollisionShape2D = _player_collision_shapes[pair_index]
		var local_bounds: Rect2 = _collision_shape_bounds_in_player(shape_node)
		var tree_top_y: float = _tree_collision_centers_world[pair_index].y \
				- _tree_collision_sizes[pair_index].y * 0.5
		player.global_position = Vector2(
			_tree_collision_centers_world[pair_index].x,
			tree_top_y - local_bounds.end.y - CONTACT_GAP_PX,
		)
		player.velocity = Vector2.ZERO
		_sync_pair_depth(pair_index)


func get_debug_snapshot() -> Dictionary:
	var collider_count: int = 0
	var active_collision_count: int = 0
	var native_layer_count: int = 0
	for tree_layer: WorldObjectPacketLayer in _tree_layers:
		var state: Dictionary = tree_layer.get_debug_state()
		collider_count += int(state.get("tree_collider_count", 0))
		active_collision_count += 1 if int(state.get("tree_collision_layer", 0)) == 2 else 0
		native_layer_count += 1 if bool(state.get("uses_native_presentation_buffers", false)) else 0
	var base_alignment_count: int = 0
	var authored_footprint_count: int = 0
	var rear_order_pass_count: int = 0
	for pair_index: int in range(_tree_roots_world.size()):
		var root_world: Vector2 = _tree_roots_world[pair_index]
		var center_world: Vector2 = _tree_collision_centers_world[pair_index]
		var size: Vector2 = _tree_collision_sizes[pair_index]
		if is_equal_approx(center_world.y + size.y * 0.5, root_world.y):
			base_alignment_count += 1
		var authored: Rect2 = _catalog.get_tree_collision_footprint_for_variant(pair_index)
		if center_world.is_equal_approx(root_world + authored.get_center()) \
				and size.is_equal_approx(authored.size):
			authored_footprint_count += 1
		var player_collision_south_y: float = _player_collision_south_world_y(pair_index)
		var player_anchor_y: float = _player_visual_feet_world_y(pair_index)
		var player_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(
			player_anchor_y,
		)
		var tree_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(root_world.y)
		var player_z: int = WorldRuntimeConstants.z_for_stripe_vs_anchor(
			player_stripe,
			player_stripe,
			true,
		)
		var tree_trunk_z: int = WorldRuntimeConstants.z_for_stripe_vs_anchor(
			tree_stripe,
			player_stripe,
			false,
		) + WorldRuntimeConstants.DEPTH_CHANNEL_OBJECT_BASE_OFFSET
		if player_collision_south_y < center_world.y - size.y * 0.5 \
				and tree_trunk_z > player_z:
			rear_order_pass_count += 1
	return {
		"ready": _native_build_ok,
		"variant_count": _tree_layers.size(),
		"player_count": _players.size(),
		"player_collision_count": _player_collision_shapes.size(),
		"tree_collider_count": collider_count,
		"active_collision_layer_count": active_collision_count,
		"native_layer_count": native_layer_count,
		"base_alignment_count": base_alignment_count,
		"authored_footprint_count": authored_footprint_count,
		"rear_order_pass_count": rear_order_pass_count,
		"tree_overlay_count": _tree_overlay_count,
		"player_overlay_count": _player_overlay_count,
		"asset_dirs": AssetCatalog.TREE_SOURCE_DIRS.duplicate(),
	}


func get_variant_focus_world_position(variant: int) -> Vector2:
	if variant < 0 or variant >= _tree_roots_world.size():
		return Vector2.ZERO
	return _tree_roots_world[variant] - Vector2(0.0, 150.0)


func _build_tree_pair(variant: int) -> bool:
	var column: int = variant % PAIR_COLUMNS
	var row: int = variant / PAIR_COLUMNS
	var q4_y: int = variant % 4
	var desired_root_x: float = (float(column) - 1.5) * PAIR_X_SPACING_PX
	var layer_origin_y: float = PAIR_ROW_ORIGINS_Y[row]
	var tree_layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	tree_layer.name = "ProductionTree%02d" % (variant + 1)
	tree_layer.position = Vector2(desired_root_x - ROOT_LOCAL_X_PX, layer_origin_y)
	add_child(tree_layer)
	tree_layer.set_world_origin_y(layer_origin_y)

	var result_variant: Variant = _world_core.call(
		"build_object_presentation_buffers",
		PackedByteArray([TREE_KIND]),
		PackedByteArray([0]),
		PackedByteArray([q4_y]),
		PackedByteArray([120 + variant * 16]),
		PackedByteArray([0]),
		PackedByteArray([variant]),
		PackedByteArray([0]),
		PackedByteArray([235]),
		PackedByteArray([variant * 29]),
		_catalog.get_tree_native_metrics(),
		_catalog.get_rock_native_metrics(),
		_catalog.get_bush_native_metrics(),
		_catalog.get_native_params(),
	)
	if not result_variant is Dictionary:
		_fail_lab("native result is not a Dictionary")
		tree_layer.queue_free()
		return false
	var result: Dictionary = result_variant as Dictionary
	result["success"] = not result.has("error")
	if not bool(result["success"]):
		_fail_lab(str(result.get("error", "native tree build failed")))
		tree_layer.queue_free()
		return false
	var collision_records: PackedFloat32Array = result.get(
		"tree_collision_records",
		PackedFloat32Array(),
	) as PackedFloat32Array
	if collision_records.size() != WorldObjectPacketLayer.TREE_COLLISION_RECORD_STRIDE:
		_fail_lab("native tree collision record count is invalid")
		tree_layer.queue_free()
		return false
	if not tree_layer.begin_presentation_result(result, _catalog):
		_fail_lab("production tree presentation rejected its native result")
		tree_layer.queue_free()
		return false
	var apply_guard: int = 0
	while tree_layer.has_pending_presentation_apply():
		tree_layer.apply_next_presentation_slice(64, 64, 64)
		apply_guard += 1
		if apply_guard > 32:
			_fail_lab("production tree presentation did not finish")
			tree_layer.queue_free()
			return false
	tree_layer.set_blocking_collision_active(true)

	var root_local := Vector2(ROOT_LOCAL_X_PX, (float(q4_y) + 0.5) * 4.0)
	var root_world: Vector2 = tree_layer.position + root_local
	var collision_center_world: Vector2 = tree_layer.position + Vector2(
		collision_records[0],
		collision_records[1],
	)
	var collision_size := Vector2(collision_records[2], collision_records[3])
	var player_pair: Dictionary = _make_player_proxy(variant)
	var player: CharacterBody2D = player_pair.get("body") as CharacterBody2D
	var player_shape: CollisionShape2D = player_pair.get("shape") as CollisionShape2D
	if player == null or player_shape == null:
		_fail_lab("player collision proxy could not be created")
		tree_layer.queue_free()
		return false
	add_child(player)

	_tree_layers.append(tree_layer)
	_players.append(player)
	_player_collision_shapes.append(player_shape)
	_tree_roots_world.append(root_world)
	_tree_collision_centers_world.append(collision_center_world)
	_tree_collision_sizes.append(collision_size)
	_add_tree_collision_overlay(collision_center_world, collision_size, root_world)
	_add_player_collision_overlay(player, player_shape)
	_add_tree_label(variant, root_world, collision_center_world, collision_size)
	return true


func _make_player_proxy(variant: int) -> Dictionary:
	var source: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	if source == null:
		return { }
	var source_visual: Sprite2D = source.get_node_or_null("Visual") as Sprite2D
	var source_shape: CollisionShape2D = source.get_node_or_null("CollisionShape2D") \
			as CollisionShape2D
	if source_visual == null or source_shape == null or source_shape.shape == null:
		source.free()
		return { }
	var player := CharacterBody2D.new()
	player.name = "PlayerBehindTree%02d" % (variant + 1)
	player.collision_layer = 1
	player.collision_mask = 2
	player.z_as_relative = false
	var visual: Sprite2D = source_visual.duplicate() as Sprite2D
	visual.name = "Visual"
	player.add_child(visual)
	var shape_node: CollisionShape2D = source_shape.duplicate() as CollisionShape2D
	shape_node.name = "CollisionShape2D"
	player.add_child(shape_node)
	source.free()
	return { "body": player, "shape": shape_node }


func _sync_pair_depth(pair_index: int) -> void:
	var player_anchor_y: float = _player_visual_feet_world_y(pair_index)
	var anchor_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(
		player_anchor_y,
	)
	_tree_layers[pair_index].update_ladder_z(anchor_stripe)
	var player: CharacterBody2D = _players[pair_index]
	player.z_index = WorldRuntimeConstants.z_for_stripe_vs_anchor(
		anchor_stripe,
		anchor_stripe,
		true,
	)


func _player_visual_feet_world_y(pair_index: int) -> float:
	return _players[pair_index].global_position.y + PLAYER_VISUAL_FEET_OFFSET_PX


func _player_collision_south_world_y(pair_index: int) -> float:
	var player: CharacterBody2D = _players[pair_index]
	var local_bounds: Rect2 = _collision_shape_bounds_in_player(
		_player_collision_shapes[pair_index],
	)
	return (player.global_transform * Vector2(0.0, local_bounds.end.y)).y


func _collision_shape_bounds_in_player(shape_node: CollisionShape2D) -> Rect2:
	if shape_node == null or shape_node.shape == null:
		return Rect2()
	if shape_node.shape is RectangleShape2D:
		var size: Vector2 = (shape_node.shape as RectangleShape2D).size
		return Rect2(shape_node.position - size * 0.5, size)
	if shape_node.shape is CircleShape2D:
		var radius: float = (shape_node.shape as CircleShape2D).radius
		return Rect2(
			shape_node.position - Vector2.ONE * radius,
			Vector2.ONE * radius * 2.0,
		)
	return Rect2()


func _add_tree_collision_overlay(
		center_world: Vector2,
		size: Vector2,
		root_world: Vector2,
) -> void:
	var overlay := Node2D.new()
	overlay.name = "TreeCollisionOverlay"
	overlay.position = center_world
	overlay.z_as_relative = false
	overlay.z_index = WorldRuntimeConstants.Z_DEBUG_OVERLAY
	add_child(overlay)
	var rect := Rect2(-size * 0.5, size)
	var rect_points := PackedVector2Array(
		[
			rect.position,
			rect.position + Vector2(rect.size.x, 0.0),
			rect.end,
			rect.position + Vector2(0.0, rect.size.y),
		],
	)
	var fill := Polygon2D.new()
	fill.polygon = rect_points
	fill.color = TREE_COLLISION_FILL
	overlay.add_child(fill)
	var outline := Line2D.new()
	outline.points = rect_points
	outline.closed = true
	outline.width = 2.5
	outline.default_color = TREE_COLLISION_LINE
	overlay.add_child(outline)
	var root_line := Line2D.new()
	root_line.position = root_world - center_world
	root_line.points = PackedVector2Array([Vector2(-22.0, 0.0), Vector2(22.0, 0.0)])
	root_line.width = 3.0
	root_line.default_color = ROOT_LINE_COLOR
	overlay.add_child(root_line)
	_tree_overlay_count += 1


func _add_player_collision_overlay(
		player: CharacterBody2D,
		shape_node: CollisionShape2D,
) -> void:
	var bounds: Rect2 = _collision_shape_bounds_in_player(shape_node)
	var overlay := Node2D.new()
	overlay.name = "PlayerCollisionOverlay"
	overlay.z_as_relative = false
	overlay.z_index = WorldRuntimeConstants.Z_DEBUG_OVERLAY
	player.add_child(overlay)
	var points := PackedVector2Array(
		[
			bounds.position,
			bounds.position + Vector2(bounds.size.x, 0.0),
			bounds.end,
			bounds.position + Vector2(0.0, bounds.size.y),
		],
	)
	var fill := Polygon2D.new()
	fill.polygon = points
	fill.color = PLAYER_COLLISION_FILL
	overlay.add_child(fill)
	var outline := Line2D.new()
	outline.points = points
	outline.closed = true
	outline.width = 2.5
	outline.default_color = PLAYER_COLLISION_LINE
	overlay.add_child(outline)
	_player_overlay_count += 1


func _add_tree_label(
		variant: int,
		root_world: Vector2,
		center_world: Vector2,
		size: Vector2,
) -> void:
	var label := Label.new()
	label.name = "TreeLabel%02d" % (variant + 1)
	label.text = Localization.t(
		"UI_TREE_COLLISION_LAB_TREE_LABEL",
		{
			"number": "%02d" % (variant + 1),
			"asset": AssetCatalog.TREE_SOURCE_DIRS[variant].get_file(),
			"width": "%.2f" % size.x,
			"depth": "%.2f" % size.y,
			"offset": "%+.2f" % (center_world.x - root_world.x),
		},
	)
	label.position = root_world + Vector2(-190.0, 48.0)
	label.size = Vector2(380.0, 42.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.87))
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.02, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.z_as_relative = false
	label.z_index = WorldRuntimeConstants.Z_DEBUG_OVERLAY
	add_child(label)


func _add_pair_backdrops() -> void:
	for variant: int in range(AssetCatalog.TREE_SOURCE_DIRS.size()):
		var column: int = variant % PAIR_COLUMNS
		var row: int = variant / PAIR_COLUMNS
		var center_x: float = (float(column) - 1.5) * PAIR_X_SPACING_PX
		var center_y: float = PAIR_ROW_ORIGINS_Y[row] + 12.0
		var panel := Polygon2D.new()
		panel.name = "PairBackdrop%02d" % (variant + 1)
		panel.polygon = PackedVector2Array(
			[
				Vector2(center_x - 270.0, center_y - 330.0),
				Vector2(center_x + 270.0, center_y - 330.0),
				Vector2(center_x + 270.0, center_y + 145.0),
				Vector2(center_x - 270.0, center_y + 145.0),
			],
		)
		panel.color = Color(0.10, 0.14, 0.10, 0.56) \
		if (variant + row) % 2 == 0 \
		else Color(0.12, 0.16, 0.11, 0.56)
		panel.z_index = -20
		add_child(panel)


func _fail_lab(reason: String) -> void:
	_native_build_ok = false
	_status_label.text = Localization.t(
		"UI_TREE_COLLISION_LAB_ERROR",
		{ "reason": reason },
	)
	push_error("TreeCollisionDepthDevScene: %s" % reason)
