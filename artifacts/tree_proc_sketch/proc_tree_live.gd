extends SceneTree

# ЖИВОЙ рантайм: процедурные деревья на равнине с ветром, сцена НЕ закрывается.
# Те же фиксы, что в field-пробе: bbox-холст (без обрезки), корни в землю, тени
# по солнцу, мягкие листья. Ходи WASD; закрой окно, чтобы выйти. Запуск (в фоне):
#   Godot_v4.7-stable_win64_console.exe --path . -s artifacts/tree_proc_sketch/proc_tree_live.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const ProcTreeSingle = preload("res://artifacts/tree_proc_sketch/proc_tree_single.gd")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const TREE_WIND_SHADER: String = "res://artifacts/tree_proc_sketch/tree_wind.gdshader"
const HOUR: float = 9.0
const HOURS_PER_DAY: float = 24.0
const VARIANT_COUNT: int = 14
const BAKE_MARGIN: int = 14
const TREE_WORLD_HEIGHT_PX: float = 205.0
const HEIGHT_JITTER: Vector2 = Vector2(0.80, 1.18)
const TREE_DENSITY_PER_TILE: float = 0.06
const MAX_TREES: int = 12000
const GROUND_SINK_PX: float = 4.0
const SHADOW_Z: int = 235
const TREE_Z: int = 250
const SHADOW_COLOR: Color = Color(0.10, 0.06, 0.03, 0.30)
const CONTACT_COLOR: Color = Color(0.05, 0.03, 0.02, 0.30)
const CANOPY_TINTS: Array[Color] = [
	Color(1.0, 1.0, 0.95), Color(1.04, 1.02, 0.82), Color(1.06, 0.94, 0.78),
	Color(1.02, 0.98, 0.90), Color(1.07, 0.88, 0.70),
]
const WIND_STRENGTH: float = 0.55
const WIND_DIR_DEG: float = 30.0
const MAX_SETTLE_FRAMES: int = 600

var _streamer: Node = null
var _tex: Array[Texture2D] = []
var _tex_size: Array[Vector2] = []
var _tex_anchor: Array[Vector2] = []
var _shadow_root: Node2D = null
var _tree_root: Node2D = null
var _wind_material: ShaderMaterial = null
var _shadow_dir: Vector2 = Vector2(0.7, 0.7)
var _shadow_foreshorten: float = 0.5
var _bake_light_dir: Vector2 = Vector2(-0.7, -0.72)
var _anchor_stripe: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("proc_tree_live: must run windowed")
		quit(1)
		return
	var sun_angle: float = _sun_angle_for_hour(HOUR)
	var light: Vector2 = Vector2(cos(sun_angle), sin(sun_angle))
	_shadow_dir = (-light).normalized()
	_shadow_foreshorten = clampf(0.5 * _shadow_len_for_hour(HOUR), 0.4, 1.3)
	_bake_light_dir = Vector2(clampf(light.x, -0.85, 0.85), -0.72).normalized()

	_wind_material = ShaderMaterial.new()
	_wind_material.shader = load(TREE_WIND_SHADER) as Shader
	await _bake_textures()
	if _tex.is_empty():
		push_error("proc_tree_live: no tree textures baked")
		quit(1)
		return

	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node("WorldStreamer")
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var camera: Camera2D = scene.get_node("Player/Camera2D") as Camera2D
	var wind: Node = root.get_node_or_null("WindRuntime")
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	_streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		MountainGenSettings.hard_coded_defaults(),
		bounds,
		FoundationGenSettings.for_bounds(bounds),
		LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict()),
	)
	if time_manager != null:
		time_manager.call("restore_persisted_state", HOUR, 1, 0)
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(0.9, 0.9)
	camera.set("_target_zoom", 0.9)

	await _settle()

	# Деревья — фиксированный слой НАД травой (не зависит от игрока). «Трава у
	# комля» запечена в текстуру.
	_shadow_root = Node2D.new()
	_shadow_root.name = "ProcTreeShadows"
	_shadow_root.z_index = 0
	scene.add_child(_shadow_root)
	_tree_root = Node2D.new()
	_tree_root.name = "ProcTreeField"
	_tree_root.y_sort_enabled = true
	_tree_root.z_index = TREE_Z
	scene.add_child(_tree_root)

	var planted: int = _plant_trees()
	if wind != null:
		wind.call("set_debug_direction_override_deg", WIND_DIR_DEG)
		wind.call("set_debug_strength_override", WIND_STRENGTH)
	_streamer._sync_sun_lighting_from_time(true)

	print("proc_tree_live: LIVE — %d деревьев, ветер вкл. Ходи WASD; закрой окно для выхода." % planted)
	# НЕ quit() — сцена живёт.


func _bake_textures() -> void:
	for i: int in range(VARIANT_COUNT):
		var tree: Node2D = ProcTreeSingle.new()
		tree.set("p_seed", 4000 + i * 7)
		tree.set("p_palette", "autumn")
		tree.set("p_canopy_tint", CANOPY_TINTS[i % CANOPY_TINTS.size()])
		tree.set("p_light_dir", _bake_light_dir)
		tree.set("p_gnarl", 0.32 + float(i % 5) * 0.13)
		tree.set("p_trunk_len", 62.0 + float(i % 3) * 16.0)
		tree.set("p_trunk_w", 19.0 + float(i % 3) * 3.0)
		tree.set("p_canopy_count", 58 + (i % 4) * 16)
		tree.set("p_canopy_radius", 38.0 + float(i % 3) * 5.0)
		tree.set("p_leaf_size", 4.5)
		tree.set("p_leaf_alpha", 0.80)
		tree.set("p_lean", float((i % 7) - 3) * 0.045)
		tree.set("base_pos", Vector2.ZERO)
		tree.call("build")
		var b: Rect2 = tree.call("get_content_bounds")
		var canvas := Vector2i(int(ceil(b.size.x)) + BAKE_MARGIN * 2, int(ceil(b.size.y)) + BAKE_MARGIN * 2)
		tree.position = -b.position + Vector2(float(BAKE_MARGIN), float(BAKE_MARGIN))
		var vp := SubViewport.new()
		vp.size = canvas
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.add_child(tree)
		root.add_child(vp)
		for _f: int in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		var used: Rect2i = img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			vp.queue_free()
			continue
		var cropped: Image = img.get_region(used)
		_tex.append(ImageTexture.create_from_image(cropped))
		_tex_size.append(Vector2(used.size))
		_tex_anchor.append(tree.position - Vector2(used.position))
		vp.queue_free()
		await process_frame


func _plant_trees() -> int:
	var planted: int = 0
	for chunk_coord_variant: Variant in _streamer._chunk_packets.keys():
		if planted >= MAX_TREES:
			break
		var chunk_coord: Vector2i = chunk_coord_variant as Vector2i
		var packet: Dictionary = _streamer._chunk_packets[chunk_coord] as Dictionary
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		if terrain_ids.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
			continue
		var origin: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
		for local_y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			for local_x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
				if planted >= MAX_TREES:
					break
				var index: int = local_y * WorldRuntimeConstants.CHUNK_SIZE + local_x
				if int(terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
					continue
				var h: int = _hash3(chunk_coord.x, chunk_coord.y, index)
				if _unit(h) > TREE_DENSITY_PER_TILE:
					continue
				var jitter_x: float = (_unit(h >> 7) - 0.5) * float(WorldRuntimeConstants.TILE_SIZE_PX)
				var jitter_y: float = (_unit(h >> 13) - 0.5) * float(WorldRuntimeConstants.TILE_SIZE_PX)
				var world_pos: Vector2 = origin + Vector2(
					(float(local_x) + 0.5) * WorldRuntimeConstants.TILE_SIZE_PX + jitter_x,
					(float(local_y) + 0.5) * WorldRuntimeConstants.TILE_SIZE_PX + jitter_y,
				)
				var variant: int = (h >> 17) % _tex.size()
				var bucket: float = _unit(h >> 25)
				var height_scale: float
				if bucket < 0.10:
					height_scale = lerpf(1.35, 1.72, _unit(h >> 21))
				elif bucket < 0.30:
					height_scale = lerpf(0.58, 0.80, _unit(h >> 21))
				else:
					height_scale = lerpf(HEIGHT_JITTER.x, HEIGHT_JITTER.y, _unit(h >> 21))
				_spawn_tree(world_pos, variant, height_scale)
				planted += 1
	return planted


func _spawn_tree(world_pos: Vector2, variant: int, height_scale: float) -> void:
	var size: Vector2 = _tex_size[variant]
	var anchor: Vector2 = _tex_anchor[variant]
	var s: float = (TREE_WORLD_HEIGHT_PX * height_scale) / size.y
	var ground: Vector2 = world_pos + Vector2(0.0, GROUND_SINK_PX)

	var contact := Polygon2D.new()
	contact.polygon = _contact_ellipse(size.x * s * 0.16)
	contact.color = CONTACT_COLOR
	contact.position = ground + Vector2(0.0, 1.0)
	contact.z_index = WorldRuntimeConstants.Z_GRASS_SHADOW - 3
	_shadow_root.add_child(contact)

	var shadow := Sprite2D.new()
	shadow.texture = _tex[variant]
	shadow.centered = false
	shadow.offset = -anchor
	shadow.modulate = SHADOW_COLOR
	var x_axis := Vector2(0.98, 0.0) * s
	var y_axis := -_shadow_dir * _shadow_foreshorten * s
	shadow.transform = Transform2D(x_axis, y_axis, ground)
	shadow.material = _wind_material
	shadow.z_index = WorldRuntimeConstants.Z_GRASS_SHADOW - 2
	_shadow_root.add_child(shadow)

	var sprite := Sprite2D.new()
	sprite.texture = _tex[variant]
	sprite.centered = false
	sprite.offset = -anchor
	sprite.scale = Vector2(s, s)
	sprite.position = ground
	sprite.material = _wind_material
	_tree_root.add_child(sprite)


func _contact_ellipse(rx: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(18):
		var a: float = TAU * float(i) / 18.0
		pts.append(Vector2(cos(a) * rx, sin(a) * rx * 0.42))
	return pts


func _sun_angle_for_hour(hour: float) -> float:
	var progress: float = fmod(hour / HOURS_PER_DAY + 0.5, 1.0)
	var shadow_angle: float = fmod(progress - 0.75 + 1.0, 1.0) * TAU
	return shadow_angle - PI


func _shadow_len_for_hour(hour: float) -> float:
	var progress: float = fmod(hour / HOURS_PER_DAY + 0.5, 1.0)
	var elevation: float = maxf(cos(progress * TAU), 0.0)
	if elevation < 0.05:
		return 6.0
	return clampf(1.0 / (elevation * 2.0), 1.0, 6.0)


func _settle() -> void:
	for _tick: int in range(MAX_SETTLE_FRAMES):
		_streamer._streaming_tick()
		if _streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			_streamer._mountain_native_mask_visual_apply_tick()
		await process_frame
		if _streamer._requested_chunks.is_empty() and not _streamer._has_pending_streaming_work():
			return


func _hash3(a: int, b: int, c: int) -> int:
	var h: int = a * 73856093
	h ^= b * 19349663
	h ^= c * 83492791
	h = (h ^ (h >> 13)) * 1274126177
	h ^= h >> 16
	return h & 0x7fffffff


func _unit(value: int) -> float:
	return float((value & 0x7fffffff) % 1000003) / 1000003.0
