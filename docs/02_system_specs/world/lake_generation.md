---
title: Lake Generation V1
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.1
last_updated: 2026-05-05
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - world_runtime.md
  - world_foundation_v1.md
  - mountain_generation.md
  - terrain_hybrid_presentation.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - ../meta/system_api.md
---

# Lake Generation V1

## Purpose

Define the canonical extension of the chunked world runtime that introduces
deterministic surface lakes on top of the existing mountain field and
foundation substrate.

This spec is the source of truth for:

- coarse lake-basin identity (`lake_id`) and its frozen-set substrate fields
- per-tile classification of `TERRAIN_LAKE_BED_SHALLOW` and
  `TERRAIN_LAKE_BED_DEEP`
- the per-chunk runtime water presentation layer
- `LakeGenSettings` resource and `worldgen_settings.lakes` persistence
- runtime classification, performance budgets, and dirty units for all of
  the above

This document deliberately follows the same shape as
`mountain_generation.md`. The lake stack is an additive layer on top of
the foundation substrate; it does not modify mountain generation,
foundation channels, or any subsurface owner.

## Status

Approved. V1 landed in four sequential iterations (`L1..L4`) tracked in
`docs/04_spec_iteration/`. L1 substrate fields are in place. L2 bed terrain
ids, `lake_flags`, and the V1 `WORLD_VERSION = 38` packet boundary are
landed. `WORLD_VERSION = 39` includes the 2026-05-03 deterministic
classification and basin-rim correction below. `WORLD_VERSION = 40`
includes the 2026-05-04 V2 / L5 basin-size and connectivity amendment below.
`WORLD_VERSION = 41` includes the 2026-05-04 V2 / L6 cross-cell shoreline
amendment below. `WORLD_VERSION = 42` includes the 2026-05-04 V2 / L7
shore-warp normalisation, connectivity UI, and mandatory persistence
amendment below. `WORLD_VERSION = 43` includes the V3 / L8 lake substrate
boundary, and current `WORLD_VERSION = 44` carries the grid-contract boundary.
L3 water presentation is landed:
`ChunkView` now owns the derived
`WaterSurfaceLayer`, populated from `lake_flags` and current resolved
`terrain_ids`, with light water over `TERRAIN_LAKE_BED_SHALLOW` and dark water
over `TERRAIN_LAKE_BED_DEEP`. The water surface uses one seamless single-tile
texture per shallow/deep variant; authored bank edges are rendered by adjacent
plains ground, not by a water autotile-47 silhouette. L4 landed
`LakeGenSettings` new-game UI,
`worldgen_settings.lakes` persistence, and spawn rejection for substrate coarse
nodes whose `lake_id > 0`.

Amendment 2026-05-03: per-tile lake classification samples
`WorldPrePass.foundation_height` bilinearly at tile centre before applying
shore warp, because `lake_water_level_q16` is encoded in `foundation_height`
units. The basin BFS contract also explicitly forbids a fixed
`center_height + fill_depth` ceiling; the observed rim is dynamic. Because this
changed canonical output for the same seed/settings, that amendment introduced
`WORLD_VERSION = 39`; `38` remains the Lake Generation L2 historical boundary.

Amendment 2026-05-04 (V2 / L5): basin size now maps from
`LakeGenSettings.scale` using the larger `lake_max_basin_cells` and
`lake_min_basin_cells` formulas below, and `LakeGenSettings.connectivity`
drives a deterministic basin-merge pass for neighbouring basins with similar
rim heights. Because this changes canonical substrate output for the same
`(seed, world_version, world_bounds, settings_packed)`, active new worlds use
`WORLD_VERSION = 40`; `39` remains the previous lake-classification
correction boundary.

Amendment 2026-05-04 (V2 / L6): per-tile lake classification now reads the
`3×3 neighbourhood` of coarse substrate cells around each tile and chooses
one deterministic best applicable lake before running the existing
`foundation_height + shore_warp < water_level` test. Spawn rejection uses the
same neighbour selection and effective-elevation test. Because this changes
canonical packet contents and spawn output for the same
`(seed, world_version, world_bounds, settings_packed)`, active new worlds use
`WORLD_VERSION = 41`; `40` remains the V2 / L5 basin-connectivity boundary.

Amendment 2026-05-04 (V2 / L7): `shore_warp_amplitude` is now interpreted as
a fraction of chosen basin depth rather than an absolute `foundation_height`
offset. `fbm_shore` returns dimensionless FBM in `[-1.0, 1.0]`, and callers
apply `fbm_unit * shore_warp_amplitude * basin_depth`. New worlds default
`shore_warp_amplitude` to `0.4` in range `0.0..1.0`, the new-game panel exposes
`LakeGenSettings.connectivity`, and `worldgen_settings.lakes.connectivity` is
mandatory for `world_version >= 42`. Because this changes canonical packet and
spawn output for the same `(seed, world_version, world_bounds,
settings_packed)`, active new worlds use `WORLD_VERSION = 42`; `41` remains the
V2 / L6 cross-cell shoreline boundary.

Amendment 2026-05-04 (V3 / L8): canonical lake substrate moves from
"strict local-min seed + bounded watershed BFS" to
"elevation-threshold mask + face-connected-component labeling on the
substrate coarse grid". Lake basin identity becomes a face-connected
component of below-water-level coarse cells with size at least
`min_lake_component_cells(scale)`, mirroring the structural pattern that
already drives mountain identity in `mountain_generation.md` (with the
inequality reversed). `LakeGenSettings.density` is reinterpreted as
target submerged-area fraction outside reject zones, and
`LakeGenSettings.scale` is reinterpreted as minimum lake component
diameter in tiles. `LakeGenSettings.connectivity` becomes a no-op for
`world_version >= 43` because the connected-component pass already
delivers natural connectivity; the field remains in `LakeGenSettings`,
`settings_packed`, and `worldgen_settings.lakes` for save-shape stability
but does not affect canonical output. Because this changes canonical
substrate fields, packet contents, terrain ids, walkable flags, lake
flags, and spawn output for the same `(seed, world_version, world_bounds,
settings_packed)`, active new worlds use `WORLD_VERSION = 43`; `42`
remains the historical V2 / L7 shore-warp normalisation boundary.
Amendment 2026-05-05 (grid-contract boundary): active new worlds now use
`WORLD_VERSION = 44` for the `64 px` tile / `16 x 16` chunk contract.
Lake algorithms from `43` are unchanged, but packet arrays now contain
`256` entries and chunk-diff sharding follows the new chunk footprint.

## Gameplay Goal

The player must be able to:

- see deterministic, organically shaped lakes generated from
  `world_seed + world_version + worldgen_settings.{world_bounds,foundation,mountains,lakes}`
- never see a lake tile that overlaps a mountain wall, mountain foot, an
  ocean band, a burning band, or reserved non-land massing
- walk into a lake and step on shallow water tiles freely, while the deep
  centre stays impassable
- read the water surface as a lighter-blue ring over shallow beds and a
  darker-blue interior over deep beds, even before any surface ripples or
  shaders ship
- tune lake density and lake size at world creation through a "water
  sector" panel mirroring the existing mountain panel, and have the
  settings travel with the save
- recognise lakes on the new-game world overview as coloured patches
  consistent with the gameplay world

The water presentation layer is intentionally separate from the lake bed
terrain so that a future drying mechanic (ADR-0007 environment runtime)
can mask water away tile-by-tile without rewriting `terrain_ids` and
without bumping `WORLD_VERSION`. After drying the bed remains as
canonical worldgen output.

## Scope (V1)

V1 is an **additive** extension of `world_runtime.md` + `mountain_generation.md`
+ `world_foundation_v1.md`. It adds:

- two new substrate fields on the existing `WorldPrePass` snapshot:
  `lake_id`, `lake_water_level_q16`
- a deterministic native lake-basin solve on the existing coarse `64`-tile
  grid, executed on the existing world-load worker path
- two new gameplay terrain ids: `TERRAIN_LAKE_BED_SHALLOW` and
  `TERRAIN_LAKE_BED_DEEP`
- one additive packet field on `ChunkPacketV1`: `lake_flags`
- one bit semantics on `lake_flags` (bit `0` = `is_water_present`)
- one new presentation `TileMapLayer` per chunk: `water_layer`
- two new presentation profiles for shallow/deep bed plus one shape set
  + material set for the water layer (light/dark variants chosen
  deterministically from the bed under the tile)
- `LakeGenSettings` resource + `worldgen_settings.lakes` section in
  `world.json`
- amended `settings_packed` with seven lake indices (`15..21`)
- `WORLD_VERSION` bump from `37` to `38` when L2 lands gameplay terrain
  ids and the `lake_flags` packet field
- amendment to the spawn contract from `world_foundation_v1.md`:
  candidate spawn tiles inside any `lake_id > 0` coarse node are rejected

## Out of Scope (V1)

V1 does not include:

- rivers, streams, deltas, river graph, flow accumulation, Strahler order,
  hydraulic erosion. These belong to a future hydrology spec, not V1.
- lake drying / water level fluctuation / seasonal drainage. Those are
  environment-runtime concerns (ADR-0007) and live in their own future
  spec; V1 only guarantees the architectural seam (separate water layer)
  that lets that mechanic ship later without re-touching base packet.
- waves, foam, ripples, reflective shaders. Presentation is flat
  light/dark tiles in V1.
- swimming, drowning, oxygen interaction with water, water-based combat.
- water as a resource (filling canisters, hydration, irrigation). Future
  content layer.
- subsurface water, aquifers, springs, cave lakes. ADR-0006 keeps surface
  and subsurface separate; V1 stays on `z = 0`.
- ocean-class water. The `ocean_band_mask` already exists on substrate
  but renders no water tile in V1; lakes do not bridge into ocean bands.
- rivers connecting lakes. Unrelated. A lake in V1 is a closed bowl with
  no outflow.
- migration of pre-`world_version = 38` saves. Active pre-alpha policy
  rejects non-current `world_version`.

## Dependencies

- `world_runtime.md` for `ChunkPacketV1` boundary, `WorldCore` ownership,
  `WorldStreamer` lifecycle, and the existing chunk publish path.
- `world_foundation_v1.md` for the `WorldPrePass` substrate, frozen-set
  rules, coarse-cell alignment (`64` tiles), and the existing
  `settings_packed` layout (indices `0..14`).
- `mountain_generation.md` for `mountain_id_per_tile`, `mountain_flags`,
  and the existing mountain-wins classification branch. Lake shoreline
  classification reuses the same mountain sample only to decide whether
  the mountain pipeline wins; water-level comparison uses
  `WorldPrePass.foundation_height` in substrate units.
- ADR-0001 for runtime work classes and dirty-update rules.
- ADR-0002 for cylindrical X wrap; lake basins must be wrap-safe on X.
- ADR-0003 for immutable base + runtime diff; lake bed terrain is base,
  any future drying is overlay, never base mutation.
- ADR-0006 for surface / subsurface separation; V1 lakes are surface only.
- ADR-0007 for keeping worldgen distinct from environment runtime; the
  water presentation layer is part of worldgen output but is **read-only**
  for environment runtime, which may later mask tiles without writing
  back into the packet.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical, runtime overlay, or visual only? | Lake basin identity, water level, bed terrain ids, and the `lake_flags` bit are canonical. The water presentation layer is visual only, derived from base packet. Future drying is runtime overlay. |
| Save/load required? | Yes, for `worldgen_settings.lakes` in `world.json`. No for substrate; substrate is RAM-only and regenerated from seed. No for water presentation; it is derived. Diff still persists per-tile `terrain_id + walkable` overrides as today. |
| Deterministic? | Yes. `lake_id`, `lake_water_level_q16`, bed terrain ids, and `lake_flags` are pure `f(seed, world_version, world_bounds, settings_packed)`. |
| Must work on unloaded chunks? | Yes. Canonical lake data is recomputable from base + diff on demand. |
| C++ compute or main-thread apply? | Lake basin solve, per-tile classification, bed atlas indices, and `lake_flags` are native (`WorldPrePass` + `WorldCore`). Water layer cell placement and per-chunk tile upload are main-thread apply, sliced through `FrameBudgetDispatcher.CATEGORY_STREAMING`. |
| Dirty unit | `64`-tile coarse cell for substrate basin solve (re-computed only on world load); `16 x 16` chunk for canonical packet generation; one tile for excavation mutation; one chunk for water presentation refresh on publish/unload. |
| Single owner | `WorldCore` (native) for substrate fields and packet output. `WorldDiffStore` for tile-override diff. `ChunkView` for water presentation layer. `world.json` for `worldgen_settings.lakes`. |
| 10x / 100x scale path | For `world_version >= 43`, lake substrate solve is one eligible-height sort plus one union-find connected-component pass over the existing coarse grid (medium = `2048` nodes; large = `8192` nodes). For `world_version <= 42`, the historical path is bounded-radius local-min plus bounded BFS. No whole-tile pass. Per-tile path adds one bounded `3×3` coarse-cell lake lookup, one bilinear `foundation_height` substrate sample, one dimensionless FBM warp call, and one multiplication by basin depth inside the existing chunk packet loop. |
| Main-thread blocking? | Forbidden during gameplay. Substrate stays on the world-load worker. Per-tile work stays inside the existing native packet generation. |
| Hidden GDScript fallback? | Forbidden. Native `WorldPrePass` + `WorldCore` are required. Absence asserts under LAW 9. |
| Could it become heavy later? | Bounded by the substrate budget and per-tile cost inside `ChunkPacketV1` generation. New consumers must read existing fields or justify a frozen-set extension via spec amendment. |
| Whole-world prepass? | Permitted under the existing LAW 12 exception for `WorldPrePass`. No separate global pass is introduced; lake solve runs inside the same substrate compute that already exists. |

## Core Contract

### Chunk Geometry

Unchanged relative to the active grid contract: `64 px` tile, `16 x 16` chunk,
X wraps per ADR-0002, Y bounded.

### Terrain IDs

V1 adds two surface terrain ids:

| Id constant | Integer value | Walkable | Used for |
|---|---|---|---|
| `TERRAIN_LAKE_BED_SHALLOW` | `5` | `1` | Lake bed shallow zone, including the shore ring around every lake. Player walks across freely. Future iterations may add slowdown / SFX as a runtime overlay; that is not part of V1. |
| `TERRAIN_LAKE_BED_DEEP` | `6` | `0` | Lake bed deep zone, the impassable interior of a lake. Blocks movement and line-of-sight the same way `TERRAIN_MOUNTAIN_WALL` blocks them. |

Constants live in `core/systems/world/world_runtime_constants.gd` and the
mirrored native definitions in `gdextension/src/world_core.cpp`.

These ids are stable for the lifetime of the spec; renumbering requires
an amendment.

### Substrate Field Extension

`world_foundation_v1.md` defines a frozen field set. V1 amends that frozen
set with two additive fields. No existing field is renamed, removed, or
reshaped.

| Field | Type | Length | Owner | Notes |
|---|---|---|---|---|
| `lake_id` | `PackedInt32Array` | `grid_width * grid_height` | `WorldPrePass` | `0` = no lake; non-zero = deterministic lake hash. For `world_version >= 43`, identity is a face-connected component of below-threshold eligible cells; for `world_version <= 42`, identity is a bounded watershed basin. |
| `lake_water_level_q16` | `PackedInt32Array` | `grid_width * grid_height` | `WorldPrePass` | Fixed-point water value in `foundation_height` units. For `world_version >= 43`, this is the component-uniform water threshold; for `world_version <= 42`, this is the watershed rim height. `0` when `lake_id == 0`. |

Both arrays are indexed by coarse node index `y * grid_width + x` to
match every other substrate field.

`lake_water_level_q16` semantics:

- value `q` corresponds to a real water level `q / 65536.0` in the same
  unit as `foundation_height` (`foundation_height` is float; the water
  level is encoded as `int32` to keep determinism stable across
  platforms);
- the encoded float must be reproducible bit-for-bit from `(seed,
  world_version, world_bounds, settings_packed)`;
- encoding is exactly `round(rim_height * 65536.0)` with no lake-local
  clamp. `world_foundation_v1.md` owns the invariant that
  `foundation_height` is already clamped to `[0, 1]`;
- for `world_version <= 42`, it represents the **rim** of the basin,
  i.e. the lowest point of the ring of cells through which water would
  spill out;
- for `world_version >= 43`, it represents the component-uniform
  submerged-area threshold selected from eligible `foundation_height`
  values.

### Lake Basin Solve

`WorldPrePass` runs one bounded native solve on the existing coarse grid
during the same world-load worker pass it already uses for the other
substrate fields.

Inputs:

- finished `latitude_t`, `ocean_band_mask`, `burning_band_mask`,
  `continent_mask`, `foundation_height`, `coarse_wall_density`,
  `coarse_foot_density`, `coarse_valley_score`
- unpacked `LakeGenSettings` (see Settings below)
- world bounds and `seed + world_version`

Basin-shape mapping:

- `d = scale / COARSE_CELL_SIZE_TILES`, where
  `COARSE_CELL_SIZE_TILES = 64` from `world_prepass.h`
- `lake_seed_search_radius = clamp(round(d / 2.5), 1, 8)`
- `lake_max_basin_cells = clamp(round(d * d), 4, 4096)`
- `lake_min_basin_cells = clamp(round(d * d / 16), 2, 64)`

Algorithm:

1. **Local-minimum candidate scan.** For each coarse node `(cx, cy)`:
   - skip if `ocean_band_mask = 1`, `burning_band_mask = 1`, or
     `continent_mask = 0`
   - skip if `coarse_wall_density >= mountain_clearance` or
     `coarse_foot_density >= mountain_clearance * 1.5`
   - apply `density` as a deterministic Bernoulli mask: skip if the
     seed-derived `hash_unit(seed, world_version, cx, cy) > density`
   - mark as candidate if `foundation_height(cx, cy)` is the strict
     minimum within a square of radius `lake_seed_search_radius`
     (default `3`) on coarse grid, with X wrap-safe
2. **Bounded basin BFS from each candidate.** Starting at the candidate,
   BFS up the gradient field (`foundation_height` increasing). Each
   accepted cell:
   - has `foundation_height < rim_height_so_far`
   - is not in any reject mask above
   - is on the same connected component (4-neighbour, X wrap-safe)
   `rim_height_so_far` is the lowest dynamically observed spill rim
   around the growing basin. A fixed `center_height + fill_depth`
   ceiling is forbidden because it is not a watershed rim.
   Basins must not touch Y bounds: if 4-neighbour growth would leave
   `[0, grid_height - 1]`, reject the candidate. X still wraps.
   Bound the BFS at `lake_max_basin_cells`. If the BFS
   would exceed the bound, abort the candidate (likely an ocean-class
   depression).
3. **Reject too small.** If the basin contains fewer than
   `lake_min_basin_cells`, drop the candidate.
4. **Reject mountain-touching.** If any cell on the basin's outer ring
   has `coarse_wall_density >= mountain_clearance` or
   `coarse_foot_density >= mountain_clearance * 1.5`, drop the
   candidate. This is the hard "do not cross mountains" guarantee.
5. **Compute rim height.** `rim_height = min over rim cells of
   foundation_height`, where rim cells are the first ring of accepted
   cells around the basin interior. Encode as
   `lake_water_level_q16 = round(rim_height * 65536.0)`.
6. **Assign identity.** `lake_id = hash(seed, world_version,
   representative_cell_origin, basin_cell_count)`. The representative
   cell is the BFS root. Hash collisions across two basins in the same
   world must be resolved by a deterministic salt sweep until distinct;
   document the loop bound in code comments.
7. **Write fields.** For every accepted basin cell, write `lake_id`
   and `lake_water_level_q16`. Other cells stay at `0`.
8. **Deterministic basin merge.** After all initial basins are written,
   compute neighbouring basin pairs from the completed `lake_id` array,
   the `connectivity` setting, and the rim heights recorded during the
   solve. Two basins `A` and `B` merge iff they touch on at least one
   shared 4-neighbour edge of coarse cells, with X wrapping, and
   `|rim_height_A - rim_height_B| < merge_height_tolerance`, where
   `merge_height_tolerance = lerp(0.0, 0.06, connectivity)` in
   `foundation_height` units. The surviving `lake_id` is the id whose
   basin has the lower BFS root index (`y * grid_width + x`); the merged
   `lake_water_level_q16` is `round(min(level_A, level_B) * 65536.0)`.
   Candidate pairs are sorted by `(min_lake_id, max_lake_id)`, merged in
   that order, and the pass repeats until a pass produces zero merges or
   `merge_iteration_cap = 16` is reached. If `connectivity == 0.0`, the
   merge pass is a no-op.

Determinism rule: candidates and BFS order must be fully deterministic
from the inputs above. No reliance on `randf()`, no reliance on
multi-threaded order, no reliance on hash-map iteration order.

Wrap-safety rule: every cell access uses `wrap_x(cx, grid_width)`.

### Per-Tile Classification

Per-tile work happens inside `WorldCore::_generate_chunk_packet` after
mountain resolution. For each tile `(lx, ly)` in the chunk:

1. Reuse the mountain-field sample already taken for this tile or halo
   sample. This sample is used only for the mountain branch.
2. **Mountain wins.** If `mountain_id_per_tile[i] > 0`, the tile keeps
   the mountain pipeline output (`TERRAIN_MOUNTAIN_WALL` /
   `TERRAIN_MOUNTAIN_FOOT`). Lake fields stay at zero.
3. Otherwise scan the `3×3 neighbourhood` of substrate coarse cells around
   the tile's containing cell `(cx-1..cx+1, cy-1..cy+1)`. X wraps per
   ADR-0002, and Y is clamped with `clamp_foundation_world_y`.
4. Among neighbours with `lake_id > 0` and
   `lake_water_level_q16 > 0`, pick the best applicable lake by:
   highest `lake_water_level_q16`; ties broken by lowest `lake_id`; second
   tie broken by deterministic neighbour priority
   `(0,0), (0,-1), (1,0), (0,1), (-1,0), (-1,-1), (1,-1), (1,1), (-1,1)`.
   If no neighbour qualifies, the tile keeps the plains pipeline and
   `lake_flags = 0`.
5. If a neighbour lake qualifies:
   - decode `water_level = lake_water_level_q16 / 65536.0`
   - compute `tile_foundation_height` by bilinear-sampling
     `WorldPrePass.foundation_height` at the tile centre
     (`wx + 0.5`, `wy + 0.5`) in coarse-grid coordinates, with X wrap
     and Y clamp matching the substrate snapshot. This is the same unit
     as `water_level`.
   - look up `basin_min_elevation` from the existing native `WorldCore`
     lookup for the chosen `lake_id`; native code caches this per `lake_id`
     to avoid recomputing per tile
   - compute `basin_depth = max(epsilon, water_level - basin_min_elevation)`
   - compute dimensionless `fbm_unit = clamp(fbm_shore(wx, wy, seed,
     world_version, shore_warp_scale), -1.0, 1.0)`; this FBM uses a
     dedicated salt distinct from mountain noise and applies no amplitude
     internally
   - compute `shore_warp = fbm_unit * shore_warp_amplitude * basin_depth`
   - compute `effective_elevation = tile_foundation_height + shore_warp`
   - if `effective_elevation >= water_level`, this is shore land (just
     above water): plains pipeline, `lake_flags = 0`
   - if `effective_elevation < water_level`:
     - `depth = water_level - effective_elevation`
     - `relative_depth = depth / basin_depth`
     - `terrain_id = relative_depth >= deep_threshold ?
       TERRAIN_LAKE_BED_DEEP : TERRAIN_LAKE_BED_SHALLOW`
     - `walkable = (terrain_id == TERRAIN_LAKE_BED_SHALLOW) ? 1 : 0`
     - `lake_flags |= 1 << 0` (water present over this bed)
6. Atlas indices for `TERRAIN_LAKE_BED_SHALLOW` /
   `TERRAIN_LAKE_BED_DEEP` use `autotile_47` against same-class
   neighbours. Adjacent `TERRAIN_PLAINS_GROUND` uses `autotile_47`
   only against shallow/deep lake-bed neighbours so dry ground draws the
   visible bank edge next to water; mountain neighbours must not open
   ground edges.

Lake classification is only allowed after the tile's own mountain solve has
resolved to plains. A tile whose own mountain branch resolves to wall or foot
must not be converted to lake terrain by a neighbouring basin; mountain-wins
is the hard tiebreaker.

`fbm_shore` rule: low-frequency FBM (2 octaves) with input scaled by
`1 / shore_warp_scale`; salt is `seed XOR LAKE_SHORE_SALT`. Output range is
dimensionless `[-1.0, +1.0]`. Amplitude is applied only by the caller as a
fraction of the chosen basin depth.

This per-tile path adds at most **one `3×3` substrate lookup + one bilinear
sample + one FBM call + one multiplication by basin depth** per non-mountain
tile. Mountain tiles skip the entire branch.

### Mass Lake Generation V3 Pipeline (`world_version >= 43`)

V3 / L8 replaces the V1 / V2 watershed BFS basin solve with an
elevation-threshold mask plus face-connected-component labeling on the
existing substrate coarse grid. The substrate fields written into
`WorldPrePass.lake_id` and `WorldPrePass.lake_water_level_q16` keep their
shape, length, owner, and frozen-set membership; only the algorithm that
produces those values changes.

The V1 / V2 algorithm is retained as a reference (see "Lake Basin Solve"
above) and remains the source of truth for `world_version <= 42`. The
active pre-alpha loader rejects pre-`world_version = 43` saves; the V1 /
V2 description stays in this spec as historical record only.

V3 / L8 pipeline runs on the same world-load worker pass as the V1 / V2
solve. Nothing else in the lake stack changes: per-tile classification,
`lake_flags` bit layout, `ChunkPacketV1` shape, water presentation,
excavation, and `LakeGenSettings` save shape are unchanged.

#### Inputs

Same as V1 / V2:

- finished `latitude_t`, `ocean_band_mask`, `burning_band_mask`,
  `continent_mask`, `foundation_height`, `coarse_wall_density`,
  `coarse_foot_density`, `coarse_valley_score`
- unpacked `LakeGenSettings` (see "Worldgen Settings" below for V3 / L8
  semantics)
- world bounds and `seed + world_version`

#### Reject Mask

Identical to V1 / V2 reject rules. A coarse cell `(cx, cy)` is rejected
from the lake mask iff at least one of:

- `ocean_band_mask = 1`
- `burning_band_mask = 1`
- `continent_mask = 0`
- `coarse_wall_density >= mountain_clearance`
- `coarse_foot_density >= mountain_clearance * 1.5`

Mountain-wins remains the hard tiebreaker.

#### Step 1 — Submerged-Area Threshold

`density` is reinterpreted as **target submerged-area fraction outside
reject zones**.

1. Collect `eligible_heights[]` = sorted ascending list of
   `foundation_height[i]` for every coarse cell `i` that is **not** in the
   reject mask above. X-wrap and Y-bounds rules from
   `world_foundation_v1.md` apply.
2. Compute `lake_water_threshold` =
   `eligible_heights[clamp(round(density * (eligible_heights.size() - 1)), 0, eligible_heights.size() - 1)]`,
   i.e. the `density` percentile of eligible cell heights. When
   `eligible_heights` is empty (all cells rejected), the threshold is
   `-infinity` and no lake is produced.
3. `density = 0.0` produces no submerged cells (threshold below all
   eligible cells); `density = 1.0` floods every eligible cell up to the
   highest non-reject height.

This reuses the same density-as-area-fraction shape that mountain
generation uses for its elevation mask, and replaces V1 / V2 Bernoulli
candidate gating.

#### Step 2 — Lake Mask

For every coarse cell `(cx, cy)`:

- `is_lake_candidate(cx, cy) = !is_reject_cell(cx, cy) && foundation_height(cx, cy) < lake_water_threshold`

The lake mask is fully deterministic from substrate and settings.

#### Step 3 — Face-Connected-Component Labeling

Run one deterministic single-pass union-find over the substrate coarse
grid using 4-neighbour face connectivity, X-wrap-safe per ADR-0002, with
Y bounded per `world_foundation_v1.md`. Iteration order is row-major
(`y * grid_width + x`), and union order is fixed: north neighbour first,
then west neighbour, both gated by `is_lake_candidate`.

Each connected component starts with a tentative numeric label.
Components whose accepted cell count is below
`min_lake_component_cells(scale)` are discarded by clearing all their
cells back to `lake_id = 0`. Mapping:

- `d = scale / COARSE_CELL_SIZE_TILES`, where
  `COARSE_CELL_SIZE_TILES = 64` (unchanged from V1 / V2)
- `min_lake_component_cells = clamp(round(d), 1, 4096)`

There is no `max_lake_component_cells`. A component the size of a
continent is allowed; this is the deliberate "giant lakes as giant
mountains" outcome.

Forbidden labeling implementations:

- diagonal-only contact must not connect two components, exactly as
  mountain identity rules in `mountain_generation.md`
- iteration order that depends on hash-map order, multi-threaded order,
  or `std::unordered_map` traversal is forbidden under the same rule
  V1 / V2 already documents

#### Step 4 — Per-Component Output

For every surviving component:

- choose a deterministic representative cell as the lowest row-major
  index `i = y * grid_width + x` among the component's cells
- assign `lake_id = hash(seed, world_version, representative_index, component_cell_count)`
  using the same salt sweep as the V1 / V2 path; collisions resolved by
  bounded deterministic salt advancement, document the loop bound in
  code comments
- compute the per-component water level:
  - `lake_water_level_q16 = round(lake_water_threshold * 65536.0)`
  - all surviving components share the same canonical `lake_water_level_q16`,
    because the threshold is component-uniform by construction
- compute the per-component basin minimum:
  - `basin_min_elevation = min over component cells of foundation_height`
  - this drives `basin_depth = max(epsilon, water_level - basin_min_elevation)`
    inside per-tile classification, exactly the same way V1 / V2 used it
- write `lake_id` and `lake_water_level_q16` into every component cell.
  Other cells stay at `0`

The native `BasinMinElevationLookup` cache stays as the per-`lake_id`
substrate lookup that per-tile classification already consumes; the
lookup builder is unchanged.

#### Step 5 — Connectivity Setting (`LakeGenSettings.connectivity`)

`connectivity` becomes a no-op for canonical output at
`world_version >= 43`. The face-connected-component pass already delivers
natural connectivity: cells reachable through the lake mask join the same
`lake_id` automatically.

`connectivity` remains:

- in `LakeGenSettings` (range `0.0..1.0`, default `0.4`) for save-shape
  stability — `worldgen_settings.lakes.connectivity` stays mandatory for
  `world_version >= 42` and is still written for new `world_version >= 43`
  saves
- in `settings_packed[21]` so `settings_packed.size() == 22` is preserved
- visible on the new-game panel — its label/tooltip copy must explicitly
  document the no-op behaviour for V3 worlds; the slider stays exposed
  rather than removed to avoid an L9-shaped UI/save churn

The previous V1 / V2 `merge_lake_basins` pass (deterministic neighbour
merge by rim-height tolerance) is removed for `world_version >= 43`.

#### Step 6 — Per-Tile Classification (Unchanged)

Per-tile classification reads `lake_id` and `lake_water_level_q16` through
the same `3×3 neighbourhood` lookup landed in V2 / L6, applies the same
bilinear `foundation_height` sample at tile centre, the same dimensionless
`fbm_shore` call, and the same
`shore_warp = fbm_unit * shore_warp_amplitude * basin_depth` formula
landed in V2 / L7. Mountain-wins remains the hard tiebreaker.

The per-component `basin_min_elevation` lookup is what makes
`shore_warp` and `relative_depth` continue to scale per lake even under
the new component-uniform water level. Shallow components stay shallow
(`basin_depth` small), deep components stay deep (`basin_depth` large),
and `deep_threshold` continues to split shallow shore from deep
interior.

#### Step 7 — Determinism, Wrap, Bound Rules

Same as V1 / V2:

- substrate budget `≤ 900 ms` total on the largest preset; lake step
  target `≤ 120 ms` on `large`
- candidate ordering, label assignment order, and component-id pick are
  fully reproducible from `(seed, world_version, world_bounds, settings_packed)`
- X uses `wrap_x(cx, grid_width)`; Y is bounded
- assertion fails fast on label-collision salt-sweep exhaustion

#### What V3 / L8 Removes Compared to V1 / V2

- strict local-min candidate scan (`is_strict_local_minimum`)
- bounded watershed BFS (`build_basin`, `pop_lowest_frontier`,
  `queue_frontier_neighbours`, `has_lower_unaccepted_neighbour`)
- `lake_seed_search_radius`, `lake_max_basin_cells`,
  `lake_min_basin_cells` mapping
- `merge_lake_basins` and the `connectivity`-driven rim-height merge pass

The V1 / V2 basin-shape-mapping section above is retained as historical
record for `world_version <= 42`; native code may delete the V1 / V2
solve path once the active pre-alpha loader is confirmed to reject all
pre-`world_version = 43` saves.

### `lake_flags` Bit Layout

`lake_flags` is a `PackedByteArray` of length `256` per chunk packet.

| Bit | Name | Meaning |
|---|---|---|
| `1 << 0` | `is_water_present` | Water surface present over this bed tile. Set iff per-tile classification placed this tile under the rim. Always `0` on non-lake tiles, mountain tiles, and shore tiles. |
| `1 << 1` | reserved | Future use, must be `0` in V1. |
| `1 << 2` | reserved | Future use, must be `0` in V1. |
| `1 << 3` | reserved | Future use, must be `0` in V1. |
| `1 << 4..7` | reserved | Must be `0` in V1. |

### `ChunkPacketV1` Extension

`ChunkPacketV1` keeps every existing field. V1 lakes add **one** field:

| Field | Type | Length | Notes |
|---|---|---|---|
| `lake_flags` | `PackedByteArray` | `256` | Per-tile bit field; bit `0` is `is_water_present`. |

Forbidden V1 packet fields:

- `lake_id_per_tile` (substrate is already authoritative; per-tile id is
  reconstructible from substrate read in any consumer that needs it)
- `lake_water_level_per_tile` (same reasoning; substrate is the truth)
- water-velocity, current, flow, drift, hydration data (out of scope)

### Worldgen Settings

`LakeGenSettings` is a `Resource` with the following exported fields and
ranges:

| Field | Range | Default | Meaning |
|---|---|---|---|
| `density` | `0.0..1.0` | `0.35` | For `world_version >= 43`: target submerged-area fraction of eligible (non-reject) coarse cells. For `world_version <= 42`: deterministic Bernoulli mask over seed-derived candidate hashes; higher = more accepted candidates per area. |
| `scale` | `64.0..2048.0` | `512.0` | For `world_version >= 43`: minimum lake component diameter in tiles, mapped to `min_lake_component_cells = clamp(round(scale / 64), 1, 4096)`. Components smaller than this are dropped from the mask. For `world_version <= 42`: target average basin diameter driving the V1 / V2 watershed search. |
| `shore_warp_amplitude` | `0.0..1.0` | `0.4` | Fraction of chosen basin depth applied as shoreline FBM warp. `0` is a sharp shoreline; `1` is the most jagged shoreline. Same semantics for V1 / V2 / V3. |
| `shore_warp_scale` | `8.0..64.0` | `16.0` | Per-tile shoreline FBM wavelength in tiles. Same semantics for V1 / V2 / V3. |
| `deep_threshold` | `0.05..0.5` | `0.18` | Relative depth (fraction of basin max depth) above which bed becomes `LAKE_BED_DEEP`. Same semantics for V1 / V2 / V3. |
| `mountain_clearance` | `0.0..0.5` | `0.10` | Minimum permitted `coarse_wall_density` for a lake-mask cell. Above this the cell is treated as mountain-touching and excluded from the lake mask. Foot density uses `mountain_clearance * 1.5`. Same semantics for V1 / V2 / V3. |
| `connectivity` | `0.0..1.0` | `0.4` | For `world_version >= 43`: no-op for canonical output, retained for save-shape stability and `settings_packed` length. The new-game UI must surface a tooltip describing the no-op behaviour. For `world_version <= 42`: similarity tolerance for the V1 / V2 deterministic neighbour-merge pass. |

Defaults live in `data/balance/lake_gen_settings.tres`. They apply only
to new worlds; existing saves always load the embedded copy from
`world.json`.

`settings_packed` extension:

| Index | Constant | Source field |
|---|---|---|
| `15` | `SETTINGS_PACKED_LAYOUT_LAKE_DENSITY` | `density` |
| `16` | `SETTINGS_PACKED_LAYOUT_LAKE_SCALE` | `scale` |
| `17` | `SETTINGS_PACKED_LAYOUT_LAKE_SHORE_WARP_AMPLITUDE` | `shore_warp_amplitude` |
| `18` | `SETTINGS_PACKED_LAYOUT_LAKE_SHORE_WARP_SCALE` | `shore_warp_scale` |
| `19` | `SETTINGS_PACKED_LAYOUT_LAKE_DEEP_THRESHOLD` | `deep_threshold` |
| `20` | `SETTINGS_PACKED_LAYOUT_LAKE_MOUNTAIN_CLEARANCE` | `mountain_clearance` |
| `21` | `SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY` | `connectivity` |
| `22` | `SETTINGS_PACKED_LAYOUT_FIELD_COUNT` | total length, `22` |

Current active lake path requires `world_version >= 44` (grid-contract
boundary on top of V3 / L8) and
exactly `22` packed values. `world_version <= 43` keeps historical
algorithm / grid layouts and is rejected by the active pre-alpha loader.
`settings_packed` shape and length do not change at the V3 / L8 boundary;
only the algorithmic interpretation of `density`, `scale`, and
`connectivity` changes.

`world.json` shape:

```json
{
  "world_seed": 131071,
  "world_version": 44,
  "worldgen_settings": {
    "world_bounds": { "...": "..." },
    "foundation":   { "...": "..." },
    "mountains":    { "...": "..." },
    "lakes": {
      "density": 0.35,
      "scale": 512.0,
      "shore_warp_amplitude": 0.4,
      "shore_warp_scale": 16.0,
      "deep_threshold": 0.18,
      "mountain_clearance": 0.10,
      "connectivity": 0.4
    }
  }
}
```

For `world_version >= 42`, all seven `worldgen_settings.lakes` fields above are
mandatory, including `connectivity`. The mandatory-fields rule survives
the V3 / L8 boundary unchanged: `worldgen_settings.lakes.connectivity` is
written and read for new `world_version >= 43` saves even though it is a
canonical no-op, to keep save shape stable across the L7 → L8 boundary.

## Runtime Architecture

### Native Boundary

Same surface as today. No new native class is introduced.

```text
WorldCore.generate_chunk_packets_batch(
    seed: int,
    coords: PackedVector2Array,
    world_version: int,
    settings_packed: PackedFloat32Array
) -> Array
```

Rules:

- one batch returns one extended `ChunkPacketV1` per coord (with
  `lake_flags`)
- `WorldPrePass::Snapshot` exposes `lake_id` and
  `lake_water_level_q16` arrays alongside existing fields
- `_generate_chunk_packet` reads substrate via the existing
  `_get_or_build_world_prepass(...)` path, no new native API
- `resolve_world_foundation_spawn_tile` (V1-R1B native API) gains a
  new rejection rule: candidate's coarse node must satisfy
  `lake_id == 0`. The rest of the surface is unchanged.

### Script Ownership

| Role | Owner | Responsibility |
|---|---|---|
| Substrate basin solve | `WorldPrePass` (native) | Compute `lake_id`, `lake_water_level_q16` once per world load. |
| Per-tile classification | `WorldCore` (native) | Emit `terrain_ids`, `walkable_flags`, `terrain_atlas_indices`, `lake_flags` for lake tiles. |
| Diff | `WorldDiffStore` | Unchanged. Player can dig a deep bed tile; the override goes through the same path as plains digging. |
| Chunk orchestration | `WorldStreamer` | Forward `lake_flags` to `ChunkView`. Persist `LakeGenSettings` in `world.json`. |
| Bed presentation | `ChunkView` | Place `TERRAIN_LAKE_BED_SHALLOW` / `TERRAIN_LAKE_BED_DEEP` cells on the existing base layer using `autotile_47` against same-class neighbours. |
| Ground bank presentation | `ChunkView` | Place `TERRAIN_PLAINS_GROUND` cells with water-only `autotile_47` edges when adjacent to shallow or deep lake beds; mountain adjacency stays solid ground. |
| Water presentation | `ChunkView.water_layer` | One TileMapLayer per chunk at terrain z-order; populated from `lake_flags.is_water_present` on publish; chooses a seamless single-tile `light` vs `dark` texture by reading the bed terrain underneath. Cleared on chunk unload. |
| Spawn rejection | Existing spawn resolver in `WorldCore` | Reject candidate if its coarse node has `lake_id > 0`. |

### Water Layer Population

- `ChunkView.water_layer` is created lazily on first lake tile in a
  given chunk
- `tile_set` comes from
  `WorldTileSetFactory.get_water_tile_set()`; two single-tile
  presentation sources (light, dark) backed by authored water textures
- on publish, iterate `lake_flags`:
  - if bit `0` set, place a water cell at `(lx, ly)`; pick `light`
    variant if the same-tile bed is `TERRAIN_LAKE_BED_SHALLOW`, otherwise
    `dark`
  - water atlas coordinates are always `(0, 0)`; water does not build
    autotile-47 corner or edge variants
- the layer stays at terrain z-order so actors render above shallow water
- on chunk unload, `ChunkView.queue_free` destroys the water layer
- runtime water masking (future drying mechanic) toggles per-tile
  visibility through a shader/material state, not by mutating
  `terrain_ids` or `lake_flags`. V1 ships only the layer; the masking
  surface is a future spec.

### Streaming and Apply

- lake packet output rides the existing V0/V1 chunk publish path
- water layer population is part of the same sliced publish loop
- no new `FrameBudgetDispatcher` category; reuse `CATEGORY_STREAMING`
- `TileMapLayer.clear()` remains forbidden on runtime mutation paths
- adjacency-dependent visual recompute around a single mutated tile
  follows the existing local-patch rule from `world_runtime.md`

### Excavation

V0 mutation path is unchanged in shape. When the player digs a
`TERRAIN_LAKE_BED_DEEP` tile:

- a single tile override is written to `WorldDiffStore` exactly as for
  plains
- `ChunkView` recomputes the bounded local visual patch around the tile
- the water layer for that chunk re-evaluates the affected tile only
  (one cell update, not a chunk-wide rebuild)
- `lake_flags.is_water_present` for the diff'd tile remains `0` after
  the bed is dug to a non-lake terrain, because the diff terrain id is
  no longer in the lake-bed set; native does not see lake_flags after
  diff apply, so the water layer reads from the chunk view's current
  resolved terrain map

## Persistence Contract

### `world.json` Extension

L4 contract: `worldgen_settings.lakes` is mandatory for the current
lake-generation save boundary. Runtime generation for an existing world uses
the embedded save copy rather than the repository default resource.

- new game writes the resource's values exactly once into
  `world.json`, then never re-reads `data/balance/lake_gen_settings.tres`
  for that world
- missing `worldgen_settings.lakes` for current `world_version` fails
  load, exactly like missing mountain or foundation settings
- missing `worldgen_settings.lakes.connectivity` for `world_version >= 42`
  fails load before chunk diffs are applied
- editing `data/balance/lake_gen_settings.tres` after a save exists
  must not retroactively change that save

### `chunks/*.json` Unchanged

`ChunkDiffV0` shape is unchanged. Forbidden additions:

- `lake_id`
- `lake_water_level`
- `lake_flags`
- any other derived presentation state

A dug lake bed tile persists exactly the same way a dug plains tile
does today: one `(local_x, local_y, terrain_id, walkable)` entry.

### `WORLD_VERSION`

`WorldRuntimeConstants.WORLD_VERSION` bumped from `37` to `38` when L2
landed, because canonical packet output (`terrain_ids`, `walkable_flags`,
`lake_flags`) changed for the same `(seed, coord)`.

The current active value is `44`. It advances from `43` because the
grid contract changes to `64 px` tiles and `16 x 16` chunks, changing packet
length and chunk-diff sharding without changing the lake algorithm itself.

`world_version <= 43` is a historical algorithm / grid boundary and is rejected
by the active pre-alpha loader.

`world_version` remains a plain integer; it is **not** a hash of
`worldgen_settings.lakes`.

## Event Contract

V1 reuses existing world signals only:

- `world_initialized(seed_value: int)`
- `chunk_loaded(chunk_coord: Vector2i)`
- `chunk_unloaded(chunk_coord: Vector2i)`

No lake-specific `EventBus` signal is introduced. Future drying / water
runtime overlays will introduce their own signals in their own spec.

## Performance Class

| Operation | Class | Dirty unit | Budget |
|---|---|---|---|
| Lake substrate solve | boot/load (native worker) | coarse `64`-tile grid; for `world_version >= 43` a single percentile-threshold pass plus one deterministic union-find face-connected-component pass; for `world_version <= 42` bounded local-min + bounded BFS + deterministic merge cap `16` | inside the existing `WorldPrePass` `≤ 900 ms` budget for the largest preset; lake step target `≤ 120 ms` on `large` |
| Per-tile classification inside chunk packet | background (native worker) | `16 x 16` chunk | 0 additional native calls beyond one bilinear substrate sample + one FBM call per non-mountain tile; median chunk packet time may grow at most `1 ms` on reference hardware |
| Bed atlas resolution (autotile-47) | background (native worker) | one tile | reuses existing autotile path |
| Ground bank atlas resolution (autotile-47) | background (native worker) / local runtime patch | one tile plus adjacent loaded patch | checks shallow/deep lake-bed neighbours only; does not inspect mountain neighbours |
| Water layer population | background apply (sliced) | one chunk | shares `CATEGORY_STREAMING` budget; no separate budget |
| Excavation mutation | interactive | one tile + bounded local patch | unchanged from V0 budget |
| Spawn rejection check | boot/load (native) | one coarse node | trivial |

### Forbidden Runtime Paths

- per-tile `set_cell` for water layer outside the existing publish slice
- main-thread water layer rebuild on chunk unload (must be `queue_free`)
- water layer touched by any system other than `ChunkView`
- substrate basin solve outside the world-load worker pass (`WorldPrePass`
  exception only)
- GDScript fallback for any lake compute when native is unavailable
- per-tile recompute of `mountain_field.sample_elevation` separately for
  the lake branch — mountain elevation must stay the existing
  mountain-wins input, while lake water-level comparison uses bilinear
  `foundation_height`
- adding water rendering through a particle system or shader-only
  approach that bypasses the per-chunk water layer
- treating water as authoritative for walkability — walkability is on
  the bed terrain id

## Acceptance Criteria

### Determinism

- [ ] same `(seed, world_version, world_bounds, settings_packed)`
      yields identical `lake_id`, `lake_water_level_q16`, `terrain_ids`,
      `walkable_flags`, `lake_flags` across sessions and hosts
- [ ] each of `density`, `scale`, `shore_warp_amplitude`,
      `shore_warp_scale`, `deep_threshold`, and `mountain_clearance`
      produces a measurable and visible change when varied alone
- [ ] for `world_version <= 42`, varying `connectivity` produces a
      measurable difference at fixed seed (V1 / V2 historical
      acceptance)
- [ ] for `world_version >= 43`, varying `connectivity` produces no
      measurable difference in canonical output at fixed seed; the
      no-op contract is testable
- [ ] `world_version` bump produces a reproducibly different output

### V3 / L8 Scale Coverage

- [ ] at `scale = 64..256` and `density = 0.1..0.4`, lakes appear as
      small isolated patches in the lowest eligible cells
- [ ] at `scale = 512..1024` and `density = 0.3..0.6`, lakes appear as
      mid-size connected components covering tens of coarse cells each
- [ ] at `scale = 1536..2048` and `density = 0.4..0.7`, lakes appear as
      continent-spanning connected components consistent with the
      mountain-range visual scale
- [ ] sweeping `scale` from `64` to `2048` at fixed `density` and
      fixed seed produces a monotonic, visually continuous change in
      submerged area (no "vanishing lakes" gap in the middle of the
      range)

### Lake Geometry

- [ ] no tile inside any lake overlaps `mountain_id > 0` or
      `mountain_flags.is_wall` or `mountain_flags.is_foot`
- [ ] no lake overlaps `ocean_band_mask` or `burning_band_mask`
- [ ] no lake overlaps `continent_mask = 0`
- [ ] for `world_version <= 42`, every lake has at least
      `lake_min_basin_cells` accepted basin cells; no orphan
      single-cell ponds
- [ ] for `world_version >= 43`, every lake is one face-connected
      component of cells with `is_lake_candidate = true`, with size
      at least `min_lake_component_cells(scale)`; no orphan
      single-cell ponds below the threshold
- [ ] for `world_version <= 42`, every lake forms a closed bowl with
      no outflow (no river logic in V1)
- [ ] for `world_version >= 43`, lakes are not required to form
      closed watershed bowls; the canonical shape is "below-threshold
      connected component", not "watershed basin"
- [ ] shoreline FBM warp produces visibly organic edges, not coarse
      grid-aligned edges
- [ ] lake outlines do not snap to coarse-cell boundaries; visual
      inspection at the new-game preview shows organic edges across
      coarse-cell seams
- [ ] no tile in the `3×3 neighbourhood` of any lake cell becomes
      water unless `bilinear(foundation_height) + shore_warp <
      chosen_water_level`

### Bed Classification

- [ ] every lake has a continuous `LAKE_BED_SHALLOW` ring around its
      `LAKE_BED_DEEP` interior
- [ ] every cell with `relative_depth >= deep_threshold` is
      `LAKE_BED_DEEP`; every cell with `0 < relative_depth <
      deep_threshold` is `LAKE_BED_SHALLOW`
- [ ] `walkable_flags` is `1` for `LAKE_BED_SHALLOW` and `0` for
      `LAKE_BED_DEEP`
- [ ] no `LAKE_BED_SHALLOW` cell is fully enclosed by `LAKE_BED_DEEP`
      cells (sanity: the shallow ring is connected to the shore)

### Water Presentation

- [ ] water layer renders only on tiles with
      `lake_flags.is_water_present`
- [ ] water variant is `light` over `LAKE_BED_SHALLOW` and `dark` over
      `LAKE_BED_DEEP`
- [ ] water layer uses single-tile atlas coordinates only; 47-tile bank
      edges belong to adjacent plains ground, not to water
- [ ] water layer renders below actors so the player is visually above
      shallow water
- [ ] water layer is destroyed on chunk unload, not leaked
- [ ] no main-thread frame builds the entire water layer in one pass
      (publish stays sliced)

### Excavation

- [ ] digging a `LAKE_BED_DEEP` tile persists the override exactly like
      digging plains terrain
- [ ] the dug tile no longer renders water on top after the publish
      slice handles the patch
- [ ] excavation does not trigger a chunk-wide water layer rebuild
- [ ] save/load round-trip preserves the dug tile and recomputes water
      presentation correctly

### Spawn

- [ ] across a sample of seeds in each preset, the spawn resolver never
      emits a spawn tile with `lake_id > 0`
- [ ] when a lake covers the natural spawn area, the resolver finds an
      adjacent dry tile or fails with the documented error

### Persistence

- [ ] new game writes `worldgen_settings.lakes` exactly once into
      `world.json`
- [ ] loading a current-version save without
      `worldgen_settings.lakes` fails loudly before chunk diffs are
      applied
- [ ] editing the repository's `lake_gen_settings.tres` does not change
      an existing save's lake layout
- [ ] loading a current-version save without
      `worldgen_settings.lakes.connectivity` fails loudly before chunk
      diffs are applied
- [ ] no `lake_*` field appears in any `chunks/*.json`

### Performance

- [ ] substrate compute total budget on `large` preset stays ≤ 900 ms
- [ ] per-tile lake classification adds ≤ 1 ms median to chunk packet
      generation on reference hardware
- [ ] interactive lake-bed dig completes within the existing V0 budget
      for a single tile mutation
- [ ] no measurable regression in V0 / V1 acceptance tests when
      `worldgen_settings.lakes.density = 0.0`

### Governance Compliance

- [ ] LAW 4: `WORLD_VERSION` bump landed in the same task as L2
- [ ] LAW 5: lake bed terrain is canonical; water presentation never
      writes back into base or diff
- [ ] LAW 6: substrate fields and packet fields cross the native
      boundary in one packet, not per-tile callbacks
- [ ] LAW 9: no GDScript fallback for any lake compute
- [ ] ADR-0006: lake generation does not touch `z != 0`
- [ ] ADR-0007: lake generation does not read environment runtime
- [ ] `world_foundation_v1.md` frozen-set amendment landed alongside L1

## Modding / Extension Points

- adding a new bed terrain class requires a spec amendment plus a new
  terrain id and a new presentation profile registered through
  `terrain_presentation_registry.gd`
- modders may add water shaders / atlas overrides by registering
  alternative `TerrainShapeSet` / `TerrainMaterialSet` resources for
  the water shape set
- modders may not change the basin solve algorithm or the
  `lake_flags` bit layout

## Failure Cases / Risks

| Risk | Mitigation |
|---|---|
| Substrate solve breaks the `≤ 900 ms` budget on `large` preset | For `world_version <= 42` bounded local-min radius and bounded BFS limit cost. For `world_version >= 43` the percentile threshold is one sort + one linear scan and the union-find is `O(N · α(N))` over coarse cells; profile gate is part of L8 closure. If breached, switch the percentile pass to a bucketed-counting approach without changing canonical output. |
| Lake straddles a mountain because the per-tile shoreline FBM warps a tile under the rim into a mountain-adjacent zone | Mountain-wins rule at per-tile classification; substrate-level rejection of mountain-touching cells from the lake mask; both are required, neither alone is enough. |
| Water layer leaks across chunk boundaries (visible seams) | Water uses seamless single-tile textures, so cross-chunk water autotile seams are not computed. Visible bank seams are owned by ground atlas indices generated from the same packet border and by the bounded local visual patch after tile diffs. |
| Player spawns inside an unreachable lake | Spawn rejection rule + escalation path: deterministic widening of search radius, fail loudly if no candidate found at preset cap. |
| Future drying mechanic accidentally bumps `WORLD_VERSION` because someone tries to put it in base | This spec calls out drying as a runtime overlay; the seam already exists (water layer is presentation-only). Drying spec must reuse it. |
| `LakeGenSettings` settings drift between `tres` and `world.json` after a content patch | Same pattern as `MountainGenSettings`: defaults from `tres` apply only to new worlds; existing saves always read their own copy. |
| Lake substrate solve depends on map-iteration order from `std::unordered_map` | Forbid `unordered_map` traversal for any output-shaping data: candidates, components, summaries. Use `std::vector` with explicit deterministic sort, or a sorted lookup vector with `std::lower_bound`, exactly the pattern V2 / L7 already enforces. |
| Hash collision on `lake_id` | Deterministic salt sweep until distinct; bounded loop; assert hard if bound exceeded. |
| V3 / L8 connected component covers a continent and pulls the spawn into water | Existing spawn rejection through `is_water_at_world_from_neighbour_lake` already filters water tiles regardless of component size; tested by `_assert_l6_spawn_tiles_are_not_published_water` smoke regression, extended for L8 cases. |
| V3 / L8 percentile threshold collapses to a constant when the eligible set is small (high-mountain world) | Native code returns `lake_water_threshold = -infinity` and emits zero lakes deterministically; documented in `lake_field.cpp` and asserted in smoke regression. |

## Open Questions

- (Closed by V3 / L8) exact monotonic mapping from
  `LakeGenSettings.scale` to V1 / V2 `lake_seed_search_radius`,
  `lake_min_basin_cells`, `lake_max_basin_cells`. Historical only;
  V3 / L8 maps `scale` directly to `min_lake_component_cells` and
  drops the V1 / V2 mapping.
- should the spawn resolver also reject the immediate one-cell ring
  around `lake_id > 0` to prevent literal water-edge spawns? Default
  V1 / V2 / V3 answer: no; the existing `coarse_valley_score`
  preference plus the in-cell rejection is sufficient. Re-evaluate if
  playtests show problems.
- should `connectivity` be repurposed for V3 / L8 (e.g. as a "merge
  components separated by ≤ 1 reject cell" bridging tolerance) instead
  of staying a no-op? Default V3 / L8 answer: stay a no-op until a
  concrete gameplay need surfaces; reopening this is a separate spec
  amendment, not an L8 task.

## Implementation Iterations

V1 ships as four iterations. Detailed implementation prompts for each
live in `docs/04_spec_iteration/`:

- L1 — Substrate basin solve and `LakeGenSettings` backend
  (`lake_generation_L1_substrate_basin_solve.md`)
- L2 — Bed terrain ids, `lake_flags` packet field, `WORLD_VERSION` 37→38
  (`lake_generation_L2_bed_terrain_packet.md`)
- L3 — Water presentation layer + light/dark variants
  (`lake_generation_L3_water_presentation_layer.md`)
- L4 — `LakeGenSettings` UI, persistence, spawn contract amendment
  (`lake_generation_L4_settings_ui_persistence_spawn.md`)

V2 amendments shipped as three sequential algorithm-only iterations
inside the existing L1..L4 surface (no UI restructuring):

- L5 — Larger basin-size mapping and connectivity-driven neighbour
  merge (`WORLD_VERSION` 39→40)
- L6 — Cross-cell `3×3` shoreline classification and matching spawn
  rejection (`WORLD_VERSION` 40→41)
- L7 — Shore-warp normalisation by basin depth and mandatory
  `worldgen_settings.lakes.connectivity` persistence
  (`WORLD_VERSION` 41→42)

V3 ships as one algorithm-only iteration:

- L8 — Replace V1 / V2 watershed BFS with elevation-threshold mask
  plus face-connected-component labeling. Preserves
  `LakeGenSettings` schema, `settings_packed` layout,
  `worldgen_settings.lakes` save shape, `ChunkPacketV1` shape,
  per-tile classification, water presentation, and excavation.
  Bumps `WORLD_VERSION` 42→43 because canonical substrate fields,
  packet contents, and spawn output change for the same
  `(seed, world_version, world_bounds, settings_packed)`. Detailed
  implementation prompt:
  `docs/04_spec_iteration/lake_generation_L8_mask_connected_components.md`
  (to be authored alongside L8 closure).

## Files That May Be Touched (Cross-Iteration List)

### New
- `core/resources/lake_gen_settings.gd`
- `data/balance/lake_gen_settings.tres`
- `gdextension/src/lake_field.h`
- `gdextension/src/lake_field.cpp`
- `data/terrain/shape_sets/lake_bed_shallow.tres`
- `data/terrain/shape_sets/lake_bed_deep.tres`
- `data/terrain/shape_sets/water_surface.tres`
- `data/terrain/material_sets/lake_bed_shallow.tres`
- `data/terrain/material_sets/lake_bed_deep.tres`
- `data/terrain/material_sets/water_surface_light.tres`
- `data/terrain/material_sets/water_surface_dark.tres`
- `data/terrain/presentation_profiles/lake_bed_shallow.tres`
- `data/terrain/presentation_profiles/lake_bed_deep.tres`
- `data/terrain/presentation_profiles/water_surface.tres`

### Modified
- `gdextension/src/world_prepass.h`
- `gdextension/src/world_prepass.cpp`
- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/world_streamer.gd`
- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `core/systems/world/world_foundation_palette.gd`
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_appliers.gd`
- `scenes/ui/new_game_panel.gd`

## Files That Must Not Be Touched

- `BuildingSystem`, `PowerSystem`, `IndoorSolver`
- combat, fauna, progression, inventory, crafting, lore systems
- subsurface (`z != 0`), underground fog, cave generation
- environment runtime (weather, season, wind, temperature)
- mountain field internals beyond reading the per-tile sample already
  computed in the chunk packet loop
- foundation substrate fields other than the two new lake fields
- `ChunkDiffV0` shape
- legacy world runtime files from the pre-rebuild stack

## Required Canonical Doc Follow-Ups When Code Lands

- `docs/02_system_specs/world/world_foundation_v1.md` — amend the
  frozen substrate field set with `lake_id` and `lake_water_level_q16`
  in the same task as L1
- `docs/02_system_specs/meta/packet_schemas.md` — add `lake_flags`
  packet field and document `WORLD_VERSION = 38` in the same task as L2;
  document the `WORLD_VERSION = 40` algorithm boundary when V2 / L5 lands;
  document the `WORLD_VERSION = 41` cross-cell shoreline boundary when V2 /
  L6 lands; document the `WORLD_VERSION = 42` shore-warp normalisation
  boundary when V2 / L7 lands; document the `WORLD_VERSION = 43`
  V3 / L8 mask + connected-component algorithm boundary when L8 lands
- `docs/02_system_specs/meta/save_and_persistence.md` — add the
  `WORLD_VERSION = 38` boundary in the same task as L2; record
  `worldgen_settings.lakes` as mandatory when L4 closes; record
  `worldgen_settings.lakes.connectivity` and the `WORLD_VERSION = 40`
  boundary when V2 / L5 lands; record the `WORLD_VERSION = 41` algorithm
  boundary when V2 / L6 lands; record the `WORLD_VERSION = 42` persistence
  boundary when V2 / L7 lands; record the `WORLD_VERSION = 43` V3 / L8
  algorithm boundary and the `connectivity`-stays-no-op clause when L8
  lands
- `docs/02_system_specs/world/world_foundation_v1.md` — when V3 / L8
  lands, update the `lake_id` / `lake_water_level_q16` field
  description so `lake_water_level_q16` reads "component-uniform water
  level threshold for `world_version >= 43`, watershed rim height for
  `world_version <= 42`"; the frozen field set itself does not change
- `docs/02_system_specs/meta/system_api.md` — only if any new public
  reading surface is introduced (no by default; spawn API surface
  unchanged in shape)
- `docs/02_system_specs/meta/event_contracts.md` — `not required`
  expected; document with grep evidence at L4 closure
- `docs/02_system_specs/meta/commands.md` — `not required` expected
  (excavation does not gain a new command in V1)
- `docs/00_governance/PROJECT_GLOSSARY.md` — add `Lake basin`,
  `Lake water level`, `Lake bed shallow`, `Lake bed deep`,
  `Water presentation layer` entries when L3 closes

`not required` entries must be accompanied by grep evidence against the
relevant doc at the time of landing.

## Status Rationale

This draft is approved for staged implementation because:

- the architecture follows the proven `mountain_generation.md` pattern
  (coarse identity + per-tile evaluation + packet enrichment + presentation
  layer + settings persistence)
- every Law 0 question has an explicit answer
- every new field, bit, and index is named in advance, so cross-iteration
  drift is bounded
- a clear "mountain wins" tiebreaker prevents the lake / mountain
  pipelines from corrupting one another
- the water presentation layer is separate from base by design, so a
  future drying mechanic does not retroactively break this spec
- L1..L4 acceptance gates are testable in isolation

V3 / L8 amendment is approved for staged implementation because:

- it tightens the structural symmetry with `mountain_generation.md`:
  mountains are "elevation > threshold + connected components",
  lakes become "elevation < threshold + connected components"; the
  same labeling discipline applies to both
- it removes the V1 / V2 size-vs-shape mismatch that prevented giant
  lakes at high `scale` (the gameplay outcome triggering the
  amendment) without touching `LakeGenSettings` schema, save shape,
  packet shape, presentation, or excavation
- substrate budget stays inside the existing `≤ 900 ms` envelope by
  using one sort + one linear scan + one union-find pass over the
  same `≤ 8192` coarse-cell grid
- per-tile classification, shore warp, deep-threshold ring, mountain
  wins, spawn rejection, and water presentation are all reused
  unchanged
- backward compatibility with `world_version <= 42` saves is not
  required (active pre-alpha policy already rejects them); the
  V1 / V2 algorithm description stays only as historical record

Changes to the rules above require a new version of this document with
`last_updated` bumped and a changelog entry describing the amendment.
