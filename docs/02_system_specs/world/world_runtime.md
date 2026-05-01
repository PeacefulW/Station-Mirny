---
title: World Runtime V0
doc_type: system_spec
status: approved
owner: engineering
source_of_truth: true
version: 1.13
last_updated: 2026-05-01
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../meta/save_and_persistence.md
  - river_generation_v1.md
  - world_grid_rebuild_foundation.md
---

# World Runtime V0

## Purpose

Define the smallest working vertical slice of the rebuilt world runtime.

This V0 spec did not authorize rivers, multiple biomes, decor streaming, or
other future systems. River Generation V1 amends the active runtime for
`world_version >= 17`; current lakebed rasterization starts at
`world_version = 18`, and current delta / controlled-split rasterization starts
at `world_version = 19`. V1-R6 adds a current-water overlay seam without
changing canonical chunk generation, so the active world version remains `19`.
V1-R7 adds a worker-published new-game overview water mode, also without
changing canonical chunk generation or `world_version`. The new-game default
composite overview later reuses the same worker/native hydrology boundary and
still does not change chunk generation or `world_version`.
V1-R8 changes canonical water raster output through organic lake shorelines,
meandered river edges, and dynamic river width, so current new worlds advance to
`world_version = 20`. V1-R9 changes canonical ocean-edge packet output through
a real walkable shore band, so current new worlds advance to
`world_version = 21`. V1-R10 changes canonical river centerline geometry
through a native refined whole-path centerline substrate and bounded river
spatial-index queries, so current new worlds advance to `world_version = 22`.
V1-R11 changes canonical river width/depth classification through refined-edge
curvature and post-confluence context, so current new worlds advance to
`world_version = 23`. V1-R12 changes canonical confluence shape through native
Y-shaped confluence zones around qualifying joins, so current new worlds
advance to `world_version = 24`. V1-R13 changes canonical controlled split
shape through native rejoining braid island loops, so current new worlds
advance to `world_version = 25`. V1-R14 changes canonical lake shape through
native basin-contour depth/spill rasterization, so current new worlds advance
to `world_version = 26`. V1-R15 changes canonical ocean output through native
organic coastline and shelf classification, so current new worlds advance to
`world_version = 27`. V1-R16 changes canonical river/ocean shape quality
through continuous refined-river width, stricter braid loop validation, and
tile-sampled coastline SDF rasterization, so current new worlds advance to
`world_version = 28`. V1-R17 changes canonical ocean coastline shape through
multi-scale headland/bay carving, so current new worlds advance to
`world_version = 29`. V1-R18 lands the Hydrology Visual Quality V3 batch for
native chunk packet generation and current new worlds advance to
`world_version = 30`; hydrology rasterization remains worker/boot packet
generation, not interactive GDScript. River/Lake/Ocean Integration V4-2
advances current new worlds to `world_version = 31` for native river/lake
mountain-clearance packet output; V4-3 advances current new worlds to
`world_version = 32` for discharge-derived river width/depth output; V4-4
advances current new worlds to `world_version = 33` for coastline-integrated
estuary/delta coast SDF and fan output; V4-5 advances current new worlds to
`world_version = 34` for lake basin continuity and widened lake inlet/outlet
shore output; V4-7 advances current new worlds to `world_version = 35` for the
preset-selected `Lakes Only` density-zero native suppression branch; V4-8
advances current new worlds to `world_version = 36` for native dense
braid-loop closure and debug agreement semantics. These V4
changes keep hydrology work native worker/boot packet generation, not
interactive GDScript.
The original V0 baseline remains documented here as the minimal chunked-runtime
foundation.

## Gameplay Goal

The player must be able to:
- move across chunk boundaries without visible world breakage
- see deterministic chunks stream in and out from `world_seed + chunk_coord + world_version`
- modify one local terrain tile
- save and reload that one tile diff correctly on top of regenerated base terrain

## Scope

V0 includes only:
- surface layer only (`z = 0`)
- one canonical base biome only: `plains`
- one minimal deterministic base terrain palette for plains, including only the
  tile kinds required for walkability plus one single-tile mutation proof
- one compact `ChunkPacketV0`
- one native packet batch entrypoint:
  `WorldCore.generate_chunk_packets_batch(seed, coords, world_version, settings_packed)`
- one GDScript streamer/orchestrator
- one symmetric ring streaming policy with simple distance ordering
- one `ChunkView` root per visible chunk
- one `TileMapLayer` path for gameplay-critical terrain cells
- one runtime diff store for tile overrides only
- one save/load path for changed chunk diffs only
- integration with existing `FrameBudgetDispatcher`, `EventBus`, `SaveManager`,
  and the current `chunk_manager` compatibility expectations in gameplay code

## Out of Scope

V0 explicitly does not include:
- rivers
- mountains
- multiple biomes
- climate data
- biome blend logic
- placements
- decor
- foliage batching
- resource spot streaming beyond the single mutation proof
- environment overlay
- seasons, snow, ice, weather
- subsurface
- Z-level linking
- connector requests
- forward lobe / velocity-biased streaming
- hidden preload experiments
- node reuse pools unless profiling later proves they are immediately required
- a broad native framework or multi-class native API

## Law 0 Classification

| Question | V0 answer |
|---|---|
| Canonical or runtime? | Base chunk terrain is canonical; tile overrides are runtime diff; `ChunkView` is presentation only |
| Save/load required? | Yes, for per-chunk tile overrides only |
| Deterministic? | Yes, base packet is pure `f(seed, coord, world_version)` |
| Must work on unloaded chunks? | Yes, diff store remains authoritative when a chunk is not loaded |
| C++ compute or main-thread apply? | Generation in C++; publish/apply on main thread only |
| Dirty unit | `32 x 32` chunk for generation, one tile for authoritative mutation, bounded local visual patch for adjacency-dependent terrain presentation, bounded cell batches for publish |
| Single owner | `WorldCore` owns canonical base output; `WorldDiffStore` owns persisted overrides; `ChunkView` owns only presentation |
| 10x / 100x scale path | More chunks increase queued packet generation and sliced publish work; they do not expand the interactive mutation path |
| Main-thread blocking risk | Allowed only for bounded apply slices; heavy generation stays off-thread |
| Hidden GDScript fallback? | Forbidden; native world core is required |
| Could it become heavy later? | Yes; V0 already keeps generation in native code and publish sliced |
| Whole-world prepass? | Forbidden; V0 is local chunk generation only |

## Core Contract

### Chunk Geometry

- one world tile = `32 px`
- one chunk = `32 x 32` tiles
- chunk-local cell coordinates are `0..31` on each axis
- world X wrap follows ADR-0002
- world Y does not wrap

### ChunkPacketV0

`ChunkPacketV0` is the only hot-path native-to-script boundary for chunk data.

Required fields:

| Field | Type | Notes |
|---|---|---|
| `chunk_coord` | `Vector2i` | canonical chunk coordinate |
| `world_seed` | `int` | copied into the packet for validation/debug |
| `world_version` | `int` | first V0 runtime value starts at `1` |
| `terrain_ids` | `PackedInt32Array` | length `1024`, one terrain id per local tile |
| `terrain_atlas_indices` | `PackedInt32Array` | length `1024`, derived presentation atlas index per local tile |
| `walkable_flags` | `PackedByteArray` | length `1024`, `1 = walkable`, `0 = blocked` |

`terrain_atlas_indices` rules:
- it is derived presentation metadata, not authoritative terrain state
- it may be computed in native code for base packets
- runtime diff save files do not persist it
- loaded mutation paths may recompute only a bounded local visual patch instead
  of republishing a full chunk
- for hydrology-enabled worlds, plains-ground edge variants may open against
  native riverbed / river-bank / lakebed / ocean-floor adjacency while remaining
  derived presentation metadata
- local visual patches may recompute the same water-adjacent ground edge only
  from already-loaded packet/diff/overlay data

Forbidden packet fields in V0:
- climate bytes
- river masks
- mountain masks
- biome blend data
- placements
- decor batches
- connector requests
- seasonal or weather state

### Terrain Palette

V0 keeps the terrain palette intentionally tiny:
- one plains walkable ground tile class; presentation may use derived atlas indices
- one plains modified-result tile class if the mutation proof needs a distinct
  post-dig state

This does not authorize broader biome or terrain taxonomy work.

## Runtime Architecture

### Native Boundary

V0 uses one native class only:

```text
WorldCore.generate_chunk_packets_batch(
    seed: int,
    coords: PackedVector2Array,
    world_version: int,
    settings_packed: PackedFloat32Array
) -> Array
```

Rules:
- the method is synchronous
- `WorldStreamer` owns async scheduling by calling it from worker tasks
- one batch request returns one packet per input coord, in input order
- no per-tile callbacks
- the live runtime uses one native packet boundary only; no single-chunk helper
  API remains

Implementation shape is intentionally flat:
- keep native sources directly under `gdextension/src/`
- do not introduce `/core` vs `/godot` source trees in V0
- keep `gdextension/SConstruct` simple; extend only as much as the single native
  world core class requires

### Script Ownership

V0 introduces only three world runtime roles:

| Role | Owner | Responsibility |
|---|---|---|
| Orchestrator | `WorldStreamer` | stream ring, request packets, receive results, schedule publish, expose compatibility reads/mutation |
| State | `WorldDiffStore` | store per-chunk tile overrides, feed save/load |
| View | `ChunkView` | own one chunk root and one local `TileMapLayer` |

V0 does not add:
- a separate publish queue object
- a second streamer
- an environment overlay owner
- a generic world service graph

### Existing Compatibility Surface

The V0 world runtime root must join the existing `chunk_manager` group and
provide the smallest compatibility surface already expected by gameplay code:

```text
is_walkable_at_world(world_pos: Vector2) -> bool
has_resource_at_world(world_pos: Vector2) -> bool
try_harvest_at_world(world_pos: Vector2) -> Dictionary
```

V0 interpretation:
- `is_walkable_at_world` reads `base + diff`
- `has_resource_at_world` is allowed only as the single-tile mutation proof for
  the current diggable surface class provided by the active world runtime;
  diagonal-only sealed rock does not qualify, because the candidate tile must
  have at least one orthogonally exposed walkable face
- `try_harvest_at_world` is allowed only to convert that one diggable tile into
  its post-mutation state and return the minimal harvest/mutation result payload;
  the current harvest input path must resolve the nearest qualifying tile along
  the player-to-cursor ray and must not skip through a nearer blocking solid

This compatibility surface is not permission to reintroduce general resource
streaming in V0.

### V1-R1B Spawn, Bounds, and Substrate Amendment

For `world_version >= 9`, the active new-world path also carries
`worldgen_settings.world_bounds` and `worldgen_settings.foundation` into the
native `settings_packed` payload.

Rules:
- X chunk coordinates are canonicalized modulo `world_bounds.width_tiles`.
- Y chunk requests outside `world_bounds.height_tiles` are filtered by the
  streamer and clipped by native generation if a caller submits them anyway.
- the preview/new-game spawn-safe patch must be resolved from the native
  `WorldPrePass` substrate through
  `WorldCore.resolve_world_foundation_spawn_tile(...)` on the worker path before
  progressive preview chunks are queued.
- the spawn resolver rejects candidates in ocean/burning masks, open-water
  continent mask, and high wall density, then returns the selected
  `spawn_tile` plus `spawn_safe_patch_rect`.
- `WorldCore` still mirrors the selected safe patch as mountain-safe output in
  chunk packets so the first loaded area stays walkable.
- runtime new-game start queues the same native spawn resolver on the world
  packet worker, applies the returned `spawn_tile` to the local player through
  `PlayerAuthority`, and only then allows the streaming ring to enqueue chunks.
- save/load remains authoritative for persisted player position; `load_world_state`
  does not apply new-game spawn placement.
- script code may parse the native spawn result, but must not rederive substrate
  channels or provide a hidden GDScript fallback for `world_version >= 9`.

### River Generation V1-R1 Boundary Amendment

`world_version = 17` is the first river-enabled runtime boundary. The original
V0 out-of-scope list remains true only for the historical V0 baseline.

V1-R2/V1-R3A add a native diagnostic `WorldHydrologyPrePass` and river graph.
V1-R3B makes that native substrate part of gameplay chunk readiness by emitting
compact hydrology packet fields for `world_version >= 17`.
V1-R4 keeps the same packet shape and makes `lake_id`, lakebed terrain, lake
shoreline / bank markers, and default lake water classes live for
`world_version >= 18`.
V1-R5 keeps the same packet shape and makes river-mouth delta / estuary flags
and controlled braid/distributary split flags live for `world_version >= 19`.
V1-R6 keeps canonical packets seed-derived and adds `EnvironmentOverlay` for
explicit local current-water overrides.
V1-R7 keeps the same world version and makes river/lake/ocean placement visible
in the new-game overview through a native hydrology overview image. The
player-facing default composite overview blends that hydrology image as a
transparent overlay over the foundation terrain image on the preview worker.
V1-R8 advances current new worlds to `world_version = 20` and keeps the same
packet shape while making lake outlines, river centerlines, and river widths
organic in native chunk/overview generation.
V1-R9 advances current new worlds to `world_version = 21` and keeps the same
packet shape while making ocean-edge chunks emit a walkable `TERRAIN_SHORE`
band around the north-ocean sink.
V1-R10 advances current new worlds to `world_version = 22` and keeps the same
packet shape while making river chunk rasterization read refined native
whole-path centerlines through a bounded spatial-index candidate query.
V1-R11 advances current new worlds to `world_version = 23` and keeps the same
packet shape while making river width/depth rasterization use refined-edge
curvature and post-confluence reach classification.
V1-R12 advances current new worlds to `world_version = 24` and keeps the same
packet shape while making confluence rasterization mark two upstream arms and
the downstream reach as one native Y-shaped zone.
V1-R13 advances current new worlds to `world_version = 25` and keeps the same
packet shape while making eligible controlled split rasterization use native
rejoining braid island loops.
V1-R14 advances current new worlds to `world_version = 26` and keeps the same
packet shape while making lake rasterization use native basin-contour depth and
spill diagnostics for shallow rim/deep basin classification.
V1-R15 advances current new worlds to `world_version = 27` and keeps the same
packet shape while making ocean rasterization use native coast distance, shelf
depth, and river-mouth influence fields for shore/shallow-shelf/deep-ocean
classification.
V1-R16 advances current new worlds to `world_version = 28` and keeps the same
packet shape while making refined river width continuous along centerline
distance, validating braid island loops more strictly, and sampling coast
distance as tile-level coastline geometry for chunk and overview output.
V1-R17 advances current new worlds to `world_version = 29` and keeps the same
packet shape while adding deterministic multi-scale headland/bay carving to
that same tile-sampled coastline geometry for chunk and overview output.
V1-R18 advances current new worlds to `world_version = 30` and keeps the same
packet shape while activating Hydrology Visual Quality V3 chunk packet output,
including soft floodplain gradient flags and the already-native V3 river/lake
visual corrections.
River/Lake/Ocean Integration V4-2 advances current new worlds to
`world_version = 31` and keeps the same packet shape while suppressing
river/lake water inside the native mountain wall/foot clearance field.
River/Lake/Ocean Integration V4-3 advances current new worlds to
`world_version = 32` and keeps the same packet shape while deriving river
width/depth from normalized discharge and refined-edge width profiles.
River/Lake/Ocean Integration V4-4 advances current new worlds to
`world_version = 33` and keeps the same packet shape while integrating
qualifying river mouths into the coast SDF/shelf classifier and delta fan
geometry.
River/Lake/Ocean Integration V4-5 advances current new worlds to
`world_version = 34` and keeps the same packet shape while keeping lake
ownership for river-connected inlet/outlet samples and classifying them as
shallow widened lake shore.
River/Lake/Ocean Integration V4-7 advances current new worlds to
`world_version = 35` and keeps the same packet shape while allowing the
new-game `Lakes Only` preset to suppress trunk/tributary river selection through
the native density-zero branch. Existing `world_version = 34` saves keep the
previous density-zero behavior.
River/Lake/Ocean Integration V4-8 advances current new worlds to
`world_version = 36` and keeps the same packet shape while restoring dense
braid-loop acceptance after the shape-quality guard and tightening native
overview/preview/chunk debug agreement. Existing `world_version <= 35` saves
keep their prior generated output.

For the first river-enabled world version, River Generation V1 extends this
runtime contract without changing the hot-path ownership:

- mountains are generated first and river generation reads mountain wall/foot as
  hard no-go terrain with a clearance buffer;
- `WorldHydrologyPrePass` is native worker/boot/preview work owned by
  `WorldCore`;
- the new-game overview water/composite modes may build/reuse
  `WorldHydrologyPrePass` on the worker and publish image output only; they must
  not instantiate gameplay chunks or write save data;
- `generate_chunk_packets_batch(...)` remains the only chunk packet hot-path
  boundary and reads the hydrology snapshot internally;
- chunk readiness for a river-enabled world includes terrain ids, water class,
  hydrology ids/flags, stream order, and water atlas fields documented in
  `packet_schemas.md`;
- chunk readiness for a lake-enabled world includes native lakebed
  rasterization and `walkable_flags` derived from default shallow/deep lake
  water class;
- chunk readiness for a delta-enabled world includes native river-mouth
  widening, estuary/ocean-floor delta markers, and controlled split markers;
- chunk readiness for an organic-water world includes native lake shoreline
  noise, meandered river raster edges, and dynamic river width modulation;
- chunk readiness for an ocean-shore world includes native walkable ocean shore
  band rasterization with `TERRAIN_SHORE`, `HYDROLOGY_FLAG_SHORE`, and no
  current water on the shore tile;
- chunk readiness for a refined-river world includes native refined whole-path
  centerline rasterization and bounded spatial-index river candidate queries;
- chunk readiness for a curvature-river world includes native curvature-aware
  river width/depth classification, outer-bank deep thalweg shift, and
  post-confluence reach flags;
- chunk readiness for a Y-confluence river world includes native Y-shaped
  confluence influence zones on upstream arms and the downstream reach, using
  the existing `HYDROLOGY_FLAG_CONFLUENCE`;
- chunk readiness for a braid-loop river world includes native rejoining island
  loop edges for eligible controlled splits, using the existing
  `HYDROLOGY_FLAG_BRAID_SPLIT`;
- chunk readiness for a basin-contour lake world includes native selected-lake
  depth/spill diagnostics and shallow-rim/deep-basin lakebed classification,
  using the existing lakebed terrain and water-class packet arrays;
- chunk readiness for an organic-coastline world includes native coast
  distance, shelf depth, and river-mouth influence fields, using the existing
  shore/ocean terrain and water-class packet arrays;
- chunk readiness for a headland-coast world includes native multi-scale
  headland/bay carving in that same coast distance sampler, still using the
  existing shore/ocean terrain and water-class packet arrays;
- `walkable_flags` must already reflect default current water class: shallow
  water is walkable, deep/ocean water is blocking;
- riverbed, lakebed, shore, ocean floor, and floodplain are canonical base
  terrain; current water is overlay state on top;
- explicit local dry/wet changes must update only `EnvironmentOverlay` through
  an aligned `16 x 16` dirty block and must not rewrite immutable
  riverbed/lakebed terrain;
- `water_overlay_changed(region: Rect2i, reason: StringName)` is the current
  dirty event for loaded packet walkability refresh;
- broad drought/refill gameplay must queue/background larger overlay work rather
  than applying unbounded synchronous tile changes;
- GDScript must not compute hydrology, derive centerlines, rasterize SDFs, or
  loop through chunk tiles to build river fields.

### Streaming Policy V0

V0 uses one streamer and one symmetric ring only.

Rules:
- no forward lobe
- no transport-aware lead
- no hidden second preload ring
- candidate chunks are ordered by simple distance from the player
- chunk lifecycle stays minimal: `absent -> queued -> generating -> ready -> visible -> evicted`

### Publish / Apply Rules

`ChunkView` rules:
- one root per chunk
- one `TileMapLayer` child for gameplay-critical terrain
- only local chunk coordinates are written into the layer
- the world-space offset is stored on the chunk root, not baked into tile keys

Main-thread publish rules:
- chunk publish runs through `FrameBudgetDispatcher.CATEGORY_STREAMING`
- publish must be sliced into bounded cell batches
- worker threads must not touch `Node`, `TileMapLayer`, or any active scene-tree object
- worker threads must not emit scene-dependent events
- `TileMapLayer.clear()` is forbidden on runtime mutation paths
- TileMap autotiling / neighbour-solving APIs are forbidden on runtime hot paths

Single-tile mutation rules:
- write one override into `WorldDiffStore`
- update walkability locally
- if adjacency-dependent terrain presentation needs neighbour correction,
  recompute only the bounded local visual patch around the changed tile for
  already-loaded chunks
- do not regenerate the whole chunk packet
- do not republish the entire chunk view

Single-tile water overlay mutation rules:
- write one explicit override into `EnvironmentOverlay`
- emit one aligned `16 x 16` `water_overlay_changed` dirty block
- update only loaded packet `walkable_flags` inside that block
- do not mutate packet `terrain_ids` or seed-derived packet `water_class`
- do not regenerate the whole chunk packet
- do not redraw the whole chunk view

## Persistence Contract

### Authoritative Save Shape

V0 save/load uses:
- `world.json` for `world_seed` and `world_version`
- `worldgen_settings.world_bounds` and `worldgen_settings.foundation` for
  `world_version >= 9`
- `worldgen_settings.rivers` for `world_version >= 17`
- optional `world.json.water_overlay` for explicit local current-water overrides
- `chunks/<x>_<y>.json` for dirty chunk tile overrides only

Rules:
- base chunk data is never saved
- empty chunk diff = no chunk file
- load order is `regenerate base -> apply terrain diff -> apply water overlay -> publish`
- missing `world_version` on older saves defaults to `0` and is treated as a
  legacy regenerate-only case
- water overlay dirty queues are transient and are not serialized

### ChunkDiffV0

Each dirty chunk file stores only the minimum data needed to reapply local
terrain overrides:

```text
{
  "chunk_coord": {"x": int, "y": int},
  "tiles": Array[
    {
      "local_x": int,
      "local_y": int,
      "terrain_id": int,
      "walkable": bool,
    }
  ],
}
```

This shape is intentionally tile-only. No chunk-level cached presentation state
belongs in save files.

## Event Contract for V0

V0 reuses existing world-facing `EventBus` signals only:
- `world_initialized(seed_value: int)`
- `chunk_loaded(chunk_coord: Vector2i)`
- `chunk_unloaded(chunk_coord: Vector2i)`

V0 does not add new world runtime events unless implementation proves that the
existing signal set is insufficient.

## Performance Class

- interactive:
  - one tile mutation
  - one local diff write
  - one bounded local visible patch apply if loaded
- background compute:
  - native chunk generation off-thread
- background apply:
  - sliced chunk publish through `FrameBudgetDispatcher`
- boot/load:
  - initial chunk bubble materialization and diff restore

V0 is invalid if it:
- moves scene-tree work into workers
- adds a GDScript generator fallback
- rebuilds a full chunk for one tile mutation
- performs a whole-world prepass

## Acceptance Criteria

- [ ] player crosses chunk boundaries without visible world breakage
- [ ] the same `world_seed + chunk_coord + world_version` always yields the same `ChunkPacketV0`
- [ ] chunks stream in and out deterministically under a symmetric ring policy
- [ ] one modified tile survives save/load on top of regenerated base terrain
- [ ] no worker thread touches the active scene tree
- [ ] single-tile mutation does not trigger full chunk rebuild or full chunk redraw

## Files That May Be Touched In The First Implementation Task

- `gdextension/SConstruct`
- `gdextension/station_mirny.gdextension`
- new native files under `gdextension/src/`
- new files under `core/systems/world/`
- `core/autoloads/save_manager.gd`
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_appliers.gd`
- `core/autoloads/save_io.gd`
- `core/autoloads/event_bus.gd`
- `core/entities/player/player.gd`
- `core/systems/building/building_system.gd`
- `scenes/world/world_runtime_v0.tscn`
- `scenes/world/world_runtime_v0_scene.gd`
- `scenes/ui/main_menu.gd`
- `scenes/ui/save_load_tab.gd`
- `scenes/ui/death_screen.gd`
- the active world/gameplay scene that instantiates the V0 world runtime root

## Files That Must Not Be Touched In The First Implementation Task

- biome registries and biome data resources
- flora/decor batching systems
- environment overlay systems
- subsurface / Z-level runtime beyond current read-only compatibility
- unrelated combat, UI, progression, or lore systems
- any deleted legacy world runtime files

## Required Canonical Doc Follow-Ups When Code Lands

When V0 is implemented, the same task must update:
- `docs/02_system_specs/meta/packet_schemas.md` with `ChunkPacketV0` and `ChunkDiffV0`
- `docs/02_system_specs/meta/save_and_persistence.md` with `world_version` and `chunks/*.json`
- `docs/02_system_specs/meta/system_api.md` with the documented `chunk_manager` compatibility surface if it remains public
- `docs/02_system_specs/meta/event_contracts.md` once `world_initialized`, `chunk_loaded`, and `chunk_unloaded` have confirmed emitters and listeners
- `docs/02_system_specs/meta/commands.md` only if implementation introduces a dedicated world mutation command object

These follow-ups are intentionally deferred until code confirms the final names
and payloads.

## Risks

- treating V0 as permission to pre-design V2+ systems
- allowing packet fields to grow before there is a consumer
- hiding a whole-chunk redraw inside a "temporary" helper
- implementing a native async API before the single synchronous packet boundary
  is proven sufficient

## Open Questions

- which existing scene is the smallest safe host for the `WorldStreamer` root?
- should the single-tile mutation proof use the current harvest input path or a
  smaller developer-only trigger in the first implementation task?
- is one chunk publish slice best expressed as rows, fixed-size cell batches, or
  another equally local apply unit?

## Implementation Iterations

### V0 - End-to-end chunk runtime proof

Goal:
- prove chunk streaming, deterministic generation, and one persisted tile diff
  without building future systems early

What changes:
- add one native world core class with `generate_chunk_packet`
- add one script streamer, one diff store, and one chunk view
- hook save/load for chunk diffs
- wire the minimal `chunk_manager` compatibility surface used by current
  gameplay code

What does not change:
- biome/content pipeline
- environment runtime layering
- mountain, river, or placement solves
- transport-aware streaming
- chunk view reuse/pooling

Verification expectation:
- static verification in-session is mandatory
- runtime crossing / save-load / hot-path behavior remains manual human
  verification unless a later implementation task explicitly runs Godot
