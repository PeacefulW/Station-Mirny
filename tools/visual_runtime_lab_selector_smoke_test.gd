extends SceneTree

const VisualRuntimeLabAuthoringScript = preload(
	"res://scenes/dev/visual_runtime_lab_authoring.gd"
)
const VisualRuntimeLabSelectorScript = preload(
	"res://scenes/dev/visual_runtime_lab_selector.gd"
)
const PROBE_SEED: int = 707


func _init() -> void:
	var authoring: VisualRuntimeLabAuthoring = (
		VisualRuntimeLabAuthoringScript.new() as VisualRuntimeLabAuthoring
	)
	var load_result: Dictionary = authoring.load_from_disk()
	if not bool(load_result.get("success", false)):
		push_error("Visual runtime lab selector could not load authoring resources.")
		quit(1)
		return
	var selector: VisualRuntimeLabSelector = (
		VisualRuntimeLabSelectorScript.new() as VisualRuntimeLabSelector
	)
	var purple_zone: Dictionary = authoring.get_ground_zone_texture_info(7)
	var purple_texture: String = String(purple_zone.get("texture", ""))
	if not purple_texture.contains("rock_top_albedo.png") \
			or not purple_texture.contains("foothill_albedo.png"):
		push_error("Purple scree zone must identify both production rock albedos.")
		quit(1)
		return
	var patch: Dictionary = selector.find_patch(
		PROBE_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		authoring.get_settings_packed(),
		Vector2i.ZERO,
	)
	if not bool(patch.get("success", false)) \
			or not bool(patch.get("exact_match", false)):
		push_error("Visual runtime lab selector did not find an exact patch: %s" % str(patch))
		quit(1)
		return
	print("visual_runtime_lab_selector_smoke_test: OK patch=%s" % str(patch))
	quit(0)
