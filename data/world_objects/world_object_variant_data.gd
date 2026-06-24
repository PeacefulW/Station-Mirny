class_name WorldObjectVariantData
extends Resource

## Authored descriptor for a single world object visual variant.

@export_group("Identity")
@export var id: StringName = &""
@export var group_id: StringName = &""
@export var tags: Array[StringName] = []

@export_group("Visual")
@export var texture: Texture2D = null
@export var atlas_index: int = 0
@export var atlas_frame: int = 0
@export var visual_size_min_px: float = 64.0
@export var visual_size_max_px: float = 64.0
@export var source_model_path: String = ""

@export_group("Placement")
@export var biome_tags: Array[StringName] = []
@export var placement_tags: Array[StringName] = []
@export_range(0.01, 10.0, 0.01) var weight: float = 1.0

@export_group("Gameplay")
@export var blocks_movement: bool = false
@export var collision_profile: StringName = &"none"
@export var shadow_profile: StringName = &"runtime_contact"
