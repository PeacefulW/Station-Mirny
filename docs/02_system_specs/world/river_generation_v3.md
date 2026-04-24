---
title: River Generation V3
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-04-24
supersedes:
  - river_generation.md (v0.3)
  - river_generation_hydrology_addendum.md (v0.1)
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
  - mountain_generation.md
  - terrain_hybrid_presentation.md
---

# River Generation V3

## Status and Supersession

V3 replaces `river_generation.md` v0.3 and its hydrology addendum v0.1. Both
are retained as historical context but are **not** source of truth once this
spec reaches `approved`.

The reason V3 exists:
- V2 + addendum required hydrology semantics (global flow accumulation,
  tributary merging, no-crossings) but permitted only macro-local solves with
  `halo = 1`. That contract is physically inconsistent for any river longer
  than two macros.
- Several beauty requirements (no sharp turns, no blobs, no unnatural
  straight lines, controlled islands, terminal seas) were not expressible
  with the V2 routing constants.
- Debug surfaces required by the addendum had no delivery channel.

V3 resolves these by splitting generation into **three bounded tiers** and
adding explicit beauty contracts enforceable by automated checks.

## Purpose

Define the canonical river layer on top of the existing mountain runtime,
such that:

1. Rivers are physically plausible: they flow downhill, tributaries merge,
   routes never cross as rails, width grows with accumulated flow.
2. Rivers are visually beautiful: natural curves, no sharp corners, no
   blob-like shapes, controlled meander amplitude, occasional islands,
   optional terminal seas.
3. Generation is deterministic from `(seed, world_version, settings)` and
   does not require whole-world per-frame or per-chunk work.
4. First-pass generation emits **dry riverbeds only**; water is a later
   overlay that may be removed by a drought mechanic without destroying
   the channel.

## Gameplay Goal

The player must be able to:

- create a new world with long, winding rivers that flow **between** mountain
  ranges, hugging the relief instead of slicing through it;
- see channels narrow through tight passes and widen where the land opens;
- occasionally see a river split around a vegetated island and rejoin
  downstream;
- occasionally see several rivers merge into one large terminal sea at a
  basin bottom;
- walk across shallow riverbeds whether they are dry or water-covered;
- be blocked by deep riverbeds whether they are dry or water-covered;
- see dry riverbeds remain visible during future drought states instead of
  disappearing with the water;
- preview river amount, width, sinuosity, and branching without blocking the
  worldgen UI;
- stream through the world with rivers enabled without any new class of
  per-frame or whole-world interactive work.

## Design Principles

**Beauty is not negotiable.** Performance is achieved by caching, bounded
work tiers, and native compute — not by weakening the visual contract.

**One bounded global pass is allowed.** V2 forbade whole-world prepass to
protect the interactive runtime. V3 permits a **single coarse global pass at
world load** (Tier 0) because:

- it is O(world_area / coarse_cell²) with `coarse_cell = 128` tiles, giving
  `64 × 64 = 4096` nodes for an `8192 × 8192` world — trivially fast in
  native code;
- it runs once, off-main-thread, during the world-load phase (behind the
  existing load progress UI);
- its output lives in RAM only and is regenerated deterministically from the
  seed on every load; no disk schema changes;
- it does not run during streaming, chunk publish, or preview slider drags.

This is distinct from the forbidden pattern of recomputing the world every
frame or every chunk request. The ADR-0001 runtime-work discipline is
preserved.

**Three tiers of generation, each bounded:**

| Tier | Scope | Runs when | Work class |
|---|---|---|---|
| **0 World skeleton** | Whole world, coarse `128`-tile grid | Once at world load | Native, background worker, ≤200ms target |
| **1 Macro detail** | One aligned `1024`-tile macro + halo | On-demand, cached | Native, background worker, per-macro |
| **2 Chunk rasterization** | One chunk, 32×32 tiles | On each packet batch request | Native, background worker, per-batch |

Tier 0 provides global truth (downstream graph, flow accumulation, trunk
network, merge topology). Tier 1 refines centerlines inside a macro using
Tier 0 as hard boundary constraints. Tier 2 writes final tile data.

This eliminates the V2 contradiction: Tier 1 no longer needs to discover
global topology from a halo-limited view — Tier 0 already resolved it.

## Pattern References

The hydrology and curve design draws from established patterns:

- **GIS D8 flow direction + flow accumulation** (standard digital-elevation
  hydrology): each node picks one of 8 neighbors as downstream based on
  elevation; flow accumulates along the directed graph. Guarantees tree
  topology and correct tributary merges.
- **Priority-flood depression filling** (Barnes et al. 2014): deterministic
  resolution of local minima without random walkers.
- **Strahler stream order**: ranks channels by tributary hierarchy. Used
  here to decide which stems are eligible for islands or splits (order ≥ 2
  only).
- **Catmull-Rom / Chaikin smoothing**: widely used in procedural curves
  (Azgaar's fantasy map generator, RedBlobGames terrain articles). Produces
  natural flowing curves cheaply.
- **Fluvial geomorphology meander wavelength** (Leopold, 1960): real river
  meander wavelength scales with channel width as `λ ≈ 10–14 × width`. Used
  to cap straight runs and choose meander amplitude by flow.
- **Distance transform on obstacle mask**: gives per-tile clearance to
  nearest wall, used for routing cost, width clipping, and smoothing
  reprojection.
- **Poisson-disk sampling**: for island placement along stems without
  clumping.

No hydraulic erosion. No particle simulation. No WFC.

## Scope (In V3-R1)

- canonical riverbed routing across the whole world using a coarse global
  flow graph followed by per-macro refinement
- two canonical riverbed terrain classes:
  - `TERRAIN_RIVERBED_SHALLOW`
  - `TERRAIN_RIVERBED_DEEP`
- initial water occupancy as packet overlay on top of riverbed terrain
- dry-first riverbed preview before any water surface is enabled
- deterministic source mouth (spring), waterfall mouth, and field source
  markers
- controlled islands on qualifying wide stems
- controlled split-and-rejoin branches on qualifying wide stems
- terminal lakes/seas at endorheic basin bottoms above a flow threshold
- river-aware 47-tile boundary presentation
- `worldgen_settings.rivers` in `world.json`
- native batch generation and per-tier cache reuse
- dev-only debug native API for inspecting every intermediate layer

## Out of Scope

- hydraulic erosion, sediment transport, or any fluid simulation
- dynamic water level simulation; drought belongs to environment runtime
- global oceans or coastlines outside the generated world rectangle
- rain runoff, groundwater, aquifers, seasonal freezing
- bridges, boats, pumps, irrigation, fishing, water power
- biome humidity, climate, weather
- arbitrary river tunneling through mountain walls
- player-dug deep channels
- player-dug shallow canals in V3-R1 (future local spec only)
- runtime recomputation of river topology after terrain digging

## Dependencies

- `world_runtime.md` for batch packet generation and chunk ownership
- `mountain_generation.md` for mountain field, mountain identity, and
  existing presentation boundary
- ADR-0001 for runtime/dirty-update discipline (interactive runtime, not
  world load)
- ADR-0002 for wrap-safe X behavior
- ADR-0003 for immutable base + runtime diff ownership
- ADR-0006 for surface vs subsurface boundaries
- ADR-0007 for worldgen being distinct from environment runtime

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical, runtime overlay, or visual only? | Riverbed terrain class, depth class, source/spring/waterfall-mouth flags, and island/split topology are canonical. Initial water occupancy is packet overlay. Future drought is environment runtime. Atlas indices are derived presentation. |
| Save/load required? | Yes, for `worldgen_settings.rivers` in `world.json`. The Tier 0 skeleton is regenerated from seed on every load and is **not** persisted. No preview caches are saved. |
| Deterministic? | Yes. Every tier is a pure function of `(seed, world_version, settings_packed, world_bounds, mountain field, tier-0 output, coord)` with explicit dependency order. |
| Must work on unloaded chunks? | Yes. Tier 0 covers the world; Tier 1 and Tier 2 are regenerated on demand from seed + Tier 0 + settings. |
| C++ compute or main-thread apply? | All three tiers are native compute on background workers. Main thread only applies chunk packet output to views. |
| Dirty unit | Tier 0: whole world, regenerated once per load. Tier 1: one aligned macro + halo. Tier 2: one chunk batch. No runtime riverbed dirty region exists — base river topology is immutable. |
| Single owner | `WorldCore` owns Tiers 0/1/2 canonical output. `ChunkView` owns presentation only. `WorldDiffStore` owns no river data. `world.json` owns the settings copy. |
| 10× / 100× scale path | Tier 0 is coarse and sub-linear in world tiles. Tier 1 and Tier 2 are already macro/chunk bounded and reuse caches. No whole-world per-tile pass exists. |
| Main-thread blocking? | Forbidden. Tier 0 runs behind the world-load progress UI; Tiers 1/2 run on the existing worker path. |
| Hidden GDScript fallback? | Forbidden. Native river solve is required. |
| Could it become heavy later? | Bounded by design. Width, sinuosity, branching propensity, island count, and water overlay all scale route/publish complexity, but each tier has explicit caps and cache reuse. |
| Whole-world prepass? | **Permitted for Tier 0 only**, under explicit budget. Runs at world load, single pass, native, off-main-thread. Not permitted during streaming, preview, or per-chunk work. |

## Architecture

### Tier 0 — World Skeleton

**Purpose.** Resolve global river topology once so Tier 1 never needs
cross-macro information to decide merges, crossings, or flow ordering.

**Inputs.**
- `seed`, `world_version`, `settings_packed.river_*`
- mountain field and mountain identity (already canonical)
- world bounds `(world_width_tiles, world_height_tiles)`

**Grid.**
- coarse cell size: `river_coarse_cell_size_tiles = 128`
- grid dimensions: `ceil(world_width / 128) × ceil(world_height / 128)`
- X wraps (ADR-0002); Y does not
- for a `8192 × 8192` world: `64 × 64 = 4096` nodes

**Per-node fields.**

| Field | Derivation |
|---|---|
| `hydro_height` | Broad-scale flow potential: `mountain_elevation_avg + world_slope_noise + low_freq_relief`. Bounded range `[0, 1]`. |
| `valley_score` | Preference for open low corridors: `1 - mean(wall_density_in_cell) - 0.5 × mean(foot_density_in_cell)`. Bounded `[0, 1]`. |
| `wall_density` | Fraction of tiles in cell that are `mountain_wall`. |
| `foot_density` | Fraction of tiles in cell that are `mountain_foot`. |
| `source_score` | Deterministic biased noise × `(hydro_height > high_terrain_threshold ? 1 : 0.2)`. Seeds sampling of headwater candidates. |

**Downstream graph construction.**
1. For each node, compute the D8 downstream neighbor by minimum
   `hydro_height`, with deterministic tie-breaking by fixed neighbor order
   `(E, SE, S, SW, W, NW, N, NE)` after X wrap canonicalization.
2. Nodes with `wall_density > wall_block_threshold = 0.5` are non-routing:
   they do not emit downstream edges and are skipped by upstream neighbors
   (treated as having infinite `hydro_height` for the purpose of neighbor
   selection).
3. Apply **priority-flood depression filling**: detect closed basins, raise
   their `hydro_height` to the spill elevation of the basin outlet, and
   re-resolve downstream edges inside the filled basin. Deterministic and
   O(N log N).
4. Detect cycles (should not exist after priority-flood; assert in debug
   builds). If a cycle is detected, break it at the edge with the highest
   canonical wrapped coordinate pair.

**Result:** a forest of inverted trees where each tree is a river system
ending at either a world-edge sink or a basin lake.

**Flow accumulation.**
1. Topologically sort nodes by descending `hydro_height`.
2. For each node in order: `flow[node] = source_score[node] + Σ flow[upstream]`.
3. Normalize flow against theoretical maximum for numerical stability.

**Visible river extraction.**
- A node/edge is **visible** iff `flow[node] ≥ flow_visible_threshold(amount)`.
- `flow_visible_threshold = lerp(high_threshold, low_threshold, amount)` —
  more `amount` → lower threshold → more visible rivers.
- Connected visible edges form **trunks**. Each trunk is a linear chain of
  coarse nodes from a visible headwater down to a terminal sink (world edge
  or basin lake).
- Assign Strahler order to each trunk node for downstream use (island and
  split eligibility).

**Terminal-lake detection (V3-R1D).**
- A basin outlet with `flow > flow_sea_threshold` becomes a terminal lake
  centered on the basin bottom, bounded by a polygon fitted to the filled
  depression shape and clamped to a maximum tile area.

**Output.** In-RAM structure:
```text
RiverSkeleton {
    coarse_grid_dims: (int, int)
    nodes: array of {
        coord_wrapped: (int, int)
        hydro_height: float
        valley_score: float
        wall_density: float
        foot_density: float
        downstream_index: int | SINK
        flow: float
        visible: bool
        strahler_order: int
        is_terminal_lake_center: bool
        terminal_lake_polygon: array of (int, int) | null
    }
    trunks: array of {
        node_indices: array of int
        strahler_order_max: int
        is_terminated_by_lake: bool
    }
}
```

**Budget.** `≤ 200ms` on native for an `8192 × 8192` world during world
load. Measured by debug counter. Exceeding the budget is a blocker.

### Tier 1 — Macro Detail

**Purpose.** Inside one aligned `1024`-tile macro plus a `1`-macro halo,
refine trunk centerlines at `32`-tile guide resolution so that final
rasterization can emit tile-accurate shallow/deep channels with natural
curves and clearance-aware widths.

**Inputs.**
- Tier 0 skeleton (read-only, shared)
- `seed`, `world_version`, `settings_packed`
- mountain field at tile resolution for this macro + halo
- pre-computed wall/foot distance transform (clearance map) for this
  macro + halo

**Steps.**

1. **Clip trunks to macro AABB + halo.** Any trunk that intersects the
   macro-plus-halo rectangle contributes its coarse-node chain within that
   rectangle. Halo ensures smoothing has enough control points at macro
   edges.
2. **Subdivide coarse chain to fine guide grid** (`32`-tile nodes): walk
   each coarse edge and sample fine nodes along it, placing each inside the
   best valley corridor using `valley_score` and clearance map.
3. **Lateral meander perturbation.** Apply deterministic 1D noise along the
   arclength of each fine chain with amplitude
   `A(flow) = min(meander_amplitude_max × sqrt(flow_norm), clearance − safety_margin)`
   and wavelength `λ(width) = meander_wavelength_factor × desired_width`.
   Natural-looking meanders, auto-scaling with flow.
4. **Curve smoothing.** Apply **Catmull-Rom** interpolation with tension
   `0.4` between fine-chain control points. Follow with two iterations of
   **Chaikin corner-cutting** on the polyline.
5. **Curvature cap enforcement.** After smoothing, measure the interior
   angle at each polyline vertex. If any angle is sharper than
   `curvature_cap_angle = 110°` (interior), insert an intermediate control
   point biased toward the average of the two neighbors and re-smooth that
   local region. Iterate up to 3 times, then accept.
6. **Clearance reprojection.** Any smoothed segment whose centerline
   overlaps a `mountain_wall` tile is reprojected laterally along the
   clearance gradient until clear. If it cannot be made clear within
   `safety_margin` tiles, the segment is marked hidden for this tile-level
   pass (the Tier 0 edge still exists but emits no visible riverbed in this
   region — forces the Tier 1 to remove orphan segments in post).
7. **Width profile.** Per centerline vertex:
   ```
   desired_width = base_width(settings.width)
                 + sqrt(flow_norm) × flow_width_gain
                 + bounded_noise(±width_jitter)
   actual_width  = min(desired_width, clearance × 2 − safety_margin)
   actual_width  = clamp(actual_width, 0, max_channel_width)
   ```
   If `actual_width < min_viable_width`, the segment is hidden (same as
   step 6).
8. **Island placement** (if `branching > 0` and Strahler order ≥ 2 and
   segment is long+straight+clear enough):
   - Sample candidate centers by Poisson-disk along the centerline segment
     at spacing `≥ island_min_spacing`.
   - Accept the candidate if: `actual_width ≥ island_min_width`,
     `clearance ≥ island_clearance_min`, segment curvature low, no junction
     within `island_exclusion_distance`, not within macro seam guard band
     `island_seam_guard_tiles = 24`.
   - Accepted island: deterministic lens/capsule mask subtracted from the
     channel mask; the remaining riverbed must stay connected around both
     sides (assert by local 4-connectivity check).
9. **Split-and-rejoin placement** (V3-R1C):
   - Similar eligibility but stronger: Strahler order ≥ 3, wider than
     `split_min_width`, segment length ≥ `split_min_length`.
   - Two offset centerlines diverge and rejoin within a bounded distance;
     each branch gets a fraction of the total flow (50/50 in MVP).
10. **Outputs for this macro:**
    - list of smoothed polylines with per-vertex width, flow, Strahler
      order, and `is_hidden_segment` flags
    - island mask regions as polygons
    - split-channel pairs with rejoin points
    - terminal-lake polygons that intersect this macro

**Cache.** Keyed by
`(seed, world_version, river_settings_hash, macro_coord_wrapped)`.
Halo reads are read-only and deterministic, so two macros generated
independently produce identical boundary data.

**Why this resolves the V2 contradiction.** Tier 1 never needs to discover
whether a route crosses another or how tributaries merge — Tier 0 already
resolved all that globally. Tier 1 only refines the shape of routes whose
topology is already fixed.

### Tier 2 — Chunk Rasterization

**Purpose.** Convert Tier 1 polylines and masks within a chunk AABB into
final tile data for `ChunkPacketV3`.

**Steps.**
1. Gather all Tier 1 polyline segments, island polygons, and terminal-lake
   polygons that intersect this chunk.
2. For each polyline vertex inside the chunk, rasterize the channel by
   stamping a width-sized cross-section perpendicular to the local tangent.
   Use a sub-tile accurate coverage test so the edge silhouette is smooth.
3. Subtract island masks from the channel coverage.
4. Add terminal-lake coverage where applicable.
5. **Shallow vs. deep classification** (per covered tile):
   - compute `distance_to_edge` inside the final channel mask (Chebyshev
     distance to nearest non-channel tile within chunk + 1-tile halo);
   - `distance_to_edge ≤ shallow_shelf_tiles = 1` → shallow;
   - otherwise → deep.
   - This produces correct shelves on bends, around islands, and along
     terminal-lake shores without branching on channel width alone.
6. Emit `river_flags`:
   - `is_riverbed = 1` on every channel tile
   - `is_deep_bed = 1` on deep tiles
   - `is_source_mouth` on the first external riverbed tile of a waterfall
     mouth from a mountain wall
   - `is_spring = 1` on a headwater source that is not mountain-adjacent
     (new in V3; see Packet Contract)
   - `has_water = 0` in V3-R1 dry passes; set in V3-R2
7. Select atlas indices from 47-tile adjacency families:
   - `riverbed_atlas_indices` for dry-bed silhouette
   - `water_atlas_indices` left at `0` until V3-R2
8. Overwrite only `plains` and `mountain_foot` terrain tiles. Never
   overwrite `mountain_wall`; if the channel mask intersects a wall tile,
   that tile is preserved and the channel is clipped around it (Tier 1 step
   6 should have already prevented this — Tier 2 is a safety net).

**Halo.** 1-tile halo around the chunk is read to resolve the 47-tile
adjacency correctly at chunk seams. Cardinal continuity of the riverbed
mask across chunk seams is a required invariant; verified by acceptance.

## Core Contract

### Chunk Geometry and Wrap-World Contract

Unchanged from the active world runtime:
- one world tile = `32 px`
- one chunk = `32 × 32` tiles
- chunk-local cell coordinates are `0..31` on each axis
- world X wraps per ADR-0002
- world Y does not wrap

Wrap rules for all three tiers:
- all coarse and fine coordinate math canonicalizes X through the shared
  world-width modulo
- trunks may cross the X seam; the identical trunk must be observed from
  either side
- terminal lakes may not extend past the north/south world edges; if a
  basin touches the Y boundary, the lake is clipped to world bounds

### Worldgen Order

```
1. mountain field / mountain identity
2. Tier 0 river skeleton (once, at world load)
3. Tier 1 macro detail (on demand, cached)
4. Tier 2 chunk rasterization (on packet batch request)
5. initial water occupancy fill (disabled in V3-R1 dry preview)
6. terrain and presentation atlas selection
```

### Terrain Classes

V3 adds two riverbed terrain ids (same as V2):

| Id constant | Walkable | Meaning |
|---|---|---|
| `TERRAIN_RIVERBED_SHALLOW` | 1 | Fordable shallow bed. Narrow channels, shallow shelves, terminal-lake shores, future shovel canals. |
| `TERRAIN_RIVERBED_DEEP` | 0 | Non-fordable deep cut. Natural generated channel cores, deep lake interiors. Blocked even when dry. |

V3 does **not** add a `TERRAIN_RIVER_BANK` class or separate water terrain
ids. Water is occupancy on top of the riverbed (V3-R2).

### Shallow vs. Deep Rule

Classification is **distance-based** on the final channel mask, not
width-based:

- `distance_to_edge = 1 tile` → shallow shelf
- `distance_to_edge ≥ 2 tiles` → deep bed
- narrow channels (`≤ 3` tiles wide) are fully shallow because no tile ever
  reaches `distance_to_edge = 2`

This gives correct shallow shelves on bends, around islands, along
terminal-lake shores, and at the narrowing/widening transitions the user
requested.

### Water Occupancy Contract

- V3-R1 emits dry riverbeds only: `has_water = 0`, `water_atlas_indices = 0`.
- V3-R2 enables deterministic static water occupancy on approved riverbeds.
- Water occupancy never changes `terrain_ids` or `riverbed_atlas_indices`.
- Future drought may toggle `has_water` but must leave riverbed terrain
  intact.

### Adjacency Presentation

47-tile autotile family for each boundary:
- `plains` ↔ `riverbed_shallow` (low bank)
- `mountain_foot` ↔ `riverbed_shallow` (cliff shore)
- `riverbed_shallow` ↔ `riverbed_deep` (deep cut)
- optional water-surface family layered on top (V3-R2)

Dry tiles adjacent to a riverbed keep their canonical terrain class and
receive a river-aware atlas index only.

## Mountain Interaction

Rules are inherited and tightened from V2:

- **`mountain_wall` is impassable to rivers** except at waterfall mouths.
  The Tier 0 downstream graph treats `wall_density > 0.5` as non-routing.
- **`mountain_foot` may be crossed** but is never an attraction target;
  `valley_score` explicitly penalizes foot regions.
- **Bypass before collision.** Because Tier 0 chooses downstream by
  `hydro_height` minus a wall-clearance term, routes curve away from walls
  early. Tier 1 step 6 (clearance reprojection) is a safety net, not a
  primary mechanism.
- **Source mouth (waterfall).** A visible trunk whose headwater is adjacent
  to a mountain wall emits `is_waterfall_mouth = 1` on the first external
  riverbed tile. The wall behind is preserved.
- **Spring source.** A headwater not adjacent to a mountain wall emits
  `is_spring = 1` on the first riverbed tile. This is new in V3 and gives
  presentation a clear signal for non-mountain origins (forested springs,
  hillside seeps).

Mutually exclusive: `is_waterfall_mouth`, `is_spring`. Exactly one is set
on each headwater tile; neither on any other tile.

## Curve Quality Contract (Beauty)

The following contracts are **required** and checked by automated
acceptance tests where possible:

### No sharp turns
- After smoothing and curvature cap enforcement, every interior angle along
  every visible centerline polyline is `≥ 110°`.
- Rasterization may expose apparent corners only where the centerline width
  collapses to 1 tile due to clearance clipping; these are not true turns.

### No blobs
- Every connected riverbed region must satisfy
  `length_along_centerline ≥ blob_ratio × max_width`
  with `blob_ratio = 6`. Terminal lakes are exempt and checked separately.
- Terminal lakes must be the result of a valid basin outlet, not an emergent
  blob; lake polygons are deterministic from Tier 0.

### No unnatural straight lines
- Any centerline segment longer than `straight_run_max_tiles = 80` without
  curvature deviation ≥ `min_curvature_deviation` is forbidden. If Tier 1
  detects such a segment, it inserts a gentle meander bump when clearance
  permits, otherwise flags the segment for review. Under tight clearance
  (e.g., between close mountain walls), straight runs are permitted because
  the constraint is physical.

### Width variation
- Every visible trunk must exhibit width variation of at least 2 tiles peak-
  to-peak across its length, unless clamped by clearance for the entire
  length.

### Branching
- Islands and splits occur only on stems with Strahler order ≥ 2 (islands)
  or ≥ 3 (splits). MVP default is islands only; splits in V3-R1C.

## Settings

`worldgen_settings.rivers` in `world.json`:

| Field | Range | V3 default | Meaning |
|---|---:|---:|---|
| `amount` | `0.0..1.0` | `0.35` | Flow-visibility threshold + headwater source density. `0.0` = no rivers. |
| `width` | `1.0..12.0` | `4.0` | Base width tendency; actual width is flow-driven and clearance-clipped. |
| `sinuosity` | `0.0..1.0` | `0.45` | Meander amplitude multiplier. |
| `branching` | `0.0..1.0` | `0.3` | Island + split propensity. `0.0` = no islands, no splits. |

Rules:
- `amount = 0.0` must produce zero visible rivers, zero Tier 1 work, and
  zero riverbed tiles. Tier 0 may still run to support future overlays but
  must emit an empty visible set.
- Settings are copied into the save on world creation and never re-read
  from repository defaults for an existing world.
- For `world_version <= 6`, all river settings behave as `amount = 0.0`.
- For `world_version >= 8`, a missing `worldgen_settings.rivers` section is
  a backward-compatibility path only and must be filled from hard-coded V3
  defaults in the loader, not from `data/balance/river_gen_settings.tres`.

### Canonical vs. Balance Separation

**Canonical parameters** (in `settings_packed`, versioned by `WORLD_VERSION`,
changing them changes terrain output):
- `amount`, `width`, `sinuosity`, `branching` (user-facing settings)

**Algorithm constants** (hard-coded, WORLD_VERSION-bumped on change):
- `river_coarse_cell_size_tiles`
- `flow_visible_threshold` mapping
- `curvature_cap_angle`, `straight_run_max_tiles`, `blob_ratio`
- depression-filling algorithm choice
- Strahler eligibility thresholds

**Balance parameters** (loaded from `data/balance/river_presentation.tres`,
changing them does **not** change terrain ids or flags — only atlas indices):
- 47-tile atlas family selections
- edge roughness / jitter seed
- water surface color and animation

This split lets designers tune presentation without invalidating existing
worlds. Modifying any canonical parameter requires a `WORLD_VERSION` bump.

### `settings_packed` Layout

Extend after the confirmed mountain layout:

| Index | Constant name | Meaning |
|---:|---|---|
| `0–8` | mountain settings | Existing, unchanged. |
| `9` | `SETTINGS_RIVER_AMOUNT` | `rivers.amount`. |
| `10` | `SETTINGS_RIVER_WIDTH` | `rivers.width`. |
| `11` | `SETTINGS_RIVER_SINUOSITY` | `rivers.sinuosity`. |
| `12` | `SETTINGS_RIVER_BRANCHING` | `rivers.branching` (new). |

- Active V3 native path requires at least `13` packed values.
- Missing indices for legacy `world_version <= 6` behave as all zeros plus
  defaults where zero is ambiguous.
- Missing indices for `world_version >= 8` are invalid after load migration
  and must fail loudly.

## Packet Contract

`ChunkPacketV3` extends `ChunkPacketV2` additively. No V1 or V2 field is
removed or reshaped.

**New / changed fields vs. V2:**

| Field | Type | Length | Meaning |
|---|---|---|---|
| `river_flags` | `PackedByteArray` | 1024 | Riverbed + water + mouth/spring bits. Bit layout below. |
| `riverbed_atlas_indices` | `PackedInt32Array` | 1024 | Atlas indices for dry riverbed geometry. `0` when not riverbed. |
| `water_atlas_indices` | `PackedInt32Array` | 1024 | Atlas indices for water surface. `0` when no water. |

`river_flags` bit layout:

| Bit | Name | Meaning |
|---|---|---|
| `1 << 0` | `is_riverbed` | Tile is canonical riverbed. |
| `1 << 1` | `is_deep_bed` | Tile is deep riverbed; non-walkable. |
| `1 << 2` | `has_water` | Water occupancy active (V3-R2). |
| `1 << 3` | `is_source_mouth` | First external riverbed tile of a mountain-adjacent headwater. |
| `1 << 4` | `is_waterfall_mouth` | First external riverbed tile emerging from a mountain wall. |
| `1 << 5` | `is_spring` | First riverbed tile of a non-mountain headwater. **New in V3.** |
| `1 << 6` | `is_terminal_lake` | Tile belongs to a terminal-lake basin (V3-R1D). |
| `1 << 7` | reserved | — |

Invariants:
- `terrain_ids` carry the riverbed class, not a water class.
- `walkable_flags` reflect shallow vs. deep walkability.
- `is_riverbed` agrees with `terrain_ids`:
  - `TERRAIN_RIVERBED_SHALLOW` → `is_riverbed=1`, `is_deep_bed=0`
  - `TERRAIN_RIVERBED_DEEP` → `is_riverbed=1`, `is_deep_bed=1`
  - non-riverbed → `river_flags = 0`
- `has_water` may be set only when `is_riverbed = 1`.
- `is_source_mouth`, `is_waterfall_mouth`, `is_spring` are pairwise
  mutually exclusive.
- Mouth/spring bits may be set while `has_water = 0` during dry preview.
- `riverbed_atlas_indices` and `water_atlas_indices` are derived
  presentation metadata and are not authoritative for gameplay,
  walkability, or save/load.

## Runtime Architecture

### Native Boundary

Same active native boundary as mountains:

```text
WorldCore.generate_chunk_packets_batch(
    seed: int,
    coords: PackedVector2Array,
    world_version: int,
    settings_packed: PackedFloat32Array
) -> Array
```

- No second native worldgen API.
- Tier 0 is run implicitly inside `WorldCore` before the first batch is
  served after world load. Internally this is a warm-up; externally the
  batch API is unchanged.
- Active river runtime requires `world_version >= 8`.
- All heavy work stays in C++; main thread only applies chunk packets.

### Debug Native API (dev-only)

A **separate** native method, compiled only in dev builds, exposes
intermediate layers without polluting the packet schema:

```text
WorldCore.get_river_debug_snapshot(
    region_aabb_tiles: Rect2i,
    layer_mask: int
) -> Dictionary
```

Layers addressable by `layer_mask` bits:
- coarse grid nodes
- downstream arrows
- `hydro_height` heatmap
- `valley_score` heatmap
- `wall_density` + `foot_density` heatmap
- clearance map
- flow accumulation heatmap
- Strahler order coloring
- visible trunk graph pre-smoothing
- smoothed centerlines
- desired width vs. actual clipped width
- final shallow/deep raster

Acceptance must reject a build if only final river tiles are visible and
intermediate layers cannot be inspected.

This API is **stripped from release builds** by a compile-time flag and
never referenced by save/load, packet, or gameplay code.

### Tier Caches

| Tier | Cache key | Eviction |
|---|---|---|
| 0 | `(seed, world_version, river_settings_hash, world_bounds)` — single entry per world | Replaced on world load; held in RAM |
| 1 | `(seed, world_version, river_settings_hash, macro_coord_wrapped)` | LRU with native-memory policy |
| 2 | per-chunk packet output | normal packet cache reuse |

Cache eviction may change performance only, not output. Two Tier 1 macros
generated independently from identical inputs must produce byte-identical
centerlines, widths, island masks, and flags.

### Script Ownership

| Role | Owner | Responsibility |
|---|---|---|
| Canonical river output | `WorldCore` | Tiers 0/1/2 terrain ids, walkability, flags, atlas indices, water occupancy. |
| Chunk orchestration | `WorldStreamer` / packet backend | Batches, identical to mountain path. |
| Presentation | `ChunkView` / terrain presentation registry | Dry riverbed geometry, water surfaces (V3-R2), river-aware edge atlases. |
| Save/load | save collectors/appliers | Persist `worldgen_settings.rivers` only. |
| Debug UI | dev-only viewer | Consumes `get_river_debug_snapshot`; not in release. |
| Future drought | Environment runtime (not V3-R1) | Toggles water occupancy only; never mutates riverbed. |

No runtime flood-fill or continuous river simulation is introduced.

## Persistence

### `world.json` Extension

```json
{
  "world_seed": 131071,
  "world_version": 8,
  "worldgen_settings": {
    "mountains": { "...": "..." },
    "rivers": {
      "amount": 0.35,
      "width": 4.0,
      "sinuosity": 0.45,
      "branching": 0.3
    }
  }
}
```

Rules:
- exact values copied once on new world creation;
- loading `world_version <= 6` preserves the no-river output path;
- loading `world_version == 7` (V2) migrates to V3 with `branching` filled
  from hard-coded default; migration is additive and terrain output may
  change because V3 supersedes V2;
- loading `world_version >= 8` without `worldgen_settings.rivers` uses
  hard-coded V3 defaults in the loader;
- `worldgen_signature`, if present, remains diagnostic only.

### Skeleton Not Persisted

Tier 0 output is regenerated from seed on every load. No new save file.

### Chunk Diffs

Unchanged. River topology is immutable base worldgen.

### `WORLD_VERSION`

V3 bumps to `world_version = 8` because canonical terrain output changes
for the same `(seed, coord)` when migrating from V2 to V3.

## Performance Class

| Operation | Class | Dirty unit | Budget |
|---|---|---|---|
| Tier 0 world-skeleton solve | one-time native worker at world load | whole world, coarse `128` grid | ≤ 200ms on `8192 × 8192` |
| Tier 1 macro refine | on-demand native worker | aligned `1024`-tile macro + halo | off main thread |
| Tier 2 chunk rasterization | native worker | requested chunk batch | off main thread |
| Atlas selection | native worker | chunk batch | off main thread |
| Water occupancy (V3-R2) | native worker | chunk batch | off main thread; disabled in V3-R1 |
| Packet publish | main-thread sliced apply | existing chunk publish batches | shares current streaming budget |
| Preview regeneration | native worker | preview batch | no synchronous UI wait; superseded requests cancelable |

**Forbidden:**
- Per-frame river update logic.
- Main-thread river routing or smoothing.
- Recomputing river topology because water dries up or returns.
- Using water occupancy to rewrite `terrain_ids`.
- Tier 0 ever running outside world load.
- Tier 0 ever persisting to disk (must remain seed-derived RAM only).
- Preview recomputing Tier 0 from scratch on each slider tick — only Tier 1
  and Tier 2 recompute on preview; Tier 0 is cached per-(seed, settings)
  and shared with live world.
- Synchronous UI-thread waits for preview results.

**Verification targets:**
- `amount = 0.0` preserves mountain-only output with no river work beyond
  a zero-visibility Tier 0.
- Normal exploration with rivers enabled adds no new hitch class where a
  single frame exceeds `22 ms`.
- Preview slider interaction never blocks input frames.
- Repeated chunk batches in one macro show Tier 1 cache hits in debug
  counters.

## Acceptance Criteria

### Generation

- [ ] Mountains generate before rivers; rivers visibly respond to relief.
- [ ] Tier 0 completes within budget for the reference world size.
- [ ] Tributaries merge; no unrelated routes cross as rails.
- [ ] Rivers widen downstream (or clamp to clearance); no inverse.
- [ ] `amount = 0.0` produces zero visible rivers and zero riverbed tiles.
- [ ] Output deterministic for same `(seed, version, settings)`.
- [ ] Channels remain continuous across chunk seams.
- [ ] Channels remain continuous across the X wrap seam; no Y wrap.
- [ ] Batch order does not affect tile output.

### Mountain Interaction

- [ ] Rivers pass through `mountain_foot` but do not rail-follow it.
- [ ] Rivers do not overwrite `mountain_wall`.
- [ ] Mountain-origin rivers appear through waterfall/source mouths.
- [ ] Non-mountain sources emit `is_spring`.
- [ ] Width clips before intersecting protected mountain geometry.
- [ ] Mountain cover and mountain identity do not regress.

### Beauty (V3 new)

- [ ] Every visible centerline polyline has all interior angles `≥ 110°`
      after smoothing.
- [ ] No centerline segment exceeds `straight_run_max_tiles` without a
      curvature deviation, unless physically constrained by clearance.
- [ ] Every connected riverbed region has `length ≥ 6 × max_width` (blobs
      forbidden), except terminal lakes.
- [ ] Each visible trunk shows width variation ≥ 2 tiles peak-to-peak,
      unless clearance-clamped along its full length.
- [ ] Islands, when enabled, keep riverbed connectivity around them.
- [ ] Split branches, when enabled, rejoin within bounded distance.
- [ ] Terminal lakes, when enabled, are basin-derived and not emergent
      blobs.

### Gameplay

- [ ] Shallow riverbed is walkable dry or wet.
- [ ] Deep riverbed is non-walkable dry or wet.
- [ ] Dry drought-state riverbeds remain visible.
- [ ] Dry terrain adjacent to riverbeds keeps its canonical class.
- [ ] 47-tile edges read correctly for plains/foot/shallow/deep
      combinations.
- [ ] Water surfaces (V3-R2) layer on top without hiding the dry bed
      silhouette.

### Performance

- [ ] Tier 0 ≤ `200ms` on reference world, off main thread.
- [ ] No river work on the main thread beyond packet application.
- [ ] Preview does not synchronously block UI.
- [ ] No new frame > `22 ms` attributable to river generation, publish, or
      presentation during exploration.
- [ ] Tier 1 cache reuse proven by debug counters on repeated batches
      within a macro.

### Persistence and Governance

- [ ] New river worlds write `worldgen_settings.rivers` with all four
      fields.
- [ ] Loading `world_version <= 6` preserves no-river output.
- [ ] Loading `world_version >= 8` with missing river settings uses
      hard-coded V3 defaults.
- [ ] `WORLD_VERSION = 8` lands in the same task as V3 code.
- [ ] `ChunkPacketV3`, `is_spring` flag, `is_terminal_lake` flag, and
      `branching` setting land in meta docs when code lands.

### Debug

- [ ] Dev builds expose every layer listed in the Debug Native API.
- [ ] Debug API is stripped from release builds by compile-time flag.

## Implementation Iteration

### V3-R1A — Tier 0 skeleton and debug
- Implement coarse grid, fields, downstream graph, priority-flood,
  flow accumulation, visible extraction, Strahler order.
- Expose debug API for all Tier 0 layers.
- No terrain writes yet; acceptance is debug-layer visual review plus
  unit tests for deterministic output and flow-tree topology.

### V3-R1B — Tier 1 + Tier 2 dry riverbed rasterization
- Implement macro refinement, smoothing, curvature cap, clearance
  reprojection, width profile.
- Implement chunk rasterization with distance-based shallow/deep
  classification.
- Emit `ChunkPacketV3` with `has_water = 0`.
- Acceptance: Generation + Beauty + Mountain Interaction criteria above.

### V3-R1C — Islands and split-and-rejoin
- Add island placement with Poisson-disk sampling and connectivity
  assertions.
- Add split-and-rejoin pairs for Strahler order ≥ 3 stems.
- Acceptance: Beauty island/split criteria.

### V3-R1D — Terminal lakes / seas
- Promote qualifying basin outlets to terminal-lake polygons.
- Add `is_terminal_lake` flag and deep-interior classification.
- Acceptance: Beauty lake criterion + Gameplay walkability.

### V3-R2 — Static water occupancy
- Enable `has_water` and `water_atlas_indices` on approved riverbeds and
  terminal lakes.
- Acceptance: water does not mutate terrain; walkability unchanged.

## Files That May Be Touched

### New
- `core/resources/river_gen_settings.gd`
- `data/balance/river_gen_settings.tres`
- `data/balance/river_presentation.tres`
- `gdextension/src/river_skeleton.h`
- `gdextension/src/river_skeleton.cpp`
- `gdextension/src/river_macro_refine.h`
- `gdextension/src/river_macro_refine.cpp`
- `gdextension/src/river_rasterize.h`
- `gdextension/src/river_rasterize.cpp`

### Modified
- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/world_streamer.gd`
- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- save/load files that own `worldgen_settings`
- new-game UI files that expose river controls

## Files That Must Not Be Touched

- `BuildingSystem`, `PowerSystem`, `IndoorSolver`, room/power topology.
- Combat, fauna, progression, inventory, crafting, lore, unrelated UI.
- `z != 0` subsurface runtime, underground fog, cave/cellar generation,
  connector systems.
- Environment runtime for weather, season, wind, temperature, spores,
  snow, ice, or dynamic water.
- Chunk diff file shape outside the existing tile override contract.
- Legacy world runtime files from the pre-rebuild stack.
- Biome registries, flora/decor batching, POI placement, resource
  streaming, climate systems unless explicitly scoped.
- `docs/02_system_specs/meta/*` until code confirms final names/payloads.

## Required Canonical Doc Follow-Ups When Code Lands

- `meta/packet_schemas.md`: `ChunkPacketV3`, new flags `is_spring`,
  `is_terminal_lake`.
- `meta/save_and_persistence.md`: `worldgen_settings.rivers.branching`,
  versioned defaults, V2→V3 migration note.
- `meta/system_api.md`: `RiverGenSettings` entrypoint and the dev-only
  `get_river_debug_snapshot`.
- `world/world_runtime.md`: Tier 0 world-load phase, if runtime scope
  statement changes materially.
- `00_governance/ENGINEERING_STANDARDS.md`: note the explicit Tier 0
  exception to the whole-world-prepass prohibition (bounded, one-time,
  off-main-thread, cached in RAM).

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Tier 0 budget breach on very large worlds | Coarse cell size is a versioned constant; can be raised to `256` tiles at the cost of merge granularity. Profile per world size before shipping. |
| Catmull-Rom/Chaikin smoothing differs near macro seams | Tier 0 fixes control point positions globally; Tier 1 smoothing operates on shared control points inside macro + halo only, with deterministic clipping. Regression-tested with seam-straddling batches. |
| Curvature-cap iteration explodes on pathological inputs | Hard iteration cap (3), after which the segment is accepted or marked hidden. |
| Island/split placement clumping | Poisson-disk sampling guarantees minimum spacing; seam guard band prevents seam-crossing islands. |
| Preview invalidation on slider drags | Tier 0 cache keyed by settings hash; sliders that only affect Tier 1/2 (e.g., `width`, `sinuosity`, `branching` at non-topology-changing ranges) do not invalidate Tier 0. |
| Balance tuning forces WORLD_VERSION bumps | Presentation balance isolated to `river_presentation.tres`; only changes atlas indices, not terrain ids or flags. |
| Debug API leaking to release | Compile-time flag, enforced by CI. |
| `is_spring` missing presentation | Spring atlas variant is part of V3-R1B acceptance. |

## Deferred

- Wider shallow shelves (> 1 tile) on very wide rivers.
- Dedicated non-walkable waterfall-lip terrain id.
- Shovel-made shallow canals + water connectivity pass.
- Drought / seasonal narrowing / full drying as environment runtime.
- Dams, water power, fluid simulation.
- Oceans and coastlines outside the generated world rectangle.
- Rain runoff, snowmelt, groundwater, aquifers.
- Sediment, erosion, delta formation.

Any of the above requires a future spec amendment and `WORLD_VERSION`
review if canonical terrain output changes.

## Status Rationale

This spec is `draft` because:
- it supersedes two approved documents and must go through design review
  before promotion to `approved`;
- Tier 0 whole-world prepass is a deliberate relaxation of a prior V2
  constraint and needs governance sign-off;
- concrete numeric thresholds (`flow_visible_threshold` mapping,
  `curvature_cap_angle`, `straight_run_max_tiles`, `blob_ratio`, island and
  split eligibility constants) are provisional and must be validated by a
  debug-layer review of Tier 0 and Tier 1 output before V3-R1B begins;
- the dev-only debug native API is a new surface and needs a compile-time
  stripping strategy confirmed by the build owner.

Changes to the rules above require a new version of this document with
`last_updated` bumped and a short amendment note in the task closure
report.
