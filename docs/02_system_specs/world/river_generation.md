---
title: River Generation V2
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-04-23
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - world_runtime.md
  - mountain_generation.md
  - terrain_hybrid_presentation.md
---

# River Generation V2

## Purpose

Define the first canonical river layer that extends the current world runtime
and mountain generation without regressing chunk streaming, preview speed, or
main-thread discipline.

This spec is the source of truth for:
- canonical river channel generation order relative to mountains
- shallow-water vs deep-water rules
- channel routing constraints around mountains
- conflict resolution between rivers and existing terrain classes
- packet/runtime ownership for river data
- river-edge presentation contract using river-aware 47-tile boundaries
- save/load ownership for river worldgen settings

## Gameplay Goal

The player must be able to:
- create a new world whose rivers feel guided by the existing mountain relief
  instead of being painted independently on top of it
- visually read narrow rivers as fordable shallow water and wider rivers as a
  channel with shallow banks and a deep center
- walk through shallow river tiles
- be blocked by deep-water tiles
- see rivers carve naturally through plains and mountain foot zones
- see rivers emerge from mountains through deterministic source mouths or
  waterfall mouths without destroying arbitrary mountain wall geometry
- preview river amount, width, and sinuosity without freezing the worldgen UI
- stream through the world with rivers enabled without introducing a new class
  of whole-world or per-frame runtime work

## Scope

V2 is an additive extension of the active `WorldCore.generate_chunk_packets_batch`
boundary and current mountain runtime. It adds:
- canonical river routing after mountain field generation
- two canonical river terrain classes:
  - `TERRAIN_RIVER_SHALLOW_WATER`
  - `TERRAIN_RIVER_DEEP_WATER`
- runtime packet fields for river classification and atlas metadata
- river-aware terrain presentation for dry tiles adjacent to water using the
  existing autotile-47 family pattern
- `worldgen_settings.rivers` in `world.json`
- deterministic source mouth / waterfall mouth markers on mountain boundaries
- native batch generation and cache reuse for river solves

## Out of Scope

V2 does not include:
- full fluid simulation
- erosion simulation
- dynamic water level changes
- lakes, swamps, oceans, tides, rain runoff, or groundwater simulation
- arbitrary river tunneling through mountain walls
- aquifers or diggable underground water pockets
- bridges, boats, pumps, irrigation, fishing, or water power
- biome humidity gameplay, climate seasons, freezing, snowmelt, or weather
- build-mode special cases beyond canonical walkability
- runtime recomputation of river topology after digging terrain

## Dependencies

- `world_runtime.md` for batch packet generation and chunk ownership
- `mountain_generation.md` for canonical mountain field, mountain identity,
  and the current presentation boundary
- ADR-0001 for runtime work and dirty-update discipline
- ADR-0002 for wrap-safe X behavior
- ADR-0003 for immutable base + runtime diff ownership
- ADR-0006 for surface vs subsurface boundaries
- ADR-0007 for keeping worldgen distinct from environment runtime

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical, runtime overlay, or visual only? | River channel class, depth class, source mouth flags, and water atlas indices are canonical. Dry river-edge cliff/shore rendering is derived presentation. |
| Save/load required? | Yes, for `worldgen_settings.rivers` in `world.json`. No for temporary preview buffers or cache entries. |
| Deterministic? | Yes. River output is pure `f(seed, world_version, worldgen_settings, mountain field, coord)`. |
| Must work on unloaded chunks? | Yes. River topology is regenerated from seed/settings plus existing canonical mountain field. |
| C++ compute or main-thread apply? | Channel routing, rasterization, depth classification, and atlas selection are native compute. Main thread only applies chunk packet output to views. |
| Dirty unit | One native batch request containing one or more chunks. No runtime river dirty region exists in V2 because rivers are immutable base worldgen. |
| Single owner | `WorldCore` owns canonical river output. `ChunkView` owns only presentation. `WorldDiffStore` does not own river topology. `world.json` owns the river settings copy. |
| 10x / 100x scale path | River routing is solved on aligned macro cells with bounded halo and reused by cache. No whole-world pathfinding pass is introduced. |
| Main-thread blocking? | Forbidden. River solve stays in the existing worker path and publish remains sliced. |
| Hidden GDScript fallback? | Forbidden. Native river solve is required. |
| Could it become heavy later? | Yes. Width, sinuosity, and source count scale route complexity. V2 keeps this bounded by macro-grid routing and cached rasterization. |
| Whole-world prepass? | Forbidden. River generation must remain local to a bounded macro solve plus deterministic halo. |

## Core Contract

### Worldgen Order

Canonical worldgen order for the active runtime becomes:
1. mountain field / mountain identity
2. river guide field and source selection
3. river channel routing
4. per-tile river rasterization and depth classification
5. terrain and presentation atlas selection

Decision:
- mountains are upstream data for rivers
- rivers are not allowed to redefine mountain identity
- river presentation must be derived after both mountain and river canonical
  classes are known

### Terrain Classes

V2 adds two water terrain ids:

| Id constant | Walkable | Meaning |
|---|---|---|
| `TERRAIN_RIVER_SHALLOW_WATER` | 1 | Fordable water. Used for narrow channels and edge bands of wide channels. |
| `TERRAIN_RIVER_DEEP_WATER` | 0 | Non-fordable channel core. Used only when channel width exceeds the shallow-only threshold. |

V2 explicitly does **not** add a `TERRAIN_RIVER_BANK` class.

Rule:
- dry terrain adjacent to river water keeps its canonical underlying terrain
  class (`plains`, `mountain_foot`, `mountain_wall`, later biome terrain)
- river influence on those dry tiles is presentation-only via river-aware atlas
  resolution

### Shallow vs Deep Water

Depth contract:
- if canonical local river width is `<= 4` tiles, every river tile in that local
  cross-section is shallow water
- if canonical local river width is `>= 5` tiles, the outermost bank-adjacent
  band remains shallow and the interior channel becomes deep water

MVP rule for wide rivers:
- width `<= 4` -> all water tiles are shallow
- width `>= 5` -> exactly one tile of shallow water on each side, center tiles
  become deep water

This rule is intentionally simple and deterministic. If later art or gameplay
requires broader shallow shelves, the threshold and shelf thickness may be
versioned in a future spec revision.

### Mountain Interaction Rules

#### Rivers and mountain foot

Rivers **may** cut through `mountain_foot`.

Reason:
- this is required for believable valleys between ranges
- it keeps channels from looking artificially detached from relief
- it avoids introducing a fake “no-river buffer” around mountains

#### Rivers and mountain wall

Rivers do **not** arbitrarily overwrite `mountain_wall` tiles.

Instead, active river channels may touch mountain walls only through deterministic
special boundary nodes:
- `source_mouth`
- `waterfall_mouth`

Rules:
- a normal routed river channel must avoid arbitrary wall penetration
- a source mouth or waterfall mouth is placed on the external boundary of the
  mountain cover domain, not by turning a large arbitrary wall segment into a
  river tunnel
- the mountain wall mass behind the mouth remains canonical mountain geometry
- discoverable underground water systems inside dug mountains are deferred to a
  later aquifer/spring spec; they are not part of V2 river generation

This keeps mountain cover, identity, and excavation rules stable.

### Conflict Resolution

Canonical conflict resolution is:

| Existing state | River overlap result |
|---|---|
| Plains / future biome ground | Overwritten by shallow or deep water if inside river channel. Otherwise preserved and may receive river-edge atlas presentation. |
| `mountain_foot` | Overwritten by shallow or deep water if inside river channel. Otherwise preserved and may receive river-edge cliff/shore presentation. |
| `mountain_wall` | Preserved. Channel routing must avoid it except at deterministic source/waterfall mouths. Adjacent dry wall may receive cliff-to-water presentation. |
| Existing dry terrain next to water | Underlying terrain wins canonically; river affects atlas/presentation only. |

Priority summary:
1. `RIVER_DEEP_WATER`
2. `RIVER_SHALLOW_WATER`
3. existing dry canonical terrain class
4. derived river-edge presentation

### River Guide Field and Routing

Rivers must not be generated by naive per-tile random painting.

V2 uses a two-stage native solve:

#### 1. Macro guide grid

- world space is divided into aligned guide cells
- each guide cell samples a deterministic river guide score derived from:
  - mountain/height field
  - downhill preference
  - valley preference
  - meander noise
  - wall-avoidance penalty
- routing on this guide grid is canonical and deterministic

#### 2. Channel rasterization

- routed guide paths are converted into tile-space centerlines
- centerlines are widened according to river width settings and local width
  variation rules
- final tile classification emits shallow/deep water classes plus source-mouth
  flags

Forbidden in V2:
- runtime tile-by-tile fluid spread
- full-world hydrology solve
- pathfinding that scans arbitrary already-generated chunks at runtime

### Width and Sinuosity

River width is driven by a deterministic width profile:
- user settings define base width tendency
- route order / downstream distance may widen channels within bounded rules
- local width jitter is allowed, but must remain deterministic and bounded

River sinuosity is driven by route perturbation on the guide grid:
- low sinuosity -> straighter channels
- high sinuosity -> wider lateral meanders
- sinuosity may not cause arbitrary wall tunneling; mountain wall avoidance
  still wins except at source/waterfall mouths

### Source Mouths and Waterfalls

V2 source contract:
- source candidates are biased toward high-elevation and mountain-adjacent guide
  cells
- if a river starts from a mountain, the visible origin is a deterministic
  external `source_mouth` or `waterfall_mouth`
- the mouth itself is part of the river water channel and can be rendered with a
  special atlas variant
- the wall behind the mouth remains mountain wall

This supports the visual fantasy of water coming out of a mountain while keeping
mountain topology simple.

### River-Edge Presentation

River-edge presentation uses the same general family as mountain edge solving:
- 47-tile adjacency resolution
- one family for water tiles
- one family per dry terrain family that needs river-aware boundaries

Presentation rules:
- water tiles resolve their atlas from water adjacency
- dry tiles adjacent to water resolve a river-aware atlas family instead of a
  separate `river_bank` terrain id
- mountain-adjacent river edges may look like lower cliff/shore ledges rather
  than full mountain-height walls

The art contract therefore becomes:
- no extra bank terrain class is required for MVP
- the river look comes from atlas families, not from exploding the canonical
  terrain taxonomy

### Packet Contract

V2 extends the active packet boundary additively. Proposed additive fields:

| Field | Type | Length | Meaning |
|---|---|---|---|
| `river_flags` | `PackedByteArray` | 1024 | Bit 0 `is_water`, bit 1 `is_deep`, bit 2 `is_source_mouth`, bit 3 `is_waterfall_mouth`. |
| `river_atlas_indices` | `PackedInt32Array` | 1024 | Atlas indices for water tiles. `0` when tile is not water. |

Rules:
- `terrain_ids` still carry the canonical water terrain class
- `walkable_flags` must already reflect shallow vs deep walkability
- dry river-edge presentation may continue to use `terrain_atlas_indices`
  because the underlying terrain class remains canonical owner for dry tiles
- no runtime-only bank/component data belongs in the packet

### Worldgen Settings

`worldgen_settings.rivers` is added to `world.json` and flattened into the
native batch boundary.

V2 minimal settings:

| Field | Range | Meaning |
|---|---|---|
| `amount` | `0.0..1.0` | Controls source attempt density and total expected channel count. |
| `width` | `1.0..12.0` | Base width tendency before local widening/narrowing rules. |
| `sinuosity` | `0.0..1.0` | Controls how strongly channels meander while still obeying mountain constraints. |

Notes:
- existing UI labels for river amount and width may map directly to these
  settings
- lakes remain out of scope in V2 even if the UI later exposes a lake control
- settings are copied into the save on new world creation and never re-read from
  repository defaults for an existing world

## Runtime Architecture

### Native Boundary

Rivers use the same active native boundary as mountains:

```text
WorldCore.generate_chunk_packets_batch(
    seed: int,
    coords: PackedVector2Array,
    world_version: int,
    settings_packed: PackedFloat32Array
) -> Array
```

Rules:
- rivers do not introduce a second native worldgen API
- the river solve is batched together with mountains and other canonical worldgen
  layers for the requested chunk batch
- all heavy river work stays in C++
- main thread only applies chunk packet output

### River Macro Solve and Cache

V2 river generation must mirror the lessons learned from mountain identity:
- aligned macro solve
- deterministic halo
- cache keyed by seed + world_version + relevant settings + macro coord
- batch grouping by macro owner when possible

Required properties:
- no per-chunk full recompute of long river routes when the same macro solve can
  be reused
- no whole-world river path cache
- no dependence on generation order of neighboring chunks

### Script Ownership

| Role | Owner | Responsibility |
|---|---|---|
| Canonical mountain + river output | `WorldCore` | Emits terrain ids, walkability, river flags, and water atlas indices. |
| Chunk orchestration | `WorldStreamer` / packet backend | Requests packets in batches exactly as for mountains. |
| Presentation | `ChunkView` / terrain presentation registry | Applies water tiles and river-aware edge atlases. |
| Save/load | save collectors / appliers | Persist only `worldgen_settings.rivers` and regular world diffs. |

No new runtime flood-fill or continuous river simulation system is introduced.

## Persistence Contract

### world.json Extension

`world.json` grows additively:

```json
{
  "world_version": 7,
  "worldgen_settings": {
    "mountains": { ... },
    "rivers": {
      "amount": 0.35,
      "width": 4.0,
      "sinuosity": 0.45
    }
  }
}
```

Rules:
- exact values are copied once on new world creation
- loading an older save without `worldgen_settings.rivers` must use versioned
  hard-coded defaults in the loader, not live repository resources
- river topology itself is not persisted; it is regenerated canonically

### Chunk Diffs

Chunk diffs remain unchanged in shape.

River topology is immutable base worldgen. Runtime digging or building does not
rewrite canonical river channels in V2.

### WORLD_VERSION

When V2 river code lands, `WORLD_VERSION` must bump because canonical terrain
output changes for the same `seed + coord`.

Expected direction:
- current active mountain runtime is `world_version >= 6`
- first river-enabled runtime should become `world_version >= 7`

## Performance Class

| Operation | Class | Dirty unit | Budget |
|---|---|---|---|
| River guide solve | background native worker | aligned macro region with bounded halo | outside main thread |
| Channel rasterization | background native worker | requested chunk batch | outside main thread |
| Water / edge atlas selection | background native worker | requested chunk batch | outside main thread |
| Packet publish | main-thread sliced apply | existing chunk publish batches | shares current streaming budget |
| Preview regeneration | background native worker | requested preview batch | must remain responsive under current preview UX expectations |

Forbidden runtime paths:
- full-world river solve on new game confirmation
- per-frame river update logic
- main-thread river routing
- chunk-local brute-force pathfinding that ignores macro cache reuse
- bank generation as a second pass that rescans all loaded chunks on movement

## Acceptance Criteria

### Generation

- [ ] mountains are generated before rivers and rivers visibly respond to the
      mountain relief
- [ ] narrow rivers (`<= 4` tiles) are fully shallow
- [ ] wider rivers (`>= 5` tiles) produce shallow edges and a deep center
- [ ] river output is deterministic for the same seed, version, and settings
- [ ] channels remain continuous across chunk seams

### Mountain Interaction

- [ ] rivers can pass through mountain foot zones
- [ ] rivers do not arbitrarily carve through mountain wall tiles
- [ ] mountain-origin rivers appear through deterministic source/waterfall mouths
      on mountain boundaries
- [ ] mountain cover and mountain identity behavior do not regress when rivers
      are enabled

### Gameplay

- [ ] shallow water is traversable
- [ ] deep water is not traversable
- [ ] dry terrain adjacent to rivers keeps its canonical terrain class
- [ ] river-edge presentation reads correctly using the authored 47-tile sets

### Performance

- [ ] enabling rivers does not introduce main-thread worldgen work
- [ ] preview remains responsive at normal settings
- [ ] normal exploration with rivers enabled does not regress current chunk
      streaming behavior noticeably
- [ ] batch generation and cache reuse remain active with rivers enabled

## Files That May Be Touched When Code Lands

### New
- `core/resources/river_gen_settings.gd`
- `data/balance/river_gen_settings.tres`
- `gdextension/src/river_field.h`
- `gdextension/src/river_field.cpp`

### Modified
- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/world_streamer.gd`
- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- save/load files that already own `worldgen_settings`
- new-game UI files that expose river controls

## Required Canonical Doc Follow-Ups When Code Lands

When V2 code lands, update in the same task:
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/02_system_specs/meta/system_api.md` if new public surfaces appear
- `docs/02_system_specs/meta/event_contracts.md` only if new river-specific
  public events are introduced
- `docs/02_system_specs/world/world_runtime.md` if the active runtime scope
  statement changes materially

## Risks

- over-designing rivers into a hydrology simulator instead of a performant world
  layer
- allowing rivers to arbitrarily overwrite mountain walls and thereby breaking
  mountain cover assumptions
- introducing a `river_bank` terrain explosion that complicates every future
  biome/terrain interaction
- letting preview call patterns defeat macro-cache reuse

## Open Questions

- should very wide rivers later widen their shallow shelf beyond one tile per
  side?
- should mountain source mouths support a dedicated non-walkable waterfall lip
  tile in a later version, or remain presentation-only?
- should lakes be their own V2.5 spec or wait for a broader water bodies pass?

## Implementation Iteration

### V2-R1 - Canonical rivers on top of mountains

Goal:
- add deterministic river channels that visually belong to the current relief
  without regressing mountain performance or chunk streaming

Minimal ship target:
- amount/width/sinuosity settings
- shallow + deep water
- source/waterfall mouths on mountain boundaries
- no bank terrain class
- native batch generation + cache reuse
- river-aware 47-tile boundary presentation

What explicitly does not ship in R1:
- lakes
- aquifers
- erosion
- dynamic water simulation
- runtime channel mutation
