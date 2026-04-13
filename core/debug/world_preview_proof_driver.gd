class_name WorldPreviewProofDriver
extends Node

## Small debug-only driver for reproducible fixed-seed ecotone proof exports.
## Activates only when launched with the user arg `codex_export_ecotone_proof`.

const ENABLE_ARG: String = "codex_export_ecotone_proof"
const VERIFY_NATIVE_TRUTH_ARG: String = "codex_verify_native_world_truth"
const VERIFY_STRUCTURE_VISIBILITY_ARG: String = "codex_verify_structure_visibility"
const EXPORT_COUNT_ARG_PREFIX: String = "codex_ecotone_proof_count="
const EXPORT_RADIUS_ARG_PREFIX: String = "codex_ecotone_radius="
const VERIFY_CHUNK_RADIUS_ARG_PREFIX: String = "codex_native_truth_chunk_radius="
const STRUCTURE_RADIUS_ARG_PREFIX: String = "codex_structure_radius="
const WorldPreviewExporterScript = preload("res://core/debug/world_preview_exporter.gd")
const MIN_ECOTONE_FACTOR: float = 0.22
const DEFAULT_EXPORT_COUNT: int = 3
const DEFAULT_RADIUS_TILES: int = 56
const DEFAULT_VERIFY_CHUNK_RADIUS: int = 2
const DEFAULT_STRUCTURE_RADIUS_TILES: int = 48
const STRUCTURE_OUTPUT_ROOT: String = "res://debug_exports/world_previews"
const STRUCTURE_SAMPLE_STEP_TILES: int = 4
const STRUCTURE_BAND_COUNT: int = 8
const STRUCTURE_BAND_SAMPLE_STRIDE_CELLS: int = 2
const STRUCTURE_NATIVE_TERRAIN_TOLERANCE: int = 0
const MAX_MISMATCH_LOGS: int = 12
const FLOAT_COMPARE_EPSILON: float = 0.01
const MIN_CENTER_DISTANCE_TILES: int = 48
const SEARCH_RADIUS_CHUNKS: int = 10

var _game_world: GameWorld = null
var _world_generator: WorldGeneratorSingleton = null
var _started: bool = false

func _ready() -> void:
	_game_world = get_parent() as GameWorld
	if not _is_enabled():
		queue_free()
		return
	if VERIFY_NATIVE_TRUTH_ARG in OS.get_cmdline_user_args():
		print("[CodexProof] native world-truth proof driver enabled")
	elif VERIFY_STRUCTURE_VISIBILITY_ARG in OS.get_cmdline_user_args():
		print("[CodexProof] authoritative structure-visibility proof driver enabled")
	else:
		print("[CodexProof] ecotone preview proof driver enabled")

func _process(_delta: float) -> void:
	if not _is_enabled() or _started:
		return
	var world_generator: WorldGeneratorSingleton = _resolve_world_generator()
	if world_generator == null or not world_generator._is_initialized or world_generator.balance == null:
		return
	_started = true
	if VERIFY_NATIVE_TRUTH_ARG in OS.get_cmdline_user_args():
		_run_native_truth_verify()
		return
	if VERIFY_STRUCTURE_VISIBILITY_ARG in OS.get_cmdline_user_args():
		_run_structure_visibility_verify()
		return
	_run_export()

func _is_enabled() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	return ENABLE_ARG in args or VERIFY_NATIVE_TRUTH_ARG in args or VERIFY_STRUCTURE_VISIBILITY_ARG in args

func _run_export() -> void:
	var world_generator: WorldGeneratorSingleton = _resolve_world_generator()
	if world_generator == null:
		print("[CodexProof] world generator unavailable")
		get_tree().quit()
		return
	var exporter: WorldPreviewExporter = WorldPreviewExporterScript.new().initialize(world_generator)
	print("[CodexProof] scanning around spawn %s (radius=%d chunks, step=%d tiles)" % [
		world_generator.spawn_tile,
		SEARCH_RADIUS_CHUNKS,
		world_generator.balance.chunk_size_tiles,
	])
	var candidates: Array = _find_hotspot_candidates()
	print("[CodexProof] hotspot candidates found: %d" % candidates.size())
	if candidates.is_empty():
		print("[CodexProof] no ecotone hotspots found for seed %d" % world_generator.world_seed)
		get_tree().quit()
		return
	var export_count: int = _get_int_arg(EXPORT_COUNT_ARG_PREFIX, DEFAULT_EXPORT_COUNT)
	var radius_tiles: int = _get_int_arg(EXPORT_RADIUS_ARG_PREFIX, DEFAULT_RADIUS_TILES)
	var exported_count: int = 0
	for candidate_variant: Variant in candidates:
		if exported_count >= export_count:
			break
		var candidate: Dictionary = candidate_variant as Dictionary
		var center_tile: Vector2i = candidate.get("tile", Vector2i.ZERO) as Vector2i
		var preview: Dictionary = exporter.build_local_preview(center_tile, radius_tiles)
		if preview.is_empty():
			continue
		var mixed_tile_count: int = int(preview.get("local_mixed_tile_count", 0))
		var ecotone_tile_count: int = int(preview.get("local_ecotone_tile_count", 0))
		var flora_tile_count: int = int(preview.get("local_flora_tile_count", 0))
		if mixed_tile_count <= 0 or flora_tile_count <= 0:
			continue
		var saved: Dictionary = exporter.save_local_preview(preview)
		if saved.is_empty():
			continue
		exported_count += 1
		print("[CodexProof] hotspot %d/%d center=%s primary=%s secondary=%s ecotone=%.2f mixed=%d ecotone_tiles=%d flora=%d" % [
			exported_count,
			export_count,
			center_tile,
			String(candidate.get("primary_biome_id", &"")),
			String(candidate.get("secondary_biome_id", &"")),
			float(candidate.get("ecotone_factor", 0.0)),
			mixed_tile_count,
			ecotone_tile_count,
			flora_tile_count,
		])
		for key: String in ["biomes", "terrain", "structures", "ecotone", "vegetation"]:
			var path: String = String(saved.get(key, ""))
			if not path.is_empty():
				print("  %s: %s" % [key, path])
	if exported_count == 0:
		print("[CodexProof] hotspot scan found candidates, but none produced mixed-border vegetation exports")
	get_tree().quit()

func _run_native_truth_verify() -> void:
	var world_generator: WorldGeneratorSingleton = _resolve_world_generator()
	if world_generator == null:
		print("[CodexProof] native truth verify aborted: world generator unavailable")
		get_tree().quit()
		return
	var native_generator: RefCounted = world_generator.get_native_chunk_generator()
	if native_generator == null:
		print("[CodexProof] native truth verify aborted: native chunk generator unavailable")
		get_tree().quit()
		return
	var chunk_radius: int = _get_int_arg(VERIFY_CHUNK_RADIUS_ARG_PREFIX, DEFAULT_VERIFY_CHUNK_RADIUS)
	var spawn_chunk: Vector2i = world_generator.tile_to_chunk(world_generator.spawn_tile)
	var compared_chunks: int = 0
	var compared_tiles: int = 0
	var payload_errors: int = 0
	var unexpected_flora_payloads: int = 0
	var terrain_mismatches: int = 0
	var biome_mismatches: int = 0
	var secondary_biome_mismatches: int = 0
	var ecotone_mismatches: int = 0
	var variation_mismatches: int = 0
	var flora_density_mismatches: int = 0
	var flora_modulation_mismatches: int = 0
	var mismatch_logs: int = 0
	var detailed_mismatch_logged: bool = false

	print("[CodexProof] verifying native world truth around spawn chunk %s (radius=%d chunks)" % [
		spawn_chunk,
		chunk_radius,
	])

	for offset_y: int in range(-chunk_radius, chunk_radius + 1):
		for offset_x: int in range(-chunk_radius, chunk_radius + 1):
			var requested_chunk: Vector2i = world_generator.offset_chunk_coord(
				spawn_chunk,
				Vector2i(offset_x, offset_y)
			)
			var canonical_chunk: Vector2i = world_generator.canonicalize_chunk_coord(requested_chunk)
			var native_data: Dictionary = world_generator.build_chunk_native_data(canonical_chunk)
			if native_data.is_empty():
				payload_errors += 1
				print("[CodexProof] empty native payload for chunk %s" % [canonical_chunk])
				continue
			if String(native_data.get("generation_source", "")) != "native_chunk_generator":
				payload_errors += 1
				print("[CodexProof] native payload for %s fell back to `%s` instead of using authoritative native chunk generation" % [
					canonical_chunk,
					String(native_data.get("generation_source", "")),
				])
				continue
			var chunk_size: int = int(native_data.get("chunk_size", world_generator.balance.chunk_size_tiles))
			var tile_count: int = chunk_size * chunk_size
			var terrain: PackedByteArray = native_data.get("terrain", PackedByteArray()) as PackedByteArray
			var biome: PackedByteArray = native_data.get("biome", PackedByteArray()) as PackedByteArray
			var secondary_biome: PackedByteArray = native_data.get("secondary_biome", PackedByteArray()) as PackedByteArray
			var variation: PackedByteArray = native_data.get("variation", PackedByteArray()) as PackedByteArray
			var ecotone_values: PackedFloat32Array = native_data.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array
			var flora_density_values: PackedFloat32Array = native_data.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array
			var flora_modulation_values: PackedFloat32Array = native_data.get("flora_modulation_values", PackedFloat32Array()) as PackedFloat32Array
			var invalid_payload: bool = terrain.size() != tile_count \
				or biome.size() != tile_count \
				or secondary_biome.size() != tile_count \
				or variation.size() != tile_count \
				or ecotone_values.size() != tile_count \
				or flora_density_values.size() != tile_count \
				or flora_modulation_values.size() != tile_count
			if invalid_payload:
				payload_errors += 1
				print("[CodexProof] invalid native payload shape for %s: terrain=%d biome=%d secondary=%d variation=%d ecotone=%d flora_density=%d flora_modulation=%d expected=%d" % [
					canonical_chunk,
					terrain.size(),
					biome.size(),
					secondary_biome.size(),
					variation.size(),
					ecotone_values.size(),
					flora_density_values.size(),
					flora_modulation_values.size(),
					tile_count,
				])
				continue
			if native_data.has("flora_placements") and not (native_data.get("flora_placements", []) as Array).is_empty():
				unexpected_flora_payloads += 1
				print("[CodexProof] unexpected native flora_placements payload for %s" % [canonical_chunk])
			var base_tile: Vector2i = native_data.get("base_tile", world_generator.chunk_to_tile_origin(canonical_chunk)) as Vector2i
			compared_chunks += 1
			for local_y: int in range(chunk_size):
				for local_x: int in range(chunk_size):
					var idx: int = local_y * chunk_size + local_x
					var tile_pos: Vector2i = world_generator.offset_tile(base_tile, Vector2i(local_x, local_y))
					var tile_data: TileGenData = world_generator.get_tile_data(tile_pos.x, tile_pos.y)
					if tile_data == null:
						payload_errors += 1
						continue
					compared_tiles += 1
					var mismatch_delta: int = _compare_native_field(
						mismatch_logs,
						"terrain",
						tile_pos,
						int(terrain[idx]),
						int(tile_data.terrain)
					)
					if mismatch_delta > 0 and not detailed_mismatch_logged:
						_print_native_chunk_payload_debug(native_data, tile_pos, base_tile, chunk_size)
						_print_script_biome_debug(world_generator, tile_pos)
						detailed_mismatch_logged = true
					terrain_mismatches += mismatch_delta
					if mismatch_delta > 0 and mismatch_logs < MAX_MISMATCH_LOGS:
						mismatch_logs += 1
					mismatch_delta = _compare_native_field(
						mismatch_logs,
						"biome",
						tile_pos,
						int(biome[idx]),
						int(tile_data.biome_palette_index)
					)
					if mismatch_delta > 0 and not detailed_mismatch_logged:
						_print_native_chunk_payload_debug(native_data, tile_pos, base_tile, chunk_size)
						_print_script_biome_debug(world_generator, tile_pos)
						detailed_mismatch_logged = true
					biome_mismatches += mismatch_delta
					if mismatch_delta > 0 and mismatch_logs < MAX_MISMATCH_LOGS:
						mismatch_logs += 1
					mismatch_delta = _compare_native_field(
						mismatch_logs,
						"secondary_biome",
						tile_pos,
						int(secondary_biome[idx]),
						int(tile_data.secondary_biome_palette_index)
					)
					if mismatch_delta > 0 and not detailed_mismatch_logged:
						_print_native_chunk_payload_debug(native_data, tile_pos, base_tile, chunk_size)
						_print_script_biome_debug(world_generator, tile_pos)
						detailed_mismatch_logged = true
					secondary_biome_mismatches += mismatch_delta
					if mismatch_delta > 0 and mismatch_logs < MAX_MISMATCH_LOGS:
						mismatch_logs += 1
					mismatch_delta = _compare_native_float_field(
						mismatch_logs,
						"ecotone",
						tile_pos,
						float(ecotone_values[idx]),
						float(tile_data.ecotone_factor)
					)
					if mismatch_delta > 0 and not detailed_mismatch_logged:
						_print_native_chunk_payload_debug(native_data, tile_pos, base_tile, chunk_size)
						_print_script_biome_debug(world_generator, tile_pos)
						detailed_mismatch_logged = true
					ecotone_mismatches += mismatch_delta
					if mismatch_delta > 0 and mismatch_logs < MAX_MISMATCH_LOGS:
						mismatch_logs += 1
					mismatch_delta = _compare_native_field(
						mismatch_logs,
						"variation",
						tile_pos,
						int(variation[idx]),
						int(tile_data.local_variation_id)
					)
					variation_mismatches += mismatch_delta
					if mismatch_delta > 0 and mismatch_logs < MAX_MISMATCH_LOGS:
						mismatch_logs += 1
					mismatch_delta = _compare_native_float_field(
						mismatch_logs,
						"flora_density",
						tile_pos,
						float(flora_density_values[idx]),
						float(tile_data.flora_density)
					)
					flora_density_mismatches += mismatch_delta
					if mismatch_delta > 0 and mismatch_logs < MAX_MISMATCH_LOGS:
						mismatch_logs += 1
					mismatch_delta = _compare_native_float_field(
						mismatch_logs,
						"flora_modulation",
						tile_pos,
						float(flora_modulation_values[idx]),
						float(tile_data.flora_modulation)
					)
					flora_modulation_mismatches += mismatch_delta
					if mismatch_delta > 0 and mismatch_logs < MAX_MISMATCH_LOGS:
						mismatch_logs += 1

	print("[CodexProof] compared_chunks=%d compared_tiles=%d payload_errors=%d unexpected_flora_payloads=%d" % [
		compared_chunks,
		compared_tiles,
		payload_errors,
		unexpected_flora_payloads,
	])
	print("[CodexProof] terrain_mismatches=%d biome_mismatches=%d secondary_biome_mismatches=%d ecotone_mismatches=%d variation_mismatches=%d flora_density_mismatches=%d flora_modulation_mismatches=%d" % [
		terrain_mismatches,
		biome_mismatches,
		secondary_biome_mismatches,
		ecotone_mismatches,
		variation_mismatches,
		flora_density_mismatches,
		flora_modulation_mismatches,
	])
	var has_failures: bool = payload_errors > 0 \
		or unexpected_flora_payloads > 0 \
		or terrain_mismatches > 0 \
		or biome_mismatches > 0 \
		or secondary_biome_mismatches > 0 \
		or ecotone_mismatches > 0 \
		or variation_mismatches > 0 \
		or flora_density_mismatches > 0 \
		or flora_modulation_mismatches > 0
	print("[CodexProof] native_truth_status=%s" % ["FAIL" if has_failures else "PASS"])
	get_tree().quit()

func _run_structure_visibility_verify() -> void:
	var world_generator: WorldGeneratorSingleton = _resolve_world_generator()
	if world_generator == null:
		print("[CodexProof] structure visibility verify aborted: world generator unavailable")
		get_tree().quit(1)
		return
	var native_generator: RefCounted = world_generator.get_native_chunk_generator()
	if native_generator == null:
		print("[CodexProof] structure visibility verify aborted: native chunk generator unavailable")
		get_tree().quit(1)
		return
	var pre_pass: RefCounted = null
	var compute_context: RefCounted = world_generator.get("_compute_context") as RefCounted
	if compute_context != null and compute_context.has_method("get_world_pre_pass"):
		pre_pass = compute_context.get_world_pre_pass()
	if pre_pass == null or not pre_pass.has_method("build_native_chunk_generator_snapshot"):
		print("[CodexProof] structure visibility verify aborted: authoritative WorldPrePass snapshot unavailable")
		get_tree().quit(1)
		return
	var snapshot: Dictionary = pre_pass.build_native_chunk_generator_snapshot() as Dictionary
	if snapshot.is_empty():
		print("[CodexProof] structure visibility verify aborted: empty authoritative pre-pass snapshot")
		get_tree().quit(1)
		return
	var exporter: WorldPreviewExporter = WorldPreviewExporterScript.new().initialize(world_generator)
	var radius_tiles: int = _get_int_arg(STRUCTURE_RADIUS_ARG_PREFIX, DEFAULT_STRUCTURE_RADIUS_TILES)
	var river_candidate: Dictionary = _find_best_river_candidate(snapshot, world_generator)
	var mountain_candidate: Dictionary = _find_best_mountain_candidate(snapshot, world_generator)
	var coverage: Dictionary = _scan_structure_coverage(snapshot, world_generator, native_generator)
	var has_failures: bool = false
	print("[CodexProof] structure visibility verify radius=%d" % [radius_tiles])
	if coverage.is_empty():
		print("[CodexProof] structure coverage scan failed: authoritative snapshot metrics unavailable")
		has_failures = true
	else:
		_print_structure_band_summary(coverage)
		_print_structure_nearest_summary(coverage)
		var sampled_tiles: int = int(coverage.get("sampled_tiles", 0))
		var native_sample_failures: int = int(coverage.get("native_sample_failures", 0))
		var terrain_mismatches: int = int(coverage.get("terrain_mismatches", 0))
		print("[CodexProof] structure coverage parity sampled_tiles=%d native_sample_failures=%d terrain_mismatches=%d tolerance=%d" % [
			sampled_tiles,
			native_sample_failures,
			terrain_mismatches,
			STRUCTURE_NATIVE_TERRAIN_TOLERANCE,
		])
		if native_sample_failures > 0 or terrain_mismatches > STRUCTURE_NATIVE_TERRAIN_TOLERANCE:
			has_failures = true
	var river_report: Dictionary = _report_structure_visibility(
		"river",
		world_generator,
		exporter,
		river_candidate,
		radius_tiles
	)
	has_failures = bool(river_report.get("has_failure", true)) or has_failures
	var mountain_report: Dictionary = _report_structure_visibility(
		"mountain",
		world_generator,
		exporter,
		mountain_candidate,
		radius_tiles
	)
	has_failures = bool(mountain_report.get("has_failure", true)) or has_failures
	var summary_artifact_path: String = _write_structure_coverage_summary_artifact(
		world_generator,
		coverage,
		river_report,
		mountain_report,
		radius_tiles
	)
	if summary_artifact_path.is_empty():
		print("[CodexProof] structure coverage summary artifact save failed")
		has_failures = true
	else:
		print("[CodexProof] structure_coverage_artifact=%s" % [summary_artifact_path])
	print("[CodexProof] structure_visibility_status=%s" % ["FAIL" if has_failures else "PASS"])
	get_tree().quit(1 if has_failures else 0)

func _find_hotspot_candidates() -> Array:
	var world_generator: WorldGeneratorSingleton = _resolve_world_generator()
	if world_generator == null or world_generator.balance == null:
		return []
	var candidates: Array = []
	var biome_palette: Array[BiomeData] = world_generator.get_biome_palette_order()
	var spawn_chunk: Vector2i = world_generator.tile_to_chunk(world_generator.spawn_tile)
	var chunk_size: int = world_generator.balance.chunk_size_tiles
	var sample_offsets: Array[Vector2i] = _build_chunk_sample_offsets(chunk_size)
	for offset_y: int in range(-SEARCH_RADIUS_CHUNKS, SEARCH_RADIUS_CHUNKS + 1):
		for offset_x: int in range(-SEARCH_RADIUS_CHUNKS, SEARCH_RADIUS_CHUNKS + 1):
			var chunk_coord: Vector2i = world_generator.offset_chunk_coord(
				spawn_chunk,
				Vector2i(offset_x, offset_y)
			)
			var chunk_origin: Vector2i = world_generator.chunk_to_tile_origin(chunk_coord)
			for sample_offset: Vector2i in sample_offsets:
				var tile_pos: Vector2i = world_generator.offset_tile(chunk_origin, sample_offset)
				var tile_data: TileGenData = world_generator.get_tile_data(tile_pos.x, tile_pos.y)
				if tile_data == null or tile_data.terrain != TileGenData.TerrainType.GROUND:
					continue
				if tile_data.secondary_biome_palette_index == tile_data.biome_palette_index:
					continue
				var ecotone_factor: float = clampf(tile_data.ecotone_factor, 0.0, 1.0)
				if ecotone_factor < MIN_ECOTONE_FACTOR:
					continue
				var secondary_biome: BiomeData = _resolve_biome_from_palette(tile_data.secondary_biome_palette_index, biome_palette)
				if secondary_biome == null:
					continue
				candidates.append({
					"tile": tile_pos,
					"primary_biome_id": tile_data.biome_id,
					"secondary_biome_id": secondary_biome.id,
					"ecotone_factor": ecotone_factor,
					"score": ecotone_factor + tile_data.flora_density * 0.14 + tile_data.local_variation_score * 0.08,
				})
	candidates.sort_custom(_sort_candidates_desc)
	return _dedupe_candidates(candidates)

func _dedupe_candidates(candidates: Array) -> Array:
	var world_generator: WorldGeneratorSingleton = _resolve_world_generator()
	var filtered: Array = []
	for candidate_variant: Variant in candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		var tile_pos: Vector2i = candidate.get("tile", Vector2i.ZERO) as Vector2i
		var is_far_enough: bool = true
		for existing_variant: Variant in filtered:
			var existing: Dictionary = existing_variant as Dictionary
			var existing_tile: Vector2i = existing.get("tile", Vector2i.ZERO) as Vector2i
			var delta_x: int = abs(world_generator.tile_wrap_delta_x(tile_pos.x, existing_tile.x))
			var delta_y: int = abs(tile_pos.y - existing_tile.y)
			if maxi(delta_x, delta_y) < MIN_CENTER_DISTANCE_TILES:
				is_far_enough = false
				break
		if is_far_enough:
			filtered.append(candidate)
	return filtered

func _sort_candidates_desc(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("score", 0.0)) > float(b.get("score", 0.0))

func _resolve_biome_from_palette(biome_index: int, biome_palette: Array[BiomeData]) -> BiomeData:
	if biome_index < 0 or biome_index >= biome_palette.size():
		return null
	return biome_palette[biome_index]

func _build_chunk_sample_offsets(chunk_size: int) -> Array[Vector2i]:
	var half: int = maxi(1, chunk_size / 2)
	var quarter: int = maxi(1, chunk_size / 4)
	var far_edge: int = maxi(0, chunk_size - quarter - 1)
	return [
		Vector2i(half, half),
		Vector2i(quarter, quarter),
		Vector2i(far_edge, quarter),
		Vector2i(quarter, far_edge),
		Vector2i(far_edge, far_edge),
	]

func _get_int_arg(prefix: String, fallback: int) -> int:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with(prefix):
			continue
		var raw_value: String = arg.trim_prefix(prefix)
		if raw_value.is_empty():
			continue
		var parsed: int = raw_value.to_int()
		if parsed > 0:
			return parsed
	return fallback

func _find_best_river_candidate(snapshot: Dictionary, world_generator: WorldGeneratorSingleton) -> Dictionary:
	var river_width_grid: PackedFloat32Array = snapshot.get("prepass_river_width_grid", PackedFloat32Array()) as PackedFloat32Array
	var floodplain_grid: PackedFloat32Array = snapshot.get("prepass_floodplain_strength_grid", PackedFloat32Array()) as PackedFloat32Array
	return _find_best_snapshot_candidate(snapshot, world_generator, river_width_grid, floodplain_grid, &"river")

func _find_best_mountain_candidate(snapshot: Dictionary, world_generator: WorldGeneratorSingleton) -> Dictionary:
	var ridge_grid: PackedFloat32Array = snapshot.get("prepass_ridge_strength_grid", PackedFloat32Array()) as PackedFloat32Array
	var mountain_grid: PackedFloat32Array = snapshot.get("prepass_mountain_mass_grid", PackedFloat32Array()) as PackedFloat32Array
	return _find_best_snapshot_candidate(snapshot, world_generator, ridge_grid, mountain_grid, &"mountain")

func _find_best_snapshot_candidate(
	snapshot: Dictionary,
	world_generator: WorldGeneratorSingleton,
	primary_grid: PackedFloat32Array,
	secondary_grid: PackedFloat32Array,
	kind: StringName
) -> Dictionary:
	var grid_width: int = int(snapshot.get("prepass_grid_width", 0))
	var grid_height: int = int(snapshot.get("prepass_grid_height", 0))
	if grid_width <= 0 or grid_height <= 0:
		return {}
	var expected_size: int = grid_width * grid_height
	if primary_grid.size() != expected_size or secondary_grid.size() != expected_size:
		return {}
	var best_candidate: Dictionary = {}
	var best_score: float = -INF
	for grid_y: int in range(grid_height):
		for grid_x: int in range(grid_width):
			var index: int = grid_y * grid_width + grid_x
			var primary_value: float = float(primary_grid[index])
			var secondary_value: float = float(secondary_grid[index])
			if kind == &"river":
				if primary_value <= FLOAT_COMPARE_EPSILON:
					continue
			elif primary_value <= FLOAT_COMPARE_EPSILON and secondary_value <= FLOAT_COMPARE_EPSILON:
				continue
			var world_pos: Vector2i = _prepass_grid_to_world_tile(snapshot, world_generator, grid_x, grid_y)
			if _distance_from_spawn_sq(world_generator, world_pos) <= _land_guarantee_radius_sq(world_generator):
				continue
			var score: float = primary_value * 1.15 + secondary_value * 0.75
			if score <= best_score:
				continue
			best_score = score
			best_candidate = {
				"kind": kind,
				"grid_pos": Vector2i(grid_x, grid_y),
				"world_pos": world_pos,
				"primary_value": primary_value,
				"secondary_value": secondary_value,
				"score": score,
			}
	return best_candidate

func _prepass_grid_to_world_tile(
	snapshot: Dictionary,
	world_generator: WorldGeneratorSingleton,
	grid_x: int,
	grid_y: int
) -> Vector2i:
	var grid_width: int = int(snapshot.get("prepass_grid_width", 1))
	var grid_height: int = int(snapshot.get("prepass_grid_height", 1))
	var wrap_width: int = world_generator.get_world_wrap_width_tiles() if world_generator.has_method("get_world_wrap_width_tiles") else world_generator.balance.world_wrap_width_tiles
	var min_y: int = int(snapshot.get("prepass_min_y", 0))
	var max_y: int = int(snapshot.get("prepass_max_y", min_y + 1))
	var y_span_tiles: int = maxi(1, max_y - min_y)
	var world_x: int = int(floor(float(grid_x) * float(wrap_width) / float(maxi(1, grid_width))))
	var world_y: int = min_y + int(floor(float(grid_y) * float(y_span_tiles) / float(maxi(1, grid_height))))
	return world_generator.canonicalize_tile(Vector2i(world_x, world_y))

func _distance_from_spawn_sq(world_generator: WorldGeneratorSingleton, tile_pos: Vector2i) -> float:
	var spawn_tile: Vector2i = world_generator.spawn_tile
	var dx: float = float(world_generator.tile_wrap_delta_x(tile_pos.x, spawn_tile.x))
	var dy: float = float(tile_pos.y - spawn_tile.y)
	return dx * dx + dy * dy

func _land_guarantee_radius_sq(world_generator: WorldGeneratorSingleton) -> float:
	if world_generator == null or world_generator.balance == null:
		return 0.0
	var radius: float = float(world_generator.balance.land_guarantee_radius)
	return radius * radius

func _is_authoritative_river_context(structure_context: WorldStructureContext) -> bool:
	return structure_context != null \
		and (structure_context.river_strength >= 0.12 or structure_context.floodplain_strength >= 0.18)

func _is_authoritative_mountain_context(structure_context: WorldStructureContext) -> bool:
	return structure_context != null \
		and (structure_context.ridge_strength >= 0.20 or structure_context.mountain_mass >= 0.18)

func _is_authoritative_river_cell(river_width: float, floodplain_strength: float) -> bool:
	return river_width > FLOAT_COMPARE_EPSILON or floodplain_strength > FLOAT_COMPARE_EPSILON

func _is_authoritative_mountain_cell(ridge_strength: float, mountain_mass: float) -> bool:
	return ridge_strength > FLOAT_COMPARE_EPSILON or mountain_mass > FLOAT_COMPARE_EPSILON

func _resolve_structure_band_index(grid_y: int, grid_height: int, band_count: int = STRUCTURE_BAND_COUNT) -> int:
	if grid_height <= 0 or band_count <= 1:
		return 0
	return clampi(
		int(floor(float(grid_y) * float(band_count) / float(grid_height))),
		0,
		band_count - 1
	)

func _resolve_structure_band_zone_label(band_index: int, band_count: int) -> String:
	if band_count <= 0:
		return "all"
	var center_fraction: float = (float(band_index) + 0.5) / float(band_count)
	return "central_50" if center_fraction >= 0.25 and center_fraction <= 0.75 else "extreme_25"

func _resolve_structure_band_world_y_range(snapshot: Dictionary, band_index: int, band_count: int) -> Vector2i:
	var min_y: int = int(snapshot.get("prepass_min_y", 0))
	var max_y: int = int(snapshot.get("prepass_max_y", min_y + 1))
	var y_span_tiles: int = maxi(1, max_y - min_y)
	var band_start: int = int(floor(float(band_index) * float(y_span_tiles) / float(maxi(1, band_count))))
	var band_end_offset: int = int(floor(float(band_index + 1) * float(y_span_tiles) / float(maxi(1, band_count)))) - 1
	band_end_offset = clampi(band_end_offset, band_start, y_span_tiles - 1)
	return Vector2i(min_y + band_start, min_y + band_end_offset)

func _prepass_grid_cell_center_to_world_tile(
	snapshot: Dictionary,
	world_generator: WorldGeneratorSingleton,
	grid_x: int,
	grid_y: int
) -> Vector2i:
	var span_x: float = maxf(1.0, float(snapshot.get("prepass_grid_span_x", 1.0)))
	var span_y: float = maxf(1.0, float(snapshot.get("prepass_grid_span_y", 1.0)))
	var min_y: int = int(snapshot.get("prepass_min_y", 0))
	var world_x: int = int(floor((float(grid_x) + 0.5) * span_x))
	var world_y: int = min_y + int(floor((float(grid_y) + 0.5) * span_y))
	return world_generator.canonicalize_tile(Vector2i(world_x, world_y))

func _update_nearest_hit(nearest_hits: Dictionary, key: String, distance_sq: float, tile_pos: Vector2i) -> void:
	var current_best: Dictionary = nearest_hits.get(key, {}) as Dictionary
	var best_distance_sq: float = float(current_best.get("distance_sq", INF))
	if distance_sq >= best_distance_sq:
		return
	nearest_hits[key] = {
		"distance_sq": distance_sq,
		"distance_tiles": sqrt(distance_sq),
		"tile": tile_pos,
	}

func _format_nearest_hit(nearest_hits: Dictionary, key: String) -> String:
	if not nearest_hits.has(key):
		return "none"
	var entry: Dictionary = nearest_hits.get(key, {}) as Dictionary
	var tile_pos: Vector2i = entry.get("tile", Vector2i.ZERO) as Vector2i
	return "%.1f tiles @ %s" % [
		float(entry.get("distance_tiles", 0.0)),
		tile_pos,
	]

func _scan_structure_coverage(
	snapshot: Dictionary,
	world_generator: WorldGeneratorSingleton,
	native_generator: RefCounted
) -> Dictionary:
	var grid_width: int = int(snapshot.get("prepass_grid_width", 0))
	var grid_height: int = int(snapshot.get("prepass_grid_height", 0))
	if grid_width <= 0 or grid_height <= 0:
		return {}
	var expected_size: int = grid_width * grid_height
	var river_width_grid: PackedFloat32Array = snapshot.get("prepass_river_width_grid", PackedFloat32Array()) as PackedFloat32Array
	var floodplain_grid: PackedFloat32Array = snapshot.get("prepass_floodplain_strength_grid", PackedFloat32Array()) as PackedFloat32Array
	var ridge_grid: PackedFloat32Array = snapshot.get("prepass_ridge_strength_grid", PackedFloat32Array()) as PackedFloat32Array
	var mountain_grid: PackedFloat32Array = snapshot.get("prepass_mountain_mass_grid", PackedFloat32Array()) as PackedFloat32Array
	if river_width_grid.size() != expected_size \
		or floodplain_grid.size() != expected_size \
		or ridge_grid.size() != expected_size \
		or mountain_grid.size() != expected_size:
		return {}
	var band_stats: Array = []
	for band_index: int in range(STRUCTURE_BAND_COUNT):
		var band_y_range: Vector2i = _resolve_structure_band_world_y_range(snapshot, band_index, STRUCTURE_BAND_COUNT)
		band_stats.append({
			"band_index": band_index,
			"zone": _resolve_structure_band_zone_label(band_index, STRUCTURE_BAND_COUNT),
			"min_y": band_y_range.x,
			"max_y": band_y_range.y,
			"authoritative_river_cells": 0,
			"authoritative_mountain_cells": 0,
			"sampled_tiles": 0,
			"sampled_authoritative_river_tiles": 0,
			"sampled_authoritative_mountain_tiles": 0,
			"visible_river_tiles": 0,
			"visible_mountain_tiles": 0,
			"script_water_tiles": 0,
			"script_bank_tiles": 0,
			"script_rock_tiles": 0,
			"native_water_tiles": 0,
			"native_bank_tiles": 0,
			"native_rock_tiles": 0,
			"native_sample_failures": 0,
			"terrain_mismatches": 0,
		})
	var nearest_hits: Dictionary = {}
	var land_guarantee_radius_sq: float = _land_guarantee_radius_sq(world_generator)
	var total_authoritative_river_cells: int = 0
	var total_authoritative_mountain_cells: int = 0
	var total_sampled_tiles: int = 0
	var total_sampled_authoritative_river_tiles: int = 0
	var total_sampled_authoritative_mountain_tiles: int = 0
	var total_visible_river_tiles: int = 0
	var total_visible_mountain_tiles: int = 0
	var total_script_water_tiles: int = 0
	var total_script_bank_tiles: int = 0
	var total_script_rock_tiles: int = 0
	var total_native_water_tiles: int = 0
	var total_native_bank_tiles: int = 0
	var total_native_rock_tiles: int = 0
	var total_native_sample_failures: int = 0
	var total_terrain_mismatches: int = 0
	for grid_y: int in range(grid_height):
		for grid_x: int in range(grid_width):
			var band_index: int = _resolve_structure_band_index(grid_y, grid_height)
			var band: Dictionary = band_stats[band_index] as Dictionary
			var index: int = grid_y * grid_width + grid_x
			var center_tile: Vector2i = _prepass_grid_cell_center_to_world_tile(snapshot, world_generator, grid_x, grid_y)
			var distance_sq: float = _distance_from_spawn_sq(world_generator, center_tile)
			if distance_sq <= land_guarantee_radius_sq:
				continue
			var river_width: float = float(river_width_grid[index])
			var floodplain_strength: float = float(floodplain_grid[index])
			var ridge_strength: float = float(ridge_grid[index])
			var mountain_mass: float = float(mountain_grid[index])
			if _is_authoritative_river_cell(river_width, floodplain_strength):
				band["authoritative_river_cells"] = int(band.get("authoritative_river_cells", 0)) + 1
				total_authoritative_river_cells += 1
				_update_nearest_hit(nearest_hits, "authoritative_river", distance_sq, center_tile)
			if _is_authoritative_mountain_cell(ridge_strength, mountain_mass):
				band["authoritative_mountain_cells"] = int(band.get("authoritative_mountain_cells", 0)) + 1
				total_authoritative_mountain_cells += 1
				_update_nearest_hit(nearest_hits, "authoritative_mountain", distance_sq, center_tile)
			if grid_x % STRUCTURE_BAND_SAMPLE_STRIDE_CELLS != 0 or grid_y % STRUCTURE_BAND_SAMPLE_STRIDE_CELLS != 0:
				band_stats[band_index] = band
				continue
			band["sampled_tiles"] = int(band.get("sampled_tiles", 0)) + 1
			total_sampled_tiles += 1
			var channels: WorldChannels = world_generator.sample_world_channels(center_tile)
			var structure_context: WorldStructureContext = world_generator.sample_structure_context(center_tile, channels)
			if structure_context == null:
				band_stats[band_index] = band
				continue
			var script_terrain: int = int(world_generator.get_terrain_type_fast(center_tile))
			var is_authoritative_river: bool = _is_authoritative_river_context(structure_context)
			var is_authoritative_mountain: bool = _is_authoritative_mountain_context(structure_context)
			if is_authoritative_river:
				band["sampled_authoritative_river_tiles"] = int(band.get("sampled_authoritative_river_tiles", 0)) + 1
				total_sampled_authoritative_river_tiles += 1
			if is_authoritative_mountain:
				band["sampled_authoritative_mountain_tiles"] = int(band.get("sampled_authoritative_mountain_tiles", 0)) + 1
				total_sampled_authoritative_mountain_tiles += 1
			if script_terrain == TileGenData.TerrainType.WATER:
				band["script_water_tiles"] = int(band.get("script_water_tiles", 0)) + 1
				total_script_water_tiles += 1
				_update_nearest_hit(nearest_hits, "visible_water", distance_sq, center_tile)
			elif script_terrain == TileGenData.TerrainType.SAND:
				band["script_bank_tiles"] = int(band.get("script_bank_tiles", 0)) + 1
				total_script_bank_tiles += 1
				_update_nearest_hit(nearest_hits, "visible_bank", distance_sq, center_tile)
			elif script_terrain == TileGenData.TerrainType.ROCK:
				band["script_rock_tiles"] = int(band.get("script_rock_tiles", 0)) + 1
				total_script_rock_tiles += 1
				_update_nearest_hit(nearest_hits, "visible_rock", distance_sq, center_tile)
			if is_authoritative_river and (
				script_terrain == TileGenData.TerrainType.WATER or script_terrain == TileGenData.TerrainType.SAND
			):
				band["visible_river_tiles"] = int(band.get("visible_river_tiles", 0)) + 1
				total_visible_river_tiles += 1
				_update_nearest_hit(nearest_hits, "visible_river", distance_sq, center_tile)
			if is_authoritative_mountain and script_terrain == TileGenData.TerrainType.ROCK:
				band["visible_mountain_tiles"] = int(band.get("visible_mountain_tiles", 0)) + 1
				total_visible_mountain_tiles += 1
				_update_nearest_hit(nearest_hits, "visible_mountain", distance_sq, center_tile)
			var native_tile: Dictionary = native_generator.sample_tile(center_tile, world_generator.spawn_tile) as Dictionary
			if native_tile.is_empty():
				band["native_sample_failures"] = int(band.get("native_sample_failures", 0)) + 1
				total_native_sample_failures += 1
				if total_native_sample_failures <= MAX_MISMATCH_LOGS:
					print("[CodexProof] native structure coverage sample failed at %s" % [center_tile])
				band_stats[band_index] = band
				continue
			var native_terrain: int = int(native_tile.get("terrain", -1))
			if native_terrain == TileGenData.TerrainType.WATER:
				band["native_water_tiles"] = int(band.get("native_water_tiles", 0)) + 1
				total_native_water_tiles += 1
			elif native_terrain == TileGenData.TerrainType.SAND:
				band["native_bank_tiles"] = int(band.get("native_bank_tiles", 0)) + 1
				total_native_bank_tiles += 1
			elif native_terrain == TileGenData.TerrainType.ROCK:
				band["native_rock_tiles"] = int(band.get("native_rock_tiles", 0)) + 1
				total_native_rock_tiles += 1
			if native_terrain != script_terrain:
				band["terrain_mismatches"] = int(band.get("terrain_mismatches", 0)) + 1
				total_terrain_mismatches += 1
				if total_terrain_mismatches <= MAX_MISMATCH_LOGS:
					print("[CodexProof] structure coverage terrain mismatch at %s script=%d native=%d band=%d" % [
						center_tile,
						script_terrain,
						native_terrain,
						band_index,
					])
			band_stats[band_index] = band
	return {
		"band_count": STRUCTURE_BAND_COUNT,
		"sample_stride_cells": STRUCTURE_BAND_SAMPLE_STRIDE_CELLS,
		"authoritative_river_cells": total_authoritative_river_cells,
		"authoritative_mountain_cells": total_authoritative_mountain_cells,
		"sampled_tiles": total_sampled_tiles,
		"sampled_authoritative_river_tiles": total_sampled_authoritative_river_tiles,
		"sampled_authoritative_mountain_tiles": total_sampled_authoritative_mountain_tiles,
		"visible_river_tiles": total_visible_river_tiles,
		"visible_mountain_tiles": total_visible_mountain_tiles,
		"script_water_tiles": total_script_water_tiles,
		"script_bank_tiles": total_script_bank_tiles,
		"script_rock_tiles": total_script_rock_tiles,
		"native_water_tiles": total_native_water_tiles,
		"native_bank_tiles": total_native_bank_tiles,
		"native_rock_tiles": total_native_rock_tiles,
		"native_sample_failures": total_native_sample_failures,
		"terrain_mismatches": total_terrain_mismatches,
		"bands": band_stats,
		"nearest_hits": nearest_hits,
	}

func _print_structure_band_summary(coverage: Dictionary) -> void:
	if coverage.is_empty():
		return
	var band_stats: Array = coverage.get("bands", []) as Array
	print("[CodexProof] structure coverage band table (auth_*_cells = exact pre-pass cells, sampled_* = sparse tile centers, band_count=%d, stride=%d cells)" % [
		int(coverage.get("band_count", 0)),
		int(coverage.get("sample_stride_cells", 0)),
	])
	print("[CodexProof] band|zone|y_range|auth_river_cells|auth_mountain_cells|sampled_tiles|auth_river_samples|auth_mountain_samples|visible_river_samples|visible_mountain_samples|script_water|script_sand|script_rock|native_water|native_sand|native_rock|native_failures|terrain_mismatches")
	for band_variant: Variant in band_stats:
		var band: Dictionary = band_variant as Dictionary
		print("[CodexProof] %d|%s|%d..%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [
			int(band.get("band_index", 0)),
			String(band.get("zone", "")),
			int(band.get("min_y", 0)),
			int(band.get("max_y", 0)),
			int(band.get("authoritative_river_cells", 0)),
			int(band.get("authoritative_mountain_cells", 0)),
			int(band.get("sampled_tiles", 0)),
			int(band.get("sampled_authoritative_river_tiles", 0)),
			int(band.get("sampled_authoritative_mountain_tiles", 0)),
			int(band.get("visible_river_tiles", 0)),
			int(band.get("visible_mountain_tiles", 0)),
			int(band.get("script_water_tiles", 0)),
			int(band.get("script_bank_tiles", 0)),
			int(band.get("script_rock_tiles", 0)),
			int(band.get("native_water_tiles", 0)),
			int(band.get("native_bank_tiles", 0)),
			int(band.get("native_rock_tiles", 0)),
			int(band.get("native_sample_failures", 0)),
			int(band.get("terrain_mismatches", 0)),
		])

func _print_structure_nearest_summary(coverage: Dictionary) -> void:
	if coverage.is_empty():
		return
	var nearest_hits: Dictionary = coverage.get("nearest_hits", {}) as Dictionary
	for label: String in [
		"authoritative_river",
		"authoritative_mountain",
		"visible_river",
		"visible_mountain",
		"visible_water",
		"visible_bank",
		"visible_rock",
	]:
		print("[CodexProof] nearest_%s=%s" % [label, _format_nearest_hit(nearest_hits, label)])

func _append_structure_report_lines(lines: PackedStringArray, kind: String, report: Dictionary) -> PackedStringArray:
	var candidate: Dictionary = report.get("candidate", {}) as Dictionary
	var metrics: Dictionary = report.get("metrics", {}) as Dictionary
	var saved: Dictionary = report.get("saved", {}) as Dictionary
	lines.append("%s_failure=%s" % [kind, str(bool(report.get("has_failure", true)))])
	lines.append("%s_center=%s" % [kind, str(report.get("center_tile", Vector2i.ZERO))])
	lines.append("%s_grid=%s" % [kind, str(candidate.get("grid_pos", Vector2i.ZERO))])
	lines.append("%s_primary=%.3f" % [kind, float(candidate.get("primary_value", 0.0))])
	lines.append("%s_secondary=%.3f" % [kind, float(candidate.get("secondary_value", 0.0))])
	lines.append("%s_score=%.3f" % [kind, float(candidate.get("score", 0.0))])
	lines.append("%s_authoritative_tiles=%d" % [kind, int(metrics.get("%s_authoritative_tiles" % kind, 0))])
	lines.append("%s_visible_tiles=%d" % [kind, int(metrics.get("%s_visible_tiles" % kind, 0))])
	for preview_key: String in ["biomes", "terrain", "structures", "ecotone", "vegetation"]:
		var path: String = String(saved.get(preview_key, ""))
		if not path.is_empty():
			lines.append("%s_%s=%s" % [kind, preview_key, path])
	return lines

func _write_structure_coverage_summary_artifact(
	world_generator: WorldGeneratorSingleton,
	coverage: Dictionary,
	river_report: Dictionary,
	mountain_report: Dictionary,
	radius_tiles: int
) -> String:
	if world_generator == null or coverage.is_empty():
		return ""
	var output_dir: String = ProjectSettings.globalize_path(STRUCTURE_OUTPUT_ROOT)
	var dir_result: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	if dir_result != OK and not DirAccess.dir_exists_absolute(output_dir):
		return ""
	var timestamp: int = Time.get_unix_time_from_system()
	var artifact_path: String = output_dir.path_join("structure_coverage_seed%d_%d.txt" % [
		world_generator.world_seed,
		timestamp,
	])
	var nearest_hits: Dictionary = coverage.get("nearest_hits", {}) as Dictionary
	var lines := PackedStringArray()
	lines.append("# Structure coverage proof")
	lines.append("seed=%d" % [world_generator.world_seed])
	lines.append("radius_tiles=%d" % [radius_tiles])
	lines.append("band_count=%d" % [int(coverage.get("band_count", 0))])
	lines.append("sample_stride_cells=%d" % [int(coverage.get("sample_stride_cells", 0))])
	lines.append("sampled_tiles=%d" % [int(coverage.get("sampled_tiles", 0))])
	lines.append("authoritative_river_cells=%d" % [int(coverage.get("authoritative_river_cells", 0))])
	lines.append("authoritative_mountain_cells=%d" % [int(coverage.get("authoritative_mountain_cells", 0))])
	lines.append("sampled_authoritative_river_tiles=%d" % [int(coverage.get("sampled_authoritative_river_tiles", 0))])
	lines.append("sampled_authoritative_mountain_tiles=%d" % [int(coverage.get("sampled_authoritative_mountain_tiles", 0))])
	lines.append("visible_river_tiles=%d" % [int(coverage.get("visible_river_tiles", 0))])
	lines.append("visible_mountain_tiles=%d" % [int(coverage.get("visible_mountain_tiles", 0))])
	lines.append("script_water_tiles=%d" % [int(coverage.get("script_water_tiles", 0))])
	lines.append("script_bank_tiles=%d" % [int(coverage.get("script_bank_tiles", 0))])
	lines.append("script_rock_tiles=%d" % [int(coverage.get("script_rock_tiles", 0))])
	lines.append("native_water_tiles=%d" % [int(coverage.get("native_water_tiles", 0))])
	lines.append("native_bank_tiles=%d" % [int(coverage.get("native_bank_tiles", 0))])
	lines.append("native_rock_tiles=%d" % [int(coverage.get("native_rock_tiles", 0))])
	lines.append("native_sample_failures=%d" % [int(coverage.get("native_sample_failures", 0))])
	lines.append("terrain_mismatches=%d" % [int(coverage.get("terrain_mismatches", 0))])
	lines.append("native_terrain_tolerance=%d" % [STRUCTURE_NATIVE_TERRAIN_TOLERANCE])
	lines.append("")
	lines.append("## Nearest distances")
	for label: String in [
		"authoritative_river",
		"authoritative_mountain",
		"visible_river",
		"visible_mountain",
		"visible_water",
		"visible_bank",
		"visible_rock",
	]:
		lines.append("%s=%s" % [label, _format_nearest_hit(nearest_hits, label)])
	lines.append("")
	lines.append("## Candidate windows")
	lines = _append_structure_report_lines(lines, "river", river_report)
	lines.append("")
	lines = _append_structure_report_lines(lines, "mountain", mountain_report)
	lines.append("")
	lines.append("## Band table")
	lines.append("band|zone|y_range|auth_river_cells|auth_mountain_cells|sampled_tiles|auth_river_samples|auth_mountain_samples|visible_river_samples|visible_mountain_samples|script_water|script_sand|script_rock|native_water|native_sand|native_rock|native_failures|terrain_mismatches")
	for band_variant: Variant in coverage.get("bands", []) as Array:
		var band: Dictionary = band_variant as Dictionary
		lines.append("%d|%s|%d..%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [
			int(band.get("band_index", 0)),
			String(band.get("zone", "")),
			int(band.get("min_y", 0)),
			int(band.get("max_y", 0)),
			int(band.get("authoritative_river_cells", 0)),
			int(band.get("authoritative_mountain_cells", 0)),
			int(band.get("sampled_tiles", 0)),
			int(band.get("sampled_authoritative_river_tiles", 0)),
			int(band.get("sampled_authoritative_mountain_tiles", 0)),
			int(band.get("visible_river_tiles", 0)),
			int(band.get("visible_mountain_tiles", 0)),
			int(band.get("script_water_tiles", 0)),
			int(band.get("script_bank_tiles", 0)),
			int(band.get("script_rock_tiles", 0)),
			int(band.get("native_water_tiles", 0)),
			int(band.get("native_bank_tiles", 0)),
			int(band.get("native_rock_tiles", 0)),
			int(band.get("native_sample_failures", 0)),
			int(band.get("terrain_mismatches", 0)),
		])
	var file: FileAccess = FileAccess.open(artifact_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return artifact_path

func _report_structure_visibility(
	kind: StringName,
	world_generator: WorldGeneratorSingleton,
	exporter: WorldPreviewExporter,
	candidate: Dictionary,
	radius_tiles: int
) -> Dictionary:
	if candidate.is_empty():
		print("[CodexProof] %s candidate missing in authoritative pre-pass snapshot" % [kind])
		return {
			"kind": String(kind),
			"has_failure": true,
			"candidate": {},
			"metrics": {},
			"saved": {},
			"center_tile": Vector2i.ZERO,
		}
	var center_tile: Vector2i = candidate.get("world_pos", Vector2i.ZERO) as Vector2i
	print("[CodexProof] measuring %s candidate window around %s" % [kind, center_tile])
	var metrics: Dictionary = _measure_structure_visibility_window(world_generator, center_tile, radius_tiles)
	var primary_label: String = "river_width" if kind == &"river" else "ridge_strength"
	var secondary_label: String = "floodplain_strength" if kind == &"river" else "mountain_mass"
	print("[CodexProof] %s candidate center=%s grid=%s %s=%.3f %s=%.3f score=%.3f" % [
		kind,
		center_tile,
		candidate.get("grid_pos", Vector2i.ZERO),
		primary_label,
		float(candidate.get("primary_value", 0.0)),
		secondary_label,
		float(candidate.get("secondary_value", 0.0)),
		float(candidate.get("score", 0.0)),
	])
	print("[CodexProof] %s metrics authoritative_tiles=%d visible_tiles=%d water=%d bank=%d rock=%d max_river_strength=%.3f max_floodplain=%.3f max_ridge=%.3f max_mass=%.3f" % [
		kind,
		int(metrics.get("%s_authoritative_tiles" % kind, 0)),
		int(metrics.get("%s_visible_tiles" % kind, 0)),
		int(metrics.get("water_tiles", 0)),
		int(metrics.get("bank_tiles", 0)),
		int(metrics.get("rock_tiles", 0)),
		float(metrics.get("max_river_strength", 0.0)),
		float(metrics.get("max_floodplain_strength", 0.0)),
		float(metrics.get("max_ridge_strength", 0.0)),
		float(metrics.get("max_mountain_mass", 0.0)),
	])
	var preview_radius: int = mini(radius_tiles, 24)
	print("[CodexProof] exporting %s proof preview around %s (radius=%d)" % [kind, center_tile, preview_radius])
	var preview: Dictionary = exporter.build_local_preview(center_tile, preview_radius)
	var saved: Dictionary = exporter.save_local_preview(preview) if not preview.is_empty() else {}
	if saved.is_empty():
		print("[CodexProof] %s preview export failed for %s" % [kind, center_tile])
	else:
		for key: String in ["biomes", "terrain", "structures", "ecotone", "vegetation"]:
			var path: String = String(saved.get(key, ""))
			if not path.is_empty():
				print("  %s_%s: %s" % [kind, key, path])
	var authoritative_key: String = "%s_authoritative_tiles" % kind
	var visible_key: String = "%s_visible_tiles" % kind
	var authoritative_tiles: int = int(metrics.get(authoritative_key, 0))
	var visible_tiles: int = int(metrics.get(visible_key, 0))
	return {
		"kind": String(kind),
		"has_failure": authoritative_tiles <= 0 or visible_tiles <= 0,
		"candidate": candidate.duplicate(true),
		"metrics": metrics.duplicate(true),
		"saved": saved.duplicate(true),
		"center_tile": center_tile,
	}

func _measure_structure_visibility_window(
	world_generator: WorldGeneratorSingleton,
	center_tile: Vector2i,
	radius_tiles: int
) -> Dictionary:
	var river_authoritative_tiles: int = 0
	var river_visible_tiles: int = 0
	var mountain_authoritative_tiles: int = 0
	var mountain_visible_tiles: int = 0
	var water_tiles: int = 0
	var bank_tiles: int = 0
	var rock_tiles: int = 0
	var max_river_strength: float = 0.0
	var max_floodplain_strength: float = 0.0
	var max_ridge_strength: float = 0.0
	var max_mountain_mass: float = 0.0
	var land_guarantee_radius_sq: float = _land_guarantee_radius_sq(world_generator)
	for offset_y: int in range(-radius_tiles, radius_tiles + 1, STRUCTURE_SAMPLE_STEP_TILES):
		for offset_x: int in range(-radius_tiles, radius_tiles + 1, STRUCTURE_SAMPLE_STEP_TILES):
			var tile_pos: Vector2i = world_generator.offset_tile(center_tile, Vector2i(offset_x, offset_y))
			if _distance_from_spawn_sq(world_generator, tile_pos) <= land_guarantee_radius_sq:
				continue
			var channels: WorldChannels = world_generator.sample_world_channels(tile_pos)
			var structure_context: WorldStructureContext = world_generator.sample_structure_context(tile_pos, channels)
			if structure_context == null:
				continue
			var terrain: int = int(world_generator.get_terrain_type_fast(tile_pos))
			max_river_strength = maxf(max_river_strength, structure_context.river_strength)
			max_floodplain_strength = maxf(max_floodplain_strength, structure_context.floodplain_strength)
			max_ridge_strength = maxf(max_ridge_strength, structure_context.ridge_strength)
			max_mountain_mass = maxf(max_mountain_mass, structure_context.mountain_mass)
			var is_authoritative_river: bool = _is_authoritative_river_context(structure_context)
			if is_authoritative_river:
				river_authoritative_tiles += 1
				if terrain == TileGenData.TerrainType.WATER:
					river_visible_tiles += 1
					water_tiles += 1
				elif terrain == TileGenData.TerrainType.SAND:
					river_visible_tiles += 1
					bank_tiles += 1
			var is_authoritative_mountain: bool = _is_authoritative_mountain_context(structure_context)
			if is_authoritative_mountain:
				mountain_authoritative_tiles += 1
				if terrain == TileGenData.TerrainType.ROCK:
					mountain_visible_tiles += 1
					rock_tiles += 1
	return {
		"river_authoritative_tiles": river_authoritative_tiles,
		"river_visible_tiles": river_visible_tiles,
		"mountain_authoritative_tiles": mountain_authoritative_tiles,
		"mountain_visible_tiles": mountain_visible_tiles,
		"water_tiles": water_tiles,
		"bank_tiles": bank_tiles,
		"rock_tiles": rock_tiles,
		"max_river_strength": max_river_strength,
		"max_floodplain_strength": max_floodplain_strength,
		"max_ridge_strength": max_ridge_strength,
		"max_mountain_mass": max_mountain_mass,
	}

func _compare_native_field(log_count: int, label: String, tile_pos: Vector2i, native_value: int, script_value: int) -> int:
	if native_value == script_value:
		return 0
	if log_count < MAX_MISMATCH_LOGS:
		print("[CodexProof] %s mismatch at %s native=%s script=%s" % [label, tile_pos, native_value, script_value])
	return 1

func _compare_native_float_field(log_count: int, label: String, tile_pos: Vector2i, native_value: float, script_value: float) -> int:
	if is_equal_approx(native_value, script_value) or absf(native_value - script_value) <= FLOAT_COMPARE_EPSILON:
		return 0
	if log_count < MAX_MISMATCH_LOGS:
		print("[CodexProof] %s mismatch at %s native=%.4f script=%.4f" % [label, tile_pos, native_value, script_value])
	return 1

func _print_script_biome_debug(world_generator: WorldGeneratorSingleton, tile_pos: Vector2i) -> void:
	if world_generator == null:
		return
	var biome_result: BiomeResult = world_generator.get_biome_result_at_tile(tile_pos)
	if biome_result == null:
		print("[CodexProof] no script biome debug available for %s" % [tile_pos])
		return
	print("[CodexProof] script biome debug %s => %s" % [tile_pos, biome_result.get_debug_summary()])
	_print_script_candidate_scores(world_generator, tile_pos)
	_print_native_authoritative_input_debug(world_generator, tile_pos)

func _print_native_chunk_payload_debug(
	native_data: Dictionary,
	tile_pos: Vector2i,
	base_tile: Vector2i,
	chunk_size: int
) -> void:
	if native_data.is_empty() or chunk_size <= 0:
		print("[CodexProof] no native chunk payload debug available for %s" % [tile_pos])
		return
	var local_x: int = tile_pos.x - base_tile.x
	var local_y: int = tile_pos.y - base_tile.y
	var idx: int = local_y * chunk_size + local_x
	var terrain: PackedByteArray = native_data.get("terrain", PackedByteArray()) as PackedByteArray
	var biome: PackedByteArray = native_data.get("biome", PackedByteArray()) as PackedByteArray
	var secondary_biome: PackedByteArray = native_data.get("secondary_biome", PackedByteArray()) as PackedByteArray
	var variation: PackedByteArray = native_data.get("variation", PackedByteArray()) as PackedByteArray
	var height: PackedFloat32Array = native_data.get("height", PackedFloat32Array()) as PackedFloat32Array
	var ecotone_values: PackedFloat32Array = native_data.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array
	var flora_density_values: PackedFloat32Array = native_data.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array
	var flora_modulation_values: PackedFloat32Array = native_data.get("flora_modulation_values", PackedFloat32Array()) as PackedFloat32Array
	if idx < 0 or idx >= terrain.size():
		print("[CodexProof] native chunk payload debug index out of range for %s" % [tile_pos])
		return
	var native_debug: Dictionary = {
		"world_pos": tile_pos,
		"terrain": int(terrain[idx]),
		"height": float(height[idx]) if idx < height.size() else 0.0,
		"variation": int(variation[idx]) if idx < variation.size() else 0,
		"biome": int(biome[idx]) if idx < biome.size() else 0,
		"secondary_biome": int(secondary_biome[idx]) if idx < secondary_biome.size() else 0,
		"ecotone_factor": float(ecotone_values[idx]) if idx < ecotone_values.size() else 0.0,
		"flora_density": float(flora_density_values[idx]) if idx < flora_density_values.size() else 0.0,
		"flora_modulation": float(flora_modulation_values[idx]) if idx < flora_modulation_values.size() else 0.0,
		"generation_source": String(native_data.get("generation_source", "")),
	}
	print("[CodexProof] native chunk payload debug %s => %s" % [tile_pos, native_debug])

func _print_script_candidate_scores(world_generator: WorldGeneratorSingleton, tile_pos: Vector2i) -> void:
	if world_generator == null:
		return
	var biome_resolver: BiomeResolver = world_generator.get("_biome_resolver") as BiomeResolver
	var compute_context: RefCounted = world_generator.get("_compute_context") as RefCounted
	if biome_resolver == null or compute_context == null or not compute_context.has_method("sample_prepass_channels"):
		return
	var channels: WorldChannels = world_generator.sample_world_channels(tile_pos)
	var structure_context: WorldStructureContext = world_generator.sample_structure_context(tile_pos, channels)
	var prepass_channels: WorldPrePassChannels = compute_context.call("sample_prepass_channels", tile_pos) as WorldPrePassChannels
	var causal_context: Dictionary = biome_resolver._build_causal_context(channels, prepass_channels, world_generator.balance)
	var candidates: Array[Dictionary] = []
	for biome: BiomeData in biome_resolver.get_biomes():
		if biome == null:
			continue
		var is_valid: bool = biome.matches_channels(channels, structure_context)
		if bool(causal_context.get("enabled", false)):
			is_valid = is_valid and biome_resolver._matches_causal_prepass(biome, causal_context)
		var fallback_channel_scores: Dictionary = biome_resolver._build_channel_scores(
			biome,
			channels,
			true,
			causal_context
		)
		var fallback_structure_scores: Dictionary = biome_resolver._build_structure_scores(
			biome,
			structure_context,
			true
		)
		var fallback_score: float = biome_resolver._compute_weighted_score(
			biome,
			fallback_channel_scores,
			fallback_structure_scores
		)
		candidates.append({
			"biome_id": biome.id,
			"score": fallback_score,
			"is_valid": is_valid,
			"channel_scores": fallback_channel_scores,
			"structure_scores": fallback_structure_scores,
			"priority": biome.priority,
		})
	candidates.sort_custom(_sort_candidate_scores_desc)
	var top_count: int = mini(4, candidates.size())
	print("[CodexProof] script candidate scores %s => %s" % [tile_pos, candidates.slice(0, top_count)])

func _print_native_authoritative_input_debug(world_generator: WorldGeneratorSingleton, tile_pos: Vector2i) -> void:
	if world_generator == null:
		return
	var native_generator: RefCounted = world_generator.get_native_chunk_generator()
	if native_generator == null or not native_generator.has_method("sample_tile"):
		return
	var spawn_tile: Vector2i = world_generator.spawn_tile
	var native_sample: Dictionary = native_generator.sample_tile(tile_pos, spawn_tile) as Dictionary
	if native_sample.is_empty():
		return
	var debug_snapshot: Dictionary = {
		"height": float(native_sample.get("channel_height", 0.0)),
		"temperature": float(native_sample.get("channel_temperature", 0.0)),
		"moisture": float(native_sample.get("channel_moisture", 0.0)),
		"ruggedness": float(native_sample.get("channel_ruggedness", 0.0)),
		"flora_density": float(native_sample.get("channel_flora_density", 0.0)),
		"latitude": float(native_sample.get("channel_latitude", 0.0)),
		"drainage": float(native_sample.get("drainage", 0.0)),
		"slope": float(native_sample.get("slope", 0.0)),
		"rain_shadow": float(native_sample.get("rain_shadow", 0.0)),
		"continentalness": float(native_sample.get("continentalness", 0.0)),
		"ridge_strength": float(native_sample.get("ridge_strength", 0.0)),
		"river_strength": float(native_sample.get("river_strength", 0.0)),
		"floodplain_strength": float(native_sample.get("floodplain_strength", 0.0)),
		"mountain_mass": float(native_sample.get("mountain_mass", 0.0)),
	}
	print("[CodexProof] native authoritative sample debug %s => %s" % [tile_pos, debug_snapshot])

func _sort_candidate_scores_desc(left: Dictionary, right: Dictionary) -> bool:
	var left_score: float = float(left.get("score", -1.0))
	var right_score: float = float(right.get("score", -1.0))
	if not is_equal_approx(left_score, right_score):
		return left_score > right_score
	var left_priority: int = int(left.get("priority", 0))
	var right_priority: int = int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	return String(left.get("biome_id", &"")) < String(right.get("biome_id", &""))

func _resolve_world_generator() -> WorldGeneratorSingleton:
	if _world_generator == null:
		_world_generator = get_node_or_null("/root/WorldGenerator") as WorldGeneratorSingleton
	return _world_generator
