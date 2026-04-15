class_name ViewEnvelopeResolver
extends RefCounted

const HOT_RADIUS_CHUNKS: int = 1
const WARM_RADIUS_CHUNKS: int = 2

var _owner: Node = null

func setup(owner: Node) -> void:
	_owner = owner

func resolve(center: Vector2i, player: Node2D, active_z: int) -> Dictionary:
	var canonical_center: Vector2i = _owner._canonical_chunk_coord(center)
	var camera: Camera2D = _resolve_camera(player)
	var debug_camera_center: Vector2i = canonical_center
	var debug_camera_radius: Vector2i = Vector2i.ZERO
	var debug_camera_visible_set: Dictionary = {}
	var debug_camera_source: String = "none"
	if camera != null and WorldGenerator:
		debug_camera_center = WorldGenerator.world_to_chunk(camera.global_position)
		debug_camera_radius = _resolve_camera_visible_radius(camera, player)
		_append_rect(debug_camera_visible_set, debug_camera_center, debug_camera_radius)
		debug_camera_source = "camera_viewport_debug_only"
	var hot_near_set: Dictionary = {}
	_append_rect(hot_near_set, canonical_center, Vector2i(HOT_RADIUS_CHUNKS, HOT_RADIUS_CHUNKS))
	var warm_preload_set: Dictionary = {}
	_append_rect(warm_preload_set, canonical_center, Vector2i(WARM_RADIUS_CHUNKS, WARM_RADIUS_CHUNKS))
	return {
		"active_z": active_z,
		"camera_center": debug_camera_center,
		"camera_visible_set": hot_near_set,
		"camera_margin_set": warm_preload_set,
		"debug_camera_visible_set": debug_camera_visible_set,
		"debug_camera_radius_chunks": debug_camera_radius,
		"debug_camera_source": debug_camera_source,
		"hot_near_set": hot_near_set,
		"warm_preload_set": warm_preload_set,
		"hot_radius_chunks": HOT_RADIUS_CHUNKS,
		"warm_radius_chunks": WARM_RADIUS_CHUNKS,
		"source": "gameplay_fixed_hot_warm",
	}

func _resolve_camera(player: Node2D) -> Camera2D:
	if player == null:
		return null
	var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		return camera
	var viewport_camera: Camera2D = player.get_viewport().get_camera_2d()
	return viewport_camera

func _resolve_camera_visible_radius(camera: Camera2D, player: Node2D) -> Vector2i:
	var chunk_size_px: float = _chunk_size_px()
	if chunk_size_px <= 0.0:
		return Vector2i.ZERO
	var viewport_size: Vector2 = Vector2.ZERO
	if player != null and player.get_viewport() != null:
		viewport_size = player.get_viewport().get_visible_rect().size
	if viewport_size == Vector2.ZERO:
		return Vector2i.ZERO
	var zoom: Vector2 = camera.zoom
	var safe_zoom_x: float = maxf(0.01, absf(zoom.x))
	var safe_zoom_y: float = maxf(0.01, absf(zoom.y))
	var visible_world_size: Vector2 = Vector2(viewport_size.x / safe_zoom_x, viewport_size.y / safe_zoom_y)
	var radius_x: int = ceili((visible_world_size.x * 0.5) / chunk_size_px)
	var radius_y: int = ceili((visible_world_size.y * 0.5) / chunk_size_px)
	return Vector2i(maxi(0, radius_x), maxi(0, radius_y))

func _chunk_size_px() -> float:
	if WorldGenerator and WorldGenerator.balance:
		return float(WorldGenerator.balance.chunk_size_tiles * WorldGenerator.balance.tile_size)
	return 0.0

func _append_rect(target: Dictionary, center: Vector2i, radius: Vector2i) -> void:
	for dx: int in range(-radius.x, radius.x + 1):
		for dy: int in range(-radius.y, radius.y + 1):
			var coord: Vector2i = _owner._offset_chunk_coord(center, Vector2i(dx, dy))
			target[coord] = true
