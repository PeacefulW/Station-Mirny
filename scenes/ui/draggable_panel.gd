class_name DraggablePanel
extends PanelContainer

## Перетаскиваемая панель. Тащишь за заголовок — окно двигается.
## Позиция сохраняется между сеансами в user://ui_layout.cfg.

# --- Сигналы ---
signal drag_started()
signal drag_ended()

# --- Экспортируемые ---
@export var panel_id: String = "default"
@export var save_position: bool = true

# --- Приватные ---
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _header_rect: Rect2 = Rect2()
var _header_height: float = 32.0

const SAVE_PATH: String = "user://ui_layout.cfg"

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	if save_position:
		_load_position()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Проверяем что клик в зоне заголовка
				if mb.position.y <= _header_height:
					_dragging = true
					_drag_offset = mb.position
					drag_started.emit()
			else:
				if _dragging:
					_dragging = false
					drag_ended.emit()
					if save_position:
						_save_position()
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		position += mm.relative
		# Не даём утащить за пределы экрана
		var vp: Vector2 = get_viewport_rect().size
		position.x = clampf(position.x, 0, vp.x - size.x)
		position.y = clampf(position.y, 0, vp.y - size.y)

## Задать высоту зоны перетаскивания.
func set_header_height(h: float) -> void:
	_header_height = h

func _save_position() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("panels", panel_id + "_x", position.x)
	cfg.set_value("panels", panel_id + "_y", position.y)
	cfg.save(SAVE_PATH)

func _load_position() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var x: float = cfg.get_value("panels", panel_id + "_x", -1.0)
	var y: float = cfg.get_value("panels", panel_id + "_y", -1.0)
	if x >= 0 and y >= 0:
		position = Vector2(x, y)
