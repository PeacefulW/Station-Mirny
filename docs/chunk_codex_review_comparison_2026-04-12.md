# Сравнительный анализ: мой ревью vs ревью Codex
_Дата: 2026-04-12_

Контекст: мой ревью охватывал `chunk_manager.gd` (316 КБ).
Ревью Codex охватывает пару `chunk_manager.gd + chunk.gd` (158 КБ).
Совокупно — 474 КБ GDScript в двух файлах.

---

## Что Codex поймал точно и я пропустил

### 1. Главный слепой пятно: chunk.gd — такой же монолит

Мой ревью был ограничен `chunk_manager.gd`. Codex справедливо указывает,
что `chunk.gd` несёт не меньше ответственностей одновременно:

- хранение состояния тайлов (`_terrain_bytes`, `_modified_tiles`, версионирование)
- рендеринг через `TileMapLayer` (5 слоёв)
- fog of war (`_fog_layer`)
- cover/reveal логику (`_revealed_local_cover_tiles`, `_cover_edge_set`)
- progressive redraw + visual batch
- mining/mutation + dirty state
- border seam fixes (`_pending_border_dirty`)
- debug markers (реальные `Polygon2D`-ноды через `_debug_root`)
- flora renderer (`FloraBatchRenderer` с `_draw()` внутри)
- native bridge (`ChunkVisualKernels`, `_try_compute_visual_batch_native`)
- interior macro (`_refresh_interior_macro_layer` — Image + set_pixel в GDScript)

Это подтверждается кодом: в `setup()` создаётся 5 `TileMapLayer` + `FloraBatchRenderer` +
`_debug_root` — всё в одном классе. Проблема системная, не локальная.

---

### 2. Дублирование визуальной логики — прямой риск рассинхрона

Codex называет параллельные пути:
- `_redraw_terrain_tile` vs `_append_terrain_visual_commands`
- `_surface_visual_class` vs `_visual_request_surface_visual_class`
- `_rock_visual_class` vs `_visual_request_rock_visual_class`
- `_resolve_interior_variant` vs `_visual_request_interior_variant`

Это реальная проблема: одно и то же правило "как выглядит тайл" описано в двух местах.
Если правило обновляется в одном — другой отстаёт. Это уже не технический долг,
это активный источник визуальных багов.

Моё ревью не касалось chunk.gd вообще — этот пункт полностью пропущен.

---

### 3. Dictionary с Vector2i — boxing/unboxing в горячих путях chunk.gd

Codex называет конкретные словари с Vector2i ключами в Chunk:
- `_pending_border_dirty: Dictionary`
- `_revealed_local_cover_tiles: Dictionary`
- `_cover_edge_set: Dictionary`
- `_operation_global_terrain_cache: Dictionary`

Это подтверждается кодом: `_build_visual_compute_request` (строки 1035–1084) строит
`terrain_lookup`, `height_lookup`, `variation_lookup`, `biome_lookup` как Dictionary
через вложенный цикл по tiles × 3×3 соседям. Каждый `dict[Vector2i]` — это Variant
boxing плюс хеширование вектора.

Я упоминал `Array[Dictionary]` для задач планировщика в `chunk_manager.gd`,
но не анализировал внутренние словари `chunk.gd`. Это важный пропуск.

---

### 4. Interior macro → native, очень конкретный кандидат

`_refresh_interior_macro_layer()` — GDScript создаёт `Image`, проходит по пикселям
через `set_pixel`, считает шумы. Это почти обязательный кандидат в C++.
У меня в ревью этого не было — потому что я не читал chunk.gd.

---

### 5. Debug через реальные ноды — конкретная утечка

`_rebuild_debug_markers()` создаёт `Polygon2D` дочерние ноды.
Вызывается из `apply_visual_dirty_batch` при `mountain_debug_visualization == true`
(строки 1029–1032 в chunk.gd). Реальные ноды для debug — это неприемлемо в core runtime:
дорогое создание, дорогой обход scene tree.

Codex прав. Я это не поймал — опять же из-за ограниченного scope.

---

### 6. Flora renderer: `ResourceLoader.load()` в `_draw()` fallback

`FloraBatchRenderer._get_cached_texture()` вызывает `ResourceLoader.load()`
если текстура не закэширована (строки 129–131 в chunk.gd). `_draw()` вызывается
каждый раз при перерисовке. Текстуры кэшируются локально внутри каждого renderer —
при 100 загруженных чанках 100 независимых кэшей.

Codex предлагает глобальный кэш текстур вместо chunk-level. Это правильно.

---

## Где я точнее Codex

### 7. Конкретные O(n) алгоритмы с номерами строк

Мой ревью нашёл и точно описал:
- `_has_load_request` — O(n) линейный скан (строки 1394–1399 chunk_manager.gd)
- LRU cache — `find()` + `remove_at()` O(n) (строки 5813–5816)
- `has_method()` в обёртках — рефлексия в горячем пути (строки 1314–1348)
- `_sync_loaded_chunk_display_positions` — O(all chunks) на каждое движение (строки 1388–1392)

Codex не анализировал chunk_manager.gd на этом уровне детализации.
Эти точечные фиксы (Итерации 1–4 в плане) дают быстрый выигрыш с минимальным риском.

---

### 8. Debug guard в планировщике

`_debug_enabled = OS.is_debug_build()` — конкретный механизм изоляции debug-кода
от release-пути. Codex говорит "debug убрать из core" в целом, но не даёт
конкретного способа реализации для текущего кода.

---

### 9. `has_method()` кэширование

Codex не упоминает проблему `has_method()` в обёртках chunk_manager.gd.
Это реальная рефлексия в горячих путях — 7 вызовов `has_method()` на каждый
`_canonical_tile`, `_canonical_chunk_coord`, `_offset_tile` и т.д.

---

### 10. GDScript topology fallback как anti-pattern

Я выделил это как Итерацию 6 с конкретным решением: убрать GDScript-путь,
оставить только native, добавить `push_error` при отсутствии расширения.
Codex вскользь упоминает topology как кандидат в native, но не акцентирует
на проблеме параллельного поддержания двух путей.

---

## Где я частично согласен, но с нюансами

### 11. Декомпозиция chunk.gd на 7 файлов — направление верное, масштаб завышен

Codex предлагает:
```
chunk_state.gd
chunk_view.gd
chunk_visual_kernel.gd
chunk_cover_state.gd
chunk_fog_state.gd
chunk_debug_renderer.gd
chunk_flora_presenter.gd
```

**Согласен с принципом**: разделение данных (state), отображения (view) и
чистой visual-математики (kernel) — правильная цель. Single source of truth
для визуальных правил — обязательно.

**Не согласен с масштабом одного шага**: 7 файлов из одного монолита за один PR —
это очень высокий риск регрессии. Зависимости между chunk_state и chunk_view
плотные (chunk_view напрямую читает `_terrain_bytes`, `_cover_edge_set` и т.д.).
Нужно 3–4 промежуточных шага, не 7.

**Практичная последовательность**:
1. Сначала `chunk_debug_renderer.gd` — минимальные зависимости, максимальная безопасность
2. Потом `chunk_fog_state.gd` — `_fog_layer` + `underground_fog_state.gd` уже рядом
3. Потом `chunk_flora_presenter.gd` — изолированный FloraBatchRenderer
4. Только потом — более глубокое разделение state/view/kernel

---

### 12. "Первая цель — chunk_visual_kernel" — согласен как архитектурная цель,
но не как первый шаг

Codex: «Самая выгодная первая цель — вынести единый chunk_visual_kernel».

Я согласен, что это наибольший архитектурный выигрыш — единый источник истины
для visual-правил и устранение дублирования.

Но как **первый шаг** это слишком рискованно:
- Дублирующие пути (`_redraw_terrain_tile` vs `_append_terrain_visual_commands`)
  нужно сначала понять и задокументировать
- Неправильная консолидация = введение новых визуальных багов на стыке

Правильный порядок:
1. Сначала покрыть текущее поведение скриншотами/тестами на seam cases и mining
2. Потом вынести debug и flora (безопасно, без risk)
3. Потом консолидировать visual kernel
4. Потом уже native

---

### 13. "Убрать Dictionary из горячих мест" — согласен, но потребует benchmark

Codex прав: `Dict<Vector2i, T>` — boxing, хеширование вектора, indirect access.
Заменить `_pending_border_dirty` и `_revealed_local_cover_tiles` на `PackedByteArray`
(битсет, 1 бит на тайл) даст реальный выигрыш.

Важный нюанс: это изменение затрагивает API между `chunk.gd` и `chunk_manager.gd`
(передача dirty sets). Нужно обновить DATA_CONTRACTS.md и PUBLIC_API.md при переходе.

---

## Где я не согласен с Codex

### 14. Приоритет "метрик прежде изменений"

Codex: «Без этого ты будешь "оптимизировать вслепую". Минимум логируй set_cell за кадр».

Проект уже содержит `WorldPerfProbe` с `begin()`/`end()` и `record()` —
инфраструктура метрик существует. Добавление ещё одного слоя логирования без
предварительных правок потеряет смысл: O(n) `_has_load_request` очевидно дорог
без профайлера, достаточно анализа кода.

Профайлинг важен для валидации после изменений, не как блокер для начала.

---

### 15. "Fix tests first" — в этом проекте нет automated tests

Codex: «Зафиксировал поведение тестами/скриншотами. Особенно на seam cases,
mining edges, cover reveal, underground fog».

Это правильный принцип, но у проекта нет automated test framework —
только `tools/` с ручными validation scripts. Поэтому "тесты" здесь = 
ручной плейтест по конкретным сценариям + скриншоты до/после.
Нужно явно прописать эти сценарии в плане, не надеяться на тестовый suite.

---

## Синтез: что правильно обновить в плане

На основе анализа chunk.gd нужно добавить в
`docs/04_execution/chunk_manager_refactor_plan.md`:

### Новые проблемы из chunk.gd (дополнение к P-01..P-14)

| ID | Проблема | Файл | Приоритет |
|----|----------|------|-----------|
| C-01 | Дублирование visual logic (instance vs request) — риск рассинхрона | chunk.gd | Критический |
| C-02 | `Dict<Vector2i>` в hot path: `_pending_border_dirty`, `_revealed_local_cover_tiles`, `_cover_edge_set` | chunk.gd | Серьёзный |
| C-03 | `_build_visual_compute_request`: nested loop с `terrain_lookup` как Dictionary | chunk.gd | Серьёзный |
| C-04 | Debug markers — реальные Polygon2D ноды в `_rebuild_debug_markers()` | chunk.gd | Серьёзный |
| C-05 | `FloraBatchRenderer`: chunk-level texture cache, `ResourceLoader.load()` в fallback | chunk.gd | Умеренный |
| C-06 | Interior macro: GDScript Image + set_pixel + noise — сильный native-кандидат | chunk.gd | Умеренный |
| C-07 | `global_to_local` вызывает `has_method()` внутри chunk.gd | chunk.gd | Умеренный |

### Скорректированный порядок декомпозиции chunk.gd

Вместо одного шага «7 файлов» — последовательно:

```
Шаг A: chunk_debug_renderer.gd    — _rebuild_debug_markers, _process_debug_marker_tile
Шаг B: chunk_fog_state.gd         — _fog_layer, fog init/update
Шаг C: chunk_flora_presenter.gd   — FloraBatchRenderer + глобальный texture cache
Шаг D: Консолидация visual kernel — после A-C, когда chunk.gd стал компактнее
Шаг E: chunk_state / chunk_view   — финальное разделение данных и отображения
```

Каждый шаг — отдельный PR с ручным плейтестом по сценариям:
seam mining, cover reveal, underground fog, flora visibility, debug overlay.

---

## Итог сравнения

| | Мой ревью | Ревью Codex |
|---|---|---|
| **Охват** | chunk_manager.gd (316 КБ) | chunk_manager + chunk.gd (474 КБ) |
| **Конкретность** | Высокая: строки, сложность, конкретные фиксы | Средняя: принципы и направления |
| **chunk.gd внутренности** | Не рассматривал | Детальный анализ |
| **Дублирование visual logic** | Не нашёл | Точно нашёл |
| **O(n) алгоритмы** | 4 конкретных случая | Общая рекомендация |
| **Декомпозиция** | 5 файлов из chunk_manager | 7 файлов из chunk + 8 из chunk_manager |
| **Native кандидаты** | topology BFS, query pocket | + interior macro, visual batch |
| **Debug guard** | Конкретный механизм | Принцип без impl |
| **Порядок итераций** | Структурированный план | Общая последовательность |

**Ключевой вывод**: оба ревью взаимодополняют друг друга.
Мой план (`chunk_manager_refactor_plan.md`) нужно расширить проблемами C-01..C-07
из chunk.gd и добавить этапы декомпозиции chunk.gd в правильном порядке.
