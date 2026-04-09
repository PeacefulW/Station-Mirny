class_name WorldPreviewProofDriver
extends Node

## Small debug-only driver for reproducible fixed-seed ecotone proof exports.
## Activates only when launched with the user arg `codex_export_ecotone_proof`.

const ENABLE_ARG: String = "codex_export_ecotone_proof"
const VERIFY_NATIVE_TRUTH_ARG: String = "codex_verify_native_world_truth"
const EXPORT_COUNT_ARG_PREFIX: String = "codex_ecotone_proof_count="
const EXPORT_RADIUS_ARG_PREFIX: String = "codex_ecotone_radius="
const VERIFY_CHUNK_RADIUS_ARG_PREFIX: String = "codex_native_truth_chunk_radius="
const WorldPreviewExporterScript = preload("res://core/debug/world_preview_exporter.gd")
const MIN_ECOTONE_FACTOR: float = 0.22
const DEFAULT_EXPORT_COUNT: int = 3
const DEFAULT_RADIUS_TILES: int = 56
const DEFAULT_VERIFY_CHUNK_RADIUS: int = 2
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
	_run_export()

func _is_enabled() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	return ENABLE_ARG in args or VERIFY_NATIVE_TRUTH_ARG in args

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
	var chunk_builder: ChunkContentBuilder = world_generator.get("_chunk_content_builder") as ChunkContentBuilder
	if chunk_builder == null:
		return
	var canonical_chunk: Vector2i = world_generator.canonicalize_chunk_coord(world_generator.tile_to_chunk(tile_pos))
	var base_tile: Vector2i = world_generator.chunk_to_tile_origin(canonical_chunk)
	var chunk_size: int = int(world_generator.balance.chunk_size_tiles) if world_generator.balance != null else 0
	if chunk_size <= 0:
		return
	var authoritative_inputs: Dictionary = chunk_builder.call("_build_native_chunk_authoritative_inputs", base_tile, chunk_size) as Dictionary
	if authoritative_inputs.is_empty():
		return
	var local_x: int = tile_pos.x - base_tile.x
	var local_y: int = tile_pos.y - base_tile.y
	var idx: int = local_y * chunk_size + local_x
	var debug_snapshot: Dictionary = {
		"height": _float_value_at(authoritative_inputs.get("height_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"temperature": _float_value_at(authoritative_inputs.get("temperature_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"moisture": _float_value_at(authoritative_inputs.get("moisture_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"ruggedness": _float_value_at(authoritative_inputs.get("ruggedness_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"flora_density": _float_value_at(authoritative_inputs.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"latitude": _float_value_at(authoritative_inputs.get("latitude_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"drainage": _float_value_at(authoritative_inputs.get("drainage_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"slope": _float_value_at(authoritative_inputs.get("slope_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"rain_shadow": _float_value_at(authoritative_inputs.get("rain_shadow_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"continentalness": _float_value_at(authoritative_inputs.get("continentalness_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"ridge_strength": _float_value_at(authoritative_inputs.get("ridge_strength_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"river_width": _float_value_at(authoritative_inputs.get("river_width_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"river_distance": _float_value_at(authoritative_inputs.get("river_distance_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"floodplain_strength": _float_value_at(authoritative_inputs.get("floodplain_strength_values", PackedFloat32Array()) as PackedFloat32Array, idx),
		"mountain_mass": _float_value_at(authoritative_inputs.get("mountain_mass_values", PackedFloat32Array()) as PackedFloat32Array, idx),
	}
	print("[CodexProof] authoritative chunk-input debug %s => %s" % [tile_pos, debug_snapshot])

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

func _float_value_at(values: PackedFloat32Array, idx: int) -> float:
	if idx < 0 or idx >= values.size():
		return 0.0
	return float(values[idx])

func _resolve_world_generator() -> WorldGeneratorSingleton:
	if _world_generator == null:
		_world_generator = get_node_or_null("/root/WorldGenerator") as WorldGeneratorSingleton
	return _world_generator
