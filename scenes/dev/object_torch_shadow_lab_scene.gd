class_name ObjectTorchShadowLabScene
extends Node2D

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const DaylightSystemScript = preload("res://core/systems/daylight/daylight_system.gd")
const MountainTorchShadowFieldScript = preload("res://core/systems/world/mountain_torch_shadow_field.gd")

const TOP_TEXTURE: Texture2D = preload("res://assets/textures/world/biomes/plains/mountain/rock_top_albedo.png")
const FACE_TEXTURE: Texture2D = preload("res://assets/textures/world/biomes/plains/mountain/rock_face_albedo.png")
const PLAINS_ROCK_ATLAS_1: Texture2D = preload("res://assets/sprites/resources/atlases/plains_rock_1_atlas.png")
const PLAINS_ROCK_ATLAS_2: Texture2D = preload("res://assets/sprites/resources/atlases/plains_rock_2_atlas.png")
const PLAINS_VOLCANIC_ROCK_ATLAS: Texture2D = preload("res://assets/sprites/resources/atlases/plains_volcanic_rock_atlas.png")
const PLAINS_RARE_ROCK_ATLAS: Texture2D = preload("res://assets/sprites/resources/atlases/plains_rare_rock_formation_atlas.png")
const PLAINS_TREE_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/plains_trees_atlas.png")
const BIG_ROCK_1: Texture2D = preload("res://assets/sprites/resources/plains/big_rocks/plains_grass_big_rock_01.png")
const BIG_ROCK_2: Texture2D = preload("res://assets/sprites/resources/plains/big_rocks/plains_grass_big_rock_02.png")
const BIG_ROCK_3: Texture2D = preload("res://assets/sprites/resources/plains/big_rocks/plains_grass_big_rock_03.png")
const BIG_ROCK_4: Texture2D = preload("res://assets/sprites/resources/plains/big_rocks/plains_grass_big_rock_04.png")

const MASK_WIDTH: int = 512
const MASK_HEIGHT: int = 512
const MASK_STEP_PX: float = 2.0
const PLAYER_START: Vector2 = Vector2(512.0, 640.0)
const DEFAULT_HOUR: float = 23.0
const DAY_SLOTS: Array[float] = [6.0, 12.0, 18.0, 23.0]
const OBJECT_FLAG_COLLIDER: int = 1
const PLAYER_FEET_OFFSET_PX: float = 41.0

var _chunk_view: ChunkView = null
var _player: Player = null
var _daylight: CanvasModulate = null
var _mountain_torch_field: Sprite2D = null
var _hud_label: Label = null
var _mountain_mask: PackedByteArray = PackedByteArray()
var _mountain_solid_pixels: int = 0
var _lab_ready: bool = false
var _current_hour: float = DEFAULT_HOUR
var _time_slot_index: int = 3
var _show_collision_debug: bool = false


func _ready() -> void:
	name = "ObjectTorchShadowLabScene"
	add_to_group("chunk_manager")
	WorldTileSetFactory.bootstrap()
	if PlayerAuthority != null:
		PlayerAuthority.clear_cache()
	_build_world()
	_build_lighting()
	_build_player()
	_build_hud()
	set_lab_hour(DEFAULT_HOUR)
	call_deferred("_finish_bootstrap")


func _process(_delta: float) -> void:
	_update_depth_ladder()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_T:
			cycle_lab_time()
			get_viewport().set_input_as_handled()
		KEY_1:
			set_lab_hour(6.0)
			get_viewport().set_input_as_handled()
		KEY_2:
			set_lab_hour(12.0)
			get_viewport().set_input_as_handled()
		KEY_3:
			set_lab_hour(18.0)
			get_viewport().set_input_as_handled()
		KEY_4:
			set_lab_hour(23.0)
			get_viewport().set_input_as_handled()
		KEY_Q:
			set_lab_hour(_current_hour - 1.0)
			get_viewport().set_input_as_handled()
		KEY_E:
			set_lab_hour(_current_hour + 1.0)
			get_viewport().set_input_as_handled()
		KEY_C:
			_show_collision_debug = not _show_collision_debug
			if _chunk_view != null and is_instance_valid(_chunk_view):
				_chunk_view.set_debug_object_collisions_visible(_show_collision_debug)
			get_viewport().set_input_as_handled()
		KEY_R:
			if _player != null and is_instance_valid(_player):
				_player.global_position = PLAYER_START
			get_viewport().set_input_as_handled()


func get_debug_snapshot() -> Dictionary:
	var torch: PointLight2D = _get_torch()
	return {
		"ready": _lab_ready,
		"chunk_view_ready": _chunk_view != null and is_instance_valid(_chunk_view),
		"mountain_ready": not _mountain_mask.is_empty(),
		"mountain_solid_pixels": _mountain_solid_pixels,
		"mountain_torch_field_ready": _mountain_torch_field != null and is_instance_valid(_mountain_torch_field),
		"tree_count": 2,
		"rock_count": 5,
		"big_rock_count": 1,
		"player_ready": _player != null and is_instance_valid(_player),
		"torch_ready": torch != null and is_instance_valid(torch),
		"torch_enabled": torch != null and torch.enabled,
		"current_hour": _current_hour,
		"daylight_ready": _daylight != null and is_instance_valid(_daylight),
		"hud_ready": _hud_label != null and is_instance_valid(_hud_label),
		"collision_debug": _show_collision_debug,
	}


func set_lab_torch_enabled(enabled: bool) -> void:
	var torch: PointLight2D = _get_torch()
	if torch == null:
		return
	torch.enabled = enabled
	_update_hud()


func set_lab_hour(hour: float) -> void:
	_current_hour = fposmod(hour, 24.0)
	if TimeManager != null and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(true)
	if TimeManager != null and TimeManager.has_method("restore_persisted_state"):
		TimeManager.restore_persisted_state(
			_current_hour,
			maxi(1, int(TimeManager.current_day)),
			int(TimeManager.current_season)
		)
	_apply_sun_to_chunk()
	_update_hud()


func cycle_lab_time() -> void:
	_time_slot_index = (_time_slot_index + 1) % DAY_SLOTS.size()
	set_lab_hour(float(DAY_SLOTS[_time_slot_index]))


func is_walkable_at_world(world_pos: Vector2) -> bool:
	if world_pos.x < 24.0 or world_pos.y < 24.0:
		return false
	var world_size := Vector2(float(MASK_WIDTH), float(MASK_HEIGHT)) * MASK_STEP_PX
	if world_pos.x > world_size.x - 24.0 or world_pos.y > world_size.y - 24.0:
		return false
	return _mountain_alpha_at(world_pos) < 0.48


func has_resource_at_world(_world_pos: Vector2) -> bool:
	return false


func try_harvest_at_world(_world_pos: Vector2) -> Dictionary:
	return {
		"success": false,
	}


func get_mountain_cover_sample(_tile_coord: Vector2i) -> Dictionary:
	return {
		"ready": false,
	}


func get_mountain_torch_shadow_field_mask(_torch_world_pos: Vector2, _radius_px: float) -> Dictionary:
	if _mountain_mask.is_empty():
		return {
			"ready": false,
		}
	return {
		"ready": true,
		"mask": _mountain_mask,
		"width": MASK_WIDTH,
		"height": MASK_HEIGHT,
		"origin_world": Vector2.ZERO,
		"step_px": MASK_STEP_PX,
		"solid_sample_count": _mountain_solid_pixels,
		"signature": "object_torch_shadow_lab_%d" % _mountain_solid_pixels,
	}


func _finish_bootstrap() -> void:
	set_lab_torch_enabled(true)
	_lab_ready = true
	_update_hud()


func _build_world() -> void:
	_chunk_view = ChunkView.new()
	_chunk_view.name = "LabChunkView"
	_chunk_view.configure(Vector2i.ZERO)
	_chunk_view.set_mountain_tile_visuals_enabled(false)
	_chunk_view.set_plains_rock_scatter_sources([
		PLAINS_ROCK_ATLAS_1,
		PLAINS_ROCK_ATLAS_2,
		PLAINS_VOLCANIC_ROCK_ATLAS,
		PLAINS_RARE_ROCK_ATLAS,
	])
	_chunk_view.set_tree_source(PLAINS_TREE_ATLAS)
	_chunk_view.set_big_grass_rock_sources([BIG_ROCK_1, BIG_ROCK_2, BIG_ROCK_3, BIG_ROCK_4])
	add_child(_chunk_view)

	var packet: Dictionary = _build_chunk_packet()
	_chunk_view.begin_apply(packet)
	while _chunk_view.apply_next_batch(WorldRuntimeConstants.PUBLISH_BATCH_SIZE):
		pass
	_chunk_view.visible = true
	_apply_mountain()
	_apply_sun_to_chunk()


func _build_lighting() -> void:
	_daylight = DaylightSystemScript.new() as CanvasModulate
	_daylight.name = "LabDaylight"
	add_child(_daylight)
	_mountain_torch_field = MountainTorchShadowFieldScript.new() as Sprite2D
	_mountain_torch_field.name = "LabMountainTorchShadowField"
	add_child(_mountain_torch_field)


func _build_player() -> void:
	_player = PlayerScene.instantiate() as Player
	_player.name = "LabPlayer"
	_player.global_position = PLAYER_START
	add_child(_player)
	var camera: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.make_current()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LabHudLayer"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "LabHudPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.offset_right = 610.0
	panel.offset_bottom = 154.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.025, 0.03, 0.68)
	style.border_color = Color(0.85, 0.62, 0.32, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	_hud_label = Label.new()
	_hud_label.name = "LabHudLabel"
	_hud_label.custom_minimum_size = Vector2(580.0, 124.0)
	_hud_label.add_theme_font_size_override("font_size", 15)
	_hud_label.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98, 1.0))
	_hud_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_hud_label)
	_update_hud()


func _build_chunk_packet() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var terrain_atlas_indices := PackedInt32Array()
	var walkable_flags := PackedByteArray()
	var lake_flags := PackedByteArray()
	var mountain_ids := PackedInt32Array()
	var mountain_flags := PackedByteArray()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		terrain_atlas_indices[index] = index % 4
		walkable_flags[index] = 1

	var objects: Array[Dictionary] = [
		_object(WorldObjectPacketLayer.OBJECT_KIND_TREE, Vector2(330.0, 530.0), 230, 0, 3, OBJECT_FLAG_COLLIDER, 224, 12),
		_object(WorldObjectPacketLayer.OBJECT_KIND_TREE, Vector2(725.0, 560.0), 218, 0, 9, OBJECT_FLAG_COLLIDER, 236, 95),
		_object(WorldObjectPacketLayer.OBJECT_KIND_ROCK, Vector2(435.0, 500.0), 58, 0, 4, OBJECT_FLAG_COLLIDER, 230, 20),
		_object(WorldObjectPacketLayer.OBJECT_KIND_ROCK, Vector2(610.0, 510.0), 62, 1, 11, OBJECT_FLAG_COLLIDER, 238, 84),
		_object(WorldObjectPacketLayer.OBJECT_KIND_ROCK, Vector2(430.0, 705.0), 50, 2, 7, OBJECT_FLAG_COLLIDER, 222, 143),
		_object(WorldObjectPacketLayer.OBJECT_KIND_ROCK, Vector2(610.0, 720.0), 68, 0, 18, OBJECT_FLAG_COLLIDER, 244, 188),
		_object(WorldObjectPacketLayer.OBJECT_KIND_ROCK, Vector2(560.0, 610.0), 52, 1, 25, OBJECT_FLAG_COLLIDER, 232, 211),
		_object(WorldObjectPacketLayer.OBJECT_KIND_BIG_GRASS_ROCK, Vector2(790.0, 735.0), 122, 0, 0, OBJECT_FLAG_COLLIDER, 238, 67),
	]
	return _packet_with_objects(
		terrain_ids,
		terrain_atlas_indices,
		walkable_flags,
		lake_flags,
		mountain_ids,
		mountain_flags,
		objects
	)


func _packet_with_objects(
		terrain_ids: PackedInt32Array,
		terrain_atlas_indices: PackedInt32Array,
		walkable_flags: PackedByteArray,
		lake_flags: PackedByteArray,
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
		objects: Array[Dictionary],
) -> Dictionary:
	var object_kind := PackedByteArray()
	var object_x := PackedByteArray()
	var object_y := PackedByteArray()
	var object_size := PackedByteArray()
	var object_atlas := PackedByteArray()
	var object_variant := PackedByteArray()
	var object_flags := PackedByteArray()
	var object_tint := PackedByteArray()
	var object_phase := PackedByteArray()
	for spec: Dictionary in objects:
		var pos: Vector2 = spec.get("position", Vector2.ZERO) as Vector2
		object_kind.append(int(spec.get("kind", 0)))
		object_x.append(_encode_local_px(pos.x))
		object_y.append(_encode_local_px(pos.y))
		object_size.append(clampi(int(spec.get("size", 64)), 1, 255))
		object_atlas.append(clampi(int(spec.get("atlas", 0)), 0, 255))
		object_variant.append(clampi(int(spec.get("variant", 0)), 0, 255))
		object_flags.append(clampi(int(spec.get("flags", 0)), 0, 255))
		object_tint.append(clampi(int(spec.get("tint", 255)), 0, 255))
		object_phase.append(clampi(int(spec.get("phase", 0)), 0, 255))
	return {
		"world_seed": WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		"world_version": WorldRuntimeConstants.WORLD_VERSION,
		"chunk_coord": Vector2i.ZERO,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"object_kind": object_kind,
		"object_local_x_px_q4": object_x,
		"object_local_y_px_q4": object_y,
		"object_size_px": object_size,
		"object_atlas_index": object_atlas,
		"object_variant": object_variant,
		"object_flags": object_flags,
		"object_tint": object_tint,
		"object_phase": object_phase,
	}


func _object(
		kind: int,
		position: Vector2,
		size: int,
		atlas: int,
		variant: int,
		flags: int,
		tint: int,
		phase: int,
) -> Dictionary:
	return {
		"kind": kind,
		"position": position,
		"size": size,
		"atlas": atlas,
		"variant": variant,
		"flags": flags,
		"tint": tint,
		"phase": phase,
	}


func _apply_mountain() -> void:
	var mask_data: Dictionary = _build_mountain_mask()
	_mountain_mask = mask_data.get("mask", PackedByteArray()) as PackedByteArray
	_mountain_solid_pixels = int(mask_data.get("solid_pixels", 0))
	var result: Dictionary = {
		"success": true,
		"ready": true,
		"native": true,
		"top_mask": _mountain_mask,
		"top_mask_width": MASK_WIDTH,
		"top_mask_height": MASK_HEIGHT,
		"top_mask_origin_world": Vector2.ZERO,
		"top_mask_step_px": MASK_STEP_PX,
		"top_texture_scale": 0.70,
		"hit_mask": mask_data.get("hit_mask", PackedByteArray()),
		"hit_mask_width": MASK_WIDTH,
		"hit_mask_height": MASK_HEIGHT,
		"hit_mask_origin_world": Vector2.ZERO,
		"hit_mask_step_px": MASK_STEP_PX,
		"hit_mask_solid_pixel_count": _mountain_solid_pixels,
		"render_origin_world": Vector2.ZERO,
		"render_size_world": Vector2(MASK_WIDTH, MASK_HEIGHT) * MASK_STEP_PX,
		"mountain_tile_count": 64,
		"top_pixel_count": _mountain_solid_pixels,
		"face_pixel_count": 0,
		"rim_pixel_count": 0,
		"image_width": MASK_WIDTH,
		"image_height": MASK_HEIGHT,
		"runtime_emit_top_mask": true,
		"runtime_edge_overlay_only": true,
		"runtime_visual_clip_to_target_rect": true,
	}
	_chunk_view.apply_mountain_render_page(result, TOP_TEXTURE, FACE_TEXTURE)


func _build_mountain_mask() -> Dictionary:
	var mask := PackedByteArray()
	var hit_mask := PackedByteArray()
	mask.resize(MASK_WIDTH * MASK_HEIGHT)
	hit_mask.resize(MASK_WIDTH * MASK_HEIGHT)
	var solid_pixels: int = 0
	for y: int in range(MASK_HEIGHT):
		for x: int in range(MASK_WIDTH):
			var p := Vector2(float(x), float(y)) * MASK_STEP_PX
			var sdf: float = _mountain_sdf(p)
			sdf += sin(p.x * 0.037 + p.y * 0.018) * 5.0
			sdf += sin(p.x * 0.071 + 1.4) * 3.0
			var alpha: float = 1.0 - smoothstep(-15.0, 15.0, sdf)
			var value: int = clampi(roundi(alpha * 255.0), 0, 255)
			var index: int = y * MASK_WIDTH + x
			mask[index] = value
			if value >= 112:
				hit_mask[index] = 1
				solid_pixels += 1
	return {
		"mask": mask,
		"hit_mask": hit_mask,
		"solid_pixels": solid_pixels,
	}


func _mountain_sdf(p: Vector2) -> float:
	var ridge_y: float = 370.0 \
			+ sin(p.x * 0.011) * 25.0 \
			+ sin(p.x * 0.025 + 1.8) * 13.0 \
			+ sin(p.x * 0.006 - 0.7) * 18.0
	var cap: float = maxf(p.y - ridge_y, maxf(78.0 - p.x, p.x - 946.0))
	var left_lobe: float = _ellipse_sdf(p, Vector2(220.0, 330.0), Vector2(180.0, 180.0))
	var right_lobe: float = _ellipse_sdf(p, Vector2(820.0, 335.0), Vector2(205.0, 165.0))
	var lower_shoulder: float = _ellipse_sdf(p, Vector2(650.0, 430.0), Vector2(210.0, 62.0))
	var d: float = minf(cap, minf(left_lobe, minf(right_lobe, lower_shoulder)))
	var notch: float = _ellipse_sdf(p, Vector2(520.0, 455.0), Vector2(112.0, 62.0))
	d = maxf(d, -notch)
	return d


func _ellipse_sdf(p: Vector2, center: Vector2, radius: Vector2) -> float:
	var q := Vector2((p.x - center.x) / radius.x, (p.y - center.y) / radius.y)
	return (q.length() - 1.0) * minf(radius.x, radius.y)


func _fbm(p: Vector2) -> float:
	var value: float = 0.0
	var amp: float = 0.55
	var total: float = 0.0
	for i: int in range(4):
		value += _value_noise(p) * amp
		total += amp
		p = p * 2.03 + Vector2(17.0 + float(i) * 3.0, -11.0)
		amp *= 0.48
	return value / maxf(total, 0.0001)


func _value_noise(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	var u := Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	var a: float = _hash(i)
	var b: float = _hash(i + Vector2(1.0, 0.0))
	var c: float = _hash(i + Vector2(0.0, 1.0))
	var d: float = _hash(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


func _hash(p: Vector2) -> float:
	return fposmod(sin(p.x * 127.1 + p.y * 311.7) * 43758.5453123, 1.0)


func _apply_sun_to_chunk() -> void:
	if _chunk_view == null or not is_instance_valid(_chunk_view):
		return
	var sun_progress: float = WorldVisualLightingProfile.sun_progress_for_hour(_current_hour)
	var low_sun: float = WorldVisualLightingProfile.low_sun_for_progress(sun_progress)
	_chunk_view.apply_sun_lighting(
		WorldVisualLightingProfile.light_angle_deg_for_hour(_current_hour),
		WorldVisualLightingProfile.shadow_length_px_for_low_sun(low_sun),
		WorldVisualLightingProfile.shadow_opacity_for_low_sun_and_hour(low_sun, _current_hour),
		WorldVisualLightingProfile.shadow_softness_px_for_low_sun(low_sun)
	)


func _update_depth_ladder() -> void:
	if _chunk_view == null or _player == null:
		return
	var anchor_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(
		_player.global_position.y + PLAYER_FEET_OFFSET_PX
	)
	_chunk_view.update_mid_ladder_z(anchor_stripe)


func _update_hud() -> void:
	if _hud_label == null:
		return
	var torch: PointLight2D = _get_torch()
	var torch_text: String = "ON" if torch != null and torch.enabled else "OFF"
	_hud_label.text = "\n".join([
		"Object torch shadow lab",
		"WASD движение | F факел: %s | T время | 1 утро 2 день 3 закат 4 ночь | Q/E час" % torch_text,
		"C коллизии: %s | R вернуть игрока | колесо мыши зум" % ("ON" if _show_collision_debug else "OFF"),
		"Час %.1f | гора + 2 дерева + 5 камней + валун | двигайся вокруг объектов" % _current_hour,
	])


func _get_torch() -> PointLight2D:
	if _player == null or not is_instance_valid(_player):
		return null
	return _player.get_node_or_null("Torch") as PointLight2D


func _mountain_alpha_at(world_pos: Vector2) -> float:
	var x: int = floori(world_pos.x / MASK_STEP_PX)
	var y: int = floori(world_pos.y / MASK_STEP_PX)
	if x < 0 or y < 0 or x >= MASK_WIDTH or y >= MASK_HEIGHT:
		return 0.0
	var index: int = y * MASK_WIDTH + x
	if index < 0 or index >= _mountain_mask.size():
		return 0.0
	return float(int(_mountain_mask[index])) / 255.0


func _encode_local_px(value: float) -> int:
	return clampi(floori((value - WorldObjectPacketLayer.OBJECT_LOCAL_PX_QUANTUM * 0.5) \
			/ WorldObjectPacketLayer.OBJECT_LOCAL_PX_QUANTUM), 0, 255)
