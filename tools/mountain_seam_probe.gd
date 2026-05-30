extends SceneTree

# Headless seam diagnostic for two horizontally-adjacent mountain chunks A and B=A+(1,0)
# whose SILHOUETTE crosses the shared boundary. Two questions:
#  (1) STATIC: do freshly-built A and B masks disagree in their world overlap?
#  (2) DIG-TRANSIENT: during a dig, A rebuilds (tile removed) while B is still stale
#      (tile present) for a few frames. Does that staggered state produce a seam?
# Pure native compute; saves diff PNGs. No GPU needed.

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const SEED: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
const DENSITY: float = 0.60
const LAKE_DENSITY: float = 0.0
const HALO_RADIUS: int = 2
const PIXELS_PER_TILE: int = 8
const SCAN_RADIUS: int = 14
const SOLID_THRESHOLD: int = 107
const INVALID_TILE: Vector2i = Vector2i(2147483647, 2147483647)
const OUTPUT_DIR: String = "res://artifacts/mountain_seam_probe"

var _core: Object = null

func _initialize() -> void:
	quit(1 if _run() else 0)

func _run() -> bool:
	print("mountain_seam_probe: start density=%.2f" % DENSITY)
	_core = ClassDB.instantiate("WorldCore")
	if _core == null or not _core.has_method("build_mountain_halo_mask"):
		push_error("WorldCore.build_mountain_halo_mask required."); return true
	var settings: PackedFloat32Array = _settings_packed()
	var spawn: Dictionary = _core.call("resolve_world_foundation_spawn_tile", SEED, WorldRuntimeConstants.WORLD_VERSION, settings) as Dictionary
	if not bool(spawn.get("success", false)):
		push_error("Spawn resolve failed."); return true
	var center: Vector2i = WorldRuntimeConstants.tile_to_chunk(spawn.get("spawn_tile", Vector2i.ZERO) as Vector2i)
	var packet_map: Dictionary = _gen_block(settings, center, SCAN_RADIUS)

	# Pick A,B where the SILHOUETTE crosses the shared vertical boundary
	# (boundary band has both solid and empty -> a real edge, not solid interior).
	var best_a: Vector2i = INVALID_TILE
	var best_score: int = -1
	for key: Variant in packet_map.keys():
		var a: Vector2i = key as Vector2i
		var b: Vector2i = a + Vector2i(1, 0)
		if not packet_map.has(b):
			continue
		var sa: int = _band_solids(packet_map[a], 13, 15)
		var ea: int = (3 * WorldRuntimeConstants.CHUNK_SIZE) - sa
		var sb: int = _band_solids(packet_map[b], 0, 2)
		var eb: int = (3 * WorldRuntimeConstants.CHUNK_SIZE) - sb
		var score: int = mini(mini(sa, ea), mini(sb, eb))   # balanced edge on both sides
		if score > best_score:
			best_score = score
			best_a = a
	if best_a == INVALID_TILE or best_score <= 0:
		push_error("No silhouette-crossing adjacent pair found."); return true
	var chunk_a: Vector2i = best_a
	var chunk_b: Vector2i = best_a + Vector2i(1, 0)
	print("mountain_seam_probe: edge pair A=%s B=%s balance-score=%d" % [str(chunk_a), str(chunk_b), best_score])

	var boundary_x: float = float(chunk_b.x * WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX)

	# (1) STATIC
	var mask_a: Dictionary = _build_mask(chunk_a, packet_map, INVALID_TILE)
	var mask_b: Dictionary = _build_mask(chunk_b, packet_map, INVALID_TILE)
	var static_stats: Dictionary = _compare(mask_a, mask_b, chunk_a, boundary_x, "%s/static_diff.png" % OUTPUT_DIR)
	print("mountain_seam_probe: [STATIC] A vs B  mean=%.2f max=%d silhouette_disagree=%d/%d (%.2f%%)" % [
		static_stats["mean"], static_stats["max"], static_stats["sil"], static_stats["count"],
		100.0 * float(static_stats["sil"]) / float(maxi(int(static_stats["count"]), 1))])

	# (2) DIG-TRANSIENT: dig an exposed solid tile in A near the boundary.
	var dug: Vector2i = _pick_exposed_solid_tile(chunk_a, packet_map)
	if dug == INVALID_TILE:
		print("mountain_seam_probe: no exposed solid tile near boundary to dig; skipping dig test.")
	else:
		print("mountain_seam_probe: dug tile=%s (local %s)" % [str(dug), str(WorldRuntimeConstants.tile_to_local(dug))])
		var mask_a_dug: Dictionary = _build_mask(chunk_a, packet_map, dug)      # A rebuilt, tile removed
		# B is still stale this frame -> mask_b (tile present). Compare staggered state.
		var dig_stats: Dictionary = _compare(mask_a_dug, mask_b, chunk_a, boundary_x, "%s/dig_transient_diff.png" % OUTPUT_DIR)
		print("mountain_seam_probe: [DIG] A(dug) vs B(stale)  mean=%.2f max=%d silhouette_disagree=%d/%d (%.2f%%)" % [
			dig_stats["mean"], dig_stats["max"], dig_stats["sil"], dig_stats["count"],
			100.0 * float(dig_stats["sil"]) / float(maxi(int(dig_stats["count"]), 1))])
		# How far the change reaches inside A (single-tile dig footprint), for context.
		var self_stats: Dictionary = _compare(mask_a_dug, mask_a, chunk_a, boundary_x, "%s/dig_self_diff.png" % OUTPUT_DIR)
		print("mountain_seam_probe: [DIG] A(dug) vs A(pre)   mean=%.2f max=%d changed_px=%d" % [
			self_stats["mean"], self_stats["max"], self_stats["changed"]])

		var transient_seam: bool = int(dig_stats["sil"]) > int(static_stats["sil"]) + 5
		print("mountain_seam_probe: TRANSIENT-DIG-SEAM %s (silhouette disagree static=%d -> staggered=%d)" % [
			"CONFIRMED" if transient_seam else "not significant", int(static_stats["sil"]), int(dig_stats["sil"])])

	print("mountain_seam_probe: images -> %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	print("mountain_seam_probe: OK")
	return false

func _compare(mask_l: Dictionary, mask_r: Dictionary, chunk_a: Vector2i, boundary_x: float, png_path: String) -> Dictionary:
	if mask_l.is_empty() or mask_r.is_empty():
		return {"mean": 0.0, "max": 0, "sil": 0, "count": 0, "changed": 0}
	var tile_px: int = WorldRuntimeConstants.TILE_SIZE_PX
	var step: float = float(mask_l["step_px"])
	var x0: float = boundary_x - float(HALO_RADIUS * tile_px)
	var x1: float = boundary_x + float(HALO_RADIUS * tile_px)
	var y0: float = float(chunk_a.y * WorldRuntimeConstants.CHUNK_SIZE * tile_px) - float(HALO_RADIUS * tile_px)
	var y1: float = y0 + float((WorldRuntimeConstants.CHUNK_SIZE + 2 * HALO_RADIUS) * tile_px)
	var cols: int = maxi(1, int((x1 - x0) / step))
	var rows: int = maxi(1, int((y1 - y0) / step))
	var img: Image = Image.create(cols, rows, false, Image.FORMAT_RGB8)
	var count: int = 0
	var sumd: int = 0
	var maxd: int = 0
	var sil: int = 0
	var changed: int = 0
	for ry: int in range(rows):
		for rx: int in range(cols):
			var wx: float = x0 + (float(rx) + 0.5) * step
			var wy: float = y0 + (float(ry) + 0.5) * step
			var l: int = _sample(mask_l, wx, wy)
			var r: int = _sample(mask_r, wx, wy)
			if l < 0 or r < 0:
				continue
			var d: int = absi(l - r)
			count += 1
			sumd += d
			maxd = maxi(maxd, d)
			if d > 0:
				changed += 1
			var s: bool = (l > SOLID_THRESHOLD) != (r > SOLID_THRESHOLD)
			if s:
				sil += 1
			var dn: float = clampf(float(d) / 96.0, 0.0, 1.0)
			img.set_pixel(rx, ry, Color(0.1, 0.9, 1.0) if s else Color(dn, dn * 0.5, 0.0))
	img.save_png(png_path)
	return {"mean": float(sumd) / float(maxi(count, 1)), "max": maxd, "sil": sil, "count": count, "changed": changed}

func _pick_exposed_solid_tile(chunk: Vector2i, packet_map: Dictionary) -> Vector2i:
	# Solid tile in chunk's right band with an empty 4-neighbour, closest to the right edge.
	for lx: int in range(WorldRuntimeConstants.CHUNK_SIZE - 1, WorldRuntimeConstants.CHUNK_SIZE - 6, -1):
		for ly: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			var tile: Vector2i = chunk * WorldRuntimeConstants.CHUNK_SIZE + Vector2i(lx, ly)
			if not _tile_solid(tile, packet_map, INVALID_TILE):
				continue
			for off: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if not _tile_solid(tile + off, packet_map, INVALID_TILE):
					return tile
	return INVALID_TILE

func _build_mask(chunk: Vector2i, packet_map: Dictionary, dug_tile: Vector2i) -> Dictionary:
	var halo: PackedByteArray = _solid_halo(chunk, packet_map, dug_tile)
	var origin: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk) - Vector2.ONE * float(WorldRuntimeConstants.TILE_SIZE_PX * HALO_RADIUS)
	var r: Dictionary = _core.call("build_mountain_halo_mask", halo, WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX, PIXELS_PER_TILE, origin.x, origin.y) as Dictionary
	var bytes: PackedByteArray = r.get("mask", PackedByteArray()) as PackedByteArray
	var w: int = int(r.get("width", 0)); var h: int = int(r.get("height", 0))
	if w <= 0 or h <= 0 or bytes.size() != w * h:
		return {}
	return {"bytes": bytes, "width": w, "height": h, "step_px": float(r.get("step_px", 0.0)), "origin": origin}

func _sample(mask: Dictionary, wx: float, wy: float) -> int:
	var origin: Vector2 = mask["origin"] as Vector2
	var step: float = float(mask["step_px"])
	var mx: int = int(floor((wx - origin.x) / step)); var my: int = int(floor((wy - origin.y) / step))
	var w: int = int(mask["width"]); var h: int = int(mask["height"])
	if mx < 0 or my < 0 or mx >= w or my >= h:
		return -1
	return int((mask["bytes"] as PackedByteArray)[my * w + mx])

func _solid_halo(chunk: Vector2i, packet_map: Dictionary, dug_tile: Vector2i) -> PackedByteArray:
	var side: int = WorldRuntimeConstants.CHUNK_SIZE + HALO_RADIUS * 2
	var halo := PackedByteArray(); halo.resize(side * side)
	for hy: int in range(side):
		for hx: int in range(side):
			var tile: Vector2i = chunk * WorldRuntimeConstants.CHUNK_SIZE + Vector2i(hx - HALO_RADIUS, hy - HALO_RADIUS)
			if _tile_solid(tile, packet_map, dug_tile):
				halo[hy * side + hx] = 1
	return halo

func _tile_solid(world_tile: Vector2i, packet_map: Dictionary, dug_tile: Vector2i) -> bool:
	if world_tile == dug_tile:
		return false
	var packet: Dictionary = packet_map.get(WorldRuntimeConstants.tile_to_chunk(world_tile), {}) as Dictionary
	if packet.is_empty():
		return false
	return _index_solid(WorldRuntimeConstants.local_to_index(WorldRuntimeConstants.tile_to_local(world_tile)), packet)

func _index_solid(index: int, packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return false
	var t: int = int(terrain_ids[index])
	if t != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL and t != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return false
	if int(walkable_flags[index]) != 0:
		return false
	if index >= mountain_ids.size() or int(mountain_ids[index]) <= 0:
		return false
	if index >= mountain_flags.size():
		return false
	return (int(mountain_flags[index]) & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0

func _band_solids(packet: Dictionary, x_lo: int, x_hi: int) -> int:
	var c: int = 0
	for ly: int in range(WorldRuntimeConstants.CHUNK_SIZE):
		for lx: int in range(x_lo, x_hi + 1):
			if _index_solid(WorldRuntimeConstants.local_to_index(Vector2i(lx, ly)), packet):
				c += 1
	return c

func _gen_block(settings: PackedFloat32Array, center: Vector2i, radius: int) -> Dictionary:
	var coords := PackedVector2Array()
	for cy: int in range(center.y - radius, center.y + radius + 1):
		for cx: int in range(center.x - radius, center.x + radius + 1):
			coords.append(Vector2(cx, cy))
	var packets: Array = _core.call("generate_chunk_packets_batch", SEED, coords, WorldRuntimeConstants.WORLD_VERSION, settings) as Array
	var map: Dictionary = {}
	for pv: Variant in packets:
		var p: Dictionary = pv as Dictionary
		map[p.get("chunk_coord", Vector2i.ZERO) as Vector2i] = p
	return map

func _settings_packed() -> PackedFloat32Array:
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = LAKE_DENSITY
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	mountain.density = DENSITY
	var packed: PackedFloat32Array = mountain.flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	return lakes.write_to_settings_packed(packed)
