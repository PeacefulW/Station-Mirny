extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DefaultFoundationGenSettings = preload("res://data/balance/foundation_gen_settings.tres")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const DefaultMountainGenSettings = preload("res://data/balance/mountain_gen_settings.tres")

const OBJECT_KIND_ROCK: int = 1
const OBJECT_KIND_LIVING_FLORA: int = 2
const OBJECT_KIND_SPIKY_FLORA: int = 3
const ROCK_ATLAS_RARE_FORMATION: int = 3
const SPIKY_FLORA_ATLAS_BROWN_SEAWEED: int = 1
const OBJECT_FIELD_NAMES: Array[String] = [
	"object_kind",
	"object_local_x_px_q4",
	"object_local_y_px_q4",
	"object_size_px",
	"object_atlas_index",
	"object_variant",
	"object_flags",
	"object_tint",
	"object_phase",
]

var _failed: bool = false

func _init() -> void:
	var packet: Dictionary = _find_native_packet_with_objects()
	if not packet.is_empty():
		_assert_packet_arrays(packet)
		_assert_packet_layer_consumes_packet(packet)

	if _failed:
		quit(1)
		return
	print("WORLD_OBJECT_PACKET_LAYER_SMOKE OK")
	quit(0)

func _find_native_packet_with_objects() -> Dictionary:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for native object packet checks.")
	if world_core == null:
		return {}

	var coords := PackedVector2Array()
	var center_chunk := Vector2i(128, 64)
	for y_offset: int in range(64):
		for x_offset: int in range(64):
			coords.append(Vector2(center_chunk.x + x_offset, center_chunk.y + y_offset))

	var packets_variant: Variant = world_core.call(
		"generate_chunk_packets_batch",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed()
	)
	_assert(packets_variant is Array, "WorldCore must return an Array for object packet smoke.")
	if not (packets_variant is Array):
		return {}

	var packets: Array = packets_variant as Array
	var best_packet: Dictionary = {}
	var best_object_count: int = 0
	var best_rock_count: int = 0
	var best_spiky_count: int = 0
	var best_living_count: int = 0
	var best_brown_seaweed_count: int = 0
	var best_rare_rock_formation_count: int = 0
	for packet_variant: Variant in packets:
		var packet: Dictionary = packet_variant as Dictionary
		var object_kind: PackedByteArray = packet.get("object_kind", PackedByteArray()) as PackedByteArray
		var object_atlas: PackedByteArray = packet.get("object_atlas_index", PackedByteArray()) as PackedByteArray
		var rock_count: int = _count_kind(object_kind, OBJECT_KIND_ROCK)
		var spiky_count: int = _count_kind(object_kind, OBJECT_KIND_SPIKY_FLORA)
		var living_count: int = _count_kind(object_kind, OBJECT_KIND_LIVING_FLORA)
		var brown_seaweed_count: int = _count_kind_atlas(object_kind, object_atlas, OBJECT_KIND_SPIKY_FLORA, SPIKY_FLORA_ATLAS_BROWN_SEAWEED)
		var rare_rock_formation_count: int = _count_kind_atlas(object_kind, object_atlas, OBJECT_KIND_ROCK, ROCK_ATLAS_RARE_FORMATION)
		if object_kind.size() > best_object_count:
			best_packet = packet
			best_object_count = object_kind.size()
			best_rock_count = rock_count
			best_spiky_count = spiky_count
			best_living_count = living_count
			best_brown_seaweed_count = brown_seaweed_count
			best_rare_rock_formation_count = rare_rock_formation_count
		if rock_count > 0 and spiky_count > 0 and brown_seaweed_count > 0 and rare_rock_formation_count > 0:
			best_packet = packet
			best_object_count = object_kind.size()
			best_rock_count = rock_count
			best_spiky_count = spiky_count
			best_living_count = living_count
			best_brown_seaweed_count = brown_seaweed_count
			best_rare_rock_formation_count = rare_rock_formation_count
			break

	_assert(best_object_count > 0, "Native object packet scan produced no objects.")
	_assert(best_rock_count > 0, "Native object packet scan produced no rock objects.")
	_assert(best_spiky_count > 0, "Native object packet scan produced no spiky flora objects.")
	_assert(best_brown_seaweed_count > 0, "Native object packet scan produced no brown seaweed biofield flora objects.")
	_assert(best_rare_rock_formation_count > 0, "Native object packet scan produced no rare rock formation objects.")
	print(
		"WORLD_OBJECT_PACKET_NATIVE objects=%d rocks=%d living=%d spiky=%d brown_seaweed=%d rare_rock_formation=%d" %
		[best_object_count, best_rock_count, best_living_count, best_spiky_count, best_brown_seaweed_count, best_rare_rock_formation_count]
	)
	return best_packet

func _assert_packet_arrays(packet: Dictionary) -> void:
	var expected_count: int = -1
	for field_name: String in OBJECT_FIELD_NAMES:
		var field: PackedByteArray = packet.get(field_name, PackedByteArray()) as PackedByteArray
		_assert(field.size() > 0, "%s must be present in the native object packet." % field_name)
		if expected_count < 0:
			expected_count = field.size()
		_assert(
			field.size() == expected_count,
			"%s must match the object packet record count." % field_name
		)

	var object_size: PackedByteArray = packet.get("object_size_px", PackedByteArray()) as PackedByteArray
	for size_byte: int in object_size:
		_assert(size_byte > 0, "object_size_px entries must be positive.")

func _assert_packet_layer_consumes_packet(packet: Dictionary) -> void:
	var layer := WorldObjectPacketLayer.new()
	root.add_child(layer)
	layer.set_rock_atlases([_make_texture(2048, 512), _make_texture(2048, 512), _make_texture(2048, 512), _make_texture(2048, 512)])
	layer.set_living_flora_atlas(_make_texture(4096, 1024))
	layer.set_spiky_flora_atlases([_make_texture(2048, 512), _make_texture(2048, 512)])
	layer.configure_packet(packet)
	layer.set_sun_lighting(234.0, 96.0, 0.55, 18.0)

	var state: Dictionary = layer.get_debug_state()
	_assert(int(state.get("rock_count", 0)) > 0, "WorldObjectPacketLayer must render rock packet records.")
	_assert(int(state.get("spiky_flora_count", 0)) > 0, "WorldObjectPacketLayer must render spiky flora packet records.")
	_assert(int(state.get("collider_count", 0)) >= 0, "WorldObjectPacketLayer collider debug count must be readable.")
	print("WORLD_OBJECT_PACKET_LAYER_STATE ", state)
	layer.free()

func _build_settings_packed() -> PackedFloat32Array:
	var world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var mountain_settings: MountainGenSettings = MountainGenSettings.from_save_dict(DefaultMountainGenSettings.to_save_dict())
	mountain_settings.density = 0.0
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.from_save_dict(
		DefaultFoundationGenSettings.to_save_dict(),
		world_bounds
	)
	var lake_settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lake_settings.density = 0.0
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, world_bounds)
	return lake_settings.write_to_settings_packed(packed)

func _make_texture(width: int, height: int) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)

func _count_kind(object_kind: PackedByteArray, kind: int) -> int:
	var count: int = 0
	for value: int in object_kind:
		if value == kind:
			count += 1
	return count

func _count_kind_atlas(object_kind: PackedByteArray, object_atlas: PackedByteArray, kind: int, atlas_index: int) -> int:
	var count: int = 0
	var object_count: int = mini(object_kind.size(), object_atlas.size())
	for index: int in range(object_count):
		if int(object_kind[index]) == kind and int(object_atlas[index]) == atlas_index:
			count += 1
	return count

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
