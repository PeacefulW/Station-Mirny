class_name WorldLab
extends Control

const BALANCE_PATH := "res://data/world/world_gen_balance.tres"
const GLOBAL_PREVIEW_MAX_DIM := 768
const LOCAL_PREVIEW_SIZE := 256
const RIVER_BASIN_MIN_TILES := 50
const NOISE_ISLAND_MAX_TILES := 20

const VIEW_MODE_BIOME := 0
const VIEW_MODE_TERRAIN := 1
const VIEW_MODE_STRUCTURE := 2
const PREVIEW_MODE_GLOBAL := 0
const PREVIEW_MODE_SPAWN_LOCAL := 1

const TERRAIN_COLORS := {
	TileGenData.TerrainType.GROUND: Color(0.35, 0.55, 0.25),
	TileGenData.TerrainType.ROCK: Color(0.55, 0.50, 0.48),
	TileGenData.TerrainType.WATER: Color(0.15, 0.35, 0.70),
	TileGenData.TerrainType.SAND: Color(0.70, 0.60, 0.35),
	TileGenData.TerrainType.GRASS: Color(0.40, 0.58, 0.25),
	TileGenData.TerrainType.MINED_FLOOR: Color(0.50, 0.42, 0.35),
	TileGenData.TerrainType.MOUNTAIN_ENTRANCE: Color(0.55, 0.48, 0.38),
}

var _seed_input: SpinBox
var _preview_mode_button: OptionButton
var _view_mode_button: OptionButton
var _cancel_button: Button
var _status_label: Label
var _map_preview: TextureRect
var _metrics_label: RichTextLabel
var _legend_panel: PanelContainer
var _legend_list: VBoxContainer

var _generation_id := 0
var _pending_generation_id := -1
var _is_generating := false
var _active_tasks: Dictionary = {}
var _worker_mutex: Mutex = Mutex.new()
var _worker_results: Dictionary = {}
var _current_result := {}
var _seed_history: Array[int] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	set_process(true)
	_build_ui()
	_rebuild_biome_legend(BiomeRegistry.get_palette_order())
	_update_side_panels()

func _process(_delta: float) -> void:
	if _active_tasks.is_empty():
		return
	var completed_generations: Array[int] = []
	for generation_variant: Variant in _active_tasks.keys():
		var generation_id: int = int(generation_variant)
		var task_id: int = int(_active_tasks.get(generation_id, -1))
		if task_id >= 0 and WorkerThreadPool.is_task_completed(task_id):
			completed_generations.append(generation_id)
	if completed_generations.is_empty():
		return
	completed_generations.sort()
	for generation_id: int in completed_generations:
		var task_id: int = int(_active_tasks.get(generation_id, -1))
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)
		_active_tasks.erase(generation_id)
		_worker_mutex.lock()
		var payload: Dictionary = (_worker_results.get(generation_id, {}) as Dictionary).duplicate(true)
		_worker_results.erase(generation_id)
		_worker_mutex.unlock()
		if generation_id != _pending_generation_id or generation_id != _generation_id:
			continue
		_pending_generation_id = -1
		_is_generating = false
		_cancel_button.disabled = true
		if payload.is_empty():
			_finish_with_error("Generation returned no preview data.")
			continue
		_on_worker_done(payload)

func _unhandled_input(event: InputEvent) -> void:
	if _is_generating or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_LEFT, KEY_DOWN:
			_browse_seed(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_UP:
			_browse_seed(1)
			get_viewport().set_input_as_handled()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.07)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var top := HBoxContainer.new()
	top.custom_minimum_size.y = 40
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)

	var title := Label.new()
	title.text = "WorldLab"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.78, 0.38))
	top.add_child(title)
	top.add_child(_make_label("Seed:"))

	_seed_input = SpinBox.new()
	_seed_input.min_value = 1
	_seed_input.max_value = 999999
	_seed_input.step = 1
	_seed_input.value = 42
	_seed_input.custom_minimum_size.x = 120
	top.add_child(_seed_input)

	top.add_child(_make_label("Preview:"))
	_preview_mode_button = OptionButton.new()
	_preview_mode_button.add_item("Global")
	_preview_mode_button.add_item("Spawn Local")
	_preview_mode_button.selected = PREVIEW_MODE_GLOBAL
	_preview_mode_button.item_selected.connect(_on_preview_mode_changed)
	top.add_child(_preview_mode_button)

	top.add_child(_make_label("Map:"))
	_view_mode_button = OptionButton.new()
	_view_mode_button.add_item("Biome")
	_view_mode_button.add_item("Terrain")
	_view_mode_button.add_item("Structure")
	_view_mode_button.selected = VIEW_MODE_TERRAIN
	_view_mode_button.item_selected.connect(_on_view_mode_changed)
	top.add_child(_view_mode_button)

	top.add_child(_make_button("Generate", _on_generate_pressed, Vector2(110, 32)))
	_cancel_button = _make_button("Cancel", _on_cancel_pressed, Vector2(90, 32))
	_cancel_button.disabled = true
	top.add_child(_cancel_button)
	top.add_child(_make_button("Copy Seeds", _on_export_pressed, Vector2(110, 32)))
	top.add_child(_make_button("Back", _on_back_pressed, Vector2(80, 32)))

	_status_label = Label.new()
	_status_label.text = "Generate a fullscreen preview. Arrow keys browse seeds."
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.add_theme_color_override("font_color", Color(0.58, 0.64, 0.60))
	top.add_child(_status_label)

	var preview_root := Control.new()
	preview_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(preview_root)

	_map_preview = TextureRect.new()
	_map_preview.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_root.add_child(_map_preview)

	_legend_panel = _make_panel(Vector2i(0, -320), Vector2i(260, 0), false)
	preview_root.add_child(_legend_panel)
	var legend_root := VBoxContainer.new()
	legend_root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	legend_root.offset_left = 10
	legend_root.offset_top = 10
	legend_root.offset_right = -10
	legend_root.offset_bottom = -10
	legend_root.add_theme_constant_override("separation", 6)
	_legend_panel.add_child(legend_root)
	var legend_title := Label.new()
	legend_title.text = "Biome Legend"
	legend_title.add_theme_font_size_override("font_size", 16)
	legend_root.add_child(legend_title)
	var legend_scroll := ScrollContainer.new()
	legend_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	legend_root.add_child(legend_scroll)
	_legend_list = VBoxContainer.new()
	_legend_list.add_theme_constant_override("separation", 4)
	legend_scroll.add_child(_legend_list)

	var metrics_panel := _make_panel(Vector2i(-360, -300), Vector2i(0, 0), true)
	preview_root.add_child(metrics_panel)
	_metrics_label = RichTextLabel.new()
	_metrics_label.fit_content = false
	_metrics_label.scroll_active = true
	_metrics_label.bbcode_enabled = false
	_metrics_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_metrics_label.offset_left = 10
	_metrics_label.offset_top = 10
	_metrics_label.offset_right = -10
	_metrics_label.offset_bottom = -10
	_metrics_label.text = "Metrics will appear here."
	metrics_panel.add_child(_metrics_label)

func _make_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label

func _make_button(text_value: String, callback: Callable, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = min_size
	button.pressed.connect(callback)
	return button

func _make_panel(top_left: Vector2i, bottom_right: Vector2i, from_right: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0 if from_right else 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0 if from_right else 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = top_left.x
	panel.offset_top = top_left.y
	panel.offset_right = bottom_right.x
	panel.offset_bottom = bottom_right.y
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.22, 0.24, 0.28, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _on_generate_pressed() -> void:
	var balance: WorldGenBalance = _load_balance()
	if balance == null:
		_finish_with_error("World balance is missing.")
		return
	var seed: int = clampi(int(_seed_input.value), int(_seed_input.min_value), int(_seed_input.max_value))
	_seed_input.value = seed
	_generation_id += 1
	_pending_generation_id = _generation_id
	_is_generating = true
	_cancel_button.disabled = false
	if _seed_history.is_empty() or _seed_history[_seed_history.size() - 1] != seed:
		_seed_history.append(seed)
	_status_label.text = "Generating seed %d..." % seed
	var task_id: int = WorkerThreadPool.add_task(_worker_generate.bind(seed, _generation_id, balance))
	_active_tasks[_generation_id] = task_id

func _on_cancel_pressed() -> void:
	if not _is_generating and _active_tasks.is_empty():
		return
	_generation_id += 1
	_pending_generation_id = -1
	_is_generating = false
	_cancel_button.disabled = true
	_status_label.text = "Generation cancelled."

func _on_export_pressed() -> void:
	if _seed_history.is_empty():
		_status_label.text = "No generated seeds to copy yet."
		return
	var unique_seeds: Array[String] = []
	var seen: Dictionary = {}
	for seed: int in _seed_history:
		if seen.has(seed):
			continue
		seen[seed] = true
		unique_seeds.append(str(seed))
	DisplayServer.clipboard_set("\n".join(unique_seeds))
	_status_label.text = "Copied %d seed(s) to clipboard." % unique_seeds.size()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_view_mode_changed(_index: int) -> void:
	_update_preview_texture()
	_update_side_panels()

func _on_preview_mode_changed(_index: int) -> void:
	_update_preview_texture()
	_update_side_panels()

func _browse_seed(offset: int) -> void:
	var next_seed: int = clampi(
		int(_seed_input.value) + offset,
		int(_seed_input.min_value),
		int(_seed_input.max_value)
	)
	if next_seed == int(_seed_input.value):
		return
	_seed_input.value = next_seed
	_on_generate_pressed()

func _worker_generate(seed: int, generation_id: int, balance: WorldGenBalance) -> void:
	var payload: Dictionary = _build_preview_set(seed, balance)
	_worker_mutex.lock()
	_worker_results[generation_id] = payload
	_worker_mutex.unlock()

func _build_preview_set(seed: int, balance: WorldGenBalance) -> Dictionary:
	var spawn_tile := Vector2i.ZERO
	var wrap_width: int = _calc_wrap_width(balance)
	var total_height_tiles: int = maxi(1, balance.latitude_half_span_tiles * 2)
	var global_width: int = GLOBAL_PREVIEW_MAX_DIM
	var global_height: int = clampi(
		int(round(float(global_width) * float(total_height_tiles) / float(maxi(wrap_width, 1)))),
		256,
		GLOBAL_PREVIEW_MAX_DIM * 2
	)
	var min_y: int = balance.equator_tile_y - balance.latitude_half_span_tiles
	var max_y: int = balance.equator_tile_y + balance.latitude_half_span_tiles - 1
	var palette_order: Array[BiomeData] = BiomeRegistry.get_palette_order()
	var native_generator: RefCounted = _create_native_generator(seed, balance)
	var compute_context: WorldComputeContext = null
	var backend: String = "native"
	if native_generator == null:
		compute_context = _create_compute_context(seed, balance, spawn_tile)
		backend = "gdscript"

	var global_biome_image: Image = Image.create(global_width, global_height, false, Image.FORMAT_RGBA8)
	var global_terrain_image: Image = Image.create(global_width, global_height, false, Image.FORMAT_RGBA8)
	var global_structure_image: Image = Image.create(global_width, global_height, false, Image.FORMAT_RGBA8)
	var terrain_grid: Array[int] = []
	var biome_grid: Array[StringName] = []
	terrain_grid.resize(global_width * global_height)
	biome_grid.resize(global_width * global_height)

	for pixel_y: int in range(global_height):
		var world_y: int = _sample_tile_y(pixel_y, global_height, min_y, max_y)
		for pixel_x: int in range(global_width):
			var world_x: int = _sample_tile_x(pixel_x, global_width, wrap_width)
			var sample: Dictionary = _sample_preview_tile(
				Vector2i(world_x, world_y),
				spawn_tile,
				native_generator,
				compute_context,
				palette_order
			)
			var index: int = pixel_y * global_width + pixel_x
			var terrain_type: int = int(sample.get("terrain", TileGenData.TerrainType.GROUND))
			var biome_id: StringName = StringName(sample.get("biome_id", &""))
			terrain_grid[index] = terrain_type
			biome_grid[index] = biome_id
			global_biome_image.set_pixel(pixel_x, pixel_y, _resolve_biome_color(biome_id))
			global_terrain_image.set_pixel(pixel_x, pixel_y, _resolve_terrain_color(terrain_type, biome_id))
			global_structure_image.set_pixel(pixel_x, pixel_y, _structure_color(sample))

	var local_biome_image: Image = Image.create(LOCAL_PREVIEW_SIZE, LOCAL_PREVIEW_SIZE, false, Image.FORMAT_RGBA8)
	var local_terrain_image: Image = Image.create(LOCAL_PREVIEW_SIZE, LOCAL_PREVIEW_SIZE, false, Image.FORMAT_RGBA8)
	var local_structure_image: Image = Image.create(LOCAL_PREVIEW_SIZE, LOCAL_PREVIEW_SIZE, false, Image.FORMAT_RGBA8)
	var local_radius: int = LOCAL_PREVIEW_SIZE / 2
	for pixel_y: int in range(LOCAL_PREVIEW_SIZE):
		var world_y: int = spawn_tile.y + pixel_y - local_radius
		for pixel_x: int in range(LOCAL_PREVIEW_SIZE):
			var world_x: int = _wrap_world_x(spawn_tile.x + pixel_x - local_radius, wrap_width)
			var sample: Dictionary = _sample_preview_tile(
				Vector2i(world_x, world_y),
				spawn_tile,
				native_generator,
				compute_context,
				palette_order
			)
			var terrain_type: int = int(sample.get("terrain", TileGenData.TerrainType.GROUND))
			var biome_id: StringName = StringName(sample.get("biome_id", &""))
			local_biome_image.set_pixel(pixel_x, pixel_y, _resolve_biome_color(biome_id))
			local_terrain_image.set_pixel(pixel_x, pixel_y, _resolve_terrain_color(terrain_type, biome_id))
			local_structure_image.set_pixel(pixel_x, pixel_y, _structure_color(sample))

	var global_spawn_pixel := Vector2i(
		_sample_pixel_x(spawn_tile.x, global_width, wrap_width),
		_sample_pixel_y(spawn_tile.y, global_height, min_y, max_y)
	)
	_draw_spawn_marker(global_biome_image, global_spawn_pixel)
	_draw_spawn_marker(global_terrain_image, global_spawn_pixel)
	_draw_spawn_marker(global_structure_image, global_spawn_pixel)
	var local_spawn_pixel := Vector2i(local_radius, local_radius)
	var safe_zone_radius: int = maxi(0, balance.safe_zone_radius)
	var land_guarantee_radius: int = maxi(0, balance.land_guarantee_radius)
	_draw_spawn_marker(local_biome_image, local_spawn_pixel, safe_zone_radius, land_guarantee_radius)
	_draw_spawn_marker(local_terrain_image, local_spawn_pixel, safe_zone_radius, land_guarantee_radius)
	_draw_spawn_marker(local_structure_image, local_spawn_pixel, safe_zone_radius, land_guarantee_radius)

	var metrics: Dictionary = _compute_metrics(terrain_grid, biome_grid, global_width, global_height, -1)
	return {
		"seed": seed,
		"backend": backend,
		"spawn_tile": spawn_tile,
		"safe_zone_radius": safe_zone_radius,
		"land_guarantee_radius": land_guarantee_radius,
		"global_biome_image": global_biome_image,
		"global_terrain_image": global_terrain_image,
		"global_structure_image": global_structure_image,
		"local_biome_image": local_biome_image,
		"local_terrain_image": local_terrain_image,
		"local_structure_image": local_structure_image,
		"metrics": metrics,
	}

func _create_compute_context(seed: int, balance: WorldGenBalance, spawn_tile: Vector2i) -> WorldComputeContext:
	var planet_sampler := PlanetSampler.new()
	planet_sampler.initialize(seed, balance)
	var structure_sampler := LargeStructureSampler.new()
	structure_sampler.initialize(seed, balance)
	var biome_resolver := BiomeResolver.new()
	biome_resolver.configure(BiomeRegistry.get_all_biomes())
	var local_variation_resolver := LocalVariationResolver.new()
	local_variation_resolver.initialize(seed, balance)
	var palette_order: Array[BiomeData] = BiomeRegistry.get_palette_order()
	var biome_by_id: Dictionary = {}
	var palette_index_by_id: Dictionary = {}
	for index: int in range(palette_order.size()):
		var biome: BiomeData = palette_order[index]
		if biome == null or str(biome.id).is_empty():
			continue
		biome_by_id[biome.id] = biome
		palette_index_by_id[biome.id] = index
	var default_biome: BiomeData = BiomeRegistry.get_default_biome()
	var context := WorldComputeContext.new().configure(
		balance,
		seed,
		spawn_tile,
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
	var surface_terrain_resolver := SurfaceTerrainResolver.new().initialize(balance, context)
	context.set_surface_terrain_resolver(surface_terrain_resolver)
	return context

func _sample_preview_tile(
	world_pos: Vector2i,
	spawn_tile: Vector2i,
	native_generator: RefCounted,
	compute_context: WorldComputeContext,
	palette_order: Array[BiomeData]
) -> Dictionary:
	if native_generator != null:
		var native_sample: Dictionary = native_generator.sample_tile(world_pos, spawn_tile)
		var biome_id: StringName = &""
		var biome_index: int = int(native_sample.get("biome", 0))
		if biome_index >= 0 and biome_index < palette_order.size():
			var biome: BiomeData = palette_order[biome_index]
			if biome:
				biome_id = biome.id
		return {
			"terrain": int(native_sample.get("terrain", TileGenData.TerrainType.GROUND)),
			"biome_id": biome_id,
			"ridge_strength": float(native_sample.get("ridge_strength", 0.0)),
			"river_strength": float(native_sample.get("river_strength", 0.0)),
			"floodplain_strength": float(native_sample.get("floodplain_strength", 0.0)),
		}
	var canonical_tile: Vector2i = compute_context.canonicalize_tile(world_pos)
	var channels: WorldChannels = compute_context.sample_world_channels(canonical_tile)
	var structure_context: WorldStructureContext = compute_context.sample_structure_context(canonical_tile, channels)
	var biome_result: BiomeResult = compute_context.get_biome_result_at_tile(canonical_tile, channels, structure_context)
	var local_variation: LocalVariationContext = compute_context.sample_local_variation(
		canonical_tile,
		biome_result,
		channels,
		structure_context
	)
	return {
		"terrain": int(compute_context.get_surface_terrain_type_from_context(
			canonical_tile,
			channels,
			structure_context,
			local_variation
		)),
		"biome_id": biome_result.biome_id if biome_result != null else &"",
		"ridge_strength": structure_context.ridge_strength if structure_context != null else 0.0,
		"river_strength": structure_context.river_strength if structure_context != null else 0.0,
		"floodplain_strength": structure_context.floodplain_strength if structure_context != null else 0.0,
	}

func _on_worker_done(payload: Dictionary) -> void:
	if payload.has("error"):
		_finish_with_error(str(payload.get("error", "Unknown generation error.")))
		return
	_current_result = payload.duplicate(true)
	var metrics: Dictionary = _current_result.get("metrics", {}) as Dictionary
	var spawn_tile: Vector2i = _current_result.get("spawn_tile", Vector2i.ZERO)
	_current_result["metrics_text"] = _format_metrics(
		int(_current_result.get("seed", 0)),
		str(_current_result.get("backend", "unknown")),
		spawn_tile,
		int(_current_result.get("safe_zone_radius", 0)),
		int(_current_result.get("land_guarantee_radius", 0)),
		metrics
	)
	_update_preview_texture()
	_update_side_panels()

func _update_preview_texture() -> void:
	if _map_preview == null:
		return
	if _current_result.is_empty():
		_map_preview.texture = null
		return
	var preview_prefix: String = "global" if _preview_mode_button.selected == PREVIEW_MODE_GLOBAL else "local"
	var suffix: String = "terrain"
	match _view_mode_button.selected:
		VIEW_MODE_BIOME:
			suffix = "biome"
		VIEW_MODE_TERRAIN:
			suffix = "terrain"
		VIEW_MODE_STRUCTURE:
			suffix = "structure"
	var image_key: String = "%s_%s_image" % [preview_prefix, suffix]
	var image: Image = _current_result.get(image_key, null) as Image
	if image == null:
		_map_preview.texture = null
		return
	_map_preview.texture = ImageTexture.create_from_image(image)
	var seed: int = int(_current_result.get("seed", 0))
	var backend: String = str(_current_result.get("backend", "unknown"))
	var preview_label: String = _preview_mode_button.get_item_text(_preview_mode_button.selected)
	var map_label: String = _view_mode_button.get_item_text(_view_mode_button.selected)
	_status_label.text = "Seed %d ready. %s / %s (%s)." % [seed, preview_label, map_label, backend]

func _update_side_panels() -> void:
	if _legend_panel != null:
		_legend_panel.visible = _view_mode_button.selected == VIEW_MODE_BIOME
	if _current_result.is_empty():
		_set_metrics_text("Metrics will appear here.")
		return
	_set_metrics_text(str(_current_result.get("metrics_text", "")))

func _rebuild_biome_legend(biomes: Array[BiomeData]) -> void:
	if _legend_list == null:
		return
	for child: Node in _legend_list.get_children():
		child.queue_free()
	for biome: BiomeData in biomes:
		if biome == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.color = biome.ground_color.lightened(0.08)
		row.add_child(swatch)
		var label := Label.new()
		label.text = biome.get_display_name()
		row.add_child(label)
		_legend_list.add_child(row)

func _compute_metrics(
	terrain_grid: Array[int],
	biome_grid: Array[StringName],
	width: int,
	height: int,
	landmark_zones: int
) -> Dictionary:
	var river_stats: Dictionary = _compute_component_stats(
		terrain_grid,
		width,
		height,
		TileGenData.TerrainType.WATER,
		RIVER_BASIN_MIN_TILES
	)
	var mountain_stats: Dictionary = _compute_component_stats(
		terrain_grid,
		width,
		height,
		TileGenData.TerrainType.ROCK
	)
	return {
		"longest_river": int(river_stats.get("largest", 0)),
		"large_river_basins": int(river_stats.get("large_count", 0)),
		"largest_mountain_chain": int(mountain_stats.get("largest", 0)),
		"top_biomes": _compute_top_biome_coverage(biome_grid),
		"small_biome_islands": _count_small_biome_islands(biome_grid, width, height),
		"transition_smoothness": _compute_transition_smoothness(biome_grid, width, height),
		"landmark_zones": landmark_zones,
	}

func _compute_component_stats(
	values: Array[int],
	width: int,
	height: int,
	target_value: int,
	large_threshold: int = -1
) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(values.size())
	var largest := 0
	var large_count := 0
	for index: int in range(values.size()):
		if visited[index] != 0 or values[index] != target_value:
			continue
		var component_size: int = _flood_fill_same_value(values, width, height, index, visited)
		largest = maxi(largest, component_size)
		if large_threshold > 0 and component_size >= large_threshold:
			large_count += 1
	return {
		"largest": largest,
		"large_count": large_count,
	}

func _compute_top_biome_coverage(biome_grid: Array[StringName]) -> Array[Dictionary]:
	var counts: Dictionary = {}
	for biome_id: StringName in biome_grid:
		counts[biome_id] = int(counts.get(biome_id, 0)) + 1
	var entries: Array[Dictionary] = []
	var total_tiles: float = maxf(1.0, float(biome_grid.size()))
	for biome_id_variant: Variant in counts.keys():
		var biome_id: StringName = biome_id_variant as StringName
		var count: int = int(counts.get(biome_id, 0))
		entries.append({
			"biome_id": biome_id,
			"coverage": (float(count) / total_tiles) * 100.0,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("coverage", 0.0)) > float(b.get("coverage", 0.0))
	)
	if entries.size() > 3:
		entries.resize(3)
	return entries

func _count_small_biome_islands(biome_grid: Array[StringName], width: int, height: int) -> int:
	var visited := PackedByteArray()
	visited.resize(biome_grid.size())
	var islands := 0
	for index: int in range(biome_grid.size()):
		if visited[index] != 0:
			continue
		var component_size: int = _flood_fill_same_value(biome_grid, width, height, index, visited)
		if component_size < NOISE_ISLAND_MAX_TILES:
			islands += 1
	return islands

func _compute_transition_smoothness(biome_grid: Array[StringName], width: int, height: int) -> float:
	var total_pairs := 0
	var matching_pairs := 0
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			var biome_id: StringName = biome_grid[index]
			if x + 1 < width:
				total_pairs += 1
				if biome_grid[index + 1] == biome_id:
					matching_pairs += 1
			if y + 1 < height:
				total_pairs += 1
				if biome_grid[index + width] == biome_id:
					matching_pairs += 1
	return 1.0 if total_pairs <= 0 else float(matching_pairs) / float(total_pairs)

func _flood_fill_same_value(values: Array, width: int, height: int, start_index: int, visited: PackedByteArray) -> int:
	var target: Variant = values[start_index]
	var queue: Array[int] = [start_index]
	var head := 0
	var size := 0
	visited[start_index] = 1
	while head < queue.size():
		var index: int = queue[head]
		head += 1
		size += 1
		var x: int = index % width
		var y: int = index / width
		if x > 0:
			var left: int = index - 1
			if visited[left] == 0 and values[left] == target:
				visited[left] = 1
				queue.append(left)
		if x + 1 < width:
			var right: int = index + 1
			if visited[right] == 0 and values[right] == target:
				visited[right] = 1
				queue.append(right)
		if y > 0:
			var up: int = index - width
			if visited[up] == 0 and values[up] == target:
				visited[up] = 1
				queue.append(up)
		if y + 1 < height:
			var down: int = index + width
			if visited[down] == 0 and values[down] == target:
				visited[down] = 1
				queue.append(down)
	return size

func _format_metrics(
	seed: int,
	backend: String,
	spawn_tile: Vector2i,
	safe_zone_radius: int,
	land_guarantee_radius: int,
	metrics: Dictionary
) -> String:
	var lines: Array[String] = []
	lines.append("Seed: %d" % seed)
	lines.append("Backend: %s" % backend)
	lines.append("Spawn: (%d, %d)" % [spawn_tile.x, spawn_tile.y])
	lines.append("Safe zone / land guarantee: %d / %d" % [safe_zone_radius, land_guarantee_radius])
	lines.append("")
	lines.append("Longest river: %d" % int(metrics.get("longest_river", 0)))
	lines.append("Large river basins: %d" % int(metrics.get("large_river_basins", 0)))
	lines.append("Largest mountain chain: %d" % int(metrics.get("largest_mountain_chain", 0)))
	var top_biomes: Array = metrics.get("top_biomes", []) as Array
	if top_biomes.is_empty():
		lines.append("Top biomes: n/a")
	else:
		lines.append("Top biomes:")
		for entry_variant: Variant in top_biomes:
			var entry: Dictionary = entry_variant as Dictionary
			var biome_id: StringName = StringName(entry.get("biome_id", &""))
			lines.append("  %s: %.1f%%" % [
				_resolve_biome_name(biome_id),
				float(entry.get("coverage", 0.0))
			])
	lines.append("Small biome islands: %d" % int(metrics.get("small_biome_islands", 0)))
	lines.append("Transition smoothness: %.3f" % float(metrics.get("transition_smoothness", 0.0)))
	var landmark_zones: int = int(metrics.get("landmark_zones", -1))
	lines.append("Landmark zones: %s" % ("N/A" if landmark_zones < 0 else str(landmark_zones)))
	lines.append("")
	lines.append("Arrow keys browse seeds. Copy Seeds exports visited seeds.")
	return "\n".join(lines)

func _set_metrics_text(text_value: String) -> void:
	if _metrics_label == null:
		return
	_metrics_label.text = text_value

func _finish_with_error(message: String) -> void:
	_is_generating = false
	_pending_generation_id = -1
	if _cancel_button != null:
		_cancel_button.disabled = true
	if _status_label != null:
		_status_label.text = message

func _resolve_biome_color(biome_id: StringName) -> Color:
	var biome: BiomeData = BiomeRegistry.get_biome_by_short_id(biome_id)
	if biome == null:
		return Color(0.2, 0.2, 0.2)
	return biome.ground_color.lightened(0.08)

func _resolve_terrain_color(terrain_type: int, biome_id: StringName) -> Color:
	var biome: BiomeData = BiomeRegistry.get_biome_by_short_id(biome_id)
	match terrain_type:
		TileGenData.TerrainType.GROUND:
			return biome.ground_color.lightened(0.04) if biome else TERRAIN_COLORS[TileGenData.TerrainType.GROUND]
		TileGenData.TerrainType.GRASS:
			return biome.grass_color.lightened(0.04) if biome else TERRAIN_COLORS[TileGenData.TerrainType.GRASS]
		_:
			return TERRAIN_COLORS.get(terrain_type, Color(0.25, 0.25, 0.25))

func _resolve_biome_name(biome_id: StringName) -> String:
	var biome: BiomeData = BiomeRegistry.get_biome_by_short_id(biome_id)
	if biome:
		return biome.get_display_name()
	return _format_biome_id(biome_id)

func _structure_color(sample: Dictionary) -> Color:
	return Color(
		clampf(float(sample.get("ridge_strength", 0.0)) * 0.90, 0.0, 1.0),
		clampf(float(sample.get("floodplain_strength", 0.0)) * 0.70, 0.0, 1.0),
		clampf(float(sample.get("river_strength", 0.0)) * 0.95, 0.0, 1.0),
		1.0
	)

func _draw_spawn_marker(image: Image, center: Vector2i, safe_zone_radius: int = -1, land_guarantee_radius: int = -1) -> void:
	if image == null:
		return
	if land_guarantee_radius >= 0:
		_draw_ring(image, center, land_guarantee_radius, Color(1.0, 0.86, 0.18, 1.0))
	if safe_zone_radius >= 0:
		_draw_ring(image, center, safe_zone_radius, Color(0.28, 0.95, 1.0, 1.0))
	for offset: int in range(-4, 5):
		_plot_marker_pixel(image, Vector2i(center.x + offset, center.y), Color(0.05, 0.05, 0.05, 1.0))
		_plot_marker_pixel(image, Vector2i(center.x, center.y + offset), Color(0.05, 0.05, 0.05, 1.0))
	for offset: int in range(-2, 3):
		_plot_marker_pixel(image, Vector2i(center.x + offset, center.y), Color(1.0, 0.24, 0.24, 1.0))
		_plot_marker_pixel(image, Vector2i(center.x, center.y + offset), Color(1.0, 0.24, 0.24, 1.0))
	_plot_marker_pixel(image, center, Color.WHITE)

func _draw_ring(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	if radius <= 0:
		return
	var min_x: int = maxi(0, center.x - radius - 1)
	var max_x: int = mini(image.get_width() - 1, center.x + radius + 1)
	var min_y: int = maxi(0, center.y - radius - 1)
	var max_y: int = mini(image.get_height() - 1, center.y + radius + 1)
	var radius_f: float = float(radius)
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var dist: float = Vector2(float(x - center.x), float(y - center.y)).length()
			if absf(dist - radius_f) <= 0.6:
				_plot_marker_pixel(image, Vector2i(x, y), color)

func _plot_marker_pixel(image: Image, pixel: Vector2i, color: Color) -> void:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height():
		return
	image.set_pixel(pixel.x, pixel.y, color)

func _format_biome_id(biome_id: StringName) -> String:
	var id_text: String = str(biome_id)
	if id_text.is_empty():
		return "Unknown"
	if id_text.contains(":"):
		var parts: PackedStringArray = id_text.split(":")
		return parts[parts.size() - 1].capitalize()
	return id_text.capitalize()

func _load_balance() -> WorldGenBalance:
	return load(BALANCE_PATH) as WorldGenBalance

func _calc_wrap_width(balance: WorldGenBalance) -> int:
	if balance == null:
		return 1
	return maxi(1, balance.world_wrap_width_tiles)

func _wrap_world_x(tile_x: int, wrap_width: int) -> int:
	if wrap_width <= 0:
		return tile_x
	return int(posmod(tile_x, wrap_width))

func _sample_tile_x(pixel_x: int, width: int, wrap_width: int) -> int:
	if width <= 1:
		return 0
	return int(round(float(pixel_x) * float(maxi(0, wrap_width - 1)) / float(width - 1)))

func _sample_tile_y(pixel_y: int, height: int, min_y: int, max_y: int) -> int:
	if height <= 1:
		return min_y
	return min_y + int(round(float(pixel_y) * float(max_y - min_y) / float(height - 1)))

func _sample_pixel_x(tile_x: int, width: int, wrap_width: int) -> int:
	if wrap_width <= 1:
		return 0
	return clampi(
		int(round(float(_wrap_world_x(tile_x, wrap_width)) * float(width - 1) / float(wrap_width - 1))),
		0,
		width - 1
	)

func _sample_pixel_y(tile_y: int, height: int, min_y: int, max_y: int) -> int:
	if max_y <= min_y:
		return 0
	return clampi(
		int(round(float(tile_y - min_y) * float(height - 1) / float(max_y - min_y))),
		0,
		height - 1
	)

func _create_native_generator(seed: int, balance: WorldGenBalance) -> RefCounted:
	if balance == null or not balance.use_native_chunk_generation:
		return null
	if not ClassDB.class_exists(&"ChunkGenerator"):
		return null
	var generator: RefCounted = ClassDB.instantiate(&"ChunkGenerator")
	if generator == null:
		return null
	generator.initialize(seed, _build_generator_params(balance))
	return generator

func _build_generator_params(balance: WorldGenBalance) -> Dictionary:
	var params: Dictionary = {
		"chunk_size": balance.chunk_size_tiles,
		"wrap_width": _calc_wrap_width(balance),
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
		"ridge_secondary_weight": balance.ridge_secondary_weight,
		"ridge_secondary_warp_amplitude_tiles": balance.ridge_secondary_warp_amplitude_tiles,
		"ridge_secondary_spacing_tiles": balance.ridge_secondary_spacing_tiles,
		"ridge_secondary_core_width_tiles": balance.ridge_secondary_core_width_tiles,
		"ridge_secondary_feather_tiles": balance.ridge_secondary_feather_tiles,
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
			"tags": biome.tags.duplicate(),
		})
	params["biomes"] = biome_defs
	return params
