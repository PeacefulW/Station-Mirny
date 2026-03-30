class_name WorldLab
extends Control

## WorldLab — Seed Atlas Viewer.
## Generates global preview minimaps for multiple seeds side by side.
## Uses WorldLabSampler (native C++ if available, GDScript fallback).
## Does NOT touch ChunkManager, Chunk, or any gameplay state.

const PREVIEW_SIZE: int = 192
const TERRAIN_COLORS: Dictionary = {
	0: Color(0.22, 0.35, 0.15),  # GROUND — dark green
	1: Color(0.45, 0.40, 0.38),  # ROCK — gray
	2: Color(0.12, 0.22, 0.45),  # WATER — blue
	3: Color(0.55, 0.48, 0.30),  # SAND — tan
	4: Color(0.30, 0.42, 0.18),  # GRASS — green
	5: Color(0.37, 0.32, 0.26),  # MINED_FLOOR
	6: Color(0.42, 0.36, 0.29),  # MOUNTAIN_ENTRANCE
}

var _grid_container: GridContainer = null
var _status_label: Label = null
var _seed_input: SpinBox = null
var _grid_size_option: OptionButton = null
var _generate_button: Button = null
var _cancel_button: Button = null
var _generation_id: int = 0
var _active_tasks: int = 0
var _grid_size: int = 3
var _cards: Array[Control] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_build_ui()

# --- UI Construction ---

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.06)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_KEEP_SIZE, 8)
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Top bar
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	vbox.add_child(top_bar)

	var title := Label.new()
	title.text = "WorldLab"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.35))
	top_bar.add_child(title)

	var seed_label := Label.new()
	seed_label.text = "Seed:"
	seed_label.add_theme_font_size_override("font_size", 14)
	top_bar.add_child(seed_label)

	_seed_input = SpinBox.new()
	_seed_input.min_value = 1
	_seed_input.max_value = 999999
	_seed_input.value = 42
	_seed_input.custom_minimum_size.x = 100
	top_bar.add_child(_seed_input)

	var grid_label := Label.new()
	grid_label.text = "Grid:"
	grid_label.add_theme_font_size_override("font_size", 14)
	top_bar.add_child(grid_label)

	_grid_size_option = OptionButton.new()
	_grid_size_option.add_item("3x3 (9)", 3)
	_grid_size_option.add_item("4x4 (16)", 4)
	_grid_size_option.add_item("5x5 (25)", 5)
	_grid_size_option.selected = 0
	_grid_size_option.item_selected.connect(_on_grid_size_changed)
	top_bar.add_child(_grid_size_option)

	_generate_button = Button.new()
	_generate_button.text = "Generate"
	_generate_button.custom_minimum_size = Vector2(100, 32)
	_generate_button.pressed.connect(_on_generate_pressed)
	top_bar.add_child(_generate_button)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.custom_minimum_size = Vector2(80, 32)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_cancel_button.disabled = true
	top_bar.add_child(_cancel_button)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(80, 32)
	back_button.pressed.connect(_on_back_pressed)
	top_bar.add_child(back_button)

	# Status
	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.5))
	vbox.add_child(_status_label)

	# Scroll + Grid
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_grid_container = GridContainer.new()
	_grid_container.columns = _grid_size
	_grid_container.add_theme_constant_override("h_separation", 6)
	_grid_container.add_theme_constant_override("v_separation", 6)
	_grid_container.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_grid_container)

# --- Events ---

func _on_grid_size_changed(idx: int) -> void:
	_grid_size = int(_grid_size_option.get_item_id(idx))
	_grid_container.columns = _grid_size

func _on_generate_pressed() -> void:
	_generation_id += 1
	_generate_button.disabled = true
	_cancel_button.disabled = false
	_clear_cards()
	var base_seed: int = int(_seed_input.value)
	var count: int = _grid_size * _grid_size
	_status_label.text = "Generating 0/%d..." % count
	_active_tasks = count
	for i: int in range(count):
		var seed_value: int = base_seed + i
		_create_placeholder_card(seed_value)
		var gen_id: int = _generation_id
		WorkerThreadPool.add_task(_worker_generate.bind(seed_value, i, gen_id))

func _on_cancel_pressed() -> void:
	_generation_id += 1
	_cancel_button.disabled = true
	_generate_button.disabled = false
	_status_label.text = "Cancelled"

func _on_back_pressed() -> void:
	_generation_id += 1
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

# --- Card Management ---

func _clear_cards() -> void:
	for card: Control in _cards:
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()

func _create_placeholder_card(seed_value: int) -> void:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11)
	style.border_color = Color(0.2, 0.22, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var seed_label := Label.new()
	seed_label.text = "Seed: %d" % seed_value
	seed_label.add_theme_font_size_override("font_size", 12)
	seed_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(seed_label)

	var maps_row := HBoxContainer.new()
	maps_row.add_theme_constant_override("separation", 3)
	maps_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(maps_row)

	var half_size: int = PREVIEW_SIZE / 2
	for map_name: String in ["Biome", "Terrain"]:
		var tex_rect := TextureRect.new()
		tex_rect.name = map_name + "Preview"
		tex_rect.custom_minimum_size = Vector2(half_size, half_size)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		maps_row.add_child(tex_rect)

	var status := Label.new()
	status.name = "StatusLabel"
	status.text = "Generating..."
	status.add_theme_font_size_override("font_size", 10)
	status.add_theme_color_override("font_color", Color(0.4, 0.45, 0.4))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status)

	_grid_container.add_child(card)
	_cards.append(card)

# --- Worker (runs on WorkerThreadPool) ---

func _worker_generate(seed_value: int, card_index: int, gen_id: int) -> void:
	if gen_id != _generation_id:
		return

	# Initialize sampler for this seed
	var balance: WorldGenBalance = _load_balance()
	if balance == null:
		call_deferred("_on_worker_done", card_index, gen_id, null, null, seed_value)
		return

	var wrap_width: int = _calc_wrap_width(balance)
	var lat_span: int = maxi(256, balance.latitude_half_span_tiles) * 2
	var step: int = maxi(1, maxi(wrap_width, lat_span) / PREVIEW_SIZE)
	var preview_w: int = wrap_width / step
	var preview_h: int = lat_span / step
	var equator_y: int = balance.equator_tile_y

	# Try native generator
	var generator: RefCounted = _create_native_generator(seed_value, balance)
	var spawn_tile: Vector2i = Vector2i(wrap_width / 2, equator_y)

	# Sample and rasterize
	var biome_img := Image.create(preview_w, preview_h, false, Image.FORMAT_RGB8)
	var terrain_img := Image.create(preview_w, preview_h, false, Image.FORMAT_RGB8)

	var start_y: int = equator_y - lat_span / 2
	for py: int in range(preview_h):
		if gen_id != _generation_id:
			return
		var wy: int = start_y + py * step
		for px: int in range(preview_w):
			var wx: int = px * step
			var tile_data: Dictionary = {}
			if generator != null:
				# Native: generate a single-tile "chunk" is wasteful.
				# Instead, generate per-chunk and sample.
				# For simplicity in iter 1: generate full chunk, read tile from it.
				var chunk_size: int = balance.chunk_size_tiles
				var chunk_coord: Vector2i = Vector2i(wx / chunk_size, wy / chunk_size)
				var local_x: int = wx % chunk_size
				var local_y: int = wy % chunk_size
				if local_x < 0:
					local_x += chunk_size
				if local_y < 0:
					local_y += chunk_size
				# Cache: generate chunk once, read multiple tiles
				# For iter 1 simplicity: one tile = one sample via channels
				tile_data = _sample_tile_native(generator, chunk_coord, spawn_tile, local_x, local_y, balance.chunk_size_tiles)
			else:
				tile_data = _sample_tile_gdscript(seed_value, wx, wy, balance)

			var terrain_type: int = int(tile_data.get("terrain", 0))
			var biome_idx: int = int(tile_data.get("biome", 0))
			terrain_img.set_pixel(px, py, TERRAIN_COLORS.get(terrain_type, Color(0.2, 0.2, 0.2)))
			biome_img.set_pixel(px, py, _biome_color(biome_idx))

	call_deferred("_on_worker_done", card_index, gen_id, biome_img, terrain_img, seed_value)

func _sample_tile_native(generator: RefCounted, chunk_coord: Vector2i, spawn_tile: Vector2i, local_x: int, local_y: int, chunk_size: int) -> Dictionary:
	# Generate full chunk and extract single tile
	var result: Dictionary = generator.generate_chunk(chunk_coord, spawn_tile)
	if result.is_empty():
		return {"terrain": 0, "biome": 0}
	var terrain_arr: PackedByteArray = result.get("terrain", PackedByteArray())
	var biome_arr: PackedByteArray = result.get("biome", PackedByteArray())
	var idx: int = local_y * chunk_size + local_x
	if idx < 0 or idx >= terrain_arr.size():
		return {"terrain": 0, "biome": 0}
	return {"terrain": terrain_arr[idx], "biome": biome_arr[idx]}

func _sample_tile_gdscript(seed_value: int, wx: int, wy: int, balance: WorldGenBalance) -> Dictionary:
	# GDScript fallback: use WorldGenerator if available
	if WorldGenerator and WorldGenerator.has_method("sample_terrain_type"):
		var terrain: int = WorldGenerator.sample_terrain_type(wx, wy)
		return {"terrain": terrain, "biome": 0}
	return {"terrain": 0, "biome": 0}

# --- Worker result callback (main thread) ---

func _on_worker_done(card_index: int, gen_id: int, biome_img: Image, terrain_img: Image, seed_value: int) -> void:
	if gen_id != _generation_id:
		return
	if card_index < 0 or card_index >= _cards.size():
		return
	var card: Control = _cards[card_index]
	if not is_instance_valid(card):
		return

	var maps_row: HBoxContainer = card.get_node_or_null("VBoxContainer/HBoxContainer")
	if maps_row == null:
		# Find by structure
		var vbox_node: VBoxContainer = card.get_child(0) as VBoxContainer
		if vbox_node and vbox_node.get_child_count() >= 2:
			maps_row = vbox_node.get_child(1) as HBoxContainer

	if maps_row and biome_img and terrain_img:
		var biome_tex := ImageTexture.create_from_image(biome_img)
		var terrain_tex := ImageTexture.create_from_image(terrain_img)
		if maps_row.get_child_count() >= 2:
			(maps_row.get_child(0) as TextureRect).texture = biome_tex
			(maps_row.get_child(1) as TextureRect).texture = terrain_tex

	var status_label: Label = _find_child_by_name(card, "StatusLabel")
	if status_label:
		if biome_img:
			status_label.text = "Seed %d — Done" % seed_value
			status_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.4))
		else:
			status_label.text = "Seed %d — Failed" % seed_value
			status_label.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4))

	_active_tasks -= 1
	if _active_tasks <= 0:
		_generate_button.disabled = false
		_cancel_button.disabled = true
		_status_label.text = "Done (%d seeds)" % (_grid_size * _grid_size)
	else:
		var total: int = _grid_size * _grid_size
		_status_label.text = "Generating %d/%d..." % [total - _active_tasks, total]

# --- Helpers ---

func _find_child_by_name(node: Node, child_name: String) -> Node:
	for child: Node in node.get_children():
		if child.name == child_name:
			return child
		var found: Node = _find_child_by_name(child, child_name)
		if found:
			return found
	return null

func _biome_color(biome_idx: int) -> Color:
	var palette: Array[BiomeData] = BiomeRegistry.get_palette_order()
	if biome_idx >= 0 and biome_idx < palette.size():
		var biome: BiomeData = palette[biome_idx]
		if biome:
			return biome.ground_color
	return Color(0.22, 0.18, 0.12)

func _load_balance() -> WorldGenBalance:
	var res: Resource = load("res://data/world/world_gen_balance.tres")
	return res as WorldGenBalance

func _calc_wrap_width(balance: WorldGenBalance) -> int:
	var tile_width: int = maxi(256, balance.world_wrap_width_tiles)
	var chunk_size: int = maxi(1, balance.chunk_size_tiles)
	var chunk_count: int = maxi(1, int(ceili(float(tile_width) / float(chunk_size))))
	return chunk_count * chunk_size

func _create_native_generator(seed_value: int, balance: WorldGenBalance) -> RefCounted:
	if not balance.use_native_chunk_generation:
		return null
	if not ClassDB.class_exists(&"ChunkGenerator"):
		return null
	var gen: RefCounted = ClassDB.instantiate(&"ChunkGenerator")
	if gen == null:
		return null
	# Build minimal params dict
	var params: Dictionary = _build_generator_params(balance)
	gen.initialize(seed_value, params)
	return gen

func _build_generator_params(balance: WorldGenBalance) -> Dictionary:
	var wrap: int = _calc_wrap_width(balance)
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
	}
	# Biome definitions
	var biome_defs: Array = []
	var palette_order: Array[BiomeData] = BiomeRegistry.get_palette_order()
	for index: int in range(palette_order.size()):
		var biome: BiomeData = palette_order[index]
		if biome == null or str(biome.id).is_empty():
			continue
		biome_defs.append({
			"id": biome.id, "priority": biome.priority, "palette_index": index,
			"min_height": biome.min_height, "max_height": biome.max_height,
			"min_temperature": biome.min_temperature, "max_temperature": biome.max_temperature,
			"min_moisture": biome.min_moisture, "max_moisture": biome.max_moisture,
			"min_ruggedness": biome.min_ruggedness, "max_ruggedness": biome.max_ruggedness,
			"min_flora_density": biome.min_flora_density, "max_flora_density": biome.max_flora_density,
			"min_latitude": biome.min_latitude, "max_latitude": biome.max_latitude,
			"min_ridge_strength": biome.min_ridge_strength, "max_ridge_strength": biome.max_ridge_strength,
			"min_river_strength": biome.min_river_strength, "max_river_strength": biome.max_river_strength,
			"min_floodplain_strength": biome.min_floodplain_strength, "max_floodplain_strength": biome.max_floodplain_strength,
			"height_weight": biome.height_weight, "temperature_weight": biome.temperature_weight,
			"moisture_weight": biome.moisture_weight, "ruggedness_weight": biome.ruggedness_weight,
			"flora_density_weight": biome.flora_density_weight, "latitude_weight": biome.latitude_weight,
			"ridge_strength_weight": biome.ridge_strength_weight, "river_strength_weight": biome.river_strength_weight,
			"floodplain_strength_weight": biome.floodplain_strength_weight,
			"tags": biome.tags.duplicate() if biome.tags else [],
			"flora_set_ids": [], "decor_set_ids": [],
		})
	params["biomes"] = biome_defs
	params["flora_sets"] = []
	params["decor_sets"] = []
	return params
