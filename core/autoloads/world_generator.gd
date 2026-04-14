class_name WorldGeneratorSingleton
extends Node

class FeatureAndPoiPayloadCache extends RefCounted:
	const PLACEMENTS_KEY: String = "placements"

	var _mutex: Mutex = Mutex.new()
	var _payload_by_chunk: Dictionary = {}

	func clear() -> void:
		_mutex.lock()
		_payload_by_chunk.clear()
		_mutex.unlock()

	func store_payload(chunk_coord: Vector2i, payload: Dictionary) -> void:
		var stored_payload: Dictionary = payload.duplicate(true)
		_mutex.lock()
		_payload_by_chunk[chunk_coord] = stored_payload
		_mutex.unlock()

	func has_payload(chunk_coord: Vector2i) -> bool:
		_mutex.lock()
		var has_cached_payload: bool = _payload_by_chunk.has(chunk_coord)
		_mutex.unlock()
		return has_cached_payload

	func get_payload(chunk_coord: Vector2i) -> Dictionary:
		_mutex.lock()
		var stored_payload: Dictionary = (_payload_by_chunk.get(chunk_coord, {}) as Dictionary).duplicate(true)
		_mutex.unlock()
		if stored_payload.is_empty():
			return {
				PLACEMENTS_KEY: [],
			}
		return stored_payload

const BALANCE_PATH: String = "res://data/world/world_gen_balance.tres"
const CHUNK_BIOME_SAMPLE_GRID: int = 3
const WorldNoiseUtilsScript = preload("res://core/systems/world/world_noise_utils.gd")
const WorldComputeContextScript = preload("res://core/systems/world/world_compute_context.gd")
const WorldPrePassScript = preload("res://core/systems/world/world_pre_pass.gd")
const SurfaceTerrainResolverScript = preload("res://core/systems/world/surface_terrain_resolver.gd")

var world_seed: int = 0
var balance: WorldGenBalance = null
var _base_balance: WorldGenBalance = null
var current_biome: BiomeData = null
var spawn_tile: Vector2i = Vector2i.ZERO
var _is_initialized: bool = false
var _planet_sampler: PlanetSampler = null
var _biome_resolver: BiomeResolver = null
var _local_variation_resolver: LocalVariationResolver = null
var _world_pre_pass: RefCounted = null
var _compute_context: RefCounted = null
var _surface_terrain_resolver: RefCounted = null
var _chunk_content_builder: ChunkContentBuilder = null
var _native_chunk_generator: RefCounted = null
var _chunk_biome_cache: Dictionary = {}
var _feature_and_poi_payload_cache: FeatureAndPoiPayloadCache = FeatureAndPoiPayloadCache.new()
var _pending_init_generation: int = 0
var _pending_init_task_id: int = -1
var _pending_init_seed: int = 0
var _pending_init_started_usec: int = 0
var _pending_init_balance: WorldGenBalance = null
var _pending_init_result_mutex: Mutex = Mutex.new()
var _pending_init_result: Dictionary = {}

func _ready() -> void:
	_base_balance = load(BALANCE_PATH) as WorldGenBalance
	if not _base_balance:
		push_error(Localization.t("SYSTEM_WORLD_BALANCE_LOAD_FAILED", {"path": BALANCE_PATH}))
		return
	balance = _duplicate_runtime_balance(_base_balance)
	current_biome = BiomeRegistry.get_default_biome()

func _exit_tree() -> void:
	_clear_pending_world_initialization_state(true)
	_feature_and_poi_payload_cache.clear()
	_clear_initialized_runtime_state()

func initialize_world(seed_value: int) -> void:
	var init_started_usec: int = WorldPerfProbe.begin()
	if not begin_initialize_world_async(seed_value):
		WorldPerfProbe.end("WorldGenerator.initialize_world", init_started_usec)
		return
	_wait_for_pending_world_initialization_sync()
	complete_pending_initialize_world()
	WorldPerfProbe.end("WorldGenerator.initialize_world", init_started_usec)

func initialize_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	initialize_world(rng.randi())

func begin_initialize_world_async(seed_value: int) -> bool:
	if _is_initialized and not is_initialize_world_pending() and world_seed == seed_value:
		return true
	if is_initialize_world_pending() and _pending_init_seed == seed_value:
		return true
	if not _ensure_world_feature_registry_ready():
		_clear_pending_world_initialization_state(true)
		_clear_initialized_runtime_state()
		return false
	_clear_pending_world_initialization_state(true)
	_clear_initialized_runtime_state()
	_feature_and_poi_payload_cache.clear()
	_reset_runtime_balance()
	world_seed = seed_value
	current_biome = BiomeRegistry.get_default_biome()
	_pending_init_seed = seed_value
	_pending_init_started_usec = Time.get_ticks_usec()
	_pending_init_balance = balance
	var worker_balance: WorldGenBalance = _duplicate_runtime_balance(_pending_init_balance)
	if worker_balance == null:
		_clear_pending_world_initialization_state(false)
		return false
	var generation: int = _pending_init_generation
	var task_id: int = WorkerThreadPool.add_task(
		_worker_compute_world_pre_pass.bind(generation, seed_value, worker_balance)
	)
	if task_id < 0:
		_clear_pending_world_initialization_state(false)
		return false
	_pending_init_task_id = task_id
	return true

func is_initialize_world_pending() -> bool:
	return _pending_init_task_id >= 0

func complete_pending_initialize_world() -> bool:
	if _is_initialized:
		return true
	if not is_initialize_world_pending():
		return false
	if not WorkerThreadPool.is_task_completed(_pending_init_task_id):
		return false
	WorkerThreadPool.wait_for_task_completion(_pending_init_task_id)
	var pre_pass_result: Dictionary = _take_pending_world_initialization_result()
	var published_seed: int = _pending_init_seed
	var published_balance: WorldGenBalance = _pending_init_balance
	var pending_age_ms: float = 0.0
	if _pending_init_started_usec > 0:
		pending_age_ms = float(Time.get_ticks_usec() - _pending_init_started_usec) / 1000.0
	_clear_pending_world_initialization_state(false)
	if pre_pass_result.is_empty():
		push_error("WorldGenerator async pre-pass completed without a publishable result")
		return false
	_publish_initialized_runtime_state(published_seed, published_balance, pre_pass_result)
	if pending_age_ms > 0.0:
		WorldPerfProbe.record("WorldGenerator.complete_pending_initialize_world.pending_age_ms", pending_age_ms)
	return _is_initialized

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
	if _compute_context == null:
		return null
	return _compute_context.sample_structure_context(canonicalize_tile(world_pos), channels)

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
	if _compute_context != null:
		return _compute_context.resolve_biome(canonical_tile, sampled_channels, sampled_structure_context)
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

func _setup_biome_resolver() -> void:
	_biome_resolver = BiomeResolver.new()
	_biome_resolver.configure(BiomeRegistry.get_all_biomes())

func _setup_local_variation_resolver() -> void:
	_local_variation_resolver = LocalVariationResolver.new()
	_local_variation_resolver.initialize(world_seed, balance)

func _wait_for_pending_world_initialization_sync() -> void:
	if not is_initialize_world_pending():
		return
	WorkerThreadPool.wait_for_task_completion(_pending_init_task_id)

func _worker_compute_world_pre_pass(
	generation: int,
	seed_value: int,
	worker_balance: WorldGenBalance
) -> void:
	var worker_planet_sampler_usec: int = Time.get_ticks_usec()
	var worker_planet_sampler: PlanetSampler = PlanetSampler.new()
	worker_planet_sampler.initialize(seed_value, worker_balance)
	var worker_planet_sampler_ms: float = float(Time.get_ticks_usec() - worker_planet_sampler_usec) / 1000.0
	var configure_usec: int = Time.get_ticks_usec()
	var pre_pass: WorldPrePass = WorldPrePassScript.new().configure(worker_balance, worker_planet_sampler)
	var configure_ms: float = float(Time.get_ticks_usec() - configure_usec) / 1000.0
	var compute_usec: int = Time.get_ticks_usec()
	pre_pass = pre_pass.compute()
	var compute_ms: float = float(Time.get_ticks_usec() - compute_usec) / 1000.0
	_pending_init_result_mutex.lock()
	if generation == _pending_init_generation:
		_pending_init_result = {
			"generation": generation,
			"worker_planet_sampler_ms": worker_planet_sampler_ms,
			"configure_ms": configure_ms,
			"compute_ms": compute_ms,
			"setup_world_pre_pass_ms": configure_ms + compute_ms,
			"world_pre_pass": pre_pass,
		}
	_pending_init_result_mutex.unlock()

func _setup_world_pre_pass() -> void:
	var configure_usec: int = WorldPerfProbe.begin()
	var pre_pass: WorldPrePass = WorldPrePassScript.new().configure(balance, _planet_sampler)
	WorldPerfProbe.end("WorldGenerator._setup_world_pre_pass.configure", configure_usec)
	var compute_usec: int = WorldPerfProbe.begin()
	_world_pre_pass = pre_pass.compute()
	WorldPerfProbe.end("WorldGenerator._setup_world_pre_pass.compute", compute_usec)

func _take_pending_world_initialization_result() -> Dictionary:
	_pending_init_result_mutex.lock()
	var result: Dictionary = _pending_init_result
	_pending_init_result = {}
	_pending_init_result_mutex.unlock()
	return result

func _clear_pending_world_initialization_state(invalidate_generation: bool) -> void:
	_pending_init_result_mutex.lock()
	if invalidate_generation:
		_pending_init_generation += 1
	_pending_init_result = {}
	_pending_init_result_mutex.unlock()
	_pending_init_task_id = -1
	_pending_init_seed = 0
	_pending_init_started_usec = 0
	_pending_init_balance = null

func _reset_runtime_balance() -> void:
	if _base_balance == null:
		return
	balance = _duplicate_runtime_balance(_base_balance)

func _duplicate_runtime_balance(source_balance: WorldGenBalance) -> WorldGenBalance:
	if source_balance == null:
		return null
	return source_balance.duplicate(true) as WorldGenBalance

func _setup_compute_context() -> void:
	var build_palette_maps_usec: int = WorldPerfProbe.begin()
	var biome_by_id: Dictionary = {}
	var palette_index_by_id: Dictionary = {}
	var palette_order: Array[BiomeData] = BiomeRegistry.get_palette_order()
	for index: int in range(palette_order.size()):
		var biome: BiomeData = palette_order[index]
		if biome == null or str(biome.id).is_empty():
			continue
		biome_by_id[biome.id] = biome
		palette_index_by_id[biome.id] = index
	WorldPerfProbe.end("WorldGenerator._setup_compute_context.build_palette_maps", build_palette_maps_usec)
	var configure_context_usec: int = WorldPerfProbe.begin()
	_compute_context = WorldComputeContextScript.new().configure(
		balance,
		world_seed,
		spawn_tile,
		current_biome,
		BiomeRegistry.get_default_biome(),
		_planet_sampler,
		_biome_resolver,
		_local_variation_resolver,
		biome_by_id,
		palette_index_by_id,
		WorldFeatureRegistry.get_all_feature_hooks(),
		_world_pre_pass
	)
	WorldPerfProbe.end("WorldGenerator._setup_compute_context.configure_context", configure_context_usec)
	var create_surface_resolver_usec: int = WorldPerfProbe.begin()
	_surface_terrain_resolver = _create_surface_terrain_resolver(_compute_context)
	WorldPerfProbe.end("WorldGenerator._setup_compute_context.create_surface_terrain_resolver", create_surface_resolver_usec)
	var attach_surface_resolver_usec: int = WorldPerfProbe.begin()
	_compute_context.set_surface_terrain_resolver(_surface_terrain_resolver)
	WorldPerfProbe.end("WorldGenerator._setup_compute_context.attach_surface_terrain_resolver", attach_surface_resolver_usec)
	var native_init_usec: int = WorldPerfProbe.begin()
	_setup_native_chunk_generator(palette_index_by_id)
	WorldPerfProbe.end("WorldGenerator._setup_compute_context.setup_native_chunk_generator", native_init_usec)

func _setup_native_chunk_generator(palette_index_by_id: Dictionary) -> void:
	_native_chunk_generator = null
	if not balance or not balance.use_native_chunk_generation:
		return
	if not ClassDB.class_exists(&"ChunkGenerator"):
		push_warning("[WorldGenerator] ChunkGenerator C++ class not available — surface runtime generation will fail closed")
		return
	var gen: RefCounted = ClassDB.instantiate(&"ChunkGenerator")
	if gen == null:
		return
	var params: Dictionary = _build_generator_params(palette_index_by_id)
	var native_generator_initialize_usec: int = WorldPerfProbe.begin()
	gen.initialize(world_seed, params)
	WorldPerfProbe.end("WorldGenerator._setup_native_chunk_generator.initialize", native_generator_initialize_usec)
	_native_chunk_generator = gen
	var biome_defs: Array = params.get("biomes", []) as Array
	var flora_set_defs: Array = params.get("flora_sets", []) as Array
	var decor_set_defs: Array = params.get("decor_sets", []) as Array
	var feature_hook_defs: Array = params.get("feature_hooks", []) as Array
	var poi_defs: Array = params.get("pois", []) as Array
	print("[WorldGenerator] Native ChunkGenerator initialized (%d biomes, %d flora sets, %d decor sets, %d feature hooks, %d pois, authoritative WorldPrePass snapshot)" % [
		biome_defs.size(),
		flora_set_defs.size(),
		decor_set_defs.size(),
		feature_hook_defs.size(),
		poi_defs.size(),
	])

func _build_generator_params(palette_index_by_id: Dictionary) -> Dictionary:
	var wrap: int = WorldNoiseUtilsScript.resolve_wrap_width_tiles(balance)
	var params: Dictionary = {
		"chunk_size": balance.chunk_size_tiles,
		"wrap_width": wrap,
		"equator_tile_y": balance.equator_tile_y,
		"latitude_half_span_tiles": balance.latitude_half_span_tiles,
		"temperature_noise_amplitude": balance.temperature_noise_amplitude,
		"temperature_latitude_weight": balance.temperature_latitude_weight,
		"latitude_temperature_curve": balance.latitude_temperature_curve,
		"height_frequency": balance.height_frequency,
		"height_octaves": balance.height_octaves,
		"temperature_frequency": balance.temperature_frequency,
		"temperature_octaves": balance.temperature_octaves,
		"moisture_frequency": balance.moisture_frequency,
		"moisture_octaves": balance.moisture_octaves,
		"ruggedness_frequency": balance.ruggedness_frequency,
		"ruggedness_octaves": balance.ruggedness_octaves,
		"flora_density_frequency": balance.flora_density_frequency,
		"flora_density_octaves": balance.flora_density_octaves,
		"mountain_density": balance.mountain_density,
		"mountain_chaininess": balance.mountain_chaininess,
		"mountain_base_threshold": balance.mountain_base_threshold,
		"safe_zone_radius": balance.safe_zone_radius,
		"land_guarantee_radius": balance.land_guarantee_radius,
		"local_variation_frequency": balance.local_variation_frequency,
		"local_variation_octaves": balance.local_variation_octaves,
		"local_variation_min_score": balance.local_variation_min_score,
		"river_min_strength": balance.river_min_strength,
		"river_ridge_exclusion": balance.river_ridge_exclusion,
		"river_max_height": balance.river_max_height,
		"bank_min_floodplain": balance.bank_min_floodplain,
		"bank_ridge_exclusion": balance.bank_ridge_exclusion,
		"bank_min_river": balance.bank_min_river,
		"bank_min_moisture": balance.bank_min_moisture,
		"bank_max_height": balance.bank_max_height,
		"prepass_frozen_river_threshold": balance.prepass_frozen_river_threshold,
		"cold_pole_temperature": balance.cold_pole_temperature,
		"cold_pole_transition_width": balance.cold_pole_transition_width,
		"ice_cap_height_bonus": balance.ice_cap_height_bonus,
		"ice_cap_max_height": balance.ice_cap_max_height,
		"hot_pole_temperature": balance.hot_pole_temperature,
		"hot_pole_transition_width": balance.hot_pole_transition_width,
		"biome_continental_drying_factor": balance.biome_continental_drying_factor,
		"biome_drainage_moisture_bonus": balance.biome_drainage_moisture_bonus,
	}
	var pre_pass: WorldPrePass = _world_pre_pass as WorldPrePass
	if pre_pass != null:
		params.merge(_build_native_prepass_params(pre_pass), true)

	var biome_defs: Array = []
	var palette_order: Array[BiomeData] = BiomeRegistry.get_palette_order()
	for index: int in range(palette_order.size()):
		var biome: BiomeData = palette_order[index]
		if biome == null or str(biome.id).is_empty():
			continue
		biome_defs.append({
			"id": biome.id,
			"priority": biome.priority,
			"palette_index": int(palette_index_by_id.get(biome.id, index)),
			"min_height": biome.min_height,
			"max_height": biome.max_height,
			"min_temperature": biome.min_temperature,
			"max_temperature": biome.max_temperature,
			"min_moisture": biome.min_moisture,
			"max_moisture": biome.max_moisture,
			"min_ruggedness": biome.min_ruggedness,
			"max_ruggedness": biome.max_ruggedness,
			"min_flora_density": biome.min_flora_density,
			"max_flora_density": biome.max_flora_density,
			"min_latitude": biome.min_latitude,
			"max_latitude": biome.max_latitude,
			"min_drainage": biome.min_drainage,
			"max_drainage": biome.max_drainage,
			"min_slope": biome.min_slope,
			"max_slope": biome.max_slope,
			"min_rain_shadow": biome.min_rain_shadow,
			"max_rain_shadow": biome.max_rain_shadow,
			"min_continentalness": biome.min_continentalness,
			"max_continentalness": biome.max_continentalness,
			"min_ridge_strength": biome.min_ridge_strength,
			"max_ridge_strength": biome.max_ridge_strength,
			"min_river_strength": biome.min_river_strength,
			"max_river_strength": biome.max_river_strength,
			"min_floodplain_strength": biome.min_floodplain_strength,
			"max_floodplain_strength": biome.max_floodplain_strength,
			"height_weight": biome.height_weight,
			"temperature_weight": biome.temperature_weight,
			"moisture_weight": biome.moisture_weight,
			"ruggedness_weight": biome.ruggedness_weight,
			"flora_density_weight": biome.flora_density_weight,
			"latitude_weight": biome.latitude_weight,
			"drainage_weight": biome.drainage_weight,
			"slope_weight": biome.slope_weight,
			"rain_shadow_weight": biome.rain_shadow_weight,
			"continentalness_weight": biome.continentalness_weight,
			"ridge_strength_weight": biome.ridge_strength_weight,
			"river_strength_weight": biome.river_strength_weight,
			"floodplain_strength_weight": biome.floodplain_strength_weight,
			"tags": biome.tags.duplicate() if biome.tags else [],
			"flora_set_ids": biome.flora_set_ids.duplicate() if biome.flora_set_ids else [],
			"decor_set_ids": biome.decor_set_ids.duplicate() if biome.decor_set_ids else [],
		})
	params["biomes"] = biome_defs
	var flora_set_defs: Array = []
	var decor_set_defs: Array = []
	var seen_flora_ids: Dictionary = {}
	var seen_decor_ids: Dictionary = {}
	if FloraDecorRegistry != null:
		for biome_data: BiomeData in palette_order:
			if biome_data == null:
				continue
			for flora_set_id: StringName in biome_data.flora_set_ids:
				if seen_flora_ids.has(flora_set_id):
					continue
				var flora_set = FloraDecorRegistry.get_flora_set(flora_set_id)
				if flora_set == null:
					continue
				seen_flora_ids[flora_set_id] = true
				var flora_set_dict: Dictionary = {
					"id": flora_set.id,
					"base_density": flora_set.base_density,
					"flora_channel_weight": flora_set.flora_channel_weight,
					"flora_modulation_weight": flora_set.flora_modulation_weight,
					"subzone_filters": flora_set.subzone_filters.duplicate() if flora_set.subzone_filters else [],
					"excluded_subzones": flora_set.excluded_subzones.duplicate() if flora_set.excluded_subzones else [],
				}
				var flora_entries: Array = []
				for entry_resource in flora_set.entries:
					if entry_resource == null:
						continue
					flora_entries.append({
						"id": entry_resource.id,
						"color": entry_resource.placeholder_color,
						"size": entry_resource.placeholder_size,
						"z_offset": entry_resource.z_index_offset,
						"texture_path": entry_resource.texture.resource_path if entry_resource.texture != null else "",
						"weight": entry_resource.weight,
						"min_density_threshold": entry_resource.min_density_threshold,
						"max_density_threshold": entry_resource.max_density_threshold,
					})
				flora_set_dict["entries"] = flora_entries
				flora_set_defs.append(flora_set_dict)
		for biome_data: BiomeData in palette_order:
			if biome_data == null:
				continue
			for decor_set_id: StringName in biome_data.decor_set_ids:
				if seen_decor_ids.has(decor_set_id):
					continue
				var decor_set = FloraDecorRegistry.get_decor_set(decor_set_id)
				if decor_set == null:
					continue
				seen_decor_ids[decor_set_id] = true
				var decor_set_dict: Dictionary = {
					"id": decor_set.id,
					"base_density": decor_set.base_density,
					"entries": [],
					"subzone_density_modifiers": decor_set.subzone_density_modifiers.duplicate() if decor_set.subzone_density_modifiers else {},
				}
				var decor_entries: Array = []
				for entry_resource in decor_set.entries:
					if entry_resource == null:
						continue
					decor_entries.append({
						"id": entry_resource.id,
						"color": entry_resource.placeholder_color,
						"size": entry_resource.placeholder_size,
						"z_offset": entry_resource.z_index_offset,
						"texture_path": entry_resource.texture.resource_path if entry_resource.texture != null else "",
						"weight": entry_resource.weight,
					})
				decor_set_dict["entries"] = decor_entries
				decor_set_defs.append(decor_set_dict)
	params["flora_sets"] = flora_set_defs
	params["decor_sets"] = decor_set_defs
	var feature_hook_defs: Array = []
	var poi_defs: Array = []
	if WorldFeatureRegistry != null and WorldFeatureRegistry.is_ready():
		for feature_hook: Resource in WorldFeatureRegistry.get_all_feature_hooks():
			if feature_hook == null:
				continue
			var feature_hook_id: StringName = feature_hook.get("id") as StringName
			if feature_hook_id == &"":
				continue
			feature_hook_defs.append({
				"id": feature_hook_id,
				"allowed_biome_ids": feature_hook.allowed_biome_ids.duplicate(),
				"required_structure_tags": feature_hook.required_structure_tags.duplicate(),
				"allowed_terrain_types": feature_hook.allowed_terrain_types.duplicate(),
				"weight": feature_hook.weight,
				"debug_marker_kind": feature_hook.debug_marker_kind,
			})
		for poi_resource: Resource in WorldFeatureRegistry.get_all_pois():
			if poi_resource == null:
				continue
			var poi_id: StringName = poi_resource.get("id") as StringName
			if poi_id == &"":
				continue
			var footprint_tiles: Array = []
			if poi_resource.has_method("get_effective_footprint_offsets"):
				footprint_tiles = (poi_resource.call("get_effective_footprint_offsets") as Array).duplicate()
			else:
				footprint_tiles = poi_resource.footprint_tiles.duplicate()
			poi_defs.append({
				"id": poi_id,
				"required_feature_hook_ids": poi_resource.required_feature_hook_ids.duplicate(),
				"allowed_biome_ids": poi_resource.allowed_biome_ids.duplicate(),
				"required_structure_tags": poi_resource.required_structure_tags.duplicate(),
				"allowed_terrain_types": poi_resource.allowed_terrain_types.duplicate(),
				"footprint_tiles": footprint_tiles,
				"anchor_offset": poi_resource.anchor_offset,
				"priority": poi_resource.priority,
				"debug_marker_kind": poi_resource.debug_marker_kind,
			})
	params["feature_hooks"] = feature_hook_defs
	params["pois"] = poi_defs

	return params

func _build_native_prepass_params(pre_pass: WorldPrePass) -> Dictionary:
	if pre_pass == null:
		return {}
	var snapshot: Dictionary = pre_pass.build_native_chunk_generator_snapshot()
	if snapshot.is_empty():
		return {}
	snapshot["prepass_seed"] = world_seed
	return snapshot

func get_native_chunk_generator() -> RefCounted:
	return _native_chunk_generator

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

func _publish_initialized_runtime_state(
	seed_value: int,
	balance_snapshot: WorldGenBalance,
	pre_pass_result: Dictionary
) -> void:
	var published_pre_pass: RefCounted = pre_pass_result.get("world_pre_pass", null) as RefCounted
	if published_pre_pass == null:
		push_error("WorldGenerator publish step requires a computed WorldPrePass result")
		return
	world_seed = seed_value
	balance = balance_snapshot if balance_snapshot != null else _duplicate_runtime_balance(_base_balance)
	var step_started_usec: int = WorldPerfProbe.begin()
	_setup_biome_resolver()
	WorldPerfProbe.end("WorldGenerator.initialize_world.setup_biome_resolver", step_started_usec)
	step_started_usec = WorldPerfProbe.begin()
	_setup_planet_sampler()
	WorldPerfProbe.end("WorldGenerator.initialize_world.setup_planet_sampler", step_started_usec)
	var worker_planet_sampler_ms: float = float(pre_pass_result.get("worker_planet_sampler_ms", 0.0))
	if worker_planet_sampler_ms > 0.0:
		WorldPerfProbe.record("WorldGenerator._setup_world_pre_pass.worker_planet_sampler", worker_planet_sampler_ms)
	var configure_ms: float = float(pre_pass_result.get("configure_ms", 0.0))
	if configure_ms > 0.0:
		WorldPerfProbe.record("WorldGenerator._setup_world_pre_pass.configure", configure_ms)
	var compute_ms: float = float(pre_pass_result.get("compute_ms", 0.0))
	if compute_ms > 0.0:
		WorldPerfProbe.record("WorldGenerator._setup_world_pre_pass.compute", compute_ms)
	var setup_world_pre_pass_ms: float = float(pre_pass_result.get("setup_world_pre_pass_ms", 0.0))
	if setup_world_pre_pass_ms > 0.0:
		WorldPerfProbe.record("WorldGenerator.initialize_world.setup_world_pre_pass", setup_world_pre_pass_ms)
	_world_pre_pass = published_pre_pass
	step_started_usec = WorldPerfProbe.begin()
	_setup_local_variation_resolver()
	WorldPerfProbe.end("WorldGenerator.initialize_world.setup_local_variation_resolver", step_started_usec)
	spawn_tile = canonicalize_tile(spawn_tile)
	_chunk_biome_cache.clear()
	current_biome = BiomeRegistry.get_default_biome()
	step_started_usec = WorldPerfProbe.begin()
	_setup_compute_context()
	WorldPerfProbe.end("WorldGenerator.initialize_world.setup_compute_context", step_started_usec)
	step_started_usec = WorldPerfProbe.begin()
	current_biome = get_biome_at_tile(spawn_tile)
	WorldPerfProbe.end("WorldGenerator.initialize_world.resolve_spawn_biome", step_started_usec)
	if _compute_context != null:
		_compute_context.current_biome = current_biome
	if _surface_terrain_resolver != null:
		step_started_usec = WorldPerfProbe.begin()
		_surface_terrain_resolver.initialize(balance, _compute_context)
		WorldPerfProbe.end("WorldGenerator.initialize_world.reinitialize_surface_terrain_resolver", step_started_usec)
	step_started_usec = WorldPerfProbe.begin()
	_setup_chunk_content_builder()
	WorldPerfProbe.end("WorldGenerator.initialize_world.setup_chunk_content_builder", step_started_usec)
	_is_initialized = true
	step_started_usec = WorldPerfProbe.begin()
	EventBus.world_initialized.emit(world_seed)
	WorldPerfProbe.end("WorldGenerator.initialize_world.emit_world_initialized", step_started_usec)

func _clear_initialized_runtime_state() -> void:
	_is_initialized = false
	_chunk_biome_cache.clear()
	_feature_and_poi_payload_cache.clear()
	_chunk_content_builder = null
	_native_chunk_generator = null
	_surface_terrain_resolver = null
	_compute_context = null
	_local_variation_resolver = null
	_biome_resolver = null
	_planet_sampler = null
	_world_pre_pass = null

func _create_chunk_content_builder(world_context: RefCounted) -> ChunkContentBuilder:
	if world_context == null:
		return null
	var builder := ChunkContentBuilder.new()
	builder.initialize(
		balance,
		world_context,
		_create_surface_terrain_resolver(world_context),
		_feature_and_poi_payload_cache
	)
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
