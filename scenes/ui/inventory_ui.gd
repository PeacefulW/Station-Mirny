class_name InventoryUI
extends Control

## UI инвентаря v2. Перетаскиваемая панель.
## Tab — открыть/закрыть. Тащи за заголовок.

const COLS: int = 5
const SLOT_SIZE: int = 56
const SLOT_GAP: int = 4

var _is_open: bool = false
var _panel: DraggablePanel = null
var _grid: GridContainer = null
var _slot_nodes: Array[Control] = []
var _title_label: Label = null
var _weight_label: Label = null
var _inventory: InventoryComponent = null
var _dimmer: ColorRect = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()
	EventBus.inventory_updated.connect(_on_inventory_updated)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	_is_open = not _is_open
	visible = _is_open
	if _is_open:
		_find_inventory()
		_refresh()

func close() -> void:
	_is_open = false
	visible = false

func _build_ui() -> void:
	# Затемнение
	_dimmer = ColorRect.new()
	_dimmer.set_anchors_preset(PRESET_FULL_RECT)
	_dimmer.color = Color(0.0, 0.0, 0.0, 0.35)
	_dimmer.mouse_filter = MOUSE_FILTER_STOP
	_dimmer.gui_input.connect(_on_dimmer_click)
	add_child(_dimmer)

	# Перетаскиваемая панель
	_panel = DraggablePanel.new()
	_panel.panel_id = "inventory"
	_panel.set_header_height(36.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.09, 0.95)
	style.border_color = Color(0.30, 0.28, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# Заголовок (зона перетаскивания)
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 24

	var drag_hint := Label.new()
	drag_hint.text = ":::  "
	drag_hint.add_theme_font_size_override("font_size", 14)
	drag_hint.add_theme_color_override("font_color", Color(0.35, 0.33, 0.28))
	header.add_child(drag_hint)

	_title_label = Label.new()
	_title_label.text = "ИНВЕНТАРЬ"
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
	_title_label.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_weight_label = Label.new()
	_weight_label.text = "0.0 кг"
	_weight_label.add_theme_font_size_override("font_size", 13)
	_weight_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
	header.add_child(_weight_label)
	vbox.add_child(header)

	# Разделитель
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.25, 0.24, 0.20))
	vbox.add_child(sep)

	# Сетка слотов
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", SLOT_GAP)
	_grid.add_theme_constant_override("v_separation", SLOT_GAP)
	vbox.add_child(_grid)

	# Подсказка внизу
	var hint := Label.new()
	hint.text = "Tab — закрыть  |  Тащи за ::: чтобы двигать"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.35, 0.33, 0.28))
	vbox.add_child(hint)

	_panel.add_child(vbox)
	_create_slot_nodes(20)

	# Центрируем если нет сохранённой позиции
	call_deferred("_center_if_needed")

func _center_if_needed() -> void:
	if _panel.position == Vector2.ZERO or _panel.position.x < 1:
		var vp: Vector2 = get_viewport_rect().size
		_panel.position = (vp - _panel.size) * 0.5

func _on_dimmer_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()

# --- Слоты ---

func _create_slot_nodes(count: int) -> void:
	for child: Node in _grid.get_children():
		child.queue_free()
	_slot_nodes.clear()
	for i: int in range(count):
		var slot_node := _create_single_slot()
		_grid.add_child(slot_node)
		_slot_nodes.append(slot_node)

func _create_single_slot() -> PanelContainer:
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	container.mouse_filter = MOUSE_FILTER_PASS

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.16, 0.13)
	bg.border_color = Color(0.25, 0.24, 0.20)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	container.add_theme_stylebox_override("panel", bg)

	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(48, 48)
	icon_rect.mouse_filter = MOUSE_FILTER_IGNORE
	container.add_child(icon_rect)

	var color_bg := ColorRect.new()
	color_bg.name = "ColorBG"
	color_bg.custom_minimum_size = Vector2(28, 28)
	color_bg.set_anchors_preset(PRESET_CENTER)
	color_bg.grow_horizontal = GROW_DIRECTION_BOTH
	color_bg.grow_vertical = GROW_DIRECTION_BOTH
	color_bg.visible = false
	color_bg.mouse_filter = MOUSE_FILTER_IGNORE
	container.add_child(color_bg)

	var amount_label := Label.new()
	amount_label.name = "Amount"
	amount_label.text = ""
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	amount_label.set_anchors_preset(PRESET_FULL_RECT)
	amount_label.add_theme_font_size_override("font_size", 12)
	amount_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
	amount_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	amount_label.add_theme_constant_override("shadow_offset_x", 1)
	amount_label.add_theme_constant_override("shadow_offset_y", 1)
	amount_label.mouse_filter = MOUSE_FILTER_IGNORE
	container.add_child(amount_label)

	return container

# --- Обновление ---

func _find_inventory() -> void:
	if _inventory:
		return
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node = players[0]
	if player.has_method("get_inventory"):
		_inventory = player.get_inventory()
		if _inventory and _slot_nodes.size() != _inventory.capacity:
			_create_slot_nodes(_inventory.capacity)

func _on_inventory_updated(_inv_node: Node) -> void:
	if _is_open:
		_refresh()

func _refresh() -> void:
	if not _inventory:
		_find_inventory()
	if not _inventory:
		return
	var total_weight: float = 0.0
	for i: int in range(_slot_nodes.size()):
		var sn: PanelContainer = _slot_nodes[i]
		var icon_r: TextureRect = sn.get_node("Icon")
		var color_bg: ColorRect = sn.get_node("ColorBG")
		var amt: Label = sn.get_node("Amount")
		if i >= _inventory.slots.size():
			_clear_slot(icon_r, color_bg, amt, sn)
			continue
		var slot: InventorySlot = _inventory.slots[i]
		if slot.is_empty():
			_clear_slot(icon_r, color_bg, amt, sn)
		else:
			if slot.item.icon:
				icon_r.texture = slot.item.icon
				color_bg.visible = false
			else:
				icon_r.texture = null
				color_bg.visible = true
				color_bg.color = _get_item_color(slot.item.id)
			amt.text = str(slot.amount) if slot.amount > 1 else ""
			sn.tooltip_text = "%s\n%d / %d" % [slot.item.display_name, slot.amount, slot.item.max_stack]
			_set_style(sn, Color(0.18, 0.19, 0.15), Color(0.35, 0.33, 0.25))
			total_weight += slot.item.weight * slot.amount
	_weight_label.text = "%.1f кг" % total_weight

func _clear_slot(icon_r: TextureRect, color_bg: ColorRect, amt: Label, sn: PanelContainer) -> void:
	icon_r.texture = null
	color_bg.visible = false
	amt.text = ""
	sn.tooltip_text = "Пусто"
	_set_style(sn, Color(0.15, 0.16, 0.13), Color(0.25, 0.24, 0.20))

func _set_style(sn: PanelContainer, bg: Color, border: Color) -> void:
	var s: StyleBoxFlat = sn.get_theme_stylebox("panel") as StyleBoxFlat
	if s:
		s.bg_color = bg
		s.border_color = border

func _get_item_color(item_id: String) -> Color:
	match item_id:
		"base:iron_ore": return Color(0.55, 0.35, 0.25)
		"base:copper_ore": return Color(0.65, 0.45, 0.20)
		"base:stone": return Color(0.45, 0.43, 0.40)
		"base:wood": return Color(0.30, 0.22, 0.15)
		"base:water_dirty": return Color(0.20, 0.35, 0.55)
	return Color(0.5, 0.5, 0.5)
