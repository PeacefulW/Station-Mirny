---
title: World Data Contracts
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.5
last_updated: 2026-03-28
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

This is the first runtime contract baseline for this stack.

`status: draft` here means the document may still expand in coverage. It does not make the document optional.

Until superseded, this document is mandatory reading for any iteration that touches the `world / mining / topology / reveal / presentation` stack.

## How Agents Must Use This Document

- Identify the affected layers before changing code.
- Do not change layer invariants implicitly.
- If touching a `canonical` layer, re-check the full derived and presentation invalidation chain.
- If touching a `derived` layer, do not alter source-of-truth semantics or unloaded read rules.
- If a change introduces a new writer, invalidation path, or cross-layer dependency, update this document in the same iteration.
- If a change crosses layer boundaries, re-verify `source of truth` vs `derived state` before merging.

## Layer Map

| Layer | Class | Owner | Writes | Reads | Scope / rebuild |
| --- | --- | --- | --- | --- | --- |
| World | `canonical` | `ChunkManager` runtime arbitration, `Chunk` loaded storage, `WorldGenerator` unloaded surface base | canonical terrain bytes and unloaded overlay | terrain/resource/walkability/presentation consumers | loaded + unloaded reads, immediate writes, generator fallback |
| Mining | `canonical` | `ChunkManager` orchestration, `Chunk` loaded mutation storage | loaded terrain mutation and mining-side invalidation entrypoint | topology, reveal, presentation, save collection | loaded-only mutation, immediate |
| Topology | `derived` | `ChunkManager`, with native `MountainTopologyBuilder` behind it when enabled | surface topology caches | `MountainRoofSystem` and topology getters | surface-only, loaded-bubble scoped, incremental patch + deferred dirty rebuild |
| Reveal | `derived` | `MountainRoofSystem`, `UndergroundFogState`, `ChunkManager` fog applier | local cover reveal and underground fog state | chunk cover/fog presentation and reveal getters | active-z dependent, loaded-bubble scoped, immediate/deferred hybrid |
| Presentation | `presentation-only` | `Chunk`, `MountainShadowSystem` | TileMap and shadow sprite output | Godot renderer | loaded-only, redraw-driven, surface shadow build is sun-angle dependent |

## Scope

Observed files for this version:

- `core/autoloads/world_generator.gd`
- `core/autoloads/event_bus.gd`
- `core/systems/commands/harvest_tile_command.gd`
- `core/systems/world/tile_gen_data.gd`
- `core/systems/world/chunk_build_result.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk_tileset_factory.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/surface_terrain_resolver.gd`
- `core/systems/world/underground_fog_state.gd`
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `scenes/world/game_world.gd`

## Current Source Of Truth Summary

- Surface base terrain for unloaded tiles comes from `WorldGenerator` through `build_chunk_native_data()`, `build_chunk_content()`, and `get_terrain_type_fast()`.
- Loaded chunk terrain truth lives in `Chunk._terrain_bytes`.
- Loaded chunk runtime modifications live in `Chunk._modified_tiles`.
- Unloaded chunk runtime modifications live in `ChunkManager._saved_chunk_data`.
- `ChunkManager.get_terrain_type_at_global()` is the current read arbiter that resolves loaded data first, then saved modifications, then generator fallback, with special underground handling.
- Underground unloaded tiles are currently treated as solid `ROCK` by `ChunkManager.get_terrain_type_at_global()`.
- Current surface chunk generation resolves canonical terrain as `GROUND`, `WATER`, `SAND`, or `ROCK`. `MINED_FLOOR` and `MOUNTAIN_ENTRANCE` are runtime mutation results, not generator outputs.
- Mountain topology caches are derived from currently loaded surface chunks only.
- Surface local mountain reveal state is derived from the current loaded open pocket around the player.
- Underground fog state is transient reveal state, shared by the active underground runtime, and not persisted.
- Rock atlas selection is explicit code in `Chunk`; current rendering does not rely on Godot TileSet terrain peering or autotile rules.
- TileMap layers, fog cells, cover erasures, cliff overlays, and mountain shadow sprites are presentation outputs, not world truth.

## Layer: World

- `classification`: `canonical`
- `owner`: `ChunkManager` owns runtime cross-state terrain arbitration, `Chunk` owns loaded chunk terrain storage, and `WorldGenerator` owns the generated surface base terrain used for unloaded fallback.
- `writers`: `WorldGenerator` and `ChunkContentBuilder` generate base chunk payloads; `Chunk.populate_native()` installs chunk state; `Chunk._set_terrain_type()` and `Chunk.mark_tile_modified()` mutate loaded runtime terrain; `ChunkManager.set_saved_data()` and `ChunkManager._unload_chunk()` write the unloaded overlay.
- `readers`: `Chunk` terrain, cover, cliff, and fog drawing paths; `ChunkManager.get_terrain_type_at_global()`; `Player` resource targeting and movement checks through `ChunkManager`; `GameWorld` indoor fallback; `MountainShadowSystem` edge detection.
- `rebuild policy`: immediate writes; loaded chunk terrain is mutated in place; unloaded runtime changes are stored as overlay state and re-applied on load; cross-state reads are centralized through `ChunkManager.get_terrain_type_at_global()`.
- `invariants`:
- `assert(chunk_coord == WorldGenerator.canonicalize_chunk_coord(chunk_coord), "chunk coord must be canonical before chunk identity is established")`
- `assert(global_tile == WorldGenerator.canonicalize_tile(global_tile), "global tile reads must use canonical tile coordinates")`
- `assert(index == local.y * chunk_size + local.x, "chunk local indexing must be row-major")`
- `assert(native_arrays_copied_before_saved_modifications and saved_modifications_reapplied_after_native_copy, "populate_native must install native arrays before saved modifications are reapplied")`
- `assert(loaded_chunk or not saved_tile_state.has("terrain") or resolved_terrain == int(saved_tile_state["terrain"]), "saved terrain override must win for unloaded reads")`
- `assert(loaded_chunk or saved_tile_state.has("terrain") or active_z == 0 or resolved_terrain == TileGenData.TerrainType.ROCK, "unloaded underground fallback must be ROCK")`
- `assert(native_data.keys().has_all(["chunk_coord", "canonical_chunk_coord", "base_tile", "chunk_size", "terrain", "height", "variation", "biome", "flora_density_values", "flora_modulation_values"]), "ChunkBuildResult.to_native_data() must export the current payload fields")`
- `write operations`:
- `WorldGenerator.build_chunk_native_data()`
- `WorldGenerator.build_chunk_content()`
- `Chunk.populate_native()`
- `Chunk._set_terrain_type()`
- `Chunk.mark_tile_modified()`
- `ChunkManager.set_saved_data()`
- `ChunkManager._unload_chunk()`
- `forbidden writes`:
- `Topology`, `Reveal`, and `Presentation` code must not mutate `Chunk._terrain_bytes`, `Chunk._modified_tiles`, or `ChunkManager._saved_chunk_data`.
- TileMap redraw paths and shadow/reveal systems must not be treated as places that can author canonical terrain changes.
- World reads must not use topology caches, reveal sets, or presentation layers as substitute source of truth for terrain semantics.
- `emitted events / invalidation signals`:
- `EventBus.chunk_loaded`
- `EventBus.chunk_unloaded`
- `ChunkManager._mark_topology_dirty()` or native topology dirtying on chunk load and unload
- `current violations / ambiguities / contract gaps`:
- `Chunk.get_terrain_type_at()` returns `GROUND` on invalid local index instead of asserting or surfacing misuse.
- `Chunk.populate_native()` silently drops mismatched `variation` and `biome` arrays by replacing them with empty arrays.
- ~~`ChunkManager.is_walkable_at_world()` falls back to `WorldGenerator.is_walkable_at()` when a chunk is not loaded, even on underground z-levels, while `get_terrain_type_at_global()` treats unloaded underground tiles as `ROCK`. Those read-path rules do not currently match.~~ **resolved 2026-03-27**: `is_walkable_at_world()` now delegates to `get_terrain_type_at_global()` for all cases, matching the authoritative loaded → saved → underground-ROCK → surface-generator fallback chain.
- `ChunkManager.has_resource_at_world()` has no unloaded fallback. For unloaded tiles it returns `false`, even though unloaded underground terrain is otherwise treated as solid rock by `get_terrain_type_at_global()`.
- `Chunk.populate_native()` reapplies saved terrain modifications tile-by-tile through `_apply_saved_modifications()` and does not recompute neighboring open-tile state during load.

## Layer: Mining

- `classification`: `canonical`
- `owner`: `ChunkManager` owns authoritative mine-tile orchestration, while `Chunk` owns the loaded terrain mutation storage that mining changes.
- `writers`: the normal production path is `HarvestTileCommand -> ChunkManager.try_harvest_at_world() -> Chunk.try_mine_at()`. Direct mutation helpers also exist in `Chunk.try_mine_at()`, `GameWorldDebug`, and `ChunkManager.ensure_underground_pocket()`.
- `readers`: topology patching in `ChunkManager`; `MountainRoofSystem`; `MountainShadowSystem`; underground fog reveal path; save collection through `Chunk.get_modifications()`.
- `rebuild policy`: immediate loaded-chunk mutation; immediate topology patch and mining event emission on the safe orchestration path; underground fog reveal is immediate on underground mining; broader topology rebuild remains deferred dirty rebuild when flagged.
- `invariants`:
- `assert(old_type == TileGenData.TerrainType.ROCK, "only ROCK is mineable through Chunk.try_mine_at()")`
- `assert((has_exterior_neighbor and new_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE) or (not has_exterior_neighbor and new_type == TileGenData.TerrainType.MINED_FLOOR), "mined tile must become ENTRANCE if exterior-adjacent, else MINED_FLOOR")`
- `assert(mining_orchestration_renormalizes_same_chunk_and_cross_chunk_cardinal_neighbors, "try_harvest_at_world() re-normalizes MINED_FLOOR/MOUNTAIN_ENTRANCE for same-chunk and cross-chunk cardinal neighbors after mining")`
- `assert(_modified_tiles[local_tile] == {"terrain": new_type}, "loaded terrain mutations must be recorded as terrain-only diffs")`
- `assert(result.item_id == str(WorldGenerator.balance.rock_drop_item_id) and result.amount == WorldGenerator.balance.rock_drop_amount, "successful world harvest must return the configured rock drop payload")`
- `write operations`:
- `ChunkManager.try_harvest_at_world()`
- `Chunk.try_mine_at()`
- `Chunk._set_terrain_type()`
- `Chunk._refresh_open_neighbors()` (called by `try_harvest_at_world()` for same-chunk neighbors)
- `Chunk._refresh_open_tile()` (called by `ChunkManager._seam_normalize_and_redraw()` for cross-chunk neighbors)
- `ChunkManager._seam_normalize_and_redraw()` (cross-chunk border normalization and redraw after mining)
- Debug-only direct writes in `scenes/world/game_world_debug.gd`
- Debug-only direct writes in `ChunkManager.ensure_underground_pocket()`
- `forbidden writes`:
- Direct callers must not treat `Chunk.try_mine_at()` or debug helpers as safe end-to-end orchestration points.
- Mining logic must not redefine mineability or open-tile semantics independently of current `TileGenData.TerrainType` values.
- Mining helpers below `ChunkManager.try_harvest_at_world()` must not be used as substitutes for the full topology / reveal / presentation invalidation chain.
- `emitted events / invalidation signals`:
- `ChunkManager._on_mountain_tile_changed()`
- `EventBus.mountain_tile_mined`
- Underground `UndergroundFogState.force_reveal()` and immediate fog apply on successful underground mining
- `MountainRoofSystem` and `MountainShadowSystem` both listen to `EventBus.mountain_tile_mined`
- `current violations / ambiguities / contract gaps`:
- `Chunk.try_mine_at()` mutates canonical terrain but does not itself emit events, patch topology, or update fog. The safe orchestration point is `ChunkManager.try_harvest_at_world()`, not the chunk method.
- ~~`Chunk.try_mine_at()` does not call `_refresh_open_neighbors()`. Neighboring `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` tiles are not re-normalized automatically, even inside the same chunk.~~ **resolved 2026-03-27**: `try_harvest_at_world()` now calls `_refresh_open_neighbors()` for same-chunk neighbors and `_refresh_open_tile()` for cross-chunk cardinal neighbors after mining.
- ~~Cross-chunk mining redraw is local-only. `_collect_mining_dirty_tiles()` returns only same-chunk tiles, so neighbor chunk visuals at seams can remain stale.~~ **resolved 2026-03-27**: `try_harvest_at_world()` now calls `_seam_normalize_and_redraw()` which detects edge-tile mining and redraws a 3-tile border strip in each affected loaded neighbor chunk. `_collect_mining_dirty_tiles()` still returns same-chunk tiles only; cross-chunk redraw is handled at the orchestration level.
- Debug direct writers bypass the normal event and invalidation chain.

## Layer: Topology

- `classification`: `derived`
- `owner`: `ChunkManager` owns the managed topology contract, and the native `MountainTopologyBuilder` owns the internal cache implementation when that path is enabled.
- `writers`: `ChunkManager` rebuild and incremental patch entrypoints update topology state; the native builder receives `set_chunk`, `remove_chunk`, `update_tile`, and `ensure_built` calls behind the same public API.
- `readers`: `MountainRoofSystem` reads `ChunkManager.query_local_underground_zone()`. No direct in-scope runtime reader was found for `get_mountain_key_at_tile()`, `get_mountain_tiles()`, or `get_mountain_open_tiles()`.
- `rebuild policy`: surface-only, loaded-bubble scoped; immediate incremental patch on successful mountain-tile mutation; deferred dirty rebuild on chunk load, unload, or explicit dirtying.
- `invariants`:
- `assert(_active_z == 0 or get_mountain_key_at_tile(tile_pos) == Vector2i(999999, 999999), "surface mountain topology must not be exposed on underground z levels")`
- `assert(terrain_type == TileGenData.TerrainType.ROCK or terrain_type == TileGenData.TerrainType.MINED_FLOOR or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE, "topology domain is ROCK + open mountain terrain")`
- `assert(open_tile_type == TileGenData.TerrainType.MINED_FLOOR or open_tile_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE, "topology open subset must be mined floor or mountain entrance")`
- `assert(connectivity_dirs == [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN], "mountain topology connectivity is cardinal only")`
- `assert(component_key == lexicographically_smallest_tile(component_tiles), "component key must be the lexicographically smallest tile in the component")`
- `assert(topology_scan_domain == _loaded_chunks, "runtime topology rebuilds operate on loaded chunks only")`
- `assert(zone_result.get("zone_kind", &"") == &"loaded_open_pocket", "query_local_underground_zone() currently returns a loaded_open_pocket product")`
- `assert(not traversal_hit_unloaded_neighbor or bool(zone_result.get("truncated", false)), "query_local_underground_zone() must mark truncated when traversal reaches an unloaded neighbor chunk")`
- `write operations`:
- `ChunkManager._mark_topology_dirty()`
- `ChunkManager._tick_topology()`
- `ChunkManager._start_topology_build()`
- `ChunkManager._process_topology_build_step()`
- `ChunkManager._rebuild_loaded_mountain_topology()`
- `ChunkManager._incremental_topology_patch()`
- Native builder calls: `set_chunk`, `remove_chunk`, `update_tile`, `ensure_built`
- `forbidden writes`:
- Topology code must not mutate canonical terrain bytes, loaded modification diffs, or unloaded saved overlays.
- Topology caches must not be treated as source of truth for unloaded world reads.
- Topology code must not redefine terrain semantics independently of current world-layer terrain values.
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
- `owner`: `MountainRoofSystem` owns surface local-zone reveal derivation, `UndergroundFogState` owns underground reveal state, and `ChunkManager` owns application of underground fog deltas to loaded chunks.
- `writers`: `MountainRoofSystem` writes the active local-zone derived state, `Chunk.set_revealed_local_cover_tiles()` writes per-chunk applied cover reveal, and `UndergroundFogState` plus `ChunkManager` write underground fog state and chunk fog application.
- `readers`: `Chunk` cover-layer and fog-layer presentation code; `MountainRoofSystem` public zone getters; no other in-scope gameplay reader was found for these reveal sets.
- `rebuild policy`: active-z dependent; surface reveal is loaded-bubble scoped and refresh-driven; underground fog is updated on fog ticks and immediately on successful underground mining; there is no unloaded fallback reveal path.
- `invariants`:
- `assert(ChunkManager.get_active_z_level() == 0 or not surface_local_reveal_running, "surface local mountain reveal only runs on z == 0")`
- `assert(seed_terrain == TileGenData.TerrainType.MINED_FLOOR or seed_terrain == TileGenData.TerrainType.MOUNTAIN_ENTRANCE, "surface local-zone seeding requires an open mountain tile")`
- `assert(revealed_cover_tiles == zone_tiles_plus_revealable_rock_halo, "surface revealed cover is derived from the loaded local zone plus revealable rock halo")`
- `assert(all_revealed_cover_tiles_are_local_to_chunk and cover_cells_are_erased_for_them, "Chunk._revealed_local_cover_tiles is a chunk-local erase mask for cover_layer")`
- `assert(shared_fog_state_instance_is_owned_by_chunk_manager, "underground fog uses one shared UndergroundFogState instance in ChunkManager")`
- `assert(fog_state_is_transient and fog_state_cleared_on_z_entry and not fog_state_persisted, "underground fog state is transient and cleared on z-level entry")`
- `assert(REVEAL_RADIUS == 5, "underground visible radius is currently fixed at 5")`
- `assert(terrain_type == TileGenData.TerrainType.MINED_FLOOR or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE or (terrain_type == TileGenData.TerrainType.ROCK and is_cave_edge_rock(local_tile)), "underground fog can only be removed for revealable tiles")`
- `write operations`:
- `MountainRoofSystem._request_refresh()`
- `MountainRoofSystem._refresh_active_local_zone()`
- `Chunk.set_revealed_local_cover_tiles()`
- `UndergroundFogState.update()`
- `UndergroundFogState.force_reveal()`
- `UndergroundFogState.clear()`
- `ChunkManager._apply_underground_fog_visible_tiles()`
- `ChunkManager._apply_underground_fog_discovered_tiles()`
- `forbidden writes`:
- Reveal code must not mutate canonical terrain, mining truth, or topology caches.
- Reveal code must not redefine what counts as `ROCK`, `MINED_FLOOR`, or `MOUNTAIN_ENTRANCE`; it only derives from those semantics.
- Reveal state must not be treated as authority for unloaded world continuity or unloaded terrain reads.
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
- `owner`: `Chunk` owns loaded chunk visual layers, and `MountainShadowSystem` owns surface mountain-shadow presentation state.
- `writers`: `Chunk` redraw and fog-application methods write TileMap state; `ChunkManager` schedules redraw and applies underground fog deltas; `MountainRoofSystem` drives cover erasure through chunk APIs; `MountainShadowSystem` writes shadow caches, textures, and sprites.
- `readers`: Godot rendering is the effective consumer. No in-scope simulation system was found that treats these presentation nodes as authority.
- `rebuild policy`: loaded-only and redraw-driven; underground fog presentation is applied to loaded chunks only; surface shadow presentation is surface-only and rebuilt when edge cache or sun-angle thresholds require it.
- `invariants`:
- `assert(terrain_layer_is_derived_from_chunk_data and cover_layer_is_derived_from_chunk_data and cliff_layer_is_derived_from_chunk_data, "terrain, cover, and cliff TileMap layers are derived outputs, not source of truth")`
- `assert(all_revealed_cover_tiles_are_erased_from_cover_layer, "surface cover reveal is applied by erasing cover_layer cells")`
- `assert(not _is_underground or roof_cover_system_disabled_for_chunk, "underground chunks do not use roof cover")`
- `assert(not _is_underground or fog_layer_initialized_to_unseen_for_all_loaded_tiles, "underground fog layer starts every loaded underground tile as UNSEEN")`
- `assert(active_z == 0 or not mountain_shadow_system_running, "MountainShadowSystem only runs in surface context")`
- `assert(shadow_inputs == {external_mountain_edges, sun_angle, shadow_length_factor}, "shadow sprites are built from cached edges plus current sun data")`
- `assert(shadow_edge_source_chunks == {target_chunk, north_chunk, south_chunk, east_chunk, west_chunk}, "shadow builds use the target chunk plus four cardinal neighbors as edge sources")`
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
- `forbidden writes`:
- Presentation code must not mutate canonical terrain, mining state, topology caches, or reveal source-of-truth state.
- Presentation nodes and layers must not be read as authority for gameplay, walkability, resource availability, or terrain semantics.
- Presentation systems must not redefine roof, fog, or mountain-edge semantics independently of the world / topology / reveal layers.
- `emitted events / invalidation signals`:
- `EventBus.chunk_loaded`
- `EventBus.chunk_unloaded`
- `EventBus.mountain_tile_mined`
- `EventBus.z_level_changed`
- Sun-angle threshold crossing in `MountainShadowSystem._process()`
- Player movement indirectly through reveal and fog systems
- `current violations / ambiguities / contract gaps`:
- ~~Cross-chunk mining redraw gaps leak directly into presentation: neighboring chunk cover, terrain, and cliff visuals are not refreshed by the current mining path.~~ **resolved 2026-03-27**: `_seam_normalize_and_redraw()` now redraws border strips in loaded neighbor chunks after seam mining.
- Presentation is loaded-chunk scoped. There is no presentation object for unloaded continuation even when world read APIs can still answer terrain queries.
- Debug direct writers can redraw visuals without going through the normal world -> mining -> topology -> reveal invalidation chain.

### Wall Atlas Selection (Presentation sublayer)

- `Что`: explicit code-side selection of the concrete rock-wall atlas tile and alternative tile ID for the terrain layer.
- `Где`: `core/systems/world/chunk.gd` in `_redraw_terrain_tile()`, `_surface_rock_visual_class()`, `_rock_visual_class()`, `_resolve_variant_atlas()`, and `_resolve_variant_alt_id()`. Atlas definitions and wall-variant layout live in `core/systems/world/chunk_tileset_factory.gd`.
- `Входные данные`: current tile `terrain_type`; cardinal neighbor terrain for surface rock; cardinal plus diagonal neighbor terrain for underground rock; global tile coordinates for hash-based wall variant and flip selection; cross-chunk neighbor reads go through `_get_neighbor_terrain()` and then `ChunkManager.get_terrain_type_at_global()`.
- `Определение "открытого" соседа`:
- Surface terrain wall shaping in `_surface_rock_visual_class()` uses a presentation-local open-neighbor predicate that treats `GROUND`, `WATER`, `SAND`, `GRASS`, `MINED_FLOOR`, and `MOUNTAIN_ENTRANCE` as open for wall-form selection. This does not change `_is_open_exterior()` or mining semantics.
- Underground terrain wall shaping in `_rock_visual_class()` uses `_is_open_for_visual()`, which currently treats every terrain type except `ROCK` as open for visual shaping.
- Surface cliff overlay selection in `_redraw_cliff_tile()` also uses `_is_open_exterior()`.
- Surface cover reveal helpers `_is_cave_edge_rock()` and `_is_surface_rock()` treat `MINED_FLOOR` and `MOUNTAIN_ENTRANCE` as open for revealability / edge detection, but that is separate from terrain atlas selection.
- `Инварианты`:
- `assert(terrain_type != TileGenData.TerrainType.ROCK or atlas_selected_explicitly_in_Chunk__redraw_terrain_tile, "rock atlas selection is explicit code, not implicit Godot autotile terrain behavior")`
- `assert(not surface_rock_has_cardinal_visual_open_neighbor or surface_rock_visual_class != ChunkTilesetFactory.WALL_INTERIOR, "surface rock with a cardinal visual-open neighbor must use a wall-form tile")`
- `assert(neighbor_terrain == TileGenData.TerrainType.ROCK or underground_neighbor_treated_as_open, "underground wall shaping treats every non-ROCK neighbor as open")`
- `assert(surface_alt_id == 0 and underground_alt_id_is_hash_selected, "surface disables wall flip alt IDs while underground enables them")`
- `forbidden writes`:
- Wall atlas selection must not mutate canonical terrain or redefine terrain semantics.
- Presentation tile choice must not be used as a substitute for topology, reveal, or mining truth.
- `current violations / ambiguities / contract gaps`:
- Surface and underground wall shaping do not share one common openness contract. Surface uses cardinal exterior-open checks only; underground uses cardinal plus diagonal non-`ROCK` openness.

## Postconditions: `generate chunk`

### Authoritative orchestration points

- Direct synchronous load path: `ChunkManager._load_chunk_for_z()`.
- Staged streaming load path: `_worker_generate()` -> `_staged_loading_phase1_create_chunk()` -> `_staged_loading_finalize()`.
- Surface generation path on direct surface cache miss: `WorldGenerator.build_chunk_content()` -> `ChunkBuildResult.to_native_data()` -> `Chunk.populate_native()`.
- Surface generation path on worker/staged surface cache miss: detached `ChunkContentBuilder.build_chunk_native_data()` or `WorldGenerator.build_chunk_native_data()` -> `Chunk.populate_native()`.
- Underground generation path: `ChunkManager._generate_solid_rock_chunk()` -> `Chunk.populate_native()`.

### Success path

- Requested chunk coordinates are canonicalized before generation or load.
- Surface load can reuse cached native payload and cached flora results. In that case the chunk is populated from cache instead of regenerating terrain.
- Surface chunk generation writes per-tile `terrain`, `height`, `variation`, and `biome` into native payload arrays. `flora_density_values` and `flora_modulation_values` are also generated in the payload for surface chunks.
- Current surface generation does not assign `MINED_FLOOR` or `MOUNTAIN_ENTRANCE`. Mountain boundary tiles generated by `SurfaceTerrainResolver._resolve_surface_terrain_sq()` remain `ROCK` even when adjacent to open exterior terrain.
- Chunk generation does not compute or store a wall-neighbor mask, autotile mask, or terrain peering metadata in canonical chunk data.
- `Chunk.populate_native()` installs native arrays, reapplies saved modifications through `_apply_saved_modifications()`, recalculates `_has_mountain`, resets cover visual state, and starts redraw.
- Saved modifications are replayed as direct tile writes. Modified neighbors are not re-normalized during load.
- Non-player streamed chunks begin progressive redraw through `_begin_progressive_redraw()`. Player chunk loads use immediate `_redraw_all()`. Boot loading can additionally force `complete_redraw_now()` after load.
- Boot loading later forces topology ready through native `ensure_built()` or `_ensure_topology_current()` before the loading sequence finishes.
- Surface flora presentation is derived after `populate_native()`: from cached flora, from `ChunkBuildResult`, or from native data, depending on load path and whether saved modifications exist.
- Underground chunks are marked with `set_underground(true)` before `populate_native()` and then receive a fog layer through `init_fog_layer()` after population.
- Once the chunk is inserted into `_loaded_chunks`, terrain reads and interaction paths use its loaded data even if progressive redraw is still in progress for that chunk.
- Surface topology is not built inside `Chunk.populate_native()`. After the chunk is attached and registered, `ChunkManager` invalidates topology through native `set_chunk(...); _native_topology_dirty = true` or `_mark_topology_dirty()`.
- `EventBus.chunk_loaded` is emitted after chunk registration and topology invalidation, not after topology readiness.

### Current non-guarantees

- Chunk generation/load does not auto-classify boundary `ROCK` as `MOUNTAIN_ENTRANCE`.
- Chunk generation/load does not compute or persist wall neighbor masks; wall forms are derived later during redraw from neighbor terrain reads.
- Reapplying saved modifications during load does not recompute neighboring `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` state.
- `EventBus.chunk_loaded` does not guarantee that surface topology is already ready. Surface topology may still be dirty or native-dirty until its rebuild path completes.

## Postconditions: `mine tile`

### Authoritative orchestration point

- The canonical safe entrypoint is `ChunkManager.try_harvest_at_world()`.
- The normal production call chain is `HarvestTileCommand -> ChunkManager.try_harvest_at_world() -> Chunk.try_mine_at()`.
- `Chunk.try_mine_at()` and debug direct mutation helpers are not safe orchestration points because they do not, by themselves, guarantee the full topology / reveal / presentation invalidation chain.

### Success path

- The target tile must have been loaded and `ROCK` at the time of the call.
- The target tile is rewritten to either `MINED_FLOOR` or `MOUNTAIN_ENTRANCE`.
- The changed terrain values are stored in the loaded chunk runtime state and written into `Chunk._modified_tiles`.
- The owning chunk is marked dirty.
- Same-chunk `3x3` dirty tiles are redrawn for terrain, cover, and cliff presentation.
- Same-chunk cardinal neighbors that are `MINED_FLOOR` or `MOUNTAIN_ENTRANCE` are re-normalized through `_refresh_open_neighbors()` and redrawn.
- If the mined tile is on a chunk edge, loaded neighbor chunks receive cross-chunk normalization for the direct cardinal neighbor and a 3-tile border strip redraw through `_seam_normalize_and_redraw()`. Cross-chunk normalization for tiles in unloaded neighbor chunks is not performed.
- Surface topology is updated immediately through `_on_mountain_tile_changed()` and may additionally be marked dirty for a background rebuild if split suspicion is detected.
- `EventBus.mountain_tile_mined` is emitted after the immediate topology patch path runs.
- If the active z-level is underground, the mined tile plus its 8-neighbor halo are force-revealed in `UndergroundFogState`, and revealable loaded tiles in that set have fog removed immediately.
- The operation returns `{ "item_id": ..., "amount": ... }` from world balance.

### No-op path

- If the target chunk is not loaded, the operation returns `{}`.
- If the target tile is not `ROCK`, the operation returns `{}`.
- In the no-op path, no mining event is emitted and no fog or topology update runs.

### Current non-guarantees

- Cross-chunk terrain normalization for tiles in **unloaded** neighbor chunks is not performed. The normalization will apply when those chunks load and their neighbors are read.

## Boundary Rules At Chunk Seams

- Tile and chunk identity are canonicalized through `WorldGenerator.canonicalize_tile()` and `canonicalize_chunk_coord()`. The world currently wraps on X and does not wrap on Y.
- Cross-chunk world reads use `Chunk._get_global_terrain()` -> `ChunkManager.get_terrain_type_at_global()`.
- Cross-chunk topology traversal uses cardinal neighbors only and only continues when the neighbor chunk is currently loaded.
- Cross-chunk local-zone traversal in `query_local_underground_zone()` also stops at unloaded chunks and reports `truncated = true`.
- `MountainRoofSystem` only reveals cover for chunks that are currently loaded.
- `MountainShadowSystem` edge detection can read across chunk seams through `get_terrain_type_at_global()`, including unloaded-neighbor fallback rules, but it still only builds sprites for loaded chunks.
- Surface terrain wall shaping can read cross-chunk neighbor terrain through unloaded fallbacks, because `_surface_rock_visual_class()` goes through `_get_neighbor_terrain()` and `ChunkManager.get_terrain_type_at_global()`.
- Mining at a chunk seam now refreshes neighbor-chunk open tiles and redraws neighbor-chunk border visuals for loaded neighbors through `ChunkManager._seam_normalize_and_redraw()`. Unloaded neighbor chunks are not normalized or redrawn at mining time.

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
- `ChunkManager.is_walkable_at_world()` delegates to `get_terrain_type_at_global()` and applies `_is_walkable_terrain()` to the result. This matches the authoritative terrain read-path for all cases including unloaded underground tiles.
- Surface terrain atlas selection for unloaded neighbors uses the same read ladder as `get_terrain_type_at_global()`. Underground wall atlas selection also uses that ladder, but underground unloaded fallback collapses to `ROCK`.

## Source Of Truth Vs Derived State

### Source of truth

- Surface generated base terrain: `WorldGenerator` / `ChunkContentBuilder` / `SurfaceTerrainResolver`
- Loaded terrain bytes: `Chunk._terrain_bytes`
- Loaded runtime modification diff: `Chunk._modified_tiles`
- Unloaded runtime modification diff: `ChunkManager._saved_chunk_data`
- Canonical active z selection: `ZLevelManager.current_z` via `ZLevelManager.change_level()`

### Derived state

- `Chunk._has_mountain`
- `ChunkManager._active_z` as downstream world-stack mirror of canonical z state
- Surface topology caches in `ChunkManager`
- `ChunkManager.query_local_underground_zone()` result
- `MountainRoofSystem` active local zone and cover-tile maps
- `UndergroundFogState` visible and revealed sets
- `MountainShadowSystem._edge_cache`
- Flora presentation inputs derived from `ChunkBuildResult` or native data

### Presentation-only state

- `Chunk` TileMap layers and flora/debug nodes
- Fog tiles written into `Chunk._fog_layer`
- Cover erasures applied to `Chunk._cover_layer`
- `MountainShadowSystem._shadow_sprites`
- Hash-based atlas variant and alternative tile selection

## Domain: Player & Survival

### Layer: Player actor / movement / combat / harvest

- `classification`: `canonical`
- `owner`: `core/entities/player/player.gd::Player`
- `writers`:
- `core/entities/player/player.gd::perform_harvest()`
- `core/entities/player/player.gd::perform_attack()`
- `core/entities/player/player.gd::collect_item()`
- `core/entities/player/player.gd::spend_scrap()`
- `core/entities/player/player.gd::spend_item()`
- `core/entities/player/player.gd::_on_died()`
- `core/entities/player/player.gd::handle_death()`
- Player state transitions in `core/entities/player/states/*.gd`
- `readers`:
- `core/entities/player/states/player_idle_state.gd::handle_input()`
- `core/entities/player/states/player_move_state.gd::handle_input()`
- `scenes/world/spawn_orchestrator.gd::_on_pickup_collected()`
- `scenes/world/game_world.gd::_canonicalize_player_world_position()`
- `core/autoloads/player_authority.gd::get_local_player()`
- `rebuild policy`: immediate, frame/input-driven runtime state; no deferred rebuild path
- `invariants`:
- `assert(_attack_timer >= 0.0, "player attack cooldown must never be negative at frame boundaries")`
- `assert(_harvest_timer >= 0.0, "player harvest cooldown must never be negative at frame boundaries")`
- `assert(can_attack() == (not _is_dead and _attack_timer <= 0.0 and _attack_area != null), "player attack readiness is derived from death state, cooldown, and attack area presence")`
- `assert(can_harvest() == (not _is_dead and _harvest_timer <= 0.0 and _chunk_manager != null and _inventory != null), "player harvest readiness is derived from death state, cooldown, chunk manager, and inventory presence")`
- `assert(not _is_dead or velocity == Vector2.ZERO, "dead player must not keep active movement velocity after death handling")`
- `write operations`:
- `Player.perform_harvest()`
- `Player.perform_attack()`
- `Player.collect_item()`
- `Player.collect_scrap()`
- `Player.spend_scrap()`
- `Player.spend_item()`
- `Player._on_died()`
- `Player.handle_death()`
- `forbidden writes`:
- External systems must not mutate `Player._attack_timer`, `Player._harvest_timer`, `Player._is_dead`, or `Player._state_machine` directly.
- External callers must not bypass `perform_attack()` / `perform_harvest()` by poking player state objects or private helpers.
- Player movement/blocking code must not redefine walkability semantics independently of `ChunkManager.is_walkable_at_world()`.
- `emitted events / invalidation signals`:
- `EventBus.item_collected`
- `EventBus.scrap_collected`
- `EventBus.player_died`
- `EventBus.game_over`
- `current violations / ambiguities / contract gaps`:
- `Player._on_speed_modifier_changed()` currently hardcodes `_speed_modifier = 1.0`, so oxygen slowdown does not actually affect movement speed.
- `Player.perform_harvest()` spends harvest cooldown before command success is known, so a failed command can still consume the cooldown window.

### Layer: Health / damage

- `classification`: `canonical`
- `owner`: host entity that owns `core/entities/components/health_component.gd::HealthComponent`
- `writers`:
- `core/entities/components/health_component.gd::take_damage()`
- `core/entities/components/health_component.gd::heal()`
- direct host setup in `core/entities/fauna/basic_enemy.gd::_ready()`
- direct host setup in `core/entities/structures/thermo_burner.gd::setup()`
- direct host setup in `core/entities/structures/ark_battery.gd::setup()`
- save/load writes in `core/autoloads/save_appliers.gd::apply_player()`
- save/load writes in `core/systems/building/building_persistence.gd::deserialize_walls()`
- `readers`:
- `core/entities/player/player.gd::_on_died()`
- `core/entities/player/player.gd::perform_attack()`
- `core/entities/fauna/basic_enemy.gd::_on_died()`
- `core/entities/fauna/basic_enemy.gd::_try_attack_target()`
- `core/systems/building/building_system.gd::_bind_building_health()`
- `core/autoloads/save_collectors.gd::collect_player()`
- `rebuild policy`: immediate writes; no rebuild layer
- `invariants`:
- `assert(max_health >= 0.0, "max_health must stay non-negative")`
- `assert(current_health >= 0.0 and current_health <= max_health, "current_health must stay within [0, max_health]")`
- `assert(current_health > 0.0 or died_signal_emitted_or_pending, "zero health must correspond to death handling")`
- `write operations`:
- `HealthComponent.take_damage()`
- `HealthComponent.heal()`
- direct load/setup assignments to `current_health` and `max_health`
- `forbidden writes`:
- External systems must not assign `current_health` or `max_health` directly on live entities unless they also own the load/setup boundary.
- Gameplay code must not emulate damage by skipping `take_damage()` because that bypasses `health_changed` / `died`.
- `emitted events / invalidation signals`:
- `HealthComponent.health_changed`
- `HealthComponent.died`
- `current violations / ambiguities / contract gaps`:
- `current_health` and `max_health` are public mutable fields, and several load/setup paths write them directly without re-emitting `health_changed`.
- `HealthComponent` has no component-level `save_state()` / `load_state()` API; persistence is fragmented across host-specific save helpers.

### Layer: Inventory runtime

- `classification`: `canonical`
- `owner`: `core/entities/components/inventory_component.gd::InventoryComponent`
- `writers`:
- `core/entities/components/inventory_component.gd::add_item()`
- `core/entities/components/inventory_component.gd::remove_item()`
- `core/entities/components/inventory_component.gd::load_state()`
- direct slot mutations in `scenes/ui/inventory/inventory_panel.gd::_on_slot_dropped()`
- direct slot mutations in `scenes/ui/inventory/inventory_panel.gd::_split_stack()`
- direct slot mutations in `scenes/ui/inventory/inventory_panel.gd::_sort_inventory()`
- direct slot mutations in `scenes/ui/inventory/inventory_panel.gd::_on_drop_outside()`
- `readers`:
- `core/entities/player/player.gd::collect_item()`
- `core/entities/player/player.gd::spend_scrap()`
- `core/entities/player/player.gd::spend_item()`
- `core/systems/crafting/crafting_system.gd::can_craft()`
- `core/systems/crafting/crafting_system.gd::execute_recipe()`
- `scenes/ui/inventory/inventory_panel.gd::_refresh()`
- `scenes/ui/crafting_panel.gd::_count_item_amount()`
- `rebuild policy`: immediate, slot-array writes; no rebuild layer
- `invariants`:
- `assert(slots.size() == capacity, "inventory must allocate exactly capacity slots")`
- `assert(for_all_slot in slots: for_all_slot.is_empty() or (for_all_slot.item != null and for_all_slot.amount > 0 and for_all_slot.amount <= for_all_slot.item.max_stack), "every non-empty inventory slot must hold a valid item stack within max_stack")`
- `assert(for_all_slot in slots: not for_all_slot.is_empty() or for_all_slot.amount == 0, "empty inventory slots must not keep positive amount")`
- `write operations`:
- `InventoryComponent.add_item()`
- `InventoryComponent.remove_item()`
- `InventoryComponent.load_state()`
- direct UI slot mutation paths in `InventoryPanel`
- `forbidden writes`:
- External systems must not mutate `InventoryComponent.slots` or `InventorySlot.item` / `InventorySlot.amount` directly.
- UI code must not become the de facto owner of split/swap/sort/drop semantics.
- `emitted events / invalidation signals`:
- `EventBus.inventory_updated`
- `current violations / ambiguities / contract gaps`:
- `InventoryPanel` directly mutates `InventoryComponent.slots` for swap, split, sort, equip handoff, and drop-outside flows instead of going through component-owned APIs.
- There is no authoritative public runtime API for move/split/sort/drop operations; current semantics live partly in UI code.

### Layer: Equipment runtime

- `classification`: `canonical`
- `owner`: `core/entities/components/equipment_component.gd::EquipmentComponent`
- `writers`:
- `core/entities/components/equipment_component.gd::equip()`
- `core/entities/components/equipment_component.gd::unequip()`
- `core/entities/components/equipment_component.gd::load_state()`
- orchestration writes in `scenes/ui/inventory/inventory_panel.gd::_try_equip_from_inventory()`
- orchestration writes in `scenes/ui/inventory/inventory_panel.gd::_on_equip_clicked()`
- `readers`:
- `scenes/ui/inventory/inventory_panel.gd::_refresh()`
- `scenes/ui/inventory/inventory_panel.gd::_on_equip_hovered()`
- `scenes/ui/inventory/equip_slot_ui.gd::set_equipped_item()`
- `rebuild policy`: immediate, slot-map writes; no rebuild layer
- `invariants`:
- `assert(_equipped.keys().size() == EquipmentSlotType.Slot.values().size(), "equipment map must track every declared equipment slot")`
- `assert(for_all_slot in _equipped.keys(): _equipped[for_all_slot] == null or int((_equipped[for_all_slot] as ItemData).equipment_slot) == int(for_all_slot), "equipped item must match declared equipment slot")`
- `assert(can_equip(slot, item) == (item != null and item.equipment_slot == slot), "equipment compatibility is currently a direct slot-id equality check")`
- `write operations`:
- `EquipmentComponent.equip()`
- `EquipmentComponent.unequip()`
- `EquipmentComponent.load_state()`
- `forbidden writes`:
- External systems must not mutate `EquipmentComponent._equipped` directly.
- Inventory/UI flows must not treat `equip()` as a substitute for full inventory + equipment orchestration unless they also handle inventory ownership explicitly.
- `emitted events / invalidation signals`:
- `EquipmentComponent.equipment_changed`
- `current violations / ambiguities / contract gaps`:
- Equipment state is not included in the current save/load flow, so equipped items do not have a canonical persisted path.
- Inventory/equipment handoff semantics currently live in `InventoryPanel`, not in an authoritative runtime orchestration API.

### Layer: Oxygen / survival

- `classification`: `canonical`
- `owner`: `core/systems/survival/oxygen_system.gd::OxygenSystem`
- `writers`:
- `core/systems/survival/oxygen_system.gd::_process()`
- `core/systems/survival/oxygen_system.gd::set_indoor()`
- `core/systems/survival/oxygen_system.gd::set_base_powered()`
- `core/systems/survival/oxygen_system.gd::load_state()`
- `core/systems/survival/oxygen_system.gd::_on_life_support_power_changed()`
- `readers`:
- `core/entities/player/player.gd::get_oxygen_system()`
- `core/entities/player/player.gd::_on_speed_modifier_changed()`
- `scenes/world/game_world.gd::_update_player_indoor_status()`
- `core/autoloads/save_collectors.gd::collect_player()`
- `rebuild policy`: immediate per-frame drain/refill; no deferred rebuild layer
- `invariants`:
- `assert(balance != null, "oxygen system requires SurvivalBalance")`
- `assert(_current_oxygen >= 0.0 and _current_oxygen <= balance.max_oxygen, "oxygen amount must stay within [0, max_oxygen]")`
- `assert(not _is_depleting or get_oxygen_percent() <= balance.low_oxygen_threshold, "depleting warning state must only be active below the low oxygen threshold")`
- `write operations`:
- `OxygenSystem.set_indoor()`
- `OxygenSystem.set_base_powered()`
- `OxygenSystem.load_state()`
- frame-driven `_update_oxygen()`
- `forbidden writes`:
- Other systems must not mutate `_current_oxygen`, `_is_indoor`, or `_is_base_powered` directly.
- Indoor semantics must not be redefined independently of `GameWorld` / room and mined-floor ownership rules.
- `emitted events / invalidation signals`:
- `EventBus.oxygen_changed`
- `EventBus.oxygen_depleting`
- `EventBus.player_entered_indoor`
- `EventBus.player_exited_indoor`
- `OxygenSystem.speed_modifier_changed`
- `current violations / ambiguities / contract gaps`:
- `OxygenSystem._on_rooms_recalculated()` is a no-op; the system relies on `GameWorld._update_player_indoor_status()` polling every frame to keep indoor state authoritative.
- There are two write paths for power context (`set_base_powered()` and `life_support_power_changed`), but no single explicit orchestration point documents which one owns runtime transitions.

### Layer: Base life support

- `classification`: `canonical`
- `owner`: `core/systems/survival/base_life_support.gd::BaseLifeSupport`
- `writers`:
- `core/systems/survival/base_life_support.gd::_ready()`
- `core/systems/survival/base_life_support.gd::_on_powered_changed()`
- `core/systems/survival/base_life_support.gd::_emit_state()`
- internal child writes through `PowerConsumerComponent.set_powered()`
- `readers`:
- `core/systems/survival/base_life_support.gd::is_powered()`
- `core/systems/survival/oxygen_system.gd::_on_life_support_power_changed()`
- `core/debug/runtime_validation_driver.gd::_prepare_power_validation()`
- `rebuild policy`: immediate event-driven state projection from the internal power consumer
- `invariants`:
- `assert(_consumer != null, "base life support must own one internal power consumer after _ready()")`
- `assert(_consumer == null or _consumer.priority == PowerConsumerComponent.Priority.CRITICAL, "life support consumer must stay CRITICAL priority")`
- `assert(is_powered() == (_consumer != null and _consumer.is_powered), "BaseLifeSupport.is_powered() is a direct projection of the internal consumer state")`
- `write operations`:
- `BaseLifeSupport._ready()`
- `BaseLifeSupport._on_powered_changed()`
- internal `PowerConsumerComponent.set_powered()`
- `forbidden writes`:
- External systems must not mutate the child `PowerConsumerComponent` directly as a substitute for `BaseLifeSupport` ownership.
- Consumers of life-support state must not emit `EventBus.life_support_power_changed` themselves.
- `emitted events / invalidation signals`:
- `EventBus.life_support_power_changed`
- `current violations / ambiguities / contract gaps`:
- `BaseLifeSupport` exposes only `is_powered()` publicly; demand and consumer ownership remain indirect through a child component that outside code can still reach and mutate.

## Domain: Structures & Economy

### Layer: Building placement / building runtime

- `classification`: `canonical`
- `owner`: `core/systems/building/building_system.gd::BuildingSystem`
- `writers`:
- `core/systems/building/building_system.gd::set_selected_building()`
- `core/systems/building/building_system.gd::place_selected_building_at()`
- `core/systems/building/building_system.gd::remove_building_at()`
- `core/systems/building/building_system.gd::load_state()`
- `core/systems/building/building_system.gd::_on_building_destroyed()`
- `core/systems/building/building_system.gd::_toggle_build_mode()`
- placement helpers in `core/systems/building/building_placement_service.gd`
- `readers`:
- `core/systems/building/building_system.gd::save_state()`
- `scenes/world/game_world.gd::_update_player_indoor_status()`
- `core/autoloads/save_collectors.gd::collect_buildings()`
- `scenes/ui/build/build_menu_panel.gd::get_selected()`
- `scenes/ui/power_ui.gd::_refresh_generators()`
- `rebuild policy`: immediate placement/removal writes; room topology invalidation is deferred dirty rebuild
- `invariants`:
- `assert(for_all_pos in walls.keys(): is_instance_valid(walls[for_all_pos]), "building grid must only point at live building nodes")`
- `assert(for_all_node in unique(walls.values()): node.get_meta("grid_origin") != null, "every placed building node must expose grid_origin metadata")`
- `assert(_placement_service != null and wall_container != null, "building runtime requires initialized placement service and wall container")`
- `write operations`:
- `BuildingSystem.place_selected_building_at()`
- `BuildingSystem.remove_building_at()`
- `BuildingSystem.load_state()`
- `BuildingSystem._on_building_destroyed()`
- `BuildingPlacementService.place_selected_at()`
- `BuildingPlacementService.remove_at()`
- `BuildingPlacementService.create_building_by_id()`
- `forbidden writes`:
- External systems must not mutate `BuildingSystem.walls` directly.
- Placement code must not bypass `BuildingSystem` by inserting/removing nodes in `wall_container` without updating `walls` and room invalidation.
- Build-mode presentation must not be treated as canonical building state.
- `emitted events / invalidation signals`:
- `EventBus.build_mode_changed`
- `EventBus.building_placed`
- `EventBus.building_removed`
- room invalidation through `BuildingSystem._mark_rooms_dirty()`
- `current violations / ambiguities / contract gaps`:
- `BuildingPlacementService.can_place_at()` only checks scrap and occupied tiles; it does not validate terrain type, walkability, z-context, or other world-placement constraints.
- `BuildingSystem.walls` is a public dictionary shared across placement and persistence helpers, so outside code can mutate canonical building occupancy without going through invalidation.

### Layer: Indoor room topology

- `classification`: `derived`
- `owner`: `core/systems/building/building_system.gd::BuildingSystem` with `core/systems/building/building_indoor_solver.gd::IndoorSolver`
- `writers`:
- `core/systems/building/building_system.gd::_mark_rooms_dirty()`
- `core/systems/building/building_system.gd::_room_recompute_tick()`
- `core/systems/building/building_system.gd::_begin_full_room_rebuild()`
- `core/systems/building/building_system.gd::_advance_full_room_rebuild()`
- `core/systems/building/building_system.gd::load_state()`
- `core/systems/building/building_indoor_solver.gd::recalculate()`
- `core/systems/building/building_indoor_solver.gd::solve_local_patch()`
- `readers`:
- `core/systems/building/building_system.gd::is_cell_indoor()`
- `scenes/world/game_world.gd::_update_player_indoor_status()`
- `core/systems/survival/oxygen_system.gd::_on_rooms_recalculated()`
- `rebuild policy`: deferred dirty rebuild via `FrameBudgetDispatcher`; synchronous full rebuild on load/boot path
- `invariants`:
- `assert(for_all_cell in indoor_cells.keys(): not walls.has(for_all_cell), "indoor cells must never overlap occupied building cells")`
- `assert(has_pending_room_recompute() == (not _dirty_room_regions.is_empty() or not _full_room_rebuild_state.is_empty()), "pending room recompute flag is derived from dirty region or staged full rebuild state")`
- `assert(_indoor_solver.indoor_cells == indoor_cells or has_pending_room_recompute(), "solver snapshot and published indoor_cells must match when no recompute is pending")`
- `write operations`:
- `BuildingSystem._mark_rooms_dirty()`
- `BuildingSystem._room_recompute_tick()`
- `BuildingSystem._begin_full_room_rebuild()`
- `BuildingSystem._advance_full_room_rebuild()`
- `BuildingSystem.load_state()`
- `IndoorSolver.recalculate()`
- `IndoorSolver.solve_local_patch()`
- `forbidden writes`:
- External systems must not mutate `BuildingSystem.indoor_cells` or `IndoorSolver.indoor_cells` directly.
- Consumers must not treat room topology as source of truth for building placement or z-level semantics.
- `emitted events / invalidation signals`:
- `EventBus.rooms_recalculated`
- `FrameBudgetDispatcher` job `building.room_recompute`
- `current violations / ambiguities / contract gaps`:
- Indoor topology is keyed only by 2D grid coordinates and has no z-level dimension.
- `BuildingSystem.indoor_cells` is a public dictionary, so outside code can bypass solver ownership and corrupt derived room state.

### Layer: Power network

- `classification`: `canonical`
- `owner`: `core/systems/power/power_system.gd::PowerSystem`
- `writers`:
- `core/systems/power/power_system.gd::register_source()`
- `core/systems/power/power_system.gd::unregister_source()`
- `core/systems/power/power_system.gd::register_consumer()`
- `core/systems/power/power_system.gd::unregister_consumer()`
- `core/systems/power/power_system.gd::force_recalculate()`
- `core/systems/power/power_system.gd::_power_recompute_tick()`
- `core/entities/components/power_source_component.gd::set_condition()`
- `core/entities/components/power_source_component.gd::set_enabled()`
- `core/entities/components/power_source_component.gd::force_shutdown()`
- `core/entities/components/power_consumer_component.gd::set_demand()`
- `core/entities/components/power_consumer_component.gd::set_priority()`
- `core/entities/components/power_consumer_component.gd::set_powered()`
- `readers`:
- `core/systems/survival/base_life_support.gd::is_powered()`
- `scenes/ui/power_ui.gd::_on_power_changed()`
- `scenes/ui/power_ui.gd::_refresh_generators()`
- `core/debug/runtime_validation_driver.gd::_prepare_power_validation()`
- `rebuild policy`: deferred dirty rebuild via `FrameBudgetDispatcher` plus heartbeat-triggered invalidation
- `invariants`:
- `assert(total_supply >= 0.0 and total_demand >= 0.0, "power aggregates must stay non-negative")`
- `assert(not is_deficit or total_supply < total_demand, "deficit flag means supply is below demand")`
- `assert(is_deficit or total_supply >= total_demand, "non-deficit flag means supply covers demand")`
- `assert(_registered_sources.size() >= 0 and _registered_consumers.size() >= 0, "power registries must stay valid dictionaries of live components")`
- `write operations`:
- `PowerSystem.register_source()`
- `PowerSystem.unregister_source()`
- `PowerSystem.register_consumer()`
- `PowerSystem.unregister_consumer()`
- `PowerSystem.force_recalculate()`
- `PowerSourceComponent.set_condition()`
- `PowerSourceComponent.set_enabled()`
- `PowerSourceComponent.force_shutdown()`
- `PowerConsumerComponent.set_demand()`
- `PowerConsumerComponent.set_priority()`
- `forbidden writes`:
- External systems must not mutate `_registered_sources`, `_registered_consumers`, `total_supply`, `total_demand`, or `is_deficit` directly.
- Callers must not mutate `PowerSourceComponent.is_enabled`, `PowerSourceComponent.condition_multiplier`, `PowerConsumerComponent.demand`, or `PowerConsumerComponent.priority` directly on live components if they expect immediate recompute semantics.
- `emitted events / invalidation signals`:
- `EventBus.power_changed`
- `EventBus.power_deficit`
- `EventBus.power_restored`
- `PowerSourceComponent.output_changed`
- `PowerConsumerComponent.powered_changed`
- `PowerConsumerComponent.configuration_changed`
- `current violations / ambiguities / contract gaps`:
- Power source and consumer configuration fields are public, so direct assignment can bypass `output_changed` / `configuration_changed` and leave power state stale until a later dirty mark.
- `PowerSystem.save_state()` exposes only aggregate fields and is not the authoritative persistence shape for runtime power state, which actually lives across components and structure nodes.

## Domain: World Entities

### Layer: Spawn / pickup orchestration

- `classification`: `canonical`
- `owner`: `scenes/world/spawn_orchestrator.gd::SpawnOrchestrator`
- `writers`:
- `scenes/world/spawn_orchestrator.gd::setup()`
- `scenes/world/spawn_orchestrator.gd::spawn_initial_scrap()`
- `scenes/world/spawn_orchestrator.gd::load_pickups()`
- `scenes/world/spawn_orchestrator.gd::clear_pickups()`
- `scenes/world/spawn_orchestrator.gd::_update_enemy_spawning()`
- `scenes/world/spawn_orchestrator.gd::_spawn_enemy()`
- `scenes/world/spawn_orchestrator.gd::_on_enemy_killed()`
- `scenes/world/spawn_orchestrator.gd::_on_item_dropped()`
- `scenes/world/spawn_orchestrator.gd::_on_pickup_collected()`
- `readers`:
- `core/autoloads/save_collectors.gd::collect_world()`
- `core/autoloads/save_appliers.gd::apply_world()`
- `scenes/world/game_world.gd::_bootstrap_session_state()`
- `scenes/world/game_world.gd::_canonicalize_player_world_position()`
- `rebuild policy`: immediate, timer/frame-driven runtime orchestration; pickup display sync runs every frame
- `invariants`:
- `assert(_enemy_count >= 0, "enemy count must never be negative")`
- `assert(for_all_pickup in _pickup_container.get_children(): pickup_has_item_id_and_amount_or_is_transient, "world pickups must carry item_id and amount metadata")`
- `assert(not (WorldGenerator and WorldGenerator._is_initialized) or saved_pickup_positions_are_canonicalized, "pickup logical positions must be canonical when world wrapping is active")`
- `write operations`:
- `SpawnOrchestrator.spawn_initial_scrap()`
- `SpawnOrchestrator.load_pickups()`
- `SpawnOrchestrator.clear_pickups()`
- `SpawnOrchestrator._spawn_enemy()`
- `SpawnOrchestrator._on_enemy_killed()`
- `SpawnOrchestrator._on_item_dropped()`
- `SpawnOrchestrator._on_pickup_collected()`
- `forbidden writes`:
- External systems must not mutate `_enemy_count`, `_spawn_timer`, or pickup metadata directly.
- Pickup persistence must not bypass `save_pickups()` / `load_pickups()` with ad hoc serialization.
- `emitted events / invalidation signals`:
- `EventBus.enemy_spawned`
- `EventBus.enemy_killed` (consumed)
- `EventBus.item_dropped` (consumed)
- `current violations / ambiguities / contract gaps`:
- `_enemy_spawning_enabled` has no writer in the current code path, so runtime enemy spawning is effectively disabled.
- Save/load currently persists pickups, but not live enemies or spawn timers, so hostile world state is not restored as a canonical session layer.

### Layer: Enemy AI / fauna runtime

- `classification`: `canonical`
- `owner`: `core/entities/fauna/basic_enemy.gd::BasicEnemy`
- `writers`:
- `core/entities/fauna/basic_enemy.gd::_update_scan()`
- `core/entities/fauna/basic_enemy.gd::_try_attack_target()`
- `core/entities/fauna/basic_enemy.gd::_on_time_changed()`
- `core/entities/fauna/basic_enemy.gd::_on_died()`
- `core/entities/fauna/basic_enemy.gd::handle_death()`
- `core/entities/fauna/basic_enemy.gd::begin_wander()`
- `core/entities/fauna/basic_enemy.gd::tick_wander()`
- `core/entities/fauna/basic_enemy.gd::clear_target()`
- state transitions in `core/entities/fauna/states/*.gd`
- `readers`:
- `core/entities/fauna/basic_enemy.gd::_check_collisions()`
- `core/entities/fauna/basic_enemy.gd::move_to_target()`
- `scenes/world/spawn_orchestrator.gd::_on_enemy_killed()`
- `core/debug/runtime_validation_driver.gd` enemy validation helpers
- `rebuild policy`: immediate physics-driven runtime state plus scan-interval refresh
- `invariants`:
- `assert(not _is_dead or (not _has_target and _attack_target == null), "dead enemies must not keep active targets")`
- `assert(_hearing_multiplier == 1.0 or _hearing_multiplier == 1.2 or _hearing_multiplier == 1.5, "enemy hearing multiplier is currently phase-based and discrete")`
- `assert(not has_attack_target() or _has_target, "attack target implies a tracked target state")`
- `write operations`:
- `BasicEnemy._update_scan()`
- `BasicEnemy._try_attack_target()`
- `BasicEnemy._on_time_changed()`
- `BasicEnemy._on_died()`
- `BasicEnemy.handle_death()`
- `BasicEnemy.begin_wander()`
- `BasicEnemy.tick_wander()`
- `BasicEnemy.clear_target()`
- `forbidden writes`:
- External systems must not mutate `_target_pos`, `_has_target`, `_attack_target`, `_wander_dir`, or `_state_machine` directly.
- Enemy AI must not redefine player or wall attack semantics outside `BasicEnemy`.
- `emitted events / invalidation signals`:
- `EventBus.enemy_killed`
- `EventBus.enemy_reached_wall`
- `EventBus.time_of_day_changed` (consumed)
- `current violations / ambiguities / contract gaps`:
- Enemy hearing scans `noise_sources` and the local player globally with no z-level filtering, so multi-z runtime can create cross-floor perception if entities coexist across floors.

### Layer: Noise / hearing input

- `classification`: `canonical`
- `owner`: owner node that contains `core/entities/components/noise_component.gd::NoiseComponent`
- `writers`:
- `core/entities/components/noise_component.gd::set_active()`
- host setup in `core/entities/structures/thermo_burner.gd::setup()`
- direct export-field writes on `noise_radius`, `noise_level`, `is_active`
- `readers`:
- `core/entities/fauna/basic_enemy.gd::_update_scan()`
- `core/entities/components/noise_component.gd::is_audible_at()`
- `rebuild policy`: immediate field writes; consumers observe changes on their next scan tick
- `invariants`:
- `assert(not is_active or noise_radius >= 0.0, "active noise source must not expose negative radius")`
- `assert(not is_active or noise_level >= 0.0, "active noise source must not expose negative noise level")`
- `assert(not is_active or get_noise_position() != null, "active noise source must resolve a world position")`
- `write operations`:
- `NoiseComponent.set_active()`
- direct host configuration during structure setup
- `forbidden writes`:
- External systems must not treat noise data as persisted world state; it is runtime-local to the owner entity.
- Callers must not expect immediate reactive fan-out from noise writes; there is no event bus for this layer.
- `emitted events / invalidation signals`:
- none
- `current violations / ambiguities / contract gaps`:
- Noise state has no emitted invalidation signal; enemy AI only notices changes on the next scan interval.

## Domain: Session & Time

### Layer: Z-level switching / stairs

- `classification`: `canonical`
- `owner`: `core/systems/world/z_level_manager.gd::ZLevelManager`, with `core/entities/structures/z_stairs.gd::ZStairs` as runtime trigger
- `writers`:
- `core/systems/world/z_level_manager.gd::change_level()`
- `core/autoloads/save_appliers.gd::apply_player()` via `change_level()`
- `core/entities/structures/z_stairs.gd::_on_body_entered()`
- `core/entities/structures/z_stairs.gd::_trigger_transition()`
- `readers`:
- `core/systems/world/z_level_manager.gd::get_current_z()`
- `scenes/world/game_world.gd::_on_z_level_changed()`
- `core/systems/daylight/daylight_system.gd::_resolve_current_z()`
- `core/entities/structures/z_stairs.gd::_on_z_level_changed()`
- `rebuild policy`: immediate; one authoritative z-change triggers downstream world/presentation sync
- `invariants`:
- `assert(current_z >= Z_MIN and current_z <= Z_MAX, "active z level must remain within declared bounds")`
- `assert(new_z != current_z_before_emit, "z_level_changed must only emit on real z transitions")`
- `assert(chunk_manager_active_z == current_z after downstream_sync, "ChunkManager._active_z must mirror canonical z after signal-driven world sync")`
- `assert(not monitoring or visible, "stairs monitoring must match current visible source_z context")`
- `write operations`:
- `ZLevelManager.change_level()`
- `ZStairs._trigger_transition()`
- `forbidden writes`:
- External systems must not assign `ZLevelManager.current_z` directly.
- External systems must not call `ChunkManager.set_active_z_level()` as a primary z-switch API; it is a downstream world-stack sink driven by `scenes/world/game_world.gd::_on_z_level_changed()`.
- Callers must not treat `ChunkManager.get_active_z_level()` as global z source of truth when `ZLevelManager` is available.
- `emitted events / invalidation signals`:
- `ZLevelManager.z_level_changed`
- `EventBus.z_level_changed`
- `current violations / ambiguities / contract gaps`:
- `ZLevelManager.current_z` is a public mutable field, so external code can bypass `change_level()` and skip event emission.
- `ChunkManager` still stores mirrored `_active_z`; bypass writes to canonical or sink paths can desync world-stack switching from canonical z ownership.
- `ZStairs` reaches into `GameWorld` to find `ZLevelManager` and `ZTransitionOverlay` directly instead of using a dedicated public transition API.

### Layer: Time / calendar / day-night

- `classification`: `canonical`
- `owner`: `core/autoloads/time_manager.gd::TimeManagerSingleton`
- `writers`:
- `core/autoloads/time_manager.gd::reset_for_new_game()`
- `core/autoloads/time_manager.gd::restore_persisted_state()`
- `core/autoloads/time_manager.gd::_process()`
- `core/autoloads/time_manager.gd::_apply_authoritative_time_state()`
- direct field writes in `scenes/world/game_world.gd::_pause_time_for_boot()`
- direct field writes in `scenes/ui/save_load_tab.gd::_on_load_pressed()`
- `readers`:
- `core/systems/daylight/daylight_system.gd::_resolve_context_color()`
- `core/systems/daylight/daylight_system.gd::_on_time_tick()`
- `core/entities/fauna/basic_enemy.gd::_on_time_changed()`
- `core/systems/game_stats.gd::_on_day_changed()`
- `scenes/ui/hud/hud_time_widget.gd::_on_hour_changed()`
- `rebuild policy`: immediate per-frame advance; no deferred rebuild
- `invariants`:
- `assert(balance != null, "time manager requires TimeBalance")`
- `assert(current_hour >= 0.0 and current_hour < float(balance.hours_per_day), "current hour must stay within the configured day range")`
- `assert(current_day >= 1, "current day starts from 1")`
- `assert(int(current_season) >= 0 and int(current_season) < Season.size(), "current season must stay within enum bounds")`
- `write operations`:
- `TimeManager.reset_for_new_game()`
- `TimeManager.restore_persisted_state()`
- frame-driven `_advance_time()`
- `forbidden writes`:
- External systems must not mutate `current_hour`, `current_day`, `current_season`, `is_paused`, or `time_scale` directly as a substitute for a documented API.
- Presentation systems must not redefine time-of-day phase semantics outside `TimeManager`.
- `emitted events / invalidation signals`:
- `EventBus.time_tick`
- `EventBus.hour_changed`
- `EventBus.time_of_day_changed`
- `EventBus.day_changed`
- `EventBus.season_changed`
- `current violations / ambiguities / contract gaps`:
- `TimeManager.is_paused` and `TimeManager.time_scale` are public mutable fields, and current callers write them directly because no public pause/resume API exists.

### Layer: Save / load orchestration

- `classification`: `canonical`
- `owner`: `core/autoloads/save_manager.gd::SaveManagerSingleton`
- `writers`:
- `core/autoloads/save_manager.gd::save_game()`
- `core/autoloads/save_manager.gd::load_game()`
- `core/autoloads/save_manager.gd::delete_save()`
- direct UI write to `pending_load_slot` in `scenes/ui/save_load_tab.gd::_on_load_pressed()`
- helper writes in `core/autoloads/save_collectors.gd`
- helper writes in `core/autoloads/save_appliers.gd`
- `readers`:
- `core/autoloads/save_manager.gd::get_save_list()`
- `core/autoloads/save_manager.gd::save_exists()`
- `scenes/world/game_world.gd::_consume_pending_load_slot()`
- `scenes/ui/save_load_tab.gd::_rebuild_slot_list()`
- `rebuild policy`: immediate orchestration; no deferred pipeline
- `invariants`:
- `assert(not is_busy or current_slot != "", "busy save manager must know the active slot")`
- `assert(successful_load_applies_world_then_chunk_overlay_then_time_then_buildings_then_player, "load_game() relies on the current apply order to rebuild runtime state correctly")`
- `assert(pending_load_slot == "" or pending_load_slot == current_slot or not is_busy, "pending load slot remains an explicit queued slot string, not hidden busy-state ownership")`
- `write operations`:
- `SaveManager.save_game()`
- `SaveManager.load_game()`
- `SaveManager.delete_save()`
- `SaveAppliers.apply_world()`
- `SaveAppliers.apply_chunk_data()`
- `SaveAppliers.apply_time()`
- `SaveAppliers.apply_buildings()`
- `SaveAppliers.apply_player()`
- `forbidden writes`:
- UI and scene code must not mutate `SaveManager.current_slot`, `SaveManager.is_busy`, or `SaveManager.pending_load_slot` directly.
- UI code must not bypass `SaveManager.get_save_list()` / `delete_save()` with direct filesystem logic.
- Helper layers must not redefine save schema outside `SaveCollectors` / `SaveAppliers`.
- `emitted events / invalidation signals`:
- `EventBus.save_requested`
- `EventBus.save_completed`
- `EventBus.load_completed`
- `current violations / ambiguities / contract gaps`:
- `SaveLoadTab` bypasses `SaveManager.get_save_list()` and `SaveManager.delete_save()` with direct file reads, recursive deletes, and direct `pending_load_slot` mutation.
- `SaveLoadTab._on_save_pressed()` ignores the boolean result of `SaveManager.save_game()` and always shows a success message when the method is present.

## Сводка текущих нарушений и contract gaps

| # | Слой | Нарушение | Severity | Симптом для игрока |
| --- | --- | --- | --- | --- |
| 1 | World | `Chunk.get_terrain_type_at()` возвращает `GROUND` для невалидного local index вместо fail-fast | medium | Ошибочный вызов может тихо маскироваться под открытую землю и давать неверные визуальные или gameplay-решения |
| 2 | World | `Chunk.populate_native()` молча сбрасывает несовпавшие `variation` / `biome` массивы | medium | После загрузки chunk может потерять вариативность поверхности или biome palette и выглядеть не так, как ожидалось |
| 3 | World | ~~`is_walkable_at_world()` для unloaded underground идёт через `WorldGenerator.is_walkable_at()`, а terrain fallback считает tile `ROCK`~~ **resolved 2026-03-27** | ~~high~~ | ~~Проверки проходимости и фактическое terrain-чтение могут расходиться на unloaded underground tiles~~ |
| 4 | World | `has_resource_at_world()` не имеет unloaded fallback | medium | Добываемый ресурс на unloaded tile не виден системам, пока chunk не подгрузится |
| 5 | World | `populate_native()` переигрывает сохранённые terrain-модификации без neighbor re-normalization | medium | Неконсистентный save diff может загрузить cave opening с устаревшим `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` состоянием |
| 6 | Mining | `Chunk.try_mine_at()` не является безопасной orchestration point | high | Любой обходной путь, который вызовет прямую мутацию, сможет выкопать tile без корректного обновления topology / reveal / visuals |
| 7 | Mining | ~~Текущий mining path не делает automatic open-tile re-normalization соседей~~ **resolved 2026-03-27** | ~~high~~ | ~~После раскопки соседние `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` tiles могут сохранить устаревшее состояние~~ |
| 8 | Mining | ~~Отсутствует cross-chunk redraw после mining~~ **resolved 2026-03-27** | ~~high~~ | ~~После копания на шве соседний chunk может оставаться визуально устаревшим~~ |
| 9 | Mining | Debug direct writers обходят normal invalidation chain | medium | Debug-операции могут оставлять мир в частично обновлённом состоянии |
| 10 | Topology | Topology loaded-bubble scoped, а не world-global | medium | Связность горы и open pocket обрывается на границе выгруженного мира |
| 11 | Topology | `_incremental_topology_patch()` использует эвристику split detection | high | После некоторых раскопок topology может временно отставать или неверно склеивать / разделять компоненты до full rebuild |
| 12 | Topology | Progressive rebuild не коммитит `*_by_chunk` topology maps | medium | Будущий chunk-scoped reader может получить неполные или пустые topology-структуры после progressive rebuild |
| 13 | Topology | Staging `*_by_chunk` словари существуют, но не участвуют в progressive flow | low | Код создаёт ложное впечатление, что chunk-scoped progressive rebuild уже поддержан |
| 14 | Reveal | `zone_kind` и `truncated` собираются, но почти не влияют на runtime behavior | medium | Игрок увидит обрыв reveal на границе подгрузки без специальной обработки или обратной связи |
| 15 | Reveal | Surface reveal loaded-bubble scoped | medium | Раскрытие локальной пещеры обрывается на unloaded boundary даже если pocket продолжается дальше |
| 16 | Reveal | `Chunk` одновременно держит `set_revealed_local_zone()` и `set_revealed_local_cover_tiles()` | low | Новый вызователь может выбрать не тот entrypoint и получить лишний слой преобразования или рассинхрон |
| 17 | Reveal | Underground fog shared across underground runtime and cleared on z change | medium | Исследованность underground не образует устойчивую непрерывную историю между разными underground floors / z-переходами |
| 18 | Presentation | ~~Cross-chunk mining redraw gap протекает прямо в presentation~~ **resolved 2026-03-27** (for loaded neighbor chunks) | ~~high~~ | ~~Игрок увидит, что соседняя стена / cover / cliff на границе чанка не обновилась после копания~~ |
| 19 | Presentation | Presentation существует только для loaded chunks | low | Продолжение мира вне loaded bubble не имеет visual object до стриминга, даже если terrain-query уже может ответить |
| 20 | Presentation | Debug direct writers могут перерисовать visuals вне world -> mining -> topology -> reveal chain | medium | Отладочное изменение может дать картинку, не совпадающую с реальным derived state |
| 21 | Wall Atlas Selection | Surface и underground wall shaping используют разные openness contracts и разные neighbor sets | medium | Одинаково выглядящая граница rock/open space может рисоваться по-разному на surface и underground |
| 22 | Player actor | `Player._on_speed_modifier_changed()` игнорирует модификатор O₂ и фиксирует `_speed_modifier = 1.0` | medium | Низкий кислород не замедляет игрока, хотя survival layer сообщает о штрафе |
| 23 | Player actor | `perform_harvest()` тратит cooldown до подтверждения успеха команды | medium | Неудачная попытка добычи может всё равно отправить игрока на откат действия |
| 24 | Health / damage | `HealthComponent` имеет публичные поля, а load/setup path пишет их напрямую без сигнала | medium | UI или логика, слушающая `health_changed`, может не увидеть восстановленное после загрузки здоровье |
| 25 | Inventory runtime | `InventoryPanel` напрямую мутирует `InventoryComponent.slots` для swap/split/sort/drop | high | Инвентарь можно изменить в обход owner-layer, что повышает риск рассинхрона между UI и runtime-логикой |
| 26 | Equipment runtime | Экипировка не входит в текущий save/load path | medium | После загрузки сохранения экипированные предметы пропадают или сбрасываются |
| 27 | Oxygen / survival | `OxygenSystem._on_rooms_recalculated()` пустой, indoor-state держится на scene-level polling из `GameWorld` | medium | Изменение комнат может отразиться на кислороде только через внешний glue path, а не через явный owner contract |
| 28 | Base life support | Authoritative consumer живёт во внутреннем child-ноде без отдельного public contract на мутацию demand/config | low | Сторонний код может залезть во внутренний consumer и изменить поведение жизнеобеспечения в обход owner-layer |
| 29 | Building runtime | `BuildingPlacementService.can_place_at()` не проверяет terrain/walkability/z-constraints | high | Постройку можно поставить в логически неподходящем месте |
| 30 | Building runtime | `BuildingSystem.walls` публичен и разделяется между несколькими helper paths | medium | Внешний код может испортить occupancy-map без корректного room/power invalidation chain |
| 31 | Indoor topology | Indoor room state keyed only by 2D grid and has no z dimension | low | Если строительство выйдет за surface-only контекст, комнаты разных уровней начнут алиаситься в одну сетку |
| 32 | Power network | Public power config fields можно менять в обход setter-ов и dirty invalidation | high | Баланс энергии и brownout-решения могут запаздывать или считаться по устаревшим данным |
| 33 | Power network | `PowerSystem.save_state()` выглядит как persistence API, хотя authoritative power state живёт в компонентах и структурах | low | Новый вызователь может сохранить/восстановить не ту форму состояния и получить ложный “успешный” результат |
| 34 | Spawn / pickup orchestration | `_enemy_spawning_enabled` нигде не включается | high | Новые враги не спавнятся вообще |
| 35 | Spawn / pickup orchestration | Save/load сохраняет pickups, но не врагов и не spawn timers | medium | После загрузки hostile population сбрасывается |
| 36 | Enemy AI / fauna | Сканирование игрока и noise sources не фильтруется по z-level | medium | Существо может реагировать на шум или игрока с другого уровня, если такие акторы одновременно живы |
| 37 | Noise / hearing input | Noise layer не эмитит invalidation signal, реакция идёт только на следующем scan tick | low | Реакция врагов на включение/выключение шумного объекта может ощущаться запаздывающей |
| 38 | Z-level switching | `ZLevelManager.current_z` публично мутируемый и может быть изменён в обход `change_level()`, что также рискует рассинхронизировать downstream mirror `ChunkManager._active_z` | medium | Смена уровня может не запустить синхронизацию мира, света и теней |
| 39 | Z-level switching | `ZStairs` напрямую ищет `GameWorld`, `ZLevelManager` и overlay в scene tree | low | Любой новый триггер перехода рискует скопировать internal glue и пропустить нужные side-effects |
| 40 | Time / calendar | `TimeManager.is_paused` и `time_scale` меняются напрямую из внешнего кода | medium | Время можно заморозить/ускорить в обход явного API и без централизованного контракта |
| 41 | Save / load orchestration | `SaveLoadTab` обходит `SaveManager` при listing/delete/load-request orchestration | high | UI и canonical save-layer могут разойтись по поведению и error handling |
| 42 | Save / load orchestration | `SaveLoadTab._on_save_pressed()` не проверяет результат `SaveManager.save_game()` | medium | Игрок может увидеть “сохранено”, хотя запись не удалась |

## Out Of Scope / Follow-up

- Save serialization and on-disk shape in `chunk_save_system.gd`, `save_collectors.gd`, and `save_appliers.gd`
- Command routing and player interaction details outside the mining entrypoint, including `harvest_tile_command.gd` and `player.gd`
- Lighting systems outside mountain-shadow presentation, including daylight and darkness systems
- Debug-only validation and mutation paths such as `runtime_validation_driver.gd` and `game_world_debug.gd`

## Minimal Debug Validators To Add Later

- Validate that chunk generation never emits `MINED_FLOOR` or `MOUNTAIN_ENTRANCE` on the surface generation path.
- Validate that `chunk_loaded` does not get treated as topology-ready by any world-stack caller.
- Validate that mining a seam tile updates open-tile classification consistently on both sides of the chunk boundary.
- Validate that seam mining redraws both the source chunk and any affected neighbor chunks.
- Validate that `get_terrain_type_at_global()` and loaded chunk local reads agree for every loaded tile, including wrapped X boundaries.
- Validate that unloaded underground walkability decisions match unloaded underground terrain fallback rules.
- Validate that saved modification replay on load preserves already-normalized `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` state or explicitly reports mismatch.
- Validate that surface wall atlas selection changes when a cardinal exterior-open neighbor appears.
- Validate that surface wall atlas selection does not accidentally treat `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` as exterior-open unless the contract is intentionally changed.
- Validate that `mountain_open_tiles_by_key` matches the set of loaded `MINED_FLOOR` and `MOUNTAIN_ENTRANCE` tiles after mining and after chunk streaming changes.
- Validate that `query_local_underground_zone()` reports `truncated = true` whenever traversal hits an unloaded continuation.
- Validate that revealed cover tiles are actually erased from `cover_layer` for every chunk in the active local zone.
- Validate that fog-visible and fog-discovered transitions only touch revealable underground tiles.
