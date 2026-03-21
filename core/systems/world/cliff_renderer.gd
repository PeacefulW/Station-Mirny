class_name CliffRenderer
extends Node2D

## Рисует клиф-спрайты по краям горных формаций в чанке.
## Вызывается из Chunk после populate_native.

const CLIFF_SIDES_PATH: String = "res://assets/textures/cliffs/cliff-sides.png"
const CLIFF_OUTER_PATH: String = "res://assets/textures/cliffs/cliff-outer.png"
const CLIFF_INNER_PATH: String = "res://assets/textures/cliffs/cliff-inner.png"

var _cliff_container: Node2D = null
var _texture_cache: Dictionary = {}

## Создать клифы для чанка.
func build_cliffs(terrain_bytes: PackedByteArray, chunk_size: int, tile_size: int, _chunk_coord: Vector2i) -> void:
	if _cliff_container:
		_cliff_container.queue_free()
	_cliff_container = Node2D.new()
	_cliff_container.name = "Cliffs"
	_cliff_container.z_index = -5
	add_child(_cliff_container)

	for ly: int in range(chunk_size):
		for lx: int in range(chunk_size):
			var idx: int = ly * chunk_size + lx
			if idx >= terrain_bytes.size():
				continue
			var terr: int = terrain_bytes[idx]
			if terr != 1:  # Только ROCK
				continue

			var n_rock: bool = _is_rock(terrain_bytes, lx, ly - 1, chunk_size)
			var s_rock: bool = _is_rock(terrain_bytes, lx, ly + 1, chunk_size)
			var e_rock: bool = _is_rock(terrain_bytes, lx + 1, ly, chunk_size)
			var w_rock: bool = _is_rock(terrain_bytes, lx - 1, ly, chunk_size)

			var cliff_type: CliffRegistry.CliffType = CliffRegistry.get_cliff_type(
				n_rock, e_rock, s_rock, w_rock
			)
			if cliff_type == CliffRegistry.CliffType.NONE:
				continue

			_place_cliff_sprite(lx, ly, cliff_type, tile_size)

func _is_rock(data: PackedByteArray, x: int, y: int, cs: int) -> bool:
	if x < 0 or x >= cs or y < 0 or y >= cs:
		return false
	var idx: int = y * cs + x
	return idx < data.size() and data[idx] == 1

func _place_cliff_sprite(lx: int, ly: int, cliff_type: CliffRegistry.CliffType, ts: int) -> void:
	var pos := Vector2(lx * ts + ts * 0.5, ly * ts + ts * 0.5)
	var config: Dictionary = _get_atlas_config(cliff_type)
	if config.is_empty():
		return

	var tex: Texture2D = _load_cliff_texture(config.get("atlas", "sides"))
	if not tex:
		return

	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = tex
	atlas_tex.region = config.get("region", Rect2(0, 0, 250, 333))

	var sprite := Sprite2D.new()
	sprite.texture = atlas_tex
	sprite.position = pos + config.get("offset", Vector2.ZERO)
	sprite.scale = config.get("scale", Vector2(0.05, 0.05))
	sprite.z_index = 0
	_cliff_container.add_child(sprite)

## Конфигурация спрайта для каждого типа клифа.
## region — область в атласе. offset — сдвиг от центра тайла. scale — масштаб.
func _get_atlas_config(cliff_type: CliffRegistry.CliffType) -> Dictionary:
	# Атласы 2048×1024. 8 столбцов (256px) × 3 ряда (341px).
	# scale ≈ 12/256 ≈ 0.05
	var sc := Vector2(0.05, 0.05)
	var cw: float = 256.0
	var ch: float = 341.0
	match cliff_type:
		CliffRegistry.CliffType.SIDE_S:
			return {"atlas": "sides", "region": Rect2(0, ch * 2, cw, ch), "offset": Vector2(0, 6), "scale": sc}
		CliffRegistry.CliffType.SIDE_N:
			return {"atlas": "sides", "region": Rect2(cw, 0, cw, ch), "offset": Vector2(0, -3), "scale": sc}
		CliffRegistry.CliffType.SIDE_E:
			return {"atlas": "sides", "region": Rect2(cw * 2, ch, cw, ch), "offset": Vector2(3, 0), "scale": sc}
		CliffRegistry.CliffType.SIDE_W:
			return {"atlas": "sides", "region": Rect2(cw * 3, ch, cw, ch), "offset": Vector2(-3, 0), "scale": sc}
		CliffRegistry.CliffType.OUTER_SE:
			return {"atlas": "outer", "region": Rect2(0, ch * 2, cw, ch), "offset": Vector2(3, 3), "scale": sc}
		CliffRegistry.CliffType.OUTER_SW:
			return {"atlas": "outer", "region": Rect2(cw, ch * 2, cw, ch), "offset": Vector2(-3, 3), "scale": sc}
		CliffRegistry.CliffType.OUTER_NE:
			return {"atlas": "outer", "region": Rect2(cw * 2, 0, cw, ch), "offset": Vector2(3, -3), "scale": sc}
		CliffRegistry.CliffType.OUTER_NW:
			return {"atlas": "outer", "region": Rect2(cw * 3, 0, cw, ch), "offset": Vector2(-3, -3), "scale": sc}
		CliffRegistry.CliffType.INNER_SE:
			return {"atlas": "inner", "region": Rect2(0, ch * 2, cw, ch), "offset": Vector2(3, 3), "scale": sc}
		CliffRegistry.CliffType.INNER_SW:
			return {"atlas": "inner", "region": Rect2(cw, ch * 2, cw, ch), "offset": Vector2(-3, 3), "scale": sc}
		CliffRegistry.CliffType.INNER_NE:
			return {"atlas": "inner", "region": Rect2(cw * 2, 0, cw, ch), "offset": Vector2(3, -3), "scale": sc}
		CliffRegistry.CliffType.INNER_NW:
			return {"atlas": "inner", "region": Rect2(cw * 3, 0, cw, ch), "offset": Vector2(-3, -3), "scale": sc}
	return {}

func _load_cliff_texture(atlas_name: String) -> Texture2D:
	if _texture_cache.has(atlas_name):
		return _texture_cache[atlas_name]
	var path: String = ""
	match atlas_name:
		"sides": path = CLIFF_SIDES_PATH
		"outer": path = CLIFF_OUTER_PATH
		"inner": path = CLIFF_INNER_PATH
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path) as Texture2D
	_texture_cache[atlas_name] = tex
	return tex
