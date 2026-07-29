class_name HudStatusWidget
extends HudWidget

## Статус укрытия: снаружи / в базе / без питания, плюс контекст стройки.
## Это якорь контраста "внутри безопасно — снаружи враждебно", поэтому строка
## меняет цвет и остаётся на экране постоянно.

var _shelter_icon: HudIcon = null
var _status_label: Label = null
var _build_row: HBoxContainer = null
var _build_label: Label = null
var _scrap_label: Label = null
var _is_indoor: bool = false
var _life_support_powered: bool = false
var _is_build_mode: bool = false
var _scrap_count: int = 0


func _setup() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(column)

	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 7)
	status_row.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(status_row)

	_shelter_icon = HudIcon.new()
	_shelter_icon.configure(HudIcons.Id.SHELTER, 14.0, HudPalette.CAUTION, 1.4)
	status_row.add_child(_shelter_icon)

	_status_label = _make_hud_label(LabelStyle.CAPS, 11, HudPalette.CAUTION)
	status_row.add_child(_status_label)

	_build_row = HBoxContainer.new()
	_build_row.add_theme_constant_override("separation", 7)
	_build_row.mouse_filter = MOUSE_FILTER_IGNORE
	_build_row.visible = false
	column.add_child(_build_row)

	var build_icon: HudIcon = HudIcon.new()
	build_icon.configure(HudIcons.Id.HAMMER, 13.0, HudPalette.EMBER, 1.3)
	_build_row.add_child(build_icon)

	_build_label = _make_hud_label(LabelStyle.CAPS, 10, HudPalette.EMBER)
	_build_row.add_child(_build_label)

	_scrap_label = _make_hud_label(
		LabelStyle.VALUE,
		11,
		HudPalette.TEXT_PRIMARY,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	_scrap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_row.add_child(_scrap_label)

	_update_status()
	_update_build_context()

	EventBus.player_entered_indoor.connect(_on_entered_indoor)
	EventBus.player_exited_indoor.connect(_on_exited_indoor)
	EventBus.life_support_power_changed.connect(_on_life_support_power_changed)
	EventBus.scrap_collected.connect(_on_scrap_collected)
	EventBus.scrap_spent.connect(_on_scrap_spent)
	EventBus.build_mode_changed.connect(_on_build_mode_changed)
	EventBus.language_changed.connect(_on_language_changed)


func _on_entered_indoor() -> void:
	_is_indoor = true
	_update_status()


func _on_exited_indoor() -> void:
	_is_indoor = false
	_update_status()


func _on_life_support_power_changed(is_powered: bool) -> void:
	_life_support_powered = is_powered
	_update_status()


func _update_status() -> void:
	if _status_label == null:
		return
	var key: String = "UI_HUD_STATUS_OUTSIDE"
	var color: Color = HudPalette.CAUTION
	if _is_indoor and _life_support_powered:
		key = "UI_HUD_STATUS_BASE_POWERED"
		color = HudPalette.STABLE
	elif _is_indoor:
		key = "UI_HUD_STATUS_BASE_UNPOWERED"
		color = HudPalette.CRITICAL
	_status_label.text = Localization.t(key)
	_status_label.add_theme_color_override("font_color", color)
	_shelter_icon.set_glyph_color(color)


func _on_scrap_collected(total: int) -> void:
	_scrap_count = total
	_refresh_scrap_label()


func _on_scrap_spent(_amount: int, remaining: int) -> void:
	_scrap_count = remaining
	_refresh_scrap_label()


func _on_build_mode_changed(is_active: bool) -> void:
	_is_build_mode = is_active
	if is_active:
		var player: Player = PlayerAuthority.get_local_player() as Player
		if player != null:
			_scrap_count = player.get_scrap_count()
	_update_build_context()


func _on_language_changed(_locale: String) -> void:
	_update_status()
	_update_build_context()


func _update_build_context() -> void:
	if _build_row == null:
		return
	_build_row.visible = _is_build_mode
	_build_label.text = Localization.t("UI_HUD_BUILD_MODE")
	_refresh_scrap_label()


func _refresh_scrap_label() -> void:
	if _scrap_label == null:
		return
	_scrap_label.text = Localization.t("UI_HUD_SCRAP", {"count": _scrap_count})
