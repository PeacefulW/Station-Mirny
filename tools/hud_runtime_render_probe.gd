extends SceneTree
## Рендер-проба игрового HUD на настоящей mountain runtime dev-сцене.
## Проверяет production-композицию, скрытый по умолчанию dev overlay и
## отсутствие интерактивной postprocess-кнопки в игровом слое.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const OUTPUT_PATH: String = "res://artifacts/hud_runtime/hud_runtime.png"
const MAX_READY_FRAMES: int = 3000
const PRESENTATION_SETTLE_FRAMES: int = 120

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("hud_runtime_render_probe must run windowed.")
		quit(1)
		return
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("artifacts/hud_runtime")
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "HUD runtime scene must load.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)

	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if bool(snapshot.get("failed", false)) or bool(snapshot.get("ready", false)):
			break
	_assert(
		bool(snapshot.get("ready", false)),
		"HUD runtime scene must become ready: %s" % str(snapshot.get("fail_reason", "")),
	)

	var dev_hud: CanvasLayer = scene.get_node_or_null("DevHud") as CanvasLayer
	_assert(dev_hud != null, "Dev HUD node must remain available for F1 diagnostics.")
	_assert(not dev_hud.visible, "Dev HUD must be hidden by default.")
	var world: Node = scene.get_node_or_null("WorldRuntimeV0")
	var context_panel: PanelContainer = null
	_assert(world != null, "Production runtime world must exist.")
	if world != null:
		_assert(
			world.get_node_or_null("HudLayer/PostProcessToggle") == null,
			"Postprocess toggle button must not pollute the player HUD.",
		)
		var hud_manager: Control = world.get_node_or_null("HudLayer/HudManager") as Control
		_assert(hud_manager != null, "Production HUD manager must exist.")
		if hud_manager != null:
			_assert(
				hud_manager.get_node_or_null("SurvivalPanel") != null,
				"Survival panel must exist.",
			)
			_assert(
				hud_manager.get_node_or_null("EnvironmentPanel") != null,
				"Environment panel must exist.",
			)
			context_panel = hud_manager.get_node_or_null("ContextPanel") as PanelContainer
			_assert(context_panel != null, "Context panel must exist.")
		# Measurement-сцена телепортирует игрока к горе раньше production
		# loading transition. Для визуальной пробы скрываем только её локальный
		# loading surface; shipping readiness contract не меняется.
		var loading_surface: CanvasLayer = (
			world.get_node_or_null("InitialLoadingScreen") as CanvasLayer
		)
		if loading_surface != null:
			loading_surface.visible = false

	for _frame: int in range(PRESENTATION_SETTLE_FRAMES):
		await process_frame
	var image: Image = root.get_texture().get_image()
	_assert(image != null, "Viewport image must be available.")
	if image != null:
		var error: Error = image.save_png(OUTPUT_PATH)
		_assert(error == OK, "HUD screenshot must save (error %d)." % error)

	var context_hidden: bool = false
	for _frame: int in range(600):
		if context_panel != null and not context_panel.visible:
			context_hidden = true
			break
		await process_frame
	_assert(context_hidden, "Default HUD hint must auto-hide.")
	var event_bus: Node = root.get_node_or_null("EventBus")
	_assert(event_bus != null, "EventBus must exist.")
	if event_bus != null and context_panel != null:
		event_bus.emit_signal("build_mode_changed", true)
		await process_frame
		_assert(context_panel.visible, "Build mode must show contextual controls.")
		event_bus.emit_signal("build_mode_changed", false)
		for _frame: int in range(30):
			await process_frame
		_assert(not context_panel.visible, "Leaving build mode must hide contextual controls.")
	if not _failed:
		print("hud_runtime_render_probe: OK output=%s" % OUTPUT_PATH)
	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
