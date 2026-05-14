extends SceneTree

const PROBE_PATH: String = "res://tools/mountain_contour_parity_probe.gd"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var probe_source: String = FileAccess.get_file_as_string(PROBE_PATH)
	_assert(not probe_source.contains("_render_runtime_proxy"), "Parity probe must not use a software proxy as visual parity evidence.")
	_assert(not probe_source.contains("DisplayServer.get_name() == \"headless\"") or probe_source.contains("manual_human_verification_required"), "Headless parity must be reported as manual verification, not pass.")
	_assert(probe_source.contains("visual_verification_mode"), "Parity report must declare visual_verification_mode.")
	_assert(probe_source.contains("renderer_name"), "Parity report must declare the renderer used for visual verification.")
	_assert(probe_source.contains("const SILHOUETTE_MISMATCH_RATIO_LIMIT: float = 0.005"), "Parity silhouette threshold must be strict enough to catch visible shape drift.")
	_assert(probe_source.contains("const MEAN_RGB_DELTA_LIMIT: float = 0.02"), "Parity mean RGB threshold must be strict enough to catch wrong textures/colors.")
	_assert(probe_source.contains("const P95_RGB_DELTA_LIMIT: float = 0.08"), "Parity p95 RGB threshold must be strict enough to catch localized facade/rim errors.")
	_assert(probe_source.contains("const NORMAL_MEAN_ANGLE_DELTA_DEG_LIMIT: float = 5.0"), "Parity must compare normal maps as angle delta in degrees.")
	_assert(probe_source.contains("const SEAM_GAP_PIXELS_LIMIT: int = 0"), "Parity must reject any seam gap pixel.")
	_assert(not probe_source.contains("NORMAL_MEAN_RGB_DELTA_LIMIT"), "Normal parity must not use soft RGB delta thresholds.")
	_assert(not probe_source.contains("NORMAL_P95_RGB_DELTA_LIMIT"), "Normal parity must not use soft RGB p95 thresholds.")
	_assert(not probe_source.contains("_load_resized"), "Parity probe must not resize generator references to make visual drift pass.")
	_assert(probe_source.contains("_load_reference_exact"), "Parity probe must load exact-scale generator references.")
	_assert(not probe_source.contains("reference images are resized"), "Parity report must not advertise resized-reference acceptance.")
	_assert(probe_source.contains("exact_generator_runtime_scale"), "Parity report must document the exact generator/runtime scale contract.")
	_assert(probe_source.contains("\"large_cave_like_cut\""), "Parity matrix must include the screenshot-like large cave/facade live fail-case.")
	_assert(probe_source.contains("_measure_seam_gap_pixels"), "Parity probe must measure seam gap pixels explicitly.")
	_assert(probe_source.contains("\"runtime_ready\""), "Parity case report must expose runtime_ready so incomplete runtime cannot pass silently.")
	_assert(probe_source.contains("\"collision_ready\""), "Parity case report must expose collision_ready so incomplete collision cannot pass silently.")
	_assert(probe_source.contains("\"face_ready\""), "Parity case report must expose face_ready so missing facade cannot pass silently.")
	_assert(probe_source.contains("\"outline_ready\""), "Parity case report must expose outline_ready so missing outline cannot pass silently.")
	quit(1 if _failed else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
