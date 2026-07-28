class_name VisualRuntimeLabTextureProbe
extends Node

const WorldRuntimeConstants = preload(
	"res://core/systems/world/world_runtime_constants.gd"
)
const WorldTileSetFactory = preload(
	"res://core/systems/world/world_tile_set_factory.gd"
)

const PROBE_SIZE: Vector2i = Vector2i(1, 1)
const RESULT_FRAMES: int = 3
const REPROBE_DISTANCE_WORLD_PX: float = 8.0

var _authoring: VisualRuntimeLabAuthoring = null
var _panel: VisualRuntimeLabPanel = null
var _viewport: SubViewport = null
var _material: ShaderMaterial = null
var _pending_frames: int = 0
var _requested_world_position: Vector2 = Vector2.INF
var _result_world_position: Vector2 = Vector2.INF
var _result_zone_id: int = -1


func setup(
	authoring: VisualRuntimeLabAuthoring,
	panel: VisualRuntimeLabPanel,
) -> void:
	_authoring = authoring
	_panel = panel


func update(inspection: Dictionary) -> void:
	_tick_pending_probe()
	if _panel == null \
			or not Input.is_key_pressed(KEY_SHIFT) \
			or inspection.is_empty():
		if _panel != null:
			_panel.hide_cursor_texture_tooltip()
		return
	var viewport_mouse: Vector2 = get_viewport().get_mouse_position()
	var terrain_id: int = int(inspection.get("terrain_id", -1))
	if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
		_update_ground_zone_tooltip(inspection, viewport_mouse)
		return
	var texture_path: String = String(inspection.get("texture", ""))
	_panel.show_cursor_texture_tooltip(
		viewport_mouse,
		Localization.t(
			"UI_VISUAL_LAB_SHIFT_TOOLTIP",
			{
				"zone": String(inspection.get("terrain_label", "")),
				"texture": (
					texture_path.get_file()
					if not texture_path.is_empty()
					else Localization.t("UI_VISUAL_LAB_TEXTURE_COMPOSITE")
				),
			},
		),
	)


func reset_runtime_probe() -> void:
	_pending_frames = 0
	_requested_world_position = Vector2.INF
	_result_world_position = Vector2.INF
	_result_zone_id = -1
	_material = null
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	if _panel != null:
		_panel.hide_cursor_texture_tooltip()


func _exit_tree() -> void:
	if _panel != null:
		_panel.hide_cursor_texture_tooltip()


func _update_ground_zone_tooltip(
	inspection: Dictionary,
	viewport_mouse: Vector2,
) -> void:
	var world_position: Vector2 = inspection.get(
		"world_position",
		Vector2.ZERO,
	) as Vector2
	if _pending_frames <= 0 \
			and (
				_result_zone_id < 0
				or world_position.distance_to(_result_world_position) \
				>= REPROBE_DISTANCE_WORLD_PX
			):
		_request_probe(world_position)
	if _result_zone_id < 0:
		_panel.show_cursor_texture_tooltip(
			viewport_mouse,
			Localization.t("UI_VISUAL_LAB_SHIFT_SAMPLING"),
		)
		return
	var zone_info: Dictionary = _authoring.get_ground_zone_texture_info(
		_result_zone_id
	)
	_panel.show_cursor_texture_tooltip(
		viewport_mouse,
		Localization.t(
			"UI_VISUAL_LAB_SHIFT_TOOLTIP",
			{
				"zone": Localization.t(String(zone_info.get("label_key", ""))),
				"texture": String(zone_info.get("texture", "")),
			},
		),
	)


func _request_probe(world_position: Vector2) -> void:
	if not _ensure_probe():
		return
	_requested_world_position = world_position
	_material.set_shader_parameter("debug_world_offset", world_position)
	_material.set_shader_parameter("debug_zone_mode", 2)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_pending_frames = RESULT_FRAMES


func _tick_pending_probe() -> void:
	if _pending_frames <= 0 or _viewport == null:
		return
	_pending_frames -= 1
	if _pending_frames > 0:
		return
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_result_zone_id = -1
		return
	var encoded_alpha: float = image.get_pixel(0, 0).a
	_result_zone_id = clampi(roundi(encoded_alpha * 16.0) - 1, 0, 9)
	_result_world_position = _requested_world_position


func _ensure_probe() -> bool:
	if _viewport != null and is_instance_valid(_viewport) and _material != null:
		return true
	var runtime_material: ShaderMaterial = (
		WorldTileSetFactory.get_built_material_for_terrain(
			WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
		)
	)
	if runtime_material == null:
		return false
	_viewport = SubViewport.new()
	_viewport.name = "GroundZonePixelProbe"
	_viewport.size = PROBE_SIZE
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	var mask_image: Image = Image.create(
		PROBE_SIZE.x,
		PROBE_SIZE.y,
		false,
		Image.FORMAT_RGBA8,
	)
	mask_image.set_pixel(0, 0, Color(1.0, 0.0, 0.0, 1.0))
	var sprite: Sprite2D = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(mask_image)
	_material = runtime_material.duplicate() as ShaderMaterial
	_material.set_shader_parameter("debug_zone_mode", 2)
	sprite.material = _material
	_viewport.add_child(sprite)
	return true
