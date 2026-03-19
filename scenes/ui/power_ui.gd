class_name PowerUI
extends Control

## UI энергосистемы. Показывает баланс сети и состояние генераторов.
## P — открыть/закрыть. Перетаскиваемая панель.

var _is_open: bool = false
var _panel: DraggablePanel = null
var _supply_bar: ProgressBar = null
var _supply_label: Label = null
var _status_label: Label = null
var _gen_container: VBoxContainer = null
var _gen_entries: Array[Control] = []
var _update_timer: float = 0.0

const UPDATE_INTERVAL: float = 0.5

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()
	EventBus.power_changed.connect(_on_power_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_power_ui"):
		toggle()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _is_open:
		return
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_refresh_generators()

func toggle() -> void:
	_is_open = not _is_open
	visible = _is_open
	if _is_open:
		_refresh_generators()

func close() -> void:
	_is_open = false
	visible = false

# --- UI ---

func _build_ui() -> void:
	_panel = DraggablePanel.new()
	_panel.panel_id = "power_ui"
	_panel.set_header_height(32.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	style.border_color = Color(0.20, 0.25, 0.40)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# Заголовок
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 22

	var drag := Label.new()
	drag.text = ":::  "
	drag.add_theme_font_size_override("font_size", 14)
	drag.add_theme_color_override("font_color", Color(0.30, 0.35, 0.50))
	header.add_child(drag)

	var icon := Label.new()
	icon.text = "⚡ ЭНЕРГОСЕТЬ"
	icon.add_theme_font_size_override("font_size", 15)
	icon.add_theme_color_override("font_color", Color(0.90, 0.85, 0.40))
	icon.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(icon)

	_status_label = Label.new()
	_status_label.text = "ОК"
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	header.add_child(_status_label)
	vbox.add_child(header)

	# Полоска supply/demand
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)

	_supply_bar = ProgressBar.new()
	_supply_bar.custom_minimum_size = Vector2(180, 16)
	_supply_bar.max_value = 100.0
	_supply_bar.value = 0.0
	_supply_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.20)
	bar_bg.set_corner_radius_all(3)
	_supply_bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.3, 0.7, 0.9)
	bar_fill.set_corner_radius_all(3)
	_supply_bar.add_theme_stylebox_override("fill", bar_fill)
	bar_row.add_child(_supply_bar)

	_supply_label = Label.new()
	_supply_label.text = "0 / 0 Вт"
	_supply_label.custom_minimum_size.x = 100
	_supply_label.add_theme_font_size_override("font_size", 13)
	_supply_label.add_theme_color_override("font_color", Color(0.70, 0.75, 0.85))
	bar_row.add_child(_supply_label)
	vbox.add_child(bar_row)

	# Разделитель
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.20, 0.22, 0.30))
	vbox.add_child(sep)

	# Заголовок списка
	var list_header := Label.new()
	list_header.text = "Генераторы:"
	list_header.add_theme_font_size_override("font_size", 12)
	list_header.add_theme_color_override("font_color", Color(0.45, 0.48, 0.58))
	vbox.add_child(list_header)

	# Контейнер для генераторов
	_gen_container = VBoxContainer.new()
	_gen_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_gen_container)

	# Подсказка
	var hint := Label.new()
	hint.text = "P — закрыть  |  E рядом — дозаправить"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.30, 0.32, 0.40))
	vbox.add_child(hint)

	_panel.add_child(vbox)
	call_deferred("_center_if_needed")

func _center_if_needed() -> void:
	if _panel.position == Vector2.ZERO or _panel.position.x < 1:
		var vp: Vector2 = get_viewport_rect().size
		_panel.position = Vector2(vp.x - 340, 80)

# --- Обновление ---

func _on_power_changed(supply: float, demand: float) -> void:
	if not _is_open:
		return
	_update_bar(supply, demand)

func _update_bar(supply: float, demand: float) -> void:
	var max_val: float = maxf(supply, demand) * 1.2
	if max_val < 10.0:
		max_val = 100.0
	_supply_bar.max_value = max_val
	_supply_bar.value = supply
	_supply_label.text = "%d / %d Вт" % [roundi(supply), roundi(demand)]

	# Цвет и статус
	var bar_fill: StyleBoxFlat = _supply_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if supply >= demand:
		if bar_fill: bar_fill.bg_color = Color(0.3, 0.7, 0.9)
		_status_label.text = "ОК"
		_status_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	elif supply > 0:
		if bar_fill: bar_fill.bg_color = Color(0.9, 0.7, 0.2)
		_status_label.text = "ДЕФИЦИТ"
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	else:
		if bar_fill: bar_fill.bg_color = Color(0.8, 0.2, 0.2)
		_status_label.text = "НЕТ СЕТИ"
		_status_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))

func _refresh_generators() -> void:
	# Очищаем старые записи
	for entry: Control in _gen_entries:
		if is_instance_valid(entry):
			entry.queue_free()
	_gen_entries.clear()

	var total_supply: float = 0.0
	var total_demand: float = 0.0

	# Сканируем источники энергии
	var sources: Array[Node] = get_tree().get_nodes_in_group("power_sources")
	for node: Node in sources:
		var ps: PowerSourceComponent = node as PowerSourceComponent
		if not ps:
			continue
		var parent: Node = ps.get_parent()
		if not parent:
			continue
		total_supply += ps.current_output
		var entry: HBoxContainer = _create_generator_entry(parent, ps)
		_gen_container.add_child(entry)
		_gen_entries.append(entry)

	# Сканируем потребителей
	var consumers: Array[Node] = get_tree().get_nodes_in_group("power_consumers")
	for node: Node in consumers:
		var pc: PowerConsumerComponent = node as PowerConsumerComponent
		if pc:
			total_demand += pc.demand

	_update_bar(total_supply, total_demand)

	# Если нет генераторов
	if _gen_entries.is_empty():
		var empty := Label.new()
		empty.text = "  Нет генераторов"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.40, 0.38, 0.45))
		_gen_container.add_child(empty)
		_gen_entries.append(empty)

func _create_generator_entry(building: Node, ps: PowerSourceComponent) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	# Статус: зелёная/красная точка
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.color = Color(0.3, 0.8, 0.3) if ps.is_enabled and ps.current_output > 0 else Color(0.6, 0.3, 0.3)
	var dot_wrap := CenterContainer.new()
	dot_wrap.custom_minimum_size = Vector2(12, 20)
	dot_wrap.add_child(dot)
	row.add_child(dot_wrap)

	# Название
	var name_label := Label.new()
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))

	# Детали по типу здания
	var detail_label := Label.new()
	detail_label.add_theme_font_size_override("font_size", 12)
	detail_label.custom_minimum_size.x = 120
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Мини-полоска (заряд/топливо)
	var mini_bar := ProgressBar.new()
	mini_bar.custom_minimum_size = Vector2(60, 10)
	mini_bar.max_value = 1.0
	mini_bar.show_percentage = false
	var mb_bg := StyleBoxFlat.new()
	mb_bg.bg_color = Color(0.15, 0.15, 0.20)
	mb_bg.set_corner_radius_all(2)
	mini_bar.add_theme_stylebox_override("background", mb_bg)
	var mb_fill := StyleBoxFlat.new()
	mb_fill.set_corner_radius_all(2)
	mini_bar.add_theme_stylebox_override("fill", mb_fill)

	# Определяем тип
	if building is ArkBattery:
		var bat: ArkBattery = building as ArkBattery
		name_label.text = "Батарея Ковчега"
		var pct: float = bat.get_charge_percent()
		mini_bar.value = pct
		mb_fill.bg_color = Color(0.3, 0.5 + 0.3 * pct, 0.8)
		detail_label.text = "%d Вт⋅ч (%.0f%%)" % [roundi(bat.charge_remaining), pct * 100]
		if pct > 0.5:
			detail_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.9))
		elif pct > 0.2:
			detail_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
		else:
			detail_label.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
	elif building.has_method("get_fuel_percent"):
		# ThermoBurner
		name_label.text = "Термосжигатель"
		var fuel_pct: float = building.get_fuel_percent()
		mini_bar.value = fuel_pct
		if fuel_pct > 0.3:
			mb_fill.bg_color = Color(0.9, 0.6, 0.2)
			detail_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
		else:
			mb_fill.bg_color = Color(0.9, 0.3, 0.2)
			detail_label.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
		var fuel_val: float = building.get("fuel_current") if building.get("fuel_current") != null else 0.0
		detail_label.text = "Топливо: %.0f (%.0f%%)" % [fuel_val, fuel_pct * 100]
		if not building.get("is_running"):
			name_label.text += " [ВЫКЛ]"
			detail_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.40))
	else:
		name_label.text = "Генератор"
		mini_bar.value = 1.0 if ps.current_output > 0 else 0.0
		mb_fill.bg_color = Color(0.5, 0.7, 0.5)
		detail_label.text = "%d Вт" % roundi(ps.current_output)
		detail_label.add_theme_color_override("font_color", Color(0.65, 0.70, 0.75))

	# Мощность
	var watt_label := Label.new()
	watt_label.text = "%dВт" % roundi(ps.current_output)
	watt_label.custom_minimum_size.x = 40
	watt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	watt_label.add_theme_font_size_override("font_size", 12)
	watt_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))

	row.add_child(name_label)
	row.add_child(mini_bar)
	row.add_child(detail_label)
	row.add_child(watt_label)

	return row
