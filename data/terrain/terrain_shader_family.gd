class_name TerrainShaderFamily
extends Resource

@export_group("Identity")
@export var id: StringName = &""
@export var render_layer_id: StringName = &""

@export_group("Shader")
@export var shader: Shader = null

@export_group("Bindings")
@export var shape_texture_params: Dictionary = {}
@export var material_texture_params: Dictionary = {}

func is_valid_family() -> bool:
	return not str(id).is_empty() and not str(render_layer_id).is_empty()
