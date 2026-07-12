extends SceneTree

## TEST/DEV ONLY.
##
## Produces a deterministic excavation-shape contact sheet. The first column is
## the native hard gameplay cutout, the second is the pre-M7 organic top-mask
## reference, and the third is the native hybrid visual mask. No production
## state or runtime code is changed.

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
const LEGACY_HEADER_COLOR: Color = Color(0.95, 0.68, 0.12, 1.0)
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
		"reference_commit": "18ce169",
		"columns": ["production_hard", "pre_m7_organic_reference", "production_visual"],
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
			"name": "diagonal_pair",
			"tiles": [Vector2i(7, 7), Vector2i(8, 8)],
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

	var legacy_organic_mask: PackedByteArray = _build_pre_m7_organic_visual_mask(closed_mask, dug_halo)
	var hard_preview: Image = _build_preview(hard_gameplay_mask)
	var legacy_preview: Image = _build_preview(legacy_organic_mask)
	var production_visual_preview: Image = _build_preview(production_visual_mask)

	_save_core_mask("%s/%s_production_hard_mask.png" % [OUTPUT_DIR, scenario_name], hard_gameplay_mask)
	_save_core_mask("%s/%s_pre_m7_organic_reference_mask.png" % [OUTPUT_DIR, scenario_name], legacy_organic_mask)
	_save_core_mask("%s/%s_production_visual_mask.png" % [OUTPUT_DIR, scenario_name], production_visual_mask)
	hard_preview.save_png("%s/%s_production_hard_preview.png" % [OUTPUT_DIR, scenario_name])
	legacy_preview.save_png("%s/%s_pre_m7_organic_reference_preview.png" % [OUTPUT_DIR, scenario_name])
	production_visual_preview.save_png("%s/%s_production_visual_preview.png" % [OUTPUT_DIR, scenario_name])

	var hard_metrics: Dictionary = _measure_mask(hard_gameplay_mask, closed_mask, dug_tiles, retained_tiles)
	var legacy_metrics: Dictionary = _measure_mask(legacy_organic_mask, closed_mask, dug_tiles, retained_tiles)
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
	if not bool(scenario.get("open_south", false)):
		_assert(
			float(production_visual_metrics.get("dug_fully_clear_fraction", 0.0)) > 0.999,
			"%s production visual must fully clear every interior dug source pixel" % scenario_name,
		)
	if not retained_tiles.is_empty():
		_assert(
			float(legacy_metrics.get("retained_mean_solid", 0.0)) > 0.55,
			"%s pre-M7 organic visual must preserve the retaining island" % scenario_name,
		)
		_assert(
			float(production_visual_metrics.get("retained_mean_solid", 0.0)) >= 0.55,
			"%s production visual must preserve the retaining island" % scenario_name,
		)

	print("EXCAVATION_SHAPE_COMPARE %s hard=%s pre_m7_reference=%s production_visual=%s" % [
		scenario_name,
		str(hard_metrics),
		str(legacy_metrics),
		str(production_visual_metrics),
	])
	return {
		"previews": [hard_preview, legacy_preview, production_visual_preview],
		"report": {
			"name": scenario_name,
			"dug_tile_count": dug_tiles.size(),
			"retained_tile_count": retained_tiles.size(),
			"production_hard": hard_metrics,
			"pre_m7_organic_reference": legacy_metrics,
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


func _build_pre_m7_organic_visual_mask(
	closed_mask: PackedByteArray,
	dug_halo: PackedByteArray,
) -> PackedByteArray:
	var result: PackedByteArray = closed_mask.duplicate()
	var padding_steps: int = maxi(1, ceili(2.0 / MASK_STEP_PX))
	var feather_px: float = maxf(MASK_STEP_PX * 2.0, 10.0)
	for tile_y: int in range(HALO_SIDE):
		for tile_x: int in range(HALO_SIDE):
			if dug_halo[tile_y * HALO_SIDE + tile_x] == 0:
				continue
			var tile_min: Vector2 = ORIGIN_WORLD + Vector2(tile_x, tile_y) * float(TILE_SIZE_PX)
			var tile_max: Vector2 = tile_min + Vector2.ONE * float(TILE_SIZE_PX)
			var min_x: int = maxi(0, tile_x * PIXELS_PER_TILE - padding_steps)
			var min_y: int = maxi(0, tile_y * PIXELS_PER_TILE - padding_steps)
			var max_x: int = mini(MASK_SIDE - 1, (tile_x + 1) * PIXELS_PER_TILE + padding_steps)
			var max_y: int = mini(MASK_SIDE - 1, (tile_y + 1) * PIXELS_PER_TILE + padding_steps)
			for py: int in range(min_y, max_y + 1):
				for px: int in range(min_x, max_x + 1):
					var index: int = py * MASK_SIDE + px
					var pixel_world: Vector2 = ORIGIN_WORLD + Vector2(float(px) + 0.5, float(py) + 0.5) * MASK_STEP_PX
					var clear_strength: float = _pre_m7_organic_clear_strength(
						pixel_world,
						tile_min,
						tile_max,
						feather_px,
					)
					result[index] = clampi(roundi(float(result[index]) * (1.0 - clear_strength)), 0, 255)
	return result


func _pre_m7_organic_clear_strength(
	pixel_world: Vector2,
	tile_min_world: Vector2,
	tile_max_world: Vector2,
	feather_px: float,
) -> float:
	var center: Vector2 = (tile_min_world + tile_max_world) * 0.5
	var half_extent: Vector2 = (tile_max_world - tile_min_world) * 0.5 + Vector2.ONE * (feather_px * 0.45)
	var radius: float = minf(half_extent.x, half_extent.y) * 0.46
	var q: Vector2 = (pixel_world - center).abs() - (half_extent - Vector2.ONE * radius)
	var outside: Vector2 = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0))
	var sdf: float = outside.length() + minf(maxf(q.x, q.y), 0.0) - radius
	if sdf <= -feather_px:
		return 1.0
	if sdf >= feather_px:
		return 0.0
	return 1.0 - smoothstep(-feather_px, feather_px, sdf)


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
		LEGACY_HEADER_COLOR,
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
