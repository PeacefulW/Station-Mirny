---
title: Mountain Generation V1
doc_type: system_spec
status: approved
owner: engineering
source_of_truth: true
version: 1.1
last_updated: 2026-04-20
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
introduces massive deterministic mountains and a mountain-interior reveal
system on top of `World Runtime V0`.

This spec is the source of truth for:
- mountain silhouette and elevation field
- mountain identity (`mountain_id`)
- roof presentation layer and reveal lifecycle
- excavation and entrance derivation
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
- dig into a mountain with the existing single-tile mutation path, and have
  the excavation persist across save/load
- when entering a mountain, have only that specific mountain's roof fade
  out; adjacent mountains remain sealed
- see only the entrance from outside; the rest of the interior stays hidden
  behind the mountain's crown texture, even if a base is built inside
- tune mountain density, scale, continuity, and ruggedness at world
  creation; the settings travel with the save and cannot be retroactively
  changed by repository edits

## Scope

V1 is an **additive** extension of V0. It adds:
- native mountain field in `WorldCore` (elevation, ridge, domain warp)
- anchor-based mountain identity with deterministic sparse anchors
- `ChunkPacketV1` with three additive fields, no V0 field removed
- new surface terrain ids: `TERRAIN_MOUNTAIN_WALL`, `TERRAIN_MOUNTAIN_FOOT`
- roof presentation layer in `ChunkView`, one `TileMapLayer` per
  `mountain_id` inside a chunk
- `MountainRevealRegistry` single-writer reveal lifecycle with time-based
  alpha fade
- `MountainResolver` per-frame point-in-mountain lookup from player tile
- derived `is_entrance` flag computed on mutation and on load
- `MountainGenSettings` resource + `worldgen_settings.mountains` section
  in `world.json`
- bump `WORLD_VERSION` from `1` to `2` for M1, then to `3` for the
  named-mountain ownership fix, then to `4` for retirement of the
  standalone plains-rock generation path

## Out of Scope

V1 does not include:
- rivers, lakes, multiple biomes, climate data, biome blend logic
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
- `World Grid Rebuild Foundation` for the `32 px` tile / `32 x 32` chunk
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
| Canonical, runtime overlay, or visual only? | Field, identity, flags, and atlas indices are canonical. Entrance flag and reveal alpha are runtime overlay. Roof cells are visual only. |
| Save/load required? | Yes, for `worldgen_settings.mountains` in `world.json`. No for reveal state or entrance cache. |
| Deterministic? | Yes. Field, identity, and atlas indices are pure `f(seed, world_version, coord, settings_packed)`. |
| Must work on unloaded chunks? | Yes. All per-tile canonical data is recomputable from base + diff on demand. |
| C++ compute or main-thread apply? | Field sample, anchor resolution, and atlas indices are C++ compute. Roof cell placement, reveal alpha, and entrance flag recompute are main-thread apply. |
| Dirty unit | `32 x 32` chunk for generation; one tile for excavation mutation; 5-tile neighborhood for entrance recompute; one `mountain_id` for reveal alpha. |
| Single owner | `WorldCore` for base field. `WorldDiffStore` for diff. `ChunkView` for roof presentation and runtime entrance cache. `MountainRevealRegistry` for reveal alpha. `world.json` for `worldgen_settings`. |
| 10x / 100x scale path | Sparse anchors + bounded local anchor lookup keep identity local. Publish inherits V0 slicing. No global tables; scale grows with number of loaded chunks only. |
| Main-thread blocking? | No. Generation stays in the existing worker path. Apply remains sliced through `FrameBudgetDispatcher.CATEGORY_STREAMING`. |
| Hidden GDScript fallback? | Forbidden. Native `WorldCore` is required; absence fails loudly per LAW 9. |
| Could it become heavy later? | Yes. Noise octaves, anchor density, and reveal participants scale. All stay inside native generation or per-mountain (not per-tile) runtime work. |
| Whole-world prepass? | Forbidden. All field and identity work is local to one chunk plus its bounded anchor neighborhood. |

## Core Contract

### Chunk Geometry

Unchanged from `world_grid_rebuild_foundation.md`:
- one world tile = `32 px`
- one chunk = `32 x 32` tiles
- chunk-local cell coordinates `0..31`
- world X wraps (ADR-0002); world Y does not

### Terrain IDs

V1 adds two surface terrain ids:

| Id constant | Walkable | Used for |
|---|---|---|
| `TERRAIN_MOUNTAIN_WALL` | 0 | Every tile with `mountain_id > 0` and `is_wall` bit set. Rendered on `_base_layer` with rock-face atlas. |
| `TERRAIN_MOUNTAIN_FOOT` | 0 | Foot-band tiles visible from outside. `mountain_id > 0`, `is_foot` bit set, no `is_interior` bit. Never covered by roof. |

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
| `terrain_ids` | `PackedInt32Array` | 1024 |
| `terrain_atlas_indices` | `PackedInt32Array` | 1024 |
| `walkable_flags` | `PackedByteArray` | 1024 |

V1 additive fields:

| Field | Type | Length | Notes |
|---|---|---|---|
| `mountain_id_per_tile` | `PackedInt32Array` | 1024 | `0` = not mountain. Non-zero = deterministic `mountain_id`. |
| `mountain_flags` | `PackedByteArray` | 1024 | Bit 0 `is_interior`, bit 1 `is_wall`, bit 2 `is_foot`, bit 3 `is_anchor`. Other bits reserved. |
| `mountain_atlas_indices` | `PackedInt32Array` | 1024 | Atlas indices for the roof `TileMapLayer`. Derived via `autotile_47` on `mountain_id` adjacency. |

Forbidden packet fields in V1 (reserved for later specs):
- climate bytes, river masks, biome blend data
- placements, decor batches, connector requests
- subsurface data
- `is_entrance` (derived, runtime-only, see Entrance Rules)

### Mountain Field

`WorldCore` exposes one logical function, inlined inside
`generate_chunk_packet`:

```text
sample_elevation(seed, world_version, wx, wy, settings_packed) -> float
```

Rules:
- pure function; no state other than inputs
- wrap-safe on X via `wrap_x(wx, world_width_tiles)`
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

Mountain identity is assigned via **deterministic sparse anchors**.

Anchor lattice:
- cell size `settings.anchor_cell_size` in tiles
- for each `(ax, ay)` anchor cell, deterministic jitter produces a single
  candidate position inside that cell using splitmix64 on
  `(seed, ax, ay)`
- for current `world_version >= 4` owner assignment, an anchor candidate
  participates when `sample_elevation(candidate) >= t_edge`

Per-tile assignment:
- for each tile `(wx, wy)` with `elevation >= t_edge`, examine a bounded
  `5 x 5` anchor-cell neighborhood around the containing anchor cell
- choose the qualifying anchor with smallest Chebyshev distance
- active mountain worlds must not emit a standalone scattered-rock terrain
  fallback for elevated tiles; `mountain_id = 0` on elevated terrain is a
  diagnostic miss, not a gameplay presentation path

`mountain_id` is a deterministic 32-bit hash of
`(seed, world_version, ax, ay)`. It is stable for the life of the world.
Values are never reused.

Identity is base data. It never mutates in response to diff, excavation,
or runtime events (LAW 5).

### Interior, Wall, Foot, Anchor Flags

For every tile with `mountain_id > 0`:
- `is_wall` = 1 iff `elevation >= t_wall`
- `is_foot` = 1 iff `t_edge <= elevation < t_wall`
- `is_interior` = 1 iff `is_wall` and the 4-neighbor Chebyshev distance
  into the wall region is `>= settings.interior_margin`
- `is_anchor` = 1 iff the tile is the anchor's jittered position itself

For every tile with `mountain_id == 0`:
- `mountain_flags = 0`
- `mountain_atlas_index = 0`
- canonical terrain stays on the ground / non-mountain path

Tiles with `is_interior == 1` are the **only** tiles that participate in
the roof layer.

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

V1 keeps one native class, `WorldCore`. Signature is extended:

```text
WorldCore.generate_chunk_packet(
    seed: int,
    coord: Vector2i,
    world_version: int,
    settings_packed: PackedFloat32Array
) -> Dictionary
```

Rules:
- one chunk per call
- no per-tile callbacks, no multiple Variant round-trips
- settings read once per call, not per tile
- absent `settings_packed` (size 0) → behave exactly as V0 (all-zero
  mountain fields)
- no second native class is introduced in V1

### Script Ownership

| Role | Owner | Responsibility |
|---|---|---|
| Base field, identity, flags, atlas | `WorldCore` (native) | Emit V1 packet. |
| Diff | `WorldDiffStore` | Unchanged from V0. |
| Chunk orchestration | `WorldStreamer` | Forward new packet fields; flatten settings; persist settings in `world.json`. |
| Presentation | `ChunkView` | Own base/overlay/roof layers; own runtime entrance cache. |
| Reveal lifecycle | `MountainRevealRegistry` | Single writer of per-`mountain_id` alpha; emit reveal/conceal signals. |
| Point-in-mountain lookup | `MountainResolver` | Per-frame derive `mountain_id` under player tile; request reveal/conceal. |

### Roof Presentation

- `ChunkView` holds `Dictionary[int, TileMapLayer] roof_layers_by_mountain`
- roof layers are created lazily on first tile assignment for a given
  `mountain_id`
- roof layer `tile_set` is provided by
  `WorldTileSetFactory.get_roof_tile_set()` and shares the rock-top atlas
  with `TERRAIN_MOUNTAIN_WALL` so the outside silhouette is seamless
- roof cells are placed only for tiles with
  `mountain_id > 0 and is_interior == 1 and is_entrance == 0`
- entrance tiles clear their roof cell via `set_cell(..., -1)`
- aggregated alpha per chunk is **forbidden**
- on chunk unload, `ChunkView.queue_free` destroys all roof layers

Guardrail (mandatory from M2 onward):
- `WorldStreamer` exposes debug metric `roof_layers_per_chunk_max`
- when value exceeds `4`, emit one warning per session:
  `"roof layer explosion: chunk %s has %d mountains"`

### Reveal Registry

- `MountainRevealRegistry` is a single autoload or child of `WorldStreamer`
- authoritative state:
  - `Dictionary[int, float] _alpha_by_mountain` (0.0..1.0, where 1.0 =
    roof fully visible)
  - `Dictionary[int, float] _target_by_mountain`
- reveal fade uses time-based interpolation only
- fade time constant `FADE_SECONDS` (0.25..0.35)
- exit debounce constant `EXIT_DEBOUNCE` (0.5)
- registry registers one job on `FrameBudgetDispatcher` under
  `CATEGORY_VISUAL` with budget 0.2 ms
- signals:
  - `mountain_revealed(mountain_id: int)` fires when target flips to 0.0
  - `mountain_concealed(mountain_id: int)` fires when target flips to 1.0
- `ChunkView` subscribes to these and updates only the layer matching
  `mountain_id`

SDF/spatial reveal effects are forbidden in V1.

### Mountain Resolver

- `MountainResolver` is invoked once per frame from
  `Player._physics_process`
- steps:
  1. convert player world position to tile, chunk, and local coord
  2. read `mountain_id_per_tile` from the loaded chunk packet; if the
     chunk is not loaded, do nothing
  3. if `current != _last_mountain_id`, call
     `MountainRevealRegistry.request_reveal(current)` and
     `request_conceal(_last_mountain_id)` as appropriate
- when `current == 0` and opposite cardinal neighbors at distance 1 are
  interior tiles of the same mountain (a narrow doorway case), the
  resolver falls back to that 5-tile cross mountain to prevent thrash;
  adjacent-cardinal corners must not trigger fallback

Resolver does O(1) work per frame; no scene-tree queries, no raycasts.

### Excavation and Entrance

- V0 interactive path (`try_harvest_at_world`) remains unchanged in
  structure
- after a tile mutation, `ChunkView` calls
  `recompute_entrance_flag(world_tile)` for the mutated tile and its 4
  neighbors (5 tiles total)
- `recompute_entrance_flag` is the **single** source of truth for the
  entrance flag:
  - a tile is an entrance iff it is `is_interior == 1` **and** its
    diff-resolved terrain is walkable **and** it has at least one
    walkable 4-neighbor that exits the interior shell
    (`mountain_id != self` or neighbor `is_interior == 0`)
- the runtime entrance cache lives in `ChunkView._entrance_cache:
  PackedByteArray` (1024 bytes per chunk)
- the cache is **never** persisted; it is always derivable from
  `base + diff`
- on load / cold chunk rebuild, `ChunkView` recomputes the cache for every
  dirty tile in the chunk under the loading screen (boot/load class per
  ADR-0001)
- entrance transitions update the affected roof layer by
  `set_cell(..., -1)` on newly-marked entrance tiles and re-placing a
  roof cell when an entrance is closed again (diff removed or covered)

### Streaming and Apply

- mountain packet fields travel through the existing V0 chunk publish
  path unchanged
- roof `TileMapLayer` population is part of the same sliced publish loop
- no new `FrameBudgetDispatcher` category is introduced; reuse
  `CATEGORY_STREAMING` for publish and `CATEGORY_VISUAL` for reveal
  fade
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
  (`mountains`, later `rivers`, `biomes`, `climate`)
- on load, legacy saves with `world_version < 2` keep mountains disabled
  (`settings_packed = []`) for V0-compatible generation
- on load, for `world_version >= 2`, missing `worldgen_settings.mountains`
  → hard-coded defaults in the save loader, **not** re-read from
  `data/balance/mountain_gen_settings.tres`
- on new game, `WorldStreamer` writes the current resource's values
  exactly once into `world.json`, then never re-reads that resource for
  that world
- optional `worldgen_signature: String` may be written for diagnostics;
  it is not authoritative and absence is always valid

### chunks/*.json Unchanged

Chunk diffs keep `ChunkDiffV0` shape. Forbidden additions:
- `is_entrance`
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
- each bump is required by LAW 4 because canonical terrain / packet
  output changes for the same `seed + coord`
- `world_version` remains a plain integer; it is **not** a hash of
  `worldgen_settings`

### Reveal and Entrance State

- `MountainRevealRegistry` state is transient; not persisted
- after load, the resolver populates the first reveal request on the
  first post-load physics frame
- `ChunkView._entrance_cache` is runtime-only; rebuilt on publish

## Event Contract

New `EventBus` signals:
- `mountain_revealed(mountain_id: int)`
- `mountain_concealed(mountain_id: int)`

Emitter: `MountainRevealRegistry`.
Listeners: `ChunkView` instances that hold a layer for the affected
`mountain_id`.

Existing world signals are reused unchanged:
- `world_initialized(seed_value: int)`
- `chunk_loaded(chunk_coord: Vector2i)`
- `chunk_unloaded(chunk_coord: Vector2i)`

When V1 code lands, `event_contracts.md` is updated in the same task to
register the two new signals with their payloads, emitter, and listener
contract.

## Performance Class

| Operation | Class | Dirty unit | Budget |
|---|---|---|---|
| Mountain field sample | background (native worker) | 32x32 chunk | outside main thread |
| Anchor resolution | background (native worker) | 3x3 anchor cells per chunk | outside main thread |
| Sliced mountain publish | background apply | batch of cells | shares V0 `CATEGORY_STREAMING` budget |
| Resolver tile lookup | interactive | 1 tile | < 0.05 ms/frame |
| Reveal alpha tween | background apply | 1 `mountain_id` | < 0.2 ms/frame inside `CATEGORY_VISUAL` |
| Excavation mutation | interactive | 1 tile | V0 budget, unchanged |
| Entrance recompute on mutation | interactive | 5 tiles | < 1.0 ms |
| Entrance rebuild on load | boot/load | all dirty tiles in chunk | loading screen only |

### Forbidden Runtime Paths

- per-tile `Tween` on reveal
- per-tile `set_cell` during reveal (roof cells are static; only entrance
  transitions mutate cells)
- flood-fill over interior tiles on enter
- `mountain_id` recompute on mutation
- reveal state in save payload
- autotile-47 pass during reveal (atlas indices are precomputed at
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
- [ ] a single mountain's `mountain_id` is stable across chunk seams
- [ ] `mountain_id` does not change after initial generation, including
      after excavation that fully bisects a mountain

### Reveal

- [ ] entering a mountain interior fades only that mountain's roof
      layers; adjacent mountains stay at full alpha
- [ ] exiting restores roof alpha after `EXIT_DEBOUNCE`
- [ ] rapid boundary crossing does not produce visible reveal/conceal
      thrash
- [ ] reveal alpha is not written to the save payload

### Excavation

- [ ] digging an interior tile adjacent to a non-mountain tile marks it
      `is_entrance` and its roof cell clears immediately
- [ ] remaining interior tiles stay covered while the mountain is sealed
      from outside
- [ ] tunneling through a mountain produces a second entrance on the
      opposite side

### Persistence

- [ ] `new game` writes `worldgen_settings.mountains` into `world.json`
      exactly once
- [ ] loading a V0 save (no `worldgen_settings`) succeeds with hard-coded
      defaults
- [ ] loading a V1 save after the repository's
      `mountain_gen_settings.tres` has been edited produces the original
      world, not the edited defaults
- [ ] excavation diff survives save/load; entrance flags are recomputed
      correctly after load

### Performance

- [ ] native chunk packet generation stays off the main thread
- [ ] interactive excavation including entrance recompute completes under
      `1.0 ms` at p95
- [ ] `roof_layers_per_chunk_max > 4` emits exactly one warning per
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
- `core/systems/world/mountain_reveal_registry.gd`
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
- `docs/02_system_specs/meta/event_contracts.md` — register
  `mountain_revealed` and `mountain_concealed` with payload, emitter,
  listener contract
- `docs/02_system_specs/meta/system_api.md` — if `MountainResolver` or
  `MountainRevealRegistry` exposes a public read surface to other systems,
  document it here
- `docs/02_system_specs/meta/commands.md` — only if excavation gains a
  new formal command object in M3

`not required` entries must be accompanied by grep evidence against the
relevant doc at the time of landing.

## Risks

- noise tuning consuming disproportionate iteration budget; mitigated by
  keeping M1 acceptance visual-only, not balance-final
- `roof_layers_per_chunk_max` exceeding the guardrail at apparently
  reasonable defaults; mitigated by the debug metric
- entrance derivation drifting between mutation and load paths;
  mitigated by the single `recompute_entrance_flag` function contract
- `world.json` migration from V0 saves without `worldgen_settings`;
  mitigated by explicit hard-coded defaults in the loader
- legacy `mountain_shadow_system.gd.uid` and shader files producing
  confusion; mitigated by treating them as dead artifacts unless M2
  explicitly reuses a shader primitive

## Resolved Open Questions

All five open questions Q1–Q5 are resolved in
`MOUNTAIN_GENERATION_ARCHITECTURE.md` §10 as canonical Decision blocks.
Summary:

- Q1. Roof presentation is per `mountain_id`, not per chunk.
- Q2. Entrance is derived via a single shared function; not persisted.
- Q3. First playable reveal uses time-based alpha fade only; SDF
  deferred.
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

### M2 — Roof Overlay and Reveal

Goal: add `roof_layers_by_mountain` + `MountainRevealRegistry` +
`MountainResolver`.

Changes:
- extend `ChunkView` with `roof_layers_by_mountain` dictionary and
  per-layer alpha handling
- add `mountain_reveal_registry.gd` with the two signals and a
  `CATEGORY_VISUAL` job
- add `mountain_resolver.gd`; wire from `Player._physics_process`
- add `roof_layers_per_chunk_max` debug metric with warning

Acceptance tests for M2:
- [ ] entering a mountain fades only its roof
- [ ] exiting restores after debounce
- [ ] two adjacent mountains behave independently
- [ ] narrow doorway fallback keeps reveal stable

### M3 — Excavation and Entrance

Goal: derived entrance flag; single `recompute_entrance_flag` function
on both mutation and load paths.

Changes:
- add `_entrance_cache: PackedByteArray` to `ChunkView`
- add `recompute_entrance_flag(world_tile)` function
- invoke from `try_harvest_at_world` for 5-tile neighborhood
- invoke from load / cold chunk rebuild for every dirty tile in the
  chunk under loading screen
- update roof layers accordingly (`set_cell(..., -1)` on entrance)

Acceptance tests for M3:
- [ ] digging into a mountain produces an entrance
- [ ] entrance tile renders no roof cell; neighbors stay covered
- [ ] tunneling through produces two entrances
- [ ] load restores entrance look without save-payload involvement

### M4 — Worldgen Settings Plumbing

Goal: player-controllable mountain settings that travel with the save.

Changes:
- add `MountainGenSettings` resource and default `.tres`
- add main-menu (or new-game screen) sliders bound to the resource
- have `WorldStreamer` flatten settings into `settings_packed` once at
  world init and save / load them under `worldgen_settings.mountains`
- loader populates hard-coded defaults when the section is missing

Acceptance tests for M4:
- [ ] each slider measurably changes generation in a new game
- [ ] new game writes the section into `world.json`
- [ ] loading an old V0 save succeeds with defaults
- [ ] editing the repository's default `.tres` does not retroactively
      change an existing save

### M5 (Deferred, Out of Initial Approval Scope)

Optional polish: SDF spatial reveal, per-mountain color variance,
minimap icons, `under_mountain_strength` hint wiring for subsurface
generator.

M5 requires a spec amendment before implementation.

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
