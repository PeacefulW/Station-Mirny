class_name PoiDefinition
extends Resource

const UNSET_ANCHOR_OFFSET: Vector2i = Vector2i(2147483647, 2147483647)
const UNSET_PRIORITY: int = -2147483648

@export_group("Identity")
@export var id: StringName = &""
@export var display_name_key: String = ""
@export var display_name: String = ""
@export var tags: Array[StringName] = []

@export_group("Placement")
@export var required_feature_hook_ids: Array[StringName] = []
@export var allowed_biome_ids: Array[StringName] = []
@export var required_structure_tags: Array[StringName] = []
@export var allowed_terrain_types: Array[int] = []
@export var footprint_tiles: Array[Vector2i] = []
@export var anchor_offset: Vector2i = UNSET_ANCHOR_OFFSET
@export var priority: int = UNSET_PRIORITY

@export_group("Debug")
@export var debug_marker_kind: StringName = &""

func get_display_name() -> String:
	return Localization.td(display_name_key, display_name)

func has_explicit_anchor_offset() -> bool:
	return anchor_offset != UNSET_ANCHOR_OFFSET

func has_explicit_priority() -> bool:
	return priority != UNSET_PRIORITY
