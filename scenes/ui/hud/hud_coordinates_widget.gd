class_name HudCoordinatesWidget
extends HudWidget

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const UPDATE_INTERVAL_SECONDS: float = 0.08
const UNKNOWN_TILE: Vector2i = Vector2i(2147483647, 2147483647)

var _label: Label = null
var _elapsed: float = 0.0
var _last_tile: Vector2i = UNKNOWN_TILE

func _setup() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.52, 0.58, 0.62))
	add_child(_label)

	EventBus.language_changed.connect(func(_locale: String) -> void:
		_last_tile = UNKNOWN_TILE
		_update_label()
	)
	_update_label()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL_SECONDS:
		return
	_elapsed = 0.0
	_update_label()

func _update_label() -> void:
	if _label == null:
		return
	var player: Node2D = PlayerAuthority.get_local_player() as Node2D
	if player == null:
		_label.text = Localization.t("UI_HUD_TILE_COORDS", {"x": "--", "y": "--"})
		return
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(player.global_position)
	if tile_coord == _last_tile:
		return
	_last_tile = tile_coord
	_label.text = Localization.t("UI_HUD_TILE_COORDS", {
		"x": tile_coord.x,
		"y": tile_coord.y,
	})
