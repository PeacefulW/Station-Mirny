class_name PlayerPopup
extends RefCounted

## Всплывающие текстовые подсказки над игроком.

## Всплывающий текст "+3 Железная руда" при добыче.
static func spawn_harvest(parent: Node2D, item_id: String, amount: int, balance: PlayerBalance) -> void:
	var item_data: ItemData = ItemRegistry.get_item(item_id)
	var display_name: String = item_data.get_display_name() if item_data else item_id
	var popup := Label.new()
	popup.text = Localization.t("UI_PICKUP_POPUP", {
		"amount": amount,
		"item": display_name,
	})
	popup.add_theme_font_size_override("font_size", 14)
	popup.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	popup.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	popup.add_theme_constant_override("shadow_offset_x", 1)
	popup.add_theme_constant_override("shadow_offset_y", 1)
	popup.position = Vector2(-40, -50)
	popup.z_index = 100
	parent.add_child(popup)
	var tween: Tween = parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		popup,
		"position:y",
		popup.position.y - balance.harvest_popup_rise_distance,
		balance.harvest_popup_duration
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, balance.harvest_popup_duration).set_delay(
		balance.harvest_popup_fade_delay
	)
	tween.chain().tween_callback(popup.queue_free)

## Контекстный попап (дозаправка и т.п.).
static func spawn_context(parent: Node2D, text: String, color: Color) -> void:
	var popup := Label.new()
	popup.text = text
	popup.add_theme_font_size_override("font_size", 13)
	popup.add_theme_color_override("font_color", color)
	popup.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	popup.add_theme_constant_override("shadow_offset_x", 1)
	popup.add_theme_constant_override("shadow_offset_y", 1)
	popup.position = Vector2(-48, -68)
	popup.z_index = 100
	parent.add_child(popup)
	var tween: Tween = parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 28.0, 0.7).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.7).set_delay(0.15)
	tween.chain().tween_callback(popup.queue_free)
