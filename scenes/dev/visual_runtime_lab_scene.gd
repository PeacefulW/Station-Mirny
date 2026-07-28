extends Node2D
const WorldRuntimeConstants = preload(
	"res://core/systems/world/world_runtime_constants.gd"
)
const TerrainPresentationRegistry = preload(
	"res://core/systems/world/terrain_presentation_registry.gd"
)
const WorldTileSetFactory = preload(
	"res://core/systems/world/world_tile_set_factory.gd"
)
const VisualRuntimeLabPanelScript = preload(
	"res://scenes/dev/visual_runtime_lab_panel.gd"
)
const VisualRuntimeLabAuthoringScript = preload(
	"res://scenes/dev/visual_runtime_lab_authoring.gd"
)
const VisualRuntimeLabSelectorScript = preload(
	"res://scenes/dev/visual_runtime_lab_selector.gd"
)
const VisualRuntimeLabTextureProbeScript = preload(
	"res://scenes/dev/visual_runtime_lab_texture_probe.gd"
)
const WORLD_SCENE: PackedScene = preload("res://scenes/world/world_runtime_v0.tscn")
const PLAYER_BALANCE: PlayerBalance = preload("res://data/balance/player_balance.tres")
const PROBE_SEED: int = 707
const PROBE_DAY_HOUR: float = 9.0
const PROBE_NIGHT_HOUR: float = 0.0
const PROBE_DAY: int = 1
const PROBE_SEASON: int = 0
const PROBE_WEATHER: StringName = &"core:clear"
const MAX_TARGET_WAIT_MSEC: int = 180000
enum LabState {
	BOOTING,
	WAITING_INITIAL_TARGET,
	SELECTING_PATCH,
	WAITING_PATCH,
	READY,
	FAILED,
}
var _state: LabState = LabState.BOOTING
var _authoring: VisualRuntimeLabAuthoring = null
var _selector: VisualRuntimeLabSelector = null
var _panel: VisualRuntimeLabPanel = null
var _texture_probe: VisualRuntimeLabTextureProbe = null
var _world: Node2D = null
var _streamer: WorldStreamer = null
var _player: Player = null
var _patch: Dictionary = {}
var _wait_started_msec: int = 0
var _is_restarting: bool = false
var _zone_enabled: bool = false
var _grid_enabled: bool = false
var _mountain_enabled: bool = false
var _collisions_enabled: bool = false
var _runtime_grid_enabled: bool = false
var _runtime_mountain_enabled: bool = false
var _runtime_collisions_enabled: bool = false
var _probe_hour: float = PROBE_DAY_HOUR
var _last_inspected_tile: Vector2i = Vector2i(2147483647, 2147483647)
var _last_inspection: Dictionary = {}
var _ready_status_key: String = "UI_VISUAL_LAB_STATUS_READY"
func _ready() -> void:
	_authoring = VisualRuntimeLabAuthoringScript.new() as VisualRuntimeLabAuthoring
	_selector = VisualRuntimeLabSelectorScript.new() as VisualRuntimeLabSelector
	var load_result: Dictionary = _authoring.load_from_disk()
	_panel = VisualRuntimeLabPanelScript.new() as VisualRuntimeLabPanel
	_panel.name = "VisualRuntimeLabPanel"
	add_child(_panel)
	if not bool(load_result.get("success", false)):
		_state = LabState.FAILED
		_panel.setup(_authoring)
		_panel.set_status("UI_VISUAL_LAB_STATUS_RESOURCE_ERROR")
		return
	_panel.setup(_authoring)
	_texture_probe = (
		VisualRuntimeLabTextureProbeScript.new() as VisualRuntimeLabTextureProbe
	)
	add_child(_texture_probe)
	_texture_probe.setup(_authoring, _panel)
	_connect_panel()
	call_deferred("_restart_runtime")


func _process(_delta: float) -> void:
	if _state == LabState.WAITING_INITIAL_TARGET:
		_tick_waiting_initial_target()
	elif _state == LabState.WAITING_PATCH:
		_tick_waiting_patch()
	elif _state == LabState.READY:
		_update_cursor_inspector()
		_texture_probe.update(_last_inspection)
func _exit_tree() -> void:
	_set_ground_zone_mode(false)


func get_debug_snapshot() -> Dictionary:
	var loading_state: Dictionary = (
		_streamer.get_initial_loading_state()
		if _streamer != null
		else {}
	)
	var camera: Camera2D = (
		_player.get_node_or_null("Camera2D") as Camera2D
		if _player != null
		else null
	)
	return {
		"ready": _state == LabState.READY,
		"failed": _state == LabState.FAILED,
		"state": _state,
		"world_runtime_instanced": _world != null,
		"world_seed": _streamer.get_world_seed() if _streamer != null else 0,
		"world_version": _streamer.get_world_version() if _streamer != null else 0,
		"camera_zoom": camera.zoom.x if camera != null else 0.0,
		"expected_min_zoom": PLAYER_BALANCE.zoom_min,
		"patch": _patch.duplicate(true),
		"loading": loading_state,
		"zone_enabled": _zone_enabled,
		"shift_tooltip": (
			_panel.get_cursor_texture_tooltip_debug_snapshot()
			if _panel != null
			else {}
		),
	}


func debug_set_zone_overlay(enabled: bool) -> void:
	if _panel != null:
		_panel.set_zone_overlay_enabled_without_signal(enabled)
	_on_zone_overlay_changed(enabled)


func _connect_panel() -> void:
	_panel.apply_requested.connect(_on_apply_requested)
	_panel.save_requested.connect(_on_save_requested)
	_panel.reset_requested.connect(_on_reset_requested)
	_panel.zone_overlay_changed.connect(_on_zone_overlay_changed)
	_panel.grid_overlay_changed.connect(_on_grid_overlay_changed)
	_panel.mountain_overlay_changed.connect(_on_mountain_overlay_changed)
	_panel.collision_overlay_changed.connect(_on_collision_overlay_changed)
	_panel.day_night_requested.connect(_on_day_night_requested)


func _restart_runtime() -> void:
	if _is_restarting or _state == LabState.FAILED:
		return
	_is_restarting = true
	_panel.set_busy(true)
	_panel.set_status("UI_VISUAL_LAB_STATUS_APPLYING")
	_texture_probe.reset_runtime_probe()
	_set_ground_zone_mode(false)
	if _world != null and is_instance_valid(_world):
		remove_child(_world)
		_world.queue_free()
		await get_tree().process_frame
	PlayerAuthority.clear_cache()
	WorldTileSetFactory.reset_debug_authoring_cache()
	_authoring.apply_material_working_copies_to_registry()
	_spawn_runtime()
	_is_restarting = false


func _spawn_runtime() -> void:
	_patch.clear()
	_last_inspected_tile = Vector2i(2147483647, 2147483647)
	_last_inspection.clear()
	_runtime_grid_enabled = false
	_runtime_mountain_enabled = false
	_runtime_collisions_enabled = false
	_world = WORLD_SCENE.instantiate() as Node2D
	add_child(_world)
	var hud_layer: CanvasLayer = _world.get_node_or_null("HudLayer") as CanvasLayer
	if hud_layer != null:
		hud_layer.visible = false
	_streamer = _world.get_node_or_null("WorldStreamer") as WorldStreamer
	_player = _world.get_node_or_null("Player") as Player
	if _streamer == null or _player == null:
		_fail("UI_VISUAL_LAB_STATUS_RUNTIME_ERROR")
		return
	if not _streamer.enable_debug_visible_only_initial_loading():
		_fail("UI_VISUAL_LAB_STATUS_RUNTIME_ERROR")
		return
	_streamer.initialize_new_world(
		PROBE_SEED,
		_authoring.mountains,
		_authoring.world_bounds,
		_authoring.foundation,
		_authoring.lakes,
		_authoring.trees,
		_authoring.small_rocks,
		_authoring.bare_stones,
	)
	_configure_environment(PROBE_DAY_HOUR)
	_apply_overlay_toggles()
	_wait_started_msec = Time.get_ticks_msec()
	_state = LabState.WAITING_INITIAL_TARGET


func _tick_waiting_initial_target() -> void:
	if _streamer == null:
		return
	var loading_state: Dictionary = _streamer.get_initial_loading_state()
	if bool(loading_state.get("target_established", false)):
		var origin_chunk: Vector2i = loading_state.get(
			"target_center_chunk",
			Vector2i.ZERO,
		) as Vector2i
		_state = LabState.SELECTING_PATCH
		_panel.set_status("UI_VISUAL_LAB_STATUS_SELECTING")
		call_deferred("_select_patch", origin_chunk)
	elif _phase_timed_out():
		_fail("UI_VISUAL_LAB_STATUS_TARGET_TIMEOUT")


func _select_patch(origin_chunk: Vector2i) -> void:
	if _streamer == null or _player == null:
		_fail("UI_VISUAL_LAB_STATUS_RUNTIME_ERROR")
		return
	var selection: Dictionary = _selector.find_patch(
		_streamer.get_world_seed(),
		_streamer.get_world_version(),
		_authoring.get_settings_packed(),
		origin_chunk,
	)
	_patch = selection
	if not bool(selection.get("success", false)):
		_fail("UI_VISUAL_LAB_STATUS_PATCH_ERROR")
		return
	var camera_tile: Vector2i = selection.get(
		"camera_tile",
		Vector2i.ZERO,
	) as Vector2i
	_player.global_position = WorldRuntimeConstants.tile_to_world_center(camera_tile)
	_set_camera_to_maximum_zoom()
	_wait_started_msec = Time.get_ticks_msec()
	_state = LabState.WAITING_PATCH
	_panel.set_status("UI_VISUAL_LAB_STATUS_LOADING_PATCH")


func _tick_waiting_patch() -> void:
	if _streamer == null:
		return
	var loading_state: Dictionary = _streamer.get_initial_loading_state()
	if bool(loading_state.get("ready", false)):
		_state = LabState.READY
		_panel.set_busy(false)
		_panel.set_status(_ready_status_key)
		_ready_status_key = "UI_VISUAL_LAB_STATUS_READY"
		_panel.set_probe_summary({
			"seed": _streamer.get_world_seed(),
			"version": _streamer.get_world_version(),
			"zoom": PLAYER_BALANCE.zoom_min,
			"chunk_count": int(loading_state.get("visible_chunk_count", 0)),
			"exact_match": bool(_patch.get("exact_match", false)),
		})
		_sync_zone_material()
	elif _phase_timed_out():
		_fail("UI_VISUAL_LAB_STATUS_PATCH_TIMEOUT")


func _phase_timed_out() -> bool:
	return Time.get_ticks_msec() - _wait_started_msec > MAX_TARGET_WAIT_MSEC


func _set_camera_to_maximum_zoom() -> void:
	if _player == null:
		return
	var camera: PlayerCamera = _player.get_node_or_null("Camera2D") as PlayerCamera
	if camera == null:
		return
	var wheel_event: InputEventMouseButton = InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_event.pressed = true
	for _step_index: int in range(64):
		camera.handle_zoom_input(wheel_event)
	camera.zoom = Vector2(PLAYER_BALANCE.zoom_min, PLAYER_BALANCE.zoom_min)
	camera.reset_smoothing()
	camera.force_update_scroll()


func _configure_environment(hour: float) -> void:
	_probe_hour = hour
	if TimeManager != null:
		TimeManager.restore_persisted_state(_probe_hour, PROBE_DAY, PROBE_SEASON)
		TimeManager.set_paused(true)
	if WeatherRuntime != null:
		WeatherRuntime.restore_persisted_state({
			"active_regime": String(PROBE_WEATHER),
			"next_regime": String(PROBE_WEATHER),
			"in_transition": false,
			"transition": 0.0,
			"remaining_hours": 12.0,
			"weather_time_hours": 0.0,
			"transition_count": 0,
		})
		WeatherRuntime.clear_debug_cloud_cover()
		WeatherRuntime.set_debug_regime(PROBE_WEATHER)


func _apply_overlay_toggles() -> void:
	if _streamer == null:
		return
	if _grid_enabled != _runtime_grid_enabled:
		_runtime_grid_enabled = _streamer.toggle_debug_tile_grid()
	if _mountain_enabled != _runtime_mountain_enabled:
		_runtime_mountain_enabled = _streamer.toggle_debug_mountain_solid_mask()
	if _collisions_enabled != _runtime_collisions_enabled:
		_runtime_collisions_enabled = _streamer.toggle_debug_object_collisions()
		_set_player_collision_visible(_runtime_collisions_enabled)


func _sync_zone_material() -> void:
	if _state == LabState.FAILED:
		return
	var material: ShaderMaterial = WorldTileSetFactory.get_built_material_for_terrain(
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
	)
	if material != null:
		material.set_shader_parameter("debug_zone_mode", 1 if _zone_enabled else 0)


func _set_ground_zone_mode(enabled: bool) -> void:
	var material: ShaderMaterial = WorldTileSetFactory.get_built_material_for_terrain(
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
	)
	if material != null:
		material.set_shader_parameter("debug_zone_mode", 1 if enabled else 0)


func _update_cursor_inspector() -> void:
	if _streamer == null or _panel == null:
		return
	var viewport_mouse: Vector2 = get_viewport().get_mouse_position()
	if viewport_mouse.x <= 418.0:
		_last_inspection.clear()
		return
	var world_pos: Vector2 = get_global_mouse_position()
	var world_tile: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
	if world_tile == _last_inspected_tile:
		return
	_last_inspected_tile = world_tile
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(world_tile)
	var packet: Dictionary = _streamer.get_chunk_packet(chunk_coord)
	if packet.is_empty():
		_last_inspection.clear()
		_panel.set_inspector_text(Localization.t("UI_VISUAL_LAB_INSPECTOR_NOT_READY"))
		return
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(world_tile)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get(
		"terrain_ids",
		PackedInt32Array(),
	) as PackedInt32Array
	if index < 0 or index >= terrain_ids.size():
		_last_inspection.clear()
		_panel.set_inspector_text(Localization.t("UI_VISUAL_LAB_INSPECTOR_NOT_READY"))
		return
	var terrain_id: int = int(terrain_ids[index])
	var profile: TerrainPresentationProfile = TerrainPresentationRegistry.get_profile_for_terrain(
		terrain_id,
	)
	var material_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
		profile.material_set_id,
	)
	var texture_path: String = _primary_texture_path(terrain_id, material_set)
	var terrain_label: String = Localization.t(_terrain_label_key(terrain_id))
	_last_inspection = {
		"tile": world_tile,
		"world_position": world_pos,
		"terrain_id": terrain_id,
		"terrain_label": terrain_label,
		"texture": texture_path,
	}
	_panel.set_inspector_text(
		Localization.t(
			"UI_VISUAL_LAB_INSPECTOR_VALUE",
			{
				"tile": str(world_tile),
				"terrain": terrain_label,
				"profile": String(profile.id),
				"material": String(material_set.id),
				"texture": texture_path,
			},
		)
	)


func _primary_texture_path(
	terrain_id: int,
	material_set: TerrainMaterialSet,
) -> String:
	if terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW:
		var water_light: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
			&"lake:water_surface_light_material",
		)
		return water_light.top_albedo.resource_path if water_light != null else ""
	if terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP:
		var water_dark: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
			&"lake:water_surface_dark_material",
		)
		return water_dark.top_albedo.resource_path if water_dark != null else ""
	if material_set.top_albedo != null:
		return material_set.top_albedo.resource_path
	return Localization.t("UI_VISUAL_LAB_TEXTURE_COMPOSITE")


func _terrain_label_key(terrain_id: int) -> String:
	match terrain_id:
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
			return "UI_VISUAL_LAB_TERRAIN_GROUND"
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
			return "UI_VISUAL_LAB_TERRAIN_DUG"
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL:
			return "UI_VISUAL_LAB_TERRAIN_MOUNTAIN_WALL"
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			return "UI_VISUAL_LAB_TERRAIN_MOUNTAIN_FOOT"
		WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW:
			return "UI_VISUAL_LAB_TERRAIN_SHALLOW"
		WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP:
			return "UI_VISUAL_LAB_TERRAIN_DEEP"
	return "UI_VISUAL_LAB_TERRAIN_UNKNOWN"


func _set_player_collision_visible(enabled: bool) -> void:
	if _player != null:
		_player.set_debug_collision_visible(enabled)


func _on_apply_requested() -> void:
	_ready_status_key = "UI_VISUAL_LAB_STATUS_APPLIED"
	call_deferred("_restart_runtime")


func _on_save_requested() -> void:
	if _is_restarting:
		return
	var result: Dictionary = _authoring.save_to_runtime()
	if not bool(result.get("success", false)):
		_panel.set_status(
			"UI_VISUAL_LAB_STATUS_SAVE_ERROR",
			{
				"path": String(result.get("path", "")),
				"error": int(result.get("error", FAILED)),
			},
		)
		return
	_ready_status_key = "UI_VISUAL_LAB_STATUS_SAVED"
	call_deferred("_restart_runtime")


func _on_reset_requested() -> void:
	if _is_restarting:
		return
	var result: Dictionary = _authoring.load_from_disk()
	if not bool(result.get("success", false)):
		_panel.set_status("UI_VISUAL_LAB_STATUS_RESOURCE_ERROR")
		return
	_panel.refresh_values()
	_ready_status_key = "UI_VISUAL_LAB_STATUS_RESET"
	call_deferred("_restart_runtime")


func _on_zone_overlay_changed(enabled: bool) -> void:
	_zone_enabled = enabled
	_set_ground_zone_mode(enabled)


func _on_grid_overlay_changed(enabled: bool) -> void:
	_grid_enabled = enabled
	if _streamer != null and enabled != _runtime_grid_enabled:
		_runtime_grid_enabled = _streamer.toggle_debug_tile_grid()


func _on_mountain_overlay_changed(enabled: bool) -> void:
	_mountain_enabled = enabled
	if _streamer != null and enabled != _runtime_mountain_enabled:
		_runtime_mountain_enabled = _streamer.toggle_debug_mountain_solid_mask()


func _on_collision_overlay_changed(enabled: bool) -> void:
	_collisions_enabled = enabled
	if _streamer != null and enabled != _runtime_collisions_enabled:
		_runtime_collisions_enabled = _streamer.toggle_debug_object_collisions()
		_set_player_collision_visible(_runtime_collisions_enabled)


func _on_day_night_requested() -> void:
	var next_hour: float = (
		PROBE_NIGHT_HOUR
		if is_equal_approx(_probe_hour, PROBE_DAY_HOUR)
		else PROBE_DAY_HOUR
	)
	_configure_environment(next_hour)


func _fail(status_key: String) -> void:
	_state = LabState.FAILED
	_panel.set_busy(false)
	_panel.set_status(status_key)
	push_error(Localization.t(status_key))
