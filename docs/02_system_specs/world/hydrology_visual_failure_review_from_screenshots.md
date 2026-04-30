---
title: Hydrology Visual Failure Review From Screenshots
doc_type: system_spec_addendum
status: draft
owner: engineering+design
source_of_truth: false
version: 1.0
last_updated: 2026-04-30
related_docs:
  - hydrology_visual_quality_v3_iteration_plan.md
  - river_generation_v1.md
  - organic_hydrology_shape_quality_v2_gpt55.md
  - mountain_generation.md
  - world_runtime.md
  - terrain_hybrid_presentation.md
  - ../meta/packet_schemas.md
---

# Hydrology Visual Failure Review From Screenshots

## Verdict

Реки не надо удалять из игры. Их надо перестать воспринимать как отдельную синюю
линию, которая потом как-нибудь ложится на карту. Текущая проблема — не в самой
идее рек, а в порядке принятия решений и в разных масштабах данных:

- горы считаются per-tile и могут победить воду;
- реки/озёра рождаются на coarse hydrology grid;
- океан, река, озеро, пойма и гора местами рендерятся как независимые слои;
- форма воды решается слишком поздно, на этапе растеризации, а не как единая
  гидрологическая система после гор.

Итог на скриншотах: океан, реки и озёра выглядят несвязанными сущностями.
Исправление — не снести всё, а ввести жёсткий V3 pipeline: сначала foundation и
mountains, затем hydrology graph с mountain clearance, затем per-tile raster SDF
для океана/озёр/рек, затем presentation.

## Screenshot Symptoms

### S1. Mountains over ocean / river

На overview видны горы в зоне воды. Это значит, что mountain terrain побеждает
hydrology при конфликте. Для игрока это выглядит как `горы нарисованы поверх рек`.

Correct result: ocean/river/lake tiles suppress mountain wall/foot only там, где
это реально вода. Прибрежные холмы могут существовать рядом, но не внутри ocean
sink / riverbed / lake basin.

### S2. Rivers enter ocean as thin unrelated lines

Река у устья не расширяется и не становится частью береговой зоны. Она выглядит
как тонкая cyan-линия, которая упёрлась в океан другого цвета.

Correct result: устье высокопорядковой реки должно иметь delta fan:
несколько distributary branches, расширенную shallow/deep zone, shore/bank band
и общий цветовой переход, чтобы река читалась как часть ocean system.

### S3. Green shape near river in 33x33 preview

Зелёное пятно/полоса рядом с рекой — это, скорее всего, floodplain. Сейчас оно
выглядит как отдельный биом, потому что threshold бинарный и coarse-cell форма
читается как ступени.

Correct result: floodplain должен быть strength-gradient overlay, а не жёсткая
зелёная плитка. Вблизи реки он сильнее, дальше растворяется в обычной земле.

### S4. Lakes intersect mountains

Озёра выбираются по hydrology cell, а mountains живут на tile level. Если coarse
cell разрешён под lake, но внутри этого cell есть mountain wall/foot тайлы, то на
скриншоте получается `озеро под горой` или `гора в озере`.

Correct result: natural lake basin selection and rasterization must reject
mountain wall/foot at tile level, not only hydrology-cell level.

### S5. River ends are cut off

Истоки и концы ответвлений выглядят отрубленными. Это признак того, что ширина
берётся из stream-order bucket and edge flags, но не из непрерывной функции по
расстоянию от истока до устья.

Correct result: river width = baseline discharge/order + smooth taper by
cumulative distance. Исток сужается плавно, confluence widens, устье grows into
fan.

### S6. Lakes are square

Озёра выглядят как 16x16 блоки, потому что lakebed пишется целиком для hydrology
cell. Noise на границе не спасает форму, если interior всё равно прямоугольный.

Correct result: lake shape must be rasterized from signed distance / basin
contour per tile. Coarse graph chooses the basin, but tile SDF draws it.

## Root Cause Map

| Symptom | Likely root cause | Correct fix |
|---|---|---|
| Mountains over water | Terrain decision order lets mountain block hydrology | V3 decision hierarchy: ocean/lake/river water masks suppress mountain only inside water footprint |
| Thin river mouth | Delta is radius_scale on one edge, not fan-out | Emit distributary fan edges near ocean terminal using existing `delta_scale` |
| Rivers look disconnected from ocean | Ocean, river and shore colors/classes are rendered independently | Shared shoreline/estuary classification and river-mouth influence on ocean shore |
| Green strip from river | Binary floodplain terrain from coarse potential | Smooth `floodplain_strength` packet + presentation gradient |
| Lake under mountain | Lake selection/rasterization uses hydrology cell granularity | Tile-level mountain conflict reject and lake SDF rasterization |
| Square lakes | `center_lake_id > 0` paints whole hydrology cell | Per-tile lake contour SDF with shallow rim and deep basin |
| Cut river sources / dead branches | Width is bucketed by stream order; no terminal/source taper | Continuous width profile by cumulative distance + source/terminal taper |

## External Reference Notes

### RimWorld pattern to borrow conceptually

RimWorld world rivers are not drawn as free random lines. The decompiled
`WorldGenStep_Rivers` builds river paths from coastal water tiles, uses elevation
change cost, accumulates rainfall flow, then creates/extends rivers based on
flow thresholds and branching rules.

The useful idea for Station Mirny: river identity should come from drainage,
flow and terrain cost, not from isolated visual strokes.

Do **not** copy RimWorld literally: it is planet-tile scale, not infinite 2D
chunk raster terrain. Borrow the concept: coast terminals + elevation cost +
flow accumulation + river definitions by flow.

### Factorio pattern to treat carefully

Factorio is a poor direct reference for realistic rivers. Its strength is
excellent procedural readability and preview UX, not hydrological river networks.
For Station Mirny, borrow the preview philosophy: deterministic settings,
immediate visual feedback, and generation that looks the same in preview and
runtime. Do not use Factorio as proof that disconnected lakes/noise-water are
enough for this game, because Station Mirny explicitly needs long north-draining
rivers, riverbeds, shallow/deep gameplay and mountain avoidance.

## Required V3 Pipeline

### Stage 1 — Foundation and mountains

Generate base height/foundation and mountain field first. Mountains are real
obstacles for rivers and lakes, but ocean band suppression must prevent mountain
terrain inside canonical ocean cells.

Output required by hydrology:

- elevation / lowland signal;
- mountain wall/foot mask;
- mountain clearance field;
- ocean band / ocean sink field;
- spawn safe area.

### Stage 2 — Hydrology graph

Build a coarse graph that knows:

- water must drain generally north into ocean;
- high mountain wall/foot and clearance are expensive/no-go;
- confluences increase discharge;
- optional branching can create islands;
- candidate basins can become lakes only if they pass mountain conflict checks.

### Stage 3 — Refined geometry

Convert the graph into refined geometry:

- Catmull/relaxed centerlines for rivers;
- cumulative distance and total river distance;
- discharge/order and confluence context;
- distributary fan at ocean mouth;
- optional braid loops that rejoin;
- lake basin contours and signed distance field.

### Stage 4 — Tile raster decision hierarchy

Per tile, resolve terrain in this strict order:

1. ocean / shore / shelf;
2. lakebed / lake shore;
3. mountain wall / mountain foot;
4. riverbed deep / riverbed shallow / bank;
5. floodplain gradient;
6. plain ground.

Important nuance: this does **not** mean rivers ignore mountains. Rivers already
avoid mountains in Stage 2. The hierarchy only prevents visual leftovers where a
water footprint was already accepted as canonical.

### Stage 5 — Presentation

Presentation consumes canonical packet fields. It must not invent hydrology in
GDScript. It can blend colors, draw foam/banks, and soften floodplain, but the
actual terrain/water decision stays native.

## Iteration Plan

### V3-1 — Ocean and mountain conflict fix

Goal: no mountain wall/foot in canonical ocean water.

Tasks:

- pass `ocean_band_tiles` and `suppress_ocean_band_mountains` into
  `mountain_field::Settings` for V3 worlds;
- fade mountain elevation to zero inside/near north ocean band;
- in chunk packet generation, if ocean mask says water, force mountain id/flags
  to zero for that tile;
- keep legacy world_version path unchanged.

Acceptance:

- overview shows no mountain pixels inside ocean sink;
- runtime chunk packets have `mountain_id = 0` on ocean tiles;
- near-coast land still can have mountains outside water footprint.

### V3-2 — Continuous river width

Goal: no cut-off skinny strokes; width grows along flow.

Tasks:

- store/propagate `total_distance`, `distance_at_source`, `distance_to_terminal`
  on refined river edges;
- compute width from smooth distance profile, not only stream_order;
- taper sources to 0.35-0.60 baseline;
- grow terminal reaches before ocean/lake/confluence;
- make confluence downstream reach wider than each incoming branch.

Acceptance:

- no visible width step between neighboring refined edges;
- source narrows gradually;
- downstream river is visibly wider after confluence.

### V3-3 — Real river-mouth delta fan

Goal: river becomes part of ocean at mouth.

Tasks:

- for ocean-terminal rivers with enough discharge/order, emit 2-6 distributary
  edges based on existing `delta_scale`;
- spread fan laterally inside shore/ocean transition;
- mark all fan tiles with `HYDROLOGY_FLAG_DELTA`;
- blend river shallow/deep into ocean shelf class;
- reject fan branches that collide with mountain exclusion.

Acceptance:

- mouth fan width is at least 3x trunk width for default delta scale;
- mouth no longer looks like a single line touching a blue rectangle;
- delta branches remain deterministic for same seed/settings.

### V3-4 — Lake basin mountain reject and organic lake SDF

Goal: no square lakes, no lake/mountain overlap.

Tasks:

- during lake candidate selection, scan candidate basin cells at tile or sampled
  sub-tile granularity for mountain wall/foot conflicts;
- reject or carve around mountain conflicts;
- build per-lake contour field from depth ratio and basin shape;
- rasterize lake via SDF, not `center_lake_id => whole cell`;
- classify shallow rim and deep center separately.

Acceptance:

- lakebed never overlaps mountain wall/foot;
- lake bounding box is not mostly full rectangle;
- shoreline has no visible 16-tile grid corners.

### V3-5 — Floodplain as gradient, not terrain blob

Goal: the green area reads as lowland/floodplain, not a broken biome.

Tasks:

- compute bilinear per-tile floodplain strength from hydrology cells;
- write `floodplain_strength` smoothly;
- only write `TERRAIN_FLOODPLAIN` at strong threshold;
- use packet flags for near/far floodplain;
- let presentation blend grass/soil tint using strength.

Acceptance:

- no hard green staircase in 33x33 preview;
- floodplain smoothly follows river and lowlands;
- ordinary ground remains readable.

### V3-6 — Preview/runtime parity and tuning pass

Goal: preview and actual runtime agree.

Tasks:

- use the same native hydrology snapshot for overview, 33x33 preview and chunk
  packet generation;
- add debug modes for mountain exclusion, flow accumulation, river order,
  lake id, floodplain strength;
- test seeds with mountains near coast, river confluence, river split/rejoin,
  lake near mountain, delta into ocean;
- tune colors so shallow/deep river, lake and ocean are visually related but not
  identical.

Acceptance:

- what player sees in overview matches local region preview and runtime tiles;
- every known screenshot defect has a debug layer showing why it happened;
- no GDScript hydrology loops are introduced.

## Do Not Do

- Do not replace rivers with random blue strokes.
- Do not let mountains and hydrology race for the same tile without hierarchy.
- Do not paint whole 16x16 lake cells as water.
- Do not fix delta only by multiplying river width on the last edge.
- Do not add new river settings until `delta_scale`, `width_scale`,
  `meander_strength`, `braid_chance`, `lake_chance` are exhausted.
- Do not add GDScript fallback rasterization for water.
- Do not merge partial V3 output into main without a world version boundary.

## Recommendation

Keep rivers. Remove or disable only the current broken presentation while V3 is
implemented behind `world_version >= 30`.

If a playable build is needed before V3 is done, temporarily expose a setting:

```text
Water Mode:
- Off
- Lakes Only
- Rivers Debug
- Rivers Full V3
```

Default for stable builds can be `Lakes Only` until V3 passes screenshots. But
the long-term game fantasy needs rivers, riverbeds, drying, shallow/deep water
and mountain navigation. That system is worth saving.
