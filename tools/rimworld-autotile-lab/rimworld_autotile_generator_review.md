# Cliff Forge 47 — Review и roadmap улучшений

Ревью файлов `rimworld_autotile_generator.html` и `rimworld_autotile_generator_runtime_export.js` по состоянию на 2026-04-20.

Генератор уже умеет: 47 канонических сигнатур, 3 пресета (гора/стена/земля), procedural top/face modulation, shader composite preview, tint-opacity, экспорт albedo/mask/shape-normal/modulation атласов + JSON-рецепта. Это хорошая база, но у неё есть выраженные дефициты и по коду, и по UX, и — главное — по **палитре доступных материалов**. Ниже — сгруппированные предложения.

---

## 1. Сильные стороны (что трогать не надо)

- Чёткое разделение `shape` (маски/высота) и `material` (modulation/albedo).
- Packed mask-atlas (R=top, G=face, B=back, A=occupancy) — это готовый к шейдеру контракт.
- Periodic FBM + ridge + circle-field + line-field как базовые примитивы. Достаточно универсально, чтобы надстраивать новые материалы без смены архитектуры.
- Profile-noise (`buildProfiles`) на 4 стороны с финальным сглаживанием — даёт приемлемый «rim-world»-контур.
- JSON Material Recipe — хороший мост к runtime импорту.

---

## 2. Проблемы по коду

### 2.1. Перформанс (главный блокер)

**Проблема:** `scheduleRender` вызывается на **любой** `input` слайдера и дебаунсится через `requestAnimationFrame` (~16 мс). `rebuildAll` пересобирает:

- 2 × material-map 256×256 (≈131 072 пикселя × много октав FBM/ridge);
- 47 × `variants` (до 6) tile-рендеров, у каждого ≥ 2 прохода (`albedo` + `shaderComposite`);
- `renderBaseVariants` (ещё 4+ canvas `tileSize²`);
- `buildAtlases` × 5 режимов preview;
- `buildGallery` пересоздаёт DOM-карточки всех 47 сигнатур;
- `drawPreview` для карты 18×12 с пер-пиксельным `paintLayeredTile` в composite.

На средней машине это сотни миллисекунд. При драг-слайдера `requestAnimationFrame` не спасает — запросы очередятся.

**Что делать:**

1. **Разделить пайплайн на стадии** с собственным «грязным» флагом:
   - `materialDirty` (topMacroScale/topMicroNoise/face*, tintJitter и т.п.);
   - `shapeDirty` (tileSize/heightPx/lipPx/backRimRatio/northRimThickness/roughness/faceSlope/innerCornerMode);
   - `colorDirty` (tints, tintOpacity, textureScale при не-мени шейпа);
   - `mapDirty` (рисование клеток, randomBlob и т.п.);
   - `variantsDirty` (variants, seed, textures).
   Каждая стадия инвалидирует нижестоящие, но не выше. Пересобирать только нужное.
2. **Дебаунс → 80-120 мс** вместо `requestAnimationFrame`. Для `input` слайдера хватит дешёвого preview (low-res mode) + полный rebuild по `change`.
3. **Low-res предпросмотр** во время drag: рисовать в половинном разрешении и апскейлить `image-rendering: pixelated`. Полное разрешение — когда слайдер отпустили.
4. **OffscreenCanvas + Worker** для `buildTopMaterialMap` / `buildFaceMaterialMap` / `renderTile`. Классический случай: чистые функции, ходят только к `params` и seed. Один `MessagePort`, Transferable ImageData — готово.
5. Typed-`ImageData` пишется прямо в `Uint8ClampedArray`; сейчас каждый пиксель трижды `scaleColor → Math.round → clamp`. Можно заменить `scaleColor` на inline-операции с предрассчитанным множителем.
6. `paintLayeredTile` во время `drawPreview` рисует композит для каждой живой клетки **на лету**. Для preview-экрана надо кэшировать composite-canvas на (signature,variant,offset) и инвалидировать по `colorDirty`.
7. `buildGallery` делает `innerHTML = ""` + 47 × `createElement` на каждый рендер. Достаточно один раз построить DOM-каркас и переприсваивать `canvas.getContext("2d").drawImage`.

### 2.2. Семантические баги / острые углы

- `PRESETS.mountain.backRimRatio = 0.55`, но дефолт в HTML — `0.5`. Значит «активная» кнопка `mountain` при загрузке **не** отражает реальное состояние слайдеров до первого клика. Привести в соответствие или вызвать `applyPreset("mountain")` в `boot()` до `scheduleRender` (сейчас вызывается — но порядок с `updateRangeLabels` не строгий; проверить, что preset применяется ДО первого `rebuildAll`).
- `scheduleRender` вызывается и для slider `variants`, но в `refreshGalleryOptions()` доступ к `refs.galleryVariant.value` может быть `""` при первом построении (сейчас обработано `|| 0`, но логика хрупкая). После изменения `variants` перестроенная галерея может съесть выбранный вариант, если `previous >= total`.
- `textureScale` в диапазоне 40-220 **шаг 5** — ок, но в `sampleTextureColor` `zoom = 100 / max(10, textureScale)` даёт не интуитивный масштаб (чем больше слайдер, тем **мельче** текстура). В UI либо инвертировать, либо переименовать в «Texture zoom out» / «Texture density».
- `jaggedSize` использует `fbmPeriodic(axisCoord * 0.21 + salt * 0.07, crossCoord * 0.13 + salt * 0.11, …, 24, 24)`. `axisCoord` — это **пиксель** тайла, а периодика задана 24 — значит на tileSize=96 шов будет виден по границам notch. Сделать period = `Math.max(12, Math.round(params.tileSize/3))`.
- Вариантные сэмплы `variantOffsets.ox/oy` складываются с мировыми `x/y` внутри `sampleTextureColor`, но при `drawContinuousBasePreview` используется **только** `globalPreviewOffsets`, игнорирующий `variantOffsets.brightness`. Composite preview может быть по-разному ярким на map-экране и на tile-card. Либо один источник истины (`globalPreviewOffsets`), либо документировать различие.
- В `signatureAt` `x, y` не ограничены к валидной области (используются через `getMapCell`, который возвращает 0 вне поля — это корректно), **но** `createSignature` строится исходя из 8 соседей → пограничные клетки карты всегда «открыты наружу». Это специально, но для тестов карт у края лучше иметь опцию «boundary as solid» / «boundary as empty».
- Сохранение/загрузка презета на `localStorage` отсутствует. На перезагрузке страницы всё теряется.

### 2.3. Архитектурные мелочи

- Нет дженерик-функции «создать slider с label+value+id»; HTML повторяется много раз — и ранжированные поля рассогласованы (например, `tileSize` объявлен в RANGE_IDS, но его label с `value`-span есть, а его `preset` в `PRESETS` **нет** — значит переключение пресета не меняет tileSize, это правильно, но непоследовательно).
- `PREVIEW_MODES` дублирует список в `previewMode`-select. Сгенерировать options из массива.
- `state.map` имеет захардкоженные `width=18, height=12`. Размер должен быть параметром.
- `state.generated.atlases[mode]` никогда не очищается при смене tileSize — старые canvas остаются как GC-мусор до следующего rebuild. Для больших tileSize это десятки мегабайт. Явно `canvas.width = canvas.height = 0` перед пере-созданием.
- `downloadJson` пишет `version: 2` без bump-схемы. Добавить `generatedAt`, `tileSize`, `presetSource`, `gitSha` (если доступен), чтобы можно было отследить происхождение.
- Нет `try/catch` на `readTexture`. Битая картинка упадёт без фидбека.
- `refs.previewCanvas.addEventListener("contextmenu", …)` — ок, но painting на pointer move не учитывает `pointercapture`; при быстром переводе курсора за пределы canvas рисование обрывается.

### 2.4. Чистота

- Повторение кода paint-loop в `paintLayeredTile`, `renderBaseVariants`, `drawSlotPreviewCanvas` — три разных цикла по `(x,y)` с похожим `image.data` заполнением. Вынести `fillImageData(width, height, sampler)` helper.
- `buildMaterialMap` top/face почти идентичны по структуре — можно заложить «contribution-стек» из слоёв (см. §4) и переиспользовать один цикл.
- Magic numbers в zone brightness (`zone === "back" ? 0.84 : zone === "face" ? 0.7 : 1`) — вынести в константы/пресет.
- CSS и HTML в одном файле. Когда разрастётся — вынести CSS в `.css`, script уже отдельным файлом; это же сделать с CSS.

---

## 3. UI / UX улучшения

### 3.1. Навигация по параметрам

- Раскрывающиеся **секции** (details/summary) — «Shape», «Top material», «Face material», «Base material», «Tints», «Map», «Export». Сейчас 360px сайдбар перегружен и листается длинно.
- **Поиск параметра** по имени (ctrl+F как у Figma): сверху текстовое поле → фильтрует видимые controls.
- **Drag-to-scrub** по подписи параметра (как в Blender/Figma): numeric-input + drag по label = ±step.
- **Reset-to-preset-default** кнопка рядом с каждой группой.
- **Сравнить A vs B**: два snapshot-слота, split-view preview, слайдер между ними.
- **Undo/Redo** (ctrl+Z) — каждый rebuild кладёт в стек snapshot params; отдельный стек для map-paint.

### 3.2. Preview

- **Zoom / pan** (колесо мыши + drag). Сейчас preview привязан к физическим 1152×768 и не увеличивается.
- **Grid overlay** toggle (показать границы тайлов).
- **Подсветка сигнатуры** под курсором (hover показывает, какая из 47 подставлена в эту клетку + кол-во её использований на карте).
- **Tool palette** карты: кисть, прямоугольник, заливка, линия, «ластик», bucket undo.
- **Map size** slider (8×6 … 48×32).
- **Resize** map через drag угла.
- **Toggle boundary** (как трактовать край карты — solid/empty).
- **Stamp-brush**: пачка заранее заготовленных конфигураций (крест, U, T, C-room) для быстрой проверки всех 47 сигнатур.
- **Signature coverage meter**: из какой доли 47 сигнатур реально видно на текущей карте («use all 47» hint).

### 3.3. Галерея тайлов

- **Hover-zoom 2×/4×** на карточку.
- **Фильтры** по сигнатуре: только solid / только с вырезами / только Г-углы / только T-perimeter.
- **Поиск по ключу** (ввод `1001|0010` подсвечивает).
- **Сравнение вариантов**: тогл-стрип сверху карточки переключает вариант не на всю галерею, а на одну карточку.
- **Копия в буфер**: клик по карточке → копирует albedo PNG в clipboard.

### 3.4. Экспорт / integration

- **Включить в имя файла** `preset_seed_tileSize` (например, `mountain_240518_64_albedo.png`).
- **ZIP-экспорт** сразу всей пачки (albedo + mask + shape-normal + modulation + JSON) — через `JSZip` из CDN или вручную собрать zip-без-сжатия.
- **Кастомный layout атласа** (columns select): 8/12/16, с опцией padding-px между тайлами для отсутствия bleed.
- **Padding / bleed** — важен для runtime (билинейная фильтрация съедает края).
- **Экспорт Godot .tres** (material recipe → `TerrainMaterialSet` / `TerrainShapeSet` prefab, т.к. такой ресурс уже есть в `data/terrain/*.tres`). Это даёт мост от тула к движку.
- **Preset save/load** — кнопка «Сохранить как preset» → в `localStorage` + ручной экспорт JSON presets.
- **Импорт JSON recipe** — загрузка обратно восстанавливает все слайдеры.
- **Copy-to-clipboard** параметров как JSON (для шаринга в Slack/Discord).

### 3.5. Доступность / usability

- **Tooltips** (`title="..."`) для каждого слайдера: одно-предложенное объяснение. Сейчас названия типа «Back rim ratio» требуют знать, что такое «rim».
- **Hotkeys**: `R` — shuffle seed, `Space` — full rebuild, `1/2/3` — переключить пресет, `[` / `]` — уменьшить/увеличить variants.
- **HiDPI canvas**: учитывать `devicePixelRatio` для `atlasCanvas` / `previewCanvas`, чтобы на Retina не было blur (да, `image-rendering: pixelated` спасает, но лучше сразу рендерить в правильное разрешение).
- **Drag-drop** текстур на карточку загрузки (сейчас только file picker).
- **Skeleton/placeholder** вместо «Собираю каталог 47 случаев...» — показывать последний валидный результат, пока новый не собран.
- **Dark / Light theme toggle** (сейчас только тёмная, в игре может понадобиться светлый прототип).
- **Клавиатурный фокус**: sidebar на мобилке перекрывает контент; добавить «hide sidebar».

---

## 4. Главное: расширение палитры материалов

Сейчас top и face генерируются одним фиксированным shader-like циклом из 4–6 источников шума. Чтобы генератор покрыл сценарии «земля / снег / гора / стена / кирпич / лёд / песок / металл», нужно превратить пайплайн в **стек слоёв** (layer stack), где каждый слой — один из перечисленных модулей, с собственной силой, маской и смешиванием.

### 4.1. Архитектура «Material Layer Stack»

```
layer = {
  type: "brick" | "stones" | "planks" | "snowDrift" | "moss" | ...,
  enabled: bool,
  strength: 0..100,
  mask: none | top | face | back | edgeOnly | topCrown | faceBottom,
  blend: "multiply" | "add" | "overlay" | "replace" | "soft-light",
  params: { ... — специфичные }
}
```

UI: список слоёв в сайдбаре с кнопкой «+», drag-sort, eye-toggle, expand-свёртка. JSON-рецепт хранит весь стек. В коде `buildTopMaterialMap`/`buildFaceMaterialMap` сводятся к циклу по layer-стеку.

### 4.2. Каталог модулей (минимальный набор — 20+ штук)

| # | Модуль | Применение | Ключевые параметры |
|---|---|---|---|
| 1 | **Brick/Ashlar** | face (стены, каменная кладка, кирпич, adobe) | rows, cols, bond type (running/stack/herringbone/flemish), mortar width px, mortar depth, brick height jitter, color jitter, chamfer px |
| 2 | **Plank** | top/face (деревянные полы, деревянные стены) | plank width, end-stagger, grain-noise strength, knot density, knot size, end-cap visibility |
| 3 | **Stone cluster** | top/face (булыжник, россыпь камней) | density, size min/max, edge roundness, gap fill noise |
| 4 | **Pebble field** | top (земля, гравий) | есть сейчас → вынести как layer |
| 5 | **Snow drift** | top + edge (накопление снега у лип) | drift bias (N/S/E/W), crown height, crystal sparkle density, melt-edge noise |
| 6 | **Frost / ice veins** | face (ледяная стена) | fracture count, branching depth, subsurface blue tint, sheen |
| 7 | **Moss / lichen patches** | top (на стенах/горах) | patch count, patch size, gradient (bottom-heavy), edge feather, color-secondary |
| 8 | **Grass tufts** | top (земляной уступ) | tuft density, height, wind direction, seasonal tint |
| 9 | **Puddles / wetness** | top (низкие места) | puddle count, reflectivity hint, darkening factor, ripple noise |
| 10 | **Cracks** | face/top (старые стены, высохшая земля, лёд) | count, branching, width, depth, jaggedness |
| 11 | **Mineral veins** | face (горы, пещеры) | count, thickness, branching, color (gold/iron/crystal), glow strength |
| 12 | **Rivets / studs** | face (металл/промышленность) | grid X×Y, rivet radius, head style (flat/dome), panel spacing |
| 13 | **Panel seams** | face (металл, стекло) | h-seam count, v-seam count, seam depth, seam width |
| 14 | **Runic carvings** | face/top (древние руины) | stroke density, stroke thickness, symbolism preset, glow opacity |
| 15 | **Debris scatter** | top (post-apoc, ruin) | count, debris kinds (sticks/bones/shrapnel), scale |
| 16 | **Cobweb** | top corner (заброшенные зоны) | corner bias, density, thread count |
| 17 | **Rust stains** | face (металл) | streak count, direction, gravity drip curve, color (orange/brown) |
| 18 | **Burn / scorch** | top (пост-пожар) | blob count, blob size, smoke smear direction |
| 19 | **Sand dune / drift** | top (пустыни, станция занесена песком) | wind dir, drift height, ripple wavelength, crest sharpness |
| 20 | **Concrete speckle** | face (бетон) | speckle density, dark/light ratio, macro patch noise |
| 21 | **Mud splatter** | top/face (дождь, болото) | splatter count, drip length, stickiness |
| 22 | **Vines / roots** | face (органика поверх камня) | main stems, leaf density, branching, downward gravity factor |
| 23 | **Dust bloom** | top edge (сухой верх скалы) | gradient bias (top-bright), speckle noise |
| 24 | **Edge grime** | top→face transition | inner shadow px, dirt color, opacity |
| 25 | **Quarried block** | top (каменная плитка) | grid random jitter, chisel-mark noise, corner chip probability |
| 26 | **Hex/honeycomb** | top/face (sci-fi панели) | hex radius, panel gap, panel emission |
| 27 | **Herringbone brick** | top (плитка пола) | cell size, rotation alternation, grout width |
| 28 | **Cobblestone** | top (мостовая) | count, voronoi relax iterations, size jitter |
| 29 | **Wood grain streak** | face (доски вертикально) | streak length, warping, knot frequency |
| 30 | **Metal brushed** | face (металл щёткой) | streak frequency, streak opacity, direction angle |

Каждый модуль — чистая функция с нормализованным выходом `[0..1]`. Для рассылки света достаточно иметь **height-contribution** слоя, тогда normal собирается автоматически из агрегированной карты высоты. Это даст материалам визуальный рельеф без ручной правки normal-атласа.

### 4.3. Дополнительные общие оси

- **Бленд top↔face** по edge-distance (моссиа/грязь копится у перехода лип → face). Сейчас жёстко `zoneBrightness`.
- **Directional weathering**: maska «север» (top крона со снегом), «юг» (сухой), «восток/запад» (мох). Для орторграфических карт — просто параметр «sun azimuth» и нацеливание снега на север.
- **Biome palette**: 1 палитра → 3–5 гармоничных tint-наборов (top/face/base/moss/accent). Swatch-grid, клик — применяет все 5 цветов.
- **Палитра из картинки**: kmeans 5 на загруженной текстуре → авто-тинты.
- **Noise presets**: «organic», «stratified», «fractal-rough», «quartz», «volcanic». Один слайдер меняет 4–5 под-параметров согласованно.

### 4.4. Shape-расширения (то, чего сейчас нет)

- **Crown bevel**: отдельный slider «толщина светлого ободка сверху лип» — визуально он уже встроен в `computePixelHeight`, но без отдельного управления.
- **Outer chamfer**: параметр скругления внешних углов (сейчас жёсткие).
- **Base erosion**: подрезание нижних пикселей фасада (из-за накопленных осколков).
- **Per-side height**: независимая heightPx для N/E/S/W (сейчас только S управляется heightPx, N — backRim).
- **Corner style per signature**: преимущество `caps/box/bevel` задаётся глобально; можно сделать per-corner override для арт-директорских нужд.
- **Interior wall vs exterior wall**: сейчас пресет `wall` один, но в игре часто нужен «стоит на полу» и «вмонтирована в гору» — разные rim/shadow.

### 4.5. PBR / shader-ready channel pack

Сейчас mask-atlas упаковывает top/face/back/occupancy. Не хватает:

- **Height atlas** (16-bit PNG идеально, но 8-bit OK): подробная высота для parallax.
- **ORM atlas** (Occlusion/Roughness/Metallic): позволяет один шейдер под все материалы. Сейчас roughness/metallic не определены вовсе.
- **Emission atlas** (для рун/жил/кристаллов с glow).
- **Flow atlas** (направление ветра/дождя/стекания) — 2-канальный xy.

Каждый layer вносит свой вклад в R/M/AO (кирпич → высокий R, металл → низкий R + M=1, моss → средний R + AO темнее). Это сразу открывает PBR pipeline в Godot.

### 4.6. Экспорт, которого сейчас нет

- **Sprite-sheet с signature-labels** (PNG + JSON manifest с координатами — manifest уже почти есть, надо только геометрию UV).
- **Godot TerrainShapeSet.tres** (соответствие `data/terrain/shape_sets/*.tres`).
- **Godot TerrainMaterialSet.tres**.
- **Image sequence** (вариант на файл) — альтернатива атласу, иногда удобнее для горячей правки.

---

## 5. Мелкие идеи «на подумать»

- **Seed timeline**: показывать мини-превью 10 соседних seed-значений для быстрого «подобрать удачный».
- **Animated preview**: тумблер «показать как выглядит при дыхании light-direction» — pan light azimuth по кругу.
- **Color-blind simulation**: фильтр-оверлей для проверки читаемости тайлов без цвета.
- **Lint checker**: после каждого rebuild проверять, что 2×2 tiling не имеет шва (через diff RMS по границе) и красить бейдж «seamless OK / seam detected».
- **Self-test map**: генератор сам кладёт 47 сигнатур в один canvas (gallery уже близка) + отдельная карта-«жирный крест» показывает Г-углы и T-стыки в нормальном контексте.
- **Embed version** (#version=...): при загрузке `recipe.json` сверяется версия схемы.
- **Deterministic build proof**: фикс-сид → hash всех атласов → если хоть один байт поехал, это регрессия. Полезно перед правкой noise-функций.
- **Export PSD/layered PNG**: отдельные слои отдельными файлами для ручной дорисовки в Photoshop.

---

## 6. Приоритизированный roadmap

### Iteration 7 — Perf & stability (без визуала)

1. Разделить `rebuildAll` на стадии `materialDirty/shapeDirty/colorDirty/mapDirty/variantsDirty`.
2. Дебаунс 100 мс + low-res preview при drag.
3. Кэш composite-canvas за (sig, variant, params.hash).
4. HiDPI-aware canvas sizing.
5. Undo/Redo для map-paint.
6. Синхронизация `PRESETS.mountain.backRimRatio` vs дефолта HTML.

### Iteration 8 — UX polish

1. Collapsible sidebar groups + parameter search.
2. Tooltips на каждый слайдер.
3. Drag-drop текстур.
4. Zoom/pan на preview-canvas.
5. Hotkeys (R/Space/1/2/3).
6. Custom preset save/load в localStorage.
7. Export filename с preset+seed+tileSize.
8. ZIP-экспорт пачки.

### Iteration 9 — Material layer stack (v1)

1. Архитектура «layer stack» в state.
2. UI списка слоёв с drag-sort.
3. 5 стартовых слоёв: brick, plank, stone-cluster, snow-drift, cracks.
4. Per-layer strength/blend/mask.
5. Height-contribution per layer → агрегированная high-fidelity normal.

### Iteration 10 — Material layer stack (v2)

1. Остальные слои из §4.2 (moss, rivets, runes, puddles, debris, rust, sand, concrete, mud, hex, cobblestone).
2. Noise presets + biome palettes + kmeans tint из текстуры.
3. Directional weathering (sun-azimuth).

### Iteration 11 — PBR pipeline

1. Height / ORM / Emission / Flow атласы.
2. Export Godot `.tres` (Shape + Material).
3. Bleed padding в атласе.
4. Seam-lint checker.
5. Deterministic build proof.

### Iteration 12 — Shape extensions

1. Per-side heightPx.
2. Crown bevel control.
3. Outer chamfer.
4. Base erosion slider.
5. Per-corner style override.

---

## 7. Что стоит проверить в следующей итерации

- Действительно ли `applyPreset("mountain")` вызывается **до** первого `scheduleRender` в `boot()`. Если нет — HTML-дефолты конфликтуют с preset-значениями (см. §2.2 про `backRimRatio`).
- Кросс-браузер: `willReadFrequently: true` на 2D-контекстах для всех canvas, с которых читаем `getImageData` (сейчас только у `readTexture`). Иначе Chrome логирует warning.
- Объём памяти при `tileSize=96, variants=6`: 6 × 47 × 96² × 4 байта × 2 прохода ≈ 20 МБ пиксельных данных + столько же атласа. Для ноутбука не критично, но вкладка легко съест 500 МБ при частых rebuild без GC-пауз.

---

## 8. TL;DR для себя

- **Главный quick-win:** разделить rebuild на стадии и дебаунсить — без этого UX задушен уже сейчас.
- **Главный арт-win:** превратить материалы в layer-stack с 20+ модулями — это то, что реально превратит генератор из «заготовки горы» в «универсального конструктора поверхностей».
- **Главный movie-win:** экспорт Godot `.tres` и ORM-атлас — закрывает мост от тула к runtime без ручной конвертации.

Дальнейшая работа логично идёт сверху вниз по §6.
