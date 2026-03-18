class_name DaylightSystem
extends CanvasModulate

## Система освещения дня и ночи. Подписывается на TimeManager
## и плавно меняет цвет CanvasModulate.
## Днём — полная яркость, ночью — тёмно-синий мрак.

# --- Константы ---
## Цвета для каждой фазы дня (мягкие, атмосферные).
const COLOR_NIGHT := Color(0.08, 0.09, 0.18)
const COLOR_DAWN := Color(0.55, 0.45, 0.35)
const COLOR_DAY := Color(1.0, 1.0, 1.0)
const COLOR_DUSK := Color(0.65, 0.40, 0.25)

# --- Приватные ---
var _target_color: Color = COLOR_DAY
## Скорость перехода между цветами (за секунду).
var _transition_speed: float = 0.4

func _ready() -> void:
	color = COLOR_DAY
	_target_color = COLOR_DAY
	EventBus.time_of_day_changed.connect(_on_time_of_day_changed)
	EventBus.time_tick.connect(_on_time_tick)

func _process(delta: float) -> void:
	# Плавный переход к целевому цвету
	color = color.lerp(_target_color, _transition_speed * delta)

# --- Приватные методы ---

func _on_time_of_day_changed(new_phase: int, _old_phase: int) -> void:
	match new_phase:
		TimeManagerSingleton.TimeOfDay.DAWN:
			_target_color = COLOR_DAWN
		TimeManagerSingleton.TimeOfDay.DAY:
			_target_color = COLOR_DAY
		TimeManagerSingleton.TimeOfDay.DUSK:
			_target_color = COLOR_DUSK
		TimeManagerSingleton.TimeOfDay.NIGHT:
			_target_color = COLOR_NIGHT

func _on_time_tick(current_hour: float, _day_progress: float) -> void:
	# Плавное подмешивание внутри фазы для естественных переходов.
	# Например: рассвет начинается тёмным и постепенно светлеет.
	if not TimeManager:
		return
	var balance: TimeBalance = TimeManager.balance
	if not balance:
		return
	var hour: int = floori(current_hour)
	var frac: float = current_hour - float(hour)

	# Внутри рассвета: плавно от ночного к рассветному
	if hour >= balance.dawn_hour and hour < balance.day_hour:
		var progress: float = (current_hour - float(balance.dawn_hour)) / float(balance.day_hour - balance.dawn_hour)
		_target_color = COLOR_NIGHT.lerp(COLOR_DAY, progress)
	# Внутри заката: плавно от дневного к закатному и к ночному
	elif hour >= balance.dusk_hour and hour < balance.night_hour:
		var progress: float = (current_hour - float(balance.dusk_hour)) / float(balance.night_hour - balance.dusk_hour)
		_target_color = COLOR_DAY.lerp(COLOR_NIGHT, progress)
