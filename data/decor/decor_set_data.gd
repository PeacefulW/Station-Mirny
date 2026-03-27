class_name DecorSetData
extends Resource

## Набор элементов декора, назначаемый биому.

@export_group("Identity")
@export var id: StringName = &""
@export var display_name_key: String = ""
@export var tags: Array[StringName] = []

@export_group("Entries")
@export var entries: Array[DecorEntry] = []

@export_group("Density")
@export_range(0.0, 1.0, 0.01) var base_density: float = 0.06

@export_group("Filters")
@export var terrain_filter: Array[int] = [0]
@export var subzone_density_modifiers: Dictionary = {}

func get_subzone_density(subzone_kind: StringName) -> float:
	var modifier: float = float(subzone_density_modifiers.get(subzone_kind, 1.0))
	return base_density * modifier

func is_allowed_on_terrain(terrain_type: int) -> bool:
	if terrain_filter.is_empty():
		return terrain_type == 0
	return terrain_filter.has(terrain_type)

func pick_entry(hash_value: float) -> DecorEntry:
	if entries.is_empty():
		return null
	var total_weight: float = 0.0
	for entry: DecorEntry in entries:
		total_weight += entry.weight
	if total_weight <= 0.0:
		return null
	var target: float = hash_value * total_weight
	var accumulated: float = 0.0
	for entry: DecorEntry in entries:
		accumulated += entry.weight
		if target <= accumulated:
			return entry
	return entries.back()
