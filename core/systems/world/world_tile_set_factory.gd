class_name WorldTileSetFactory
extends RefCounted

const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const PLAINS_TEXTURE: Texture2D = preload("res://assets/textures/terrain/terrain_plains.png")
const ROCK_ATLAS_TEXTURE: Texture2D = preload("res://assets/sprites/terrain/plain_rock_atlas.png")
const DUG_TEXTURE: Texture2D = preload("res://assets/textures/terrain/terrain_shore.png")

static var _tile_set: TileSet = null
static var _source_ids: Dictionary = {}

static func get_tile_set() -> TileSet:
	_ensure_tileset()
	return _tile_set

static func get_source_id(terrain_id: int) -> int:
	_ensure_tileset()
	return int(_source_ids.get(terrain_id, _source_ids[WorldRuntimeConstants.TERRAIN_PLAINS_GROUND]))

static func get_atlas_coords(terrain_id: int, atlas_index: int = 0) -> Vector2i:
	if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_ROCK:
		return Autotile47.atlas_index_to_coords(atlas_index)
	return Vector2i.ZERO

static func _ensure_tileset() -> void:
	if _tile_set != null:
		return
	_tile_set = TileSet.new()
	_tile_set.tile_size = Vector2i(
		WorldRuntimeConstants.TILE_SIZE_PX,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	_source_ids = {
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND: _tile_set.add_source(_build_single_tile_source(PLAINS_TEXTURE)),
		WorldRuntimeConstants.TERRAIN_PLAINS_ROCK: _tile_set.add_source(
			Autotile47.build_full_atlas_source(
				ROCK_ATLAS_TEXTURE,
				WorldRuntimeConstants.TILE_SIZE_PX
			)
		),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG: _tile_set.add_source(_build_single_tile_source(DUG_TEXTURE)),
	}

static func _build_single_tile_source(texture: Texture2D) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(
		WorldRuntimeConstants.TILE_SIZE_PX,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	source.create_tile(Vector2i.ZERO)
	return source
