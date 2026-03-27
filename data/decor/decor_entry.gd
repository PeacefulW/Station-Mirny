class_name DecorEntry
extends Resource

## Одиночный элемент декора: камни, кости, споровые пятна, обломки.

@export_group("Identity")
@export var id: StringName = &""
@export var display_name_key: String = ""
@export var tags: Array[StringName] = []

@export_group("Visual")
@export var texture: Texture2D = null
@export var placeholder_color: Color = Color(0.4, 0.35, 0.3, 1.0)
@export var placeholder_size: Vector2i = Vector2i(10, 10)
@export var z_index_offset: int = -1

@export_group("Placement")
@export_range(0.01, 10.0, 0.01) var weight: float = 1.0
