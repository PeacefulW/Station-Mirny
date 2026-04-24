---
title: River Generation V2
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 0.3
last_updated: 2026-04-24
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

# River Generation V2

## Purpose

Define the first canonical river layer that extends the current world runtime
and mountain generation without regressing chunk streaming, preview speed, or
main-thread discipline.

This spec is the source of truth for:
- canonical riverbed generation order relative to mountains
- the separation between riverbed geometry and water occupancy
- shallow-bed vs deep-bed rules
- dry riverbed preview before water is enabled
- channel routing constraints around mountains
- conflict resolution between rivers and existing terrain classes
- packet/runtime ownership for river data
- riverbed and water presentation contracts using river-aware 47-tile
  boundaries
- future shallow player-dug canal guardrails
- save/load ownership for river worldgen settings

## Gameplay Goal

The player must be able to:
- create a new world whose rivers feel guided by the existing mountain relief
  instead of being painted independently on top of it
- first preview dry riverbeds before water is enabled, so route placement,
  shallow shelves, and deep cuts can be reviewed and corrected visually
- visually read narrow channels as shallow riverbeds and wider channels as a
  riverbed with shallow shelves and a deep center
- see dry riverbeds remain visible during future drought states instead of
  disappearing with the water
- walk through shallow riverbed tiles whether they are dry or water-covered
- be blocked by deep riverbed tiles even when they are dry
- see rivers carve naturally through plains and mountain foot zones
- see rivers emerge from mountains through deterministic source mouths or
  waterfall mouths without destroying arbitrary mountain wall geometry
- preview river amount, width, and sinuosity without freezing the worldgen UI
- stream through the world with rivers enabled without introducing a new class
  of whole-world or per-frame runtime work

## Scope

V2 is an additive extension of the active `WorldCore.generate_chunk_packets_batch`
boundary and current mountain runtime. It adds:
- canonical riverbed routing after mountain field generation
- two canonical riverbed terrain classes:
  - `TERRAIN_RIVERBED_SHALLOW`
  - `TERRAIN_RIVERBED_DEEP`
- initial water occupancy as packet data layered on top of riverbed terrain,
  not as a replacement terrain id
- runtime packet fields for riverbed classification, water occupancy, and atlas
  metadata
- dry-first riverbed presentation using authored 47-tile low-bank and
  deep-cut shape families before any water surface is rendered
- river-aware terrain presentation for dry tiles adjacent to a riverbed or
  water-covered riverbed using the existing autotile-47 family pattern
- `worldgen_settings.rivers` in `world.json`
- deterministic source mouth / waterfall mouth markers on mountain boundaries
- native batch generation and cache reuse for river solves

## Out of Scope

V2 does not include:
- full fluid simulation
- erosion simulation
- dynamic water level simulation; drought and seasonal narrowing are future
  environment/runtime extensions that must reuse the riverbed/water split
- lakes, swamps, oceans, tides, rain runoff, or groundwater simulation
- arbitrary river tunneling through mountain walls
- aquifers or diggable underground water pockets
- bridges, boats, pumps, irrigation, fishing, or water power
- biome humidity gameplay, climate seasons, freezing, snowmelt, or weather
- build-mode special cases beyond canonical walkability
- player-made deep channels
- player-dug canals in V2-R1; future shovel canals may only create shallow
  canal/ditch diffs and must not recalculate canonical river routes
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
| Canonical, runtime overlay, or visual only? | Riverbed channel class, depth class, and source / waterfall mouth flags are canonical. Initial water occupancy is packet data layered on top of the riverbed. Future drought/narrowing belongs to environment/runtime overlay. Riverbed atlas and water atlas indices are derived presentation metadata. |
| Save/load required? | Yes, for `worldgen_settings.rivers` in `world.json`. No for temporary preview buffers, macro caches, riverbed atlas indices, or water atlas indices. Future player-dug shallow canals would be saved as runtime diff, not as rewritten base river topology. |
| Deterministic? | Yes. Base riverbed output is pure `f(seed, world_version, settings_packed, mountain field, chunk_coord)`. Initial V2 water occupancy is also deterministic and derived from that riverbed output. |
| Must work on unloaded chunks? | Yes. Riverbed topology is regenerated from seed/settings plus existing canonical mountain field. Initial water occupancy is regenerated from riverbed classification and settings. |
| C++ compute or main-thread apply? | Channel routing, riverbed rasterization, depth classification, initial water occupancy, and atlas selection are native compute. Main thread only applies chunk packet output to views. |
| Dirty unit | One aligned river macro region for routing/cache, one requested chunk batch for riverbed rasterization and packet output. No runtime riverbed dirty region exists in V2 because generated riverbeds are immutable base worldgen. Future water overlay changes must declare their own local tile-block/subchunk dirty unit. |
| Single owner | `WorldCore` owns canonical riverbed output and initial water occupancy. Future environment runtime owns drought/narrowing overlay state. `ChunkView` owns only presentation. `WorldDiffStore` does not own generated river topology, but future shallow shovel canals would live there as player diffs. `world.json` owns the river settings copy. |
| 10x / 100x scale path | Riverbed routing is solved on aligned macro cells with bounded halo and reused by cache. Initial water fill is a local classification pass over already-rasterized riverbed tiles. No whole-world pathfinding or fluid pass is introduced. |
| Main-thread blocking? | Forbidden. River solve stays in the existing worker path and publish remains sliced. |
| Hidden GDScript fallback? | Forbidden. Native river solve is required. |
| Could it become heavy later? | Yes. Width, sinuosity, source count, visual shape families, and future water overlay all scale route/publish complexity. V2 keeps this bounded by macro-grid routing, cached rasterization, dry-first validation, and no per-frame water simulation. |
| Whole-world prepass? | Forbidden. River generation must remain local to a bounded macro solve plus deterministic halo. |

## Core Contract

### Chunk Geometry and Wrap-World Contract

Unchanged from the active world runtime:
- one world tile = `32 px`
- one chunk = `32 x 32` tiles
- chunk-local cell coordinates are `0..31` on each axis
- world X wraps per ADR-0002
- world Y does not wrap

River routing rules for cylindrical topology:
- all guide-grid and tile-space coordinate math must canonicalize X through
  the same world-width modulo used by the active world runtime
- guide neighbors across the east/west seam are valid neighbors, not
  disconnected endpoints
- Y-neighbors outside the valid generated Y range are invalid; routing may
  terminate near a Y boundary but may not wrap north/south
- macro cache keys use canonical wrapped X macro coordinates and ordinary Y
  macro coordinates
- the same route sampled from either side of the X seam must produce identical
  `terrain_ids`, `river_flags`, `riverbed_atlas_indices`, and
  `water_atlas_indices`

### Worldgen Order

Canonical worldgen order for the active runtime becomes:
1. mountain field / mountain identity
2. river guide field and source selection
3. riverbed channel routing
4. per-tile riverbed rasterization and depth classification
5. initial water occupancy fill, disabled in the dry riverbed preview pass
6. terrain and presentation atlas selection

Decision:
- mountains are upstream data for rivers
- rivers are not allowed to redefine mountain identity
- river presentation must be derived after both mountain and river canonical
  classes are known
- the first implementation pass must stop at dry riverbed geometry before water
  surfaces are enabled

### Terrain Classes

V2 adds two riverbed terrain ids:

| Id constant | Walkable | Meaning |
|---|---|---|
| `TERRAIN_RIVERBED_SHALLOW` | 1 | Fordable shallow bed. Used for narrow channels, shallow shelves, and future shovel-made shallow canals. |
| `TERRAIN_RIVERBED_DEEP` | 0 | Non-fordable deep cut. Used only for natural generated river cores when channel width exceeds the shallow-only threshold. It remains blocked even when dry. |

V2 explicitly does **not** add a `TERRAIN_RIVER_BANK` class.
V2 also does **not** add separate water terrain ids.

Rule:
- the riverbed is the canonical terrain class
- water is occupancy on top of the riverbed, represented by packet flags and
  water atlas metadata
- drought or seasonal water loss must never delete or reshape the generated
  riverbed

Rule:
- dry terrain adjacent to a riverbed keeps its canonical underlying terrain
  class (`plains`, `mountain_foot`, `mountain_wall`, later biome terrain)
- river influence on those outside-channel dry tiles is presentation-only via
  river-aware atlas resolution

### Player-Dug Shallow Canal Guardrail

Future shovel support is intentionally limited:
- a shovel may create only a shallow canal/ditch runtime diff
- a shovel may not create `TERRAIN_RIVERBED_DEEP`
- a shovel may not recalculate, reroute, widen, or delete canonical generated
  riverbeds
- if a future water-connectivity pass allows shallow canals to fill from a
  river, that pass must be local and dirty-bounded; it is not permission to add
  full fluid simulation in the interactive path

This keeps the shovel fantasy compatible with performance: player digging marks
a small local diff, while generated river topology stays immutable.

### Shallow vs Deep Riverbed and Water Occupancy

Depth contract:
- if canonical local river width is `<= 4` tiles, every river tile in that local
  cross-section is shallow riverbed
- if canonical local river width is `>= 5` tiles, the outermost bank-adjacent
  band remains shallow riverbed and the interior channel becomes deep riverbed

MVP rule for wide rivers:
- width `<= 4` -> all channel tiles are shallow riverbed
- width `>= 5` -> exactly one tile of shallow riverbed on each side, center
  tiles become deep riverbed

This rule is intentionally simple and deterministic. If later art or gameplay
requires broader shallow shelves, the threshold and shelf thickness may be
versioned in a future spec revision.

Water occupancy contract:
- V2-R1A emits dry riverbeds only: `has_water = 0` and `water_atlas_indices = 0`
  for every tile
- V2-R1B enables deterministic static water occupancy on already-approved
  riverbeds
- water occupancy may cover shallow and deep riverbed tiles, but it must not
  change `terrain_ids` or `riverbed_atlas_indices`
- future drought may narrow or remove `has_water`, but the dry shallow/deep
  riverbed must remain visible
- shallow riverbed remains walkable dry or wet; deep riverbed remains blocked
  dry or wet

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
- a source mouth or waterfall mouth flag is placed on the first riverbed tile
  outside the mountain wall domain
- the adjacent mountain wall tile behind the flagged mouth remains
  `TERRAIN_MOUNTAIN_WALL` and keeps its `mountain_id`
- mouth presentation on the dry wall face is atlas / material presentation
  only; it must not convert the wall tile into river terrain
- source and waterfall mouth flags are mutually exclusive in V2-R1
- discoverable underground water systems inside dug mountains are deferred to a
  later aquifer/spring spec; they are not part of V2 river generation

This keeps mountain cover, identity, and excavation rules stable.

### Conflict Resolution

Canonical conflict resolution is:

| Existing state | River overlap result |
|---|---|
| Plains / future biome ground | Overwritten by shallow or deep riverbed if inside river channel. Otherwise preserved and may receive river-edge atlas presentation. |
| `mountain_foot` | Overwritten by shallow or deep riverbed if inside river channel. Otherwise preserved and may receive river-edge cliff/shore presentation. |
| `mountain_wall` | Preserved. Channel routing must avoid it. Source/waterfall mouth flags live on the adjacent external riverbed tile; adjacent dry wall may receive cliff-to-riverbed/water presentation. |
| Existing dry terrain next to riverbed or water | Underlying terrain wins canonically; river affects atlas/presentation only. |

Priority summary:
1. `RIVERBED_DEEP`
2. `RIVERBED_SHALLOW`
3. existing dry canonical terrain class
4. water occupancy overlay
5. derived river-edge presentation

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

V2-R1 routing constants:

| Constant | Value | Contract |
|---|---:|---|
| `river_macro_cell_size_tiles` | `1024` | Cache ownership unit for route solving. |
| `river_macro_halo_cells` | `1` | Each macro solve may read one macro cell of deterministic halo on every side. |
| `river_guide_cell_size_tiles` | `32` | One guide node spans one world chunk in tile units. |
| `max_source_attempts_per_macro` | `24` | Upper bound before source filtering. |
| `max_routes_per_macro` | `12` | Upper bound after deterministic source filtering. |
| `max_route_steps` | `160` guide nodes | Hard cap per routed channel. |

Source count rule:
- `amount == 0.0` must produce zero source attempts, zero river flags, and no
  riverbed terrain ids
- otherwise `source_attempts = clamp(round(amount * 24), 1, 24)` per macro
  interior before filtering
- source candidates are sorted by deterministic score, then by canonical
  wrapped world coordinate, before the `max_routes_per_macro` cap is applied

Route selection rules:
- route cost ties are resolved by fixed neighbor order after cost comparison:
  E, SE, S, SW, W, NW, N, NE after X wrapping is applied
- routing may use 8-neighbor guide movement, but tile rasterization must produce
  cardinally continuous riverbed coverage across chunk seams
- if a route enters a local minimum without a lower valid guide neighbor inside
  the macro + halo solve, it terminates as a dry-end sink in V2-R1; no lake is
  emitted
- if a route reaches the Y boundary, it may terminate; it may not wrap on Y
- if a route crosses the X seam, it continues through canonical wrapped X
  coordinates and must be identical when generated from either adjacent macro
  owner
- route output must not depend on the order in which chunks or batches are
  requested

#### 2. Channel rasterization

- routed guide paths are converted into tile-space centerlines
- centerlines are widened according to river width settings and local width
  variation rules
- final tile classification emits shallow/deep riverbed classes plus source-mouth
  flags
- initial water occupancy is a separate deterministic fill pass over the
  already-classified riverbed tiles; it must not influence route selection or
  riverbed depth classification

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
- the flagged mouth tile is the first riverbed tile outside the mountain wall
  domain; it is part of the riverbed channel and can be rendered with a special
  dry-mouth variant before water is enabled
- when static water occupancy is enabled, that same flagged mouth tile may also
  receive a special water atlas variant
- the wall behind the mouth remains mountain wall, with optional presentation
  detail only
- mouth walkability follows the emitted riverbed depth class: shallow mouth
  tiles are walkable, deep mouth tiles are blocked
- V2-R1 does not emit a dedicated non-walkable waterfall lip terrain id

This supports the visual fantasy of water coming out of a mountain while keeping
mountain topology simple.

### River-Edge Presentation

River-edge presentation uses the same general family as mountain edge solving:
- 47-tile adjacency resolution
- one low-bank shape family for ground-to-shallow-riverbed boundaries
- one deep-cut shape family for shallow-to-deep-riverbed boundaries
- one optional water-surface family for tiles with `has_water = 1`
- one family per outside dry terrain family that needs river-aware boundaries

Presentation rules:
- dry riverbed tiles resolve their atlas from riverbed adjacency even when there
  is no water
- water-covered tiles resolve water surface atlas from water adjacency, layered
  on top of the riverbed presentation
- dry tiles adjacent to riverbed or water resolve a river-aware atlas family
  instead of a separate `river_bank` terrain id
- mountain-adjacent river edges may look like lower cliff/shore ledges rather
  than full mountain-height walls
- deep dry riverbeds must visibly read as a lowered cut and remain
  non-walkable, not as ordinary dry ground

The art contract therefore becomes:
- no extra bank terrain class is required for MVP
- the dry channel look comes from authored atlas families, not from runtime
  numeric height reconstruction
- water can disappear later without deleting the channel silhouette
- the first reviewable milestone is a dry riverbed map, before water surfaces
  are enabled

### Packet Contract

`ChunkPacketV2` extends the current `ChunkPacketV1` boundary additively.
No V0 or V1 field is removed or reshaped.

V2 keeps all V1 fields:
- `chunk_coord`
- `world_seed`
- `world_version`
- `terrain_ids`
- `terrain_atlas_indices`
- `walkable_flags`
- `mountain_id_per_tile`
- `mountain_flags`
- `mountain_atlas_indices`

V2 additive fields:

| Field | Type | Length | Meaning |
|---|---|---|---|
| `river_flags` | `PackedByteArray` | 1024 | Riverbed and water occupancy bits documented below. |
| `riverbed_atlas_indices` | `PackedInt32Array` | 1024 | Atlas indices for dry riverbed/channel geometry. `0` when tile is not riverbed. |
| `water_atlas_indices` | `PackedInt32Array` | 1024 | Atlas indices for water surface presentation. `0` when tile has no water. |

`river_flags` bit layout:

| Bit | Name | Meaning |
|---|---|---|
| `1 << 0` | `is_riverbed` | Tile is canonical generated riverbed. |
| `1 << 1` | `is_deep_bed` | Tile is deep riverbed and must be non-walkable whether dry or wet. |
| `1 << 2` | `has_water` | Tile currently has deterministic V2 water occupancy. Always `0` in V2-R1A dry preview. |
| `1 << 3` | `is_source_mouth` | Tile is the first external riverbed tile of a source mouth. |
| `1 << 4` | `is_waterfall_mouth` | Tile is the first external riverbed tile of a waterfall mouth. |

Rules:
- `terrain_ids` carry the canonical riverbed terrain class, not a water class
- `walkable_flags` must already reflect shallow vs deep riverbed walkability
- `river_flags.is_riverbed` must agree with `terrain_ids`:
  - `TERRAIN_RIVERBED_SHALLOW` -> `is_riverbed = 1`, `is_deep_bed = 0`
  - `TERRAIN_RIVERBED_DEEP` -> `is_riverbed = 1`, `is_deep_bed = 1`
  - non-riverbed terrain -> `river_flags = 0`
- `has_water` may be set only when `is_riverbed = 1`
- `is_source_mouth` and `is_waterfall_mouth` are mutually exclusive
- mouth bits may be set when `is_riverbed = 1` even during dry preview where
  `has_water = 0`
- `riverbed_atlas_indices` and `water_atlas_indices` are derived presentation
  metadata and are not authoritative for gameplay, walkability, or save/load
- dry river-edge presentation outside the channel may continue to use
  `terrain_atlas_indices`
  because the underlying terrain class remains canonical owner for dry tiles
- no runtime-only bank/component data belongs in the packet
- no PNG paths, texture ids, material ids, or presentation resource paths belong
  in `ChunkPacketV2`
- V2-R1A dry preview packets must emit `water_atlas_indices = 0` for every tile
  while still emitting riverbed terrain, riverbed flags, and
  `riverbed_atlas_indices`
- V2-R1B water packets may set `has_water` and `water_atlas_indices`, but must
  not change `terrain_ids`, riverbed depth bits, mouth bits, or
  `riverbed_atlas_indices` for the same seed/settings/version

### Worldgen Settings

`worldgen_settings.rivers` is added to `world.json` and flattened into the
native batch boundary.

V2 minimal settings:

| Field | Range | V2 default | Meaning |
|---|---:|---:|---|
| `amount` | `0.0..1.0` | `0.35` | Controls source attempt density and total expected channel count. |
| `width` | `1.0..12.0` | `4.0` | Base width tendency before local widening/narrowing rules. |
| `sinuosity` | `0.0..1.0` | `0.45` | Controls how strongly channels meander while still obeying mountain constraints. |

Notes:
- existing UI labels for river amount and width may map directly to these
  settings
- lakes remain out of scope in V2 even if the UI later exposes a lake control
- settings are copied into the save on new world creation and never re-read from
  repository defaults for an existing world
- for `world_version <= 6`, river settings are ignored and effective
  `amount = 0.0`
- for `world_version >= 7`, a missing `worldgen_settings.rivers` section is a
  backward-compatibility path only and must be filled from hard-coded V2
  defaults in the loader, not from `data/balance/river_gen_settings.tres`

### `settings_packed` Layout

Rivers do not introduce a second native API. They extend the existing packed
settings payload after the confirmed mountain layout.

Required V2 layout:

| Index | Constant name | Meaning |
|---:|---|---|
| `0` | `SETTINGS_MOUNTAIN_DENSITY` | Existing mountain setting. |
| `1` | `SETTINGS_MOUNTAIN_SCALE` | Existing mountain setting. |
| `2` | `SETTINGS_MOUNTAIN_CONTINUITY` | Existing mountain setting. |
| `3` | `SETTINGS_MOUNTAIN_RUGGEDNESS` | Existing mountain setting. |
| `4` | `SETTINGS_MOUNTAIN_ANCHOR_CELL_SIZE` | Existing mountain compatibility setting. |
| `5` | `SETTINGS_MOUNTAIN_GRAVITY_RADIUS` | Existing mountain compatibility setting. |
| `6` | `SETTINGS_MOUNTAIN_FOOT_BAND` | Existing mountain setting. |
| `7` | `SETTINGS_MOUNTAIN_INTERIOR_MARGIN` | Existing mountain setting. |
| `8` | `SETTINGS_MOUNTAIN_LATITUDE_INFLUENCE` | Existing mountain setting. |
| `9` | `SETTINGS_RIVER_AMOUNT` | `worldgen_settings.rivers.amount`. |
| `10` | `SETTINGS_RIVER_WIDTH` | `worldgen_settings.rivers.width`. |
| `11` | `SETTINGS_RIVER_SINUOSITY` | `worldgen_settings.rivers.sinuosity`. |

Rules:
- the active V2 native path requires at least `12` packed values
- all river values are read once per batch, not per tile
- missing river indices for legacy `world_version <= 6` must behave exactly as
  `amount = 0.0`, `width = 4.0`, `sinuosity = 0.45`
- missing river indices for `world_version >= 7` are invalid after load
  migration and must fail loudly rather than silently sampling repository
  defaults

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
- one batch returns one `ChunkPacketV2` per input coord, in input order
- the active river runtime requires `world_version >= 7`
- the active river runtime requires the full V2 `settings_packed` layout after
  save/load migration
- all heavy river work stays in C++
- main thread only applies chunk packet output

### River Macro Solve and Cache

V2 river generation must mirror the lessons learned from mountain identity:
- aligned `1024 x 1024` macro solve
- deterministic `1`-macro halo
- cache keyed by seed + world_version + relevant river settings + canonical
  wrapped macro coord
- batch grouping by macro owner when possible

Required properties:
- no per-chunk full recompute of long river routes when the same macro solve can
  be reused
- no whole-world river path cache
- no dependence on generation order of neighboring chunks
- cache entries may be evicted by normal native memory policy; eviction must
  change performance only, not output
- preview and live generation may share the same deterministic solver, but
  preview cache state must not become an authoritative runtime input
- preview requests may be cancelled or superseded without affecting live-world
  generation output

### Script Ownership

| Role | Owner | Responsibility |
|---|---|---|
| Canonical mountain + riverbed output | `WorldCore` | Emits terrain ids, walkability, riverbed flags, initial water occupancy, riverbed atlas indices, and water atlas indices. |
| Chunk orchestration | `WorldStreamer` / packet backend | Requests packets in batches exactly as for mountains. |
| Presentation | `ChunkView` / terrain presentation registry | Applies dry riverbed geometry, optional water surfaces, and river-aware edge atlases. |
| Save/load | save collectors / appliers | Persist only `worldgen_settings.rivers` and regular world diffs. |
| Future drought/narrowing overlay | Environment runtime, not V2-R1 | May alter water occupancy later, but must not own or mutate base riverbed topology. |

No new runtime flood-fill or continuous river simulation system is introduced.

## Persistence Contract

### world.json Extension

`world.json` grows additively:

```json
{
  "world_seed": 131071,
  "world_version": 7,
  "worldgen_settings": {
    "mountains": {
      "density": 0.3,
      "scale": 512.0,
      "continuity": 0.65,
      "ruggedness": 0.55,
      "anchor_cell_size": 128,
      "gravity_radius": 96,
      "foot_band": 0.08,
      "interior_margin": 1,
      "latitude_influence": 0.0
    },
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
- loading a `world_version <= 6` save must preserve the no-river output path,
  regardless of repository river defaults
- loading a `world_version >= 7` save without `worldgen_settings.rivers` must
  use hard-coded V2 defaults in the loader, not live repository resources
- `worldgen_signature`, if present, remains diagnostic only and is not used as
  an authority for river settings
- river topology itself is not persisted; it is regenerated canonically

### Chunk Diffs

Chunk diffs remain unchanged in shape.

River topology is immutable base worldgen. Runtime digging or building does not
rewrite canonical river channels in V2.

Future shovel-made shallow canals, if implemented, must be stored as runtime
diff tiles on top of the immutable base. They may connect visually or
hydrologically to generated rivers only through a future local, dirty-bounded
water-connectivity spec.

### WORLD_VERSION

When V2 river code lands, `WORLD_VERSION` must bump because canonical terrain
output changes for the same `seed + coord`.

Expected direction:
- current active mountain runtime is `world_version >= 6`
- first river-enabled runtime should become `world_version >= 7`
- `world_version` remains a plain integer algorithm boundary; it is not a hash
  of river settings

## Performance Class

| Operation | Class | Dirty unit | Budget |
|---|---|---|---|
| Riverbed guide solve | background native worker | aligned `1024 x 1024` macro region with `1`-macro halo | outside main thread |
| Riverbed rasterization | background native worker | requested chunk batch | outside main thread |
| Dry riverbed atlas selection | background native worker | requested chunk batch | outside main thread |
| Initial water occupancy and water atlas selection | background native worker | requested chunk batch | outside main thread; disabled in V2-R1A dry preview |
| Packet publish | main-thread sliced apply | existing chunk publish batches | shares current streaming budget |
| Dry riverbed preview regeneration | background native worker | requested preview batch | no synchronous UI wait; superseded preview requests may be discarded |

Forbidden runtime paths:
- full-world river solve on new game confirmation
- per-frame river update logic
- main-thread river routing
- recomputing riverbed geometry because water dries up or returns
- using water occupancy changes to rewrite canonical `terrain_ids`
- chunk-local brute-force pathfinding that ignores macro cache reuse
- bank generation as a second pass that rescans all loaded chunks on movement
- synchronous waiting for preview generation from the UI thread
- rebuilding all loaded chunks because one preview slider changed
- discovering or validating river terrain resources during visible chunk publish

Performance verification targets for implementation:
- no river routing, rasterization, or atlas solve runs on the main thread
- V2-R1A dry riverbed preview must pass visual and performance acceptance before
  V2-R1B water occupancy is enabled
- V2-R1B water occupancy must not change riverbed terrain ids or riverbed atlas
  output compared with V2-R1A for the same seed/settings/version
- normal exploration with rivers enabled must not add a new hitch class where a
  single frame exceeds `22 ms`
- preview slider interaction must not block input frames; a superseded preview
  may be cancelled rather than completed
- `amount = 0.0` must take the no-river path and preserve the current mountain
  runtime output except for version metadata
- repeated chunk batches within the same macro owner must show macro-cache reuse
  in debug counters or equivalent test instrumentation

## Acceptance Criteria

### Generation

- [ ] mountains are generated before rivers and rivers visibly respond to the
      mountain relief
- [ ] V2-R1A emits visible dry riverbeds with no water occupancy
- [ ] narrow rivers (`<= 4` tiles) are fully shallow riverbed
- [ ] wider rivers (`>= 5` tiles) produce shallow riverbed shelves and a deep
      riverbed center
- [ ] river output is deterministic for the same seed, version, and settings
- [ ] channels remain continuous across chunk seams
- [ ] channels remain continuous across the X wrap seam and never wrap on Y
- [ ] batch order does not affect `terrain_ids`, `river_flags`, or
      `riverbed_atlas_indices`
- [ ] V2-R1B water occupancy does not change riverbed `terrain_ids`,
      riverbed depth bits, mouth bits, or `riverbed_atlas_indices`
- [ ] `worldgen_settings.rivers.amount = 0.0` produces no riverbed terrain,
      no river flags, no riverbed atlas indices, and no water atlas indices

### Mountain Interaction

- [ ] rivers can pass through mountain foot zones
- [ ] rivers do not arbitrarily carve through mountain wall tiles
- [ ] mountain-origin rivers appear through deterministic source/waterfall mouths
      on mountain boundaries
- [ ] source/waterfall mouth flags are emitted on external riverbed tiles, while
      the adjacent mountain wall tile remains canonical mountain geometry
- [ ] mountain cover and mountain identity behavior do not regress when rivers
      are enabled

### Gameplay

- [ ] shallow riverbed is traversable whether dry or water-covered
- [ ] deep riverbed is not traversable whether dry or water-covered
- [ ] dry drought-state riverbeds remain visible as channel geometry instead of
      reverting to ordinary ground
- [ ] dry terrain adjacent to riverbeds keeps its canonical terrain class
- [ ] low ground-to-shallow-riverbed edges read correctly using authored
      47-tile sets
- [ ] shallow-to-deep-riverbed transitions read correctly using authored
      47-tile sets
- [ ] water surfaces, when enabled, layer on top of riverbed presentation without
      hiding the dry-bed shape contract

### Performance

- [ ] enabling rivers does not introduce main-thread worldgen work
- [ ] dry riverbed preview does not synchronously block the UI thread
- [ ] preview requests do not synchronously block the UI thread; superseded
      preview requests may be cancelled
- [ ] normal exploration with rivers enabled does not introduce a new frame
      over `22 ms` attributable to river generation, publish, or presentation
- [ ] batch generation and macro-cache reuse remain active with rivers enabled
- [ ] repeated chunk batches in the same river macro region reuse cached macro
      solves or emit equivalent debug proof

### Persistence and Governance

- [ ] new river worlds write `worldgen_settings.rivers` into `world.json`
      exactly once
- [ ] loading `world_version <= 6` saves preserves no-river output
- [ ] loading `world_version >= 7` saves with missing river settings uses
      hard-coded V2 defaults, not repository `.tres` resources
- [ ] `WORLD_VERSION` bump is included in the same implementation task
- [ ] `ChunkPacketV2` and `worldgen_settings.rivers` are added to the relevant
      meta docs when code lands

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

## Files That Must Not Be Touched When Code Lands

- `BuildingSystem`, `PowerSystem`, `IndoorSolver`, and room / power topology
  systems
- combat, fauna, progression, inventory, crafting, lore, and unrelated UI
  systems
- `z != 0` subsurface runtime, underground fog, cave/cellar generation, and
  connector systems
- environment runtime systems for weather, season, wind, temperature, spores,
  snow, ice, or dynamic water
- chunk diff file shape outside the existing tile override contract
- any deleted legacy world runtime files from the pre-rebuild stack
- biome registries, flora/decor batching, POI placement, resource streaming,
  and climate systems unless a separate approved spec amendment explicitly
  includes them
- `docs/02_system_specs/meta/*` before code confirms final names and payloads;
  those docs are updated in the same task that lands the implementation

## Required Canonical Doc Follow-Ups When Code Lands

When V2 code lands, update in the same task:
- `docs/02_system_specs/meta/packet_schemas.md` with `ChunkPacketV2`,
  `river_flags`, `riverbed_atlas_indices`, and `water_atlas_indices`
- `docs/02_system_specs/meta/save_and_persistence.md` with
  `worldgen_settings.rivers`, versioned defaults, and the no-river path for
  `world_version <= 6`
- `docs/02_system_specs/meta/system_api.md` if new public surfaces appear
  (for example a new `RiverGenSettings` new-game entrypoint or river debug
  read surface)
- `docs/02_system_specs/meta/event_contracts.md` only if new river-specific
  public events are introduced
- `docs/02_system_specs/meta/commands.md` only if a new command or mutation
  path is introduced
- `docs/02_system_specs/world/world_runtime.md` if the active runtime scope
  statement changes materially

`not required` entries must be accompanied by grep evidence against the
relevant doc at the time of landing.

## Risks

- over-designing rivers into a hydrology simulator instead of a performant world
  layer
- collapsing riverbed and water into the same terrain id, which would make
  drought erase the visible channel and make future water changes more
  expensive
- allowing rivers to arbitrarily overwrite mountain walls and thereby breaking
  mountain cover assumptions
- introducing a `river_bank` terrain explosion that complicates every future
  biome/terrain interaction
- allowing shovel canals to become a general-purpose deep excavation or river
  rerouting system without a separate bounded-runtime spec
- letting preview call patterns defeat macro-cache reuse
- choosing macro constants that are visually too sparse or too dense; mitigated
  by keeping constants versioned and acceptance tests deterministic
- failing to test the X-wrap seam; mitigated by explicit seam continuity
  acceptance criteria

## Deferred Questions

These questions are intentionally deferred and are not blockers for V2-R1:

- very wide rivers may later widen their shallow shelf beyond one tile per side
- mountain source mouths may later support a dedicated non-walkable waterfall
  lip tile
- lakes may become their own V2.5 spec or wait for a broader water bodies pass
- drought, seasonal narrowing, or full drying may later alter only water
  occupancy and water presentation while preserving riverbed terrain
- shovel-made shallow canals may later fill from nearby river water through a
  local connectivity/water-occupancy pass, but they may not create deep
  riverbeds or reroute generated rivers
- dams and water power require a separate spec for local head/flow/power
  abstraction; they are not unlocked by V2-R1 dry riverbeds alone

Any of the above requires a future spec amendment and `WORLD_VERSION` review if
canonical terrain output changes.

## Implementation Iteration

### V2-R1A - Dry riverbed geometry preview

Goal:
- add deterministic dry riverbeds that visually belong to the current relief
  without regressing mountain performance or chunk streaming

Minimal ship target:
- amount/width/sinuosity settings
- shallow + deep riverbed terrain
- source/waterfall mouths on mountain boundaries
- no bank terrain class
- native batch generation + cache reuse
- riverbed-aware 47-tile boundary presentation
- `has_water = 0` and `water_atlas_indices = 0` for every emitted packet

Human review gate:
- designers must be able to inspect river route placement, shallow shelves,
  deep cuts, and dry mouth presentation before any water surface is enabled
- performance proof for dry riverbed generation/publish must pass before
  V2-R1B starts

Acceptance tests for V2-R1A:
- [ ] deterministic regeneration of the same chunks with fixed seed, version,
      and river settings
- [ ] `amount = 0.0` preserves the no-river output path
- [ ] X-wrap seam riverbed continuity is proven with a seam-straddling batch
- [ ] source/waterfall mouth flags stay on external riverbed tiles and do not
      rewrite mountain wall tiles
- [ ] dry riverbeds visibly show low ground-to-shallow edges and deeper
      shallow-to-deep cuts
- [ ] deep dry riverbed is non-walkable
- [ ] no riverbed solve runs on the main thread and no hidden GDScript fallback
      exists

### V2-R1B - Static water occupancy on approved riverbeds

Goal:
- enable water presentation only after dry riverbed geometry is approved

What explicitly does not ship in R1:
- lakes
- aquifers
- erosion
- dynamic water simulation
- runtime channel mutation
- drought runtime
- shovel canals
- dams or water power

Acceptance tests for V2-R1B:
- [ ] water occupancy sets `has_water` only on existing riverbed tiles
- [ ] water presentation uses `water_atlas_indices` without changing
      `terrain_ids`, riverbed depth bits, mouth bits, or
      `riverbed_atlas_indices`
- [ ] shallow water-covered riverbed remains walkable
- [ ] deep water-covered riverbed remains non-walkable
- [ ] `ChunkPacketV2` fields are additive and meta docs are updated when code
      lands
- [ ] no water occupancy or atlas solve runs on the main thread and no hidden
      GDScript fallback exists

## Status Rationale

This spec is approved because:
- all 12 Law 0 questions are answered with explicit ownership, dirty units, and
  scale path
- the packet extension is defined as additive `ChunkPacketV2` over
  `ChunkPacketV1`
- riverbed geometry is now explicitly separated from water occupancy
- the first implementation pass is dry riverbed preview, which isolates route,
  depth, edge art, and publish cost before any water surface is introduced
- the `settings_packed` layout, defaults, and legacy no-river path are explicit
- route solving has bounded macro ownership, halo, source caps, tie-breakers,
  and batch-order invariance requirements
- wrap-world behavior is explicitly governed by ADR-0002
- source / waterfall mouth semantics preserve mountain wall identity
- performance acceptance criteria are measurable rather than subjective
- implementation scope now includes both allowed and forbidden files

Changes to the rules above require a new version of this document with
`last_updated` bumped and a short amendment note in the task closure report.
