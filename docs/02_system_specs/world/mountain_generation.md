---
title: Mountain Generation V1
doc_type: system_spec
status: approved
owner: engineering
source_of_truth: true
version: 1.11
last_updated: 2026-07-12
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
- when inside, remove the construction roof only above the current connected
  orthogonal cavity; the live remaining mountain mass supplies its real inner
  walls, while foreign cavity interiors remain sealed
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
- native construction mask set in `ChunkView`: immutable closed roof `C`,
  gameplay remaining mass `S`, visual remaining mass `V`, and optional
  full-resolution physical facade aperture `A`
- `MountainCavityCache` runtime-derived opening / cavity component cache
- `MountainResolver` bounded O(1) per-step point-in-cavity lookup from the
  exact floor tile or its real organic excavation fringe
- component-only roof reveal driven by a retained displayed cavity selector;
  outside the upper roof is exactly the immutable closed mask, while a separate
  native full-resolution aperture removes only the physical facade wall
- `MountainGenSettings` resource + `worldgen_settings.mountains` section
  in `world.json`
- bump `WORLD_VERSION` from `1` to `2` for M1, then to `3` for the
  named-mountain ownership fix, then to `4` for retirement of the
  standalone plains-rock generation path, then to `5` for the spawn-safe
  carveout, then to `6` for hierarchical mountain-domain labeling

## Out of Scope

V1 does not include:
- water generation, multiple biomes, climate data, biome blend logic
- radial reveal effects and authored door decals; the approved construction
  roof uses only the bounded whole-component alpha transition defined below
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
| Canonical, runtime overlay, or visual only? | Field, identity, flags, and atlas indices are canonical. Excavation is authoritative diff. Closed roof `C`, gameplay remaining mass `S`, visual remaining mass `V`, native facade aperture `A`, cavity component membership, mouth metadata, target/displayed selectors, and reveal blend are runtime-derived presentation/cache data. |
| Save/load required? | Yes, for `worldgen_settings.mountains` and excavation diff. No for `C`, `S`, `V`, `A`, cavity cache, mouth/reveal selectors, target/displayed cover state, or reveal blend: they rebuild from immutable base + diff. |
| Deterministic? | Yes. Field, identity, and atlas indices are pure `f(seed, world_version, coord, settings_packed)`. |
| Must work on unloaded chunks? | Yes. All per-tile canonical data is recomputable from base + diff on demand. |
| C++ compute or main-thread apply? | Field generation and the `C/S/V/A` `32 x 32`-tile halo rasterization are worker-side C++. Main thread uploads queued textures and updates bounded `32 x 32` tile reveal/mouth halos. |
| Dirty unit | `16 x 16` chunk for generation; one tile plus native-halo seam neighbours for excavation; old/new component chunks plus one chunk halo for enter/exit; published/unloaded chunk plus seam participants for streaming. |
| Single owner | `WorldCore` for base field and native `C/S/V/A` compute. `WorldDiffStore` for excavation diff. `ChunkView` for visual `C/V/A` presentation while retaining `S` for gameplay sampling. `MountainCavityCache` for transient component membership. `WorldStreamer` for target/displayed cover state, mouth metadata and dirty scheduling. |
| 10x / 100x scale path | Version `6` keeps identity on aligned macro solves with reusable native cache, recursive subdivision only for mixed cells, and versioned `min_label_cell_size = 8`. Publish inherits V0 slicing. No whole-world scan is introduced. |
| Main-thread blocking? | No broad work. Paired masks stay in the existing worker queue; texture uploads stay under the existing mountain visual upload budget; active reveal rebuild touches only transition/dirty chunks and halo neighbours. |
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
| Presentation | `ChunkView` | Keep gameplay remaining mass `S` for collision/mining sampling, upload visual remaining mass `V`, and lazily own immutable closed-roof `C`, native full-resolution facade aperture `A`, a component-only roof selector, and separate directional mouth metadata. |
| Runtime cover cache | `MountainCavityCache` | Derive orthogonal cavity component membership from canonical mountain ownership + excavation diff. Legacy opening/shell metadata is diagnostic only and does not drive the construction roof. |
| Point-in-cavity lookup | `MountainResolver` | Per-frame derive current cavity component from the exact floor tile or the bounded organic `C-S` fringe around it; update immediate target cover selection. |

### Roof Presentation

- Native worker input for every mountain mask request is one paired halo:
  - `C_tiles`: immutable roof-bearing ownership from
    `mountain_id > 0 && flags & (WALL|FOOT)`, ignoring diff;
  - `D_tiles`: authoritative mountain-owned `TERRAIN_PLAINS_DUG` cells after
    diff application.
- The broad blur/noise pass rasterizes `C_tiles` once into immutable closed
  organic roof mask `C`.
- The visual excavation contour `V` is the retained `fbedb3b` room formula:
  the dug tile field receives one box blur of `pixels_per_tile / 4`, samples the
  mountain's broad displacement at `0.32` strength, and applies
  `smooth((cutout_field - 0.28) / 0.44)` against `C`. This gives joined rooms,
  corners and branches one continuous hand-cut contour instead of a grid of
  full-tile rectangles.
- Every dug tile additionally forces a central `25%..75%` topology core and a
  half-tile arm toward each dug cardinal neighbour fully open in `V`. Arms meet
  across tile seams, so straight, L, T and cross junctions cannot close at their
  centres even when the organic contour is displaced.
- A physical mouth is the deliberate non-organic exception in `V`: the outward
  half of a dug tile next to exterior `C_tiles=0` is clamped to a straight
  portal. Its one-tile lateral bounds are `12.5%..87.5%`; a same-direction mouth
  in the adjacent tile extends that side to the seam. Thus a `2..N`-tile-wide
  entrance is one uninterrupted span with jambs only at its outer ends.
- The same native pass emits optional full-resolution L8
  `physical_mouth_aperture_mask = A`. `A` is exactly `C - V`, gated to the
  physical source tile's outward half and the single exterior cell needed to
  clear `C`'s organic spill. Digging farther inward cannot change `A`; only
  widening or creating a real surface mouth can change it.
- Gameplay remaining mass `S` equals `V` on non-dug source tiles but hard-zeros
  every pixel of every `D_tiles=1` source tile. The organic fringe in adjacent
  retaining cells remains mineable/collidable, while no visual overhang can
  make an already mined tile impassable. Required invariant:
  `0 <= S <= V <= C` for every pixel.
- One worker result carries `closed_roof_mask = C`,
  `remaining_mass_mask = S`, `visual_remaining_mass_mask = V`, optional
  `physical_mouth_aperture_mask = A`, and compatibility alias `mask = S`.
  `mask`/`S` is not the texture used to draw the room contour. No synchronous
  GDScript pixel compositor is allowed.
- `ChunkView` renders two sprites with the same origin, clip and material set:
  - `BASE(V,A)` draws the physical outer/inner facade and exposes the real ground
    floor; `A` only disables cosmetic crag warp in a narrow neighbourhood of the
    exact native facade cut; collision and mining separately sample `S`;
  - `ROOF(C,V_ref,M,R_displayed,b)` is visual-only and always computes top
    geometry, normals and colour from immutable `C`. `M` may choose which local
    `C` edge belongs to the vertical facade for N/E/S/W ownership, but it does
    not remove top geometry. `V_ref` is a read-only reference used only to locate
    the already-rendered internal `BASE(V)` structural facade. Final alpha uses:
    `displayed_weight = max(component_floor, owned_base_facade)` and
    `roof_alpha *= 1 - displayed_weight * b`. `owned_base_facade` is accepted
    only when the point immediately beyond its organic `V` edge belongs exactly
    to `R_displayed`.
- `A` and directional mouth metadata never participate in component roof
  reveal. Outside, the roof mask remains byte-identical to `C`; the entrance is
  the missing `BASE` facade beneath `C`'s unchanged lower lip, not a hole cut
  into the upper surface.
- `ROOF` is the immediate equal-z sibling after `BASE`, below the existing
  player/decor depth ladder. This preserves the approved exterior
  mountain/object occlusion contract; generated objects are never anchored on
  immutable mountain cells, and the local player reveals the component before
  occupying its interior.
- The roof contribution suppresses its own structural facade/eave band. This
  leaves the live `BASE` facade in charge of the real mouth and prevents the
  facade from moving deeper into the mountain when the roof is closed.
- While inside, `ROOF` additionally yields alpha only over a SOUTH-facing
  `BASE(V)` structural wall whose open side is owned by `R_displayed`. This
  restores internal walls and stone-island facades without exposing island top,
  foreign cavities, or the upper `C` surface. A coarse selector look-ahead may
  skip the `V` edge search away from the active component, but never owns pixels.
- The ordinary ground `_base_layer` remains visible below every cutout. Black
  fill, clear-color holes, entrance decals and duplicated floor textures are
  forbidden.
- Collision, resolver and mining always sample gameplay `S`, never `V`, `A`,
  `R_displayed`, `M`, or the rendered roof. Introducing those fields changes
  presentation only; roof ownership and resolver entry/exit semantics remain
  unchanged.
- Mountain torch-shadow composition samples `C` outside and selects `V` for
  active-component floor tiles plus a torch-only one-tile support ring. This
  derived light selector never changes `ROOF`, excavation or collision. Torch
  occlusion follows the same native organic `C-V` edge that the player sees
  instead of a 64 px rectangle,
  while hidden/foreign excavation remains under `C` (ADR-0005).
- The closed mask remains publishable even when every local mountain cell has
  been excavated; quarry/collapse semantics are a separate future feature.
- The legacy `roof_layers_by_mountain` tile presentation may remain disabled
  for compatibility, but it is not an authoritative or active cover path.

### Cover Cache and Visibility

- `MountainCavityCache` is runtime-derived only; it never mutates canonical
  packet fields
- required runtime cache surfaces:
  - tile -> `component_id`
  - component -> authoritative excavated member tiles and touched chunks
- outside state is `R_displayed=0` and `b=0`; `ROOF` therefore renders immutable
  `C` without any physical-mouth exception
- inside state uses `R_displayed=displayed_component.tiles` only; shell, opening
  shell and outside-visible fields must not be copied into the roof selector
- `M` is independent of the active component and contains opening floor cells
  only, never opening shell; its low four bits are `N=1/E=2/S=4/W=8`, and bits
  `16/32` mark lateral continuation for a wide mouth. The bit-`64` outward copy
  lets both `BASE` and `ROOF` classify the same local N/E/S/W facade band across
  `C`'s one-cell organic spill. No `M` bit cuts the upper `C` surface, enters
  component alpha, or reconstructs aperture geometry in the shader
- `ChunkView` uploads the binary `32 x 32` displayed-component selector
  separately from `M`. It also uploads full-resolution `A` only when a real
  aperture exists. `A` is sampled by `BASE` for local unwarp only; it is disabled
  on `ROOF`. There is no shader mouth SDF, procedural header, or combined `R+M`
  reveal texture
- the tile reveal halo is `32 x 32` L8 bytes: chunk `16 x 16` plus the same
  `8`-tile native halo on every side; it shares UV/world origin with `C` and `S`
- torch-only support expands raw binary `R` by exactly one Chebyshev tile on
  the complete `32 x 32` halo before chunk clipping. It contains only non-dug
  cells. A support cell touching any foreign dug source fails closed; neither a
  foreign dug tile nor a second support ring is selected. The bound matches the
  native cutout reach (`blur + warp < 1 tile`) and preserves chunk continuity
- wide mouths, left/right branches and multiple mouths require no special-case
  identity: orthogonally connected dug tiles share the same component and
  `BASE(V)` supplies every physical aperture
- diagonal-only contact never connects cavity components
- adjacent mountains must remain independent because component membership is
  constrained by stable canonical `mountain_id`
- component ids are transient and may change after merge/reload; membership,
  not the numeric id, is the contract
- component floor chunks are cached incrementally, and per-chunk selectors use
  fixed `16 x 16` membership lookups; enter/exit must not rescan every tile once
  per component chunk
- Resolver ownership and presentation state are deliberately split:
  - `target_component`/active cover changes immediately and remains authoritative
    for gameplay and torch selection;
  - `displayed_component` retains the component whose roof is currently fading;
  - `component_reveal_blend b` is presentation-only and never rebuilds native
    masks or enters persistence.
- Enter opens `b: 0 -> 1` over `150 ms` with cubic-out easing. Exit holds for
  `60 ms`, then closes `b: 1 -> 0` over `180 ms` with cubic-in-out easing.
  Re-entering the same component reverses from the current value without a jump.
  A different mountain closes the displayed component fully before installing
  and opening the new selector. A component-id repair inside the same mountain
  swaps selector membership without closing the roof.
- Opening alpha does not advance until the deferred displayed-selector upload is
  ready. New/reloaded `ChunkView` instances receive the current `b` before their
  roof material is created, preventing one-frame closed or wrong-cavity flashes.

### Mountain Resolver

- `MountainResolver` is invoked once per frame from
  `Player._physics_process`
- steps:
  1. convert player world position to tile, chunk, and local coord
  2. query cached cover sample for that tile; if the chunk is not loaded, do
     nothing
  3. treat `component_id > 0` as inside immediately, including when standing
     on an entrance tile
  4. if the exact tile has no component, sample immutable `C` and remaining
     raw `S` (without facade-collision projection) at the player position; only
     when `C` is solid and `S` is open, inspect the fixed `3 x 3` tile
     neighbourhood and prefer the previous component. Fallback distance uses
     wrapped X and ordinary Y distance under ADR-0002.
     This retains ownership in a real organic excavated corner without keeping
     the roof open on ordinary exterior ground
  5. when the component changes, update `WorldStreamer.target_component`
     immediately; the presentation controller independently retains and fades
     `displayed_component`

Resolver does bounded O(1) work per frame (one exact sample, two raster samples,
at most eight cached neighbour samples); no flood fill, scene-tree query, or
raycast is allowed on the hot path.

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
- the immediate collision patch may clear gameplay `S` locally, but the queued
  native reconcile is authoritative for `S/V` separation: `S` must preserve a
  fully open source cell for every `D_tiles=1`, while `V` may retain organic
  corner overhang outside its guaranteed topology core/arms
- facade collision remains authoritative on retaining rock. The only exterior
  exemption is a walkable apron tile cardinally adjacent to a true opening;
  this prevents the projected facade lip from pinching the player's footprint
  before its centre reaches the dug mouth
- cover updates after mutation must not use mass `set_cell`, `TileMap.clear`,
  or loaded-world global rebuilds

### Streaming and Apply

- mountain packet fields travel through the existing V0 chunk publish
  path unchanged
- `C/S/V/A` mask compute travels through the existing worker mask queue and one
  revision/inflight/cache key per chunk
- no new `FrameBudgetDispatcher` category is introduced; reuse
  the existing mountain visual-upload queue and its `0.75 ms/frame` budget
- on chunk publish / unload, update only the published or unloaded chunk plus
  direct seam-neighbor diff participants needed to refresh cavity metadata
- on a displayed-component transition, refresh only the union of old/new
  component chunks expanded by one chunk for the native halo; an empty target
  list must never mean "scan every loaded ChunkView"
- a newly published chunk remains hidden only while its real native mountain
  visual is pending. Plain/shore chunks never enter this gate. After the `C/S/V/A`
  result, restored displayed selector, and current reveal blend are installed,
  the view becomes visible and only then emits `chunk_loaded`, preventing a
  one-frame closed-roof or stale-selector flash on reload
- zero-dug mountain chunks use the legacy single `BASE` draw and allocate no
  CLOSED/selector textures; the second roof sprite/resources are created lazily
  on the first excavation
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
- `closed_roof_mask`, `remaining_mass_mask`, `visual_remaining_mass_mask`,
  `physical_mouth_aperture_mask`, dug/reveal/mouth halos, GPU textures and worker
  revisions are transient derived data; none enter `world.json` or
  `chunks/*.json`
- after load, derived cavity / opening state is rebuilt from loaded packet +
  diff data during publish
- a player restored on a mountain-owned dug tile must resolve the rebuilt
  component before that chunk's first visible roof state; no save payload stores
  reveal / cover state or relies on stable numeric `component_id`

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
| Closed/gameplay/visual/aperture native masks (`C/S/V/A`) | background (native worker) | one `32 x 32` tile halo / chunk revision | outside main thread; one result, queued `C/V/A` and tiny-selector uploads |
| Resolver tile lookup | interactive | 1 tile | < 0.05 ms/frame |
| Roof reveal upload on state switch | background apply | old/new component chunks + one-chunk halo | existing `0.75 ms/frame` visual budget; no native rebuild |
| Roof reveal alpha transition | interactive presentation | one uniform on displayed component chunks | `150 ms` enter; `60 ms` exit delay + `180 ms` close; no mask rebuild |
| Excavation mutation | interactive | 1 tile + native-halo seam neighbours | immediate collision patch; native/GPU follow-up queued |
| Cavity/opening cache refresh on mutation | interactive | local dirty neighborhood + affected component metadata | < 1.0 ms at normal scale |
| Cavity/opening rebuild on publish / unload | boot/load | published/unloaded chunk plus direct seam participants | loading / streaming only |

### Forbidden Runtime Paths

- per-tile `Tween` on reveal
- per-tile `set_cell` during cover updates
- flood-fill over interior tiles on enter / movement
- chunk-wide rescan on every player step
- global rebuild of loaded-world cavity visibility on every publish / unload
- all-loaded-chunk reveal sweep on enter, exit or one-tile excavation
- synchronous native-mask generation or `ImageTexture` upload in the mining input frame
- CPU composition of `C`, `S`, `V`, `A` and `R_displayed` into a replacement
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

- [ ] outside mountain: `BASE(V)` makes the physical mouth readable and shows
      the real ground floor; no black/clear-color fill is visible
- [ ] outside mountain: `ROOF(C)` hides the tunnel depth and the outer facade
      remains at the immutable construction edge instead of moving inward
- [ ] standing on an entrance tile updates gameplay/torch target ownership
      immediately
- [ ] entering a cavity reveals only the full connected orthogonal cavity with
      the specified `150 ms` cubic-out fade
- [ ] leaving retains the displayed selector for `60 ms`, closes it over
      `180 ms` cubic-in-out, then restores a roof pixel-identical to the initial
      outside state
- [ ] separate cavities remain isolated while inside one of them
- [ ] foreign cavity interiors remain hidden while inside a current cavity
- [ ] the active cavity's internal SOUTH facade is identical to `BASE(V)`;
      a stone island keeps its CLOSED top but exposes the facade facing active
      floor, while a neighbouring cavity's facade remains covered
- [ ] adjacent mountains behave independently
- [ ] narrow, wide, L/T-shaped and cross-chunk cavities do not show a cellular
      roof boundary
- [ ] a one-tile mouth is a straight native facade break beneath the unchanged
      `C` lip; a `2..N`-tile mouth has no internal posts and retains only its two
      outer jambs
- [ ] outside, effective `ROOF` geometry is byte-equivalent to `C`; no orange
      floor or aperture appears in the upper roof surface
- [ ] digging inward by `1`, `3`, or `10` tiles leaves `A` byte-identical;
      widening the physical mouth changes only its lateral span
- [ ] rapid exit/re-entry reverses from the current blend without a jump, and a
      different mountain closes before its selector is replaced
- [ ] torch shadows inside those cavities follow the same native organic edge;
      no square 64 px shadow plate remains around active dug tiles
- [ ] cover state is not written to the save payload

### Excavation

- [ ] digging a new mouth makes the opening visible from outside without
      revealing the whole cavity
- [ ] one-tile and wide dug source cells remain fully open after native
      reconcile; the actual player footprint can traverse them
- [ ] retaining wall cells stay solid, blocked and mineable
- [ ] orthogonal excavation that joins two cavities makes them reveal as one
- [ ] diagonal-only contact does not merge passability or visibility
- [ ] `remaining_mass_mask <= closed_roof_mask` for every native output pixel
- [ ] `remaining_mass_mask <= visual_remaining_mass_mask <= closed_roof_mask`
      for every native output pixel; only gameplay `S` is required to be zero
      across the whole dug source tile
- [ ] non-empty `physical_mouth_aperture_mask` equals gated `C - V` only in the
      physical source half and its one-cell exterior projection
- [ ] reveal never becomes the source of truth for wall geometry, collision or
      mining

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
- [ ] fully excavated local mountain metadata still publishes its closed roof
      outside; `C/S/V` and numeric component ids are reconstructed, not saved

### Performance

- [ ] native chunk packet generation stays off the main thread
- [ ] player movement does not trigger flood fill or broad rescan
- [ ] chunk publish / evict do not trigger full loaded-world cover rebuild
- [ ] interactive excavation including cover-cache refresh completes under
      `1.0 ms` at p95
- [ ] enter/exit does not request native rebuild and queued roof/reveal uploads
      remain inside the existing `0.75 ms/frame` budget
- [ ] one excavation dirties only owner chunk plus native-halo seam neighbours
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

- Q1. Canonical ownership remains per `mountain_id`; active presentation is a
  per-chunk native `C/S/V` mask set with matching halo, not one tile layer per owner.
- Q2. Cavity/opening visibility is runtime-derived from packet + diff;
  not persisted.
- Q3. First playable cover uses immutable construction roof `C`, gameplay mass
  `S`, visual mass `V`, native facade aperture `A`, a displayed-component-only
  selector `R`, and the bounded target/displayed alpha transition defined above.
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

### M7 — Construction Roof and Native Excavation Cutout (2026-07-11)

Goal: replace the disabled tile-roof visibility path with the natural
construction model proven by the runtime prototype.

Changes:
- worker emits `C/S/V/A` masks from immutable ownership + diff
- gameplay `S` hard-clears every dug tile while `V` keeps the organic fbed room
  contour, topology core/arms, and straight continuation-aware physical mouths
- `ChunkView` renders live `BASE(V,A)` plus independent visual
  `ROOF(C,V_ref,R_displayed,b)`; `V_ref` owns only internal-facade alpha while
  collision/mining keep sampling `S`
- `MountainResolver` keeps automatic entry/exit; gameplay target changes
  immediately while reveal contains only displayed-component floor cells
- derived masks/components stay out of persistence and rebuild from base + diff

Acceptance tests for M7 are the Cover Visibility, Excavation, Persistence and
Performance gates above. M7 supersedes the active presentation semantics of M2
and M3; their tile-layer/opening-shell text is implementation history only.

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

Version `1.7` is the M7 amendment: paired construction masks replace the legacy
tile-roof/opening-shell presentation without changing packet or save schemas.
Version `1.9` fixes the torch-only component selector so dynamic light consumes
the active native excavation mask (including its bounded organic fringe), while
roof reveal, collision, excavation truth, packet shape and persistence remain
unchanged.
Version `1.10` separates gameplay remaining mass `S` from visual remaining mass
`V`, restores the fbed room contour with guaranteed topology cores/arms, and
defines straight modular mouths plus their independent physical selector and
one-cell exterior projection. Construction-roof and resolver ownership do not
change.
Version `1.11` replaces the shader-generated roof mouth with native
full-resolution facade aperture `A`, keeps `ROOF` geometry immutable `C`, makes
the roof selector component-only, and splits immediate target ownership from the
retained displayed component used by the `150 ms` / `60+180 ms` alpha transition.
`ROOF` may read `V` only as an auxiliary ownership mask so the active cavity's
existing `BASE(V)` structural facade is not covered by the immutable cap.
