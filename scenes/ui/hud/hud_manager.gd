class_name HudManager
extends Control

## Менеджер HUD. Размещает виджеты по зонам экрана.
## Добавить новый виджет = создать экземпляр + добавить в зону.

# --- Зоны экрана ---
var _top_left: VBoxContainer = null
var _top_right: VBoxContainer = null
var _bottom_left: VBoxContainer = null
var _bottom_center: HBoxContainer = null
var _alerts: VBoxContainer = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_create_zones()
	_create_widgets()

# --- Зоны ---

func _create_zones() -> void:
	# Top-left: O₂, HP, статус, скрап
	_top_left = VBoxContainer.new()
	_top_left.position = Vector2(12, 12)
	_top_left.add_theme_constant_override("separation", 4)
	_top_left.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_top_left)

	# Top-right: время, день, этаж
	_top_right = VBoxContainer.new()
	_top_right.anchor_left = 1.0
	_top_right.anchor_right = 1.0
	_top_right.position = Vector2(-160, 12)
	_top_right.add_theme_constant_override("separation", 4)
	_top_right.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_top_right)

	# Bottom-left: подсказки
	_bottom_left = VBoxContainer.new()
	_bottom_left.anchor_top = 1.0
	_bottom_left.anchor_bottom = 1.0
	_bottom_left.position = Vector2(12, -40)
	_bottom_left.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_bottom_left)

	# Bottom-center: quickbar (будущее)
	_bottom_center = HBoxContainer.new()
	_bottom_center.anchor_top = 1.0
	_bottom_center.anchor_bottom = 1.0
	_bottom_center.anchor_left = 0.5
	_bottom_center.anchor_right = 0.5
	_bottom_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom_center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_bottom_center)

	# Center-right: предупреждения (будущее)
	_alerts = VBoxContainer.new()
	_alerts.anchor_left = 1.0
	_alerts.anchor_right = 1.0
	_alerts.anchor_top = 0.5
	_alerts.position = Vector2(-180, 0)
	_alerts.add_theme_constant_override("separation", 4)
	_alerts.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_alerts)

# --- Виджеты ---

func _create_widgets() -> void:
	# === РЕАЛИЗОВАНО (механики есть) ===
	_top_left.add_child(HudOxygenWidget.new())
	_top_left.add_child(HudHpWidget.new())
	_top_left.add_child(HudStatusWidget.new())
	_top_right.add_child(HudTimeWidget.new())
	_top_right.add_child(HudFloorWidget.new())
	_bottom_left.add_child(HudHintsWidget.new())

	# === ЗАГЛУШКИ (раскомментировать когда появится механика) ===
	# _top_left.add_child(HudHungerWidget.new())       # Этап 5.1
	# _top_left.add_child(HudThirstWidget.new())       # Этап 5.1
	# _top_left.add_child(HudStaminaWidget.new())      # когда спринт
	# _alerts.add_child(HudTemperatureAlert.new())     # Этап 5.4
	# _alerts.add_child(HudToxicityAlert.new())        # Этап 5.5
	# _bottom_center.add_child(HudQuickbar.new())      # Этап 8.2
