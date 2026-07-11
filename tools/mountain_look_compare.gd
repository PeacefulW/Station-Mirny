extends Node

# Phase 1 comparison harness: render ONE real mountain chunk two ways in an
# identical frame so the canon look can be chosen by eye.
#   A) baked raster  -> MountainPlateau2DRasterLayer (build_mountain_plateau_raster_image)
#   B) shader-from-mask -> native build_mountain_halo_mask + mountain_top_mask_underlay.gdshader
# Both consume the same generated chunk packets and the same source textures.
# Must run WINDOWED (not --headless): SubViewport.get_image() needs a real GPU.

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const MountainPlateau2DRasterLayer = preload("res://core/systems/world/mountain_plateau_2d_raster_layer.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const MOUNTAIN_TOP_MASK_UNDERLAY_SHADER = preload("res://assets/shaders/mountain_top_mask_underlay.gdshader")

const TOP_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_albedo.png"
const FACE_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_albedo.png"
const PRESET_PATH: String = "res://scenes/dev/mountain_2d_raster_preset.json"
const OUTPUT_DIR: String = "res://artifacts/mountain_look_compare"

const PROBE_SEED: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
const DENSITY: float = 0.60
const LAKE_DENSITY: float = 0.0
const HALO_RADIUS_TILES: int = 2          # MOUNTAIN_HALO_MASK_RADIUS_TILES
const HALO_PIXELS_PER_TILE: int = 8       # MOUNTAIN_HALO_MASK_PIXELS_PER_TILE
const SOURCE_RADIUS_CHUNKS: int = 1
const SCAN_RADIUS_CHUNKS: int = 12
const GOOD_ENOUGH_SOLID_TILES: int = 150
const VIEW_SIZE: int = 1280
const ZOOM: float = 3.0                       # south-edge zoom so the facade reads
const FACADE_SHOW_PX: float = 96.0            # baked facade height for the comparison (preset max)
const MASK_TOP_TEXTURE_SCALE: float = 0.70   # ChunkView default
const BG_COLOR: Color = Color(0.17, 0.21, 0.15, 1.0)
const GAP_PX: int = 24

var _failed: bool = false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("mountain_look_compare: start density=%.2f" % DENSITY)
	if DisplayServer.get_name() == "headless":
		push_error("mountain_look_compare must run WINDOWED (not --headless): viewport capture needs a GPU.")
		_finish_failed()
		return
	_prepare_output_dir()

	var core: Object = ClassDB.instantiate("WorldCore")
	_assert(core != null, "WorldCore required.")
	if core == null:
		_finish_failed()
		return
	_assert(core.has_method("build_mountain_halo_mask"), "WorldCore.build_mountain_halo_mask required - rebuild GDExtension.")
	_assert(core.has_method("build_mountain_plateau_raster_image"), "WorldCore.build_mountain_plateau_raster_image required - rebuild GDExtension.")

	var settings_packed: PackedFloat32Array = _build_settings_packed()
	var spawn_result: Dictionary = core.call(
		"resolve_world_foundation_spawn_tile",
		PROBE_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	) as Dictionary
	_assert(bool(spawn_result.get("success", false)), "Spawn resolution must succeed.")
	if not bool(spawn_result.get("success", false)):
		_finish_failed()
		return
	var spawn_tile: Vector2i = spawn_result.get("spawn_tile", Vector2i.ZERO) as Vector2i
	var center_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(spawn_tile)

	var target_chunk: Vector2i = _find_best_mountain_chunk(core, settings_packed, center_chunk)
	_assert(target_chunk != WorldRuntimeConstants.tile_to_chunk(Vector2i(2147483647, 2147483647)), "No mountain chunk found in scan radius.")
	print("mountain_look_compare: target_chunk=%s" % str(target_chunk))

	# Gather the 3x3 source packets around the target (covers both the baked
	# source radius and the 2-tile halo).
	var packet_map: Dictionary = {}
	var coords: PackedVector2Array = PackedVector2Array()
	for cy: int in range(target_chunk.y - SOURCE_RADIUS_CHUNKS, target_chunk.y + SOURCE_RADIUS_CHUNKS + 1):
		for cx: int in range(target_chunk.x - SOURCE_RADIUS_CHUNKS, target_chunk.x + SOURCE_RADIUS_CHUNKS + 1):
			coords.append(Vector2(cx, cy))
	var source_packets: Array = core.call(
		"generate_chunk_packets_batch",
		PROBE_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	) as Array
	var baked_packets: Array[Dictionary] = []
	for packet_variant: Variant in source_packets:
		var packet: Dictionary = packet_variant as Dictionary
		packet_map[packet.get("chunk_coord", Vector2i.ZERO) as Vector2i] = packet
		baked_packets.append(packet)

	var solid_tile_count: int = _packet_solid_count(packet_map.get(target_chunk, {}) as Dictionary)
	print("mountain_look_compare: target solid mountain tiles=%d, source packets=%d" % [solid_tile_count, baked_packets.size()])

	# Frame on the SOUTH edge of the blob, zoomed, so the facade ("wall") reads.
	var frame_center: Vector2 = _target_south_frame_center(target_chunk, packet_map)
	var frame_top_left: Vector2 = frame_center - Vector2(VIEW_SIZE, VIEW_SIZE) / (2.0 * ZOOM)
	print("mountain_look_compare: frame_center=%s zoom=%.1f" % [str(frame_center), ZOOM])

	var top_texture: Texture2D = load(TOP_TEXTURE_PATH) as Texture2D
	var face_texture: Texture2D = load(FACE_TEXTURE_PATH) as Texture2D
	_assert(top_texture != null and face_texture != null, "Source mountain textures must load from res://.")

	var viewport_baked: SubViewport = _build_baked_viewport(baked_packets, target_chunk, frame_top_left, ZOOM)
	var viewport_shader: SubViewport = _build_shader_viewport(core, packet_map, target_chunk, frame_top_left, ZOOM, top_texture, face_texture)
	add_child(viewport_baked)
	add_child(viewport_shader)

	# Let both SubViewports render. Native builds above were synchronous.
	for _frame: int in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image_baked: Image = _capture(viewport_baked)
	var image_shader: Image = _capture(viewport_shader)
	_assert(image_baked != null, "Baked viewport capture must produce an image.")
	_assert(image_shader != null, "Shader viewport capture must produce an image.")
	if image_baked == null or image_shader == null:
		_finish_failed()
		return

	var baked_path: String = "%s/A_baked_raster.png" % OUTPUT_DIR
	var shader_path: String = "%s/B_shader_from_mask.png" % OUTPUT_DIR
	var side_by_side_path: String = "%s/compare_side_by_side.png" % OUTPUT_DIR
	image_baked.save_png(baked_path)
	image_shader.save_png(shader_path)
	_save_side_by_side(image_baked, image_shader, side_by_side_path)

	var report: Dictionary = {
		"seed": PROBE_SEED,
		"density": DENSITY,
		"target_chunk": target_chunk,
		"solid_mountain_tiles": solid_tile_count,
		"view_size": VIEW_SIZE,
		"baked_png": ProjectSettings.globalize_path(baked_path),
		"shader_png": ProjectSettings.globalize_path(shader_path),
		"side_by_side_png": ProjectSettings.globalize_path(side_by_side_path),
	}
	var report_file := FileAccess.open("%s/compare_report.json" % OUTPUT_DIR, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print("MOUNTAIN_LOOK_COMPARE_JSON=" + JSON.stringify(report))
	print("mountain_look_compare: OK -> %s" % ProjectSettings.globalize_path(side_by_side_path))
	_finish()

func _build_baked_viewport(packets: Array[Dictionary], target_chunk: Vector2i, frame_top_left: Vector2, zoom: float) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(_make_background())
	var content := Node2D.new()
	content.scale = Vector2(zoom, zoom)
	content.position = -frame_top_left * zoom
	viewport.add_child(content)
	var layer: MountainPlateau2DRasterLayer = MountainPlateau2DRasterLayer.new()
	layer.set_target_chunk_anchor_enabled(false)
	layer.set_ground_surface_enabled(false)
	var preset: Dictionary = _load_preset()
	preset["facade_height_px"] = FACADE_SHOW_PX
	layer.set_preset(preset)
	content.add_child(layer)
	layer.rebuild_from_packets(packets, target_chunk)
	var debug: Dictionary = layer.get_debug_snapshot()
	print("mountain_look_compare: baked ready=%s image=%dx%d" % [
		str(debug.get("ready", false)),
		int(debug.get("image_width", 0)),
		int(debug.get("image_height", 0)),
	])
	return viewport

func _build_shader_viewport(
	core: Object,
	packet_map: Dictionary,
	target_chunk: Vector2i,
	frame_top_left: Vector2,
	zoom: float,
	top_texture: Texture2D,
	face_texture: Texture2D
) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(_make_background())
	var content := Node2D.new()
	content.scale = Vector2(zoom, zoom)
	content.position = -frame_top_left * zoom
	viewport.add_child(content)

	var mask_origin_world: Vector2 = WorldRuntimeConstants.chunk_origin_px(target_chunk) \
		- Vector2.ONE * float(WorldRuntimeConstants.TILE_SIZE_PX * HALO_RADIUS_TILES)
	var solid_halo: PackedByteArray = _build_solid_halo(target_chunk, packet_map)
	var mask_result: Dictionary = core.call(
		"build_mountain_halo_mask",
		solid_halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		HALO_PIXELS_PER_TILE,
		mask_origin_world.x,
		mask_origin_world.y
	) as Dictionary
	var mask_bytes: PackedByteArray = mask_result.get("mask", PackedByteArray()) as PackedByteArray
	var mask_width: int = int(mask_result.get("width", 0))
	var mask_height: int = int(mask_result.get("height", 0))
	var mask_step_px: float = float(mask_result.get("step_px", 0.0))
	print("mountain_look_compare: mask=%dx%d step=%.2f solids=%d" % [
		mask_width, mask_height, mask_step_px, int(mask_result.get("solid_sample_count", 0)),
	])
	_assert(mask_width > 0 and mask_height > 0 and mask_bytes.size() == mask_width * mask_height, "Native halo mask must be non-empty.")
	if mask_width <= 0 or mask_height <= 0 or mask_bytes.size() != mask_width * mask_height:
		return viewport

	var mask_image: Image = Image.create_from_data(mask_width, mask_height, false, Image.FORMAT_L8, mask_bytes)
	var mask_texture: ImageTexture = ImageTexture.create_from_image(mask_image)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.texture = mask_texture
	sprite.position = mask_origin_world
	sprite.scale = Vector2.ONE * mask_step_px
	var material := ShaderMaterial.new()
	material.shader = MOUNTAIN_TOP_MASK_UNDERLAY_SHADER
	material.set_shader_parameter("closed_mask_texture", mask_texture)
	material.set_shader_parameter("top_texture", top_texture)
	material.set_shader_parameter("top_texture_size", Vector2(maxf(1.0, float(top_texture.get_width())), maxf(1.0, float(top_texture.get_height()))))
	material.set_shader_parameter("face_texture", face_texture)
	material.set_shader_parameter("face_texture_size", Vector2(maxf(1.0, float(face_texture.get_width())), maxf(1.0, float(face_texture.get_height()))))
	material.set_shader_parameter("world_origin_px", mask_origin_world)
	material.set_shader_parameter("sample_step_px", mask_step_px)
	material.set_shader_parameter("top_texture_scale", MASK_TOP_TEXTURE_SCALE)
	material.set_shader_parameter("face_texture_scale", 0.46)
	material.set_shader_parameter("facade_height_px", FACADE_SHOW_PX)
	sprite.material = material
	content.add_child(sprite)
	return viewport

func _make_background() -> ColorRect:
	var background := ColorRect.new()
	background.color = BG_COLOR
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	return background

func _capture(viewport: SubViewport) -> Image:
	var texture: Texture2D = viewport.get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _save_side_by_side(image_left: Image, image_right: Image, path: String) -> void:
	var height: int = maxi(image_left.get_height(), image_right.get_height())
	var width: int = image_left.get_width() + GAP_PX + image_right.get_width()
	var combined: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	combined.fill(BG_COLOR)
	combined.blit_rect(image_left, Rect2i(0, 0, image_left.get_width(), image_left.get_height()), Vector2i.ZERO)
	combined.blit_rect(image_right, Rect2i(0, 0, image_right.get_width(), image_right.get_height()), Vector2i(image_left.get_width() + GAP_PX, 0))
	combined.save_png(path)

func _find_best_mountain_chunk(core: Object, settings_packed: PackedFloat32Array, center_chunk: Vector2i) -> Vector2i:
	var best_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(Vector2i(2147483647, 2147483647))
	var best_count: int = 0
	for radius: int in range(0, SCAN_RADIUS_CHUNKS + 1):
		var coords: PackedVector2Array = _ring_coords(center_chunk, radius)
		if coords.is_empty():
			continue
		var packets: Array = core.call(
			"generate_chunk_packets_batch",
			PROBE_SEED,
			coords,
			WorldRuntimeConstants.WORLD_VERSION,
			settings_packed
		) as Array
		for packet_variant: Variant in packets:
			var packet: Dictionary = packet_variant as Dictionary
			var count: int = _packet_solid_count(packet)
			if count > best_count:
				best_count = count
				best_chunk = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
		if best_count >= GOOD_ENOUGH_SOLID_TILES:
			break
	return best_chunk

func _ring_coords(center_chunk: Vector2i, radius: int) -> PackedVector2Array:
	var coords: PackedVector2Array = PackedVector2Array()
	if radius == 0:
		coords.append(Vector2(center_chunk.x, center_chunk.y))
		return coords
	for cy: int in range(center_chunk.y - radius, center_chunk.y + radius + 1):
		for cx: int in range(center_chunk.x - radius, center_chunk.x + radius + 1):
			if maxi(absi(cx - center_chunk.x), absi(cy - center_chunk.y)) != radius:
				continue
			coords.append(Vector2(cx, cy))
	return coords

func _packet_solid_count(packet: Dictionary) -> int:
	if packet.is_empty():
		return 0
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var count: int = 0
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		if _index_is_solid(index, terrain_ids, walkable_flags, mountain_ids, mountain_flags):
			count += 1
	return count

func _target_south_frame_center(target_chunk: Vector2i, packet_map: Dictionary) -> Vector2:
	var packet: Dictionary = packet_map.get(target_chunk, {}) as Dictionary
	var min_tile := Vector2i(2147483647, 2147483647)
	var max_tile := Vector2i(-2147483648, -2147483648)
	if not packet.is_empty():
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
		var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
		var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
		for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
			if not _index_is_solid(index, terrain_ids, walkable_flags, mountain_ids, mountain_flags):
				continue
			var world_tile: Vector2i = target_chunk * WorldRuntimeConstants.CHUNK_SIZE + WorldRuntimeConstants.index_to_local(index)
			min_tile.x = mini(min_tile.x, world_tile.x)
			min_tile.y = mini(min_tile.y, world_tile.y)
			max_tile.x = maxi(max_tile.x, world_tile.x)
			max_tile.y = maxi(max_tile.y, world_tile.y)
	if min_tile.x > max_tile.x:
		return WorldRuntimeConstants.chunk_origin_px(target_chunk) \
			+ Vector2.ONE * float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX) * 0.5
	var center_x: float = (float(min_tile.x) + float(max_tile.x) + 1.0) * 0.5 * float(WorldRuntimeConstants.TILE_SIZE_PX)
	var south_y: float = float(max_tile.y + 1) * float(WorldRuntimeConstants.TILE_SIZE_PX)
	return Vector2(center_x, south_y + FACADE_SHOW_PX * 0.3)

func _build_solid_halo(center_chunk: Vector2i, packet_map: Dictionary) -> PackedByteArray:
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + HALO_RADIUS_TILES * 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(halo_side * halo_side)
	for halo_y: int in range(halo_side):
		for halo_x: int in range(halo_side):
			var local_coord := Vector2i(halo_x - HALO_RADIUS_TILES, halo_y - HALO_RADIUS_TILES)
			var world_tile: Vector2i = center_chunk * WorldRuntimeConstants.CHUNK_SIZE + local_coord
			if _tile_is_solid(world_tile, packet_map):
				solid_halo[halo_y * halo_side + halo_x] = 1
	return solid_halo

func _tile_is_solid(world_tile: Vector2i, packet_map: Dictionary) -> bool:
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(world_tile)
	var packet: Dictionary = packet_map.get(chunk_coord, {}) as Dictionary
	if packet.is_empty():
		return false
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(world_tile)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	return _index_is_solid(index, terrain_ids, walkable_flags, mountain_ids, mountain_flags)

func _index_is_solid(
	index: int,
	terrain_ids: PackedInt32Array,
	walkable_flags: PackedByteArray,
	mountain_ids: PackedInt32Array,
	mountain_flags: PackedByteArray
) -> bool:
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return false
	var terrain_id: int = int(terrain_ids[index])
	if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return false
	if int(walkable_flags[index]) != 0:
		return false
	if index >= mountain_ids.size() or int(mountain_ids[index]) <= 0:
		return false
	if index >= mountain_flags.size():
		return false
	var flags: int = int(mountain_flags[index])
	return (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0

func _build_settings_packed() -> PackedFloat32Array:
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = LAKE_DENSITY
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	mountain.density = DENSITY
	var packed: PackedFloat32Array = mountain.flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	return lakes.write_to_settings_packed(packed)

func _load_preset() -> Dictionary:
	var file: FileAccess = FileAccess.open(PRESET_PATH, FileAccess.READ)
	if file == null:
		return MountainPlateau2DRasterLayer.default_preset()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	return MountainPlateau2DRasterLayer.default_preset()

func _prepare_output_dir() -> void:
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("artifacts/mountain_look_compare")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true

func _finish() -> void:
	get_tree().quit(1 if _failed else 0)

func _finish_failed() -> void:
	_failed = true
	get_tree().quit(1)
