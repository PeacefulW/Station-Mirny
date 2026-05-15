# Ревью генератора тайлов `tools/rimworld-autotile-lab/desktop_app`

**Дата ревью:** 2026-05-16
**Дата частичного применения:** 2026-05-16
**Объём кода:** ~15k LOC (Rust core + Python shell). `core/src/render.rs` — 8287 строк.
**Фокус:** производительность и контракт экспорта в игру (Godot).
**Метод:** три параллельных подагента (render-горячие пути, контракт экспорта, Python-shell/IPC), сведено в один прио-список. Все ссылки — `file:line`.

---

## Уже устранено (см. отчёт о выполнении)

- **#1** Cancel убивает Rust-сервер → переписан `core_bridge.py` с одним долгоживущим reader-тредом и id-мультиплексированием. Cancel больше не убивает процесс, кэши Rust-стороны переживают отмену.
- **#2** Неатомарный экспорт → Python-staging dir внутри `export_target_dir`, `os.replace` per-file, на отмене `shutil.rmtree`.
- **#3** Серийный PNG-save с дефолтной компрессией → `save_png_fast` (PngEncoder Fast/NoFilter) + `save_pngs_parallel` через rayon. Применено в Full16 и RuntimeSdfContour.
- **#6** Утечка reader-треда + per-call thread → один долгоживущий reader-тред в `_CoreServer` с диспатчем по id.
- **#8** Mountain bottom outline: `clone()` mask+albedo + sequential + sqrt в early-out → parallel rows, без clone albedo, squared comparison early-out, мёртвый `apply_outline_mask_coverage` удалён.
- **#9** `face_power.powf` per pixel → thread-local LUT 1024 entries с linear interpolation.
- **#11** `i%width`/`i/width` в parallel hot loops → `par_chunks_mut(row_stride)` + tight inner loop в 5 местах: `build_scalar_image`, `build_wrapped_normal_image`, `build_material_albedo_and_values`, `GlobalSdfDistanceCache::new_region`, `GlobalRenderHeightCache::new_region`.
- **#29** `core_sources_newer_than` стат-сканит на каждый запрос → кэшируется per-process через `_SOURCES_FRESH_FOR_BINARY`.
- **#30** LANCZOS resize в `<Configure>` → `after(60ms, ...)` debounce вместо `after_idle` для preview и atlas canvas.
- **#31** `_draw_map` пересоздаёт 315 rectangles per stroke → кэш `map_cell_items`, dirty `itemconfigure` только для изменённых ячеек.
- **#33** `_confirm_overwrite_if_needed` сравнивает по name-pattern → использует `expected_export_file_names(asset_name, export_mode)` с per-mode диспатчем (Full16/RuntimeSdf/BaseVariants/MaskOnly/Decals/Silhouettes).
- **#34** Тестов на `core_bridge.py` нет → 5 unit-тестов в `tests/test_core_bridge.py` (id-dispatch, stale-discard, concurrent routing, stop-cleanup, cancel-без-kill).
- **#35** `process.stderr.read()` блокирующий → `drain_stderr` зовётся только после `is_alive()==False`, OS уже закрыл pipe.
- **#36** `_on_panel_scale_release` добавляет 180ms даже при pending draft → cancels pending debounce и fires `request_render("draft")` сразу.

## Скипнуто с обоснованием (не делать)

- **#16** `procedural_layer_material` match по строке per-pixel → микрооптимизация. Hot cost доминирует FBM (4-7 октав 2D-хеша на каждый из 17 материалов), string-compare с length-prefix exit стоит <50ns. Не стоит chain-of-callsite refactor'а.
- **#17** `voronoi_edge_mask` два sqrt → математически невыводимый sqrt-free early-out. `line_mask(second.sqrt() - nearest.sqrt(), width)` фундаментально требует разности корней; squared-form early-out не даёт корректного отсечения.
- **#32** `_paint_at` schedule_draft per mouse-motion → после #31 `_draw_map` стал O(changed_cells), brush-stroke cost ограничен. Дополнительный debounce уже не нужен.
- **#37** Мёртвое state `decal_image_labels` → ревью ошиблось, поле живое (используется в `app.py:1111, 1205, 1881, 1888, 2682, 2683` для UI labels per decal cell).

---

## Остаётся: ВЫСОКИЕ — производительность ядра (требуют осторожности)

Эти правки трогают визуальные пути render.rs и риск регрессий — нужна валидация против ref-images. Делать пакетом с careful comparison.

### #4 Дублирующийся `sample_material_color` в горячем пиксельном цикле
`render.rs:1533-1734` (`render_tile_with_field`): на пикселях зоны `Edge` материал семплируется на топ/face/back до 6 раз с одними и теми же координатами (стр. 1568, 1580, 1655, 1667, 1679). Каждый вызов прогоняет 4-7 октав FBM.
**Фикс:** один раз в начале пиксельного блока вычислить `top_sample/face_sample/back_sample` (под флагами coverage>0), переиспользовать.

### #5 Три прохода по тайлу делают одну и ту же градиентную работу
`render.rs:3787-3833` (`apply_crown_bevel`) и `:3836-3881` (`apply_organic_height_relief`) — отдельные `for y { for x }` поверх уже отрендеренного тайла, вызывают `contour_distance_for_field`/`exposed_edge_distance` (а внутри — gradient + 4 distance lookups) на тех же пикселях, что и основной цикл.
**Фикс:** свернуть оба прохода в основной пиксельный цикл — gradient считается один раз.

### #7 Параллелизм атласа — серийный merge после параллельного рендера
`render.rs:805-814` — таски рендерятся в `rayon`, но финальный blit в 4 RgbaImage идёт последовательно `blit_exact` с проверкой границ. На 4×2048²×4 = 64 МБ это ощутимо.
**Фикс:** аллоцировать 4 raw `Vec<u8>`, в `par_iter` писать в banded-чанки через `chunks_mut` (`build_map_preview_outputs:1256-1290` уже показывает паттерн).

### #10 Per-pixel `projected_sdf_facade` без кэша
`render.rs:1646-1690` зовут `material_coords_for_zone` (`:4070`), а внутри — `projected_sdf_facade` (`:2474`) с binary-search'ем (`projected_axis_depth:2569` — 7 бисекций + до `max_depth` линейных шагов). На каждый «shaded» пиксель.
**Фикс:** региональный кэш `Vec<ProjectedFacade>` по аналогии с `GlobalSdfDistanceCache`, переиспользуется между `material_coords_for_zone`, `sample_global_height_with_sampler`, `apply_organic_height_relief`.

### #12 Шесть аллокаций на тайл + 4 `RgbaImage::new`
`render.rs:1382-1387` — 6 свежих `Vec` (heights, zones, occupancies, top/face/back coverages) на каждый из 96 тайлов Full16; плюс `:1499-1502` — 4× zero-fill RGBA-буфера.
**Фикс:** `TileScratch` через `rayon::iter::ParallelIterator::map_init` (или `thread_local!`), переиспользовать между тайлами.

### #13 Variant-уровневая re-работа геометрии
`build_full_atlases` (`:776-822`) гонит 16 кейсов × 6 вариантов = 96 независимых задач. При `geometry_variance == 0` все варианты разделяют идентичную геометрию (меняется только material seed) — но heightfield/zone/coverage пересчитываются заново.
**Фикс:** группировать по case, рендерить geometry один раз, цикл по вариантам пересемплирует только материалы.

### #14 Кэш `MAP_SDF_CACHE` имеет ровно один слот
`render.rs:1077-1105`: `Mutex<Option<...>>`. Любая смена preset/map/padding вытесняет. Плюс ключ кэша считает `DefaultHasher` по полному `map.cells` (~64 КБ) каждый рендер (`:1109`).
**Фикс:** LRU из 4 слотов, отпечаток `MapData` хранить кэшированным fingerprint'ом.

### #15 Draft-путь не различает «что поменялось»
`render.rs:1140` — `GlobalSdfDistanceCache::new_region` пересчитывается на каждый tick draft'а, потому что ключ — это весь `request`. Поменял цвет материала — пересчитал distance-cache.
**Фикс:** разделить fields на `shape_*` и `material_*`, ключевать distance/height-cache только по shape-полям.

---

## Остаётся: ВЫСОКИЕ — экспорт в игру (отложено по решению пользователя)

Контрактные правки. Затрагивают game-side ещё-не-существующих консумеров (`WorldStreamer`, `ChunkView`, `WorldCore.build_contour_chunk`). Требуют ADR/спека сначала.

### #18 Контракт recipe vs реальный консумер не сходятся
- Smoke-тесты ассертят `res://assets/textures/terrain/{ground,mountains}/unnamed_runtime_sdf_recipe.json` (`runtime_sdf_contour_cutover_validation_smoke_test.gd:114-119`), но этих файлов нет — единственный `unnamed_*` лежит в `desktop_app/exports/session/`. Шага «копировать bake → assets» нет в репо.
- `Full47` legacy alias жив в Python pipeline (`tools/recipe_to_tres.py:80,136,173,191,196`), но Godot-side `cutover_validation_smoke_test.gd:101-104` явно запрещает «нормализацию legacy Full47 recipes». Pipeline'ы рассинхронизированы.
- `WorldStreamer`, `ChunkView`, `WorldCore.build_contour_chunk`, `CONTOUR_CLASS_*`, `CONTOUR_HALO_TILES` — упоминаются в smoke-тестах, **в коде игры не существуют**. Recipe — это контракт под ещё-не-написанного потребителя.
**Фикс:** прежде чем добавлять поля в recipe — определиться, кто его реально читает; иначе схема дрейфует против вакуума.

### #19 `tile_size_px` в recipe — runtime-tile, а не authoring
`render.rs:638` — `geometry_scale = 64 / authored_tile_size` зашивается в каждое `*_px` поле перед сериализацией. Игра не может перешкалировать в другой runtime-tile без перебейка.
**Фикс:** добавить `authored_tile_size_px` и эмитить геометрию в авторских пикселях; шкалирование на стороне консумера.

### #20 Смешанные единицы и mislabeled `_px`
`mountain_runtime_sdf_recipe.json:9-30`:
- `roughness_px` (`render.rs:651`) — НЕ шкалируется `geometry_scale`, по факту безразмерная амплитуда.
- `crown_bevel_px` (`:655`) — то же.
- `face_power`, `back_drop`, `contour_relax`, `corner_variation`, `edge_debris`, `edge_color_strength`, `geometry_variance` — нормализованные 0..1, но без суффикса `_norm`.
**Фикс:** строгая конвенция `_px / _norm / _pow / _factor`; per-field unit annotation; `roughness_px → roughness`.

### #21 Schema versioning — фейковый
`render.rs:25` — `RECIPE_VERSION: u32 = 7` встраивается только в legacy `RecipePayload`, не в `RuntimeSdfRecipePayload`. Schema-string `"...recipe.v1"` есть, но никто его не валидирует кроме одной строки в `cutover_validation_smoke_test.gd:128`.
**Фикс:** в `RuntimeSdfRecipePayload` добавить `generator_version`, `generator_git_sha`, `schema_revision`; на стороне Godot отказывать на unknown major version.

### #22 Нет content-hash / package manifest
Игра не может детектить «recipe говорит v3, рядом лежит PNG v2». `main.rs:67-70` пишет `manifest.json` только в build-output, без чексумм.
**Фикс:** sibling `_package.json` рядом с recipe: `{files: [{name, sha256, bytes, mtime}], generator_version, request_hash}`. Runtime отвергает recipe при несовпадении хешей.

### #23 12 PNG на терреин — packing не использован
`runtime_sdf_reference/mountain_*` = 12 файлов:
- `top_modulation` + `face_modulation` — обе скалярные (`render.rs:952-957`) → пакуются в один RG8.
- Нормали уже RG (после `build_wrapped_normal_image`) → `top_normal.RG | face_normal.RG` в один RGBA8.
- `RuntimeSdfContour` всё равно гонит «reference» PNG для парити-дебага — вынести в `debug/` сабдир, чтобы продакшн-копировальщик не тащил их в игру.
- В `.import` нет hint'ов по компрессии (BC1/ETC2) — все PNG идут как uncompressed RGBA8. Recipe должен нести `compression: "bc1" | ...` per-texture.

### #24 Атлас в `Full16` орфанный
`render.rs:353-356` — Full16 пишет 4 атласа PNG **плюс** runtime SDF recipe (`:374`). Recipe `materials.*` ссылается только на 7 material-PNG (см. `mountain_runtime_sdf_recipe.json:32-43`) — атласы там не упомянуты. Игра не знает, как их найти.
**Фикс:** либо убрать атласы из Full16 (если SDF-путь — единственный консумер), либо добавить `materials.atlas_*` пути.

### #25 Контур/коллизия пересчитываются runtime'ом из mask'а
`collision_smoke_test.gd:104-110` — `PackedFloat32Array(33*33)` на каждый chunk per dirty revision. Это можно перенести в bake.
**Фикс — самый ценный «move work to bake»:**
- Эмитить per-case marching-squares полилинии (≤ сотни сегментов на 16 кейсов × 6 вариантов).
- Эмитить `outline_pixel mask` per-case (сейчас `apply_mountain_bottom_outline_from_source:1843` делает это per-пиксель в runtime — сэкономили бы и время bake, и runtime).
- Эмитить per-tile AABB / area для early-cull коллизии.

### #26 Дубли и мусор в схеме
- `collision.threshold` и `collision.threshold_px` всегда идентичны (`render.rs:684-685`) — выкинуть `threshold`.
- `materials.top_albedo = "mountain_top_albedo.png"` — это просто `<asset_name>_<slot>.png` (`render.rs:704-708`). Либо честно класть путь с сабдиром, либо выкинуть поле.
- `forced_variant` — семантика не задокументирована, ни один консумер его не читает.
- `contour_class` (smoke-тесты) vs `solid_class` (recipe) — drift.

### #27 Нет `halo_tiles_required` в recipe
`streaming_smoke_test.gd:97` хардкодит halo=2. При увеличении `contour_warp_px`/`edge_debris` runtime будет визуально клампиться на стыках чанков без предупреждения.
**Фикс:** считать максимально-возможный halo от geometry-параметров и эмитить.

### #28 TODO-парити двух codepaths
`render.rs:182` — `// TODO: remove the local marching path after SDF atlas export reaches parity.` Пока две ветки (`SurfaceField::Local` vs `Global`), recipe не гарантирует одинаковый результат при идентичных параметрах.

---

## Топ оставшихся «начать с этого»

| # | Фикс | Файл | Цена | Эффект |
|---|------|------|------|--------|
| #4 | Кэшировать `top/face/back_sample` per-pixel | `render.rs:1533-1734` | средняя | -3-4× FBM в горячем цикле |
| #5 | Свернуть bevel+relief в основной pixel-loop | `render.rs:3787-3881` | средняя | gradient считается 1 раз вместо 3 |
| #7 | Parallel atlas merge через banded-чанки | `render.rs:805-814` | средняя | убирает 64МБ серийного blit |
| #10 | ProjectedFacade region cache | `render.rs:1646-1690, 2474, 2569` | большая | убирает binary-search per-pixel |
| #12 | TileScratch arena per-rayon-thread | `render.rs:1382-1502` | средняя | -10 alloc на каждый из 96 тайлов |
| #13 | Reuse geometry across variants when `geometry_variance==0` | `render.rs:776-822` | средняя | до 6× меньше геометрии для Full16 |
| #14 | LRU кэш для `MAP_SDF_CACHE` + cached cells fingerprint | `render.rs:1077-1140` | малая | -64KB hashing per render |
| #15 | Split shape/material cache keys для draft path | `render.rs:1140-1149` | средняя | материал-слайдер не сбрасывает SDF-кэш |
| #18-#28 | Контрактные правки recipe/export | render.rs:579-695, рядом | большая | требует ADR/спека сначала |

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
