---
title: World Data Contracts
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.3
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
- `ChunkManager.is_walkable_at_world()` falls back to `WorldGenerator.is_walkable_at()` when a chunk is not loaded, even on underground z-levels, while `get_terrain_type_at_global()` treats unloaded underground tiles as `ROCK`. Those read-path rules do not currently match.
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
- `assert(current_mining_path_classifies_only_the_mined_tile, "current code classifies the mined tile itself but does not automatically re-normalize neighboring open tiles")`
- `assert(_modified_tiles[local_tile] == {"terrain": new_type}, "loaded terrain mutations must be recorded as terrain-only diffs")`
- `assert(result.item_id == str(WorldGenerator.balance.rock_drop_item_id) and result.amount == WorldGenerator.balance.rock_drop_amount, "successful world harvest must return the configured rock drop payload")`
- `write operations`:
- `ChunkManager.try_harvest_at_world()`
- `Chunk.try_mine_at()`
- `Chunk._set_terrain_type()`
- `Chunk._refresh_open_neighbors()` (currently unused helper)
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
- `Chunk.try_mine_at()` does not call `_refresh_open_neighbors()`. Neighboring `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` tiles are not re-normalized automatically, even inside the same chunk.
- Cross-chunk mining redraw is local-only. `_collect_mining_dirty_tiles()` returns only same-chunk tiles, so neighbor chunk visuals at seams can remain stale.
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
- Cross-chunk mining redraw gaps leak directly into presentation: neighboring chunk cover, terrain, and cliff visuals are not refreshed by the current mining path.
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
- Surface topology is updated immediately through `_on_mountain_tile_changed()` and may additionally be marked dirty for a background rebuild if split suspicion is detected.
- `EventBus.mountain_tile_mined` is emitted after the immediate topology patch path runs.
- If the active z-level is underground, the mined tile plus its 8-neighbor halo are force-revealed in `UndergroundFogState`, and revealable loaded tiles in that set have fog removed immediately.
- The operation returns `{ "item_id": ..., "amount": ... }` from world balance.

### No-op path

- If the target chunk is not loaded, the operation returns `{}`.
- If the target tile is not `ROCK`, the operation returns `{}`.
- In the no-op path, no mining event is emitted and no fog or topology update runs.

### Current non-guarantees

- Neighboring `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` tiles are not guaranteed to be re-normalized by the current mining path.
- Cross-chunk redraw after mining is not guaranteed today.

## Boundary Rules At Chunk Seams

- Tile and chunk identity are canonicalized through `WorldGenerator.canonicalize_tile()` and `canonicalize_chunk_coord()`. The world currently wraps on X and does not wrap on Y.
- Cross-chunk world reads use `Chunk._get_global_terrain()` -> `ChunkManager.get_terrain_type_at_global()`.
- Cross-chunk topology traversal uses cardinal neighbors only and only continues when the neighbor chunk is currently loaded.
- Cross-chunk local-zone traversal in `query_local_underground_zone()` also stops at unloaded chunks and reports `truncated = true`.
- `MountainRoofSystem` only reveals cover for chunks that are currently loaded.
- `MountainShadowSystem` edge detection can read across chunk seams through `get_terrain_type_at_global()`, including unloaded-neighbor fallback rules, but it still only builds sprites for loaded chunks.
- Surface terrain wall shaping can read cross-chunk neighbor terrain through unloaded fallbacks, because `_surface_rock_visual_class()` goes through `_get_neighbor_terrain()` and `ChunkManager.get_terrain_type_at_global()`.
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
- Surface terrain atlas selection for unloaded neighbors uses the same read ladder as `get_terrain_type_at_global()`. Underground wall atlas selection also uses that ladder, but underground unloaded fallback collapses to `ROCK`.

## Source Of Truth Vs Derived State

### Source of truth

- Surface generated base terrain: `WorldGenerator` / `ChunkContentBuilder` / `SurfaceTerrainResolver`
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
- Flora presentation inputs derived from `ChunkBuildResult` or native data

### Presentation-only state

- `Chunk` TileMap layers and flora/debug nodes
- Fog tiles written into `Chunk._fog_layer`
- Cover erasures applied to `Chunk._cover_layer`
- `MountainShadowSystem._shadow_sprites`
- Hash-based atlas variant and alternative tile selection

## Сводка текущих нарушений и contract gaps

| # | Слой | Нарушение | Severity | Симптом для игрока |
| --- | --- | --- | --- | --- |
| 1 | World | `Chunk.get_terrain_type_at()` возвращает `GROUND` для невалидного local index вместо fail-fast | medium | Ошибочный вызов может тихо маскироваться под открытую землю и давать неверные визуальные или gameplay-решения |
| 2 | World | `Chunk.populate_native()` молча сбрасывает несовпавшие `variation` / `biome` массивы | medium | После загрузки chunk может потерять вариативность поверхности или biome palette и выглядеть не так, как ожидалось |
| 3 | World | `is_walkable_at_world()` для unloaded underground идёт через `WorldGenerator.is_walkable_at()`, а terrain fallback считает tile `ROCK` | high | Проверки проходимости и фактическое terrain-чтение могут расходиться на unloaded underground tiles |
| 4 | World | `has_resource_at_world()` не имеет unloaded fallback | medium | Добываемый ресурс на unloaded tile не виден системам, пока chunk не подгрузится |
| 5 | World | `populate_native()` переигрывает сохранённые terrain-модификации без neighbor re-normalization | medium | Неконсистентный save diff может загрузить cave opening с устаревшим `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` состоянием |
| 6 | Mining | `Chunk.try_mine_at()` не является безопасной orchestration point | high | Любой обходной путь, который вызовет прямую мутацию, сможет выкопать tile без корректного обновления topology / reveal / visuals |
| 7 | Mining | Текущий mining path не делает automatic open-tile re-normalization соседей | high | После раскопки соседние `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` tiles могут сохранить устаревшее состояние |
| 8 | Mining | Отсутствует cross-chunk redraw после mining | high | После копания на шве соседний chunk может оставаться визуально устаревшим |
| 9 | Mining | Debug direct writers обходят normal invalidation chain | medium | Debug-операции могут оставлять мир в частично обновлённом состоянии |
| 10 | Topology | Topology loaded-bubble scoped, а не world-global | medium | Связность горы и open pocket обрывается на границе выгруженного мира |
| 11 | Topology | `_incremental_topology_patch()` использует эвристику split detection | high | После некоторых раскопок topology может временно отставать или неверно склеивать / разделять компоненты до full rebuild |
| 12 | Topology | Progressive rebuild не коммитит `*_by_chunk` topology maps | medium | Будущий chunk-scoped reader может получить неполные или пустые topology-структуры после progressive rebuild |
| 13 | Topology | Staging `*_by_chunk` словари существуют, но не участвуют в progressive flow | low | Код создаёт ложное впечатление, что chunk-scoped progressive rebuild уже поддержан |
| 14 | Reveal | `zone_kind` и `truncated` собираются, но почти не влияют на runtime behavior | medium | Игрок увидит обрыв reveal на границе подгрузки без специальной обработки или обратной связи |
| 15 | Reveal | Surface reveal loaded-bubble scoped | medium | Раскрытие локальной пещеры обрывается на unloaded boundary даже если pocket продолжается дальше |
| 16 | Reveal | `Chunk` одновременно держит `set_revealed_local_zone()` и `set_revealed_local_cover_tiles()` | low | Новый вызователь может выбрать не тот entrypoint и получить лишний слой преобразования или рассинхрон |
| 17 | Reveal | Underground fog shared across underground runtime and cleared on z change | medium | Исследованность underground не образует устойчивую непрерывную историю между разными underground floors / z-переходами |
| 18 | Presentation | Cross-chunk mining redraw gap протекает прямо в presentation | high | Игрок увидит, что соседняя стена / cover / cliff на границе чанка не обновилась после копания |
| 19 | Presentation | Presentation существует только для loaded chunks | low | Продолжение мира вне loaded bubble не имеет visual object до стриминга, даже если terrain-query уже может ответить |
| 20 | Presentation | Debug direct writers могут перерисовать visuals вне world -> mining -> topology -> reveal chain | medium | Отладочное изменение может дать картинку, не совпадающую с реальным derived state |
| 21 | Wall Atlas Selection | Surface и underground wall shaping используют разные openness contracts и разные neighbor sets | medium | Одинаково выглядящая граница rock/open space может рисоваться по-разному на surface и underground |

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
