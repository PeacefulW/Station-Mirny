class_name TerrainVisualV2Runtime
extends RefCounted

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const TerrainVisualPacketBackend = preload(
	"res://core/systems/world/terrain_visual_packet_backend.gd"
)
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const RUNTIME_ENABLED_SETTING := "station_mirny/terrain_visual/v2_chunk_runtime_enabled"

var _packet_backend: TerrainVisualPacketBackend = TerrainVisualPacketBackend.new()
var _pending_full_queue: Array[Vector2i] = []
var _pending_patch_queue: Array[Vector2i] = []
var _owner_node: Node = null
var _chunk_views: Dictionary = { }
var _chunk_packets: Dictionary = { }
var _canonicalize_chunk: Callable = Callable()
var _build_solid_halo: Callable = Callable()
var _did_warn_default_biome_fallback: bool = false
var _did_warn_missing_recipe: bool = false


func configure_context(
		owner_node: Node,
		chunk_views: Dictionary,
		chunk_packets: Dictionary,
		canonicalize_chunk: Callable,
		build_solid_halo: Callable,
) -> void:
	_owner_node = owner_node
	_chunk_views = chunk_views
	_chunk_packets = chunk_packets
	_canonicalize_chunk = canonicalize_chunk
	_build_solid_halo = build_solid_halo


func start() -> void:
	_packet_backend.start()


func stop() -> void:
	_packet_backend.stop()


func clear_queued_work() -> void:
	_packet_backend.clear_queued_work()
	_pending_full_queue.clear()
	_pending_patch_queue.clear()


func erase_chunk(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_pending_full_queue.erase(chunk_coord)
	_pending_patch_queue.erase(chunk_coord)


func has_pending_work() -> bool:
	if not _pending_full_queue.is_empty() or not _pending_patch_queue.is_empty():
		return true
	return _packet_backend.has_pending_requests()


func tick(world_wrap_width_tiles: int) -> bool:
	if _pending_patch_queue.is_empty() and _pending_full_queue.is_empty():
		return false
	if not _pending_patch_queue.is_empty():
		return _advance_patch_apply(world_wrap_width_tiles)
	return _advance_full_apply(world_wrap_width_tiles)


func configure_chunk(
		chunk_view: ChunkView,
		chunk_coord: Vector2i,
		packet: Dictionary,
		world_wrap_width_tiles: int,
) -> void:
	var enabled := is_enabled()
	chunk_view.set_terrain_visual_v2_enabled(enabled)
	chunk_view.set_terrain_visual_packet_backend(_packet_backend)
	if not enabled:
		chunk_view.set_terrain_visual_recipe(null)
		chunk_view.set_terrain_visual_solid_halo(PackedByteArray())
		chunk_view.set_terrain_visual_world_wrap_width_tiles(0)
		return
	chunk_view.set_terrain_visual_recipe(resolve_chunk_rock_visual_recipe(chunk_coord, packet))
	chunk_view.set_terrain_visual_solid_halo(_make_solid_halo(chunk_coord))
	chunk_view.set_terrain_visual_world_wrap_width_tiles(world_wrap_width_tiles)


func queue_full_refresh(chunk_coord: Vector2i) -> void:
	if not is_enabled():
		return
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _chunk_views.has(chunk_coord) or not _chunk_packets.has(chunk_coord):
		return
	if _pending_full_queue.has(chunk_coord):
		return
	_pending_full_queue.append(chunk_coord)


func queue_patch_apply(chunk_coord: Vector2i) -> void:
	if not is_enabled():
		return
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _chunk_views.has(chunk_coord) or not _chunk_packets.has(chunk_coord):
		return
	if _pending_patch_queue.has(chunk_coord):
		return
	_pending_patch_queue.append(chunk_coord)


func queue_full_refreshes_around_chunk(center_chunk_coord: Vector2i) -> void:
	if not is_enabled():
		return
	for y: int in range(center_chunk_coord.y - 1, center_chunk_coord.y + 2):
		for x: int in range(center_chunk_coord.x - 1, center_chunk_coord.x + 2):
			queue_full_refresh(Vector2i(x, y))


func packet_has_v2_mountain_surface(packet: Dictionary) -> bool:
	var mountain_ids: PackedInt32Array = packet.get(
		"mountain_id_per_tile",
		PackedInt32Array(),
	) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get(
		"mountain_flags",
		PackedByteArray(),
	) as PackedByteArray
	var surface_flags := (
		WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
	)
	var count := mini(mountain_ids.size(), mountain_flags.size())
	for index: int in range(count):
		if int(mountain_ids[index]) <= 0:
			continue
		var flags := int(mountain_flags[index])
		if (flags & surface_flags) != 0:
			return true
	return false


func is_enabled() -> bool:
	return bool(ProjectSettings.get_setting(RUNTIME_ENABLED_SETTING, true))


func resolve_chunk_rock_visual_recipe(chunk_coord: Vector2i, packet: Dictionary) -> Resource:
	var biome: Object = _resolve_packet_biome(packet)
	if biome == null:
		if not _did_warn_default_biome_fallback:
			push_warning(
				"Terrain visual V2 chunk %s has no biome_id; using default biome recipe fallback."
				% [chunk_coord],
			)
			_did_warn_default_biome_fallback = true
		biome = _get_default_biome_for_visuals()
	if biome == null:
		return null
	var recipe: Resource = biome.get("rock_visual_recipe") as Resource
	if recipe == null and not _did_warn_missing_recipe:
		push_warning("Terrain visual V2 biome %s has no rock_visual_recipe." % [biome.get("id")])
		_did_warn_missing_recipe = true
	return recipe


func _advance_patch_apply(world_wrap_width_tiles: int) -> bool:
	var chunk_coord: Vector2i = _pending_patch_queue.pop_front()
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if chunk_view == null or packet.is_empty() or not is_enabled():
		return _has_queued_work()
	configure_chunk(chunk_view, chunk_coord, packet, world_wrap_width_tiles)
	var patch_started_usec := WorldPerfProbe.begin()
	var has_more_patch_work := chunk_view.apply_pending_terrain_visual_v2_patch()
	WorldPerfProbe.end("WorldStreamer.terrain_visual_v2.patch_apply", patch_started_usec)
	if has_more_patch_work and not _pending_patch_queue.has(chunk_coord):
		_pending_patch_queue.append(chunk_coord)
	return _has_queued_work()


func _advance_full_apply(world_wrap_width_tiles: int) -> bool:
	var chunk_coord: Vector2i = _pending_full_queue.pop_front()
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if chunk_view == null or packet.is_empty() or not is_enabled():
		return _has_queued_work()
	if not packet_has_v2_mountain_surface(packet):
		return _has_queued_work()

	configure_chunk(chunk_view, chunk_coord, packet, world_wrap_width_tiles)
	var started_usec := WorldPerfProbe.begin()
	var has_more_visual_work := chunk_view.apply_pending_terrain_visual_v2_full()
	WorldPerfProbe.end("WorldStreamer.terrain_visual_v2.full_apply", started_usec)
	if has_more_visual_work and not _pending_full_queue.has(chunk_coord):
		_pending_full_queue.append(chunk_coord)
	return _has_queued_work()


func _has_queued_work() -> bool:
	return not _pending_patch_queue.is_empty() or not _pending_full_queue.is_empty()


func _canonicalize_chunk_coord(chunk_coord: Vector2i) -> Vector2i:
	if not _canonicalize_chunk.is_valid():
		return chunk_coord
	var chunk_variant: Variant = _canonicalize_chunk.call(chunk_coord)
	if chunk_variant is Vector2i:
		return chunk_variant as Vector2i
	return chunk_coord


func _make_solid_halo(chunk_coord: Vector2i) -> PackedByteArray:
	if not _build_solid_halo.is_valid():
		return PackedByteArray()
	var halo_variant: Variant = _build_solid_halo.call(chunk_coord)
	if halo_variant is PackedByteArray:
		return halo_variant as PackedByteArray
	return PackedByteArray()


func _resolve_packet_biome(packet: Dictionary) -> Object:
	var biome_id: StringName = _packet_biome_id(packet)
	if biome_id == &"":
		return null
	var registry: Node = _get_biome_registry()
	if registry == null:
		return null
	if registry.has_method("get_biome"):
		var biome: Object = registry.call("get_biome", biome_id) as Object
		if biome != null:
			return biome
	if registry.has_method("get_biome_by_short_id"):
		return registry.call("get_biome_by_short_id", biome_id) as Object
	return null


func _packet_biome_id(packet: Dictionary) -> StringName:
	var biome_id: Variant = packet.get("biome_id", &"")
	if biome_id is StringName:
		return biome_id
	if biome_id is String:
		return StringName(biome_id)
	return &""


func _get_default_biome_for_visuals() -> Object:
	var registry: Node = _get_biome_registry()
	if registry == null or not registry.has_method("get_default_biome"):
		return null
	return registry.call("get_default_biome") as Object


func _get_biome_registry() -> Node:
	if _owner_node == null or not is_instance_valid(_owner_node):
		return null
	return _owner_node.get_node_or_null("/root/BiomeRegistry")
