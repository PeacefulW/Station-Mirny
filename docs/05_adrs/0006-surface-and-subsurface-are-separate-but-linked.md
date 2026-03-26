---
title: ADR-0006 Surface and Subsurface Are Separate but Linked
doc_type: adr
status: approved
owner: engineering
source_of_truth: true
version: 1.1
last_updated: 2026-03-26
related_docs:
  - ../02_system_specs/world/subsurface_and_verticality_foundation.md
  - ../02_system_specs/base/building_and_rooms.md
---

# ADR-0006 Surface and Subsurface Are Separate but Linked

## Context

The game has surface gameplay (base building, exploration) and underground gameplay (mining, cellars, caves). These could be one unified system or two distinct systems. We need to decide.

## Decision

Surface (z=0) and subsurface (z<0) are **separate world layers with explicit connections**:

- **Separate logic.** Each Z-level has its own chunk data, terrain, lighting rules, threat profile, and environmental pressure. Surface has daylight and weather. Underground has permanent darkness and excavation.
- **Separate streaming.** Only the active Z-level and its immediate neighbors are loaded. Player at z=0 does not load z=-3.
- **Linked by connectors.** Stairs, ladders, hatches connect Z-levels. Connectors have stable identity (persist across save/load). Both ends must exist for the link to work.
- **Not a monolith.** Surface code does not know underground internals. Underground code does not depend on surface weather. They share interfaces (connector protocol, chunk streaming API), not implementation.

Underground types:
- **Cellar** (z=-1): player-built, beneath the base, safe fantasy ("bunker")
- **Mine/cave**: excavated from mountain rock, discovered, risky fantasy ("what's in there")
- **Deep** (z<-1): future expansion, higher pressure

## Consequences

- Z-level manager handles transitions, not surface or underground systems directly.
- Each Z-level can have different environmental rules without polluting the other.
- Chunk streaming loads only relevant Z layers — no wasted memory on distant depths.
- Building system works on any Z-level but rooms are Z-local (a room at z=0 is not connected to z=-1 unless a connector exists).

## Implementation Status (2026-03-26)

Underground Fog of War MVP rollout complete. Separation enforced in code:

- **Chunk generation**: z != 0 → solid ROCK (`_generate_solid_rock_chunk`), not surface terrain
- **Chunk terrain tileset**: underground uses `rock_faces_atlas_dungeon.png`, surface uses `rock_faces_atlas.png`
- **Cover/roof system**: `MountainRoofSystem._request_refresh()` skips z != 0. `Chunk._redraw_cover_tile()` skips `_is_underground`.
- **Fog of war**: underground-only `_fog_layer` (TileMapLayer z=7) with 3-state visibility (unseen/discovered/visible). Surface has no fog layer.
- **Terrain fallback**: `get_terrain_type_at_global()` returns ROCK for unloaded underground tiles, surface terrain for z=0.
- **Pocket creation**: `ensure_underground_pocket()` loads all needed chunks across boundaries, mines tiles per-chunk correctly.
- **Fog state**: transient (`UndergroundFogState`), cleared on z-entry, not persisted.
