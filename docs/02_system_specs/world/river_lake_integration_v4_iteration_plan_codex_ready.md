---
title: River/Lake/Ocean Integration V4 - Iteration Plan
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: false
version: 0.6
last_updated: 2026-05-01
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - river_generation_v1.md
  - hydrology_visual_quality_v3_iteration_plan.md
  - mountain_generation.md
  - world_foundation_v1.md
  - world_runtime.md
  - terrain_hybrid_presentation.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
---

# River/Lake/Ocean Integration V4 — Iteration Plan

## Purpose

Этот документ фиксирует следующий шаг после Hydrology Visual Quality V3: не
"ещё раз переписать реки", а связать океан, реки, озёра, горы и превью в одну
авторитетную tile-level систему принятия решений.

Проблема на скриншотах выглядит не как один баг. Она выглядит как несколько
слоёв генерации и рендера, которые всё ещё спорят друг с другом:

- горы и вода принимают решение разными полями и разным разрешением;
- overview и 33x33 preview могут использовать не тот же приоритет слоёв, что
  runtime chunk packet;
- река в устье не модифицирует берег океана, а просто заканчивается линией;
- озёра всё ещё могут читаться как cell-based blob, а не basin contour;
- floodplain выводится как резкая зелёная зона, а не мягкий переход;
- river / lake / ocean presentation использует разные визуальные языки.

V4 не отменяет River Generation V1 и не удаляет V3. V4 ставит поверх них
строгую интеграционную цель: каждый water tile должен иметь единого владельца,
единый SDF/width смысл и одинаковую правду в overview, region preview и runtime.

## Non-goals

V4 не делает полноценную гидравлическую симуляцию, эрозию, погодное наполнение,
лодки, плавание, сезонный лёд или динамический global drought. Riverbed/water
separation остаётся как в V1: riverbed/lakebed/ocean floor — immutable base,
current water — overlay.

## External Design References

### Red Blob / Mapgen-style hydrology

Хороший practical generator обычно не рисует "синие линии" независимо от мира.
Он строит высоты/водоразделы, считает rainfall/flow accumulation и выводит
ширину из величины потока. Это главный принцип для V4: ширина реки не должна
быть только stream_order bucket + маленький radius_scale.

### RimWorld-style priority discipline

RimWorld не решает задачу Station Mirny один-в-один: локальная карта получает
river belt из world-tile river metadata, а не полный seamless hydrology network.
Но полезная идея у него сильная: локальный terrain decision имеет жёсткий
приоритет — ocean / river / beach / terrain — и river maker не выглядит как
независимый overlay поверх всего.

### Factorio-style water fallback

Factorio на Nauvis ближе к lakes/oceans generator, чем к river-network generator.
Если нужна временная playable версия без риска, `Lakes Only` может быть отдельным
preset/debug fallback. Но это не закрывает fantasy Station Mirny про вертикальные
реки, слияния, дельты и сухие русла.

## Current-Code Diagnosis

### RC-A — Overview water mode still lets mountain pixels win

`world_core.cpp::blend_overview_images(...)` сохраняет foundation mountain pixels
и не даёт hydrology overlay перекрыть их. Даже если canonical chunk output уже
подавляет mountain tiles внутри ocean/lake/river, overview может продолжать
показывать горы поверх воды.

**Fix direction:** water overview mode must use the same tile classifier / layer
winner as runtime. In water mode, hydrology pixels must be allowed to override
foundation mountain pixels for ocean/lake/river tiles. Debug mountain mode can
preserve mountains; gameplay water mode cannot.

### RC-B — No single authoritative tile classifier

Сейчас решение разнесено между mountain sampling, hydrology raster, lake/ocean
sampling, packet terrain assignment, overview blending and preview rendering.
Любое расхождение даёт "на карте вода, в регионе гора" или наоборот.

**Fix direction:** introduce one native `HydrologyTileClassifier` or equivalent
function and reuse it in:

- chunk packet rasterization;
- hydrology overview image;
- 33x33 region preview;
- debug overlays.

### RC-C — Mountain avoidance is still too coarse in parts of the pipeline

Hydrology graph may use `mountain_exclusion_mask` on hydrology-cell granularity,
while mountain wall/foot terrain is tile-level. This is enough to avoid some
massifs, but not enough to guarantee "river/lake never touches wall/foot and
bends smoothly around it".

**Fix direction:** build or query a tile-level mountain clearance distance field
for every water candidate. Rivers and lakes should use a cost field, not just a
binary hydrology-cell reject.

### RC-D — River mouths are not true coastline features

A delta/estuary cannot be only `edge.radius_scale` on the last line segment.
The coastline must react to the river mouth: local bay/estuary carving, shallow
shelf, distributary fan, and a smooth color/material merge into ocean.

**Fix direction:** river mouth modifies coast SDF and emits multiple
river-mouth distributary branches when eligible.

### RC-E — Width profile is not visually strong enough

Even with continuous distance fields, if the visible width is still bounded by
small stream-order buckets, a clamp, and a weak delta multiplier, rivers will
look like cut lines.

**Fix direction:** width must be a function of cumulative discharge and distance:
source taper, confluence widening, lowland widening, ford narrowing, terminal
estuary expansion.

### RC-F — Lakes must be basin SDF in every output path

If chunk output uses a better lake SDF but overview/region preview still uses
cell-level lake ids or old color decisions, screenshots will still show square
or disconnected lakes.

**Fix direction:** lake SDF / basin contour is required for overview and region
preview too. Any lake cell-center shortcut is debug-only.

### RC-G — Floodplain reads as a bug, not as terrain language

A hard green stripe makes the player ask "what is this green coming from the
river?" That means the terrain class may be technically correct but the
presentation is wrong.

**Fix direction:** keep `floodplain_strength`, but render it as subtle gradient
or vegetation/wetness overlay. Only strong values become the main terrain tile.

## Core Design Decision

Do not delete rivers as the main design direction.

Rivers should stay because they are central to the requested fantasy:
continuous vertical drainage, tributaries, confluences, drier/wetter riverbeds,
ford crossings, dельты, lakes with outlets, and mountain-guided navigation.

However, add a `Lakes Only` preset/debug mode as a safe fallback while V4 lands.
That mode should disable trunk/tributary river graph selection but keep ocean,
lakes, shore, lakebeds and water overlay. It is a fallback, not the canonical
Station Mirny water fantasy.

## Codex Implementation Contract

This document is implementation-ready only if Codex follows it as an iteration
plan, not as a single giant rewrite.

Binding rules for Codex:

- implement V4 incrementally in ordered slices, starting with V4-0 and V4-1;
- do not delete River Generation V1 or Hydrology Visual Quality V3;
- do not remove rivers from the default game;
- do not make `Lakes Only` the default preset;
- do not add GDScript hot-path hydrology loops;
- do not change save schema unless the PR also updates the relevant docs,
  settings resources and UI;
- any canonical terrain/water output change must be gated by a world-version
  boundary and must preserve a legacy path for existing saves;
- every PR must include deterministic tests or debug counters proving the
  acceptance criteria for the implemented slice.

Recommended Codex PR order:

1. **PR-1 / V4-0:** add debug overlays, mismatch counters and failure-seed tests.
2. **PR-2 / V4-1:** introduce the single native tile classifier and route chunk,
   overview and region preview through it.
3. **PR-3 / V4-2:** add tile-level mountain clearance and water/mountain
   invariant tests.
4. **PR-4 / V4-3 + V4-4:** improve river discharge width and integrate river
   mouths into coast SDF / delta fan logic.
5. **PR-5 / V4-5:** lake SDF continuity.
6. **PR-6 / V4-6:** unified presentation.
7. **PR-7 / V4-7 + V4-8:** presets, version bump, final docs, performance pass.

Codex must stop after each PR with a summary of touched files, tests run,
remaining risks and screenshots/debug images if available.

## Preset Semantics And How To Leave `Lakes Only`

`Lakes Only` is a worldgen preset, not a permanent product direction.

Preferred implementation: `Lakes Only` should be a UI/settings preset that maps
to existing `RiverGenSettings` values where possible. It should not be a hidden
persistent global toggle.

Default preset:

```text
Full Hydrology
  rivers.enabled = true
  target_trunk_count = default/auto
  density = default non-zero
  lake_chance = default
  meander_strength = default
  braid_chance = default
  shallow_crossing_frequency = default
  delta_scale = default
```

Temporary fallback preset:

```text
Lakes Only
  hydrology/ocean/lake generation stays enabled
  trunk/tributary river selection is disabled
  density = 0.0
  braid_chance = 0.0
  delta_scale = 0.0
  lake_chance = lakes-only fallback value
  target_trunk_count is ignored or left at default
```

Important: current River Generation V1 semantics define `target_trunk_count = 0`
as auto-scale, not as "no rivers". Therefore `Lakes Only` must **not** rely on
`target_trunk_count = 0` alone. Codex must either prove that `density = 0.0`
fully disables trunk/tributary selection while preserving lakes/ocean, or add an
explicit native branch such as `hydrology_mode = FULL | LAKES_ONLY` or
`river_network_enabled = false`.

Also, if the current implementation uses `rivers.enabled = false` to disable all
hydrology including lakes/ocean packet output, then `Lakes Only` must **not** use
`enabled = false`. If a new mode/field becomes persisted, Codex must update
save/UI/docs together.

How the player/developer leaves `Lakes Only`:

- for a **new world**, choose the `Full Hydrology` preset or restore the default
  river settings before generation;
- for an **already created save**, do not silently switch the same world from
  `Lakes Only` to river mode, because that changes canonical base terrain. The
  safe path is to create/regenerate a new world with `Full Hydrology`, unless a
  separate migration/regeneration tool is explicitly implemented;
- if the UI has individual sliders, changing any river slider away from a preset
  should mark the water preset as `Custom`, not keep showing `Lakes Only`.

## Authoritative Tile Decision Order

For V4 water-enabled worlds, every tile must be classified by one ordered
function. The order is:

1. **Ocean/coast SDF** — north ocean, organic coast, estuary/shelf. Ocean owns
   the tile and suppresses mountain rendering inside ocean water.
2. **Hard mountain wall/foot/no-go** — blocks lakes and rivers unless the tile
   was already classified as ocean by coast SDF.
3. **Lake basin SDF** — lakebed / lake water / lake shore, rejected if mountain
   clearance fails.
4. **River channel SDF** — riverbed / shallow / deep / bank, rejected or rerouted
   if mountain clearance fails.
5. **Floodplain gradient** — soft terrain/presentation gradient from
   floodplain strength.
6. **Base terrain** — plains, mountain foot/wall, other terrain.

This is not a visual-only order. It is the canonical terrain/water packet order.
Overview and region preview must read the same result.

## Iteration Plan

### Implementation status

- V4-0/V4-1 first PR scope: native `HydrologyTileClassifier` shared helper,
  V4 debug counters/overlays, chunk/preview layer-winner routing, composite
  overview water priority, V3 lake SDF overview parity, and deterministic
  classifier-agreement smoke test. Agreement counters compare hydrology
  layer-family winners while leaving subtype differences visible in debug
  colours/codes.
- This first PR is debug/refactor/presentation-only for canonical terrain:
  no new save fields, no packet arrays, no `WORLD_VERSION` bump, no `Lakes Only`
  default, and no GDScript hot-path hydrology loops.
- V4-2 follow-up scope: `WORLD_VERSION 31` gates canonical river/lake
  mountain-clearance output for new worlds. The implementation keeps clearance
  diagnostics RAM-only, adds no save fields or packet arrays, and preserves
  `world_version = 30` generated output for existing saves.
- V4-3 follow-up scope: `WORLD_VERSION 32` gates canonical river width/depth
  rasterization from native normalized cumulative discharge and refined-edge
  width profiles. The implementation keeps the normalized discharge and profile
  records RAM-only debug diagnostics, adds no save fields or packet arrays, and
  preserves `world_version = 31` generated output for existing saves.
- V4-4 follow-up scope: `WORLD_VERSION 33` gates coastline-integrated
  estuary/delta output. The implementation keeps estuary fan and coast SDF
  diagnostics RAM-only, adds no save fields or packet arrays, and preserves
  `world_version = 32` generated output for existing saves.
- V4-5 follow-up scope: `WORLD_VERSION 34` gates canonical lake basin
  continuity output. The implementation keeps outlet continuation, widened
  inlet/outlet shore, and mountain-clipped lake SDF diagnostics RAM-only, adds
  no save fields or packet arrays, and preserves `world_version = 33`
  generated output for existing saves.

### V4-0 — Debug invariants and reproducible failure seeds

**Goal:** stop guessing which layer lied.

**Native/dev changes:**

- add debug overlay modes: `layer_winner`, `mountain_clearance`, `water_sdf`,
  `river_width`, `river_discharge`, `lake_sdf`, `coast_sdf`;
- add deterministic seed list for the current screenshot failures;
- expose counts in hydrology debug snapshot:
  - mountain/water overlap tiles;
  - river tiles adjacent to wall/foot tiles;
  - lake tiles adjacent to wall/foot tiles;
  - river mouths without terminal widening;
  - rivers with cut endpoints;
  - overview/runtime classifier mismatch count.

**Acceptance:** one command/test can prove whether a screenshot bug is canonical
terrain, overview rendering, region preview rendering, or presentation color.

### V4-1 — One native tile classifier

**Goal:** make runtime, overview and preview tell the same truth.

**Native changes:**

- create `HydrologyTileClassifier` or equivalent native helper;
- move ocean/lake/river/mountain/floodplain winner logic into that helper;
- call it from chunk packet rasterization;
- call it from overview water image generation;
- call it from 33x33 region preview;
- delete or bypass overview logic that preserves foundation mountain pixels in
  gameplay water mode.

**Acceptance:** for sampled tiles, `overview_pixel_class == region_preview_class
== chunk_packet_class` for terrain/water category.

### V4-2 — Tile-level mountain clearance distance field

**Goal:** rivers and lakes never overlap or hug mountains.

**Native changes:**

- compute/query tile-level `mountain_clearance_distance_tiles` for wall and foot
  terrain;
- keep it RAM-only in hydrology snapshot or bounded macro cache;
- use it for lake candidate acceptance, lake SDF rasterization, river centerline
  refinement and river channel rasterization;
- turn hard blockers into high-cost detour fields before refined centerlines are
  emitted.

**Acceptance:** zero lake/river water tiles on wall/foot; zero wet tiles within
`mountain_clearance_tiles` unless explicitly allowed by debug override; rivers
bend around massifs with readable arcs.

### V4-3 — River discharge and continuous width profile

**Goal:** river width tells the story of flow.

**Native changes:**

- store normalized cumulative discharge per selected river segment/sample;
- derive width from discharge instead of mostly integer stream order;
- apply source taper over final upstream `5..10` tiles;
- apply confluence widening using upstream discharge sum;
- apply terminal estuary expansion over final `20..40` tiles;
- apply shallow ford narrowing as local width/depth modifier, not hard cuts;
- round/cap endpoints so branch ends fade instead of stopping flat.

**Acceptance:** sources taper smoothly, confluences visibly widen downstream,
river mouths are wider than upstream reaches, no branch looks saw-cut unless it
enters a lake/ocean/sink.

**Implementation note:** implemented for `world_version >= 32` in the native
hydrology prepass and chunk/overview rasterizers. The RAM-only diagnostics are
`river_discharge_normalized`, `refined_river_edge_width_profile`, and aggregate
profile counters for profiled edges, source taper, terminal expansion,
confluence widening, and shallow-ford narrowing. Branch endpoint visual caps
remain limited to the existing bank/fade behavior; richer endpoint shaping is
left to V4-4/V4-5 presentation work if screenshots still show cut ends.

### V4-4 — Estuary and delta as coastline-integrated features

**Goal:** river mouths become part of the ocean edge.

**Native changes:**

- river terminal modifies local coast SDF / shelf classification;
- eligible low-slope high-discharge terminals emit distributary fan branches;
- fan branch count is derived from `delta_scale` and discharge;
- all distributary tiles carry delta hydrology flags;
- ocean/river water colors/materials merge at mouth;
- no delta branch may cross mountain clearance field.

**Acceptance:** default `delta_scale = 1.0` produces a visible fan for major
rivers, terminal fan width is at least `3x` trunk width on qualifying mouths,
and the river never appears as a thin line pasted onto ocean.

**Implementation note:** implemented for `world_version >= 33` in the native
hydrology prepass, coast SDF samplers, overview rasterizer, and chunk packet
rasterizer. Fan branch count is derived from `delta_scale` plus normalized
discharge, distributary edges are marked as delta/braid-split hydrology, and
the local river-mouth influence adjusts the coast SDF/shelf classification.
RAM-only diagnostics are `estuary_delta_fan_terminal_count`,
`estuary_delta_fan_edge_count`, `estuary_discharge_fan_branch_count`,
`estuary_coast_sdf_modified_node_count`,
`estuary_mountain_blocked_branch_count`, and
`estuary_terminal_fan_width_ratio_max`.

### V4-5 — Lake basin SDF with inlet/outlet continuity

**Goal:** lakes look like filled basins, not rectangles.

**Native changes:**

- ensure lake shape uses basin contour SDF in every output path;
- reject or clip lake SDF by mountain clearance field;
- store outlet/spill point diagnostics;
- continue downstream river from spill outlet when possible;
- let rivers enter lakes with widened inlet shore, not a hard line stop.

**Acceptance:** lakes have non-rectangular silhouettes, no visible 16x16 cell
corners, no mountain overlap, and connected inlet/outlet behavior when graph
conditions allow it.

**Implementation note:** implemented for `world_version >= 34` in the native
`WorldHydrologyPrePass`, chunk packet rasterizer, and hydrology overview debug
classifier. It keeps lake SDF continuity, outlet continuation, widened
inlet/outlet shore, and mountain clipping diagnostics RAM-only; it does not add
packet arrays or save fields.

### V4-6 — Presentation unification

**Goal:** water reads as one world system.

**Presentation/native changes:**

- unify water palette between ocean, lake, river deep, river shallow and shelf;
- draw riverbed/bank as underlay/rim, not as dry brown center when active water
  exists;
- use SDF normals for shore/bank transition masks;
- render floodplain as strength gradient overlay, not a hard terrain stripe;
- keep debug colors separate from gameplay colors.

**Acceptance:** player can tell what is water, what is bank, what is dry bed,
what is floodplain, and what is ocean without reading debug mode labels.

**Implementation note:** implemented as a presentation-only slice with no
`WORLD_VERSION` bump. The shared native hydrology helper now exposes a gameplay
palette used by 33x33 preview patches and hydrology overview rendering, while
debug winner overlays keep their own palette. Runtime hydrology shape resources
for ocean floor, lakebed, riverbeds, and shore were aligned to the same palette.
No packet arrays, save fields, river deletion, or Lakes Only default were added.

### V4-7 — Settings, presets and safe fallback

**Goal:** make water tunable without breaking save boundaries.

**Changes:**

- keep existing settings where possible: `target_trunk_count`, `density`,
  `width_scale`, `lake_chance`, `meander_strength`, `braid_chance`,
  `shallow_crossing_frequency`, `mountain_clearance_tiles`, `delta_scale`,
  `north_drainage_bias`, `hydrology_cell_size_tiles`;
- add presets, not necessarily new save fields:
  - `Lakes Only`;
  - `Sparse Arctic Rivers`;
  - `Wet River Network`;
  - `Delta Heavy`;
- if new canonical fields are added, update `save_and_persistence.md`,
  `packet_schemas.md`, settings resources and UI together.

**Acceptance:** user can temporarily choose lakes-only worldgen, but default
preset keeps rivers enabled and improved.

**Implementation note:** implemented as existing-field presets on
`RiverGenSettings`, a localized Water Sector preset selector, and a native
`world_version >= 35` density-zero branch. No new save fields or packet arrays
were added. `Full Hydrology` remains the default; existing `world_version = 34`
saves keep the old density-zero river behavior, and non-`Lakes Only` hydrology
detail seeds stay pinned to the V4-5 shape boundary.

### V4-8 — Versioning, tests and performance closure

**Goal:** land the work safely.

**Required:**

- bump world version for each canonical output slice; current V4 boundaries are
  `WORLD_VERSION 31` for V4-2 mountain clearance and `WORLD_VERSION 32` for
  V4-3 discharge-based river width, and `WORLD_VERSION 33` for V4-4
  coastline-integrated estuary/delta output, and `WORLD_VERSION 34` for V4-5
  lake basin continuity output, `WORLD_VERSION 35` for V4-7
  preset-selected Lakes Only density-zero river-network suppression, and
  `WORLD_VERSION 36` for V4-8 dense braid-loop closure;
- no hidden GDScript fallback;
- all compute remains native worker/prepass/chunk packet work;
- no save schema changes unless V4-7 adds explicit settings;
- performance regression on large preset must stay inside accepted budget;
- existing V30 worlds load through legacy V30 path.

**Implementation note:** implemented for `world_version >= 36` as a native
closure boundary. V4-8 restores dense braid island loop acceptance after the
V1-R16 shape-quality guard, keeps legacy `world_version <= 35` output stable,
keeps overview/chunk/preview agreement counters native-side, and bounds refined
overview sampling through the native river spatial index. The accepted largest
preset debug prepass budget for the V4 stack is `3200 ms`; no save fields,
packet arrays, or GDScript hydrology raster loops were added.

## Acceptance Criteria

### Mountains and water

- [ ] zero mountain wall/foot tiles inside ocean/lake/river water in canonical
      packet output;
- [ ] zero gameplay-water overview pixels showing mountain over them;
- [ ] rivers/lakes keep configured clearance from wall/foot terrain;
- [ ] mountains may shape rivers, but never sit inside them.

### Rivers

- [ ] each major river has continuous path from source or upstream graph entry
      to lake/ocean terminal;
- [ ] sources taper smoothly instead of ending flat;
- [ ] confluences widen downstream over a smooth reach;
- [ ] lowland/flat reaches can be wider and shallower;
- [ ] shallow crossings are local depth/width events, not broken geometry;
- [ ] eligible mouths become estuary/delta coast features.

### Lakes

- [ ] no lake overlaps mountain wall/foot terrain;
- [ ] no lake shows 16x16 hydrology-cell rectangular corners in gameplay view;
- [ ] lake shore is generated from basin SDF / contour, not only cell adjacency;
- [ ] lake inlets/outlets connect to river graph when graph conditions allow it.

### Presentation

- [ ] river, lake and ocean colors/materials feel connected;
- [ ] floodplain reads as wet/vegetation transition, not a random green stripe;
- [ ] debug colors are never confused with gameplay water colors;
- [ ] overview, 33x33 preview and runtime chunk render agree on the same water
      shape.

### Determinism and performance

- [ ] same `(seed, world_version, settings)` always gives same output;
- [ ] no main-thread hydrology tile loops;
- [ ] no save data for RAM-only SDF/width fields;
- [ ] large preset hydrology remains within approved performance budget.

## Immediate Hotfixes Before Full V4

1. **Fix water overview priority.** In gameplay water mode, do not let
   foundation mountain mask skip hydrology overlay pixels. This is likely the
   fastest visible improvement for mountains appearing over water in the menu.

2. **Verify world version and V3 guard.** Ensure new worlds in the UI are really
   generated with `world_version >= WORLD_HYDROLOGY_VISUAL_V3_VERSION` and that
   settings packing enables `suppress_ocean_band_mountains` / hydrology V3 paths.

3. **Add a temporary `Lakes Only` preset.** This is not the final design, but it
   gives a playable fallback while river mouth, width and mountain-clearance work
   is fixed.

4. **Add mismatch debug overlay.** Any tile where overview/region/chunk disagree
   should render as a loud debug color in dev builds.

## Implementation Sketch

```cpp
enum class HydroTileWinner : uint8_t {
    Ground,
    MountainFoot,
    MountainWall,
    OceanDeep,
    OceanShelf,
    Shore,
    LakeDeep,
    LakeShallow,
    LakeShore,
    RiverDeep,
    RiverShallow,
    RiverBank,
    Floodplain
};

struct HydroTileDecision {
    HydroTileWinner winner;
    int32_t terrain_id;
    uint8_t water_class;
    int32_t hydrology_id;
    int32_t hydrology_flags;
    uint8_t floodplain_strength;
    uint8_t stream_order;
    float water_sdf;
    float mountain_clearance_tiles;
};

HydroTileDecision classify_hydro_tile(
    const Snapshot& hydro,
    const MountainFieldCache& mountains,
    int64_t world_x,
    int64_t world_y,
    const ClassifierSettings& settings
);
```

All overview/preview/runtime code paths should consume `HydroTileDecision` or a
thin packed equivalent. No separate layer-specific truth.
