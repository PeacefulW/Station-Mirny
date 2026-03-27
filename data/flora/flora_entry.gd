class_name FloraEntry
extends Resource

## Одиночный элемент флоры: споростебель, коралловый шпиль, светомох и т.д.

@export_group("Identity")
@export var id: StringName = &""
@export var display_name_key: String = ""
@export var tags: Array[StringName] = []

@export_group("Visual")
@export var texture: Texture2D = null
@export var placeholder_color: Color = Color(0.3, 0.5, 0.2, 1.0)
@export var placeholder_size: Vector2i = Vector2i(12, 24)
@export var z_index_offset: int = 0

@export_group("Placement")
@export var tile_footprint: Vector2i = Vector2i(1, 1)
@export_range(0.0, 1.0, 0.01) var min_density_threshold: float = 0.0
@export_range(0.0, 1.0, 0.01) var max_density_threshold: float = 1.0
@export_range(0.01, 10.0, 0.01) var weight: float = 1.0

@export_group("Gameplay")
@export var is_harvestable: bool = false
@export var harvest_item_id: StringName = &""
