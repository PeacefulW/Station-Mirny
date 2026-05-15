# Ревью генератора тайлов `tools/rimworld-autotile-lab/desktop_app`

**Дата:** 2026-05-16
**Объём кода:** ~15k LOC (Rust core + Python shell). `core/src/render.rs` — 8287 строк.
**Фокус:** производительность и контракт экспорта в игру (Godot).
**Метод:** три параллельных подагента (render-горячие пути, контракт экспорта, Python-shell/IPC), сведено в один прио-список. Все ссылки — `file:line`.

---

## КРИТИЧЕСКИЕ — чинить первыми

### 1. Cancel убивает Rust-сервер (вместо переиспользования)
`shell/core_bridge.py:142-144` — `RenderCancelled` зовёт `stop_core_server()`, что делает `terminate()→kill()`. README обещает «один долгоживущий процесс с тёплыми кэшами» — на практике каждое движение слайдера, опередившее предыдущий рендер, убивает процесс и поднимает новый со всеми его кэшами с нуля.
**Фикс:** ввести protocol-level cancel (`{"id":N,"cancel":true}`), Rust дропает работу и шлёт `cancelled`-ответ; либо просто помечать ответ как stale по `id` и не убивать процесс.

### 2. Экспорт неатомарен — Godot ловит полузаписанные PNG
Все `image::save(&path)` (`render.rs:353-365, 441-453`) и `fs::write(&recipe_path,...)` (`render.rs:506,586`) пишут напрямую в `output_dir`. Ни одного `.tmp+rename`, нет `fsync`. Importer Godot, опрашивающий папку, может прочитать обрезанный PNG. Плюс при отмене full-export'а `_handle_cancelled` (`app.py:2104-2105`) не чистит уже записанные файлы.
**Фикс:** в Python — `output_dir = tempfile.mkdtemp(...)`, по успеху `os.replace`; на отмене `shutil.rmtree`. Альтернатива в Rust: писать в `*.tmp`, в конце переименовывать.

### 3. PNG-кодирование — главный wallclock-bottleneck Full16
`render.rs:353-365` и `:441-453`: 11 PNG-атласов сохраняются последовательно одной нитью, каждый с `image::save` (deflate уровня default ≈ 9). Для 2048×2048 RGBA это огромная цена.
**Фикс:** собрать `(path, &RgbaImage)`, прогнать `into_par_iter().for_each(...)` через `rayon`, и переключить кодек на `PngEncoder::new_with_quality(CompressionType::Fast, FilterType::NoFilter)`. По прикидке — ускорение Full16 в разы.

### 4. Дублирующийся `sample_material_color` в горячем пиксельном цикле
`render.rs:1533-1734` (`render_tile_with_field`): на пикселях зоны `Edge` материал семплируется на топ/face/back до 6 раз с одними и теми же координатами (стр. 1568, 1580, 1655, 1667, 1679). Каждый вызов прогоняет 4-7 октав FBM.
**Фикс:** один раз в начале пиксельного блока вычислить `top_sample/face_sample/back_sample` (под флагами coverage>0), переиспользовать.

### 5. Три прохода по тайлу делают одну и ту же градиентную работу
`render.rs:3787-3833` (`apply_crown_bevel`) и `:3836-3881` (`apply_organic_height_relief`) — отдельные `for y { for x }` поверх уже отрендеренного тайла, вызывают `contour_distance_for_field`/`exposed_edge_distance` (а внутри — gradient + 4 distance lookups) на тех же пикселях, что и основной цикл.
**Фикс:** свернуть оба прохода в основной пиксельный цикл — gradient считается один раз.

### 6. Cancel течёт reader-тред + новый тред на каждый запрос
`core_bridge.py:128-153` поднимает свежий daemon-тред на `process.stdout.readline()` для каждого `run_core`. При cancel-через-kill тред живёт до EOF; гонка очевидна.
**Фикс:** один долгоживущий reader-тред на процесс, диспатч ответов в `dict[id]→Queue`.

---

## ВЫСОКИЕ — производительность ядра

### 7. Параллелизм атласа — серийный merge после параллельного рендера
`render.rs:805-814` — таски рендерятся в `rayon`, но финальный blit в 4 RgbaImage идёт последовательно `blit_exact` с проверкой границ. На 4×2048²×4 = 64 МБ это ощутимо.
**Фикс:** аллоцировать 4 raw `Vec<u8>`, в `par_iter` писать в banded-чанки через `chunks_mut` (`build_map_preview_outputs:1256-1290` уже показывает паттерн).

### 8. `apply_mountain_bottom_outline_from_source` клонирует mask и albedo полностью
`render.rs:1801, 1823, 1855` — `mask.clone()`+`albedo.clone()` (по 16 МБ для 2048-атласа) на одном треде, плюс `bottom_outline_strength` гоняет тройной цикл по `(2r+1)²` с `sqrt` в early-out.
**Фикс:** не клонировать albedo (читать из dst), параллелизовать по строкам, заменить `(dx²+dy²).sqrt() > r` на `dx²+dy² > r²`.

### 9. `face_power` в `powf` на каждый пиксель
`render.rs:3698`: `(1.0 - progress).powf(request.face_power)` — `face_power` константен на весь request. Один из самых медленных скаляров на x86.
**Фикс:** 256-entry LUT по `(progress*255) as usize` один раз на request. Аналогично `back_height_for_progress`.

### 10. Per-pixel `projected_sdf_facade` без кэша
`render.rs:1646-1690` зовут `material_coords_for_zone` (`:4070`), а внутри — `projected_sdf_facade` (`:2474`) с binary-search'ем (`projected_axis_depth:2569` — 7 бисекций + до `max_depth` линейных шагов). На каждый «shaded» пиксель.
**Фикс:** региональный кэш `Vec<ProjectedFacade>` по аналогии с `GlobalSdfDistanceCache`, переиспользуется между `material_coords_for_zone`, `sample_global_height_with_sampler`, `apply_organic_height_relief`.

### 11. `% width` и `/ width` в hot path параллельных проходов
`render.rs:1004-1006, 1031-1032, 1046-1047, 2733-2746, 2839-2851` — `par_chunks_mut(4).enumerate()` с `i%width`/`i/width` для восстановления (x,y). Деление per-pixel.
**Фикс:** `par_chunks_mut(width*4).enumerate()` → row index, внутри плотный цикл по x.

### 12. Шесть аллокаций на тайл + 4 `RgbaImage::new`
`render.rs:1382-1387` — 6 свежих `Vec` (heights, zones, occupancies, top/face/back coverages) на каждый из 96 тайлов Full16; плюс `:1499-1502` — 4× zero-fill RGBA-буфера.
**Фикс:** `TileScratch` через `rayon::iter::ParallelIterator::map_init` (или `thread_local!`), переиспользовать между тайлами.

### 13. Variant-уровневая re-работа геометрии
`build_full_atlases` (`:776-822`) гонит 16 кейсов × 6 вариантов = 96 независимых задач. При `geometry_variance == 0` все варианты разделяют идентичную геометрию (меняется только material seed) — но heightfield/zone/coverage пересчитываются заново.
**Фикс:** группировать по case, рендерить geometry один раз, цикл по вариантам пересемплирует только материалы.

### 14. Кэш `MAP_SDF_CACHE` имеет ровно один слот
`render.rs:1077-1105`: `Mutex<Option<...>>`. Любая смена preset/map/padding вытесняет. Плюс ключ кэша считает `DefaultHasher` по полному `map.cells` (~64 КБ) каждый рендер (`:1109`).
**Фикс:** LRU из 4 слотов, отпечаток `MapData` хранить кэшированным fingerprint'ом.

### 15. Draft-путь не различает «что поменялось»
`render.rs:1140` — `GlobalSdfDistanceCache::new_region` пересчитывается на каждый tick draft'а, потому что ключ — это весь `request`. Поменял цвет материала — пересчитал distance-cache.
**Фикс:** разделить fields на `shape_*` и `material_*`, ключевать distance/height-cache только по shape-полям.

### 16. `procedural_layer_material` — `match` по строке + до 12 FBM на пиксель
`render.rs:7187-7413` диспатчит на 17+ kind по `material.kind.as_str()` per-pixel. Внутри 6-12 вызовов `fbm_tiled` на пиксель.
**Фикс:** при загрузке request'а резолвить `kind: String` в `enum MaterialKind` один раз, диспатч по дискриминанту; кэшировать FBM-выборки по строке (см. п.10/15).

### 17. `voronoi_edge_mask` — лишний sqrt
`render.rs:8030-8068` — два `sqrt` на каждый вызов внутри материала.
**Фикс:** сравнивать squared distances, sqrt только для финальных двух значений.

---

## ВЫСОКИЕ — экспорт в игру

### 18. Контракт recipe vs реальный консумер не сходятся
- Smoke-тесты ассертят `res://assets/textures/terrain/{ground,mountains}/unnamed_runtime_sdf_recipe.json` (`runtime_sdf_contour_cutover_validation_smoke_test.gd:114-119`), но этих файлов нет — единственный `unnamed_*` лежит в `desktop_app/exports/session/`. Шага «копировать bake → assets» нет в репо.
- `Full47` legacy alias жив в Python pipeline (`tools/recipe_to_tres.py:80,136,173,191,196`), но Godot-side `cutover_validation_smoke_test.gd:101-104` явно запрещает «нормализацию legacy Full47 recipes». Pipeline'ы рассинхронизированы.
- `WorldStreamer`, `ChunkView`, `WorldCore.build_contour_chunk`, `CONTOUR_CLASS_*`, `CONTOUR_HALO_TILES` — упоминаются в smoke-тестах, **в коде игры не существуют**. Recipe — это контракт под ещё-не-написанного потребителя.
**Фикс:** прежде чем добавлять поля в recipe — определиться, кто его реально читает; иначе схема дрейфует против вакуума.

### 19. `tile_size_px` в recipe — runtime-tile, а не authoring
`render.rs:638` — `geometry_scale = 64 / authored_tile_size` зашивается в каждое `*_px` поле перед сериализацией. Игра не может перешкалировать в другой runtime-tile без перебейка.
**Фикс:** добавить `authored_tile_size_px` и эмитить геометрию в авторских пикселях; шкалирование на стороне консумера.

### 20. Смешанные единицы и mislabeled `_px`
`mountain_runtime_sdf_recipe.json:9-30`:
- `roughness_px` (`render.rs:651`) — НЕ шкалируется `geometry_scale`, по факту безразмерная амплитуда.
- `crown_bevel_px` (`:655`) — то же.
- `face_power`, `back_drop`, `contour_relax`, `corner_variation`, `edge_debris`, `edge_color_strength`, `geometry_variance` — нормализованные 0..1, но без суффикса `_norm`.
**Фикс:** строгая конвенция `_px / _norm / _pow / _factor`; per-field unit annotation; `roughness_px → roughness`.

### 21. Schema versioning — фейковый
`render.rs:25` — `RECIPE_VERSION: u32 = 7` встраивается только в legacy `RecipePayload`, не в `RuntimeSdfRecipePayload`. Schema-string `"...recipe.v1"` есть, но никто его не валидирует кроме одной строки в `cutover_validation_smoke_test.gd:128`.
**Фикс:** в `RuntimeSdfRecipePayload` добавить `generator_version`, `generator_git_sha`, `schema_revision`; на стороне Godot отказывать на unknown major version.

### 22. Нет content-hash / package manifest
Игра не может детектить «recipe говорит v3, рядом лежит PNG v2». `main.rs:67-70` пишет `manifest.json` только в build-output, без чексумм.
**Фикс:** sibling `_package.json` рядом с recipe: `{files: [{name, sha256, bytes, mtime}], generator_version, request_hash}`. Runtime отвергает recipe при несовпадении хешей.

### 23. 12 PNG на терреин — packing не использован
`runtime_sdf_reference/mountain_*` = 12 файлов:
- `top_modulation` + `face_modulation` — обе скалярные (`render.rs:952-957`) → пакуются в один RG8.
- Нормали уже RG (после `build_wrapped_normal_image`) → `top_normal.RG | face_normal.RG` в один RGBA8.
- `RuntimeSdfContour` всё равно гонит «reference» PNG для парити-дебага — вынести в `debug/` сабдир, чтобы продакшн-копировальщик не тащил их в игру.
- В `.import` нет hint'ов по компрессии (BC1/ETC2) — все PNG идут как uncompressed RGBA8. Recipe должен нести `compression: "bc1" | ...` per-texture.

### 24. Атлас в `Full16` орфанный
`render.rs:353-356` — Full16 пишет 4 атласа PNG **плюс** runtime SDF recipe (`:374`). Recipe `materials.*` ссылается только на 7 material-PNG (см. `mountain_runtime_sdf_recipe.json:32-43`) — атласы там не упомянуты. Игра не знает, как их найти.
**Фикс:** либо убрать атласы из Full16 (если SDF-путь — единственный консумер), либо добавить `materials.atlas_*` пути.

### 25. Контур/коллизия пересчитываются runtime'ом из mask'а
`collision_smoke_test.gd:104-110` — `PackedFloat32Array(33*33)` на каждый chunk per dirty revision. Это можно перенести в bake.
**Фикс — самый ценный «move work to bake»:**
- Эмитить per-case marching-squares полилинии (≤ сотни сегментов на 16 кейсов × 6 вариантов).
- Эмитить `outline_pixel mask` per-case (сейчас `apply_mountain_bottom_outline_from_source:1843` делает это per-пиксель в runtime — сэкономили бы и время bake, и runtime).
- Эмитить per-tile AABB / area для early-cull коллизии.

### 26. Дубли и мусор в схеме
- `collision.threshold` и `collision.threshold_px` всегда идентичны (`render.rs:684-685`) — выкинуть `threshold`.
- `materials.top_albedo = "mountain_top_albedo.png"` — это просто `<asset_name>_<slot>.png` (`render.rs:704-708`). Либо честно класть путь с сабдиром, либо выкинуть поле.
- `forced_variant` — семантика не задокументирована, ни один консумер его не читает.
- `contour_class` (smoke-тесты) vs `solid_class` (recipe) — drift.

### 27. Нет `halo_tiles_required` в recipe
`streaming_smoke_test.gd:97` хардкодит halo=2. При увеличении `contour_warp_px`/`edge_debris` runtime будет визуально клампиться на стыках чанков без предупреждения.
**Фикс:** считать максимально-возможный halo от geometry-параметров и эмитить.

### 28. TODO-парити двух codepaths
`render.rs:182` — `// TODO: remove the local marching path after SDF atlas export reaches parity.` Пока две ветки (`SurfaceField::Local` vs `Global`), recipe не гарантирует одинаковый результат при идентичных параметрах.

---

## СРЕДНИЕ — IPC и UI

### 29. `core_sources_newer_than` стат-сканит на каждый запрос
`core_bridge.py:32, 51-63` — на каждый `run_core` ходит по `src/*.rs`, `Cargo.toml`, `BUILD_SCRIPT`. На NTFS+антивирус — заметно.
**Фикс:** кэшировать на жизнь процесса.

### 30. Главный поток Tk резайзит атлас LANCZOS в `<Configure>`
`app.py:2326` — синхронный `source.resize(target_size, LANCZOS)` на каждом событии resize/scroll. На 2048² и зуме 0.5× — 80-150 мс на main thread.
**Фикс:** `after(60ms, ...)` с cancel-and-replace вместо `after_idle`.

### 31. `_draw_map` сносит canvas и пересоздаёт 315 rectangles per stroke
`app.py:1644-1654` — `canvas.delete("all")` + `create_rectangle` per cell на каждый B1-Motion sample.
**Фикс:** держать item-id в 2D-списке, `itemconfigure(fill=...)` только изменённые ячейки.

### 32. `_paint_at` шедулит `schedule_draft` на каждое движение мыши
`app.py:1565` — после draft-рендера 180 мс таймера absorb'ит, но `_draw_map` всё равно перерисовывает всё.

### 33. `_confirm_overwrite_if_needed` — name-pattern, race
`app.py:2698-2704` — `glob(f"{asset_name}_*")` ДО рендера. Между диалогом и записью могут влезть.
**Фикс:** считать `expected_export_file_names(asset_name, export_mode)` (уже есть `app.py:340`), пересекать с реально существующими.

### 34. Тестов на `core_bridge.py` нет
Нет тестов на reuse-сервера, на cancel без kill, на id-mismatch, на `inline_preview=True ⇔ mode=='draft'`.

### 35. `process.stderr.read()` на main worker thread
`core_bridge.py:158-162` — блокирующий read на ошибочной ветке. Если Rust завис, worker замирает.
**Фикс:** `process.wait(timeout=0.5)` сначала; читать `read(8192)` или через дренаж-тред.

### 36. Дублированный `_on_panel_scale_release`
`app.py:1480` — добавляет 180 мс задержки даже когда draft уже scheduled. Releases должны fire'ить немедленно или не bind'иться вовсе при `debounce_full=False`.

### 37. Мёртвое state
`app.py:656-668` — `decal_image_labels` инициализируется и никогда не используется. Удалить.

---

## Топ-10 «начать с этого»

| # | Фикс | Файл | Цена | Эффект |
|---|------|------|------|--------|
| 1 | Не убивать сервер на cancel | `core_bridge.py:142` | малая | **холодные кэши → тёплые** |
| 2 | Атомарный экспорт через temp dir | `app.py:2076-2081` | малая | убирает race с importer'ом Godot |
| 3 | Параллельный PNG-save + `CompressionType::Fast` | `render.rs:353-365, 441-453` | малая | **главный wallclock Full16** |
| 4 | Кэшировать `top/face/back_sample` per-pixel | `render.rs:1533-1734` | средняя | -3-4× FBM в горячем цикле |
| 5 | Свернуть bevel+relief в основной pixel-loop | `render.rs:3787-3881` | средняя | gradient считается 1 раз вместо 3 |
| 6 | LUT для `face_power` powf | `render.rs:3698` | малая | -1 powf/pixel |
| 7 | Один reader-тред на процесс | `core_bridge.py:128-153` | средняя | убирает per-render thread leak |
| 8 | `authored_tile_size_px` + строгая конвенция `_px/_norm` | `render.rs:631-695` | малая | контракт перестаёт врать |
| 9 | `_package.json` с sha256+generator_version | новый файл | средняя | runtime ловит stale art |
| 10 | Bake marching-squares полилиний и outline-mask per-case | `render.rs:579-695, 1843` | большая | move-to-bake = быстрее runtime + быстрее повторный bake |

---

## Сводка пройденных файлов
- `tools/rimworld-autotile-lab/desktop_app/core/Cargo.toml`
- `tools/rimworld-autotile-lab/desktop_app/core/src/main.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/model.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/render.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/sdf.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/noise.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/silhouette.rs`
- `tools/rimworld-autotile-lab/desktop_app/shell/app.py`
- `tools/rimworld-autotile-lab/desktop_app/shell/core_bridge.py`
- `tools/rimworld-autotile-lab/desktop_app/shell/presets.py`
- `tools/rimworld-autotile-lab/desktop_app/shell/tests/test_app_payload.py`
- `tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/mountain_runtime_sdf_recipe.json`
- `tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/earth_runtime_sdf_recipe.json`
- `tools/runtime_sdf_contour_*.gd` (6 smoke-тестов)
