class_name PlanetSampler
extends RefCounted

const WORLD_CHANNELS_SCRIPT := preload("res://core/systems/world/world_channels.gd")

var _world_seed: int = 0
var _balance: WorldGenBalance = null
var _height_noise: FastNoiseLite = FastNoiseLite.new()
var _temperature_noise: FastNoiseLite = FastNoiseLite.new()
var _moisture_noise: FastNoiseLite = FastNoiseLite.new()
var _ruggedness_noise: FastNoiseLite = FastNoiseLite.new()
var _flora_density_noise: FastNoiseLite = FastNoiseLite.new()

func initialize(seed_value: int, balance_resource: WorldGenBalance) -> void:
	_world_seed = seed_value
	_balance = balance_resource
	if not _balance:
		return
	_setup_noise_instance(_height_noise, _world_seed + 11, _balance.height_frequency, _balance.height_octaves)
	_setup_noise_instance(_temperature_noise, _world_seed + 101, _balance.temperature_frequency, _balance.temperature_octaves)
	_setup_noise_instance(_moisture_noise, _world_seed + 131, _balance.moisture_frequency, _balance.moisture_octaves)
	_setup_noise_instance(_ruggedness_noise, _world_seed + 151, _balance.ruggedness_frequency, _balance.ruggedness_octaves)
	_setup_noise_instance(_flora_density_noise, _world_seed + 181, _balance.flora_density_frequency, _balance.flora_density_octaves)

func sample_world_channels(world_pos: Vector2i):
	var channels = WORLD_CHANNELS_SCRIPT.new()
	channels.world_pos = world_pos
	channels.canonical_world_pos = canonicalize_world_pos(world_pos)
	channels.latitude = sample_latitude(world_pos)
	channels.height = sample_height(world_pos)
	channels.temperature = _sample_temperature(world_pos, channels.latitude)
	channels.moisture = _sample_periodic_noise01(_moisture_noise, world_pos)
	channels.ruggedness = _sample_periodic_noise01(_ruggedness_noise, world_pos)
	channels.flora_density = _sample_flora_density(world_pos, channels.moisture)
	return channels

func sample_height(world_pos: Vector2i) -> float:
	return _sample_periodic_noise01(_height_noise, world_pos)

func sample_latitude(world_pos: Vector2i) -> float:
	var half_span: int = _resolve_latitude_half_span_tiles()
	if half_span <= 0:
		return 0.0
	var equator_y: int = _resolve_equator_tile_y()
	return clampf(absf(float(world_pos.y - equator_y)) / float(half_span), 0.0, 1.0)

func canonicalize_world_pos(world_pos: Vector2i) -> Vector2i:
	return Vector2i(wrap_world_x(world_pos.x), world_pos.y)

func wrap_world_x(world_x: int) -> int:
	var width: int = _resolve_wrap_width_tiles()
	if width <= 0:
		return world_x
	return int(posmod(world_x, width))

func get_wrap_width_tiles() -> int:
	return _resolve_wrap_width_tiles()

func _sample_temperature(world_pos: Vector2i, latitude: float) -> float:
	var climate_noise: float = _sample_periodic_noise01(_temperature_noise, world_pos)
	var climate_offset: float = (climate_noise - 0.5) * _resolve_temperature_noise_amplitude() * 2.0
	var latitude_temperature: float = 1.0 - pow(latitude, _resolve_latitude_temperature_curve())
	return clampf(
		lerpf(latitude_temperature + climate_offset, climate_noise, 1.0 - _resolve_temperature_latitude_weight()),
		0.0,
		1.0
	)

func _sample_flora_density(world_pos: Vector2i, moisture: float) -> float:
	var flora_noise: float = _sample_periodic_noise01(_flora_density_noise, world_pos)
	return clampf(lerpf(flora_noise, moisture, 0.35), 0.0, 1.0)

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

func _resolve_latitude_half_span_tiles() -> int:
	if not _balance:
		return 4096
	return maxi(256, _balance.latitude_half_span_tiles)

func _resolve_equator_tile_y() -> int:
	if not _balance:
		return 0
	return _balance.equator_tile_y

func _resolve_temperature_noise_amplitude() -> float:
	if not _balance:
		return 0.18
	return clampf(_balance.temperature_noise_amplitude, 0.0, 0.5)

func _resolve_temperature_latitude_weight() -> float:
	if not _balance:
		return 0.72
	return clampf(_balance.temperature_latitude_weight, 0.0, 1.0)

func _resolve_latitude_temperature_curve() -> float:
	if not _balance:
		return 1.35
	return maxf(0.5, _balance.latitude_temperature_curve)

func _sample01(value: float) -> float:
	return value * 0.5 + 0.5
