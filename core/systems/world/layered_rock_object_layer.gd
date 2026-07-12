class_name LayeredRockObjectLayer
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")

const SNOW_ACCUMULATION_SHADER: Shader = preload("res://assets/shaders/layered_tree_snow_accumulation.gdshader")

const LADDER_ANCHOR_UNSET: int = 1 << 30
const BAKED_SHADOW_DIRECTION: Vector2 = Vector2(0.887216, -0.461354)
const DEFAULT_RUNTIME_SHADOW_DIRECTION: Vector2 = Vector2(0.70710678, 0.70710678)
const DEFAULT_ASSET_DIR: String = "res://assets/sprites/decor/plains/layered_small_rocks/small_rock_01"
const FALLBACK_VISIBLE_WIDTH_PX: float = 360.0
const USE_PACKET_TINT: bool = true

var _asset_dirs: Array[String] = [DEFAULT_ASSET_DIR]
var _assets_by_dir: Dictionary = {}
var _asset_dir: String = DEFAULT_ASSET_DIR
var _meta: Dictionary = {}
var _textures: Dictionary = {}
var _snow_material: ShaderMaterial = null
var _visual_root: Node2D = null
var _shadow_root: Node2D = null
var _rock_nodes: Array[Node2D] = []
var _shadow_nodes: Array[Node2D] = []
var _instances: Array[Dictionary] = []
var _world_origin_y: float = 0.0
var _applied_anchor_stripe: int = LADDER_ANCHOR_UNSET
var _season_amount: float = 0.0
var _shadow_length_scale: float = 1.0
var _shadow_opacity: float = 0.0
var _shadow_direction: Vector2 = DEFAULT_RUNTIME_SHADOW_DIRECTION
var _shadow_rotation_rad: float = DEFAULT_RUNTIME_SHADOW_DIRECTION.angle() - BAKED_SHADOW_DIRECTION.angle()


func set_asset_dir(asset_dir: String) -> void:
	set_asset_dirs([asset_dir] if not asset_dir.is_empty() else [])


func set_asset_dirs(asset_dirs: Array) -> void:
	var normalized: Array[String] = _normalize_asset_dirs(asset_dirs)
	if normalized == _asset_dirs and not _assets_by_dir.is_empty():
		return
	_asset_dirs = normalized
	_asset_dir = _asset_dirs[0] if not _asset_dirs.is_empty() else ""
	_load_assets()
	_rebuild_instances()


func set_world_origin_y(world_origin_y: float) -> void:
	_world_origin_y = world_origin_y
	if _applied_anchor_stripe != LADDER_ANCHOR_UNSET:
		update_ladder_z(_applied_anchor_stripe)


func set_sun_lighting(
		light_angle_deg: float,
		shadow_length_px: float,
		shadow_opacity: float,
		_shadow_softness_px: float,
) -> void:
	_shadow_direction = WorldVisualLightingProfile.shadow_direction_for_light_angle_deg(light_angle_deg)
	_shadow_rotation_rad = _shadow_direction.angle() - BAKED_SHADOW_DIRECTION.angle()
	var low_sun: float = clampf(
		(shadow_length_px - WorldVisualLightingProfile.SHADOW_MIN_LENGTH_PX)
				/ maxf(
					WorldVisualLightingProfile.SHADOW_MAX_LENGTH_PX - WorldVisualLightingProfile.SHADOW_MIN_LENGTH_PX,
					0.001,
				),
		0.0,
		1.0,
	)
	_shadow_length_scale = lerpf(1.0, 1.85, low_sun)
	_shadow_opacity = clampf(shadow_opacity * 0.82, 0.0, 0.82)
	_rebuild_all_shadow_polygons()


func update_ladder_z(anchor_stripe: int) -> void:
	_applied_anchor_stripe = anchor_stripe
	for rock_root: Node2D in _rock_nodes:
		if rock_root == null or not is_instance_valid(rock_root):
			continue
		var position: Vector2 = rock_root.get_meta("rock_position", Vector2.ZERO) as Vector2
		var world_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(_world_origin_y + position.y)
		rock_root.z_index = WorldRuntimeConstants.z_for_stripe_vs_anchor(world_stripe, anchor_stripe, true)
	for shadow_root: Node2D in _shadow_nodes:
		if shadow_root == null or not is_instance_valid(shadow_root):
			continue
		var position: Vector2 = shadow_root.get_meta("rock_position", Vector2.ZERO) as Vector2
		var world_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(_world_origin_y + position.y)
		# Small rock shadows must stay below their own visual, while still using the same depth stripe.
		shadow_root.z_index = WorldRuntimeConstants.z_for_stripe_vs_anchor(world_stripe, anchor_stripe, false)


func set_season_amount(season_amount: float) -> void:
	_season_amount = clampf(season_amount, 0.0, 1.0)
	for asset: Dictionary in _assets_by_dir.values():
		var snow_material: ShaderMaterial = asset.get("snow_material", null) as ShaderMaterial
		if snow_material != null:
			snow_material.set_shader_parameter("season_amount", _season_amount)
	for rock_root: Node2D in _rock_nodes:
		if rock_root == null or not is_instance_valid(rock_root):
			continue
		var snow: CanvasItem = rock_root.get_node_or_null("SnowOverlay") as CanvasItem
		if snow != null:
			snow.visible = _season_amount > 0.01


func set_instances(instances: Array[Dictionary]) -> void:
	_instances = instances.duplicate(true)
	_rebuild_instances()


func clear_instances() -> void:
	_instances.clear()
	_clear_instance_nodes()


func get_debug_state() -> Dictionary:
	return {
		"ready": not _assets_by_dir.is_empty(),
		"asset_dir": _asset_dir,
		"asset_dirs": _asset_dirs.duplicate(),
		"asset_count": _asset_dirs.size(),
		"loaded_asset_count": _assets_by_dir.size(),
		"unique_asset_dir_count": _unique_instance_asset_dir_count(),
		"instance_count": _rock_nodes.size(),
		"shadow_instance_count": _shadow_nodes.size(),
		"has_snow_material": _snow_material != null,
		"has_normal_texture": false,
		"blocks_movement": false,
		"collision_radius": 0.0,
		"shadow_length_scale": _shadow_length_scale,
		"shadow_direction": _shadow_direction,
		"shadow_rotation_degrees": rad_to_deg(_shadow_rotation_rad),
		"season_amount": _season_amount,
		"uses_packet_tint": USE_PACKET_TINT,
		"unique_visual_scale_count": _unique_visual_scale_count(),
	}


func _ready() -> void:
	_ensure_roots()
	_load_assets()
	_rebuild_instances()


func _load_assets() -> void:
	_assets_by_dir.clear()
	for asset_dir: String in _asset_dirs:
		var asset: Dictionary = _load_asset(asset_dir)
		if asset.is_empty():
			continue
		_assets_by_dir[asset_dir] = asset
	_set_primary_asset_data()


func _load_asset(asset_dir: String) -> Dictionary:
	var meta: Dictionary = _load_json_dictionary("%s/meta.json" % asset_dir)
	if meta.is_empty():
		return {}
	var textures: Dictionary = {
		"albedo": _load_png_texture("%s/albedo.png" % asset_dir),
		"shadow": _load_png_texture("%s/shadow.png" % asset_dir),
		"snow_overlay": _load_png_texture("%s/snow_overlay.png" % asset_dir),
		"snow_mask": _load_png_texture("%s/snow_mask.png" % asset_dir),
	}
	var snow_material := ShaderMaterial.new()
	snow_material.shader = SNOW_ACCUMULATION_SHADER
	snow_material.set_shader_parameter("snow_mask_texture", textures.get("snow_mask"))
	snow_material.set_shader_parameter("season_amount", _season_amount)
	return {
		"asset_dir": asset_dir,
		"meta": meta,
		"textures": textures,
		"snow_material": snow_material,
	}


func _set_primary_asset_data() -> void:
	var primary: Dictionary = {}
	for asset_dir: String in _asset_dirs:
		if _assets_by_dir.has(asset_dir):
			primary = _assets_by_dir[asset_dir] as Dictionary
			break
	_meta = primary.get("meta", {}) as Dictionary
	_textures = primary.get("textures", {}) as Dictionary
	_snow_material = primary.get("snow_material", null) as ShaderMaterial


func _ensure_roots() -> void:
	if _shadow_root == null or not is_instance_valid(_shadow_root):
		_shadow_root = Node2D.new()
		_shadow_root.name = "LayeredRockShadowRoot"
		add_child(_shadow_root)
	_shadow_root.z_index = 0
	if _visual_root == null or not is_instance_valid(_visual_root):
		_visual_root = Node2D.new()
		_visual_root.name = "LayeredRockVisualRoot"
		add_child(_visual_root)
	_visual_root.z_index = 0


func _rebuild_instances() -> void:
	_ensure_roots()
	_clear_instance_nodes()
	if _assets_by_dir.is_empty():
		return
	for index: int in range(_instances.size()):
		var instance: Dictionary = _instances[index]
		var asset_dir: String = _asset_dir_for_instance(instance, index)
		if asset_dir.is_empty() or not _assets_by_dir.has(asset_dir):
			continue
		var asset: Dictionary = _assets_by_dir[asset_dir] as Dictionary
		var position: Vector2 = instance.get("position", Vector2.ZERO) as Vector2
		var scale_factor: float = _scale_for_size(asset, float(instance.get("size_px", 56.0)))
		var tint: Color = Color.WHITE
		if USE_PACKET_TINT:
			tint = instance.get("tint", Color.WHITE) as Color
		_rock_nodes.append(_build_visual_rock(index, asset, position, scale_factor, tint))
		_shadow_nodes.append(_build_shadow_rock(index, asset, position, scale_factor))
	if _applied_anchor_stripe != LADDER_ANCHOR_UNSET:
		update_ladder_z(_applied_anchor_stripe)


func _clear_instance_nodes() -> void:
	for node: Node2D in _rock_nodes:
		if node != null and is_instance_valid(node):
			node.free()
	for node: Node2D in _shadow_nodes:
		if node != null and is_instance_valid(node):
			node.free()
	_rock_nodes.clear()
	_shadow_nodes.clear()


func _build_visual_rock(index: int, asset: Dictionary, position: Vector2, scale_factor: float, tint: Color) -> Node2D:
	var root := Node2D.new()
	root.name = "LayeredRock%d" % index
	root.position = position
	root.set_meta("asset_dir", str(asset.get("asset_dir", "")))
	root.set_meta("rock_position", position)
	_visual_root.add_child(root)

	var textures: Dictionary = asset.get("textures", {}) as Dictionary
	var sprite_position: Vector2 = _sprite_position_for_scale(asset, scale_factor)
	var albedo := _make_sprite("Albedo", textures.get("albedo") as Texture2D, sprite_position, scale_factor)
	albedo.z_index = 0
	albedo.modulate = tint
	root.add_child(albedo)

	var snow := _make_sprite("SnowOverlay", textures.get("snow_overlay") as Texture2D, sprite_position, scale_factor)
	snow.z_index = 1
	snow.material = asset.get("snow_material", null) as ShaderMaterial
	snow.visible = _season_amount > 0.01
	root.add_child(snow)
	return root


func _build_shadow_rock(index: int, asset: Dictionary, position: Vector2, scale_factor: float) -> Node2D:
	var root := Node2D.new()
	root.name = "LayeredRockShadow%d" % index
	root.position = position
	root.set_meta("asset_dir", str(asset.get("asset_dir", "")))
	root.set_meta("scale_factor", scale_factor)
	root.set_meta("rock_position", position)
	_shadow_root.add_child(root)
	var textures: Dictionary = asset.get("textures", {}) as Dictionary
	for polygon_name: String in ["ShadowBack", "ShadowForward"]:
		var polygon := Polygon2D.new()
		polygon.name = polygon_name
		polygon.texture = textures.get("shadow") as Texture2D
		polygon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		polygon.modulate = Color(1.0, 1.0, 1.0, _shadow_opacity)
		root.add_child(polygon)
	_rebuild_shadow_polygons_for(root, asset, scale_factor)
	return root


func _rebuild_all_shadow_polygons() -> void:
	for shadow_node: Node2D in _shadow_nodes:
		if shadow_node == null or not is_instance_valid(shadow_node):
			continue
		var asset_dir: String = str(shadow_node.get_meta("asset_dir", ""))
		if not _assets_by_dir.has(asset_dir):
			continue
		var scale_factor: float = float(shadow_node.get_meta("scale_factor", 1.0))
		_rebuild_shadow_polygons_for(shadow_node, _assets_by_dir[asset_dir] as Dictionary, scale_factor)


func _rebuild_shadow_polygons_for(root: Node2D, asset: Dictionary, scale_factor: float) -> void:
	var back := root.get_node_or_null("ShadowBack") as Polygon2D
	var forward := root.get_node_or_null("ShadowForward") as Polygon2D
	if back == null or forward == null:
		return
	back.modulate = Color(1.0, 1.0, 1.0, _shadow_opacity)
	forward.modulate = Color(1.0, 1.0, 1.0, _shadow_opacity)
	var frame_size: Vector2 = _frame_size(asset)
	var rect_points: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(frame_size.x, 0.0),
		frame_size,
		Vector2(0.0, frame_size.y),
	]
	var anchor: Vector2 = _anchor(asset)
	_set_shadow_polygon(back, _clip_shadow_polygon(rect_points, false, anchor), scale_factor, false, anchor)
	_set_shadow_polygon(forward, _clip_shadow_polygon(rect_points, true, anchor), scale_factor, true, anchor)


func _set_shadow_polygon(
		polygon: Polygon2D,
		texture_points: Array[Vector2],
		scale_factor: float,
		stretch_forward: bool,
		anchor: Vector2,
) -> void:
	var local_points: Array[Vector2] = []
	for point: Vector2 in texture_points:
		local_points.append(_shadow_texture_point_to_local(point, scale_factor, stretch_forward, anchor))
	polygon.polygon = PackedVector2Array(local_points)
	polygon.uv = PackedVector2Array(texture_points)


func _shadow_texture_point_to_local(point: Vector2, scale_factor: float, stretch_forward: bool, anchor: Vector2) -> Vector2:
	var delta: Vector2 = point - anchor
	if stretch_forward:
		var forward_distance: float = maxf(delta.dot(BAKED_SHADOW_DIRECTION), 0.0)
		delta += BAKED_SHADOW_DIRECTION * forward_distance * (_shadow_length_scale - 1.0)
	return delta.rotated(_shadow_rotation_rad) * scale_factor


func _clip_shadow_polygon(points: Array[Vector2], keep_forward: bool, anchor: Vector2) -> Array[Vector2]:
	if points.is_empty():
		return []
	var clipped: Array[Vector2] = []
	for index: int in range(points.size()):
		var current: Vector2 = points[index]
		var previous: Vector2 = points[(index + points.size() - 1) % points.size()]
		var current_inside: bool = _shadow_point_inside(current, keep_forward, anchor)
		var previous_inside: bool = _shadow_point_inside(previous, keep_forward, anchor)
		if current_inside:
			if not previous_inside:
				clipped.append(_shadow_line_intersection(previous, current, anchor))
			clipped.append(current)
		elif previous_inside:
			clipped.append(_shadow_line_intersection(previous, current, anchor))
	return clipped


func _shadow_point_inside(point: Vector2, keep_forward: bool, anchor: Vector2) -> bool:
	var distance: float = _shadow_signed_distance(point, anchor)
	return distance >= -0.01 if keep_forward else distance <= 0.01


func _shadow_line_intersection(a: Vector2, b: Vector2, anchor: Vector2) -> Vector2:
	var da: float = _shadow_signed_distance(a, anchor)
	var db: float = _shadow_signed_distance(b, anchor)
	var denominator: float = da - db
	if absf(denominator) < 0.0001:
		return a
	return a.lerp(b, clampf(da / denominator, 0.0, 1.0))


func _shadow_signed_distance(point: Vector2, anchor: Vector2) -> float:
	return (point - anchor).dot(BAKED_SHADOW_DIRECTION)


func _scale_for_size(asset: Dictionary, size_px: float) -> float:
	return clampf(size_px, 1.0, 254.0) / maxf(_visible_width(asset), 1.0)


func _visible_width(asset: Dictionary) -> float:
	var meta: Dictionary = asset.get("meta", {}) as Dictionary
	var bbox: Array = meta.get("alpha_bbox", []) as Array
	if bbox.size() >= 4:
		return maxf(float(bbox[2]), 1.0)
	return FALLBACK_VISIBLE_WIDTH_PX


func _unique_visual_scale_count() -> int:
	var unique_scales: Dictionary = {}
	for rock_root: Node2D in _rock_nodes:
		if rock_root == null or not is_instance_valid(rock_root):
			continue
		var albedo := rock_root.get_node_or_null("Albedo") as Sprite2D
		if albedo == null:
			continue
		unique_scales[roundi(albedo.scale.x * 10000.0)] = true
	return unique_scales.size()


func _unique_instance_asset_dir_count() -> int:
	var unique_asset_dirs: Dictionary = {}
	for rock_root: Node2D in _rock_nodes:
		if rock_root == null or not is_instance_valid(rock_root):
			continue
		unique_asset_dirs[str(rock_root.get_meta("asset_dir", ""))] = true
	return unique_asset_dirs.size()


func _sprite_position_for_scale(asset: Dictionary, scale_factor: float) -> Vector2:
	var center: Vector2 = _frame_size(asset) * 0.5
	return -(_anchor(asset) - center) * scale_factor


func _frame_size(asset: Dictionary) -> Vector2:
	var meta: Dictionary = asset.get("meta", {}) as Dictionary
	return Vector2(
		float(meta.get("frame_width", 768)),
		float(meta.get("frame_height", 768)),
	)


func _anchor(asset: Dictionary) -> Vector2:
	var meta: Dictionary = asset.get("meta", {}) as Dictionary
	var anchor_array: Array = meta.get("anchor", [384.0, 482.0]) as Array
	return Vector2(float(anchor_array[0]), float(anchor_array[1]))


func _make_sprite(sprite_name: String, texture: Texture2D, sprite_position: Vector2, scale_factor: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.centered = true
	sprite.position = sprite_position
	sprite.scale = Vector2.ONE * scale_factor
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return sprite


func _load_png_texture(path: String) -> Texture2D:
	if FileAccess.file_exists(path + ".import"):
		var imported: Texture2D = load(path) as Texture2D
		if imported != null:
			return imported
	var image := Image.new()
	var err: int = image.load(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("LayeredRockObjectLayer: cannot load %s (err %d)" % [path, err])
		return null
	return ImageTexture.create_from_image(image)


func _asset_dir_for_instance(instance: Dictionary, index: int) -> String:
	var requested: String = str(instance.get("asset_dir", ""))
	if not requested.is_empty() and _assets_by_dir.has(requested):
		return requested
	if _asset_dirs.is_empty():
		return ""
	return _asset_dirs[index % _asset_dirs.size()]


func _normalize_asset_dirs(asset_dirs: Array) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	for value: Variant in asset_dirs:
		var asset_dir: String = str(value).strip_edges()
		if asset_dir.is_empty() or seen.has(asset_dir):
			continue
		seen[asset_dir] = true
		result.append(asset_dir)
	return result


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("LayeredRockObjectLayer: missing JSON %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed as Dictionary
	push_error("LayeredRockObjectLayer: invalid JSON %s" % path)
	return {}
