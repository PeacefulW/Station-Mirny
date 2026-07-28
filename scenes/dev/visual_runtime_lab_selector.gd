class_name VisualRuntimeLabSelector
extends RefCounted

const WorldRuntimeConstants = preload(
	"res://core/systems/world/world_runtime_constants.gd"
)

const PREFERRED_CAMERA_CHUNK: Vector2i = Vector2i(34, 108)
const PREFERRED_LAKE_CHUNK: Vector2i = Vector2i(33, 109)
const PREFERRED_MOUNTAIN_CHUNK: Vector2i = Vector2i(37, 107)
const MAX_SCAN_RADIUS_CHUNKS: int = 4
const CAMERA_WINDOW_X: int = 4
const CAMERA_WINDOW_Y: int = 2
const MOUNTAIN_EAST_MIN: int = 1
const MOUNTAIN_EAST_MAX: int = CAMERA_WINDOW_X + 1
const MAX_SMALL_LAKE_TILES_IN_WINDOW: int = 640

const OBJECT_KIND_LIVING_FLORA: int = 2
const OBJECT_KIND_SPIKY_FLORA: int = 3
const OBJECT_KIND_TREE: int = 4
const OBJECT_KIND_SMALL_ROCK: int = 7
const REQUIRED_OBJECT_KINDS: Array[int] = [
	OBJECT_KIND_LIVING_FLORA,
	OBJECT_KIND_SPIKY_FLORA,
	OBJECT_KIND_TREE,
	OBJECT_KIND_SMALL_ROCK,
]


func find_patch(
	seed_value: int,
	world_version: int,
	settings_packed: PackedFloat32Array,
	_origin_chunk: Vector2i,
	world_core_override: Object = null,
) -> Dictionary:
	var world_core: Object = (
		world_core_override
		if world_core_override != null
		else ClassDB.instantiate("WorldCore")
	)
	if world_core == null:
		return {
			"success": false,
			"error": "native_unavailable",
		}
	var summaries: Dictionary = {}
	var best: Dictionary = {}
	var preferred: Dictionary = {}
	for radius: int in range(MAX_SCAN_RADIUS_CHUNKS + 1):
		var coords: PackedVector2Array = _chunk_ring(
			PREFERRED_CAMERA_CHUNK,
			radius,
		)
		var packets: Array = world_core.call(
			"generate_chunk_packets_batch",
			seed_value,
			coords,
			world_version,
			settings_packed,
		) as Array
		for packet_variant: Variant in packets:
			var packet: Dictionary = packet_variant as Dictionary
			var summary: Dictionary = _summarize_packet(packet)
			var chunk_coord: Vector2i = summary.get(
				"chunk_coord",
				Vector2i.ZERO,
			) as Vector2i
			summaries[chunk_coord] = summary
		if radius < CAMERA_WINDOW_X:
			continue
		preferred = _build_candidate(
			summaries,
			PREFERRED_LAKE_CHUNK,
			PREFERRED_MOUNTAIN_CHUNK,
			PREFERRED_CAMERA_CHUNK,
		)
		if bool(preferred.get("exact_match", false)):
			preferred["success"] = true
			preferred["scanned_radius_chunks"] = radius
			preferred["scanned_chunk_count"] = summaries.size()
			return preferred
		var candidate: Dictionary = _find_best_candidate(summaries)
		if not candidate.is_empty():
			var candidate_exact: bool = bool(candidate.get("exact_match", false))
			var best_exact: bool = bool(best.get("exact_match", false))
			if best.is_empty() \
					or (candidate_exact and not best_exact) \
					or (
						candidate_exact == best_exact
						and int(candidate.get("score", -1)) \
						> int(best.get("score", -1))
					):
				best = candidate
		if bool(best.get("exact_match", false)):
			best["success"] = true
			best["scanned_radius_chunks"] = radius
			best["scanned_chunk_count"] = summaries.size()
			return best
	if not bool(best.get("exact_match", false)):
		best = _build_prepared_fallback(summaries)
	best["success"] = true
	best["scanned_radius_chunks"] = MAX_SCAN_RADIUS_CHUNKS
	best["scanned_chunk_count"] = summaries.size()
	return best


func _build_prepared_fallback(summaries: Dictionary) -> Dictionary:
	var window_summary: Dictionary = _collect_window_summary(
		summaries,
		PREFERRED_CAMERA_CHUNK,
	)
	var mountain_summary: Dictionary = summaries.get(
		PREFERRED_MOUNTAIN_CHUNK,
		{},
	) as Dictionary
	return {
		"score": 0,
		"exact_match": false,
		"camera_chunk": PREFERRED_CAMERA_CHUNK,
		"camera_tile": (
			PREFERRED_CAMERA_CHUNK * WorldRuntimeConstants.CHUNK_SIZE
			+ Vector2i(
				WorldRuntimeConstants.CHUNK_SIZE / 2,
				WorldRuntimeConstants.CHUNK_SIZE / 2,
			)
		),
		"lake_chunk": PREFERRED_LAKE_CHUNK,
		"mountain_chunk": PREFERRED_MOUNTAIN_CHUNK,
		"water_tile_count": int(window_summary.get("water_count", 0)),
		"shallow_tile_count": int(window_summary.get("shallow_count", 0)),
		"deep_tile_count": int(window_summary.get("deep_count", 0)),
		"window_present_chunk_count": int(
			window_summary.get("present_chunk_count", 0)
		),
		"mountain_tile_count": int(mountain_summary.get("mountain_count", 0)),
		"object_counts": window_summary.get("object_counts", {}) as Dictionary,
	}


func _summarize_packet(packet: Dictionary) -> Dictionary:
	var terrain_ids: PackedInt32Array = packet.get(
		"terrain_ids",
		PackedInt32Array(),
	) as PackedInt32Array
	var object_kinds: PackedByteArray = packet.get(
		"object_kind",
		PackedByteArray(),
	) as PackedByteArray
	var shallow_count: int = 0
	var deep_count: int = 0
	var mountain_count: int = 0
	for terrain_id: int in terrain_ids:
		if terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW:
			shallow_count += 1
		elif terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP:
			deep_count += 1
		elif terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			mountain_count += 1
	var kinds: Dictionary = {}
	for kind: int in object_kinds:
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	return {
		"chunk_coord": packet.get("chunk_coord", Vector2i.ZERO) as Vector2i,
		"shallow_count": shallow_count,
		"deep_count": deep_count,
		"water_count": shallow_count + deep_count,
		"mountain_count": mountain_count,
		"object_kinds": kinds,
	}


func _find_best_candidate(summaries: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for lake_coord_variant: Variant in summaries.keys():
		var lake_coord: Vector2i = lake_coord_variant as Vector2i
		var lake_summary: Dictionary = summaries.get(lake_coord, {}) as Dictionary
		if int(lake_summary.get("water_count", 0)) <= 0:
			continue
		for delta_x: int in range(MOUNTAIN_EAST_MIN, MOUNTAIN_EAST_MAX + 1):
			for delta_y: int in range(-CAMERA_WINDOW_Y, CAMERA_WINDOW_Y + 1):
				var mountain_coord: Vector2i = lake_coord + Vector2i(delta_x, delta_y)
				var mountain_summary: Dictionary = summaries.get(
					mountain_coord,
					{},
				) as Dictionary
				if int(mountain_summary.get("mountain_count", 0)) < 8:
					continue
				var camera_chunk: Vector2i = Vector2i(
					lake_coord.x + 1,
					floori(float(lake_coord.y + mountain_coord.y) * 0.5),
				)
				var candidate: Dictionary = _build_candidate(
					summaries,
					lake_coord,
					mountain_coord,
					camera_chunk,
				)
				if not best.is_empty():
					var candidate_exact: bool = bool(
						candidate.get("exact_match", false)
					)
					var best_exact: bool = bool(best.get("exact_match", false))
					if best_exact and not candidate_exact:
						continue
					if candidate_exact == best_exact \
							and int(candidate.get("score", -1)) \
							<= int(best.get("score", -1)):
						continue
				best = candidate
	return best


func _build_candidate(
	summaries: Dictionary,
	lake_coord: Vector2i,
	mountain_coord: Vector2i,
	camera_chunk: Vector2i,
) -> Dictionary:
	var lake_summary: Dictionary = summaries.get(lake_coord, {}) as Dictionary
	var mountain_summary: Dictionary = summaries.get(mountain_coord, {}) as Dictionary
	if int(lake_summary.get("water_count", 0)) <= 0 \
			or int(mountain_summary.get("mountain_count", 0)) < 8:
		return {}
	var window_summary: Dictionary = _collect_window_summary(
		summaries,
		camera_chunk,
	)
	var object_counts: Dictionary = window_summary.get(
		"object_counts",
		{},
	) as Dictionary
	var water_count: int = int(window_summary.get("water_count", 0))
	var has_shallow: bool = int(window_summary.get("shallow_count", 0)) > 0
	var has_deep: bool = int(window_summary.get("deep_count", 0)) > 0
	var window_complete: bool = (
		int(window_summary.get("present_chunk_count", 0))
		== (CAMERA_WINDOW_X * 2 + 1) * (CAMERA_WINDOW_Y * 2 + 1)
	)
	var score: int = 40
	score += mini(int(mountain_summary.get("mountain_count", 0)), 64)
	score += 24 if has_shallow else 0
	score += 24 if has_deep else 0
	score += 16 if water_count <= MAX_SMALL_LAKE_TILES_IN_WINDOW else 0
	for kind: int in REQUIRED_OBJECT_KINDS:
		if int(object_counts.get(kind, 0)) > 0:
			score += 24
	var required_object_count: int = 0
	for kind: int in REQUIRED_OBJECT_KINDS:
		required_object_count += int(object_counts.get(kind, 0))
	score -= mini(floori(float(required_object_count) / 16.0), 120)
	var exact_match: bool = (
		window_complete
		and has_shallow
		and has_deep
		and water_count <= MAX_SMALL_LAKE_TILES_IN_WINDOW
	)
	for kind: int in REQUIRED_OBJECT_KINDS:
		exact_match = exact_match and int(object_counts.get(kind, 0)) > 0
	return {
		"score": score,
		"exact_match": exact_match,
		"camera_chunk": camera_chunk,
		"camera_tile": (
			camera_chunk * WorldRuntimeConstants.CHUNK_SIZE
			+ Vector2i(
				WorldRuntimeConstants.CHUNK_SIZE / 2,
				WorldRuntimeConstants.CHUNK_SIZE / 2,
			)
		),
		"lake_chunk": lake_coord,
		"mountain_chunk": mountain_coord,
		"water_tile_count": water_count,
		"shallow_tile_count": int(window_summary.get("shallow_count", 0)),
		"deep_tile_count": int(window_summary.get("deep_count", 0)),
		"window_present_chunk_count": int(
			window_summary.get("present_chunk_count", 0)
		),
		"mountain_tile_count": int(mountain_summary.get("mountain_count", 0)),
		"object_counts": object_counts,
	}


func _collect_window_summary(
	summaries: Dictionary,
	camera_chunk: Vector2i,
) -> Dictionary:
	var counts: Dictionary = {}
	var shallow_count: int = 0
	var deep_count: int = 0
	var present_chunk_count: int = 0
	for chunk_y: int in range(
			camera_chunk.y - CAMERA_WINDOW_Y,
			camera_chunk.y + CAMERA_WINDOW_Y + 1,
	):
		for chunk_x: int in range(
			camera_chunk.x - CAMERA_WINDOW_X,
			camera_chunk.x + CAMERA_WINDOW_X + 1,
		):
			var summary: Dictionary = summaries.get(
				Vector2i(chunk_x, chunk_y),
				{},
			) as Dictionary
			if not summary.is_empty():
				present_chunk_count += 1
			shallow_count += int(summary.get("shallow_count", 0))
			deep_count += int(summary.get("deep_count", 0))
			var kinds: Dictionary = summary.get("object_kinds", {}) as Dictionary
			for kind_variant: Variant in kinds.keys():
				var kind: int = int(kind_variant)
				counts[kind] = int(counts.get(kind, 0)) + int(kinds[kind_variant])
	return {
		"object_counts": counts,
		"shallow_count": shallow_count,
		"deep_count": deep_count,
		"water_count": shallow_count + deep_count,
		"present_chunk_count": present_chunk_count,
	}


func _chunk_ring(center_chunk: Vector2i, radius: int) -> PackedVector2Array:
	var coords: PackedVector2Array = PackedVector2Array()
	for chunk_y: int in range(center_chunk.y - radius, center_chunk.y + radius + 1):
		for chunk_x: int in range(
			center_chunk.x - radius,
			center_chunk.x + radius + 1,
		):
			if maxi(
				absi(chunk_x - center_chunk.x),
				absi(chunk_y - center_chunk.y),
			) != radius:
				continue
			coords.append(Vector2(float(chunk_x), float(chunk_y)))
	return coords
