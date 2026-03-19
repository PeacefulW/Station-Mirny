# Станция «Мирный» — Стандарт кодирования v1.0

> **Цель документа:** Набор правил и паттернов, которым ОБЯЗАНЫ следовать все участники проекта (включая ИИ-ассистентов). Гарантирует чистый, модульный, расширяемый код без хардкода.
>
> **Движок:** Godot 4.x | **Язык:** GDScript | **Парадигма:** Data-Driven + Event-Driven

---

## 0. Золотые правила (читай первыми)

Эти правила не обсуждаются. Любой коммит, нарушающий их, отклоняется.

1. **Никакого хардкода данных.** Числа, строки, пути, параметры — всё в Resource-файлах или JSON. Если ты пишешь `health = 100` внутри скрипта — ты делаешь неправильно.
2. **Каждая система знает только о себе.** Системы общаются через EventBus (сигналы) или Registry (запросы данных). Прямые ссылки между системами запрещены.
3. **Один скрипт — одна ответственность.** Если скрипт делает больше одной вещи — разбей его.
4. **Всегда используй типизацию.** Каждая переменная, параметр и возвращаемое значение имеют явный тип.
5. **Моды — не afterthought.** Каждая система проектируется так, чтобы мод мог её расширить, переопределить или заменить.

---

## 1. Стиль кода GDScript

### 1.1 Именование

Следуем официальному GDScript Style Guide:

```gdscript
# Файлы и папки — snake_case
player_controller.gd
survival_system.gd

# Классы — PascalCase
class_name PlayerController
class_name SurvivalSystem

# Функции и переменные — snake_case
var current_health: float = 0.0
func take_damage(amount: float) -> void:

# Константы и enum-значения — UPPER_SNAKE_CASE
const MAX_OXYGEN: float = 100.0
enum State { IDLE, RUNNING, CRAFTING, DYING }

# Приватные члены — с подчёркиванием
var _internal_timer: float = 0.0
func _calculate_toxicity() -> float:

# Сигналы — прошедшее время (что случилось)
signal health_changed(new_value: float)
signal item_crafted(item_id: StringName)
signal filter_clogged(filter_node: Node)

# Булевы переменные — is_, has_, can_
var is_inside_base: bool = false
var has_oxygen_mask: bool = true
var can_craft: bool = false
```

### 1.2 Порядок элементов в скрипте

Всегда строго в этом порядке:

```gdscript
class_name MySystem          # 1. Имя класса
extends Node                 # 2. Наследование

## Описание класса           # 3. Документация (##)

# --- Сигналы ---            # 4. Сигналы
signal something_happened(data: Dictionary)

# --- Перечисления ---       # 5. Enums
enum State { IDLE, ACTIVE }

# --- Константы ---          # 6. Константы
const TICK_RATE: float = 1.0

# --- Экспортируемые ---     # 7. @export (настраиваемые из редактора)
@export var max_value: float = 100.0

# --- Публичные ---          # 8. Публичные переменные
var current_value: float = 0.0

# --- Приватные ---          # 9. Приватные переменные
var _timer: float = 0.0

# --- Встроенные ---         # 10. Встроенные функции Godot
func _ready() -> void:
func _process(delta: float) -> void:
func _physics_process(delta: float) -> void:

# --- Публичные методы ---   # 11. Публичные методы
func add_value(amount: float) -> void:

# --- Приватные методы ---   # 12. Приватные методы
func _recalculate() -> void:
```

### 1.3 Типизация (обязательна)

```gdscript
# ПРАВИЛЬНО — явные типы везде
var player_name: String = "Engineer"
var health: float = 100.0
var inventory: Array[ItemData] = []
var active_effects: Dictionary = {}

func calculate_damage(base: float, modifier: float) -> float:
    return base * modifier

func get_items_by_type(type: StringName) -> Array[ItemData]:
    return inventory.filter(func(item: ItemData) -> bool: return item.type == type)

# НЕПРАВИЛЬНО — без типов
var name = "Engineer"
var health = 100
func calculate_damage(base, modifier):
    return base * modifier
```

### 1.4 Документация

```gdscript
## Система выживания. Управляет шкалами O₂, токсичности,
## температуры, голода и жажды.
## Не содержит логику отображения — только данные и расчёты.
class_name SurvivalSystem
extends Node

## Вызывается когда любая шкала изменилась.
## [param stat_name] — имя шкалы ("oxygen", "toxicity", ...).
## [param new_value] — новое значение (0.0 — 1.0).
signal stat_changed(stat_name: StringName, new_value: float)

## Применяет урон от спор к токсичности.
## Учитывает модификатор скафандра и резист персонажа.
func apply_spore_damage(base_amount: float, resist_modifier: float) -> void:
    var final_damage: float = base_amount * (1.0 - resist_modifier)
    _set_stat(&"toxicity", _stats[&"toxicity"] + final_damage)
```

---

## 2. Архитектурные паттерны

### 2.1 Data-Driven Design (главный принцип)

**ВСЕ игровые данные живут в файлах, НЕ в коде.**

Для этого используем Custom Resources (наследники `Resource`):

```gdscript
# data/items/item_data.gd
## Определение предмета. Все параметры задаются в .tres файлах.
class_name ItemData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var weight: float = 0.0
@export var stack_size: int = 1
@export var icon: Texture2D = null
@export var item_type: ItemType = ItemType.MATERIAL
@export var tags: Array[StringName] = []

enum ItemType { MATERIAL, TOOL, WEAPON, CONSUMABLE, MODULE, BUILDING }
```

Затем в редакторе Godot создаёшь `.tres` файлы:

```
data/items/
├── iron_ore.tres        ← id="iron_ore", weight=5.0, type=MATERIAL
├── iron_ingot.tres      ← id="iron_ingot", weight=2.5, type=MATERIAL
├── rifle.tres           ← id="rifle", weight=3.8, type=WEAPON
└── spore_filter.tres    ← id="spore_filter", weight=0.5, type=MODULE
```

**Почему это важно:**
- Новый предмет = новый .tres файл, не нужно трогать код
- Моды добавляют свои .tres файлы → предметы появляются в игре
- Баланс меняется без перекомпиляции
- ИИ-ассистент может генерировать .tres файлы по описанию

### 2.2 Registry (Реестр)

Центральное хранилище, куда регистрируются все игровые данные при загрузке:

```gdscript
# core/autoloads/registry.gd
## Глобальный реестр всех игровых данных.
## Загружает .tres файлы из data/ и позволяет получать их по ID.
## Моды регистрируют свои данные через тот же механизм.
class_name GameRegistry
extends Node

var _items: Dictionary = {}          # StringName -> ItemData
var _recipes: Dictionary = {}        # StringName -> RecipeData
var _creatures: Dictionary = {}      # StringName -> CreatureData
var _buildings: Dictionary = {}      # StringName -> BuildingData
var _biomes: Dictionary = {}         # StringName -> BiomeData
var _tech_tree: Dictionary = {}      # StringName -> TechData
var _events: Dictionary = {}         # StringName -> EventData

func _ready() -> void:
    _load_all_from_directory("res://data/items/", _items)
    _load_all_from_directory("res://data/recipes/", _recipes)
    _load_all_from_directory("res://data/creatures/", _creatures)
    _load_all_from_directory("res://data/buildings/", _buildings)
    # Моды загружаются после базовых данных
    _load_mods()

## Получить предмет по ID. Возвращает null если не найден.
func get_item(id: StringName) -> ItemData:
    return _items.get(id)

## Получить все предметы определённого типа.
func get_items_by_type(type: ItemData.ItemType) -> Array[ItemData]:
    return _items.values().filter(
        func(item: ItemData) -> bool: return item.item_type == type
    )

## Зарегистрировать предмет (используется модами).
func register_item(item: ItemData) -> void:
    if _items.has(item.id):
        push_warning("Registry: предмет '%s' переопределён" % item.id)
    _items[item.id] = item
    EventBus.registry_item_added.emit(item.id)

## Загрузить все .tres файлы из директории.
func _load_all_from_directory(path: String, target: Dictionary) -> void:
    var dir := DirAccess.open(path)
    if not dir:
        push_warning("Registry: директория не найдена: %s" % path)
        return
    dir.list_dir_begin()
    var file_name: String = dir.get_next()
    while file_name != "":
        if file_name.ends_with(".tres"):
            var resource: Resource = load(path + file_name)
            if resource and resource.get("id"):
                target[resource.id] = resource
        file_name = dir.get_next()
```

**Правило: Никогда не загружай ресурсы по пути напрямую в коде.**

```gdscript
# НЕПРАВИЛЬНО — хардкод пути + невозможно переопределить модом
var iron_ore: ItemData = load("res://data/items/iron_ore.tres")

# ПРАВИЛЬНО — через реестр
var iron_ore: ItemData = Registry.get_item(&"iron_ore")
```

### 2.3 EventBus (Шина событий)

Глобальный Autoload-синглтон, через который системы общаются:

```gdscript
# core/autoloads/event_bus.gd
## Глобальная шина событий. Все межсистемные коммуникации
## проходят через сигналы этого синглтона.
## Моды могут подписываться на любой сигнал.
class_name GameEventBus
extends Node

# --- Игрок ---
signal player_health_changed(new_value: float)
signal player_stat_changed(stat_name: StringName, new_value: float)
signal player_died()
signal player_respawned(position: Vector2)
signal player_entered_base()
signal player_exited_base()

# --- Выживание ---
signal oxygen_depleting(remaining_percent: float)
signal toxicity_threshold_reached(level: int)
signal temperature_critical(is_cold: bool)
signal hunger_critical()

# --- Строительство ---
signal building_placed(building_id: StringName, position: Vector2i)
signal building_destroyed(building_id: StringName, position: Vector2i)
signal room_sealed(room_id: int)
signal room_breached(room_id: int)
signal airlock_cycled(airlock_node: Node)

# --- Крафт ---
signal item_crafted(recipe_id: StringName, result_item: ItemData)
signal recipe_unlocked(recipe_id: StringName)

# --- Технологии ---
signal decryption_started(tech_id: StringName)
signal decryption_completed(tech_id: StringName)
signal decryption_progress(tech_id: StringName, progress: float)

# --- Фауна ---
signal creature_spawned(creature_id: StringName, position: Vector2)
signal creature_killed(creature_id: StringName, position: Vector2)
signal creature_detected_player(creature_node: Node)

# --- Инженерные системы ---
signal power_changed(total_supply: float, total_demand: float)
signal filter_clogged(filter_id: StringName)
signal pipe_damaged(pipe_position: Vector2i)

# --- Эвенты ---
signal world_event_started(event_id: StringName)
signal world_event_ended(event_id: StringName)

# --- Сохранение ---
signal save_requested()
signal save_completed()
signal load_completed()

# --- Моды ---
signal mod_loaded(mod_id: String)
signal registry_item_added(item_id: StringName)
```

**Правила использования EventBus:**

```gdscript
# ПРАВИЛЬНО — система выживания сообщает об изменении,
# UI подписывается и обновляет отображение
# survival_system.gd
func _update_oxygen(delta: float) -> void:
    _oxygen -= _drain_rate * delta
    EventBus.player_stat_changed.emit(&"oxygen", _oxygen)
    if _oxygen < 0.2:
        EventBus.oxygen_depleting.emit(_oxygen)

# ui/hud_oxygen.gd
func _ready() -> void:
    EventBus.player_stat_changed.connect(_on_stat_changed)

func _on_stat_changed(stat_name: StringName, new_value: float) -> void:
    if stat_name == &"oxygen":
        _update_bar(new_value)


# НЕПРАВИЛЬНО — система выживания напрямую меняет UI
# survival_system.gd
func _update_oxygen(delta: float) -> void:
    _oxygen -= _drain_rate * delta
    $"/root/Game/UI/HUD/OxygenBar".value = _oxygen  # УЖАС
```

### 2.4 State Machine (Конечный автомат)

Для всего, что имеет состояния: игрок, существа, постройки, игровой процесс.

```gdscript
# core/systems/state_machine/state_machine.gd
## Универсальный конечный автомат. Присваивается как дочерний
## узел к любой сущности, которая имеет состояния.
class_name StateMachine
extends Node

signal state_changed(old_state: StringName, new_state: StringName)

@export var initial_state: NodePath = NodePath("")

var current_state: State = null
var _states: Dictionary = {}

func _ready() -> void:
    for child: Node in get_children():
        if child is State:
            _states[child.name] = child
            child.state_machine = self
    if initial_state:
        current_state = get_node(initial_state)
        current_state.enter({})

func transition_to(target_state_name: StringName, data: Dictionary = {}) -> void:
    if not _states.has(target_state_name):
        push_error("StateMachine: состояние '%s' не найдено" % target_state_name)
        return
    var old_name: StringName = current_state.name if current_state else &""
    if current_state:
        current_state.exit()
    current_state = _states[target_state_name]
    current_state.enter(data)
    state_changed.emit(old_name, target_state_name)

func _process(delta: float) -> void:
    if current_state:
        current_state.update(delta)

func _physics_process(delta: float) -> void:
    if current_state:
        current_state.physics_update(delta)

func _unhandled_input(event: InputEvent) -> void:
    if current_state:
        current_state.handle_input(event)
```

```gdscript
# core/systems/state_machine/state.gd
## Базовый класс состояния. Наследуй для каждого конкретного состояния.
class_name State
extends Node

var state_machine: StateMachine = null

## Вызывается при входе в состояние.
func enter(_data: Dictionary) -> void:
    pass

## Вызывается при выходе из состояния.
func exit() -> void:
    pass

## Вызывается каждый кадр (аналог _process).
func update(_delta: float) -> void:
    pass

## Вызывается каждый физический кадр.
func physics_update(_delta: float) -> void:
    pass

## Вызывается при вводе пользователя.
func handle_input(_event: InputEvent) -> void:
    pass
```

**Пример: Состояния игрока**

```
Player (CharacterBody2D)
├── StateMachine
│   ├── Idle       ← state_idle.gd
│   ├── Running    ← state_running.gd
│   ├── Crafting   ← state_crafting.gd
│   ├── InVehicle  ← state_in_vehicle.gd
│   └── Dying      ← state_dying.gd
├── Sprite2D
├── CollisionShape2D
└── ...
```

### 2.5 Component Pattern (Компонентный паттерн)

Для переиспользуемого поведения, которое можно прикрепить к любой сущности:

```gdscript
# core/entities/components/health_component.gd
## Компонент здоровья. Прикрепляется к любой сущности,
## которая может получать урон и умирать.
class_name HealthComponent
extends Node

signal health_changed(new_health: float, max_health: float)
signal died()

@export var max_health: float = 100.0
@export var current_health: float = 100.0

func take_damage(amount: float) -> void:
    current_health = maxf(current_health - amount, 0.0)
    health_changed.emit(current_health, max_health)
    if current_health <= 0.0:
        died.emit()

func heal(amount: float) -> void:
    current_health = minf(current_health + amount, max_health)
    health_changed.emit(current_health, max_health)

func get_health_percent() -> float:
    return current_health / max_health if max_health > 0.0 else 0.0
```

```gdscript
# core/entities/components/noise_component.gd
## Компонент шума. Прикрепляется к постройкам и механизмам.
## Очистители реагируют на шум через Area2D.
class_name NoiseComponent
extends Node

@export var noise_radius: float = 200.0
@export var noise_level: float = 1.0
@export var is_active: bool = true

var _area: Area2D = null

func _ready() -> void:
    _setup_area()

func set_active(active: bool) -> void:
    is_active = active
    if _area:
        _area.monitoring = active

func _setup_area() -> void:
    _area = Area2D.new()
    var shape := CircleShape2D.new()
    shape.radius = noise_radius
    var collision := CollisionShape2D.new()
    collision.shape = shape
    _area.add_child(collision)
    _area.collision_layer = 0
    _area.collision_mask = 4  # Слой фауны
    _area.monitoring = is_active
    add_child(_area)
```

**Как собирается сущность:**

```
Generator (Node2D)
├── Sprite2D
├── HealthComponent          ← Можно ломать
├── NoiseComponent           ← Привлекает Очистителей
├── PowerSourceComponent     ← Производит электричество
└── FuelConsumerComponent    ← Потребляет топливо
```

Любой компонент можно прикрепить к любой сущности. Мод может добавить новый компонент.

### 2.6 Command Pattern (для мультиплеера и Undo)

Все действия игрока — это команды. Это критично для будущего мультиплеера и для отмены действий в строительном режиме.

```gdscript
# core/systems/commands/command.gd
## Базовый класс команды. Все действия игрока наследуют его.
class_name Command
extends RefCounted

## Выполнить команду. Возвращает true при успехе.
func execute() -> bool:
    return false

## Отменить команду (для строительного режима).
func undo() -> bool:
    return false

## Сериализовать для передачи по сети (мультиплеер).
func serialize() -> Dictionary:
    return {}

## Создать из сериализованных данных.
static func deserialize(_data: Dictionary) -> Command:
    return null
```

```gdscript
# core/systems/commands/place_building_command.gd
class_name PlaceBuildingCommand
extends Command

var building_id: StringName
var position: Vector2i
var _placed_node: Node = null

func _init(p_building_id: StringName, p_position: Vector2i) -> void:
    building_id = p_building_id
    position = p_position

func execute() -> bool:
    var building_data: BuildingData = Registry.get_building(building_id)
    if not building_data:
        return false
    # Проверки: есть ли ресурсы, свободно ли место, и т.д.
    _placed_node = BuildingFactory.create(building_data, position)
    EventBus.building_placed.emit(building_id, position)
    return true

func undo() -> bool:
    if _placed_node:
        _placed_node.queue_free()
        EventBus.building_destroyed.emit(building_id, position)
        return true
    return false

func serialize() -> Dictionary:
    return {"type": "place_building", "id": building_id, "pos": [position.x, position.y]}
```

### 2.7 Factory Pattern (Фабрики)

Создание сложных объектов — через фабрики, не напрямую:

```gdscript
# core/entities/factories/creature_factory.gd
## Фабрика для создания существ по данным из реестра.
class_name CreatureFactory

## Создать существо по его ID из реестра.
static func create(creature_id: StringName, spawn_position: Vector2) -> Node2D:
    var data: CreatureData = Registry.get_creature(creature_id)
    if not data:
        push_error("CreatureFactory: существо '%s' не найдено" % creature_id)
        return null

    var scene: PackedScene = load(data.scene_path)
    var instance: Node2D = scene.instantiate()
    instance.global_position = spawn_position

    # Настройка компонентов из данных
    var health: HealthComponent = instance.get_node("HealthComponent")
    if health:
        health.max_health = data.max_health
        health.current_health = data.max_health

    var ai: AIComponent = instance.get_node("AIComponent")
    if ai:
        ai.behavior_id = data.behavior_id
        ai.detection_radius = data.detection_radius

    EventBus.creature_spawned.emit(creature_id, spawn_position)
    return instance
```

---

## 3. Запрещённые практики

### 3.1 Никаких Magic Numbers

```gdscript
# НЕПРАВИЛЬНО
if player.health < 20:
    play_warning_sound()
if temperature < -30:
    apply_frostbite()

# ПРАВИЛЬНО — все числа в ресурсах или константах
# Эти значения берутся из data/balance/survival_balance.tres
if player.health < _balance.critical_health_threshold:
    play_warning_sound()
if temperature < _balance.frostbite_temperature:
    apply_frostbite()
```

### 3.2 Никаких строковых путей к нодам

```gdscript
# НЕПРАВИЛЬНО — хрупко, ломается при любом переименовании
var hud := get_node("/root/Game/UI/HUD")
var player := get_node("../../Player")

# ПРАВИЛЬНО — через группы
var players: Array[Node] = get_tree().get_nodes_in_group("player")

# ПРАВИЛЬНО — через экспорт и настройку в редакторе
@export var target_node: Node

# ПРАВИЛЬНО — через EventBus (не нужна ссылка вообще)
EventBus.player_health_changed.emit(new_health)
```

### 3.3 Никаких God-классов

Если скрипт превышает **200 строк** — он слишком большой. Разбей на подсистемы.

```gdscript
# НЕПРАВИЛЬНО — один файл player.gd на 800 строк:
# движение + анимация + инвентарь + крафт + стрельба + выживание

# ПРАВИЛЬНО — разбивка по компонентам и системам:
# Player (CharacterBody2D)
# ├── PlayerMovement.gd        ← Только движение
# ├── HealthComponent           ← Только здоровье
# ├── InventoryComponent        ← Только инвентарь
# ├── StateMachine              ← Управление состояниями
# └── ...
```

### 3.4 Никаких прямых зависимостей между системами

```gdscript
# НЕПРАВИЛЬНО — BuildingSystem знает о SurvivalSystem
func place_wall(pos: Vector2i) -> void:
    # ...
    var survival: SurvivalSystem = get_node("/root/SurvivalSystem")
    survival.recalculate_room_oxygen()  # Прямая зависимость!

# ПРАВИЛЬНО — через событие
func place_wall(pos: Vector2i) -> void:
    # ...
    EventBus.building_placed.emit(&"wall", pos)
    # SurvivalSystem сам подписан на это событие и пересчитает
```

### 3.5 Никаких `match` / `if` по строкам для определения типа

```gdscript
# НЕПРАВИЛЬНО — добавление нового типа = изменение кода
func use_item(item_id: String) -> void:
    match item_id:
        "medkit": heal(50)
        "antidote": reduce_toxicity(30)
        "food_ration": restore_hunger(40)
        # ... растёт бесконечно

# ПРАВИЛЬНО — полиморфизм через данные
# Каждый ItemData имеет массив эффектов:
func use_item(item: ItemData) -> void:
    for effect: ItemEffect in item.effects:
        effect.apply(self)

# data/items/medkit.tres:
# effects = [HealEffect(amount=50)]
# data/items/antidote.tres:
# effects = [ReduceToxicityEffect(amount=30)]
```

---

## 4. Правила для систем проекта

### 4.1 Как писать новую систему

Каждая система — это Autoload или нода, которая:

1. **Подписывается на EventBus** при `_ready()`
2. **Читает данные из Registry** (не из хардкода)
3. **Испускает сигналы EventBus** при изменении состояния
4. **Не знает о других системах** (только EventBus и Registry)
5. **Имеет свой Resource-файл** с балансовыми параметрами

```gdscript
# Шаблон новой системы
class_name MyNewSystem
extends Node

## Ресурс с настройками баланса этой системы.
@export var balance: MySystemBalance = null

func _ready() -> void:
    # Подписка на нужные события
    EventBus.some_event.connect(_on_some_event)

func _on_some_event(data: Variant) -> void:
    # Реакция на событие
    var result: float = _calculate(data)
    # Уведомление о результате
    EventBus.my_result_changed.emit(result)

func _calculate(data: Variant) -> float:
    # Логика использует balance, а не хардкод
    return data * balance.multiplier
```

### 4.2 Правила для данных (Resources)

```gdscript
# Каждый тип данных — отдельный Resource-класс
class_name RecipeData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var station_type: StringName = &""  # ID станции крафта
@export var craft_time: float = 1.0
@export var ingredients: Array[RecipeIngredient] = []
@export var results: Array[RecipeResult] = []
@export var required_tech: StringName = &""  # Какая технология нужна
@export var tags: Array[StringName] = []

# Вложенный ресурс для ингредиентов
class_name RecipeIngredient
extends Resource

@export var item_id: StringName = &""
@export var amount: int = 1
```

### 4.3 Правила для UI

```gdscript
# UI НИКОГДА не меняет игровые данные напрямую.
# UI только:
# 1. Подписывается на EventBus и обновляет отображение
# 2. При действии пользователя — создаёт Command или эмитит сигнал

# НЕПРАВИЛЬНО
func _on_craft_button_pressed() -> void:
    player.inventory.remove(iron_ingot, 3)
    player.inventory.add(rifle, 1)

# ПРАВИЛЬНО
func _on_craft_button_pressed() -> void:
    var cmd := CraftCommand.new(&"rifle_recipe")
    CommandManager.execute(cmd)
```

### 4.4 Правила для сохранения/загрузки

Каждая система реализует интерфейс сериализации:

```gdscript
# Каждая система, чьё состояние нужно сохранять,
# реализует эти два метода:

## Вернуть текущее состояние как словарь.
func save_state() -> Dictionary:
    return {
        "oxygen": _oxygen,
        "toxicity": _toxicity,
        "temperature": _temperature,
    }

## Восстановить состояние из словаря.
func load_state(data: Dictionary) -> void:
    _oxygen = data.get("oxygen", 1.0)
    _toxicity = data.get("toxicity", 0.0)
    _temperature = data.get("temperature", 20.0)
```

---

## 5. Правила для модов

### 5.1 Расширяемость через данные

Мод добавляет новый предмет — он просто кладёт `.tres` файл в свою папку:

```
mods/alien_weapons/
├── mod.tres                       ← ModData resource
├── data/items/plasma_rifle.tres   ← Новый предмет
├── data/recipes/plasma_rifle_recipe.tres
└── assets/sprites/plasma_rifle.png
```

ModLoader при загрузке сканирует папку мода и регистрирует все ресурсы в Registry.

### 5.2 Расширяемость через хуки

```gdscript
# Система крафта вызывает хуки до и после крафта:
func craft(recipe: RecipeData) -> bool:
    # Хук "до крафта" — моды могут отменить или модифицировать
    var context := {"recipe": recipe, "cancel": false}
    EventBus.before_craft.emit(context)
    if context.cancel:
        return false

    # ... логика крафта ...

    # Хук "после крафта" — моды могут добавить эффекты
    EventBus.after_craft.emit({"recipe": recipe, "result": result_item})
    return true
```

### 5.3 Расширяемость через переопределение

Моды могут заменить Resource в реестре:

```gdscript
# Мод переопределяет баланс железной руды:
# mods/harder_mode/data/items/iron_ore.tres
# Тот же id="iron_ore", но weight=10.0 вместо 5.0
# ModLoader загрузит его ПОСЛЕ базовых данных и перезапишет
```

---

## 6. Соглашения по Git

### 6.1 Структура коммитов

```
[система] краткое описание

feat(survival): добавлена шкала токсичности
fix(building): исправлен расчёт герметичности
refactor(crafting): вынесены рецепты в ресурсы
data(items): добавлены 5 новых руд
docs: обновлён GDD раздел про фауну
```

### 6.2 Ветки

```
main              ← Стабильная версия
develop           ← Активная разработка
feature/survival  ← Новая фича
fix/airlock-bug   ← Исправление бага
```

---

## 7. Чеклист перед коммитом

Перед каждым коммитом (и перед каждой генерацией кода ИИ) проверь:

- [ ] Нет magic numbers — все числа в ресурсах или константах
- [ ] Нет строковых путей к нодам — используются группы, экспорт или EventBus
- [ ] Все переменные и функции типизированы
- [ ] Скрипт не превышает 200 строк
- [ ] Система не знает о других системах напрямую
- [ ] Новые данные — в .tres файлах, не в коде
- [ ] Есть документация (## комментарии) для классов и публичных методов
- [ ] Сигналы именованы в прошедшем времени
- [ ] Если добавлен новый тип данных — обновлён Registry
- [ ] Если добавлено новое событие — добавлено в EventBus
- [ ] Соблюдён порядок элементов в скрипте (раздел 1.2)

---

## 8. Инструкция для ИИ-ассистентов

> **Этот раздел читают Claude, Gemini и другие ИИ при генерации кода для проекта.**

### При получении задачи:

1. **Прочитай этот документ** и GDD перед написанием кода
2. **Определи, к какой системе относится задача** (survival, building, crafting, combat, ai, transport, events, ui)
3. **Проверь, есть ли существующие компоненты,** которые можно переиспользовать
4. **Создай Resource-файл** для любых новых данных
5. **Используй EventBus** для межсистемных коммуникаций
6. **Не создавай зависимостей** между системами

### При генерации кода:

- Всегда используй `class_name`
- Всегда используй типизацию
- Всегда добавляй `##` документацию
- Группируй элементы по порядку из раздела 1.2
- Именуй файлы и переменные по правилам раздела 1.1
- Проверяй чеклист из раздела 7

### При предложении архитектурных решений:

- Всегда объясняй, как это расширяется модами
- Всегда объясняй, как это сохраняется/загружается
- Всегда учитывай будущий мультиплеер (Command pattern)
- Никогда не предлагай решения с хардкодом

---

*Документ создан: v1.0*
*Последнее обновление: Март 2026*
