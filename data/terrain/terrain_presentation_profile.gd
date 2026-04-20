class_name TerrainPresentationProfile
extends Resource

@export_group("Identity")
@export var id: StringName = &""
@export var terrain_class_id: StringName = &""
@export var terrain_ids: Array[int] = []

@export_group("Bindings")
@export var shape_set_id: StringName = &""
@export var material_set_id: StringName = &""
@export var shader_family_id: StringName = &""

func is_valid_profile() -> bool:
	return not str(id).is_empty() \
		and not str(terrain_class_id).is_empty() \
		and not terrain_ids.is_empty() \
		and not str(shape_set_id).is_empty() \
		and not str(material_set_id).is_empty() \
		and not str(shader_family_id).is_empty()
