class_name TerrainMaterialSet
extends Resource

@export_group("Identity")
@export var id: StringName = &""
@export var shader_family_id: StringName = &""

@export_group("Textures")
@export var top_albedo: Texture2D = null
@export var face_albedo: Texture2D = null
@export var top_modulation: Texture2D = null
@export var face_modulation: Texture2D = null
@export var top_normal: Texture2D = null
@export var face_normal: Texture2D = null
## Named material-only maps for shader families that need more than the fixed
## slots (e.g. grass density ladder albedos). Keys are slot StringNames.
@export var extra_textures: Dictionary = {}

@export_group("Sampling")
@export var sampling_params: Dictionary = {}

func is_valid_material() -> bool:
	return not str(id).is_empty() and not str(shader_family_id).is_empty()

func get_texture_slot(slot_id: StringName) -> Texture2D:
	match slot_id:
		&"top_albedo":
			return top_albedo
		&"face_albedo":
			return face_albedo
		&"top_modulation":
			return top_modulation
		&"face_modulation":
			return face_modulation
		&"top_normal":
			return top_normal
		&"face_normal":
			return face_normal
		_:
			return extra_textures.get(slot_id, null) as Texture2D
