extends SceneTree

# Static contract probe for M8.2. It deliberately checks ownership and bounded
# update paths without booting the world.
#
# Run:
#   Godot_v4.7-stable_win64_console.exe --headless --path . \
#     -s tools/mountain_cavity_skylight_field_static_smoke_test.gd

const FIELD_SCRIPT_PATH := "res://core/systems/world/mountain_cavity_skylight_field.gd"
const FIELD_SHADER_PATH := "res://assets/shaders/mountain_cavity_skylight_field.gdshader"
const CHUNK_VIEW_PATH := "res://core/systems/world/chunk_view.gd"
const WORLD_STREAMER_PATH := "res://core/systems/world/world_streamer.gd"
const WORLD_SCENE_PATH := "res://scenes/world/world_runtime_v0.tscn"

var _failures: Array[String] = []


func _init() -> void:
	var field_script: String = _read_text(FIELD_SCRIPT_PATH)
	var field_shader: String = _read_text(FIELD_SHADER_PATH)
	var chunk_view: String = _read_text(CHUNK_VIEW_PATH)
	var world_streamer: String = _read_text(WORLD_STREAMER_PATH)
	var world_scene: String = _read_text(WORLD_SCENE_PATH)

	_expect(field_script.contains("class_name MountainCavitySkylightField"), "field owner missing")
	_expect(not field_script.contains("func _process("), "field must have no per-frame CPU loop")
	_expect(not field_script.contains("get_nodes_in_group"), "field must not scan the scene tree")
	_expect(not field_script.contains("PointLight2D"), "field script must not enumerate point lights")
	_expect(not field_script.contains("LightOccluder2D"), "field must not create occluder geometry")
	_expect(
		field_script.contains("WorldRuntimeConstants.Z_GRASS_SPORE + 1"),
		"field must cover world objects below UI/debug overlays",
	)
	var reveal_function: String = _function_slice(field_script, "func set_reveal_blend(")
	_expect(not reveal_function.contains("for "), "reveal blend must remain O(1)")
	_expect(not reveal_function.contains("while "), "reveal blend must remain O(1)")
	_expect(
		field_script.contains("modulate = Color(_reveal_blend, 1.0, 1.0, 1.0)"),
		"shared reveal scalar must stay a parent-level O(1) update",
	)
	_expect(
		field_script.contains("var is_active: bool = true"),
		"ready dug chunks must remain available while the roof selector is empty",
	)
	var visibility_function: String = _function_slice(field_script, "func _refresh_visibility(")
	_expect(
		not visibility_function.contains("_reveal_blend"),
		"closed-mouth visibility must not be globally gated by reveal blend",
	)

	_expect(field_shader.contains("hint_screen_texture"), "field must sample the pre-field world")
	_expect(field_shader.contains("void light()"), "field must define light-aware composition")
	_expect(field_shader.contains("LIGHT_IS_DIRECTIONAL"), "directional sun rejection missing")
	_expect(field_shader.contains("LIGHT = vec4(0.0)"), "directional light must contribute zero")
	_expect(
		not field_shader.contains("return;"),
		"Godot light processor must not use an early return",
	)
	_expect(field_shader.contains("scene_color - COLOR.rgb"), "generic point-light restoration missing")
	_expect(field_shader.contains("reveal_selector_texture"), "component selector clipping missing")
	_expect(
		field_shader.contains("sample_guarded_active_foreign_pair"),
		"organic selector fringe guard missing",
	)
	_expect(
		field_shader.contains("any_cutout_halo_texture"),
		"foreign-cavity ownership guard missing",
	)
	_expect(
		field_shader.contains("sample_any_cutout_broad"),
		"bounded facade broad phase missing",
	)
	_expect(field_shader.contains("sky_exposure_texture"), "derived exposure input missing")
	_expect(
		field_shader.contains(
			"uniform float darkness_ramp_gamma : hint_range(1.0, 3.0) = 1.35"
		),
		"M8.4 entrance-ramp tuning is missing",
	)
	_expect(
		field_shader.contains("pow(natural_darkness_linear, darkness_ramp_gamma)"),
		"natural darkness must use the monotonic post-smoothstep ramp",
	)
	_expect(
		field_shader.contains("sample_closed_mouth_coverage"),
		"closed-roof mouth coverage is missing",
	)
	_expect(
		field_shader.contains("float reveal_blend = clamp(COLOR.r"),
		"shader must consume the shared parent reveal scalar",
	)
	_expect(
		field_shader.contains("revealed_coverage * reveal_blend"),
		"revealed component coverage is not blended independently from the mouth",
	)
	_expect(
		not field_shader.contains("player_position"),
		"closed-mouth coverage must not depend on player position",
	)
	_expect(not field_shader.contains("unshaded"), "final field must remain light-aware")
	var source_identity_pattern := RegEx.new()
	source_identity_pattern.compile("\\b(torch|lamp)\\b")
	_expect(
		source_identity_pattern.search(field_shader.to_lower()) == null,
		"shader must not couple to torch/lamp identity",
	)

	var source_function: String = _function_slice(
		chunk_view,
		"func get_mountain_cavity_skylight_field_source(",
	)
	_expect(source_function.contains("_mountain_top_mask_texture"), "live V texture not reused")
	_expect(source_function.contains("_mountain_closed_roof_mask_texture"), "closed C texture not reused")
	_expect(source_function.contains("_mountain_sky_exposure_texture"), "exposure texture not reused")
	_expect(source_function.contains("_mountain_active_floor_halo_texture"), "selector texture not reused")
	_expect(source_function.contains("_mountain_dug_halo_texture"), "dug guard texture not reused")
	_expect(
		not source_function.contains("selector_sample_count"),
		"field source must not rescan the selector only to decide closed visibility",
	)
	_expect(
		source_function.contains(
			'_mountain_closed_roof_mask_material.get_shader_parameter("facade_height_px")'
		),
		"field must reuse the authored construction-roof facade height",
	)
	_expect(
		source_function.contains('"facade_height_px": facade_height_px'),
		"authored facade height is not published to the field",
	)
	_expect(not source_function.contains("Image.create"), "field source must not create a mask copy")
	_expect(not source_function.contains("ImageTexture.create"), "field source must not upload a mask copy")
	_expect(
		field_script.contains(
			'set_shader_parameter("any_cutout_halo_texture", any_cutout_texture)'
		),
		"exact dug guard binding missing",
	)
	_expect(
		field_script.contains(
			'set_shader_parameter("any_cutout_broad_texture", any_cutout_texture)'
		),
		"facade broad phase must reuse the same uploaded dug texture",
	)

	_expect(
		world_streamer.count(
			"_sync_mountain_cavity_skylight_field_chunk(chunk_coord, chunk_view)"
		) == 2,
		"budgeted visual/selector sync missing",
	)
	_expect(
		world_streamer.contains("_remove_mountain_cavity_skylight_field_chunk(chunk_coord)"),
		"eviction cleanup missing",
	)
	_expect(
		world_streamer.contains("_clear_mountain_cavity_skylight_field()"),
		"runtime reset cleanup missing",
	)
	_expect(not world_streamer.contains("mountain_skylight_changed"), "M8 must add no EventBus signal")
	_expect(
		world_scene.contains("[node name=\"MountainCavitySkylightField\""),
		"live scene wiring missing",
	)

	if _failures.is_empty():
		print("mountain_cavity_skylight_field_static_smoke_test: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("mountain_cavity_skylight_field_static_smoke_test: %s" % failure)
	quit(1)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("cannot read %s" % path)
		return ""
	return file.get_as_text()


func _function_slice(source: String, signature: String) -> String:
	var start: int = source.find(signature)
	if start < 0:
		return ""
	var next_function: int = source.find("\nfunc ", start + signature.length())
	return source.substr(start) if next_function < 0 else source.substr(start, next_function - start)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
