extends SceneTree

const FOLIAGE_WIND_SHADER: Shader = preload("res://assets/shaders/layered_tree_foliage_wind.gdshader")
const SNOW_ACCUMULATION_SHADER: Shader = preload("res://assets/shaders/layered_tree_snow_accumulation.gdshader")
const TRUNK_SEASON_SHADER: Shader = preload("res://assets/shaders/layered_tree_trunk_season.gdshader")

const TREE_DIR: String = "res://assets/sprites/flora/layered_trees/tree_01"
const OUTPUT_DIR: String = "res://artifacts/layered_tree_lighting_diagnosis"
const VIEWPORT_SIZE: Vector2i = Vector2i(900, 900)
const ROOT_POSITION: Vector2 = Vector2(450.0, 760.0)
const TREE_SCALE: float = 0.86

const COLOR_DAY: Color = Color(0.85, 0.85, 0.83)
const COLOR_DAWN: Color = Color(0.55, 0.48, 0.52)
const COLOR_DUSK: Color = Color(0.66, 0.50, 0.40)
const COLOR_NIGHT: Color = Color(0.03, 0.035, 0.05)
const COLOR_OVERCAST_TINT: Color = Color(0.66, 0.72, 0.84)
const SUN_DAY_ENERGY: float = 0.45
const SUN_COLOR_DAY: Color = Color(1.0, 0.92, 0.74)
const SUN_COLOR_LOW: Color = Color(1.0, 0.72, 0.46)
const SUN_ROTATION_DEG: float = 234.0

var _meta: Dictionary = {}
var _results: Array[Dictionary] = []
var _mask_reference: Image = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEWPORT_SIZE
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0, 0.0))
	DirAccess.open("res://").make_dir_recursive("artifacts/layered_tree_lighting_diagnosis")
	_meta = _load_json_dictionary("%s/meta.json" % TREE_DIR)
	if _meta.is_empty():
		push_error("layered_tree_lighting_diagnosis_probe: missing tree metadata")
		quit(1)
		return

	var cases: Array[Dictionary] = [
		{
			"name": "00_raw_textures_no_light",
			"use_shader": false,
			"ambient": Color.WHITE,
			"sun": false,
			"note": "Texture layers only: no tree shader, no CanvasModulate, no DirectionalLight2D.",
		},
		{
			"name": "01_runtime_shader_no_light",
			"use_shader": true,
			"ambient": Color.WHITE,
			"sun": false,
			"note": "Runtime layered shaders only, with wind frozen and season 0.",
		},
		{
			"name": "02_canvas_day_only",
			"use_shader": true,
			"ambient": COLOR_DAY,
			"sun": false,
			"note": "Daylight CanvasModulate day ambient only.",
		},
		{
			"name": "03_canvas_dawn_only",
			"use_shader": true,
			"ambient": COLOR_DAWN,
			"sun": false,
			"note": "Daylight CanvasModulate dawn ambient only.",
		},
		{
			"name": "04_canvas_dusk_only",
			"use_shader": true,
			"ambient": COLOR_DUSK,
			"sun": false,
			"note": "Daylight CanvasModulate dusk ambient only.",
		},
		{
			"name": "05_canvas_night_only",
			"use_shader": true,
			"ambient": COLOR_NIGHT,
			"sun": false,
			"note": "Daylight CanvasModulate night ambient only.",
		},
		{
			"name": "06_canvas_overcast_day_only",
			"use_shader": true,
			"ambient": COLOR_DAY * COLOR_OVERCAST_TINT,
			"sun": false,
			"note": "Day ambient multiplied by full overcast weather tint.",
		},
		{
			"name": "07_canvas_day_plus_sun",
			"use_shader": true,
			"ambient": COLOR_DAY,
			"sun": true,
			"sun_color": SUN_COLOR_DAY,
			"sun_energy": SUN_DAY_ENERGY,
			"note": "Day ambient plus runtime DirectionalLight2D sun.",
		},
		{
			"name": "08_canvas_dawn_plus_sun",
			"use_shader": true,
			"ambient": COLOR_DAWN,
			"sun": true,
			"sun_color": SUN_COLOR_LOW,
			"sun_energy": SUN_DAY_ENERGY * 0.62,
			"note": "Dawn ambient plus low warm sun.",
		},
		{
			"name": "09_raw_canvas_day_plus_sun",
			"use_shader": false,
			"ambient": COLOR_DAY,
			"sun": true,
			"sun_color": SUN_COLOR_DAY,
			"sun_energy": SUN_DAY_ENERGY,
			"note": "Raw texture layers under day ambient plus sun; isolates shader from Light2D.",
		},
	]

	var baseline: Dictionary = {}
	var rendered_cases: Array[Dictionary] = []
	for test_case: Dictionary in cases:
		var image: Image = await _render_case(test_case)
		var name: String = str(test_case.get("name", "case"))
		var path: String = "%s/%s.png" % [OUTPUT_DIR, name]
		image.save_png(path)
		rendered_cases.append({
			"case": test_case,
			"image": image,
			"name": name,
			"path": path,
		})
	if not rendered_cases.is_empty():
		_mask_reference = rendered_cases[0].get("image") as Image
		var legacy_image: Image = _make_legacy_double_multiply_image(_mask_reference)
		var legacy_name: String = "00b_before_legacy_double_multiply_simulated"
		var legacy_path: String = "%s/%s.png" % [OUTPUT_DIR, legacy_name]
		legacy_image.save_png(legacy_path)
		rendered_cases.insert(1, {
			"case": {
				"name": legacy_name,
				"note": "Simulated old shader bug: sampled tree color multiplied by itself, matching the pre-fix darkening.",
			},
			"image": legacy_image,
			"name": legacy_name,
			"path": legacy_path,
		})
	for rendered: Dictionary in rendered_cases:
		var image: Image = rendered.get("image") as Image
		var test_case: Dictionary = rendered.get("case") as Dictionary
		var name: String = str(rendered.get("name", "case"))
		var path: String = str(rendered.get("path", ""))
		var metrics: Dictionary = _measure_tree_pixels(image)
		if baseline.is_empty():
			baseline = metrics.duplicate()
		var result: Dictionary = {
			"name": name,
			"path": ProjectSettings.globalize_path(path),
			"note": str(test_case.get("note", "")),
			"avg_rgb": metrics.get("avg_rgb", []),
			"avg_luma": metrics.get("avg_luma", 0.0),
			"luma_vs_raw": _safe_ratio(float(metrics.get("avg_luma", 0.0)), float(baseline.get("avg_luma", 1.0))),
			"sampled_pixels": int(metrics.get("sampled_pixels", 0)),
		}
		_results.append(result)
		print("%s luma=%.4f raw_ratio=%.3f" % [name, float(result["avg_luma"]), float(result["luma_vs_raw"])])

	_write_report()
	_write_comparison_images(rendered_cases)
	quit(0)


func _render_case(test_case: Dictionary) -> Image:
	var world := Node2D.new()
	world.name = "ProbeWorld"
	root.add_child(world)

	var ambient: Color = test_case.get("ambient", Color.WHITE) as Color
	if not ambient.is_equal_approx(Color.WHITE):
		var canvas := CanvasModulate.new()
		canvas.name = "ProbeCanvasModulate"
		canvas.color = ambient
		world.add_child(canvas)

	if bool(test_case.get("sun", false)):
		var sun := DirectionalLight2D.new()
		sun.name = "ProbeSun"
		sun.energy = float(test_case.get("sun_energy", SUN_DAY_ENERGY))
		sun.color = test_case.get("sun_color", SUN_COLOR_DAY) as Color
		sun.rotation = deg_to_rad(SUN_ROTATION_DEG)
		sun.shadow_enabled = false
		world.add_child(sun)

	_build_tree(world, bool(test_case.get("use_shader", true)))
	for _frame: int in range(10):
		await process_frame
	var image: Image = root.get_texture().get_image()
	world.queue_free()
	await process_frame
	return image


func _build_tree(parent: Node2D, use_shader: bool) -> void:
	var frame_size := Vector2(
		float(_meta.get("frame_width", 768)),
		float(_meta.get("frame_height", 768)),
	)
	var anchor_array: Array = _meta.get("anchor", [384.0, 539.0]) as Array
	var anchor := Vector2(float(anchor_array[0]), float(anchor_array[1]))
	var center := frame_size * 0.5
	var sprite_position: Vector2 = ROOT_POSITION - (anchor - center) * TREE_SCALE

	var trunk := _make_sprite("Trunk", "%s/trunk.png" % TREE_DIR, sprite_position)
	var foliage := _make_sprite("Foliage", "%s/foliage.png" % TREE_DIR, sprite_position)
	var snow := _make_sprite("SnowOverlay", "%s/snow_overlay.png" % TREE_DIR, sprite_position)
	trunk.z_index = 0
	foliage.z_index = 1
	snow.z_index = 2
	snow.visible = false
	if use_shader:
		trunk.material = _make_trunk_material()
		foliage.material = _make_foliage_material()
		snow.material = _make_snow_material()
	parent.add_child(trunk)
	parent.add_child(foliage)
	parent.add_child(snow)


func _make_sprite(sprite_name: String, path: String, sprite_position: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = _load_png_texture(path)
	sprite.centered = true
	sprite.position = sprite_position
	sprite.scale = Vector2.ONE * TREE_SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return sprite


func _make_trunk_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TRUNK_SEASON_SHADER
	material.set_shader_parameter("snow_mask_texture", _load_png_texture("%s/snow_mask.png" % TREE_DIR))
	material.set_shader_parameter("wind_mask_texture", _load_png_texture("%s/wind_mask.png" % TREE_DIR))
	material.set_shader_parameter("wind_strength_px", 0.0)
	material.set_shader_parameter("season_amount", 0.0)
	return material


func _make_foliage_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FOLIAGE_WIND_SHADER
	material.set_shader_parameter("wind_mask_texture", _load_png_texture("%s/wind_mask.png" % TREE_DIR))
	material.set_shader_parameter("season_mask_texture", _load_png_texture("%s/season_mask.png" % TREE_DIR))
	material.set_shader_parameter("wind_strength_px", 0.0)
	material.set_shader_parameter("season_amount", 0.0)
	return material


func _make_snow_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SNOW_ACCUMULATION_SHADER
	material.set_shader_parameter("snow_mask_texture", _load_png_texture("%s/snow_mask.png" % TREE_DIR))
	material.set_shader_parameter("season_amount", 0.0)
	return material


func _measure_tree_pixels(image: Image) -> Dictionary:
	var sum := Vector3.ZERO
	var count: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if not _is_reference_tree_pixel(image, x, y):
				continue
			var color: Color = image.get_pixel(x, y)
			sum += Vector3(color.r, color.g, color.b)
			count += 1
	if count <= 0:
		return {"avg_rgb": [0.0, 0.0, 0.0], "avg_luma": 0.0, "sampled_pixels": 0}
	var inv: float = 1.0 / float(count)
	var avg := sum * inv
	var luma: float = avg.x * 0.299 + avg.y * 0.587 + avg.z * 0.114
	return {
		"avg_rgb": [_round3(avg.x), _round3(avg.y), _round3(avg.z)],
		"avg_luma": _round4(luma),
		"sampled_pixels": count,
	}


func _is_reference_tree_pixel(image: Image, x: int, y: int) -> bool:
	if _mask_reference == null:
		return false
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return false
	if x >= _mask_reference.get_width() or y >= _mask_reference.get_height():
		return false
	var mask_color: Color = _mask_reference.get_pixel(x, y)
	var mask_luma: float = mask_color.r * 0.299 + mask_color.g * 0.587 + mask_color.b * 0.114
	return mask_luma > 0.003


func _write_report() -> void:
	var lines: PackedStringArray = [
		"# Layered Tree Lighting Diagnosis",
		"",
		"All captures use the same tree asset, same position, wind frozen, season 0, and normal maps disabled.",
		"",
		"| Case | Avg luma | vs raw | Meaning |",
		"|---|---:|---:|---|",
	]
	for result: Dictionary in _results:
		lines.append(
			"| `%s` | %.4f | %.3f | %s |" % [
				str(result["name"]),
				float(result["avg_luma"]),
				float(result["luma_vs_raw"]),
				str(result["note"]).replace("|", "/"),
			]
		)
	lines.append("")
	lines.append("## Files")
	lines.append("")
	for result: Dictionary in _results:
		lines.append("- `%s`: `%s`" % [str(result["name"]), str(result["path"])])
	var report_path: String = "%s/report.md" % OUTPUT_DIR
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()

	var json_path: String = "%s/metrics.json" % OUTPUT_DIR
	var json := FileAccess.open(json_path, FileAccess.WRITE)
	json.store_string(JSON.stringify(_results, "\t"))
	json.close()


func _make_legacy_double_multiply_image(source: Image) -> Image:
	var result: Image = source.duplicate()
	for y: int in range(result.get_height()):
		for x: int in range(result.get_width()):
			if not _is_reference_tree_pixel(source, x, y):
				continue
			var color: Color = result.get_pixel(x, y)
			result.set_pixel(x, y, Color(color.r * color.r, color.g * color.g, color.b * color.b, color.a))
	return result


func _write_comparison_images(rendered_cases: Array[Dictionary]) -> void:
	var before: Image = _find_rendered_image(rendered_cases, "00b_before_legacy_double_multiply_simulated")
	var after: Image = _find_rendered_image(rendered_cases, "01_runtime_shader_no_light")
	if before != null and after != null:
		before = before.duplicate()
		after = after.duplicate()
		before.convert(Image.FORMAT_RGBA8)
		after.convert(Image.FORMAT_RGBA8)
		var comparison := Image.create(before.get_width() * 2, before.get_height(), false, Image.FORMAT_RGBA8)
		comparison.fill(Color(0.0, 0.0, 0.0, 1.0))
		comparison.blit_rect(before, Rect2i(Vector2i.ZERO, before.get_size()), Vector2i.ZERO)
		comparison.blit_rect(after, Rect2i(Vector2i.ZERO, after.get_size()), Vector2i(before.get_width(), 0))
		comparison.save_png("%s/before_after_shader_double_multiply.png" % OUTPUT_DIR)

	var ordered_names: PackedStringArray = [
		"00_raw_textures_no_light",
		"00b_before_legacy_double_multiply_simulated",
		"01_runtime_shader_no_light",
		"02_canvas_day_only",
		"07_canvas_day_plus_sun",
		"05_canvas_night_only",
	]
	var cell_size := Vector2i(300, 169)
	var grid := Image.create(cell_size.x * 3, cell_size.y * 2, false, Image.FORMAT_RGBA8)
	grid.fill(Color(0.0, 0.0, 0.0, 1.0))
	for index: int in range(ordered_names.size()):
		var image: Image = _find_rendered_image(rendered_cases, ordered_names[index])
		if image == null:
			continue
		var resized: Image = image.duplicate()
		resized.convert(Image.FORMAT_RGBA8)
		resized.resize(cell_size.x, cell_size.y, Image.INTERPOLATE_LANCZOS)
		var target := Vector2i((index % 3) * cell_size.x, (index / 3) * cell_size.y)
		grid.blit_rect(resized, Rect2i(Vector2i.ZERO, cell_size), target)
	grid.save_png("%s/diagnosis_grid.png" % OUTPUT_DIR)


func _find_rendered_image(rendered_cases: Array[Dictionary], name: String) -> Image:
	for rendered: Dictionary in rendered_cases:
		if str(rendered.get("name", "")) == name:
			return rendered.get("image") as Image
	return null


func _safe_ratio(value: float, baseline: float) -> float:
	if absf(baseline) <= 0.00001:
		return 0.0
	return _round3(value / baseline)


func _round3(value: float) -> float:
	return roundf(value * 1000.0) / 1000.0


func _round4(value: float) -> float:
	return roundf(value * 10000.0) / 10000.0


func _load_png_texture(path: String) -> Texture2D:
	if FileAccess.file_exists(path + ".import"):
		var imported: Texture2D = load(path) as Texture2D
		if imported != null:
			return imported
	var image := Image.new()
	var err: int = image.load(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("layered_tree_lighting_diagnosis_probe: cannot load %s" % path)
		return null
	return ImageTexture.create_from_image(image)


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}
