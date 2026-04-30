---
title: Hydrology Visual Quality V3 - Iteration Plan
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.1
last_updated: 2026-04-30
related_docs:
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - river_generation_v1.md
  - mountain_generation.md
  - organic_hydrology_shape_quality_v2_gpt55.md
  - world_foundation_v1.md
  - world_runtime.md
  - terrain_hybrid_presentation.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
---

# Hydrology Visual Quality V3 — Iteration Plan

## Purpose

Этот документ — приземлённый, основанный на актуальном code review план исправлений
визуального качества генерации воды и гор Station Mirny.

Он дополняет `organic_hydrology_shape_quality_v2_gpt55.md` (общий контракт качества,
GPT-5.5-friendly), но фокусируется на конкретных багах, найденных при анализе
текущего runtime в `gdextension/src/world_core.cpp`,
`gdextension/src/world_hydrology_prepass.cpp` и `gdextension/src/mountain_field.cpp`,
и наблюдаемых на скриншотах нового мира (M-overview + 33×33 region preview).

V3 ничего не переделывает с нуля. Он:

- закрывает 6 конкретных дефектов формы;
- сохраняет существующий native-only прайспас (`WorldHydrologyPrePass`);
- сохраняет shape `ChunkPacketV1` + текущие water/hydrology id-ы;
- бампит `WORLD_VERSION` шаг за шагом, без пакетных миграций.

## Gameplay Goal

Игрок при первом взгляде на overview карту и на 33×33 region preview должен видеть:

- горы выглядят как часть суши, а не "плавают" поверх океана;
- реки расширяются дельтой при впадении в океан и сужаются у истока, ширина
  непрерывно меняется вдоль русла;
- озёра находятся в естественных низинах, обходят горы, имеют органичную форму
  и не напоминают квадратные клетки;
- floodplain ("пойма") читается как мягкий аккуратный переход, а не контрастная
  зелёная полоса в стороне от русла.

## Scope

V3 покрывает:

- удаление гор поверх океана (визуальный артефакт + canonical packet output);
- ширину реки как непрерывную функцию вдоль `cumulative_distance`;
- настоящую дельту-fan-out при впадении высокопорядковых рек в океан;
- избегание гор натуральными озёрами на уровне tile, а не hydrology cell;
- shoreline озёр на уровне tile из контура basin и `lake_depth_ratio`;
- сглаживание/смягчение presentation `TERRAIN_FLOODPLAIN`.

V3 **не** покрывает (см. `organic_hydrology_shape_quality_v2_gpt55.md`):

- erozию, weather, swimming, fluid sim;
- multi-scale headland/bay (это уже V1-R17);
- островa в океане;
- shore/riverbed art (это будущая `TERRAIN_HYBRID_PRESENTATION` работа);
- любую runtime-mutable воду сверх существующего `EnvironmentOverlay` (V1-R6).

## Out of Scope

- любой rewrite hydrology graph или Priority-Flood;
- любые изменения `world.json` save schema;
- любые изменения `EventBus` сигналов;
- любые изменения runtime mutation path (`try_harvest_at_world`).

## Dependencies

- `World Foundation V1` для финитного цилиндра, ocean band tiles, foundation snapshot;
- `River Generation V1` (включая V1-R8..V1-R17) как baseline native hydrology;
- `Mountain Generation V1` (M1..M6) как канонический mountain field;
- ADR-0001 для классификации runtime work;
- ADR-0002 для wrap-safe X sampling;
- ADR-0003 для immutable base + runtime diff.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical / runtime / visual | Canonical: terrain ids, mountain flags, water_class, hydrology_flags. RAM-only: refined river width profile, lake SDF cache. Visual only: floodplain alpha gradient (presentation). |
| Save/load required | Нет. Все данные — функция `(seed, world_version, settings)`. `WORLD_VERSION` бампится поэтапно. |
| Deterministic | Да. Все правки — детерминированные функции тех же входов. |
| Must work on unloaded chunks | Да. Native прайспас уже это держит. |
| C++ или main-thread apply | Все правки — C++ native (`world_hydrology_prepass`, `world_core`, `mountain_field`). Main thread только публикует пакеты. |
| Dirty unit | 32×32 чанк для генерации; aligned 1024×1024 macro cell для гор; hydrology snapshot в RAM для рек/озёр/океана. Без runtime-mutable hydrology. |
| Single owner | `WorldCore` для базового пакета. `WorldHydrologyPrePassSnapshot` для cached refined geometry. `MountainField` для гор. Без новых владельцев. |
| 10x / 100x scale path | Все RAM-only refinements строятся per-snapshot. Spatial index уже есть. Per-chunk запросы остаются bounded. |
| Main-thread blocking | Нет. Все правки внутри уже native worker path. |
| Hidden GDScript fallback | Запрещён. Native required, как и сейчас. |
| Could become heavy later | Per-tile lake SDF read и continuous width lookup сложнее текущего per-cell. Митигировано RAM-only кэшем + bounded chunk halo. |
| Whole-world prepass | Уже native worker prepass. Никаких новых world-wide passes. |

## Code Review Findings (Root Causes)

### Finding 1 — Mountains painted over ocean tiles (RC1)

**Что:** `gdextension/src/world_core.cpp` строки 2147..2155 пишут
`TERRAIN_MOUNTAIN_WALL/FOOT` чисто на основе `mountain_id > 0 && elevation >= t_*`,
**до** проверки гидрологии. Затем строки 2357..2359:

```cpp
const bool hydrology_blocked =
        (resolved_mountain_flags & (MOUNTAIN_FLAG_WALL | MOUNTAIN_FLAG_FOOT)) != 0U;
if (has_hydrology && !hydrology_blocked) {
    // ocean / lake / river
}
```

Если гора есть, hydrology не пишется. Гора всегда побеждает океан.

`mountain_field::sample_elevation()` ничего не знает про `ocean_sink_mask` — это
чистая функция от `(seed, world_version, world_x, world_y, settings)`. Foundation
prepass `coarse_wall_density` / `coarse_foot_density` применяется отдельно (для
hydrology mountain_exclusion_mask), но не подавляет фактический mountain field
вблизи северного океанского band.

**Эффект:** на overview видны вершины гор, торчащие из синего океана сверху.

**Где:**
- `gdextension/src/world_core.cpp` chunk rasterization 2147..2155, 2357..2359;
- `gdextension/src/mountain_field.cpp` отсутствует ocean-band suppression;
- `gdextension/src/world_hydrology_prepass.cpp:2265..2309` (`build_mountain_clearance`)
  суппрессит mountain_exclusion_mask внутри ocean cells, но это только для рек,
  не подавляет mountain_field elevation.

### Finding 2 — Rivers don't widen at the ocean mouth (RC2)

**Что:** В `world_hydrology_prepass.cpp:1020..1022`:

```cpp
if (enable_v1_r5 && to_ocean && delta_scale > 0.0f) {
    edge.delta = true;
    edge.radius_scale = 1.0f + delta_scale * 0.85f;
}
```

При `delta_scale = 1.0` это даёт ~1.85× от обычной ширины — едва заметно.
`delta_branch` (1049..1062) — это просто параллельная braid_split линия, а не
разветвлённый fan.

`resolve_river_channel_radii` (`world_core.cpp:745..760`) использует
`edge_radius_scale` напрямую. Bank radius у дельты `+2.6` тайла — не видно
"распахивания" на shore.

**Эффект:** река входит в океан тонкой нитью. Никакого fan-out, никакого "delta
plain". Это и видно на скриншоте — реки буквально "обрезаны" на берегу.

### Finding 3 — Floodplain strip looks like a stripe, not a transition (RC3)

**Что:** `world_core.cpp:2533..2544` пишет `TERRAIN_FLOODPLAIN` бинарно при
`floodplain_potential > 0.62`. Сам `floodplain_potential` — per-hydrology-cell
(16 тайлов). Threshold резкий, без сглаживания.

Поэтому на 33×33 preview "пойма" читается как зелёные клетчатые ступени, а не
плавная полоса вдоль реки.

**Эффект:** игрок воспринимает это как "странная зелёная полоса от реки".
Технически это floodplain, но презентация не передаёт смысл.

### Finding 4 — Lakes overlap mountains (RC4)

**Что:** `world_hydrology_prepass.cpp:select_lake_basins` (2425..) проверяет
`mountain_exclusion_mask` только на hydrology cell granularity (16 тайлов).
`build_mountain_clearance` (2265..) тоже работает per-cell, использует
foundation `coarse_*_density` в центре cell.

Затем `sample_lake_raster` (`world_core.cpp:1469..1600`) при `center_lake_id > 0`
красит **всю** 16×16 cell как `TERRAIN_LAKEBED`. Если в этой cell действительно
есть mountain_id wall/foot тайлы (mountain field оперирует per-tile), то:

- mountain wall пишется как terrain (line 2148..2155);
- `hydrology_blocked` возвращает true (line 2358);
- lake тайлы внутри cell остаются lakebed, mountain wall тайлы остаются стеной.

В итоге визуально часть lake "лежит на горе" / гора стоит "в озере".

**Эффект:** видно "озеро под горой". Это и есть пункт 4.

### Finding 5 — River width is bucketed by stream order, not continuous (RC5)

**Что:** `world_core.cpp:resolve_river_channel_radii`:

```cpp
const float order_f = std::max(1.0f, static_cast<float>(p_sample.stream_order));
radii.deep_radius = std::max(0.55f, (0.35f + order_f * 0.16f) * scale);
```

`stream_order` — целое (бакет 1..N). Между бакетами скачки. `radius_scale` хоть
и `cumulative_distance`-modulated в V1-R16, но амплитуда `±0.045..0.08` — это
3..8% вариация, не визуально читаемый taper к истоку и устью.

**Эффект:** река выглядит "обрезанной" на конце — резко исчезает там, где
заканчивается edge с минимальным stream_order; не сужается органично к истоку,
не расширяется органично к устью между бакетами.

### Finding 6 — Lakes look square (RC6)

**Что:** `sample_lake_raster` (`world_core.cpp:1525`):

```cpp
if (center_lake_id > 0) {
    sample.is_lakebed = true;   // вся 16×16 cell — lakebed
    ...
}
```

Lake interior — целиком rectangular cell. Shore noise добавляется только на
**границах** между cell-ами с разным lake_id. Это даёт "квадратное озеро со
слегка изломанной кромкой по периметру".

`lake_depth_ratio` уже считается per-node в snapshot, но в rasterization
используется только для shore_width modulation, а не для решения "это вообще
часть basin или нет".

**Эффект:** игрок видит "квадратные озёра", особенно при близком зуме.

## Design Principles

### P1. Hydrology graph остаётся skeleton

V3 не меняет hydrology graph. Все правки — улучшение **визуальной проекции**
этого графа: refined centerline, basin SDF, ocean coastline already in V1-R15..R17.

### P2. Гора, океан, озеро, река — упорядоченная иерархия decisioning per tile

Per chunk tile порядок принятия решения становится:

1. **Океанский tile?** (organic coast SDF + ocean_band) → ocean / shore / shelf.
   Гора подавляется.
2. **Озёрный tile?** (basin contour SDF + lake_depth_ratio) → lakebed / lake shore.
   Гора подавляется внутри озера, river yields к озеру.
3. **Гора?** (mountain_id + elevation thresholds) → mountain wall / foot.
4. **Речной tile?** (refined centerline distance ≤ band radius) → riverbed / bank.
5. **Floodplain mask?** (smooth gradient, не binary) → floodplain или plain.
6. **Иначе** → plain.

### P3. Per-tile вода для shape quality, не per-cell

Решение "вода или нет" должно браться на основе тайл-уровневых SDF/contour
полей, не "центр cell — вода ⇒ вся cell — вода". Hydrology cell остаётся
authoritative для hydrology graph, но rasterization читает per-tile signed
distance.

### P4. Reaches вода как функция cumulative_distance

Width реки — непрерывная гладкая функция от `cumulative_distance` на
`river_segment`. Stream order остаётся как baseline, поверх — taper к истоку
и устью.

### P5. Дельта — fan-out из набора distributary edges

Дельта не "одна расширенная edge"; это набор детерминированных distributary
ветвей, расходящихся в shore band, каждая с убывающей шириной от устья наружу.

## Runtime Architecture

V3 — only-native. Только три файла native расширяются:

| File | Что меняется |
|---|---|
| `gdextension/src/mountain_field.cpp` | ocean-band suppression `sample_elevation` |
| `gdextension/src/world_hydrology_prepass.cpp` | per-tile mountain conflict check, lake SDF/depth field, refined width by cumulative_distance, distributary fan, lake basin tile-level mountain reject |
| `gdextension/src/world_core.cpp` | new decision order при чанк-rasterization, per-tile lake SDF query, per-tile ocean SDF query, soft floodplain gradient |

Никаких новых GDScript hot-loop-ов. Все per-tile вычисления — в native packet
generation.

## Event Contracts

Не меняются. `world_initialized`, `chunk_loaded`, `chunk_unloaded`,
`water_overlay_changed` остаются как есть.

## Save / Persistence Contracts

Не меняются. `world_version` бампится **поэтапно** (см. итерации). Существующие
сохранения остаются load-compatible через ветку legacy-version в каждом native
шаге.

## Performance Class

| Operation | Class | Dirty unit | Budget |
|---|---|---|---|
| Mountain ocean-band suppression | background (native) | per-tile, inside chunk packet | внутри уже native sample, +O(1) per tile |
| Refined width continuous along distance | background (native) | per refined edge sample | +O(1) per sample, без extra prepass |
| Distributary fan для дельты | background (native) | last 1..3 reaches before ocean terminal | +O(K) per river, K ≤ 6, RAM-only |
| Lake basin tile-level mountain reject | background (native) | per candidate basin cell | +1 tile-grid sweep по basin |
| Lake SDF rasterization | background (native) | per chunk tile с halo | bounded by chunk halo, no full lake scan |
| Soft floodplain gradient | background (native) | per chunk tile | +O(1) bilinear on existing field |

Никаких main-thread loop-ов. Никаких new globally-scaling passes.

## Acceptance Criteria

### General
- [ ] same `(seed, world_version, settings)` всегда даёт идентичный output
- [ ] без новых сейв-полей; `world.json` shape не меняется
- [ ] world_version бампится для каждой итерации, ломающей canonical output
- [ ] V0-V1 пакетные форматы не меняются
- [ ] нет новых main-thread tile-loop-ов, нет новых GDScript hot loops

### Mountains
- [ ] на overview ни один mountain wall/foot pixel не появляется внутри океанской
      зоны (`ocean_sink_mask`)
- [ ] mountain_id остаётся 0 на ocean tiles
- [ ] near-coast mountains имеют smooth fade-out перед береговой линией

### Rivers
- [ ] ширина reach непрерывно растёт от истока к устью на одной и той же реке
- [ ] никаких видимых "step" разрывов ширины между двумя соседними edges
- [ ] высоко-порядковые реки впадают в океан через distinct distributary fan
      (минимум 2 distributary edges, общий fan width ≥ 3× ширины коренной reach)
- [ ] устьевая дельта пишет `HYDROLOGY_FLAG_DELTA` на всех distributary tiles
- [ ] исток сужается плавно (taper последних 5..10 тайлов до 0.4× ширины)

### Lakes
- [ ] озёра не перекрываются mountain wall/foot тайлами (zero overlap)
- [ ] озёра имеют округлую форму — bounding rectangle охватывает озеро не более
      чем на 70% от своей площади (т.е. >30% bounding rect — не lakebed)
- [ ] shoreline lake не показывает 90° углы 16-тайловой сетки

### Floodplain
- [ ] floodplain пишется не по бинарному порогу, а по плавному gradient
      (smoothstep на `floodplain_potential`)
- [ ] floodplain stripe ширина варьирует с stream order и slope
- [ ] нет "ступенек" между cells разной классификации floodplain в overview

### Performance
- [ ] прайспас остаётся в RAM, не пишет ничего нового в save
- [ ] chunk packet генерация остаётся worker-side
- [ ] нет регрессии тайма прайспаса больше +20% на large preset

### Governance
- [ ] LAW 4: каждая итерация бампит world_version
- [ ] LAW 9: нет GDScript fallback
- [ ] ADR-0003: base immutable, нет diff-write на mountain/lake/river

## Failure Cases / Risks

- **R1.** Ocean-band mountain suppression может переусердствовать и срезать прибрежные
  холмы. Митигация: smooth fade-out band (не hard cutoff), tunable distance.
- **R2.** Distributary fan может пересекать mountain shores. Митигация: каждая
  distributary edge проверяется на `mountain_exclusion_mask` перед эмитом.
- **R3.** Tile-level lake SDF удорожает chunk rasterization. Митигация: SDF
  читается из RAM-only spatial index, query по chunk halo, не по всему миру.
- **R4.** Continuous river width может породить редкие "тонкие" реки на низком
  stream order. Митигация: hard floor `min_width_tiles = 1.5` всегда.
- **R5.** Soft floodplain gradient может слиться с обычным ground в финальном
  presentation. Митигация: presentation gradient остаётся отдельным цветом, но
  плавный, как trans-region (визуальное решение в hybrid presentation).
- **R6.** World version drift — много мелких бампов. Митигация: каждый шаг
  legacy-compatible через явный `world_version >= V_X` guard.

## Resolved Questions

User approved the following resolutions on 2026-04-30. They are binding for all
V3 iterations.

### Q1 — World version bump strategy: single atomic bump at V3 completion

**Decision:** один бамп `WORLD_VERSION` 29 → 30 в финальной итерации V3-6 при
мердже всей V3 серии в `main`.

**Implementation discipline (binding):**
- все 6 итераций V3-1..V3-6 разрабатываются в фича-ветке
  `feature/hydrology_visual_v3`;
- ни одна V3 итерация не мерджится в `main` отдельно;
- все native изменения V3 гейтятся одним guard `world_version >= 30` (или
  эквивалентным `WORLD_HYDROLOGY_VISUAL_V3_VERSION` константой);
- legacy путь для `world_version <= 29` остаётся ровно тем, что в `main` сейчас;
- финальный мердж — атомарный: native код, single version bump, обновления
  meta-доков и presentation в одном PR.

**Rationale:** соответствует LAW 4 (`ENGINEERING_STANDARDS.md`). Если бы
итерации мерджились в `main` поэтапно без bump-а, для одного и того же
`(world_seed, chunk_coord)` canonical output менялся бы между релизами
без version sentinel, ломая существующие сейвы.

**Tradeoff:** longer feature branch life. Митигация — каждая итерация всё
равно landed как отдельный commit в фича-ветке, с собственными acceptance
tests, и каждая может быть rolled back без затрагивания остальных. Финальный
PR в `main` содержит summary всех 6 шагов.

### Q2 — Delta fan count: reuse delta_scale

**Decision:** distributary fan-out переиспользует существующее настройку
`RiverGenSettings.delta_scale`. Никакого нового setting.

**Mapping (binding):**
```text
fan_count = clamp(round(2 + delta_scale * 3), 2, 6)
```

| `delta_scale` | `fan_count` | Visual feel |
|---|---|---|
| 0.0 | (нет дельты) | дельта-fan не эмитится |
| 0.5 | 3 ветви | компактная дельта |
| 1.0 (default) | 5 ветвей | классический веер |
| 2.0 | 6 ветвей | широкий разлив |

**Rationale:** минимально достаточное изменение по WORKFLOW (one task, one
step). `delta_scale` уже в `RiverGenSettings`, в `world.json`, в
`worldgen_settings.rivers` и в Water Sector UI — никаких новых полей,
миграций или UI слайдеров. Игрок управляет силой дельты единой ручкой,
которую уже видит.

**Forbidden in V3:** добавление `delta_fan_count`, `delta_fan_min`,
`delta_fan_max` или любого другого нового поля в `RiverGenSettings`. Если
позже понадобится более тонкий контроль — отдельный V4 амендмент с явным
обновлением `RiverGenSettings`, `save_and_persistence.md`,
`packet_schemas.md` и UI.

### Q3 — Floodplain: change packet contract + presentation

**Decision:** floodplain переходит на explicit packet contract с smoother
gradient. Меняем canonical packet output, и presentation работает поверх.

**Packet changes (binding):**
- существующий `floodplain_strength: PackedByteArray` (1024 per chunk)
  остаётся, но больше не зависит от binary `floodplain_potential > 0.62`;
  он становится smooth `smoothstep(0.45, 0.85, floodplain_potential) * 255`,
  с per-tile bilinear sampling;
- `terrain_id = TERRAIN_FLOODPLAIN` пишется только при
  `floodplain_strength >= 96`. Между этим порогом и 0 — обычный
  `TERRAIN_PLAINS_GROUND` с не-нулевой `floodplain_strength` в packet,
  чтобы presentation мог рисовать gradient overlay;
- два новых битовых флага в `hydrology_flags`:
  - `HYDROLOGY_FLAG_FLOODPLAIN_NEAR = 1 << 9` — strength ∈ [192, 255];
  - `HYDROLOGY_FLAG_FLOODPLAIN_FAR = 1 << 10` — strength ∈ [96, 192).
  существующий `HYDROLOGY_FLAG_FLOODPLAIN = 1 << 4` остаётся для tile-ов с
  TERRAIN_FLOODPLAIN.

**Presentation changes (binding):**
- `terrain_hybrid_presentation` или его наследник читает
  `floodplain_strength` per-tile;
- gradient: 0..96 — обычная земля без оверлея; 96..192 — лёгкий vegetation
  oversaturation overlay; 192..255 — `TERRAIN_FLOODPLAIN` основная плитка.

**Required canonical doc updates (binding):**
- `docs/02_system_specs/meta/packet_schemas.md` — добавить два новых флага
  `HYDROLOGY_FLAG_FLOODPLAIN_NEAR` и `HYDROLOGY_FLAG_FLOODPLAIN_FAR` в
  `hydrology_flags` table;
- `docs/02_system_specs/world/river_generation_v1.md` — обновить
  `Status and Current-Code Boundary` с описанием V3 floodplain semantics;
- `docs/02_system_specs/world/terrain_hybrid_presentation.md` — добавить
  раздел про `floodplain_strength` gradient consumption.

**Rationale:** binary threshold даёт ступенчатый артефакт. Smooth
strength + new flags позволяют presentation делать аккуратный gradient,
а будущие системы (фауна, погода, sound) могут читать гладкое поле без
guess-work. Это входит в общий V3 single bump.

## Implementation Iterations

Каждая итерация — отдельный commit в фича-ветке `feature/hydrology_visual_v3`.
Ни одна итерация не мерджится в `main` отдельно. Финальный мердж в `main` —
атомарный, с единым `WORLD_VERSION` bump 29 → 30 и обновлением canonical
docs (см. Q1, Q3 resolutions).

В native коде вводится одна общая константа:

```cpp
constexpr int64_t WORLD_HYDROLOGY_VISUAL_V3_VERSION = 30;
```

Все шесть итераций гейтятся одним и тем же guard:

```cpp
if (world_version >= WORLD_HYDROLOGY_VISUAL_V3_VERSION) {
    // V3 path: ocean-band suppression / continuous width / fan / etc.
} else {
    // legacy path: behavior identical to current main at version 29
}
```

Перед стартом каждой итерации пользователь подтверждает scope. Acceptance
tests итерации проверяются на seed-ах с `world_version = 30` (V3) и на
seed-ах с `world_version = 29` (legacy regression).

### Iteration V3-1 — Ocean-band mountain suppression

**Goal:** убрать горы, торчащие из океана.

**Native changes (gated by `world_version >= 30`):**
- `mountain_field::sample_elevation`: добавить smooth attenuation по Y близко
  к северному ocean band (foundation `ocean_band_tiles`). Параметр fade
  начинается за `2 × ocean_band_tiles` от верхнего края мира, к границе
  океана gain → 0.
- `world_core.cpp` chunk loop: после получения `elevation`, если для tile
  `foundation.ocean_sink_mask != 0` или tile внутри `ocean_band_tiles` —
  принудительно `elevation = 0`, `mountain_id = 0`. Это уже частично сделано
  для spawn safety; распространить на ocean band.

**Acceptance:**
- mountain pixel не появляется внутри `ocean_sink_mask` зоны на seed-ах с
  `world_version = 30`;
- foundation overview и hydrology overview согласованны;
- legacy worlds (`world_version <= 29`) не меняются (regression test).

**Files allowed:**
- `gdextension/src/mountain_field.cpp`
- `gdextension/src/mountain_field.h`
- `gdextension/src/world_core.cpp`
- `core/systems/world/world_runtime_constants.gd` (только bump)
- этот spec

**Files forbidden:**
- save collectors, appliers, save_io;
- UI preview canvas;
- любой GDScript runtime hot path.

### Iteration V3-2 — Continuous river width along cumulative distance

**Goal:** реки сужаются у истока, плавно расширяются к устью; никаких ступенек.

**Native changes (gated by `world_version >= 30`):**
- `world_hydrology_prepass.cpp`: при построении refined edges рассчитать
  `total_river_distance` для каждого `river_segment_ranges` chain (от source
  до terminal). Записать в каждый `RefinedRiverEdge`:
  - `cumulative_start / cumulative_end` (уже есть);
  - `total_distance` (новый RAM-only field);
  - `distance_at_source` (cumulative_start);
  - `distance_to_terminal` (total - cumulative_end).
- `world_core.cpp:resolve_river_channel_radii`: ширина = baseline(stream_order)
  × continuous_taper(t), где
  `t = cumulative_distance / total_distance`,
  `taper(t) = source_taper(t) × terminal_grow(t)`,
  `source_taper(t) = smoothstep(0.04, 0.18, t)` (sub-tail у истока),
  `terminal_grow(t) = lerp(1.0, 1.45, smoothstep(0.7, 0.97, t))`.
- остаётся floor `min_width_tiles = 1.5`.

**Acceptance:**
- единая река не показывает >0.5 tile скачков ширины между соседними edges
  на `world_version = 30`;
- последние 5 тайлов истока ≤ 0.6 × baseline width;
- последние 5 тайлов перед устьем ≥ 1.25 × baseline width (если без дельты);
- legacy `world_version = 29` width unchanged (regression).

### Iteration V3-3 — Distributary delta fan-out

**Goal:** реки впадают в океан через настоящую веерную дельту. Использует
`delta_scale` (см. Q2 resolution).

**Native changes (gated by `world_version >= 30`):**
- `world_hydrology_prepass.cpp`: для каждой `river_segment_ranges` chain,
  заканчивающейся в ocean terminal, и с `stream_order >= 3` и
  `delta_scale > 0`, эмитировать набор distributary edges:
  - `fan_count = clamp(round(2 + delta_scale × 3), 2, 6)` (см. Q2);
  - каждая ветвь стартует на главной reach в последних 1..3 hydrology cells
    до устья;
  - расходятся под небольшим углом к нормали shore (±15°..±35°);
  - каждая ветвь имеет свой `radius_scale` убывающий от 0.85 до 0.4 по
    `cumulative_distance` ветви;
  - все ветви валидируются `refined_branch_polyline_is_clear` (не пересекают
    mountain mask, не выходят за shore).
- помечаются `edge.delta = true`, `edge.braid_split = true` (для distributary).
- `world_core.cpp` chunk rasterization: уже умеет рисовать `HYDROLOGY_FLAG_DELTA`
  внутри `ocean_sink_mask`. Дополнительно — сглаженный fade-in width на shore,
  чтобы дельта "разливалась", а не обрезалась.

**Acceptance:**
- реки stream_order ≥ 3 имеют ≥ 2 distributary ветвей у устья на
  `world_version = 30`;
- общая ширина fan на shore ≥ 3× ширины main reach;
- delta tiles все помечены `HYDROLOGY_FLAG_DELTA`;
- distributary никогда не пересекают mountain mask;
- `delta_scale = 0` отключает fan;
- legacy `world_version = 29` дельта output unchanged (regression).

### Iteration V3-4 — Per-tile mountain conflict for lakes

**Goal:** озёра обходят горы на уровне tile, не на уровне 16-тайловой cell.

**Native changes (gated by `world_version >= 30`):**
- `world_hydrology_prepass.cpp:select_lake_basins`:
  - для каждой кандидатной cell дополнительно сэмплировать mountain_field
    в 4 точках внутри cell (по тайл-уровню). Если хотя бы одна — wall/foot,
    cell отвергается из basin candidate;
  - alternatively (предпочтительно): расчитать lake basin на пост-этапе
    "tile-level prune": basin SDF carve вокруг mountain wall/foot тайлов,
    lake_depth_ratio re-derived по чистым tile-ам.
- `world_core.cpp`: при rasterization, перед `terrain_id = TERRAIN_LAKEBED`,
  дополнительная проверка `mountain_id == 0`. Если mountain — lakebed yield,
  гора побеждает.

**Acceptance:**
- ноль перекрытий между озером и mountain wall/foot тайлами на overview
  при `world_version = 30`;
- lake outlets всё ещё корректно соединяются с river network;
- regression check на legacy `world_version = 29`: lake count и геометрия
  unchanged.

### Iteration V3-5 — Per-tile lake basin SDF rasterization

**Goal:** убрать "квадратность" озёр.

**Native changes (gated by `world_version >= 30`):**
- `world_hydrology_prepass.cpp`: добавить RAM-only поле:
  `lake_water_level_per_id` (float per lake_id) — уровень spill point.
  Уже есть basin contour data (`lake_depth_ratio`, `lake_spill_node_mask`).
- `world_core.cpp:sample_lake_raster`: вместо "если центр cell — lake, вся
  cell — lakebed", сэмплить per tile:
  - bilinear sample `filled_elevation`, `hydro_elevation` в точке tile;
  - tile is lakebed iff `(lake_id_nearest > 0) && (hydro_elevation_at_tile <= water_level + shoreline_noise(tile))`;
  - shoreline noise — детерминированный 2D noise (3..6 tile wavelength)
    на periphery, амплитуда 1..3 тайла;
  - shore tiles — band ≤ 1 tile вокруг contour.
- lake interior всё ещё сохраняет `lake_id` packet; rasterization меняется.

**Acceptance:**
- на `world_version = 30`: bounding rect lake — площадь lake ≤ 70% от
  площади bounding rect;
- 4 random orientations теста дают не более 20% sharedplane edges
  (т.е. shoreline ломаная, не сетка);
- shoreline visually не выравнивается по 16-тайловой сетке;
- legacy `world_version = 29`: lake rasterization unchanged.

### Iteration V3-6 — Soft floodplain gradient + final V3 merge

**Goal (двойной):**
1. Floodplain читается как мягкий переход у реки, с явными packet flags
   (см. Q3 resolution);
2. Финальный мердж всей V3 серии в `main` с единым `WORLD_VERSION` bump
   29 → 30 (см. Q1 resolution).

**Native changes (gated by `world_version >= 30`):**
- `world_hydrology_prepass.cpp`: bilinear `floodplain_potential` на per-tile
  level (уже хранится в snapshot per-cell, добавить spatial query).
- `world_core.cpp` chunk rasterization:
  - `floodplain_strength_byte = clamp(round(smoothstep(0.45, 0.85, fp) * 255), 0, 255)`;
  - `terrain_id = TERRAIN_FLOODPLAIN` только при `floodplain_strength >= 96`;
  - hydrology_flags запись:
    - `HYDROLOGY_FLAG_FLOODPLAIN` (bit 4, существующий) на TERRAIN_FLOODPLAIN tiles;
    - `HYDROLOGY_FLAG_FLOODPLAIN_NEAR` (bit 9, новый) при strength ∈ [192, 255];
    - `HYDROLOGY_FLAG_FLOODPLAIN_FAR` (bit 10, новый) при strength ∈ [96, 192).

**Constants update:**
- `world_runtime_constants.gd`: bump `WORLD_VERSION` 29 → 30, define
  `WORLD_HYDROLOGY_VISUAL_V3_VERSION = 30`, add new flag bits 9 и 10.

**Required canonical doc updates (atomic with V3 merge):**
- `docs/02_system_specs/world/river_generation_v1.md` — `Status and
  Current-Code Boundary`: add V1-R18 line ("V3 visual quality batch landed
  ocean-band mountain suppression, continuous river width, distributary
  fan-out, per-tile lake mountain conflict, per-tile lake basin SDF, soft
  floodplain gradient. Current new worlds advance to `world_version = 30`.");
- `docs/02_system_specs/world/mountain_generation.md` — add M7 iteration
  description for ocean-band suppression;
- `docs/02_system_specs/meta/packet_schemas.md` — add bits 9, 10 to
  `hydrology_flags` table;
- `docs/02_system_specs/meta/save_and_persistence.md` — note V3 batch
  bump (no save shape change);
- `docs/02_system_specs/world/terrain_hybrid_presentation.md` — add section
  про floodplain gradient consumption.

**Acceptance:**
- на `world_version = 30`: между floodplain и plain нет clear-cut границы;
- `floodplain_strength` packet field имеет smooth distribution (histogram
  не имеет binary spike);
- bit 9 и bit 10 hydrology_flags корректно выставлены;
- legacy `world_version = 29`: floodplain unchanged (regression);
- все 6 итераций (V3-1..V3-6) активны в одной ветке кода с guard
  `world_version >= 30`;
- все 5 canonical docs обновлены в том же PR.

**Pre-merge checklist (binding):**
- [ ] V3-1..V3-5 acceptance tests проходят на seed `world_version = 30`;
- [ ] regression suite проходит на seed `world_version = 29`;
- [ ] performance: prepass time на large preset ≤ +20% от baseline;
- [ ] все 5 canonical docs обновлены в этом же PR;
- [ ] grep evidence для каждого canonical doc update в closure report;
- [x] presentation gradient (V3-7 hook) landed as separate follow-up task.

### V3-7 (presentation polish)

V3-7 — отдельный follow-up task на presentation:
- `core/systems/world/terrain_presentation_registry.gd` —
  consumer для `floodplain_strength` gradient;
- `data/balance/water_presentation_*.tres`;
- `tools/world_hydrology_overview_*.gd`.

V3-7 не бампит world_version (presentation only). Может landить независимо
от main V3 PR, но не раньше его.

Implementation status:
- V3-7 landed as presentation-only follow-up after V3-6;
- `data/balance/water_presentation_floodplain.tres` owns floodplain overlay
  tuning;
- `ChunkView` applies a chunk-local one-pixel-per-tile overlay texture through
  the existing bounded publish batches;
- no packet shape, save shape, command/event boundary, or `WORLD_VERSION`
  changed.

## Required Canonical Doc Follow-Ups When Code Lands

Все обновления — атомарны с финальным V3 PR в `main` (см. Q1 resolution).
Промежуточные итерации в фича-ветке canonical docs не трогают.

При финальном мердже V3-6:
- `docs/02_system_specs/world/river_generation_v1.md` — `Status and
  Current-Code Boundary`: одна строка про V1-R18 / V3 batch с описанием
  canonical output изменений и новым `world_version = 30`;
- `docs/02_system_specs/world/mountain_generation.md` — раздел
  `Implementation Iterations`: M7 описание ocean-band suppression;
- `docs/02_system_specs/meta/packet_schemas.md` — добавить
  `HYDROLOGY_FLAG_FLOODPLAIN_NEAR (1 << 9)` и
  `HYDROLOGY_FLAG_FLOODPLAIN_FAR (1 << 10)` в `hydrology_flags` table;
- `docs/02_system_specs/meta/save_and_persistence.md` — note V3 batch bump
  (без изменения save shape);
- `docs/02_system_specs/world/terrain_hybrid_presentation.md` — секция про
  consumption `floodplain_strength` gradient (если presentation добавляется
  в этом же PR; иначе deferred V3-7 task с явной ссылкой).

`not required` записи требуют grep-доказательства, как в WORKFLOW.md.

## Status Rationale

Документ **approved** пользователем 2026-04-30 c явным выбором по Q1, Q2, Q3:
- Q1 = single atomic bump 29 → 30 в финальной итерации;
- Q2 = переиспользовать `delta_scale`, mapping
  `fan_count = clamp(round(2 + delta_scale * 3), 2, 6)`;
- Q3 = новые packet flags `HYDROLOGY_FLAG_FLOODPLAIN_NEAR/FAR` + smooth
  `floodplain_strength`.

Implementation начинается с V3-1 (ocean-band mountain suppression) на ветке
`feature/hydrology_visual_v3`. Каждая итерация делается отдельным
implementation prompt + closure report. Финальный мердж в `main` —
атомарный, с обновлением 5 canonical docs.
