---
title: World Data Contracts
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.9
last_updated: 2026-04-13
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

This document records the current data contracts for the `world / feature definitions / mining / topology / reveal / presentation` runtime stack as it exists in code today.

It is intentionally descriptive, not aspirational.

It does not propose architecture changes, refactors, or optimizations.

This is the first runtime contract baseline for this stack.

`status: draft` here means the document may still expand in coverage. It does not make the document optional.

Until superseded, this document is mandatory reading for any iteration that touches the `world / feature definitions / mining / topology / reveal / presentation` stack.

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
| Feature / POI Definitions | `canonical` | `WorldFeatureRegistry` | boot-time registry load of immutable definition resources | `WorldFeatureRegistry` read APIs, `WorldGenerator` readiness gate, native `ChunkGenerator` initialization snapshot | boot-time load only, read-only during runtime |
| Feature Hook Decisions | `derived` | `WorldGenerator` generation pipeline | deterministic native hook decision compute from canonical generator context + immutable definition snapshot | native POI arbitration, chunk payload generation, debug inspectors | per-origin deterministic compute inside native `ChunkGenerator`, no persistence |
| POI Placement Decisions | `derived` | `WorldGenerator` generation pipeline | deterministic native POI arbitration from hook decisions + immutable POI definitions | chunk payload generation, future debug/materialization consumers | per-origin deterministic compute inside native `ChunkGenerator`, owner-only placement authority, no persistence |
| World Pre-pass | `canonical` | `WorldPrePass`, bootstrapped by `WorldGenerator` | boot-time coarse height / filled-height / eroded-height / flow-direction / accumulation / drainage / river-mask / river-width / river-distance / floodplain-strength / ridge-strength / mountain-mass / slope / rain-shadow / continentalness / tectonic spine-seed records / ridge-path graph / ridge spline samples + half-width profile / lake-mask / lake-record grids derived from seed + balance + planet sampler | `WorldGenerator` initialization, `WorldComputeContext` holder, future generator-side resolvers and samplers | boot-time compute only, deterministic rebuild, not persisted |
| World | `canonical` | `ChunkManager` runtime arbitration, `Chunk` loaded storage, `WorldGenerator` unloaded surface base | canonical terrain bytes and unloaded overlay | terrain/resource/walkability/presentation consumers | loaded + unloaded reads, immediate writes, generator fallback |
| Chunk Lifecycle | `canonical` / `publication-contract` | `ChunkManager` + chunk-local `Chunk` publication proof | loaded chunk install/unload, chunk visibility publication/revoke, terminal surface packet proof, publication-time pending border-debt baseline and diagnostic repeat signatures | `GameWorld`, `ChunkStreamingService`, `ChunkBootPipeline`, visual scheduler diagnostics | loaded-bubble scoped, runtime-only; publication diagnostics are cleared on unload/runtime clear and are not persisted |
| Surface Final Packet Envelope | `derived` / `publication-contract` | `ChunkContentBuilder` for emitted packet shape, `ChunkManager` publication-payload completion, `ChunkSurfacePayloadCache` for duplicated retained copies | build/stamp versioned terminal surface packet dictionaries, including publication-ready flora payloads, and cache validated duplicates | `WorldGenerator.build_chunk_native_data()`, `ChunkStreamingService`, `ChunkBootPipeline`, diagnostics | surface z=0 only, deterministic build output, cached runtime copies not persisted |
| Frontier Planning / Reserved Scheduling | `derived` | `TravelStateResolver`, `ViewEnvelopeResolver`, `FrontierPlanner`, and `FrontierScheduler`, coordinated by `ChunkStreamingService` | per-update travel/fixed hot-warm/frontier plan dictionaries, debug-only camera envelope diagnostics, lane-tagged runtime load queues, active generation lane metadata, reserved-capacity diagnostics | `ChunkStreamingService`, `ChunkDebugSystem`, F11 overlay, perf diagnostics | runtime-only, active-z scoped, recalculated on player chunk/motion updates, not persisted |
| Mining | `canonical` | `ChunkManager` orchestration, `Chunk` loaded mutation storage | loaded terrain mutation and mining-side invalidation entrypoint | topology, reveal, presentation, save collection | loaded-only mutation, immediate |
| Topology | `derived` | `ChunkTopologyService`, with mandatory native `MountainTopologyBuilder` worker compute for full rebuild snapshots | surface topology caches | `MountainRoofSystem` and topology getters | surface-only, loaded-bubble scoped, incremental patch + deferred dirty rebuild |
| Loaded Open-Pocket Query | `derived` | `ChunkManager`, with native `LoadedOpenPocketQuery` as the active-z loaded terrain mirror | active-z loaded-chunk terrain mirror for capped open-pocket queries | `ChunkManager.query_local_underground_zone()`, `MountainRoofSystem` | active-z loaded-only, rebuilt on z switch, incrementally updated on load/unload/mining, not persisted |
| Reveal | `derived` | `MountainRoofSystem`, `UndergroundFogState`, `ChunkManager` fog applier | local cover reveal and underground fog state | chunk cover/fog presentation and reveal getters | active-z dependent, loaded-bubble scoped, immediate/deferred hybrid |
| Visual Task Scheduling | `derived` | `ChunkVisualScheduler` | per-chunk visual task queues, dedupe/version state, worker-prepare state, scheduler telemetry containers | `ChunkManager` boot/runtime loops, instrumentation, `ChunkDebugSystem` snapshot assembly | loaded-bubble scoped, per-tick budgeted, not persisted |
| Surface Payload Cache | `derived` / `presentation-cache` | `ChunkSurfacePayloadCache` | duplicated generated terminal surface final packets plus flora payload/result cache entries | `ChunkStreamingService`, boot compute/apply helpers, chunk install preparation | surface z=0 only, bounded LRU, runtime cache only, not persisted |
| Seam Repair Queue | `derived` | `ChunkSeamService`, coordinated by `ChunkManager` | pending seam refresh tile queue and neighbor border-fix enqueue decisions | topology tick, visual scheduler, mining seam follow-up | loaded-neighbor only, small per-step queue drain, not persisted |
| Chunk Debug Overlay Snapshot | `derived` | `ChunkDebugSystem`, coordinated by `ChunkManager` | bounded per-player debug snapshot assembled from existing chunk/queue/readiness state plus bounded incident/trace correlations | `WorldChunkDebugOverlay`, debug inspection | active-z, bounded debug radius, read-only, not persisted |
| Runtime Diagnostic Timeline Buffer | `derived` | `WorldRuntimeDiagnosticLog` | bounded diagnostic event ring buffer with dedupe metadata and optional `trace_id` / `incident_id` correlation | `WorldChunkDebugOverlay`, debug inspection, validation tooling | transient, cooldown-deduped, not gameplay truth |
| F11 Chunk Debug Overlay Log File | `derived` / `debug-only` | `WorldChunkDebugOverlay` | per-process diagnostic `.log` artifact serialized from the bounded F11 snapshot | humans, agents, debug inspection | writes only while overlay is visible, overwritten on first F11 open per process, not save/load truth |
| F11 Chunk Incident Dump File | `derived` / `debug-only` | `WorldChunkDebugOverlay` | explicit on-demand incident dump serialized from one bounded snapshot and bounded trace buffers | humans, agents, debug inspection | written only on manual `Ctrl+F11`, may say `no_active_incident`, not save/load truth |
| Presentation | `presentation-only` | `Chunk`, `MountainShadowSystem`, `WorldFeatureDebugOverlay`, `WorldChunkDebugOverlay` | TileMap, shadow sprite, debug anchor-marker output, and debug chunk overlay drawing | Godot renderer, debug inspection | loaded-only/redraw-driven for world presentation; read-only snapshot-driven for debug overlay |
| Boot Readiness | `derived` | `ChunkBootPipeline` | per-chunk boot state tracking and aggregate gate flags | `GameWorld`, boot progress UI, instrumentation | boot-time only, not persisted |

## Scope

Observed files for this version:

- `core/autoloads/world_feature_registry.gd`
- `core/autoloads/world_generator.gd`
- `core/autoloads/event_bus.gd`
- `core/systems/commands/harvest_tile_command.gd`
- `core/systems/world/tile_gen_data.gd`
- `core/systems/world/chunk_build_result.gd`
- `core/systems/world/chunk_final_packet.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/world_compute_context.gd`
- `core/systems/world/world_pre_pass.gd`
- `core/systems/world/world_feature_hook_resolver.gd`
- `core/systems/world/world_poi_resolver.gd`
- `core/systems/world/chunk_tileset_factory.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/travel_state_resolver.gd`
- `core/systems/world/view_envelope_resolver.gd`
- `core/systems/world/frontier_planner.gd`
- `core/systems/world/frontier_scheduler.gd`
- `core/systems/world/underground_transition_coordinator.gd`
- `core/systems/world/chunk_streaming_service.gd`
- `core/systems/world/chunk_visual_scheduler.gd`
- `core/systems/world/chunk_surface_payload_cache.gd`
- `core/systems/world/chunk_seam_service.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_visual_kernel.gd`
- `core/systems/world/chunk_debug_renderer.gd`
- `core/systems/world/chunk_fog_presenter.gd`
- `core/systems/world/chunk_flora_presenter.gd`
- `core/systems/world/world_feature_debug_overlay.gd`
- `core/debug/world_chunk_debug_overlay.gd`
- `core/debug/world_runtime_diagnostic_log.gd`
- `core/autoloads/world_perf_monitor.gd`
- `core/systems/world/surface_terrain_resolver.gd`
- `core/systems/world/underground_fog_state.gd`
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `scenes/world/game_world.gd`
- `data/world/features/feature_hook_data.gd`
- `data/world/features/poi_definition.gd`

## Current Source Of Truth Summary

- Feature hook and POI definition truth lives in `WorldFeatureRegistry` and is loaded from registry-backed resources before world initialization.
- Feature hook decisions are derived inside native `ChunkGenerator` from canonical generator context plus immutable registry-backed definitions exported during `WorldGenerator` initialization; they are not loaded-world or presentation truth.
- POI placement decisions are derived inside native `ChunkGenerator` from hook decisions plus immutable POI definitions; canonical anchor ownership and arbitration order are computed before any payload/materialization step.
- `WorldGenerator.build_chunk_native_data()` emits the deterministic `feature_and_poi_payload` directly from native chunk generation, and `WorldGenerator.build_chunk_content()` hydrates `ChunkBuildResult` from that same authoritative native packet. Owner chunks carry the authoritative baseline placement records. Only `build_chunk_native_data()` stamps the versioned `frontier_surface_final_packet` envelope consumed by player-reachable surface runtime install/cache boundaries, and the surface path must fail closed instead of emitting an empty placeholder or recomputing feature/POI truth in GDScript.
- `WorldFeatureDebugOverlay` consumes cached copies of already-built `feature_and_poi_payload` records as a debug-only presentation proof; disabling that overlay does not change placement truth.
- `WorldPrePass` owns boot-time coarse-grid prepass state (`_height_grid`, `_filled_height_grid`, `_flow_dir_grid`, `_accumulation_grid`, `_drainage_grid`, `_river_mask_grid`, `_river_width_grid`, `_river_distance_grid`, `_floodplain_strength_grid`, `_ridge_strength_grid`, `_mountain_mass_grid`, `_eroded_height_grid`, `_slope_grid`, `_rain_shadow_grid`, `_continentalness_grid`, `_spine_seeds`, `_ridge_paths`, `_lake_mask`, `_lake_records`) derived from the initialized `PlanetSampler` plus `WorldGenBalance`; each `RidgePath` now carries the raw coarse-grid polyline plus internal `spline_samples` (stored in wrap-local continuous X space for seam-safe smoothing) and `spline_half_widths`.
- `WorldGenerator.initialize_world()` or the staged `begin_initialize_world_async()` -> `complete_pending_initialize_world()` flow computes `WorldPrePass` before `WorldComputeContext` creation and publishes one read-only snapshot for the requested seed into runtime state.
- `WorldPrePass.sample()` / `get_grid_value()` expose `height`, normalized `drainage`, `river_width`, `river_distance`, normalized `floodplain_strength`, normalized `ridge_strength`, normalized `mountain_mass`, normalized `slope`, normalized `rain_shadow`, and normalized `continentalness`. The published `river_width` / `river_distance` pair is the single visible hydrology handoff for both river corridors and qualifying lake basins; raw lake records and `lake_mask` remain internal-only outside those curated APIs. `WorldComputeContext.sample_prepass_channels()` packages the normalized `drainage`, `slope`, `rain_shadow`, and `continentalness` subset into a lightweight runtime-safe container for consumers that should not traffic in channel-name strings. Filled-height, eroded-height, flow-direction, accumulation internals, river mask, spine-seed, ridge-graph, raw ridge spline data, and lake data remain internal-only outside those curated APIs.
- `WorldComputeContext.sample_structure_context()` now builds `WorldStructureContext` from that published pre-pass snapshot: `ridge_strength`, `mountain_mass`, `floodplain_strength`, `river_distance`, and `river_width` come directly from `WorldPrePass`, while runtime `river_strength` is derived as a continuous width-and-proximity semantic from those sampled hydrology metrics, including lake-fed basins that were folded into the same published river channels. `mountain_mass` is the broader massif-fill companion to `ridge_strength`, not just a second copy of the ridge core; `river_strength` must clamp to zero when sampled `river_width` is absent; runtime terrain consumers read the same pre-pass-driven river corridor and mountain-support semantics instead of legacy band/noise structure sampling.
- `WorldComputeContext.resolve_biome()` now samples typed `WorldPrePassChannels` and passes them into `BiomeResolver`, so causal biome scoring consumes the curated pre-pass facade rather than reading `WorldPrePass` internals directly.
- Public `WorldGenerator.resolve_biome()` preserves its caller-facing signature but delegates to `WorldComputeContext.resolve_biome()`, so runtime biome reads no longer bypass the pre-pass-powered authoritative path.
- Surface base terrain for unloaded tiles comes from `WorldGenerator` through `build_chunk_native_data()`, `build_chunk_content()`, and `get_terrain_type_fast()`.
- Loaded chunk terrain truth lives in `Chunk._terrain_bytes`.
- Loaded chunk runtime modifications live in `Chunk._modified_tiles`.
- Unloaded chunk runtime modifications live in `ChunkManager._saved_chunk_data`.
- `ChunkManager.get_terrain_type_at_global()` is the current read arbiter that resolves loaded data first, then saved modifications, then generator fallback, with special underground handling.
- Underground unloaded tiles are currently treated as solid `ROCK` by `ChunkManager.get_terrain_type_at_global()`.
- Current surface chunk generation resolves canonical terrain as `GROUND`, `WATER`, `SAND`, or `ROCK`. `MINED_FLOOR` and `MOUNTAIN_ENTRANCE` are runtime mutation results, not generator outputs.
- Surface chunk payload `variation` bytes are presentation-only overlay markers. In addition to biome-local subzones, they may now carry polar overlay ids (`polar_ice`, `polar_scorched`, `polar_salt_flat`, `polar_dry_riverbed`) without mutating canonical terrain ownership or unloaded walkability truth.
- Mountain topology caches are derived from currently loaded surface chunks only.
- `ChunkTopologyService` owns the validated native topology builder handle, dirty/converged runtime state, and the load/unload/mining mutation bridge into `MountainTopologyBuilder`; `ChunkManager` remains the public facade plus lifecycle/mutation coordinator that forwards into that service.
- Surface local mountain reveal state is derived from the current loaded open pocket around the player.
- Underground fog state is transient reveal state, shared by the active underground runtime, and not persisted.
- `ChunkBootPipeline` owns boot readiness flags, boot compute/apply queues, boot metrics, and runtime handoff state for the startup bubble; `ChunkManager.boot_load_initial_chunks()` remains the public boot entrypoint and lifecycle coordinator around that internal owner.
- Visual task queues, queue latency metrics, invalidation versions, worker visual-compute state, and the bounded scheduler drain loop are runtime-only state owned by `ChunkVisualScheduler`; `ChunkManager` remains the public/lifecycle coordinator, enqueue/invalidation source, and bounded tick caller.
- Runtime streaming queue relevance/pruning, worker generation handoff, staged install handoff, and unload routing are owned by `ChunkStreamingService`; `ChunkManager` remains the world-facing facade plus the single final install commit/save/topology coordination path via `_finalize_chunk_install()` and related owner helpers. After R4, runtime streaming requests are built from `FrontierPlanner` output, tagged into `frontier_critical`, `camera_visible_support`, or `background` lanes by `FrontierScheduler`, and non-critical lanes cannot consume the reserved frontier worker slot.
- Surface payload reuse for generated surface chunks is owned by `ChunkSurfacePayloadCache`; it stores duplicated native payload arrays plus flora payload/result cache entries and is cleared on teardown, not persisted.
- Seam refresh queueing, neighbor border enqueue logic, and mining-side seam follow-up repair are owned by `ChunkSeamService`; `ChunkManager` keeps the mining entrypoint and topology tick orchestration but no longer owns the mutable seam refresh queue.
- Bounded forensic incidents, trace contexts, visual-task debug metadata, and bounded overlay snapshot assembly are debug-only derived runtime behavior owned by `ChunkDebugSystem`; `ChunkManager` exposes the public entrypoint and forwards narrow debug API calls only.
- `ChunkManager.get_chunk_debug_overlay_snapshot()` forwards to `ChunkDebugSystem.build_overlay_snapshot()`, which assembles a bounded active-z diagnostic snapshot around `_player_chunk` by reading chunk lifecycle/queue/readiness state plus bounded incident/trace/task metadata, but never requests, unloads, generates, or publishes chunks.
- `WorldRuntimeDiagnosticLog` owns a transient bounded timeline buffer for human-readable Russian diagnostic summaries plus structured technical event records; optional `trace_id` / `incident_id` correlation remains diagnostic-only and is not gameplay state or persistence.
- `WorldChunkDebugOverlay` owns the derived `user://debug/f11_chunk_overlay.log` artifact; it serializes the already-built overlay snapshot only while F11 is visible and never becomes save/load or gameplay truth.
- `WorldChunkDebugOverlay` also owns explicit incident dump artifacts under `user://debug/f11_chunk_incident_<timestamp>.log`; the dump serializes one already-built bounded snapshot plus bounded trace buffers and must not trigger world work.
- Rock atlas selection is explicit code in `Chunk`; current rendering does not rely on Godot TileSet terrain peering or autotile rules.
- TileMap layers, ground elevation face overlays, fog cells, cover erasures, cliff overlays, and mountain shadow sprites are presentation outputs, not world truth.

## Layer: Feature / POI Definitions

- `classification`: `canonical`
- `owner`: `WorldFeatureRegistry` owns the registry-backed catalog of feature hook and POI definitions loaded at boot.
- `writers`: authored `.tres` resources under `data/world/features`; `WorldFeatureRegistry._load_base_definitions()` and its private registration helpers.
- `readers`: `WorldFeatureRegistry.get_feature_by_id()`, `get_all_feature_hooks()`, `get_poi_by_id()`, and `get_all_pois()`; `WorldGenerator.initialize_world()` / `begin_initialize_world_async()` readiness guard; future generator-side feature/POI resolvers.
- `rebuild policy`: boot-time load only; definitions are duplicated into registry-owned runtime instances and stay read-only for gameplay/runtime generation. Any invalid, duplicate, or unsupported definition aborts the load, clears the runtime snapshot, and leaves the registry not ready.
- `invariants`:
- `assert(feature_id != &"" and String(feature_id).contains(":"), "feature hook ids must be non-empty and namespaced in the runtime registry")`
- `assert(poi_id != &"" and String(poi_id).contains(":"), "poi ids must be non-empty and namespaced in the runtime registry")`
- `assert(WorldFeatureRegistry.is_ready(), "feature/poi definition registry must finish boot loading before world initialization")`
- `assert(WorldFeatureRegistry.get_all_feature_hooks().size() >= 1 and WorldFeatureRegistry.get_all_pois().size() >= 1, "baseline registry content must include at least one feature and one poi definition")`
- `assert(any invalid_or_duplicate_or_unsupported_definition => not WorldFeatureRegistry.is_ready(), "registry readiness must fail closed on invalid content")`
- `assert(not WorldFeatureRegistry.is_ready() => WorldFeatureRegistry.get_all_feature_hooks().is_empty() and WorldFeatureRegistry.get_all_pois().is_empty(), "failed registry load must not expose a partial runtime snapshot")`
- `assert(for_all_poi in WorldFeatureRegistry.get_all_pois(): for_all_poi.has_explicit_anchor_offset(), "iteration 7 baseline requires explicit poi anchor_offset")`
- `assert(for_all_poi in WorldFeatureRegistry.get_all_pois(): for_all_poi.has_explicit_priority(), "iteration 7 baseline requires explicit poi priority")`
- `write operations`:
- `WorldFeatureRegistry._load_base_definitions()`
- `WorldFeatureRegistry._load_definitions_from_directory()`
- `WorldFeatureRegistry._register_feature()`
- `WorldFeatureRegistry._register_poi()`
- `forbidden writes`:
- Runtime gameplay, chunk lifecycle, mining, topology, reveal, and presentation code must not mutate registry-backed feature or POI definitions.
- Generator build paths must not direct-load feature or POI resources from `res://data/world/features`; registry reads are the only sanctioned runtime path.
- Feature / POI definition resources must not be lazy-loaded during chunk generation.
- Worker-thread and detached builder compute paths must not access `WorldFeatureRegistry` autoload or any scene-tree node directly; they must receive an immutable POI/feature snapshot at builder initialization time on the main thread.
- `emitted events / invalidation signals`:
- none; readiness is established by boot-time load completion and consumed by `WorldGenerator.initialize_world()` or the staged async begin/complete flow before runtime publication
- `current violations / ambiguities / contract gaps`:
- No public mutation or mod-loading API exists yet for this catalog; that remains deferred until the dedicated extension-layer iteration.

## Layer: Feature Hook Decisions

- `classification`: `derived`
- `owner`: `WorldGenerator` generation pipeline owns feature-hook decision compute; native `ChunkGenerator` is the only writer path.
- `writers`: native `ChunkGenerator.generate_chunk()` internal feature-hook resolution using canonical generator context plus immutable feature-hook definitions exported at initialization.
- `readers`: native POI arbitration, chunk payload build integration, debug/validation tooling.
- `rebuild policy`: deterministic per-origin compute only; no persistence, no chunk-local authority, no presentation back-write.
- `invariants`:
- `assert(same_seed_and_candidate_origin => same hook decision set, "feature-hook resolution must be deterministic for a canonical origin")`
- `assert(hook_decisions_depend_only_on_canonical_generator_context_and_definition_catalog, "feature-hook resolution must stay unloaded-safe and registry-backed")`
- `assert(feature_hook_decisions_are_sorted_by_explicit_stable_order, "hook decision ordering must not depend on resource load order")`
- `assert(chunk_edge_evaluation_uses_canonical_origin_only, "neighboring chunk builds must resolve identical hook decisions for the same canonical origin")`
- `write operations`:
- native `ChunkGenerator.generate_chunk()` internal feature-hook resolution helpers
- `WorldGenerator.build_chunk_native_data()` / `build_chunk_content()` as packet/hydration consumers only
- `forbidden writes`:
- `Chunk`, `ChunkManager`, mining, topology, reveal, and presentation systems must not author or mutate feature-hook decisions.
- Feature-hook compute must not mutate terrain answers, structure context, biome results, or local variation outputs while evaluating eligibility.
- Feature-hook compute must not read `ChunkManager`, `Chunk`, topology caches, reveal state, underground fog, or presentation objects as hidden inputs.
- `emitted events / invalidation signals`:
- none; decisions are derived synchronously from canonical generator context when queried.
- `current violations / ambiguities / contract gaps`:
- Feature-hook decision truth remains internal-only to native chunk generation; external/runtime consumers read serialized feature records only through `feature_and_poi_payload` on existing chunk build outputs.

## Layer: POI Placement Decisions

- `classification`: `derived`
- `owner`: `WorldGenerator` generation pipeline owns deterministic POI placement arbitration; native `ChunkGenerator` is the only writer path.
- `writers`: native `ChunkGenerator.generate_chunk()` internal POI arbitration helpers using canonical hook decisions plus immutable POI definitions.
- `readers`: chunk payload build integration, future debug/materialization consumers.
- `rebuild policy`: deterministic per-origin compute only; no deferred queue, no second-pass arbitration, no persistence.
- `invariants`:
- `assert(each_canonical_anchor_produces_zero_or_one_final_placement, "single baseline exclusive slot is enforced per anchor")`
- `assert(anchor_tile == candidate_origin + anchor_offset, "anchor ownership is explicit and deterministic")`
- `assert(owner_chunk == canonical_chunk_containing(anchor_tile), "placement ownership is derived from anchor tile, not load order")`
- `assert(competing_valid_pois_at_same_anchor_are_resolved_by_priority_then_hash_then_lexicographic_id, "arbitration order must stay fixed")`
- `assert(footprint_tiles_are_canonical_world_tiles_sorted_deterministically, "downstream payload export must not depend on load order")`
- `write operations`:
- native `ChunkGenerator.generate_chunk()` internal POI arbitration helpers
- `WorldGenerator.build_chunk_native_data()` / `build_chunk_content()` as packet/hydration consumers only
- `forbidden writes`:
- `Chunk`, `ChunkManager`, mining, topology, reveal, and presentation systems must not author or mutate POI placement decisions.
- POI placement compute must not use loaded runtime diffs, topology caches, reveal state, underground fog, or presentation objects as hidden inputs.
- POI placement compute must not introduce deferred placement queues, second-pass arbitration, or non-owner secondary authority in the baseline.
- `emitted events / invalidation signals`:
- none; placements are rebuilt synchronously from deterministic generator inputs when queried.
- `current violations / ambiguities / contract gaps`:
- Placement decisions remain internal-only; baseline owner-only payload serialization exists, but non-owner chunk projection/materialization is still out of scope.

## Layer: World Pre-pass

- `classification`: `canonical`
- `owner`: `WorldPrePass` owns the deterministic coarse-grid prepass channels built at boot; `WorldGenerator` is responsible only for lifecycle/orchestration (`initialize_world()` synchronous path or `begin_initialize_world_async()` -> `complete_pending_initialize_world()` staged path computes it, then hands the read-only reference into `WorldComputeContext`). Optional native `WorldPrePassKernels` helpers may execute pure-data inner loops for that owner, but they do not become a second published writer or source of truth.
- `writers`: `WorldPrePass.compute()` samples canonical height from `PlanetSampler`, runs Y-boundary priority flood over the coarse grid, derives D8 flow directions over the filled surface, computes latitude-shaped flow accumulation with thaw-banded glacial melt and temperature-scaled downstream evaporation, normalizes a drainage read channel from accumulation, extracts thresholded river cells and river widths, integrates qualifying lake basins back into the same published hydrology handoff by seeding `_river_mask_grid`, `_river_width_grid`, and `_river_distance_grid` for those basins, propagates a nearest-river distance field, expands river reach into a normalized floodplain-strength field, selects deterministic tectonic spine seed records from coarse height plus ruggedness with a latitude-band distribution guard before global heap fill, grows deterministic main and branch ridge polylines from those seeds, smooths each ridge into wrap-aware spline samples with per-sample half-width profile, rasterizes those splines into a normalized ridge-strength field, derives a normalized `mountain_mass` field as broader massif-fill support from local ridge neighborhood strength plus height/ruggedness gates, applies the internal erosion proxy over filled / accumulation / ridge / river inputs, derives a normalized `slope` field from the maximum 8-neighbor gradient over `eroded-height`, transports sampler moisture along the prevailing wind direction to derive a normalized `rain_shadow` field from positive eroded-height gradients, derives a normalized `continentalness` field from the distance to sea-level coarse cells and Y-edge water boundaries, and authors `_height_grid`, `_filled_height_grid`, `_flow_dir_grid`, `_accumulation_grid`, `_drainage_grid`, `_river_mask_grid`, `_river_width_grid`, `_river_distance_grid`, `_floodplain_strength_grid`, `_ridge_strength_grid`, `_mountain_mass_grid`, `_eroded_height_grid`, `_slope_grid`, `_rain_shadow_grid`, `_continentalness_grid`, `_spine_seeds`, `_ridge_paths`, `_lake_mask`, and `_lake_records`. When native helpers are enabled, `compute_priority_flood`, `compute_lake_records`, `compute_flow_directions`, `compute_flow_accumulation`, `compute_floodplain_strength`, `compute_floodplain_deposition`, `compute_slope_grid`, `compute_rain_shadow`, and `compute_ridge_strength_grid` remain pure-data implementation details invoked by `WorldPrePass.compute()`; publish ownership and fallback semantics stay with `WorldPrePass`.
- `readers`: `WorldGenerator.initialize_world()` boot sequence or the staged `begin_initialize_world_async()` / `complete_pending_initialize_world()` publish path, `WorldComputeContext.get_world_pre_pass()`, `WorldComputeContext.sample_prepass_channels()`, `WorldComputeContext.sample_structure_context()`, `WorldComputeContext.resolve_biome()` / `BiomeResolver` via typed `WorldPrePassChannels`, public `WorldGenerator.resolve_biome()` through that same compute-context path, `WorldLab`, and the native chunk-generation bridge via the immutable pre-pass snapshot serialized into `ChunkGenerator.initialize()`. Runtime world/chunk/mining/topology/reveal/presentation systems still do not read mutable `WorldPrePass` internals directly.
- `rebuild policy`: computed during `initialize_world()` or detached during `begin_initialize_world_async()` and published during `complete_pending_initialize_world()` before compute-context publication; deterministic from seed + canonical coarse-grid coordinates + the runtime `WorldGenBalance` snapshot. Runtime initialization does not validate landmarks, mutate thresholds, or search neighboring seeds before publication. The layer is not persisted to save data.
- `invariants`:
- `assert(_height_grid.size() == grid_width * grid_height, "prepass coarse height grid must cover the entire configured coarse grid")`
- `assert(_filled_height_grid.size() == _height_grid.size(), "filled-height grid must stay index-aligned with the coarse height grid")`
- `assert(_flow_dir_grid.size() == _height_grid.size(), "flow-direction grid must stay index-aligned with the coarse height grid")`
- `assert(_accumulation_grid.size() == _height_grid.size(), "accumulation grid must stay index-aligned with the coarse height grid")`
- `assert(_drainage_grid.size() == _height_grid.size(), "drainage grid must stay index-aligned with the coarse height grid")`
- `assert(_river_mask_grid.size() == _height_grid.size(), "river mask grid must stay index-aligned with the coarse height grid")`
- `assert(_river_width_grid.size() == _height_grid.size(), "river width grid must stay index-aligned with the coarse height grid")`
- `assert(_river_distance_grid.size() == _height_grid.size(), "river distance grid must stay index-aligned with the coarse height grid")`
- `assert(_floodplain_strength_grid.size() == _height_grid.size(), "floodplain strength grid must stay index-aligned with the coarse height grid")`
- `assert(_ridge_strength_grid.size() == _height_grid.size(), "ridge strength grid must stay index-aligned with the coarse height grid")`
- `assert(_mountain_mass_grid.size() == _height_grid.size(), "mountain mass grid must stay index-aligned with the coarse height grid")`
- `assert(_eroded_height_grid.size() == _height_grid.size(), "eroded-height grid must stay index-aligned with the coarse height grid")`
- `assert(_slope_grid.size() == _height_grid.size(), "slope grid must stay index-aligned with the coarse height grid")`
- `assert(_rain_shadow_grid.size() == _height_grid.size(), "rain shadow grid must stay index-aligned with the coarse height grid")`
- `assert(_continentalness_grid.size() == _height_grid.size(), "continentalness grid must stay index-aligned with the coarse height grid")`
- `assert(_lake_mask.size() == _height_grid.size(), "lake mask must stay index-aligned with the coarse height grid")`
- `assert(_spine_seeds.size() <= prepass_target_spine_count, "tectonic spine seed selection must never exceed the configured target count")`
- `assert(for_all_path in _ridge_paths: path.points.size() >= 2, "ridge graph paths must contain at least two coarse-grid points")`
- `assert(for_all_cell in coarse_grid: _filled_height_grid[cell] >= _height_grid[cell], "priority flood must never lower source height values")`
- `assert(native helper success or fallback still publishes the same WorldPrePass-owned coarse-grid channels, "native pre-pass helpers must not create an alternate published hydrology or structure truth")`
- `assert(for_all_cell in coarse_grid: _flow_dir_grid[cell] in [0, 1, 2, 3, 4, 5, 6, 7, 255], "flow-direction grid uses D8 encoding with 255 reserved for sink/edge outlets")`
- `assert(for_all_cell in coarse_grid where cell.y == 0 or cell.y == grid_height - 1: _flow_dir_grid[cell] == 255, "Y-edge coarse cells remain terminal drainage outlets")`
- `assert(for_all_cell in coarse_grid: _accumulation_grid[cell] >= 0.0, "flow accumulation must stay non-negative even after latitude evaporation")`
- `assert(for_all_cell in coarse_grid: _drainage_grid[cell] >= 0.0 and _drainage_grid[cell] <= 1.0, "drainage read channel must stay normalized to [0,1]")`
- `assert(for_all_cell in coarse_grid: _river_mask_grid[cell] in [0, 1], "river mask uses binary coarse-grid membership")`
- `assert(for_all_cell in coarse_grid where _river_mask_grid[cell] == 1: _river_width_grid[cell] >= prepass_river_base_width, "river cells must resolve to at least the configured base width")`
- `assert(for_all_cell in coarse_grid: _river_distance_grid[cell] >= 0.0, "nearest-river distance field must stay non-negative")`
- `assert(for_all_cell in coarse_grid where _lake_mask[cell] > 0: _river_width_grid[cell] >= prepass_river_base_width, "qualifying lake basins must seed visible hydrology width through the published river channels")`
- `assert(for_all_cell in coarse_grid: _floodplain_strength_grid[cell] >= 0.0 and _floodplain_strength_grid[cell] <= 1.0, "floodplain strength must stay normalized to [0,1]")`
- `assert(for_all_cell in coarse_grid where _river_mask_grid[cell] == 1: _floodplain_strength_grid[cell] == 1.0, "river cells must seed floodplain strength at full intensity")`
- `assert(for_all_cell in coarse_grid: _ridge_strength_grid[cell] >= 0.0 and _ridge_strength_grid[cell] <= 1.0, "ridge strength field must stay normalized to [0,1]")`
- `assert(for_all_cell in coarse_grid: _mountain_mass_grid[cell] >= 0.0 and _mountain_mass_grid[cell] <= 1.0, "mountain mass field must stay normalized to [0,1]")`
- `assert(for_all_cell in coarse_grid: _eroded_height_grid[cell] >= 0.0 and _eroded_height_grid[cell] <= 1.0, "erosion proxy height must stay normalized to [0,1]")`
- `assert(for_all_cell in coarse_grid: _slope_grid[cell] >= 0.0 and _slope_grid[cell] <= 1.0, "slope field must stay normalized to [0,1]")`
- `assert(for_all_cell in coarse_grid: _rain_shadow_grid[cell] >= 0.0 and _rain_shadow_grid[cell] <= 1.0, "rain shadow field must stay normalized to [0,1]")`
- `assert(for_all_cell in coarse_grid: _continentalness_grid[cell] >= 0.0 and _continentalness_grid[cell] <= 1.0, "continentalness field must stay normalized to [0,1]")`
- `assert(for_all_cell in coarse_grid where _lake_mask[cell] > 0: absf(_eroded_height_grid[cell] - _filled_height_grid[cell]) <= 0.001, "erosion proxy must preserve filled lake surface cells")`
- `assert(for_all_lake in _lake_records: lake.id >= 1 and lake.id <= 32767, "lake ids written into PackedInt32Array mask must stay within the configured widened lake-mask range")`
- `assert(for_all_lake in _lake_records: lake.area_grid_cells == lake.grid_cells.size(), "lake records must report area consistent with their stored cell list")`
- `assert(for_all_lake in _lake_records: lake.inflow_accumulation >= 0.0, "lake inflow accumulation must stay non-negative")`
- `assert(for_all_seed in _spine_seeds: seed.position.x >= 0 and seed.position.x < grid_width and seed.position.y >= 0 and seed.position.y < grid_height, "spine seed positions must stay inside the coarse grid")`
- `assert(for_all_seed in _spine_seeds: seed.strength >= 0.5 and seed.strength <= 1.0, "spine seed strength must stay normalized to the [0.5, 1.0] ridge seed range")`
- `assert(for_all_seed in _spine_seeds where seed.direction_bias != Vector2.ZERO: absf(seed.direction_bias.length() - 1.0) <= 0.001, "non-zero spine seed direction bias must stay normalized")`
- `assert(for_all_distinct_seed_pairs in _spine_seeds: wrapped_grid_distance(seed_a.position, seed_b.position) >= prepass_min_spine_distance_grid, "spine seeds must respect the configured coarse-grid Poisson spacing")`
- `assert(prepass_target_spine_count >= configured_latitude_band_count implies spine selection reserves the strongest still-valid candidate from each latitude band before unrestricted global fill, "spine seed selection must not let a few extreme-latitude maxima monopolize all seed slots")`
- `assert(for_all_main_path in _ridge_paths where not main_path.is_branch: main_path.points.size() <= prepass_max_ridge_length_grid + 1, "main ridge paths must respect the configured max coarse-grid length")`
- `assert(for_all_branch_path in _ridge_paths where branch_path.is_branch: branch_path.points.size() <= prepass_max_branch_length_grid + 1, "branch ridge paths must respect the configured branch max coarse-grid length")`
- `assert(for_all_point in _ridge_paths: point.x >= 0 and point.x < grid_width and point.y >= 0 and point.y < grid_height, "ridge path points must stay inside the coarse grid")`
- `assert(for_all_path in _ridge_paths: path.spline_samples.size() >= 2, "ridge spline smoothing must emit at least two samples per ridge path")`
- `assert(for_all_path in _ridge_paths: path.spline_half_widths.size() == path.spline_samples.size(), "ridge spline half-width profile must stay index-aligned with spline samples")`
- `assert(for_all_sample in _ridge_paths: sample.y >= 0.0 and sample.y <= grid_height - 1, "ridge spline sample Y coordinates must stay inside the latitude-bounded coarse band")`
- `assert(for_all_half_width in _ridge_paths: half_width > 0.0, "ridge spline half-width profile must stay strictly positive")`
- `assert(X-neighbors-wrap and Y-neighbors-clamp_to_prepass_band, "prepass connectivity keeps cylindrical X wrap and latitude-bounded Y domain")`
- `assert(WorldGenerator.initialize_world() or WorldGenerator.complete_pending_initialize_world() publishes only one computed pre-pass snapshot into runtime state for the requested seed, "runtime boot must not leak partial or alternate-seed pre-pass truth into runtime readers")`
- `assert(WorldComputeContext.sample_structure_context() derives structure truth only from the published pre-pass snapshot, "runtime structure context must not reintroduce legacy band/noise world truth beside WorldPrePass")`
- `assert(WorldComputeContext.sample_structure_context() emits river_strength > 0 only when sampled river_width > 0, "river semantics must not inflate dry tiles into authoritative river context")`
- `assert(WorldComputeContext.sample_structure_context() exposes mountain_mass as broader massif-fill support around local ridge neighborhoods rather than only ridge-core overlap, "runtime mountain semantics must preserve the pre-pass massif-fill signal consumed by script/native terrain classification")`
- `write operations`:
- `WorldPrePass.compute()`
- `forbidden writes`:
- `WorldComputeContext`, `WorldGenerator`, and future generator-side consumers must not mutate `_height_grid`, `_filled_height_grid`, `_accumulation_grid`, `_flow_dir_grid`, `_drainage_grid`, `_river_mask_grid`, `_river_width_grid`, `_river_distance_grid`, `_floodplain_strength_grid`, `_ridge_strength_grid`, `_mountain_mass_grid`, `_eroded_height_grid`, `_slope_grid`, `_rain_shadow_grid`, `_continentalness_grid`, `_spine_seeds`, `_ridge_paths`, `_lake_mask`, or `_lake_records` after publication, including `RidgePath.spline_samples` and `RidgePath.spline_half_widths`.
- Chunk/runtime world systems must not treat prepass grids as writable terrain state or mutate them in response to gameplay.
- `emitted events / invalidation signals`:
- none; the layer is published by `WorldGenerator.initialize_world()` or by the main-thread completion step in `WorldGenerator.complete_pending_initialize_world()`
- `current violations / ambiguities / contract gaps`:
- Filled-height, eroded-height, flow-direction, accumulation internals, river mask, spine-seed, ridge-graph, raw ridge spline state, and lake internals remain internal-only. The public read surface for this layer is now limited to `WorldPrePass.sample()`, `get_grid_value()`, plus the typed `WorldComputeContext.sample_prepass_channels()` / `sample_structure_context()` facades; any wider raw-channel or batch-lookup API remains out of scope until a dedicated contract is approved.

## Layer: World

- `classification`: `canonical`
- `owner`: `ChunkManager` owns runtime cross-state terrain arbitration, `Chunk` owns loaded chunk terrain storage, and `WorldGenerator` owns the generated surface base terrain used for unloaded fallback.
- `writers`: `WorldGenerator` and `ChunkContentBuilder` generate base chunk payloads; player-reachable surface payloads must use the native `ChunkGenerator` C++ path and fail closed if that path is unavailable or invalid, while underground solid-rock payloads remain owner-generated script data. `Chunk.populate_native()` installs chunk state; `Chunk._set_terrain_type()` and `Chunk.mark_tile_modified()` mutate loaded runtime terrain; `ChunkManager.set_saved_data()` and `ChunkManager._unload_chunk()` write the unloaded overlay.
- `readers`: `Chunk` terrain, cover, cliff, and fog drawing paths; `ChunkManager.get_terrain_type_at_global()`; `Player` resource targeting and movement checks through `ChunkManager`; `GameWorld` indoor fallback; `MountainShadowSystem` edge detection.
- `rebuild policy`: immediate writes; loaded chunk terrain is mutated in place; unloaded runtime changes are stored as overlay state and re-applied on load; cross-state reads are centralized through `ChunkManager.get_terrain_type_at_global()`.
- `invariants`:
- `assert(chunk_coord == WorldGenerator.canonicalize_chunk_coord(chunk_coord), "chunk coord must be canonical before chunk identity is established")`
- `assert(global_tile == WorldGenerator.canonicalize_tile(global_tile), "global tile reads must use canonical tile coordinates")`
- `assert(index == local.y * chunk_size + local.x, "chunk local indexing must be row-major")`
- `assert(native_arrays_copied_before_saved_modifications and saved_modifications_reapplied_after_native_copy, "populate_native must install native arrays before saved modifications are reapplied")`
- `assert(loaded_chunk or not saved_tile_state.has("terrain") or resolved_terrain == int(saved_tile_state["terrain"]), "saved terrain override must win for unloaded reads")`
- `assert(loaded_chunk or saved_tile_state.has("terrain") or active_z == 0 or resolved_terrain == TileGenData.TerrainType.ROCK, "unloaded underground fallback must be ROCK")`
- `assert(surface_runtime_install_paths_consume_versioned_surface_final_packet, "player-reachable surface runtime must install chunks only from ChunkContentBuilder.build_chunk_native_data() or cached duplicates of the same versioned packet envelope, not from structured ChunkBuildResult exports")`
- `assert(no_direct_sync_surface_load_path, "player-reachable surface runtime must not use ChunkStreamingService.load_chunk_for_z() to build native data, create a Chunk node, and finalize install in one main-thread path")`
- `assert(native_cpp_output_format_matches_surface_final_packet_builder_inputs, "ChunkGenerator C++ generate_chunk() output Dictionary must remain wire-compatible with the authoritative tile-array inputs expected by ChunkContentBuilder.build_chunk_native_data() before it merges packet metadata, feature/POI payload, and publication buffers.")`
- `assert(surface_native_visual_payload_arrays_are_aligned_when_present, "rock_visual_class, ground_face_atlas, cover_mask, cliff_overlay, variant_id, and alt_id must either all match tile_count or be treated as unavailable presentation cache")`
- `assert(surface_native_generation_fails_closed_when_native_generator_unavailable, "player-reachable surface generation must fail closed if ChunkGenerator C++ is unavailable; runtime must not fall back to legacy GDScript generation")`
- `assert(native_chunk_generator_requires_authoritative_prepass_snapshot, "ChunkGenerator.initialize() must fail closed when the serialized WorldPrePass snapshot is missing, malformed, or from a different seed; native generation must not fall back to legacy structure formulas or alternate world truth")`
- `assert(native_chunk_generator_requires_compact_native_request, "ChunkGenerator.generate_chunk() must fail closed unless ChunkContentBuilder provides compact request kind native_chunk_generation_request_v1 or an explicitly legacy debug authoritative input snapshot; normal runtime must not bridge per-tile channel arrays from GDScript")`
- `assert(native_chunk_payload_shape_validated_before_use, "ChunkContentBuilder validates native terrain/biome/ecotone array sizes before treating native payload as authoritative worker input")`
- `assert(native_chunk_payload_has_generation_source_provenance, "ChunkContentBuilder.build_chunk_native_data() stamps versioned surface final packet metadata, including generation_source, so proof tooling can detect unexpected non-native surface generation")`
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
- Native topology dirtying through `MountainTopologyBuilder.set_chunk()` / `remove_chunk()` on chunk load and unload
- `current violations / ambiguities / contract gaps`:
- ~~`Chunk.get_terrain_type_at()` returns `GROUND` on invalid local index instead of asserting or surfacing misuse.~~ **resolved 2026-03-28**: invalid local reads now raise `push_error` + `assert` and fall back to `ROCK` rather than silently masquerading as open ground.
- ~~`Chunk.populate_native()` silently drops mismatched `variation` and `biome` arrays by replacing them with empty arrays.~~ **resolved 2026-03-28**: native payload size mismatch now raises `push_error` + `assert` and normalizes arrays to deterministic default-filled buffers instead of silently dropping them.
- ~~`ChunkManager.is_walkable_at_world()` falls back to `WorldGenerator.is_walkable_at()` when a chunk is not loaded, even on underground z-levels, while `get_terrain_type_at_global()` treats unloaded underground tiles as `ROCK`. Those read-path rules do not currently match.~~ **resolved 2026-03-27**: `is_walkable_at_world()` now delegates to `get_terrain_type_at_global()` for all cases, matching the authoritative loaded → saved → underground-ROCK → surface-generator fallback chain.
- ~~`ChunkManager.has_resource_at_world()` has no unloaded fallback. For unloaded tiles it returns `false`, even though unloaded underground terrain is otherwise treated as solid rock by `get_terrain_type_at_global()`.~~ **resolved 2026-03-28**: `has_resource_at_world()` now delegates to `get_terrain_type_at_global()`, so unloaded underground reads observe the same `ROCK` fallback as the world-layer arbiter.
- ~~`Chunk.populate_native()` reapplies saved terrain modifications tile-by-tile through `_apply_saved_modifications()` and does not recompute neighboring open-tile state during load.~~ **resolved 2026-03-28**: after replaying saved terrain diffs, `populate_native()` now re-normalizes affected open tiles and their cardinal neighbors inside the loaded chunk before redraw starts.

## Layer: Chunk Lifecycle

- `classification`: `canonical` / `publication-contract`
- `owner`: `ChunkManager` owns loaded chunk install/unload orchestration, fresh-load hidden state, `Chunk.visible` publication/revoke decisions, boot progress notification for visual completion, and runtime diagnostics for publication churn. `Chunk` remains the chunk-local owner of `ChunkVisualState`, redraw phase, terminal surface packet proof, and `pending_border_dirty_count`; `ChunkSeamService` remains the owner that discovers and enqueues seam dirty tiles.
- `writers`: `Chunk.populate_native()` records terminal surface packet proof from the already-validated install payload; `ChunkManager._finalize_chunk_install_stage()`, `ChunkManager._sync_chunk_visibility_for_publication()`, `ChunkManager._try_finalize_chunk_visual_convergence()`, `ChunkManager._invalidate_chunk_visual_convergence()`, `ChunkManager._ensure_chunk_full_redraw_task()`, and `ChunkManager._ensure_chunk_border_fix_task()` coordinate publication state. The publication-time pending border-debt baseline and repeated-revoke signature are `ChunkManager` diagnostics only; they are updated on full publication/revoke and cleared on unload/runtime clear.
- `readers`: `GameWorld` boot handoff, `ChunkBootPipeline` readiness gates, `ChunkStreamingService` install/unload flow, `ChunkVisualScheduler` readiness telemetry, `ChunkDebugSystem`, `WorldRuntimeDiagnosticLog`, and `WorldPerfProbe`.
- `rebuild policy`: runtime-only and loaded-chunk scoped. Fresh chunks enter hidden and become visible only through terminal `FULL_READY`. A visible chunk may be revoked only when owner-observed `pending_border_dirty_count` has newly increased beyond the count captured at the previous full publication. Repeated revoke attempts without a changed chunk-local visual state emit diagnostic telemetry instead of silently expanding publication churn.
- `invariants`:
- `assert(fresh_loaded_chunks_enter_hidden_until_terminal_full_ready_publication, "fresh chunk nodes must not become visible before Chunk.is_full_redraw_ready()")`
- `assert(surface_full_ready_publication_requires_terminal_frontier_surface_final_packet, "surface chunks may not enter FULL_READY or visible publication unless Chunk.populate_native() captured a terminal frontier_surface_final_packet")`
- `assert(neighbor_visibility_revoke_requires_new_pending_border_fix_debt, "revoke must be caused by newly discovered border debt, not by boilerplate invalidation")`
- `assert(published_chunk_that_reaches_full_ready_does_not_re_enter_revoked_state_within_startup_bubble, "startup publication is terminal unless real new debt appears")`
- `assert(repeated_visibility_revoke_without_state_change_is_diagnostic_signal_only, "repeat revoke for the same chunk/signature must emit diagnostic_signal telemetry and must not be treated as a new root cause")`
- `write operations`:
- `ChunkManager._sync_chunk_visibility_for_publication()`
- `ChunkManager._try_finalize_chunk_visual_convergence()`
- `ChunkManager._invalidate_chunk_visual_convergence()`
- `ChunkManager._ensure_chunk_border_fix_task()`
- `ChunkManager._remove_native_loaded_open_pocket_query_chunk()` for publication diagnostic cleanup on unload
- `forbidden writes`:
- `ChunkSeamService` must not mutate `Chunk.visible` or publication baselines.
- `ChunkVisualScheduler` must not directly publish/revoke visibility; it may only expose readiness telemetry and task completion back to `ChunkManager`.
- Debug overlays and `WorldPerfProbe` must not repair visibility or mutate lifecycle state.
- `emitted events / invalidation signals`:
- `chunk_visible`
- `chunk_visibility_revoked`
- `chunk_visibility_revoke_short_circuited`
- `chunk_visibility_revoke_repeated_without_state_change`
- counters `chunk.visibility_revoke_without_new_border_debt_total` and `chunk.visibility_revoke_without_state_change_total`
- `current violations / ambiguities / contract gaps`:
- none in current Iteration 3 scope.

## Layer: Surface Final Packet Envelope

- `classification`: `derived` / `publication-contract`
- `owner`: `ChunkContentBuilder` owns the emitted `frontier_surface_final_packet` envelope and version metadata; `ChunkManager._complete_surface_final_packet_publication_payload()` owns terminal publication-payload completion for runtime/boot surface generation; `ChunkSurfacePayloadCache` may retain duplicated copies, but it must not mutate packet semantics.
- `writers`: `WorldGenerator.build_chunk_native_data()`, `ChunkContentBuilder.build_chunk_native_data()`, `ChunkFinalPacket.stamp_surface_packet_metadata()`, `ChunkManager._complete_surface_final_packet_publication_payload()`, and `ChunkSurfacePayloadCache.cache_native_payload()` for validated duplicate retention only.
- `readers`: `ChunkStreamingService.prepare_chunk_install_entry()`, `ChunkBootPipeline.compute_chunk_native_data()` / `apply_chunk_from_native_data()`, `ChunkManager._duplicate_native_data()`, `Chunk.populate_native()` terminal packet proof capture, `Chunk._can_publish_full_redraw_ready()`, and diagnostics.
- `rebuild policy`: surface z=0 only; deterministic for the same canonical chunk coord, world seed, and `generator_version`; cached runtime copies are duplicated and never persisted.
- `invariants`:
- `assert(packet_kind == "frontier_surface_final_packet" and packet_version == 1, "surface packet envelope must stay versioned and explicit")`
- `assert(generator_version == 1, "surface final packet determinism must be tied to an explicit generator_version")`
- `assert(z_level == 0, "frontier_surface_final_packet v1 is the surface packet contract")`
- `assert(generation_source != "", "surface final packet must carry provenance for proof/debug")`
- `assert(surface_packet_contains_tiled_authoritative_arrays_and_publication_buffers_for_one_tile_count, "terrain/biome/ecotone/flora-density arrays and publication-local buffers must stay index-aligned inside the packet")`
- `assert(surface_packet_contains_flora_placements_and_feature_and_poi_payload, "deterministic flora and feature/POI placement truth must travel with the packet instead of being inferred from hidden fallback state")`
- `assert(surface_terminal_packet_contains_flora_payload_when_flora_placements_are_non_empty, "surface final packet publication must not owe later flora completion")`
- `assert(surface_terminal_packet_flora_payload_matches_canonical_chunk_and_has_prebuilt_render_packet, "flora publication data must be pure data ready for install, not a script recompute request")`
- `assert(surface_native_packet_visual_payload_is_built_by_ChunkVisualKernels, "player-reachable native surface packets must fail closed when native visual packet construction is unavailable")`
- `assert(ChunkStreamingService.prepare_chunk_install_entry() rejects invalid terminal surface packets before chunk creation, "surface install boundary must fail closed on missing version metadata, broken field alignment, or incomplete publication payloads")`
- `assert(Chunk.populate_native() records terminal surface packet proof before any surface chunk can publish FULL_READY, "live publication consumes the installed final packet contract instead of trusting anonymous native_data")`
- `assert(ChunkSurfacePayloadCache.cache_native_payload() and try_get_native_data() validate terminal surface packets, "surface cache must not retain or replay incomplete packet shapes")`
- `assert(player_reachable_surface_runtime_does_not_install_from_ChunkBuildResult_to_native_data, "structured ChunkBuildResult exports are not the player-reachable final packet contract")`
- `write operations`:
- `WorldGenerator.build_chunk_native_data()`
- `ChunkContentBuilder.build_chunk_native_data()`
- `ChunkFinalPacket.stamp_surface_packet_metadata()`
- `ChunkManager._complete_surface_final_packet_publication_payload()`
- `ChunkSurfacePayloadCache.cache_native_payload()`
- `forbidden writes`:
- Cache, install, and presentation paths must not mutate packet dictionaries in place to invent missing layers, relabel packet version, or erase provenance.
- Install/cache paths must not synthesize missing terminal flora or visual payloads by recomputing script-side critical completion after validation.
- `ChunkBuildResult.to_native_data()` and other structured/debug exports must not be treated as the sanctioned player-reachable surface packet contract.
- `emitted events / invalidation signals`:
- none; packet validation happens at build/install boundaries rather than through a dedicated event bus.
- `current violations / ambiguities / contract gaps`:
- none in current R5 scope; live surface `FULL_READY` and visibility publication now require chunk-local proof that `populate_native()` consumed a terminal `frontier_surface_final_packet`.

## Layer: Mining

- `classification`: `canonical`
- `owner`: `ChunkManager` owns authoritative mine-tile orchestration, while `Chunk` owns the loaded terrain mutation storage that mining changes.
- `writers`: the normal production path is `HarvestTileCommand -> ChunkManager.try_harvest_at_world() -> Chunk.try_mine_at()`. Debug pocket generation now reuses `ChunkManager.try_harvest_at_world()` after loading required underground chunks.
- `readers`: native topology update in `ChunkManager`; `MountainRoofSystem`; `MountainShadowSystem`; underground fog reveal path; save collection through `Chunk.get_modifications()`.
- `rebuild policy`: immediate loaded-chunk mutation; immediate native topology mirror update and mining event emission on the safe orchestration path; underground fog reveal is immediate on underground mining; broader topology convergence remains deferred to `_tick_topology()` / `MountainTopologyBuilder.ensure_built()`.
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
- ~~`Chunk.try_mine_at()` mutates canonical terrain but does not itself emit events, patch topology, or update fog. The safe orchestration point is `ChunkManager.try_harvest_at_world()`, not the chunk method.~~ **resolved 2026-03-28**: `Chunk.try_mine_at()` now asserts on unauthorized direct use; `ChunkManager.try_harvest_at_world()` explicitly authorizes the chunk-local mutation just for the sanctioned orchestration path.
- ~~`Chunk.try_mine_at()` does not call `_refresh_open_neighbors()`. Neighboring `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` tiles are not re-normalized automatically, even inside the same chunk.~~ **resolved 2026-03-27**: `try_harvest_at_world()` now calls `_refresh_open_neighbors()` for same-chunk neighbors and `_refresh_open_tile()` for cross-chunk cardinal neighbors after mining.
- ~~Cross-chunk mining redraw is local-only. `_collect_mining_dirty_tiles()` returns only same-chunk tiles, so neighbor chunk visuals at seams can remain stale.~~ **resolved 2026-04-14; R4.4 tightened 2026-04-15**: `try_harvest_at_world()` now keeps the authoritative local mutation and neighbor normalization in the interactive chain, but same-chunk local patch repair no longer completes player-near border dirt inline. Local and cross-chunk seam repair must escalate to scheduler-owned `TASK_BORDER_FIX` / `TASK_FULL_REDRAW` resumable work, with `ChunkSeamService` owning neighbor enqueue decisions. `_collect_mining_dirty_tiles()` still returns same-chunk tiles only; convergence ownership remains at the orchestration/scheduler level.
- ~~Debug direct writers bypass the normal event and invalidation chain.~~ **resolved 2026-03-28**: debug pocket carving now goes through `ChunkManager.try_harvest_at_world()`, and direct debug rock placement was removed instead of leaving an unsafe terrain write path.

## Layer: Topology

- `classification`: `derived`
- `owner`: `ChunkTopologyService` owns the surface topology runtime contract and the validated native builder state; native `MountainTopologyBuilder` remains the mandatory topology backend and the only production owner of derived topology caches. `ChunkManager` stays the public facade, lifecycle coordinator, and mining/load/unload orchestration owner that forwards into the service.
- `writers`: `ChunkTopologyService.setup_native_builder()`, `install_surface_chunk()`, `remove_surface_chunk()`, `note_mountain_tile_changed()`, and `tick()`. `ChunkManager._finalize_chunk_install()`, `ChunkStreamingService.unload_chunk()`, `ChunkManager._on_mountain_tile_changed()`, and `ChunkManager._tick_topology()` may request topology work only through those service-owned entrypoints.
- `readers`: `MountainRoofSystem` surface local-zone queries read `ChunkManager.get_mountain_key_at_tile()` and `get_mountain_open_tiles()`. No other direct in-scope runtime reader was found for `get_mountain_tiles()`.
- `rebuild policy`: surface-only, loaded-bubble scoped; chunk load/unload update the service-owned native builder mirror immediately and mark native topology dirty, successful mountain-tile mutation updates the mirror on the spot, and deferred convergence stays behind `ChunkTopologyService.tick()` / `MountainTopologyBuilder.ensure_built()`. Full rebuild has no production GDScript fallback.
- `invariants`:
- `assert(_active_z == 0 or get_mountain_key_at_tile(tile_pos) == Vector2i(999999, 999999), "surface mountain topology must not be exposed on underground z levels")`
- `assert(terrain_type == TileGenData.TerrainType.ROCK or terrain_type == TileGenData.TerrainType.MINED_FLOOR or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE, "topology domain is ROCK + open mountain terrain")`
- `assert(open_tile_type == TileGenData.TerrainType.MINED_FLOOR or open_tile_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE, "topology open subset must be mined floor or mountain entrance")`
- `assert(connectivity_dirs == [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN], "mountain topology connectivity is cardinal only")`
- `assert(native_topology_builder_is_active, "surface topology reads and writes require active MountainTopologyBuilder")`
- `assert(native_topology_domain == loaded_surface_chunks, "runtime topology rebuilds operate on loaded surface chunks mirrored into MountainTopologyBuilder only")`
- `assert(no_gdscript_topology_scheduler, "production topology must not use GDScript rebuild snapshots, worker commits, or _mountain_* dictionary fallback")`
- `assert(not ClassDB.class_exists("MountainTopologyBuilder") => chunk_runtime_boot_fails, "surface topology rebuild must fail fast when the required native builder is missing")`
- `write operations`:
- `ChunkTopologyService.setup_native_builder()`
- `ChunkTopologyService.install_surface_chunk()`
- `ChunkTopologyService.remove_surface_chunk()`
- `ChunkTopologyService.note_mountain_tile_changed()`
- `ChunkTopologyService.tick()`
- `ChunkManager._setup_native_topology_builder()` facade forwarding to `ChunkTopologyService.setup_native_builder()`
- `ChunkManager._tick_topology()` facade forwarding to `ChunkTopologyService.tick()`
- `ChunkManager._on_mountain_tile_changed()` facade forwarding topology writes through `ChunkTopologyService.note_mountain_tile_changed()`
- `ChunkManager._install_surface_chunk_into_topology()` facade forwarding to `ChunkTopologyService.install_surface_chunk()`
- `ChunkManager._remove_surface_chunk_from_topology()` facade forwarding to `ChunkTopologyService.remove_surface_chunk()`
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
- ~~Incremental split detection in the old GDScript topology patch path was heuristic.~~ **resolved 2026-04-13**: the GDScript patch path was deleted; in-domain mountain changes update the native topology mirror and convergence stays behind `MountainTopologyBuilder.ensure_built()`.
- ~~The old managed topology rebuild path could drift between whole-topology and chunk-scoped dictionaries.~~ **resolved 2026-04-13**: production topology no longer commits GDScript `_mountain_*` dictionaries; native `MountainTopologyBuilder` owns the derived topology cache.
- ~~The old staging dictionaries for chunk-scoped topology existed separately from the managed rebuild flow.~~ **resolved 2026-04-13**: the staging dictionaries were removed with the GDScript rebuild scheduler.

## Layer: Loaded Open-Pocket Query

- `classification`: `derived`
- `owner`: `ChunkManager` owns the active-z loaded terrain mirror and writes it into native `LoadedOpenPocketQuery`; the native kernel is the only production traversal path for `query_local_underground_zone()`.
- `writers`: `ChunkManager._rebuild_native_loaded_open_pocket_query_cache()` rebuilds the active-z mirror on init and z-switch; `ChunkManager._sync_native_loaded_open_pocket_query_chunk()` / `_remove_native_loaded_open_pocket_query_chunk()` keep the mirror aligned on active-z chunk load/unload; `_on_mountain_tile_changed()` applies tile-local terrain updates to the same mirror after mining mutations.
- `readers`: `ChunkManager.query_local_underground_zone()` reads the native kernel result and publishes the user-facing `{ zone_kind, seed_tile, tiles, chunk_coords, truncated }` product; `MountainRoofSystem` consumes only that published result.
- `rebuild policy`: active-z only, loaded-only, not persisted; traversal is cardinal and native-backed, with a hard cap on explored tiles per request (`LOADED_OPEN_POCKET_QUERY_TILE_CAP = 65536`). `truncated = true` when traversal reaches an unloaded continuation or the native tile cap.
- `invariants`:
- `assert(zone_result.get("zone_kind", &"") == &"loaded_open_pocket", "query_local_underground_zone() returns a loaded_open_pocket product")`
- `assert((traversal_hit_unloaded_neighbor or traversal_hit_native_tile_cap) => bool(zone_result.get("truncated", false)), "query_local_underground_zone() must mark truncated when traversal stops at an unloaded continuation or native tile cap")`
- `assert(active_open_pocket_query_write_owner == ChunkManager, "LoadedOpenPocketQuery mirror must be written only by ChunkManager")`
- `assert(not ClassDB.class_exists("LoadedOpenPocketQuery") => chunk_runtime_boot_fails, "local open-pocket query must fail fast when the required native kernel is missing")`
- `write operations`:
- `ChunkManager._rebuild_native_loaded_open_pocket_query_cache()`
- `ChunkManager._sync_native_loaded_open_pocket_query_chunk()`
- `ChunkManager._remove_native_loaded_open_pocket_query_chunk()`
- `ChunkManager._on_mountain_tile_changed()`
- Native query calls: `clear`, `set_chunk`, `remove_chunk`, `update_tile`, `query_open_pocket`
- `forbidden writes`:
- Systems outside `ChunkManager` must not mutate the native open-pocket mirror directly.
- The native query mirror must not be treated as authoritative terrain truth for loaded or unloaded world reads.
- `emitted events / invalidation signals`:
- none; cache invalidation happens only through `ChunkManager` chunk lifecycle and mining mutation paths.
- `current violations / ambiguities / contract gaps`:
- The mirror is active-z scoped, so z-switch rebuild is an explicit replay step instead of a world-global cache.

## Layer: Reveal

- `classification`: `derived`
- `owner`: `MountainRoofSystem` owns surface local-zone reveal derivation, `UndergroundFogState` owns underground reveal state, and `ChunkManager` owns application of underground fog deltas to loaded chunks.
- `writers`: `MountainRoofSystem` writes the active local-zone derived state, `Chunk.set_revealed_local_cover_tiles()` writes per-chunk applied cover reveal, and `UndergroundFogState` plus `ChunkManager` write underground fog state and chunk fog application.
- `readers`: `Chunk` cover-layer and fog-layer presentation code; `MountainRoofSystem` public zone getters; no other in-scope gameplay reader was found for these reveal sets.
- `rebuild policy`: active-z dependent; surface reveal is loaded-bubble scoped, may apply only a bounded immediate local cover patch on successful surface mining when the active zone can be incrementally extended or single-tile-bootstrapped, queues larger mined-cover deltas through the normal cover-apply path instead of forcing synchronous harvest-side apply, and runs full local-zone cover rebuild as a staged multi-frame refresh under an explicit per-frame time budget instead of a monolithic `_process()` rebuild; underground fog is updated on fog ticks and immediately on successful underground mining; there is no unloaded fallback reveal path.
- `invariants`:
- `assert(ChunkManager.get_active_z_level() == 0 or not surface_local_reveal_running, "surface local mountain reveal only runs on z == 0")`
- `assert(seed_terrain == TileGenData.TerrainType.MINED_FLOOR or seed_terrain == TileGenData.TerrainType.MOUNTAIN_ENTRANCE, "surface local-zone seeding requires an open mountain tile")`
- `assert(surface_mining_refresh_is_not_gated_only_on_player_open_tile, "surface mining-triggered reveal refresh must stay correct even when the player is still outside the newly opened pocket")`
- `assert(surface_full_local_zone_cover_rebuild_is_staged, "surface full local-zone cover rebuild must advance through a bounded staged refresh instead of a single synchronous _process() spike")`
- `assert(surface_immediate_mining_cover_patch_stays_bounded, "surface mining may publish only a bounded immediate local cover patch inline; larger cover deltas must fall back to queued cover apply or staged refresh")`
- `assert(revealed_cover_tiles == zone_tiles_plus_revealable_rock_halo, "surface revealed cover is derived from the loaded local zone plus revealable rock halo")`
- `assert(all_revealed_cover_tiles_are_local_to_chunk and cover_cells_are_erased_for_them, "Chunk._revealed_local_cover_tiles is a packed chunk-local erase mask for cover_layer")`
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
- On `EventBus.mountain_tile_mined`, `MountainRoofSystem` first attempts a bounded immediate local cover patch by reusing the active local-zone seed when the newly opened tile touches the active zone or by bootstrapping a one-tile zone when that is sufficient; if that fast path cannot prove correctness, it seeds refresh from the mined open tile itself and only falls back to the player tile when the player is already inside an opened pocket.
- Underground fog invalidation is driven by z-level entry, fog update ticks, and immediate successful underground mining.
- `current violations / ambiguities / contract gaps`:
- `MountainRoofSystem` tracks `zone_kind` and `truncated`, but current runtime behavior does not branch on `zone_kind`, and `truncated` is only exposed as a getter.
- Surface reveal is loaded-bubble scoped. If the local open pocket continues into an unloaded chunk, reveal stops at the current load boundary.
- ~~`Chunk` currently exposes both `set_revealed_local_zone()` and `set_revealed_local_cover_tiles()`. The active runtime path uses the cover-tile API directly.~~ **resolved 2026-03-28**: the unused `set_revealed_local_zone()` wrapper was removed; reveal writes now have one chunk-level entrypoint.
- Underground fog state is shared across underground runtime and cleared on z change, so discovered-state continuity between underground floors is not currently represented.

## Layer: Frontier Planning / Reserved Scheduling

- `classification`: `derived`
- `owner`: `TravelStateResolver` owns travel-mode/speed-class planning inputs, `ViewEnvelopeResolver` owns the fixed gameplay `3x3` hot and `5x5` warm envelope derivation plus debug-only raw camera envelope diagnostics, `FrontierPlanner` owns the current active-z frontier plan sets, and `FrontierScheduler` owns lane classification/reserved-capacity policy. `ChunkStreamingService` stores the runtime lane queues and active generation lane metadata that execute that plan.
- `writers`: `TravelStateResolver.resolve()`, `ViewEnvelopeResolver.resolve()`, `FrontierPlanner.build_plan()`, `FrontierScheduler.resolve_lane_for_coord()`, `FrontierScheduler.build_capacity_snapshot()`, `ChunkStreamingService.update_chunks()`, `enqueue_load_request()`, `prune_load_queue()`, `sort_load_queue_by_priority()`, `tick_loading()`, `submit_async_generate()`, and `collect_completed_runtime_generates()`.
- `readers`: `ChunkStreamingService` load/generation selection, `ChunkDebugSystem` and `WorldChunkDebugOverlay` snapshots, `WorldRuntimeDiagnosticLog`, `WorldPerfProbe`, and runtime validation/manual inspection.
- `rebuild policy`: runtime-only and active-z scoped. The plan is rebuilt when `ChunkStreamingService.update_chunks()` receives the current player chunk, including bounded in-chunk motion refreshes while the player is moving. Queue entries are reclassified against the latest plan on enqueue/prune. Active generation lane metadata is cleared when the worker result is collected. No frontier plan, lane queue, or active-lane metadata is persisted.
- `invariants`:
- `assert(fixed_hot_chunks_are_frontier_critical, "fixed gameplay hot chunks must be classified into frontier-critical scheduling before background work")`
- `assert(debug_camera_visible_chunks_do_not_widen_runtime_scope, "raw debug camera-visible chunks are diagnostics only and must not expand the gameplay needed_set")`
- `assert(occupancy_chunk_is_frontier_critical, "the player occupancy chunk must always be in the frontier-critical set")`
- `assert(motion_frontier_uses_travel_speed_class, "motion frontier width must come from travel mode and speed-class planning inputs, not only current load radius sorting")`
- `assert(frontier_critical_capacity_is_reserved, "frontier-critical generation must have at least one reserved worker slot")`
- `assert(noncritical_lanes_cannot_use_reserved_frontier_capacity, "warm-support/background work must not occupy the reserved frontier slot")`
- `assert(frontier_plan_is_derived_runtime_state, "frontier plan and lane metadata are transient scheduling state, not save/load or terrain truth")`
- `write operations`:
- `TravelStateResolver.resolve()`
- `ViewEnvelopeResolver.resolve()`
- `FrontierPlanner.build_plan()`
- `FrontierScheduler.resolve_lane_for_coord()`
- `ChunkStreamingService.enqueue_load_request()`
- `ChunkStreamingService.prune_load_queue()`
- `ChunkStreamingService.submit_async_generate()`
- `ChunkStreamingService.collect_completed_runtime_generates()`
- `forbidden writes`:
- Code outside the frontier owners and `ChunkStreamingService` must not mutate frontier lane queues, `_last_frontier_plan`, `gen_active_lanes`, or reserved-capacity counters directly.
- Background/far streaming policy must not submit work into the reserved frontier slot by bypassing `FrontierScheduler`.
- Frontier planning must not become canonical terrain/readiness truth; `full_ready` remains chunk publication/readiness state.
- `emitted events / invalidation signals`:
- No gameplay event. Diagnostics use `WorldRuntimeDiagnosticLog` records and `WorldPerfProbe` metrics such as `frontier.reserved_capacity_blocked`.
- `current violations / ambiguities / contract gaps`:
- none in current R5 publication-gate scope; frontier planning remains derived scheduling state and does not replace chunk-local full-ready publication proof.

## Layer: Visual Task Scheduling

- `classification`: `derived`
- `owner`: `ChunkVisualScheduler` owns the visual scheduler queues, task versioning maps, worker visual-compute maps, apply-feedback state, queue latency telemetry containers, duplicate requeue rejection counter, visual readiness timing maps, and the bounded queue-drain/task-processing policy for chunk visual work; `ChunkManager` remains the lifecycle coordinator, invalidation source, chunk/publication owner, and bounded tick caller.
- `writers`: `ChunkVisualScheduler.clear_runtime_state()`, `begin_step()`, `queue_for_band()`, `ordered_queues()`, `tick_budget()`, `tick_once()`, `reset_runtime_telemetry()`, `ensure_task()`, `refresh_task_priorities()`, `clear_task()`, `push_task_front()`, `promote_existing_task_to_front()`, `mark_apply_started()`, `mark_convergence_started()`, `mark_first_pass_ready()`, `mark_full_ready()`, `clear_full_ready()`, and the internal scheduler drain helpers invoked by those tick entrypoints; `ChunkManager._schedule_chunk_visual_work()`, `_ensure_chunk_full_redraw_task()`, `_ensure_chunk_border_fix_task()`, `_invalidate_chunk_visual_convergence()`, and `_try_finalize_chunk_visual_convergence()` may request scheduler work only through those scheduler-owned entrypoints.
- `readers`: `ChunkManager` boot/runtime work loops, worker-side visual batch preparation, `ChunkDebugSystem` snapshot assembly, `WorldPerfProbe`, and console/instrumentation consumers.
- `rebuild policy`: runtime-only, per-tick, budgeted scheduler state. Task queues are repopulated from loaded chunk redraw state and dirty-border state; they are not persisted and are cleared on teardown through `ChunkVisualScheduler.clear_runtime_state()`. Terrain / cover / cliff / flora / border-fix work must resume through versioned scheduler tasks with stored slice phase/cursor telemetry and worker-prepared serializable command batches or flora render packets plus bounded main-thread apply. Enqueue, requeue, priority refresh, worker-compute return, and queue-rotation paths must pass through one scheduler-owned live-task dedupe gate for `(chunk_coord, z_level, task_kind, invalidation_version)`; rejected duplicates increment `scheduler.duplicate_requeue_rejected_total` through `WorldPerfProbe` and must not inflate `scheduler.visual_task_requeue_total`. When the visual budget is exhausted, unfinished `TASK_FULL_REDRAW` / `TASK_BORDER_FIX` work is requeued; player-near relief paths must not complete full border/full redraw work inline. The scheduler-owned drain budget must stay aligned with `WorldGenBalance.visual_scheduler_budget_ms` instead of self-expanding past the registered dispatcher budget.
- `invariants`:
- `assert(only_chunk_visual_scheduler_owned_containers_hold_visual_task_queues, "visual task queues, versions, and compute maps must live in the scheduler owner, not ad-hoc manager dictionaries")`
- `assert(chunk_manager_executes_visual_policy_only_through_scheduler_owned_state, "ChunkManager may coordinate visual task policy but must not introduce a second mutable scheduler store")`
- `assert(terrain_urgent_and_terrain_near_work_outrank_far_and_cosmetic_work, "near first-pass work must outrank far convergence work")`
- `assert(visible_border_fix_work_outranks_far_full_redraw, "near-visible seam repair must run before far full convergence work")`
- `assert(task_dedupe_and_versioning_prevent_duplicate_live_work_for_same_chunk_kind, "scheduler must not accumulate multiple live tasks for one chunk/kind/version")`
- `assert(scheduler_rejects_duplicate_live_task_for_same_chunk_kind_version, "requeue must not resurrect a live task for an identical chunk/kind/version triple")`
- `assert(scheduler_visual_task_requeue_total_grows_sublinearly_in_startup_bubble_chunks, "startup bubble requeue must scale roughly linearly with chunks, not quadratically")`
- `assert(chunk_visual_state_transitions_follow_uninitialized_native_proxy_terrain_full_pending_full_ready, "ChunkVisualState is the chunk-local readiness contract for scheduler-owned publication")`
- `assert(chunk_full_ready_is_revoked_on_visual_invalidation_until_followup_work_closes, "approximation, seam repair, and mining-side convergence debt must drop FULL_READY back to FULL_PENDING until the owed work is complete")`
- `assert(visual_scheduler_work_stays_within_an_explicit_per_tick_budget, "visual queue draining is budgeted by WorldGenBalance.visual_scheduler_budget_ms")`
- `assert(visual_scheduler_internal_drain_budget_does_not_exceed_registered_dispatcher_budget, "visual scheduler must not silently enlarge its own per-tick drain budget beyond the dispatcher job budget")`
- `assert(urgent_wait_and_queue_depth_are_observable, "scheduler telemetry must expose urgent wait, queue depth, processed count, budget exhaustion, slice counts, requeues, and max single-task apply time")`
- `assert(worker_visual_prepare_only_emits_serializable_command_batches, "worker visual prepare may compute terrain/ground-face/rock/cover/cliff commands only as pure data, never scene-tree writes")`
- `assert(worker_flora_prepare_only_emits_serializable_render_packets, "worker flora prepare may group ChunkFloraResult placements into pure-data layer/type render packets only; it must not instantiate per-placement nodes")`
- `assert(main_thread_visual_apply_is_bounded_to_ready_commands, "main-thread visual scheduler apply is limited to publishing prepared batches via bounded TileMap mutation on the main thread, optionally through a native bulk-apply helper, or a single flora batch-renderer update")`
- `write operations`:
- `ChunkVisualScheduler.clear_runtime_state()`
- `ChunkVisualScheduler.begin_step()`
- `ChunkVisualScheduler.queue_for_band()`
- `ChunkVisualScheduler.ordered_queues()`
- `ChunkVisualScheduler.tick_budget()`
- `ChunkVisualScheduler.tick_once()`
- `ChunkVisualScheduler.reset_runtime_telemetry()`
- `ChunkManager._schedule_chunk_visual_work()`
- `ChunkManager._ensure_chunk_full_redraw_task()`
- `ChunkManager._ensure_chunk_border_fix_task()`
- `ChunkManager._invalidate_chunk_visual_convergence()`
- `ChunkManager._try_finalize_chunk_visual_convergence()`
- `ChunkManager._tick_visuals_budget()` facade forwarding to `ChunkVisualScheduler.tick_budget()`
- `forbidden writes`:
- Code outside `ChunkVisualScheduler` / the `ChunkManager` visual scheduler owner path must not push directly into visual task queues, mutate task pending/version maps, mutate compute maps, or author visual readiness telemetry maps.
- Scheduler state must not be persisted or treated as canonical world/readiness truth.
- Direct synchronous terrain completion in the runtime streaming finalize path must not bypass scheduler ownership for near-chunk first-pass work.
- `emitted events / invalidation signals`:
- none; observability is currently telemetry/log based rather than event based.
- `current violations / ambiguities / contract gaps`:
- `Chunk.continue_redraw()` still exists as a local/debug progressive redraw helper, but scheduler-owned player-reachable `TASK_FIRST_PASS` / `TASK_FULL_REDRAW` must hard-block and emit a zero-tolerance breach if native critical compute is unavailable instead of using it as a compatibility executor.

## Layer: Surface Payload Cache

- `classification`: `derived` / `presentation-cache`
- `owner`: `ChunkSurfacePayloadCache` owns bounded surface payload reuse state for generated z=0 chunks.
- `writers`: `ChunkSurfacePayloadCache.cache_native_payload()`, `cache_flora_payload()`, `cache_flora_result()`, and `clear()`.
- `readers`: `ChunkStreamingService` load/stage paths through `ChunkManager` facade helpers, boot compute helpers, and chunk install preparation.
- `rebuild policy`: runtime cache only, surface z=0 only, not persisted. Native payload arrays are accepted only after `ChunkFinalPacket.validate_terminal_surface_packet()` succeeds, duplicated on cache write, and duplicated again on read so cache entries do not become mutable terrain truth. Flora payloads may be hydrated with texture paths before reuse. LRU bookkeeping is owned by the cache service and trimmed to `SURFACE_PAYLOAD_CACHE_LIMIT`.
- `invariants`:
- `assert(surface_payload_cache_is_not_world_truth, "cached native payloads and flora packets are reusable generated presentation/base payloads, not authoritative terrain diffs")`
- `assert(surface_payload_cache_duplicates_native_arrays_on_read_and_write, "cache reuse must not share mutable PackedArray instances with loaded chunks")`
- `assert(surface_payload_cache_is_surface_only_and_not_persisted, "underground chunks and save/load truth must not depend on the surface payload cache")`
- `assert(surface_payload_cache_retains_only_terminal_surface_packets, "cache replay must not reintroduce install-time script completion debt")`
- `write operations`:
- `ChunkSurfacePayloadCache.cache_native_payload()`
- `ChunkSurfacePayloadCache.cache_flora_payload()`
- `ChunkSurfacePayloadCache.cache_flora_result()`
- `ChunkSurfacePayloadCache.clear()`
- `forbidden writes`:
- Code outside `ChunkSurfacePayloadCache` must not mutate its entries or private LRU-link state directly.
- Cached payloads must not be used as a substitute for loaded terrain bytes, saved runtime diffs, or unloaded terrain read arbitration.
- Invalid or non-terminal surface packets must be rejected/evicted instead of repaired by the cache.
- `emitted events / invalidation signals`:
- none; cache state is private runtime reuse state.
- `current violations / ambiguities / contract gaps`:
- none in current scope.

## Layer: Seam Repair Queue

- `classification`: `derived`
- `owner`: `ChunkSeamService` owns pending seam refresh tiles, duplicate suppression, neighbor border enqueue logic, and mining-side seam follow-up repair. `ChunkManager` remains the mining/topology coordinator and calls the service from sanctioned owner paths.
- `writers`: `ChunkSeamService.enqueue_neighbor_border_redraws()`, `seam_normalize_and_redraw()`, `process_queue_step()`, and `clear()`.
- `readers`: `ChunkManager._tick_topology()`, visual scheduler border-fix task creation, and debug queue-depth snapshot helpers.
- `rebuild policy`: runtime-only queue, not persisted. Mining at a loaded chunk edge enqueues only loaded-neighbor seam tiles; topology tick drains at most `SEAM_REFRESH_MAX_TILES_PER_STEP` tiles per step and schedules visual border-fix work rather than synchronously redrawing all affected neighbors. Visual border-fix apply is sliced by `WorldGenBalance.visual_border_fix_tiles_per_step`; one scheduler slice may process fewer tiles for far/background work, but must not process more than the configured export.
- `invariants`:
- `assert(seam_repair_queue_is_loaded_neighbor_only, "seam repair must not synthesize unloaded neighbor mutation or redraw work")`
- `assert(seam_repair_queue_dedupes_tiles, "one seam tile should not accumulate duplicate pending refresh entries")`
- `assert(seam_repair_drain_is_bounded_per_step, "seam refresh work must stay budgeted and must not redraw all neighbor borders in one interactive mining frame")`
- `assert(border_fix_slice_processes_at_most_configured_tiles_per_step, "one border-fix slice must not exceed visual_border_fix_tiles_per_step")`
- `assert(border_fix_slice_respects_visual_category_budget, "border-fix slice must stop when visual category budget is exhausted within the same tick")`
- `assert(seam_border_fix_uses_visual_scheduler, "seam repair may enqueue border-fix work but must not bypass visual scheduler convergence ownership")`
- `write operations`:
- `ChunkSeamService.enqueue_neighbor_border_redraws()`
- `ChunkSeamService.seam_normalize_and_redraw()`
- `ChunkSeamService.process_queue_step()`
- `ChunkSeamService.clear()`
- `forbidden writes`:
- Code outside `ChunkSeamService` must not mutate the pending seam refresh queue or lookup.
- Seam service must not mutate canonical terrain outside the loaded neighbor open-tile normalization path owned by mining seam repair.
- `emitted events / invalidation signals`:
- none; it schedules existing visual border-fix tasks and emits diagnostics through the `ChunkManager` diagnostic facade.
- `current violations / ambiguities / contract gaps`:
- none in current scope.

## Layer: Chunk Debug Overlay Snapshot

- `classification`: `derived`
- `owner`: `ChunkDebugSystem` owns assembly of the F11 chunk debug snapshot plus the bounded forensic incident / trace / task metadata that feeds it; `ChunkManager` remains the owner of chunk lifecycle, queue, stage-age, and visual scheduler state consumed during assembly.
- `writers`: `ChunkManager.get_chunk_debug_overlay_snapshot()` is the public read entrypoint and forwards to `ChunkDebugSystem.build_overlay_snapshot()`; chunk lifecycle transitions (`_enqueue_load_request()`, `_submit_async_generate()`, `_collect_completed_runtime_generates()`, `_stage_prepared_chunk_install()`, `_finalize_chunk_install()`, `_try_finalize_chunk_visual_convergence()`, `_unload_chunk()`) and visual-task owner transitions feed the narrow `ChunkDebugSystem` API, which stores bounded diagnostic timestamps, trace metadata, task rows, and the returned overlay snapshot sections for debug reads.
- `readers`: `WorldChunkDebugOverlay` and debug/validation tools.
- `rebuild policy`: transient read snapshot, active-z only, bounded around `_player_chunk` by `DEBUG_OVERLAY_MAX_RADIUS`, queue rows capped/grouped, incident / trace / causality sections capped separately, not persisted and not consumed by gameplay. Release runtime must be able to select/process scheduler work without deep per-task forensic enrichment by default; detailed trace/task metadata remains behind the debug owner path.
- `invariants`:
- `assert(chunk_debug_overlay_snapshot_is_read_only, "F11 overlay snapshot must not request, unload, generate, publish, or mutate chunks")`
- `assert(chunk_debug_overlay_snapshot_radius_is_clamped, "F11 overlay snapshot must stay bounded around the player and must not scan the whole world")`
- `assert(chunk_debug_queue_rows_are_capped_or_grouped, "debug queue output must expose active work without printing thousands of identical rows")`
- `assert(stalled_chunk_state_is_observational, "stalled state in the overlay is an observed delay and must not be reported as a proven root cause unless an owner record says so")`
- `assert(forensics_sections_are_bounded, "incident_summary, trace_events, chunk_causality_rows, task_debug_rows, and suspicion_flags must remain bounded and derived from `ChunkDebugSystem` debug state plus owner lifecycle state")`
- `assert(release_scheduler_path_is_not_forensics_bound, "release scheduler path must not require deep per-task forensic enrichment to select, requeue, or skip visual work")`
- `write operations`:
- `ChunkManager.get_chunk_debug_overlay_snapshot()` forwarding to `ChunkDebugSystem.build_overlay_snapshot()`
- internal diagnostic timestamp/recent-event writes through `ChunkDebugSystem` entry points called from the `ChunkManager` lifecycle transition methods listed above
- `forbidden writes`:
- `WorldChunkDebugOverlay` must not mutate `ChunkManager`, `Chunk`, terrain, topology, reveal, save data, visual task queues, or worker/apply lifecycle state.
- Snapshot consumers must not treat `chunks`, `queue_rows`, `metrics`, `timeline_events`, `incident_summary`, `trace_events`, `chunk_causality_rows`, `task_debug_rows`, or `suspicion_flags` as authoritative gameplay truth.
- Snapshot data must not be persisted.
- `emitted events / invalidation signals`:
- none; the overlay polls the bounded snapshot on a throttled cadence.
- `current violations / ambiguities / contract gaps`:
- The current `simulation_radius` shown in the overlay is a diagnostic label for the active loaded/simulated relevance band, not a separate authoritative simulation owner. If a future gameplay simulation radius becomes canonical, this layer must be updated to read that owner instead of deriving the label from load relevance.

## Layer: Runtime Diagnostic Timeline Buffer

- `classification`: `derived`
- `owner`: `WorldRuntimeDiagnosticLog` owns bounded diagnostic event buffering and Russian human-readable summary formatting for runtime diagnostics.
- `writers`: `WorldRuntimeDiagnosticLog.emit_summary()`, `emit_detail()`, and `emit_record()` update the transient ring buffer while preserving existing console log emission.
- `readers`: `WorldChunkDebugOverlay`, debug inspection, validation tooling, and humans reading console logs.
- `rebuild policy`: bounded in-memory ring buffer, cooldown-deduped by `actor + action + target + reason + impact + state + code`, with `trace_id` / `incident_id` folded into dedupe when present, not persisted and not replayed into gameplay.
- `invariants`:
- `assert(timeline_event_has_human_summary_and_structured_record, "diagnostic timeline events must keep both Russian summary text and structured technical fields")`
- `assert(timeline_event_history_is_bounded, "diagnostic timeline must not grow unbounded during traversal")`
- `assert(timeline_dedupe_updates_repeat_count, "unchanged diagnostic events inside cooldown must update repeat_count instead of appending spam")`
- `write operations`:
- `WorldRuntimeDiagnosticLog.emit_summary()`
- `WorldRuntimeDiagnosticLog.emit_detail()`
- `WorldRuntimeDiagnosticLog.emit_record()`
- `forbidden writes`:
- Timeline events must not be used as gameplay state, save/load state, or scheduler input.
- Debug timeline formatting must not scan all loaded chunks or perform world work just to phrase a message.
- `emitted events / invalidation signals`:
- none; readers pull `WorldRuntimeDiagnosticLog.get_timeline_snapshot()`.
- `current violations / ambiguities / contract gaps`:
- Dynamic runtime diagnostic summaries are Russian-first debug text rather than fully localized gameplay UI text. Static overlay chrome uses localization keys; future shipping-facing diagnostics must define a localized message-key contract before leaving debug scope.

## Layer: F11 Chunk Debug Overlay Log File

- `classification`: `derived` / `debug-only`
- `owner`: `WorldChunkDebugOverlay` owns the per-process `.log` artifact at `user://debug/f11_chunk_overlay.log`.
- `writers`: `WorldChunkDebugOverlay._ensure_log_file()`, `_write_log_snapshot()`, and `_close_log_file()`.
- `readers`: humans and agents inspecting local debug output after an in-game F11 session.
- `rebuild policy`: overwritten on the first F11 open in a new game process; subsequent F11 opens in the same process append below the existing session header; writes occur only while the overlay is visible and only from the already-bounded overlay snapshot.
- `invariants`:
- `assert(f11_overlay_log_is_debug_only, "F11 overlay log must not be save/load data, gameplay truth, or scheduler input")`
- `assert(f11_overlay_log_writes_only_when_visible, "F11 overlay log must only append snapshots while F11 overlay is open")`
- `assert(f11_overlay_log_serializes_existing_snapshot, "F11 overlay log must not trigger additional world scans or new ChunkManager lifecycle work")`
- `assert(f11_overlay_log_is_overwritten_per_process, "F11 overlay log must be reset on the first F11 open after a fresh game process starts")`
- `write operations`:
- `WorldChunkDebugOverlay._ensure_log_file()`
- `WorldChunkDebugOverlay._write_log_snapshot()`
- `WorldChunkDebugOverlay._close_log_file()`
- `forbidden writes`:
- `ChunkManager`, `WorldRuntimeDiagnosticLog`, `WorldPerfMonitor`, save/load systems, and gameplay systems must not write directly to `user://debug/f11_chunk_overlay.log`.
- The log file must not be parsed back into runtime state or treated as a source of truth.
- Log writing must not perform unbounded chunk/world iteration; it may only serialize the bounded snapshot already requested for the visible overlay.
- `emitted events / invalidation signals`:
- none; the artifact is a local debug file, not an event source.
- `current violations / ambiguities / contract gaps`:
- The log path is a Godot `user://` path; on Windows it resolves under Godot app user data for the project name. The exact OS path is written in the log header through `ProjectSettings.globalize_path(LOG_PATH)`.

## Layer: F11 Chunk Incident Dump File

- `classification`: `derived` / `debug-only`
- `owner`: `WorldChunkDebugOverlay` owns explicit incident dump artifacts at `user://debug/f11_chunk_incident_<timestamp>.log`.
- `writers`: `WorldChunkDebugOverlay.request_incident_dump()` and `_write_incident_dump()`.
- `readers`: humans and agents inspecting one captured incident snapshot after manual `Ctrl+F11`.
- `rebuild policy`: created only on explicit manual capture; serializes one already-built bounded snapshot plus bounded incident/trace sections; may legitimately serialize `no_active_incident`.
- `invariants`:
- `assert(incident_dump_is_manual_only, "incident dump must be produced only on explicit Ctrl+F11/manual capture in this iteration")`
- `assert(incident_dump_serializes_existing_bounded_debug_state, "incident dump must not enqueue, load, generate, publish, or scan the world")`
- `assert(incident_dump_remains_debug_only, "incident dump artifact must not become gameplay truth or persistence data")`
- `write operations`:
- `WorldChunkDebugOverlay.request_incident_dump()`
- `WorldChunkDebugOverlay._write_incident_dump()`
- `forbidden writes`:
- `ChunkManager`, `WorldRuntimeDiagnosticLog`, `MountainRoofSystem`, and gameplay systems must not write directly to `user://debug/f11_chunk_incident_<timestamp>.log`.
- Incident dump generation must not create a second world debug bus or recompute world state outside the bounded snapshot request.
- `emitted events / invalidation signals`:
- none; the artifact is an explicit local capture.
- `current violations / ambiguities / contract gaps`:
- `forensics` remains debug-only overlay behavior; it is not a public runtime support workflow and should not be parsed back into engine state.

## Layer: Presentation

- `classification`: `presentation-only`
- `owner`: `Chunk` owns loaded chunk visual presentation and now delegates fog/flora/debug rendering internals to `ChunkFogPresenter`, `ChunkFloraPresenter`, and `ChunkDebugRenderer`; `MountainShadowSystem` owns surface mountain-shadow presentation state; `WorldFeatureDebugOverlay` owns debug-only anchor-marker presentation sourced from serialized chunk payloads; and `WorldChunkDebugOverlay` owns F11 debug overlay UI/drawing state sourced from bounded diagnostics snapshots.
- `writers`: `Chunk` redraw methods still own terrain/ground-face/rock/cover/cliff publication, while `ChunkFogPresenter` owns fog-layer node creation/apply, `ChunkFloraPresenter` owns chunk-local flora packet publication plus shared texture-cache-backed draw calls, and `ChunkDebugRenderer` owns debug marker batching without per-marker scene nodes; `ChunkManager` schedules redraw and applies underground fog deltas; `MountainRoofSystem` drives cover erasure through chunk APIs; `MountainShadowSystem` owns shadow-local caches plus the main-thread texture/sprite apply path while detached shadow/edge compute stays pure-data only and requires native `MountainShadowKernels` for full edge-cache and shadow-raster work; `WorldFeatureDebugOverlay` writes its chunk-local anchor-marker cache and redraw state; `WorldChunkDebugOverlay` writes only its own Control/Node2D presentation state.
- `readers`: Godot rendering is the effective consumer; developer-facing debug inspection can read `WorldFeatureDebugOverlay` marker snapshots and `WorldChunkDebugOverlay` output. No in-scope simulation system was found that treats these presentation nodes as authority.
- `rebuild policy`: loaded-only and redraw-driven; underground fog presentation is applied to loaded chunks only; surface shadow presentation is surface-only and rebuilt when edge cache or sun-angle thresholds require it, but shadow rebuild/finalize work must yield while player-visible chunk visual debt is pending so it does not compete with near streaming/border-fix publication in the same frame.
- `invariants`:
- `assert(terrain_layer_is_derived_from_chunk_data and ground_face_layer_is_derived_from_chunk_data and cover_layer_is_derived_from_chunk_data and cliff_layer_is_derived_from_chunk_data, "terrain, ground-face, cover, and cliff TileMap layers are derived outputs, not source of truth")`
- `assert(surface_ground_face_layer_uses_wall_interior_for_non_water_ground_grass_sand_and_water_shaped_faces_for_water_adjacent_tiles, "ground/sand face overlay stays presentation-only but is applied consistently across eligible surface terrain")`
- `assert(water_adjacent_ground_face_tiles_may_use_water_underlay_in_terrain_layer_to_expose_face_alpha, "riverbank/coast presentation may intentionally place WATER under face overlays for eligible surface tiles")`
- `assert(wall_interiors_use_world_space_deterministic_family_then_micro_variant_and_transform_selection_with_load_order_independent_left_up_antirepeat, "WALL_INTERIOR presentation selection must stay deterministic across reloads and chunk seams while preserving coarse blended family regions")`
- `assert(interior_macro_overlay_is_enabled_only_via_native_backed_pixel_compute, "interior macro overlay may run only through the native-backed compute/apply path and must remain presentation-only plus seam-safe")`
- `assert(all_revealed_cover_tiles_are_erased_from_cover_layer, "surface cover reveal is applied by erasing cover_layer cells")`
- `assert(not _is_underground or roof_cover_system_disabled_for_chunk, "underground chunks do not use roof cover")`
- `assert(not _is_underground or fog_layer_initialized_to_unseen_for_all_loaded_tiles, "underground fog layer starts every loaded underground tile as UNSEEN")`
- `assert(fresh_near_visible_chunk_nodes_stay_hidden_until_chunk_is_full_redraw_ready, "fresh loaded chunk visibility is gated by Chunk.is_full_redraw_ready() rather than raw apply or first-pass completion")`
- `assert(chunk_full_ready_is_chunk_local_terminal_visual_state, "ChunkVisualState.FULL_READY is the only terminal chunk-local readiness state exposed by Chunk")`
- `assert(surface_chunk_full_ready_requires_installed_terminal_final_packet, "surface ChunkVisualState.FULL_READY is valid only after terminal frontier_surface_final_packet proof is captured during populate_native")`
- `assert(chunk_full_ready_requires_redraw_done_and_no_pending_border_fix, "FULL_READY may be published only after redraw convergence is complete and no border-fix debt remains for the chunk")`
- `assert(targeted_mutation_or_seam_patch_does_not_by_itself_redefine_terminal_visual_truth, "immediate dirty-tile redraw may provide responsive local feedback, but final terminal convergence is restored only through owner-side follow-up checks")`
- `assert(worker_threads_never_mutate_chunk_tilemap_layers, "terrain, ground-face, rock, cover, and cliff TileMap mutation stays on the main thread through prepared-batch apply only")`
- `assert(active_z == 0 or not mountain_shadow_system_running, "MountainShadowSystem only runs in surface context")`
- `assert(shadow_inputs == {external_mountain_edges, sun_angle, shadow_length_factor}, "shadow sprites are built from cached edges plus current sun data")`
- `assert(shadow_edge_source_chunks == {target_chunk, north_chunk, south_chunk, east_chunk, west_chunk}, "shadow builds use the target chunk plus four cardinal neighbors as edge sources")`
- `assert(shadow_compute_uses_versioned_snapshot_inputs_and_drops_stale_results, "shadow edge-cache and raster jobs consume snapshot/versioned inputs and must discard completed results that no longer match current chunk/sun state")`
- `assert(ClassDB.class_exists("MountainShadowKernels"), "production mountain-shadow full edge-cache and raster compute must use native MountainShadowKernels and fail closed when unavailable")`
- `assert(shadow_renderer_mutation_stays_in_finalize_steps_only, "ImageTexture and Sprite2D mutation is limited to _finalize_shadow_texture() and _finalize_shadow_apply() on the main thread")`
- `assert(surface_shadow_runtime_yields_to_player_visible_visual_pressure, "surface shadow presentation must defer while player-visible chunk visual debt is pending")`
- `assert(feature_debug_overlay_reads_only_serialized_feature_and_poi_payload, "debug feature/POI presentation must consume only built payload records")`
- `assert(feature_debug_overlay_draws_anchor_markers_only, "debug feature/POI proof stays marker-only and does not materialize gameplay content")`
- `assert(disabling_feature_debug_overlay_does_not_change_feature_or_poi_truth, "presentation delay or disable must not change placement truth")`
- `write operations`:
- `Chunk._redraw_all()`
- `Chunk.continue_redraw()`
- `Chunk._redraw_dirty_tiles()`
- `Chunk._redraw_cover_tiles()`
- `Chunk.apply_visual_phase_batch()`
- `Chunk.apply_visual_dirty_batch()`
- `Chunk._refresh_interior_macro_layer()`
- `Chunk.apply_fog_visible()`
- `Chunk.apply_fog_discovered()`
- `MountainShadowSystem._build_edge_cache_now()`  (shadow-local cache write; compact detached `terrain_snapshot` + native edge compute, no renderer mutation)
- `MountainShadowSystem._advance_edge_cache_build()`  (shadow-local cache publication only)
- `MountainShadowSystem._start_shadow_build()`  (detached shadow compute kickoff only)
- `MountainShadowSystem._advance_shadow_build()`  (detached compute result polling/publication only)
- `MountainShadowSystem._finalize_shadow_texture()`
- `MountainShadowSystem._finalize_shadow_apply()`
- `forbidden writes`:
- Presentation code must not mutate canonical terrain, mining state, topology caches, or reveal source-of-truth state.
- Presentation nodes and layers must not be read as authority for gameplay, walkability, resource availability, or terrain semantics.
- Presentation systems must not redefine roof, fog, or mountain-edge semantics independently of the world / topology / reveal layers.
- `WorldFeatureDebugOverlay` must not query registries, resolvers, world channels, canonical terrain reads, `ChunkManager`, `Chunk`, topology, or reveal in order to reconstruct feature / POI truth.
- `emitted events / invalidation signals`:
- `EventBus.chunk_loaded`
- `EventBus.chunk_unloaded`
- `EventBus.mountain_tile_mined`
- `EventBus.z_level_changed`
- Sun-angle threshold crossing in `MountainShadowSystem._process()`
- Player movement indirectly through reveal and fog systems
- `current violations / ambiguities / contract gaps`:
- ~~Cross-chunk mining redraw gaps leak directly into presentation: neighboring chunk cover, terrain, and cliff visuals are not refreshed by the current mining path.~~ **resolved 2026-04-02**: seam repair now becomes explicit scheduler-owned border-fix work; affected chunks lose `FULL_READY` until the queued seam repair closes their pending convergence debt.
- Presentation is loaded-chunk scoped. There is no presentation object for unloaded continuation even when world read APIs can still answer terrain queries.
- ~~Debug direct writers can redraw visuals without going through the normal world -> mining -> topology -> reveal invalidation chain.~~ **resolved 2026-03-28**: debug terrain mutation paths no longer call raw chunk redraw helpers directly; the remaining pocket-carve path reuses production mining orchestration.

### Wall Atlas Selection (Presentation sublayer)

- `WALL_INTERIOR family selection`: interior-only presentation first resolves a coarse deterministic blended world-space family field, then picks family-local micro variation plus transform within an overlapping family window.

- `Что`: explicit code-side selection of the concrete rock-wall atlas tile and alternative tile ID for the terrain layer.
- `Где`: owner-side rule selection now lives in `core/systems/world/chunk_visual_kernel.gd`; `core/systems/world/chunk.gd` keeps only thin facades like `_surface_rock_visual_class()`, `_rock_visual_class()`, `_resolve_variant_atlas()`, `_resolve_variant_alt_id()`, `_cover_rock_atlas()`, and `_cliff_overlay_kind()`. Atlas definitions and wall-variant layout still live in `core/systems/world/chunk_tileset_factory.gd`.
- `Входные данные`: `ChunkVisualKernel` receives a request dictionary with dense center-chunk arrays (`terrain_bytes`, `height_bytes`, `variation_bytes`, `biome_bytes`, `secondary_biome_bytes`, `ecotone_values`), plus sparse `terrain_lookup` only for out-of-chunk one-tile cardinal/diagonal halo reads when the request touches chunk borders. Generation-time prebaked derivation may additionally provide full `terrain_halo`. Direct redraw builds the same contract through `Chunk._build_single_tile_visual_request()`, while batch paths use `Chunk._build_visual_compute_request()`.
- `Определение "открытого" соседа`:
- Surface terrain wall shaping in `_surface_rock_visual_class()` uses a presentation-local open-neighbor predicate that treats `GROUND`, `WATER`, `SAND`, `GRASS`, `MINED_FLOOR`, and `MOUNTAIN_ENTRANCE` as open for wall-form selection. This does not change `_is_open_exterior()` or mining semantics.
- Underground terrain wall shaping in `_rock_visual_class()` uses `_is_open_for_visual()`, which currently treats every terrain type except `ROCK` as open for visual shaping.
- Surface cliff overlay selection in `_redraw_cliff_tile()` also uses `_is_open_exterior()`.
- Surface cover reveal helpers `_is_cave_edge_rock()` and `_is_surface_rock()` treat `MINED_FLOOR` and `MOUNTAIN_ENTRANCE` as open for revealability / edge detection, but that is separate from terrain atlas selection.
- `Инварианты`:
- `assert(terrain_type != TileGenData.TerrainType.ROCK or atlas_selected_explicitly_in_Chunk__redraw_terrain_tile, "rock atlas selection is explicit code, not implicit Godot autotile terrain behavior")`
- `assert(direct_redraw_and_batch_compute_route_wall_form_selection_through_ChunkVisualKernel, "surface/underground wall-form, variant, cover, and cliff decisions must share one visual kernel source")`
- `assert(not surface_rock_has_cardinal_visual_open_neighbor or surface_rock_visual_class != ChunkTilesetFactory.WALL_INTERIOR, "surface rock with a cardinal visual-open neighbor must use a wall-form tile")`
- `assert(neighbor_terrain == TileGenData.TerrainType.ROCK or underground_neighbor_treated_as_open, "underground wall shaping treats every non-ROCK neighbor as open")`
- `assert(wall_interior_family_selection_uses_coarser_world_space_blended_regions_than_micro_variation, "WALL_INTERIOR family choice must produce larger coherent regions than per-tile micro hash selection without degenerating into chunked square blocks")`
- `assert(surface_alt_id == 0 and underground_alt_id_is_hash_selected, "surface disables wall flip alt IDs while underground enables them")`
- `forbidden writes`:
- Wall atlas selection must not mutate canonical terrain or redefine terrain semantics.
- Presentation tile choice must not be used as a substitute for topology, reveal, or mining truth.
- `current violations / ambiguities / contract gaps`:
- ~~Surface and underground wall shaping do not share one common openness contract. Surface uses cardinal exterior-open checks only; underground uses cardinal plus diagonal non-`ROCK` openness.~~ **resolved 2026-03-28**: surface rock wall-form selection now uses the same cardinal+diagonal wall-shape neighborhood set as underground shaping, while preserving the explicit current-surface-open terrain set.

### Visual Kernel Request and Batch Contract (Presentation sublayer)

- `Что`: `ChunkVisualKernel` is the single presentation-rule owner for terrain / ground-face / rock / cover / cliff classification and prepared command emission. It does not own flora or debug marker semantics; those phases remain scheduler-visible names only.
- `Где`: `core/systems/world/chunk_visual_kernel.gd`, request builders in `core/systems/world/chunk.gd` (`_build_visual_compute_request()`, `_build_single_tile_visual_request()`), prepared-batch entrypoints `Chunk.build_visual_phase_batch()`, `Chunk.build_visual_dirty_batch()`, `Chunk.compute_visual_batch()`, and single-tile adapters like `_apply_single_tile_visual_phase()`.
- `Request contract`:
- `terrain_bytes`, `height_bytes`, `variation_bytes`, `biome_bytes`, `secondary_biome_bytes`, and `ecotone_values` carry the dense center-chunk state for terrain-phase or dirty requests that may resolve ground-face / surface atlas decisions.
- `terrain_lookup` is now a sparse out-of-chunk halo map for cardinal and diagonal neighbor reads outside the local chunk bounds; `terrain_halo` is the sanctioned dense alternative for full-chunk prebaked derivation.
- `chunk_coord`, `chunk_size`, and `is_underground` are required so the kernel can derive canonical global coordinates, underground-vs-surface atlas selection, and ecotone-aware biome resolution.
- `Phase names`:
- `terrain`, `cover`, `cliff`, `flora`, `debug_interior`, `debug_collision`, `done` are the scheduler-visible phase names from `ChunkVisualKernel.visual_phase_name()`.
- Dirty / border-fix work uses `mode = "dirty"` with an explicit tile list; phase batches use `mode = "phase"` plus `phase` / `phase_name`.
- `Command semantics`:
- Each kernel-emitted command carries `layer`, `tile`, `op`, and for set operations also `source_id`, `atlas`, and `alt_id`.
- `op = set` writes one concrete TileMap cell; `op = erase` clears one cell. The kernel never mutates scene nodes directly; `Chunk.apply_visual_phase_batch()`, `Chunk.apply_visual_dirty_batch()`, and `_apply_visual_commands()` remain the only appliers.
- `Ownership / batch lanes`:
- First pass and full redraw use `build_visual_phase_batch()` with sequential tile ranges and may consume ready prebaked payload buffers when those derived arrays are still valid.
- Dirty redraw and seam repair / border fix use `build_visual_dirty_batch()`, `build_visual_dirty_batch_from_tiles()`, or `_apply_single_tile_visual_phase()` with an explicit dirty tile list, but must still go through the same `ChunkVisualKernel` request/command contract instead of a second local rule implementation.
- `Инварианты`:
- `assert(visual_request_halo_covers_cardinal_and_diagonal_reads_for_every_requested_tile, "visual kernel must never sample neighbor terrain outside an explicit one-tile request halo")`
- `assert(border_fix_and_full_redraw_share_same_visual_kernel_rules, "seam repair may narrow the dirty tile set, but not switch to an alternate wall/cover/cliff rule source")`
- `assert(kernel_commands_do_not_write_scene_tree_directly, "visual kernel emits prepared data only; apply ownership stays in Chunk")`

### Surface Prebaked Visual Payload (Presentation sublayer)

- `Что`: generation-time surface presentation payload stored in `native_data` for pristine generated chunks: `rock_visual_class`, `ground_face_atlas`, `cover_mask`, `cliff_overlay`, `variant_id`, and `alt_id`. These buffers are derived-only; they are not canonical terrain truth.
- `Где`: `core/systems/world/chunk_content_builder.gd` now passes `native_visual_tables` inside the compact native generation request and only backfills via `_build_prebaked_visual_payload()` / `_build_terrain_halo()` when the authoritative native packet arrives without embedded visual arrays; owner-side rule selection stays in `core/systems/world/chunk_visual_kernel.gd`, native derivation lives in `gdextension/src/chunk_generator.cpp` + `gdextension/src/chunk_visual_kernels.cpp`, GDScript fallback remains `Chunk.build_prebaked_visual_payload()`, and runtime consumption stays in `Chunk.populate_native()`, `Chunk.build_visual_phase_batch()`, and `Chunk.compute_visual_batch()`.
- `Входные данные`: center-chunk `terrain` / `height` / `variation` / `biome` / `secondary_biome` / `ecotone_values` arrays, one-tile `terrain_halo` around the chunk, canonical chunk/global coordinates, and the same `ChunkVisualKernel` wall/ground-face/cover/cliff rules that direct redraw and dirty redraw use.
- `Жизненный цикл`: payload is usable only for unmodified generated surface chunks. `ChunkGenerator.generate_chunk()` may embed the six derived arrays directly into the authoritative native packet using the same one-tile seam halo contract that `ChunkVisualKernels.build_prebaked_visual_payload()` expects; `ChunkContentBuilder.build_chunk_native_data()` must validate the embedded arrays and only call the secondary native builder when they are absent. `Chunk.populate_native()` marks the payload valid only when every array matches `tile_count`. Any saved terrain replay during load or later `_set_terrain_type()` invalidates the cached payload; dirty/mutation redraw paths then fall back to live neighbor-based derivation.
- `Инварианты`:
- `assert(surface_prebaked_visual_halo_size == (chunk_size + 2) * (chunk_size + 2), "surface prebaked visual derivation must sample a one-tile halo to stay seam-safe at chunk borders")`
- `assert(surface_native_packet_embeds_complete_prebaked_visual_arrays_or_builder_backfills_them_before_terminal_validation, "surface final packet may skip the second native visual builder call only when all six prebaked visual arrays are already embedded and tile-count aligned")`
- `assert(prebaked_visual_phase_skips_neighbor_derivation_when_payload_valid, "terrain/cover/cliff phase batches may apply ready buffers directly when prebaked payload is valid")`
- `assert(prebaked_payload_and_live_dirty_redraw_share_the_same_chunk_visual_kernel_rules, "prebaked surface visual buffers and live redraw fallback must stay visually equivalent because they come from one kernel contract")`
- `assert(prebaked_visual_payload_never_authors_canonical_terrain, "prebaked visual payload may accelerate presentation only and must not become terrain/topology/reveal truth")`
- `forbidden writes`:
- Prebaked visual payload builders must not mutate `terrain`, saved diffs, topology caches, reveal state, or public terrain semantics.
- Runtime consumers must not try to repair mutated chunks by editing prebaked arrays in place; once terrain changes, the payload is invalidated and normal redraw rules apply.

### Interior Macro Overlay (Presentation sublayer)

- `Current runtime status`: enabled with native-backed pixel compute.

- `Что`: chunk-local presentation overlay that adds placeholder macro detail over tiles that currently resolve to `WALL_INTERIOR`.
- `Где`: `core/systems/world/chunk.gd` builds the chunk-local target mask and applies the resulting `ImageTexture` in `_refresh_interior_macro_layer()`, while native `gdextension/src/chunk_visual_kernels.cpp::ChunkVisualKernels.build_interior_macro_overlay()` owns the per-sample RGBA generation.
- `Входные данные`: current chunk terrain and wall-form resolution collapsed into a chunk-local interior target mask, current biome tint data, deterministic world-space sample coordinates derived from `chunk_coord`, and `samples_per_tile`.
- `Инварианты`:
- `assert(interior_macro_overlay_pixel_compute_is_native_backed, "production interior macro overlay must not run per-pixel Image generation loops in GDScript")`
- `assert(chunk_gd_only_builds_target_mask_and_applies_texture_for_interior_macro_overlay, "Chunk keeps apply ownership for the interior macro Sprite2D, but heavy sample generation stays in ChunkVisualKernels")`
- `forbidden writes`:
- Interior macro overlay must not mutate terrain bytes, wall-form classification, mining state, topology caches, reveal state, or public runtime APIs.

## Layer: Boot Readiness

- `classification`: `derived`
- `owner`: `ChunkBootPipeline` owns all boot readiness state for the startup chunk bubble; `ChunkManager` remains the public boot entrypoint and lifecycle coordinator that wraps the service with `_is_boot_in_progress`.
- `writers`: `ChunkBootPipeline.boot_load_initial_chunks()`, `on_chunk_applied()`, `on_chunk_redraw_progress()`, `invalidate_visual_complete()`, `update_gates()`, `promote_redrawn_chunks()`, `init_readiness()`, and `set_chunk_state()`. `ChunkManager.boot_load_initial_chunks()` and the existing `_boot_*` facade helpers may request boot-readiness mutations only through the service-owned entrypoints.
- `readers`: `GameWorld` boot sequence, boot progress UI, instrumentation/logging.
- `rebuild policy`: boot-time only; state is initialized at boot start, updated during boot, and remains static after boot completes. Not persisted across save/load.
- `invariants`:
- `assert(boot_chunk_state != VISUAL_COMPLETE or boot_chunk_state_was_APPLIED_first, "visual completion must not precede apply for any boot chunk")`
- `assert(not first_playable or player_chunk_full_ready, "first_playable requires the player chunk (ring 0) to reach Chunk.is_full_redraw_ready()")`
- `assert(not first_playable or all_ring_0_and_ring_1_chunks_are_loaded_applied_and_full_ready, "first_playable requires ring 0..1 (Chebyshev distance) full visual convergence, not raw first-pass publication")`
- `assert(startup_spawn_tile_is_center_tile_of_ring_0, "startup/player-visible handoff anchors the player to the center tile of ring 0 instead of a seam or 4-chunk junction")`
- `assert(startup_near_envelope_is_ring_0_plus_all_8_chebyshev_neighbors, "startup near envelope is the player chunk plus all eight surrounding ring-1 chunks around the centered spawn chunk")`
- `assert(boot_ring_uses_chebyshev_distance, "ring distance is max(abs(dx), abs(dy)), not Manhattan — diagonal chunk at (1,1) is ring 1")`
- `assert(first_playable does not require topology_ready, "topology is decoupled from the internal ChunkManager first_playable gate")`
- `assert(first_playable_starts_boot_finalization_but_not_player_handoff, "GameWorld may use first_playable to start boot finalization, but player input/physics/loading-screen dismissal must wait for the full boot-ready handoff")`
- `assert(no_reblocking_after_first_playable, "remaining boot work (outer chunks, topology, shadows) completes in background without re-blocking once boot finalization starts")`
- `assert(no_synchronous_shadow_rebuild_after_first_playable, "shadow build uses schedule_boot_shadows() + _tick_shadows() via FrameBudgetDispatcher (1ms), not synchronous prepare_boot_shadows()")`
- `assert(no_synchronous_topology_build_after_first_playable, "topology uses _tick_topology() via FrameBudgetDispatcher (2ms), not synchronous ensure_built() in _tick_boot_remaining()")`
- `assert(no_sync_topology_rebuild_in_harvest, "harvest path updates the native topology mirror and leaves convergence to _tick_topology(), not a synchronous full topology rebuild")`
- `assert(runtime_near_chunks_enter_scheduler_owned_first_pass_lane, "runtime-streamed near chunks must enter the scheduler-owned first-pass lanes instead of bypassing visual scheduling with synchronous terrain completion")`
- `assert(no_sync_visual_bypass_in_streaming_runtime, "streaming runtime finalize must not bypass scheduler ownership with synchronous terrain/full redraw helpers")`
- `assert(not boot_complete or all_startup_chunks_state >= VISUAL_COMPLETE, "boot_complete requires all startup chunks to reach the Chunk.is_full_redraw_ready() terminal state")`
- `assert(not boot_complete or topology_ready, "boot_complete requires topology to be ready")`
- `assert(normal_boot_first_playable_path_uses_scheduler_owned_full_publication_work, "boot critical path must reach first_playable through scheduler-owned full-publication work rather than direct terrain helper shortcuts")`
- `assert(non_player_startup_chunks_use_progressive_redraw, "all non-player startup chunks use progressive redraw instead of synchronous ring-1 terrain completion")`
- `assert(startup_chunks_hidden_until_first_full_publication, "fresh startup chunk visibility is false until Chunk.is_full_redraw_ready(), then becomes visible through scheduler/boot progress callbacks")`
- `assert(first_playable_handoff_is_honest, "after internal first_playable, unfinished startup coords are handed to runtime streaming but remain boot-tracked until real apply/redraw completion; player handoff still waits for full boot-ready")`
- `assert(no_unbounded_apply_in_gameplay_frames, "post-first-playable does not call _boot_apply_from_queue(); outer chunks load via budgeted runtime streaming")`
- `assert(shadow_edge_cache_compute_is_detached, "_build_edge_cache_now() / _start_edge_cache_build() prepare detached snapshot input, worker compute owns heavy edge detection, and _advance_edge_cache_build() only polls/publishes the completed cache")`
- `assert(shadow_edge_cache_request_uses_compact_terrain_snapshot, "edge-cache worker input is a compact `(chunk_size + 2)^2` terrain snapshot; main thread must not bridge nine neighbor chunk arrays or a detached ChunkContentBuilder into the worker request")`
- `assert(boot_promote_waits_for_chunk_full_redraw_ready, "_boot_promote_redrawn_chunks() promotes VISUAL_COMPLETE only after Chunk.is_full_redraw_ready()")`
- `assert(boot_visual_complete_can_be_revoked_before_boot_complete, "startup chunk state may drop from VISUAL_COMPLETE back to APPLIED when late seam or convergence debt appears before boot_complete is finalized")`
- `assert(first_playable_and_boot_complete_are_distinct_boot_milestones, "first_playable starts post-ready finalization, while player-visible handoff waits for GameWorld boot_complete after startup chunks, topology, and boot shadows are ready")`
- `assert(ring_2_deferred_to_runtime_at_boot, "ring 2+ chunks are NOT applied inside boot loop — they are handed off to runtime streaming via _boot_start_runtime_handoff() after first_playable (boot_fast_first_playable_spec)")`
- `assert(boot_progressive_redraw_prioritizes_near_ring, "_boot_process_redraw_budget() processes only ring 0-1 chunks during boot, deferring ring 2+ to end of queue (boot_fast_first_playable_spec)")`
- `assert(diagnostics_only_sync_visual_helpers_do_not_define_boot_readiness, "compatibility helpers such as complete_terrain_phase_now() may still exist for diagnostics/fallback use, but normal boot readiness no longer depends on them")`
- `write operations`:
- `ChunkBootPipeline.init_readiness()`
- `ChunkBootPipeline.set_chunk_state()`
- `ChunkBootPipeline.update_gates()`
- `ChunkBootPipeline.promote_redrawn_chunks()`
- `ChunkBootPipeline.on_chunk_applied()`
- `ChunkBootPipeline.on_chunk_redraw_progress()`
- `ChunkBootPipeline.invalidate_visual_complete()`
- `ChunkManager._boot_init_readiness()` facade forwarding to `ChunkBootPipeline.init_readiness()`
- `ChunkManager._boot_set_chunk_state()` facade forwarding to `ChunkBootPipeline.set_chunk_state()`
- `ChunkManager._boot_update_gates()` facade forwarding to `ChunkBootPipeline.update_gates()`
- `ChunkManager._boot_promote_redrawn_chunks()` facade forwarding to `ChunkBootPipeline.promote_redrawn_chunks()`
- `forbidden writes`:
- UI, scene code, or non-owner systems must not write boot readiness state.
- Boot readiness must not be inferred from `_load_queue.is_empty()` alone.
- `is_topology_ready()` must not be treated as identical to `is_boot_first_playable()`.
- `emitted events / invalidation signals`:
- none; readiness is polled via `is_boot_first_playable()` and `is_boot_complete()`. Console log milestones are printed on first gate transition and mirrored into `WorldPerfProbe.mark_milestone("Boot.first_playable")` / `WorldPerfProbe.mark_milestone("Boot.boot_complete")`.
- `current violations / ambiguities / contract gaps`:
- ~~`GameWorld._boot_complete` is a separate flag that covers the full boot sequence including shadow build and player input enable. `ChunkManager._boot_complete_flag` covers only chunk readiness and topology. Unification is deferred until `GameWorld` adopts staged boot.~~ **resolved 2026-03-29, refined 2026-04-05**: `GameWorld` uses staged boot. `_boot_first_playable_done` marks that the near world is internally ready enough to start boot finalization (driven by `ChunkManager.is_boot_first_playable()`), but player input/physics/loading-screen dismissal no longer happen there. `_boot_complete` plus boot-shadow drain now define the actual player-visible handoff. Shadow build uses `schedule_boot_shadows()` (seeds dirty queues) and incremental `_tick_shadows()` via FrameBudgetDispatcher (1ms budget). Topology uses existing `_tick_topology()` (2ms budget) — no synchronous `ensure_built()` in post-first-playable path.

## Layer: Boot Compute Queue

- `classification`: `derived`
- `owner`: `ChunkBootPipeline` owns the bounded boot compute queue, worker lifecycle, prepare/apply queues, and runtime handoff state.
- `writers`: `ChunkBootPipeline.submit_pending_tasks()`, `collect_completed()`, `drain_computed_to_apply_queue()`, `prepare_apply_entries()`, `apply_from_queue()`, `worker_compute()` (via mutex), `tick_remaining()`, `start_runtime_handoff()`, `cleanup_compute_pipeline()`, and `wait_all_compute()`. `ChunkManager` boot facades may request compute/apply progress only through those service-owned entrypoints.
- `readers`: boot progress loop, instrumentation (`get_boot_compute_active_count()`, `get_boot_compute_pending_count()`, `get_boot_failed_coords()`).
- `rebuild policy`: initialized at boot start; driven during boot loop until `first_playable`, then unfinished startup coords are handed off to runtime streaming while stale boot worker results are discarded. Not persisted.
- `invariants`:
- `assert(active_compute_tasks <= BOOT_MAX_CONCURRENT_COMPUTE, "bounded concurrency must be enforced")`
- `assert(no_chunk_has_more_than_one_active_compute_task, "duplicate compute races must be blocked")`
- `assert(worker_output_contains_only_serializable_payloads_and_metrics, "worker results may include native_data, flora_payload, generation, and timing metadata — never scene-tree objects")`
- `assert(stale_generation_results_are_discarded, "results from previous boot generations must not be applied")`
- `assert(empty_native_data_is_treated_as_failure, "failed compute does not silently advance readiness — chunk remains unresolved or is re-enqueued into runtime load")`
- `assert(applied_chunks_per_step <= BOOT_MAX_APPLY_PER_STEP, "main-thread install/attach budget is enforced per boot step")`
- `assert(apply_queue_sorted_by_distance, "near-player chunks are always applied before far chunks")`
- `assert(first_playable_exits_boot_loop_early, "boot_load_initial_chunks returns on first_playable; unfinished startup coords are runtime-enqueued instead of being faked complete")`
- `assert(ring_0_first_playable_waits_for_scheduler_owned_full_publication, "player-adjacent startup chunks reach first_playable only after scheduler-owned full publication convergence; boot apply does not call complete_terrain_phase_now() as a visibility shortcut")`
- `assert(non_player_startup_apply_is_install_only, "non-player boot apply step is install/attach + cache hookup without synchronous terrain/full redraw")`
- `write operations`:
- `ChunkBootPipeline.submit_pending_tasks()`
- `ChunkBootPipeline.worker_compute()` (mutex-protected result write)
- `ChunkBootPipeline.collect_completed()`
- `ChunkBootPipeline.drain_computed_to_apply_queue()`
- `ChunkBootPipeline.prepare_apply_entries()`
- `ChunkBootPipeline.apply_from_queue()`
- `ChunkBootPipeline.start_runtime_handoff()`
- `ChunkBootPipeline.tick_remaining()`
- `ChunkBootPipeline.cleanup_compute_pipeline()`
- `ChunkBootPipeline.wait_all_compute()`
- `ChunkManager._boot_submit_pending_tasks()` facade forwarding to `ChunkBootPipeline.submit_pending_tasks()`
- `ChunkManager._boot_worker_compute()` facade forwarding to `ChunkBootPipeline.worker_compute()`
- `ChunkManager._boot_collect_completed()` facade forwarding to `ChunkBootPipeline.collect_completed()`
- `ChunkManager._boot_drain_computed_to_apply_queue()` facade forwarding to `ChunkBootPipeline.drain_computed_to_apply_queue()`
- `forbidden writes`:
- Worker threads must not create `Chunk` nodes, `TileMapLayer` objects, or any scene-tree references.
- Boot compute submission must remain internal to `ChunkManager`; no public gameplay API for submitting boot compute.
- Unbounded submission of all startup chunks without concurrency cap is forbidden.
- `emitted events / invalidation signals`:
- none; queue state is polled from the boot loop.

## Postconditions: `generate chunk`

### Authoritative orchestration points

- Direct synchronous runtime load path is removed from `ChunkStreamingService.load_chunk_for_z()`. The legacy facade may only reject already-loaded/invalid requests, hard-block player-reachable surface calls, or enqueue a non-surface request for the same async/staged pipeline; it must not build native data, create a `Chunk`, or call `ChunkManager._finalize_chunk_install()` in one main-thread path.
- Staged streaming load path: `_worker_generate()` / surface-cache stage -> `ChunkManager._stage_prepared_chunk_install()` facade -> `ChunkStreamingService.stage_prepared_chunk_install()` -> shell create in `ChunkStreamingService.staged_loading_create()` -> resumable `ChunkStreamingService.staged_loading_finalize()` substeps (`payload_attach`, `scene_attach`, `visual_enqueue`, `topology`, `eventbus`, `visibility`) -> `ChunkManager._finalize_chunk_install_stage()`. During `payload_attach`, `Chunk.populate_native()` captures terminal surface final-packet proof; without that proof, later `FULL_READY` and visibility publication are blocked. The compatibility `_finalize_chunk_install()` path is a stage wrapper for boot/internal apply, not permission to drain topology/visual/seam/shadow synchronously in one runtime step.
- Surface generation path on runtime surface cache miss: `ChunkStreamingService.submit_async_generate()` -> `_worker_generate()` -> detached `ChunkContentBuilder.build_chunk_native_data()` / `WorldGenerator.build_chunk_native_data()` -> `ChunkManager._complete_surface_final_packet_publication_payload()` -> ready queue -> `ChunkStreamingService.stage_prepared_chunk_install()` -> shell create -> staged payload attach/follow-up enqueue/publish gate -> visual scheduler.
- Surface generation path on worker/staged surface cache miss: detached `ChunkContentBuilder.build_chunk_native_data()` or `WorldGenerator.build_chunk_native_data()` -> `ChunkManager._complete_surface_final_packet_publication_payload()` -> `Chunk.populate_native()`.
- Underground generation path: `ChunkManager._generate_solid_rock_chunk()` -> `Chunk.populate_native()`.

### Success path

- Requested chunk coordinates are canonicalized before generation or load.
- Surface load can reuse cached native payload and cached flora payload/result entries through `ChunkSurfacePayloadCache`. Cached native payload replay is allowed only for terminal surface packets that pass validation on write and read; otherwise the entry is rejected or evicted and the chunk must regenerate rather than replay incomplete data.
- Surface load/install boundaries now require the versioned terminal `frontier_surface_final_packet` envelope. Missing packet metadata, missing `flora_placements`, missing required `flora_payload` for non-empty flora placements, missing prebuilt flora render packet, or broken tiled-array alignment are contract failures for player-reachable runtime, not permission to fall back to an older structured export.
- Player-reachable surface runtime never installs by calling the direct synchronous `load_chunk_for_z()` path. Cache hits may stage already-validated packet duplicates, and cache misses must go through async generate, ready queue promotion, staged create, staged finalize with terminal packet proof capture, and then visual scheduler publication.
- Surface chunk generation writes per-tile `terrain`, `height`, `variation`, and `biome` into native payload arrays. `flora_density_values` and `flora_modulation_values` are also generated in the payload for surface chunks. `variation` remains presentation-only metadata; polar overlays live there instead of expanding canonical terrain types.
- Surface native payloads also carry serialized `flora_placements`; an empty Array is a valid "no flora" result, but a missing `flora_placements` key is a contract failure for player-reachable runtime. When `flora_placements` is non-empty, the packet must also carry `flora_payload` with matching canonical chunk coord/chunk size, matching placement count, and a prebuilt pure-data `render_packet`.
- The normal runtime path passes only compact request metadata (`native_chunk_generation_request_v1`) to `ChunkGenerator.generate_chunk()`. Per-tile channel/prepass/structure sampling and `feature_and_poi_payload` assembly are owned by C++ and read the immutable `WorldPrePass` snapshot plus native noise/biome/feature/POI params initialized at world setup; the old `world_chunk_authoritative_inputs_v1` bridge is deleted and any attempt to bypass the native request contract is a fail-closed error.
- Surface chunk generation may additionally write presentation-only derived arrays `rock_visual_class`, `ground_face_atlas`, `cover_mask`, `cliff_overlay`, `variant_id`, and `alt_id`. In player-reachable native generation these arrays must come from native `ChunkVisualKernels.build_prebaked_visual_payload()`; missing native visual packet construction is a fail-closed error, not permission to use GDScript visual convergence. The arrays are computed from the current chunk arrays plus a one-tile seam halo so terrain/cover/cliff visual phases can reuse ready buffers instead of rebuilding neighbor lookup state for pristine chunks.
- Current surface generation does not assign `MINED_FLOOR` or `MOUNTAIN_ENTRANCE`. Mountain boundary tiles generated by `SurfaceTerrainResolver._resolve_surface_terrain_sq()` remain `ROCK` even when adjacent to open exterior terrain.
- Chunk generation does not publish a generic wall-neighbor mask or terrain-peering API as canonical chunk data. Any stored `rock_visual_class` / `ground_face_atlas` / `cover_mask` / `cliff_overlay` / `variant_id` / `alt_id` buffers remain presentation-only derived state.
- `Chunk.populate_native()` installs native arrays, loads the presentation payload cache when array sizes match, reapplies saved modifications through `_apply_saved_modifications()`, invalidates the presentation cache if saved terrain diffs exist, recalculates `_has_mountain`, resets cover visual state, and starts redraw.
- Saved modifications are replayed as direct tile writes and then re-normalized for affected open tiles plus their cardinal same-chunk neighbors before redraw starts.
- Streamed chunks begin progressive redraw through `_begin_progressive_redraw()`, enter `ChunkVisualState.NATIVE_READY`, and remain hidden until terminal `Chunk.is_full_redraw_ready()` publication closes. For surface chunks, `Chunk.is_full_redraw_ready()` now also requires terminal `frontier_surface_final_packet` proof captured during `populate_native()`. Internal first-pass milestones may still advance scheduler bookkeeping, but they do not authorize visibility, occupancy, or publish-now/finish-later semantics. When the surface presentation payload cache is valid, terrain/cover/cliff phase batches may skip neighbor derivation and only apply ready buffers; if native critical compute is unavailable for a player-reachable chunk, runtime must emit a zero-tolerance breach and block the path rather than fall back to legacy script convergence or keep the chunk visible while convergence debt remains.
- Boot loading tracks per-chunk readiness through `BootChunkState` transitions `QUEUED_COMPUTE -> COMPUTED -> QUEUED_APPLY -> APPLIED`, with `APPLIED <-> VISUAL_COMPLETE` remaining revocable until final convergence settles. Aggregate gates `first_playable` (ring 0..1 honest full-ready publication, topology NOT required inside `ChunkManager`) and `boot_complete` (all startup chunks currently terminal/full-ready + topology ready) are updated after each chunk. Ring distance uses Chebyshev metric (`max(abs(dx), abs(dy))`), so diagonal chunks at offset (1,1) are ring 1 — critical for 4-chunk junction spawns. `first_playable` is now an internal boot-finalization milestone: `GameWorld` may start shadow/topology completion there, but player input/physics/loading-screen dismissal wait for the full boot-ready handoff after shadows are drained. See `Layer: Boot Readiness`.
- Boot loading does not fake terminal state for unfinished startup coords after handoff. Remaining startup coords are enqueued into runtime streaming, stay boot-tracked, and only contribute to `boot_complete` after real apply/redraw progress. Topology readiness is part of `boot_complete` but not the internal `first_playable` gate; player-visible handoff additionally waits for boot shadow completion.
- Surface flora presentation is installed from the packet/cached `flora_payload` when the pristine surface path has no saved terrain modifications. Runtime may reuse cached flora payload/result entries, but it must not synthesize missing terminal flora from a legacy script fallback when the final packet contains non-empty `flora_placements`. Publication of that flora is presentation-only and routes through worker-prepared pure-data render packets plus a single chunk-local `ChunkFloraPresenter` on the main thread, backed by a shared texture cache rather than per-chunk texture ownership or per-placement scene-tree churn. Runtime flora texture priming must use non-blocking threaded resource requests; if a texture is not yet cached, the presenter may draw the packet's fallback color until the threaded load resolves, but it must not call synchronous `ResourceLoader.load()` from visual apply or draw paths.
- Underground chunks are marked with `set_underground(true)` before `populate_native()` and then receive a fog layer through `init_fog_layer()` after population.
- Once the chunk is inserted into `_loaded_chunks`, terrain reads and interaction paths use its loaded data even if progressive redraw is still in progress for that chunk.
- Surface topology is not built inside `Chunk.populate_native()`. After the chunk is attached and registered, `ChunkManager` invalidates topology through native `set_chunk(...); _native_topology_dirty = true`; there is no GDScript topology dirty fallback.
- `EventBus.chunk_loaded` is emitted after chunk registration and topology invalidation, not after topology readiness.

### Current non-guarantees

- Chunk generation/load does not auto-classify boundary `ROCK` as `MOUNTAIN_ENTRANCE`.
- Chunk generation/load does not expose a generic persisted wall-neighbor mask API. Mutated or otherwise invalidated chunks still derive wall/cover/cliff visuals later during redraw from current neighbor terrain reads.
- Save replay still does not normalize cross-chunk open-tile state for unloaded neighbor chunks until those chunks are loaded.
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
- Same-chunk `3x3` dirty tiles are queued into scheduler-owned dirty-batch work for terrain, cover, and cliff presentation; worker prep computes ready commands and main-thread apply publishes the bounded TileMap mutations.
- Same-chunk cardinal neighbors that are `MINED_FLOOR` or `MOUNTAIN_ENTRANCE` are re-normalized through `_refresh_open_neighbors()` and redrawn.
- If the mined tile is on a chunk edge, loaded neighbor chunks receive cross-chunk normalization for the direct cardinal neighbor and a 3-tile border strip redraw through `ChunkSeamService.seam_normalize_and_redraw()` behind the `ChunkManager._seam_normalize_and_redraw()` facade. Cross-chunk normalization for tiles in unloaded neighbor chunks is not performed.
- Surface topology is updated immediately through `_on_mountain_tile_changed()` and may additionally be marked dirty for a background rebuild if split suspicion is detected.
- `EventBus.mountain_tile_mined` is emitted after the immediate topology patch path runs.
- On surface, that mining event must run one sanctioned `MountainRoofSystem` reveal/apply consequence chain even if the player remains outside the newly opened entrance: use a bounded immediate local cover patch when incremental or bootstrap reveal is sufficient, otherwise fall back to the refresh/apply path; stale roof correctness must not depend on `_is_player_on_opened_mountain_tile()`.
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
- Cross-chunk local-zone traversal in `query_local_underground_zone()` stops at unloaded chunks and also reports `truncated = true` when the native open-pocket traversal reaches its explored-tile cap.
- `MountainRoofSystem` only reveals cover for chunks that are currently loaded.
- `MountainShadowSystem` edge detection can read across chunk seams for loaded chunks; when a neighbor chunk is unloaded, the edge-cache snapshot samples detached surface terrain truth rather than querying scene-owned chunk state on the main thread. Full edge-cache build and shadow rasterization require native `MountainShadowKernels`; production runtime must fail closed if those kernels are unavailable instead of running a GDScript full-scan or raster path.
- Surface generation-time visual derivation reads one-tile seam context through `ChunkContentBuilder._build_terrain_halo()` and detached terrain sampling, so initial `rock_visual_class` / `ground_face_atlas` / `cover_mask` / `cliff_overlay` / `variant_id` / `alt_id` buffers do not wait for neighbor chunk nodes to load.
- Surface terrain wall shaping can read cross-chunk neighbor terrain through unloaded fallbacks, because `_surface_rock_visual_class()` goes through `_get_neighbor_terrain()` and `ChunkManager.get_terrain_type_at_global()`.
- Mining at a chunk seam now refreshes neighbor-chunk open tiles and redraws neighbor-chunk border visuals for loaded neighbors through `ChunkSeamService` behind the `ChunkManager._seam_normalize_and_redraw()` facade. Unloaded neighbor chunks are not normalized or redrawn at mining time.

## Loaded Vs Unloaded Read-Path Rules

- `Chunk.get_terrain_type_at(local)` is a loaded-chunk local-array read only.
- `ChunkManager.get_terrain_type_at_global(tile)` is the current authoritative cross-state terrain read:
- If the chunk is loaded, read `Chunk._terrain_bytes`.
- Else, if `_saved_chunk_data` has a saved local override, read that override.
- Else, if active z is underground, return `ROCK`.
- Else, on surface, fall back to `WorldGenerator.get_terrain_type_fast()`.
- `ChunkManager.query_local_underground_zone(seed_tile)` requires the seed tile to be loaded and open in the current active `_loaded_chunks` set. There is no unloaded fallback path, and the answer comes from the active-z native `LoadedOpenPocketQuery` mirror rather than direct chunk-node traversal.
- `ChunkManager.get_mountain_key_at_tile()`, `get_mountain_tiles()`, and `get_mountain_open_tiles()` only expose surface topology and do not synthesize unloaded topology.
- `ChunkManager.has_resource_at_world()` delegates to `get_terrain_type_at_global()` before checking mineable terrain, so it observes the same loaded -> saved overlay -> underground `ROCK` -> surface generator read ladder.
- `ChunkManager.is_walkable_at_world()` delegates to `get_terrain_type_at_global()` and applies `_is_walkable_terrain()` to the result. This matches the authoritative terrain read-path for all cases including unloaded underground tiles.
- Surface terrain atlas selection for unloaded neighbors uses the same read ladder as `get_terrain_type_at_global()`. Underground wall atlas selection also uses that ladder, but underground unloaded fallback collapses to `ROCK`.

## Source Of Truth Vs Derived State

### Source of truth

- Surface generated base terrain: `WorldGenerator` / `ChunkContentBuilder` / `SurfaceTerrainResolver`
- Loaded terrain bytes: `Chunk._terrain_bytes`
- Loaded runtime modification diff: `Chunk._modified_tiles`
- Unloaded runtime modification diff: `ChunkManager._saved_chunk_data`
- Canonical active z selection: private `ZLevelManager._current_z` via `ZLevelManager.change_level()`

### Derived state

- `Chunk._has_mountain`
- `ChunkManager._active_z` as downstream world-stack mirror of canonical z state
- Surface topology caches in `ChunkManager`
- Native `LoadedOpenPocketQuery` active-z terrain mirror in `ChunkManager`
- `ChunkManager.query_local_underground_zone()` result
- `MountainRoofSystem` active local zone and cover-tile maps
- `UndergroundFogState` visible and revealed sets
- `MountainShadowSystem._edge_cache`
- Flora presentation inputs derived from `ChunkBuildResult` or native data

### Presentation-only state

- `Chunk` TileMap layers (including water-adjacent ground/sand face overlays), the chunk-local `ChunkFloraPresenter`, the chunk-local `ChunkFogPresenter` layer node, and the chunk-local `ChunkDebugRenderer`
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
- ~~`Player._on_speed_modifier_changed()` hardcoded `_speed_modifier = 1.0`, so oxygen slowdown did not affect movement speed.~~ **resolved 2026-03-28**: the player now applies the emitted oxygen modifier directly.
- ~~`Player.perform_harvest()` spent harvest cooldown before command success was known, so a failed command could still consume the cooldown window.~~ **resolved 2026-03-28**: harvest cooldown is now committed only after a successful command result with a valid item payload.

### Layer: Health / damage

- `classification`: `canonical`
- `owner`: host entity that owns `core/entities/components/health_component.gd::HealthComponent`
- `writers`:
- `core/entities/components/health_component.gd::take_damage()`
- `core/entities/components/health_component.gd::heal()`
- `core/entities/components/health_component.gd::restore_state()`
- host setup in `core/entities/fauna/basic_enemy.gd::_ready()`
- host setup in `core/entities/structures/thermo_burner.gd::setup()`
- host setup in `core/entities/structures/ark_battery.gd::setup()`
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
- `HealthComponent.restore_state()`
- `forbidden writes`:
- External systems must not assign `current_health` or `max_health` directly on live entities unless they also own the load/setup boundary.
- Gameplay code must not emulate damage by skipping `take_damage()` because that bypasses `health_changed` / `died`.
- `emitted events / invalidation signals`:
- `HealthComponent.health_changed`
- `HealthComponent.died`
- `current violations / ambiguities / contract gaps`:
- ~~`current_health` and `max_health` were written directly by several live load/setup paths without re-emitting `health_changed`.~~ **resolved 2026-03-28**: live setup and save/load restoration now go through `HealthComponent.restore_state()`, which re-emits `health_changed`.
- `HealthComponent` has no component-level `save_state()` / `load_state()` API; persistence is fragmented across host-specific save helpers.

### Layer: Inventory runtime

- `classification`: `canonical`
- `owner`: `core/entities/components/inventory_component.gd::InventoryComponent`
- `writers`:
- `core/entities/components/inventory_component.gd::add_item()`
- `core/entities/components/inventory_component.gd::remove_item()`
- `core/entities/components/inventory_component.gd::move_slot_contents()`
- `core/entities/components/inventory_component.gd::split_stack()`
- `core/entities/components/inventory_component.gd::sort_slots_by_name()`
- `core/entities/components/inventory_component.gd::remove_amount_from_slot()`
- `core/entities/components/inventory_component.gd::remove_slot_contents()`
- `core/entities/components/inventory_component.gd::load_state()`
- orchestration calls from `scenes/ui/inventory/inventory_panel.gd`
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
- `InventoryComponent.move_slot_contents()`
- `InventoryComponent.split_stack()`
- `InventoryComponent.sort_slots_by_name()`
- `InventoryComponent.remove_amount_from_slot()`
- `InventoryComponent.remove_slot_contents()`
- `InventoryComponent.load_state()`
- `forbidden writes`:
- External systems must not mutate `InventoryComponent.slots` or `InventorySlot.item` / `InventorySlot.amount` directly.
- UI code must not become the de facto owner of split/swap/sort/drop semantics.
- `emitted events / invalidation signals`:
- `EventBus.inventory_updated`
- `current violations / ambiguities / contract gaps`:
- ~~`InventoryPanel` directly mutated `InventoryComponent.slots` for swap, split, sort, equip handoff, and drop-outside flows instead of going through component-owned APIs.~~ **resolved 2026-03-28**: UI orchestration now delegates move/split/sort/drop through `InventoryComponent` owner methods.
- ~~There was no authoritative public runtime API for move/split/sort/drop operations; semantics lived partly in UI code.~~ **resolved 2026-03-28**: `InventoryComponent` now owns dedicated move/split/sort/remove entrypoints.

### Layer: Equipment runtime

- `classification`: `canonical`
- `owner`: `core/entities/components/equipment_component.gd::EquipmentComponent`
- `writers`:
- `core/entities/components/equipment_component.gd::equip()`
- `core/entities/components/equipment_component.gd::unequip()`
- `core/entities/components/equipment_component.gd::equip_from_inventory_slot()`
- `core/entities/components/equipment_component.gd::unequip_to_inventory()`
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
- `EquipmentComponent.equip_from_inventory_slot()`
- `EquipmentComponent.unequip_to_inventory()`
- `EquipmentComponent.load_state()`
- `forbidden writes`:
- External systems must not mutate `EquipmentComponent._equipped` directly.
- Inventory/UI flows must not treat `equip()` as a substitute for full inventory + equipment orchestration unless they also handle inventory ownership explicitly.
- `emitted events / invalidation signals`:
- `EquipmentComponent.equipment_changed`
- `current violations / ambiguities / contract gaps`:
- ~~`EquipmentComponent.load_state()` existed at component level, but equipment state was not included in the `SaveManager` flow.~~ **resolved 2026-03-28**: player save/load now collects and restores equipment state through `SaveCollectors.collect_player()` and `SaveAppliers.apply_player()`.
- ~~Inventory/equipment handoff semantics lived in `InventoryPanel`, not in an authoritative runtime orchestration API.~~ **resolved 2026-03-28**: `EquipmentComponent` now owns inventory handoff via `equip_from_inventory_slot()` and `unequip_to_inventory()`.

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
- `core/systems/survival/oxygen_system.gd::_refresh_indoor_state()`
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
- Indoor semantics must not be redefined independently of room topology, loaded mined-floor reads, and `OxygenSystem._refresh_indoor_state()`.
- `emitted events / invalidation signals`:
- `EventBus.oxygen_changed`
- `EventBus.oxygen_depleting`
- `EventBus.player_entered_indoor`
- `EventBus.player_exited_indoor`
- `OxygenSystem.speed_modifier_changed`
- `current violations / ambiguities / contract gaps`:
- ~~`OxygenSystem._on_rooms_recalculated()` was a no-op, so indoor state relied on `GameWorld` polling every frame.~~ **resolved 2026-03-28**: `OxygenSystem` now refreshes indoor state itself on both frame ticks and `rooms_recalculated`.
- Runtime life-support power now enters through `EventBus.life_support_power_changed` into `OxygenSystem._on_life_support_power_changed()`, while `load_state()` remains the persistence boundary for restoring `_is_base_powered`.

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
- `BaseLifeSupport.set_power_demand()`
- `BaseLifeSupport._on_powered_changed()`
- internal `PowerConsumerComponent.set_powered()`
- `forbidden writes`:
- External systems must not mutate the child `PowerConsumerComponent` directly as a substitute for `BaseLifeSupport` ownership.
- Consumers of life-support state must not emit `EventBus.life_support_power_changed` themselves.
- `emitted events / invalidation signals`:
- `EventBus.life_support_power_changed`
- `current violations / ambiguities / contract gaps`:
- ~~`BaseLifeSupport` exposed only `is_powered()` publicly, while demand/config ownership stayed indirect through a child consumer.~~ **resolved 2026-03-28**: `BaseLifeSupport` now exposes owner-owned demand accessors (`set_power_demand()` / `get_power_demand()`) and config writes no longer need to tunnel through the child consumer.

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
- `core/systems/survival/oxygen_system.gd::_refresh_indoor_state()`
- `core/autoloads/save_collectors.gd::collect_buildings()`
- `scenes/ui/build/build_menu_panel.gd::get_selected()`
- `scenes/ui/power_ui.gd::_refresh_generators()`
- `rebuild policy`: immediate placement/removal writes; room topology invalidation is deferred dirty rebuild
- `invariants`:
- `assert(for_all_pos in _walls.keys(): is_instance_valid(_walls[for_all_pos]), "building grid must only point at live building nodes")`
- `assert(for_all_node in unique(_walls.values()): node.get_meta("grid_origin") != null, "every placed building node must expose grid_origin metadata")`
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
- External systems must not mutate `BuildingSystem._walls` or `BuildingPlacementService.walls` directly.
- Placement code must not bypass `BuildingSystem` by inserting/removing nodes in `wall_container` without updating the owner occupancy map and room invalidation.
- Build-mode presentation must not be treated as canonical building state.
- `emitted events / invalidation signals`:
- `EventBus.build_mode_changed`
- `EventBus.building_placed`
- `EventBus.building_removed`
- room invalidation through `BuildingSystem._mark_rooms_dirty()`
- `current violations / ambiguities / contract gaps`:
- ~~`BuildingPlacementService.can_place_at()` only checked scrap and occupied tiles; it did not validate terrain type, walkability, z-context, or other world-placement constraints.~~ **resolved 2026-03-28**: `BuildingSystem.can_place_selected_building_at()` and `place_selected_building_at()` now enforce active-z, walkability, and `ROCK` / `WATER` rejection before placement.
- ~~`BuildingSystem.walls` was a public dictionary shared across placement and persistence helpers.~~ **resolved 2026-03-28**: occupancy is now held behind private `_walls` with read access through `has_building_at()` / `get_building_node_at()`.

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
- `core/systems/survival/oxygen_system.gd::_refresh_indoor_state()`
- `core/systems/survival/oxygen_system.gd::_on_rooms_recalculated()`
- `rebuild policy`: deferred dirty rebuild via `FrameBudgetDispatcher`; synchronous full rebuild on load/boot path
- `invariants`:
- `assert(for_all_cell in indoor_cells.keys(): not _walls.has(for_all_cell), "indoor cells must never overlap occupied building cells")`
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
- ~~Indoor topology was keyed only by 2D grid coordinates with no z-level dimension.~~ **resolved 2026-03-28 for current runtime scope**: authoritative building placement now refuses non-surface z-levels, so supported room topology remains surface-only and cannot alias across active z levels.
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
- `core/systems/power/power_system.gd::_refresh_observed_runtime_configs()`
- `core/entities/components/power_source_component.gd::set_condition()`
- `core/entities/components/power_source_component.gd::set_max_output()`
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
- Owner-only power setter paths must not be used to reconfigure the internal child consumer owned by `BaseLifeSupport`.
- `emitted events / invalidation signals`:
- `EventBus.power_changed`
- `EventBus.power_deficit`
- `EventBus.power_restored`
- `PowerSourceComponent.output_changed`
- `PowerConsumerComponent.powered_changed`
- `PowerConsumerComponent.configuration_changed`
- `current violations / ambiguities / contract gaps`:
- ~~Power source and consumer configuration fields were public, so direct assignment could bypass `output_changed` / `configuration_changed` and leave power state stale until a later dirty mark.~~ **resolved 2026-03-28**: owner paths now use setters, and `PowerSystem._refresh_observed_runtime_configs()` watches registered components for bypass config drift and re-invalidates balance.
- ~~`PowerSystem.save_state()` looked like a persistence API even though authoritative power state lives across components and structure nodes.~~ **resolved 2026-03-28**: the misleading method was replaced with `get_debug_snapshot()`, explicitly documenting aggregate debug/export intent only.

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
- `SpawnOrchestrator.save_enemy_runtime()`
- `SpawnOrchestrator.load_enemy_runtime()`
- `SpawnOrchestrator.clear_pickups()`
- `SpawnOrchestrator.clear_enemies()`
- `SpawnOrchestrator.set_enemy_spawning_enabled()`
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
- ~~`_enemy_spawning_enabled` had no writer in the current code path, so runtime enemy spawning was effectively disabled.~~ **resolved 2026-03-28**: `SpawnOrchestrator.setup()` now enables spawning through `set_enemy_spawning_enabled(true)`.
- ~~Save/load persisted pickups, but not live enemies or spawn timers.~~ **resolved 2026-03-28**: world save/load now serializes `enemy_runtime` through `SpawnOrchestrator.save_enemy_runtime()` / `load_enemy_runtime()`.

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
- ~~Enemy hearing scanned `noise_sources` and the local player globally with no z-level filtering.~~ **resolved 2026-03-28 for current runtime scope**: `BasicEnemy._update_scan()` now drops targets and suppresses perception whenever the active runtime z is not the supported surface layer.

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
- Callers must not treat `EventBus.noise_source_changed` as a persistence or gameplay-state signal; it is a runtime invalidation hint for perception consumers.
- `emitted events / invalidation signals`:
- `EventBus.noise_source_changed`
- `current violations / ambiguities / contract gaps`:
- ~~Noise state had no emitted invalidation signal; enemy AI only noticed changes on the next scan interval.~~ **resolved 2026-03-28**: `NoiseComponent.set_active()` now emits `EventBus.noise_source_changed`, and `BasicEnemy` uses it to pull the next scan immediately.

## Domain: Session & Time

### Layer: Z-level switching / stairs

- `classification`: `canonical`
- `owner`: `core/systems/world/z_level_manager.gd::ZLevelManager` for canonical z state, with `core/systems/world/underground_transition_coordinator.gd::UndergroundTransitionCoordinator` as scene-level blackout/handoff owner and `core/entities/structures/z_stairs.gd::ZStairs` as runtime trigger
- `writers`:
- `core/systems/world/z_level_manager.gd::change_level()`
- `core/autoloads/save_appliers.gd::apply_player()` via `change_level()`
- `core/systems/world/underground_transition_coordinator.gd::request_transition()`
- `core/systems/world/underground_transition_coordinator.gd::_run_transition()`
- `core/entities/structures/z_stairs.gd::_on_body_entered()`
- `core/entities/structures/z_stairs.gd::_trigger_transition()`
- `readers`:
- `core/systems/world/z_level_manager.gd::get_current_z()`
- `scenes/world/game_world.gd::_on_z_level_changed()`
- `core/systems/daylight/daylight_system.gd::_resolve_current_z()`
- `core/entities/structures/z_stairs.gd::_on_z_level_changed()`
- `core/systems/world/chunk_manager.gd::is_active_player_hot_envelope_full_ready()`
- `rebuild policy`: controlled hidden transition; `GameWorld.request_z_transition()` fades to black, hides world publication through `ChunkManager.set_transition_hidden(true)`, performs the canonical `ZLevelManager.change_level()`, waits until the active player hot `3x3` envelope reports `full_ready`, then restores publication and allows fade-in
- `invariants`:
- `assert(_current_z >= Z_MIN and _current_z <= Z_MAX, "active z level must remain within declared bounds")`
- `assert(new_z != current_z_before_emit, "z_level_changed must only emit on real z transitions")`
- `assert(chunk_manager_active_z == _current_z after downstream_sync, "ChunkManager._active_z must mirror canonical z after signal-driven world sync")`
- `assert(fade_in_waits_for_active_player_hot_envelope_full_ready, "controlled z transition may not reveal the target level before the active hot envelope is terminal full_ready")`
- `assert(chunk_manager_transition_hidden_masks_runtime_publication_during_blackout, "controlled blackout must hide chunk publication while the target z-level is still converging")`
- `assert(not monitoring or visible, "stairs monitoring must match current visible source_z context")`
- `write operations`:
- `ZLevelManager.change_level()`
- `scenes/world/game_world.gd::request_z_transition()`
- `UndergroundTransitionCoordinator.request_transition()`
- `ChunkManager.set_transition_hidden()`
- `ZStairs._trigger_transition()`
- `forbidden writes`:
- External systems must not assign `ZLevelManager._current_z` directly.
- External systems must not call `ChunkManager.set_active_z_level()` as a primary z-switch API; it is a downstream world-stack sink driven by `scenes/world/game_world.gd::_on_z_level_changed()`.
- External systems must not bypass `GameWorld.request_z_transition()` by calling `ZLevelManager.change_level()` directly for staircase traversal; that skips blackout/readiness gating owned by `UndergroundTransitionCoordinator`.
- Callers must not treat `ChunkManager.get_active_z_level()` as global z source of truth when `ZLevelManager` is available.
- `emitted events / invalidation signals`:
- `ZLevelManager.z_level_changed`
- `EventBus.z_level_changed`
- `current violations / ambiguities / contract gaps`:
- ~~`ZLevelManager.current_z` was a public mutable field, so external code could bypass `change_level()` and skip event emission.~~ **resolved 2026-03-28**: canonical z state is now private `_current_z`, readable only through `get_current_z()`.
- `ChunkManager` still stores mirrored `_active_z`, but it is now a downstream sink updated from canonical `ZLevelManager` transitions rather than a competing owner path.
- ~~`ZStairs` reached into `GameWorld`, `ZLevelManager`, and overlay internals directly.~~ **resolved 2026-03-28**: stairs now go through `GameWorld.request_z_transition()` as the scene-orchestration entrypoint.
- **resolved 2026-04-15**: staircase transitions no longer use blind `overlay -> change_level -> fade-in`; `UndergroundTransitionCoordinator` now holds the runtime under controlled blackout until the target hot envelope reaches terminal `full_ready`.

### Layer: Time / calendar / day-night

- `classification`: `canonical`
- `owner`: `core/autoloads/time_manager.gd::TimeManagerSingleton`
- `writers`:
- `core/autoloads/time_manager.gd::reset_for_new_game()`
- `core/autoloads/time_manager.gd::restore_persisted_state()`
- `core/autoloads/time_manager.gd::set_paused()`
- `core/autoloads/time_manager.gd::set_time_scale()`
- `core/autoloads/time_manager.gd::_process()`
- `core/autoloads/time_manager.gd::_apply_authoritative_time_state()`
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
- `TimeManager.set_paused()`
- `TimeManager.set_time_scale()`
- frame-driven `_advance_time()`
- `forbidden writes`:
- External systems must not mutate `current_hour`, `current_day`, `current_season`, `_is_paused`, or `_time_scale` directly as a substitute for a documented API.
- Presentation systems must not redefine time-of-day phase semantics outside `TimeManager`.
- `emitted events / invalidation signals`:
- `EventBus.time_tick`
- `EventBus.hour_changed`
- `EventBus.time_of_day_changed`
- `EventBus.day_changed`
- `EventBus.season_changed`
- `current violations / ambiguities / contract gaps`:
- ~~`TimeManager.is_paused` and `TimeManager.time_scale` were public mutable fields, and callers wrote them directly because no public pause/resume API existed.~~ **resolved 2026-03-28**: time pause/scale now go through `set_paused()` / `set_time_scale()`, while the mutable fields became private probes.

### Layer: Save / load orchestration

- `classification`: `canonical`
- `owner`: `core/autoloads/save_manager.gd::SaveManagerSingleton`
- `writers`:
- `core/autoloads/save_manager.gd::save_game()`
- `core/autoloads/save_manager.gd::load_game()`
- `core/autoloads/save_manager.gd::delete_save()`
- `core/autoloads/save_manager.gd::request_load_after_scene_change()`
- `core/autoloads/save_manager.gd::consume_pending_load_slot()`
- `core/autoloads/save_manager.gd::clear_pending_load_request()`
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
- `assert(SaveAppliers.apply_world() restores saved mountain and hydrology generation overrides into WorldGenerator.balance before WorldGenerator.initialize_world(), "load_game() must rebuild the same deterministic world-generation inputs for the saved slot instead of silently falling back to current default balance values")`
- `assert(_pending_load_slot == "" or _pending_load_slot == current_slot or not is_busy, "pending load slot remains an explicit queued slot string, not hidden busy-state ownership")`
- `write operations`:
- `SaveManager.save_game()`
- `SaveManager.load_game()`
- `SaveManager.delete_save()`
- `SaveManager.request_load_after_scene_change()`
- `SaveManager.consume_pending_load_slot()`
- `SaveManager.clear_pending_load_request()`
- `SaveAppliers.apply_world()`
- `SaveAppliers.apply_chunk_data()`
- `SaveAppliers.apply_time()`
- `SaveAppliers.apply_buildings()`
- `SaveAppliers.apply_player()`
- `forbidden writes`:
- UI and scene code must not mutate `SaveManager.current_slot`, `SaveManager.is_busy`, or `SaveManager._pending_load_slot` directly.
- UI code must not bypass `SaveManager.get_save_list()` / `delete_save()` with direct filesystem logic.
- Helper layers must not redefine save schema outside `SaveCollectors` / `SaveAppliers`.
- `emitted events / invalidation signals`:
- `EventBus.save_requested`
- `EventBus.save_completed`
- `EventBus.load_completed`
- `current violations / ambiguities / contract gaps`:
- ~~`SaveLoadTab` bypassed `SaveManager.get_save_list()` / `delete_save()` and wrote `pending_load_slot` directly.~~ **resolved 2026-03-28**: save/load UI now routes list/delete/load-queue orchestration through `SaveManager`.
- ~~`SaveLoadTab._on_save_pressed()` ignored the boolean result of `SaveManager.save_game()`.~~ **resolved 2026-03-28**: save success UI now depends on the actual boolean result of `save_game()`.

## Сводка текущих нарушений и contract gaps

| # | Слой | Нарушение | Severity | Симптом для игрока |
| --- | --- | --- | --- | --- |
| 1 | World | ~~`Chunk.get_terrain_type_at()` возвращает `GROUND` для невалидного local index вместо fail-fast~~ **resolved 2026-03-28** | ~~medium~~ | ~~Ошибочный вызов может тихо маскироваться под открытую землю и давать неверные визуальные или gameplay-решения~~ |
| 2 | World | ~~`Chunk.populate_native()` молча сбрасывает несовпавшие `variation` / `biome` массивы~~ **resolved 2026-03-28** | ~~medium~~ | ~~После загрузки chunk может потерять вариативность поверхности или biome palette и выглядеть не так, как ожидалось~~ |
| 3 | World | ~~`is_walkable_at_world()` для unloaded underground идёт через `WorldGenerator.is_walkable_at()`, а terrain fallback считает tile `ROCK`~~ **resolved 2026-03-27** | ~~high~~ | ~~Проверки проходимости и фактическое terrain-чтение могут расходиться на unloaded underground tiles~~ |
| 4 | World | ~~`has_resource_at_world()` не имеет unloaded fallback~~ **resolved 2026-03-28** | ~~medium~~ | ~~Добываемый ресурс на unloaded tile не виден системам, пока chunk не подгрузится~~ |
| 5 | World | ~~`populate_native()` переигрывает сохранённые terrain-модификации без neighbor re-normalization~~ **resolved 2026-03-28** | ~~medium~~ | ~~Неконсистентный save diff может загрузить cave opening с устаревшим `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` состоянием~~ |
| 6 | Mining | ~~`Chunk.try_mine_at()` не является безопасной orchestration point~~ **resolved 2026-03-28** | ~~high~~ | ~~Любой обходной путь, который вызовет прямую мутацию, сможет выкопать tile без корректного обновления topology / reveal / visuals~~ |
| 7 | Mining | ~~Текущий mining path не делает automatic open-tile re-normalization соседей~~ **resolved 2026-03-27** | ~~high~~ | ~~После раскопки соседние `MINED_FLOOR` / `MOUNTAIN_ENTRANCE` tiles могут сохранить устаревшее состояние~~ |
| 8 | Mining | ~~Отсутствует cross-chunk redraw после mining~~ **resolved 2026-03-27** | ~~high~~ | ~~После копания на шве соседний chunk может оставаться визуально устаревшим~~ |
| 9 | Mining | ~~Debug direct writers обходят normal invalidation chain~~ **resolved 2026-03-28** | ~~medium~~ | ~~Debug-операции могут оставлять мир в частично обновлённом состоянии~~ |
| 10 | Topology | Topology loaded-bubble scoped, а не world-global | medium | Связность горы и open pocket обрывается на границе выгруженного мира |
| 11 | Topology | ~~GDScript incremental topology patch использовал эвристику split detection~~ **resolved 2026-04-13** | ~~high~~ | ~~После некоторых раскопок topology может временно отставать или неверно склеивать / разделять компоненты до full rebuild~~ |
| 12 | Topology | ~~Progressive rebuild не коммитит `*_by_chunk` topology maps~~ **resolved 2026-03-28** | ~~medium~~ | ~~Будущий chunk-scoped reader может получить неполные или пустые topology-структуры после progressive rebuild~~ |
| 13 | Topology | ~~Staging `*_by_chunk` словари существуют, но не участвуют в progressive flow~~ **resolved 2026-03-28** | ~~low~~ | ~~Код создаёт ложное впечатление, что chunk-scoped progressive rebuild уже поддержан~~ |
| 14 | Reveal | `zone_kind` и `truncated` собираются, но почти не влияют на runtime behavior | medium | Игрок увидит обрыв reveal на границе подгрузки без специальной обработки или обратной связи |
| 15 | Reveal | Surface reveal loaded-bubble scoped | medium | Раскрытие локальной пещеры обрывается на unloaded boundary даже если pocket продолжается дальше |
| 16 | Reveal | ~~`Chunk` одновременно держит `set_revealed_local_zone()` и `set_revealed_local_cover_tiles()`~~ **resolved 2026-03-28** | ~~low~~ | ~~Новый вызователь может выбрать не тот entrypoint и получить лишний слой преобразования или рассинхрон~~ |
| 17 | Reveal | Underground fog shared across underground runtime and cleared on z change | medium | Исследованность underground не образует устойчивую непрерывную историю между разными underground floors / z-переходами |
| 18 | Presentation | ~~Cross-chunk mining redraw gap протекает прямо в presentation~~ **resolved 2026-03-27** (for loaded neighbor chunks) | ~~high~~ | ~~Игрок увидит, что соседняя стена / cover / cliff на границе чанка не обновилась после копания~~ |
| 19 | Presentation | Presentation существует только для loaded chunks | low | Продолжение мира вне loaded bubble не имеет visual object до стриминга, даже если terrain-query уже может ответить |
| 20 | Presentation | ~~Debug direct writers могут перерисовать visuals вне world -> mining -> topology -> reveal chain~~ **resolved 2026-03-28** | ~~medium~~ | ~~Отладочное изменение может дать картинку, не совпадающую с реальным derived state~~ |
| 21 | Wall Atlas Selection | ~~Surface и underground wall shaping используют разные openness contracts и разные neighbor sets~~ **resolved 2026-03-28** | ~~medium~~ | ~~Одинаково выглядящая граница rock/open space может рисоваться по-разному на surface и underground~~ |
| 22 | Player actor | ~~`Player._on_speed_modifier_changed()` игнорирует модификатор O₂ и фиксирует `_speed_modifier = 1.0`~~ **resolved 2026-03-28** | ~~medium~~ | ~~Низкий кислород не замедляет игрока, хотя survival layer сообщает о штрафе~~ |
| 23 | Player actor | ~~`perform_harvest()` тратит cooldown до подтверждения успеха команды~~ **resolved 2026-03-28** | ~~medium~~ | ~~Неудачная попытка добычи может всё равно отправить игрока на откат действия~~ |
| 24 | Health / damage | ~~`HealthComponent` имеет публичные поля, а load/setup path пишет их напрямую без сигнала~~ **resolved 2026-03-28** | ~~medium~~ | ~~UI или логика, слушающая `health_changed`, может не увидеть восстановленное после загрузки здоровье~~ |
| 25 | Inventory runtime | ~~`InventoryPanel` напрямую мутирует `InventoryComponent.slots` для swap/split/sort/drop~~ **resolved 2026-03-28** | ~~high~~ | ~~Инвентарь можно изменить в обход owner-layer, что повышает риск рассинхрона между UI и runtime-логикой~~ |
| 26 | Equipment runtime | ~~Экипировка не входит в текущий save/load path~~ **resolved 2026-03-28** | ~~medium~~ | ~~После загрузки сохранения экипированные предметы пропадают или сбрасываются~~ |
| 27 | Oxygen / survival | ~~`OxygenSystem._on_rooms_recalculated()` пустой, indoor-state держится на scene-level polling из `GameWorld`~~ **resolved 2026-03-28** | ~~medium~~ | ~~Изменение комнат может отразиться на кислороде только через внешний glue path, а не через явный owner contract~~ |
| 28 | Base life support | ~~Authoritative consumer живёт во внутреннем child-ноде без отдельного public contract на мутацию demand/config~~ **resolved 2026-03-28** | ~~low~~ | ~~Сторонний код может залезть во внутренний consumer и изменить поведение жизнеобеспечения в обход owner-layer~~ |
| 29 | Building runtime | ~~`BuildingPlacementService.can_place_at()` не проверяет terrain/walkability/z-constraints~~ **resolved 2026-03-28** | ~~high~~ | ~~Постройку можно поставить в логически неподходящем месте~~ |
| 30 | Building runtime | ~~`BuildingSystem.walls` публичен и разделяется между несколькими helper paths~~ **resolved 2026-03-28** | ~~medium~~ | ~~Внешний код может испортить occupancy-map без корректного room/power invalidation chain~~ |
| 31 | Indoor topology | ~~Indoor room state keyed only by 2D grid and has no z dimension~~ **resolved 2026-03-28 for current runtime scope** | ~~low~~ | ~~Если строительство выйдет за surface-only контекст, комнаты разных уровней начнут алиаситься в одну сетку~~ |
| 32 | Power network | ~~Public power config fields можно менять в обход setter-ов и dirty invalidation~~ **resolved 2026-03-28** | ~~high~~ | ~~Баланс энергии и brownout-решения могут запаздывать или считаться по устаревшим данным~~ |
| 33 | Power network | ~~`PowerSystem.save_state()` выглядит как persistence API, хотя authoritative power state живёт в компонентах и структурах~~ **resolved 2026-03-28** | ~~low~~ | ~~Новый вызователь может сохранить/восстановить не ту форму состояния и получить ложный “успешный” результат~~ |
| 34 | Spawn / pickup orchestration | ~~`_enemy_spawning_enabled` нигде не включается~~ **resolved 2026-03-28** | ~~high~~ | ~~Новые враги не спавнятся вообще~~ |
| 35 | Spawn / pickup orchestration | ~~Save/load сохраняет pickups, но не врагов и не spawn timers~~ **resolved 2026-03-28** | ~~medium~~ | ~~После загрузки hostile population сбрасывается~~ |
| 36 | Enemy AI / fauna | ~~Сканирование игрока и noise sources не фильтруется по z-level~~ **resolved 2026-03-28 for current runtime scope** | ~~medium~~ | ~~Существо может реагировать на шум или игрока с другого уровня, если такие акторы одновременно живы~~ |
| 37 | Noise / hearing input | ~~Noise layer не эмитит invalidation signal, реакция идёт только на следующем scan tick~~ **resolved 2026-03-28** | ~~low~~ | ~~Реакция врагов на включение/выключение шумного объекта может ощущаться запаздывающей~~ |
| 38 | Z-level switching | ~~`ZLevelManager.current_z` публично мутируемый и может быть изменён в обход `change_level()`, что также рискует рассинхронизировать downstream mirror `ChunkManager._active_z`~~ **resolved 2026-03-28** | ~~medium~~ | ~~Смена уровня может не запустить синхронизацию мира, света и теней~~ |
| 39 | Z-level switching | ~~`ZStairs` напрямую ищет `GameWorld`, `ZLevelManager` и overlay в scene tree~~ **resolved 2026-03-28** | ~~low~~ | ~~Любой новый триггер перехода рискует скопировать internal glue и пропустить нужные side-effects~~ |
| 40 | Time / calendar | ~~`TimeManager.is_paused` и `time_scale` меняются напрямую из внешнего кода~~ **resolved 2026-03-28** | ~~medium~~ | ~~Время можно заморозить/ускорить в обход явного API и без централизованного контракта~~ |
| 41 | Save / load orchestration | ~~`SaveLoadTab` обходит `SaveManager` при listing/delete/load-request orchestration~~ **resolved 2026-03-28** | ~~high~~ | ~~UI и canonical save-layer могут разойтись по поведению и error handling~~ |
| 42 | Save / load orchestration | ~~`SaveLoadTab._on_save_pressed()` не проверяет результат `SaveManager.save_game()`~~ **resolved 2026-03-28** | ~~medium~~ | ~~Игрок может увидеть “сохранено”, хотя запись не удалась~~ |

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
