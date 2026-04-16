class_name ChunkTopologyService
extends RefCounted

const TOPOLOGY_REBUILD_IDLE_DEBOUNCE_USEC: int = 750000

var _owner: Node = null
var _native_builder_class_name: StringName = &""
var _native_builder: RefCounted = null
var _native_builder_available: bool = false
var _native_builder_active: bool = false
var _native_topology_dirty: bool = false
var _native_topology_dirty_since_usec: int = 0

func setup(owner: Node, native_builder_class_name: StringName) -> void:
	_owner = owner
	_native_builder_class_name = native_builder_class_name

func set_validated_native_builder(native_builder: RefCounted) -> void:
	_native_builder = native_builder
	_native_builder_available = native_builder != null
	_native_builder_active = false
	_native_topology_dirty = false

func clear_runtime_state() -> void:
	_native_topology_dirty = false
	_native_builder_active = false
	_native_topology_dirty_since_usec = 0
	if _native_builder != null and _native_builder.has_method("clear"):
		_native_builder.call("clear")

func deactivate() -> void:
	_native_topology_dirty = false
	_native_builder_active = false
	_native_topology_dirty_since_usec = 0

func is_available() -> bool:
	return _native_builder_available

func is_native_enabled() -> bool:
	return _native_builder_active and _native_builder != null

func is_dirty() -> bool:
	return _native_topology_dirty

func setup_native_builder() -> void:
	_native_topology_dirty = false
	_native_topology_dirty_since_usec = 0
	_native_builder_active = _native_builder_available and _native_builder != null
	if not _native_builder_active:
		push_error(
			"Chunk runtime requires %s for surface topology rebuild. Build or load the world GDExtension before running the game." % [
				String(_native_builder_class_name)
			]
		)
		return
	_native_builder.call("clear")

func is_topology_ready(active_z: int) -> bool:
	if active_z != 0:
		return false
	return is_native_enabled() and not _native_topology_dirty

func get_mountain_key_at_tile(active_z: int, tile_pos: Vector2i) -> Vector2i:
	if active_z != 0:
		return Vector2i(999999, 999999)
	if is_native_enabled():
		return _native_builder.call("get_mountain_key_at_tile", tile_pos) as Vector2i
	push_error("Chunk runtime requires active native topology before get_mountain_key_at_tile().")
	return Vector2i(999999, 999999)

func get_mountain_tiles(active_z: int, mountain_key: Vector2i) -> Dictionary:
	if active_z != 0:
		return {}
	if is_native_enabled():
		return _native_builder.call("get_mountain_tiles", mountain_key) as Dictionary
	push_error("Chunk runtime requires active native topology before get_mountain_tiles().")
	return {}

func get_mountain_open_tiles(active_z: int, mountain_key: Vector2i) -> Dictionary:
	if active_z != 0:
		return {}
	if is_native_enabled():
		return _native_builder.call("get_mountain_open_tiles", mountain_key) as Dictionary
	push_error("Chunk runtime requires active native topology before get_mountain_open_tiles().")
	return {}

func tick(active_z: int, streaming_generation_idle: bool) -> bool:
	if active_z != 0:
		return false
	if is_native_enabled():
		if _native_topology_dirty:
			if not streaming_generation_idle:
				return true
			if _owner != null \
				and _owner.has_method("_has_player_visible_visual_pressure") \
				and bool(_owner._has_player_visible_visual_pressure()):
				return true
			if _native_topology_dirty_since_usec > 0 \
				and Time.get_ticks_usec() - _native_topology_dirty_since_usec < TOPOLOGY_REBUILD_IDLE_DEBOUNCE_USEC:
				return true
			_native_builder.call("ensure_built")
			_native_topology_dirty = false
			_native_topology_dirty_since_usec = 0
		return false
	push_error("Chunk runtime requires active native topology before topology tick.")
	return false

func install_surface_chunk(coord: Vector2i, chunk: Chunk) -> void:
	if not is_native_enabled():
		push_error("Chunk runtime requires active native topology before installing surface chunk %s." % [coord])
		return
	_native_builder.call("set_chunk", coord, chunk.get_terrain_bytes(), WorldGenerator.balance.chunk_size_tiles)
	_native_topology_dirty = true
	_native_topology_dirty_since_usec = Time.get_ticks_usec()

func remove_surface_chunk(coord: Vector2i) -> void:
	if not is_native_enabled():
		push_error("Chunk runtime requires active native topology before unloading surface chunk %s." % [coord])
		return
	_native_builder.call("remove_chunk", coord)
	_native_topology_dirty = true
	_native_topology_dirty_since_usec = Time.get_ticks_usec()

func note_mountain_tile_changed(active_z: int, tile_pos: Vector2i, old_type: int, new_type: int) -> void:
	if active_z != 0:
		return
	var old_is_mountain: bool = _is_mountain_topology_tile(old_type)
	var new_is_mountain: bool = _is_mountain_topology_tile(new_type)
	if not (old_is_mountain or new_is_mountain):
		return
	var started_usec: int = WorldPerfProbe.begin()
	if is_native_enabled():
		_native_builder.call("update_tile", tile_pos, new_type)
		_native_topology_dirty_since_usec = Time.get_ticks_usec()
		WorldPerfProbe.end("ChunkManager._on_mountain_tile_changed", started_usec)
		return
	push_error("Chunk runtime requires active native topology before mountain tile mutation %s." % [tile_pos])
	WorldPerfProbe.end("ChunkManager._on_mountain_tile_changed", started_usec)

func _is_mountain_topology_tile(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.ROCK \
		or terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE
