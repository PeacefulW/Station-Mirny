class_name ViewEnvelopeResolver
extends RefCounted

const CAMERA_MARGIN_CHUNKS: int = 1

var _owner: Node = null

func setup(owner: Node) -> void:
	_owner = owner

func resolve(center: Vector2i, player: Node2D, active_z: int) -> Dictionary:
	var canonical_center: Vector2i = _owner._canonical_chunk_coord(center)
	var camera: Camera2D = _resolve_camera(player)
	var camera_center: Vector2i = canonical_center
	var source: String = "fallback_radius"
	var visible_radius: Vector2i = _fallback_visible_radius()
	if camera != null and WorldGenerator:
		camera_center = WorldGenerator.world_to_chunk(camera.global_position)
		visible_radius = _resolve_camera_visible_radius(camera, player)
		source = "camera_viewport"
	var camera_visible_set: Dictionary = {}
	_append_rect(camera_visible_set, camera_center, visible_radius)
	var camera_margin_set: Dictionary = {}
	_append_rect(
		camera_margin_set,
		camera_center,
		visible_radius + Vector2i(CAMERA_MARGIN_CHUNKS, CAMERA_MARGIN_CHUNKS)
	)
	return {
		"active_z": active_z,
		"camera_center": camera_center,
		"camera_visible_set": camera_visible_set,
		"camera_margin_set": camera_margin_set,
		"visible_radius_chunks": visible_radius,
		"margin_chunks": CAMERA_MARGIN_CHUNKS,
		"source": source,
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
		return _fallback_visible_radius()
	var viewport_size: Vector2 = Vector2.ZERO
	if player != null and player.get_viewport() != null:
		viewport_size = player.get_viewport().get_visible_rect().size
	if viewport_size == Vector2.ZERO:
		return _fallback_visible_radius()
	var zoom: Vector2 = camera.zoom
	var safe_zoom_x: float = maxf(0.01, absf(zoom.x))
	var safe_zoom_y: float = maxf(0.01, absf(zoom.y))
	var visible_world_size: Vector2 = Vector2(viewport_size.x / safe_zoom_x, viewport_size.y / safe_zoom_y)
	var radius_x: int = ceili((visible_world_size.x * 0.5) / chunk_size_px) + CAMERA_MARGIN_CHUNKS
	var radius_y: int = ceili((visible_world_size.y * 0.5) / chunk_size_px) + CAMERA_MARGIN_CHUNKS
	return Vector2i(maxi(1, radius_x), maxi(1, radius_y))

func _fallback_visible_radius() -> Vector2i:
	var radius: int = 1
	if WorldGenerator and WorldGenerator.balance:
		radius = maxi(1, int(WorldGenerator.balance.near_visible_chunk_radius))
	return Vector2i(radius, radius)

func _chunk_size_px() -> float:
	if WorldGenerator and WorldGenerator.balance:
		return float(WorldGenerator.balance.chunk_size_tiles * WorldGenerator.balance.tile_size)
	return 0.0

func _append_rect(target: Dictionary, center: Vector2i, radius: Vector2i) -> void:
	for dx: int in range(-radius.x, radius.x + 1):
		for dy: int in range(-radius.y, radius.y + 1):
			var coord: Vector2i = _owner._offset_chunk_coord(center, Vector2i(dx, dy))
			target[coord] = true
