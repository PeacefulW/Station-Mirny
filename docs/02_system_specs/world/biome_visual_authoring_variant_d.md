---
title: Biome Visual Authoring — Variant D (Rock-First)
doc_type: system_spec
status: superseded
owner: engineering+art
source_of_truth: false
version: 1.1
last_updated: 2026-05-17
superseded_by: ./biome_visual_authoring_variant_d_v2.md
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ./world_runtime.md
  - ./terrain_hybrid_presentation.md
  - ./mountain_generation.md
  - ./rock_shader_presentation_iteration_brief.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
---

# Biome Visual Authoring — Variant D (Rock-First)

## 0. Superseded Notice

This document is retained as historical reference for Variant D v1 decisions.
It is superseded by `biome_visual_authoring_variant_d_v2.md`, which is the
canonical active terrain visual source of truth after V2-IT9.

Do not extend this document as the active terrain visual path. New runtime,
editor, recipe, solver, packet, and cutover work belongs to Variant D v2.

## 1. Purpose

Эта спека фиксирует **архитектуру визуального авторинга биома**, в которой
**один и тот же `gdshader` используется и в инструменте-редакторе, и в рантайме
игры**, а параметры авторятся через **`Resource`-файлы (`.tres`)**, привязанные
к конкретному биому.

Spec закрывает повторяющийся класс провалов, наблюдавшихся в итерациях v1 и
testtt: визуал, собранный во внешнем Rust-генераторе и запекаемый в PNG-атлас,
**не давал parity** с тем, что игрок видит в Godot, потому что:

- внешний рендерер и Godot-шейдер реализованы независимо;
- параметры мигрировали через PNG и теряли смысл;
- любая ручка в инструменте требовала повторной разработки в Godot.

Variant D устраняет источник расхождения **по построению**: визуал — это
шейдер плюс параметры. Шейдер ровно один. Параметры — один `.tres`. Tool-сцена
в Godot редакторе и runtime используют один и тот же путь.

Текущий итерационный фокус — **rock (горы)**. Ground и water — отдельные
будущие спеки. См. секцию Scope и Out of Scope.

## 2. Gameplay Goal

Визуал горы должен давать игроку три ощущения одновременно:

1. **Гора как стена с накрытием** — не просто высокая плитка пола, а
   читаемый объём: вертикальная грань (face) + перекрытие сверху (top) +
   ушедшая в тень обратная сторона (back). Это визуальный приём, отличающий
   нас от Factorio cliffs (см. memory `project_mountain_silhouette_intent`).
2. **Sanctuary contrast** — внутри базы и в безопасных зонах гора читается
   как защищающая стена; снаружи — как преграда и угроза. Контраст работает
   через свет/тень и силуэт, не через лор-надписи.
3. **Органическая граница** — силуэт горы выглядит как природная скала, а
   не как квадратный 47-blob набор. Marching-squares по `terrain_id` даёт
   диагонали и плавные углы.

Эти три цели — критерий приёмки визуала, а не только эстетика.

## 3. Scope

**В скоупе этой спеки — только rock.**

- Один `gdshader` для rock (top / face / back).
- Один `Resource`-класс параметров (`BiomeVisualResource`) с минимальным
  подсетом ручек, реально влияющих на финальный кадр.
- Один `.tres` файл с дефолтными значениями для rock-биома.
- Tool-сцена в Godot editor (`@tool` + Inspector) с auto-repaint.
- Marching-squares в C++ внутри WorldCore (`gdextension/src/world_core.cpp`
  или соседний файл) для генерации полилинии силуэта горы.
- Runtime-интеграция: `ChunkView` читает `.tres`, применяет шейдер, рендерит
  силуэт.

## 4. Out of Scope

Явно не входит в эту итерацию:

- **Ground** (земля, почва, материал поверхности вне горы) — отдельная
  будущая спека.
- **Water** (озёра, береговая линия) — отдельная будущая спека.
- **Decals** (детальные накладки, мусор, трещины-как-декали) — обсуждается
  после того, как rock-шейдер стабилизирован.
- **Дополнительные биомы** (tundra, forest и т.п.) — после rock.
- **Custom EditorPlugin / Dock UI** — авторинг идёт через стандартный
  Inspector + `.tres`. Dock — future task (см. Required Follow-Ups).
- **Любой 3D-путь** для горы — остаёмся в 2D top-down.
- **Software-rasterizer fallback** в GDExtension, имитирующий шейдер —
  запрещено по построению (см. Anti-Patterns).
- **PNG-атлас как source-of-truth** для визуала горы — запрещено.
- **Ghost-файлы** `runtime_sdf_contours_iteration_01..07`, упомянутые в
  `docs/02_system_specs/README.md` как несуществующие — здесь не воскрешаем.
  Cleanup — future task.

## 5. Why Variant D (Decision Record)

Рассматривались три направления:

- **Variant A — внешний генератор + PNG-атлас.** Rust-инструмент
  `tools/rimworld-autotile-lab/desktop_app` рендерит спрайты в PNG, Godot
  потребляет их как обычные текстуры. Это путь, по которому шли v1 и testtt.
  **Провал:** parity между PNG и игрой не достигался, потому что Godot
  применял шейдер/освещение поверх запечённого результата, а инструмент — нет.
  Каждый ревёрт parity-проб подтверждал, что расхождение системно.
- **Variant C — два независимых рендерера (Rust для tool, Godot для game),
  с авторингом параметров и сверкой через probe.** Лучше, чем A, но требует
  поддерживать два рендерера и постоянно гонять parity-probe. На практике
  второй рендерер всегда отставал.
- **Variant D — один Godot-шейдер, один путь, `.tres` как авторинг.**
  Parity достигается по построению, потому что tool-preview и runtime —
  это **тот же шейдер с теми же uniforms**. Инструмент перестаёт быть
  отдельной кодовой базой; он становится `@tool`-сценой в Godot.

Решение зафиксировано в memory `project_variant_d_single_renderer_godot`.

## 6. Architectural Overview

Поток данных:

```
BiomeVisualResource (.tres)
        |
        | (uniforms)
        v
  rock_variant_d.gdshader  ────────────────┐
        ^                                  |
        | (тот же путь)                    |
        |                                  v
  [tool-scene preview]            [runtime ChunkView]
  (@tool, Inspector edit)         (game world)


Mountain silhouette:

  chunk terrain_id grid (WorldCore, C++)
        |
        | marching-squares (C++, in gdextension)
        v
  polyline list (per chunk, per edge of rock region)
        |
        v
  rendered as Line2D / canvas-shader overlay
  (uses params from BiomeVisualResource for stroke/contrast)
```

Ключевая инвариантa: **шейдерный путь и параметры — одни и те же** между
редактором и рантаймом. Любая ручка, которую видит художник в Inspector,
немедленно применяется к runtime ChunkView, если запустить игру.

## 7. Source of Truth and Owners

- **Authoritative source of truth для визуала горы** — файл
  `core/data/visuals/rock_biome_visual.tres` (имя финализируется в IT1).
- **Single write owner** — designer/художник, через стандартный Godot
  Inspector в редакторе.
- **Runtime** читает `.tres` как read-only ресурс. **Не мутирует.** Никакой
  ран­тайм-системы, переписывающей параметры, нет.
- **Класс ресурса** — `BiomeVisualResource` (gdscript Resource, `class_name`).
  Описывает только визуальный авторинг, не геймплей.
- **Привязка к биому (binding)** — поле `rock_visual: BiomeVisualResource`
  добавляется **непосредственно в существующие биом-данные** (биом-реестр /
  биом-Resource). Runtime получает ресурс через биом, не через отдельную
  мапу. Решение зафиксировано пользователем 2026-05-16: ссылка живёт в
  биоме, не в отдельной таблице соответствия.

Это согласуется с ADR-0003 (immutable base + runtime diff): `.tres` — это
authored content, не runtime diff. См. секцию Save/Load.

## 8. Runtime Classification

Согласно ADR-0001 (runtime work and dirty/update foundation):

- **Boot** — `BiomeVisualResource` загружается при старте уровня и кэшируется.
  Это одноразовая работа.
- **Background** — marching-squares по чанку запускается, когда:
  - подгружается новый чанк (chunk load),
  - меняется `terrain_id` сразу в большом регионе (например, разрушение).
  Эта работа разбивается на bounded units (chunk-or-smaller). Если граница
  слишком длинная, escalation — split per-edge work между кадрами.
- **Interactive** — мутация **одного тайла** (mining, placement) **не должна
  пересчитывать весь чанк**. Dirty unit — **локальный adjacency**: 3×3 окно
  вокруг изменённого тайла, патч marching-squares в пределах этого окна.
  Целевой бюджет — < 2ms на interactive path (см. ENGINEERING_STANDARDS.md).

Dirty unit определяется явно как **bounded local marching-squares patch**,
а не «весь чанк». Это критично для acceptance test «no main-thread hitch».

## 9. Conflicts with Approved Specs

**`docs/02_system_specs/world/terrain_hybrid_presentation.md` v0.5
(status: approved)** предполагает pre-baked PNG как материал поверхности —
это прямо противоречит Variant D, где source-of-truth для визуала — `.tres`,
а PNG-атласа для горы не существует.

**В рамках этой таски конфликт НЕ разрешается.** `terrain_hybrid_presentation.md`
**не правится**. Конфликт зафиксирован здесь и попадает в Required Follow-Ups
как отдельная задача supersede/частичный пересмотр.

Это сознательное ограничение скоупа — менять approved spec без отдельного
WORKFLOW-прохода запрещено.

## 10. Migration from Rust Generator

Текущий внешний генератор `tools/rimworld-autotile-lab/desktop_app` имеет
большой набор ручек, накопленный за итерации. **В Variant D переезжает
только минимальный подсет, реально влияющий на финальный кадр шейдера.**

Ориентировочный список (точный — фиксируется в IT1):

- **Палитра**: top color, face color, back color (или градиент).
- **Height-band cutoffs**: пороги, где top переходит во face и face в back.
- **Ledge contrast**: контраст между top и face на ребре.
- **Coverage knobs**: top / face / back пропорции в общем покрытии тайла.
- **Normal strength**: интенсивность вычисляемой нормали для освещения.

**НЕ переезжает:**

- Неиспользуемые ручки, добавленные в Rust-генератор «на всякий случай».
- Software-specific kernels, не имеющие GLSL/`gdshader` аналога.
- Внутренние post-process шаги, дублирующие функции Godot материала.

Архивирование самого Rust-приложения — отдельная follow-up таска после
успешного завершения IT1–IT5.

## 11. Shared GDShader Contract

Один файл `assets/shaders/rock_variant_d.gdshader` (точное имя — в IT2)
используется и в tool-сцене (preview), и в runtime (ChunkView).

**Inputs (uniforms)** — биндятся из `BiomeVisualResource`:

- цвета top/face/back (или градиент);
- height-band cutoffs;
- ledge contrast;
- coverage weights;
- normal strength.

**Outputs:**

- `albedo` — итоговый цвет фрагмента;
- `normal` — **публичный output**, потребляется gameplay light renderer
  (фонарики, лампы) для рельефного отклика. Решение зафиксировано
  пользователем 2026-05-16: шейдер скалы интегрирован в pipeline динамического
  света. **Граница с ADR-0005:** normal — это **render-input** для отрисовки
  света; **authoritative gameplay-видимость и safety state остаются за
  light/visibility authority** и нормали из шейдера **не читают**. Если
  authority говорит «темно» — gameplay видит «темно», даже если шейдер
  отрисовал блик от фонарика. См. anti-pattern 8 (переформулирован).
- `mask` — каналы top/face/back для возможной композиции (например, decals
  поверх top, но не поверх face — это иллюстрация будущей ground spec,
  не часть rock scope).

**Parity guarantee** — обеспечивается не сверкой, а **тем, что это
буквально один и тот же `.gdshader`**. Никаких reimplementations.

## 12. Tool Scene Architecture

Tool живёт **как Godot editor plugin** в `addons/biome_visual_authoring/`
(финальное имя плагина — в IT3). Решение зафиксировано пользователем
2026-05-16: идиоматичный путь Godot, плагин включается/выключается флажком
в Project Settings → Plugins, **не пакуется в release build** при
выключенном флаге.

Структура плагина (ориентировочно):

- `addons/biome_visual_authoring/plugin.cfg` — манифест.
- `addons/biome_visual_authoring/plugin.gd` — `EditorPlugin` entry point
  (минимальный, без custom dock в этой итерации).
- `addons/biome_visual_authoring/biome_visual_preview.tscn` — preview-сцена.
- `addons/biome_visual_authoring/biome_visual_preview.gd` — `@tool` скрипт
  preview.

Поведение:

- Корневой скрипт preview помечен `@tool`.
- `@export var biome: BiomeVisualResource` — художник назначает `.tres`
  через Inspector.
- При изменении любого поля ресурса — **auto-repaint** preview в редакторе.
  Реализация — через сигнал `changed` ресурса и `queue_redraw()` / обновление
  материала.
- Side-by-side preview (например, top vs face vs back) — **opt-in через
  свойство в самой preview-сцене**, без отдельного dock.

**UI-решение (зафиксированное):** только Inspector + минимальный
EditorPlugin entry point. Никакого custom dock с пресетами / compare /
gradient editor в этой итерации. Это сознательный выбор, чтобы не тратить
итерационный бюджет на инфраструктуру UI редактора, пока сам шейдер не
доведён. Полноценный dock — Required Follow-Up (25e).

## 13. Mountain Silhouette via Marching-Squares (C++)

**Где живёт код:** `gdextension/src/world_core.cpp` (или новый соседний
`.cpp` файл в той же папке). **НЕ GDScript.** **НЕ software-rasterizer
пиксельный.** Marching-squares — алгоритм извлечения изолиний из 2D-сетки
значений.

**Контракт функции** (имя — в IT4):

- **Input:** `terrain_id grid` чанка (или его подобласти), плюс предикат
  «этот id — rock».
- **Output:** список полилиний (`Vector<PackedVector2Array>`) для каждой
  связной границы rock-региона.

**Кэширование:**

- Результат кэшируется per-chunk.
- Кэш инвалидируется на **bounded local patch** при mutation одного тайла
  (см. секцию Runtime Classification).
- При chunk unload — кэш сбрасывается.

**Escalation path:**

- Если полилиния чанка становится слишком длинной (более N сегментов,
  N задаётся в IT4), работа по marching-squares **разбивается по рёбрам**:
  одно ребро чанка обрабатывается за кадр. Это сохраняет < 2ms бюджет
  на interactive path.

## 14. Runtime Integration

- `ChunkView` (или эквивалент в существующем коде world runtime) при
  активации чанка:
  1. Получает `BiomeVisualResource` биома **через поле `rock_visual` на
     самом биом-Resource** (зафиксировано в секции 7). Никакой отдельной
     мапы биом→визуал нет.
  2. Создаёт `ShaderMaterial` с `rock_variant_d.gdshader` и биндит uniforms
     из ресурса.
  3. Запрашивает у WorldCore (C++) полилинию силуэта горы для этого чанка.
  4. Рендерит силуэт через `Line2D` или canvas-shader overlay, используя
     параметры stroke/contrast из того же ресурса.
- Используются только **safe entry points** в WorldCore (никаких прямых
  обращений к внутреннему состоянию). Если контракт WorldCore нужно
  расширить — это добавление новой функции с явным API, не утечка
  внутренностей.

## 15. Save/Load Impact

**`BiomeVisualResource` — authored content, не runtime diff.**

- Загружается один раз на старте уровня.
- Immutable на сессию.
- **Не сохраняется в save файлы.** В save хранится только id биома (или
  путь к ресурсу), а не значения параметров.

**Mountain silhouette** — derived state из `terrain_id`. **Не сохраняется.**
Восстанавливается из `terrain_id` через marching-squares при load.

Это согласуется с ADR-0003 (immutable base + runtime diff): авторский
ресурс — это база, не diff.

**Grep proof (требуемая проверка после имплементации):**

```
rg "BiomeVisualResource" docs/02_system_specs/meta/packet_schemas.md
rg "BiomeVisualResource" docs/02_system_specs/save/  # ожидание: 0 matches
rg "biome_visual" core/systems/save/                  # ожидание: 0 matches
```

Если ресурс появляется где-либо в save-пути — это баг, не фича.

## 16. Boundary Doc Check

Проверка boundary-документов:

- **`docs/02_system_specs/meta/system_api.md`** — нужно убедиться, что
  WorldCore expose'ит безопасный API для запроса marching-squares
  полилинии. Если нет — IT4 добавляет такую функцию в API. **Это требует
  правки `system_api.md`** в рамках IT4 (отдельный mini-PR на доку,
  не зашитый в большой код-PR).
- **`docs/02_system_specs/meta/event_contracts.md`** — не меняется. Variant D
  не вводит новых событий шины (визуал — это pull от ChunkView, не push).
- **`docs/02_system_specs/meta/packet_schemas.md`** — не меняется.
  `.tres` не передаётся по net/IPC.
- **`docs/02_system_specs/meta/commands.md`** — не меняется. Visual
  authoring не создаёт commands мутации мира.

**Grep proof:**

```
rg "biome_visual_authoring" docs/02_system_specs/meta/
# ожидание: 0 matches до IT4, потом точечные изменения в system_api.md
```

## 17. Implementation Iterations

Семь итераций, каждая ≤ 1 день, c явным runtime work classification, allowed
files, forbidden files, acceptance test и manual/static проверкой.

### IT1 — Resource class + минимальный подсет параметров + первый `.tres`

- **Цель:** определить класс `BiomeVisualResource` и зафиксировать
  окончательный минимальный список параметров.
- **Runtime work class:** boot only (loaded once).
- **Allowed files:**
  - `core/data/visuals/biome_visual_resource.gd` (new, `class_name BiomeVisualResource`)
  - `core/data/visuals/rock_biome_visual.tres` (new, default values)
- **Forbidden files:** любые runtime/world/save файлы.
- **Acceptance test:** в Godot редакторе можно создать новый `.tres` этого
  типа через File → New Resource. Все поля видны в Inspector.
- **Manual verification:** открыть `.tres`, поправить значение, сохранить,
  закрыть, открыть — значение сохранилось.

### IT2 — `rock_variant_d.gdshader` для top/face/back

- **Цель:** один `gdshader`, принимающий uniforms из `BiomeVisualResource`.
- **Runtime work class:** boot (compile once) + interactive (per-frame
  render, GPU).
- **Allowed files:**
  - `assets/shaders/rock_variant_d.gdshader` (new)
- **Forbidden files:** runtime gdscript, save, world streamer.
- **Acceptance test:** шейдер компилируется без ошибок. Применённый к
  тестовой плоскости с дефолтным `.tres` — даёт визуально различимые
  top/face/back зоны.
- **Manual verification:** через тестовую сцену (даже простой Sprite2D
  + ShaderMaterial) убедиться, что изменение color поля в `.tres` меняет
  цвет на экране.

### IT3 — Godot plugin (`addons/`) с `@tool` preview-сценой и auto-repaint

- **Цель:** editor plugin, который перерисовывает preview при изменении
  ресурса. Плагин включается/выключается флажком в Project Settings →
  Plugins, не пакуется в release при выключенном флаге.
- **Runtime work class:** editor-only (не игровой runtime).
- **Allowed files:**
  - `addons/biome_visual_authoring/plugin.cfg` (new, манифест)
  - `addons/biome_visual_authoring/plugin.gd` (new, минимальный
    `EditorPlugin` entry point — без custom dock)
  - `addons/biome_visual_authoring/biome_visual_preview.tscn` (new)
  - `addons/biome_visual_authoring/biome_visual_preview.gd` (new, `@tool`)
- **Forbidden files:** любой custom dock с пресетами / side-by-side
  compare / gradient editor (это Required Follow-Up 25e); runtime world
  файлы; save файлы.
- **Acceptance test:** включить плагин в Project Settings, открыть
  preview-сцену в редакторе, назначить `.tres`, изменить поле — preview
  перерисовался без перезапуска редактора. После выключения флажка плагина
  редактор не падает.
- **Manual verification:** короткое видео или скриншоты до/после изменения
  одной ручки.

### IT4 — Marching-squares в C++ WorldCore

- **Цель:** функция в `gdextension/src/world_core.cpp` (или соседнем
  `.cpp`), извлекающая полилинию границы rock-региона.
- **Runtime work class:** background (chunk load) + interactive (bounded
  local patch).
- **Allowed files:**
  - `gdextension/src/world_core.cpp` (modify) **или** новый соседний `.cpp`
  - соответствующий header
  - GDExtension binding registration
  - точечная правка `docs/02_system_specs/meta/system_api.md` (новая
    экспортируемая функция)
- **Forbidden files:** GDScript world runtime, save, любые UI файлы.
- **Acceptance test:** для прямоугольной rock-области (тест-фикстура)
  функция возвращает ожидаемую замкнутую полилинию. Для одного rock-тайла
  посреди ground — возвращает короткий контур.
- **Manual verification:** микро-юнит-тест на стороне C++ (или smoke-сцена
  в Godot, вызывающая функцию и логирующая результат).

### IT5 — Runtime ChunkView reads `.tres` и применяет shader + silhouette

- **Цель:** игровая сцена использует `BiomeVisualResource` через тот же
  `gdshader`, силуэт горы рисуется по полилинии из IT4.
- **Runtime work class:** background (chunk load wiring) + interactive
  (per-frame render).
- **Allowed files:**
  - `core/systems/world/chunk_view.gd` (modify, minimal)
  - возможно одна точка wiring в biome registry чтобы достать `.tres`
- **Forbidden files:** `core/systems/world/world_diff_store.gd`,
  `core/systems/world/world_streamer.gd` (кроме minimal wiring если
  необходимо), save файлы, Rust desktop_app.
- **Acceptance test:** в работающей игре, при загрузке чанка с rock,
  ChunkView применяет `rock_variant_d.gdshader` с параметрами из `.tres`
  и рисует силуэт. Изменение `.tres` (через restart) меняет картинку.
- **Manual verification:** запуск игры, перемещение камеры к горе,
  скриншот.

### IT6 — Golden parity test (tool preview == runtime)

- **Цель:** acceptance test, не feature: скриншот из tool-сцены и скриншот
  из runtime для одного и того же `.tres` должны быть **pixel-identical**
  в контролируемом виде (фиксированная камера, фиксированный размер).
- **Runtime work class:** test-only.
- **Allowed files:**
  - `tests/visual/rock_parity_test.gd` (или эквивалент в существующей
    тестовой структуре) (new)
  - тестовые фикстуры (`.tres`, `.tscn`)
- **Forbidden files:** runtime production файлы.
- **Acceptance test:** parity-тест зелёный — два скриншота побайтово
  совпадают (или с минимальным tolerance, который IT6 решает).
- **Manual verification:** если тест красный — это сигнал, что parity
  потерян; разбираться, не отключать порог.

### IT7 — Removal/archival path for Rust desktop_app

- **Цель:** документировать решение об архивации Rust-генератора в этой же
  спеке (этой секцией и Required Follow-Ups). **Реализация архивации —
  отдельная follow-up таска**, не в этой итерации.
- **Runtime work class:** none (документ + структурный шаг).
- **Allowed files:**
  - этот файл (этой итерацией уже описано).
- **Forbidden files:** удаление кода в Rust до отдельной таски.
- **Acceptance test:** в этом spec присутствует явный пункт о том, что
  Rust-приложение архивируется после успешного завершения IT5; имя
  follow-up таски указано.
- **Manual verification:** прочитать секции 10 и 25 — пункт виден.

## 18. Acceptance Tests (Overall)

- **Golden parity** — IT6 зелёный.
- **No save/load regression** — `BiomeVisualResource` не присутствует в
  save-файле; силуэт горы восстанавливается из `terrain_id` после load;
  существующие save-тесты остаются зелёными.
- **No full chunk rebuild on single tile mutation** — изменение одного
  rock-тайла триггерит только bounded local patch marching-squares, не
  пересчёт всего чанка. Проверяется через лог/инструментирование в IT4.
- **No main-thread hitch на marching-squares** — interactive path
  укладывается в < 2ms; если работа большего чанка/региона не влезает —
  срабатывает escalation (split per-edge), а не блокировка кадра.
- **Mountain silhouette не выглядит как 47-blob square pattern** —
  визуальная приёмка (см. memory `project_mountain_silhouette_intent`):
  на тестовом нерегулярном rock-регионе видны диагонали и плавные углы.

## 19. Anti-Patterns

1. **PNG-атлас как source-of-truth для rock.** Запрещено: ровно этот путь
   проваливал parity в v1 и testtt.
2. **Software-rasterizer в GDExtension, повторяющий gdshader.** Запрещено:
   parity недостижим по построению — это второй рендерер.
3. **Два разных шейдера для tool и runtime.** Запрещено по той же причине,
   что и (2). Шейдер ровно один.
4. **Mountain silhouette в GDScript на каждый кадр.** Запрещено: нарушает
   frame budget; marching-squares — C++ с кэшем.
5. **Marching-squares на весь чанк при мутации одного тайла.** Запрещено:
   нарушает ADR-0001 (bounded units), даёт interactive hitch.
6. **Запекание силуэта в save.** Запрещено: silhouette — derived state из
   `terrain_id`, нарушает ADR-0003.
7. **47-blob квадратный pattern для горы.** Запрещено: теряет органичность,
   противоречит `project_mountain_silhouette_intent`.
8. **Gameplay authority читает normal/albedo из шейдера для решений
   "освещено/темно/безопасно".** Запрещено: нарушает ADR-0005. Шейдерный
   normal output **разрешён** как render-input для рисования света
   фонариком (решение пользователя 2026-05-16, секция 11), но authoritative
   visibility/safety state остаётся за light/visibility authority. Если
   gameplay-система начинает скрейпить пиксели или нормали — это нарушение.
9. **Hardcoded параметры в шейдере без `.tres`.** Запрещено: ломает
   авторинг, заставляет править GLSL вместо ресурса.
10. **Расширение спеки на ground/water в этой же итерации.** Запрещено:
    нарушает memory `user_one_biome_focus` («один биом до блеска»).
11. **Pre-baked atlas как fallback «если шейдер не справится».**
    Запрещено: значит шейдер недостаточен и должен быть доведён, а не
    обойдён атласом.
12. **Полноценный custom dock с пресетами / side-by-side compare /
    gradient editor в IT1–IT7.** Запрещено: явный пользовательский выбор C
    (2026-05-16). Минимальный `EditorPlugin` entry point
    (`addons/biome_visual_authoring/plugin.gd`) в IT3 **разрешён** как
    инфраструктурный носитель плагина; запрещён именно advanced UX dock.
    Полный dock — Required Follow-Up 25e.

## 20. Allowed Files

Точные имена уточняются в каждой IT, но рамка зафиксирована:

- `assets/shaders/rock_variant_d.gdshader`
- `core/data/visuals/biome_visual_resource.gd`
- `core/data/visuals/rock_biome_visual.tres`
- `core/systems/world/chunk_view.gd` (минимальные правки в IT5)
- `gdextension/src/world_core.cpp` (или соседний `.cpp`/`.h` для marching-squares)
- `addons/biome_visual_authoring/plugin.cfg`
- `addons/biome_visual_authoring/plugin.gd`
- `addons/biome_visual_authoring/biome_visual_preview.tscn`
- `addons/biome_visual_authoring/biome_visual_preview.gd`
- поле `rock_visual: BiomeVisualResource` в существующем биом-Resource
  (точный файл — биом-реестр, уточняется в IT5 при wiring)
- `tests/visual/rock_parity_test.gd` (или эквивалент в существующей тестовой структуре, в IT6)
- `docs/02_system_specs/meta/system_api.md` (точечная правка в IT4 при добавлении новой экспортируемой функции)

## 21. Forbidden Files

- `tools/rimworld-autotile-lab/desktop_app/**` — только архивация, не
  активное развитие в рамках этих итераций.
- `core/systems/world/world_diff_store.gd` — диффы здесь не нужны.
- `core/systems/world/world_streamer.gd` — кроме минимального wiring если
  необходимо в IT5.
- Любые save-related файлы (collectors / appliers / save format).
- Любой существующий PNG terrain атлас — не должен использоваться как
  материал для rock в Variant D.
- `docs/02_system_specs/world/terrain_hybrid_presentation.md` — **не
  правится** в этой таске (см. секцию Conflicts).

## 22. Performance / Scalability Guardrails

- **Target scale:** ≥ 9 чанков одновременно загружено (центральный + 8
  соседей). Каждый чанк потенциально содержит rock-регион.
- **Frame budget на silhouette refresh:** при mutation одного тайла —
  < 2ms на bounded local patch; при загрузке нового чанка — fit в
  background budget (см. ENGINEERING_STANDARDS.md), при необходимости
  разбиение по рёбрам через FrameBudgetDispatcher.
- **Escalation:** если размер полилинии превышает порог (точное значение
  фиксируется в IT4), работа делится на per-edge units и распределяется
  по кадрам.
- **GPU side:** шейдер должен оставаться one-pass без heavy branching.
  Любые дорогие эффекты (e.g. multi-tap blur) — флаг и отдельное решение.

## 23. Save/Load and Runtime Diff Boundary

Повторно, явно:

- **`BiomeVisualResource` (`.tres`)** — authored content, не runtime diff.
  Не пишется в save. ADR-0003 совместим.
- **Mountain silhouette polyline** — derived state из `terrain_id`. Не
  пишется в save. Восстанавливается через marching-squares при load.
- **`terrain_id` мутации** — сохраняются существующим механизмом world
  diff store. Эта спека ничего там не меняет.

Если кто-то начнёт сериализовать полилинию силуэта в save — это нарушение
этой спеки и ADR-0003, не оптимизация.

## 24. Open Questions

- Точное окончательное имя `class_name` ресурса (`BiomeVisualResource` vs
  более узкое `RockVisualResource`) — решается в IT1. Если в дальнейшем
  расширяется на ground/water, удобнее иметь общий базовый тип, но это
  зависит от того, делятся ли поля.
- Точный финальный список параметров (см. секцию 10) — фиксируется в IT1.
- Точный C++ контракт marching-squares функции (имя, namespace, способ
  биндинга в GDExtension) — IT4.
- Порог длины полилинии для escalation — IT4.
- Tolerance для golden parity test (pixel-identical или с малым eps?) —
  IT6.
- **Контракт интеграции с gameplay light renderer:** какой точно safe
  entry point у системы освещения принимает normal output rock-шейдера?
  Имя viewport / canvas group / material slot — зафиксировать в IT5 при
  wiring. Граница «render-input vs authority-state» уже зафиксирована
  (секции 11, 14, anti-pattern 8), но конкретный API нужен.
- **Конкретный файл биом-Resource**, в который добавляется поле
  `rock_visual: BiomeVisualResource` — уточняется в IT5 (зависит от
  существующей структуры биом-реестра).
- **Стиль рендеринга силуэта:** `Line2D` vs canvas-shader overlay для
  полилинии из marching-squares (секция 14 даёт OR) — выбор фиксируется в
  IT5, влияет на batching и параметры stroke.
- **Порядок при load:** marching-squares строит силуэт **после**
  применения runtime diff к `terrain_id`, не до. Зафиксировать как
  инвариант в IT5, иначе первый кадр после load покажет силуэт без
  применённых мутаций.

## 25. Required Follow-Ups

Следующие задачи **не входят в эту спеку**, но обязаны быть открыты:

- **(a) Supersede / частичный пересмотр `docs/02_system_specs/world/terrain_hybrid_presentation.md` v0.5**
  в части «PNG как материал поверхности» для rock. Требует отдельного
  WORKFLOW-прохода (review, версия, миграция содержания).
- **(b) Cleanup ghost-файлов** `runtime_sdf_contours_iteration_01..07`
  из `docs/02_system_specs/README.md` — это несуществующие файлы,
  упомянутые как existing. Future docs hygiene task.
- **(c) Архивация `tools/rimworld-autotile-lab/desktop_app`** после
  успешного завершения IT1–IT5: перенос параметров уже произошёл,
  Rust-приложение становится историческим артефактом. Конкретный путь
  архивации (отдельная папка `archive/`, отдельный repo, или удаление с
  ссылкой на git tag) — решается в follow-up.
- **(d) Ground spec и water spec** — отдельные spec'и по той же схеме
  Variant D, после стабилизации rock.
- **(e) Custom EditorPlugin / Dock** для авторинга биомов — UX-улучшение
  поверх существующего Inspector-пути. Только когда rock-pipeline доведён
  до состояния, в котором tooling стоит вложения.

## 26. Out-of-Scope Observations

Замечено, но **не правится** этой таской:

- В `docs/02_system_specs/README.md` присутствуют ссылки на
  `runtime_sdf_contours_iteration_01..07`, которых физически нет в репо —
  см. follow-up (b).
- `terrain_hybrid_presentation.md` v0.5 (approved) конфликтует с этой
  спекой по вопросу источника визуала — см. follow-up (a).
- В Rust-инструменте есть несколько ручек, которые исторически добавлялись
  «на всякий случай» и не влияют на финальный кадр — их миграция в `.tres`
  явно отклонена (секция 10). Если позже выяснится, что одна из них всё
  же нужна — добавляется через нормальный change-request к этой спеке.
- Динамическое освещение (см. memory `dynamic_lighting_planned`) —
  отдельная gameplay-система (ADR-0005). Cosmetic-нормали из шейдера
  rock — не заменяют её и не претендуют на gameplay light.
