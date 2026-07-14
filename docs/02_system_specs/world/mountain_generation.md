---
title: Mountain Generation V1
doc_type: system_spec
status: approved
owner: engineering
source_of_truth: true
version: 1.8
last_updated: 2026-07-14
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - world_runtime.md
  - world_grid_rebuild_foundation.md
  - rock_shader_presentation_iteration_brief.md
  - MOUNTAIN_GENERATION_ARCHITECTURE.md
---

# Mountain Generation V1

## Purpose

Define the first canonical extension of the chunked world runtime that
introduces massive deterministic mountains and a mountain-interior cover
visibility system on top of `World Runtime V0`.

This spec is the source of truth for:
- mountain silhouette and elevation field
- mountain identity (`mountain_id`)
- roof presentation layer and cover visibility lifecycle
- excavation and opening / cavity derivation
- persistence of worldgen settings
- runtime classification for all of the above

Detailed background and alternatives are documented in
`MOUNTAIN_GENERATION_ARCHITECTURE.md` (design_proposal). This spec
references that file only for historical reasoning; all binding rules live
here.

## Gameplay Goal

The player must be able to:
- see large continuous mountain ranges generated deterministically from
  `world_seed + world_version + worldgen_settings.mountains`
- start a new world on a small plains-only spawn-safe patch around the
  initial player tile so the first frame never places the player inside a
  mountain roof or wall packet
- dig into a mountain with the existing single-tile mutation path, and have
  the excavation persist across save/load
- when standing on an entrance tile, count as inside immediately with no
  extra step or reveal delay
- from outside, see only real mouth / opening holes; the rest of the
  interior stays hidden behind the mountain's crown texture
- when inside, fade the construction roof only above the current connected
  orthogonal cavity; the live organic remaining mass keeps supplying every
  facade and cave wall, while foreign cavity interiors remain sealed
- tune mountain density, scale, continuity, and ruggedness at world
  creation; the settings travel with the save and cannot be retroactively
  changed by repository edits

## Scope

V1 is an **additive** extension of V0. It adds:
- native mountain field in `WorldCore` (elevation, ridge, domain warp)
- versioned mountain identity:
  deterministic sparse anchors for legacy worlds and implicit-domain
  hierarchical labeling for `world_version >= 6`
- `ChunkPacketV1` with three additive fields, no V0 field removed
- new surface terrain ids: `TERRAIN_MOUNTAIN_WALL`, `TERRAIN_MOUNTAIN_FOOT`
- roof presentation layer in `ChunkView`, one `TileMapLayer` per
  `mountain_id` inside a chunk
- `MountainCavityCache` runtime-derived opening / cavity component cache
- `MountainResolver` O(1) per-step point-in-cavity lookup from player tile
- mask-only roof reveal driven by current cavity or outside opening state
- `MountainGenSettings` resource + `worldgen_settings.mountains` section
  in `world.json`
- bump `WORLD_VERSION` from `1` to `2` for M1, then to `3` for the
  named-mountain ownership fix, then to `4` for retirement of the
  standalone plains-rock generation path, then to `5` for the spawn-safe
  carveout, then to `6` for hierarchical mountain-domain labeling

## Out of Scope

V1 does not include:
- water generation, multiple biomes, climate data, biome blend logic
- SDF or door-opening spatial reveal effects (deferred polish; requires a
  separate spec amendment to pursue)
- propagation of surface `mountain_id` to `z != 0` as canonical identity
  (ADR-0006 boundary; only a cheap generation modifier is allowed)
- node-per-mountain debug visualization beyond a single debug metric
- changes to building placement, power, combat, or room systems
- Z-level linking beyond what V0 and ADR-0006 already define
- renumbering legacy terrain ids or changing `ChunkDiffV0` shape
- changes to `BuildingSystem`, `PowerSystem`, `IndoorSolver`
- migration from legacy pre-rebuild `64 x 64` saves

## Dependencies

- `World Runtime V0` for the end-to-end chunked runtime that V1 extends
- `World Grid Rebuild Foundation` for the `64 px` tile / `16 x 16` chunk
  contract
- ADR-0001 for runtime work classes and dirty-update rules
- ADR-0002 for wrap-safe X sampling
- ADR-0003 for immutable base + runtime diff ownership
- ADR-0005 for darkness contract inside mountain interiors
- ADR-0006 for the surface / subsurface separation that V1 must respect
- ADR-0007 for keeping mountain generation distinct from environment
  runtime

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical, runtime overlay, or visual only? | Field, identity, flags, and atlas indices are canonical. Cavity component membership, opening flags, and active viewer state are runtime-derived overlay. Roof cells are visual only. |
| Save/load required? | Yes, for `worldgen_settings.mountains` in `world.json`. No for cavity cache, opening cache, or active cover state. |
| Deterministic? | Yes. Field, identity, and atlas indices are pure `f(seed, world_version, coord, settings_packed)`. |
| Must work on unloaded chunks? | Yes. All per-tile canonical data is recomputable from base + diff on demand. |
| C++ compute or main-thread apply? | Field sample, hierarchical domain solve / legacy anchor fallback, and atlas indices are C++ compute. Roof cell placement, chunk mask upload, and cavity/opening cache refresh are main-thread apply. |
| Dirty unit | `16 x 16` chunk for generation; one tile for excavation mutation; one loaded chunk plus direct seam-neighbor diff participants for publish / unload; one current cavity component for inside reveal. |
| Single owner | `WorldCore` for base field. `WorldDiffStore` for diff. `ChunkView` for static roof presentation and per-chunk mask material. `MountainCavityCache` for runtime-derived cavity/opening state. `WorldStreamer` for active cover selection. `world.json` for `worldgen_settings`. |
| 10x / 100x scale path | Version `6` keeps identity on aligned macro solves with reusable native cache, recursive subdivision only for mixed cells, and versioned `min_label_cell_size = 8`. Publish inherits V0 slicing. No whole-world scan is introduced. |
| Main-thread blocking? | No. Generation stays in the existing worker path. Apply remains sliced through `FrameBudgetDispatcher.CATEGORY_STREAMING`. |
| Hidden GDScript fallback? | Forbidden. Native `WorldCore` is required; absence fails loudly per LAW 9. |
| Could it become heavy later? | Yes. Noise octaves, hierarchical leaf count, and revealed cavity size scale. All stay inside native generation or bounded cache refresh; movement-time work remains cached lookup only. |
| Whole-world prepass? | Forbidden. All field and identity work is local to one chunk plus a bounded aligned macro halo reused through `WorldCore`. |

## Core Contract

### Chunk Geometry

Unchanged from `world_grid_rebuild_foundation.md`:
- one world tile = `64 px`
- one chunk = `16 x 16` tiles
- chunk-local cell coordinates `0..15`
- world X wraps (ADR-0002); world Y does not

### Terrain IDs

V1 adds two surface terrain ids:

| Id constant | Walkable | Used for |
|---|---|---|
| `TERRAIN_MOUNTAIN_WALL` | 0 | Every tile with `mountain_id > 0` and `is_wall` bit set. Rendered on `_base_layer` with rock-face atlas. |
| `TERRAIN_MOUNTAIN_FOOT` | 0 | Foot-band tiles visible from outside. `mountain_id > 0`, `is_foot` bit set, no `is_interior` bit. They still participate in the static roof overlay so dug foot-band tunnels stay hidden until cover visibility opens them. |

Legacy terrain slot `1` remains reserved for backward numeric compatibility,
but new mountain worlds do not generate a standalone plains-rock terrain
class. Mountain tiles never use a separate scattered-rock fallback.

Integer values are assigned in `world_runtime_constants.gd` as part of the
M1 implementation task.

### ChunkPacketV1

`ChunkPacketV1` extends `ChunkPacketV0` additively. No V0 field is removed
or reshaped.

V0 fields remain as defined in `world_runtime.md`:

| Field | Type | Length |
|---|---|---|
| `chunk_coord` | `Vector2i` | — |
| `world_seed` | `int` | — |
| `world_version` | `int` | — |
| `terrain_ids` | `PackedInt32Array` | 256 |
| `terrain_atlas_indices` | `PackedInt32Array` | 256 |
| `walkable_flags` | `PackedByteArray` | 256 |

V1 additive fields:

| Field | Type | Length | Notes |
|---|---|---|---|
| `mountain_id_per_tile` | `PackedInt32Array` | 256 | `0` = not mountain. Non-zero = deterministic `mountain_id`. |
| `mountain_flags` | `PackedByteArray` | 256 | Bit 0 `is_interior`, bit 1 `is_wall`, bit 2 `is_foot`, bit 3 `is_anchor`. Other bits reserved. |
| `mountain_atlas_indices` | `PackedInt32Array` | 256 | Atlas indices for the roof `TileMapLayer`. Derived via `autotile_47` on `mountain_id` adjacency. |

Forbidden packet fields in V1 (reserved for later specs):
- climate bytes, water-generation masks, biome blend data
- placements, decor batches, connector requests
- subsurface data
- `is_opening` / `component_id` (derived, runtime-only cover state)

### Mountain Field

`WorldCore` exposes one logical field solve, executed inside
`generate_chunk_packets_batch`:

```text
sample_elevation(seed, world_version, wx, wy, settings_packed) -> float
```

Rules:
- pure function; no state other than inputs
- wrap-safe on X via `wrap_x(wx, world_width_tiles)`
- for `world_version >= 10`, `world_width_tiles` is the saved finite
  `worldgen_settings.world_bounds.width_tiles`; `world_version <= 9`
  is a historical algorithm path and is not load-compatible under the active
  pre-alpha save policy
- combines:
  1. `domain warp` FBM on `(wx, wy)` using `settings.continuity`
  2. `macro FBM` on warped coordinates at wavelength `settings.scale`
  3. `ridge noise` weighted by `settings.ruggedness` and gated by the
     macro value so ridges only appear inside already-elevated regions
  4. optional latitude bias on Y per `settings.latitude_influence`
- thresholds `t_edge` and `t_wall` are derived from `settings.density` and
  `settings.foot_band`; implementation must document the derivation in
  code comments inside `mountain_field.cpp`

Classification per tile:
- `elevation >= t_wall` → candidate for `TERRAIN_MOUNTAIN_WALL`
  (subject to identity assignment below)
- `t_edge <= elevation < t_wall` → candidate for
  `TERRAIN_MOUNTAIN_FOOT`
- `elevation < t_edge` → plains terrain per V0 pipeline

### Mountain Identity

Mountain identity in the active packet runtime is hierarchical
(`world_version >= 6`):
- world space is divided into aligned power-of-two cells
- `WorldCore` keeps a reusable native cache keyed by a central
  `1024 x 1024` macro cell; each cache entry solves one interior macro cell
  plus a deterministic `1`-macro halo on every side
- each cell is classified by a bounded probe stencil as `empty`, `solid`,
  or `mixed`
- only `mixed` cells recurse
- recursion stops at the versioned internal
  `min_label_cell_size = 8`
- on `min_label_cell_size`, a bounded `5 x 5` local ambiguity solve may
  collapse local boundary/noise back to `empty` or `solid` without reading
  outside the leaf
- canonical mountain domains are the face-connected components of `solid`
  leaves on that hierarchical solve; diagonal-only contact never connects
- each component chooses a deterministic representative leaf by maximal
  representative elevation, tie-break by lexicographic leaf cell
  coordinate
- `mountain_id` is a deterministic 32-bit hash of
  `(seed, world_version, representative_cell_origin, representative_cell_size)`

Per-tile assignment for `world_version >= 6`:
- if `sample_elevation < t_edge`, `mountain_id = 0`
- otherwise the tile inherits the domain of its resolved hierarchical leaf
  cell inside the cached macro interior
- sub-`8`-tile bridges, raw-anchor noise, and local irregularities that fail
  the leaf ambiguity solve stay at `mountain_id = 0` instead of spawning a
  separate canonical mountain
- active mountain worlds must not emit a standalone scattered-rock terrain
  fallback for elevated tiles; `mountain_id = 0` above `t_edge` is now the
  explicit scale cutoff, not an anonymous-owner fallback
- `world_version == 45` is the historical first satellite-outcrop boundary.
- `world_version == 46` is the historical first clustered satellite-outcrop
  boundary.
- `world_version == 47` is the historical strengthened satellite-outcrop
  boundary: sparse groups of `2..20` separate deterministic `3..18`-tile
  components generated from native anchor cells in the outer ring of an
  existing main mountain.
- `world_version >= 48` is the active mountain passage/outcrop refinement
  boundary. It keeps the same packet shape, strengthens satellite outcrop
  clustering frequency and placement variation, and adds deterministic native
  mountain carve masks for walkable passages, pockets, and gorges. These cuts
  run before final terrain classification, so carved tiles become ordinary
  ground/lake packet tiles instead of visual overlays. Outcrops remain
  deterministic mountain components with their own `mountain_id`; carved
  passages remain `mountain_id = 0`.

Identity is base data. It never mutates in response to diff, excavation,
or runtime events (LAW 5).

### Interior, Wall, Foot, Anchor Flags

For every tile with `mountain_id > 0`:
- `is_wall` = 1 iff `elevation >= t_wall`
- `is_foot` = 1 iff `t_edge <= elevation < t_wall`
- `is_interior` = 1 iff `is_wall` and the 4-neighbor Chebyshev distance
  into the wall region is `>= settings.interior_margin`
- `is_anchor` = 1 iff the tile is the representative tile of the
  component's deterministic representative leaf (field name retained for
  packet compatibility)

For every tile with `mountain_id == 0`:
- `mountain_flags = 0`
- `mountain_atlas_index = 0`
- canonical terrain stays on the ground / non-mountain path

Tiles with `mountain_id > 0` and either `is_wall == 1` or `is_foot == 1`
participate in the roof layer.

### Worldgen Settings

`MountainGenSettings` is a `Resource` with the following exported fields
and ranges:

| Field | Range | Meaning |
|---|---|---|
| `density` | `0.0..1.0` | Shifts elevation thresholds; higher = more mountains. |
| `scale` | `32.0..2048.0` | Macro noise wavelength; higher = larger mountain footprints. |
| `continuity` | `0.0..1.0` | Domain warp strength; higher = more elongated ranges. |
| `ruggedness` | `0.0..1.0` | Ridge weighting; higher = spikier silhouettes. |
| `anchor_cell_size` | `32..512` | Tile-size of an anchor cell. |
| `gravity_radius` | `32..256` | Legacy owner-radius control for pre-`4` worlds; retained in the packed settings layout for versioned compatibility. |
| `foot_band` | `0.02..0.3` | Elevation width of the foot band. |
| `interior_margin` | `0..4` | Tiles of wall depth required before a tile counts as interior. |
| `latitude_influence` | `-1.0..1.0` | Y-axis latitude bias. |

Defaults live in `data/balance/mountain_gen_settings.tres`. These defaults
apply **only to new worlds**. Existing saves always load their own
embedded copy from `world.json` (see Persistence Contract).

Settings are flattened into `settings_packed: PackedFloat32Array` before
crossing the native boundary, in a fixed canonical order defined by
`world_runtime_constants.gd`.

## Runtime Architecture

### Native Boundary

V1 keeps one native class, `WorldCore`. Active packet generation uses:

```text
WorldCore.generate_chunk_packets_batch(
    seed: int,
    coords: PackedVector2Array,
    world_version: int,
    settings_packed: PackedFloat32Array
) -> Array
```

Rules:
- one batch returns one `ChunkPacketV1` per input coord, in input order
- no per-tile callbacks, no multiple Variant round-trips
- settings are read once per batch, not per tile
- the active packet runtime requires the full `settings_packed` layout
- the active packet runtime requires `world_version >= 6`
- batch generation groups chunks by owning macro cell and reuses cached
  `1024 x 1024` hierarchical solves through `WorldCore`
- no second native class is introduced in V1

### Script Ownership

| Role | Owner | Responsibility |
|---|---|---|
| Base field, identity, flags, atlas | `WorldCore` (native) | Emit V1 packet. |
| Diff | `WorldDiffStore` | Unchanged from V0. |
| Chunk orchestration | `WorldStreamer` | Forward new packet fields; flatten settings; persist settings in `world.json`. |
| Presentation | `ChunkView` | Keep the live organic remaining mass `V` for BASE facade, collision and mining sampling; lazily own the immutable closed-roof mask `C`, the displayed-component selector halo, and the visual-only `ROOF` sprite. |
| Runtime cover cache | `MountainCavityCache` | Derive orthogonal cavity component membership from canonical mountain ownership + excavation diff. Legacy opening/shell metadata is diagnostic only and does not drive the construction roof. |
| Point-in-cavity lookup | `MountainResolver` | Per-frame derive current cavity component from the exact floor tile or the bounded organic `C-V` fringe around it; update immediate target cover selection. |

### Roof Presentation

The active cover presentation is the M7-organic construction-roof model. It
adds a second, presentation-only mask pass on top of the unchanged live
organic mask; the excavation look, collision and mining truth do not change.

- The live per-chunk native mask `V` (remaining mass) is built exactly as
  before M7: one `build_mountain_halo_mask` worker call over the post-diff
  `remaining_halo` (`mountain_id > 0 && flags & (WALL|FOOT) && not dug`).
  `V` keeps its organic re-blur contour after every excavation and remains
  the single source for `BASE` rendering, facade collision band, and mining
  samples. No square-tile hard clears, no native aperture mask, and no
  directional mouth metadata are introduced.
- The immutable closed roof `C` is the same native recipe over the
  `closed_halo` (`mountain_id > 0 && flags & (WALL|FOOT)`, ignoring diff).
  It is byte-identical to what `V` was before the first excavation and never
  changes while digging deeper. The worker builds `C` inside the same queued
  mask request as a second `build_mountain_halo_mask` invocation, only for
  chunks whose halo contains at least one dug mountain-owned cell
  (`dug_halo` non-empty). Zero-dug chunks keep the single legacy `BASE`
  pass and allocate no roof textures or sprite.
- `ChunkView` renders two sprites with the same origin and material shader:
  - `BASE(V)` is unchanged: physical outer/inner facade, roof surface of the
    remaining mass, eave, projected sun shadow;
  - `ROOF(C, V_ref, R_displayed, b)` is visual-only. It computes top geometry,
    normals and colour from immutable `C`, suppresses its own structural
    facade band and eave (the live `BASE(V)` facade owns the real mouth, so a
    dug entrance is never re-covered by the old facade), and draws no
    projected sun shadow. Its `C-V` residual and live-facade cover are separate
    alpha contributions with separate ownership proofs; combining ownership
    first is forbidden because it can reveal an adjacent cavity.
  - The residual uses over-compositing alpha
    `(closed_target_alpha - live_top_alpha) / (1 - live_top_alpha)` when the
    numerator is positive. Thus `BASE + ROOF` reconstructs one `C` pass rather
    than double-brightening unchanged mountain pixels.
  - `owned_organic_cutout` is the pixel-exact `C - V` excavation delta gated
    by the displayed selector tile or a guarded `3 x 3` fringe, so the reveal
    boundary follows the organic excavation contour, never the square tile
    selector. An exact foreign tile always wins; ambiguous active+foreign
    neighbour fringes remain closed. Diagonal fringe ownership is allowed for
    continuous raster corners but never connects cavity components.
  - Internal-facade cover first uses `dug_halo` only as a bounded `3 x 4`
    broad phase, then proves the wall from the full-resolution organic `C-V`
    delta immediately beyond the SOUTH-facing `BASE(V)` edge. Its alpha owner
    is binary, so a partially covered wall cannot bleed through the roof.
    The displayed selector and its guarded `3 x 3` fringe control reveal only;
    an active+foreign ambiguity remains closed.
  - The cover is clipped by `C`'s original structural-facade band. A facade
    pixel that existed before digging is never replaced with top texture even
    when a new entrance touches it; only a new internal `BASE(V)` facade
    outside that band is covered. Therefore the unchanged BASE facade remains
    the sole point-light/torch receiver and ROOF neither darkens nor doubles it.
  - `BASE(V)` sun-side bevel colour can extend into still-solid pixels around a
    newly dug edge even where top alpha is unchanged. ROOF compares the exact
    full-resolution `C` and `V` probes used by `side_shade_reach_px` and adds a
    colour-replacement contribution only where their signed bevel differs.
    This organic contribution is clipped by the same original-facade rule and
    uses guarded component ownership for reveal; a tile-shaped affected band
    is forbidden.
- Outside (`R_displayed = 0`, `b = 0`) the effective top silhouette follows
  immutable `C` while the original structural facade remains live `BASE(V)`:
  tunnel depth stays hidden and the real entrance/facade stays readable.
- `BASE`/page remain at `Z_MOUNTAIN_TOP = 19`; `ROOF` uses the dedicated
  `Z_MOUNTAIN_ROOF = 20`, below the player/decor depth ladder (`21+`). This
  guarantees `BASE < ROOF` across chunk boundaries independently of sibling
  publication order while preserving the approved exterior mountain/object
  occlusion contract.
- `ROOF` keeps the existing three-pixel anti-crack body overlap, but
  neighbouring roof chunks apply complementary edge/corner ownership weights.
  Each share uses `1 - (1 - alpha)^weight`; weights sum to one, so the overlap
  reconstructs exactly one roof contribution instead of a rectangular seam.
- The permanent foothill footprint is captured from immutable `C` when the
  dual state exists, so the outer apron does not shrink with excavation.
- The ordinary ground `_base_layer` remains visible below every cutout. Black
  fill, clear-color holes and entrance decals are forbidden.
- Collision, resolver and mining keep sampling the live mask bytes; the roof
  selector, `C`, and the reveal blend are presentation-only and never enter
  gameplay truth.
- The legacy `roof_layers_by_mountain` tile presentation remains disabled
  compatibility state; it is not an authoritative or active cover path.
- aggregated alpha per chunk remains **forbidden** for tile layers; the
  component reveal blend is a per-material uniform over the displayed
  component chunks, not a tile-layer alpha.

### Cover Cache and Visibility

- `MountainCavityCache` is runtime-derived only; it never mutates canonical
  packet fields
- required runtime cache surfaces:
  - tile -> `component_id`
  - component -> authoritative excavated member tiles and touched chunks
- outside state is `R_displayed = 0` and `b = 0`; `ROOF` therefore restores
  immutable `C` top geometry with no selector exception while leaving `C`'s
  original structural-facade band to `BASE(V)`
- inside state uses `R_displayed = displayed_component.tiles` only; shell,
  opening shell and outside-visible fields must not be copied into the roof
  selector
- the tile reveal halo is `32 x 32` L8 bytes: chunk `16 x 16` plus the same
  `8`-tile native halo on every side; it shares UV/world origin with `C` and
  the live mask
- the per-chunk `dug_halo` (all excavated mountain-owned cells regardless of
  component) rides along as the foreign-cutout guard. Component ownership is
  nearest/binary; full-resolution `C-V` carries the organic feather, so the
  tile selector itself is never linearly softened into a foreign excavation
- diagonal-only contact never connects cavity components
- adjacent mountains must remain independent because component membership is
  constrained by stable canonical `mountain_id`
- component ids are transient and may change after merge/reload; membership,
  not the numeric id, is the contract
- component floor chunks are cached incrementally, and per-chunk selectors use
  fixed `16 x 16` membership lookups; enter/exit must not rescan every tile
  once per component chunk
- Resolver ownership and presentation state are deliberately split:
  - `target_component`/active cover changes immediately and remains
    authoritative for gameplay reads;
  - `displayed_component` retains the component whose roof is currently
    fading;
  - `component_reveal_blend b` is presentation-only and never rebuilds native
    masks or enters persistence.
- Enter opens `b: 0 -> 1` over `150 ms` with cubic-out easing. Exit holds for
  `60 ms`, then closes `b: 1 -> 0` over `180 ms` with cubic-in-out easing.
  Re-entering the same component reverses from the current value without a
  jump. A different mountain closes the displayed component fully before
  installing and opening the new selector. A component-id repair inside the
  same mountain swaps selector membership without closing the roof.
- Opening alpha does not advance until the deferred displayed-selector upload
  is ready. Selector updates are generation-staged per affected chunk: GPU
  textures upload privately through the bounded visual queue, then every
  texture uniform in that generation is swapped synchronously on the main
  thread only after the complete set is ready. Superseded generations cannot
  commit. New/reloaded `ChunkView` instances remain behind the same visibility
  gate and receive the current `b` before their roof material is created,
  preventing chunkwise rectangles, one-frame closed roofs and wrong-cavity
  flashes.

### Mountain Resolver

- `MountainResolver` is invoked once per frame from
  `Player._physics_process`
- steps:
  1. convert player world position to tile, chunk, and local coord
  2. query cached cover sample for that tile; if the chunk is not loaded, do
     nothing
  3. treat `component_id > 0` as inside immediately, including when standing
     on an entrance tile
  4. if the exact tile has no component, sample immutable `C` and the live
     raw mask (without facade-collision projection) at the player position;
     only when `C` is solid and the live mask is open, inspect the fixed
     `3 x 3` tile neighbourhood and prefer the previous component. Fallback
     distance uses wrapped X and ordinary Y distance under ADR-0002. This
     retains ownership in a real organic excavated corner without keeping the
     roof open on ordinary exterior ground
  5. when the component changes, update `WorldStreamer` target selection
     immediately; the presentation controller independently retains and fades
     `displayed_component`

Resolver does bounded O(1) work per frame (one exact sample, two raster
samples, at most eight cached neighbour samples); no flood fill, scene-tree
query, or raycast is allowed on the hot path.

### Excavation and Opening Derivation

- V0 interactive path (`try_harvest_at_world`) remains unchanged in
  structure
- after a tile mutation, the runtime cover cache refreshes only the mutated
  tile, its local cardinal neighborhood, and the affected cavity metadata
- `is_opening` is a derived runtime flag:
  - the tile must be `mountain_id > 0`, belong to canonical mountain
    geometry (`is_wall == 1 or is_foot == 1`), and be walkable
  - at least one walkable cardinal neighbor must exit the current mountain
    cover domain (`mountain_id != self` or neighbor has neither
    `is_wall` nor `is_foot`)
- component membership is cached from walkable mountain-owned tiles only and is
  never written back into packet or diff
- orthogonal excavation that joins two cavity components merges them into one
  visible cavity; diagonal-only contact does not
- cover updates after mutation must not use mass `set_cell`, `TileMap.clear`,
  or loaded-world global rebuilds

### Streaming and Apply

- mountain packet fields travel through the existing V0 chunk publish
  path unchanged
- the `V` (+ optional `C`) mask compute travels through the existing worker
  mask queue with one revision/inflight/cache key per chunk; a chunk with any
  dug mountain-owned halo cell performs two bounded native mask builds inside
  the same worker request
- no new `FrameBudgetDispatcher` category is introduced; roof/selector
  texture uploads reuse the existing mountain visual-upload queue and budget
- on chunk publish / unload, update only the published or unloaded chunk plus
  direct seam-neighbor diff participants needed to refresh cavity metadata
- on a displayed-component transition, refresh only the union of old/new
  component chunks expanded by one chunk for the native halo; an empty target
  list must never mean "scan every loaded ChunkView"
- a newly published chunk with roof-bearing mountain metadata remains hidden
  only while its native mountain visual (including roof/selector state) is
  pending. Plain/shore chunks never enter this gate. After the visual is
  installed the view becomes visible and only then emits `chunk_loaded`,
  preventing a one-frame closed-roof or stale-selector flash on reload
- publish/prefetch mask gating keys on the closed (ownership) halo, so a
  fully excavated local mountain still publishes its closed roof
- `TileMapLayer.clear()` remains forbidden on runtime mutation paths

## Persistence Contract

### world.json Extension

`world.json` schema grows by one field. `world_seed` and `world_version`
remain as V0 defined them.

```json
{
  "world_seed": 42,
  "world_version": 3,
  "worldgen_settings": {
    "mountains": {
      "density": 0.30,
      "scale": 512.0,
      "continuity": 0.65,
      "ruggedness": 0.55,
      "anchor_cell_size": 128,
      "gravity_radius": 96,
      "foot_band": 0.08,
      "interior_margin": 1,
      "latitude_influence": 0.0
    }
  }
}
```

Rules:
- `worldgen_settings` is namespaced from the start
  (`mountains`, later `biomes`, `climate`)
- current-version load requires `worldgen_settings.mountains`; missing settings
  fail instead of using hard-coded compatibility defaults or re-reading
  `data/balance/mountain_gen_settings.tres`
- on new game, `WorldStreamer` writes the current resource's values
  exactly once into `world.json`, then never re-reads that resource for
  that world
- optional `worldgen_signature: String` may be written for diagnostics;
  it is not authoritative and absence is always valid

### chunks/*.json Unchanged

Chunk diffs keep `ChunkDiffV0` shape. Forbidden additions:
- `is_opening`
- `component_id`
- `mountain_id`
- `mountain_flags`
- any other derived presentation state

### WORLD_VERSION

- `WORLD_VERSION` bumped from `1` to `2` when M1 landed
- `world_version == 1` stays on the V0 no-mountains path
- `world_version == 2` preserves the original M1/M2 mountain output
- `WORLD_VERSION` bumps from `2` to `3` for the named-mountain ownership
  fix, because anonymous high-elevation shoulders now fall back to the V0
  scattered-rock path instead of emitting mountain terrain without
  `mountain_id`
- `WORLD_VERSION` bumps from `3` to `4` for retirement of the active
  plains-rock worldgen path: new worlds no longer emit a standalone
  scattered blocked terrain class, and owner-anchor resolution widens so
  elevated mountain terrain resolves into named mountain output
- `WORLD_VERSION` bumps from `4` to `5` for the spawn-safe carveout:
  tiles in the initial `12..20 x 12..20` start patch force
  `sample_elevation = 0.0`, `mountain_id = 0`, and zero mountain flags so
  the starting packet cannot place the player inside mountain output
- `WORLD_VERSION` bumps from `5` to `6` for implicit-domain hierarchical
  labeling: new worlds no longer derive canonical `mountain_id` from raw
  nearest-anchor ownership and instead hash the deterministic representative
  leaf of a bounded hierarchical mountain domain solve
- `WORLD_VERSION` bumps from `9` to `10` for finite-cylinder mountain aspect
  normalisation: new V1 worlds sample mountain elevation, hierarchical
  identity, and mountain atlas coordinates in the saved finite world width
  instead of remapping finite X into the legacy `65536`-tile sample width.
  `world_version == 9` remains a historical algorithm boundary; the active
  pre-alpha loader rejects non-current saves instead of preserving legacy
  save-load compatibility.
- `WORLD_VERSION` bumps from `10` to `11` in `world_foundation_v1.md` for the
  high-resolution foundation substrate (`64`-tile cells) and native overview
  image pass. Mountain sampling semantics remain the `world_version >= 10`
  finite-width path.
- `WORLD_VERSION` bumps from `44` to `45` for sparse satellite outcrops:
  deterministic `3..10`-tile mountain components may spawn in the outer ring
  around large mountain masses. They use the existing `mountain_id`,
  `mountain_flags`, terrain id, collision, and excavation contracts; they are
  not visual decals and do not add packet or save fields.
- `WORLD_VERSION` bumps from `45` to `46` for clustered satellite outcrops:
  sparse groups of `2..6` separate deterministic `3..10`-tile mountain
  components may spawn near large mountain masses, with varied compact,
  elongated, L-like, and tapered footprints. They keep the same packet and
  save shape as ordinary mountains.
- `WORLD_VERSION` bumps from `46` to `47` for strengthened satellite outcrop
  clusters: deterministic groups now target `2..20` separate `3..18`-tile
  mountain components, are biased toward `10..20` components, and allow
  occasional larger footprints. They keep the same packet and save shape as
  ordinary mountains.
- `WORLD_VERSION` bumps from `47` to `48` for mountain passage/outcrop
  refinement: outcrop clusters become more frequent and spatially varied, and
  native deterministic carve masks create passages, pockets, and gorges inside
  base mountain masses. The packet/save shape remains unchanged because the
  result is still expressed through existing `terrain_ids`, `walkable_flags`,
  `mountain_id_per_tile`, and `mountain_flags`.
- each bump is required by LAW 4 because canonical terrain / packet
  output changes for the same `seed + coord`
- `world_version` remains a plain integer; it is **not** a hash of
  `worldgen_settings`

### Cover Runtime State

- `MountainCavityCache` state is transient; not persisted
- target/displayed cover selection, transition state and reveal blend are
  transient; not persisted
- `closed_roof_mask`, selector halos, `dug_halo`, GPU textures and worker
  revisions are transient derived data; none enter `world.json` or
  `chunks/*.json`
- after load, derived cavity / opening state is rebuilt from loaded packet +
  diff data during publish
- a player restored on a mountain-owned dug tile must resolve the rebuilt
  component before that chunk's first visible roof state; no save payload
  stores reveal / cover state or relies on stable numeric `component_id`

## Event Contract

Existing world signals are reused unchanged:
- `world_initialized(seed_value: int)`
- `chunk_loaded(chunk_coord: Vector2i)`
- `chunk_unloaded(chunk_coord: Vector2i)`

No mountain-specific `EventBus` reveal lifecycle is part of the current V1
contract.

## Performance Class

| Operation | Class | Dirty unit | Budget |
|---|---|---|---|
| Mountain field sample | background (native worker) | 32x32 chunk | outside main thread |
| Hierarchical mountain-domain solve | background (native worker) | aligned `1024 x 1024` macro cell interior with cached `1`-macro halo | outside main thread |
| Satellite outcrop solve | background (native worker) | current chunk candidate anchor cells | outside main thread |
| Passage / pocket / gorge carve solve | background (native worker) | current chunk `32 x 32` mountain sample grid plus bounded nearby `32`-tile anchors | outside main thread |
| Sliced mountain publish | background apply | batch of cells | shares V0 `CATEGORY_STREAMING` budget |
| Closed roof mask `C` (dug chunks only) | background (native worker) | one `32 x 32` tile halo / chunk revision, second bounded build in the same request | outside main thread |
| Resolver tile lookup | interactive | 1 tile + bounded organic-fringe fallback | < 0.05 ms/frame |
| Roof reveal upload on state switch | background apply | old/new component chunks + one-chunk halo | existing mountain visual-upload budget; no native rebuild |
| Roof reveal alpha transition | interactive presentation | one uniform on displayed component chunks | `150 ms` enter; `60 ms` exit delay + `180 ms` close; no mask rebuild |
| Excavation mutation | interactive | 1 tile + native-halo seam neighbours | V0 budget, unchanged; native/GPU follow-up queued |
| Cavity/opening cache refresh on mutation | interactive | local dirty neighborhood + affected component metadata | < 1.0 ms at normal scale |
| Cavity/opening rebuild on publish / unload | boot/load | published/unloaded chunk plus direct seam participants | loading / streaming only |

### Forbidden Runtime Paths

- per-tile `Tween` on reveal
- per-tile `set_cell` during cover updates
- flood-fill over interior tiles on enter / movement
- chunk-wide rescan on every player step
- global rebuild of loaded-world cavity visibility on every publish / unload
- all-loaded-chunk reveal sweep on enter, exit or one-tile excavation
- synchronous native-mask generation or `ImageTexture` upload in the mining
  input frame
- CPU composition of `C`, `V` and the selector into a replacement
  collision/render mask
- `mountain_id` recompute on mutation
- cover state in save payload
- autotile-47 pass during cover updates (atlas indices are precomputed at
  generation time)
- direct scene-tree queries to decide current mountain

## Acceptance Criteria

### Deterministic Generation

- [ ] same `(seed, world_version, worldgen_settings.mountains)` always
      yields identical tile layout across sessions
- [ ] each of the four primary settings (`density`, `scale`, `continuity`,
      `ruggedness`) produces a measurable and visible change when varied
      alone
- [ ] `world_version` bump produces a reproducibly different field

### Identity

- [ ] any two spatially adjacent but logically separate mountains produce
      different `mountain_id` values
- [ ] sparse satellite outcrops appear as independent `3..18`-tile
      mountain components in `2..20`-component groups near large mountain
      masses at density `0.60`, with at least one deterministic probe group
      in the `10..20` range
- [ ] deterministic passage/pocket/gorge cuts produce walkable ground/lake
      packet tiles inside or through mountain masses at density `0.60`
- [ ] a single mountain's `mountain_id` is stable across chunk seams
- [ ] `mountain_id` does not change after initial generation, including
      after excavation that fully bisects a mountain

### Cover Visibility

- [ ] outside mountain: `BASE(V)` keeps the dug mouth readable with the real
      ground floor visible; no black/clear-color fill appears
- [ ] outside mountain: `ROOF(C)` hides the tunnel depth; no interior cavity
      leaks through the cover, and the old facade is not re-drawn over a dug
      entrance
- [ ] an original `C` structural-facade pixel is never replaced by ROOF top
      texture and retains the established BASE point-light/torch response;
      a newly exposed internal `V` facade outside that band is fully covered
- [ ] no live `V` sun-side bevel/edge line remains visible through CLOSED
      roof top; the active bevel returns in OPEN and foreign bevels stay closed
- [ ] standing on an entrance tile updates target ownership immediately
- [ ] entering a cavity reveals only the full connected orthogonal cavity
      with the specified `150 ms` cubic-out fade
- [ ] leaving retains the displayed selector for `60 ms`, closes it over
      `180 ms` cubic-in-out, then restores a roof pixel-identical to the
      initial outside state
- [ ] the reveal boundary follows the organic excavation contour (`C - V`),
      not the square tile selector
- [ ] separate cavities remain isolated while inside one of them
- [ ] foreign cavity interiors remain hidden while inside a current cavity
- [ ] the active cavity's internal SOUTH facade is identical to `BASE(V)`
      while revealed; a neighbouring cavity's facade remains covered
- [ ] adjacent mountains behave independently
- [ ] rapid exit/re-entry reverses from the current blend without a jump, and
      a different mountain closes before its selector is replaced
- [ ] cover state is not written to the save payload

### Excavation

- [ ] digging a new mouth makes the opening visible from outside without
      revealing the whole cavity
- [ ] remaining interior tiles stay covered while the mountain is sealed
      from outside
- [ ] the live organic excavation contour (`V` re-blur after every dig) is
      byte-identical to the pre-M7 behaviour; no square-tile visual clears
      are introduced
- [ ] orthogonal excavation that joins two cavities makes them reveal as one
- [ ] diagonal-only contact does not merge passability or visibility
- [ ] reveal never becomes the source of truth for wall geometry, collision,
      mining, or autotile-47 presentation

### Persistence

- [ ] `new game` writes `worldgen_settings.mountains` into `world.json`
      exactly once
- [ ] loading a V0 save (no `worldgen_settings`) succeeds with hard-coded
      defaults
- [ ] loading a V1 save after the repository's
      `mountain_gen_settings.tres` has been edited produces the original
      world, not the edited defaults
- [ ] excavation diff survives save/load; cavity / opening runtime state is
      reconstructed correctly after load

### Performance

- [ ] native chunk packet generation stays off the main thread
- [ ] player movement does not trigger flood fill or broad rescan
- [ ] chunk publish / evict do not trigger full loaded-world cover rebuild
- [ ] interactive excavation including cover-cache refresh completes under
      `1.0 ms` at p95
- [ ] `roof_layers_per_chunk_max > 24` emits exactly one warning per
      session, not per frame
- [ ] no measurable regression in V0 acceptance tests when
      `worldgen_settings.mountains.density = 0.0`

### Governance Compliance

- [ ] LAW 9: no GDScript fallback for `WorldCore`; absence asserts
- [ ] LAW 4: `WORLD_VERSION` bump included in the same task that lands
      mountain generation
- [ ] ADR-0006: no surface `mountain_id` is written to `z != 0` state
- [ ] ADR-0007: mountain generator does not read environment runtime

## Files That May Be Touched In The First Implementation Task

### New
- `gdextension/src/third_party/FastNoiseLite.h`
- `gdextension/src/mountain_field.h`
- `gdextension/src/mountain_field.cpp`
- `core/resources/mountain_gen_settings.gd`
- `data/balance/mountain_gen_settings.tres`
- `core/systems/world/mountain_cavity_cache.gd`
- `core/systems/world/mountain_resolver.gd`

### Modified
- `gdextension/SConstruct`
- `gdextension/station_mirny.gdextension`
- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `core/systems/world/world_runtime_constants.gd`
  (bump `WORLD_VERSION` to `3`; add new terrain ids, flag bit constants,
  `settings_packed` layout constants)
- `core/systems/world/world_streamer.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `core/entities/player/player.gd`
- `core/autoloads/event_bus.gd`
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_appliers.gd`
- `core/autoloads/save_io.gd`
- `scenes/ui/main_menu.gd` or the current new-game screen, when M4 lands

## Files That Must Not Be Touched In The First Implementation Task

- `BuildingSystem`, `PowerSystem`, `IndoorSolver`
- any `z != 0` code path, including `UndergroundFogState` and
  `MountainShadowSystem` legacy remnants
- any deleted legacy world runtime files from the pre-rebuild stack
- V0 plains terrain ids and their atlas pipeline
- combat, UI, progression, lore systems unrelated to new-world screens
- `docs/02_system_specs/meta/*` (updated only when code lands per the
  canonical follow-ups below)

## Required Canonical Doc Follow-Ups When Code Lands

Each item below must be addressed inside the same task that lands its
feature.

- `docs/02_system_specs/meta/packet_schemas.md` — add `ChunkPacketV1`
  with the three new fields and their bit layout
- `docs/02_system_specs/meta/save_and_persistence.md` — add
  `worldgen_settings.mountains` shape in `world.json`; note that
  `world_version` remains a plain integer boundary
- `docs/02_system_specs/meta/event_contracts.md` — remove obsolete
  mountain reveal lifecycle if code no longer emits it
- `docs/02_system_specs/meta/system_api.md` — document public
  `WorldStreamer` mountain cover surfaces if they are exposed to other
  systems
- `docs/02_system_specs/meta/commands.md` — only if excavation gains a
  new formal command object in M3

`not required` entries must be accompanied by grep evidence against the
relevant doc at the time of landing.

## Risks

- noise tuning consuming disproportionate iteration budget; mitigated by
  keeping M1 acceptance visual-only, not balance-final
- `roof_layers_per_chunk_max` exceeding the guardrail at apparently
  reasonable defaults; mitigated by the debug metric
- cavity/opening derivation drifting between mutation, publish, and load
  paths; mitigated by the single runtime cache refresh path
- `world.json` migration from V0 saves without `worldgen_settings`;
  mitigated by active pre-alpha rejection of non-current `world_version`
- legacy `mountain_shadow_system.gd.uid` and shader files producing
  confusion; mitigated by treating them as dead artifacts unless M2
  explicitly reuses a shader primitive

## Resolved Open Questions

All five open questions Q1–Q5 are resolved in
`MOUNTAIN_GENERATION_ARCHITECTURE.md` §10 as canonical Decision blocks.
Summary:

- Q1. Roof presentation is per `mountain_id`, not per chunk.
- Q2. Cavity/opening visibility is runtime-derived from packet + diff;
  not persisted.
- Q3. First playable cover uses static roof + mask-only reveal; SDF and
  time-based alpha fade are deferred.
- Q4. Settings live in `world.json` under `worldgen_settings`;
  `world_version` is not a settings hash.
- Q5. Subsurface stays a separate domain; surface `mountain_id` does not
  cross `z = 0`; at most a generation modifier is allowed.

No open questions remain at spec-approval time. Any new question raised
during implementation must be handled as a spec amendment, not by silent
drift.

## Implementation Iterations

### M1 — Native Mountain Field and ChunkPacketV1

Goal: emit deterministic mountain silhouettes with correct `mountain_id`
from native generation. No reveal, no roof, no entrance.

Changes:
- vendor FastNoise Lite under `gdextension/src/third_party/`
- add `mountain_field.{h,cpp}` with `sample_elevation`, anchor resolution,
  atlas index derivation
- extend `world_core.cpp` to emit the three V1 packet fields
- bump `WORLD_VERSION` to `3`
- extend `WorldStreamer` to forward new fields; still publish through the
  base layer only
- add new terrain ids and flag bit constants in
  `world_runtime_constants.gd`

Acceptance tests for M1:
- [ ] deterministic regeneration of the same world with fixed inputs
- [ ] visible effect of each of the four primary settings
- [ ] V0 acceptance tests still pass at `density = 0.0`
- [ ] no GDScript fallback path for native generation

### M2 — Static Roof and Cover Cache

Goal: add `roof_layers_by_mountain` + `MountainCavityCache` +
`MountainResolver` with mask-only cover reveal.

Changes:
- extend `ChunkView` with `roof_layers_by_mountain`
  (`mountain_id -> presentation terrain_id -> layer`) and per-chunk mask
  textures / materials
- add `mountain_cavity_cache.gd` for derived cavity, opening, and shell
  metadata
- add `mountain_resolver.gd`; wire from `Player._physics_process`
- add `roof_layers_per_chunk_max` debug metric with warning

Acceptance tests for M2:
- [ ] outside shows only real openings
- [ ] entrance tile counts as inside immediately
- [ ] two adjacent mountains behave independently
- [ ] separate cavities stay isolated until orthogonally connected

### M3 — Local Mutation and Seam Refresh

Goal: update openings, components, and cover masks only in bounded local
paths on mutation, publish, unload, and save/load rebuild.

Changes:
- invoke local cover-cache refresh from `try_harvest_at_world`
- rebuild cover metadata on chunk publish / unload only for the published
  or unloaded chunk plus seam-neighbor diff participants
- keep roof cells static and update runtime visibility through masks only

Acceptance tests for M3:
- [ ] digging a new mouth reveals only the mouth from outside
- [ ] orthogonal tunneling merges cavities; diagonal contact does not
- [ ] chunk seam publish / unload keeps cover state stable
- [ ] load restores derived cavity/opening behavior without save-payload
      cover state

### M4 — Worldgen Settings Plumbing

Goal: player-controllable mountain settings that travel with the save.

Changes:
- add `MountainGenSettings` resource and default `.tres`
- add main-menu (or new-game screen) sliders bound to the resource
- have `WorldStreamer` flatten settings into `settings_packed` once at
  world init and save / load them under `worldgen_settings.mountains`
- loader rejects current-version saves when the section is missing

Acceptance tests for M4:
- [ ] each slider measurably changes generation in a new game
- [ ] new game writes the section into `world.json`
- [ ] loading an old V0 save fails cleanly before diffs/player/base state apply
- [ ] editing the repository's default `.tres` does not retroactively
      change an existing save

### M5 (Deferred, Out of Initial Approval Scope)

Optional polish: SDF spatial reveal, per-mountain color variance,
minimap icons, `under_mountain_strength` hint wiring for subsurface
generator.

M5 requires a spec amendment before implementation.

### M6 — Finite-Cylinder Mountain Aspect Normalization

Goal: make V1 finite-cylinder mountains keep their intended tile-space aspect
ratio on `small`, `medium`, and `large` presets.

Problem:
- `world_version == 9` finite worlds saved explicit bounds, but the mountain
  sample path still remapped finite X into the legacy `65536`-tile cylinder.
- On the `large` preset (`8192` tiles wide), this compresses X-domain variation
  by roughly `8x` relative to Y and produces tall needle-like mountain slices.

Changes:
- add `world_wrap_width_tiles` to the native mountain settings after unpacking
  from `settings_packed`;
- for `world_version >= 10`, derive that width from
  `worldgen_settings.world_bounds.width_tiles`;
- for `world_version <= 9`, keep the legacy `65536` width and legacy finite-X
  remap as a historical native algorithm path only;
- keep the same `settings_packed` shape and `world.json` shape;
- bump `WorldRuntimeConstants.WORLD_VERSION` to `10`.

Files allowed:
- `gdextension/src/mountain_field.h`
- `gdextension/src/mountain_field.cpp`
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_prepass.cpp`
- `core/systems/world/world_runtime_constants.gd`
- this spec and directly affected canonical docs.

Files forbidden:
- save collectors / appliers, unless verification finds a concrete schema bug;
- `WorldStreamer` runtime state and chunk publish code;
- UI preview canvas / palette files, because preview already reflects runtime.

Acceptance tests for M6:
- [ ] M6 landed new worlds at `world_version = 10`; current new-world
      version may be higher after later canonical worldgen owners
      (currently `11` in `world_foundation_v1.md`);
- [ ] `world_version == 9` remains a historical algorithm boundary only; active
      pre-alpha save/load rejects non-current `world_version` values;
- [ ] on the `large` preset, generated mountain output no longer appears as
      vertically stretched one-tile-to-few-tile slices caused by finite-X
      remapping;
- [ ] X seam sampling remains wrap-safe at `x = -1 / 0 / width - 1 / width`;
- [ ] no save payload shape changes are introduced;
- [ ] native packet generation remains worker-side and introduces no
      main-thread generation loop.

### M7 — Organic Construction Roof and Component Reveal (2026-07-14)

Goal: cover excavated tunnels with the mountain's own pre-dig top surface
while the player is outside, and fade that cover only over the current
connected cavity while the player is inside — without changing the organic
excavation presentation, collision, mining, or persistence in any way.

Changes:
- `WorldStreamer` builds three tile halos per chunk mask request:
  `remaining_halo` (post-diff, unchanged input of the live `V` mask),
  `closed_halo` (ownership ignoring diff), and `dug_halo`
- the worker backend performs a second `build_mountain_halo_mask` call over
  `closed_halo` only when `dug_halo` is non-empty and attaches
  `closed_roof_mask` + `dug_halo` to the same result; the native
  `build_mountain_halo_mask` C++ surface is unchanged
- `ChunkView` lazily renders visual-only `ROOF(C, V_ref, R_displayed, b)`
  above `BASE(V)`; collision/mining keep sampling the live mask bytes
- `MountainResolver` keeps automatic entry/exit; target ownership changes
  immediately, while the displayed selector fades with the
  `150 ms` / `60 + 180 ms` transition
- derived masks/components stay out of persistence and rebuild from
  base + diff

Explicitly out of M7 scope (rejected during the roof2 prototype review):
- square-tile hard clears of the visual mask (`V` keeps the live organic
  re-blur contour)
- native physical mouth aperture masks and N/E/S/W mouth direction metadata
- cosmetic mouth dressing (maw gradient, jamb shade, roof lip, closed-mask
  sun occluder override)

Acceptance tests for M7 are the Cover Visibility, Excavation, Persistence
and Performance gates above. M7 supersedes the active presentation semantics
of M2 and M3; their tile-layer/opening-shell text is implementation history
only.

## Status Rationale

This spec is approved because:
- every architectural rule has an explicit Decision statement in
  `MOUNTAIN_GENERATION_ARCHITECTURE.md` §10, and each decision has been
  mirrored into a binding contract section above
- all 12 Law 0 questions are answered in the classification table
- additive extension preserves every V0 invariant; no V0 field or owner
  boundary is mutated
- performance contract names a dirty unit and budget for every new
  operation
- the spec respects ADR-0001, ADR-0002, ADR-0003, ADR-0005, ADR-0006,
  ADR-0007 boundaries explicitly

Implementation tasks may cite this spec as `approved` prerequisite.
Changes to the rules above require a new version of this document with
`last_updated` bumped and a changelog entry describing the amendment.

Version `1.8` completes the M7-organic amendment: a presentation-only construction
roof `C` with a displayed-component reveal covers excavated tunnels, while
the live organic mask `V` keeps owning facade, collision, mining and the
excavation look unchanged. It also defines atomic selector publication,
cross-chunk roof ownership and the exact facade boundary: full-resolution
`C-V` proves new internal walls, while `C`'s original structural facade and
its torch response remain BASE-owned. Packet and save schemas do not change;
the worker mask-result dictionary gains derived `closed_roof_mask` /
`dug_halo` fields (see `packet_schemas.md`).
