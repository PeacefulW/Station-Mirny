# CODING_STANDARDS — Патч v1.1

## Что обновить в CODING_STANDARDS.md

Этот файл описывает конкретные изменения. Применять вручную или через ИИ.

---

### 1. Золотые правила (секция 0) — ДОБАВИТЬ правило 6:

После правила 5 добавить:

```
6. **Никаких текстов в коде.** Все строки для пользователя — через ключи локализации (`Localization.t("КЛЮЧ")`). Русский/английский текст живёт только в .po файлах.
```

---

### 2. НОВАЯ СЕКЦИЯ — вставить перед секцией 5 (Правила для модов):

```markdown
## 4b. Локализация

### 4b.1 Формат и структура

**Формат:** .po (gettext) — индустриальный стандарт.
**Ключи:** UPPER_SNAKE_CASE с префиксом категории.
**Файлы:** отдельный .po на каждый язык, в папке `locale/{код_языка}/`.

```
locale/
├── ru/messages.po    ← Русский (fallback)
├── en/messages.po    ← English
└── zh/messages.po    ← 中文 (когда добавим)
```

### 4b.2 Именование ключей

```
UI_*              — интерфейс (UI_INVENTORY_TITLE, UI_POWER_HINT)
ITEM_*            — предметы (ITEM_IRON_ORE, ITEM_IRON_ORE_DESC)
BUILD_*           — здания (BUILD_WALL, BUILD_THERMO_BURNER_DESC)
FAUNA_*           — фауна (FAUNA_CLEANER, FAUNA_FILTERER_DESC)
FLORA_*           — флора (FLORA_SPORESTALK)
RECIPE_*          — рецепты (RECIPE_IRON_SMELT)
LORE_*            — лор и записи
TUTORIAL_*        — обучение
SYSTEM_*          — системные сообщения (SYSTEM_INVENTORY_FULL)
```

Суффикс `_DESC` = описание (тултип, подробный текст).

### 4b.3 Использование в коде

**LocalizationService** (`Localization` autoload) — обёртка над `tr()`:

```gdscript
# Простой текст
label.text = Localization.t("UI_INVENTORY_TITLE")

# С именованными аргументами
label.text = Localization.t("UI_POWER_WATTS", {"supply": 120, "demand": 80})
# В .po: msgstr "{supply} / {demand} Вт"

# Из data-ресурса
label.text = Localization.t(item_data.display_name_key)
```

**НЕПРАВИЛЬНО:**
```gdscript
label.text = "ИНВЕНТАРЬ"                    # Хардкод русского
label.text = tr("UI_POWER_WATTS") % [s, d]  # Позиционные аргументы (хрупко)
```

**ПРАВИЛЬНО:**
```gdscript
label.text = Localization.t("UI_INVENTORY_TITLE")
label.text = Localization.t("UI_POWER_WATTS", {"supply": s, "demand": d})
```

### 4b.4 Data-ресурсы

В ItemData, BuildingData, RecipeData — хранить ключи, не тексты:

```gdscript
# НЕПРАВИЛЬНО — текст в ресурсе
@export var display_name: String = "Железная руда"

# ПРАВИЛЬНО — ключ локализации
@export var display_name_key: String = "ITEM_IRON_ORE"
@export var description_key: String = "ITEM_IRON_ORE_DESC"
```

В UI:
```gdscript
name_label.text = Localization.t(item_data.display_name_key)
desc_label.text = Localization.t(item_data.description_key)
```

### 4b.5 Команды (Command Pattern)

Команды возвращают ключи, не тексты:

```gdscript
# НЕПРАВИЛЬНО
return {"success": false, "message": "Инвентарь полон!"}

# ПРАВИЛЬНО
return {
    "success": false,
    "message_key": "SYSTEM_INVENTORY_FULL",
    "message_args": {"overflow": leftover},
}
```

UI преобразует:
```gdscript
var msg: String = Localization.t(result.message_key, result.get("message_args", {}))
```

### 4b.6 Добавление нового ключа

1. Выбери категорию (UI_, ITEM_, BUILD_, SYSTEM_ и т.д.)
2. Добавь в `locale/ru/messages.po`:
   ```
   msgid "ITEM_NEW_THING"
   msgstr "Новая штука"
   ```
3. Добавь в `locale/en/messages.po`:
   ```
   msgid "ITEM_NEW_THING"
   msgstr "New thing"
   ```
4. В коде: `Localization.t("ITEM_NEW_THING")`

### 4b.7 Переключение языка

```gdscript
TranslationServer.set_locale("en")  # English
TranslationServer.set_locale("ru")  # Русский
EventBus.language_changed.emit(locale_code)
```
```

---

### 3. Чеклист (секция 7) — ДОБАВИТЬ пункты:

```
- [ ] Нет текстов на русском/английском в .gd файлах — всё через Localization.t()
- [ ] Новые ключи добавлены в locale/ru/ И locale/en/
- [ ] Data-ресурсы используют display_name_key, не display_name с текстом
- [ ] Команды возвращают message_key, не текст
```

---

### 4. Инструкция для ИИ (секция 8) — ДОБАВИТЬ в "При генерации кода":

```
- Все пользовательские строки — через Localization.t("КЛЮЧ")
- При создании нового UI/предмета/здания — добавляй ключи в .po файлы
- Команды возвращают message_key + message_args, не русский текст
- Сверяйся с GDD_Addendum_v1_2_Resources.md при создании ресурсов/предметов
```

---

### 5. Структура проекта (секция в начале) — ДОБАВИТЬ locale/:

```
res://
├── core/
│   ├── autoloads/    ← + Localization (LocalizationService)
├── locale/           ← НОВАЯ ПАПКА
│   ├── ru/messages.po
│   └── en/messages.po
```
