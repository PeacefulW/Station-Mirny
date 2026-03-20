# AGENTS.md — Инструкция для всех ИИ-ассистентов

> Этот файл — **первое что ты читаешь** перед любой работой над проектом «Станция Мирный».

---

## Обязательные документы

Перед любым изменением прочитай:

1. **PROJECT_INSTRUCTIONS.md** — роли, структура проекта, правила работы
2. **CODING_STANDARDS.md** — паттерны, стиль кода, архитектура, локализация
3. **GDD_Station_Mirny.md** — Game Design Document, все механики и лор
4. **GDD_Addendum_v1_2_Resources.md** — ресурсы (руды, флора), прогрессия инструментов, экономическая цепочка

При конфликте между документами: **CODING_STANDARDS.md > GDD > PROJECT_INSTRUCTIONS**.

---

## Золотые правила (нарушение = отклонение)

1. **Никакого хардкода данных.** Числа, строки, пути — в .tres или .po файлах.
2. **Никаких текстов в коде.** Все пользовательские строки — через `Localization.t("КЛЮЧ")`. Русский/английский только в `locale/*.po`.
3. **Системы не знают друг о друге.** Общение через EventBus (сигналы) или Registry (данные).
4. **Всё типизировано.** Каждая переменная, параметр, возвращаемое значение.
5. **Моды — не afterthought.** Каждая система расширяема через данные.
6. **Один скрипт — одна ответственность.** Soft limit 200 строк, hard limit 300.

---

## Архитектурные паттерны (обязательны)

| Паттерн | Где | Пример |
|---------|-----|--------|
| **Data-Driven** | Все данные | ItemData .tres, BuildingData .tres, PlayerBalance .tres |
| **EventBus** | Межсистемное общение | `EventBus.building_placed.emit(pos)` |
| **Registry** | Доступ к данным | `ItemRegistry.get_item("base:iron_ore")` |
| **Command Pattern** | Действия игрока | PlaceBuildingCommand, CraftRecipeCommand |
| **State Machine** | Сущности с состояниями | Player (idle/move/attack/harvest/dead), Enemy |
| **Component Pattern** | Переиспользуемое поведение | HealthComponent, PowerSourceComponent, NoiseComponent |
| **Factory Pattern** | Создание сложных объектов | EnemyFactory, PickupFactory |
| **Services** | Декомпозиция систем | BuildingPlacementService, IndoorSolver, BuildingPersistence |

---

## Локализация (обязательна для любого нового кода)

**Формат:** .po (gettext), отдельный файл на язык: `locale/ru/messages.po`, `locale/en/messages.po`.  
**Ключи:** UPPER_SNAKE_CASE с префиксом: `UI_`, `ITEM_`, `BUILD_`, `FAUNA_`, `FLORA_`, `RECIPE_`, `SYSTEM_`, `LORE_`.  
**Суффикс `_DESC`** = описание/тултип.

```gdscript
# ПРАВИЛЬНО
label.text = Localization.t("UI_INVENTORY_TITLE")
label.text = Localization.t("CRAFT_SUCCESS", {"item": name, "amount": 5})

# НЕПРАВИЛЬНО
label.text = "ИНВЕНТАРЬ"
label.text = "Crafted: %s x%d" % [name, amount]
```

**Data-ресурсы:** `display_name_key = "ITEM_IRON_ORE"`, не `display_name = "Железная руда"`.  
**Команды:** возвращают `message_key` + `message_args`, не текст.

При создании нового предмета/здания/UI — **обязательно** добавь ключи в оба .po файла.

---

## Ресурсы мира (краткая справка)

**Базовые (стартовый биом):** железная руда, медная руда, камень, скрап.  
**Инопланетные:** сидерит (вулканы → сверхпроводник, экспансия), халкит (споровые леса → ускорение дешифровки).  
**Редкие:** предтечий сплав (данжи), спорит, криосталь.  
**Флора:** споростволы (биомасса), коралловые шпили (кремнезём), жилоросты (вода), светомхи, споровые грозди.  
**Деревьев нет** — это чужая планета. Аналог дерева = споростволы.

Подробности → GDD_Addendum_v1_2_Resources.md.

---

## Текущее состояние проекта

**Фаза 1, ~87% завершена.** Работает:

- C++ генерация мира (GDExtension), текстуры земли и ресурсов
- Строительство (стены, батарея, термосжигатель) — Facade + 3 сервиса, save/load
- Инвентарь (стакование, UI на Tab), крафт (1→1, CraftingPanel)
- Энергосистема (PowerSystem, PowerUI на P), BaseLifeSupport (питание→O₂)
- Добыча ресурсов (E), дозаправка термосжигателя
- ИИ врагов на шум (StateMachine, ночной бонус слуха)
- Command Pattern (4 команды + executor), Factory Pattern, State Machine
- Локализация (.po, LocalizationService)

**Осталось:** 5-10 рецептов, фильтровальщик, свет в базе, POI, шлюзовая камера.

---

## Чеклист (проверяй перед каждым ответом)

- [ ] Прочитаны все обязательные документы
- [ ] Нет хардкода данных — числа в .tres, строки в .po
- [ ] Нет русского/английского текста в .gd — всё через `Localization.t()`
- [ ] Новые ключи добавлены в `locale/ru/` И `locale/en/`
- [ ] Data-ресурсы используют `display_name_key`, не `display_name` с текстом
- [ ] Команды возвращают `message_key` + `message_args`, не текст
- [ ] Типизация на всех переменных, параметрах, возвратах
- [ ] Системы общаются через EventBus, не прямые ссылки
- [ ] Действия игрока — через Command Pattern
- [ ] Скрипт ≤ 300 строк, одна ответственность
- [ ] Документация `##` на классе и публичных методах
- [ ] Порядок элементов: class_name → extends → docs → signals → enum → const → @export → public → private → _ready → public methods → private methods
- [ ] Новые данные — в .tres + зарегистрированы в Registry
- [ ] Новые события — добавлены в EventBus
- [ ] Проверено соответствие GDD и GDD Addendum