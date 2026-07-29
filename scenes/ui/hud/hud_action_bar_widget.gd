class_name HudActionBarWidget
extends HudWidget
## Нижняя панель действий: что можно нажать прямо сейчас.
## Показывается на старте и в режимах, затем уходит. Постоянный список клавиш
## превратил бы HUD в шпаргалку и заглушил бы тревожные состояния сверху.

const DEFAULT_VISIBLE_SECONDS: float = 8.0
const SLOT_MIN_WIDTH: float = 88.0

const DEFAULT_ACTIONS: Array[Dictionary] = [
	{"icon": HudIcons.Id.MOVE, "key": "UI_KEY_WASD", "caption": "UI_ACTION_MOVE"},
	{"icon": HudIcons.Id.INTERACT, "key": "UI_KEY_E", "caption": "UI_ACTION_INTERACT"},
	{"icon": HudIcons.Id.PACK, "key": "UI_KEY_TAB", "caption": "UI_ACTION_INVENTORY"},
	{"icon": HudIcons.Id.HAMMER, "key": "UI_KEY_B", "caption": "UI_ACTION_BUILD"},
	{"icon": HudIcons.Id.STRIKE, "key": "UI_KEY_SPACE", "caption": "UI_ACTION_ATTACK"},
	{"icon": HudIcons.Id.BOLT, "key": "UI_KEY_P", "caption": "UI_ACTION_POWER"},
]

const BUILD_ACTIONS: Array[Dictionary] = [
	{"icon": HudIcons.Id.PLACE, "key": "UI_KEY_LMB", "caption": "UI_ACTION_PLACE"},
	{"icon": HudIcons.Id.REMOVE, "key": "UI_KEY_RMB", "caption": "UI_ACTION_REMOVE"},
	{"icon": HudIcons.Id.EXIT, "key": "UI_KEY_B", "caption": "UI_ACTION_EXIT_BUILD"},
]

var _row: HBoxContainer = null
var _slots: Array[HudActionSlot] = []
var _hide_timer: Timer = null
var _fade_tween: Tween = null
var _is_build_mode: bool = false


func _setup() -> void:
	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 8)
	_row.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_row)

	var pool_size: int = maxi(DEFAULT_ACTIONS.size(), BUILD_ACTIONS.size())
	for _index: int in range(pool_size):
		var slot: HudActionSlot = HudActionSlot.new()
		slot.custom_minimum_size.x = SLOT_MIN_WIDTH
		slot.visible = false
		_row.add_child(slot)
		_slots.append(slot)

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(_hide_bar)
	add_child(_hide_timer)

	_apply_actions(DEFAULT_ACTIONS)
	_show_bar(DEFAULT_VISIBLE_SECONDS)
	EventBus.build_mode_changed.connect(_on_build_mode_changed)
	EventBus.language_changed.connect(_on_language_changed)


func _on_build_mode_changed(is_active: bool) -> void:
	_is_build_mode = is_active
	if not is_active:
		_hide_bar()
		return
	_apply_actions(BUILD_ACTIONS)
	_show_bar(0.0)


func _on_language_changed(_locale: String) -> void:
	for slot: HudActionSlot in _slots:
		if slot.visible:
			slot.refresh_text()


func _apply_actions(actions: Array[Dictionary]) -> void:
	for index: int in range(_slots.size()):
		var slot: HudActionSlot = _slots[index]
		if index >= actions.size():
			slot.visible = false
			continue
		var action: Dictionary = actions[index]
		slot.configure(
			action["icon"] as HudIcons.Id,
			String(action["key"]),
			String(action["caption"]),
		)
		slot.visible = true


func _show_bar(duration_seconds: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	visible = true
	modulate.a = 1.0
	if _hide_timer == null:
		return
	_hide_timer.stop()
	if duration_seconds > 0.0:
		_hide_timer.start(duration_seconds)


func _hide_bar() -> void:
	if _hide_timer != null:
		_hide_timer.stop()
	if not visible:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	await _fade_tween.finished
	visible = false
	modulate.a = 1.0
