extends SceneTree

const MOUNTAIN_SHADER_PATH: String = "res://assets/shaders/mountain_top_mask_underlay.gdshader"
const TORCH_SHADOW_FIELD_SHADER_PATH: String = "res://assets/shaders/mountain_torch_shadow_field.gdshader"
const MOUNTAIN_MATERIAL_SET_PATH: String = "res://data/terrain/material_sets/mountain_mask_underlay_material_set.tres"
const WORLD_STREAMER_PATH: String = "res://core/systems/world/world_streamer.gd"
const PLAYER_TORCH_PATH: String = "res://core/entities/player/player_torch.gd"

var _failed: bool = false


func _init() -> void:
	_assert_mountain_shader_gates_point_lights()
	_assert_mountain_mask_runtime_resolution()
	_assert_mountain_facade_texture_scale()
	_assert_mountain_facade_no_terraces()
	_assert_torch_shadow_field_facade_foot_smooth()
	_assert_player_torch_uses_high_res_image_texture()

	quit(1 if _failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true


func _assert_mountain_shader_gates_point_lights() -> void:
	var shader_source: String = FileAccess.get_file_as_string(MOUNTAIN_SHADER_PATH)
	_assert(
		shader_source.contains("varying float point_light_facade_accept"),
		"Mountain shader must pass facade point-light acceptance from fragment to light pass.",
	)
	_assert(
		shader_source.contains("void light()"),
		"Mountain shader must own the CanvasItem light pass.",
	)
	_assert(
		shader_source.contains("float accept = clamp(point_light_facade_accept"),
		"Mountain shader must gate PointLight2D contribution by facade acceptance.",
	)
	_assert(
		not shader_source.contains("point_light_facade_accept = is_wall ? 1.0 : 0.0"),
		"Mountain shader must not use a binary is_wall point-light gate; runtime mask texels make that visible as stair steps.",
	)
	_assert(
		shader_source.contains("wall_mask"),
		"Mountain shader must expose a smoothed wall/facade mask for lighting and wall blending.",
	)
	_assert(
		shader_source.contains("SHADOW_MODULATE = vec4(1.0)"),
		"Mountain shader must not apply the engine shadow texture to the mountain sprite point-light pass.",
	)
	_assert(
		not shader_source.contains("strata_wave") and not shader_source.contains("strata_line"),
		"Mountain facade shader must not reintroduce procedural horizontal strata; torch light makes them read as ribbed bands.",
	)
	_assert(
		not shader_source.contains("cut_highlight")
				and not shader_source.contains("cleft =")
				and not shader_source.contains("top_rim")
				and not shader_source.contains("base_debris =")
				and not shader_source.contains("wall_depth)"),
		"Mountain facade shader must not use quantized wall_depth tonal bands; the 8px mask depth reads as ribbed contour stripes under torch light.",
	)


func _assert_mountain_mask_runtime_resolution() -> void:
	var streamer_source: String = FileAccess.get_file_as_string(WORLD_STREAMER_PATH)
	_assert(
		streamer_source.contains("const MOUNTAIN_HALO_MASK_PIXELS_PER_TILE: int = 8"),
		"Runtime mountain visual mask must stay at 8 px/tile samples; 4 samples/tile exposes 16px stair steps under torch light.",
	)


func _assert_mountain_facade_texture_scale() -> void:
	var material_set: Resource = load(MOUNTAIN_MATERIAL_SET_PATH)
	_assert(material_set != null, "Mountain mask material set must load.")
	if material_set == null:
		return
	var sampling_params: Dictionary = material_set.get("sampling_params") as Dictionary
	_assert(
		float(sampling_params.get("face_texture_scale", 0.0)) >= 1.0,
		"Mountain facade face_texture_scale must not stretch the face albedo into a blurry smear.",
	)


func _assert_mountain_facade_no_terraces() -> void:
	var material_set: Resource = load(MOUNTAIN_MATERIAL_SET_PATH)
	_assert(material_set != null, "Mountain mask material set must load.")
	if material_set == null:
		return
	var sampling_params: Dictionary = material_set.get("sampling_params") as Dictionary
	_assert(
		float(sampling_params.get("terrace_strength", 0.0)) <= 0.001,
		"Live mountain material must not enable concentric height terraces; torch light reads them as ribbed contour bands.",
	)


func _assert_torch_shadow_field_facade_foot_smooth() -> void:
	var shader_source: String = FileAccess.get_file_as_string(TORCH_SHADOW_FIELD_SHADER_PATH)
	_assert(
		shader_source.contains("const int MARCH_MAX = 80"),
		"Torch shadow field must cover the same pool with a finer 8px march step.",
	)
	_assert(
		shader_source.contains("uniform float march_step_px = 8.0"),
		"Torch shadow field must use an 8px march step to reduce near-wall teeth.",
	)
	_assert(
		shader_source.contains("float march_dist = (float(i) - 0.5) * march_step_px"),
		"Torch shadow field must sample segment centers instead of step boundaries.",
	)
	_assert(
		shader_source.contains("segment_weight"),
		"Torch shadow field must fade the terminal march segment instead of adding ring bands abruptly.",
	)
	_assert(
		not shader_source.contains("float march_dist = float(i) * march_step_px"),
		"Torch shadow field must not sample raw integer march steps; they create concentric bands.",
	)
	_assert(
		shader_source.contains("facade_foot_step_px"),
		"Torch shadow field must use a dedicated fine facade-foot step, not the coarser ray-march step.",
	)
	_assert(
		shader_source.contains("mask_solid_gradient"),
		"Torch shadow field must derive a contour normal from the solid mask for near-wall facade origins.",
	)
	_assert(
		shader_source.contains("open_dir = -normalize(gradient)"),
		"Torch shadow field must push facade origins outward along the contour normal.",
	)
	_assert(
		shader_source.contains("facade_origin_from_normal"),
		"Torch shadow field must find the facade origin along the contour normal, not only straight down.",
	)
	_assert(
		not shader_source.contains("float south = float(j) * march_step_px"),
		"Torch shadow field facade-foot search must not quantize wall self-occlusion by the ray-march step.",
	)
	_assert(
		shader_source.contains("foot_open_bias_px"),
		"Torch shadow field must bias the facade foot into open ground so front-lit facades do not self-shadow in bands.",
	)


func _assert_player_torch_uses_high_res_image_texture() -> void:
	var torch_source: String = FileAccess.get_file_as_string(PLAYER_TORCH_PATH)
	_assert(
		torch_source.contains("const TEXTURE_SIZE: int = 1024"),
		"Player torch must use a high-resolution radial texture to reduce visible light rings.",
	)
	_assert(
		torch_source.contains("const RANGE_SCALE: float = 1.1"),
		"Player torch must keep the old world radius after doubling the texture resolution.",
	)
	_assert(
		torch_source.contains("ImageTexture.create_from_image"),
		"Player torch radial light must be generated as an ImageTexture so it can use a custom falloff/dither.",
	)
	_assert(
		torch_source.contains("_radial_dither"),
		"Player torch radial light must add tiny deterministic dither to break 8-bit radial banding.",
	)
	_assert(
		not torch_source.contains("GradientTexture2D.new()"),
		"Player torch must not use GradientTexture2D for the main torch pool; it shows radial bands when stretched.",
	)
