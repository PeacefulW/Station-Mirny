class_name HudPostProcessToggle
extends Button

const LABEL_ON_KEY: String = "UI_POSTPROCESS_ON"
const LABEL_OFF_KEY: String = "UI_POSTPROCESS_OFF"

@export var overlay_path: NodePath = ^"../../PostProcessLayer/PostProcessOverlay"

var _overlay: Node = null


func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(164.0, 32.0)
	toggled.connect(_on_toggled)
	var event_bus: Node = get_node_or_null("/root/EventBus")
	if event_bus != null and event_bus.has_signal("language_changed"):
		var callback := Callable(self, "_on_language_changed")
		if not event_bus.is_connected("language_changed", callback):
			event_bus.connect("language_changed", callback)
	_sync_from_overlay()
	call_deferred("_sync_from_overlay")


func _sync_from_overlay() -> void:
	var overlay: Node = _resolve_overlay()
	var enabled: bool = true
	if overlay != null and overlay.has_method("get_postprocess_enabled"):
		enabled = bool(overlay.call("get_postprocess_enabled"))
	set_pressed_no_signal(enabled)
	_refresh_label(enabled)


func _resolve_overlay() -> Node:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	_overlay = get_node_or_null(overlay_path)
	if _overlay != null and _overlay.has_signal("postprocess_enabled_changed"):
		var callback := Callable(self, "_on_overlay_enabled_changed")
		if not _overlay.is_connected("postprocess_enabled_changed", callback):
			_overlay.connect("postprocess_enabled_changed", callback)
	return _overlay


func _on_toggled(is_pressed: bool) -> void:
	var overlay: Node = _resolve_overlay()
	if overlay != null and overlay.has_method("get_postprocess_enabled"):
		var current_enabled: bool = bool(overlay.call("get_postprocess_enabled"))
		if current_enabled != is_pressed and overlay.has_method("toggle_postprocess"):
			overlay.call("toggle_postprocess")
		elif overlay.has_method("set_postprocess_enabled"):
			overlay.call("set_postprocess_enabled", is_pressed)
	_refresh_label(is_pressed)


func _on_overlay_enabled_changed(enabled: bool) -> void:
	set_pressed_no_signal(enabled)
	_refresh_label(enabled)


func _on_language_changed(_locale_code: String) -> void:
	_refresh_label(button_pressed)


func _refresh_label(enabled: bool) -> void:
	var key: String = LABEL_ON_KEY if enabled else LABEL_OFF_KEY
	var localization: Node = get_node_or_null("/root/Localization")
	text = str(localization.call("t", key)) if localization != null and localization.has_method("t") else key
