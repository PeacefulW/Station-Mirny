class_name WorldObjectPlacementGroupData
extends Resource

## Placement grouping for authored world object variants.

@export_group("Identity")
@export var id: StringName = &""
@export var object_family: StringName = &""
@export var biome_id: StringName = &""
@export var tags: Array[StringName] = []

@export_group("Variants")
@export var variants: Array[Resource] = []

@export_group("Atlas")
@export var atlas_texture: Texture2D = null
@export var atlas_columns: int = 1
@export var atlas_rows: int = 1
@export var atlas_frame_count: int = 1
@export var visual_size_min_px: float = 64.0
@export var visual_size_max_px: float = 64.0
@export var source_model_directory: String = ""

@export_group("Placement")
@export var placement_mask: StringName = &""
@export_range(0.0, 1.0, 0.01) var density: float = 0.0
@export var max_per_chunk: int = 0
@export var min_distance_px: float = 0.0

@export_group("Gameplay")
@export var blocks_movement: bool = false
@export var collision_profile: StringName = &"none"
@export var shadow_profile: StringName = &"runtime_contact"
