class_name WorldGeneratorSingleton
extends Node

const BALANCE_PATH: String = "res://data/world/world_gen_balance.tres"
const CHUNK_BIOME_SAMPLE_GRID: int = 3
const WorldNoiseUtilsScript = preload("res://core/systems/world/world_noise_utils.gd")
const WorldComputeContextScript = preload("res://core/systems/world/world_compute_context.gd")
const SurfaceTerrainResolverScript = preload("res://core/systems/world/surface_terrain_resolver.gd")

var world_seed: int = 0
var balance: WorldGenBalance = null
var current_biome: BiomeData = null
var spawn_tile: Vector2i = Vector2i.ZERO
var _is_initialized: bool = false
var _planet_sampler: PlanetSampler = null
var _structure_sampler: LargeStructureSampler = null
var _biome_resolver: BiomeResolver = null
var _local_variation_resolver: LocalVariationResolver = null
var _compute_context: RefCounted = null
var _surface_terrain_resolver: RefCounted = null
var _chunk_content_builder: ChunkContentBuilder = null
var _chunk_biome_cache: Dictionary = {}

func _ready() -> void:
	balance = load(BALANCE_PATH) as WorldGenBalance
	if not balance:
		push_error(Localization.t("SYSTEM_WORLD_BALANCE_LOAD_FAILED", {"path": BALANCE_PATH}))
		return
	current_biome = BiomeRegistry.get_default_biome()

func _exit_tree() -> void:
	_chunk_biome_cache.clear()
	_chunk_content_builder = null
	_surface_terrain_resolver = null
	_compute_context = null
	_local_variation_resolver = null
	_biome_resolver = null
	_structure_sampler = null
	_planet_sampler = null

func initialize_world(seed_value: int) -> void:
	if not _ensure_world_feature_registry_ready():
		_clear_initialized_runtime_state()
		return
	world_seed = seed_value
	_setup_planet_sampler()
	_setup_structure_sampler()
	_setup_biome_resolver()
	_setup_local_variation_resolver()
	spawn_tile = canonicalize_tile(spawn_tile)
	_chunk_biome_cache.clear()
	current_biome = get_biome_at_tile(spawn_tile)
	_setup_compute_context()
	_setup_chunk_content_builder()
	_is_initialized = true
	EventBus.world_initialized.emit(world_seed)

func initialize_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	initialize_world(rng.randi())

func get_tile_data(tile_x: int, tile_y: int) -> TileGenData:
	return build_tile_data(Vector2i(tile_x, tile_y))

func build_tile_data(tile_pos: Vector2i) -> TileGenData:
	if not _is_initialized:
		return TileGenData.new()
	var canonical_tile: Vector2i = canonicalize_tile(tile_pos)
	if _surface_terrain_resolver:
		return _surface_terrain_resolver.build_tile_data(canonical_tile)
	return TileGenData.new()

func build_chunk_content(chunk_coord: Vector2i) -> ChunkBuildResult:
	if not _is_initialized or not _chunk_content_builder:
		return null
	return _chunk_content_builder.build_chunk(canonicalize_chunk_coord(chunk_coord))

func build_chunk_result(chunk_coord: Vector2i) -> ChunkBuildResult:
	return build_chunk_content(chunk_coord)

func build_chunk_native_data(chunk_coord: Vector2i) -> Dictionary:
	if not _is_initialized or not _chunk_content_builder:
		return {}
	return _chunk_content_builder.build_chunk_native_data(canonicalize_chunk_coord(chunk_coord))

func sample_world_channels(world_pos: Vector2i) -> WorldChannels:
	if not _planet_sampler:
		return WorldChannels.new()
	return _planet_sampler.sample_world_channels(world_pos)

func sample_structure_context(world_pos: Vector2i, channels: WorldChannels = null) -> WorldStructureContext:
	if not _structure_sampler:
		return null
	return _structure_sampler.sample_structure_context(world_pos, channels)

func sample_local_variation(world_pos: Vector2i, biome: BiomeResult = null, channels: WorldChannels = null, structure_context: WorldStructureContext = null) -> LocalVariationContext:
	var canonical_tile: Vector2i = canonicalize_tile(world_pos)
	var sampled_channels: WorldChannels = channels
	if sampled_channels == null:
		sampled_channels = sample_world_channels(canonical_tile)
	var sampled_structure_context: WorldStructureContext = structure_context
	if sampled_structure_context == null:
		sampled_structure_context = sample_structure_context(canonical_tile, sampled_channels)
	var resolved_biome: BiomeResult = biome
	if resolved_biome == null:
		resolved_biome = get_biome_result_at_tile(canonical_tile, sampled_channels, sampled_structure_context)
	if _local_variation_resolver:
		return _local_variation_resolver.resolve_local_variation(
			canonical_tile,
			resolved_biome,
			sampled_channels,
			sampled_structure_context
		)
	return LocalVariationContext.new()

func get_registered_biomes() -> Array[BiomeData]:
	return BiomeRegistry.get_all_biomes()

func get_biome_by_id(biome_id: StringName) -> BiomeData:
	return BiomeRegistry.get_biome_by_short_id(biome_id)

func get_biome_palette_index(biome_id: StringName) -> int:
	return BiomeRegistry.get_palette_index(biome_id)

func get_biome_palette_order() -> Array[BiomeData]:
	return BiomeRegistry.get_palette_order()

func get_biome_result_at_tile(tile_pos: Vector2i, channels: WorldChannels = null, structure_context: WorldStructureContext = null) -> BiomeResult:
	var canonical_tile: Vector2i = canonicalize_tile(tile_pos)
	var sampled_channels: WorldChannels = channels
	if sampled_channels == null:
		sampled_channels = sample_world_channels(canonical_tile)
	var sampled_structure_context: WorldStructureContext = structure_context
	if sampled_structure_context == null:
		sampled_structure_context = sample_structure_context(canonical_tile, sampled_channels)
	return resolve_biome(canonical_tile, sampled_channels, sampled_structure_context)

func resolve_biome(world_pos: Vector2i, channels: WorldChannels = null, structure_context: WorldStructureContext = null) -> BiomeResult:
	var canonical_tile: Vector2i = canonicalize_tile(world_pos)
	var sampled_channels: WorldChannels = channels
	if sampled_channels == null:
		sampled_channels = sample_world_channels(canonical_tile)
	var sampled_structure_context: WorldStructureContext = structure_context
	if sampled_structure_context == null:
		sampled_structure_context = sample_structure_context(canonical_tile, sampled_channels)
	if _biome_resolver:
		return _biome_resolver.resolve_biome(canonical_tile, sampled_channels, sampled_structure_context)
	return null

func get_tile_biome(tile_pos: Vector2i) -> BiomeData:
	return get_biome_at_tile(tile_pos)

func resolve_biome_at_tile(tile_pos: Vector2i) -> BiomeResult:
	return get_biome_result_at_tile(tile_pos)

func get_biome_at_tile(tile_pos: Vector2i) -> BiomeData:
	var result: BiomeResult = get_biome_result_at_tile(tile_pos)
	if result:
		var biome: BiomeData = result.biome as BiomeData
		if biome:
			return biome
	return BiomeRegistry.get_default_biome()

func get_dominant_biome_for_chunk(chunk_coord: Vector2i) -> BiomeData:
	var canonical_chunk: Vector2i = canonicalize_chunk_coord(chunk_coord)
	var cached_biome: BiomeData = _chunk_biome_cache.get(canonical_chunk, null) as BiomeData
	if cached_biome:
		return cached_biome
	var dominant_biome: BiomeData = _resolve_chunk_dominant_biome(canonical_chunk)
	if dominant_biome:
		_chunk_biome_cache[canonical_chunk] = dominant_biome
		return dominant_biome
	return BiomeRegistry.get_default_biome()

## Alias retained for compatibility with chunk_manager and other callers.
func get_chunk_biome(chunk_coord: Vector2i) -> BiomeData:
	return get_dominant_biome_for_chunk(chunk_coord)

func canonicalize_tile(tile_pos: Vector2i) -> Vector2i:
	if not _planet_sampler:
		return tile_pos
	return _planet_sampler.canonicalize_world_pos(tile_pos)

func wrap_world_tile_x(tile_x: int) -> int:
	if not _planet_sampler:
		return tile_x
	return _planet_sampler.wrap_world_x(tile_x)

func get_world_wrap_width_tiles() -> int:
	if not balance:
		return 0
	return WorldNoiseUtilsScript.resolve_wrap_width_tiles(balance)

func get_world_wrap_width_pixels() -> float:
	if not balance:
		return 0.0
	return float(get_world_wrap_width_tiles() * balance.tile_size)

func get_world_wrap_chunk_count() -> int:
	if not balance:
		return 0
	return maxi(1, int(get_world_wrap_width_tiles() / balance.chunk_size_tiles))

func wrap_chunk_x(chunk_x: int) -> int:
	var chunk_count: int = get_world_wrap_chunk_count()
	if chunk_count <= 0:
		return chunk_x
	return int(posmod(chunk_x, chunk_count))

func canonicalize_chunk_coord(chunk_coord: Vector2i) -> Vector2i:
	return Vector2i(wrap_chunk_x(chunk_coord.x), chunk_coord.y)

func get_display_chunk_coord(chunk_coord: Vector2i, reference_chunk_coord: Vector2i) -> Vector2i:
	var canonical_chunk: Vector2i = canonicalize_chunk_coord(chunk_coord)
	var canonical_reference: Vector2i = canonicalize_chunk_coord(reference_chunk_coord)
	return Vector2i(
		canonical_reference.x + chunk_wrap_delta_x(canonical_chunk.x, canonical_reference.x),
		canonical_chunk.y
	)

func world_wrap_delta_x(world_x: float, reference_x: float) -> float:
	var wrap_width: float = get_world_wrap_width_pixels()
	if wrap_width <= 0.0:
		return world_x - reference_x
	var wrapped_world_x: float = fposmod(world_x, wrap_width)
	var wrapped_reference_x: float = fposmod(reference_x, wrap_width)
	var delta: float = wrapped_world_x - wrapped_reference_x
	var half_width: float = wrap_width * 0.5
	if delta > half_width:
		delta -= wrap_width
	elif delta < -half_width:
		delta += wrap_width
	return delta

func get_display_world_position(world_pos: Vector2, reference_world_pos: Vector2) -> Vector2:
	var canonical_world_pos: Vector2 = canonicalize_world_position(world_pos)
	return Vector2(
		reference_world_pos.x + world_wrap_delta_x(canonical_world_pos.x, reference_world_pos.x),
		canonical_world_pos.y
	)

func offset_tile(tile_pos: Vector2i, offset: Vector2i) -> Vector2i:
	return canonicalize_tile(tile_pos + offset)

func offset_chunk_coord(chunk_coord: Vector2i, offset: Vector2i) -> Vector2i:
	return canonicalize_chunk_coord(chunk_coord + offset)

func tile_wrap_delta_x(tile_x: int, reference_x: int) -> int:
	var wrap_width: int = get_world_wrap_width_tiles()
	if wrap_width <= 0:
		return tile_x - reference_x
	var delta: int = wrap_world_tile_x(tile_x) - wrap_world_tile_x(reference_x)
	var half_width: int = wrap_width / 2
	if delta > half_width:
		delta -= wrap_width
	elif delta < -half_width:
		delta += wrap_width
	return delta

func chunk_wrap_delta_x(chunk_x: int, reference_chunk_x: int) -> int:
	var chunk_count: int = get_world_wrap_chunk_count()
	if chunk_count <= 0:
		return chunk_x - reference_chunk_x
	var delta: int = wrap_chunk_x(chunk_x) - wrap_chunk_x(reference_chunk_x)
	var half_width: int = chunk_count / 2
	if delta > half_width:
		delta -= chunk_count
	elif delta < -half_width:
		delta += chunk_count
	return delta

func chunk_to_tile_origin(chunk_coord: Vector2i) -> Vector2i:
	var canonical_chunk: Vector2i = canonicalize_chunk_coord(chunk_coord)
	return Vector2i(
		canonical_chunk.x * balance.chunk_size_tiles,
		canonical_chunk.y * balance.chunk_size_tiles
	)

func tile_to_local_in_chunk(tile_pos: Vector2i, chunk_coord: Vector2i) -> Vector2i:
	var canonical_tile: Vector2i = canonicalize_tile(tile_pos)
	var chunk_origin: Vector2i = chunk_to_tile_origin(chunk_coord)
	return Vector2i(
		canonical_tile.x - chunk_origin.x,
		canonical_tile.y - chunk_origin.y
	)

func chunk_local_to_tile(chunk_coord: Vector2i, local_tile: Vector2i) -> Vector2i:
	return canonicalize_tile(chunk_to_tile_origin(chunk_coord) + local_tile)

func wrap_world_position_x(world_x: float) -> float:
	var wrap_width_px: float = get_world_wrap_width_pixels()
	if wrap_width_px <= 0.0:
		return world_x
	return fposmod(world_x, wrap_width_px)

func canonicalize_world_position(world_pos: Vector2) -> Vector2:
	return Vector2(wrap_world_position_x(world_pos.x), world_pos.y)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return canonicalize_tile(Vector2i(
		floori(world_pos.x / balance.tile_size),
		floori(world_pos.y / balance.tile_size)
	))

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	var ts: float = float(balance.tile_size)
	var canonical_tile: Vector2i = canonicalize_tile(tile_pos)
	return Vector2(canonical_tile.x * ts + ts * 0.5, canonical_tile.y * ts + ts * 0.5)

func world_to_chunk(world_pos: Vector2) -> Vector2i:
	return tile_to_chunk(world_to_tile(world_pos))

func tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	var canonical_tile: Vector2i = canonicalize_tile(tile_pos)
	var cs: int = balance.chunk_size_tiles
	return canonicalize_chunk_coord(Vector2i(
		floori(float(canonical_tile.x) / cs),
		floori(float(canonical_tile.y) / cs)
	))

func get_terrain_type_fast(tile_pos: Vector2i) -> TileGenData.TerrainType:
	if not _is_initialized or not _surface_terrain_resolver:
		return TileGenData.TerrainType.GROUND
	var canonical_tile: Vector2i = canonicalize_tile(tile_pos)
	return _surface_terrain_resolver.sample_terrain_type(canonical_tile.x, canonical_tile.y)

func is_walkable_at(world_pos: Vector2) -> bool:
	var tile_pos: Vector2i = world_to_tile(world_pos)
	return _is_walkable_terrain(get_terrain_type_fast(tile_pos))

func _setup_planet_sampler() -> void:
	_planet_sampler = PlanetSampler.new()
	_planet_sampler.initialize(world_seed, balance)

func _setup_structure_sampler() -> void:
	_structure_sampler = LargeStructureSampler.new()
	_structure_sampler.initialize(world_seed, balance)

func _setup_biome_resolver() -> void:
	_biome_resolver = BiomeResolver.new()
	_biome_resolver.configure(BiomeRegistry.get_all_biomes())

func _setup_local_variation_resolver() -> void:
	_local_variation_resolver = LocalVariationResolver.new()
	_local_variation_resolver.initialize(world_seed, balance)

func _setup_compute_context() -> void:
	var biome_by_id: Dictionary = {}
	var palette_index_by_id: Dictionary = {}
	var palette_order: Array[BiomeData] = BiomeRegistry.get_palette_order()
	for index: int in range(palette_order.size()):
		var biome: BiomeData = palette_order[index]
		if biome == null or str(biome.id).is_empty():
			continue
		biome_by_id[biome.id] = biome
		palette_index_by_id[biome.id] = index
	_compute_context = WorldComputeContextScript.new().configure(
		balance,
		spawn_tile,
		current_biome,
		BiomeRegistry.get_default_biome(),
		_planet_sampler,
		_structure_sampler,
		_biome_resolver,
		_local_variation_resolver,
		biome_by_id,
		palette_index_by_id
	)
	_surface_terrain_resolver = _create_surface_terrain_resolver(_compute_context)

func _setup_chunk_content_builder() -> void:
	_chunk_content_builder = _create_chunk_content_builder(_compute_context)

func create_detached_chunk_content_builder() -> ChunkContentBuilder:
	return _create_chunk_content_builder(_compute_context)

func _ensure_world_feature_registry_ready() -> bool:
	if not WorldFeatureRegistry or not WorldFeatureRegistry.is_ready():
		push_error("WorldFeatureRegistry must be ready before WorldGenerator.initialize_world()")
		assert(false, "WorldFeatureRegistry must be ready before world initialization")
		return false
	return true

func _clear_initialized_runtime_state() -> void:
	_is_initialized = false
	_chunk_biome_cache.clear()
	_chunk_content_builder = null
	_surface_terrain_resolver = null
	_compute_context = null
	_local_variation_resolver = null
	_biome_resolver = null
	_structure_sampler = null
	_planet_sampler = null

func _create_chunk_content_builder(world_context: RefCounted) -> ChunkContentBuilder:
	if world_context == null:
		return null
	var builder := ChunkContentBuilder.new()
	builder.initialize(balance, world_context, _create_surface_terrain_resolver(world_context))
	return builder

func _create_surface_terrain_resolver(world_context: RefCounted) -> RefCounted:
	if world_context == null:
		return null
	return SurfaceTerrainResolverScript.new().initialize(balance, world_context)

func _is_walkable_terrain(terrain_type: int) -> bool:
	return terrain_type != TileGenData.TerrainType.ROCK \
		and terrain_type != TileGenData.TerrainType.WATER

func _resolve_chunk_dominant_biome(chunk_coord: Vector2i) -> BiomeData:
	var chunk_size: int = balance.chunk_size_tiles if balance else 64
	var score_by_id: Dictionary = {}
	var wins_by_id: Dictionary = {}
	var center_biome_id: StringName = &""
	for sample_local: Vector2i in _get_chunk_biome_sample_points(chunk_size):
		var sample_tile: Vector2i = chunk_local_to_tile(chunk_coord, sample_local)
		var channels: WorldChannels = sample_world_channels(sample_tile)
		var result: BiomeResult = get_biome_result_at_tile(sample_tile, channels)
		var sample_biome: BiomeData = null
		var sample_score: float = 0.25
		if result:
			sample_biome = result.biome as BiomeData
			sample_score = maxf(0.01, float(result.score))
		if not sample_biome:
			sample_biome = BiomeRegistry.get_default_biome()
		if not sample_biome:
			continue
		var biome_id: StringName = sample_biome.id
		score_by_id[biome_id] = float(score_by_id.get(biome_id, 0.0)) + sample_score
		wins_by_id[biome_id] = int(wins_by_id.get(biome_id, 0)) + 1
		if sample_local == Vector2i(chunk_size / 2, chunk_size / 2):
			center_biome_id = biome_id
	var best_biome: BiomeData = BiomeRegistry.get_default_biome()
	var best_score: float = -1.0
	var best_wins: int = -1
	for biome_id: StringName in score_by_id:
		var biome: BiomeData = get_biome_by_id(biome_id)
		if not biome:
			continue
		var total_score: float = float(score_by_id[biome_id])
		var total_wins: int = int(wins_by_id.get(biome_id, 0))
		var is_better: bool = total_score > best_score
		if is_better == false and is_equal_approx(total_score, best_score):
			is_better = total_wins > best_wins
		if is_better == false and is_equal_approx(total_score, best_score) and total_wins == best_wins:
			is_better = biome_id == center_biome_id
		if is_better == false and is_equal_approx(total_score, best_score) and total_wins == best_wins and biome.id != center_biome_id:
			var best_priority: int = best_biome.priority if best_biome else -999999
			is_better = biome.priority > best_priority
		if is_better:
			best_biome = biome
			best_score = total_score
			best_wins = total_wins
	return best_biome

func _get_chunk_biome_sample_points(chunk_size: int) -> Array[Vector2i]:
	var sample_points: Array[Vector2i] = []
	for gy: int in range(CHUNK_BIOME_SAMPLE_GRID):
		for gx: int in range(CHUNK_BIOME_SAMPLE_GRID):
			var fx: float = float(gx + 1) / float(CHUNK_BIOME_SAMPLE_GRID + 1)
			var fy: float = float(gy + 1) / float(CHUNK_BIOME_SAMPLE_GRID + 1)
			sample_points.append(Vector2i(
				clampi(int(round(fx * float(chunk_size - 1))), 0, chunk_size - 1),
				clampi(int(round(fy * float(chunk_size - 1))), 0, chunk_size - 1)
			))
	return sample_points
