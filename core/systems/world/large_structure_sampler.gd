class_name LargeStructureSampler
extends RefCounted

const WORLD_STRUCTURE_CONTEXT_SCRIPT := preload("res://core/systems/world/world_structure_context.gd")

const _RIDGE_DIR := Vector2(0.86, 0.51)
const _RIVER_DIR := Vector2(-0.38, 0.92)

var _world_seed: int = 0
var _balance: WorldGenBalance = null
var _ridge_warp_noise: FastNoiseLite = FastNoiseLite.new()
var _ridge_cluster_noise: FastNoiseLite = FastNoiseLite.new()
var _river_warp_noise: FastNoiseLite = FastNoiseLite.new()

func initialize(seed_value: int, balance_resource: WorldGenBalance) -> void:
	_world_seed = seed_value
	_balance = balance_resource
	if not _balance:
		return
	_setup_noise_instance(_ridge_warp_noise, _world_seed + 211, _balance.ridge_warp_frequency, 2)
	_setup_noise_instance(_ridge_cluster_noise, _world_seed + 223, _balance.ridge_cluster_frequency, 3)
	_setup_noise_instance(_river_warp_noise, _world_seed + 241, _balance.river_warp_frequency, 2)

func sample_structure_context(world_pos: Vector2i, channels = null):
	var context = WORLD_STRUCTURE_CONTEXT_SCRIPT.new()
	context.world_pos = world_pos
	context.canonical_world_pos = canonicalize_world_pos(world_pos)
	var height_value: float = _channel_value(channels, "height", 0.5)
	var ruggedness_value: float = _channel_value(channels, "ruggedness", 0.5)
	var moisture_value: float = _channel_value(channels, "moisture", 0.5)
	context.mountain_mass = _sample_mountain_mass(context.canonical_world_pos, height_value, ruggedness_value)
	context.ridge_strength = _sample_ridge_strength(context.canonical_world_pos, context.mountain_mass, height_value, ruggedness_value)
	context.river_strength = _sample_river_strength(
		context.canonical_world_pos,
		context.ridge_strength,
		context.mountain_mass,
		height_value,
		ruggedness_value,
		moisture_value
	)
	context.floodplain_strength = _sample_floodplain_strength(
		context.canonical_world_pos,
		context.river_strength,
		context.mountain_mass,
		height_value,
		ruggedness_value,
		moisture_value
	)
	return context.clamp_fields()

func canonicalize_world_pos(world_pos: Vector2i) -> Vector2i:
	return Vector2i(wrap_world_x(world_pos.x), world_pos.y)

func wrap_world_x(world_x: int) -> int:
	var width: int = _resolve_wrap_width_tiles()
	if width <= 0:
		return world_x
	return int(posmod(world_x, width))

func get_wrap_width_tiles() -> int:
	return _resolve_wrap_width_tiles()

func _sample_mountain_mass(world_pos: Vector2i, height_value: float, ruggedness_value: float) -> float:
	var cluster_noise: float = _sample_periodic_noise01(_ridge_cluster_noise, world_pos)
	var cluster_gate: float = clampf((cluster_noise - 0.34) / 0.52, 0.0, 1.0)
	var terrain_gate: float = clampf(height_value * 0.65 + ruggedness_value * 0.85 - 0.30, 0.0, 1.0)
	return clampf(cluster_gate * terrain_gate, 0.0, 1.0)

func _sample_ridge_strength(world_pos: Vector2i, mountain_mass: float, height_value: float, ruggedness_value: float) -> float:
	var ridge_coord: float = _directed_coordinate(world_pos, _RIDGE_DIR)
	ridge_coord += _sample_periodic_noise_signed(_ridge_warp_noise, world_pos) * _balance.ridge_warp_amplitude_tiles
	var band_strength: float = _sample_repeating_band(
		ridge_coord,
		float(_balance.ridge_spacing_tiles),
		_balance.ridge_core_width_tiles,
		_balance.ridge_feather_tiles
	)
	var terrain_gate: float = clampf(height_value * 0.55 + ruggedness_value * 0.95 - 0.24, 0.0, 1.0)
	var mass_gate: float = lerpf(0.30, 1.0, mountain_mass)
	return clampf(band_strength * terrain_gate * mass_gate, 0.0, 1.0)

func _sample_river_strength(
	world_pos: Vector2i,
	ridge_strength: float,
	mountain_mass: float,
	height_value: float,
	ruggedness_value: float,
	moisture_value: float
) -> float:
	var river_coord: float = _directed_coordinate(world_pos, _RIVER_DIR)
	river_coord += _sample_periodic_noise_signed(_river_warp_noise, world_pos) * _balance.river_warp_amplitude_tiles
	var band_strength: float = _sample_repeating_band(
		river_coord,
		float(_balance.river_spacing_tiles),
		_balance.river_core_width_tiles,
		_balance.river_floodplain_width_tiles * 0.45
	)
	var lowland_gate: float = clampf(1.0 - (height_value * 0.95 + ruggedness_value * 0.65), 0.0, 1.0)
	var moisture_gate: float = clampf(0.40 + moisture_value * 0.60, 0.0, 1.0)
	var mountain_penalty: float = clampf(1.0 - ridge_strength * 0.55 - mountain_mass * 0.30, 0.10, 1.0)
	return clampf(band_strength * lowland_gate * moisture_gate * mountain_penalty, 0.0, 1.0)

func _sample_floodplain_strength(
	world_pos: Vector2i,
	river_strength: float,
	mountain_mass: float,
	height_value: float,
	ruggedness_value: float,
	moisture_value: float
) -> float:
	var river_coord: float = _directed_coordinate(world_pos, _RIVER_DIR)
	river_coord += _sample_periodic_noise_signed(_river_warp_noise, world_pos) * _balance.river_warp_amplitude_tiles
	var floodplain_band: float = _sample_repeating_band(
		river_coord,
		float(_balance.river_spacing_tiles),
		_balance.river_core_width_tiles * 2.5,
		_balance.river_floodplain_width_tiles
	)
	var lowland_gate: float = clampf(1.0 - (height_value * 0.80 + ruggedness_value * 0.45), 0.0, 1.0)
	var moisture_gate: float = clampf(0.25 + moisture_value * 0.75, 0.0, 1.0)
	var mountain_penalty: float = clampf(1.0 - mountain_mass * 0.50, 0.20, 1.0)
	return clampf(maxf(river_strength * 0.55, floodplain_band * lowland_gate * moisture_gate * mountain_penalty), 0.0, 1.0)

func _directed_coordinate(world_pos: Vector2i, direction: Vector2) -> float:
	return float(world_pos.x) * direction.normalized().x + float(world_pos.y) * direction.normalized().y

func _sample_repeating_band(coord: float, spacing: float, core_half_width: float, feather_width: float) -> float:
	if spacing <= 0.001:
		return 0.0
	var wrapped_coord: float = fposmod(coord + spacing * 0.5, spacing) - spacing * 0.5
	var distance_to_center: float = absf(wrapped_coord)
	if distance_to_center <= core_half_width:
		return 1.0
	if feather_width <= 0.001:
		return 0.0
	return clampf(1.0 - ((distance_to_center - core_half_width) / feather_width), 0.0, 1.0)

func _channel_value(channels, property_name: String, fallback_value: float) -> float:
	if channels == null:
		return fallback_value
	var value: Variant = channels.get(property_name) if channels is Object else fallback_value
	if value is float:
		return value
	if value is int:
		return float(value)
	return fallback_value

func _sample_periodic_noise_signed(noise: FastNoiseLite, world_pos: Vector2i) -> float:
	return _sample_periodic_noise01(noise, world_pos) * 2.0 - 1.0

func _sample_periodic_noise01(noise: FastNoiseLite, world_pos: Vector2i) -> float:
	var width: int = _resolve_wrap_width_tiles()
	if width <= 0:
		return _sample01(noise.get_noise_2d(world_pos.x, world_pos.y))
	var wrapped_x: int = wrap_world_x(world_pos.x)
	var angle: float = TAU * float(wrapped_x) / float(width)
	var ring_radius: float = float(width) / TAU
	var sample_x: float = cos(angle) * ring_radius
	var sample_y: float = float(world_pos.y)
	var sample_z: float = sin(angle) * ring_radius
	return _sample01(noise.get_noise_3d(sample_x, sample_y, sample_z))

func _setup_noise_instance(noise: FastNoiseLite, seed_value: int, frequency: float, octaves: int) -> void:
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.55
	noise.fractal_lacunarity = 2.1
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

func _resolve_wrap_width_tiles() -> int:
	if not _balance:
		return 4096
	var tile_width: int = maxi(256, _balance.world_wrap_width_tiles)
	var chunk_size: int = maxi(1, _balance.chunk_size_tiles)
	var chunk_count: int = maxi(1, int(ceili(float(tile_width) / float(chunk_size))))
	return chunk_count * chunk_size

func _sample01(value: float) -> float:
	return value * 0.5 + 0.5
