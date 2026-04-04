class_name WorldNoiseUtils
extends RefCounted
## Shared noise sampling utilities for cylindrical world wrap.
## Eliminates duplication across PlanetSampler, LocalVariationResolver,
## ChunkContentBuilder, and any remaining native/legacy structure helpers.

const DEFAULT_FRACTAL_GAIN: float = 0.55
const DEFAULT_FRACTAL_LACUNARITY: float = 2.1
const DEFAULT_WRAP_WIDTH_TILES: int = 4096
const FRACTAL_TYPE_FBM: int = 1  # FastNoiseLite.FRACTAL_FBM


static func setup_noise_instance(noise: FastNoiseLite, seed_value: int, frequency: float, octaves: int) -> void:
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_type = FRACTAL_TYPE_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = DEFAULT_FRACTAL_GAIN
	noise.fractal_lacunarity = DEFAULT_FRACTAL_LACUNARITY
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX


static func sample_periodic_noise01(noise: FastNoiseLite, world_pos: Vector2i, wrap_width: int) -> float:
	if wrap_width <= 0:
		return remap_noise(noise.get_noise_2d(world_pos.x, world_pos.y))
	var wrapped_x: int = int(posmod(world_pos.x, wrap_width))
	var angle: float = TAU * float(wrapped_x) / float(wrap_width)
	var ring_radius: float = float(wrap_width) / TAU
	var sample_x: float = cos(angle) * ring_radius
	var sample_y: float = float(world_pos.y)
	var sample_z: float = sin(angle) * ring_radius
	return remap_noise(noise.get_noise_3d(sample_x, sample_y, sample_z))


static func sample_periodic_noise_signed(noise: FastNoiseLite, world_pos: Vector2i, wrap_width: int) -> float:
	return sample_periodic_noise01(noise, world_pos, wrap_width) * 2.0 - 1.0


static func remap_noise(value: float) -> float:
	return value * 0.5 + 0.5


static func resolve_wrap_width_tiles(balance: WorldGenBalance) -> int:
	if not balance:
		return DEFAULT_WRAP_WIDTH_TILES
	var tile_width: int = maxi(256, balance.world_wrap_width_tiles)
	var chunk_size: int = maxi(1, balance.chunk_size_tiles)
	var chunk_count: int = maxi(1, int(ceili(float(tile_width) / float(chunk_size))))
	return chunk_count * chunk_size


static func wrap_x(world_x: int, wrap_width: int) -> int:
	if wrap_width <= 0:
		return world_x
	return int(posmod(world_x, wrap_width))


static func canonicalize_pos(world_pos: Vector2i, wrap_width: int) -> Vector2i:
	return Vector2i(wrap_x(world_pos.x, wrap_width), world_pos.y)
