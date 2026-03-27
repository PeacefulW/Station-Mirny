class_name FloraSetData
extends Resource

## Набор элементов флоры, назначаемый биому или подзоне.
## Управляет плотностью и фильтрацией по условиям мира.

@export_group("Identity")
@export var id: StringName = &""
@export var display_name_key: String = ""
@export var tags: Array[StringName] = []

@export_group("Entries")
@export var entries: Array[FloraEntry] = []

@export_group("Density")
@export_range(0.0, 1.0, 0.01) var base_density: float = 0.10
@export_range(0.0, 2.0, 0.01) var flora_channel_weight: float = 1.0
@export_range(0.0, 2.0, 0.01) var flora_modulation_weight: float = 0.5

@export_group("Filters")
@export var subzone_filters: Array[StringName] = []
@export var excluded_subzones: Array[StringName] = []
@export var terrain_filter: Array[int] = [0]

func is_allowed_in_subzone(subzone_kind: StringName) -> bool:
	if not excluded_subzones.is_empty() and excluded_subzones.has(subzone_kind):
		return false
	if not subzone_filters.is_empty() and not subzone_filters.has(subzone_kind):
		return false
	return true

func is_allowed_on_terrain(terrain_type: int) -> bool:
	if terrain_filter.is_empty():
		return terrain_type == 0
	return terrain_filter.has(terrain_type)

func pick_entry(hash_value: float, flora_density: float) -> FloraEntry:
	var eligible: Array[FloraEntry] = []
	var total_weight: float = 0.0
	for entry: FloraEntry in entries:
		if flora_density >= entry.min_density_threshold and flora_density <= entry.max_density_threshold:
			eligible.append(entry)
			total_weight += entry.weight
	if eligible.is_empty() or total_weight <= 0.0:
		return null
	var target: float = hash_value * total_weight
	var accumulated: float = 0.0
	for entry: FloraEntry in eligible:
		accumulated += entry.weight
		if target <= accumulated:
			return entry
	return eligible.back()
