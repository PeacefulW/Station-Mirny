extends SceneTree

const VisualRuntimeLabAuthoringScript = preload(
	"res://scenes/dev/visual_runtime_lab_authoring.gd"
)

var _saved_runtime_paths: Array[String] = []
var _saved_probe_paths: Array[String] = []


func _init() -> void:
	var authoring: VisualRuntimeLabAuthoring = (
		VisualRuntimeLabAuthoringScript.new() as VisualRuntimeLabAuthoring
	)
	var load_result: Dictionary = authoring.load_from_disk()
	if not bool(load_result.get("success", false)):
		_fail("Authoring resources must load.")
		return
	authoring.set_value(&"ground.grass_coverage", 0.37)
	authoring.set_value(&"grass.density_scale", 3.25)
	if not is_equal_approx(authoring.trees.grass_coverage, 0.37) \
			or not is_equal_approx(authoring.small_rocks.grass_coverage, 0.37) \
			or not is_equal_approx(authoring.bare_stones.grass_coverage, 0.37):
		_fail("Ground sampling fields must stay synchronized across placement settings.")
		return
	var save_result: Dictionary = authoring.save_to_runtime(_save_to_probe_path)
	if not bool(save_result.get("success", false)):
		_fail("Injected authoring save failed: %s" % str(save_result))
		return
	var runtime_paths: Array = save_result.get("paths", []) as Array
	if runtime_paths.size() != 7 \
			or not runtime_paths.has(
				"res://data/world_objects/placement_groups/plains_bare_ground_stones.tres"
			):
		_fail("Runtime save plan must contain all seven coherent authoring resources.")
		return
	if _saved_runtime_paths != runtime_paths or _saved_probe_paths.size() != 7:
		_fail("Injected save must receive the exact runtime save plan.")
		return
	for probe_path: String in _saved_probe_paths:
		var reloaded: Resource = ResourceLoader.load(
			probe_path,
			"",
			ResourceLoader.CACHE_MODE_IGNORE,
		)
		if reloaded == null:
			_fail("Saved probe resource must reload: %s" % probe_path)
			return
	print(
		"visual_runtime_lab_authoring_smoke_test: OK paths=%s"
		% str(_saved_runtime_paths)
	)
	quit(0)


func _save_to_probe_path(resource: Resource, runtime_path: String) -> Error:
	var probe_path: String = (
		"user://visual_runtime_lab_save_smoke_%02d_%s"
		% [_saved_probe_paths.size(), runtime_path.get_file()]
	)
	_saved_runtime_paths.append(runtime_path)
	_saved_probe_paths.append(probe_path)
	return ResourceSaver.save(resource, probe_path)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
