class_name WorldTileSetFactory
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const PLAINS_TEXTURE: Texture2D = preload("res://assets/textures/terrain/terrain_plains.png")
const ROCK_TEXTURE: Texture2D = preload("res://assets/textures/terrain/terrain_rock.png")
const DUG_TEXTURE: Texture2D = preload("res://assets/textures/terrain/terrain_shore.png")

static var _tile_set: TileSet = null
static var _source_ids: Dictionary = {}

static func get_tile_set() -> TileSet:
	_ensure_tileset()
	return _tile_set

static func get_source_id(terrain_id: int) -> int:
	_ensure_tileset()
	return int(_source_ids.get(terrain_id, _source_ids[WorldRuntimeConstants.TERRAIN_PLAINS_GROUND]))

static func get_atlas_coords(_terrain_id: int) -> Vector2i:
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
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND: _tile_set.add_source(_build_source(PLAINS_TEXTURE)),
		WorldRuntimeConstants.TERRAIN_PLAINS_ROCK: _tile_set.add_source(_build_source(ROCK_TEXTURE)),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG: _tile_set.add_source(_build_source(DUG_TEXTURE)),
	}

static func _build_source(texture: Texture2D) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(
		WorldRuntimeConstants.TILE_SIZE_PX,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	source.create_tile(Vector2i.ZERO)
	return source
