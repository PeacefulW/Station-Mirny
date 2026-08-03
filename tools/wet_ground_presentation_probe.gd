extends SceneTree

# Headless contract probe for the transient wet-ground presentation path.
# It validates tuning, integration math, shared-material publication and shader
# cost guards. Pixel quality still requires a windowed render check.
# Run:
#   Godot_v4.7-stable_win64_console.exe --headless --path . \
#     -s tools/wet_ground_presentation_probe.gd

const PROFILE_SCRIPT_PATH: String = "res://data/balance/ground_wetness_profile.gd"
const PROFILE_RESOURCE_PATH: String = "res://data/balance/ground_wetness_profile.tres"
const PRESENTER_SCRIPT_PATH: String = (
	"res://core/systems/world/ground_wetness_presenter.gd"
)
const FACTORY_SCRIPT_PATH: String = (
	"res://core/systems/world/world_tile_set_factory.gd"
)
const GROUND_SHADER_PATH: String = "res://assets/shaders/ground_hybrid_material.gdshader"
const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const PRECIPITATION_NONE: int = 0
const PRECIPITATION_RAIN: int = 1
const TERRAIN_PLAINS_GROUND: int = 0

var _failures: Array[String] = []


func _init() -> void:
	print("wet_ground_presentation_probe: START")
	call_deferred("_run")


func _run() -> void:
	var profile_script: Script = ResourceLoader.load(PROFILE_SCRIPT_PATH) as Script
	var profile: Variant = ResourceLoader.load(PROFILE_RESOURCE_PATH)
	var presenter_script: Script = ResourceLoader.load(PRESENTER_SCRIPT_PATH) as Script
	var factory_script: Script = ResourceLoader.load(FACTORY_SCRIPT_PATH) as Script
	var ground_shader: Shader = ResourceLoader.load(GROUND_SHADER_PATH) as Shader
	var world_scene: PackedScene = ResourceLoader.load(WORLD_SCENE_PATH) as PackedScene
	_check(profile_script != null, "GroundWetnessProfile script loads")
	_check(profile != null, "authored ground wetness profile loads")
	_check(presenter_script != null, "GroundWetnessPresenter script loads")
	_check(factory_script != null, "WorldTileSetFactory script loads")
	_check(ground_shader != null, "shared ground shader loads")
	_check(world_scene != null, "world runtime scene loads with wet-ground wiring")
	if (
		profile_script == null
		or profile == null
		or presenter_script == null
		or factory_script == null
		or ground_shader == null
		or world_scene == null
	):
		_finish()
		return
	_check(profile_script.can_instantiate(), "GroundWetnessProfile script compiles")
	_check(presenter_script.can_instantiate(), "GroundWetnessPresenter script compiles")
	_check(factory_script.can_instantiate(), "WorldTileSetFactory script compiles")
	if (
		not profile_script.can_instantiate()
		or not presenter_script.can_instantiate()
		or not factory_script.can_instantiate()
	):
		_finish()
		return

	_assert_profile_contract(profile)
	_assert_integration_math(profile, presenter_script)
	_assert_static_contracts()
	await _assert_shared_material_publication(
		profile,
		presenter_script,
		factory_script,
	)
	_finish()


func _assert_profile_contract(profile: Variant) -> void:
	_check(
		bool(profile.call("is_valid_profile")),
		"authored profile passes its validity contract",
	)
	var invalid_cadence: Variant = profile.duplicate(true)
	invalid_cadence.set("update_interval_seconds", 1.01)
	_check(
		not bool(invalid_cadence.call("is_valid_profile")),
		"profile rejects cadence outside its authored runtime bound",
	)
	var invalid_impact_cell: Variant = profile.duplicate(true)
	invalid_impact_cell.set("impact_cell_size_px", 161.0)
	_check(
		not bool(invalid_impact_cell.call("is_valid_profile")),
		"profile rejects impact scale outside its authored runtime bound",
	)
	_check(
		profile.get("id") == &"core:ground_wetness",
		"profile has a stable namespaced id",
	)
	_check(
		_profile_float(profile, "update_interval_seconds") >= 0.05
		and _profile_float(profile, "update_interval_seconds") <= 1.0,
		"profile cadence is bounded and slower than the frame loop",
	)
	_check(
		_profile_float(profile, "accumulation_rate_per_second")
		> _profile_float(profile, "drying_rate_per_second"),
		"authored rain accumulation is faster than passive drying",
	)
	_check(
		_profile_float(profile, "puddle_threshold") > 0.5
		and _profile_float(profile, "puddle_opacity") > 0.0
		and _profile_float(profile, "puddle_opacity") < 0.5,
		"puddles are sparse and visually restrained",
	)

	var invalid_identity: Variant = profile.duplicate(true)
	invalid_identity.set("id", &"")
	_check(
		not bool(invalid_identity.call("is_valid_profile")),
		"empty profile id is rejected",
	)
	var invalid_impact: Variant = profile.duplicate(true)
	invalid_impact.set("impact_cell_size_px", 0.0)
	_check(
		not bool(invalid_impact.call("is_valid_profile")),
		"non-positive impact cell is rejected",
	)


func _assert_integration_math(profile: Variant, presenter_script: Script) -> void:
	var accumulated: float = _calculate_next_amount(
		presenter_script,
		profile,
		0.20,
		4.0,
		PRECIPITATION_RAIN,
		1.0,
	)
	_check(
		is_equal_approx(
			accumulated,
			0.20 + _profile_float(profile, "accumulation_rate_per_second") * 4.0,
		),
		"full rain integrates authored accumulation linearly",
	)
	var half_rain: float = _calculate_next_amount(
		presenter_script,
		profile,
		0.20,
		4.0,
		PRECIPITATION_RAIN,
		0.5,
	)
	_check(
		is_equal_approx(
			half_rain,
			0.20 + _profile_float(profile, "accumulation_rate_per_second") * 2.0,
		),
		"rain intensity scales accumulation",
	)
	var dried: float = _calculate_next_amount(
		presenter_script,
		profile,
		0.45,
		10.0,
		PRECIPITATION_NONE,
		0.0,
	)
	_check(
		is_equal_approx(
			dried,
			0.45 - _profile_float(profile, "drying_rate_per_second") * 10.0,
		),
		"dry weather integrates authored passive drying",
	)
	_check(
		is_equal_approx(
			_calculate_next_amount(
				presenter_script,
				profile,
				0.37,
				0.0,
				PRECIPITATION_RAIN,
				1.0,
			),
			0.37,
		),
		"zero delta leaves wetness unchanged",
	)
	_check(
		is_equal_approx(
			_calculate_next_amount(
				presenter_script,
				profile,
				0.95,
				100.0,
				PRECIPITATION_RAIN,
				2.0,
			),
			1.0,
		),
		"rain amount and intensity clamp at the wet bound",
	)
	_check(
		is_equal_approx(
			_calculate_next_amount(
				presenter_script,
				profile,
				0.02,
				100.0,
				PRECIPITATION_NONE,
				0.0,
			),
			0.0,
		),
		"drying clamps at the dry bound",
	)


func _assert_shared_material_publication(
		profile: Variant,
		presenter_script: Script,
		factory_script: Script,
) -> void:
	var base_tile_set: TileSet = factory_script.call("get_base_tile_set") as TileSet
	_check(base_tile_set != null, "factory builds the shared base TileSet")
	var first_material: ShaderMaterial = (
		factory_script.call(
			"get_built_material_for_terrain",
			TERRAIN_PLAINS_GROUND,
		) as ShaderMaterial
	)
	var second_material: ShaderMaterial = (
		factory_script.call(
			"get_built_material_for_terrain",
			TERRAIN_PLAINS_GROUND,
		) as ShaderMaterial
	)
	_check(first_material != null, "factory getter returns the built plains material")
	_check(
		first_material == second_material,
		"factory getter preserves shared material identity",
	)
	if first_material == null:
		return

	var presenter: Node = presenter_script.new() as Node
	presenter.set("profile", profile)
	root.add_child(presenter)
	await process_frame
	await process_frame

	var weather: Node = root.get_node_or_null("WeatherRuntime")
	_check(weather != null, "WeatherRuntime autoload is available")
	if weather == null:
		presenter.queue_free()
		await process_frame
		return

	weather.call("set_debug_regime", &"core:overcast")
	weather.call("set_debug_cloud_cover", 1.0)
	weather.call("set_debug_humidity", 1.0)
	_check(
		int(weather.call("get_precipitation_kind"))
		== PRECIPITATION_RAIN,
		"debug weather supplies authoritative rain",
	)
	presenter.call(
		"_process",
		_profile_float(profile, "update_interval_seconds") + 0.01,
	)
	var wet_amount: float = float(presenter.call("get_ground_wetness"))
	_check(wet_amount > 0.0, "presenter accumulates transient wetness under rain")
	_check(
		is_equal_approx(
			_uniform_float(first_material, "wet_ground_amount"),
			wet_amount,
		),
		"presenter publishes amount to the factory-owned material",
	)
	_check(
		_uniform_float(first_material, "wet_ground_rain_intensity") > 0.0,
		"presenter publishes live rain intensity for impact rings",
	)
	_assert_profile_uniforms(first_material, profile)
	_check(
		factory_script.call(
			"get_built_material_for_terrain",
			TERRAIN_PLAINS_GROUND,
		) == first_material,
		"uniform publication does not replace shared material identity",
	)

	presenter.call("_on_z_level_changed", -1, 0)
	_check(
		is_zero_approx(_uniform_float(first_material, "wet_ground_amount"))
		and is_zero_approx(
			_uniform_float(first_material, "wet_ground_rain_intensity"),
		),
		"z transition immediately disables the surface-only wet skin",
	)

	presenter.call("_on_z_level_changed", 0, -1)
	weather.call("set_debug_regime", &"core:clear")
	weather.call("set_debug_cloud_cover", 0.0)
	weather.call("set_debug_humidity", 0.0)
	var amount_before_drying: float = float(presenter.call("get_ground_wetness"))
	presenter.call(
		"_process",
		_profile_float(profile, "update_interval_seconds") + 0.01,
	)
	_check(
		float(presenter.call("get_ground_wetness")) < amount_before_drying
		and _uniform_float(first_material, "wet_ground_amount") > 0.0
		and is_zero_approx(
			_uniform_float(first_material, "wet_ground_rain_intensity"),
		),
		"wet mask dries gradually while impact rings stop with rain",
	)

	weather.call("clear_debug_humidity")
	weather.call("clear_debug_cloud_cover")
	weather.call("clear_debug_regime")
	presenter.queue_free()
	await process_frame
	_check(
		is_zero_approx(_uniform_float(first_material, "wet_ground_amount"))
		and is_zero_approx(
			_uniform_float(first_material, "wet_ground_rain_intensity"),
		),
		"presenter clears transient shared uniforms when leaving the tree",
	)


func _assert_profile_uniforms(
		material: ShaderMaterial,
		profile: Variant,
) -> void:
	var scalar_uniforms: Dictionary = {
		"wet_ground_basin_contrast": _profile_float(profile, "basin_contrast"),
		"wet_ground_grass_floor": _profile_float(profile, "grass_wetness_floor"),
		"wet_ground_puddle_threshold": _profile_float(profile, "puddle_threshold"),
		"wet_ground_darkening": _profile_float(profile, "wet_darkening"),
		"wet_ground_desaturation": _profile_float(profile, "wet_desaturation"),
		"wet_ground_puddle_opacity": _profile_float(profile, "puddle_opacity"),
		"wet_ground_impact_cell_px": _profile_float(profile, "impact_cell_size_px"),
		"wet_ground_impact_ring_width_px": _profile_float(profile, "impact_ring_width"),
		"wet_ground_impact_lifetime_seconds": _profile_float(
			profile,
			"impact_lifetime_seconds",
		),
		"wet_ground_impact_density": _profile_float(profile, "impact_density"),
	}
	var all_scalars_match: bool = true
	for uniform_name: String in scalar_uniforms:
		all_scalars_match = all_scalars_match and is_equal_approx(
			_uniform_float(material, uniform_name),
			float(scalar_uniforms[uniform_name]),
		)
	_check(all_scalars_match, "all authored scalar uniforms publish once material exists")
	var tint_variant: Variant = material.get_shader_parameter("wet_ground_puddle_tint")
	var authored_tint: Color = profile.get("puddle_tint")
	_check(
		tint_variant is Color and (tint_variant as Color).is_equal_approx(authored_tint),
		"authored puddle tint publishes to the shared material",
	)


func _assert_static_contracts() -> void:
	var scene_source: String = FileAccess.get_file_as_string(WORLD_SCENE_PATH)
	var presenter_source: String = FileAccess.get_file_as_string(PRESENTER_SCRIPT_PATH)
	var factory_source: String = FileAccess.get_file_as_string(FACTORY_SCRIPT_PATH)
	var shader_source: String = FileAccess.get_file_as_string(GROUND_SHADER_PATH)
	_check(
		scene_source.count(PRESENTER_SCRIPT_PATH.trim_prefix("res://")) == 1
		and scene_source.count(PROFILE_RESOURCE_PATH.trim_prefix("res://")) == 1
		and scene_source.count(
			"[node name=\"GroundWetnessPresenter\" type=\"Node\"",
		) == 1,
		"world scene wires one presenter with one authored profile",
	)
	_check(
		presenter_source.contains("get_built_material_for_terrain")
		and factory_source.contains("func get_built_material_for_terrain")
		and not presenter_source.contains("_get_or_create_material_for_terrain"),
		"presenter uses only the safe existing-material factory getter",
	)
	var presenter_without_preloads: String = presenter_source.replace("preload(", "")
	_check(
		not presenter_source.contains("ShaderMaterial.new")
		and not presenter_without_preloads.contains("load(")
		and not presenter_source.contains("ResourceLoader.load")
		and not presenter_source.contains("PackedScene.instantiate")
		and not presenter_source.contains("add_child(")
		and not presenter_source.contains("get_nodes_in_group")
		and not _contains_loop_statement(presenter_source),
		"presenter creates no materials, loads, nodes, scene instances, or loops",
	)
	_check(
		shader_source.contains(
			"uniform float wet_ground_amount : hint_range(0.0, 1.0) = 0.0;",
		)
		and shader_source.contains(
			"uniform float wet_ground_rain_intensity : hint_range(0.0, 1.0) = 0.0;",
		),
		"wet-ground dynamic shader uniforms have exact dry defaults",
	)

	var wet_block: String = _source_between(
		shader_source,
		"// --- rain skin: broad wet soil, sparse puddles, analytic impacts ---",
		"\n\t\t\tif (debug_zone_mode > 0)",
	)
	_check(not wet_block.is_empty(), "wet-ground shader block is structurally bounded")
	_check(
		wet_block.contains("if (wet_ground_amount > 0.001)")
		and wet_block.find("if (wet_ground_amount > 0.001)")
		< wet_block.find("float basin_source"),
		"dry ground exits the entire wet-ground work branch early",
	)
	_check(
		wet_block.contains("world_pos")
		and wet_block.contains("soil_field")
		and wet_block.contains("shade_a")
		and wet_block.contains("top_macro")
		and wet_block.contains("path_open")
		and wet_block.contains("grass_density_visual")
		and wet_block.contains("rock_region_visual"),
		"wet mask reuses existing world-space terrain fields",
	)
	_check(
		wet_block.count("floor(") == 1
		and wet_block.contains("floor(world_pos / impact_cell)")
		and wet_block.contains("TIME / max(wet_ground_impact_lifetime_seconds"),
		"drop impacts use one analytic world cell and shader TIME",
	)
	_check(
		wet_block.contains("float impact_lod = gravel_lod *")
		and wet_block.contains("gravel_lod_fade_start_px * 0.45")
		and wet_block.contains("impact_lod > 0.004")
		and wet_block.contains("* impact_lod"),
		"subpixel impact rings reuse the existing procedural-detail LOD",
	)
	var wet_block_lower: String = wet_block.to_lower()
	_check(
		not wet_block_lower.contains("sampler")
		and not wet_block_lower.contains("texture(")
		and not wet_block_lower.contains("screen_texture")
		and not wet_block_lower.contains("hint_screen_texture")
		and not wet_block_lower.contains("render_mode")
		and not wet_block_lower.contains("pass")
		and not wet_block_lower.contains("fbm")
		and not _contains_loop_statement(wet_block),
		"wet block adds no sampler, pass, screen copy, noise field, or loop",
	)
	_check(
		not scene_source.contains("PuddleNode")
		and not scene_source.contains("RainImpactNode")
		and not scene_source.contains("DropImpactNode"),
		"world scene has no per-puddle or per-impact nodes",
	)


func _source_between(source: String, start_marker: String, end_marker: String) -> String:
	var start_index: int = source.find(start_marker)
	if start_index < 0:
		return ""
	var end_index: int = source.find(end_marker, start_index)
	if end_index < 0:
		return ""
	return source.substr(start_index, end_index - start_index)


func _contains_loop_statement(source: String) -> bool:
	var padded: String = "\n%s" % source
	return (
		padded.contains("\n\tfor ")
		or padded.contains("\n\twhile ")
		or padded.contains("\n\t\tfor ")
		or padded.contains("\n\t\twhile ")
		or source.contains("for (")
		or source.contains("while (")
	)


func _calculate_next_amount(
		presenter_script: Script,
		profile: Variant,
		current_amount: float,
		delta: float,
		precipitation_kind: int,
		precipitation_intensity: float,
) -> float:
	return float(
		presenter_script.call(
			"calculate_next_amount",
			profile,
			current_amount,
			delta,
			precipitation_kind,
			precipitation_intensity,
		),
	)


func _profile_float(profile: Variant, property_name: String) -> float:
	return float(profile.get(property_name))


func _uniform_float(material: ShaderMaterial, uniform_name: String) -> float:
	return float(material.get_shader_parameter(uniform_name))


func _finish() -> void:
	if _failures.is_empty():
		print("wet_ground_presentation_probe: ALL CHECKS PASSED")
		quit(0)
		return
	for failure: String in _failures:
		print("wet_ground_presentation_probe: FAILED %s" % failure)
	quit(1)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("wet_ground_presentation_probe: PASS %s" % description)
		return
	_failures.append(description)
	print("wet_ground_presentation_probe: FAIL %s" % description)
