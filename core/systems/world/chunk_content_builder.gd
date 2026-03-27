class_name ChunkContentBuilder
extends RefCounted

var _world_context: RefCounted = null
var _terrain_resolver: RefCounted = null
var _balance: WorldGenBalance = null

func initialize(balance_resource: WorldGenBalance, world_context: RefCounted, terrain_resolver: RefCounted) -> void:
	_balance = balance_resource
	_world_context = world_context
	_terrain_resolver = terrain_resolver
	if not _balance:
		return

func build_chunk(chunk_coord: Vector2i) -> ChunkBuildResult:
	var canonical_chunk: Vector2i = _canonicalize_chunk_coord(chunk_coord)
	var base_tile: Vector2i = _chunk_to_tile_origin(canonical_chunk)
	var result: ChunkBuildResult = ChunkBuildResult.new().initialize(canonical_chunk, _chunk_size(), base_tile)
	if not result.is_valid():
		return result
	var chunk_size: int = result.chunk_size
	var spawn_tile: Vector2i = _world_context.spawn_tile if _world_context else Vector2i.ZERO
	var tile_data: TileGenData = TileGenData.new()
	var canonical_tile: Vector2i = base_tile
	var row_index: int = 0
	for local_y: int in range(chunk_size):
		canonical_tile.x = base_tile.x
		canonical_tile.y = base_tile.y + local_y
		for local_x: int in range(chunk_size):
			var index: int = row_index + local_x
			_terrain_resolver.populate_chunk_build_data(canonical_tile, spawn_tile, tile_data)
			result.set_tile(
				index,
				tile_data.terrain,
				tile_data.height,
				tile_data.local_variation_id,
				tile_data.biome_palette_index,
				tile_data.flora_density,
				tile_data.flora_modulation
			)
			canonical_tile.x += 1
		row_index += chunk_size
	return result

func build_chunk_native_data(chunk_coord: Vector2i) -> Dictionary:
	var canonical_chunk: Vector2i = _canonicalize_chunk_coord(chunk_coord)
	var base_tile: Vector2i = _chunk_to_tile_origin(canonical_chunk)
	var chunk_size: int = _chunk_size()
	if chunk_size <= 0:
		return {}
	var tile_count: int = chunk_size * chunk_size
	var terrain := PackedByteArray()
	var height := PackedFloat32Array()
	var variation := PackedByteArray()
	var biome := PackedByteArray()
	var flora_density_values := PackedFloat32Array()
	var flora_modulation_values := PackedFloat32Array()
	terrain.resize(tile_count)
	height.resize(tile_count)
	variation.resize(tile_count)
	biome.resize(tile_count)
	flora_density_values.resize(tile_count)
	flora_modulation_values.resize(tile_count)
	var spawn_tile: Vector2i = _world_context.spawn_tile if _world_context else Vector2i.ZERO
	var tile_data: TileGenData = TileGenData.new()
	var canonical_tile: Vector2i = base_tile
	var row_index: int = 0
	for local_y: int in range(chunk_size):
		canonical_tile.x = base_tile.x
		canonical_tile.y = base_tile.y + local_y
		for local_x: int in range(chunk_size):
			var index: int = row_index + local_x
			_terrain_resolver.populate_chunk_build_data(canonical_tile, spawn_tile, tile_data)
			terrain[index] = tile_data.terrain
			height[index] = tile_data.height
			variation[index] = tile_data.local_variation_id
			biome[index] = tile_data.biome_palette_index
			flora_density_values[index] = tile_data.flora_density
			flora_modulation_values[index] = tile_data.flora_modulation
			canonical_tile.x += 1
		row_index += chunk_size
	return {
		"chunk_coord": canonical_chunk,
		"canonical_chunk_coord": canonical_chunk,
		"base_tile": base_tile,
		"chunk_size": chunk_size,
		"terrain": terrain,
		"height": height,
		"variation": variation,
		"biome": biome,
		"flora_density_values": flora_density_values,
		"flora_modulation_values": flora_modulation_values,
	}

func build_tile_data(tile_x: int, tile_y: int) -> TileGenData:
	if _terrain_resolver == null:
		return TileGenData.new()
	return _terrain_resolver.build_tile_data(Vector2i(tile_x, tile_y))

func sample_terrain_type(tile_x: int, tile_y: int) -> TileGenData.TerrainType:
	if _terrain_resolver == null:
		return TileGenData.TerrainType.GROUND
	return _terrain_resolver.sample_terrain_type(tile_x, tile_y)

func _chunk_size() -> int:
	return _balance.chunk_size_tiles if _balance else 0

func _canonicalize_chunk_coord(chunk_coord: Vector2i) -> Vector2i:
	if _terrain_resolver:
		return _terrain_resolver.canonicalize_chunk_coord(chunk_coord)
	return chunk_coord

func _chunk_to_tile_origin(chunk_coord: Vector2i) -> Vector2i:
	if _terrain_resolver:
		return _terrain_resolver.chunk_to_tile_origin(chunk_coord)
	return Vector2i.ZERO
