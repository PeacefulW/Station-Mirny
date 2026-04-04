class_name WorldPreviewProofDriver
extends Node

## Small debug-only driver for reproducible fixed-seed ecotone proof exports.
## Activates only when launched with the user arg `codex_export_ecotone_proof`.

const ENABLE_ARG: String = "codex_export_ecotone_proof"
const EXPORT_COUNT_ARG_PREFIX: String = "codex_ecotone_proof_count="
const EXPORT_RADIUS_ARG_PREFIX: String = "codex_ecotone_radius="
const WorldPreviewExporterScript = preload("res://core/debug/world_preview_exporter.gd")
const MIN_ECOTONE_FACTOR: float = 0.22
const DEFAULT_EXPORT_COUNT: int = 3
const DEFAULT_RADIUS_TILES: int = 56
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
	print("[CodexProof] ecotone preview proof driver enabled")

func _process(_delta: float) -> void:
	if not _is_enabled() or _started:
		return
	var world_generator: WorldGeneratorSingleton = _resolve_world_generator()
	if world_generator == null or not world_generator._is_initialized or world_generator.balance == null:
		return
	_started = true
	_run_export()

func _is_enabled() -> bool:
	return ENABLE_ARG in OS.get_cmdline_user_args()

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

func _resolve_world_generator() -> WorldGeneratorSingleton:
	if _world_generator == null:
		_world_generator = get_node_or_null("/root/WorldGenerator") as WorldGeneratorSingleton
	return _world_generator
