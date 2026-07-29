extends SceneTree
## Рендер-проба кустов равнины: поднимает dev-сцену, дожидается дневного света
## и осевшего мира, снимает кадр и печатает, сколько кустов реально загружено.
##
##     Godot --path . -s tools/plains_bush_render_probe.gd

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const OUTPUT_DIR: String = "res://artifacts/plains_bush_runtime"
const MAX_READY_FRAMES: int = 6000
const BRIGHTNESS_STEPS: int = 400
const BRIGHTNESS_FRAMES_PER_STEP: int = 15
const MIN_BRIGHTNESS: float = 0.24

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("artifacts/plains_bush_runtime")
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Dev scene must load.")
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
	_assert(bool(snapshot.get("ready", false)), "Dev scene must become ready.")
	print("BUSH_PROBE stage=ready")

	var time_manager: Node = root.get_node_or_null("TimeManager")
	_assert(time_manager != null, "TimeManager autoload must be present.")
	if time_manager != null:
		time_manager.call("restore_persisted_state", 9.0, 1, 0)
		time_manager.call("set_paused", true)

	# Освещение доезжает лерпом, а стриминг догружает кольцо чанков за экраном
	# загрузки: ждём фактическую яркость кадра, а не число кадров.
	var brightness: float = 0.0
	for _step: int in range(BRIGHTNESS_STEPS):
		for _frame: int in range(BRIGHTNESS_FRAMES_PER_STEP):
			await process_frame
		brightness = _viewport_center_brightness()
		if brightness >= MIN_BRIGHTNESS:
			break
	print("BUSH_PROBE stage=daylight brightness=%.3f" % brightness)
	_assert(brightness >= MIN_BRIGHTNESS, "Viewport must brighten before the shot (got %.3f)." % brightness)

	for _frame: int in range(60):
		await process_frame
	var counts: Dictionary = _count_families(scene)
	# The dev scene spawns the player against the mountain, which is bare ground
	# by design. Walk the camera to a chunk that actually holds bushes, or the
	# shot proves nothing about the family it is meant to show.
	var bush_anchor: Vector2 = counts.get("bush_instance_position", counts.get("bush_anchor", Vector2.ZERO)) as Vector2
	if bush_anchor != Vector2.ZERO:
		var world: Node = scene.get_node_or_null("WorldRuntimeV0")
		var player: Node2D = world.get_node_or_null("Player") as Node2D if world != null else null
		if player != null:
			player.global_position = bush_anchor
			print("BUSH_PROBE stage=moved_to_bushes at=%s" % str(bush_anchor))
			for _frame: int in range(240):
				await process_frame
	print("BUSH_PROBE batch instances=%d active_stripes=%d visible_layers=%d/%d" % [
		int(counts.get("batch_instances", 0)),
		int(counts.get("batch_active_stripes", 0)),
		int(counts.get("batch_visible", 0)),
		int(counts.get("batch_layers", 0)),
	])
	print("BUSH_PROBE loaded bush_count=%d tree_count=%d rock_count=%d in %d object layers" % [
		int(counts.get("bush", 0)),
		int(counts.get("tree", 0)),
		int(counts.get("rock", 0)),
		int(counts.get("layers", 0)),
	])
	_capture("%s/bush_world.png" % OUTPUT_DIR)
	print("BUSH_PROBE stage=captured")
	_assert(int(counts.get("bush", 0)) > 0, "Loaded chunks must contain bushes.")
	quit(1 if _failed else 0)


func _count_families(scene: Node) -> Dictionary:
	var totals: Dictionary = {"bush": 0, "tree": 0, "rock": 0, "layers": 0}
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)
		if not node.has_method("get_debug_state"):
			continue
		if node.get_class() != "Node2D" and not (node is Node2D):
			continue
		var state: Dictionary = node.call("get_debug_state") as Dictionary
		if not state.has("bush_count"):
			continue
		totals["layers"] = int(totals["layers"]) + 1
		var layer_bushes: int = int(state.get("bush_count", 0))
		if layer_bushes > 0 and not totals.has("bush_anchor"):
			totals["bush_anchor"] = (node as Node2D).global_position
		totals["bush"] = int(totals["bush"]) + layer_bushes
		totals["tree"] = int(totals["tree"]) + int(state.get("tree_count", 0))
		totals["rock"] = int(totals["rock"]) + int(state.get("small_rock_count", 0))
		var bush_batch: Node = node.get_node_or_null("LayeredBushBatchLayer")
		if bush_batch != null and not totals.has("bush_instance_position"):
			var instance_position: Variant = _first_instance_position(bush_batch as Node2D)
			if instance_position != null:
				totals["bush_instance_position"] = instance_position
		if bush_batch != null and bush_batch.has_method("get_debug_state"):
			var batch_state: Dictionary = bush_batch.call("get_debug_state") as Dictionary
			totals["batch_instances"] = int(totals.get("batch_instances", 0)) 					+ int(batch_state.get("instance_count", 0))
			totals["batch_active_stripes"] = int(totals.get("batch_active_stripes", 0)) 					+ int(batch_state.get("active_stripe_count", 0))
			totals["batch_visible"] = int(totals.get("batch_visible", 0)) 					+ (1 if bool((bush_batch as Node2D).visible) else 0)
			totals["batch_layers"] = int(totals.get("batch_layers", 0)) + 1
	return totals


func _viewport_center_brightness() -> float:
	var image: Image = root.get_texture().get_image()
	if image == null:
		return 0.0
	var width: int = image.get_width()
	var height: int = image.get_height()
	var total: float = 0.0
	var samples: int = 0
	for y: int in range(height / 3, height * 2 / 3, 8):
		for x: int in range(width / 3, width * 2 / 3, 8):
			var color: Color = image.get_pixel(x, y)
			total += (color.r + color.g + color.b) / 3.0
			samples += 1
	return total / maxf(1.0, float(samples))


func _capture(path: String) -> void:
	var image: Image = root.get_texture().get_image()
	_assert(image != null, "Viewport image must be available.")
	if image == null:
		return
	var error: Error = image.save_png(ProjectSettings.globalize_path(path))
	_assert(error == OK, "Screenshot must be written to %s (err %d)." % [path, error])


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


## Reads the first live instance origin straight out of a slot's raw MultiMesh
## buffer, so the probe frames a real bush instead of a chunk corner.
func _first_instance_position(batch_layer: Node2D) -> Variant:
	if batch_layer == null:
		return null
	for child: Node in batch_layer.get_children():
		var instance: MultiMeshInstance2D = child as MultiMeshInstance2D
		if instance == null or instance.multimesh == null:
			continue
		if instance.multimesh.instance_count <= 0:
			continue
		var buffer: PackedFloat32Array = instance.multimesh.buffer
		if buffer.size() < 12:
			continue
		return instance.global_position + Vector2(buffer[3], buffer[7])
	return null
