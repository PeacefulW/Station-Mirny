class_name FeatureHookData
extends Resource

@export_group("Identity")
@export var id: StringName = &""
@export var display_name_key: String = ""
@export var display_name: String = ""
@export var tags: Array[StringName] = []

@export_group("Eligibility")
@export var allowed_biome_ids: Array[StringName] = []
@export var required_structure_tags: Array[StringName] = []
@export var allowed_terrain_types: Array[int] = []
@export_range(0.0, 10.0, 0.01) var weight: float = 1.0

@export_group("Debug")
@export var debug_marker_kind: StringName = &""

func get_display_name() -> String:
	return Localization.td(display_name_key, display_name)
