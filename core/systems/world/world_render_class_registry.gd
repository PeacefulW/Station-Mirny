class_name WorldRenderClassRegistry
extends RefCounted
## Boot-only data registry for the fixed world-render passes.
##
## A descriptor selects packed sprite channels and metadata. A source binding
## tells the native packer where an already-produced family buffer lives. Both
## are authored data: neither the renderer nor WorldCore names content families.

const DEFAULT_REGISTRY_PATH: String = "res://data/world_render/render_class_registry.json"
const WorldVisualLightingProfile = preload(
	"res://core/systems/world/world_visual_lighting_profile.gd"
)

const PASS_GROUND: int = 1
const PASS_BODY: int = 2
const PASS_SHADOW: int = 4
const PASS_EMISSIVE: int = 8
const PASS_OVERHEAD: int = 16

const FLAG_LAYERED: int = 1
const FLAG_SEASONAL_SIMPLE: int = 2
const FLAG_ACTOR: int = 4
const FLAG_WIND: int = 8
const FLAG_CUTOUT: int = 16
const FLAG_GROUND: int = 32

const DESCRIPTOR_LUT_ROWS: int = 5
const MAX_SHADER_DESCRIPTORS: int = 64
const MAX_SHADER_VARIANTS: int = 256

var _ready: bool = false
var _registry_path: String = ""
var _manifest: Dictionary = { }
var _descriptor_capacity: int = MAX_SHADER_DESCRIPTORS
var _descriptors: Array[Dictionary] = []
var _source_bindings: Array[Dictionary] = []
var _actor_descriptor_ids := PackedInt32Array()
var _textures: Dictionary = { }
var _descriptor_lut: Texture2D = null
var _variant_crop_lut: Texture2D = null
var _variant_anchor_lut: Texture2D = null


func configure(
		registry_path: String = DEFAULT_REGISTRY_PATH,
		load_texture_assets: bool = true,
) -> bool:
	_ready = false
	_registry_path = registry_path
	_descriptor_capacity = MAX_SHADER_DESCRIPTORS
	_manifest.clear()
	_descriptors.clear()
	_source_bindings.clear()
	_actor_descriptor_ids = PackedInt32Array()
	_textures.clear()
	_descriptor_lut = null
	_variant_crop_lut = null
	_variant_anchor_lut = null
	if not FileAccess.file_exists(registry_path):
		push_error("WorldRenderClassRegistry: missing %s" % registry_path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	if not parsed is Dictionary:
		push_error("WorldRenderClassRegistry: invalid JSON %s" % registry_path)
		return false
	_manifest = parsed as Dictionary
	if not _parse_descriptors() or not _parse_source_bindings():
		return false
	if load_texture_assets and not _load_textures():
		return false
	if not _build_metadata_luts():
		return false
	_ready = true
	return true


func is_ready() -> bool:
	return _ready


func get_registry_path() -> String:
	return _registry_path


func get_native_source_bindings() -> Array:
	return _source_bindings.duplicate(true)


func get_descriptor_lut() -> Texture2D:
	return _descriptor_lut


func get_variant_crop_lut() -> Texture2D:
	return _variant_crop_lut


func get_variant_anchor_lut() -> Texture2D:
	return _variant_anchor_lut


func get_texture(id: StringName) -> Texture2D:
	return _textures.get(id) as Texture2D


func get_descriptor_count() -> int:
	return _descriptors.size()


## LUT width the descriptor rows were built at. Every render material must be
## told this value, or `descriptor_id` resolves to the wrong LUT column.
func get_descriptor_capacity() -> int:
	return _descriptor_capacity


func get_source_binding_count() -> int:
	return _source_bindings.size()


func get_actor_descriptor_id(local_sprite_id: int) -> int:
	if local_sprite_id < 0 or local_sprite_id >= _actor_descriptor_ids.size():
		return -1
	return _actor_descriptor_ids[local_sprite_id]


func get_pass_count() -> int:
	return (_manifest.get("passes", []) as Array).size()


func get_hard_bounds() -> Dictionary:
	return (_manifest.get("hard_bounds", { }) as Dictionary).duplicate(true)


func describe_descriptor_counts(counts: PackedInt32Array) -> Dictionary:
	var described: Dictionary = { }
	for descriptor: Dictionary in _descriptors:
		var descriptor_id: int = int(descriptor.get("descriptor_id", -1))
		if descriptor_id < 0:
			continue
		described[str(descriptor.get("id", descriptor_id))] = \
				counts[descriptor_id] if descriptor_id < counts.size() else 0
	return described


func get_debug_contract() -> Dictionary:
	return {
		"registry_path": _registry_path,
		"descriptor_count": _descriptors.size(),
		"source_binding_count": _source_bindings.size(),
		"actor_descriptor_count": _actor_descriptor_ids.size(),
		"fixed_pass_count": get_pass_count(),
		"hard_bounds": get_hard_bounds(),
	}


func _parse_descriptors() -> bool:
	var descriptors_value: Variant = _manifest.get("descriptors", null)
	if not descriptors_value is Array:
		push_error("WorldRenderClassRegistry: descriptors must be an Array")
		return false
	# Single resolution point: descriptor-id validation, LUT width and the shader
	# uniform must all agree, otherwise descriptor lookups sample the wrong column.
	var capacity: int = int(_manifest.get("descriptor_capacity", MAX_SHADER_DESCRIPTORS))
	if capacity < 1 or capacity > MAX_SHADER_DESCRIPTORS:
		push_error("WorldRenderClassRegistry: descriptor capacity exceeds shader bound")
		return false
	_descriptor_capacity = capacity
	var seen: Dictionary = { }
	var actor_by_id: Dictionary = { }
	for descriptor_value: Variant in descriptors_value as Array:
		if not descriptor_value is Dictionary:
			return false
		var descriptor: Dictionary = (descriptor_value as Dictionary).duplicate(true)
		var descriptor_id: int = int(descriptor.get("descriptor_id", -1))
		var layout: Array = descriptor.get("atlas_layout", []) as Array
		var crops: Array = descriptor.get("render_crops", []) as Array
		var anchors: Array = descriptor.get("anchors", []) as Array
		if descriptor_id < 0 or descriptor_id >= capacity or seen.has(descriptor_id) \
				or layout.size() != 3 or crops.is_empty() \
				or crops.size() > MAX_SHADER_VARIANTS or anchors.size() != crops.size():
			push_error("WorldRenderClassRegistry: invalid descriptor %s" % descriptor.get("id", "?"))
			return false
		if int(layout[0]) < 1 or int(layout[1]) < 1 or int(layout[2]) < 1 \
				or int(layout[2]) > MAX_SHADER_VARIANTS:
			return false
		seen[descriptor_id] = true
		_descriptors.append(descriptor)
		if int(descriptor.get("flags", 0)) & FLAG_ACTOR:
			actor_by_id[descriptor_id] = descriptor_id
	_descriptors.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("descriptor_id", -1)) < int(right.get("descriptor_id", -1))
	)
	var actor_ids: Array = actor_by_id.keys()
	actor_ids.sort()
	for actor_id: Variant in actor_ids:
		_actor_descriptor_ids.append(int(actor_id))
	return not _descriptors.is_empty()


func _parse_source_bindings() -> bool:
	var bindings_value: Variant = _manifest.get("source_bindings", null)
	if not bindings_value is Array:
		push_error("WorldRenderClassRegistry: source_bindings must be an Array")
		return false
	var descriptors_by_id: Dictionary = { }
	for descriptor: Dictionary in _descriptors:
		descriptors_by_id[int(descriptor.get("descriptor_id", -1))] = descriptor
	for binding_value: Variant in bindings_value as Array:
		if not binding_value is Dictionary:
			return false
		var authored: Dictionary = binding_value as Dictionary
		var descriptor_id: int = int(authored.get("descriptor_id", -1))
		var result_set: String = str(authored.get("result_set", ""))
		var geometry: String = str(authored.get("geometry", ""))
		var metrics: PackedFloat32Array = _packed_float_array(authored.get("metrics", []))
		var crops: PackedFloat32Array = _flatten_vec4_table(authored.get("render_crops", []))
		var shadow_crop: PackedFloat32Array = _packed_float_array(
			authored.get("shadow_source_crop", []),
		)
		var shadow_crops: PackedFloat32Array = _flatten_vec4_table(
			authored.get("shadow_source_crops", []),
		)
		if shadow_crops.is_empty() and shadow_crop.size() == 4:
			shadow_crops.resize(crops.size())
			for index: int in range(crops.size()):
				shadow_crops[index] = shadow_crop[index % 4]
		var compact_ground_shadow_rects: PackedFloat32Array = _flatten_vec4_table(
			authored.get("compact_ground_shadow_rects", []),
		)
		var metric_stride: int = int(authored.get("metric_stride", 0))
		if not descriptors_by_id.has(descriptor_id) or not result_set in ["objects", "grass"] \
				or not geometry in ["anchored", "south_edge"] \
				or str(authored.get("buffer_key", "")).is_empty() \
				or metric_stride < 5 or crops.size() < 4 or crops.size() % 4 != 0 \
				or shadow_crop.size() != 4 or shadow_crops.size() != crops.size() \
				or (geometry == "south_edge" \
						and compact_ground_shadow_rects.size() != crops.size()) \
				or (geometry == "anchored" and metrics.size() % metric_stride != 0):
			push_error("WorldRenderClassRegistry: invalid source binding %s" % authored.get("id", "?"))
			return false
		var descriptor: Dictionary = descriptors_by_id[descriptor_id] as Dictionary
		var pass_mask: int = int(descriptor.get("passes", 0))
		if geometry == "anchored" and (pass_mask & PASS_SHADOW) != 0:
			var shadow_frame_size: Array = descriptor.get(
				"shadow_frame_size_px", descriptor.get("frame_size_px", []),
			) as Array
			if shadow_frame_size.size() != 2 \
					or float(shadow_frame_size[0]) <= 0.0 or float(shadow_frame_size[1]) <= 0.0:
				return false
			var frame_size: Vector2 = Vector2(
				float(shadow_frame_size[0]), float(shadow_frame_size[1]),
			)
			shadow_crop = _pad_shadow_source_crops(shadow_crop, frame_size)
			shadow_crops = _pad_shadow_source_crops(shadow_crops, frame_size)
		_source_bindings.append({
			"id": str(authored.get("id", "")),
			"descriptor_id": descriptor_id,
			"passes": pass_mask,
			"result_set": 0 if result_set == "objects" else 1,
			"buffer_key": StringName(str(authored.get("buffer_key", ""))),
			"geometry": 0 if geometry == "anchored" else 1,
			"semantic_layer": int(authored.get("semantic_layer", 10)),
			"metric_stride": metric_stride,
			"metrics": metrics,
			"render_crops": crops,
			"shadow_source_crop": shadow_crop,
			"shadow_source_crops": shadow_crops,
			"compact_ground_shadow_rects": compact_ground_shadow_rects,
			"lod_scaled": bool(authored.get("lod_scaled", false)),
			"shadow_lod_scaled": bool(authored.get("shadow_lod_scaled", false)),
			"shadow_lod_start_fraction": clampf(
				float(authored.get("shadow_lod_start_fraction", 0.0)),
				0.0,
				0.99,
			),
		})
	return not _source_bindings.is_empty()


static func _pad_shadow_source_crops(
		crops: PackedFloat32Array,
		shadow_frame_size: Vector2,
) -> PackedFloat32Array:
	# The maximum transverse filter tap and its bilinear footprint must fit
	# inside the source quad before native projection stretches its shadow.
	var radius: float = WorldVisualLightingProfile.MAX_OBJECT_SHADOW_SOFTNESS_TEXELS \
			+ WorldVisualLightingProfile.OBJECT_SHADOW_BILINEAR_GUARD_TEXELS
	var padding: Vector2 = Vector2.ONE * radius / shadow_frame_size
	var padded: PackedFloat32Array = crops.duplicate()
	for offset: int in range(0, padded.size(), 4):
		var right: float = minf(1.0, padded[offset] + padded[offset + 2] + padding.x)
		var bottom: float = minf(1.0, padded[offset + 1] + padded[offset + 3] + padding.y)
		padded[offset] = maxf(0.0, padded[offset] - padding.x)
		padded[offset + 1] = maxf(0.0, padded[offset + 1] - padding.y)
		padded[offset + 2] = right - padded[offset]
		padded[offset + 3] = bottom - padded[offset + 1]
	return padded


func _load_textures() -> bool:
	var atlas_value: Variant = _manifest.get("atlases", null)
	if not atlas_value is Dictionary:
		return false
	var atlases: Dictionary = atlas_value as Dictionary
	for id: StringName in [
		&"body_base", &"foliage", &"snow_overlay", &"wind_mask",
		&"snow_mask", &"season_mask", &"shadow", &"emissive", &"overhead",
		&"actor_body", &"actor_shadow",
	]:
		var path: String = str(atlases.get(id, ""))
		if path.is_empty():
			if id in [&"actor_body", &"actor_shadow"]:
				continue
			return false
		var resource: Resource = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE)
		if not resource is Texture2D:
			push_error("WorldRenderClassRegistry: could not load %s" % path)
			return false
		_textures[id] = resource as Texture2D
	return true


func _build_metadata_luts() -> bool:
	var descriptor_capacity: int = _descriptor_capacity
	var descriptor_image := Image.create_empty(
		descriptor_capacity,
		DESCRIPTOR_LUT_ROWS,
		false,
		Image.FORMAT_RGBAF,
	)
	var crop_image := Image.create_empty(
		MAX_SHADER_VARIANTS,
		descriptor_capacity,
		false,
		Image.FORMAT_RGBAF,
	)
	var anchor_image := Image.create_empty(
		MAX_SHADER_VARIANTS,
		descriptor_capacity,
		false,
		Image.FORMAT_RGF,
	)
	for y: int in range(descriptor_capacity):
		for x: int in range(MAX_SHADER_VARIANTS):
			crop_image.set_pixel(x, y, Color(0.0, 0.0, 1.0, 1.0))
			anchor_image.set_pixel(x, y, Color(0.5, 0.5, 0.0, 1.0))
	for descriptor: Dictionary in _descriptors:
		var descriptor_id: int = int(descriptor.get("descriptor_id", 0))
		var flags: int = int(descriptor.get("flags", 0))
		var actor: bool = bool(flags & FLAG_ACTOR)
		var body_size: Vector2 = _atlas_size(actor, false)
		var shadow_size: Vector2 = _atlas_size(actor, true)
		var body_rect: Color = _normalized_rect(descriptor.get("body_rect_px", []), body_size)
		var shadow_rect: Color = _normalized_rect(
			descriptor.get("shadow_rect_px", descriptor.get("body_rect_px", [])),
			shadow_size,
		)
		var layout: Array = descriptor.get("atlas_layout", []) as Array
		var frame_size: Array = descriptor.get("frame_size_px", []) as Array
		if body_rect.b <= 0.0 or body_rect.a <= 0.0 or shadow_rect.b <= 0.0 \
				or shadow_rect.a <= 0.0 or layout.size() != 3 or frame_size.size() != 2:
			return false
		descriptor_image.set_pixel(descriptor_id, 0, body_rect)
		descriptor_image.set_pixel(descriptor_id, 1, shadow_rect)
		descriptor_image.set_pixel(
			descriptor_id,
			2,
			Color(float(layout[0]), float(layout[1]), float(layout[2]), float(flags)),
		)
		descriptor_image.set_pixel(
			descriptor_id,
			3,
			Color(
				1.0 / maxf(float(frame_size[0]), 1.0),
				1.0 / maxf(float(frame_size[1]), 1.0),
				float(descriptor.get("wind_strength_px", 0.0)),
				float(descriptor.get("passes", 0)),
			),
		)
		var shadow_frame_size: Array = descriptor.get(
			"shadow_frame_size_px",
			frame_size,
		) as Array
		if shadow_frame_size.size() != 2:
			return false
		descriptor_image.set_pixel(
			descriptor_id,
			4,
			Color(
				1.0 / maxf(float(shadow_frame_size[0]), 1.0),
				1.0 / maxf(float(shadow_frame_size[1]), 1.0),
				0.0,
				0.0,
			),
		)
		var crops: Array = descriptor.get("render_crops", []) as Array
		var anchors: Array = descriptor.get("anchors", []) as Array
		for variant_index: int in range(crops.size()):
			var crop: Array = crops[variant_index] as Array
			var anchor: Array = anchors[variant_index] as Array
			if crop.size() != 4 or anchor.size() != 2:
				return false
			crop_image.set_pixel(
				variant_index,
				descriptor_id,
				Color(float(crop[0]), float(crop[1]), float(crop[2]), float(crop[3])),
			)
			anchor_image.set_pixel(
				variant_index,
				descriptor_id,
				Color(float(anchor[0]), float(anchor[1]), 0.0, 1.0),
			)
	_descriptor_lut = ImageTexture.create_from_image(descriptor_image)
	_variant_crop_lut = ImageTexture.create_from_image(crop_image)
	_variant_anchor_lut = ImageTexture.create_from_image(anchor_image)
	return _descriptor_lut != null and _variant_crop_lut != null and _variant_anchor_lut != null


func _atlas_size(actor: bool, shadow: bool) -> Vector2:
	var atlases: Dictionary = _manifest.get("atlases", { }) as Dictionary
	var key: String = "actor_shadow_size_px" if shadow else "actor_body_size_px"
	var fallback_key: String = "static_size_px"
	var value: Array = atlases.get(key if actor else fallback_key, []) as Array
	if value.size() != 2:
		var synthetic_size: Array = _manifest.get("atlas_size_px", []) as Array
		value = synthetic_size
	if value.size() != 2:
		return Vector2.ONE
	return Vector2(maxf(float(value[0]), 1.0), maxf(float(value[1]), 1.0))


static func _normalized_rect(rect_value: Variant, atlas_size: Vector2) -> Color:
	var rect: Array = rect_value as Array
	if rect.size() != 4:
		return Color(0.0, 0.0, 0.0, 0.0)
	return Color(
		float(rect[0]) / atlas_size.x,
		float(rect[1]) / atlas_size.y,
		float(rect[2]) / atlas_size.x,
		float(rect[3]) / atlas_size.y,
	)


static func _packed_float_array(value: Variant) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if not value is Array:
		return result
	for component: Variant in value as Array:
		result.append(float(component))
	return result


static func _flatten_vec4_table(value: Variant) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if not value is Array:
		return result
	for row_value: Variant in value as Array:
		if not row_value is Array or (row_value as Array).size() != 4:
			return PackedFloat32Array()
		for component: Variant in row_value as Array:
			result.append(float(component))
	return result
