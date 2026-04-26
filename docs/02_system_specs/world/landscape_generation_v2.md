---
title: Landscape Generation V2 - Unified Mountain + River + Lake System
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: false
version: 0.11
last_updated: 2026-04-26
deletes_on_approval:
  - river_generation.md (V1.0)
  - river_generation_r1b_fix.md
replaces_on_approval:
  - mountain_generation.md (mountain field generation only; reveal/cavity sections move into a separate slimmed-down spec)
target_world_version: 16
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - world_foundation_v1.md
  - world_runtime.md
  - world_grid_rebuild_foundation.md
  - mountain_generation.md
  - terrain_hybrid_presentation.md
  - WORLD_GENERATION_PREVIEW_ARCHITECTURE.md
---

# Landscape Generation V2 - Unified Mountain + River + Lake System

## Status

This spec is `draft`. It is the spec-first design for the rebuild of mountain
and river generation as a single coupled landscape system. No code lands
until the spec is approved by the maintainer.

### Greenfield rule

The project is pre-alpha. There are no shipped saves to protect, no live
players, no public worlds to reproduce, and no compatibility commitments.
V2 is built on a clean slate.

Concrete consequences:

- **No backward compatibility.** V2 deletes the old generation paths, not
  versions them. There is no pre-V16 legacy branch in V2 code. Any code
  path whose only purpose is "keep loading the old world" is removed in
  the same task that lands V2.
- **No save migration.** Old saves are not upgraded; they are
  unsupported. The save loader for `world_version != 16` raises a fatal
  `save format obsolete; start a new world` error. Existing chunk diff
  files for old worlds are dead data.
- **No fallback to old defaults.** `worldgen_settings.landscape` missing
  on load is a fatal error, not a "load defaults" trigger. The only
  place defaults are read is "create a brand new world", and even there
  defaults are constants in the loader, not silent compatibility shims.
- **No hidden fallback path** of any kind. LAW 9 is binding. Native
  required, no GDScript replacement, no "demote range to a single-ridge
  fallback" recovery, no "if `mountain_region` empty, use threshold
  noise as backup". Failures are asserts and fatal errors, not soft
  recoveries.
- **Old specs are removed**, not amended around. `river_generation.md`
  V1.0 and `river_generation_r1b_fix.md` are deleted on V2 land.
  `mountain_generation.md` is reduced to its reveal / cavity / cover
  half, which becomes a smaller spec named `mountain_interior.md`; its
  field-derivation, mountain identity derivation, and silhouette
  packet-shape sections are deleted because they are fully replaced by
  V2.
- **V2 restates surviving rules directly.** Historical V1 / R1B
  river documents may explain why a rule exists, but after V2
  approval they are not normative and V2 does not depend on deleted
  river specs for authority.

### Hard boundaries V2 still respects

V2 is allowed to rewrite anything inside the project, except for the
governing layer that defines the project itself:

- the four governing docs (`AGENTS.md`, `WORKFLOW.md`,
  `ENGINEERING_STANDARDS.md`, `PROJECT_GLOSSARY.md`);
- ADR-0001, ADR-0002, ADR-0003, ADR-0007;
- `world_grid_rebuild_foundation.md` (`32 px` tile, `32 x 32` chunk);
- `world_runtime.md` chunk publish boundary;
- the existing `WorldPrePass` LAW 12 exception in
  `world_foundation_v1.md`.

Inside those boundaries V2 may rewrite anything else.

### What V2 explicitly does not redesign

V2 redesigns the silhouette layer of the world: ridges, valleys, river
corridors, lake basins, deltas, and how chunks paint terrain from that
geometry.

V2 does **not** redesign mountain interior gameplay: excavation,
cavity / opening cache, cover visibility, the reveal lifecycle, or
`mountain_flags` bit semantics that the player-facing mountain interior
relies on. Those rules survive V2 unchanged because they are gameplay
contracts, not silhouette contracts. They will live in the slimmed-down
`mountain_interior.md` after V2 lands.

The only preserved mountain contracts are the gameplay-facing mountain
interior contracts:

- excavation;
- cavity / opening cache;
- cover visibility;
- reveal lifecycle;
- `mountain_flags` bit semantics required by those systems.

V2 owns `mountain_id` derivation for `world_version == 16`. It must
provide stable deterministic `mountain_id` values, but the rule for
deriving them is defined here, not inherited from deleted
`mountain_generation.md` sections.

If V2 implementation finds those gameplay contracts blocking, it stops
and writes a separate amendment, not a quiet workaround.

### Approval effect

On approval:

- this document becomes `source_of_truth: true`;
- it **deletes** `river_generation.md` V1.0 and
  `river_generation_r1b_fix.md` from the docs tree;
- it **replaces** the field-derivation half of `mountain_generation.md`;
  the surviving reveal/cavity half is moved into a new
  `mountain_interior.md` in the same task;
- `WORLD_VERSION` is set to `16` for the new generation. Older numbers
  are dead.
- V2 supports exactly `world_version == 16`. Future `world_version >
  16` requires a new spec amendment.

This spec is `not` a content spec for biomes, climate, weather, water
overlay, drought, fauna, or progression.

## Purpose

Define a single coupled landscape pipeline that produces:

- mountain ranges that read as elongated **massifs and ridges with valleys
  between them**, not as raw noise threshold blobs with chopped edges;
- rivers that read as **continuous ribbon corridors** with variable width,
  proper banks, shallow / deep zones, junctions, and deltas, draining into
  the top-Y ocean band, narrow in the headwaters and wider near the coast;
- lakes that read as **irregular basins integrated into the river network**,
  with at least one inflow river and an outflow river when the basin is not
  terminal;
- a landscape where **mountains shape rivers and rivers carve valleys
  through the mountain foot**, instead of two independent noise layers
  competing over each tile.

Reference target: an overhead view where rivers braid out of southern
mountain ranges, twist between massifs, widen as they approach the
northern ocean, and pool into lakes carved into the relief - the kind of
silhouette you would draw on a fantasy map or expect from a healthy
hydraulic GIS visualization.

## Why this exists (gap analysis)

The historical V1 river generation produced architecturally correct dry
beds, but the visual output still fails the shape acceptance:

1. Rivers render as **roughly straight bands** between coarse downstream
   nodes. Adding inline "centerline jitter" inside a single coarse cell
   does not produce real meanders, because the routing graph itself is
   D8-straight.
2. River ribbons are **fixed-radius capsule paths** stamped per segment.
   Width does not interpolate smoothly along the trunk and does not
   respond to local valley constriction.
3. Banks are **single-tile shallow shoulders** around a thin deep channel.
   They do not feel like continuous riverbanks; they feel like outlines
   around capsules.
4. **Lakes are circular polygons** vertex-modulated to look slightly
   irregular. They are not built from a depression filled by drainage,
   they do not show outflow rivers, they pop where the trunk happens to
   end, and they do not contain islands.
5. **Mountains are threshold noise**. The silhouette is rounded blobs with
   chopped edges at the noise threshold; there is no skeleton, no ridge
   spine, no valley gap, no foothill structure that rivers can read.
6. **Rivers are not aware of mountains** beyond rejecting wall tiles.
   They cannot route through a valley between two ranges. They cannot
   carve a canyon through a foot band. When a river has to cross a foot
   zone, the bed simply ends or jumps.
7. **Mountains are not aware of rivers**. There are no enforced valley
   gaps for river passage. A wall blob can land on top of a routed
   downstream chain and the rasterizer either erases the river under
   mountain priority or leaves a thin line that visually disappears.
8. **Settings are isolated**. `mountain_density` only changes how much
   mountain area exists. `river_amount` only changes trunk visibility
   threshold. There is no coupling: cranking mountains up does not make
   rivers more sinuous, and cranking rivers up does not change mountain
   silhouettes around active drainages.
9. **Per-segment rasterization** stamps a circle at every tile sample of
   every segment. Each stamped circle is independent; sub-tile coherence
   is fragile, banks bead along chunk seams, and small-radius headwater
   trunks turn into dotted strokes.

V2 is the rebuild that makes mountain and river generation a single
deterministic landscape solve over a shared skeleton, so all of the gaps
above close together.

## Reference target (binding intent)

This list is **intent**, not a numeric specification. Acceptance numbers
are formalised later in this document.

A correct V2 world, viewed from the overview, must show:

1. Top-Y ocean band, fed by river mouths, with an irregular playable
   coastline instead of a straight horizontal strip.
2. Rivers visibly enter the ocean as **wide, sometimes braided mouths,
   estuaries, or small deltas**, not as narrow cracks ending at a ruler-
   straight coast.
3. Trunk rivers form **continuous ribbons** spanning many coarse cells,
   with smooth turns, no per-segment beading, no abrupt width steps.
4. Trunks **fork into tributaries** as you move upstream, not the other
   way around. Tributary count is visible in the network.
5. Rivers **bend around mountain massifs** instead of cutting through
   them. Where they do cut, the cut is a **canyon / pass** signature
   (narrowed shallow, deeper deep, foot eaten away on both sides) and
   not a flat channel through wall.
6. Mountains read as **elongated ranges with skeleton and foothills**,
   not as round blobs. Ridges are oriented coherently (not random per
   tile).
7. The space **between two ranges** is a continuous valley corridor
   that rivers prefer.
8. Lakes are **irregular**, possibly with islands, sit in **depressions**
   bounded by relief, have a **clearly visible inflow** and (when not
   terminal) a **clearly visible outflow**, and never appear as round
   stamps disconnected from the network.
9. Increasing `mountain_density` makes the map **more mountainous AND
   more sinuous** at the same time: rivers tighten, fork more, gain
   canyons, and gain inline lakes. Decreasing it leaves wide rivers
   meandering across plains.

If the resulting overview does not look like that, the implementation
has not satisfied this spec.

## Design Principles

### P1. The world has one landscape pipeline, not two

The pipeline is:

```
seed + bounds + settings
   |
   v
[macro relief]   -> macro_height, mountain_pressure
   |
   v
[ridge skeleton] -> mountain ridges as oriented poly-lines
   |
   v
[mountain field] -> wall / foot / slope / scree distance fields
   |
   v
[hydro height]   -> macro_height + ridge_height + low-freq noise
   |
   v
[depression fill + flow]
                 -> downstream graph, flow accumulation, basins
   |
   v
[trunk + tributary selection]
                 -> ocean-directed trunk graph with split / rejoin
   |
   v
[river corridor] -> centerline spline, width curve, banks
   |
   v
[lake basins]   -> irregular polygons, inflow / outflow links, islands
   |
   v
[ocean shoreline]
                 -> hard ocean band + irregular shallow coast +
                    river-mouth estuaries
   |
   v
[landscape candidate index]
                 -> coarse spatial candidate buckets + cached corridor /
                    polygon geometry on snapshot
   |
   v
[chunk rasterization with spatial-index context]
                 -> per-tile terrain id + walkability + atlas
                 -> rivers carve valleys in foot inside corridor
                 -> mountains keep priority outside corridor
```

Both mountains and rivers are outputs of the same solve, so they cannot
contradict each other.

### P2. The mountain silhouette is a skeleton plus distance fields, not a noise threshold

Mountains are generated from:

1. a **macro mountain region mask** (low-frequency, biased by latitude)
   that says where ranges can exist;
2. a **ridge skeleton** inside that mask: a deterministic set of
   oriented poly-lines that play the role of the mountain spine;
3. a **distance field** from the skeleton that produces, in order
   from the skeleton outward: `core`, `wall`, `foot`, `slope`, `scree`,
   and `valley_gap`;
4. a **detail noise overlay** that perturbs the silhouette but cannot
   create or destroy a range on its own.

A tile is a wall not because `noise > T`, but because its distance to
the nearest ridge skeleton is below a wall radius derived from per-range
parameters.

### P3. The river is a corridor, not a chain of stamped circles

A river is:

```
graph -> centerline -> spline -> width curve -> signed-distance bank classification
       -> shallow / deep zones -> mouth / delta widening
```

A trunk is generated as one continuous geometric object covering the
full ocean-directed downstream chain, and only then sliced into
per-chunk tile contributions during chunk rasterization.

Per-segment "draw a circle for each segment, then somehow blend"
stamping is forbidden as the only path. Width is interpolated along
arc length, not stamped.

### P4. Lakes are part of the river system

A lake is:

- the surface of a **filled depression** detected during priority-flood
  routing;
- bounded by an **irregular polygon** derived from the basin shape and
  hydro_height isoline at the spill elevation, deformed by deterministic
  noise, possibly containing one or more **islands**;
- always **connected** to the river graph: at least one inflow trunk
  ends at the lake interior, and a non-terminal lake emits an outflow
  trunk from a chosen spill cell;
- visible as a **shallow rim + deep basin**, the same way rivers carry
  shallow / deep classes.

Lakes that are not connected to any river chain do not exist as
gameplay-facing lakes in V2.

### P5. River cost knows mountains; mountain valleys know rivers

Routing cost per coarse cell:

```
cost(cell) =
    cost_base
  + cost_wall   * inside_wall_weight
  + cost_foot   * inside_foot_weight
  + cost_slope  * slope_weight
  - cost_valley * valley_weight
  - cost_river  * established_river_weight     (later passes)
```

Where `inside_wall_weight = +infinity` (effectively non-routing).
Foot is not freely routable. A corridor may interact with foot only in
three modes:

1. run along the foot edge without carve;
2. cross foot through a `pass_anchor` with carve;
3. reject illegal dense-foot crossing.

Only at canonically marked passes / canyons may the solver lower
`inside_foot_weight` to a finite high cost so a river can carve a foot
canyon if there is no cheaper path. Outside those marked passes, the
centerline may run beside foot but must not cross dense foot; wall is
forbidden.

After routing, a `valley_carve_request` is emitted only for pass /
canyon arc-length ranges, not for every trunk cell. The chunk
rasterizer translates those requests into local `foot -> ground`
rewrites near the corridor, producing the **carved valley** look around
real passes.

### P6. Settings are coupled

```
mountain_density:
    + mountain_pressure
    + ridge_density
    + average_range_length
    + routing_cost (foot/wall fractions)
    + valley_constriction (sinuosity along trunks)
    + lake_in_basin_probability
    - river_visible_threshold (because more valleys collect more flow)

mountain_scale:
    + average_range_length
    + valley_corridor_width
    - junction_density (longer ranges = fewer junctions per area)

mountain_continuity:
    + ridge_chaining (more elongated, less blob-like)
    + valley_corridor_continuity

mountain_ruggedness:
    + ridge_count_per_range
    + canyon_probability
    + scree_band_width

river_amount:
    + visible_trunks
    + tributary_density
    + average_trunk_width
    + delta_count
    + lake_in_basin_probability

river_meander:
    + per-trunk sinuosity multiplier
    + meander wavelength on plains
    + canyon zigzag tightness in mountains
```

There is **one** set of slider entries; cranking any one of them must
visibly change the silhouette in a way consistent with the table.

### P7. The substrate is global; the rasterization is per chunk with a spatial index, not a brute halo

Trunk graphs, ridge skeletons, lake basins, and corridor geometry are
solved once per world load, in `WorldPrePass`, in native code. They are
RAM-only and seed-derived (LAW 12 exception, same as current
`WorldPrePass`).

Chunk rasterization is local. For each requested chunk:

1. Native code queries a **spatial index** over snapshot geometry
   (ridges, trunk corridor splines, lake polygons, basin polygons) by
   the chunk's tile-space AABB, padded only by a small `autotile margin`
   (`autotile_margin_tiles`, default `4`). The index returns the small
   set of geometry items that intersect the chunk.
2. For each output tile inside the chunk's `32 x 32` window, native code
   classifies the tile by signed-distance / point-in-polygon tests
   against that small set, plus per-tile detail noise.
3. The chunk packet is filled from those per-tile classifications.

There is **no full iteration over a large `chunk + halo` window**.
"Halo" in V2 means only:

- the autotile margin needed to resolve `47`-case neighbour tiles at
  the chunk boundary;
- the spatial-index AABB padding needed to catch geometry whose centre
  is outside the chunk but whose footprint reaches inside (a lake
  polygon, a wide trunk, a foot fade).

The acceptance gate is timing, not halo radius. Chunk rasterization
must classify only `32 x 32` final tiles per chunk regardless of how
large lakes, ranges, or corridors are elsewhere on the map.

### P8. The base is immutable, the diff is per tile, the overlay is runtime

ADR-0003 holds. River corridor geometry, lake polygons, ridge skeletons,
and chunk rasterization output are **base data**. They are not saved
per tile. They are regenerated from `seed + world_version + bounds +
settings`.

Player mining / construction goes through `WorldDiffStore` exactly as
today. There is no "carved a tunnel through the river" special case in
V2; the chunk read is `base + diff`, identical to V1.

Water presence remains future scope; V2 ships **dry beds and dry
lakes**. V2 restates the dry-first rule here directly: generated river,
lake, delta, and ocean footprints are terrain scars first, and runtime
water is a later overlay that must not rewrite immutable base terrain.

### P9. Preview reads only the substrate

The new-game overview canvas reads the snapshot and renders one image,
exactly like today. Adding ridges, valleys, river corridors, lake
polygons, and deltas to the overview is a snapshot pass over geometry,
not a chunk batch.

In-game gameplay world ships **dry beds only** for V2-R1: rivers, lakes,
deltas, and ocean band remain dry-bed terrain until a future water
overlay lands. V2 does not depend on deleted river specs for this
authority; the dry-first rule is binding because it is restated here.

The overview preview is **allowed and encouraged** to render river,
lake, and ocean footprints with temporary blue presentation colours so
the player and the developer can read corridor shape, lake outline, and
delta widening without hand-decoding dry terrain. The blue overview
colour is `presentation only`: it is a hint about future water, not a
runtime water overlay, and it must not affect chunk packets, walkability,
or save state.

### P10. Failure is explicit, not silent

If routing produces a cycle, an unreachable trunk, a lake without
inflow, a corridor crossing a wall, or an unaccountable per-tile
contradiction, V2 must assert in debug builds and fail loudly in
release builds with a clear actionable error. Visible-but-wrong worlds
are not acceptable.

During new-world creation, invalid landscape candidates are rejected
before the world is created. If the user pressed `Random`, the generator
may retry with a new random seed up to
`LANDSCAPE_RANDOM_SEED_RETRY_LIMIT` times. If the user entered an
explicit seed, failure is shown as a clear validation error with the
debug reason. This is not a fallback path: no invalid snapshot is
silently repaired, downgraded, or loaded with different rules.

### P11. Quality outranks historical continuity on the V2 boundary

Inside the `world_version == 16` boundary, the only constraints V2 must
respect are the governing layer listed in `## Status`. Historical V1 /
R1B river documents may explain why a rule exists, but they are not
normative after V2 approval. Any surviving mountain-interior rule from
`mountain_generation.md` applies only where this spec explicitly
preserves it.

V2 has exactly one supported generation path: `world_version == 16`.
Any save with `world_version != 16` is rejected as obsolete. No attempt
is made to preserve seed-by-seed visual continuity across the V15 ->
V16 boundary.

## Scope

V2-R1 (this spec, on approval) covers:

- new substrate fields on `WorldPrePassSnapshot` for ridge skeleton,
  mountain region mask, distance fields, routing cost, basin polygons,
  trunk corridor geometry, and lake polygons;
- new native landscape solve replacing both threshold mountain field
  generation and per-segment river capsule rasterization;
- `mountain_id` derivation for V16, defined by this spec and based on
  the new ridge skeleton (stable, deterministic, never mutated by
  diff);
- new chunk rasterization: per-tile terrain id, walkable, atlas,
  packet bits derived from snapshot geometry plus spatial-index
  candidate context and autotile neighbour margin;
- river corridor pass / canyon carve modifier for original `foot`
  tiles inside `pass_anchor` windows (the "river carves valley" rule);
- lake basin polygons with islands and inflow/outflow links;
- coupled settings, with the table in P6 enforced by acceptance;
- updated `worldgen_settings.landscape` block, replacing
  `worldgen_settings.rivers` and merging into mountain settings where
  natural;
- `WORLD_VERSION` bump from `15` to `16`;
- updated overview palette to render new substrate channels (ridges,
  valleys, corridors, lakes);
- exactly one supported generation path: `world_version == 16`; any
  save with `world_version != 16` is rejected as obsolete.

## Out of Scope

V2-R1 does not include:

- water overlay - dry beds only;
- player canal / dam / pump tools;
- biome content (ocean biome, latitude belts, tundra, jungle, etc.);
- environment runtime (weather, season, wind, temperature);
- subsurface / Z-level connectors;
- new building / power / combat systems;
- migration of obsolete saves into V2 generation;
- multiplayer replication of the new substrate beyond what is already
  pure-function deterministic;
- riverbank flora / decor placements (those go into a future flora spec
  consuming V2 corridor metadata);
- erosion simulation after world load;
- mountain interior cavity changes (preserved gameplay contract, moved
  to `mountain_interior.md` after V2 approval);
- save chunk diff shape;
- arbitrary legacy runtime file cleanup unrelated to V2;
- Z-level mountain identity propagation (ADR-0006 stays as-is).

In scope: deleting old generation branches / files that exist only to
support pre-V16 generation.

## Dependencies

- ADR-0001 for runtime work classes and dirty-update limits.
- ADR-0002 for cylindrical X wrap and bounded Y.
- ADR-0003 for immutable base + runtime diff.
- ADR-0007 for worldgen / environment-runtime separation.
- `world_grid_rebuild_foundation.md` for `32 px` tile and `32 x 32`
  chunk geometry.
- `world_runtime.md` for chunk packet boundary, streaming discipline,
  and `WorldStreamer` role.
- `world_foundation_v1.md` for finite cylindrical bounds, the existing
  `WorldPrePass` substrate, and the LAW 12 exception that V2 inherits
  unchanged.
- `mountain_generation.md` only as temporary home for gameplay-facing
  mountain interior contracts until `mountain_interior.md` exists:
  excavation, cavity / opening cache, cover lifecycle, reveal lifecycle,
  and `mountain_flags` bit semantics required by those systems. V2 owns
  `mountain_id` derivation and silhouette packet-shape semantics for
  `world_version == 16`.
- V2 itself is the authority for the dry-first principle, the ground
  `47`-tile bank rule, and the V16 terrain id assignments. Deleted
  river specs are historical context only and are not dependencies.
- `terrain_hybrid_presentation.md` for terrain shape / material profile
  rules.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical, runtime overlay, or visual only? | Canonical base. Ridge skeleton, river corridors, lake polygons, foot/wall fields, and chunk-level terrain ids are deterministic base data. Future water is overlay. Player mining is diff. Overview pixels and dry-bed art are presentation. |
| Save / load required? | Yes, for `worldgen_settings.landscape` in `world.json`. The substrate snapshot itself is RAM-only, never persisted. Per-tile landscape output is regenerated from `(seed, world_version, bounds, settings_packed)` on demand, exactly like V1. |
| Deterministic? | Yes. All landscape outputs are pure functions of `(seed, world_version, bounds, settings_packed, snapshot_signature)`. |
| Must work on unloaded chunks? | Yes. Any chunk regenerates its tile output independently from the cached snapshot. |
| C++ compute or main-thread apply? | All compute (skeleton solve, distance fields, routing, corridor geometry, lake polygon, rasterization) is native worker. Main thread only applies prepared packet arrays through the existing sliced chunk publish path. |
| Dirty unit | Whole-world snapshot at world load (boot/load class). `32 x 32` output chunk for tile rasterization (background class). Context read: spatial-index candidate geometry plus `AUTOTILE_MARGIN_TILES` neighbour margin. The rasterizer never classifies a full `chunk + halo` tile rectangle. One tile for player mutation (interactive). |
| Single owner | `WorldCore` (native) for substrate solve and chunk rasterization. `WorldDiffStore` for player mutations. `ChunkView` for presentation only. `world.json` for the settings copy. No new autoload is introduced. |
| 10x / 100x scale path | Substrate stays sub-linear in world area at `coarse cell = 32 tiles` (binding for V2). Trunk graph node count grows like the substrate grid. Corridor geometry is bounded by `O(visible trunks * average trunk length)` polylines, not per-tile. Chunk reads go through a spatial index, not full halo iteration. No new whole-world tile pass during gameplay. |
| Main-thread blocking? | Forbidden during gameplay. Substrate solve runs at world load behind the loading screen or new-game preview debounce, identical to V1 substrate. |
| Hidden GDScript fallback? | Forbidden. Native `WorldCore` is required; absence asserts and fails loudly. |
| Could it become heavy later? | Yes. Therefore ridge skeleton solve, distance field, routing, corridor smoothing, lake polygon, and tile rasterization belong in native code from V2 day one. |
| Whole-world prepass? | Yes, under the existing LAW 12 exception inherited from `world_foundation_v1.md`. No new whole-world prepass is added; the existing one grows. |

## Core Vocabulary

### Mountain region mask

Low-frequency boolean field saying where mountain ranges may exist. It is
biased by latitude so larger / denser ranges concentrate on the bottom-Y
side (away from the top-Y ocean), with a smooth gradient across the
middle band.

### Ridge skeleton

A deterministic set of oriented poly-lines living inside the mountain
region mask. Each ridge has a `range_id`, a list of vertices in
tile-space (X-wrap-safe), an orientation, a width profile, and metadata
(strength, age, junctions).

The ridge skeleton plays the role that "high-density noise contour"
plays today. It is the spine of every mountain.

### Range / massif

The connected set of ridges sharing a `range_id`. A range is the unit a
designer thinks about when they say "there is a mountain over there".

### Pass / canyon

A coarse-cell-marked location where a ridge segment is allowed to be
crossed by a river corridor. Marked deterministically from skeleton
geometry: a pass is a place where two ridges almost meet, a saddle in
the relief, or a deliberate gap in a long ridge.

### Mountain distance field

For every tile inside or near a range, the distance (in tiles) to the
nearest ridge skeleton segment. Drives the wall / foot / slope / scree
classification.

| Distance | Class |
|---|---|
| `0..wall_radius` | core / wall |
| `wall_radius..foot_radius` | foot |
| `foot_radius..slope_radius` | slope |
| `slope_radius..scree_radius` | scree |
| `> scree_radius` | not part of mountain |

Numeric radii are functions of range strength and the active settings.

### Hydro height

`hydro_height = macro_relief + ridge_contribution + low_freq_noise +
slope_bias_term`. Inputs:

- `macro_relief`: the same low-frequency relief used by `mountain region
  mask`, smoothed;
- `ridge_contribution`: a falloff function of the mountain distance
  field that adds elevation along skeletons;
- `low_freq_noise`: a wide-wavelength domain-warped noise so plains are
  not perfectly flat;
- `slope_bias_term`: a Y-axis tilt that biases drainage toward the
  ocean band.

### Routing cost field

Per-coarse-cell cost used by river routing. See P5.

### Trunk

A continuous river polyline whose downstream tip enters the ocean band
(or a non-terminal lake whose outflow itself reaches the ocean band).
Trunks own width curves, side channels, and lake junctions.

### Corridor

The 2D footprint of a trunk: shallow zone, deep zone, banks, plus any
side-channel branches that fork off and rejoin the same trunk. The
corridor is the geometric object that finally rasterizes into per-tile
terrain.

### Tributary

A trunk whose downstream tip is **not** the ocean but another trunk.
Tributaries are first-class trunks of lower Strahler order.

### Side channel / split-rejoin

A secondary polyline forking off a trunk and reconnecting downstream
along the same trunk, enclosing a land island.

### Delta / mouth widening

The corridor section where a trunk enters the ocean band. Width grows,
the deep zone fans out, and bank shoulders broaden into shoreline. May
optionally split into braids inside the band.

### Ocean shoreline / estuary

The playable coast below the hard top-Y ocean band. It is generated
from a shoreline field, not from a straight `y < ocean_band_tiles`
comparison. Estuaries are river-mouth cuts where a trunk widens the
shoreline into a bay-like inlet before reaching deep ocean.

### Lake basin

A filled depression detected in the priority-flood pass. Has a basin
polygon, an inflow trunk count, and (when not terminal) an outflow
trunk anchor.

### Lake polygon

The polygon describing the lakebed footprint. Generated from the basin
shape and the spill-elevation isoline of the filled depression, then
deformed by deterministic noise. May contain one or more islands.

### Carved valley

Not a competing terrain owner. `carved_valley_flag` is emitted when
`RIVER_CORRIDOR` or `RIVER_BANK` overlaps original `MOUNTAIN_FOOT`
inside a `pass_anchor` window. The final terrain owner remains the
riverbed / river bank / surrounding ground selected by tile-level
resolution; the flag records that a mountain foot was eaten by river
passage.

### Snapshot signature

A `uint64` hash of `(seed, world_version, bounds, settings_packed)`
identifying the substrate snapshot. Bumping any input changes the
signature; chunks regenerate against the new signature.

## Architecture Overview

### Layered model (no priority shortcut)

The current generator's "if mountain wall then write wall else if river
then write river" priority is replaced by a **layered commit**:

```
1. mountain region mask           (regional)
2. ridge skeleton                 (regional)
3. mountain distance field        (per coarse cell aggregate)
4. routing cost field             (per coarse cell)
5. depression fill + flow accum   (substrate-wide)
6. trunk / tributary selection    (substrate-wide)
7. corridor + bank geometry       (per trunk, vector)
8. lake polygon + islands         (per basin, vector)
8b. ocean shoreline field         (hard band + shallow coast +
                                   mouth estuary, vector / coarse)
9a. coarse candidate index        (per coarse bucket: geometry refs
                                   and possible owner kinds only)
9b/10. tile-level resolve         (per output tile, reading
                                   stage 9a candidates and stage 1..8
                                   geometry plus autotile margin)
```

Stage 9a builds a coarse spatial candidate index only. Stage 9b / 10
resolves the authoritative owner per output tile by running the actual
geometry tests against those candidates. No coarse cell owner may
directly decide `terrain_id`, `walkable_flags`, or river / mountain
packet bits.

After stage 10 every output tile knows whether it is `mountain_wall`,
`mountain_foot`, `valley_floor`, `river_corridor`, `river_bank`,
`lake_rim`, `lake_basin`, `delta`, `deep_ocean`, `shallow_coast`,
`mouth_estuary`, `burning`, or `plains`.
Multiple candidate kinds are allowed only in well-defined combinations;
the tile-level resolver decides the final owner and any modifier flags.

### Single landscape pipeline (data flow)

```
WorldPrePass solve (boot/load):

  inputs:  seed, world_version, world_bounds, settings_packed
  outputs: WorldPrePassSnapshot {
              ... existing V1 fields ...
              mountain_region_mask     [coarse]
              ridge_skeleton           [vector list]
              ridge_strength           [coarse]
              mountain_distance        [coarse]
              wall_density             [coarse]   (rebuilt from skeleton)
              foot_density             [coarse]   (rebuilt from skeleton)
              valley_score             [coarse]   (rebuilt from skeleton)
              hydro_height             [coarse]
              routing_cost             [coarse]
              downstream_index         [coarse]
              flow_accumulation        [coarse]
              basin_polygons           [vector list]
              trunk_corridors          [vector list]
              lake_polygons            [vector list]
              shoreline_offset         [coarse]
              ocean_zone_mask          [coarse buckets]
              coarse_owner_index       [coarse buckets]
              snapshot_signature       u64
           }
```

```
chunk batch (background):

  inputs:  chunk_coord, snapshot_ref
  outputs: ChunkPacketV2 {
              ... existing packet fields ...
              terrain_ids              [1024]
              terrain_atlas_indices    [1024]
              walkable_flags           [1024]
              mountain_id_per_tile     [1024]
              mountain_flags           [1024]
              mountain_atlas_indices   [1024]
              mountain_presentation_band [1024]
              ridge_orientation_bucket [1024]
              riverbed_flags           [1024]
              riverbed_depth           [1024]
              river_flow_q8            [1024]
              ... new V2 fields below ...
              landscape_kind           [1024]   (debug)
              corridor_distance_q8     [1024]   (optional)
              carved_valley_flag_byte  [1024]   (bit 0 only)
           }
```

`mountain_id_per_tile` is derived by V2 from skeleton-stable inputs.
`mountain_flags` and `mountain_atlas_indices` preserve only the
gameplay-facing semantics required by excavation, reveal, cover, and
cavity / opening systems. They are not inherited as silhouette
authority from deleted `mountain_generation.md` sections.
`mountain_presentation_band` and `ridge_orientation_bucket` are V2
presentation metadata emitted by the landscape rasterizer; they do not
become gameplay authority.

### Wrap-safety

Every solve step is wrap-safe on X. Skeleton vertices that cross the
seam are duplicated with `+/- world_width_tiles` X offset for
neighbour queries; lake polygons crossing the seam are emitted as two
sub-polygons clipped at the seam. The per-tile reader always
canonicalises X before any geometry test.

Y is bounded; ridge skeletons, trunk corridors, and lake polygons are
all clipped at `[0, height_tiles - 1]`.

## Substrate Extensions

### V2 binding constants

These constants are not tunable. They are part of the canonical V2
contract and changing any of them is a `WORLD_VERSION` bump.

| Constant | Value | Purpose |
|---|---|---|
| `LANDSCAPE_COARSE_CELL_TILES` | `32` | Substrate grid resolution. |
| `LANDSCAPE_MAX_RIDGES_LARGE` | `512` | Hard cap for `Ridge` records on the largest preset. Smaller presets scale by area. |
| `AUTOTILE_MARGIN_TILES` | `4` | Spatial-index padding for chunk classification. |
| `RIDGE_VERTEX_COUNT_HINT` | `64` | Average vertex budget per ridge polyline. |
| `SPLINE_GEOMETRY_SAMPLE_STEP_TILES` | `0.5` | Fine geometry sample step for spline spatial indexing. |
| `WIDTH_BANK_SAMPLE_STEP_TILES` | `4` | Coarser arc-length sample step for width and bank-noise profiles. |
| `BANK_NOISE_WAVELENGTH_TILES` | `8 / 24 / 64` | Coherent 1D bank-noise wavelength bands. |
| `BANK_NOISE_MAX_DELTA_PER_TILE` | `0.25` | Maximum adjacent bank-offset delta per 1 tile sample outside explicit rocky / canyon tags. |
| `MOUNTAIN_ORIENTATION_BUCKET_COUNT` | `16` | Ridge tangent orientation buckets used by mountain atlas/material selection. |
| `LANDSCAPE_SNAPSHOT_MEMORY_BUDGET_MB` | `256` | Maximum `WorldPrePassSnapshot` memory on the large preset at default settings. |
| `LANDSCAPE_MAX_SPLINE_SAMPLES_LARGE` | `1000000` | Maximum total geometry spline samples on the large preset at default settings. |
| `COASTLINE_MIN_Y_VARIATION_TILES` | `24` | Minimum accepted y-offset variation for the playable coastline on reference seeds. |
| `COASTLINE_MAX_STRAIGHT_SEGMENT_TILES` | `96` | Maximum accepted straight coastline run outside debug-flat-coast mode. |
| `LANDSCAPE_RANDOM_SEED_RETRY_LIMIT` | `16` | Maximum rejected-candidate retries after the user presses `Random`. |
| `LANDSCAPE_QUANTIZATION` | see "Quantization Table" below | Fixed-point scales for determinism. |

### Quantization Table (Q7 binding)

Topology-bearing values are stored at the indicated fixed-point scale.
Floats are allowed only for local interpolation that does not feed back
into topology, sorting, hashing, or packet output.

| Field | Storage | Notes |
|---|---|---|
| Coarse cell coordinates | `int32` | Integer cell indices. |
| Tile coordinates | `int32` | Integer tile indices. |
| `hydro_height` | `q16` | 16-bit fixed-point over `[-1, +1]` after normalisation. |
| `flow_accumulation` | `q16` | 16-bit fixed-point over `[0, 1]`. |
| `wall_density`, `foot_density`, `valley_score`, `mountain_region` | `q8` | 8-bit fixed-point over `[0, 1]`. |
| `shoreline_offset` | `q8 signed` | Coastline y-offset below the hard ocean band. |
| `ocean_zone_mask` | `u8 enum` | `none`, `deep_ocean`, `shallow_coast`, `mouth_estuary`. |
| `routing_cost` | `q16` | 16-bit fixed-point; saturates on wall blocker. |
| `mountain_strength` | `q8` | 8-bit fixed-point over `[0, 1]`. |
| `mountain_distance` | `q8` (capped to `255` tiles) | Beyond cap = "no mountain". |
| `bank_noise_left_q8(s)` | `q8 signed` (-128..+127) | Coherent 1D noise pre-sampled at `WIDTH_BANK_SAMPLE_STEP_TILES` for the left bank and smoothed before quantization. |
| `bank_noise_right_q8(s)` | `q8 signed` (-128..+127) | Coherent 1D noise pre-sampled at `WIDTH_BANK_SAMPLE_STEP_TILES` for the right bank and smoothed before quantization. |
| `mountain_presentation_band` | `u8 enum` | `none`, `crest_high_ridge`, `wall_mass`, `slope`, `foot`, `scree`, `external_edge`. |
| `ridge_orientation_bucket` | `u8` | Local ridge tangent bucket in `[0, MOUNTAIN_ORIENTATION_BUCKET_COUNT)`. |
| Ridge vertices | `int32` tile coords | After deterministic jitter. |
| Trunk corridor anchors | `int32` cell coords | Output of corridor solver. |
| Trunk spline samples | `int32` quantised tile coords | Pre-sampled at `SPLINE_GEOMETRY_SAMPLE_STEP_TILES`, snapped to `q1` (half-tile resolution). |
| Width / bank profile samples | `q8/q16 arrays` | Stored more coarsely than geometry samples; rasterizer interpolates locally. |
| Lake polygon vertices | `int32` quantised tile coords | Snapped to `q1` (half-tile). |
| Snapshot signature | `uint64` | Hash over all of the above. |

### V2 terrain id constants

The following dry-bed terrain ids are required V2 constants, not
ad-hoc rasterizer literals:

| Terrain id | Meaning |
|---|---|
| `TERRAIN_RIVERBED_SHALLOW` | Dry shallow riverbed / side-channel bed. |
| `TERRAIN_RIVERBED_DEEP` | Dry deep riverbed. |
| `TERRAIN_LAKEBED_SHALLOW` | Dry lake rim / shallow lakebed. |
| `TERRAIN_LAKEBED_DEEP` | Dry lake basin. |
| `TERRAIN_OCEAN_BED_SHALLOW` | Dry shallow ocean-band bed near coast / mouth. |
| `TERRAIN_OCEAN_BED_DEEP` | Dry deep ocean-band bed. |

`TERRAIN_OCEAN_BED_SHALLOW` and `TERRAIN_OCEAN_BED_DEEP` must be
documented alongside river and lake terrain ids in the packet schema
and presentation follow-ups. The ocean band may not remain an
undocumented special case.

### Substrate field set

Stage 1..9a add the following new fields to the snapshot. Field names
are illustrative; final native names live in code.

### 1. Mountain region mask

Per coarse cell, a float in `[0, 1]`:

```
mountain_region(cell) =
    smoothstep(threshold,
               threshold + edge,
               low_freq_noise(cell, seed) +
               latitude_bias(cell.y, settings))
```

Inputs:

- `low_freq_noise`: domain-warped FBM at wavelength
  `mountain_region_wavelength_tiles` (default 1024). Wraps on X,
  clamps on Y.
- `latitude_bias`: smooth function biased toward bottom-Y. Default
  `lerp(-0.20, +0.30, latitude_t)`. Strength scaled by
  `mountain_latitude_influence`.
- `threshold`, `edge`: derived from `mountain_density`. Higher density
  lowers the threshold and shrinks the edge band.

A cell with `mountain_region(cell) > 0` is eligible to host ridges; a
cell with `mountain_region(cell) <= 0` cannot host ridges.

### 2. Ridge skeleton

A deterministic list of `Ridge` records. Each ridge has:

| Field | Type | Notes |
|---|---|---|
| `range_id` | u32 | Stable per range. Hashed from seed + range origin. |
| `vertices` | `PackedVector2Array` | In tile-space, X-wrap-safe. |
| `orientation_rad` | float | Average tangent angle. |
| `length_tiles` | float | Total polyline length. |
| `strength` | float | `[0, 1]`. Drives wall radius and ridge height. |
| `parent_range_id` | u32 or 0 | Set when the ridge branches off another ridge inside the same range. |
| `pass_anchors` | `PackedInt32Array` | Indices on `vertices` marked as canonical passes. |

Generation rule (deterministic):

1. Sample candidate range origins on a Poisson disc inside cells with
   `mountain_region > 0`. Spacing scales with `mountain_scale`.
2. For each origin, grow a primary spine by integrating a domain-warped
   tangent field (low frequency noise). Length scales with
   `mountain_scale * mountain_continuity`.
3. Optionally branch sub-spines off the primary spine when
   `mountain_ruggedness` is high. Each branch shares the parent's
   `range_id` but receives its own `parent_range_id`.
4. Mark `pass_anchors` at vertex indices where ridge curvature, ridge
   thinning, or proximity to another ridge from the same range crosses
   a deterministic threshold. Frequency scales with `mountain_density`
   (more density -> more passes, otherwise routing dies).
5. Ridges do **not** hard-terminate at the `mountain_region_mask`
   boundary. As a ridge approaches the mask edge, its `strength` and
   `wall_radius` taper to zero over a configurable transition distance
   (`ridge_taper_tiles`, default scaled by `mountain_scale`). The
   ridge ends only after taper reaches zero. Hard clipping is allowed
   only at world Y bounds, not at noise-mask boundaries. This avoids
   the "chopped edge" artefact where a range visibly ends along a
   constant-noise contour.

Two ridges sharing a `range_id` form one massif. Multiple massifs with
distinct `range_id` values may sit close to each other; rivers may
route between them in the gap.

The ridge skeleton replaces threshold noise as the source of mountain
shape. Detail noise (P2 step 4) is allowed only as a perturbation of
the distance field, not as a generator of new ridges.

### 3. Mountain distance field

Per coarse cell:

```
mountain_distance(cell) = min over all ridges:
    distance_tiles(cell.center, ridge_polyline)
mountain_strength(cell) = max over all ridges:
    ridge.strength * falloff(distance_tiles, ridge)
```

Used by:

- `wall_density(cell)`: 1.0 inside `wall_radius(cell)`, 0.0 outside.
  At chunk rasterization time, refined to per-tile distance using the
  ridge geometry plus a per-tile detail noise.
- `foot_density(cell)`: 1.0 inside `foot_radius`, decaying to 0.0 at
  `slope_radius`.
- `valley_score(cell)`: `1 - clamp(wall + 0.5 * foot, 0, 1)`. High in
  passes and gaps, low inside ranges.

The distance-field query must use a spatial acceleration structure over
ridge segment AABBs. A full scan over every ridge segment for every
coarse cell is forbidden on the large preset
(`LANDSCAPE_MAX_RIDGES_LARGE * RIDGE_VERTEX_COUNT_HINT` segments across
the full coarse grid).

### 4. Hydro height

Per coarse cell, a float:

```
hydro_height(cell) =
      macro_relief(cell)
    + ridge_height_contribution(cell)
    + low_freq_noise(cell)
    + slope_bias_term(cell.y)
```

`slope_bias_term` is monotone on Y, sign and magnitude controlled by
`landscape_slope_bias` (existing `foundation.slope_bias`, reinterpreted
for V2). Default biases drainage toward the top-Y ocean band.

Existing `WorldPrePass` `hydro_height` is replaced by this formulation
for `world_version == 16`.

### 4b. Ocean shoreline field

Top-Y ocean is guaranteed beyond `ocean_band_tiles`, but the playable
coastline is not a straight horizontal line.

V2 generates a shoreline mask below the hard ocean band using:

- low-frequency coast noise, X-wrap safe and quantized before it reaches
  the snapshot;
- bay carving from broad negative shoreline-offset pockets;
- river-mouth erosion from accepted mouth-class trunks after corridor
  geometry exists.

Ocean owner has three zones:

1. `DEEP_OCEAN`: always ocean inside the hard top band.
2. `SHALLOW_COAST`: irregular coastline / bays below the hard band.
3. `MOUTH_ESTUARY`: river-driven widening where trunks enter the ocean.

`MOUTH_ESTUARY` is generated from trunk mouth geometry, not from a
generic coast-noise pocket. It may overlap delta / braid geometry, but
it remains ocean terrain; the river / delta flags describe the drainage
context.

Debug-flat-coast mode is allowed only as a dev visualization switch. It
must not be the default V16 generation path and must not satisfy
coastline acceptance.

### 5. Routing cost field

Per coarse cell:

```
cost(cell) =
    cost_base
  + cost_wall_term     (effectively + INF if wall_density >= wall_block)
  + cost_foot_term     (linear in foot_density)
  + cost_slope_term    (from local |grad(hydro_height)|)
  - cost_valley_term   (from valley_score)
  - cost_pass_term     (from passes anchored to skeleton)
```

`cost_pass_term` is non-zero only where a pass anchor is within one
coarse cell of `cell`. Passes are the only legal way for routing to
traverse a foot zone.

### 6. Depression fill and flow accumulation

The substrate uses an `effective_drainage` quantity, not raw
`hydro_height`, to decide downstream flow. Routing cost is part of
the choice, not a tie-break. Walls are non-routing. Dense foot outside
a pass is not a legal crossing; foot-edge proximity remains expensive,
and passes are cheap relative to surrounding foot.

For each cell `c` and each neighbour `n` (D8, X-wrap canonical):

```
effective_drainage(c -> n) =
      filled_hydro_height(n)
    + routing_cost(n) * routing_cost_to_height_scale
    + turn_penalty(c, n)
    + wall_blocker(n)         // +infinity if wall_density(n) >= wall_block
    + foot_crossing_blocker(c, n)
```

Pipeline:

1. Apply **priority-flood depression filling** to `hydro_height` so
   the field is non-decreasing along any descending path. Closed
   basins are detected and tagged with `basin_id`. The spill cell is
   the neighbour through which the basin overflows at the spill
   elevation.
2. After filling, recompute `effective_drainage` per neighbour pair
   using the filled height plus the routing-cost / turn-penalty /
   wall-blocker / foot-crossing-blocker terms above.
2a. Neighbour eligibility rejects dense-foot crossing outside pass
   windows. A D8 edge `c -> n` is illegal when:
   - `n` is dense `MOUNTAIN_FOOT`;
   - the edge is not inside or adjacent to a `pass_anchor` window;
   - the step is not classified as a soft foot edge.
   Illegal foot edges receive `+infinity` through
   `foot_crossing_blocker(c, n)` before downstream selection.
3. Each cell selects its downstream neighbour as the minimum
   `effective_drainage` candidate that preserves monotone descent
   after the fill. Ties resolve by deterministic neighbour order with
   X-wrap canonical alignment.
4. Cycle detection: after this pass no cycles may remain. Assert in
   debug builds. If a cycle is found, break at the edge with the
   highest canonical wrapped coordinate pair.
5. Topologically sort by descending filled height; accumulate flow.
6. Normalise flow against the theoretical maximum.

`routing_cost_to_height_scale` is a versioned constant chosen so that
a single foot cell is more expensive than detouring up to
`max_detour_cells` valley cells, but cheaper than a wall. The default
is calibrated during L2 review.

Closed basins where every spill candidate has `wall_blocker = +inf` or
`foot_crossing_blocker = +inf` become **terminal basins** and are
eligible for terminal lakes. Closed basins with a finite spill remain
**non-terminal** and emit an outflow trunk from the spill cell.

### 7. Trunk and tributary selection (D8 is hydrology base, not final geometry)

The D8 downstream graph from stage 6 is the **hydrology base**. It
defines who flows into whom and where lakes form. It is **not** the
final river geometry. Spline smoothing on a D8 chain only hides the
grid; it does not remove it.

Final trunk geometry is produced by a **least-cost corridor solve** on
the coarse cost field, run independently per accepted hydrology chain.

A hydrology chain is selected as a trunk when:

- `flow_accumulation >= flow_visible_threshold(river_amount)`;
- the downstream chain reaches the top-Y ocean band, possibly via a
  non-terminal lake basin whose spill cell continues toward the ocean;
- the total chain length exceeds `min_trunk_length_tiles`.

For each accepted chain, the corridor solver computes a least-cost
poly-line from chain start to chain end on a coarse grid where the
edge cost is:

```
edge_cost(c -> n) =
      base_step
    + routing_cost(n) * corridor_cost_scale
    + turn_penalty(c, n)
    + wall_blocker(n)
    + foot_crossing_blocker(c, n)
    - valley_score(n) * corridor_valley_bonus
    - pass_anchor_bonus(n)
    - downstream_alignment_bonus(c, n, hydrology_direction)
```

Solver is a deterministic A* (or Dijkstra on a small bounded band)
seeded by the hydrology chain so the corridor stays in the same
drainage but is allowed to deviate by up to `corridor_band_cells`
coarse cells from the D8 chain to find a cheaper valley path. The
solve is X-wrap safe.

Output of the corridor solver is the **corridor poly-line**: a list
of coarse cell anchors that the spline (Substrate Extension 8) reads.
Spline smoothing may refine the corridor, but it must **not** be the
primary wall-avoidance mechanism. Wall avoidance lives in the
corridor solver and in `wall_blocker`, not in cosmetic smoothing.
`foot_crossing_blocker(c, n)` is also binding here: dense-foot crossing
outside pass windows is rejected before corridor smoothing.

Tributaries are trunks whose downstream tip is another trunk. Strahler
order `s` is computed by the standard rule. The trunk graph is the
union of trunks, tributaries, side channels, and lake junctions.

Each trunk has:

| Field | Type | Notes |
|---|---|---|
| `trunk_id` | u32 | Stable per session. |
| `hydrology_nodes` | `PackedInt32Array` | D8 chain (debug / hydrology). |
| `corridor_anchors` | `PackedInt32Array` | Least-cost corridor poly-line, upstream-to-downstream. |
| `parent_trunk_id` | u32 or 0 | Set on tributaries. |
| `strahler_order` | u8 | |
| `start_cell` | i32 | First anchor. |
| `end_cell` | i32 | Last anchor (ocean band, lake polygon, or another trunk's anchor). |
| `total_length_tiles` | float | |

### 8. Corridor centerline + width curve (signed-distance classification, no polygon offset)

For each trunk, native code generates one continuous **centerline
spline** in tile-space:

1. Convert `corridor_anchors` (from stage 7) to tile-space anchor
   points.
2. Apply deterministic sub-cell jitter to each anchor based on
   `(seed, trunk_id, anchor_index)` and local valley_score (more
   jitter on plains, less in canyons).
3. Smooth the polyline with a chord-length parameterised Catmull-Rom
   (or equivalent) spline, then apply Chaikin-style smoothing passes
   to remove residual angles. Number of passes scales with local
   `valley_score` and `river_meander`.
4. Sample the spline at fine arc-length steps
   (`SPLINE_GEOMETRY_SAMPLE_STEP_TILES`, default `0.5` tiles) to
   produce a poly-line approximation that the chunk rasterizer can index
   spatially.
5. Compute and store side-specific `bank_noise_left_q8(s)` and
   `bank_noise_right_q8(s)` values at `WIDTH_BANK_SAMPLE_STEP_TILES`
   intervals, deterministic from `(seed, trunk_id, side, s)`. These are
   scalar edge offsets, not 2D polygons. One bank may be rough while the
   opposite bank remains calmer. Bank noise is sampled from coherent 1D
   noise along arc length using `BANK_NOISE_WAVELENGTH_TILES`
   (`8 / 24 / 64` tiles), then smoothed before quantization.
   Independent per-sample random offsets are forbidden.
6. Width and bank data may be stored at a coarser arc-length resolution
   than geometry samples; the rasterizer interpolates width and noise
   locally after selecting candidate spline geometry. This keeps memory
   bounded without returning to per-segment circle stamping.
7. Clip to world Y bounds; resolve seam crossings by emitting two
   sub-splines wrapped in X.

Width curve along arc length:

```
width_shallow(s) =
       width_base
     + width_flow      * sqrt(flow_accumulation_along_s)
     + width_order     * strahler_order_along_s
     + width_downstream* downstream_factor(s)         (grows toward mouth)
     - width_constrict * mountain_pressure_along_s    (narrow in canyons)
     + width_valley    * valley_score_along_s         (wider on plains)
     + width_lake      * lake_proximity_term(s)       (widening near lakes)
```

```
width_deep(s) = clamp(
                   width_shallow(s) * deep_ratio,
                   deep_min,
                   width_shallow(s) - bank_min
                )
```

Constants are scaled by `bed_width_scale`, `mouth_width_scale`,
`river_meander`, and `mountain_density` per the coupling table in P6.

**No polygon offset is performed.** Producing left/right bank polygons
by offsetting the centerline introduces self-intersections at sharp
turns, ugly joins at split/rejoin points, and seam-wrap pain. V2 uses
a **signed-distance classification** instead.

Per output tile inside a chunk:

```
1. Spatial index returns all candidate spline segments whose AABB can
   cover the tile after width and bank padding.
2. For each candidate, find the closest point on the segment;
   compute arc length s and signed perpendicular distance d_signed.
3. Read width_shallow(s), width_deep(s), and side-specific bank noise:
       bank_noise_side =
           d_signed < 0 ? bank_noise_left_q8(s) : bank_noise_right_q8(s)
4. Effective side-specific radii:
       r_shallow_side(s) = width_shallow(s) + bank_noise_amp * bank_noise_side
       r_deep_side(s) = width_deep(s) + bank_noise_amp * 0.5 * bank_noise_side
5. Candidate membership:
       |d_signed| <= r_deep_side(s)            -> RIVER_CORRIDOR (deep)
       |d_signed| <= r_shallow_side(s)         -> RIVER_CORRIDOR (shallow)
       |d_signed| <= r_shallow_side(s) + bank  -> RIVER_BANK
       else                                    -> not river
6. Final river class is the maximum membership across all candidates:
       deep beats shallow; shallow beats bank; higher Strahler / parent
       trunk wins ties; side channel may not erase parent trunk width at
       split / rejoin junctions.
```

This produces a continuous ribbon with smooth width interpolation,
forbids per-segment circle stamping (the river footprint is a union of
continuous spline memberships, not a chain of capsules), handles
tributary junctions / side-channel split-rejoin / delta overlaps, and
avoids polygon-offset pathologies.

For each `pass_anchor` crossed by the corridor, a `canyon` flag is
attached to the affected arc-length range. Canyon segments narrow
`width_shallow(s)` by an extra factor, deepen `width_deep(s)`, and
emit a `valley_carve_request` so the chunk rasterizer rewrites the
foot inside the corridor (CB2 / L6).

### 8b. Side channels and split-rejoin islands

Side channels are deterministic secondary splines that fork off a
trunk and reconnect downstream along the same trunk, enclosing a
land island.

Side-channel generation algorithm (per trunk):

```
1. Eligibility:
   - parent trunk strahler_order >= side_channel_min_order (default 2);
   - parent trunk arc-length range outside any canyon segment;
   - local valley_score > side_channel_min_valley.
2. Pick split point s_split deterministically from
   (seed, trunk_id, candidate_index).
3. Pick rejoin point s_rejoin in
   [s_split + side_channel_min_offset, s_split + side_channel_max_offset].
4. Run a small-band least-cost solve from the split point to the
   rejoin point, biased lateral by side_channel_lateral_offset.
5. Reject the candidate if:
   - the resulting polyline crosses a wall;
   - the enclosed island area < side_channel_min_island_area_tiles;
   - the side-channel length > side_channel_max_length_factor * |s_rejoin - s_split|;
   - the candidate intersects another active side channel or lake polygon
     in a way the spec does not allow;
   - the candidate violates corridor cost budget.
6. Width curve:
       side_channel_width_shallow(s) = parent_width_shallow_at(s_proj) * side_channel_ratio
   where s_proj is the projected arc length on the parent trunk.
7. Cap side-channel count per trunk segment by `max_side_channels_per_segment`.
```

Side-channel deltas at ocean mouths follow the same rule with relaxed
rejoin: a delta braid may rejoin the parent trunk inside the ocean
band, or terminate inside the band, but it must not escape the band
back to land.

### 9. Lake basin polygon (basin-first, not radial-first)

Lake polygons are derived primarily from **basin membership** and the
**hydro-height isoline at the spill elevation**, not from a circle
deformed by noise. Radial noise is allowed only as a small perturbation
of the basin-derived outline, never as the primary shape source.

For each filled basin that meets the gameplay criteria below:

1. **Basin membership.** Build the set of coarse cells whose
   `filled_hydro_height` lies at or below the spill elevation and
   that belong to the same `basin_id`.
2. **Isoline traversal.** Walk the perimeter of that cell set at the
   spill elevation; this is the rough outline.
3. **Sub-cell refinement.** For each perimeter coarse cell, refine
   the boundary at the tile-level resolution by sampling
   `hydro_height` at sub-cell positions, so the outline does not
   look like a stair-stepped coarse polygon.
4. **Noise perturbation.** Apply small deterministic noise normal to
   the boundary; perturbation amplitude is bounded by
   `lake_outline_noise_max` (default `2` tiles) and may not move the
   outline outside the basin membership set.
5. **Island detection.** Sub-cells inside the basin whose
   `hydro_height` exceeds the spill elevation form **islands**. An
   island is kept only if its area is at least
   `lake_island_min_area_tiles`.
6. **Wall / highland exclusion.** Lake deep / shallow footprint may not
   overlap `MOUNTAIN_WALL`. High terrain inside a lake basin becomes an
   island polygon only if it is fully enclosed and passes island area
   limits. Otherwise the lake candidate is rejected or clipped before
   rasterization. Clipped lakes must still pass connectedness, shape
   source, and area limits.
7. **Inflow / outflow snapping.** Snap inflow corridor endpoints to
   boundary points adjacent to the corridor's last anchor before the
   lake. Snap the outflow corridor start (if `outflow != 0`) to the
   spill cell's perimeter. Visual continuity between river and lake
   is required.

A basin is **rejected as a lake** (downgraded to `PLAINS` for that
region) if any of the gameplay limits below fails:

| Limit | Default | Purpose |
|---|---|---|
| `lake_min_area_tiles` | 64 | No micro-puddles. |
| `lake_max_area_tiles` | 16384 | No mega-lakes that consume the map. |
| `lake_min_inflow_length_tiles` | 32 | No lake on a 2-cell creek. |
| `lake_min_distance_from_ocean_tiles` | 32 | No lake glued to the ocean band. |
| `lake_min_spacing_tiles` | 96 | Lakes do not stack adjacent. |
| `terminal_lake_probability` | 0.30 | Closed basins become terminal lakes only at this rate; the rest stay terminal_basin without water. |

A basin whose final outline is closer to a radial blob than to its
basin footprint (measured by area-symmetric difference between the
emitted polygon and the basin membership set) **must be rejected**.

Result is a `LakePolygon`:

| Field | Type | Notes |
|---|---|---|
| `lake_id` | u32 | Hashed from seed + basin id. |
| `outer` | `PackedVector2Array` | CCW perimeter, X-wrap-safe. |
| `islands` | `Array[PackedVector2Array]` | CW perimeter for each island. |
| `inflows` | `PackedInt32Array` | Trunk IDs entering the lake. |
| `outflow` | `i32` or `0` | Trunk ID leaving the lake. `0` for terminal lakes. |
| `shallow_band_tiles` | float | Width of the shallow rim. |
| `spill_elevation` | float | Used for cross-pass consistency. |
| `area_tiles` | i32 | Computed; must satisfy lake limits above. |
| `terminal` | bool | True when `outflow == 0`. |

A lake is **terminal** when `outflow = 0`. Terminal lakes are allowed
only in deep closed basins; they are clipped at world Y bounds and
must not appear in the ocean band.

### 10. Landscape owner (per tile, not per coarse cell)

A coarse cell is `32 x 32` tiles in V2. A 3-tile river running through
a coarse cell does not own the whole `32 x 32` block; a foot fade does
not own the whole block either. Per-coarse-cell ownership even at this
resolution is too coarse to be authoritative.

Therefore stage 9 in V2 is split:

**Stage 9a (coarse spatial index).** Per coarse cell, build a
small list of candidate owners derived from the geometry whose AABB
intersects the cell. Each entry references the geometry it came
from (ridge id, trunk id, lake id, basin id). This is an
**acceleration / caching layer**, not a final terrain authority.

```
coarse_owner_index(cell) -> {
    candidates: [
        { kind: MOUNTAIN_WALL,  ridge_id, range_id, geometry_ref },
        { kind: MOUNTAIN_FOOT,  range_id, geometry_ref },
        { kind: RIVER_CORRIDOR, trunk_id, geometry_ref },
        { kind: RIVER_BANK,     trunk_id, geometry_ref },
        { kind: LAKE_BASIN,     lake_id,  geometry_ref },
        { kind: LAKE_RIM,       lake_id,  geometry_ref },
        { kind: DELTA,          trunk_id, geometry_ref },
        { kind: DEEP_OCEAN,     geometry_ref },
        { kind: SHALLOW_COAST,  geometry_ref },
        { kind: MOUTH_ESTUARY,  trunk_id, geometry_ref },
        { kind: PASS_ANCHOR,    ridge_id, geometry_ref },
        ...
    ],
    ocean_band_overlap:   bool,
    burning_band_overlap: bool,
    plains_default:       bool
}
```

**Stage 9b (tile-level authoritative resolve in stage 10).** During
chunk rasterization, every tile classifies its own owner by querying
the candidate list for its coarse cell, performing the actual
geometric tests (signed-distance to spline, point-in-polygon for
lake, distance-to-ridge for wall/foot) on the candidate geometry,
and applying the priority rule below.

Tile-level owner resolution rule (highest wins):

| Priority | Owner | Test |
|---|---|---|
| 1 | `DEEP_OCEAN` | tile inside hard ocean band |
| 2 | `MOUTH_ESTUARY` | tile inside river-mouth erosion / estuary widening |
| 3 | `SHALLOW_COAST` | tile inside irregular shoreline / bay mask below hard band |
| 4 | `BURNING_BAND` | tile inside burning Y band |
| 5 | `MOUNTAIN_WALL` | tile inside any ridge `wall_radius` |
| 6 | `LAKE_BASIN` (deep) | tile inside lake polygon, deep band |
| 7 | `LAKE_RIM` (shallow) | tile inside lake polygon, shallow band |
| 8 | `DELTA` | tile inside delta widening, ocean-side mouth |
| 9 | `RIVER_CORRIDOR` (deep) | `\|d_signed\| <= r_deep(s)` |
| 10 | `RIVER_CORRIDOR` (shallow) | `\|d_signed\| <= r_shallow(s)` |
| 11 | `RIVER_BANK` | shallow shoulder band beyond river_shallow |
| 12 | `MOUNTAIN_FOOT` | tile inside foot fade band |
| 13 | `VALLEY_FLOOR` | tile inside a high `valley_score` corridor between ranges, no other owner |
| 14 | `PLAINS` | default |

`CARVED_VALLEY` is not a competing terrain owner. It is a modifier
emitted when `RIVER_CORRIDOR` or `RIVER_BANK` overlaps original
`MOUNTAIN_FOOT` inside a `pass_anchor` window.

Final terrain owner remains:

- `RIVER_CORRIDOR` deep / shallow inside the river;
- `RIVER_BANK` on the bank shoulder;
- `PLAINS`, `VALLEY_FLOOR`, or a rocky bank profile on carved
  surrounding foot.

`carved_valley_flag` marks that the original mountain foot was eaten by
river passage. Outside pass anchors, `MOUNTAIN_WALL` outranks corridors
only when the corridor solver has already failed CB4 (which is itself
an assert).

Tile-level resolution is the **single authority** for terrain id and
walkable flag. `coarse_owner_index` is purely an acceleration
structure; it must not be queried directly by chunk rasterization to
decide a tile's terrain id.

If a tile-level resolution produces a contradiction (e.g.
`RIVER_CORRIDOR` claimed but no spline within `r_shallow(s)`), the
chunk rasterizer must assert (CB10).

### 10b. Mountain presentation bands

Mountain rasterization must output enough presentation metadata to
render distinct mountain materials without making atlas selection depend
on random per-tile noise. At minimum, `ChunkPacketV2` emits:

- crest / high ridge;
- wall mass;
- slope;
- foot;
- scree;
- external edge;
- ridge tangent / local orientation bucket.

Mountain atlas selection must be orientation-aware. Long ridge streaks
follow the local ridge tangent bucket instead of choosing arbitrary
per-tile directions. Detail noise may vary material within a band, but
it must not erase the band identity or make wall / foot / scree read as
one flat material blob.

### 11. Detail noise overlay (per chunk read)

At chunk rasterization time, native code applies a small per-tile
detail noise to mountain boundary tests to break perfectly straight
skeleton-distance contours. Detail noise:

- never changes the final tile owner selected from river / lake /
  delta / band geometry;
- only perturbs the **boundary** of `MOUNTAIN_WALL` -> `MOUNTAIN_FOOT`
  -> `MOUNTAIN_SLOPE` -> `PLAINS` by at most `2` tiles in any
  direction;
- never crosses `RIVER_CORRIDOR` or `LAKE_BASIN` boundaries (those are
  authoritative geometry);
- is fully deterministic from `(seed, world_version, tile_coord,
  snapshot_signature)`.

Without this overlay, mountain edges look unnaturally clean.

## Coupled Behaviors (binding rules)

### CB1. Rivers route through valleys, not through walls

`MOUNTAIN_WALL` cells are non-routing; routing cost is effectively
infinite. Routing must produce a `cycle-free downstream graph` even
when this leaves a sub-region with no path to the ocean - in that case
the sub-region accepts only terminal lakes.

### CB2. River-foot interaction has exactly three modes

There is no fourth case. Implementations that produce any other
behaviour (a river dissolving into foot, a river ending at foot, a
flat channel through foot without carve) are forbidden.

1. **Soft foot edge (corridor along foot).**
   - The corridor passes alongside foot but the centerline stays
     outside the foot fade. The bank may touch foot tiles.
   - `valley_carve_request` is **not** emitted.
   - Tile-level resolution paints the corridor inside its own
     `RIVER_CORRIDOR` / `RIVER_BANK` zones; surrounding foot tiles
     stay `MOUNTAIN_FOOT`.
   - Visual reading: river hugs the foot of a range.

2. **Foot pass / canyon (corridor through `pass_anchor`).**
   - The corridor crosses foot **only** through a `pass_anchor`.
   - `valley_carve_request` **is** emitted on the affected arc-length
     range.
   - Tile-level resolution emits `carved_valley_flag` for any
     `RIVER_CORRIDOR` or `RIVER_BANK` tile whose original classification
     was `MOUNTAIN_FOOT` inside the pass window. The final owner remains
     riverbed or river bank. Surrounding foot inside the carve window may
     become `PLAINS`, `VALLEY_FLOOR`, or a rocky bank profile so the
     passage reads as cut into the range. The deep band may dip below
     the surrounding plains height for canyon presentation in a future
     amendment.
   - Visual reading: river cuts a canyon through the range.

3. **Illegal foot crossing (forbidden).**
   - The corridor crosses dense foot **outside** any `pass_anchor`.
   - This is a hard error. The corridor solver must reject the
     candidate path and re-solve with elevated cost. If the rejection
     loops, the landscape candidate is invalid and must be rejected
     before world creation or load publication. It must not silently
     downgrade the trunk into a different generation path.
   - Tile-level resolution must never paint such a corridor.

Spline smoothing must respect these modes. Smoothing that pushes a
soft-edge corridor into foot is a smoothing bug, not a routing
permission. Smoothing that pushes a pass corridor outside its pass
window is also a bug; the pass-aware path must be preserved across
the smoothing pass.

### CB3. Mountain skeletons preserve at least one route

For every range `range_id`, the substrate must guarantee that at least
one pass anchor exists inside its bounding region. If the skeleton
solver produces a range with no pass anchors, it must inject at least
one synthetic pass at the thinnest segment of the longest ridge.

Synthetic pass injection is not a fallback path. It is a required
deterministic step of ridge skeleton construction. It must run before
validation and be included in the snapshot signature.

This is a hard rule. Without it, dense mountain settings can land a
ring-shaped range that traps a basin and produces a frozen routing
graph. If the required deterministic injection cannot produce a valid
pass under the configured attempt cap, the landscape candidate is
rejected; it must not demote the range into a fallback topology.

### CB4. Trunks never cross walls

A trunk corridor never includes a `MOUNTAIN_WALL` cell. If the
centerline spline crosses a wall boundary, smoothing must shift the
spline outward until it is at least `bank_min` tiles away from the
wall.

### CB5. Mountains never overwrite a corridor

Tile-level resolution gives `RIVER_CORRIDOR` and `RIVER_BANK` higher
priority than `MOUNTAIN_FOOT`, but lower than `MOUNTAIN_WALL`. Because
of CB4, a corridor is never on a wall cell, so the ordering never
collides. `carved_valley_flag` is emitted as context after the final
owner is known; it does not re-rank terrain.

### CB6. Lakes connect to rivers

The landscape solve must reject any lake polygon with no inflow trunk
inside the candidate basin. Such a basin remains ordinary ground in the
tile-level resolver (even if it is a local relief depression). This
eliminates "blue blobs" disconnected from the network.

### CB7. Outflow of non-terminal lakes is a real trunk

If a lake basin has `outflow != 0`, the corresponding trunk must exist
in the trunk graph and must enter the lake polygon at the chosen spill
cell.

### CB8. Mouths widen

A trunk whose downstream tip touches `DEEP_OCEAN`, `SHALLOW_COAST`, or
`MOUTH_ESTUARY` is `mouth-class`. Mouth-class corridor segments
increase `width_shallow` by `mouth_bonus(flow, mouth_width_scale)` and
may, when `river_amount >= split_threshold`, fork into braids inside the
estuary / coast zone. Braids must reconnect or terminate inside an
ocean zone; they never escape back into land.

Mouths must cut the shoreline field. A mouth-class trunk emits
`MOUTH_ESTUARY` geometry that widens the playable coastline into a bay
or inlet before the trunk reaches `DEEP_OCEAN`; it must not simply draw
a river line that stops at a straight ocean band.

### CB9. Coupled settings (binding form of P6)

For a fixed seed, varying any single coupled setting must produce a
visible, monotone change matching the table in P6. Acceptance includes
A/B comparison samples per setting at default vs +50% vs -50%.

### CB10. Per-tile contradictions are forbidden

If chunk rasterization detects a cell with conflicting owner /
geometry references (for example `RIVER_CORRIDOR` cell whose nearest
trunk is more than `corridor_max_tiles` away), it must assert in
debug builds and emit a clear actionable error in release.

## Determinism

V2 outputs are pure functions of:

- `seed`;
- `world_version`;
- `world_bounds.width_tiles`, `world_bounds.height_tiles`;
- `settings_packed` (full V2 layout);
- `snapshot_signature` (derived from the above).

### Topology decisions are integer-only

Cross-host byte-identical determinism is **not achievable** when
topology depends on raw IEEE-754 float comparisons across compilers,
SIMD widths, and STL implementations. V2 therefore enforces:

- every **topology decision** (D8 neighbour selection, depression
  fill ordering, downstream tie-break, corridor solver A* tie-break,
  cycle-break tie-break, side-channel candidate ranking, lake
  acceptance / rejection, ridge growth termination, pass-anchor
  selection) must operate on **integer or fixed-point** values;
- floating-point arithmetic is allowed only after the topology is
  fixed, for local geometric interpolation that does not feed back
  into topology;
- any float-derived value that is committed to the snapshot, used
  for sorting, used for hashing, or fed into a packet field must
  first be **quantized** to a fixed integer representation
  (`q8`, `q16`, or a documented fixed-point scale per field);
- priority queues and ordered traversals must use deterministic
  composite keys: `(quantized_height, canonical_x, canonical_y,
  trunk_id)` style, never `float, float, float`.

### Snapshot scope

Across independent runs and hosts honouring the integer-only rule,
the same `(seed, world_version, world_bounds, settings_packed)` must
produce byte-identical:

- `mountain_region_mask`, `ridge_skeleton`, `mountain_distance`,
  quantised `hydro_height`, `routing_cost`, `downstream_index`,
  `flow_accumulation`, `corridor_anchors`, `trunk_corridors`
  (vertex list quantised), `lake_polygons` (vertex list quantised),
  `shoreline_offset`, `ocean_zone_mask`, `coarse_owner_index`,
  snapshot signature;
- per-chunk packet output for any chunk coord.

Determinism asserts in debug builds. A failure here is a blocker.

## Persistence

### `world.json` shape under V2

`worldgen_settings` carries exactly one landscape-related block:
`landscape`. The old `rivers` and the field-derivation half of
`mountains` are gone. `mountains` is removed from `worldgen_settings`
entirely; mountain shape is part of `landscape`. Mountain interior
gameplay (cavity / cover) does not need persisted settings.

```json
{
  "world_seed": 42,
  "world_version": 16,
  "worldgen_settings": {
    "world_bounds": { "width_tiles": 4096, "height_tiles": 2048 },
    "foundation": {
      "ocean_band_tiles": 128,
      "burning_band_tiles": 128,
      "pole_orientation": 0,
      "slope_bias": -0.30
    },
    "landscape": {
      "mountain_density":            0.55,
      "mountain_scale":              768.0,
      "mountain_continuity":         0.70,
      "mountain_ruggedness":         0.55,
      "mountain_latitude_influence": 0.60,
      "river_amount":                0.55,
      "river_meander":               0.55,
      "bed_width_scale":             1.0,
      "mouth_width_scale":           1.0,
      "lake_density_scale":          1.0,
      "lake_radius_scale":           1.0
    }
  }
}
```

Loader rules (binding, no fallback):

- a new world always writes the `landscape` block from initial
  defaults baked into the loader;
- during new-world creation, invalid landscape candidates are rejected
  before world creation. Random-seed creation may retry up to
  `LANDSCAPE_RANDOM_SEED_RETRY_LIMIT`; explicit user seeds fail with a
  clear validation error and debug reason;
- on load, `world_version != 16` is a fatal `save format obsolete`
  error; the loader does not attempt to upgrade older shapes;
- on load, `worldgen_settings.landscape` missing is a fatal error;
  the loader does not substitute defaults silently;
- on load, any field inside `landscape` outside its clamp range is
  a fatal error; the loader does not clamp silently;
- changing the `landscape` field set or default semantics later
  requires a `WORLD_VERSION` bump and a corresponding spec
  amendment.

### What V2 saves

- `worldgen_settings.landscape` (above);
- player diff in `WorldDiffStore` (unchanged).

### What V2 never saves

- ridge skeletons;
- mountain distance fields;
- trunk corridors;
- lake polygons;
- routing cost field;
- per-tile landscape owner;
- chunk packet bits;
- spatial index buckets;
- snapshot signature (regenerated on load).

### `WORLD_VERSION`

There is exactly one V2 generation path. `world_version` is set to
`16` by V2. There is no boundary table, no legacy compatibility
matrix, and no transition path. Any save with a different value is
rejected. Future `world_version > 16` requires a new spec amendment;
this document does not define future-version compatibility.

## Performance Class

| Operation | Class | Dirty unit | Budget |
|---|---|---|---|
| Substrate solve (skeleton + distance + routing + corridors + lakes) | one-time native worker at world load | whole world coarse grid + per-trunk geometry | target `<= 4000 ms` on the largest preset (8192 x 4096) at `coarse cell = 32`. The `4x` budget jump vs the old `coarse = 64` baseline reflects the binding Q1 decision. Breaching is a closure blocker, addressed by lowering ridge cap or tightening solver constants - never by raising `coarse cell` (binding) and never by adding a fallback path. |
| Snapshot memory | one-time native worker at world load | one `WorldPrePassSnapshot` | `<= LANDSCAPE_SNAPSHOT_MEMORY_BUDGET_MB` on the large preset at default settings |
| Spatial index build | one-time native worker at world load | per-snapshot R-tree / grid bucket over geometry AABBs | included in substrate solve budget |
| Substrate cache read by chunk batch | native, non-blocking | (no dirty unit; immutable) | free |
| Chunk packet generation | background native worker | `32 x 32` output chunk; `AUTOTILE_MARGIN_TILES` neighbour margin is context read only | shares existing chunk batch budget; final tile classification iterates over `1024` tiles per chunk regardless of nearby geometry size |
| Spatial index query per chunk | background native worker | `O(log K)` for `K` geometry items in the snapshot | bounded by snapshot geometry, not by neighbour-margin radius |
| Detail noise overlay | background native worker | per tile inside chunk | O(1) per tile, no allocations |
| Carved valley flag / local surrounding-foot rewrite | background native worker | per output tile inside corridor or carve window | O(1) per tile |
| Overview render | native worker + main-thread publish | one substrate snapshot | within existing overview pipeline timing |
| Player mining | interactive | one tile in diff | unchanged |

Forbidden:

- GDScript loops over chunk tiles to compute landscape kind;
- recomputing ridge skeletons per chunk;
- recomputing trunk corridors per chunk;
- full scan over every ridge segment for every coarse cell when
  computing mountain distance fields on the large preset; use spatial
  acceleration over ridge segment AABBs instead;
- per-segment circle stamping as the width source;
- polygon-offset bank generation (V2 uses signed-distance to spline,
  Substrate Extensions section 8);
- storing width / bank profile samples at the full geometry sample rate
  when `WIDTH_BANK_SAMPLE_STEP_TILES` is sufficient;
- independent per-sample random bank offsets; bank roughness must come
  from coherent 1D noise along arc length;
- accepting lake deep / shallow footprints that overlap
  `MOUNTAIN_WALL`;
- iterating over `chunk + large halo` tiles instead of querying the
  spatial index (P7);
- per-coarse-cell authoritative owner queries inside chunk
  rasterization (Substrate Extensions section 10 mandates tile-level
  resolution);
- floating-point-only topology decisions that can drift across hosts
  (the integer-only topology rule, Determinism section);
- mass `TileMapLayer.clear()` on landscape changes;
- saving any landscape geometry to disk;
- substrate solve on the main thread or during interactive play;
- adding a second whole-world prepass alongside `WorldPrePass`;
- secondary GDScript fallback when native is unavailable (LAW 9);
- changes to excavation, cavity / opening cache, cover lifecycle, or
  reveal semantics from `mountain_generation.md` without a separate
  amendment (Status section).

Verification targets:

- chunk batch timing regression `<= 15%` vs current V1 path on the
  same preset and seed;
- substrate budget holds on `small`, `medium`, `large` presets at
  default settings;
- determinism check: two cold runs of the same world produce identical
  snapshot signatures and identical chunk packets;
- no new hitch class (>22 ms frame) attributable to landscape reads
  during exploration.

## Acceptance Criteria

### A. Mountain shape (numeric + visual)

- [ ] **Range elongation.** For every primary range on the medium
      preset, `range bounding-box major-axis / minor-axis >= 1.8`.
- [ ] **Two adjacent ranges separable.** Inter-range valley_score
      median between two `range_id`s is at least `0.4` higher than
      either range's interior valley_score.
- [ ] **No chopped edges.** Across all sampled range outlines, no
      perimeter segment longer than `8` tiles lies along a
      constant-noise contour of `mountain_region_mask`. Verified by
      comparing the outline to the mask boundary.
- [ ] **Continuity / ruggedness coupling.** Doubling
      `mountain_continuity` increases mean ridge length by at least
      `40%`. Doubling `mountain_ruggedness` increases pass-anchor
      count per range by at least `40%`.
- [ ] **Ridge streak coherence.** On overview / reference chunks, at
      least `70%` of high-ridge detail strokes align within `30`
      degrees of the local ridge tangent.
- [ ] **Mountain material bands visible.** Core / wall / foot / scree
      presentation bands remain visibly distinct and do not collapse
      into one flat blob.
- [ ] **Visual sanity.** Reference-seed overview is reviewed by a
      human and matches the reference target intent (final visual
      gate).

### B. River shape (numeric + visual)

- [ ] **Beading rejection.** For every trunk, sample river centerline
      every `1` tile and width every `4` tiles. Outside lake / mouth /
      canyon tags, adjacent width samples differ by `<= 0.75` tiles.
      Inside canyons, allowed step is `<= 1.5` tiles per `4`-tile arc.
      Adjacent width samples may not alternate high / low in a periodic
      pattern caused by segment endpoints. The rendered river footprint
      must have no repeated circular lobes at spline sample spacing.
- [ ] **Bank roughness no sawtooth.** Adjacent bank offset delta is
      `<= BANK_NOISE_MAX_DELTA_PER_TILE` per `1` tile sample outside
      explicit rocky / canyon tags. Independent one-sample jitter is a
      failure even when the signed-distance footprint is continuous.
- [ ] **Sinuosity.** `trunk_sinuosity = arc_length / straight_distance`.
      Plains trunks: `1.15..1.8`. Canyon trunks: `1.02..1.25`. Mid-
      course: `1.10..1.50`.
- [ ] **Width band.** Headwaters: shallow radius `<= 1.5` tiles.
      Mid-course: `2..5` tiles. Pre-mouth: `5..7.5` tiles plus mouth
      bonus.
- [ ] **Mouth widening.** Mouth diameter `>= 10` tiles on trunks
      with `flow >= 0.5`.
- [ ] **Tributary count.** At least one trunk per medium-preset
      seed has `>= 2` tributaries; at least 50% of trunks have
      `>= 1` tributary.
- [ ] **Wall overlap.** River deep / shallow tiles overlapping
      `MOUNTAIN_WALL`: exactly `0`. This is a hard zero, not a budget.
- [ ] **Side channels enclose islands.** Each side channel encloses
      at least `side_channel_min_island_area_tiles` of land.
- [ ] **Visual sanity.** Reference-seed overview is reviewed by a
      human and matches the reference target intent.

### B2. Ocean shoreline shape (numeric + visual)

- [ ] **Coastline irregularity.** On reference seeds, coastline
      y-offset variation is at least
      `COASTLINE_MIN_Y_VARIATION_TILES`, and no straight coast segment
      longer than `COASTLINE_MAX_STRAIGHT_SEGMENT_TILES` appears
      outside debug-flat-coast mode.
- [ ] **Estuary cuts.** River mouths create estuary / bay cuts in the
      shoreline field, not just river lines ending at a straight ocean
      band.
- [ ] **Ocean zones.** Every ocean-owned tile resolves to exactly one
      of `DEEP_OCEAN`, `SHALLOW_COAST`, or `MOUTH_ESTUARY`; there is
      no generic straight `OCEAN_BAND` owner in V16 tile output.

### C. Lake shape (numeric + visual)

- [ ] **Lake connectedness.** Every accepted lake polygon has at
      least one inflow trunk endpoint inside the polygon, or a
      trunk crossing the boundary into the polygon. **Zero**
      disconnected lakes.
- [ ] **Outflow.** Every non-terminal lake has a trunk anchored at
      the spill cell leaving the polygon.
- [ ] **Shape source.** Area-symmetric difference between the
      emitted lake polygon and its underlying basin membership set
      is below `lake_basin_match_tolerance` (default `15%` of basin
      area). Lakes outside this tolerance must be rejected.
- [ ] **Limits.** All accepted lakes satisfy `lake_min_area_tiles`,
      `lake_max_area_tiles`, `lake_min_inflow_length_tiles`,
      `lake_min_distance_from_ocean_tiles`, `lake_min_spacing_tiles`.
- [ ] **Islands.** At least 10% of accepted lakes on the medium
      preset contain one island.
- [ ] **Wall overlap.** Lake deep / shallow tiles overlapping
      `MOUNTAIN_WALL`: exactly `0`.
- [ ] **Wall / highland islands.** Wall or highland inside an accepted
      lake is represented as an island polygon or rejected before tile
      rasterization.
- [ ] **Visual sanity.** Reference-seed overview is reviewed by a
      human and matches the reference target intent.

### D. Coupled behaviour

- [ ] At fixed seed, doubling `mountain_density` produces visibly
      more sinuous trunks and more inline lakes than baseline.
- [ ] At fixed seed, halving `mountain_density` produces visibly
      wider, smoother trunks across plains.
- [ ] At fixed seed, doubling `river_amount` produces more
      tributaries and a larger delta count.
- [ ] No setting at default produces walls without passes
      (CB3 hard rule).
- [ ] No setting produces a lake without inflow (CB6 hard rule).

### E. Routing correctness

- [ ] Downstream graph is cycle-free for every accepted snapshot
      (assert-on-debug, log-on-release).
- [ ] No accepted trunk crosses `MOUNTAIN_WALL`.
- [ ] No accepted corridor produces tile-level walkability that
      contradicts the tile-level owner priority.

### E2. Spawn safety (V16 only)

V2 changes the set of dangerous tiles a spawn resolver can fall into.
The amended spawn rule for `world_version == 16` must satisfy:

- [ ] Spawn resolver rejects every candidate tile whose tile-level
      owner is one of `DEEP_OCEAN`, `SHALLOW_COAST`,
      `MOUTH_ESTUARY`, `BURNING_BAND`, `MOUNTAIN_WALL`,
      `MOUNTAIN_FOOT` unless explicitly allowed by spawn settings,
      `RIVER_CORRIDOR` (deep or shallow), `RIVER_BANK`, `LAKE_BASIN`,
      `LAKE_RIM`, or `DELTA`.
- [ ] Spawn resolver prefers `PLAINS` or `VALLEY_FLOOR` tiles within
      readable distance of a water footprint, outside every dry bed
      footprint, and with safe patch radius
      `>= SPAWN_SAFE_PATCH_MIN_TILE` (spawn settings constant).
- [ ] Every accepted new-world seed resolves a valid spawn safe patch.
      If not, the candidate seed is rejected before world creation.
      Random-seed creation may retry under the new-world candidate
      rejection rule; explicit user seeds raise a clear
      `seed unspawnable on preset` validation error rather than
      silently spawning in a forbidden tile.
- [ ] Across a sample of `>= 16` seeds per preset, zero spawns are
      placed in forbidden owners.

### F. Determinism

- [ ] Two cold runs of the same `(seed, world_version, bounds,
      settings_packed)` produce identical snapshot signatures and
      identical chunk packets across all loaded chunks.
- [ ] X-wrap seam: chunks at `chunk_x = 0` and chunks at
      `chunk_x = world_width / 32 - 1` produce continuous skeleton,
      corridor, and lake geometry across the seam.

### G. Persistence

- [ ] New worlds at `world_version == 16` always write
      `worldgen_settings.landscape`.
- [ ] Loading any save with `world_version != 16` fails with
      `save format obsolete; start a new world`.
- [ ] Loading `world_version == 16` without `worldgen_settings.landscape`
      fails loudly.
- [ ] No landscape geometry is ever written to `chunks/*.json` or
      `world.json` outside the settings block.

### H. Performance

- [ ] Substrate solve fits within budget on `small / medium / large`
      at default settings.
- [ ] Snapshot memory budget `<= LANDSCAPE_SNAPSHOT_MEMORY_BUDGET_MB`
      on the large preset at default settings.
- [ ] Total spline sample count `<= LANDSCAPE_MAX_SPLINE_SAMPLES_LARGE`
      on the large preset at default settings.
- [ ] Width / bank data may be stored at coarser arc-length resolution
      than geometry samples; rasterizer interpolates width / noise
      locally.
- [ ] Mountain distance-field generation uses a spatial acceleration
      structure over ridge segment AABBs; large preset does not perform
      a full ridge-segment scan for every coarse cell.
- [ ] Chunk batch timing regression `<= 15%` vs V1 baseline on the
      same preset / seed.
- [ ] No GDScript fallback path computes landscape geometry.
- [ ] No new main-thread hitch class observed during exploration.

### I. Governance compliance

- [ ] LAW 1: heavy compute is in C++, not GDScript.
- [ ] LAW 4: `WORLD_VERSION` bumped from `15` to `16` in the same
      task that lands the new generation.
- [ ] LAW 5: no per-tile mutation of landscape base by any system
      other than `WorldDiffStore`.
- [ ] LAW 8: single owner per data type (table in Architecture).
- [ ] LAW 9: native required, no hidden fallback.
- [ ] LAW 11: dirty units named for substrate, chunk, and tile
      paths.
- [ ] LAW 12: only the existing `WorldPrePass` boot/load exception
      is reused; no second prepass added.
- [ ] ADR-0001: every operation classified.
- [ ] ADR-0002: X wrap-safe at all stages.
- [ ] ADR-0003: base / diff / overlay separation preserved.
- [ ] ADR-0007: worldgen does not read environment runtime.

### J. Spec cleanup grep gate

Before approval and before each code-land closure, grep the spec for
stale legacy wording. The gate passes only when the following cleanup
regexes produce no matches outside this subsection:

- `world_version\s*<=\s*15`
- `legacy generation\s+path`
- `V1/R1B\s+byte-for-byte`
- `CARVED_VALLEY\s+is\s+(a\s+)?owner`
- `landscape_owner\s+\[coarse\]`
- `per-coarse-cell\s+landscape_owner`
- `river_generation\.md.*normative dependency`
- `hard-coded loader defaults apply when.*missing`
- `preserve\s+identity\s+contract`
- `amends\s+two\s+living\s+approved\s+specs`
- `removing\s+or\s+renaming\s+legacy\s+world\s+runtime\s+files`

Historical mentions are allowed only when explicitly marked as
historical context and not used as normative dependency language.

## Implementation Iterations

### L0 - Spec land

Goal: this document. Approval gate before any code.

Scope:
- write this spec;
- update `docs/02_system_specs/world/` index;
- coordinate `WORLD_VERSION = 16` reservation with current owners of
  `world_runtime_constants.gd` (no code change in L0; the version
  number is reserved in writing here);
- no code changes;
- no canonical-doc edits beyond optional cross-links from
  `mountain_generation.md` Status Rationale once approved.

Acceptance:
- spec names every owner, every dirty unit, every budget, every
  setting, every world_version boundary;
- coupled-settings table is binding;
- determinism, persistence, and performance contracts are explicit;
- obsolete-save rejection for `world_version != 16` is explicit;
- spec cleanup grep gate J passes.

### L1 - Native landscape skeleton substrate

Goal: extend `WorldPrePass` with the new substrate fields **without**
yet wiring them to chunk packets.

Scope:
- add `mountain_region_mask`, `ridge_skeleton`,
  `mountain_distance`, `wall_density` (recomputed),
  `foot_density` (recomputed), `valley_score`, new `hydro_height`
  formulation, `routing_cost`, and coarse candidate-index scaffolding to the
  snapshot;
- implement skeleton solve, distance field, routing cost (P5);
- expose dev-only `get_world_foundation_snapshot` layers for each
  new field;
- add overview palette debug variants for the new fields;
- keep the current pre-V16 packet path unchanged behind the development
  integration gate. This path is deleted in L6 when V16 becomes the
  supported path.

Acceptance:
- determinism on every new field;
- substrate budget holds at default settings on all three presets;
- dev overview shows new fields when toggled;
- no change in chunk packet output outside the development integration
  gate, no `WORLD_VERSION` bump yet.

### L2 - Native trunk graph + corridor geometry

Goal: extend the snapshot with `trunk_corridors` and `lake_polygons`
as vector geometry while keeping the current pre-V16 packet path
unchanged behind the development integration gate. This path is deleted
in L6 when V16 becomes the supported path.

Scope:
- depression fill + flow accumulation against the new substrate;
- trunk and tributary selection (CB rules);
- centerline spline + width curve + signed-distance bank
  classification (P3);
- pass-anchor detection on skeletons (CB2, CB3);
- lake polygon construction (CB6, CB7);
- delta / mouth widening tagging (CB8);
- ocean shoreline field: coast noise, bay carving, and mouth-estuary
  geometry (Substrate Extensions section 4b);
- expose trunk and lake geometry in dev-only snapshot API;
- add overview palette layers for trunks, lakes, deltas, passes,
  shoreline, shallow coast, and estuaries;
- still no chunk packet change.

Acceptance:
- determinism;
- visual A/B in dev overview shows expected reference-target shape
  (ribbons, tributaries, irregular lakes, deltas);
- no change in chunk packet output, no `WORLD_VERSION` bump yet.

### L3 - Stage 9a coarse candidate index

Goal: produce `coarse_owner_index` candidate buckets from the geometry
already built in L1 + L2, without making coarse cells authoritative.

Scope:
- build candidate buckets keyed by coarse cell and geometry AABB;
- implement the tile-level owner resolver used by debug validation;
- assert no tile contradiction (CB10);
- expose dev-only overview painter that colours by sampled tile-level
  owner, not by a coarse owner;
- still no chunk packet change.

Acceptance:
- determinism;
- contention rules verified by sample-seed checks;
- pass-anchor coverage per range verified (CB3 hard rule);
- no chunk packet change.

### L4 - V2 chunk rasterization (mountains, integration gate)

Goal: replace the current threshold-noise mountain field in chunk
packets with the L1..L3 substrate-driven mountain assignment behind a
development-only integration gate. Intermediate builds in this sequence
must not create supported saves; `world_version == 16` becomes the only
supported path only after L4 + L5 + L6 pass together.

Scope:
- chunk batch path resolves mountains via tile-level owner (Substrate
  Extensions section 10) under the development integration gate;
- detail noise overlay is the only allowed perturbation
  (P2 step 4 + Substrate Extensions section 11);
- `mountain_id_per_tile` is derived from skeleton-stable inputs
  (`range_id`, `ridge_id`, representative anchor);
- `mountain_flags` preserves the gameplay-facing bit semantics listed
  in Status / Dependencies for excavation, reveal, cover, and cavity /
  opening systems;
- `mountain_presentation_band` and `ridge_orientation_bucket` are
  emitted so mountain atlas selection follows local ridge tangent and
  visible material bands;
- no supported user save format is introduced in L4.

Acceptance:
- mountain shape A acceptance criteria pass under the integration gate;
- chunk batch timing regression `<= 15%` under the integration gate;
- excavation, cavity, opening, and cover lifecycle unchanged.

### L5 - V2 chunk rasterization (rivers, lakes, deltas) (integration gate)

Goal: replace per-segment circle stamping with corridor + lake +
delta rasterization under the development integration gate.

Scope:
- chunk batch path queries `coarse_owner_index`, fetches candidate
  geometry, and runs tile-level signed-distance / point-in-polygon
  classification (Substrate Extensions section 10);
- emit terrain ids `TERRAIN_RIVERBED_SHALLOW`,
  `TERRAIN_RIVERBED_DEEP`, `TERRAIN_LAKEBED_SHALLOW`,
  `TERRAIN_LAKEBED_DEEP`, `TERRAIN_OCEAN_BED_SHALLOW`,
  `TERRAIN_OCEAN_BED_DEEP`;
- resolve ocean tile owners as `DEEP_OCEAN`, `SHALLOW_COAST`, or
  `MOUTH_ESTUARY`; no generic straight `OCEAN_BAND` owner is emitted;
- emit `riverbed_flags` bits `is_riverbed`, `is_lakebed`,
  `is_ocean_directed`, `is_side_channel`, `is_mouth_or_delta`;
- enforce CB4 (corridors never on walls);
- enforce ground `47`-tile bank rule against bed footprints;
- still no supported user save format is introduced before L6.

Acceptance:
- river shape B, lake shape C, and side-channel acceptance criteria
  pass under the integration gate;
- ocean shoreline B2 acceptance criteria pass under the integration
  gate;
- `47`-tile bank rule continues to hold in dry preview;
- determinism acceptance passes under the integration gate (cross-host, after
  the integer-only topology rule);
- no obsolete compatibility path is required or accepted.

### L6 - Carved valley + canyon detail + V16 boundary commit

Goal: implement the "river eats foot" rule and the canyon visual
signature, then **flip the default path** to V2 for new worlds.

Scope (carved valley + canyon):
- corridor crossings of `MOUNTAIN_FOOT` tiles **inside** a
  `pass_anchor` emit `carved_valley_flag` at tile-level resolution;
- chunk rasterization keeps riverbed / river bank as the final owner
  inside the corridor and paints carved surrounding foot as `PLAINS`,
  `VALLEY_FLOOR`, or rocky bank ground as appropriate; corner / seam
  autotile cases are explicitly tested;
- canyon segments narrow `width_shallow` and deepen `width_deep` per
  CB8 / P3 width formulation;
- debug overlay highlights canyon segments.

Scope (V16 boundary commit):
- only after L4 + L5 + L6 pass on the same build, bump
  `WORLD_VERSION` from `15` to `16`;
- V16 becomes the supported default world path;
- new-game flow can create a V16 world using baked default landscape
  settings;
- no full designer-facing landscape slider UI is required in L6;
- old generation paths are deleted in the same task that makes V16 the
  supported path;
- loading any save with `world_version != 16` fails with
  `save format obsolete; start a new world`.

Acceptance:
- canyon section is visually identifiable on at least one reference
  seed: narrow deep channel, narrow shallow shoulder, foot removed
  only inside the corridor, autotile resolves cleanly;
- new worlds at default settings load at `world_version = 16`;
- the `WORLD_VERSION` bump, old generation path deletion, and obsolete
  save rejection land in the same task and are verified together;
- all of mountain shape A, river shape B, ocean shoreline B2, lake
  shape C, coupling D, routing E, determinism F, persistence G
  acceptance pass on a default new world.

### L7 - Coupled settings UI + tuning

Goal: ship the designer-facing `worldgen_settings.landscape` controls
in the new-game UI with the coupled semantics from P6 enforced.

Scope:
- actual coupled landscape sliders / inputs for the `landscape` block;
- map the new-game UI's mountain density / scale / continuity /
  ruggedness controls into `worldgen_settings.landscape` for V16 new
  worlds; no save migration is provided;
- live overview update on slider change (debounce + epoch as today);
- tooltips and A/B preview labels reflecting coupled effects.

Acceptance:
- coupled-behaviour D acceptance criteria pass;
- save-load round-trip preserves slider values exactly.

### L8 - Debug overlays + counters

Goal: complete the dev tuning surface so future amendments can be
authored without re-instrumenting the generator.

Scope:
- overlays: mountain region mask, ridge skeleton, distance field,
  wall density, foot density, valley score, routing cost, downstream
  graph, flow accumulation, basin polygons, trunk corridor, lake
  polygons, deltas, pass anchors, tile-level landscape owner,
  carved_valley_flag;
- counters: ridge count, range count, average ridge length, pass
  anchor count, accepted trunk count, tributary count, side channel
  count, accepted lake count, terminal lake count, delta count,
  total spline sample count, snapshot memory bytes, carved-valley tile
  count per loaded chunk;
- a single dev-mode `landscape_overview` toggle that switches the
  overview canvas to a multi-channel diagnostic palette;
- counters published to `WorldStreamer` debug surfaces consistent
  with existing `roof_layers_per_chunk_max` reporting style.

Acceptance:
- every overlay listed in scope is visible in a dev build;
- every counter is observable on a dev build via the existing
  performance/debug instrumentation seam.

### L9 - Performance gate + closure

Goal: prove every performance acceptance criterion holds on
reference hardware.

Scope:
- profile substrate solve, chunk batch, overview render at
  `small`, `medium`, `large`;
- profile snapshot memory and total spline sample count at `large`
  default settings;
- run determinism cross-host test;
- run X-wrap seam continuity test;
- profile p95 frame time during free-camera traversal of mountain,
  river, and lake regions on a reference seed;
- finalize closure report;
- update canonical docs (`packet_schemas.md`, `system_api.md`,
  `save_and_persistence.md`, `PROJECT_GLOSSARY.md`,
  `terrain_hybrid_presentation.md` if presentation profiles change,
  `world_runtime.md` spawn contract if substrate fields used by
  spawn change names).

Acceptance:
- performance H acceptance criteria pass;
- governance I acceptance criteria pass;
- determinism F acceptance criteria pass.

### Iteration ordering rules

- L1..L3 must land before any chunk-packet behaviour change to keep
  blast radius bounded.
- L4 and L5 must both stay behind a development-only integration gate
  until L6. Either order is allowed; whichever lands second must re-run
  determinism / regression tests of the previous owner.
- L6 must not land before L4 + L5.
- **`WORLD_VERSION` bumps exactly once, at the end of L6**, only
  after mountains, rivers, lakes, side channels, deltas, and carved
  valleys all pass acceptance together on the same build. There is no
  intermediate user-facing V16 world with V2 mountains and V1 rivers.
- L7..L9 may land in any order after L6 and do not bump again unless
  they change canonical output for the same `(seed, settings)`.
- No implementation iteration may add a supported `world_version != 16`
  generation path or a byte-for-byte legacy compatibility acceptance
  gate.

## Files That May Be Touched (when code lands)

Likely new files:

- `gdextension/src/landscape_skeleton.h`
- `gdextension/src/landscape_skeleton.cpp`
- `gdextension/src/ridge_skeleton.h`
- `gdextension/src/ridge_skeleton.cpp`
- `gdextension/src/landscape_routing.h`
- `gdextension/src/landscape_routing.cpp`
- `gdextension/src/river_corridor.h`
- `gdextension/src/river_corridor.cpp`
- `gdextension/src/lake_basin.h`
- `gdextension/src/lake_basin.cpp`
- `gdextension/src/landscape_commit.h`
- `gdextension/src/landscape_commit.cpp`
- `core/resources/landscape_gen_settings.gd`
- `data/balance/landscape_gen_settings.tres` (designer tuning copy
  only; not the loader default of last resort)

Likely modified files:

- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_prepass.h`
- `gdextension/src/world_prepass.cpp`
- `gdextension/src/river_rasterizer.h`
- `gdextension/src/river_rasterizer.cpp`
  (eventually retired in favour of `river_corridor.cpp`)
- `gdextension/src/mountain_field.h`
- `gdextension/src/mountain_field.cpp`
  (mountain field becomes a wrapper over the skeleton + distance
  field; identity logic preserved)
- `core/systems/world/world_runtime_constants.gd`
  (`WORLD_VERSION = 16`, new settings layout indices)
- `core/systems/world/world_streamer.gd`
- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/world_preview_controller.gd`
- `core/systems/world/world_foundation_palette.gd`
- `core/systems/world/world_preview_palette.gd`
- `scenes/ui/new_game_panel.gd`
- `scenes/ui/world_overview_canvas.gd`
- save / load files that own `worldgen_settings.landscape`

Files forbidden:

- `BuildingSystem`, `PowerSystem`, `IndoorSolver`;
- combat, fauna, progression, inventory, crafting, lore;
- subsurface / Z-level runtime;
- environment runtime (weather, season, wind, water overlay - those
  remain future overlay territory);
- save chunk diff shape;
- runtime files outside the listed V2 generation targets;
- ADRs (V2 fits inside the existing ADR stack; no ADR change is
  required by this spec).

## Required Canonical Doc Follow-Ups (when code lands)

Each entry below requires grep-backed confirmation in the closure
report.

- `docs/02_system_specs/meta/packet_schemas.md`: confirm
  `ChunkPacketV2` field set; document new `settings_packed` layout
  for `landscape`; document V2 terrain id constants including
  `TERRAIN_OCEAN_BED_SHALLOW` and `TERRAIN_OCEAN_BED_DEEP`; document
  `landscape_kind` debug field if shipped in release.
- `docs/02_system_specs/meta/save_and_persistence.md`: document
  `worldgen_settings.landscape` for `world_version == 16` and
  obsolete-save rejection for `world_version != 16`.
- `docs/02_system_specs/meta/system_api.md`: document any new public
  read surfaces on `WorldCore` / `WorldStreamer` (e.g.
  `get_world_foundation_snapshot` layer additions).
- `docs/02_system_specs/meta/event_contracts.md`: only if new domain
  events are added.
- `docs/02_system_specs/meta/commands.md`: only if new mutation paths
  are added (none expected in V2).
- `docs/00_governance/PROJECT_GLOSSARY.md`: add terms `Ridge skeleton`,
  `Range / massif`, `Pass / canyon`, `Mountain distance field`,
  `Hydro height`, `Routing cost field`, `Trunk`, `Tributary`,
  `Corridor`, `Lake basin`, `Carved valley`, `Landscape owner`.
- `docs/02_system_specs/world/mountain_generation.md`: replace / split
  the spec. Move reveal / cavity / cover gameplay sections into
  `mountain_interior.md`; remove field-derivation, mountain identity
  derivation, and silhouette packet-shape sections; point to this spec
  as the V16 authority for `mountain_id` derivation and mountain
  silhouette.
- `docs/README.md` and `docs/02_system_specs/README.md`: remove links
  to deleted river specs and add this spec as the current landscape
  generation authority after approval.
- `docs/02_system_specs/world/world_foundation_v1.md`: extend the
  frozen substrate field set to include the V2 additions, with a
  `WORLD_VERSION = 16` note.
- `docs/02_system_specs/world/terrain_hybrid_presentation.md`: extend
  if new presentation profiles are needed for `carved_valley_flag`,
  delta widening, lake islands, or the V2 ocean-bed shallow / deep
  terrain ids.

`not required` is valid only with grep evidence.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Substrate solve breaches budget on `large` preset | Coarse cell sizing is versioned; ridge density is settings-driven; closure gate at L9. |
| Determinism drifts between hosts due to floating-point ordering | Use deterministic neighbour order, fixed-radix sums, integer hashing for skeleton seeds; assert in debug builds. |
| Mountain identity changes break cavity / cover cache | Inside `world_version == 16`, `mountain_id` is freely re-derived from skeleton-stable inputs (`range_id`, `ridge_id`, representative anchor). The cavity cache is runtime-derived and not save-persisted, so a V2 world rebuilds it cleanly on load. Obsolete saves are rejected rather than migrated. |
| Corridor smoothing crosses a wall after the routing pass approves the cell | CB4 enforces post-smoothing wall avoidance; smoothing is iterative with wall pushback; assert if push-back fails. |
| Pass anchor injection (CB3) loops forever on degenerate skeletons | Hard cap the synthetic-pass attempts; if exhausted, reject the landscape candidate before world creation or load publication. Do not demote the range to a fallback topology. |
| Player diff intersects with carved-valley context in unexpected ways | Diff continues to override base; `carved_valley_flag` is base context, not a runtime overlay or owner; mining / building behaves like it does on the final terrain owner. |
| Obsolete world settings drift | Saves with `world_version != 16` are rejected. `worldgen_settings.landscape` is written only for V16 worlds and is required on load. |
| Halo growth doubles chunk batch time | V2 uses a spatial index over snapshot geometry; chunk rasterization classifies only `1024` tiles per chunk regardless of nearby geometry extent. Acceptance H caps regression at `15%`; profiling gate in L9. |
| Premature `WORLD_VERSION` bump leaves V16 in a half-built state | `WORLD_VERSION` bumps only at L6 commit, after L4 + L5 + L6 all pass on the same build. L4 and L5 stay behind a development-only integration gate. No user-facing V16 world ships with V2 mountains and V1 rivers. |
| Coarse candidate bucket is too crude | Stage 9a in V2 is a coarse spatial index, not authoritative. Tile-level owner is resolved inside chunk rasterization (Substrate Extensions section 10). |
| D8 grid leaks into final river geometry | D8 is hydrology base only. Trunk geometry comes from a least-cost corridor solver over the cost field (Substrate Extensions section 7). Spline smoothing must not be the wall-avoidance mechanism. |
| Ridge hard-clip at noise mask boundary produces "chopped" edges | Ridge taper / fade replaces hard clipping at noise-mask boundaries. Hard clip remains only at world Y bounds (Substrate Extensions section 2). |
| Float topology drift across hosts | Topology decisions are integer / fixed-point only. Floats only for local interpolation after topology is fixed. Determinism section is binding. |
| Spawn lands inside corridor / lake / foot under V2 | Spawn acceptance E2 covers all V2 owners. Resolver must be amended in L6 alongside the V16 boundary commit. |
| Polygon offset for banks fails at sharp turns | Banks come from signed-distance classification against the spline, not from polygon offsets (Substrate Extensions section 8). |
| Lake polygons drift back to radial blobs | Lake shape is basin-first, not radial-first; symmetric-difference acceptance rejects radial-blob outlines (Substrate Extensions section 9 + Acceptance C). |
| Designers crank settings beyond intended ranges | Clamp every coupled setting on load; expose tooltip ranges in the UI; keep a binding default block in the loader. |
| Future water overlay breaks against carved valleys | Water overlay reads final tile owner, `riverbed_flags`, and optional `carved_valley_flag`; the flag is context only, so water behavior follows riverbed / lakebed footprints. |
| Visual contrast erodes if river-ground edge stops working | The `47`-tile bank rule is restated in this spec and binding; CB10 contradiction asserts catch any regression. |

## Locked Decisions and Remaining Open Questions

### Decisions already locked

These are binding V2 decisions, not open questions:

1. `LANDSCAPE_COARSE_CELL_TILES = 32`.
2. `LANDSCAPE_MAX_RIDGES_LARGE = 512`.
3. `RIDGE_VERTEX_COUNT_HINT = 64`.
4. `AUTOTILE_MARGIN_TILES = 4`.
5. `SPLINE_GEOMETRY_SAMPLE_STEP_TILES = 0.5`.
6. `WIDTH_BANK_SAMPLE_STEP_TILES = 4`.
7. `LANDSCAPE_SNAPSHOT_MEMORY_BUDGET_MB = 256`.
8. `LANDSCAPE_MAX_SPLINE_SAMPLES_LARGE = 1000000`.
9. `COASTLINE_MIN_Y_VARIATION_TILES = 24`.
10. `COASTLINE_MAX_STRAIGHT_SEGMENT_TILES = 96`.
11. Quantization Table is binding.
12. `landscape_gen_settings.tres` is a designer tuning copy only;
   loader defaults are used only for brand-new world creation. On load,
   missing `worldgen_settings.landscape` is fatal.

### Remaining open questions

Each open question below has its own required decision gate. Only
questions marked **L1 blocker** block L1 start.

1. **L2 gate - `routing_cost_to_height_scale` calibration.** Effective
   drainage uses cost as a height-equivalent term. The numeric scale
   that keeps "one foot cell more expensive than `max_detour_cells`
   valley cells, but cheaper than a wall" is calibrated during L2
   review on sample seeds.
2. **L4 gate - `mountain_id` tuning stability.** V2 hashes
   `mountain_id` from `(seed, world_version, range_id, ridge_id,
   representative_anchor)` for `world_version == 16`. There is no
   retro-migration. The open question is whether the skeleton-derived
   hash is stable across L7 settings tuning, or whether default settings
   must be locked at L6 commit.
3. **L5 gate - side-channel default constants.**
   `side_channel_min_order`, `side_channel_min_offset`,
   `side_channel_max_offset`, `side_channel_lateral_offset`,
   `side_channel_min_island_area_tiles`,
   `side_channel_max_length_factor`, `max_side_channels_per_segment`,
   `side_channel_ratio` need defaults locked before L5 lands.
4. **L6 gate - `is_foot` / `carved_valley_flag_byte` presentation
   decision.** V2 removes `is_foot` from corridor-deep tiles and keeps
   it on the corridor boundary shoulder, so presentation can still
   resolve the carved-cliff transition. Remaining question: whether
   `carved_valley_flag_byte` is enough for presentation or if an
   additional packet bit is needed. Decision in L6 design review.
5. **L9 gate - cross-host cold-run determinism check workflow.** The
   determinism F acceptance requires comparing snapshots across hosts.
   The workflow (build environment, hashes, automated comparison) is not
   yet defined; decision before L9.

## Status Rationale

This spec is `draft` because:

- it deletes / replaces approved generation specs and supersedes the
  historical R1B-Fix amendment; approval requires maintainer sign-off,
  not agent autonomy;
- it bumps `WORLD_VERSION`, which by LAW 4 requires the
  governance owner to confirm the boundary plan;
- it touches the existing `WorldPrePass` LAW 12 exception, which by
  ENGINEERING_STANDARDS LAW 12 requires explicit governance
  acknowledgement;
- it contains performance budgets that require a profiling pass
  before they are binding (L9 closure gate);
- the remaining open questions above block L1 start.

Do not begin L1 implementation while this spec is in `draft`. The
spec-first rule from `WORKFLOW.md` and `AGENTS.md` is binding.

The next safe step is review by the world / runtime owner. Once
approved, status flips to `approved`, source_of_truth flips to
`true`, and L1 may begin.
