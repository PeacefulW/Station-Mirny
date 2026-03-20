class_name InventoryPanel
extends Control

## Панель инвентаря и экипировки.
## Tab — открыть/закрыть. Слева сетка рюкзака, справа слоты экипировки.

const GRID_COLS: int = 5

var _is_open: bool = false
var _inventory: InventoryComponent = null
var _equipment: EquipmentComponent = null

var _dimmer: ColorRect = null
var _panel: DraggablePanel = null
var _grid: GridContainer = null
var _equip_container: VBoxContainer = null
var _slot_nodes: Array[InventorySlotUI] = []
var _equip_slots: Dictionary = {}
var _weight_label: Label = null
var _title_label: Label = null
var _equip_title_label: Label = null
var _hint_label: Label = null
var _tooltip: ItemTooltip = null
var _crafting_panel: CraftPanel = null
var _crafting_system: CraftingSystem = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	add_to_group("closeable_ui")
	_build_ui()
	EventBus.inventory_updated.connect(_on_inventory_updated)
	EventBus.language_changed.connect(_on_language_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()
		get_viewport().set_input_as_handled()

## Передать ссылки на компоненты данных.
func setup(inventory: InventoryComponent, equipment: EquipmentComponent) -> void:
	_inventory = inventory
	_equipment = equipment

func toggle() -> void:
	_is_open = not _is_open
	visible = _is_open
	if _is_open:
		_find_components()
		_refresh()
		_center_panel_if_needed()

func close() -> void:
	_is_open = false
	visible = false
	if _tooltip:
		_tooltip.hide_tooltip()

# --- Построение UI ---

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	_dimmer = _DropDimmer.new()
	_dimmer.set_anchors_preset(PRESET_FULL_RECT)
	_dimmer.color = Color(0.0, 0.0, 0.0, 0.4)
	_dimmer.mouse_filter = MOUSE_FILTER_STOP
	_dimmer.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and not _dimmer.is_dropping:
			close()
	)
	_dimmer.item_dropped_outside.connect(_on_drop_outside)
	add_child(_dimmer)

	_panel = DraggablePanel.new()
	_panel.panel_id = "inventory"
	_panel.set_header_height(36.0)
	_panel.custom_minimum_size = Vector2(520, 380)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.07, 0.96)
	style.border_color = Color(0.28, 0.26, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)

	# Заголовок + вес
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 28
	var drag_hint := Label.new()
	drag_hint.text = ":::  "
	drag_hint.add_theme_font_size_override("font_size", 14)
	drag_hint.add_theme_color_override("font_color", Color(0.35, 0.33, 0.28))
	header.add_child(drag_hint)
	_title_label = Label.new()
	_title_label.text = Localization.t("UI_INVENTORY_TITLE")
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
	_title_label.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(_title_label)
	_weight_label = Label.new()
	_weight_label.add_theme_font_size_override("font_size", 12)
	_weight_label.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
	header.add_child(_weight_label)

	var sort_btn := Button.new()
	sort_btn.text = Localization.t("UI_INVENTORY_SORT")
	sort_btn.add_theme_font_size_override("font_size", 11)
	sort_btn.custom_minimum_size = Vector2(60, 0)
	sort_btn.pressed.connect(_sort_inventory)
	header.add_child(sort_btn)

	root.add_child(header)

	# Контент: инвентарь + экипировка
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_vertical = SIZE_EXPAND_FILL

	# Левая часть — сетка + крафт
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	left.add_child(_grid)

	_crafting_panel = CraftPanel.new()
	left.add_child(_crafting_panel)
	content.add_child(left)

	# Разделитель
	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	content.add_child(sep)

	# Правая часть — экипировка
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 120
	right.add_theme_constant_override("separation", 4)
	_equip_title_label = Label.new()
	_equip_title_label.text = Localization.t("UI_EQUIPMENT_TITLE")
	_equip_title_label.add_theme_font_size_override("font_size", 13)
	_equip_title_label.add_theme_color_override("font_color", Color(0.7, 0.68, 0.58))
	_equip_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(_equip_title_label)

	_equip_container = VBoxContainer.new()
	_equip_container.add_theme_constant_override("separation", 3)
	_build_equip_slots()
	right.add_child(_equip_container)
	content.add_child(right)

	root.add_child(content)

	# Подсказка внизу
	_hint_label = Label.new()
	_hint_label.text = Localization.t("UI_INVENTORY_HINT")
	_hint_label.add_theme_font_size_override("font_size", 10)
	_hint_label.add_theme_color_override("font_color", Color(0.35, 0.33, 0.28))
	root.add_child(_hint_label)

	_panel.add_child(root)

	# Тултип (поверх всего)
	_tooltip = ItemTooltip.new()
	add_child(_tooltip)

	_create_slot_nodes(20)

func _build_equip_slots() -> void:
	for slot_value: int in EquipmentSlotType.Slot.values():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var equip_ui := EquipSlotUI.new()
		equip_ui.setup_slot(slot_value)
		equip_ui.equip_clicked.connect(_on_equip_clicked)
		equip_ui.equip_hovered.connect(_on_equip_hovered)
		equip_ui.equip_unhovered.connect(_on_slot_unhovered)
		row.add_child(equip_ui)

		var name_label := Label.new()
		name_label.text = equip_ui.get_slot_name()
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.add_theme_color_override("font_color", Color(0.4, 0.42, 0.48))
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)

		_equip_container.add_child(row)
		_equip_slots[slot_value] = equip_ui

func _create_slot_nodes(count: int) -> void:
	for child: Node in _grid.get_children():
		child.queue_free()
	_slot_nodes.clear()
	for i: int in range(count):
		var slot_ui := InventorySlotUI.new()
		slot_ui.slot_index = i
		slot_ui.slot_clicked.connect(_on_slot_clicked)
		slot_ui.slot_dropped.connect(_on_slot_dropped)
		slot_ui.slot_hovered.connect(_on_slot_hovered)
		slot_ui.slot_unhovered.connect(_on_slot_unhovered)
		_grid.add_child(slot_ui)
		_slot_nodes.append(slot_ui)

# --- Обновление ---

func _refresh() -> void:
	if not _inventory:
		return
	if _slot_nodes.size() != _inventory.capacity:
		_create_slot_nodes(_inventory.capacity)

	var total_weight: float = 0.0
	for i: int in range(_slot_nodes.size()):
		if i >= _inventory.slots.size():
			_slot_nodes[i].set_slot_data(null, 0)
			continue
		var slot: InventorySlot = _inventory.slots[i]
		if slot.is_empty():
			_slot_nodes[i].set_slot_data(null, 0)
		else:
			_slot_nodes[i].set_slot_data(slot.item, slot.amount)
			total_weight += slot.item.weight * slot.amount

	_weight_label.text = Localization.t("UI_INVENTORY_WEIGHT", {"weight": "%.1f" % total_weight})

	# Обновить экипировку
	if _equipment:
		for slot_type: int in _equip_slots:
			var equip_ui: EquipSlotUI = _equip_slots[slot_type]
			equip_ui.set_equipped_item(_equipment.get_equipped(slot_type))

	if _crafting_panel:
		_crafting_panel.setup_inventory(_inventory)
		_crafting_panel.open(_crafting_panel._station_type, _inventory)

# --- Обработка кликов ---

func _on_slot_clicked(slot_index: int, button: int) -> void:
	if not _inventory:
		return
	if button == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT):
		_split_stack(slot_index)
	elif button == MOUSE_BUTTON_RIGHT:
		_try_equip_from_inventory(slot_index)

## Обмен предметов между двумя слотами (drag-drop).
func _on_slot_dropped(from_index: int, to_index: int) -> void:
	if not _inventory:
		return
	if from_index < 0 or from_index >= _inventory.slots.size():
		return
	if to_index < 0 or to_index >= _inventory.slots.size():
		return
	var slot_a: InventorySlot = _inventory.slots[from_index]
	var slot_b: InventorySlot = _inventory.slots[to_index]
	# Если одинаковый предмет — объединить стаки
	if not slot_a.is_empty() and not slot_b.is_empty() and slot_a.item.id == slot_b.item.id:
		var space: int = slot_b.item.max_stack - slot_b.amount
		var transfer: int = mini(space, slot_a.amount)
		slot_b.amount += transfer
		slot_a.amount -= transfer
		if slot_a.amount <= 0:
			slot_a.clear()
	else:
		# Swap
		var tmp_item: ItemData = slot_a.item
		var tmp_amount: int = slot_a.amount
		slot_a.item = slot_b.item
		slot_a.amount = slot_b.amount
		slot_b.item = tmp_item
		slot_b.amount = tmp_amount
	EventBus.inventory_updated.emit(_inventory)

func _on_equip_clicked(slot_type: int) -> void:
	if not _equipment or not _inventory:
		return
	var item: ItemData = _equipment.unequip(slot_type)
	if item:
		_inventory.add_item(item, 1)
	_refresh()

func _split_stack(slot_index: int) -> void:
	if not _inventory or slot_index >= _inventory.slots.size():
		return
	var slot: InventorySlot = _inventory.slots[slot_index]
	if slot.is_empty() or slot.amount <= 1:
		return
	var half: int = slot.amount / 2
	slot.amount -= half
	_inventory.add_item(slot.item, half)
	EventBus.inventory_updated.emit(_inventory)

func _try_equip_from_inventory(slot_index: int) -> void:
	if not _inventory or not _equipment or slot_index >= _inventory.slots.size():
		return
	var slot: InventorySlot = _inventory.slots[slot_index]
	if slot.is_empty() or slot.item.equipment_slot < 0:
		return
	var equip_slot: int = slot.item.equipment_slot
	if not _equipment.can_equip(equip_slot, slot.item):
		return
	var previous: ItemData = _equipment.equip(equip_slot, slot.item)
	slot.clear()
	if previous:
		_inventory.add_item(previous, 1)
	EventBus.inventory_updated.emit(_inventory)

# --- Тултипы ---

func _on_slot_hovered(slot_index: int) -> void:
	if not _inventory or not _tooltip or slot_index >= _inventory.slots.size():
		return
	var slot: InventorySlot = _inventory.slots[slot_index]
	if slot.is_empty():
		_tooltip.hide_tooltip()
		return
	_tooltip.show_item(slot.item, get_global_mouse_position())

func _on_equip_hovered(slot_type: int) -> void:
	if not _tooltip:
		return
	if _equipment:
		var item: ItemData = _equipment.get_equipped(slot_type)
		if item:
			_tooltip.show_item(item, get_global_mouse_position())
			return
	var equip_ui: EquipSlotUI = _equip_slots.get(slot_type) as EquipSlotUI
	if equip_ui:
		_tooltip.show_equip_slot(equip_ui.get_slot_name(), get_global_mouse_position())

func _on_slot_unhovered() -> void:
	if _tooltip:
		_tooltip.hide_tooltip()

# --- Утилиты ---

func _find_components() -> void:
	if _inventory and _equipment:
		return
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node = players[0]
	if not _inventory and player.has_method("get_inventory"):
		_inventory = player.get_inventory()
	if not _equipment:
		_equipment = player.get_node_or_null("EquipmentComponent") as EquipmentComponent
	if not _crafting_system:
		var systems: Array[Node] = get_tree().get_nodes_in_group("crafting_system")
		if not systems.is_empty():
			_crafting_system = systems[0] as CraftingSystem

func _on_inventory_updated(_inv_node: Node) -> void:
	if _is_open:
		_refresh()

func _on_language_changed(_locale: String) -> void:
	if _title_label:
		_title_label.text = Localization.t("UI_INVENTORY_TITLE")
	if _equip_title_label:
		_equip_title_label.text = Localization.t("UI_EQUIPMENT_TITLE")
	if _hint_label:
		_hint_label.text = Localization.t("UI_INVENTORY_HINT")
	if _is_open:
		_refresh()

func _center_panel_if_needed() -> void:
	if not _panel:
		return
	if _panel.position == Vector2.ZERO or _panel.position.x < 1:
		var vp: Vector2 = get_viewport_rect().size
		_panel.position = (vp - _panel.size) * 0.5

## Сортировка инвентаря по имени предмета (A→Z).
func _sort_inventory() -> void:
	if not _inventory:
		return
	# Собрать непустые слоты
	var items: Array[Dictionary] = []
	for slot: InventorySlot in _inventory.slots:
		if not slot.is_empty():
			items.append({"item": slot.item, "amount": slot.amount})
		slot.clear()
	# Сортировка по имени
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["item"] as ItemData).get_display_name() < (b["item"] as ItemData).get_display_name()
	)
	# Положить обратно
	var idx: int = 0
	for entry: Dictionary in items:
		if idx < _inventory.slots.size():
			_inventory.slots[idx].item = entry["item"]
			_inventory.slots[idx].amount = entry["amount"]
			idx += 1
	EventBus.inventory_updated.emit(_inventory)

## Выбросить предмет на землю (drop за пределы панели).
func _on_drop_outside(from_index: int) -> void:
	if not _inventory or from_index < 0 or from_index >= _inventory.slots.size():
		return
	var slot: InventorySlot = _inventory.slots[from_index]
	if slot.is_empty():
		return
	var item_id: String = slot.item.id
	var amount: int = slot.amount
	slot.clear()
	EventBus.inventory_updated.emit(_inventory)
	EventBus.item_dropped.emit(item_id, amount, Vector2.ZERO)

# --- Внутренний класс: dimmer с поддержкой drop ---

class _DropDimmer extends ColorRect:
	signal item_dropped_outside(from_index: int)
	var is_dropping: bool = false

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		if data is Dictionary and data.get("source") == "inventory":
			return true
		return false

	func _drop_data(_position: Vector2, data: Variant) -> void:
		if data is Dictionary and data.get("source") == "inventory":
			is_dropping = true
			item_dropped_outside.emit(int(data.get("slot_index", -1)))
			# Сбросить флаг на следующем кадре (не триггерить close)
			(func() -> void: is_dropping = false).call_deferred()
