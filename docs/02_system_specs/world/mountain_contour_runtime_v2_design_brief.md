---
title: Mountain Contour Runtime V2 — Design Brief
doc_type: design_brief
status: draft
owner: engineering+art
created: 2026-05-13
source_of_truth: false
related_docs:
  - docs/02_system_specs/meta/packet_schemas.md
  - docs/02_system_specs/world/terrain_hybrid_presentation.md
  - docs/02_system_specs/world/oversized_terrain_presentation.md
  - tools/rimworld-autotile-lab/desktop_app/README.md
  - gdextension/src/mountain_contour.cpp
  - core/systems/world/chunk_view.gd
  - core/systems/world/world_streamer.gd
---

# Mountain Contour Runtime V2 — Design Brief

## 1. Короткое резюме

Нужно перенести художественное качество `Cliff Forge` / `rimworld-autotile-lab` preview в реальную игру, но не повторять провал `perenos v.1`.

Цель: горы должны выглядеть как в генераторе — с верхней площадкой, фасадом вниз, кромкой, нижней обводкой, высокодетальной текстурой и normal maps — при этом копание должно обновлять визуал и collision быстро, без квадратных fallback-тайлов и без задержки исчезновения выкопанной клетки.

Предлагаемый подход:

```text
клеточная логика мира + runtime diff от копания
        ↓
быстрый native contour runtime builder
        ↓
единая production contour-структура:
  - visual mesh
  - collision footprint
  - edge/rim/face metadata
        ↓
generator-authored contour style shader:
  - top / face / base textures
  - top / face normals
  - rim / outline / debris / height параметры
```

Генератор остаётся главным инструментом настройки внешнего вида. Игра не должна генерировать большие per-chunk SDF-картинки при копании. Игра должна быстро пересобирать геометрию и collision, а shader должен применять стиль, экспортированный из генератора.

Рабочее название: **Mountain Contour Runtime V2**.

---

## 2. Зачем это нужно

Сейчас мир логически клеточный, и это нормально для save/load, mining, chunk streaming и world diff. Проблема в том, что визуал и collision не должны выглядеть и ощущаться клеточными.

Нужный результат:

- не видно квадратов `64 × 64`;
- горы выглядят как цельный природный массив;
- фасад горы идёт вниз, как в preview генератора;
- верх горы выглядит как площадка / срез;
- фасад и верх используют разные материалы и разные normal maps;
- нижняя обводка есть только снизу фасада;
- при копании новая дырка получает такие же красивые края и фасад;
- collision идёт по видимой форме, а не по квадратам;
- игрок и NPC мягко скользят вдоль округлой стены;
- после копания визуал и collision обновляются сразу, без stale-состояния.

---

## 3. Чего делать нельзя

Эти запреты являются частью brief и должны быть перенесены в будущую system spec.

- Не возвращать `perenos v.1` целиком.
- Не пересоздавать большие `mask / height / normal / collision_sdf` textures после каждого копания.
- Не вызывать `ImageTexture.create_from_image()` на hot path копания.
- Не делать half-resolution render с последующим upscale.
- Не оставлять квадратные mountain TileMap cells как видимый fallback.
- Не использовать `walkable_flags` как fallback collision рядом с contour terrain.
- Не ждать async contour readiness после mining.
- Не менять save format ради визуала.
- Не менять logical tile size и chunk size.
- Не ломать текущий generator preview как художественный инструмент.

Если contour cache для chunk отсутствует, движение не должно использовать квадратный fallback. Правильное fail-safe поведение: считать область неготовой / заблокированной до готовности contour cache.

---

## 4. Текущая отправная точка

### 4.1. Мир и логика

Текущий runtime использует:

```text
TILE_SIZE_PX = 64
CHUNK_SIZE = 16
CHUNK_CELL_COUNT = 256
```

Логика мира, diff от копания, save/load и chunk packet остаются клеточными. Это не проблема. Визуал и collision должны быть производными от этих данных.

### 4.2. Текущий F10 contour

Сейчас F10 использует debug-путь: native helper строит marching-squares mesh из `solid_halo` и возвращает `vertices / indices`. Это хорошее доказательство, что маленький contour rebuild может быть быстрым.

Но текущий F10 результат является debug-only. Он не должен напрямую стать production terrain без расширения, потому что сейчас не содержит:

- production visual layers;
- face/rim/bottom outline metadata;
- collision loops;
- capsule-safe movement data;
- seam ownership;
- parity contract с генератором.

### 4.3. Генератор

`Cliff Forge` уже умеет экспортировать художественные данные:

- `top_albedo`;
- `face_albedo`;
- `base_albedo`;
- `top_normal`;
- `face_normal`;
- modulation textures;
- recipe параметры вроде `rim_width`, `edge_debris`, `mountain_outline_enabled`, `mountain_outline_width`, `normal_strength`, `normal_detail_strength`, `south_height`, `north_height`, `side_height`.

Эти данные должны стать источником стиля для игры.

---

## 5. Главная архитектурная идея

Нужно отделить **форму** от **стиля**.

### Форма

Форма строится в игре из текущих runtime-данных:

```text
base terrain packet
+ runtime diff от копания
+ one-tile или bounded halo
→ contour topology
```

Форма отвечает за:

- где находится гора;
- где верхняя площадка;
- где фасад;
- где нижняя видимая линия;
- где collision footprint;
- где seam между chunk’ами.

### Стиль

Стиль экспортируется генератором:

```text
contour_style_recipe.v1.json
+ top / face / base textures
+ top / face normals
+ modulation maps
+ profile LUTs
```

Стиль отвечает за:

- цвет и текстуру верха;
- цвет и текстуру фасада;
- толщину и цвет кромки;
- нижнюю обводку;
- edge debris;
- normal response;
- world-space UV scale;
- face-space UV scale;
- художественные параметры preview.

Игра не должна пересчитывать этот стиль при копании. Она должна пересобирать только contour mesh и collision cache.

---

## 6. Целевой runtime pipeline

```text
WorldStreamer / ChunkView
  получает ChunkPacketV1 + runtime diff
        ↓
MountainContourRuntimeBuilder
  читает mountain solid halo
  строит production contour result
        ↓
MountainContourChunkResult
  top_mesh
  face_mesh
  rim_mesh
  bottom_outline_mesh
  collision_loops
  seam metadata
  debug stats
        ↓
MountainContourLayer
  обновляет ArrayMesh / MeshInstance2D surfaces
  применяет ShaderMaterial из generator style
        ↓
ContourCollisionWorld
  обновляет chunk collision cache
  отвечает на capsule movement / NPC / building placement queries
```

---

## 7. Production contour result

Новый native result не должен называться debug. Предлагаемый контракт:

```text
MountainContourChunkResultV2 {
  chunk_coord: Vector2i
  revision: int

  top_vertices: PackedVector2Array
  top_indices: PackedInt32Array
  top_uv0: PackedVector2Array
  top_custom: PackedFloat32Array

  face_vertices: PackedVector2Array
  face_indices: PackedInt32Array
  face_uv0: PackedVector2Array
  face_custom: PackedFloat32Array

  rim_vertices: PackedVector2Array
  rim_indices: PackedInt32Array
  rim_custom: PackedFloat32Array

  bottom_outline_vertices: PackedVector2Array
  bottom_outline_indices: PackedInt32Array
  bottom_outline_custom: PackedFloat32Array

  collision_loops: Array[PackedVector2Array]
  collision_revision: int

  seam_edges: Dictionary
  stats: Dictionary
}
```

`custom` channels должны передавать shader’у не готовую картинку, а параметры:

- `edge_distance_px`;
- `face_depth_px`;
- `zone_kind`;
- `edge_kind`;
- `world_noise_coord`;
- `style_variant`;
- возможно `signed_edge_side` или `edge_normal`.

---

## 8. Rendering model

Гора рисуется не через square `TileMapLayer`, а через dedicated contour layer.

```text
ChunkView
  TerrainBaseLayer         # временно ground/dug/water старым путём, пока не перенесены
  TerrainOverlayLayer
  WaterSurfaceLayer
  MountainContourLayer     # новый production visual layer
  Roof/Cover layers        # должны быть совместимы позже
```

Для первой итерации mountain TileMap cells должны быть отключены как visible terrain. Они могут оставаться только как логические `terrain_ids` внутри packets/diff.

### Визуальные поверхности

```text
Top surface
```

Верхняя площадка горы. Использует `top_albedo`, `top_normal`, top modulation, world-space UV.

```text
Face surface
```

Фасад вниз. Использует `face_albedo`, `face_normal`, face modulation, face-space UV. Фасад строится по нижним и диагональным boundary edges, как в preview.

```text
Rim surface
```

Кромка между top и face. Толщина, цвет, debris и normal response берутся из style recipe.

```text
Bottom outline surface
```

Тёмная линия контакта только снизу фасада. Не должна обводить весь контур.

---

## 9. Shader model

Shader не должен получать per-chunk mask/height/normal textures. Он должен получать:

- geometry attributes;
- style textures;
- маленькие profile LUTs;
- global style params.

Предлагаемые texture slots:

```text
top_albedo_tex
face_albedo_tex
base_albedo_tex

top_normal_tex
face_normal_tex

top_modulation_tex
face_modulation_tex

edge_profile_lut
height_profile_lut
```

Предлагаемые scalar/vector params:

```text
top_world_scale_px
face_world_scale_px
macro_world_scale_px
rim_width_px
edge_debris
edge_color_strength
bottom_outline_enabled
bottom_outline_width_px
south_height_px
north_height_px
side_height_px
normal_strength
normal_detail_strength
```

Normal blending:

```text
material_normal = top_normal или face_normal
shape_normal = функция(edge_distance, face_depth, height_profile_lut)
final_normal = blend(shape_normal, material_normal)
```

Это нужно для динамического освещения солнцем/лампами без runtime normal texture generation.

---

## 10. Collision model

Collision должен идти по той же production contour-структуре, что и визуал.

Требование: collision идёт по **нижней видимой линии фасада**, а не по квадратной клетке.

Значит collision footprint для горы:

```text
top contour area
+ visual face extrusion down
+ bottom outline boundary
= blocked mountain footprint
```

Movement API должен быть capsule-based:

```text
is_capsule_walkable_at_world(pos: Vector2, radius: float) -> bool
move_capsule_with_slide(start: Vector2, motion: Vector2, radius: float) -> Dictionary
```

NPC используют тот же query, что и игрок.

Building placement должен использовать contour collision footprint, а не только tile grid. Это позволит ставить объекты вдоль диагональной стены, если объект реально помещается.

Fallback policy:

```text
contour collision cache ready     → use contour collision
contour collision cache not ready → blocked / chunk not ready
```

Квадратный fallback запрещён.

---

## 11. Mining update model

При исчезновении одного mountain tile:

```text
1. WorldDiffStore записывает override → PLAINS_DUG
2. loaded packet arrays обновляются
3. ChunkView обновляет dug ground cell
4. MountainContourRuntimeBuilder rebuild текущего chunk
5. Если tile на seam, rebuild нужных соседних chunks
6. MountainContourLayer обновляет mesh surfaces
7. ContourCollisionWorld обновляет collision cache
8. Event/debug stats фиксируют latency
```

Update должен быть синхронным для изменённого chunk’а или иметь гарантированное frame-bounded применение без stale visual. Игрок не должен видеть задержку исчезновения выкопанной горы.

Performance target:

```text
обычный dig: желательно <= 16–33 ms
seam dig: желательно <= 50 ms
hard ceiling: <= 100 ms
```

Нельзя батчить исчезновение нескольких tiles в production mining, потому что tile исчезает после завершения конкретного mining action.

---

## 12. Seam policy

Chunk seam должен быть идеальный.

Production contour builder должен получать bounded halo и иметь deterministic seam ownership:

- одинаковый input на обеих сторонах seam даёт одинаковую boundary geometry;
- edge noise / contour warp должен быть world-space deterministic, а не chunk-local;
- vertices на seam должны совпадать или быть явно owned одной стороной;
- collision loops не должны иметь щели на границе chunk.

Acceptance test обязан включать копание на границе chunk.

---

## 13. Generator export contract

Нужен новый лёгкий export mode или новый файл поверх текущего export:

```text
ContourStyleV1
```

Пример файлов:

```text
mountain_contour_style.v1.json
mountain_top_albedo.png
mountain_face_albedo.png
mountain_base_albedo.png
mountain_top_normal.png
mountain_face_normal.png
mountain_top_modulation.png
mountain_face_modulation.png
mountain_edge_profile_lut.png
mountain_height_profile_lut.png
mountain_reference_preview.png
mountain_reference_normal.png
```

Style recipe должен хранить все параметры, которые пользователь может менять в генераторе без правки runtime code:

```json
{
  "schema": "station_peaceful.contour_style.v1",
  "asset_name": "mountain",
  "preset": "mountain",
  "tile_size_px": 64,
  "authoring_tile_size_px": 128,
  "projection": {
    "top_world_scale_px": 224.0,
    "face_world_scale_px": 112.0,
    "macro_world_scale_px": 448.0
  },
  "geometry_style": {
    "south_height_px": 64,
    "north_height_px": 0,
    "side_height_px": 0,
    "corner_round_px": 32,
    "diagonal_smooth_px": 64,
    "contour_warp_px": 1.5,
    "roughness": 10.0,
    "rim_width_px": 16,
    "edge_debris": 0.8,
    "edge_color_strength": 0.35,
    "bottom_outline_enabled": true,
    "bottom_outline_width_px": 6
  },
  "normal_style": {
    "normal_strength": 8.0,
    "normal_detail_strength": 4.0
  },
  "textures": {
    "top_albedo": "mountain_top_albedo.png",
    "face_albedo": "mountain_face_albedo.png",
    "base_albedo": "mountain_base_albedo.png",
    "top_normal": "mountain_top_normal.png",
    "face_normal": "mountain_face_normal.png",
    "top_modulation": "mountain_top_modulation.png",
    "face_modulation": "mountain_face_modulation.png",
    "edge_profile_lut": "mountain_edge_profile_lut.png",
    "height_profile_lut": "mountain_height_profile_lut.png"
  }
}
```

`authoring_tile_size_px` может быть больше runtime logical tile size. Runtime не меняет логическую сетку; он только использует стиль и scale.

---

## 14. Preview parity requirement

Генератор должен оставаться полезным. Поэтому нужен parity gate:

```text
same mask
same contour style recipe
same textures
same camera

Generator reference render
vs
Godot runtime contour render
```

Сравнивать нужно:

- silhouette coverage;
- albedo diff;
- normal diff;
- bottom outline placement;
- seam pixels;
- фасад после копания;
- diagonal cases.

Если Godot render не похож на generator preview, итерация не принимается.

Важно: для полного совпадения generator и runtime должны использовать один style contract. Если генератор добавляет новый художественный эффект, runtime shader должен поддержать соответствующее поле recipe. Иначе эффект не появится в игре автоматически.

---

## 15. First scope

Первая production-итерация должна быть только про горы.

В scope:

- `TERRAIN_MOUNTAIN_WALL`;
- `TERRAIN_MOUNTAIN_FOOT`;
- mining горы в `PLAINS_DUG`;
- визуал горы через contour mesh;
- collision горы через contour footprint;
- player/NPC movement query;
- chunk seam test;
- generator parity test.

Out of first scope:

- земля как contour terrain;
- dug ground как полноценный contour terrain;
- lake bed / shore contour;
- biome variants;
- ore/rock-type variants;
- full roof/cavity rewrite.

Эти пункты должны прийти позже, после доказанного mountain pipeline.

---

## 16. Acceptance criteria

### Visual

- Квадраты `64 × 64` не видны на горе.
- Гора имеет верхнюю площадку и фасад вниз.
- Кромка и нижняя обводка соответствуют generator style.
- Верх и фасад используют разные textures и normal maps.
- Выкопанная дырка получает такой же фасад/кромку, как внешний край.
- Нет видимых seam cracks между chunk’ами.
- Godot runtime screenshot проходит visual parity с generator reference.

### Collision

- Player capsule не упирается в невидимые квадратные углы.
- Player capsule не проходит сквозь видимую гору.
- Collision идёт по нижней видимой линии фасада.
- NPC используют тот же contour query.
- Нет квадратного fallback рядом с contour terrain.
- Если contour cache не готов, область считается blocked/not ready.

### Mining

- После исчезновения tile visual обновляется сразу.
- Collision обновляется вместе с visual.
- Обычный dig укладывается в целевой latency budget.
- Seam dig не создаёт трещин и stale collision.

### Performance

- Нет per-dig generation больших `ImageTexture`.
- Нет per-dig full-chunk SDF texture buffers.
- Нет многосекундного contour readiness.
- Стабильный gameplay target: 60 FPS минимум, желательно 120 FPS, на GTX 1060 / Ryzen 2600 class hardware.
- Карта, заполненная горами, не должна ломать streaming или mining latency.

---

## 17. Proposed iterations

### Iteration 01 — Design and contract lock

Deliverables:

- этот design brief;
- ADR: почему выбран generator-authored contour mesh runtime;
- system spec: `Mountain Contour Runtime V2`;
- export contract: `ContourStyleV1`;
- test/acceptance matrix.

### Iteration 02 — Generator style export

Deliverables:

- `ContourStyleV1` export mode or additive export file;
- texture slots for top/face/base/normal/modulation;
- edge/height profile LUTs;
- reference preview/normal output for parity tests.

No gameplay code cutover yet.

### Iteration 03 — Native production contour builder

Deliverables:

- `MountainContourChunkResultV2` native API;
- top/face/rim/bottom-outline mesh generation;
- collision loops;
- seam deterministic behavior;
- no rendering cutover yet except debug/probe scene.

### Iteration 04 — Godot mountain contour visual layer

Deliverables:

- `MountainContourLayer` in `ChunkView`;
- shader material from `ContourStyleV1`;
- old mountain TileMap visual disabled;
- generator-vs-Godot parity screenshot test.

### Iteration 05 — Contour collision and movement

Deliverables:

- `ContourCollisionWorld`;
- capsule query and slide;
- player movement uses contour collision;
- NPC path/movement uses same query or safe wrapper;
- no square fallback.

### Iteration 06 — Mining dirty update

Deliverables:

- mining triggers immediate contour rebuild;
- seam-neighbour rebuild when needed;
- visual and collision revision update together;
- latency tests for normal dig and seam dig.

### Iteration 07 — Hard acceptance and cutover

Deliverables:

- mountain TileMap visual fully removed;
- stale/fallback checks;
- stress test with dense mountain map;
- final parity screenshots;
- docs updated from draft to accepted.

---

## 18. Risks

### 18.1. Preview mismatch

Самый большой риск: generator preview и Godot runtime shader разойдутся. Mitigation: один style contract, reference images, visual diff gate.

### 18.2. Collision mismatch

Если visual footprint и collision footprint строятся разными путями, появятся невидимые стены или проходы сквозь скалу. Mitigation: visual mesh и collision loops должны выходить из одного native contour result.

### 18.3. Shader complexity

Если попытаться перенести абсолютно все SDF preview эффекты в shader сразу, первая итерация может стать слишком большой. Mitigation: сначала перенести обязательные эффекты mountain preset, но contract оставить расширяемым.

### 18.4. Seam cracks

World-space noise и chunk-local generation могут дать разный край на соседних chunk’ах. Mitigation: deterministic world-space sampling, halo, seam tests.

### 18.5. Runtime hidden fallback

Fallback на старые квадратные flags может временно скрыть баги, но нарушит цель. Mitigation: automated grep/test/debug state, где fallback рядом с contour terrain запрещён.

---

## 19. Open questions for later spec

- Точная структура `custom` vertex attributes для Godot shader.
- Нужен ли один `ArrayMesh` с surfaces или несколько `MeshInstance2D`.
- Как именно кодировать `collision_loops` для fast capsule query.
- Какой допустимый numeric threshold для visual diff с generator preview.
- Нужно ли preview генератора добавить отдельный `runtime parity mode` без изменения основного live preview.
- Как roof/cavity/cover будет стыковаться с contour terrain после mountain cutover.
- Как потом переносить `PLAINS_GROUND`, `PLAINS_DUG`, `LAKE_BED_SHALLOW`, `LAKE_BED_DEEP` на тот же contour architecture.

---

## 20. Recommendation

Не начинать с кода и не начинать с implementation plan.

Сначала нужно зафиксировать:

1. этот design brief;
2. ADR по архитектурному выбору;
3. system spec с точными runtime/export контрактами;
4. test matrix;
5. только потом implementation plan с итерациями.

Иначе есть риск снова получить большой cutover, где одновременно меняются generator export, rendering, streaming, mining и collision.
