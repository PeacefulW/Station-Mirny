extends SceneTree

const SHADER_PATH: String = "res://assets/shaders/mountain_contour_runtime.gdshader"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var shader_source: String = FileAccess.get_file_as_string(SHADER_PATH)
	_assert(shader_source.contains("texture(top_albedo_tex, top_uv).rgb;"), "Runtime shader must use exported top albedo without multiplying by legacy tint.")
	_assert(shader_source.contains("texture(face_albedo_tex, face_uv).rgb;"), "Runtime shader must use exported face albedo without multiplying by legacy tint.")
	_assert(shader_source.contains("texture(base_albedo_tex, macro_uv).rgb;"), "Runtime shader must use exported base albedo without multiplying by legacy tint.")
	_assert(not shader_source.contains("texture(top_albedo_tex, top_uv).rgb * top_tint.rgb"), "Top albedo must not be double-tinted.")
	_assert(not shader_source.contains("texture(face_albedo_tex, face_uv).rgb * face_tint.rgb"), "Face albedo must not be double-tinted.")
	_assert(not shader_source.contains("texture(base_albedo_tex, macro_uv).rgb * base_tint.rgb"), "Base albedo must not be double-tinted.")
	_assert(not shader_source.contains("mix(face_albedo, base_albedo"), "Facade must not be shifted toward ground/base albedo.")
	quit(1 if _failed else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
