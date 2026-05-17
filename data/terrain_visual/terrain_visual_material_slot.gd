class_name TerrainVisualMaterialSlot
extends Resource

const SOURCE_PROCEDURAL: StringName = &"procedural"
const SOURCE_IMAGE: StringName = &"image"
const SOURCE_FLAT: StringName = &"flat"

const PROCEDURAL_STRATIFIED_ROCK: StringName = &"stratified_rock"
const PROCEDURAL_ROUGH_STONE: StringName = &"rough_stone"
const PROCEDURAL_CRACKED_DRY_EARTH: StringName = &"cracked_dry_earth"
const PROCEDURAL_PACKED_DIRT: StringName = &"packed_dirt"

const VALID_SOURCES: Array[StringName] = [SOURCE_PROCEDURAL, SOURCE_IMAGE, SOURCE_FLAT]
const VALID_PROCEDURAL_KINDS: Array[StringName] = [
	PROCEDURAL_STRATIFIED_ROCK,
	PROCEDURAL_ROUGH_STONE,
	PROCEDURAL_CRACKED_DRY_EARTH,
	PROCEDURAL_PACKED_DIRT,
]

@export_group("Source")
@export var source: StringName = SOURCE_PROCEDURAL
@export var procedural_kind: StringName = PROCEDURAL_STRATIFIED_ROCK
@export var image_albedo: Texture2D = null
@export var image_normal: Texture2D = null
@export var image_modulation: Texture2D = null
@export var flat_color: Color = Color(0.55, 0.53, 0.48, 1.0)

@export_group("Procedural Colors")
@export var color_a: Color = Color(0.34, 0.33, 0.30, 1.0)
@export var color_b: Color = Color(0.60, 0.58, 0.52, 1.0)
@export var highlight_color: Color = Color(0.76, 0.73, 0.65, 1.0)

@export_group("Procedural Controls")
@export_range(0.01, 64.0, 0.01) var scale: float = 1.0
@export_range(0.0, 4.0, 0.01) var contrast: float = 1.0
@export_range(0.0, 1.0, 0.01) var crack_amount: float = 0.35
@export_range(0.0, 1.0, 0.01) var wear: float = 0.25
@export_range(0.0, 1.0, 0.01) var grain: float = 0.45
@export_range(0.0, 1.0, 0.01) var edge_darkening: float = 0.35
@export var seed: int = 0

@export_group("Render Mix")
@export_range(0.0, 1.0, 0.01) var normal_mix: float = 1.0
@export_range(0.0, 1.0, 0.01) var modulation_strength: float = 0.75


func is_valid_material() -> bool:
	return validate().is_empty()


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not VALID_SOURCES.has(source):
		errors.append("source is unsupported")
	if source == SOURCE_PROCEDURAL:
		if str(procedural_kind).is_empty():
			errors.append("procedural_kind is required when source is procedural")
		elif not VALID_PROCEDURAL_KINDS.has(procedural_kind):
			errors.append("procedural_kind is unsupported")
	elif source == SOURCE_IMAGE:
		if image_albedo == null:
			errors.append("image_albedo is required when source is image")
	if scale <= 0.0:
		errors.append("scale must be greater than 0")
	_append_normalized_range_error(errors, contrast, "contrast", 0.0, 4.0)
	_append_normalized_range_error(errors, crack_amount, "crack_amount", 0.0, 1.0)
	_append_normalized_range_error(errors, wear, "wear", 0.0, 1.0)
	_append_normalized_range_error(errors, grain, "grain", 0.0, 1.0)
	_append_normalized_range_error(errors, edge_darkening, "edge_darkening", 0.0, 1.0)
	_append_normalized_range_error(errors, normal_mix, "normal_mix", 0.0, 1.0)
	_append_normalized_range_error(errors, modulation_strength, "modulation_strength", 0.0, 1.0)
	return errors


func _append_normalized_range_error(
		errors: PackedStringArray,
		value: float,
		field_name: String,
		min_value: float,
		max_value: float,
) -> void:
	if value < min_value or value > max_value:
		errors.append("%s must be between %.2f and %.2f" % [field_name, min_value, max_value])
