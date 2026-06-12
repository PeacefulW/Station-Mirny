extends SceneTree

# Экспорт атласа пучков травы в PNG-ассет (generator-first authoring).
# Рантайм и dev-сцена потребляют только этот PNG; runtime-bake запрещён спекой.
# Запуск (headless ок):
#   Godot_v4.6.2-stable_win64_console.exe --headless --path . -s tools/grass_atlas_export.gd

const GrassAtlasPainter = preload("res://tools/grass_atlas_painter.gd")

const OUTPUT_PATH: String = "res://assets/textures/world/biomes/plains/flora/grass_tuft_atlas.png"


func _init() -> void:
	DirAccess.open("res://").make_dir_recursive("assets/textures/world/biomes/plains/flora")
	var image: Image = GrassAtlasPainter.build_atlas_image()
	var error: int = image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("grass_atlas_export: save failed (%d)" % error)
		quit(1)
		return
	print(
		"grass_atlas_export: saved %s (%dx%d)" % [
			ProjectSettings.globalize_path(OUTPUT_PATH),
			image.get_width(),
			image.get_height(),
		],
	)
	quit(0)
