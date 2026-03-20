class_name SettingsManagerSingleton
extends Node

## Менеджер настроек. Сохраняет/загружает из user://settings.cfg.
## Autoload: SettingsManager.

const SETTINGS_PATH: String = "user://settings.cfg"

# --- Настройки: Игра ---
var locale: String = "ru"
var autosave_interval: int = 300  ## секунды (0 = выкл)

# --- Настройки: Графика ---
var fullscreen: bool = false
var vsync: bool = true
var ui_scale: float = 1.0
var brightness: float = 1.0

# --- Настройки: Звук ---
var volume_master: float = 1.0
var volume_music: float = 0.8
var volume_sfx: float = 1.0
var volume_ambient: float = 0.7

func _ready() -> void:
	load_settings()
	apply_all()

## Загрузить настройки из файла.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	locale = cfg.get_value("game", "locale", locale)
	autosave_interval = cfg.get_value("game", "autosave_interval", autosave_interval)
	fullscreen = cfg.get_value("graphics", "fullscreen", fullscreen)
	vsync = cfg.get_value("graphics", "vsync", vsync)
	ui_scale = cfg.get_value("graphics", "ui_scale", ui_scale)
	brightness = cfg.get_value("graphics", "brightness", brightness)
	volume_master = cfg.get_value("audio", "master", volume_master)
	volume_music = cfg.get_value("audio", "music", volume_music)
	volume_sfx = cfg.get_value("audio", "sfx", volume_sfx)
	volume_ambient = cfg.get_value("audio", "ambient", volume_ambient)

## Сохранить настройки в файл.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "locale", locale)
	cfg.set_value("game", "autosave_interval", autosave_interval)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "ui_scale", ui_scale)
	cfg.set_value("graphics", "brightness", brightness)
	cfg.set_value("audio", "master", volume_master)
	cfg.set_value("audio", "music", volume_music)
	cfg.set_value("audio", "sfx", volume_sfx)
	cfg.set_value("audio", "ambient", volume_ambient)
	cfg.save(SETTINGS_PATH)

## Применить все настройки.
func apply_all() -> void:
	apply_locale()
	apply_graphics()
	apply_audio()

func apply_locale() -> void:
	TranslationServer.set_locale(locale)

func apply_graphics() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	get_tree().root.content_scale_factor = ui_scale

func apply_audio() -> void:
	_set_bus_volume("Master", volume_master)
	_set_bus_volume("Music", volume_music)
	_set_bus_volume("SFX", volume_sfx)
	_set_bus_volume("Ambient", volume_ambient)

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
	AudioServer.set_bus_mute(idx, linear < 0.01)
