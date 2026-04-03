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
const WorldFeatureHookResolverScript = preload("res://core/systems/world/world_feature_hook_resolver.gd")
const WorldPoiResolverScript = preload("res://core/systems/world/world_poi_resolver.gd")
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
var _world_pre_pass: RefCounted = null
var _compute_context: RefCounted = null
var _surface_terrain_resolver: RefCounted = null
var _chunk_content_builder: ChunkContentBuilder = null
var _native_chunk_generator: RefCounted = null
var _chunk_biome_cache: Dictionary = {}
var _feature_and_poi_payload_cache: FeatureAndPoiPayloadCache = FeatureAndPoiPayloadCache.new()

func _ready() -> void:
	balance = load(BALANCE_PATH) as WorldGenBalance
	if not balance:
		push_error(Localization.t("SYSTEM_WORLD_BALANCE_LOAD_FAILED", {"path": BALANCE_PATH}))
		return
	current_biome = BiomeRegistry.get_default_biome()

func _exit_tree() -> void:
	_chunk_biome_cache.clear()
	_feature_and_poi_payload_cache.clear()
	_chunk_content_builder = null
	_surface_terrain_resolver = null
	_compute_context = null
	_local_variation_resolver = null
	_biome_resolver = null
	_structure_sampler = null
	_planet_sampler = null
	_world_pre_pass = null

func initialize_world(seed_value: int) -> void:
	if not _ensure_world_feature_registry_ready():
		_clear_initialized_runtime_state()
		return
	_feature_and_poi_payload_cache.clear()
	world_seed = seed_value
	_setup_planet_sampler()
	_setup_structure_sampler()
	_setup_biome_resolver()
	_setup_local_variation_resolver()
	_setup_world_pre_pass()
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

func _setup_world_pre_pass() -> void:
	_world_pre_pass = WorldPrePassScript.new().configure(balance, _planet_sampler).compute()

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
		world_seed,
		spawn_tile,
		current_biome,
		BiomeRegistry.get_default_biome(),
		_planet_sampler,
		_structure_sampler,
		_biome_resolver,
		_local_variation_resolver,
		biome_by_id,
		palette_index_by_id,
		WorldFeatureRegistry.get_all_feature_hooks(),
		_world_pre_pass
	)
	_surface_terrain_resolver = _create_surface_terrain_resolver(_compute_context)
	_compute_context.set_surface_terrain_resolver(_surface_terrain_resolver)
	_setup_native_chunk_generator(palette_index_by_id)

func _setup_native_chunk_generator(palette_index_by_id: Dictionary) -> void:
	_native_chunk_generator = null
	if not balance or not balance.use_native_chunk_generation:
		return
	if not ClassDB.class_exists(&"ChunkGenerator"):
		push_warning("[WorldGenerator] ChunkGenerator C++ class not available — falling back to GDScript")
		return
	var gen: RefCounted = ClassDB.instantiate(&"ChunkGenerator")
	if gen == null:
		return
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
		"ridge_warp_frequency": balance.ridge_warp_frequency,
		"ridge_warp_amplitude_tiles": balance.ridge_warp_amplitude_tiles,
		"ridge_cluster_frequency": balance.ridge_cluster_frequency,
		"ridge_spacing_tiles": balance.ridge_spacing_tiles,
		"ridge_core_width_tiles": balance.ridge_core_width_tiles,
		"ridge_feather_tiles": balance.ridge_feather_tiles,
		"ridge_secondary_warp_frequency": balance.ridge_secondary_warp_frequency,
		"ridge_secondary_weight": balance.get("ridge_secondary_weight") if balance.get("ridge_secondary_weight") != null else 0.0,
		"ridge_secondary_warp_amplitude_tiles": balance.get("ridge_secondary_warp_amplitude_tiles") if balance.get("ridge_secondary_warp_amplitude_tiles") != null else 0.0,
		"ridge_secondary_spacing_tiles": balance.get("ridge_secondary_spacing_tiles") if balance.get("ridge_secondary_spacing_tiles") != null else 0.0,
		"ridge_secondary_core_width_tiles": balance.get("ridge_secondary_core_width_tiles") if balance.get("ridge_secondary_core_width_tiles") != null else 0.0,
		"ridge_secondary_feather_tiles": balance.get("ridge_secondary_feather_tiles") if balance.get("ridge_secondary_feather_tiles") != null else 0.0,
		"river_spacing_tiles": balance.river_spacing_tiles,
		"river_core_width_tiles": balance.river_core_width_tiles,
		"river_floodplain_width_tiles": balance.river_floodplain_width_tiles,
		"river_warp_frequency": balance.river_warp_frequency,
		"river_warp_amplitude_tiles": balance.river_warp_amplitude_tiles,
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
		"hot_evaporation_rate": balance.hot_evaporation_rate,
	}
	# Biome definitions
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
			"min_height": biome.min_height, "max_height": biome.max_height,
			"min_temperature": biome.min_temperature, "max_temperature": biome.max_temperature,
			"min_moisture": biome.min_moisture, "max_moisture": biome.max_moisture,
			"min_ruggedness": biome.min_ruggedness, "max_ruggedness": biome.max_ruggedness,
			"min_flora_density": biome.min_flora_density, "max_flora_density": biome.max_flora_density,
			"min_latitude": biome.min_latitude, "max_latitude": biome.max_latitude,
			"min_ridge_strength": biome.min_ridge_strength, "max_ridge_strength": biome.max_ridge_strength,
			"min_river_strength": biome.min_river_strength, "max_river_strength": biome.max_river_strength,
			"min_floodplain_strength": biome.min_floodplain_strength, "max_floodplain_strength": biome.max_floodplain_strength,
			"height_weight": biome.height_weight,
			"temperature_weight": biome.temperature_weight,
			"moisture_weight": biome.moisture_weight,
			"ruggedness_weight": biome.ruggedness_weight,
			"flora_density_weight": biome.flora_density_weight,
			"latitude_weight": biome.latitude_weight,
			"ridge_strength_weight": biome.ridge_strength_weight,
			"river_strength_weight": biome.river_strength_weight,
			"floodplain_strength_weight": biome.floodplain_strength_weight,
			"tags": biome.tags.duplicate(),
			"flora_set_ids": biome.flora_set_ids.duplicate() if biome.flora_set_ids else [],
			"decor_set_ids": biome.decor_set_ids.duplicate() if biome.decor_set_ids else [],
		})
	params["biomes"] = biome_defs
	# Flora/decor set definitions for native flora computation
	# Collect unique flora/decor sets referenced by biomes
	var flora_set_defs: Array = []
	var decor_set_defs: Array = []
	var seen_flora_ids: Dictionary = {}
	var seen_decor_ids: Dictionary = {}
	if FloraDecorRegistry:
		for biome_data: BiomeData in palette_order:
			if biome_data == null:
				continue
			for fs_id: StringName in biome_data.flora_set_ids:
				if seen_flora_ids.has(fs_id):
					continue
				var fs: Resource = FloraDecorRegistry.get_flora_set(fs_id)
				if fs == null:
					continue
				seen_flora_ids[fs_id] = true
				var fs_dict: Dictionary = {
					"id": fs.id,
					"base_density": fs.base_density,
					"flora_channel_weight": fs.flora_channel_weight,
					"flora_modulation_weight": fs.flora_modulation_weight,
					"subzone_filters": fs.subzone_filters.duplicate() if fs.subzone_filters else [],
					"excluded_subzones": fs.excluded_subzones.duplicate() if fs.excluded_subzones else [],
				}
				var entries_arr: Array = []
				for entry_res: Resource in fs.entries:
					if entry_res == null:
						continue
					entries_arr.append({
						"id": entry_res.id,
						"color": entry_res.placeholder_color,
						"size": entry_res.placeholder_size,
						"z_offset": entry_res.z_index_offset,
						"weight": entry_res.weight,
						"min_density_threshold": entry_res.min_density_threshold,
						"max_density_threshold": entry_res.max_density_threshold,
					})
				fs_dict["entries"] = entries_arr
				flora_set_defs.append(fs_dict)
		for biome_data2: BiomeData in palette_order:
			if biome_data2 == null:
				continue
			for ds_id: StringName in biome_data2.decor_set_ids:
				if seen_decor_ids.has(ds_id):
					continue
				var ds: Resource = FloraDecorRegistry.get_decor_set(ds_id)
				if ds == null:
					continue
				seen_decor_ids[ds_id] = true
				var ds_dict: Dictionary = {
					"id": ds.id,
					"base_density": ds.base_density,
					"entries": [],
					"subzone_density_modifiers": ds.subzone_density_modifiers.duplicate() if ds.subzone_density_modifiers else {},
				}
				var entries_arr: Array = []
				for entry_res: Resource in ds.entries:
					if entry_res == null:
						continue
					entries_arr.append({
						"id": entry_res.id,
						"color": entry_res.placeholder_color,
						"size": entry_res.placeholder_size,
						"z_offset": entry_res.z_index_offset,
						"weight": entry_res.weight,
					})
				ds_dict["entries"] = entries_arr
				decor_set_defs.append(ds_dict)
	params["flora_sets"] = flora_set_defs
	params["decor_sets"] = decor_set_defs
	gen.initialize(world_seed, params)
	_native_chunk_generator = gen
	print("[WorldGenerator] Native ChunkGenerator initialized (%d biomes, %d flora sets, %d decor sets)" % [biome_defs.size(), flora_set_defs.size(), decor_set_defs.size()])

func get_native_chunk_generator() -> RefCounted:
	return _native_chunk_generator

func _setup_chunk_content_builder() -> void:
	_chunk_content_builder = _create_chunk_content_builder(_compute_context)

func create_detached_chunk_content_builder() -> ChunkContentBuilder:
	return _create_chunk_content_builder(_compute_context)

func _get_cached_feature_and_poi_payload(chunk_coord: Vector2i) -> Dictionary:
	var canonical_chunk: Vector2i = canonicalize_chunk_coord(chunk_coord)
	return _feature_and_poi_payload_cache.get_payload(canonical_chunk)

func _resolve_feature_hook_decisions(candidate_origin: Vector2i) -> Array[Dictionary]:
	if not _is_initialized or _compute_context == null:
		return []
	return WorldFeatureHookResolverScript.resolve_for_origin(candidate_origin, _compute_context)

func _resolve_poi_placement_decisions(candidate_origin: Vector2i) -> Array[Dictionary]:
	if not _is_initialized or _compute_context == null:
		return []
	var hook_decisions: Array[Dictionary] = _resolve_feature_hook_decisions(candidate_origin)
	var all_pois: Array[Resource] = WorldFeatureRegistry.get_all_pois() if WorldFeatureRegistry and WorldFeatureRegistry.is_ready() else []
	return WorldPoiResolverScript.resolve_for_origin(candidate_origin, hook_decisions, _compute_context, all_pois)

func _ensure_world_feature_registry_ready() -> bool:
	if not WorldFeatureRegistry or not WorldFeatureRegistry.is_ready():
		push_error("WorldFeatureRegistry must be ready before WorldGenerator.initialize_world()")
		assert(false, "WorldFeatureRegistry must be ready before world initialization")
		return false
	return true

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
	_structure_sampler = null
	_planet_sampler = null
	_world_pre_pass = null

func _create_chunk_content_builder(world_context: RefCounted) -> ChunkContentBuilder:
	if world_context == null:
		return null
	var all_pois: Array[Resource] = []
	if WorldFeatureRegistry and WorldFeatureRegistry.is_ready():
		all_pois = WorldFeatureRegistry.get_all_pois()
	var builder := ChunkContentBuilder.new()
	builder.initialize(
		balance,
		world_context,
		_create_surface_terrain_resolver(world_context),
		_feature_and_poi_payload_cache,
		all_pois
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
