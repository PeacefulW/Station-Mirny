class_name BuildingTooltip
extends PanelContainer

## Подробная карточка здания. Появляется при наведении на BuildingCard.

var _name_label: Label = null
var _desc_label: Label = null
var _cost_label: Label = null
var _stats_label: Label = null
var _tech_label: Label = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	z_index = 200
	custom_minimum_size = Vector2(200, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.96)
	style.border_color = Color(0.3, 0.32, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = MOUSE_FILTER_IGNORE

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	vbox.add_child(_name_label)

	_desc_label = Label.new()
	_desc_label.add_theme_font_size_override("font_size", 11)
	_desc_label.add_theme_color_override("font_color", Color(0.55, 0.53, 0.48))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size.x = 190
	vbox.add_child(_desc_label)

	_cost_label = Label.new()
	_cost_label.add_theme_font_size_override("font_size", 11)
	_cost_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
	vbox.add_child(_cost_label)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	vbox.add_child(_stats_label)

	_tech_label = Label.new()
	_tech_label.add_theme_font_size_override("font_size", 11)
	_tech_label.add_theme_color_override("font_color", Color(0.6, 0.4, 0.3))
	_tech_label.visible = false
	vbox.add_child(_tech_label)

	add_child(vbox)

## Показать тултип для здания.
func show_building(building: BuildingData, screen_pos: Vector2) -> void:
	if not building:
		hide_tooltip()
		return

	_name_label.text = building.get_display_name()
	_desc_label.text = building.get_description()
	_cost_label.text = _format_cost(building)
	_stats_label.text = _format_stats(building)
	_stats_label.visible = not _stats_label.text.is_empty()

	if building.required_tech != &"":
		_tech_label.text = Localization.t("UI_BUILD_REQUIRES_TECH", {"tech": str(building.required_tech)})
		_tech_label.visible = true
	else:
		_tech_label.visible = false

	global_position = _clamp_to_screen(screen_pos + Vector2(0, -size.y - 16))
	visible = true

## Скрыть тултип.
func hide_tooltip() -> void:
	visible = false

func _format_cost(building: BuildingData) -> String:
	if building.cost.size() > 0:
		var lines: Array[String] = [Localization.t("UI_BUILD_COST")]
		for entry: Dictionary in building.cost:
			var item_id: String = str(entry.get("item_id", ""))
			var amount: int = int(entry.get("amount", 0))
			var item: ItemData = ItemRegistry.get_item(item_id)
			var item_name: String = item.get_display_name() if item else item_id
			lines.append("  %s x%d" % [item_name, amount])
		return "\n".join(lines)
	elif building.scrap_cost > 0:
		return Localization.t("UI_BUILD_COST_SCRAP", {"amount": building.scrap_cost})
	return ""

func _format_stats(building: BuildingData) -> String:
	var parts: Array[String] = []
	if building.size_x > 1 or building.size_y > 1:
		parts.append(Localization.t("UI_BUILD_SIZE", {"w": building.size_x, "h": building.size_y}))
	if building.power_production > 0:
		parts.append(Localization.t("UI_BUILD_POWER_PROD", {"watts": building.power_production}))
	elif building.power_consumption > 0:
		parts.append(Localization.t("UI_BUILD_POWER_CONS", {"watts": building.power_consumption}))
	return "\n".join(parts)

func _clamp_to_screen(pos: Vector2) -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	pos.x = clampf(pos.x, 0, vp.x - size.x - 8)
	pos.y = clampf(pos.y, 8, vp.y - size.y - 8)
	return pos
