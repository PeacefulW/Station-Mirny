class_name MiningFeedbackLayer
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const MAX_BURSTS: int = 18
const BURST_DURATION: float = 1.12
const DUST_DURATION: float = 0.54
const CHIP_DURATION: float = 0.48
const DECAL_DURATION: float = 1.08

var _bursts: Array[Dictionary] = []
var _sequence: int = 0

func _ready() -> void:
	set_process(false)

func clear_feedback() -> void:
	_bursts.clear()
	set_process(false)
	queue_redraw()

func spawn_mountain_mining_feedback(world_tile: Vector2i, impact_world_pos: Vector2 = Vector2(INF, INF)) -> void:
	var origin: Vector2 = impact_world_pos
	if not origin.is_finite():
		origin = WorldRuntimeConstants.tile_to_world_center(world_tile)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for_tile(world_tile, _sequence)
	_sequence += 1

	var dust: Array[Dictionary] = []
	for index: int in range(8):
		var angle: float = rng.randf_range(-PI, PI)
		var speed: float = rng.randf_range(16.0, 58.0)
		dust.append({
			"offset": Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-10.0, 12.0)),
			"velocity": Vector2(cos(angle), sin(angle)) * speed + Vector2(0.0, rng.randf_range(-22.0, 18.0)),
			"radius": rng.randf_range(5.0, 12.0),
			"growth": rng.randf_range(14.0, 24.0),
			"alpha": rng.randf_range(0.18, 0.34),
		})

	var chips: Array[Dictionary] = []
	for index: int in range(7):
		var angle: float = rng.randf_range(-PI * 0.95, -PI * 0.05)
		var speed: float = rng.randf_range(38.0, 112.0)
		chips.append({
			"offset": Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-12.0, 10.0)),
			"velocity": Vector2(cos(angle), sin(angle)) * speed,
			"size": rng.randf_range(2.2, 5.2),
			"spin": rng.randf_range(-8.0, 8.0),
			"angle": rng.randf_range(-PI, PI),
			"light": rng.randf_range(0.55, 1.0),
		})

	var decals: Array[Dictionary] = []
	for index: int in range(4):
		var angle: float = rng.randf_range(-0.85, 0.85)
		var length: float = rng.randf_range(10.0, 24.0)
		var direction := Vector2(cos(angle), sin(angle) * 0.45).normalized()
		var center := Vector2(rng.randf_range(-17.0, 17.0), rng.randf_range(-12.0, 14.0))
		decals.append({
			"from": center - direction * length * 0.5,
			"to": center + direction * length * 0.5,
			"width": rng.randf_range(1.3, 2.2),
			"alpha": rng.randf_range(0.16, 0.30),
		})

	_bursts.append({
		"age": 0.0,
		"origin": origin,
		"dust": dust,
		"chips": chips,
		"decals": decals,
	})
	while _bursts.size() > MAX_BURSTS:
		_bursts.pop_front()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	for index: int in range(_bursts.size() - 1, -1, -1):
		var burst: Dictionary = _bursts[index]
		var age: float = float(burst.get("age", 0.0)) + delta
		if age >= BURST_DURATION:
			_bursts.remove_at(index)
			continue
		burst["age"] = age
		_bursts[index] = burst
	if _bursts.is_empty():
		set_process(false)
	queue_redraw()

func _draw() -> void:
	for burst_variant: Variant in _bursts:
		var burst: Dictionary = burst_variant as Dictionary
		var age: float = float(burst.get("age", 0.0))
		var origin: Vector2 = burst.get("origin", Vector2.ZERO) as Vector2
		_draw_decals(origin, burst.get("decals", []) as Array, age)
		_draw_dust(origin, burst.get("dust", []) as Array, age)
		_draw_chips(origin, burst.get("chips", []) as Array, age)

func _draw_dust(origin: Vector2, dust: Array, age: float) -> void:
	var t: float = clampf(age / DUST_DURATION, 0.0, 1.0)
	if t >= 1.0:
		return
	var fade: float = pow(1.0 - t, 1.8)
	for dust_variant: Variant in dust:
		var particle: Dictionary = dust_variant as Dictionary
		var pos: Vector2 = origin \
			+ (particle.get("offset", Vector2.ZERO) as Vector2) \
			+ (particle.get("velocity", Vector2.ZERO) as Vector2) * age
		var radius: float = float(particle.get("radius", 6.0)) + float(particle.get("growth", 16.0)) * t
		var alpha: float = float(particle.get("alpha", 0.22)) * fade
		draw_circle(pos, radius, Color(0.54, 0.38, 0.24, alpha))

func _draw_chips(origin: Vector2, chips: Array, age: float) -> void:
	var t: float = clampf(age / CHIP_DURATION, 0.0, 1.0)
	if t >= 1.0:
		return
	var fade: float = pow(1.0 - t, 1.35)
	for chip_variant: Variant in chips:
		var chip: Dictionary = chip_variant as Dictionary
		var pos: Vector2 = origin \
			+ (chip.get("offset", Vector2.ZERO) as Vector2) \
			+ (chip.get("velocity", Vector2.ZERO) as Vector2) * age \
			+ Vector2(0.0, 120.0) * age * age
		var size: float = float(chip.get("size", 3.0))
		var angle: float = float(chip.get("angle", 0.0)) + float(chip.get("spin", 0.0)) * age
		var right := Vector2(cos(angle), sin(angle))
		var up := Vector2(-right.y, right.x)
		var points := PackedVector2Array([
			pos + right * size,
			pos - right * size * 0.55 + up * size * 0.72,
			pos - right * size * 0.45 - up * size * 0.58,
		])
		var light: float = float(chip.get("light", 0.75))
		draw_colored_polygon(points, Color(0.34 * light, 0.19 * light, 0.10 * light, 0.92 * fade))

func _draw_decals(origin: Vector2, decals: Array, age: float) -> void:
	var t: float = clampf(age / DECAL_DURATION, 0.0, 1.0)
	if t >= 1.0:
		return
	var fade: float = pow(1.0 - t, 0.82)
	for decal_variant: Variant in decals:
		var decal: Dictionary = decal_variant as Dictionary
		draw_line(
			origin + (decal.get("from", Vector2.ZERO) as Vector2),
			origin + (decal.get("to", Vector2.ZERO) as Vector2),
			Color(0.08, 0.035, 0.018, float(decal.get("alpha", 0.2)) * fade),
			float(decal.get("width", 1.5)),
			true
		)

func _seed_for_tile(world_tile: Vector2i, sequence: int) -> int:
	var value: int = int(world_tile.x) * 73856093
	value = value ^ (int(world_tile.y) * 19349663)
	value = value ^ (sequence * 83492791)
	return absi(value)
