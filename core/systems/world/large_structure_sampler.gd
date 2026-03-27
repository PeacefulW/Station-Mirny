class_name LargeStructureSampler
extends RefCounted

const _RIDGE_DIR := Vector3(0.82, 0.53, 0.21)
const _RIVER_DIR := Vector3(-0.31, 0.90, 0.30)
const WorldNoiseUtilsScript = preload("res://core/systems/world/world_noise_utils.gd")

var _world_seed: int = 0
var _balance: WorldGenBalance = null
var _cached_wrap_width: int = WorldNoiseUtilsScript.DEFAULT_WRAP_WIDTH_TILES
var _ridge_warp_noise: FastNoiseLite = FastNoiseLite.new()
var _ridge_cluster_noise: FastNoiseLite = FastNoiseLite.new()
var _river_warp_noise: FastNoiseLite = FastNoiseLite.new()

func initialize(seed_value: int, balance_resource: WorldGenBalance) -> void:
	_world_seed = seed_value
	_balance = balance_resource
	if not _balance:
		return
	_cached_wrap_width = WorldNoiseUtilsScript.resolve_wrap_width_tiles(_balance)
	WorldNoiseUtilsScript.setup_noise_instance(_ridge_warp_noise, _world_seed + 211, _balance.ridge_warp_frequency, 2)
	WorldNoiseUtilsScript.setup_noise_instance(_ridge_cluster_noise, _world_seed + 223, _balance.ridge_cluster_frequency, 3)
	WorldNoiseUtilsScript.setup_noise_instance(_river_warp_noise, _world_seed + 241, _balance.river_warp_frequency, 2)

func sample_structure_context(world_pos: Vector2i, channels: WorldChannels = null) -> WorldStructureContext:
	var context: WorldStructureContext = WorldStructureContext.new()
	context.world_pos = world_pos
	context.canonical_world_pos = canonicalize_world_pos(world_pos)
	var height_value: float = _channel_value(channels, &"height", 0.5)
	var ruggedness_value: float = _channel_value(channels, &"ruggedness", 0.5)
	var moisture_value: float = _channel_value(channels, &"moisture", 0.5)
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
	return WorldNoiseUtilsScript.canonicalize_pos(world_pos, _cached_wrap_width)

func wrap_world_x(world_x: int) -> int:
	return WorldNoiseUtilsScript.wrap_x(world_x, _cached_wrap_width)

func get_wrap_width_tiles() -> int:
	return _cached_wrap_width

func _sample_mountain_mass(world_pos: Vector2i, height_value: float, ruggedness_value: float) -> float:
	var cluster_noise: float = _sample_noise(_ridge_cluster_noise, world_pos)
	var density_floor: float = clampf(0.44 - _balance.mountain_density * 0.30, 0.20, 0.38)
	var cluster_gate: float = clampf((cluster_noise - density_floor) / 0.44, 0.0, 1.0)
	var terrain_gate: float = clampf(height_value * 0.58 + ruggedness_value * 0.92 - 0.24, 0.0, 1.0)
	return clampf(cluster_gate * terrain_gate, 0.0, 1.0)

func _sample_ridge_strength(world_pos: Vector2i, mountain_mass: float, height_value: float, ruggedness_value: float) -> float:
	var ridge_coord: float = _directed_coordinate(world_pos, _RIDGE_DIR)
	ridge_coord += _sample_noise_signed(_ridge_warp_noise, world_pos) * _balance.ridge_warp_amplitude_tiles
	var band_strength: float = _sample_repeating_band(
		ridge_coord,
		float(_balance.ridge_spacing_tiles),
		_balance.ridge_core_width_tiles,
		_balance.ridge_feather_tiles
	)
	var band_profile: float = band_strength * band_strength * (3.0 - 2.0 * band_strength)
	var cluster_support: float = clampf(_sample_noise(_ridge_cluster_noise, world_pos) * 1.15 - 0.18, 0.0, 1.0)
	var chaininess: float = clampf(_balance.mountain_chaininess, 0.0, 1.0)
	var terrain_gate: float = clampf(height_value * 0.50 + ruggedness_value * 1.02 - 0.18, 0.08, 1.0)
	var mass_floor: float = lerpf(0.24, 0.46, chaininess)
	var mass_gate: float = lerpf(mass_floor, 1.0, mountain_mass)
	var ridge_bias: float = lerpf(0.94, 1.14, chaininess)
	var ridge_backbone: float = maxf(band_profile, band_strength * cluster_support)
	var massif_fill: float = mountain_mass * lerpf(0.18, 0.30, chaininess)
	var core_bonus: float = maxf(0.0, band_profile - 0.72) * lerpf(0.18, 0.28, chaininess)
	return clampf((ridge_backbone * ridge_bias + massif_fill + core_bonus) * terrain_gate * mass_gate, 0.0, 1.0)

func _sample_river_strength(
	world_pos: Vector2i,
	ridge_strength: float,
	mountain_mass: float,
	height_value: float,
	ruggedness_value: float,
	moisture_value: float
) -> float:
	var river_coord: float = _directed_coordinate(world_pos, _RIVER_DIR)
	river_coord += _sample_noise_signed(_river_warp_noise, world_pos) * _balance.river_warp_amplitude_tiles
	var band_strength: float = _sample_repeating_band(
		river_coord,
		float(_balance.river_spacing_tiles),
		_balance.river_core_width_tiles,
		_balance.river_floodplain_width_tiles * 0.70
	)
	var band_profile: float = band_strength * band_strength * (3.0 - 2.0 * band_strength)
	var lowland_gate: float = clampf(1.0 - (height_value * 0.70 + ruggedness_value * 0.42), 0.08, 1.0)
	var moisture_gate: float = clampf(0.58 + moisture_value * 0.42, 0.0, 1.0)
	var valley_gate: float = clampf(1.0 - (height_value * 0.62 + ruggedness_value * 0.48 + ridge_strength * 0.22), 0.0, 1.0)
	var mountain_penalty: float = clampf(1.0 - ridge_strength * 0.34 - mountain_mass * 0.18, 0.22, 1.0)
	var drainage_bonus: float = maxf(0.0, moisture_value - 0.42) * 0.12
	return clampf((band_profile * lowland_gate * moisture_gate * mountain_penalty) + (band_strength * valley_gate * drainage_bonus), 0.0, 1.0)

func _sample_floodplain_strength(
	world_pos: Vector2i,
	river_strength: float,
	mountain_mass: float,
	height_value: float,
	ruggedness_value: float,
	moisture_value: float
) -> float:
	var river_coord: float = _directed_coordinate(world_pos, _RIVER_DIR)
	river_coord += _sample_noise_signed(_river_warp_noise, world_pos) * _balance.river_warp_amplitude_tiles
	var floodplain_band: float = _sample_repeating_band(
		river_coord,
		float(_balance.river_spacing_tiles),
		_balance.river_core_width_tiles * 2.5,
		_balance.river_floodplain_width_tiles
	)
	var floodplain_profile: float = floodplain_band * floodplain_band * (3.0 - 2.0 * floodplain_band)
	var lowland_gate: float = clampf(1.0 - (height_value * 0.60 + ruggedness_value * 0.25), 0.10, 1.0)
	var moisture_gate: float = clampf(0.45 + moisture_value * 0.55, 0.0, 1.0)
	var mountain_penalty: float = clampf(1.0 - mountain_mass * 0.36, 0.28, 1.0)
	var river_support: float = maxf(river_strength * 0.82, floodplain_band * 0.46)
	return clampf(maxf(river_support, floodplain_profile * lowland_gate * moisture_gate * mountain_penalty), 0.0, 1.0)

func _directed_coordinate(world_pos: Vector2i, direction: Vector3) -> float:
	return _cylindrical_point(world_pos).dot(direction.normalized())

func _cylindrical_point(world_pos: Vector2i) -> Vector3:
	var wrapped_x: int = wrap_world_x(world_pos.x)
	var angle: float = TAU * float(wrapped_x) / float(maxi(1, _cached_wrap_width))
	var radius: float = maxf(1.0, float(_cached_wrap_width) / TAU)
	return Vector3(
		cos(angle) * radius,
		float(world_pos.y),
		sin(angle) * radius
	)

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

func _channel_value(channels: WorldChannels, property_name: StringName, fallback_value: float) -> float:
	if channels == null:
		return fallback_value
	var value: Variant = channels.get(property_name)
	if value is float:
		return value
	if value is int:
		return float(value)
	return fallback_value

func _sample_noise(noise: FastNoiseLite, world_pos: Vector2i) -> float:
	return WorldNoiseUtilsScript.sample_periodic_noise01(noise, world_pos, _cached_wrap_width)

func _sample_noise_signed(noise: FastNoiseLite, world_pos: Vector2i) -> float:
	return WorldNoiseUtilsScript.sample_periodic_noise_signed(noise, world_pos, _cached_wrap_width)
