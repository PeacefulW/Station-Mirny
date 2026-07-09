extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	var shader_source: String = FileAccess.get_file_as_string("res://assets/shaders/mountain_foothill_overlay.gdshader")

	_assert(
		chunk_view_source.contains("_mountain_rock_underlay_sprite")
			and chunk_view_source.contains("MountainRockUnderlay"),
		"ChunkView must have a dedicated live rock underlay sprite under the mountain mask."
	)
	_assert(
		chunk_view_source.contains("_sync_mountain_rock_underlay_visual")
			and chunk_view_source.contains("_mountain_top_mask_texture"),
		"Mountain rock underlay must sync from the live native mountain mask texture, not the captured foothill footprint."
	)
	_assert(
		chunk_view_source.contains("\"footprint_fill_strength\"")
			and chunk_view_source.contains("MOUNTAIN_ROCK_UNDERLAY_FILL_STRENGTH"),
		"Mountain rock underlay must enable the shader footprint fill so grass ground cannot show through the live mountain footprint."
	)
	_assert(
		chunk_view_source.contains("\"footprint_fill_alpha\"")
			and chunk_view_source.contains("MOUNTAIN_ROCK_UNDERLAY_FILL_ALPHA"),
		"Mountain rock underlay must override footprint fill alpha independently from the soft foothill apron."
	)
	_assert(
		chunk_view_source.contains("_clear_mountain_rock_underlay()"),
		"Clearing the live mountain mask must also clear the live rock underlay."
	)
	_assert(
		shader_source.contains("uniform float max_alpha")
			and shader_source.contains("uniform float footprint_fill_alpha")
			and shader_source.contains("clamp(feather * foothill_alpha * organic_alpha, 0.0, max_alpha)"),
		"Foothill shader must expose max_alpha so the live rock underlay can become opaque while the soft apron keeps its old alpha cap."
	)

	if _failed:
		quit(1)
		return
	print("mountain_rock_underlay_smoke_test: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
