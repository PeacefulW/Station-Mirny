---
title: River Generation V1
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.0
last_updated: 2026-04-25
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - world_grid_rebuild_foundation.md
  - world_runtime.md
  - world_foundation_v1.md
  - terrain_hybrid_presentation.md
---

# River Generation V1

## Status

This is the approved river specification for the first tile-level riverbed
generation pass.

It consumes the existing `WorldPrePass` substrate from
`world_foundation_v1.md`. It does not replace `WorldPrePass`, does not create a
second world-scale river prepass, and does not implement water simulation in
the first iteration.

The first implementation target is intentionally dry:

- all riverbeds are visible as empty terrain features;
- lake footprints are visible as empty lakebed scars;
- no water overlay is rendered yet;
- no deep-water blocking exists yet;
- the dry pass exists so the river shapes can be inspected and tuned before
  water hides the bed geometry.

## Purpose

Define how Station Mirny turns the coarse river skeleton already owned by
`WorldPrePass` into tile-level riverbeds and lakebeds while preserving:

- deterministic chunk generation;
- the immutable base plus runtime diff model;
- future drought support;
- bounded chunk publish/apply work;
- water-independent visual review of river paths;
- terrain edge readability through `47`-case ground autotile decisions.

## Gameplay Goal

The player should eventually read the surface as a large cylindrical world with:

- a top-Y ocean band;
- river systems that drain into that ocean;
- channels that are broader near the ocean and narrower farther down the map;
- occasional split and rejoin channels that create islands;
- lake basins and dry lake traces;
- clear shallow/deep channel identity;
- drought states where water may disappear but the riverbed remains visible.

Before water is implemented, the player and developer must be able to inspect
the same river network as dry terrain:

- empty riverbeds show the future path of water;
- empty lakebeds show future lake footprints;
- the surrounding ground already forms proper `47`-tile banks against those
  beds;
- tuning can happen on the bed layout itself without water presentation hiding
  mistakes.

## Design Principles

### Riverbed is not water

`riverbed` is canonical base world data. It answers: "where did water carve or
will water flow?"

`water` is future runtime/environment overlay data. It answers: "how much water
is present right now?"

This split is mandatory because drought can remove water without deleting the
riverbed.

### Dry review comes first

The first playable/debug iteration must render riverbeds and lakebeds without
water. This is not a placeholder failure mode. It is the required authoring and
tuning phase.

### Rivers drain into the top ocean

The visual direction is:

- top Y: ocean mouth / lower drainage outlet;
- lower map: narrower upstream channels and headwaters.

The player may describe the rivers as "coming from the ocean" visually, but the
worldgen contract treats them as draining into the ocean. This keeps hydrology
coherent while matching the desired map read: wide near the ocean, narrow
toward the bottom.

### `WorldPrePass` remains the substrate source

The river rasterizer consumes:

- `downstream_index`;
- `flow_accumulation`;
- `visible_trunk_mask`;
- `strahler_order`;
- `is_terminal_lake_center`;
- `terminal_lake_polygon`;
- `continent_mask`;
- `ocean_band_mask`;
- `burning_band_mask`;
- `coarse_wall_density`;
- `coarse_valley_score`;
- `hydro_height`.

It must not recalculate a second competing flow graph.

### Ground banks must resolve against dry beds

Plain ground and other ordinary ground terrain must use `47`-tile edge
decisions when adjacent to:

- dry riverbed shallow tiles;
- dry riverbed deep-channel tiles;
- dry lakebed shallow tiles;
- dry lakebed deep-basin tiles;
- future water overlay tiles;
- ocean-band water terrain, once ocean terrain is realized.

This is true even before water exists. The edge trigger is the channel or basin
footprint, not the visible water surface.

## Scope

V1 covers:

- tile-level dry riverbed rasterization from `WorldPrePass`;
- tile-level dry lakebed rasterization from terminal lake polygons;
- shallow/deep bed classification;
- ocean-directed river realization;
- bounded split/rejoin side channels that create islands;
- deterministic river width curves;
- additive chunk packet fields for riverbed/lakebed data;
- dry riverbed and dry lakebed presentation;
- ground `47`-tile edge solving against river/lake footprints;
- debug/readability surfaces needed to tune river paths before water;
- future water overlay ownership rules.

## Out of Scope

V1 does not include:

- runtime water simulation;
- drought gameplay implementation;
- flowing water animation;
- seasonal water level changes;
- flooding;
- boats, swimming, bridges, fishing, water harvesting, or water processing;
- biome content beyond river/lake structure context;
- ocean biome terrain art beyond the existing ocean-band substrate mask;
- erosion simulation after world load;
- player-made canal digging;
- save migration for older worlds beyond the normal `world_version` boundary;
- subsurface rivers or aquifers;
- multiplayer water replication details.

## Dependencies

- `world_foundation_v1.md` owns `WorldPrePass`, finite bounds, ocean band,
  river skeleton fields, and `river_amount`.
- `world_runtime.md` owns chunk packet/publish discipline and the current
  `ChunkPacketV1` shape.
- `world_grid_rebuild_foundation.md` owns `32 px` tile and `32 x 32` chunk
  geometry.
- `terrain_hybrid_presentation.md` owns terrain shape/material presentation
  rules and registry-backed terrain profiles.
- ADR-0001 owns runtime work classes and dirty-update restrictions.
- ADR-0002 owns cylindrical X wrapping and bounded Y.
- ADR-0003 owns immutable base plus runtime diff.
- ADR-0007 owns the worldgen versus environment-runtime boundary.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical, runtime overlay, or visual only? | Riverbed and lakebed footprints are canonical base world data. Water presence is future runtime/environment overlay. Dry preview art is derived presentation. |
| Save / load required? | Riverbed/lakebed are not saved per tile; they regenerate from seed, `world_version`, bounds, mountain settings, foundation settings, and future river settings. Future drought/water state may persist only slow world state, not per-tile water snapshots. |
| Deterministic? | Yes. Dry bed output is a pure function of `(seed, world_version, chunk_coord, settings_packed, WorldPrePass snapshot)`. |
| Must work on unloaded chunks? | Yes. Any chunk can regenerate its riverbed/lakebed base output independently from the native substrate cache. |
| C++ compute or main-thread apply? | Rasterization and atlas decisions are native worker compute. Main thread only publishes prepared packet arrays through sliced chunk apply. |
| Dirty unit | `32 x 32` chunk for base generation. One local tile/diff for future player mutation. Future water overlay dirty unit is chunk or basin-region, never whole loaded world on an interactive path. |
| Single owner | `WorldCore` owns base riverbed/lakebed rasterization. Future `WaterRuntime` or environment overlay owner owns water presence. `WorldDiffStore` owns player changes. `ChunkView` owns presentation only. |
| 10x / 100x scale path | River graph remains coarse in `WorldPrePass`; tile rasterization happens per requested chunk plus bounded halo. No whole-world tile raster is required during gameplay. |
| Main-thread blocking? | Forbidden. No GDScript tile loops for generation, river masks, or atlas decisions. |
| Hidden GDScript fallback? | Forbidden. If native river rasterization is unavailable for a world version that requires it, generation fails loudly. |
| Could it become heavy later? | Yes. Therefore centerline generation, distance fields, width solve, split/rejoin selection, and atlas decisions belong in native code from the first implementation. |
| Whole-world prepass or local compute only? | The existing `WorldPrePass` whole-world coarse substrate is allowed by `world_foundation_v1.md`. V1 river rasterization itself is local chunk compute over that substrate, not a second whole-world pass. |

## Core Terms

### Riverbed

Canonical dry channel terrain carved by future or historical water.

Riverbed remains visible when water is absent. It is base world data, not a
runtime water state.

### Riverbed depth

Tile-level bed classification:

- `none`: no river/lake bed;
- `shallow`: edge shelf, walkable in dry state;
- `deep`: central channel or basin depression, still dry-bed terrain until
  water overlay marks it as filled.

The term `deep` does not mean blocked by itself. `deep water` blocks movement;
dry deep bed does not block by default.

### Water overlay

Future runtime/environment layer that marks whether a bed tile currently
contains water.

Water overlay is allowed to affect walkability, visuals, audio, and harvesting,
but it must not rewrite canonical riverbed/lakebed base terrain.

### Lakebed scar

Dry footprint of a lake candidate. It remains visible before water exists and
during drought.

### Ocean-directed trunk

A visible river trunk whose downstream chain reaches the top-Y ocean band.
Only ocean-directed trunks become primary rivers in V1.

### Side channel

A deterministic secondary channel created from one point of an existing trunk to
a downstream point on the same river system. Side channels are used for islands,
braids, and deltas. They must rejoin or terminate in a valid lake/ocean outlet.

## Data Model

### Terrain IDs

V1 implementation should add new terrain ids rather than overloading plains or
mountain terrain.

Recommended ids:

| Constant | Base walkable | Purpose |
|---|---:|---|
| `TERRAIN_RIVERBED_SHALLOW` | `1` | Dry shallow shelf along river edges. |
| `TERRAIN_RIVERBED_DEEP` | `1` | Dry central channel. Future water overlay may block this tile when filled. |
| `TERRAIN_LAKEBED_SHALLOW` | `1` | Dry lake rim / lake shelf. |
| `TERRAIN_LAKEBED_DEEP` | `1` | Dry basin center. Future water overlay may block this tile when filled. |

The dry base terrain remains walkable so the first riverbed review pass does
not introduce invisible movement blockers before water is implemented.

Future water blocking must be computed by the movement query as:

```text
base_walkable && !water_overlay_blocks(world_tile)
```

not by permanently writing blocked base terrain into dry riverbed tiles.

### ChunkPacketV2 Additive Fields

`ChunkPacketV2` should extend `ChunkPacketV1` additively. No existing field is
removed or reshaped.

Recommended additive fields:

| Field | Type | Length | Notes |
|---|---|---:|---|
| `riverbed_flags` | `PackedByteArray` | 1024 | Bit layout below. |
| `riverbed_depth` | `PackedByteArray` | 1024 | `0 none`, `1 shallow`, `2 deep`. |
| `riverbed_atlas_indices` | `PackedInt32Array` | 1024 | Optional if bed terrain uses a separate topology from `terrain_atlas_indices`; otherwise keep this omitted. |
| `river_flow_q8` | `PackedByteArray` | 1024 | Optional quantized flow for presentation/debug, `0..255`; not authoritative for hydrology. |

`riverbed_flags` bit layout:

| Bit | Name | Meaning |
|---:|---|---|
| `1 << 0` | `is_riverbed` | Tile belongs to a river channel footprint. |
| `1 << 1` | `is_lakebed` | Tile belongs to a lakebed footprint. |
| `1 << 2` | `is_ocean_directed` | River path drains into the top ocean band. |
| `1 << 3` | `is_side_channel` | Tile belongs to a split/rejoin side channel. |
| `1 << 4` | `is_mouth_or_delta` | Tile belongs to ocean mouth/delta widening. |
| `1 << 5` | `is_debug_orphan` | Dev-only flag for a candidate rejected from gameplay realization. Must be stripped or zero in release packets. |

The final implementation may collapse `riverbed_atlas_indices` into
`terrain_atlas_indices` if every bed terrain id can use the normal per-tile
atlas field. If a new bed topology family needs independent atlas decisions,
document that in `packet_schemas.md` when code lands.

### Save Data

No per-tile riverbed or lakebed data is saved.

Current `worldgen_settings.foundation.river_amount` remains the first density
knob because it already exists in save shape and `settings_packed`.

If implementation adds more river controls, introduce:

```json
{
  "worldgen_settings": {
    "rivers": {
      "bed_width_scale": 1.0,
      "split_density": 0.35,
      "lake_scale": 1.0,
      "ocean_mouth_bias": 1.0
    }
  }
}
```

Rules:

- new worlds write river settings once;
- existing worlds load river settings from `world.json`;
- missing `worldgen_settings.rivers` restores hard-coded loader defaults, not
  repository `.tres` values;
- adding or changing river settings that alter canonical output requires a
  `WORLD_VERSION` bump.

### Future Water State

Future drought/water state must not be stored as per-tile full-world water.

Allowed save direction:

- global drought phase;
- basin or region water-level scalar if the later design needs local variation;
- timestamp/seasonal state needed to reconstruct water overlay.

Forbidden save direction:

- full map water tile dump;
- duplicated riverbed footprint;
- storing water overlay inside `ChunkDiffFile` unless a player action changes a
  specific tile as an authoritative diff.

## River Rasterization Pipeline

### 1. Select ocean-directed trunks

Starting from `visible_trunk_mask` nodes, follow `downstream_index` until the
chain terminates.

Realize a primary river only when the downstream chain reaches:

- `ocean_band_mask == 1`; or
- a terminal lake that has an accepted outlet chain to the ocean.

Do not realize as gameplay river:

- chains that drain into the burning band;
- chains that drain into open-water continent gaps not connected to the top
  ocean;
- chains whose downstream path is blocked by high mountain wall density;
- cycles or invalid chains, which should already be rejected by `WorldPrePass`
  debug assertions.

Rejected chains may be exposed in dev debug layers as `orphan drainage`, but
they must not become player-facing riverbeds in V1.

### 2. Build deterministic centerlines

For each accepted trunk:

1. Convert coarse node centers to tile coordinates.
2. Add deterministic sub-cell offsets from seed, river id, node id, and flow.
3. Smooth the path with a bounded curve method.
4. Clamp the path inside routing-eligible land and away from hard mountain wall
   cells.
5. Preserve X-wrap continuity when a river crosses the cylindrical seam.

The centerline is not saved. It is derived inside native chunk generation or
inside a native cache keyed by the `WorldPrePass` signature.

### 3. Width and depth solve

Width is a deterministic function of:

- `flow_accumulation`;
- `strahler_order`;
- downstream distance to ocean mouth;
- local `coarse_valley_score`;
- local mountain wall pressure;
- optional future `worldgen_settings.rivers.bed_width_scale`.

Required shape:

- near ocean mouths: wider channels and possible delta/braid widening;
- mid course: stable medium channel;
- upstream/lower-map headwaters: narrow channel;
- low-flow branches below a visible threshold: no player-facing riverbed.

Depth split:

```text
distance_to_center <= deep_radius      -> deep bed
distance_to_center <= shallow_radius   -> shallow bed
else                                   -> no riverbed
```

Deep radius must never consume the whole bed. A visible shallow shelf is
required on both sides whenever width allows it.

### 4. Split and rejoin side channels

`WorldPrePass` D8 routing gives one downstream edge, so split/rejoin islands
must be a second deterministic layer.

Side-channel eligibility:

- parent trunk has high enough `flow_accumulation`;
- parent trunk has `strahler_order >= 2`;
- local slope is low or valley score is high;
- side channel can rejoin the same trunk downstream within a bounded distance;
- generated loop does not cross mountain walls, ocean band, or another active
  island loop;
- island interior remains land.

Required constraints:

- every side channel must rejoin or terminate in a valid lake/ocean outlet;
- no dead-end side channels;
- no random branch that becomes a second untracked source of truth;
- side-channel count per trunk segment is capped by settings and packet budget;
- islands must be visible in dry preview before water exists.

### 5. Lakebed scars

Use `terminal_lake_polygon` and `is_terminal_lake_center` from `WorldPrePass`.

For each accepted lake candidate:

- render a dry lakebed scar in the first implementation;
- classify rim as shallow lakebed;
- classify basin center as deep lakebed;
- connect incoming riverbeds to the lakebed footprint;
- connect outgoing bed only when the lake has an accepted outlet chain;
- clip lakebed at Y world bounds;
- preserve X-wrap correctness and avoid self-overlap at the seam.

Future water may fill lakes, but dry lakebed must remain visible when water is
absent.

### 6. Terrain priority

Base terrain priority during packet generation:

1. hard Y ocean/burning bands, when their actual terrain content exists;
2. mountain wall/foot terrain;
3. riverbed/lakebed terrain where not blocked by mountain wall;
4. ordinary ground/biome terrain.

Riverbeds must not cut through canonical mountain walls in V1. A river may run
along valleys and foothills, but not overwrite mountain ownership.

### 7. Ground `47`-tile edge solve

After riverbed/lakebed classification, native terrain atlas solving must compute
ordinary ground edges against the final base footprint.

For a ground tile, each neighbor is ground-compatible only if that neighbor is
ordinary ground or another terrain class explicitly declared ground-compatible.

Non-ground-compatible neighbors include:

- `TERRAIN_RIVERBED_SHALLOW`;
- `TERRAIN_RIVERBED_DEEP`;
- `TERRAIN_LAKEBED_SHALLOW`;
- `TERRAIN_LAKEBED_DEEP`;
- future water-only terrain or ocean terrain;
- mountain wall/foot terrain where the current terrain family already treats
  mountains as a boundary.

This replaces the current "solid ground only until water exists" behavior once
R1B lands. The rule must be implemented in native atlas decisions, not in a
GDScript post-process.

## Runtime Architecture

### Native responsibilities

`WorldCore` owns:

- accepted trunk selection from `WorldPrePass`;
- centerline smoothing;
- split/rejoin side-channel generation;
- lakebed footprint rasterization;
- riverbed depth classification;
- ground adjacency/atlas decisions against river/lake footprints;
- compact chunk packet output.

### GDScript responsibilities

`WorldStreamer` owns:

- forwarding packet arrays;
- applying `WorldDiffStore` overrides;
- exposing read methods that combine base terrain, diff, and future water
  overlay for walkability;
- never recomputing river masks in script.

`ChunkView` owns:

- dry riverbed/lakebed publication;
- future water overlay publication;
- no authoritative state.

`TerrainPresentationRegistry` owns:

- shape/material profile mapping for dry riverbed and dry lakebed terrain ids;
- no terrain truth.

### Future water owner

A later `WaterRuntime` or environment overlay owner must own water presence.

It may read:

- riverbed/lakebed flags;
- riverbed depth;
- world clock / season / drought state;
- biome/environment context.

It must not mutate:

- `WorldPrePass`;
- base `terrain_ids`;
- riverbed/lakebed packet fields;
- `WorldDiffStore` except through a documented command/diff path.

## Presentation Contract

### Dry-first presentation

R1 dry presentation must clearly show:

- shallow bed;
- deep channel;
- lake rim;
- lake basin;
- split/rejoin side channels;
- islands between channels;
- ocean mouths/delta widening where present.

It must not show:

- water fill;
- animated water;
- water blocking;
- flood or drought UI.

### Terrain profiles

Dry river/lake bed terrain ids should resolve through
`TerrainPresentationRegistry`, using data resources and shared shape/material
patterns.

The first visual pass may reuse an existing topology family if it satisfies the
bank readability requirement, but long-term bed presentation should have a
dedicated material profile so dry beds read as channels, not as generic dug
ground.

### Ground edge requirement

Ground bank edges are part of acceptance. A dry riverbed touching ordinary
ground must already produce a visible edge, even with no water layer.

Failure signs:

- plains ground stays visually solid when adjacent to riverbed;
- banks appear only after water is enabled;
- shallow bed is treated as ground-compatible and erases the bank edge;
- edge decisions are patched in `ChunkView` instead of native packet solve.

## Save / Load Contract

Riverbed and lakebed base output is regenerated. It is not saved.

Save files may store:

- `world_seed`;
- `world_version`;
- `worldgen_settings.world_bounds`;
- `worldgen_settings.foundation`;
- `worldgen_settings.mountains`;
- future `worldgen_settings.rivers`;
- future slow drought/water state.

Save files must not store:

- `riverbed_flags` arrays;
- `riverbed_depth` arrays;
- centerline control points;
- lake polygons copied from `WorldPrePass`;
- presentation atlas indices;
- dry preview debug output.

Loading an existing world after river generation lands must either:

- preserve the old output path for old `world_version`; or
- intentionally migrate through a documented `WORLD_VERSION` boundary.

## Event and Command Contract

R1 dry riverbed generation should not add domain events or commands.

Future water/drought may require events such as water-level changed, but those
must be defined in `event_contracts.md` only when code lands.

Future player-made canals, dams, pumps, or water manipulation must use command
objects and runtime diffs. They are not part of V1.

## Performance Class

| Operation | Class | Dirty unit | Budget |
|---|---|---|---|
| `WorldPrePass` substrate build | boot/load or preview worker | whole coarse substrate | existing `world_foundation_v1.md` budget |
| Riverbed/lakebed rasterization | background native worker | `32 x 32` chunk plus bounded halo | part of chunk packet generation |
| Ground atlas solve against beds | background native worker | `32 x 32` chunk plus neighbor halo | part of chunk packet generation |
| Dry bed publish | background apply | sliced cell batches | existing streaming publish budget |
| Future water overlay visual update | background apply | chunk or basin-region | must use dirty queue / budgeted apply |
| Movement walkability query with water | interactive | one tile | no flood fill, no chunk scan |

Forbidden:

- GDScript loops over chunk tiles to generate river masks;
- full-world tile rasterization during gameplay;
- rebuilding all loaded chunks when drought changes;
- mass `TileMapLayer.clear()` to toggle water;
- storing water by mutating base terrain ids;
- per-tile node instances for water or bed tiles.

## Debug and Tuning Contract

R1 must expose enough debug data to tune dry river layout before water.

Required debug views:

- dry riverbed/lakebed overlay in world chunks;
- overview layer for accepted ocean-directed trunks;
- overview layer for rejected/orphan drainage candidates;
- lakebed scars;
- side-channel/island candidates;
- river depth class;
- ground-bank edge adjacency.

Required debug counters:

- accepted trunk count;
- rejected trunk count by reason;
- side channel count;
- lakebed count;
- riverbed tile count per loaded chunk;
- deep/shallow ratio;
- ocean-mouth count;
- max side channels per trunk;
- chunks where ground edge solve has riverbed adjacency.

Debug surfaces are not save data.

## Acceptance Criteria

### Dry Riverbed Preview

- [ ] With water disabled, all accepted rivers are visible as empty beds.
- [ ] With water disabled, lake candidates are visible as empty lakebed scars.
- [ ] Shallow and deep bed zones are visually distinguishable.
- [ ] The dry view shows split/rejoin side channels and islands.
- [ ] No water overlay appears in R1 dry preview.

### Hydrology / Shape

- [ ] Realized primary rivers drain into the top-Y ocean band.
- [ ] River width generally increases toward the ocean mouth and narrows toward
      lower-map upstream/headwater segments.
- [ ] River paths are continuous across chunk seams.
- [ ] X-wrap seam rivers remain continuous and do not self-overlap.
- [ ] Rejected non-ocean drainage does not become player-facing riverbed.
- [ ] Terminal lakebed polygons are clipped at Y bounds and are seam-safe on X.

### Split / Rejoin

- [ ] Every side channel rejoins downstream or terminates in a valid lake/ocean
      outlet.
- [ ] Side channels create land islands, not filled rectangles of water/bed.
- [ ] No side channel crosses mountain walls.
- [ ] Side-channel generation is deterministic for the same seed/settings.

### Terrain Edges

- [ ] Ordinary ground uses `47`-tile edge decisions when adjacent to dry shallow
      riverbed.
- [ ] Ordinary ground uses `47`-tile edge decisions when adjacent to dry deep
      riverbed.
- [ ] Ordinary ground uses `47`-tile edge decisions when adjacent to dry
      lakebed.
- [ ] The same bank edge remains valid when future water overlay fills the bed.
- [ ] Edge decisions are native packet output, not a `ChunkView` post-process.

### Persistence

- [ ] Riverbed/lakebed arrays are not written to save files.
- [ ] Existing `world_version` compatibility rules are preserved.
- [ ] Any canonical river output change bumps `WORLD_VERSION`.
- [ ] Future `worldgen_settings.rivers` values, if added, are written once for
      new worlds and restored from save on load.

### Performance

- [ ] Riverbed rasterization runs in native chunk generation, off the main
      thread.
- [ ] Chunk publish remains sliced through the existing streaming budget.
- [ ] No GDScript fallback computes river masks or atlas decisions.
- [ ] Movement queries do not scan chunks or flood-fill water.
- [ ] Future drought/water changes have a dirty unit and do not rebuild all
      loaded chunks synchronously.

## Implementation Iterations

### R1A - Spec and dry debug target

Goal: establish this spec and prepare implementation scope.

Scope:

- write this spec;
- update docs indices;
- no code;
- no packet schema change yet.

Acceptance:

- spec names source of truth, owners, packet direction, save rules, dry-first
  requirement, and ground `47`-tile edge requirement.

### R1B - Native dry riverbed rasterization

Goal: show empty riverbeds and lakebed scars in gameplay chunks.

Expected changes:

- add native river rasterization consuming `WorldPrePass`;
- add river/lake terrain ids;
- add `ChunkPacketV2` additive river fields;
- update ground atlas solve to treat river/lake beds as ground boundaries;
- add terrain presentation profiles for dry river/lake bed ids;
- bump `WORLD_VERSION`;
- update `packet_schemas.md`, `save_and_persistence.md`, `system_api.md` if
  final surfaces differ from this spec.

No water overlay in R1B.

### R1C - Dry overview and tuning diagnostics

Goal: make the full-world/new-game overview useful for river tuning.

Expected changes:

- show accepted dry trunks;
- show lakebed scars;
- show rejected/orphan drainage debug layer;
- show side-channel candidates;
- expose counters listed in Debug and Tuning Contract.

No water overlay in R1C.

### R1D - Split/rejoin islands

Goal: add controlled island-forming side channels after primary dry beds are
readable.

Expected changes:

- deterministic side-channel generation;
- rejoin validation;
- island interior preservation;
- debug counters and rejection reasons.

No water overlay in R1D unless R1B/R1C/R1D dry shape acceptance is already
closed.

### R2 - Water overlay contract

Goal: implement water only after dry riverbeds are accepted.

Expected changes:

- add water overlay owner;
- define water level state;
- combine water overlay with walkability queries;
- render shallow/deep water over existing beds;
- keep dry bed visible when water disappears.

R2 requires either this spec to be amended or a separate water-runtime spec.

## Files That May Be Touched When Code Lands

Likely new files:

- `gdextension/src/river_rasterizer.h`
- `gdextension/src/river_rasterizer.cpp`
- dry river/lake terrain presentation resources under `data/terrain/`
- optional `core/resources/river_gen_settings.gd`
- optional `data/balance/river_gen_settings.tres`

Likely modified files:

- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_prepass.h`
- `gdextension/src/world_prepass.cpp`
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/world_streamer.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `core/systems/world/world_foundation_palette.gd`
- `core/systems/world/world_preview_controller.gd`
- `scenes/ui/world_overview_canvas.gd`
- save/load owners only if `worldgen_settings.rivers` or future water state is
  added

Docs to update when code lands:

- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/event_contracts.md` only if new events land
- `docs/02_system_specs/meta/commands.md` only if new commands land
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `docs/02_system_specs/world/terrain_hybrid_presentation.md` if topology or
  profile rules change beyond this spec

## Files That Must Not Be Touched In R1B

- `BuildingSystem`, `PowerSystem`, `IndoorSolver`;
- combat, fauna, progression, inventory, crafting, lore systems;
- subsurface / Z-level runtime;
- environment runtime weather/season/wind implementation, except future R2 water
  spec work;
- save chunk diff shape, unless a later approved task adds player-made terrain
  water/canal mutation;
- deleted legacy world runtime files.

## Required Canonical Doc Follow-Ups When Code Lands

- `packet_schemas.md`: add `ChunkPacketV2` fields and river flag bit layout.
- `save_and_persistence.md`: document `worldgen_settings.rivers` only if new
  settings are added; otherwise document that `river_amount` remains under
  `foundation` for R1.
- `system_api.md`: document any new public read/debug surfaces on `WorldCore`,
  `WorldStreamer`, or water runtime.
- `event_contracts.md`: update only if water/drought events are emitted and
  listened to.
- `commands.md`: update only if player-made canals, dams, pumps, or direct water
  mutations are introduced.
- `PROJECT_GLOSSARY.md`: confirm the current `Riverbed`, `Riverbed depth`,
  `Lakebed scar`, `Water overlay`, `Ocean-directed trunk`, and `Side channel`
  definitions still match final implementation names and semantics.

`not required` must be backed by grep evidence in the implementation closure
report.

## Risks

| Risk | Mitigation |
|---|---|
| Rivers look like random blue/no-water cracks instead of drainage systems | Accept only ocean-directed trunks, expose rejected drainage debug, tune dry beds before water. |
| Water hides bed mistakes too early | R1 explicitly forbids water overlay. Dry riverbed acceptance must close first. |
| Drought mutates base terrain | Keep riverbed as base and water as runtime overlay. Movement reads `base + diff + water`, not rewritten base terrain. |
| Chunk seams break centerlines | Rasterizer uses chunk plus bounded halo and wrap-safe centerline sampling. |
| Side channels create dead ends | Every side channel must validate rejoin or valid lake/ocean outlet. |
| Ground banks do not form until water exists | Ground `47`-tile solve reads bed footprint, not water visibility. |
| Packet grows too much | Use byte arrays for flags/depth and omit optional fields unless required. |
| WorldPrePass leaks into interactive runtime | Keep substrate immutable and read only from native generation/preview worker paths. |

## Open Questions

- Final numeric width curve for ocean mouth, middle course, and headwater beds.
- Whether `worldgen_settings.foundation.river_amount` is enough for R1B, or
  whether R1B should introduce `worldgen_settings.rivers` immediately.
- Final terrain ids and presentation profile names for dry river/lake beds.
- Whether deep dry bed should remain fully walkable forever or later gain a
  local movement cost before water is implemented.
- Whether terminal lakes without ocean outlet should appear as dry lakebed scars
  only, or also receive future water in closed basins.

## Status Rationale

This spec is approved for staged implementation. R1B has landed the first
accepted native dry riverbed/lakebed realization path for `world_version = 14`.
The acceptance correction narrows river/lake radii to tile-scale dry beds and
adds a player-facing dry river/lake overlay to the world overview so accepted
ocean-directed trunks are visible during seed selection. For this version,
coarse flow routing treats the top-Y ocean band as the primary river sink
instead of allowing interior non-continent pockets to consume most trunks before
the ocean-directed acceptance filter runs. Pattern tuning inside the same
accepted boundary adds deterministic centerline bends between coarse nodes and
sparse inline basin lake scars on strong dry trunks, so the player-facing map
reads as cut river corridors with occasional lake bowls rather than straight
bands or featureless drainage.

The core architectural direction is constrained by approved docs:

- `WorldPrePass` is already the source of coarse river skeleton truth;
- actual riverbed tile rasterization was explicitly deferred to a future river
  spec;
- base terrain is immutable and not saved per untouched chunk;
- water/drought belongs above base generation as a runtime/environment layer;
- ground presentation already reserves water adjacency for future edge solving.

The next safe step after R1B is deeper R1C tuning diagnostics. R1D side-channel
islands and R2 water overlay remain out of scope until the dry shape acceptance
is closed.
