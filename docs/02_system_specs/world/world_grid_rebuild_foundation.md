---
title: World Grid Rebuild Foundation
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 2.0
last_updated: 2026-05-05
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../meta/save_and_persistence.md
  - world_runtime.md
---

# World Grid Rebuild Foundation

## Purpose

Re-establish one canonical world-grid contract for the post-deletion rebuild of the
world runtime.

## Gameplay Goal

The rebuilt world must read cleanly at a larger tile size, keep building/world
alignment exact, and use smaller chunks so streaming, rendering, and persistence
operate on tighter local units.

## Core statement

The rebuild contract is:
- one world tile = `64 px`
- one chunk = `16 x 16` tiles

World-facing systems must derive tile/world conversion, building alignment,
visibility radii, chunk addressing, and save sharding from this contract instead of
carrying legacy `32 px`, `64 x 64`, or `12 px` assumptions.

The `16 x 16` chunk footprint is intentional: at `64 px` tiles it preserves the
previous `1024 x 1024 px` chunk presentation footprint while cutting one chunk
packet / publish unit from `1024` cells to `256` cells.

## Scope

This spec owns:
- canonical tile pixel size for the rebuilt world
- canonical chunk dimensions for streaming, rendering, and persistence
- surviving world-facing fallback values that still exist in the current repo
- file scope for the first rebuild iteration

## Out of Scope

This spec does not by itself:
- re-implement `Chunk`, `ChunkManager`, or world generation
- define old-save migration from the removed `64 x 64` world runtime
- choose final native vs GDScript implementation strategy for the new world stack

## Related Documents

- `docs/README.md`
- `docs/02_system_specs/README.md`
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- `docs/05_adrs/0002-wrap-world-is-cylindrical.md`
- `docs/05_adrs/0003-immutable-base-plus-runtime-diff.md`
- `docs/02_system_specs/meta/save_and_persistence.md`

## Dependencies

- ADR-0001 for runtime work classes and dirty-update limits
- ADR-0002 for wrap-safe chunk addressing on X
- ADR-0003 for base+diff save ownership
- Save/Persistence spec for changed-chunk storage rules

## Data Model

### Tile contract

- Logical world coordinates remain tile-based (`Vector2i` tile cells).
- The presentation size of one world tile is `64 px`.
- Pixels are presentation scale only; gameplay and save logic stay tile-based.
- Building placement grid must stay aligned with the same `64 px` tile contract.

### Chunk contract

- Chunk footprint: `16 x 16` tiles.
- One chunk therefore materializes `256` tiles.
- Chunk coordinates remain `Vector2i` in chunk space.
- Local tile indices inside a chunk are `0..15` on each axis.
- A chunk is still a streaming/rendering/persistence unit, not the owner of world identity.

### Save contract

- Changed world state is sharded by `16 x 16` chunk coordinates.
- No new save writer may key world state by pixels.
- Compatibility with removed `64 x 64` chunk saves is deferred explicitly until a
  dedicated migration task exists.
- Compatibility with the previous `32 px` / `32 x 32` pre-alpha contract is not
  migrated; the active load path rejects non-current `world_version` saves.

## Runtime Architecture

- Runtime class:
  - boot: initial chunk materialization
  - background: chunk streaming, rebuild, topology/presentation catch-up
  - interactive: one local tile mutation plus bounded dirty marking only
- Authoritative source of truth: the rebuilt world/chunk runtime that owns tile and
  chunk addressing.
- Single write owner: rebuilt world services, not presentation nodes.
- Derived/cache state:
  - loaded chunk nodes
  - visibility/presentation helpers
  - local building/world previews
- Dirty unit:
  - one tile mutation for interactive world changes
  - one chunk materialization request for streaming/build work
- Forbidden shortcuts:
  - mixing `32 px` and `64 px` conversions in parallel
  - keeping `64 x 64` save/stream assumptions "for now"
  - full-world or full-loaded-chunk sweeps in the interactive path

## Event Contracts

- Tile events continue to speak in tile coordinates, not pixel coordinates.
- Chunk events continue to speak in chunk coordinates, now under the `16 x 16` contract.

## Save / Persistence Contracts

- World diffs remain authoritative changed state.
- Save payloads must shard changed world data by rebuilt `16 x 16` chunks.
- Old `64 x 64` data is not silently reinterpreted as compatible.
- Previous `32 x 32` pre-alpha chunk-diff data is not silently reinterpreted as
  compatible; `WORLD_VERSION` owns that boundary.

## Performance Class

- Interactive path must remain bounded by one local tile mutation and local dirty marking.
- Chunk creation, terrain generation, and broad presentation rebuilds remain boot or background work.
- Smaller chunks are not permission to add more synchronous work per player action.

## Modding / Extension Points

- Future world content must resolve in tile/chunk coordinates under this contract.
- Modded world data must not assume a different tile pixel size or chunk footprint.

## Acceptance Criteria

- Canonical docs state `64 px` tiles and `16 x 16` chunks for the rebuild.
- Surviving world-facing code in the current repo no longer hardcodes `32 px` or `12 px`
  tile-size fallbacks.
- Live balance data keeps the building grid at `64`.
- System-spec indices point to this world rebuild contract.

## Failure Cases / Risks

- A data resource silently reintroduces `32` while code defaults say `64`.
- World systems mix logical tile size and presentation pixels.
- A future save path assumes old `64 x 64` chunks without a migration boundary.

## Open Questions

- Do pre-rebuild `64 x 64` saves or previous `32 px` / `32 x 32` pre-alpha saves
  need migration later, or should this remain a clean compatibility boundary?

## Implementation Iterations

### Iteration 1 - Contract establishment

Goal: move the active contract to `64 px` tiles and `16 x 16` chunks while
preserving tile-based gameplay/save math.

What changes:
- update this spec, glossary, runtime specs, packet/save docs, and relevant world specs
- align shared runtime constants to `64 px` and `16 x 16`
- align surviving world-facing fallback sizes to `64 px`
- align current building grid balance data to `64`
- bump `WORLD_VERSION` because chunk packet shape and chunk-diff sharding changed

Acceptance tests:
- [ ] `docs/00_governance/PROJECT_GLOSSARY.md` states `64 px` tile and `16 x 16` chunk contract
- [ ] `core/systems/world/world_runtime_constants.gd` sets `TILE_SIZE_PX = 64`, `CHUNK_SIZE = 16`, and a new current `WORLD_VERSION`
- [ ] `gdextension/src/world_core.cpp` mirrors the `16 x 16` chunk packet geometry
- [ ] `data/balance/building_balance.tres` sets `grid_size = 64`
- [ ] current terrain shape sets use `64 px` source regions so `TileSet.tile_size` and source atlases remain aligned
- [ ] surviving world-facing scripts no longer contain `32 px` or `12 px` tile-size fallbacks in active contract paths

Files that may be touched:
- `docs/02_system_specs/world/world_grid_rebuild_foundation.md`
- `docs/02_system_specs/README.md`
- `docs/README.md`
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `docs/00_governance/ENGINEERING_STANDARDS.md`
- `docs/02_system_specs/world/world_runtime.md`
- `docs/02_system_specs/world/world_foundation_v1.md`
- `docs/02_system_specs/world/mountain_generation.md`
- `docs/02_system_specs/world/lake_generation.md`
- `docs/02_system_specs/world/oversized_terrain_presentation.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `data/balance/building_balance.tres`
- `data/balance/building_balance.gd`
- `core/systems/world/world_runtime_constants.gd`
- `gdextension/src/world_core.cpp`
- `data/terrain/terrain_shape_set.gd`
- `data/terrain/shape_sets/*.tres`
- `assets/sprites/terrain/*_64.png`
- `core/entities/player/player_visibility_indicator.gd`
- `core/entities/structures/z_stairs.gd`
- `core/entities/structures/ark_battery.gd`
- `core/entities/structures/thermo_burner.gd`

Files that must not be touched:
- deleted legacy world runtime files from the removed pre-rebuild stack

### Iteration 2 - World runtime scaffold

Goal: reintroduce the smallest viable world runtime surfaces that consume this contract
without restoring the deleted stack wholesale.

Scope anchor:
- `world/world_runtime.md`
- only the V0 vertical slice from that spec is in scope for the first rebuilt
  runtime implementation task

### Iteration 3 - Streaming, save, and rebuild implementation

Goal: reintroduce chunked world generation, persistence, and streaming under the
`64 px` / `16 x 16` contract after the V0 slice is proven and approved for
extension.
