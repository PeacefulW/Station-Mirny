---
title: Organic Hydrology Shape Quality V2 for GPT-5.5
doc_type: system_spec
status: proposed
owner: engineering+design
source_of_truth: false
version: 0.1
last_updated: 2026-04-29
related_docs:
  - river_generation_v1.md
  - world_runtime.md
  - world_foundation_v1.md
  - mountain_generation.md
  - terrain_hybrid_presentation.md
  - ../meta/packet_schemas.md
  - ../meta/system_api.md
  - ../meta/save_and_persistence.md
---

# Organic Hydrology Shape Quality V2 for GPT-5.5

## Purpose

This document defines the next quality pass for rivers, lakes, and ocean shapes.
It does not replace `river_generation_v1.md`. V1 remains the baseline contract
for deterministic hydrology, riverbeds, water overlays, chunk packet boundaries,
and native ownership. This V2 document focuses on mathematical shape quality:
water should look alive because its geometry follows coherent rules, not because
textures hide weak shapes.

The target is simple:

> Keep the existing hydrology graph as the skeleton, but turn the visible river,
> lake, and ocean geometry into coherent natural forms.

In plain design language: the current river should stop reading as a chain of
individually bent segments. It should read as one continuous flexible hose laid
through the terrain.

## Intended use with GPT-5.5

This spec is intentionally written for an agentic coding model that can inspect
the current codebase, reason across native C++ and GDScript boundaries, and make
implementation choices safely.

GPT-5.5 may choose the exact math primitive where this spec allows freedom:
Catmull-Rom, Hermite, Bezier, signed distance fields, contour tracing, or another
compact deterministic equivalent. The exact implementation is flexible. The
contracts are not.

Required behavior:

- preserve deterministic world generation;
- preserve current native-owned hydrology architecture;
- avoid GDScript tile loops for hydrology or water rasterization;
- keep runtime chunk packets compact;
- keep player-facing water geometry stable for the same seed/settings/version;
- fail loudly rather than silently falling back to weak script-side logic;
- add tests or smoke coverage for each landed quality phase.

Creative freedom is allowed only inside those boundaries.

## Current-code boundary

Current approved baseline already includes:

- `WorldHydrologyPrePass` in native code;
- hydrology snapshots with river paths, lake ids, ocean sink masks, flow, stream
  order, discharge, and mountain exclusion data;
- organic V1-R8 additions such as deterministic lake shoreline noise, per-edge
  river meander subdivision, per-edge width modulation, dельta output, and
  controlled split flags;
- new-game water preview sourced from native hydrology;
- chunk packet output for riverbed, lakebed, shore, floodplain, ocean floor, and
  default water class.

This V2 quality pass should extend that structure. It should not restart water
generation from scratch.

Likely files to inspect first:

- `gdextension/src/world_hydrology_prepass.cpp`
- `gdextension/src/world_hydrology_prepass.h`
- `gdextension/src/world_core.cpp`
- `core/systems/world/world_runtime_constants.gd`
- `scenes/ui/new_game_panel.gd`
- `tools/world_hydrology_overview_v1_r7_smoke_test.gd`
- `tools/world_composite_overview_smoke_test.gd`
- `docs/02_system_specs/world/river_generation_v1.md`

## Non-goals

This quality pass is not about textures, materials, shaders, animation, water
sound, boats, swimming, weather, full hydraulic erosion, or physically accurate
fluid simulation.

This quality pass is about geometry:

- how the river bends;
- how the river width changes;
- how tributaries merge;
- how branches leave and rejoin;
- how lakes occupy basins;
- how rivers enter lakes and ocean;
- how the ocean coast reads as land meeting water rather than a map border.

## Design principles

### 1. Hydrology graph first, shape second

The coarse hydrology graph remains the authority for connectivity, drainage,
stream order, lakes, and ocean terminal behavior. The visible shape is a refined
projection of that graph.

Do not create decorative rivers that ignore the graph.

### 2. One river is one body

A river path should be shaped as a continuous path, not as unrelated local
segments. Local randomness is allowed, but it must be filtered through direction
memory, slope, clearance, and downstream context.

### 3. The terrain should explain the shape

The player should be able to read the map and believe that:

- flat terrain allows wide meanders;
- mountains squeeze rivers into straighter channels;
- lowland water can split around islands;
- lakes sit in basins and spill through outlets;
- big river mouths modify the coastline.

### 4. Beauty is mathematical before it is visual

Textures can make water prettier, but they cannot fix bad geometry. The shape
itself must be coherent in debug overview mode.

### 5. Performance stays a first-class design goal

Do not chase beauty by turning chunk rasterization into an `all pixels x all
river edges` scan. Build vector features once, index them spatially, and sample
only nearby features during packet generation.

## Glossary

| Term | Meaning |
|---|---|
| Coarse hydrology graph | Current graph built from hydrology cells, flow direction, river paths, stream order, lake ids, and ocean sinks. |
| Centerline | Smooth world-space curve representing the middle of a river channel. |
| River sample | A point along the centerline with position, tangent, normal, width, depth profile, slope factor, curvature, stream order, and flags. |
| Direction memory | Rule that prevents the river from changing bend direction too quickly without terrain reason. |
| Curvature | How sharply the centerline bends at a sample. Used for width/depth asymmetry and meander quality. |
| Confluence | Zone where two or more upstream channels merge into one downstream channel. |
| Braid / island loop | A split where a branch leaves the main channel and rejoins downstream, forming readable land between branches. |
| Spill point | Lowest outlet point where a lake overflows and continues into a river. |
| Shelf | Ocean gradient from shore to shallow ocean to deep ocean. |

## Required V2 features

## 1. Whole-river centerline smoothing

### Problem

The current visible meander logic is too local: each graph edge can be bent on
its own. That produces better lines than a raw grid, but it can still read as a
chain of small independent bends instead of one smooth river.

### Contract

Before rasterization, convert each river path from coarse hydrology nodes into a
smooth world-space centerline.

Input:

- `river_segment_ranges`;
- `river_path_node_indices`;
- hydrology node centers;
- stream order / discharge;
- lake and ocean terminal context;
- mountain exclusion mask and clearance information.

Output:

- a native-only centerline representation for each river segment;
- sampled points with position, tangent, normal, cumulative distance, local
  width, local depth profile, stream order, and feature flags;
- a spatial index so chunks query only nearby centerline samples/segments.

### Implementation freedom

GPT-5.5 may use Catmull-Rom, Hermite, Bezier chains, or another deterministic
smoothing method.

The method must:

- unwrap cylindrical X consistently before smoothing;
- preserve graph connectivity at endpoints;
- avoid moving the river through mountain exclusion cells;
- reduce smoothing locally when clearance is too tight;
- keep lake/ocean/confluence endpoints stable enough that packet output remains
  connected.

### Acceptance

- River overview shows fewer hard corners and stair-step turns.
- Centerline is continuous across hydrology cell boundaries.
- Same seed/settings/version produce identical centerline samples.
- Smoothed centerlines never cross mountain wall/foot or clearance mask.
- Fallback to raw graph is allowed only locally and only for safety, not as a
  global shortcut.

## 2. Direction memory and bend inertia

### Problem

A river should not randomly decide to bend left, then immediately right, then
left again at every small segment. That creates a drunk broken line.

### Contract

Add a direction-memory layer to meander generation.

The river should remember its current bend tendency along cumulative path
length. Bend direction may change, but not too often and not without enough
space.

Rules:

- bend sign changes should be low-frequency;
- maximum turn angle between neighboring samples should be limited;
- sharp turns are allowed near obstacles, confluences, lake outlets, or ocean
  mouths, but should still be smoothed into readable geometry;
- meander offset should be a coherent function along the path, not an unrelated
  random value per graph edge.

### Implementation notes

Prefer a seeded low-frequency offset function along cumulative river distance:

```text
lateral_offset(distance) = signed_smooth_noise(distance / wavelength) * amplitude
```

Then filter it by:

- local slope;
- mountain clearance;
- channel width;
- proximity to confluence/lake/ocean control points.

### Acceptance

- Long rivers visibly have flowing S-curves instead of per-cell jitter.
- Adjacent bends usually continue the previous tendency before reversing.
- Debug curvature view does not show excessive alternating high-curvature spikes.

## 3. Slope-aware meanders

### Problem

Meander strength should not be a pure global setting. A flat lowland river and a
river squeezed between mountains should not behave the same.

### Contract

Compute a local `slope_factor` and use it to control meanders, width, branches,
and floodplain potential.

Expected behavior:

| Terrain situation | River behavior |
|---|---|
| Flat lowland | Wider, slower-feeling, stronger meanders, more floodplain, possible braids. |
| Mountain / narrow valley | Straighter, narrower, less lateral wandering, fewer branches. |
| Lake approach | Slower and wider, possible marshy fan. |
| Ocean approach | Wider mouth, delta or estuary depending on `delta_scale`. |

### Inputs

Use available data first:

- `hydro_elevation`;
- `filled_elevation`;
- flow direction;
- stream order/discharge;
- mountain exclusion distance or clearance proxy;
- floodplain potential.

### Suggested formula shape

The exact formula is implementation-owned, but should follow this shape:

```text
meander_amplitude = base_width
                  * meander_strength
                  * low_slope_factor
                  * clearance_factor
                  * valley_freedom_factor
```

Where:

- low slope increases meander amplitude;
- high slope reduces it;
- low clearance reduces it;
- wider downstream rivers can support larger meander wavelengths.

### Acceptance

- Lowlands are visibly more sinuous than steep/mountain areas.
- Rivers near mountains do not jitter against the mountain mask.
- Meander strength slider still matters, but terrain context modifies it.

## 4. Curvature-aware width and depth

### Problem

Current width variation can make rivers breathe, but the width/depth pattern
should be explained by the river bend.

### Contract

Width and depth must react to centerline curvature.

Expected behavior:

- outside of a bend tends to be deeper and slightly more eroded/wider;
- inside of a bend tends to have shallow water, shoal, or bank/point-bar feel;
- after confluence, downstream channel widens;
- before a split, the channel can widen before dividing;
- straight narrow high-slope channels should not randomly balloon.

### Implementation notes

Each centerline sample should know:

- local tangent;
- local normal;
- signed curvature;
- base width from stream order/discharge;
- local width multiplier;
- optional lateral depth-center offset toward the outside of the bend.

The rasterizer can then evaluate the signed distance to the centerline and use
curvature to decide whether a tile is deep bed, shallow bed, shore, bank, or
floodplain.

### Acceptance

- Deep channel tends to move toward the outside of bends.
- Inner bends more often produce shallow water/shore/floodplain.
- Width changes feel tied to channel shape, not random noise alone.
- Existing shallow/deep gameplay classes continue to work.

## 5. Y-shaped confluences

### Problem

If tributaries simply collide at one graph node, the result can look like a
technical T-junction or hard pixel merge.

### Contract

Detect confluences and turn each into a small merge zone.

A good confluence should:

- bring tributaries together gradually;
- align incoming tributary tangents toward the downstream river tangent;
- leave a readable land nose / pointed bank between channels where possible;
- widen the downstream channel after the merge;
- avoid impossible angles and abrupt width jumps.

### Implementation notes

A confluence zone may be defined by:

- confluence node;
- upstream centerline windows;
- downstream centerline window;
- merge length based on downstream width/stream order;
- blend handles or control points that form a Y shape.

### Acceptance

- Large confluences read as Y-shaped water geometry, not as line intersections.
- Downstream width/order is at least as strong as the largest upstream branch.
- No confluence produces a detached water blob or broken flow continuation.

## 6. Braids, splits, and island loops

### Problem

A split branch should not be a simple parallel duplicate of the main river. It
should create land that reads as an island or distributary feature.

### Contract

Replace purely decorative parallel split behavior with validated branch loops.

A braid/island loop is valid only when:

- slope is low enough;
- stream order/discharge is high enough;
- local channel is wide enough;
- mountain/lake/ocean constraints leave enough clearance;
- the branch rejoins downstream or exits into a valid lake/ocean/delta terminal;
- the island between branches has minimum readable size.

### Branch behavior

The branch should:

- leave the main river smoothly;
- separate enough to make land visible;
- curve around the island body;
- rejoin smoothly downstream;
- receive only part of the parent channel width/discharge;
- avoid forming orphan water slivers.

### Acceptance

- Every split branch has a valid rejoin or valid terminal.
- Islands have a minimum width and length in tiles.
- Braid output does not create thin one-tile nonsense unless explicitly allowed
  as shallow channels.
- Branches do not cross mountains or existing lake/ocean masks incorrectly.

## 7. Basin-contour lakes with spill outlets

### Problem

A lake made from coarse cells with noisy edges can still feel like a selected
mask rather than water filling a real basin.

### Contract

Natural lakes should be shaped from basin contours and spill elevation.

A lake should have:

- basin cells selected from hydrology depression / lowland context;
- water level derived from a spill point or terminal condition;
- an outlet/spill point when not terminal;
- shoreline traced as a contour around that water level;
- deterministic shoreline roughness that does not destroy the basin logic;
- lakebed terrain preserved under water.

### Lake types

Support at least the design space below, even if not all types land in the same
commit:

| Lake type | Shape behavior |
|---|---|
| Mountain lake | Long, narrow, squeezed between ridges, limited shoreline noise. |
| Lowland lake | Wider, softer, more marsh/floodplain around edges. |
| Chain lake | Several small basins connected by short river sections. |
| Oxbow lake | Crescent-shaped abandoned meander near a river. |

### River/lake connection

- Inflow rivers should enter the lake through a wider/softer mouth.
- Outflow should leave at the spill point, not a random shoreline tile.
- Large inflows may create a small delta/fan inside the lake.

### Acceptance

- Lake shorelines no longer read as coarse grid masks.
- Every non-terminal lake has a clear deterministic outlet.
- Inflow and outflow connections remain continuous in chunk packets and overview.
- Drying a lake leaves lakebed, not ordinary land.

## 8. Oxbow lakes / abandoned meanders

### Problem

The world can feel much more natural if some old river bends remain as crescent
lakes near the main channel.

### Contract

After centerline smoothing, high-curvature lowland meanders may occasionally
spawn oxbow candidates.

A valid oxbow:

- appears near a high-curvature meander;
- has a crescent or horseshoe outline;
- does not intersect the active main channel except optionally through a narrow
  wet/marsh connection;
- has enough distance from mountains and other water features;
- creates `TERRAIN_LAKEBED` or equivalent lakebed-compatible output;
- is deterministic and controlled by existing or new lake/braid probability
  settings.

### Acceptance

- Oxbows appear rarely enough to feel special.
- Oxbows are mostly in flat lowland/floodplain zones.
- They do not break active river connectivity.

## 9. Organic ocean coastline, estuaries, and shelf

### Problem

The ocean should not read as just a top map boundary with water. It should read
as a coastline.

### Contract

Replace straight-band ocean appearance with a coastline field.

The ocean system should provide:

- irregular but connected coastline;
- bays and capes;
- optional small islands if they meet minimum size and connectivity rules;
- river mouth widening;
- estuary or delta behavior controlled by `delta_scale` and stream order;
- shelf gradient from shore to shallow ocean to deep ocean.

### Shelf behavior

From land into ocean, output should be able to distinguish:

1. shore / beach / wet edge;
2. shallow ocean shelf;
3. deep ocean / impassable ocean.

This is still geometry/terrain classification, not texture work.

### Acceptance

- Ocean edge is not a straight line in overview.
- Large rivers visibly modify the coastline at their mouth.
- Shallow/deep ocean classes are spatially coherent.
- Ocean remains connected to the top boundary and does not create accidental
  inland seas unless intentionally generated as lakes.

## Performance architecture

### Required spatial index

V2 centerlines, confluence zones, braids, lake outlines, and coastline features
should be indexed in native code.

Chunk rasterization must query:

```text
features_near(chunk_rect_with_halo)
```

It must not scan every river/lake/ocean feature for every tile.

Acceptable index options:

- coarse grid bucket by hydrology cell;
- chunk-sized feature bins;
- packed vector of feature ids per coarse region;
- another deterministic bounded native structure.

### Sample spacing

Centerline sample spacing should be stable and bounded. Suggested rule:

```text
sample_spacing_tiles = clamp(base_width * 0.5, 2, hydrology_cell_size_tiles * 0.5)
```

Exact formula may differ, but must avoid both:

- too few samples causing angular rivers;
- too many samples causing memory/performance spikes.

### Memory rule

Do not save refined centerlines or per-tile hydrology arrays. Regenerate from
seed/settings/version. Keep refined structures RAM-only inside native hydrology
snapshot/cache.

### Hot path rule

Player movement and normal gameplay reads already materialized terrain/water
classes. It never computes hydrology, centerlines, slope, contours, or coastline.

## Debug and review tools

Add or extend debug/overview modes so shape quality can be judged without final
textures.

Useful debug layers:

- raw hydrology graph nodes;
- smoothed centerline samples;
- tangent/normal markers every N samples;
- curvature heatmap;
- slope factor heatmap;
- width/depth band overlay;
- confluence zones;
- braid/island validity overlay;
- lake basin + spill point overlay;
- ocean coastline SDF / shelf bands;
- mountain clearance violations.

A water shape pass is not reviewable if all we can see is the final texture-like
water color.

## Suggested implementation phases

### Phase A — Centerline substrate

Goal: create native refined centerline data from current river paths without
changing the whole water design.

Tasks:

- extract river path node centers;
- unwrap cylindrical X;
- build smooth centerline samples;
- preserve endpoint connectivity;
- build spatial index;
- add debug overview for raw path vs smoothed path;
- add determinism smoke test.

### Phase B — Direction memory + slope-aware meanders

Goal: make rivers read as continuous bodies with terrain-dependent sinuosity.

Tasks:

- compute local slope factor;
- compute clearance factor;
- replace per-edge random meander with distance-based coherent offset;
- reduce meander near mountains and steep sections;
- add curvature/slope debug overlays;
- add smoke test that lowland rivers are more sinuous than steep/mountain river
  sections on the same world preset.

### Phase C — Curvature-aware width/depth

Goal: make width and depth follow the bend shape.

Tasks:

- compute signed curvature for centerline samples;
- modify width/depth profile by curvature;
- shift deep channel toward outside bends;
- keep shallow/deep water classes stable;
- add overview/debug test for width continuity and no broken channels.

### Phase D — Y-shaped confluences

Goal: replace hard joins with merge zones.

Tasks:

- detect multi-upstream selected river nodes;
- create confluence zones with upstream/downstream windows;
- blend tributary centerlines into downstream tangent;
- widen downstream channel;
- add tests for continuity and no detached water blobs.

### Phase E — Braid island loops

Goal: make splits form readable islands.

Tasks:

- validate slope/discharge/clearance before split;
- generate branch centerline that leaves and rejoins;
- enforce island minimum size;
- distribute width/discharge across branches;
- add tests for valid rejoin/terminal and no orphan branches.

### Phase F — Basin-contour lakes and oxbows

Goal: make lakes feel like filled basins and add rare abandoned meanders.

Tasks:

- improve lake outline from basin/spill contour;
- expose/debug spill point;
- widen inflow/outflow transitions;
- optionally generate oxbow lakes from high-curvature lowland meanders;
- add tests for outlet continuity and shoreline non-rectangularity.

### Phase G — Organic coastline and shelf

Goal: make ocean read as coast, not just boundary.

Tasks:

- build coastline SDF;
- generate connected irregular coast;
- classify shore/shallow shelf/deep ocean;
- modify coast at large river mouths;
- add tests for ocean top-boundary connectivity and no accidental disconnected
  ocean pools.

## Acceptance criteria

General:

- [ ] Same seed/settings/world version produce identical output.
- [ ] No river/lake/ocean shape crosses mountain wall/foot or the clearance mask.
- [ ] No river terminates on ordinary land.
- [ ] Chunk packets and overview agree at feature-placement level.
- [ ] No GDScript hydrology/rasterization tile loops are introduced.
- [ ] Centerline and feature indexing keep chunk rasterization bounded.

Rivers:

- [ ] Long river centerlines are smooth across hydrology nodes.
- [ ] Adjacent bends show direction memory rather than rapid random alternation.
- [ ] Low-slope reaches are more sinuous than steep or mountain-constrained
      reaches.
- [ ] Width and depth vary coherently with stream order, slope, and curvature.
- [ ] Outside bends tend to have deeper channel output than inside bends.

Confluences:

- [ ] Major tributary joins read as Y-shaped merge zones.
- [ ] Downstream channel is wider/stronger than each individual upstream input.
- [ ] Merge zones do not produce detached blobs or broken water continuity.

Braids/islands:

- [ ] Every branch either rejoins or reaches valid lake/ocean/delta terminal.
- [ ] Island loops have minimum readable land size.
- [ ] Braid branches do not look like arbitrary parallel decorative strokes.

Lakes:

- [ ] Natural lakes read as basin-filled shapes, not coarse rectangular masks.
- [ ] Non-terminal lakes have deterministic spill outlets.
- [ ] Inflow/outflow transitions are smooth and visible.
- [ ] Rare oxbows, if enabled, appear near appropriate lowland meanders only.

Ocean:

- [ ] Coastline is irregular but connected to the top ocean boundary.
- [ ] River mouths modify coastline through estuary/delta widening.
- [ ] Shelf bands produce coherent shore -> shallow ocean -> deep ocean gradient.

Performance:

- [ ] Largest supported new-game preview does not hitch the main thread.
- [ ] Chunk rasterization uses spatially bounded feature queries.
- [ ] Runtime player movement never computes hydrology.
- [ ] Broad water changes remain overlay/diff work, not base hydrology rebuilds.

## Hard no list

Do not:

- rewrite river generation as decorative noise lines independent of hydrology;
- move hydrology computation into GDScript;
- store full refined per-tile hydrology in saves;
- allow split branches that do not rejoin or terminate validly;
- let smoothing push rivers into mountains;
- solve beauty by adding texture assumptions;
- create one giant all-features scan per chunk tile;
- break existing `river_generation_v1.md` packet/save/runtime contracts without
  updating the related meta docs and bumping world version where necessary.

## Final design target

The ideal result is a map where even in a flat debug overview the player can say:

- this river has a body and direction;
- this bend looks like water carved it;
- this tributary really flows into the main channel;
- this island exists because the river split and came back;
- this lake sits in a basin and spills out logically;
- this ocean is a coastline, not a ruler-straight border.

If the water geometry is beautiful in debug colors, textures can later make it
excellent. If the geometry is weak, textures will only hide the problem.
