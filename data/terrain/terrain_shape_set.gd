class_name TerrainShapeSet
extends Resource

@export_group("Identity")
@export var id: StringName = &""
@export var topology_family_id: StringName = &""

@export_group("Atlases")
@export var mask_atlas: Texture2D = null
@export var shape_normal_atlas: Texture2D = null

@export_group("Layout")
@export_range(1, 4096, 1) var tile_size_px: int = 32
@export_range(1, 1024, 1) var case_count: int = 1
@export_range(1, 1024, 1) var variant_count: int = 1

func is_valid_shape() -> bool:
	return not str(id).is_empty() \
		and not str(topology_family_id).is_empty() \
		and mask_atlas != null \
		and tile_size_px > 0 \
		and case_count > 0 \
		and variant_count > 0

func get_texture_slot(slot_id: StringName) -> Texture2D:
	match slot_id:
		&"mask_atlas":
			return mask_atlas
		&"shape_normal_atlas":
			return shape_normal_atlas
		_:
			return null
