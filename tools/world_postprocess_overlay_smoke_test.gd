extends SceneTree

var _failed: bool = false


func _init() -> void:
	var scene_source: String = FileAccess.get_file_as_string("res://scenes/world/world_runtime_v0.tscn")
	var runtime_source: String = FileAccess.get_file_as_string("res://scenes/world/world_runtime_v0_scene.gd")
	var overlay_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_postprocess_overlay.gd")
	var toggle_source: String = FileAccess.get_file_as_string("res://scenes/ui/hud/hud_postprocess_toggle.gd")
	var shader_source: String = FileAccess.get_file_as_string("res://assets/shaders/world_postprocess_overlay.gdshader")
	var ru_locale: String = FileAccess.get_file_as_string("res://locale/ru/messages.po")
	var en_locale: String = FileAccess.get_file_as_string("res://locale/en/messages.po")

	_assert(
		scene_source.contains("res://core/systems/world/world_postprocess_overlay.gd"),
		"World runtime scene must preload the postprocess overlay script."
	)
	_assert(
		scene_source.contains("[node name=\"PostProcessLayer\" type=\"CanvasLayer\" parent=\".\" groups=[\"world_render_source\"]]")
				and scene_source.contains("layer = 5"),
		"Postprocess must live in its own CanvasLayer below HUD."
	)
	_assert(
		scene_source.contains("[node name=\"PostProcessOverlay\" type=\"ColorRect\" parent=\"PostProcessLayer\"]")
				and scene_source.contains("mouse_filter = 2"),
		"Postprocess overlay must be a full-screen ColorRect that ignores mouse input."
	)
	_assert(
		scene_source.contains("[node name=\"HudLayer\" type=\"CanvasLayer\" parent=\".\"]")
				and scene_source.contains("layer = 10"),
		"HUD CanvasLayer must stay above postprocess so UI is not color-graded."
	)
	_assert(
		runtime_source.contains("toggle_postprocess()"),
		"WorldRuntimeV0Scene must keep a keyboard toggle hook for postprocess A/B checks."
	)
	_assert(
		overlay_source.contains("class_name WorldPostProcessOverlay")
				and overlay_source.contains("extends ColorRect"),
		"WorldPostProcessOverlay must be a dedicated ColorRect presentation component."
	)
	_assert(
		overlay_source.contains("func set_postprocess_enabled(enabled: bool) -> void:")
				and overlay_source.contains("func toggle_postprocess() -> bool:"),
		"WorldPostProcessOverlay must expose explicit enable and toggle methods."
	)
	_assert(
		shader_source.contains("hint_screen_texture")
				and shader_source.contains("uniform bool effect_enabled = true")
				and shader_source.contains("vignette_strength")
				and shader_source.contains("warm_bloom_strength")
				and shader_source.contains("grade_strength"),
		"Postprocess shader must read the screen texture and expose restrained grade/vignette/bloom controls."
	)
	_assert(
		toggle_source.contains("class_name HudPostProcessToggle")
				and toggle_source.contains("UI_POSTPROCESS_ON")
				and toggle_source.contains("UI_POSTPROCESS_OFF")
				and toggle_source.contains("toggle_postprocess"),
		"HUD toggle must localize its labels and call the overlay toggle surface."
	)
	_assert(
		ru_locale.contains("UI_POSTPROCESS_ON")
				and ru_locale.contains("UI_POSTPROCESS_OFF")
				and en_locale.contains("UI_POSTPROCESS_ON")
				and en_locale.contains("UI_POSTPROCESS_OFF"),
		"Postprocess toggle labels must exist in RU and EN locale files."
	)
	_assert_loads_and_instantiates()

	if _failed:
		quit(1)
		return
	print("world_postprocess_overlay_smoke_test: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true


func _assert_loads_and_instantiates() -> void:
	var shader: Resource = load("res://assets/shaders/world_postprocess_overlay.gdshader")
	_assert(shader is Shader, "Postprocess shader must load as a Shader resource.")
	var overlay_script: Resource = load("res://core/systems/world/world_postprocess_overlay.gd")
	_assert(overlay_script is Script, "WorldPostProcessOverlay script must compile.")
	var toggle_script: Resource = load("res://scenes/ui/hud/hud_postprocess_toggle.gd")
	_assert(toggle_script is Script, "HudPostProcessToggle script must compile.")
	if overlay_script is Script:
		var overlay_instance: Object = (overlay_script as Script).new()
		_assert(overlay_instance is ColorRect, "WorldPostProcessOverlay must instantiate as a ColorRect.")
		_assert(overlay_instance.has_method("toggle_postprocess"), "WorldPostProcessOverlay instance must expose toggle_postprocess().")
		if overlay_instance is Node:
			var overlay_node: Node = overlay_instance as Node
			get_root().add_child(overlay_node)
			overlay_node.call("set_postprocess_enabled", false)
			_assert(not overlay_node.visible, "Disabled postprocess overlay must skip its fullscreen pass.")
			overlay_node.call("set_postprocess_enabled", true)
			_assert(overlay_node.visible, "Enabled postprocess overlay must restore its fullscreen pass.")
			overlay_node.queue_free()
			var render_target := SubViewport.new()
			render_target.size = Vector2i(1792, 1008)
			get_root().add_child(render_target)
			var postprocess_layer := CanvasLayer.new()
			postprocess_layer.custom_viewport = render_target
			get_root().add_child(postprocess_layer)
			var resized_overlay: ColorRect = (overlay_script as Script).new() as ColorRect
			postprocess_layer.add_child(resized_overlay)
			resized_overlay.call("sync_render_target_rect")
			_assert(
				resized_overlay.position == Vector2.ZERO
						and resized_overlay.size == Vector2(1792.0, 1008.0),
				"Postprocess overlay must cover its routed render target after resize.",
			)
			postprocess_layer.queue_free()
			render_target.queue_free()
	if toggle_script is Script:
		var toggle_instance: Object = (toggle_script as Script).new()
		_assert(toggle_instance is Button, "HudPostProcessToggle must instantiate as a Button.")
		toggle_instance.free()
