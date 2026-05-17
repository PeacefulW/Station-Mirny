class_name TerrainVisualRecipe
extends Resource

const SUPPORTED_SCHEMA_VERSION: int = 1

const SURFACE_ROCK: StringName = &"rock"
const SURFACE_GROUND: StringName = &"ground"
const SURFACE_LAKE_BANK: StringName = &"lake_bank"
const SURFACE_SNOW: StringName = &"snow"
const SURFACE_ASH: StringName = &"ash"

const SUPPORTED_SURFACE_KINDS: Array[StringName] = [
	SURFACE_ROCK,
	SURFACE_GROUND,
	SURFACE_LAKE_BANK,
	SURFACE_SNOW,
	SURFACE_ASH,
]
const SUPPORTED_SHAPE_SUPERSAMPLING: Array[int] = [1, 2, 4, 8]

@export_group("Identity")
@export var id: StringName = &""
@export var schema_version: int = SUPPORTED_SCHEMA_VERSION
@export var display_name_key: StringName = &""
@export var surface_kind: StringName = SURFACE_ROCK
@export var solver_family_id: StringName = &"terrain_visual_sdf_v2"
@export var default_seed: int = 0
@export_range(1, 4096, 1) var tile_size_px: int = 64
@export_range(1, 1024, 1) var variant_count: int = 6

@export_group("Shape")
@export_range(0.0, 512.0, 0.1) var south_height_px: float = 64.0
@export_range(0.0, 512.0, 0.1) var north_height_px: float = 0.0
@export_range(0.0, 512.0, 0.1) var side_height_px: float = 0.0
@export_range(0.1, 8.0, 0.01) var face_power: float = 2.5
@export_range(0.0, 1.0, 0.01) var back_drop: float = 0.8
@export_range(0.0, 256.0, 0.1) var crown_bevel_px: float = 4.0
@export_range(0.0, 256.0, 0.1) var outer_corner_radius_px: float = 40.0
@export_range(0.0, 256.0, 0.1) var inner_corner_radius_px: float = 40.0
@export_range(0.0, 256.0, 0.1) var corner_round_px: float = 32.0
@export_range(0.0, 256.0, 0.1) var diagonal_smooth_px: float = 64.0
@export_range(0.0, 1.0, 0.01) var contour_relax: float = 0.0
@export_range(0.0, 64.0, 0.1) var contour_warp_px: float = 1.5
@export_range(0.0, 1.0, 0.01) var corner_variation: float = 0.55
@export_range(0.0, 1.0, 0.01) var geometry_variance: float = 0.75
@export_range(1, 8, 1) var shape_supersampling: int = 4

@export_group("Edge And Rim")
@export_range(0.0, 256.0, 0.1) var rim_width_px: float = 16.0
@export_range(0.0, 1.0, 0.01) var edge_debris: float = 0.8
@export_range(0.0, 1.0, 0.01) var edge_color_strength: float = 0.55
@export var contact_outline_enabled: bool = true
@export_range(0.0, 64.0, 0.1) var contact_outline_width_px: float = 6.0
@export var contact_outline_color: Color = Color(0.05, 0.045, 0.04, 1.0)

@export_group("Normal")
@export_range(0.0, 16.0, 0.01) var normal_strength: float = 8.0
@export_range(0.0, 16.0, 0.01) var normal_detail_strength: float = 4.0
@export_range(0.0, 16.0, 0.1) var height_to_normal_blur_radius_px: float = 1.0
@export var bake_height_shading_for_reference: bool = false

@export_group("Materials")
@export var top_material: Resource = null
@export var face_material: Resource = null
@export var base_material: Resource = null
@export var back_material: Resource = null
@export var edge_material_override: Resource = null


func is_valid_recipe() -> bool:
	return validate().is_empty()


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if str(id).is_empty():
		errors.append("id is required")
	if schema_version != SUPPORTED_SCHEMA_VERSION:
		errors.append("schema_version is unsupported")
	if str(display_name_key).is_empty():
		errors.append("display_name_key is required")
	if not SUPPORTED_SURFACE_KINDS.has(surface_kind):
		errors.append("surface_kind is unsupported")
	if str(solver_family_id).is_empty():
		errors.append("solver_family_id is required")
	if tile_size_px <= 0:
		errors.append("tile_size_px must be greater than 0")
	if variant_count <= 0:
		errors.append("variant_count must be greater than 0")
	if not SUPPORTED_SHAPE_SUPERSAMPLING.has(shape_supersampling):
		errors.append("shape_supersampling is unsupported")
	_append_non_negative_error(errors, south_height_px, "south_height_px")
	_append_non_negative_error(errors, north_height_px, "north_height_px")
	_append_non_negative_error(errors, side_height_px, "side_height_px")
	_append_non_negative_error(errors, crown_bevel_px, "crown_bevel_px")
	_append_non_negative_error(errors, outer_corner_radius_px, "outer_corner_radius_px")
	_append_non_negative_error(errors, inner_corner_radius_px, "inner_corner_radius_px")
	_append_non_negative_error(errors, corner_round_px, "corner_round_px")
	_append_non_negative_error(errors, diagonal_smooth_px, "diagonal_smooth_px")
	_append_non_negative_error(errors, contour_warp_px, "contour_warp_px")
	_append_non_negative_error(errors, rim_width_px, "rim_width_px")
	_append_non_negative_error(errors, contact_outline_width_px, "contact_outline_width_px")
	_append_range_error(errors, face_power, "face_power", 0.1, 8.0)
	_append_range_error(errors, back_drop, "back_drop", 0.0, 1.0)
	_append_range_error(errors, contour_relax, "contour_relax", 0.0, 1.0)
	_append_range_error(errors, corner_variation, "corner_variation", 0.0, 1.0)
	_append_range_error(errors, geometry_variance, "geometry_variance", 0.0, 1.0)
	_append_range_error(errors, edge_debris, "edge_debris", 0.0, 1.0)
	_append_range_error(errors, edge_color_strength, "edge_color_strength", 0.0, 1.0)
	_append_range_error(errors, normal_strength, "normal_strength", 0.0, 16.0)
	_append_range_error(errors, normal_detail_strength, "normal_detail_strength", 0.0, 16.0)
	_append_range_error(
		errors,
		height_to_normal_blur_radius_px,
		"height_to_normal_blur_radius_px",
		0.0,
		16.0,
	)
	_validate_material_slot(errors, top_material, "top_material")
	_validate_material_slot(errors, face_material, "face_material")
	_validate_material_slot(errors, base_material, "base_material")
	_validate_material_slot(errors, back_material, "back_material")
	if edge_material_override != null:
		_append_prefixed_errors(errors, "edge_material_override", edge_material_override.validate())
	return errors


func get_material_slot(slot_id: StringName) -> Resource:
	match slot_id:
		&"top":
			return top_material
		&"face":
			return face_material
		&"base":
			return base_material
		&"back":
			return back_material
		&"edge":
			return edge_material_override
		_:
			return null


func _validate_material_slot(
		errors: PackedStringArray,
		material_slot: Resource,
		field_name: String,
) -> void:
	if material_slot == null:
		errors.append("%s is required" % field_name)
		return
	if not material_slot.has_method("validate"):
		errors.append("%s must expose validate()" % field_name)
		return
	_append_prefixed_errors(errors, field_name, material_slot.call("validate"))


func _append_prefixed_errors(
		errors: PackedStringArray,
		prefix: String,
		nested_errors: PackedStringArray,
) -> void:
	for nested_error: String in nested_errors:
		errors.append("%s.%s" % [prefix, nested_error])


func _append_non_negative_error(
		errors: PackedStringArray,
		value: float,
		field_name: String,
) -> void:
	if value < 0.0:
		errors.append("%s must be non-negative" % field_name)


func _append_range_error(
		errors: PackedStringArray,
		value: float,
		field_name: String,
		min_value: float,
		max_value: float,
) -> void:
	if value < min_value or value > max_value:
		errors.append("%s must be between %.2f and %.2f" % [field_name, min_value, max_value])
