class_name WorldLab
extends Control

## WorldLab - single-seed world viewer.
## Renders one large overview map for the selected seed without touching runtime chunks.

const MAX_PREVIEW_WIDTH: int = 1024
const MAX_PREVIEW_HEIGHT: int = 640
const PROGRESS_ROW_BATCH: int = 16

const TERRAIN_COLORS: Dictionary = {
	0: Color(0.22, 0.35, 0.15),  # GROUND
	1: Color(0.45, 0.40, 0.38),  # ROCK
	2: Color(0.12, 0.22, 0.45),  # WATER
	3: Color(0.55, 0.48, 0.30),  # SAND
	4: Color(0.30, 0.42, 0.18),  # GRASS
	5: Color(0.37, 0.32, 0.26),  # MINED_FLOOR
	6: Color(0.42, 0.36, 0.29),  # MOUNTAIN_ENTRANCE
}

enum MapMode {
	TERRAIN,
	BIOME,
}

class WorldLabSampler:
	extends RefCounted

	var _balance: WorldGenBalance = null
	var _seed_value: int = 0
	var _spawn_tile: Vector2i = Vector2i.ZERO
	var _wrap_width: int = 0
	var _wrap_chunk_count: int = 0
	var _native_generator: RefCounted = null
	var _native_chunk_cache: Dictionary = {}
	var _world_context: WorldComputeContext = null
	var _surface_terrain_resolver: SurfaceTerrainResolver = null

	func configure(request: Dictionary) -> WorldLabSampler:
		_balance = request.get("balance", null) as WorldGenBalance
		_seed_value = int(request.get("seed", 0))
		_spawn_tile = request.get("spawn_tile", Vector2i.ZERO)
		_wrap_width = int(request.get("wrap_width", 0))
		var chunk_size: int = _balance.chunk_size_tiles if _balance else 1
		_wrap_chunk_count = maxi(1, int(ceili(float(maxi(1, _wrap_width)) / float(maxi(1, chunk_size)))))
		_build_gdscript_fallback(request)
		_build_native_generator(request)
		return self

	func sample_tile(tile_pos: Vector2i) -> Dictionary:
		if _native_generator != null:
			var native_tile: Dictionary = _sample_tile_native(tile_pos)
			if not native_tile.is_empty():
				return native_tile
		return _sample_tile_gdscript(tile_pos)

	func _build_native_generator(request: Dictionary) -> void:
		if _balance == null or not bool(request.get("use_native", false)):
			return
		if not ClassDB.class_exists(&"ChunkGenerator"):
			return
		var generator: RefCounted = ClassDB.instantiate(&"ChunkGenerator")
		if generator == null:
			return
		var params: Dictionary = (request.get("native_params", {}) as Dictionary).duplicate(true)
		generator.initialize(_seed_value, params)
		_native_generator = generator

	func _build_gdscript_fallback(request: Dictionary) -> void:
		if _balance == null:
			return
		var all_biomes: Array[BiomeData] = []
		for entry: Variant in request.get("all_biomes", []):
			if entry is BiomeData:
				all_biomes.append(entry as BiomeData)
		var palette_order: Array[BiomeData] = []
		for entry: Variant in request.get("palette_order", []):
			if entry is BiomeData:
				palette_order.append(entry as BiomeData)
		var default_biome: BiomeData = request.get("default_biome", null) as BiomeData

		var planet_sampler := PlanetSampler.new()
		planet_sampler.initialize(_seed_value, _balance)

		var structure_sampler := LargeStructureSampler.new()
		structure_sampler.initialize(_seed_value, _balance)

		var biome_resolver := BiomeResolver.new()
		biome_resolver.configure(all_biomes)

		var local_variation_resolver := LocalVariationResolver.new()
		local_variation_resolver.initialize(_seed_value, _balance)

		var biome_by_id: Dictionary = {}
		var palette_index_by_id: Dictionary = {}
		for index: int in range(palette_order.size()):
			var biome: BiomeData = palette_order[index]
			if biome == null or str(biome.id).is_empty():
				continue
			biome_by_id[biome.id] = biome
			palette_index_by_id[biome.id] = index

		_world_context = WorldComputeContext.new().configure(
			_balance,
			_seed_value,
			_spawn_tile,
			default_biome,
			default_biome,
			planet_sampler,
			structure_sampler,
			biome_resolver,
			local_variation_resolver,
			biome_by_id,
			palette_index_by_id,
			[]
		)
		_surface_terrain_resolver = SurfaceTerrainResolver.new().initialize(_balance, _world_context)
		_world_context.set_surface_terrain_resolver(_surface_terrain_resolver)
		var spawn_biome: BiomeData = _world_context.get_biome_at_tile(_spawn_tile)
		if spawn_biome != null:
			_world_context.current_biome = spawn_biome
			_surface_terrain_resolver.initialize(_balance, _world_context)

	func _sample_tile_native(tile_pos: Vector2i) -> Dictionary:
		if _native_generator == null or _balance == null:
			return {}
		var chunk_size: int = maxi(1, _balance.chunk_size_tiles)
		var wrapped_x: int = int(posmod(tile_pos.x, maxi(1, _wrap_width)))
		var chunk_x: int = int(posmod(floori(float(wrapped_x) / float(chunk_size)), _wrap_chunk_count))
		var chunk_y: int = floori(float(tile_pos.y) / float(chunk_size))
		var chunk_coord := Vector2i(chunk_x, chunk_y)
		var chunk_data: Dictionary = _get_native_chunk(chunk_coord)
		if chunk_data.is_empty():
			return {}

		var local_x: int = int(posmod(wrapped_x, chunk_size))
		var local_y: int = tile_pos.y - chunk_y * chunk_size
		var tile_index: int = local_y * chunk_size + local_x
		var terrain_arr: PackedByteArray = chunk_data.get("terrain", PackedByteArray())
		var biome_arr: PackedByteArray = chunk_data.get("biome", PackedByteArray())
		if tile_index < 0 or tile_index >= terrain_arr.size():
			return {}
		return {
			"terrain": int(terrain_arr[tile_index]),
			"biome": int(biome_arr[tile_index]) if tile_index < biome_arr.size() else 0,
		}

	func _get_native_chunk(chunk_coord: Vector2i) -> Dictionary:
		if _native_chunk_cache.has(chunk_coord):
			return _native_chunk_cache[chunk_coord]
		if _native_generator == null:
			return {}
		var chunk_data: Dictionary = _native_generator.generate_chunk(chunk_coord, _spawn_tile)
		_native_chunk_cache[chunk_coord] = chunk_data
		return chunk_data

	func _sample_tile_gdscript(tile_pos: Vector2i) -> Dictionary:
		if _surface_terrain_resolver == null or _world_context == null:
			return {
				"terrain": 0,
				"biome": 0,
			}
		var tile_data: TileGenData = _surface_terrain_resolver.build_tile_data(tile_pos)
		return {
			"terrain": int(tile_data.terrain),
			"biome": int(tile_data.biome_palette_index),
		}

var _status_label: Label = null
var _seed_input: SpinBox = null
var _mode_option: OptionButton = null
var _generate_button: Button = null
var _cancel_button: Button = null
var _preview_title: Label = null
var _preview_texture_rect: TextureRect = null
var _preview_meta: Label = null

var _generation_id: int = 0
var _terrain_image: Image = null
var _biome_image: Image = null
var _current_seed: int = 0
var _current_preview_size: Vector2i = Vector2i.ZERO
var _current_sample_step: int = 1
var _current_world_size: Vector2i = Vector2i.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.06)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_KEEP_SIZE, 12)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	root.add_child(top_bar)

	var title := Label.new()
	title.text = "WorldLab"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.35))
	top_bar.add_child(title)

	var seed_label := Label.new()
	seed_label.text = "Seed:"
	top_bar.add_child(seed_label)

	_seed_input = SpinBox.new()
	_seed_input.min_value = 1
	_seed_input.max_value = 999999
	_seed_input.value = 42
	_seed_input.custom_minimum_size.x = 110
	top_bar.add_child(_seed_input)

	var mode_label := Label.new()
	mode_label.text = "Map:"
	top_bar.add_child(mode_label)

	_mode_option = OptionButton.new()
	_mode_option.add_item("Terrain", MapMode.TERRAIN)
	_mode_option.add_item("Biome", MapMode.BIOME)
	_mode_option.selected = 0
	_mode_option.item_selected.connect(_on_mode_changed)
	top_bar.add_child(_mode_option)

	_generate_button = Button.new()
	_generate_button.text = "Generate"
	_generate_button.custom_minimum_size = Vector2(110, 34)
	_generate_button.pressed.connect(_on_generate_pressed)
	top_bar.add_child(_generate_button)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.custom_minimum_size = Vector2(90, 34)
	_cancel_button.disabled = true
	_cancel_button.pressed.connect(_on_cancel_pressed)
	top_bar.add_child(_cancel_button)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(90, 34)
	back_button.pressed.connect(_on_back_pressed)
	top_bar.add_child(back_button)

	_status_label = Label.new()
	_status_label.text = "Ready to render a full-seed overview."
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.58, 0.62, 0.66))
	root.add_child(_status_label)

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.10)
	style.border_color = Color(0.18, 0.20, 0.24)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	preview_panel.add_theme_stylebox_override("panel", style)
	root.add_child(preview_panel)

	var preview_margin := MarginContainer.new()
	preview_panel.add_child(preview_margin)

	var preview_box := VBoxContainer.new()
	preview_box.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_box.size_flags_vertical = SIZE_EXPAND_FILL
	preview_box.add_theme_constant_override("separation", 8)
	preview_margin.add_child(preview_box)

	_preview_title = Label.new()
	_preview_title.text = "Terrain Preview"
	_preview_title.add_theme_font_size_override("font_size", 18)
	_preview_title.add_theme_color_override("font_color", Color(0.82, 0.84, 0.88))
	preview_box.add_child(_preview_title)

	_preview_texture_rect = TextureRect.new()
	_preview_texture_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_texture_rect.size_flags_vertical = SIZE_EXPAND_FILL
	_preview_texture_rect.custom_minimum_size = Vector2(960, 560)
	_preview_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_box.add_child(_preview_texture_rect)

	_preview_meta = Label.new()
	_preview_meta.text = "No preview generated yet."
	_preview_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_meta.add_theme_font_size_override("font_size", 12)
	_preview_meta.add_theme_color_override("font_color", Color(0.58, 0.62, 0.66))
	preview_box.add_child(_preview_meta)

func _on_mode_changed(_index: int) -> void:
	_refresh_preview_texture()

func _on_generate_pressed() -> void:
	var seed_value: int = int(_seed_input.value)
	var request: Dictionary = _build_generation_request(seed_value)
	if request.is_empty():
		_status_label.text = "Failed to prepare world sampler."
		return
	_generation_id += 1
	_current_seed = seed_value
	_generate_button.disabled = true
	_cancel_button.disabled = false
	_terrain_image = null
	_biome_image = null
	_preview_texture_rect.texture = null
	_preview_title.text = "%s Preview" % _current_mode_name()
	_preview_meta.text = "Generating seed %d..." % seed_value
	_status_label.text = "Generating seed %d..." % seed_value
	var gen_id: int = _generation_id
	WorkerThreadPool.add_task(_worker_generate.bind(request, gen_id))

func _on_cancel_pressed() -> void:
	_generation_id += 1
	_generate_button.disabled = false
	_cancel_button.disabled = true
	_status_label.text = "Cancelled"
	if _preview_texture_rect.texture == null:
		_preview_meta.text = "Generation cancelled."

func _on_back_pressed() -> void:
	_generation_id += 1
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _worker_generate(request: Dictionary, gen_id: int) -> void:
	if gen_id != _generation_id:
		return
	var sampler := WorldLabSampler.new().configure(request)
	var wrap_width: int = int(request.get("wrap_width", 0))
	var lat_span: int = int(request.get("lat_span", 0))
	var start_y: int = int(request.get("start_y", 0))
	var seed_value: int = int(request.get("seed", 0))
	var preview_layout: Dictionary = _compute_preview_layout(wrap_width, lat_span)
	var preview_w: int = int(preview_layout.get("preview_w", 0))
	var preview_h: int = int(preview_layout.get("preview_h", 0))
	var step: int = int(preview_layout.get("step", 1))
	if preview_w <= 0 or preview_h <= 0:
		call_deferred("_on_worker_failed", gen_id, seed_value)
		return

	var terrain_img := Image.create(preview_w, preview_h, false, Image.FORMAT_RGB8)
	var biome_img := Image.create(preview_w, preview_h, false, Image.FORMAT_RGB8)
	var biome_colors: Array = request.get("biome_colors", [])

	for py: int in range(preview_h):
		if gen_id != _generation_id:
			return
		var wy: int = mini(start_y + py * step, start_y + lat_span - 1)
		for px: int in range(preview_w):
			var wx: int = mini(px * step, wrap_width - 1)
			var tile_data: Dictionary = sampler.sample_tile(Vector2i(wx, wy))
			var terrain_type: int = int(tile_data.get("terrain", 0))
			var biome_idx: int = int(tile_data.get("biome", 0))
			terrain_img.set_pixel(px, py, TERRAIN_COLORS.get(terrain_type, Color(0.2, 0.2, 0.2)))
			biome_img.set_pixel(px, py, _resolve_biome_preview_color(biome_colors, biome_idx))
		if (py + 1) % PROGRESS_ROW_BATCH == 0 or py == preview_h - 1:
			call_deferred("_on_worker_progress", gen_id, seed_value, py + 1, preview_h)

	call_deferred(
		"_on_worker_done",
		gen_id,
		seed_value,
		terrain_img,
		biome_img,
		Vector2i(preview_w, preview_h),
		step,
		Vector2i(wrap_width, lat_span)
	)

func _on_worker_progress(gen_id: int, seed_value: int, completed_rows: int, total_rows: int) -> void:
	if gen_id != _generation_id:
		return
	_status_label.text = "Generating seed %d... %d/%d rows" % [seed_value, completed_rows, total_rows]

func _on_worker_failed(gen_id: int, seed_value: int) -> void:
	if gen_id != _generation_id:
		return
	_generate_button.disabled = false
	_cancel_button.disabled = true
	_status_label.text = "Generation failed for seed %d." % seed_value
	_preview_meta.text = "WorldLab could not build the preview for seed %d." % seed_value

func _on_worker_done(
	gen_id: int,
	seed_value: int,
	terrain_img: Image,
	biome_img: Image,
	preview_size: Vector2i,
	step: int,
	world_size: Vector2i
) -> void:
	if gen_id != _generation_id:
		return
	_terrain_image = terrain_img
	_biome_image = biome_img
	_current_seed = seed_value
	_current_preview_size = preview_size
	_current_sample_step = step
	_current_world_size = world_size
	_generate_button.disabled = false
	_cancel_button.disabled = true
	_status_label.text = "Seed %d rendered." % seed_value
	_refresh_preview_texture()

func _refresh_preview_texture() -> void:
	_preview_title.text = "%s Preview" % _current_mode_name()
	var selected_mode: int = _mode_option.get_item_id(_mode_option.selected) if _mode_option != null else MapMode.TERRAIN
	var source_image: Image = _terrain_image if selected_mode == MapMode.TERRAIN else _biome_image
	if source_image == null:
		_preview_texture_rect.texture = null
		return
	_preview_texture_rect.texture = ImageTexture.create_from_image(source_image)
	_preview_meta.text = "Seed %d | world %dx%d tiles | sample step %d | preview %dx%d" % [
		_current_seed,
		_current_world_size.x,
		_current_world_size.y,
		_current_sample_step,
		_current_preview_size.x,
		_current_preview_size.y,
	]

func _current_mode_name() -> String:
	var selected_mode: int = _mode_option.get_item_id(_mode_option.selected) if _mode_option != null else MapMode.TERRAIN
	return "Biome" if selected_mode == MapMode.BIOME else "Terrain"

func _compute_preview_layout(wrap_width: int, lat_span: int) -> Dictionary:
	if wrap_width <= 0 or lat_span <= 0:
		return {
			"step": 1,
			"preview_w": 0,
			"preview_h": 0,
		}
	var required_step: int = maxi(
		1,
		maxi(
			ceili(float(wrap_width) / float(MAX_PREVIEW_WIDTH)),
			ceili(float(lat_span) / float(MAX_PREVIEW_HEIGHT))
		)
	)
	return {
		"step": required_step,
		"preview_w": maxi(1, ceili(float(wrap_width) / float(required_step))),
		"preview_h": maxi(1, ceili(float(lat_span) / float(required_step))),
	}

func _build_generation_request(seed_value: int) -> Dictionary:
	var balance: WorldGenBalance = _load_balance()
	if balance == null:
		return {}
	var wrap_width: int = _calc_wrap_width(balance)
	var lat_span: int = maxi(256, balance.latitude_half_span_tiles) * 2
	var equator_y: int = balance.equator_tile_y
	return {
		"seed": seed_value,
		"balance": balance,
		"wrap_width": wrap_width,
		"lat_span": lat_span,
		"start_y": equator_y - lat_span / 2,
		"spawn_tile": Vector2i(wrap_width / 2, equator_y),
		"all_biomes": BiomeRegistry.get_all_biomes(),
		"palette_order": BiomeRegistry.get_palette_order(),
		"biome_colors": _build_biome_preview_colors(),
		"default_biome": BiomeRegistry.get_default_biome(),
		"use_native": balance.use_native_chunk_generation,
		"native_params": _build_generator_params(balance),
	}

func _build_biome_preview_colors() -> Array[Color]:
	var colors: Array[Color] = []
	var palette: Array[BiomeData] = BiomeRegistry.get_palette_order()
	for biome: BiomeData in palette:
		colors.append(biome.ground_color if biome else Color(0.22, 0.18, 0.12))
	return colors

func _resolve_biome_preview_color(biome_colors: Array, biome_idx: int) -> Color:
	if biome_idx >= 0 and biome_idx < biome_colors.size():
		var color_value: Variant = biome_colors[biome_idx]
		if color_value is Color:
			return color_value
	return Color(0.22, 0.18, 0.12)

func _load_balance() -> WorldGenBalance:
	var res: Resource = load("res://data/world/world_gen_balance.tres")
	return res as WorldGenBalance

func _calc_wrap_width(balance: WorldGenBalance) -> int:
	var tile_width: int = maxi(256, balance.world_wrap_width_tiles)
	var chunk_size: int = maxi(1, balance.chunk_size_tiles)
	var chunk_count: int = maxi(1, int(ceili(float(tile_width) / float(chunk_size))))
	return chunk_count * chunk_size

func _build_generator_params(balance: WorldGenBalance) -> Dictionary:
	var wrap_width: int = _calc_wrap_width(balance)
	var params: Dictionary = {
		"chunk_size": balance.chunk_size_tiles,
		"wrap_width": wrap_width,
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
	}

	var biome_defs: Array = []
	var palette_order: Array[BiomeData] = BiomeRegistry.get_palette_order()
	for index: int in range(palette_order.size()):
		var biome: BiomeData = palette_order[index]
		if biome == null or str(biome.id).is_empty():
			continue
		biome_defs.append({
			"id": biome.id,
			"priority": biome.priority,
			"palette_index": index,
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
			"ridge_strength_weight": biome.ridge_strength_weight,
			"river_strength_weight": biome.river_strength_weight,
			"floodplain_strength_weight": biome.floodplain_strength_weight,
			"tags": biome.tags.duplicate() if biome.tags else [],
			"flora_set_ids": [],
			"decor_set_ids": [],
		})
	params["biomes"] = biome_defs

	var flora_set_defs: Array = []
	var decor_set_defs: Array = []
	var seen_flora_ids: Dictionary = {}
	var seen_decor_ids: Dictionary = {}
	if FloraDecorRegistry:
		for biome_data: BiomeData in palette_order:
			if biome_data == null:
				continue
			for flora_set_id: StringName in biome_data.flora_set_ids:
				if seen_flora_ids.has(flora_set_id):
					continue
				var flora_set: Resource = FloraDecorRegistry.get_flora_set(flora_set_id)
				if flora_set == null:
					continue
				seen_flora_ids[flora_set_id] = true
				var flora_dict: Dictionary = {
					"id": flora_set.id,
					"base_density": flora_set.base_density,
					"flora_channel_weight": flora_set.flora_channel_weight,
					"flora_modulation_weight": flora_set.flora_modulation_weight,
					"subzone_filters": flora_set.subzone_filters.duplicate() if flora_set.subzone_filters else [],
					"excluded_subzones": flora_set.excluded_subzones.duplicate() if flora_set.excluded_subzones else [],
				}
				var flora_entries: Array = []
				for flora_entry: Resource in flora_set.entries:
					if flora_entry == null:
						continue
					flora_entries.append({
						"id": flora_entry.id,
						"color": flora_entry.placeholder_color,
						"size": flora_entry.placeholder_size,
						"z_offset": flora_entry.z_index_offset,
						"weight": flora_entry.weight,
						"min_density_threshold": flora_entry.min_density_threshold,
						"max_density_threshold": flora_entry.max_density_threshold,
					})
				flora_dict["entries"] = flora_entries
				flora_set_defs.append(flora_dict)
		for biome_data_2: BiomeData in palette_order:
			if biome_data_2 == null:
				continue
			for decor_set_id: StringName in biome_data_2.decor_set_ids:
				if seen_decor_ids.has(decor_set_id):
					continue
				var decor_set: Resource = FloraDecorRegistry.get_decor_set(decor_set_id)
				if decor_set == null:
					continue
				seen_decor_ids[decor_set_id] = true
				var decor_dict: Dictionary = {
					"id": decor_set.id,
					"base_density": decor_set.base_density,
					"entries": [],
					"subzone_density_modifiers": decor_set.subzone_density_modifiers.duplicate() if decor_set.subzone_density_modifiers else {},
				}
				var decor_entries: Array = []
				for decor_entry: Resource in decor_set.entries:
					if decor_entry == null:
						continue
					decor_entries.append({
						"id": decor_entry.id,
						"color": decor_entry.placeholder_color,
						"size": decor_entry.placeholder_size,
						"z_offset": decor_entry.z_index_offset,
						"weight": decor_entry.weight,
					})
				decor_dict["entries"] = decor_entries
				decor_set_defs.append(decor_dict)
	params["flora_sets"] = flora_set_defs
	params["decor_sets"] = decor_set_defs
	return params
