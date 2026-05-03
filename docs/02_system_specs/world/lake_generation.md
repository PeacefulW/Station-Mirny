---
title: Lake Generation V1
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 0.5
last_updated: 2026-05-03
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
landed. Current `WORLD_VERSION = 39` includes the 2026-05-03 deterministic
classification and basin-rim correction below. L3 water presentation is landed:
`ChunkView` now owns the derived
`WaterSurfaceLayer`, populated from `lake_flags` and current resolved
`terrain_ids`, with light water over `TERRAIN_LAKE_BED_SHALLOW` and dark water
over `TERRAIN_LAKE_BED_DEEP`. L4 landed `LakeGenSettings` new-game UI,
`worldgen_settings.lakes` persistence, and spawn rejection for substrate coarse
nodes whose `lake_id > 0`.

Amendment 2026-05-03: per-tile lake classification samples
`WorldPrePass.foundation_height` bilinearly at tile centre before applying
shore warp, because `lake_water_level_q16` is encoded in `foundation_height`
units. The basin BFS contract also explicitly forbids a fixed
`center_height + fill_depth` ceiling; the observed rim is dynamic. Because this
changes canonical output for the same seed/settings, active new worlds use
`WORLD_VERSION = 39`; `38` remains the Lake Generation L2 historical boundary.

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
- amended `settings_packed` with six new indices (`15..20`)
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
| Dirty unit | `64`-tile coarse cell for substrate basin solve (re-computed only on world load); `32 x 32` chunk for canonical packet generation; one tile for excavation mutation; one chunk for water presentation refresh on publish/unload. |
| Single owner | `WorldCore` (native) for substrate fields and packet output. `WorldDiffStore` for tile-override diff. `ChunkView` for water presentation layer. `world.json` for `worldgen_settings.lakes`. |
| 10x / 100x scale path | Lake basin solve is bounded-radius local-min plus bounded BFS over the existing coarse grid (medium = `2048` nodes; large = `8192` nodes). No whole-tile pass. Per-tile path adds one bilinear `foundation_height` substrate sample + one FBM warp call inside the existing chunk packet loop. |
| Main-thread blocking? | Forbidden during gameplay. Substrate stays on the world-load worker. Per-tile work stays inside the existing native packet generation. |
| Hidden GDScript fallback? | Forbidden. Native `WorldPrePass` + `WorldCore` are required. Absence asserts under LAW 9. |
| Could it become heavy later? | Bounded by the substrate budget and per-tile cost inside `ChunkPacketV1` generation. New consumers must read existing fields or justify a frozen-set extension via spec amendment. |
| Whole-world prepass? | Permitted under the existing LAW 12 exception for `WorldPrePass`. No separate global pass is introduced; lake solve runs inside the same substrate compute that already exists. |

## Core Contract

### Chunk Geometry

Unchanged: `32 px` tile, `32 x 32` chunk, X wraps per ADR-0002, Y bounded.

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
| `lake_id` | `PackedInt32Array` | `grid_width * grid_height` | `WorldPrePass` | `0` = no lake; non-zero = deterministic lake hash. |
| `lake_water_level_q16` | `PackedInt32Array` | `grid_width * grid_height` | `WorldPrePass` | Fixed-point representation of the rim height in `foundation_height` units. `0` when `lake_id == 0`. |

Both arrays are indexed by coarse node index `y * grid_width + x` to
match every other substrate field.

`lake_water_level_q16` semantics:

- value `q` corresponds to a real water level `q / 65536.0` in the same
  unit as `foundation_height` (`foundation_height` is float; the water
  level is encoded as `int32` to keep determinism stable across
  platforms);
- the encoded float must be reproducible bit-for-bit from `(seed,
  world_version, world_bounds, settings_packed)`;
- it represents the **rim** of the basin, i.e. the lowest point of the
  ring of cells through which water would spill out.

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

Algorithm:

1. **Local-minimum candidate scan.** For each coarse node `(cx, cy)`:
   - skip if `ocean_band_mask = 1`, `burning_band_mask = 1`, or
     `continent_mask = 0`
   - skip if `coarse_wall_density >= mountain_clearance` or
     `coarse_foot_density >= mountain_clearance * 1.5`
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
   Bound the BFS at `lake_max_basin_cells` (default `64`). If the BFS
   would exceed the bound, abort the candidate (likely an ocean-class
   depression).
3. **Reject too small.** If the basin contains fewer than
   `lake_min_basin_cells` (default `2`), drop the candidate.
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
3. Otherwise look up `(lake_id, lake_water_level_q16)` in the substrate
   for the coarse cell containing `(wx, wy)`.
4. If `lake_id == 0`, plains pipeline as today. `lake_flags = 0`.
5. If `lake_id > 0`:
   - decode `water_level = lake_water_level_q16 / 65536.0`
   - compute `tile_foundation_height` by bilinear-sampling
     `WorldPrePass.foundation_height` at the tile centre
     (`wx + 0.5`, `wy + 0.5`) in coarse-grid coordinates, with X wrap
     and Y clamp matching the substrate snapshot. This is the same unit
     as `water_level`.
   - compute `shore_warp = fbm_shore(wx, wy, seed, world_version,
     shore_warp_scale) * shore_warp_amplitude`; this FBM uses a
     dedicated salt distinct from mountain noise
   - compute `effective_elevation = tile_foundation_height + shore_warp`
   - if `effective_elevation >= water_level`, this is shore land (just
     above water): plains pipeline, `lake_flags = 0`
   - if `effective_elevation < water_level`:
     - `depth = water_level - effective_elevation`
     - `relative_depth = depth / max(epsilon, water_level - basin_min_elevation)`
       where `basin_min_elevation` comes from the substrate snapshot
       (smallest `foundation_height` cell inside the basin); native code
       caches this per `lake_id` to avoid recomputing per tile
     - `terrain_id = relative_depth >= deep_threshold ?
       TERRAIN_LAKE_BED_DEEP : TERRAIN_LAKE_BED_SHALLOW`
     - `walkable = (terrain_id == TERRAIN_LAKE_BED_SHALLOW) ? 1 : 0`
     - `lake_flags |= 1 << 0` (water present over this bed)
6. Atlas indices for `TERRAIN_LAKE_BED_SHALLOW` /
   `TERRAIN_LAKE_BED_DEEP` use `autotile_47` against same-class
   neighbours, exactly the existing pattern for plains terrain.

`fbm_shore` rule: low-frequency FBM (2–3 octaves) with input scaled by
`1 / shore_warp_scale`; salt is `seed XOR LAKE_SHORE_SALT`. Output range
is `[-shore_warp_amplitude, +shore_warp_amplitude]`.

This per-tile path adds at most **one substrate read + one FBM call**
per non-mountain tile. Mountain tiles skip the entire branch.

### `lake_flags` Bit Layout

`lake_flags` is a `PackedByteArray` of length `1024` per chunk packet.

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
| `lake_flags` | `PackedByteArray` | `1024` | Per-tile bit field; bit `0` is `is_water_present`. |

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
| `density` | `0.0..1.0` | `0.35` | Acceptance threshold scaling for lake-candidate basins; higher = more accepted candidates per area. |
| `scale` | `64.0..2048.0` | `512.0` | Target average basin diameter in tiles. Drives `lake_seed_search_radius`, `lake_min_basin_cells`, `lake_max_basin_cells` via fixed monotonic mapping documented in `lake_field.cpp`. |
| `shore_warp_amplitude` | `0.0..2.0` | `0.8` | Per-tile shoreline FBM amplitude in `foundation_height` units. |
| `shore_warp_scale` | `8.0..64.0` | `16.0` | Per-tile shoreline FBM wavelength in tiles. |
| `deep_threshold` | `0.05..0.5` | `0.18` | Relative depth (fraction of basin max depth) above which bed becomes `LAKE_BED_DEEP`. |
| `mountain_clearance` | `0.0..0.5` | `0.10` | Minimum permitted `coarse_wall_density` for a basin cell. Above this the cell is treated as mountain-touching and the basin is rejected. Foot density uses `mountain_clearance * 1.5`. |

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
| `21` | `SETTINGS_PACKED_LAYOUT_FIELD_COUNT` | total length, `21` |

Active V1 lake path requires `world_version >= 38` and exactly `21`
packed values. `world_version <= 37` keeps the legacy non-lake field
count and is a historical algorithm boundary; the active pre-alpha
loader rejects non-current `world_version`.

`world.json` shape:

```json
{
  "world_seed": 131071,
  "world_version": 39,
  "worldgen_settings": {
    "world_bounds": { "...": "..." },
    "foundation":   { "...": "..." },
    "mountains":    { "...": "..." },
    "lakes": {
      "density": 0.35,
      "scale": 512.0,
      "shore_warp_amplitude": 0.8,
      "shore_warp_scale": 16.0,
      "deep_threshold": 0.18,
      "mountain_clearance": 0.10
    }
  }
}
```

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
| Water presentation | `ChunkView.water_layer` | One TileMapLayer per chunk; populated from `lake_flags.is_water_present` on publish; chooses `light` vs `dark` water variant by reading the bed terrain underneath. Cleared on chunk unload. |
| Spawn rejection | Existing spawn resolver in `WorldCore` | Reject candidate if its coarse node has `lake_id > 0`. |

### Water Layer Population

- `ChunkView.water_layer` is created lazily on first lake tile in a
  given chunk
- `tile_set` comes from
  `WorldTileSetFactory.get_water_tile_set()`; one shared 47-tile
  presentation resource with two atlases (light, dark)
- on publish, iterate `lake_flags`:
  - if bit `0` set, place a water cell at `(lx, ly)`; pick `light`
    variant if the same-tile bed is `TERRAIN_LAKE_BED_SHALLOW`, otherwise
    `dark`
  - autotile-47 picks corner / edge variants from same-class neighbours
    inside `lake_flags`
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

The current active value is `39`. It advances from `38` because the
2026-05-03 amendment changes deterministic lake classification and basin
rim solve output for the same `(seed, coord, settings)`.

`world_version <= 38` is a historical algorithm boundary and is rejected
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
| Lake basin solve | boot/load (native worker) | coarse `64`-tile grid, bounded local-min + bounded BFS | inside the existing `WorldPrePass` `≤ 900 ms` budget for the largest preset; lake step alone target `≤ 100 ms` on `large` |
| Per-tile classification inside chunk packet | background (native worker) | `32 x 32` chunk | 0 additional native calls beyond one bilinear substrate sample + one FBM call per non-mountain tile; median chunk packet time may grow at most `1 ms` on reference hardware |
| Bed atlas resolution (autotile-47) | background (native worker) | one tile | reuses existing autotile path |
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
- [ ] each of the six `LakeGenSettings` fields produces a measurable
      and visible change when varied alone
- [ ] `world_version` bump produces a reproducibly different output

### Lake Geometry

- [ ] no tile inside any lake basin overlaps `mountain_id > 0` or
      `mountain_flags.is_wall` or `mountain_flags.is_foot`
- [ ] no lake basin overlaps `ocean_band_mask` or `burning_band_mask`
- [ ] no lake basin overlaps `continent_mask = 0`
- [ ] every lake has at least `lake_min_basin_cells` accepted basin
      cells; no orphan single-cell ponds
- [ ] every lake forms a closed bowl with no outflow (no river logic
      in V1)
- [ ] shoreline FBM warp produces visibly organic edges, not coarse
      grid-aligned edges

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
| Substrate basin solve breaks the `≤ 900 ms` budget on `large` preset | Bounded local-min radius and bounded BFS limit cost; profile gate is part of L1 closure. If breached, raise `lake_seed_search_radius` granularity (sample every other coarse cell) without changing the frozen set. |
| Lake straddles a mountain because the per-tile shoreline FBM warps a tile under the rim into a mountain-adjacent zone | Mountain-wins rule at per-tile classification; substrate-level rejection of mountain-touching basins; both are required, neither alone is enough. |
| Water layer leaks across chunk boundaries (visible seams) | Autotile-47 with same-chunk neighbours plus seam refresh on chunk publish. Seam refresh re-evaluates the chunk edge tiles only, not the full layer. |
| Player spawns inside an unreachable lake | Spawn rejection rule + escalation path: deterministic widening of search radius, fail loudly if no candidate found at preset cap. |
| Future drying mechanic accidentally bumps `WORLD_VERSION` because someone tries to put it in base | This spec calls out drying as a runtime overlay; the seam already exists (water layer is presentation-only). Drying spec must reuse it. |
| `LakeGenSettings` settings drift between `tres` and `world.json` after a content patch | Same pattern as `MountainGenSettings`: defaults from `tres` apply only to new worlds; existing saves always read their own copy. |
| Lake basin solve depends on map-iteration order from `std::unordered_map` | Forbid `unordered_map` for the candidate set; use `std::vector` of candidates with explicit deterministic sort. |
| Hash collision on `lake_id` | Deterministic salt sweep until distinct; bounded loop; assert hard if bound exceeded. |

## Open Questions

- exact monotonic mapping from `LakeGenSettings.scale` to
  `lake_seed_search_radius`, `lake_min_basin_cells`,
  `lake_max_basin_cells`. Locked in L1 with a debug-layer review and
  documented in `lake_field.cpp`.
- should the spawn resolver also reject the immediate one-cell ring
  around `lake_id > 0` to prevent literal water-edge spawns? Default
  V1 answer: no; the existing `coarse_valley_score` preference plus the
  in-cell rejection is sufficient. Re-evaluate if playtests show
  problems.

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
  packet field and document `WORLD_VERSION = 38` in the same task as L2
- `docs/02_system_specs/meta/save_and_persistence.md` — add the
  `WORLD_VERSION = 38` boundary in the same task as L2; record
  `worldgen_settings.lakes` as mandatory when L4 closes
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

Changes to the rules above require a new version of this document with
`last_updated` bumped and a changelog entry describing the amendment.
