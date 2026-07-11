extends SceneTree

## TEST/DEV ONLY.
##
## Produces a deterministic excavation-shape contact sheet. The first column is
## the native hard gameplay cutout, the second is a visual-only reference
## reconstructed from commit fbedb3b, and the third is the native hybrid visual
## mask. No production state or runtime code is changed.

const OUTPUT_DIR: String = "res://artifacts/mountain_excavation_shape_compare"
const CHUNK_SIZE: int = 16
const TILE_SIZE_PX: int = 64
const HALO_RADIUS_TILES: int = 8
const HALO_SIDE: int = CHUNK_SIZE + HALO_RADIUS_TILES * 2
const PIXELS_PER_TILE: int = 8
const MASK_SIDE: int = HALO_SIDE * PIXELS_PER_TILE
const CORE_SIDE_PX: int = CHUNK_SIZE * PIXELS_PER_TILE
const ORIGIN_WORLD: Vector2 = Vector2(-512.0, -512.0)
const MASK_STEP_PX: float = float(TILE_SIZE_PX) / float(PIXELS_PER_TILE)

const ROCK_COLOR: Color = Color(0.58, 0.45, 0.31, 1.0)
const CAVE_COLOR: Color = Color(0.025, 0.018, 0.014, 1.0)
const HARD_HEADER_COLOR: Color = Color(0.86, 0.27, 0.18, 1.0)
const FBED_HEADER_COLOR: Color = Color(0.95, 0.68, 0.12, 1.0)
const PRODUCTION_VISUAL_HEADER_COLOR: Color = Color(0.20, 0.75, 0.45, 1.0)

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_clear_previous_outputs()
	var core: Object = ClassDB.instantiate("WorldCore")
	_assert(core != null, "WorldCore must be available")
	_assert(
		core != null and core.has_method("build_mountain_halo_mask"),
		"WorldCore.build_mountain_halo_mask is required; rebuild the GDExtension",
	)
	if _failed:
		_finish()
		return

	var scenarios: Array[Dictionary] = _build_scenarios()
	var report: Dictionary = {
		"probe": "mountain_excavation_shape_compare",
		"reference_commit": "fbedb3b",
		"columns": ["production_hard", "fbed_style_reference", "production_visual"],
		"pixels_per_tile": PIXELS_PER_TILE,
		"scenarios": [],
	}
	var rows: Array[Array] = []
	for scenario: Dictionary in scenarios:
		var result: Dictionary = _run_scenario(core, scenario)
		if result.is_empty():
			continue
		rows.append(result.get("previews", []) as Array)
		(report["scenarios"] as Array).append(result.get("report", {}))

	_save_contact_sheet(rows)
	var report_path: String = "%s/report.json" % OUTPUT_DIR
	var report_file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	_assert(report_file != null, "could not write %s" % report_path)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print("EXCAVATION_SHAPE_COMPARE report=%s scenarios=%d" % [report_path, rows.size()])
	_finish()


func _clear_previous_outputs() -> void:
	var directory: DirAccess = DirAccess.open(OUTPUT_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		if file_name.ends_with(".png") or file_name == "report.json":
			directory.remove(file_name)


func _build_scenarios() -> Array[Dictionary]:
	var t_room: Array[Vector2i] = []
	for y: int in range(4, 9):
		t_room.append(Vector2i(8, y))
	for x: int in range(5, 12):
		t_room.append(Vector2i(x, 8))

	var island_room: Array[Vector2i] = []
	for y: int in range(5, 11):
		for x: int in range(5, 12):
			if Vector2i(x, y) != Vector2i(8, 8):
				island_room.append(Vector2i(x, y))

	return [
		{
			"name": "one_tile_entrance",
			"tiles": [Vector2i(8, 15)],
			"open_south": true,
			"retained_tiles": [],
		},
		{
			"name": "straight_3_tile_corridor",
			"tiles": [Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8)],
			"retained_tiles": [],
		},
		{
			"name": "l_turn",
			"tiles": [
				Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 8),
				Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8),
			],
			"retained_tiles": [],
		},
		{
			"name": "t_room",
			"tiles": t_room,
			"retained_tiles": [],
		},
		{
			"name": "adjacent_retaining_island",
			"tiles": island_room,
			"retained_tiles": [Vector2i(8, 8)],
		},
	]


func _run_scenario(core: Object, scenario: Dictionary) -> Dictionary:
	var scenario_name: String = str(scenario.get("name", "unnamed"))
	var dug_tiles: Array = scenario.get("tiles", []) as Array
	var retained_tiles: Array = scenario.get("retained_tiles", []) as Array
	var closed_halo: PackedByteArray = _build_closed_halo(bool(scenario.get("open_south", false)))
	var dug_halo: PackedByteArray = _build_dug_halo(dug_tiles)
	var native_result: Dictionary = core.call(
		"build_mountain_halo_mask",
		closed_halo,
		CHUNK_SIZE,
		TILE_SIZE_PX,
		PIXELS_PER_TILE,
		ORIGIN_WORLD.x,
		ORIGIN_WORLD.y,
		dug_halo,
	) as Dictionary
	var hard_gameplay_mask: PackedByteArray = native_result.get(
		"remaining_mass_mask",
		native_result.get("mask", PackedByteArray()),
	) as PackedByteArray
	var production_visual_mask: PackedByteArray = native_result.get(
		"visual_remaining_mass_mask",
		PackedByteArray(),
	) as PackedByteArray
	var closed_mask: PackedByteArray = native_result.get(
		"closed_roof_mask",
		PackedByteArray(),
	) as PackedByteArray
	_assert(hard_gameplay_mask.size() == MASK_SIDE * MASK_SIDE, "%s hard mask shape" % scenario_name)
	_assert(
		production_visual_mask.size() == MASK_SIDE * MASK_SIDE,
		"%s production visual mask shape" % scenario_name,
	)
	_assert(closed_mask.size() == MASK_SIDE * MASK_SIDE, "%s closed mask shape" % scenario_name)
	if hard_gameplay_mask.size() != MASK_SIDE * MASK_SIDE \
			or production_visual_mask.size() != MASK_SIDE * MASK_SIDE \
			or closed_mask.size() != MASK_SIDE * MASK_SIDE:
		return {}

	var fbed_style_mask: PackedByteArray = _build_fbed_style_visual_mask(closed_mask, dug_halo)
	var hard_preview: Image = _build_preview(hard_gameplay_mask)
	var fbed_preview: Image = _build_preview(fbed_style_mask)
	var production_visual_preview: Image = _build_preview(production_visual_mask)

	_save_core_mask("%s/%s_production_hard_mask.png" % [OUTPUT_DIR, scenario_name], hard_gameplay_mask)
	_save_core_mask("%s/%s_fbed_style_reference_mask.png" % [OUTPUT_DIR, scenario_name], fbed_style_mask)
	_save_core_mask("%s/%s_production_visual_mask.png" % [OUTPUT_DIR, scenario_name], production_visual_mask)
	hard_preview.save_png("%s/%s_production_hard_preview.png" % [OUTPUT_DIR, scenario_name])
	fbed_preview.save_png("%s/%s_fbed_style_reference_preview.png" % [OUTPUT_DIR, scenario_name])
	production_visual_preview.save_png("%s/%s_production_visual_preview.png" % [OUTPUT_DIR, scenario_name])

	var hard_metrics: Dictionary = _measure_mask(hard_gameplay_mask, closed_mask, dug_tiles, retained_tiles)
	var fbed_metrics: Dictionary = _measure_mask(fbed_style_mask, closed_mask, dug_tiles, retained_tiles)
	var production_visual_metrics: Dictionary = _measure_mask(
		production_visual_mask,
		closed_mask,
		dug_tiles,
		retained_tiles,
	)
	_assert(
		float(hard_metrics.get("dug_mean_reveal", 0.0)) > 0.999,
		"%s hard gameplay mask must fully clear every dug source pixel" % scenario_name,
	)
	_assert_visual_is_bounded_by_closed(production_visual_mask, closed_mask, scenario_name)
	if not retained_tiles.is_empty():
		_assert(
			float(fbed_metrics.get("retained_mean_solid", 0.0)) > 0.55,
			"%s fbed-style visual must preserve the retaining island" % scenario_name,
		)
		_assert(
			float(production_visual_metrics.get("retained_mean_solid", 0.0)) >= 0.55,
			"%s production visual must preserve the retaining island" % scenario_name,
		)

	print("EXCAVATION_SHAPE_COMPARE %s hard=%s fbed_reference=%s production_visual=%s" % [
		scenario_name,
		str(hard_metrics),
		str(fbed_metrics),
		str(production_visual_metrics),
	])
	return {
		"previews": [hard_preview, fbed_preview, production_visual_preview],
		"report": {
			"name": scenario_name,
			"dug_tile_count": dug_tiles.size(),
			"retained_tile_count": retained_tiles.size(),
			"production_hard": hard_metrics,
			"fbed_style_reference": fbed_metrics,
			"production_visual": production_visual_metrics,
		},
	}


func _build_closed_halo(open_south: bool) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(HALO_SIDE * HALO_SIDE)
	result.fill(1)
	if open_south:
		for y: int in range(HALO_RADIUS_TILES + CHUNK_SIZE, HALO_SIDE):
			for x: int in range(HALO_SIDE):
				result[y * HALO_SIDE + x] = 0
	return result


func _build_dug_halo(dug_tiles: Array) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(HALO_SIDE * HALO_SIDE)
	for tile_variant: Variant in dug_tiles:
		var tile: Vector2i = tile_variant as Vector2i
		var halo_tile: Vector2i = tile + Vector2i.ONE * HALO_RADIUS_TILES
		result[halo_tile.y * HALO_SIDE + halo_tile.x] = 1
	return result


func _build_fbed_style_visual_mask(
	closed_mask: PackedByteArray,
	dug_halo: PackedByteArray,
) -> PackedByteArray:
	var cutout_field := PackedFloat32Array()
	cutout_field.resize(MASK_SIDE * MASK_SIDE)
	for py: int in range(MASK_SIDE):
		var tile_y: int = py / PIXELS_PER_TILE
		for px: int in range(MASK_SIDE):
			var tile_x: int = px / PIXELS_PER_TILE
			cutout_field[py * MASK_SIDE + px] = 1.0 \
					if dug_halo[tile_y * HALO_SIDE + tile_x] != 0 else 0.0
	var cutout_blurred: PackedFloat32Array = _box_blur_once(
		cutout_field,
		MASK_SIDE,
		MASK_SIDE,
		maxi(1, PIXELS_PER_TILE / 4),
	)
	var result := PackedByteArray()
	result.resize(closed_mask.size())
	for py: int in range(MASK_SIDE):
		var tile_y: int = py / PIXELS_PER_TILE
		var world_y: float = ORIGIN_WORLD.y + (float(py) + 0.5) * MASK_STEP_PX
		for px: int in range(MASK_SIDE):
			var index: int = py * MASK_SIDE + px
			var world_x: float = ORIGIN_WORLD.x + (float(px) + 0.5) * MASK_STEP_PX
			var disp_x: float = (
				(_fbm_noise((world_x + 43.0) / 360.0, (world_y - 139.0) / 360.0) - 0.5)
					* float(PIXELS_PER_TILE) * 1.15
			) + (
				(_fbm_noise((world_x - 211.0) / 170.0, (world_y + 79.0) / 170.0) - 0.5)
					* float(PIXELS_PER_TILE) * 0.46
			)
			var disp_y: float = (
				(_fbm_noise((world_x - 97.0) / 380.0, (world_y + 181.0) / 380.0) - 0.5)
					* float(PIXELS_PER_TILE) * 1.15
			) + (
				(_fbm_noise((world_x + 157.0) / 176.0, (world_y - 223.0) / 176.0) - 0.5)
					* float(PIXELS_PER_TILE) * 0.46
			)
			var cutout_value: float = _sample_bilinear(
				cutout_blurred,
				MASK_SIDE,
				MASK_SIDE,
				float(px) + disp_x * 0.32,
				float(py) + disp_y * 0.32,
			)
			var cutout_alpha: float = _smooth_float((cutout_value - 0.28) / 0.44)
			var tile_x: int = px / PIXELS_PER_TILE
			if dug_halo[tile_y * HALO_SIDE + tile_x] != 0:
				var local_x: float = fmod(float(px) + 0.5, float(PIXELS_PER_TILE))
				var local_y: float = fmod(float(py) + 0.5, float(PIXELS_PER_TILE))
				var core_min: float = float(PIXELS_PER_TILE) * 0.25
				var core_max: float = float(PIXELS_PER_TILE) * 0.75
				if local_x >= core_min and local_x <= core_max \
						and local_y >= core_min and local_y <= core_max:
					cutout_alpha = 1.0
			result[index] = clampi(roundi(float(closed_mask[index]) * (1.0 - cutout_alpha)), 0, 255)
	return result


func _box_blur_once(
	source: PackedFloat32Array,
	width: int,
	height: int,
	radius: int,
) -> PackedFloat32Array:
	var temp := PackedFloat32Array()
	temp.resize(width * height)
	var result := PackedFloat32Array()
	result.resize(width * height)
	var divisor: float = float(radius * 2 + 1)
	for y: int in range(height):
		var sum: float = 0.0
		for sample_offset: int in range(-radius, radius + 1):
			sum += source[y * width + clampi(sample_offset, 0, width - 1)]
		for x: int in range(width):
			temp[y * width + x] = sum / divisor
			var remove_x: int = clampi(x - radius, 0, width - 1)
			var add_x: int = clampi(x + radius + 1, 0, width - 1)
			sum += source[y * width + add_x] - source[y * width + remove_x]
	for x: int in range(width):
		var sum: float = 0.0
		for sample_offset: int in range(-radius, radius + 1):
			sum += temp[clampi(sample_offset, 0, height - 1) * width + x]
		for y: int in range(height):
			result[y * width + x] = sum / divisor
			var remove_y: int = clampi(y - radius, 0, height - 1)
			var add_y: int = clampi(y + radius + 1, 0, height - 1)
			sum += temp[add_y * width + x] - temp[remove_y * width + x]
	return result


func _sample_bilinear(
	values: PackedFloat32Array,
	width: int,
	height: int,
	x_value: float,
	y_value: float,
) -> float:
	var sample_x: float = clampf(x_value, 0.0, float(width - 1))
	var sample_y: float = clampf(y_value, 0.0, float(height - 1))
	var x0: int = floori(sample_x)
	var y0: int = floori(sample_y)
	var x1: int = mini(width - 1, x0 + 1)
	var y1: int = mini(height - 1, y0 + 1)
	var tx: float = sample_x - float(x0)
	var ty: float = sample_y - float(y0)
	var a: float = values[y0 * width + x0]
	var b: float = values[y0 * width + x1]
	var c: float = values[y1 * width + x0]
	var d: float = values[y1 * width + x1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _smooth_float(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _hash_float(x_value: int, y_value: int) -> float:
	var value: int = _u32(_u32(x_value) * 0x8da6b343)
	value = _u32(value ^ _u32(_u32(y_value) * 0xd8163841))
	value = _u32(value ^ (value >> 13))
	value = _u32(value * 0x6c50b47c)
	value = _u32(value ^ (value >> 16))
	return float(value & 0x00ffffff) / float(0x00ffffff)


func _u32(value: int) -> int:
	return value & 0xffffffff


func _value_noise(x_value: float, y_value: float) -> float:
	var ix: int = floori(x_value)
	var iy: int = floori(y_value)
	var fx: float = x_value - float(ix)
	var fy: float = y_value - float(iy)
	var sx: float = _smooth_float(fx)
	var sy: float = _smooth_float(fy)
	return lerpf(
		lerpf(_hash_float(ix, iy), _hash_float(ix + 1, iy), sx),
		lerpf(_hash_float(ix, iy + 1), _hash_float(ix + 1, iy + 1), sx),
		sy,
	)


func _fbm_noise(x_value: float, y_value: float) -> float:
	var value: float = 0.0
	var amplitude: float = 0.55
	var frequency: float = 1.0
	var total: float = 0.0
	for _octave: int in range(4):
		value += _value_noise(x_value * frequency, y_value * frequency) * amplitude
		total += amplitude
		amplitude *= 0.5
		frequency *= 2.03
	return value / total if total > 0.0 else 0.5


func _measure_mask(
	mask: PackedByteArray,
	closed_mask: PackedByteArray,
	dug_tiles: Array,
	retained_tiles: Array,
) -> Dictionary:
	var dug_lookup: Dictionary = {}
	for tile_variant: Variant in dug_tiles:
		dug_lookup[tile_variant as Vector2i] = true
	var retained_lookup: Dictionary = {}
	for tile_variant: Variant in retained_tiles:
		retained_lookup[tile_variant as Vector2i] = true
	var dug_reveal_sum: float = 0.0
	var dug_count: int = 0
	var dug_open_50_count: int = 0
	var dug_fully_clear_count: int = 0
	var retained_solid_sum: float = 0.0
	var retained_count: int = 0
	var threshold_open := PackedByteArray()
	threshold_open.resize(CORE_SIDE_PX * CORE_SIDE_PX)
	for core_y: int in range(CORE_SIDE_PX):
		var py: int = core_y + HALO_RADIUS_TILES * PIXELS_PER_TILE
		var tile_y: int = core_y / PIXELS_PER_TILE
		for core_x: int in range(CORE_SIDE_PX):
			var px: int = core_x + HALO_RADIUS_TILES * PIXELS_PER_TILE
			var tile_x: int = core_x / PIXELS_PER_TILE
			var index: int = py * MASK_SIDE + px
			var closed_value: float = float(closed_mask[index])
			var solid_ratio: float = float(mask[index]) / maxf(closed_value, 1.0)
			var reveal: float = clampf(1.0 - solid_ratio, 0.0, 1.0)
			var local_tile := Vector2i(tile_x, tile_y)
			if dug_lookup.has(local_tile) and closed_value >= 8.0:
				dug_reveal_sum += reveal
				dug_count += 1
				if reveal >= 0.5:
					dug_open_50_count += 1
				if int(mask[index]) == 0:
					dug_fully_clear_count += 1
			if retained_lookup.has(local_tile) and closed_value >= 8.0:
				retained_solid_sum += clampf(solid_ratio, 0.0, 1.0)
				retained_count += 1
			if reveal >= 0.5:
				threshold_open[core_y * CORE_SIDE_PX + core_x] = 1
	return {
		"dug_mean_reveal": snappedf(dug_reveal_sum / maxf(float(dug_count), 1.0), 0.0001),
		"dug_open_fraction_at_50": snappedf(float(dug_open_50_count) / maxf(float(dug_count), 1.0), 0.0001),
		"dug_fully_clear_fraction": snappedf(float(dug_fully_clear_count) / maxf(float(dug_count), 1.0), 0.0001),
		"retained_mean_solid": snappedf(retained_solid_sum / maxf(float(retained_count), 1.0), 0.0001),
		"open_components_at_50": _count_components(threshold_open, CORE_SIDE_PX),
	}


func _count_components(open_pixels: PackedByteArray, side: int) -> int:
	var visited := PackedByteArray()
	visited.resize(open_pixels.size())
	var components: int = 0
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for index: int in range(open_pixels.size()):
		if open_pixels[index] == 0 or visited[index] != 0:
			continue
		components += 1
		var queue: Array[Vector2i] = [Vector2i(index % side, index / side)]
		visited[index] = 1
		var cursor: int = 0
		while cursor < queue.size():
			var point: Vector2i = queue[cursor]
			cursor += 1
			for direction: Vector2i in directions:
				var neighbour: Vector2i = point + direction
				if neighbour.x < 0 or neighbour.y < 0 or neighbour.x >= side or neighbour.y >= side:
					continue
				var neighbour_index: int = neighbour.y * side + neighbour.x
				if open_pixels[neighbour_index] == 0 or visited[neighbour_index] != 0:
					continue
				visited[neighbour_index] = 1
				queue.append(neighbour)
	return components


func _assert_visual_is_bounded_by_closed(
	visual_mask: PackedByteArray,
	closed_mask: PackedByteArray,
	scenario_name: String,
) -> void:
	if visual_mask.size() != closed_mask.size():
		return
	for index: int in range(visual_mask.size()):
		if visual_mask[index] <= closed_mask[index]:
			continue
		_assert(
			false,
			"%s production visual exceeds closed roof at pixel %d" % [scenario_name, index],
		)
		return


func _save_core_mask(path: String, mask: PackedByteArray) -> void:
	var crop := PackedByteArray()
	crop.resize(CORE_SIDE_PX * CORE_SIDE_PX)
	for core_y: int in range(CORE_SIDE_PX):
		var source_y: int = core_y + HALO_RADIUS_TILES * PIXELS_PER_TILE
		for core_x: int in range(CORE_SIDE_PX):
			var source_x: int = core_x + HALO_RADIUS_TILES * PIXELS_PER_TILE
			crop[core_y * CORE_SIDE_PX + core_x] = mask[source_y * MASK_SIDE + source_x]
	var image: Image = Image.create_from_data(
		CORE_SIDE_PX,
		CORE_SIDE_PX,
		false,
		Image.FORMAT_L8,
		crop,
	)
	_assert(image.save_png(path) == OK, "could not save %s" % path)


func _build_preview(mask: PackedByteArray) -> Image:
	var image: Image = Image.create(CORE_SIDE_PX, CORE_SIDE_PX, false, Image.FORMAT_RGB8)
	for core_y: int in range(CORE_SIDE_PX):
		var source_y: int = core_y + HALO_RADIUS_TILES * PIXELS_PER_TILE
		for core_x: int in range(CORE_SIDE_PX):
			var source_x: int = core_x + HALO_RADIUS_TILES * PIXELS_PER_TILE
			var solid: float = float(mask[source_y * MASK_SIDE + source_x]) / 255.0
			image.set_pixel(core_x, core_y, CAVE_COLOR.lerp(ROCK_COLOR, solid))
	return image


func _save_contact_sheet(rows: Array[Array]) -> void:
	if rows.is_empty():
		return
	var margin: int = 8
	var header: int = 5
	var width: int = margin * 4 + CORE_SIDE_PX * 3
	var height: int = margin * (rows.size() + 1) + (CORE_SIDE_PX + header) * rows.size()
	var sheet: Image = Image.create(width, height, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.055, 0.047, 0.042, 1.0))
	var headers: Array[Color] = [
		HARD_HEADER_COLOR,
		FBED_HEADER_COLOR,
		PRODUCTION_VISUAL_HEADER_COLOR,
	]
	for row_index: int in range(rows.size()):
		var row: Array = rows[row_index]
		var y: int = margin + row_index * (CORE_SIDE_PX + header + margin)
		for column: int in range(mini(3, row.size())):
			var x: int = margin + column * (CORE_SIDE_PX + margin)
			sheet.fill_rect(Rect2i(x, y, CORE_SIDE_PX, header), headers[column])
			var preview: Image = row[column] as Image
			sheet.blit_rect(
				preview,
				Rect2i(Vector2i.ZERO, preview.get_size()),
				Vector2i(x, y + header),
			)
	var path: String = "%s/comparison.png" % OUTPUT_DIR
	_assert(sheet.save_png(path) == OK, "could not save %s" % path)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("mountain_excavation_shape_compare_probe: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
