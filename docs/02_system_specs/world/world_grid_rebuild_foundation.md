---
title: World Grid Rebuild Foundation
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.0
last_updated: 2026-04-18
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../meta/save_and_persistence.md
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
- one world tile = `32 px`
- one chunk = `32 x 32` tiles

World-facing systems must derive tile/world conversion, building alignment,
visibility radii, chunk addressing, and save sharding from this contract instead of
carrying legacy `64 px`, `64 x 64`, or `12 px` assumptions.

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
- The presentation size of one world tile is `32 px`.
- Pixels are presentation scale only; gameplay and save logic stay tile-based.
- Building placement grid must stay aligned with the same `32 px` tile contract.

### Chunk contract

- Chunk footprint: `32 x 32` tiles.
- One chunk therefore materializes `1024` tiles.
- Chunk coordinates remain `Vector2i` in chunk space.
- Local tile indices inside a chunk are `0..31` on each axis.
- A chunk is still a streaming/rendering/persistence unit, not the owner of world identity.

### Save contract

- Changed world state is sharded by `32 x 32` chunk coordinates.
- No new save writer may key world state by pixels.
- Compatibility with removed `64 x 64` chunk saves is deferred explicitly until a
  dedicated migration task exists.

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
- Chunk events continue to speak in chunk coordinates, now under the `32 x 32` contract.

## Save / Persistence Contracts

- World diffs remain authoritative changed state.
- Save payloads must shard changed world data by rebuilt `32 x 32` chunks.
- Old `64 x 64` data is not silently reinterpreted as compatible.

## Performance Class

- Interactive path must remain bounded by one local tile mutation and local dirty marking.
- Chunk creation, terrain generation, and broad presentation rebuilds remain boot or background work.
- Smaller chunks are not permission to add more synchronous work per player action.

## Modding / Extension Points

- Future world content must resolve in tile/chunk coordinates under this contract.
- Modded world data must not assume a different tile pixel size or chunk footprint.

## Acceptance Criteria

- Canonical docs state `32 px` tiles and `32 x 32` chunks for the rebuild.
- Surviving world-facing code in the current repo no longer hardcodes `64 px` or `12 px`
  tile-size fallbacks.
- Live balance data no longer overrides the building grid back to `64`.
- System-spec indices point to this world rebuild contract.

## Failure Cases / Risks

- A data resource silently reintroduces `64` while code defaults say `32`.
- World systems mix logical tile size and presentation pixels.
- A future save path assumes old `64 x 64` chunks without a migration boundary.

## Open Questions

- Where should the shared grid constants live once the new world runtime is reintroduced:
  autoload, balance resource, or dedicated world config resource?
- Do pre-rebuild `64 x 64` saves need migration, or should the rebuilt world start with a
  clean compatibility boundary?

## Implementation Iterations

### Iteration 1 - Contract establishment

Goal: make the rebuild contract explicit and remove the surviving repo-level fallback
assumptions that still contradict it.

What changes:
- create this spec
- update docs indices and glossary
- align surviving world-facing fallback sizes to `32 px`
- align current building grid balance data to `32`

Acceptance tests:
- [ ] `docs/00_governance/PROJECT_GLOSSARY.md` states `32 px` tile and `32 x 32` chunk contract
- [ ] `data/balance/building_balance.tres` sets `grid_size = 32`
- [ ] surviving world-facing scripts no longer contain `64 px` or `12 px` tile-size fallbacks

Files that may be touched:
- `docs/02_system_specs/world/world_grid_rebuild_foundation.md`
- `docs/02_system_specs/README.md`
- `docs/README.md`
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `data/balance/building_balance.tres`
- `core/entities/player/player_visibility_indicator.gd`
- `core/entities/structures/z_stairs.gd`
- `core/entities/structures/ark_battery.gd`
- `core/entities/structures/thermo_burner.gd`

Files that must not be touched:
- deleted legacy world runtime files from the removed pre-rebuild stack

### Iteration 2 - World runtime scaffold

Goal: reintroduce the smallest viable world runtime surfaces that consume this contract
without restoring the deleted stack wholesale.

### Iteration 3 - Streaming, save, and rebuild implementation

Goal: reintroduce chunked world generation, persistence, and streaming under the
`32 px` / `32 x 32` contract.
