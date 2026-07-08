extends SceneTree

# Рендер-проба дев-сцены травы: загружает grass_wind_dev_scene.tscn, ждёт
# кадры прогрева, снимает вьюпорт (полный + правая панель параметров) и
# выходит. Windowed (захват вьюпорта требует GPU). Запуск:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/grass_wind_dev_scene_probe.gd

const SCENE_PATH: String = "res://scenes/dev/grass_wind_dev_scene.tscn"
const OUTPUT_DIR: String = "res://artifacts/grass_wind_dev_probe"
const SETTLE_FRAMES: int = 90


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var error: Error = change_scene_to_file(SCENE_PATH)
	if error != OK:
		push_error("grass_wind_dev_scene_probe: change_scene failed (%d)" % error)
		quit(1)
		return
	for _i: int in range(SETTLE_FRAMES):
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var image: Image = root.get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/dev_scene_full.png" % OUTPUT_DIR))
	print("grass_wind_dev_scene_probe: saved dev_scene_full.png %dx%d" % [image.get_width(), image.get_height()])
	# Вторая точка: сезон вручную на середину, чтобы снег/зиму было видно.
	var scene_root: Node = current_scene
	if scene_root != null and scene_root.has_method("_set_season_amount"):
		scene_root.call("_set_season_amount", 0.65, false)
		scene_root.set("_season_auto", false)
	for _i: int in range(30):
		await process_frame
	var winter_image: Image = root.get_viewport().get_texture().get_image()
	winter_image.save_png(ProjectSettings.globalize_path("%s/dev_scene_season.png" % OUTPUT_DIR))
	print("grass_wind_dev_scene_probe: saved dev_scene_season.png")
	quit(0)
