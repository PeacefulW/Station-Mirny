extends SceneTree


const EXPECTED_TEXTURES: Array[String] = [
	"res://assets/sprites/player/player_idle_mixamo_16dir_16frames_256.png",
	"res://assets/sprites/player/player_run_forward_mixamo_16dir_16frames_256.png",
	"res://assets/sprites/player/player_run_backward_mixamo_16dir_16frames_256.png",
	"res://assets/sprites/player/player_strafe_left_mixamo_16dir_16frames_256.png",
	"res://assets/sprites/player/player_strafe_right_mixamo_16dir_16frames_256.png",
]

const EXPECTED_SCENE_SNIPPETS: Array[String] = [
	"idle_visual_texture = ExtResource(\"3_idle\")",
	"run_forward_visual_texture = ExtResource(\"2_75vfm\")",
	"run_backward_visual_texture = ExtResource(\"8_back\")",
	"strafe_left_visual_texture = ExtResource(\"9_left\")",
	"strafe_right_visual_texture = ExtResource(\"10_right\")",
	"region_enabled = true",
	"region_rect = Rect2(0, 0, 256, 256)",
]


func _init() -> void:
	var scene_text: String = FileAccess.get_file_as_string("res://scenes/player/player.tscn")
	if scene_text.is_empty():
		_fail("player.tscn should be readable")
		return
	if scene_text.contains("player_idle_placeholder_16dir_16frames_256.png"):
		_fail("player scene should not reference placeholder idle atlas")
		return
	for path: String in EXPECTED_TEXTURES:
		if not scene_text.contains(path.trim_prefix("res://")):
			_fail("player scene missing texture path: %s" % path)
			return
		var texture: Texture2D = ResourceLoader.load(path) as Texture2D
		if texture == null:
			_fail("texture should load: %s" % path)
			return
		if texture.get_width() != 4096 or texture.get_height() != 4096:
			_fail("texture should be 4096x4096: %s got %sx%s" % [path, texture.get_width(), texture.get_height()])
			return
	for snippet: String in EXPECTED_SCENE_SNIPPETS:
		if not scene_text.contains(snippet):
			_fail("player scene missing snippet: %s" % snippet)
			return

	print("PLAYER_VISUAL_MIXAMO_RESOURCE_SMOKE_OK textures=%d" % EXPECTED_TEXTURES.size())
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
