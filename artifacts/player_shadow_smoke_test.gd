extends SceneTree


const PLAYER_SCENE_PATH: String = "res://scenes/player/player.tscn"
const SHADOW_SCRIPT_PATH: String = "res://core/entities/player/player_sun_shadow.gd"
const SHADOW_SHADER_PATH: String = "res://assets/shaders/player_silhouette_shadow.gdshader"
const CLIP_JSON_PATHS: Array[String] = [
	"res://assets/sprites/player/player_idle_mixamo_16dir_16frames_256.json",
	"res://assets/sprites/player/player_run_forward_mixamo_16dir_16frames_256.json",
	"res://assets/sprites/player/player_run_backward_mixamo_16dir_16frames_256.json",
	"res://assets/sprites/player/player_strafe_left_mixamo_16dir_16frames_256.json",
	"res://assets/sprites/player/player_strafe_right_mixamo_16dir_16frames_256.json",
]
const EXPECTED_CONTACT_FRAMES: int = 256
const EXPECTED_SCENE_SNIPPETS: Array[String] = [
	"[node name=\"SunShadow\" type=\"Sprite2D\" parent=\".\"]",
	"z_index = 19",
	"z_as_relative = false",
	"script = ExtResource(\"11_shadow\")",
	"[node name=\"Visual\" type=\"Sprite2D\" parent=\".\"",
]


func _init() -> void:
	var scene_text: String = FileAccess.get_file_as_string(PLAYER_SCENE_PATH)
	if scene_text.is_empty():
		_fail("player scene should be readable")
		return
	for snippet: String in EXPECTED_SCENE_SNIPPETS:
		if not scene_text.contains(snippet):
			_fail("player scene missing snippet: %s" % snippet)
			return
	var shadow_script: Script = ResourceLoader.load(SHADOW_SCRIPT_PATH) as Script
	if shadow_script == null:
		_fail("shadow script should load")
		return
	var shadow_shader: Shader = ResourceLoader.load(SHADOW_SHADER_PATH) as Shader
	if shadow_shader == null:
		_fail("shadow shader should load")
		return
	if not scene_text.contains("texture = ExtResource(\"2_75vfm\")"):
		_fail("SunShadow and Visual should start from the same atlas resource")
		return
	if not scene_text.contains("region_rect = Rect2(0, 0, 256, 256)"):
		_fail("SunShadow should start from the same atlas region contract")
		return
	for json_path: String in CLIP_JSON_PATHS:
		var json_text: String = FileAccess.get_file_as_string(json_path)
		if json_text.is_empty():
			_fail("clip metadata missing: %s" % json_path)
			return
		var parsed: Variant = JSON.parse_string(json_text)
		if not (parsed is Dictionary):
			_fail("clip metadata not a dictionary: %s" % json_path)
			return
		var raw: Variant = (parsed as Dictionary).get("frame_contact_uv")
		if not (raw is Array) or (raw as Array).size() != EXPECTED_CONTACT_FRAMES:
			_fail("clip %s must bake %d frame_contact_uv entries" % [json_path, EXPECTED_CONTACT_FRAMES])
			return
	print("PLAYER_SUN_SHADOW_RESOURCE_SMOKE_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
