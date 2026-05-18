class_name ChunkVisualBridge
extends RefCounted

const TerrainVisualRuntimePresenter = preload(
	"res://core/systems/world/terrain_visual_runtime_presenter.gd"
)
const TerrainVisualPacketBackend = preload(
	"res://core/systems/world/terrain_visual_packet_backend.gd"
)

var _owner: Node = null
var _presenter: TerrainVisualRuntimePresenter = null
var _packet_backend: TerrainVisualPacketBackend = null
var _solid_halo: PackedByteArray = PackedByteArray()


func configure(owner: Node) -> void:
	_owner = owner


func clear() -> void:
	if _presenter != null and is_instance_valid(_presenter):
		_presenter.clear()


func is_enabled() -> bool:
	return _presenter != null and _presenter.is_enabled()


func set_enabled(enabled: bool) -> void:
	var presenter := _ensure_presenter()
	if presenter != null:
		presenter.set_enabled(enabled)


func set_recipe(recipe: Resource) -> void:
	var presenter := _ensure_presenter()
	if presenter != null:
		presenter.set_recipe(recipe)


func set_packet_backend(packet_backend: TerrainVisualPacketBackend) -> void:
	_packet_backend = packet_backend
	if _presenter != null and is_instance_valid(_presenter):
		_presenter.set_packet_backend(_packet_backend)


func set_solid_halo(solid_halo: PackedByteArray) -> void:
	_solid_halo = solid_halo.duplicate()
	if _presenter != null and is_instance_valid(_presenter):
		_presenter.set_chunk_solid_halo(_solid_halo)


func set_world_wrap_width_tiles(width_tiles: int) -> void:
	var presenter := _ensure_presenter()
	if presenter != null:
		presenter.set_world_wrap_width_tiles(width_tiles)


func get_debug_state() -> Dictionary:
	if _presenter != null and is_instance_valid(_presenter):
		return _presenter.get_debug_state()
	return { "enabled": false }


func begin_chunk_apply(packet: Dictionary) -> void:
	if not is_enabled():
		return
	_presenter.begin_chunk_apply(packet)
	_presenter.set_chunk_solid_halo(_solid_halo)


func mark_dirty_patch(local_coord: Vector2i) -> void:
	if is_enabled():
		_presenter.mark_dirty_patch(local_coord)


func apply_dirty_patch(
		chunk_coord: Vector2i,
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
) -> bool:
	if not is_enabled():
		return false
	return _presenter.apply_dirty_patch(chunk_coord, mountain_ids, mountain_flags)


func apply_full_pending(
		chunk_coord: Vector2i,
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
) -> bool:
	if not is_enabled():
		return false
	return _presenter.apply_full_pending(chunk_coord, mountain_ids, mountain_flags)


func _ensure_presenter() -> TerrainVisualRuntimePresenter:
	if _presenter != null and is_instance_valid(_presenter):
		return _presenter
	if _owner == null or not is_instance_valid(_owner):
		push_error("ChunkVisualBridge requires a valid owner before creating V2 presenter.")
		return null
	_presenter = TerrainVisualRuntimePresenter.new()
	_presenter.name = "TerrainVisualV2RuntimePresenter"
	_presenter.set_packet_backend(_packet_backend)
	_owner.add_child(_presenter)
	return _presenter
