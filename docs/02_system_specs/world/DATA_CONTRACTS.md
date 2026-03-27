---
title: World Data Contracts
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-27
depends_on:
  - world_generation_foundation.md
  - subsurface_and_verticality_foundation.md
related_docs:
  - world_generation_foundation.md
  - environment_runtime_foundation.md
  - lighting_visibility_and_darkness.md
  - subsurface_and_verticality_foundation.md
  - ../../00_governance/AI_PLAYBOOK.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
---

# World Data Contracts

This document records the current data contracts for the `world / mining / topology / reveal / presentation` runtime stack as it exists in code today.

It is intentionally descriptive, not aspirational.

It does not propose architecture changes, refactors, or optimizations.

## Scope

Observed files for this first version:

- `core/autoloads/world_generator.gd`
- `core/autoloads/event_bus.gd`
- `core/systems/world/tile_gen_data.gd`
- `core/systems/world/chunk_build_result.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/underground_fog_state.gd`
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `scenes/world/game_world.gd`

## Current Source Of Truth Summary

- Surface base terrain for unloaded tiles comes from `WorldGenerator` through `build_chunk_native_data()` and `get_terrain_type_fast()`.
- Loaded chunk terrain truth lives in `Chunk._terrain_bytes`.
- Loaded chunk runtime modifications live in `Chunk._modified_tiles`.
- Unloaded chunk runtime modifications live in `ChunkManager._saved_chunk_data`.
- `ChunkManager.get_terrain_type_at_global()` is the current read arbiter that resolves loaded data first, then saved modifications, then generator fallback, with special underground handling.
- Underground unloaded tiles are currently treated as solid `ROCK` by `ChunkManager.get_terrain_type_at_global()`.
- Mountain topology caches are derived from currently loaded surface chunks only.
- Surface local mountain reveal state is derived from the current loaded open pocket around the player.
- Underground fog state is transient reveal state, shared by the active underground runtime, and not persisted.
- TileMap layers, fog cells, cover erasures, cliff overlays, and mountain shadow sprites are presentation outputs, not world truth.

## Layer: World

- `classification`: `canonical`
- `owners`: `WorldGenerator` and `ChunkContentBuilder` generate base chunk data; `Chunk.populate_native()` installs that data into live chunks; `Chunk._set_terrain_type()` mutates loaded chunk terrain; `ChunkManager.set_saved_data()` and `ChunkManager._unload_chunk()` write the unloaded runtime overlay.
- `readers`: `Chunk` terrain, cover, cliff, and fog drawing paths; `ChunkManager.get_terrain_type_at_global()`; `Player` resource targeting and movement checks through `ChunkManager`; `GameWorld` indoor fallback; `MountainShadowSystem` edge detection.
- `invariants`:
- Chunk coordinates are canonicalized through `WorldGenerator.canonicalize_chunk_coord()` before chunk identity is established.
- Global tile reads are canonicalized through `WorldGenerator.canonicalize_tile()` before cross-chunk lookup.
- `Chunk` local array indexing is `local.y * chunk_size + local.x`.
- `Chunk.populate_native()` copies terrain, height, variation, and biome bytes and then reapplies saved modifications.
- Surface unloaded reads prefer saved modification overlay over generator base terrain.
- Underground unloaded reads currently resolve to `TileGenData.TerrainType.ROCK`.
- `ChunkBuildResult.to_native_data()` currently exports only `chunk_size`, `terrain`, `height`, `variation`, and `biome`.
- `write operations`:
- `WorldGenerator.build_chunk_native_data()`
- `Chunk.populate_native()`
- `Chunk._set_terrain_type()`
- `Chunk.mark_tile_modified()`
- `ChunkManager.set_saved_data()`
- `ChunkManager._unload_chunk()`
- `emitted events / invalidation signals`:
- `EventBus.chunk_loaded`
- `EventBus.chunk_unloaded`
- `ChunkManager._mark_topology_dirty()` or native topology dirtying on chunk load and unload
- `current violations / ambiguities / contract gaps`:
- `Chunk.get_terrain_type_at()` returns `GROUND` on invalid local index instead of asserting or surfacing misuse.
- `Chunk.populate_native()` silently drops mismatched `variation` and `biome` arrays by replacing them with empty arrays.
- `ChunkManager.is_walkable_at_world()` falls back to `WorldGenerator.is_walkable_at()` when a chunk is not loaded, even on underground z-levels, while `get_terrain_type_at_global()` treats unloaded underground tiles as `ROCK`. Those read-path rules do not currently match.
- `ChunkManager.has_resource_at_world()` has no unloaded fallback. For unloaded tiles it returns `false`, even though unloaded underground terrain is otherwise treated as solid rock by `get_terrain_type_at_global()`.

## Layer: Mining

- `classification`: `canonical`
- `owners`: the normal write path is `HarvestTileCommand -> ChunkManager.try_harvest_at_world() -> Chunk.try_mine_at()`. Current debug-only direct writers also exist in `GameWorldDebug` and `ChunkManager.ensure_underground_pocket()`.
- `readers`: topology patching in `ChunkManager`; `MountainRoofSystem`; `MountainShadowSystem`; underground fog reveal path; save collection through `Chunk.get_modifications()`.
- `invariants`:
- Only `TileGenData.TerrainType.ROCK` is mineable through `Chunk.try_mine_at()`.
- The mined tile resolves to `MOUNTAIN_ENTRANCE` if any cardinal neighbor is exterior-open terrain; otherwise it resolves to `MINED_FLOOR`.
- After a successful mine, the same tile and same-chunk cardinal open neighbors are re-normalized through `_refresh_open_neighbors()`.
- Loaded mutations are recorded as `{ "terrain": terrain_type }` in `Chunk._modified_tiles`.
- A successful world harvest returns an item payload derived from `WorldGenerator.balance.rock_drop_item_id` and `rock_drop_amount`.
- `write operations`:
- `ChunkManager.try_harvest_at_world()`
- `Chunk.try_mine_at()`
- `Chunk._set_terrain_type()`
- `Chunk._refresh_open_neighbors()`
- Debug-only direct writes in `scenes/world/game_world_debug.gd`
- Debug-only direct writes in `ChunkManager.ensure_underground_pocket()`
- `emitted events / invalidation signals`:
- `ChunkManager._on_mountain_tile_changed()`
- `EventBus.mountain_tile_mined`
- Underground `UndergroundFogState.force_reveal()` and immediate fog apply on successful underground mining
- `MountainRoofSystem` and `MountainShadowSystem` both listen to `EventBus.mountain_tile_mined`
- `current violations / ambiguities / contract gaps`:
- `Chunk.try_mine_at()` mutates canonical terrain but does not itself emit events, patch topology, or update fog. The safe orchestration point is `ChunkManager.try_harvest_at_world()`, not the chunk method.
- Cross-chunk mining adjacency is not normalized. `_refresh_open_tile()` returns early for out-of-chunk locals, so `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` status is only refreshed inside the current chunk.
- Cross-chunk mining redraw is also local-only. `_collect_mining_dirty_tiles()` returns only same-chunk tiles, so neighbor chunk visuals at seams can remain stale.
- Debug direct writers bypass the normal event and invalidation chain.

## Layer: Topology

- `classification`: `derived`
- `owners`: `ChunkManager` owns the managed topology state; when enabled, the native `MountainTopologyBuilder` owns the internal implementation behind the same public getters.
- `readers`: `MountainRoofSystem` reads `ChunkManager.query_local_underground_zone()`. No direct in-scope runtime reader was found for `get_mountain_key_at_tile()`, `get_mountain_tiles()`, or `get_mountain_open_tiles()`.
- `invariants`:
- Surface mountain topology is only exposed when `ChunkManager._active_z == 0`.
- The topology domain is `ROCK`, `MINED_FLOOR`, and `MOUNTAIN_ENTRANCE`.
- The open subset is `MINED_FLOOR` and `MOUNTAIN_ENTRANCE`.
- Connectivity for mountain components is cardinal only.
- The component key is the lexicographically smallest tile encountered in the component.
- Runtime topology rebuilds operate on currently loaded chunks only.
- `query_local_underground_zone()` also operates on the current `_loaded_chunks` set only and returns `zone_kind = loaded_open_pocket`.
- `query_local_underground_zone()` marks `truncated = true` when traversal reaches an unloaded neighbor chunk.
- `write operations`:
- `ChunkManager._mark_topology_dirty()`
- `ChunkManager._tick_topology()`
- `ChunkManager._start_topology_build()`
- `ChunkManager._process_topology_build_step()`
- `ChunkManager._rebuild_loaded_mountain_topology()`
- `ChunkManager._incremental_topology_patch()`
- Native builder calls: `set_chunk`, `remove_chunk`, `update_tile`, `ensure_built`
- `emitted events / invalidation signals`:
- There is currently no dedicated `topology_changed` or `topology_ready` event.
- Invalidation happens on chunk load, chunk unload, and successful mountain-tile mutation.
- Readiness is currently observable only through `ChunkManager.is_topology_ready()`.
- `current violations / ambiguities / contract gaps`:
- Topology is loaded-bubble scoped, not world-global. Unloaded continuation is absent from the cache even when canonical surface terrain exists.
- Incremental split detection is heuristic. `_incremental_topology_patch()` only escalates to a dirty rebuild when a newly opened tile sees at least two rock neighbors.
- The progressive topology rebuild path commits `_mountain_key_by_tile`, `_mountain_tiles_by_key`, and `_mountain_open_tiles_by_key`, but does not rebuild or commit `_mountain_tiles_by_key_by_chunk` or `_mountain_open_tiles_by_key_by_chunk`.
- Staging dictionaries `_topology_build_tiles_by_key_by_chunk` and `_topology_build_open_tiles_by_key_by_chunk` currently exist but are not part of the progressive rebuild flow.

## Layer: Reveal

- `classification`: `derived`
- `owners`: `MountainRoofSystem` owns surface local-zone and cover-reveal derivation; `Chunk` owns the per-chunk local cover reveal set it applies; `UndergroundFogState` owns underground revealed/visible sets; `ChunkManager` owns the application of underground fog deltas to loaded chunks.
- `readers`: `Chunk` cover-layer and fog-layer presentation code; `MountainRoofSystem` public zone getters; no other in-scope gameplay reader was found for these reveal sets.
- `invariants`:
- Surface local mountain reveal only runs when `ChunkManager.get_active_z_level() == 0`.
- `MountainRoofSystem` only seeds a surface local zone from a player tile that is currently `MINED_FLOOR` or `MOUNTAIN_ENTRANCE`.
- Surface revealed cover is derived from `query_local_underground_zone()` and then expanded with a revealable rock halo around zone tiles.
- `Chunk._revealed_local_cover_tiles` is local-to-chunk and applied by erasing cells from `cover_layer`.
- Underground fog uses one shared `UndergroundFogState` instance in `ChunkManager`.
- Underground fog state is transient, cleared on z-level entry, and not persisted.
- Underground visible radius is currently fixed at `REVEAL_RADIUS = 5`.
- Underground fog can only be removed for revealable tiles: open tiles always, rock only when it is a cave-edge rock tile.
- `write operations`:
- `MountainRoofSystem._request_refresh()`
- `MountainRoofSystem._refresh_active_local_zone()`
- `Chunk.set_revealed_local_cover_tiles()`
- `UndergroundFogState.update()`
- `UndergroundFogState.force_reveal()`
- `UndergroundFogState.clear()`
- `ChunkManager._apply_underground_fog_visible_tiles()`
- `ChunkManager._apply_underground_fog_discovered_tiles()`
- `emitted events / invalidation signals`:
- There is currently no dedicated reveal-state-changed event.
- Surface reveal invalidation is driven by player tile movement, `EventBus.mountain_tile_mined`, `EventBus.chunk_loaded`, and `EventBus.chunk_unloaded`.
- Underground fog invalidation is driven by z-level entry, fog update ticks, and immediate successful underground mining.
- `current violations / ambiguities / contract gaps`:
- `MountainRoofSystem` tracks `zone_kind` and `truncated`, but current runtime behavior does not branch on `zone_kind`, and `truncated` is only exposed as a getter.
- Surface reveal is loaded-bubble scoped. If the local open pocket continues into an unloaded chunk, reveal stops at the current load boundary.
- `Chunk` currently exposes both `set_revealed_local_zone()` and `set_revealed_local_cover_tiles()`. The active runtime path uses the cover-tile API directly.
- Underground fog state is shared across underground runtime and cleared on z change, so discovered-state continuity between underground floors is not currently represented.

## Layer: Presentation

- `classification`: `presentation-only`
- `owners`: `Chunk` owns terrain, cover, cliff, fog, flora, and debug visuals for a loaded chunk; `ChunkManager` schedules progressive redraw and applies underground fog cell changes; `MountainRoofSystem` drives cover erasure through chunk APIs; `MountainShadowSystem` owns shadow edge cache, shadow build queues, and shadow sprites.
- `readers`: Godot rendering is the effective consumer. No in-scope simulation system was found that treats these presentation nodes as authority.
- `invariants`:
- `Chunk._terrain_layer`, `_cover_layer`, and `_cliff_layer` are rebuilt from current chunk data, not treated as truth.
- Surface cover reveal is applied by erasing `cover_layer` cells for revealed local cover tiles.
- Underground chunks do not use roof cover. They use a dedicated fog layer instead.
- Underground fog layer initializes every loaded underground tile as `UNSEEN`.
- `MountainShadowSystem` only runs in surface context.
- `MountainShadowSystem` builds shadow sprites from cached external mountain edges plus current sun angle and shadow length factor.
- Shadow builds use the target chunk plus the four cardinal neighbor chunks as edge sources.
- `write operations`:
- `Chunk._redraw_all()`
- `Chunk.continue_redraw()`
- `Chunk._redraw_dirty_tiles()`
- `Chunk._redraw_cover_tiles()`
- `Chunk.apply_fog_visible()`
- `Chunk.apply_fog_discovered()`
- `MountainShadowSystem._build_edge_cache_now()`
- `MountainShadowSystem._advance_edge_cache_build()`
- `MountainShadowSystem._start_shadow_build()`
- `MountainShadowSystem._advance_shadow_build()`
- `MountainShadowSystem._finalize_shadow_texture()`
- `MountainShadowSystem._finalize_shadow_apply()`
- `emitted events / invalidation signals`:
- `EventBus.chunk_loaded`
- `EventBus.chunk_unloaded`
- `EventBus.mountain_tile_mined`
- `EventBus.z_level_changed`
- Sun-angle threshold crossing in `MountainShadowSystem._process()`
- Player movement indirectly through reveal and fog systems
- `current violations / ambiguities / contract gaps`:
- Cross-chunk mining redraw gaps leak directly into presentation: neighboring chunk cover, terrain, and cliff visuals are not refreshed by the current mining path.
- Presentation is loaded-chunk scoped. There is no presentation object for unloaded continuation even when world read APIs can still answer terrain queries.
- Debug direct writers can redraw visuals without going through the normal world -> mining -> topology -> reveal invalidation chain.

## Postconditions: `mine tile`

### Success path

- The target tile must have been loaded and `ROCK` at the time of the call.
- The target tile is rewritten to either `MINED_FLOOR` or `MOUNTAIN_ENTRANCE`.
- Same-chunk cardinal open neighbors are re-normalized between `MINED_FLOOR` and `MOUNTAIN_ENTRANCE`.
- The changed terrain values are stored in the loaded chunk runtime state and written into `Chunk._modified_tiles`.
- The owning chunk is marked dirty.
- Same-chunk `3x3` dirty tiles are redrawn for terrain, cover, and cliff presentation.
- Surface topology is updated immediately through `_on_mountain_tile_changed()` and may additionally be marked dirty for a background rebuild if split suspicion is detected.
- `EventBus.mountain_tile_mined` is emitted after the immediate topology patch path runs.
- If the active z-level is underground, the mined tile plus its 8-neighbor halo are force-revealed in `UndergroundFogState`, and revealable loaded tiles in that set have fog removed immediately.
- The operation returns `{ "item_id": ..., "amount": ... }` from world balance.

### No-op path

- If the target chunk is not loaded, the operation returns `{}`.
- If the target tile is not `ROCK`, the operation returns `{}`.
- In the no-op path, no mining event is emitted and no fog or topology update runs.

### Current non-guarantees

- Cross-chunk open-tile normalization is not guaranteed today.
- Cross-chunk redraw after mining is not guaranteed today.

## Boundary Rules At Chunk Seams

- Tile and chunk identity are canonicalized through `WorldGenerator.canonicalize_tile()` and `canonicalize_chunk_coord()`. The world currently wraps on X and does not wrap on Y.
- Cross-chunk world reads use `Chunk._get_global_terrain()` -> `ChunkManager.get_terrain_type_at_global()`.
- Cross-chunk topology traversal uses cardinal neighbors only and only continues when the neighbor chunk is currently loaded.
- Cross-chunk local-zone traversal in `query_local_underground_zone()` also stops at unloaded chunks and reports `truncated = true`.
- `MountainRoofSystem` only reveals cover for chunks that are currently loaded.
- `MountainShadowSystem` edge detection can read across chunk seams through `get_terrain_type_at_global()`, including unloaded-neighbor fallback rules, but it still only builds sprites for loaded chunks.
- Current contract gap: mining at a chunk seam does not refresh or normalize neighbor-chunk open tiles or neighbor-chunk visuals.

## Loaded Vs Unloaded Read-Path Rules

- `Chunk.get_terrain_type_at(local)` is a loaded-chunk local-array read only.
- `ChunkManager.get_terrain_type_at_global(tile)` is the current authoritative cross-state terrain read:
- If the chunk is loaded, read `Chunk._terrain_bytes`.
- Else, if `_saved_chunk_data` has a saved local override, read that override.
- Else, if active z is underground, return `ROCK`.
- Else, on surface, fall back to `WorldGenerator.get_terrain_type_fast()`.
- `ChunkManager.query_local_underground_zone(seed_tile)` requires the seed tile to be loaded and open in the current active `_loaded_chunks` set. There is no unloaded fallback path.
- `ChunkManager.get_mountain_key_at_tile()`, `get_mountain_tiles()`, and `get_mountain_open_tiles()` only expose surface topology and do not synthesize unloaded topology.
- `ChunkManager.has_resource_at_world()` has no unloaded fallback and returns `false` for unloaded chunks.
- `ChunkManager.is_walkable_at_world()` falls back to `WorldGenerator.is_walkable_at()` for unloaded chunks regardless of active z. That currently disagrees with underground terrain fallback in `get_terrain_type_at_global()`.

## Source Of Truth Vs Derived State

### Source of truth

- Surface generated base terrain: `WorldGenerator` / `ChunkContentBuilder`
- Loaded terrain bytes: `Chunk._terrain_bytes`
- Loaded runtime modification diff: `Chunk._modified_tiles`
- Unloaded runtime modification diff: `ChunkManager._saved_chunk_data`
- Active z selection for chunk set switching: `ChunkManager._active_z`

### Derived state

- `Chunk._has_mountain`
- Surface topology caches in `ChunkManager`
- `ChunkManager.query_local_underground_zone()` result
- `MountainRoofSystem` active local zone and cover-tile maps
- `UndergroundFogState` visible and revealed sets
- `MountainShadowSystem._edge_cache`

### Presentation-only state

- `Chunk` TileMap layers and flora/debug nodes
- Fog tiles written into `Chunk._fog_layer`
- Cover erasures applied to `Chunk._cover_layer`
- `MountainShadowSystem._shadow_sprites`

## Out Of Scope / Follow-up

- Save serialization and on-disk shape in `chunk_save_system.gd`, `save_collectors.gd`, and `save_appliers.gd`
- Command routing and player interaction details outside the mining entrypoint, including `harvest_tile_command.gd` and `player.gd`
- Lighting systems outside mountain-shadow presentation, including daylight and darkness systems
- Debug-only validation and mutation paths such as `runtime_validation_driver.gd` and `game_world_debug.gd`

## Minimal Debug Validators To Add Later

- Validate that mining a seam tile updates open-tile classification consistently on both sides of the chunk boundary.
- Validate that seam mining redraws both the source chunk and any affected neighbor chunks.
- Validate that `get_terrain_type_at_global()` and loaded chunk local reads agree for every loaded tile, including wrapped X boundaries.
- Validate that unloaded underground walkability decisions match unloaded underground terrain fallback rules.
- Validate that `mountain_open_tiles_by_key` matches the set of loaded `MINED_FLOOR` and `MOUNTAIN_ENTRANCE` tiles after mining and after chunk streaming changes.
- Validate that `query_local_underground_zone()` reports `truncated = true` whenever traversal hits an unloaded continuation.
- Validate that revealed cover tiles are actually erased from `cover_layer` for every chunk in the active local zone.
- Validate that fog-visible and fog-discovered transitions only touch revealable underground tiles.
