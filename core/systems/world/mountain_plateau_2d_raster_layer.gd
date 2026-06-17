class_name MountainPlateau2DRasterLayer
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const TOP_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_albedo.png"
const FACE_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_albedo.png"
const TOP_NORMAL_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_normal.png"
const FACE_NORMAL_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_normal.png"

const TILE_SIZE_PX: float = 64.0
const SAMPLE_STEP_PX: float = 1.0
const GROUND_BACKDROP_PADDING_TILES: int = 2

# Scaled from the lab defaults: tile_size=128, south_height=64, rim_width=16.
const FACADE_HEIGHT_PX: float = 32.0
const ROUND_BLUR_RADIUS_PX: float = 32.0
const ROUND_BLUR_PASSES: int = 2

const TOP_THRESHOLD_LOW: float = 0.492
const TOP_THRESHOLD_HIGH: float = 0.508
const RIM_INNER_LOW: float = 0.670
const RIM_INNER_HIGH: float = 0.690

const TOP_TEXTURE_SOURCE_SCALE: float = 0.70
const FACE_TEXTURE_SOURCE_SCALE: float = 0.46
const TOP_TEXTURE_BLEND: float = 0.34
const FACE_TEXTURE_BLEND: float = 0.42

const GROUND_COLOR: Color = Color(0.24, 0.18, 0.12, 1.0)
const GROUND_DETAIL_COLOR: Color = Color(0.34, 0.26, 0.17, 1.0)
const TOP_COLOR: Color = Color(0.76, 0.31, 0.10, 1.0)
const TOP_LIGHT_COLOR: Color = Color(0.93, 0.44, 0.16, 1.0)
const TOP_DARK_COLOR: Color = Color(0.39, 0.13, 0.04, 1.0)
const FACE_TOP_COLOR: Color = Color(0.48, 0.18, 0.06, 1.0)
const FACE_BOTTOM_COLOR: Color = Color(0.15, 0.045, 0.018, 1.0)
const RIM_COLOR: Color = Color(0.17, 0.055, 0.02, 1.0)
const RIM_LIGHT_COLOR: Color = Color(0.63, 0.24, 0.075, 1.0)
const OUTLINE_COLOR: Color = Color(0.018, 0.012, 0.008, 1.0)

const DEFAULT_PRESET: Dictionary = {
	"facade_height_px": 32.0,
	"round_blur_radius_px": 32.0,
	"shape_blob_radius_px": 76.0,
	"shape_domain_warp_px": 14.0,
	"shape_domain_warp_scale_px": 288.0,
	"shape_lobe_px": 8.0,
	"shape_lobe_scale_px": 168.0,
	"normal_strength": 4.0,
	"normal_top_detail_strength": 0.72,
	"normal_face_detail_strength": 0.95,
	"normal_detail_scale_px": 18.0,
	"normal_macro_scale_px": 96.0,
	"top_threshold_center": 0.500,
	"top_threshold_width": 0.016,
	"rim_threshold_center": 0.680,
	"rim_threshold_width": 0.020,
	"edge_warp_px": 0.0,
	"edge_warp_scale_px": 192.0,
	"top_texture_scale": 0.70,
	"top_texture_blend": 0.34,
	"top_macro_scale_px": 420.0,
	"top_macro_strength": 0.10,
	"face_texture_scale": 0.46,
	"face_texture_blend": 0.42,
	"face_darkening": 0.18,
	"rim_strength": 0.92,
	"rim_light_strength": 0.16,
	"outline_strength": 0.85,
	"runtime_ground_patch": false,
}

static func default_preset() -> Dictionary:
	return DEFAULT_PRESET.duplicate(true)

static func preset_specs() -> Array[Dictionary]:
	return [
		{"key": "facade_height_px", "label": "Facade height", "min": 8.0, "max": 96.0, "step": 1.0},
		{"key": "round_blur_radius_px", "label": "Round blur", "min": 4.0, "max": 72.0, "step": 1.0},
		{"key": "shape_blob_radius_px", "label": "Shape blob radius", "min": 42.0, "max": 112.0, "step": 1.0},
		{"key": "shape_domain_warp_px", "label": "Shape wave strength", "min": 0.0, "max": 36.0, "step": 0.5},
		{"key": "shape_domain_warp_scale_px", "label": "Shape wave size", "min": 96.0, "max": 768.0, "step": 1.0},
		{"key": "shape_lobe_px", "label": "Shape lobe strength", "min": 0.0, "max": 28.0, "step": 0.5},
		{"key": "shape_lobe_scale_px", "label": "Shape lobe size", "min": 64.0, "max": 512.0, "step": 1.0},
		{"key": "normal_strength", "label": "Normal strength", "min": 0.2, "max": 9.0, "step": 0.1},
		{"key": "normal_top_detail_strength", "label": "Top normal detail", "min": 0.0, "max": 1.8, "step": 0.01},
		{"key": "normal_face_detail_strength", "label": "Face normal detail", "min": 0.0, "max": 2.2, "step": 0.01},
		{"key": "normal_detail_scale_px", "label": "Normal fine scale", "min": 6.0, "max": 96.0, "step": 1.0},
		{"key": "normal_macro_scale_px", "label": "Normal macro scale", "min": 32.0, "max": 320.0, "step": 1.0},
		{"key": "top_threshold_center", "label": "Top threshold", "min": 0.420, "max": 0.580, "step": 0.001},
		{"key": "top_threshold_width", "label": "Top edge AA", "min": 0.002, "max": 0.080, "step": 0.001},
		{"key": "rim_threshold_center", "label": "Rim threshold", "min": 0.540, "max": 0.860, "step": 0.001},
		{"key": "rim_threshold_width", "label": "Rim edge AA", "min": 0.002, "max": 0.120, "step": 0.001},
		{"key": "edge_warp_px", "label": "Edge warp", "min": 0.0, "max": 18.0, "step": 0.25},
		{"key": "edge_warp_scale_px", "label": "Warp scale", "min": 32.0, "max": 640.0, "step": 1.0},
		{"key": "top_texture_scale", "label": "Top tex scale", "min": 0.10, "max": 2.00, "step": 0.01},
		{"key": "top_texture_blend", "label": "Top tex blend", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": "top_macro_scale_px", "label": "Top macro scale", "min": 64.0, "max": 1200.0, "step": 1.0},
		{"key": "top_macro_strength", "label": "Top macro power", "min": 0.0, "max": 0.50, "step": 0.01},
		{"key": "face_texture_scale", "label": "Face tex scale", "min": 0.10, "max": 2.00, "step": 0.01},
		{"key": "face_texture_blend", "label": "Face tex blend", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": "face_darkening", "label": "Face darkening", "min": 0.0, "max": 0.65, "step": 0.01},
		{"key": "rim_strength", "label": "Rim strength", "min": 0.0, "max": 1.50, "step": 0.01},
		{"key": "rim_light_strength", "label": "Rim light", "min": 0.0, "max": 0.60, "step": 0.01},
		{"key": "outline_strength", "label": "Outline strength", "min": 0.0, "max": 1.50, "step": 0.01},
	]

var _mountain_tiles: Dictionary = {}
var _bounds: Rect2i = Rect2i()
var _render_origin_world: Vector2 = Vector2.ZERO
var _render_size_world: Vector2 = Vector2.ZERO
var _image_texture: ImageTexture = null
var _normal_texture: ImageTexture = null
var _lit_texture: CanvasTexture = null
var _ground_texture: ImageTexture = null
var _ground_normal_texture: ImageTexture = null
var _ground_lit_texture: CanvasTexture = null
var _mountain_texture: ImageTexture = null
var _mountain_normal_texture: ImageTexture = null
var _mountain_lit_texture: CanvasTexture = null
var _hit_mask: PackedByteArray = PackedByteArray()
var _hit_mask_width: int = 0
var _hit_mask_height: int = 0
var _hit_mask_origin_world: Vector2 = Vector2.ZERO
var _hit_mask_step_px: float = 0.0
var _display_normal_map: bool = false
var _display_light_map: bool = false
var _display_ground_surface: bool = false
var _anchor_to_target_chunk: bool = true
var _ground_sprite: Sprite2D = null
var _mountain_sprite: Sprite2D = null
var _normal_preview_sprite: Sprite2D = null
var _light_occluder: LightOccluder2D = null
var _light_occluder_polygon: PackedVector2Array = PackedVector2Array()
var _top_image: Image = null
var _face_image: Image = null
var _native_core: Object = null
var _preset: Dictionary = default_preset()
var _debug_snapshot: Dictionary = {
	"ready": false,
}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_render_nodes()

func rebuild_from_packets(packets: Array[Dictionary], target_chunk: Vector2i) -> void:
	_ensure_source_images_loaded()
	_ensure_native_core()
	_mountain_tiles.clear()
	_bounds = Rect2i()
	_clear_textures()
	position = _resolve_layer_position(target_chunk)
	var result: Dictionary = _native_core.call(
		"build_mountain_plateau_raster_image",
		packets,
		target_chunk,
		_preset,
		_top_image,
		_face_image
	) as Dictionary
	_apply_native_result(result, target_chunk, packets.size())

func apply_raster_result(result: Dictionary, target_chunk: Vector2i, packet_count: int = 0) -> void:
	_mountain_tiles.clear()
	_bounds = Rect2i()
	_clear_textures()
	position = _resolve_layer_position(target_chunk)
	_apply_native_result(result, target_chunk, packet_count)

func apply_hit_mask_result(result: Dictionary, target_chunk: Vector2i, packet_count: int = 0) -> void:
	_mountain_tiles.clear()
	_bounds = Rect2i()
	_clear_textures()
	position = _resolve_layer_position(target_chunk)
	_store_hit_mask(result)
	_render_origin_world = result.get("render_origin_world", Vector2.ZERO) as Vector2
	_render_size_world = result.get("render_size_world", Vector2.ZERO) as Vector2
	_sync_render_nodes()
	_debug_snapshot = _compact_native_result(result)
	_debug_snapshot["preset"] = get_preset()
	_debug_snapshot["normal_preview"] = false
	_debug_snapshot["light_preview"] = false
	_debug_snapshot["lit_texture_ready"] = false
	_debug_snapshot["ground_lit_texture_ready"] = false
	_debug_snapshot["mountain_lit_texture_ready"] = false
	_debug_snapshot["lit_split_surface_ready"] = false
	_debug_snapshot["light_occluder_ready"] = false
	_debug_snapshot["hit_mask_ready"] = _hit_mask_width > 0 and _hit_mask_height > 0 and not _hit_mask.is_empty()
	_debug_snapshot["hit_mask_width"] = _hit_mask_width
	_debug_snapshot["hit_mask_height"] = _hit_mask_height
	_debug_snapshot["hit_mask_step_px"] = _hit_mask_step_px
	_debug_snapshot["hit_mask_origin_world"] = _hit_mask_origin_world
	_debug_snapshot["ground_surface_visible"] = false
	_debug_snapshot["target_chunk_anchor_enabled"] = _anchor_to_target_chunk
	_debug_snapshot["layer_position"] = position
	_debug_snapshot["target_chunk"] = target_chunk
	_debug_snapshot["packet_count"] = packet_count if packet_count > 0 else int(_debug_snapshot.get("packet_count", 0))
	queue_redraw()

func get_source_images() -> Dictionary:
	_ensure_source_images_loaded()
	return {
		"top_image": _top_image.duplicate() if _top_image != null else null,
		"face_image": _face_image.duplicate() if _face_image != null else null,
	}

func _apply_native_result(result: Dictionary, target_chunk: Vector2i, packet_count: int) -> void:
	var image: Image = result.get("image", null) as Image
	var normal_image: Image = result.get("normal_image", null) as Image
	var ground_image: Image = result.get("ground_image", null) as Image
	var ground_normal_image: Image = result.get("ground_normal_image", null) as Image
	var mountain_image: Image = result.get("mountain_image", null) as Image
	var mountain_normal_image: Image = result.get("mountain_normal_image", null) as Image
	if normal_image == null:
		normal_image = mountain_normal_image
	if mountain_image == null \
			or (_display_ground_surface and ground_image == null):
		push_error("MountainPlateau2DRasterLayer native raster build returned incomplete runtime images.")
		_debug_snapshot = {
			"ready": false,
			"packet_count": packet_count,
			"native": true,
			"target_chunk": target_chunk,
			"success": bool(result.get("success", false)),
			"message": str(result.get("message", "")),
		}
		_sync_render_nodes()
		queue_redraw()
		return
	_image_texture = ImageTexture.create_from_image(image) if image != null else null
	_normal_texture = ImageTexture.create_from_image(normal_image) if normal_image != null else null
	_ground_texture = ImageTexture.create_from_image(ground_image) if ground_image != null else null
	_ground_normal_texture = ImageTexture.create_from_image(ground_normal_image) if ground_normal_image != null else null
	_mountain_texture = ImageTexture.create_from_image(mountain_image)
	_mountain_normal_texture = ImageTexture.create_from_image(mountain_normal_image) if mountain_normal_image != null else null
	_lit_texture = _create_lit_texture(_image_texture, _normal_texture) if _image_texture != null and _normal_texture != null else null
	_ground_lit_texture = _create_lit_texture(_ground_texture, _ground_normal_texture) if _ground_texture != null and _ground_normal_texture != null else null
	_mountain_lit_texture = _create_lit_texture(_mountain_texture, _mountain_normal_texture) if _mountain_normal_texture != null else null
	_store_hit_mask(result)
	_light_occluder_polygon = result.get("light_occluder_polygon", PackedVector2Array()) as PackedVector2Array
	_render_origin_world = result.get("render_origin_world", Vector2.ZERO) as Vector2
	_render_size_world = result.get("render_size_world", Vector2.ZERO) as Vector2
	_sync_render_nodes()
	_debug_snapshot = _compact_native_result(result)
	_debug_snapshot["preset"] = get_preset()
	_debug_snapshot["normal_preview"] = _display_normal_map
	_debug_snapshot["light_preview"] = _display_light_map
	_debug_snapshot["lit_texture_ready"] = _lit_texture != null
	_debug_snapshot["ground_lit_texture_ready"] = _ground_lit_texture != null
	_debug_snapshot["mountain_lit_texture_ready"] = _mountain_lit_texture != null
	_debug_snapshot["lit_split_surface_ready"] = _ground_lit_texture != null and _mountain_lit_texture != null
	_debug_snapshot["light_occluder_ready"] = _light_occluder_polygon.size() >= 8
	_debug_snapshot["hit_mask_ready"] = _hit_mask_width > 0 and _hit_mask_height > 0 and not _hit_mask.is_empty()
	_debug_snapshot["hit_mask_width"] = _hit_mask_width
	_debug_snapshot["hit_mask_height"] = _hit_mask_height
	_debug_snapshot["hit_mask_step_px"] = _hit_mask_step_px
	_debug_snapshot["hit_mask_origin_world"] = _hit_mask_origin_world
	_debug_snapshot["ground_surface_visible"] = _display_ground_surface
	_debug_snapshot["target_chunk_anchor_enabled"] = _anchor_to_target_chunk
	_debug_snapshot["layer_position"] = position
	_debug_snapshot["target_chunk"] = target_chunk
	_debug_snapshot["packet_count"] = packet_count if packet_count > 0 else int(_debug_snapshot.get("packet_count", 0))
	queue_redraw()

func clear_plateau() -> void:
	_mountain_tiles.clear()
	_bounds = Rect2i()
	_clear_textures()
	_sync_render_nodes()
	_debug_snapshot = {
		"ready": false,
		"light_preview": _display_light_map,
		"lit_texture_ready": false,
		"lit_split_surface_ready": false,
		"light_occluder_ready": false,
		"hit_mask_ready": false,
		"ground_surface_visible": _display_ground_surface,
		"target_chunk_anchor_enabled": _anchor_to_target_chunk,
		"layer_position": position,
	}
	queue_redraw()

func get_debug_snapshot() -> Dictionary:
	return _debug_snapshot.duplicate(true)

func set_preset(preset: Dictionary) -> void:
	_preset = _sanitize_preset(preset)

func get_preset() -> Dictionary:
	return _preset.duplicate(true)

func set_display_normal_map(enabled: bool) -> void:
	_display_normal_map = enabled
	if _display_normal_map:
		_display_light_map = false
	_debug_snapshot["normal_preview"] = _display_normal_map
	_debug_snapshot["light_preview"] = _display_light_map
	_sync_render_nodes()
	queue_redraw()

func is_displaying_normal_map() -> bool:
	return _display_normal_map

func set_display_light_map(enabled: bool) -> void:
	_display_light_map = enabled
	if _display_light_map:
		_display_normal_map = false
	_debug_snapshot["light_preview"] = _display_light_map
	_debug_snapshot["normal_preview"] = _display_normal_map
	_debug_snapshot["lit_texture_ready"] = _lit_texture != null
	_debug_snapshot["ground_lit_texture_ready"] = _ground_lit_texture != null
	_debug_snapshot["mountain_lit_texture_ready"] = _mountain_lit_texture != null
	_debug_snapshot["lit_split_surface_ready"] = _ground_lit_texture != null and _mountain_lit_texture != null
	_debug_snapshot["light_occluder_ready"] = _light_occluder_polygon.size() >= 8
	_sync_render_nodes()
	queue_redraw()

func is_displaying_light_map() -> bool:
	return _display_light_map

func set_ground_surface_enabled(enabled: bool) -> void:
	_display_ground_surface = enabled
	_debug_snapshot["ground_surface_visible"] = _display_ground_surface
	_sync_render_nodes()
	queue_redraw()

func is_ground_surface_enabled() -> bool:
	return _display_ground_surface

func set_target_chunk_anchor_enabled(enabled: bool) -> void:
	_anchor_to_target_chunk = enabled
	_debug_snapshot["target_chunk_anchor_enabled"] = _anchor_to_target_chunk
	_debug_snapshot["layer_position"] = position

func is_target_chunk_anchor_enabled() -> bool:
	return _anchor_to_target_chunk

func sample_mountain_hit_at_world(world_pos: Vector2) -> Dictionary:
	if _hit_mask.is_empty() or _hit_mask_width <= 0 or _hit_mask_height <= 0 or _hit_mask_step_px <= 0.0:
		return {
			"ready": false,
			"in_bounds": false,
			"solid": false,
		}
	var mask_position: Vector2 = (world_pos - _hit_mask_origin_world) / _hit_mask_step_px
	var x: int = floori(mask_position.x)
	var y: int = floori(mask_position.y)
	if x < 0 or y < 0 or x >= _hit_mask_width or y >= _hit_mask_height:
		return {
			"ready": true,
			"in_bounds": false,
			"solid": false,
		}
	var index: int = y * _hit_mask_width + x
	return {
		"ready": true,
		"in_bounds": true,
		"solid": int(_hit_mask[index]) != 0,
	}

func _draw() -> void:
	pass

func _clear_textures() -> void:
	_image_texture = null
	_normal_texture = null
	_lit_texture = null
	_ground_texture = null
	_ground_normal_texture = null
	_ground_lit_texture = null
	_mountain_texture = null
	_mountain_normal_texture = null
	_mountain_lit_texture = null
	_light_occluder_polygon = PackedVector2Array()
	_hit_mask = PackedByteArray()
	_hit_mask_width = 0
	_hit_mask_height = 0
	_hit_mask_origin_world = Vector2.ZERO
	_hit_mask_step_px = 0.0

func _store_hit_mask(result: Dictionary) -> void:
	_hit_mask = result.get("hit_mask", PackedByteArray()) as PackedByteArray
	_hit_mask_width = int(result.get("hit_mask_width", 0))
	_hit_mask_height = int(result.get("hit_mask_height", 0))
	_hit_mask_origin_world = result.get("hit_mask_origin_world", Vector2.ZERO) as Vector2
	_hit_mask_step_px = float(result.get("hit_mask_step_px", 0.0))

func _compact_native_result(result: Dictionary) -> Dictionary:
	var compact: Dictionary = {}
	for key_variant: Variant in result.keys():
		var key: Variant = key_variant
		if key in [
			"image",
			"normal_image",
			"ground_image",
			"ground_normal_image",
			"mountain_image",
			"mountain_normal_image",
			"light_occluder_polygon",
			"hit_mask",
		]:
			continue
		compact[key] = result[key]
	return compact

func _create_lit_texture(diffuse: Texture2D, normal: Texture2D) -> CanvasTexture:
	var lit_texture := CanvasTexture.new()
	lit_texture.diffuse_texture = diffuse
	lit_texture.normal_texture = normal
	return lit_texture

func _ensure_render_nodes() -> void:
	if _ground_sprite == null or not is_instance_valid(_ground_sprite):
		_ground_sprite = _create_sprite("GroundLitSurface", 0)
	if _mountain_sprite == null or not is_instance_valid(_mountain_sprite):
		_mountain_sprite = _create_sprite("MountainLitSurface", 1)
	if _normal_preview_sprite == null or not is_instance_valid(_normal_preview_sprite):
		_normal_preview_sprite = _create_sprite("NormalPreviewSurface", 2)
	if _light_occluder == null or not is_instance_valid(_light_occluder):
		_light_occluder = LightOccluder2D.new()
		_light_occluder.name = "MountainLightOccluder"
		add_child(_light_occluder)

func _create_sprite(sprite_name: String, _sprite_z_index: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.centered = false
	sprite.z_index = 0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	return sprite

func _sync_render_nodes() -> void:
	_ensure_render_nodes()
	_ground_sprite.position = _render_origin_world
	_mountain_sprite.position = _render_origin_world
	_normal_preview_sprite.position = _render_origin_world
	_ground_sprite.texture = _ground_lit_texture if _display_light_map and _ground_lit_texture != null else _ground_texture
	_mountain_sprite.texture = _mountain_lit_texture if _display_light_map else _mountain_texture
	_normal_preview_sprite.texture = _normal_texture
	_ground_sprite.visible = _ground_texture != null and not _display_normal_map and _display_ground_surface
	_mountain_sprite.visible = _mountain_texture != null and not _display_normal_map
	_normal_preview_sprite.visible = _normal_texture != null and _display_normal_map
	var has_occluder_polygon: bool = _light_occluder_polygon.size() >= 8
	if has_occluder_polygon:
		var occluder_polygon := OccluderPolygon2D.new()
		occluder_polygon.polygon = _light_occluder_polygon
		_light_occluder.occluder = occluder_polygon
	_light_occluder.visible = _display_light_map and has_occluder_polygon

func _ensure_source_images_loaded() -> void:
	if _top_image == null:
		_top_image = _load_external_image(TOP_TEXTURE_PATH, "mountain top")
	if _face_image == null:
		_face_image = _load_external_image(FACE_TEXTURE_PATH, "mountain face")

func _resolve_layer_position(target_chunk: Vector2i) -> Vector2:
	if not _anchor_to_target_chunk:
		return Vector2.ZERO
	return -WorldRuntimeConstants.chunk_origin_px(target_chunk)

func _load_external_image(path: String, label: String) -> Image:
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		push_error("MountainPlateau2DRasterLayer cannot load %s texture: %s" % [label, path])
		return null
	var image: Image = texture.get_image()
	if image == null:
		push_error("MountainPlateau2DRasterLayer %s texture has no readable image: %s" % [label, path])
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _ensure_native_core() -> void:
	if _native_core != null:
		return
	_native_core = ClassDB.instantiate("WorldCore")
	assert(_native_core != null, "WorldCore required for MountainPlateau2DRasterLayer native raster build.")
	assert(
		_native_core.has_method("build_mountain_plateau_raster_image"),
		"WorldCore.build_mountain_plateau_raster_image required - rebuild GDExtension."
	)

func _collect_mountain_tiles(packet: Dictionary) -> void:
	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(terrain_ids[index])
		if not _is_mountain_terrain(terrain_id):
			continue
		if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
			continue
		if terrain_id != WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
				and index < mountain_flags.size():
			var flags: int = int(mountain_flags[index])
			if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
				continue
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var world_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local_coord
		_mountain_tiles[world_tile] = true

func _build_raster_image(packet_count: int) -> void:
	if _mountain_tiles.is_empty():
		_debug_snapshot = {
			"ready": false,
			"packet_count": packet_count,
		}
		return

	_bounds = _calculate_tile_bounds()
	var facade_height_px: float = _preset_float("facade_height_px")
	var render_min_tile: Vector2i = _bounds.position - Vector2i(
		GROUND_BACKDROP_PADDING_TILES,
		GROUND_BACKDROP_PADDING_TILES
	)
	var render_tile_size: Vector2i = _bounds.size + Vector2i(
		GROUND_BACKDROP_PADDING_TILES * 2,
		GROUND_BACKDROP_PADDING_TILES * 2 + ceili(facade_height_px / TILE_SIZE_PX)
	)
	_render_origin_world = _grid_vertex_to_world(render_min_tile)
	_render_size_world = Vector2(render_tile_size) * TILE_SIZE_PX + Vector2(0.0, facade_height_px)
	var image_width: int = ceili(_render_size_world.x / SAMPLE_STEP_PX)
	var image_height: int = ceili(_render_size_world.y / SAMPLE_STEP_PX)
	var total_pixels: int = image_width * image_height

	var source_mask: PackedFloat32Array = _build_source_mask(render_min_tile, image_width, image_height)
	var smooth_mask: PackedFloat32Array = source_mask
	for _pass_index: int in range(ROUND_BLUR_PASSES):
		smooth_mask = _box_blur(smooth_mask, image_width, image_height, _blur_radius_samples())

	var top_alpha := PackedFloat32Array()
	top_alpha.resize(total_pixels)
	var top_threshold_center: float = _preset_float("top_threshold_center")
	var top_threshold_half_width: float = maxf(_preset_float("top_threshold_width") * 0.5, 0.001)
	var edge_warp_px: float = _preset_float("edge_warp_px")
	var edge_warp_scale_px: float = _preset_float("edge_warp_scale_px")
	var round_blur_radius_px: float = _preset_float("round_blur_radius_px")
	for index: int in range(total_pixels):
		var x: int = index % image_width
		var y: int = floori(float(index) / float(image_width))
		top_alpha[index] = _top_alpha_at(
			smooth_mask[index],
			x,
			y,
			top_threshold_center,
			top_threshold_half_width,
			edge_warp_px,
			edge_warp_scale_px,
			round_blur_radius_px
		)

	var face_alpha := PackedFloat32Array()
	var face_depth := PackedFloat32Array()
	_build_projected_face(top_alpha, image_width, image_height, face_alpha, face_depth)

	var image: Image = Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)
	var rim_center: float = _preset_float("rim_threshold_center")
	var rim_half_width: float = maxf(_preset_float("rim_threshold_width") * 0.5, 0.001)
	var rim_strength: float = _preset_float("rim_strength")
	var rim_light_strength: float = _preset_float("rim_light_strength")
	var outline_strength: float = _preset_float("outline_strength")
	var top_texture_scale: float = _preset_float("top_texture_scale")
	var top_texture_blend: float = _preset_float("top_texture_blend")
	var top_macro_scale_px: float = _preset_float("top_macro_scale_px")
	var top_macro_strength: float = _preset_float("top_macro_strength")
	var face_texture_scale: float = _preset_float("face_texture_scale")
	var face_texture_blend: float = _preset_float("face_texture_blend")
	var face_darkening: float = _preset_float("face_darkening")
	var top_pixel_count: int = 0
	var face_pixel_count: int = 0
	var rim_pixel_count: int = 0
	for y: int in range(image_height):
		for x: int in range(image_width):
			var index: int = y * image_width + x
			var world_position := _render_origin_world + Vector2(
				(float(x) + 0.5) * SAMPLE_STEP_PX,
				(float(y) + 0.5) * SAMPLE_STEP_PX
			)
			var color: Color = _ground_color_at(x, y, world_position)
			var face_a: float = face_alpha[index]
			if face_a > 0.01:
				face_pixel_count += 1
				color = _blend(
					color,
					_face_color_at(world_position, face_depth[index], face_texture_scale, face_texture_blend, face_darkening),
					face_a
				)

			var top_a: float = top_alpha[index]
			if top_a > 0.01:
				top_pixel_count += 1
				color = _blend(
					color,
					_top_color_at(
						x,
						y,
						world_position,
						top_texture_scale,
						top_texture_blend,
						top_macro_scale_px,
						top_macro_strength
					),
					top_a
				)
				var inner_alpha: float = smoothstep(rim_center - rim_half_width, rim_center + rim_half_width, smooth_mask[index])
				var rim_alpha: float = clampf(top_a - inner_alpha, 0.0, 1.0)
				if rim_alpha > 0.02:
					rim_pixel_count += 1
					color = _blend(color, RIM_COLOR, rim_alpha * rim_strength)
				var rim_light: float = maxf(0.0, inner_alpha - smoothstep(0.76, 0.90, smooth_mask[index]))
				color = _blend(color, RIM_LIGHT_COLOR, rim_light * rim_light_strength)

			var bottom_outline_alpha: float = _bottom_outline_alpha(
				face_alpha,
				image_width,
				image_height,
				x,
				y,
				index,
				outline_strength
			)
			if bottom_outline_alpha > 0.01:
				color = _blend(color, OUTLINE_COLOR, bottom_outline_alpha)
			image.set_pixel(x, y, color)

	_image_texture = ImageTexture.create_from_image(image)
	_debug_snapshot = {
		"ready": _image_texture != null,
		"packet_count": packet_count,
		"mountain_tile_count": _mountain_tiles.size(),
		"bounds_position": _bounds.position,
		"bounds_size": _bounds.size,
		"sample_step_px": SAMPLE_STEP_PX,
		"image_width": image_width,
		"image_height": image_height,
		"top_pixel_count": top_pixel_count,
		"face_pixel_count": face_pixel_count,
		"rim_pixel_count": rim_pixel_count,
		"facade_height_px": facade_height_px,
		"top_image_loaded": _top_image != null,
		"face_image_loaded": _face_image != null,
		"preset": get_preset(),
	}

func _calculate_tile_bounds() -> Rect2i:
	var min_tile := Vector2i(2147483647, 2147483647)
	var max_tile := Vector2i(-2147483648, -2147483648)
	for tile_variant: Variant in _mountain_tiles.keys():
		var tile: Vector2i = tile_variant as Vector2i
		min_tile.x = mini(min_tile.x, tile.x)
		min_tile.y = mini(min_tile.y, tile.y)
		max_tile.x = maxi(max_tile.x, tile.x)
		max_tile.y = maxi(max_tile.y, tile.y)
	return Rect2i(min_tile, max_tile - min_tile + Vector2i.ONE)

func _build_source_mask(render_min_tile: Vector2i, image_width: int, image_height: int) -> PackedFloat32Array:
	var mask := PackedFloat32Array()
	mask.resize(image_width * image_height)
	var samples_per_tile: int = _samples_per_tile()
	for tile_variant: Variant in _mountain_tiles.keys():
		var tile: Vector2i = tile_variant as Vector2i
		var start_x: int = (tile.x - render_min_tile.x) * samples_per_tile
		var start_y: int = (tile.y - render_min_tile.y) * samples_per_tile
		var end_x: int = mini(start_x + samples_per_tile, image_width)
		var end_y: int = mini(start_y + samples_per_tile, image_height)
		start_x = maxi(start_x, 0)
		start_y = maxi(start_y, 0)
		for y: int in range(start_y, end_y):
			var row: int = y * image_width
			for x: int in range(start_x, end_x):
				mask[row + x] = 1.0
	return mask

func _box_blur(source: PackedFloat32Array, width: int, height: int, radius: int) -> PackedFloat32Array:
	var horizontal := PackedFloat32Array()
	horizontal.resize(width * height)
	var row_prefix := PackedFloat32Array()
	row_prefix.resize(width + 1)
	for y: int in range(height):
		var row: int = y * width
		row_prefix[0] = 0.0
		for x: int in range(width):
			row_prefix[x + 1] = row_prefix[x] + source[row + x]
		for x: int in range(width):
			var start_x: int = maxi(0, x - radius)
			var end_x: int = mini(width - 1, x + radius)
			horizontal[row + x] = (row_prefix[end_x + 1] - row_prefix[start_x]) / float(end_x - start_x + 1)

	var result := PackedFloat32Array()
	result.resize(width * height)
	var column_prefix := PackedFloat32Array()
	column_prefix.resize(height + 1)
	for x: int in range(width):
		column_prefix[0] = 0.0
		for y: int in range(height):
			column_prefix[y + 1] = column_prefix[y] + horizontal[y * width + x]
		for y: int in range(height):
			var start_y: int = maxi(0, y - radius)
			var end_y: int = mini(height - 1, y + radius)
			result[y * width + x] = (column_prefix[end_y + 1] - column_prefix[start_y]) / float(end_y - start_y + 1)
	return result

func _build_projected_face(
	top_alpha: PackedFloat32Array,
	width: int,
	height: int,
	face_alpha: PackedFloat32Array,
	face_depth: PackedFloat32Array
) -> void:
	face_alpha.resize(width * height)
	face_depth.resize(width * height)
	var facade_samples: int = _facade_samples()
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			var top_here: float = top_alpha[index]
			var exposure: float = 1.0 - clampf(top_here * 1.15, 0.0, 1.0)
			if exposure <= 0.01:
				continue
			var best_alpha: float = 0.0
			var best_depth: float = 0.0
			for depth: int in range(1, facade_samples + 1):
				var sample_y: int = y - depth
				if sample_y < 0:
					break
				var candidate: float = top_alpha[sample_y * width + x] * exposure
				if candidate <= best_alpha:
					continue
				best_alpha = candidate
				best_depth = float(depth) / float(facade_samples)
			face_alpha[index] = best_alpha
			face_depth[index] = best_depth

func _ground_color_at(x: int, y: int, world_position: Vector2) -> Color:
	var coarse_x: int = int(floor(world_position.x / 48.0))
	var coarse_y: int = int(floor(world_position.y / 48.0))
	var noise: float = _noise_i(coarse_x, coarse_y, 19)
	var color: Color = GROUND_COLOR.lerp(GROUND_DETAIL_COLOR, noise * 0.18)
	if _noise_i(x / 6, y / 6, 71) > 0.92:
		color = color.lerp(Color(0.36, 0.27, 0.17, 1.0), 0.10)
	return color

func _top_color_at(
	x: int,
	y: int,
	world_position: Vector2,
	texture_scale: float,
	texture_blend: float,
	macro_scale_px: float,
	macro_strength: float
) -> Color:
	var texture_color: Color = _sample_source_image(_top_image, world_position, texture_scale)
	var macro_noise: float = _value_noise(world_position, macro_scale_px, 313)
	var macro_color: Color = TOP_COLOR.lerp(TOP_LIGHT_COLOR, maxf(0.0, macro_noise - 0.5) * macro_strength)
	macro_color = macro_color.lerp(TOP_DARK_COLOR, maxf(0.0, 0.5 - macro_noise) * macro_strength)
	var color: Color = macro_color.lerp(texture_color, texture_blend)
	if _noise_i(x / 5, y / 5, 131) > 0.94:
		color = color.lerp(TOP_LIGHT_COLOR, 0.20)
	if _noise_i(x / 9, y / 9, 239) < 0.07:
		color = color.lerp(TOP_DARK_COLOR, 0.15)
	return color

func _face_color_at(
	world_position: Vector2,
	depth: float,
	texture_scale: float,
	texture_blend: float,
	face_darkening: float
) -> Color:
	var base: Color = FACE_TOP_COLOR.lerp(FACE_BOTTOM_COLOR, clampf(depth, 0.0, 1.0))
	var texture_color: Color = _sample_source_image(_face_image, world_position, texture_scale)
	return base.lerp(texture_color, texture_blend).lerp(
		FACE_BOTTOM_COLOR,
		depth * face_darkening
	)

func _sample_source_image(image: Image, world_position: Vector2, source_scale: float) -> Color:
	if image == null:
		return Color.WHITE
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return Color.WHITE
	var sample_x: int = posmod(int(floor(world_position.x * source_scale)), width)
	var sample_y: int = posmod(int(floor(world_position.y * source_scale)), height)
	return image.get_pixel(sample_x, sample_y)

func _bottom_outline_alpha(
	face_alpha: PackedFloat32Array,
	width: int,
	height: int,
	x: int,
	y: int,
	index: int,
	outline_strength: float
) -> float:
	var current: float = face_alpha[index]
	if current <= 0.01:
		return 0.0
	var below: float = face_alpha[(y + 1) * width + x] if y + 1 < height else 0.0
	return clampf((current - below) * 2.8, 0.0, outline_strength)

func _blend(base: Color, overlay: Color, alpha: float) -> Color:
	var amount: float = clampf(alpha * overlay.a, 0.0, 1.0)
	return Color(
		lerpf(base.r, overlay.r, amount),
		lerpf(base.g, overlay.g, amount),
		lerpf(base.b, overlay.b, amount),
		1.0
	)

func _grid_vertex_to_world(vertex: Vector2i) -> Vector2:
	return WorldRuntimeConstants.tile_to_world_center(vertex) - Vector2(TILE_SIZE_PX * 0.5, TILE_SIZE_PX * 0.5)

func _samples_per_tile() -> int:
	return maxi(1, roundi(TILE_SIZE_PX / SAMPLE_STEP_PX))

func _facade_samples() -> int:
	return maxi(1, roundi(_preset_float("facade_height_px") / SAMPLE_STEP_PX))

func _blur_radius_samples() -> int:
	return maxi(1, roundi(_preset_float("round_blur_radius_px") / SAMPLE_STEP_PX))

func _top_alpha_at(
	mask_value: float,
	x: int,
	y: int,
	center_value: float,
	half_width: float,
	warp_px: float,
	warp_scale_px: float,
	blur_radius_px: float
) -> float:
	var center: float = center_value
	if warp_px > 0.0:
		var edge_band: float = 1.0 - clampf(absf(mask_value - center) / 0.24, 0.0, 1.0)
		if edge_band > 0.0:
			var world_position := _render_origin_world + Vector2(
				(float(x) + 0.5) * SAMPLE_STEP_PX,
				(float(y) + 0.5) * SAMPLE_STEP_PX
			)
			var noise: float = _value_noise(world_position, warp_scale_px, 907)
			center += (noise - 0.5) * (warp_px / maxf(blur_radius_px, 1.0)) * edge_band
	return smoothstep(center - half_width, center + half_width, mask_value)

func _preset_float(key: String) -> float:
	return float(_preset.get(key, DEFAULT_PRESET.get(key, 0.0)))

func _sanitize_preset(preset: Dictionary) -> Dictionary:
	var result: Dictionary = default_preset()
	for spec: Dictionary in preset_specs():
		var key: String = str(spec.get("key", ""))
		if key.is_empty():
			continue
		if not preset.has(key):
			continue
		result[key] = snappedf(
			clampf(float(preset[key]), float(spec["min"]), float(spec["max"])),
			float(spec["step"])
		)
	return result

func _value_noise(world_position: Vector2, scale_px: float, salt: int) -> float:
	var scale: float = maxf(scale_px, 1.0)
	var gx: int = floori(world_position.x / scale)
	var gy: int = floori(world_position.y / scale)
	var tx: float = smoothstep(0.0, 1.0, fposmod(world_position.x, scale) / scale)
	var ty: float = smoothstep(0.0, 1.0, fposmod(world_position.y, scale) / scale)
	var a: float = _noise_i(gx, gy, salt)
	var b: float = _noise_i(gx + 1, gy, salt)
	var c: float = _noise_i(gx, gy + 1, salt)
	var d: float = _noise_i(gx + 1, gy + 1, salt)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

func _noise_i(x: int, y: int, salt: int) -> float:
	var value: int = x * 92837111 + y * 689287499 + salt * 283923481
	value = posmod(value * 1103515245 + 12345, 100000)
	return float(value) / 99999.0

func _is_mountain_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED
