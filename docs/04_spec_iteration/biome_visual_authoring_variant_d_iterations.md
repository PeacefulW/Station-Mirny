---
title: Biome Visual Authoring — Variant D Implementation Iterations
doc_type: iteration_brief
status: approved
owner: engineering+art
source_of_truth: false
version: 1.0
last_updated: 2026-05-16
related_docs:
  - ../02_system_specs/world/biome_visual_authoring_variant_d.md
  - ../00_governance/WORKFLOW.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../05_adrs/0005-light-is-gameplay-system.md
---

# Biome Visual Authoring — Variant D: Implementation Iteration Briefs

> Это исполнительный документ под одобренный system spec
> `docs/02_system_specs/world/biome_visual_authoring_variant_d.md` (status:
> approved, v1.0). Спек — источник истины; этот документ — пошаговая
> программа имплементации с готовыми промптами под автономный прогон.

## 0. Codex Autonomous Run Brief

Этот файл рассчитан на автономный многоитерационный прогон агента
(например, ночной Codex). Правила прогона:

1. **Один проход = одна итерация.** После каждой IT агент **обязан**
   написать closure report в формате WORKFLOW.md, прогнать acceptance tests
   и остановиться, если что-то красное.
2. **Никогда не объединять итерации.** Если IT2 уперлась — IT3 не начинать.
3. **Doc-first каждый раз.** Перед началом любой IT агент перечитывает
   обязательный набор (см. секцию 2 ниже), даже если уже читал.
4. **Никаких opportunistic refactor'ов.** Только то, что в `Scope - what
   to do`. Всё лишнее — `Out-of-scope observations` в closure report.
5. **Spec неприкосновенен.** Файл
   `docs/02_system_specs/world/biome_visual_authoring_variant_d.md` в
   рамках IT1–IT7 **не правится**. Если возникает несостыковка между
   спекой и реальностью — фиксируется как blocker, не переписывание
   спеки.
6. **Russian closure reports** с EN-терминами в скобках, согласно
   WORKFLOW.md.

## 1. Repo State Notes (Read Before IT1)

Эти факты в текущем репо влияют на исполнение всех IT:

- **BiomeRegistry** — autoload `core/autoloads/biome_registry.gd`. Тип
  биом-ресурса — `BiomeData` (файл `.gd` под этот класс есть в репо,
  агент локализует через grep по `class_name BiomeData`).
  Биом-ресурсы лежат в `res://data/biomes/`. Default биом — `base:plains`.
- **DaylightSystem** (`core/systems/daylight/daylight_system.gd`) — это
  `CanvasModulate` для дня/ночи. **Не consumer нормалей.** На момент
  написания спеки **gameplay light renderer, потребляющий normal map скалы,
  не существует**. Поэтому IT5 wire'ит шейдер так, чтобы normal output был
  **публичным каналом**, доступным будущему потребителю; реальный consumer
  — отдельный future-task, не входит в эту серию итераций.
- **Orphaned native files** в `gdextension/src/`: `mountain_contour.{cpp,h}`,
  `mountain_field.{cpp,h}` — это код ревёрнутых попыток контура горы
  (`f6b6e06 Revert mountain contour commits` и связанные). **Не использовать
  как базу.** IT4 пишет marching-squares как новый чистый модуль. Удаление
  orphaned файлов — отдельный future-task (см. Spec секция 25b).
- **Rust desktop_app** в `tools/rimworld-autotile-lab/desktop_app/` —
  заархивирован по решению Variant D. В рамках IT1–IT7 **не правится**.
  В нём может быть незакоммиченный diff на момент старта прогона — это
  не блокер, агент его не трогает.
- **`terrain_hybrid_presentation.md` v0.5** (approved) конфликтует с
  Variant D по PNG-as-material. **Не правится** в IT1–IT7 (см. spec
  секция 9).

## 2. Required Reading (Every Iteration Start)

Перед началом **любой** IT агент читает в этом порядке:

1. `AGENTS.md`
2. `docs/README.md`
3. `docs/00_governance/WORKFLOW.md`
4. `docs/00_governance/ENGINEERING_STANDARDS.md`
5. `docs/00_governance/PROJECT_GLOSSARY.md`
6. `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
7. `docs/05_adrs/0003-immutable-base-plus-runtime-diff.md`
8. `docs/05_adrs/0005-light-is-gameplay-system.md`
9. `docs/02_system_specs/world/biome_visual_authoring_variant_d.md` —
   **целиком**.
10. Этот файл (`biome_visual_authoring_variant_d_iterations.md`), секции
    0–1 и секция текущей IT.

## 3. Common Sequencing

```
IT1 → IT2 → IT3 → IT4 → IT5 → IT6 → IT7
```

Каждая последующая зависит от предыдущей. Если IT_n не прошла acceptance —
**стоп**, ждать ручного разбора. Не переходить через blocker.

---

## 4. IT1 — Resource Class + Default `.tres`

### Required reading
- См. секцию 2 этого файла.
- Spec секции: 7, 10, 17 (IT1), 19 (anti-patterns 1, 9), 24.

### Task
Создать GDScript Resource класс `RockVisualResource` с минимальным
подсетом параметров визуала скалы и один default `.tres` файл.

### Context
Этот класс становится **authoritative source-of-truth** для параметров
визуала горы (spec секция 7). Runtime читает его, не мутирует. В IT2
параметры из этого ресурса пойдут в шейдер как uniforms. В IT5 ресурс
крепится к биому через поле `rock_visual` в `BiomeData`.

### Design decisions fixed for this IT
- **Имя класса:** `RockVisualResource` (узкое имя, не общий
  `BiomeVisualResource`). Общий базовый класс будет создан только когда
  ground/water spec'и реально потребуют общих полей. Spec секция 24
  оставляла этот вопрос открытым; здесь фиксируем `RockVisualResource`.
- **Список параметров:** ровно 10 полей (см. ниже). Никаких «на запас».

### Boundary contract check
- Не меняются: `system_api.md`, `event_contracts.md`, `packet_schemas.md`,
  `commands.md` (spec секция 16).
- Resource — authored content, не save boundary (spec секция 15).

### Performance / scalability guardrails
- Runtime class: **boot only.**
- Target scale: один `.tres` на биом.
- Source of truth: `.tres` файл, single write owner — designer через
  Inspector.
- Dirty unit: N/A.
- Escalation path: N/A.

### Scope — what to do
1. Создать `core/data/visuals/biome_visual_resource.gd` (создать папку
   `visuals` если её нет):
   ```gdscript
   class_name RockVisualResource
   extends Resource

   ## Authored visual parameters for rock surface.
   ## Source of truth — see
   ## docs/02_system_specs/world/biome_visual_authoring_variant_d.md.

   @export var top_color: Color = Color(0.72, 0.70, 0.66)
   @export var face_color: Color = Color(0.45, 0.42, 0.40)
   @export var back_color: Color = Color(0.22, 0.20, 0.19)

   @export_range(0.0, 1.0, 0.01) var top_to_face_cutoff: float = 0.62
   @export_range(0.0, 1.0, 0.01) var face_to_back_cutoff: float = 0.28

   @export_range(0.0, 2.0, 0.05) var ledge_contrast: float = 1.2

   @export_range(0.0, 1.0, 0.01) var top_coverage: float = 0.55
   @export_range(0.0, 1.0, 0.01) var face_coverage: float = 0.30
   @export_range(0.0, 1.0, 0.01) var back_coverage: float = 0.15

   @export_range(0.0, 2.0, 0.05) var normal_strength: float = 1.0
   ```
   Никаких методов, никаких сигналов, чистый dumb resource.

2. Создать `core/data/visuals/rock_biome_visual.tres`:
   - Тип `RockVisualResource`.
   - Дефолтные значения из (1) — менять не нужно, `.tres` фиксирует
     сериализованный snapshot.

### Scope — what NOT to do
- Не создавать шейдер.
- Не создавать tool/plugin сцены или addons-каталог.
- Не править `core/systems/world/**`.
- Не править `core/autoloads/biome_registry.gd`.
- Не править `BiomeData` (биом-binding — IT5).
- Не привязывать ресурс к биому в этой итерации.
- Не делать общий базовый `BiomeVisualResource` без явного запроса.
- Не добавлять параметры «на будущее», не указанные выше.
- Не трогать `tools/rimworld-autotile-lab/desktop_app/`.

### Files that may be touched
- `core/data/visuals/biome_visual_resource.gd` (new)
- `core/data/visuals/rock_biome_visual.tres` (new)

### Files that must NOT be touched
- Любой файл в `core/systems/`, `core/autoloads/`, `gdextension/`.
- Любой существующий `.tres` биома или PNG terrain атлас.
- Любой spec/ADR в `docs/`.

### Acceptance tests
- [ ] `.gd` файл парсится без ошибок Godot. (Static verification: загрузка
      файла Godot'ом, либо `grep "class_name RockVisualResource"` +
      проверка отсутствия синтаксических ошибок визуально.)
- [ ] В Godot редакторе через File → New Resource можно создать
      `RockVisualResource`. **Manual human verification required.**
- [ ] `rock_biome_visual.tres` существует и открывается в Inspector с
      видимыми 10 полями. **Manual human verification required.**
- [ ] `grep "RockVisualResource" docs/02_system_specs/meta/` → 0 matches.
- [ ] `grep "RockVisualResource" core/systems/save/` → 0 matches.

### Result format
Closure report по WORKFLOW.md шаблону (русский + EN термины). Обязательно:
- grep proofs выше.
- `Canonical Docs Updated`: `not required` для всех meta docs (с grep
  proof). Spec Variant D не правится.

---

## 5. IT2 — Single `gdshader` for Tool and Runtime

### Required reading
- См. секцию 2.
- Spec секции: 11, 17 (IT2), 19 (anti-patterns 2, 3).

### Task
Написать **один** `gdshader` для рендера rock-поверхности, принимающий
все uniforms из `RockVisualResource`.

### Context
Этот шейдер — единственный рендерер скалы. Используется и в editor
preview (IT3), и в runtime (IT5). Parity между ними обеспечивается тем,
что это **буквально один файл**, не два разных пути.

### Design decisions fixed for this IT
- **Имя файла:** `assets/shaders/rock_variant_d.gdshader`.
- **Тип:** `canvas_item` (2D top-down проект).
- **Outputs:**
  - `ALBEDO` или `COLOR` — итоговый цвет фрагмента.
  - `NORMAL_MAP` — публичный канал для будущего gameplay light
    consumer (spec секция 11). **На момент IT2 потребителя нет** — это
    канал на будущее, не активная интеграция.

### Boundary contract check
- Меняемые boundary docs: нет.

### Performance / scalability guardrails
- Runtime class: **boot** (compile once) + **interactive** (per-frame GPU).
- Шейдер — GPU work, не main-thread CPU. Бюджет — GPU, не CPU
  frame budget.

### Scope — what to do
1. Создать `assets/shaders/rock_variant_d.gdshader`:
   - `shader_type canvas_item;`
   - Uniforms, **в порядке полей** `RockVisualResource`:
     - `uniform vec4 top_color : source_color`
     - `uniform vec4 face_color : source_color`
     - `uniform vec4 back_color : source_color`
     - `uniform float top_to_face_cutoff : hint_range(0.0, 1.0) = 0.62;`
     - `uniform float face_to_back_cutoff : hint_range(0.0, 1.0) = 0.28;`
     - `uniform float ledge_contrast : hint_range(0.0, 2.0) = 1.2;`
     - `uniform float top_coverage : hint_range(0.0, 1.0) = 0.55;`
     - `uniform float face_coverage : hint_range(0.0, 1.0) = 0.30;`
     - `uniform float back_coverage : hint_range(0.0, 1.0) = 0.15;`
     - `uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;`
   - `fragment()` функция:
     - На основе `UV.y` (или встроенного field — на твоё усмотрение)
       определяет zone: top если `UV.y < top_to_face_cutoff`, back если
       `UV.y > 1.0 - face_to_back_cutoff`, иначе face.
     - Применяет `ledge_contrast` как контраст между top и face на
       границе.
     - Смешивает цвета пропорционально `*_coverage` weights.
     - Выставляет `NORMAL_MAP` через простой gradient (например,
       Y-направленная нормаль масштабированная на `normal_strength`).
       **Не пытаться** воспроизводить точную форму скалы — этим займётся
       IT4 marching-squares + IT5 silhouette overlay.

### Scope — what NOT to do
- Не создавать второй шейдер «для tool».
- Не создавать `ShaderMaterial.tres` файл — материал создаётся
  программно в IT3 и IT5.
- Не вставлять hardcoded цвета в шейдер вне defaults для uniform'ов.
- Не пытаться вычислять marching-squares контур в шейдере.
- Не trying to PBR — это canvas_item, не spatial.

### Files that may be touched
- `assets/shaders/rock_variant_d.gdshader` (new)

### Files that must NOT be touched
- `core/**`, `gdextension/**`, `addons/**`, `tools/**`, `docs/**`,
  `tests/**`.

### Acceptance tests
- [ ] Шейдер компилируется без ошибок Godot. (Static verification:
      Godot Output panel не показывает shader errors; либо `grep` по
      `assets/shaders/rock_variant_d.gdshader` подтверждает корректный
      синтаксис.) **Manual human verification required** (Godot должен
      реально его скомпилировать).
- [ ] Все 10 uniform'ов из `RockVisualResource` присутствуют по именам.
      (Static verification: grep каждого имени поля в `.gdshader`.)
- [ ] Шейдер применённый к тестовому `ColorRect` или `Sprite2D` с
      `rock_biome_visual.tres` даёт визуально различимые top/face/back
      зоны. **Manual human verification required.**

### Result format
Closure report. Grep proofs: каждое из 10 uniform-имён найдено в файле
шейдера ровно один раз (или столько раз, сколько использовано).

---

## 6. IT3 — Godot Editor Plugin with `@tool` Preview

### Required reading
- См. секцию 2.
- Spec секции: 12, 17 (IT3), 19 (anti-pattern 12).

### Task
Создать минимальный Godot editor plugin в `addons/biome_visual_authoring/`
с `@tool` preview-сценой, которая авто-перерисовывает rock-материал при
изменении `.tres`.

### Context
Плагин — единственная авторинг-поверхность для Variant D (spec секция 12).
Никакого custom dock с пресетами / compare / gradient editor — это
future task (spec 25e). Плагин **не пакуется в release** при выключенном
флажке в Project Settings.

### Design decisions fixed for this IT
- **Имя плагина:** `biome_visual_authoring`.
- **Корневой путь:** `addons/biome_visual_authoring/`.
- **EditorPlugin entry point:** минимальный — только регистрация плагина,
  без custom dock / tool buttons / inspector plugins.

### Boundary contract check
- Меняемые boundary docs: нет (editor-only).

### Performance / scalability guardrails
- Runtime class: **editor-only** (не игровой runtime).
- Не должен влиять на boot time игры при выключенном флажке.

### Scope — what to do

1. **`addons/biome_visual_authoring/plugin.cfg`** (new):
   ```ini
   [plugin]
   name="Biome Visual Authoring"
   description="Tool scene for authoring rock visual parameters (Variant D)."
   author="Station Mirny"
   version="1.0"
   script="plugin.gd"
   ```

2. **`addons/biome_visual_authoring/plugin.gd`** (new):
   ```gdscript
   @tool
   extends EditorPlugin

   func _enter_tree() -> void:
       pass

   func _exit_tree() -> void:
       pass
   ```
   Минимальный entry point. Никаких custom dock/buttons.

3. **`addons/biome_visual_authoring/biome_visual_preview.tscn`** (new) —
   простая сцена:
   - Root: `Node2D` с прикреплённым `biome_visual_preview.gd`.
   - Child: `Sprite2D` (или `ColorRect` нужного размера) с
     `ShaderMaterial`, ссылающимся на `rock_variant_d.gdshader`.

4. **`addons/biome_visual_authoring/biome_visual_preview.gd`** (new):
   ```gdscript
   @tool
   extends Node2D

   @export var biome_visual: RockVisualResource:
       set(value):
           if biome_visual == value:
               return
           if biome_visual:
               biome_visual.changed.disconnect(_on_resource_changed)
           biome_visual = value
           if biome_visual:
               biome_visual.changed.connect(_on_resource_changed)
           _apply_uniforms()

   @onready var _sprite: Node = $Sprite2D  # или ColorRect

   func _ready() -> void:
       _apply_uniforms()

   func _on_resource_changed() -> void:
       _apply_uniforms()

   func _apply_uniforms() -> void:
       if not is_instance_valid(_sprite):
           return
       var mat: ShaderMaterial = _sprite.material as ShaderMaterial
       if mat == null or biome_visual == null:
           return
       mat.set_shader_parameter("top_color", biome_visual.top_color)
       mat.set_shader_parameter("face_color", biome_visual.face_color)
       mat.set_shader_parameter("back_color", biome_visual.back_color)
       mat.set_shader_parameter("top_to_face_cutoff", biome_visual.top_to_face_cutoff)
       mat.set_shader_parameter("face_to_back_cutoff", biome_visual.face_to_back_cutoff)
       mat.set_shader_parameter("ledge_contrast", biome_visual.ledge_contrast)
       mat.set_shader_parameter("top_coverage", biome_visual.top_coverage)
       mat.set_shader_parameter("face_coverage", biome_visual.face_coverage)
       mat.set_shader_parameter("back_coverage", biome_visual.back_coverage)
       mat.set_shader_parameter("normal_strength", biome_visual.normal_strength)
   ```

### Scope — what NOT to do
- Никакого custom dock (`add_control_to_dock`).
- Никаких custom inspector plugins.
- Никаких toolbar buttons.
- Никаких пресетов, side-by-side compare, gradient editor — это 25e.
- Не править файлы вне `addons/biome_visual_authoring/`.
- Не пакуется в release: не править `export_presets.cfg`.

### Files that may be touched
- `addons/biome_visual_authoring/plugin.cfg` (new)
- `addons/biome_visual_authoring/plugin.gd` (new)
- `addons/biome_visual_authoring/biome_visual_preview.tscn` (new)
- `addons/biome_visual_authoring/biome_visual_preview.gd` (new)

### Files that must NOT be touched
- `core/**`, `gdextension/**`, `tools/**`, `assets/**`,
  `docs/**`, `data/**`.
- `project.godot` — флажок плагина включает пользователь вручную.

### Acceptance tests
- [ ] Плагин виден в Project Settings → Plugins. **Manual human
      verification required.**
- [ ] При включении флажка редактор не падает; при выключении — тоже.
      **Manual human verification required.**
- [ ] Открыть `biome_visual_preview.tscn` в редакторе, назначить
      `rock_biome_visual.tres` в `biome_visual` свойство — preview
      отрисовывается. **Manual human verification required.**
- [ ] Поправить значение поля в `rock_biome_visual.tres` (через
      Inspector в открытой preview-сцене) — preview перерисовался без
      перезапуска редактора. **Manual human verification required.**

### Result format
Closure report. Static grep: `grep "add_control_to_dock"
addons/biome_visual_authoring/` → **0 matches** (подтверждает: нет
custom dock).

---

## 7. IT4 — Marching-Squares in C++ WorldCore

### Required reading
- См. секцию 2.
- Spec секции: 13, 17 (IT4), 19 (anti-patterns 4, 5, 7), 24.
- `gdextension/src/world_core.{cpp,h}` — точечно, чтобы понять
  существующий API.
- `gdextension/src/register_types.cpp` — для регистрации новой
  функции.
- `docs/02_system_specs/meta/system_api.md` — точечная правка.

### Task
Реализовать в C++ (GDExtension) функцию extraction'а полилинии
(полилиний) границы rock-региона из `terrain_id` grid'а чанка
через marching-squares.

### Context
GDScript-реализация на каждый кадр запрещена (spec секция 13,
anti-pattern 4). Marching-squares извлекает изолинии из 2D-сетки —
даёт **органический силуэт горы**, а не 47-blob квадратный pattern
(anti-pattern 7).

### Design decisions fixed for this IT
- **Файл:** новый модуль `gdextension/src/rock_marching_squares.{cpp,h}`.
  **Не использовать** orphaned `mountain_contour.{cpp,h}` или
  `mountain_field.{cpp,h}` — они от ревёрнутых попыток, удаление —
  отдельный future task.
- **Класс/функция (предложение):**
  ```cpp
  class RockMarchingSquares : public Object {
      GDCLASS(RockMarchingSquares, Object)
  public:
      // Returns Array of PackedVector2Array, each — closed or open
      // polyline of one rock-region boundary.
      Array extract_polylines(const PackedInt32Array &terrain_ids,
                              int width, int height,
                              int rock_terrain_id) const;
  protected:
      static void _bind_methods();
  };
  ```
  Точное имя и сигнатура — на твоё усмотрение, **но**:
  - Имя `class_name`-эквивалента в Godot: `RockMarchingSquares`.
  - Метод вызывается из GDScript как
    `RockMarchingSquares.new().extract_polylines(...)`.
- **Алгоритм:** классический marching-squares 16-case lookup table.
- **Кэширование:** **не в IT4.** Кэш per-chunk появляется в IT5 на
  GDScript-стороне. IT4 — pure stateless function.
- **Escalation threshold:** не реализуется в IT4 (это
  per-frame budgeting, а pure function вызывается один раз на чанк).
  Зафиксирован в IT5.

### Boundary contract check
- **Меняется:** `docs/02_system_specs/meta/system_api.md` — добавить
  запись о новой экспортируемой GDExtension функции `RockMarchingSquares`.
- Не меняются: `event_contracts.md`, `packet_schemas.md`, `commands.md`.

### Performance / scalability guardrails
- Runtime class: **background** (chunk load) + **interactive** через
  IT5 batching (не в IT4).
- Сложность: O(width × height) на чанк. Для типичного чанка 32×32 это
  ~1024 cells — ничтожно.
- Pure function, без аллокаций кроме output Array.

### Scope — what to do

1. Создать `gdextension/src/rock_marching_squares.h`:
   - Заголовок класса `RockMarchingSquares : public Object`.
   - Объявление `extract_polylines(...)`.
   - `_bind_methods()`.

2. Создать `gdextension/src/rock_marching_squares.cpp`:
   - Реализация marching-squares через 16-case lookup.
   - Соединение сегментов в полилинии (`union-find` или простой
     trace).
   - Возврат `Array<PackedVector2Array>`.

3. Зарегистрировать в `gdextension/src/register_types.cpp` (modify):
   - `ClassDB::register_class<RockMarchingSquares>();` в существующей
     функции initialize_module (имя функции — как в текущем коде).
   - Include нового header'а.

4. Обновить `SConstruct` / `build` конфиг если требуется (в проекте
   может быть автоматический glob `.cpp` — проверить). Не вводить
   новый build system.

5. Точечная правка `docs/02_system_specs/meta/system_api.md`:
   - Добавить запись в существующую секцию GDExtension API:
     `RockMarchingSquares.extract_polylines(...)` — описание, входы,
     выходы, ссылка на spec
     `biome_visual_authoring_variant_d.md` секция 13.

### Scope — what NOT to do
- Не править `mountain_contour.{cpp,h}` (orphaned).
- Не править `mountain_field.{cpp,h}` (orphaned).
- Не интегрировать с `ChunkView` (это IT5).
- Не делать кэш / per-frame batching / escalation (IT5).
- Не трогать GDScript мир.
- Не править `register_types.cpp` глобально — только добавить одну
  регистрацию.

### Files that may be touched
- `gdextension/src/rock_marching_squares.h` (new)
- `gdextension/src/rock_marching_squares.cpp` (new)
- `gdextension/src/register_types.cpp` (modify, минимально)
- `gdextension/src/register_types.h` (modify, если требуется include)
- `SConstruct` или эквивалент build конфига (modify, если требуется)
- `docs/02_system_specs/meta/system_api.md` (modify, точечно)

### Files that must NOT be touched
- `gdextension/src/mountain_contour.{cpp,h}` — orphaned.
- `gdextension/src/mountain_field.{cpp,h}` — orphaned.
- `gdextension/src/world_core.{cpp,h}` — не нужно для marching-squares.
- Любой GDScript файл в `core/**`.
- Любой spec кроме `system_api.md`.

### Acceptance tests
- [ ] GDExtension компилируется без ошибок и warnings (или с warnings,
      уже существовавшими до этой IT). **Manual human verification
      required** (запустить `scons` или эквивалент).
- [ ] Smoke test: вызвать `RockMarchingSquares.new().extract_polylines(...)`
      из любого тестового GDScript скрипта на фикстуре:
      - 3×3 grid, центральная клетка = rock_id, остальные = 0 →
        возвращается **1 замкнутая полилиния** с 4 сегментами вокруг
        центра.
      - 3×3 grid, все клетки = 0 → возвращается пустой Array.
      - 4×4 grid, левая половина = rock_id → возвращается 1
        вертикальная полилиния.
      **Manual human verification required**, либо автоматический GUT
      тест.
- [ ] `system_api.md` содержит запись о `RockMarchingSquares`.
      `grep "RockMarchingSquares" docs/02_system_specs/meta/system_api.md`
      → ≥ 1 match.
- [ ] `grep "RockMarchingSquares" docs/02_system_specs/world/biome_visual_authoring_variant_d.md`
      → 0 matches (spec не правится, имя ещё не было зафиксировано в
      спеке — мы фиксируем здесь и в meta).

### Result format
Closure report. Static verification: build лог; grep'ы выше.
Performance artifacts: статически — линейная сложность подтверждается
кодом; runtime — `not run in this task per policy`, manual human check
рекомендован.

---

## 8. IT5 — Runtime ChunkView Wiring + Silhouette Rendering

### Required reading
- См. секцию 2.
- Spec секции: 7, 8, 14, 17 (IT5), 19, 24.
- `core/autoloads/biome_registry.gd` — целиком, чтобы понять
  Resource access.
- Существующий `BiomeData` GDScript класс — локализовать через
  `grep "class_name BiomeData" core/`, прочитать.
- `core/systems/world/chunk_view.gd` — целиком.

### Task
Привязать `RockVisualResource` к биому, прокинуть его параметры в
runtime ChunkView, нарисовать силуэт горы по полилинии из IT4.

### Context
Это самая большая итерация. Объединяет всё предыдущее в работающий
runtime.

### Design decisions fixed for this IT
- **Поле `rock_visual: RockVisualResource`** добавляется в **`BiomeData`**
  (не в `BiomeRegistry`). Это поле — единственная точка binding визуала
  к биому.
- **Стиль рендеринга силуэта:** `Line2D`. Причины: проще batching, проще
  стиль stroke (width, color), не требует второго шейдера. Если в
  будущем понадобится stylized stroke — мигрируем на canvas-shader
  overlay (Required Follow-Up).
- **Порядок при load:** `terrain_id` диффы применяются **до** запроса
  marching-squares. Marching-squares вызывается **после** того, как
  ChunkView получил финальный `terrain_id` grid чанка.
- **Bounded local patch на mutation одного тайла:** 3×3 окно вокруг
  изменённого тайла, marching-squares прогоняется только на этом окне,
  полилиния patches существующий результат для чанка.
- **Escalation threshold:** если полилиния чанка превышает **2048
  сегментов**, marching-squares разбивается по 4 рёбрам чанка, по
  одному ребру за кадр. (Число — порог, который IT5 фиксирует, можно
  тюнить в будущем.)
- **Normal channel:** доступен через ShaderMaterial. Реального consumer
  light renderer'а **на момент IT5 не существует** — это viaduct,
  prepared for future. **Не интегрировать с `DaylightSystem`** —
  он `CanvasModulate` для global tint, не consumer нормалей. Future
  consumer — отдельная задача за пределами IT1–IT7.

### Boundary contract check
- Возможная правка: добавление поля в `BiomeData` — это публичный
  ресурс, изменение его API. Если `BiomeData` упомянут в любом
  boundary doc (`system_api.md`, etc.), доку **обновить точечно**.
- grep `BiomeData` по `docs/02_system_specs/meta/` — выполнить **до**
  начала кода. Если matches есть — добавить в scope правку
  соответствующего файла.

### Performance / scalability guardrails
- Runtime class:
  - **boot** (`BiomeRegistry._ready()` — загрузка биом-ресурсов, уже
    существует, мы только дополняем поле в `BiomeData`).
  - **background** (chunk load — построение полилинии).
  - **interactive** (mining/placement одного тайла — bounded local
    patch).
- Target scale: N активных чанков (зависит от world streamer). Для
  каждого — кэшированная полилиния.
- Source of truth: `BiomeData.rock_visual` — write owner designer
  через `.tres`.
- Dirty unit: **3×3 окно вокруг изменённого тайла** для interactive
  path.
- Escalation path: split per-edge, 1 edge/frame, при превышении
  порога 2048 сегментов.

### Scope — what to do

1. **Добавить поле в `BiomeData`** (modify):
   ```gdscript
   @export var rock_visual: RockVisualResource
   ```
   Поле может быть `null` для биомов без скалы — обработка через
   `null`-check в ChunkView.

2. **Открыть default `BiomeData` для plains** (или другой биом, где
   логически есть rock — определить через чтение существующих
   `data/biomes/*.tres`), назначить `rock_biome_visual.tres` в поле
   `rock_visual`. Если plains не использует rock — найти подходящий
   биом или создать новый минимальный `rock_test_biome.tres` в
   `data/biomes/` для целей smoke test.

3. **`core/systems/world/chunk_view.gd`** (modify, минимально):
   - На chunk load:
     a. Получить `BiomeData` через `BiomeRegistry`.
     b. Получить `rock_visual` поле.
     c. Если не null:
        - Создать `ShaderMaterial` с `rock_variant_d.gdshader`.
        - Прокинуть uniforms (как в `biome_visual_preview.gd` из IT3,
          вынесет общую функцию если уместно).
        - Применить материал к rock-cells канвасу/тайлам (точная
          точка применения — там, где уже сейчас применяется текущий
          rock рендер).
     d. Вызвать `RockMarchingSquares.new().extract_polylines(...)` с
        `terrain_id` grid'ом чанка.
     e. Создать `Line2D` node как child, заполнить points полилинии.
        Если полилиний несколько — несколько `Line2D` или один с
        breaks (на твоё усмотрение, точное решение зафиксировать в
        closure report).
   - На chunk unload — удалить созданные `Line2D` nodes, освободить
     материал.
   - На mutation одного тайла (signal/callback):
     - Прогнать marching-squares на 3×3 окне вокруг тайла.
     - Patch существующий `Line2D` (или пересоздать только затронутые
       сегменты).
   - **Escalation:** если полилиния чанка превышает 2048 сегментов,
     marching-squares разбивается на 4 ребра, по одному за кадр.
     Реализовать через простой counter + `set_process(true)`.

### Scope — what NOT to do
- Не править `world_streamer.gd` сверх минимального wiring (если
  вообще требуется).
- Не править `world_diff_store.gd`.
- Не сохранять полилинию в save (spec секция 15, anti-pattern 6).
- Не интегрировать с DaylightSystem.
- Не создавать дополнительные ChunkView'ы.
- Не делать full chunk rebuild на одну мутацию тайла (anti-pattern 5).
- Не использовать `tools/rimworld-autotile-lab/desktop_app/` как
  источник параметров.
- Не пересохранять `rock_biome_visual.tres` с другими дефолтами.

### Files that may be touched
- Файл `BiomeData` (точное имя локализуется в начале IT5; modify).
- Один или несколько `.tres` биомов в `data/biomes/` — только
  назначение поля `rock_visual` (modify).
- Возможно `data/biomes/rock_test_biome.tres` (new) — только если
  существующие биомы не подходят для smoke test.
- `core/systems/world/chunk_view.gd` (modify).
- Возможно `docs/02_system_specs/meta/system_api.md` (modify) — если
  `BiomeData` упомянут.

### Files that must NOT be touched
- `core/systems/world/world_diff_store.gd`.
- `core/systems/world/world_streamer.gd` (кроме minimal wiring, если
  абсолютно необходимо).
- Любой save-related файл.
- `core/systems/daylight/daylight_system.gd`.
- `gdextension/src/world_core.{cpp,h}`.
- `addons/biome_visual_authoring/**` (это authoring, не runtime).
- Любой PNG terrain атлас.
- `docs/02_system_specs/world/biome_visual_authoring_variant_d.md`.
- `docs/02_system_specs/world/terrain_hybrid_presentation.md`.

### Acceptance tests
- [ ] Игра запускается без ошибок. **Manual human verification
      required.**
- [ ] При загрузке чанка с rock-тайлами рендерится материал из
      `rock_variant_d.gdshader` с параметрами из `rock_biome_visual.tres`.
      **Manual human verification required.**
- [ ] Силуэт горы виден как `Line2D` overlay поверх rock-региона,
      форма **не квадратная** (есть диагонали). **Manual human
      verification required.**
- [ ] Mutation одного rock-тайла (mining) **не вызывает** полный
      rebuild чанка — лог/инструментирование показывает только
      bounded patch. **Manual human verification required.**
- [ ] `grep "rock_visual" core/systems/save/` → **0 matches** (поле
      не утекает в save).
- [ ] `grep "extract_polylines" core/systems/save/` → **0 matches**.
- [ ] Save/load round-trip: сохранить, загрузить — силуэт
      восстанавливается из `terrain_id`. **Manual human verification
      required.**

### Result format
Closure report. Performance artifacts: явный замер времени
marching-squares на типичном чанке (32×32 или whatever's actual)
рекомендован как Suggested human check. Если есть авто-инструментация
— включить вывод в лог и приложить.

---

## 9. IT6 — Golden Parity Test

### Required reading
- См. секцию 2.
- Spec секции: 17 (IT6), 18, 24.

### Task
Создать automated parity test, который проверяет, что preview-сцена в
editor (IT3) и runtime рендер (IT5) с одним и тем же `.tres` дают
**pixel-identical** результат (с явным tolerance, фиксируемым здесь).

### Context
Цель — поймать любой будущий drift между tool и runtime. Поскольку
шейдер ровно один (IT2), теоретически diff должен быть 0. Тест ловит
**ошибки wiring** (другие uniforms, другая ориентация, разный размер
viewport), не алгоритмические расхождения.

### Design decisions fixed for this IT
- **Tolerance:** `pixel-identical` с допуском **≤ 1 LSB на канал**
  (то есть RGB(255,0,0) и RGB(254,0,0) считаются равными). Причина —
  GPU floating-point может давать минимальные расхождения между
  driver'ами/платформами, но > 1 LSB — это уже реальный drift.
- **Test scene:** фиксированный `Viewport` 256×256, фиксированный
  `rock_biome_visual.tres` (тот же файл).
- **Framework:** GUT (если уже в проекте) или простой test-сцена с
  `_ready()` ассертами.

### Boundary contract check
- Меняемых boundary docs нет.

### Performance / scalability guardrails
- Runtime class: **test-only.** Не влияет на игру.

### Scope — what to do

1. Создать `tests/visual/rock_parity_test.gd` (создать папки если
   нужно):
   - Спавнит два `Viewport` 256×256.
   - В первый — `biome_visual_preview.tscn` (tool path).
   - Во второй — runtime ChunkView equivalent (минимальный
     fragment, использующий тот же шейдер через тот же материал).
   - Прогоняет 1–2 frame'а.
   - Сравнивает `get_texture().get_image()` двух viewport'ов pixel
     by pixel с tolerance 1 LSB.
   - Fail → красный test с подробным diff (количество расхождений,
     первая координата с diff'ом).

2. Зарегистрировать test в существующей test-runner структуре
   (если GUT — добавить в test suite; если нет — отдельная test-сцена
   запускаемая вручную).

### Scope — what NOT to do
- Не править production code.
- Не делать tolerance > 1 LSB без явного обоснования.
- Не сохранять reference screenshot в git (фикстуры — да, изображения
  — нет; всё генерируется в test).
- Не пытаться сравнить marching-squares output (это IT5 territory).

### Files that may be touched
- `tests/visual/rock_parity_test.gd` (new)
- `tests/visual/rock_parity_fixture.tscn` (new, если требуется)
- Test runner конфиг (modify, минимально, если требуется).

### Files that must NOT be touched
- `core/**`, `gdextension/**`, `addons/**`, `assets/**`, `data/**`.
- Любой spec.

### Acceptance tests
- [ ] Тест компилируется и запускается. **Manual human verification
      required.**
- [ ] При сегодняшнем коде (IT1–IT5 завершены без багов) тест
      зелёный. **Manual human verification required.**
- [ ] Преднамеренный sabotage: изменить один uniform в preview-пути
      (например, `top_color` на красный) — тест красный с понятным
      сообщением. **Manual human verification required.**

### Result format
Closure report. Если тест красный без sabotage — это blocker,
останавливаемся, IT7 не начинается.

---

## 10. IT7 — Rust desktop_app Archival Documentation

### Required reading
- См. секцию 2.
- Spec секции: 10, 17 (IT7), 25.

### Task
**Только документация.** Зафиксировать в этой серии итераций путь
архивации Rust-генератора `tools/rimworld-autotile-lab/desktop_app/`.
Реальное удаление/перенос — отдельная follow-up таска, не в IT7.

### Context
После IT5 параметры мигрировали в `.tres`, Rust desktop_app больше не
нужен как источник истины. Но удалять его сразу опасно — он может
быть нужен для исторической справки, для извлечения дополнительных
ручек, или для cross-check parity test'а IT6.

### Design decisions fixed for this IT
- **Не удаляем код в IT7.** Только документируем путь.
- **Способ архивации:** git tag `archive/rimworld-autotile-lab-v1`
  на текущий HEAD после прохождения IT6, **затем** отдельная
  follow-up таска удаляет директорию из main, оставляя её доступной
  через tag.

### Boundary contract check
- Никаких.

### Performance / scalability guardrails
- Никаких (документ).

### Scope — what to do

1. Создать файл `tools/rimworld-autotile-lab/ARCHIVED.md`:
   ```md
   # ARCHIVED

   Этот инструмент архивирован 2026-05-16 в рамках перехода на
   Variant D (единый Godot-шейдер на инструмент и игру).

   - Spec миграции:
     `docs/02_system_specs/world/biome_visual_authoring_variant_d.md`.
   - Implementation iterations:
     `docs/04_spec_iteration/biome_visual_authoring_variant_d_iterations.md`.
   - Параметры визуала мигрировали в:
     `core/data/visuals/rock_biome_visual.tres`.
   - Authoring новый — через Godot editor plugin
     `addons/biome_visual_authoring/`.

   **Не вноси сюда изменения.** Если нужно извлечь дополнительный
   параметр — это change-request к spec Variant D, не правка этого
   инструмента.

   Окончательное удаление этой директории — отдельная follow-up
   таска (Spec секция 25c), будет выполнено после git tag
   `archive/rimworld-autotile-lab-v1`.
   ```

2. **Не править ничего другого.**

### Scope — what NOT to do
- Не удалять Rust код.
- Не делать git tag (это вне scope автономного прогона).
- Не править `Cargo.toml`, `*.rs`, никакие исходники Rust.
- Не править spec.
- Не править `docs/02_system_specs/README.md` (cleanup ghost-файлов
  `runtime_sdf_contours_iteration_01..07` — это **отдельный** future
  task, Spec 25b).

### Files that may be touched
- `tools/rimworld-autotile-lab/ARCHIVED.md` (new)

### Files that must NOT be touched
- Всё остальное.

### Acceptance tests
- [ ] Файл `tools/rimworld-autotile-lab/ARCHIVED.md` существует.
      (Static verification: file read.)
- [ ] Содержит ссылку на spec и на этот iteration brief. (Static
      verification: grep'ы.)

### Result format
Closure report. Самая короткая из всех IT.

---

## 11. Closing the Series

После прохождения всех IT1–IT7 — общий final report:

1. Перечислить все 7 closure report'ов кратко (1 строка каждая —
   passed / failed / partial).
2. Проверить, что spec Variant D в `docs/02_system_specs/world/`
   **не был изменён**:
   `git log -1 --format='%H' docs/02_system_specs/world/biome_visual_authoring_variant_d.md`
   должен показать коммит **до начала IT1** или коммит этой
   же серии, **только если** был легитимный point fix через
   change-request (которого мы здесь не санкционировали — значит ноль).
3. Перечислить Required Follow-Ups, которые остаются открытыми:
   - 25a (supersede terrain_hybrid_presentation.md)
   - 25b (cleanup ghost-файлов)
   - 25c (физическое удаление Rust desktop_app + git tag)
   - 25d (ground spec + water spec)
   - 25e (полноценный custom dock)
   - Удаление orphaned `mountain_contour.{cpp,h}` и
     `mountain_field.{cpp,h}`.

## 12. Out-of-Scope Throughout

Если в ходе любой IT агент натыкается на что-то странное (битая
ссылка в README, неконсистентный naming, dead code, etc.) — это
**не правится**, фиксируется в `Out-of-scope observations` closure
report соответствующей IT.

Финальный final report собирает все out-of-scope наблюдения вместе.
