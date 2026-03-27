class_name WorldPreviewExporter
extends RefCounted

const OUTPUT_ROOT: String = "res://debug_exports/world_previews"
const PREVIEW_WIDTH: int = 1024
const MAX_PREVIEW_HEIGHT: int = 2048

var _world_generator: WorldGeneratorSingleton = null

func initialize(world_generator: WorldGeneratorSingleton) -> WorldPreviewExporter:
	_world_generator = world_generator
	return self

func export_current_world_preview() -> Dictionary:
	if not _can_export():
		return {}
	var spec: Dictionary = _build_preview_spec()
	var biome_image: Image = Image.create(spec["width"], spec["height"], false, Image.FORMAT_RGBA8)
	var terrain_image: Image = Image.create(spec["width"], spec["height"], false, Image.FORMAT_RGBA8)
	var structure_image: Image = Image.create(spec["width"], spec["height"], false, Image.FORMAT_RGBA8)
	for pixel_y: int in range(int(spec["height"])):
		var tile_y: int = _sample_tile_y(pixel_y, int(spec["height"]), int(spec["min_y"]), int(spec["max_y"]))
		for pixel_x: int in range(int(spec["width"])):
			var tile_x: int = _sample_tile_x(pixel_x, int(spec["width"]), int(spec["wrap_width"]))
			var tile_data: TileGenData = _world_generator.get_tile_data(tile_x, tile_y)
			var biome: BiomeData = _world_generator.get_biome_by_id(tile_data.biome_id)
			biome_image.set_pixel(pixel_x, pixel_y, _resolve_biome_preview_color(biome))
			terrain_image.set_pixel(pixel_x, pixel_y, _resolve_terrain_preview_color(tile_data, biome))
			structure_image.set_pixel(pixel_x, pixel_y, _resolve_structure_preview_color(tile_data))
	var output_dir: String = _ensure_output_directory()
	if output_dir.is_empty():
		return {}
	var prefix: String = "seed_%d_%d" % [_world_generator.world_seed, Time.get_unix_time_from_system()]
	var biome_path: String = output_dir.path_join("%s_biomes.png" % prefix)
	var terrain_path: String = output_dir.path_join("%s_terrain.png" % prefix)
	var structure_path: String = output_dir.path_join("%s_structures.png" % prefix)
	biome_image.save_png(biome_path)
	terrain_image.save_png(terrain_path)
	structure_image.save_png(structure_path)
	return {
		"biomes": biome_path,
		"terrain": terrain_path,
		"structures": structure_path,
	}

func _can_export() -> bool:
	return _world_generator != null \
		and _world_generator._is_initialized \
		and _world_generator.balance != null

func _build_preview_spec() -> Dictionary:
	var wrap_width: int = maxi(1, _world_generator.get_world_wrap_width_tiles())
	var half_span: int = maxi(1, _world_generator.balance.latitude_half_span_tiles)
	var total_height_tiles: int = half_span * 2
	var preview_height: int = int(round(float(PREVIEW_WIDTH) * float(total_height_tiles) / float(wrap_width)))
	preview_height = clampi(preview_height, 256, MAX_PREVIEW_HEIGHT)
	var equator_y: int = _world_generator.balance.equator_tile_y
	return {
		"width": PREVIEW_WIDTH,
		"height": preview_height,
		"wrap_width": wrap_width,
		"min_y": equator_y - half_span,
		"max_y": equator_y + half_span - 1,
	}

func _sample_tile_x(pixel_x: int, width: int, wrap_width: int) -> int:
	if width <= 1:
		return 0
	return int(round(float(pixel_x) * float(wrap_width - 1) / float(width - 1)))

func _sample_tile_y(pixel_y: int, height: int, min_y: int, max_y: int) -> int:
	if height <= 1:
		return min_y
	return min_y + int(round(float(pixel_y) * float(max_y - min_y) / float(height - 1)))

func _resolve_biome_preview_color(biome: BiomeData) -> Color:
	if biome == null:
		return Color(0.2, 0.2, 0.2, 1.0)
	return biome.ground_color.lightened(0.08)

func _resolve_terrain_preview_color(tile_data: TileGenData, biome: BiomeData) -> Color:
	if tile_data == null:
		return Color(0.0, 0.0, 0.0, 1.0)
	var ground_color: Color = biome.ground_color if biome else Color(0.32, 0.28, 0.22, 1.0)
	var grass_color: Color = biome.grass_color if biome else Color(0.35, 0.55, 0.18, 1.0)
	match tile_data.terrain:
		TileGenData.TerrainType.ROCK:
			return Color(0.60, 0.63, 0.70, 1.0)
		TileGenData.TerrainType.WATER:
			return Color(0.08, 0.46, 0.90, 1.0)
		TileGenData.TerrainType.SAND:
			return Color(0.78, 0.68, 0.34, 1.0)
		TileGenData.TerrainType.GRASS:
			return grass_color.lightened(0.06)
		TileGenData.TerrainType.MINED_FLOOR:
			return Color(0.52, 0.46, 0.36, 1.0)
		TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			return Color(0.70, 0.54, 0.24, 1.0)
		_:
			return _apply_variation_preview(ground_color, tile_data.local_variation_id, grass_color)

func _apply_variation_preview(base_color: Color, variation_id: int, grass_color: Color) -> Color:
	match variation_id:
		ChunkTilesetFactory.SURFACE_VARIATION_SPARSE_FLORA:
			return base_color.lerp(grass_color, 0.30)
		ChunkTilesetFactory.SURFACE_VARIATION_DENSE_FLORA:
			return base_color.lerp(grass_color, 0.60)
		ChunkTilesetFactory.SURFACE_VARIATION_CLEARING:
			return base_color.lightened(0.10)
		ChunkTilesetFactory.SURFACE_VARIATION_ROCKY_PATCH:
			return base_color.lerp(Color(0.55, 0.55, 0.58, 1.0), 0.45)
		ChunkTilesetFactory.SURFACE_VARIATION_WET_PATCH:
			return base_color.lerp(Color(0.10, 0.40, 0.55, 1.0), 0.35)
		_:
			return base_color

func _resolve_structure_preview_color(tile_data: TileGenData) -> Color:
	if tile_data == null:
		return Color.BLACK
	var ridge: float = tile_data.ridge_strength
	var mass: float = tile_data.mountain_mass
	var river: float = tile_data.river_strength
	var flood: float = tile_data.floodplain_strength
	return Color(
		clampf(mass * 0.45 + ridge * 0.85, 0.0, 1.0),
		clampf(flood * 0.55 + mass * 0.20, 0.0, 1.0),
		clampf(river * 0.95 + flood * 0.40, 0.0, 1.0),
		1.0
	)

func _ensure_output_directory() -> String:
	var absolute_path: String = ProjectSettings.globalize_path(OUTPUT_ROOT)
	var dir_result: Error = DirAccess.make_dir_recursive_absolute(absolute_path)
	if dir_result != OK and not DirAccess.dir_exists_absolute(absolute_path):
		return ""
	return absolute_path
