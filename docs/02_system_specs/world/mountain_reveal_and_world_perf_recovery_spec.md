---
title: Mountain Reveal And World Perf Recovery Spec
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-09
depends_on:
  - DATA_CONTRACTS.md
  - native_chunk_generation_spec.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
related_docs:
  - boot_topology_integration_spec.md
  - streaming_redraw_budget_spec.md
  - ../../04_execution/world_startup_and_runtime_perf_investigation.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
---

# Feature: Mountain Reveal And World Perf Recovery

## Design Intent

This spec exists to fix two player-facing failures that are currently coupled:

1. mining a mountain tile sometimes leaves stale roof cover visible even though the tile is already opened
2. mining, traversal, and staged world initialization still land too much work on the main thread, creating visible hitches and budget overruns

The implementation policy is deliberately strict:

- Iteration 1 fixes correctness first. The roof bug must disappear before any broader optimization work is allowed to hide it.
- Iteration 2 removes as much reveal/topology/runtime consequence work from the main thread as possible without introducing a second world model.
- Iteration 3 moves the remaining heavy pure-data math and bridge-heavy world-generation work into native C++ kernels where the measured GDScript path still fails budget.

The accepted end state is:

- mining correctness does not depend on where the player is standing
- the synchronous part of mining stays local and within interactive contract
- reveal/topology/shadow consequences run through dirty queues, worker tasks, or bounded incremental steps
- `WorldPrePass` remains the single authoritative source of macro world truth even after native migration

## Measured baseline

The current spec is based on the 2026-04-09 runtime/boot investigation and the archived runtime log reviewed for this task.

Measured hotspots:

- `WorldGenerator._setup_world_pre_pass.compute`: `5995.06 ms`
- `WorldPrePass.compute.rain_shadow`: `1166.30 ms`
- `WorldPrePass.compute.flow_accumulation`: `982.28 ms`
- `WorldPrePass.compute.flow_directions`: `923.53 ms`
- `WorldPrePass.compute.lake_aware_fill`: `653.75 ms`
- `WorldPrePass.compute.slope_grid`: `533.54 ms`
- `WorldPrePass.compute.erosion_proxy`: `442.17 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `421.97 ms`
- `ChunkManager.query_local_underground_zone`: repeated `9-19 ms` warnings against a `2.0 ms` contract
- `MountainRoofSystem._refresh_local_zone`: repeated `43-64 ms` warnings against a `2.0 ms` contract
- `MountainRoofSystem._request_refresh`: repeated `43-64 ms` warnings against a `4.0 ms` contract
- `MountainRoofSystem._process_cover_step`: repeated `10-47 ms` warnings against a `2.0 ms` contract
- `FrameBudgetDispatcher.topology.chunk_manager.topology_rebuild`: spikes up to `178.28 ms`
- `slow native generate_chunk`: repeated `575-859 ms`

These numbers are not accepted steady-state behavior under `PERFORMANCE_CONTRACTS.md`.

## Affected PERFORMANCE_CONTRACTS.md sections

- `§1.2 Background work`
- `§1.3 Interactive work`
- `§1.4 Interactive whitelist`
- `§2.2 Background budget targets`
- `§2.3 Interactive contracts`
- `§4 Dirty Queue + Budget`
- `§6 Precompute / Native Cache`
- `§8 Incremental Update`

## Public API impact

Current public APIs affected semantically:

- `ChunkManager.try_harvest_at_world(world_pos: Vector2) -> Dictionary`
- `ChunkManager.query_local_underground_zone(seed_tile: Vector2i) -> Dictionary`
- `ChunkManager.get_mountain_key_at_tile(tile_pos: Vector2i) -> Vector2i`
- `ChunkManager.get_mountain_open_tiles(mountain_key: Vector2i) -> Dictionary`
- `WorldGenerator.build_chunk_native_data(chunk_coord: Vector2i) -> Dictionary`
- `ChunkGenerator.generate_chunk(chunk_coord: Vector2i, spawn_tile: Vector2i, authoritative_inputs: Dictionary) -> Dictionary`

Required API/documentation outcome after implementation:

- `ChunkManager.try_harvest_at_world()` remains the only sanctioned mining mutation entrypoint.
- `MountainRoofSystem` still does not gain a public manual refresh API.
- `PUBLIC_API.md` must stop implying that roof refresh correctness depends on the player already standing on an opened mountain tile.
- If `query_local_underground_zone()` remains in the codebase after Iteration 2, its docs must explicitly describe it as a loaded-bubble fallback/debug-oriented query rather than the primary hot-path reveal truth.
- If Iteration 3 changes how authoritative chunk-local inputs are packed or cached for native generation, `PUBLIC_API.md` must describe the bridge semantics at `WorldGenerator.build_chunk_native_data()` and `ChunkGenerator.generate_chunk()` without introducing a second world-truth path.

## Required runtime policy

### Interactive mining policy

The synchronous part of mining is limited to:

- mutate one terrain tile through the sanctioned path
- renormalize the immediate same-chunk / seam-local neighbors already owned by the mining orchestration
- enqueue topology, reveal, and shadow dirty work
- publish the immediate local response that keeps the action feeling responsive

Forbidden in the synchronous mining chain:

- full loaded-bubble BFS over opened mountain tiles
- full topology snapshot rebuild
- full cover recompute for the whole active local zone
- mass `TileMap` erase/redraw beyond the local patch

### Background reveal / topology policy

Reveal, topology, and shadow consequences must follow:

`mine event -> dirty unit queue -> budgeted or worker processing -> bounded main-thread apply`

Dirty units for this spec are:

- one mined tile
- one touched chunk seam
- one affected loaded topology component
- one prepared per-chunk cover/shadow delta payload

### Native migration policy

Native migration is allowed only for pure-data kernels or native-side cache/packing work.

Forbidden native migration:

- a second structure model beside `WorldPrePass`
- scene-tree reads or writes from C++
- native code silently synthesizing alternate ridge/river/mountain truth when authoritative data is missing

## Data Contracts — new and affected

### New layers

No new canonical world layer is introduced by this spec.

### Affected layer: Mining

- What changes:
  - post-mine reveal invalidation becomes explicit and correctness-oriented
  - a successful mountain-opening mine must schedule reveal work even when the player is still standing outside the opened pocket
- New invariants:
  - roof correctness must not depend on `_is_player_on_opened_mountain_tile()`
  - a successful mine of a surface mountain tile must enqueue exactly one sanctioned reveal/topology consequence chain
  - helper methods below `ChunkManager.try_harvest_at_world()` remain implementation details and must not become alternate gameplay entrypoints
- Who adapts:
  - `ChunkManager`
  - `MountainRoofSystem`
  - `MountainShadowSystem`
- What does NOT change:
  - canonical terrain ownership
  - `HarvestTileCommand -> ChunkManager.try_harvest_at_world()` as the safe mutation path

### Affected layer: Topology

- What changes:
  - topology becomes the primary loaded-bubble open-component truth for reveal after Iteration 2 instead of repeated ad hoc pocket BFS on the interactive path
- New invariants:
  - interactive mining must not trigger a full loaded-chunk topology snapshot rebuild
  - component-local dirty processing is the default; full rebuild is a fallback for chunk load/unload invalidation, desync recovery, or boot/runtime resync
  - topology commits must publish changed component data, not swap a newly rebuilt full-world dictionary by default
- Who adapts:
  - `ChunkManager`
- What does NOT change:
  - topology remains derived state
  - topology remains surface-only and loaded-bubble scoped

### Affected layer: Reveal

- What changes:
  - reveal refresh seed policy becomes explicit and mined-tile/component aware
  - full local-zone recompute becomes fallback behavior, not the default hot path
- New invariants:
  - surface roof reveal correctness must not depend on the player’s current terrain type
  - prepared per-chunk cover deltas are the preferred publication unit after Iteration 2
  - loaded/unloaded boundaries must still be represented honestly; if a continuation is unknown, reveal state must continue to surface truncated truth rather than pretending completeness
- Who adapts:
  - `MountainRoofSystem`
  - `Chunk`
- What does NOT change:
  - no public reveal refresh API is added
  - underground fog ownership remains outside this spec unless a touched proof path requires alignment

### Affected layer: Presentation

- What changes:
  - cover and shadow application become strictly budgeted per-chunk delta applies
  - the main thread becomes apply-only for cover/shadow publication as far as practical
- New invariants:
  - one mining event must not synchronously trigger mass cover redraw beyond the local patch
  - main-thread `TileMap` mutation remains allowed only for bounded visible deltas
  - degraded convergence for a few frames is acceptable if the published state is truthful and stable
- Who adapts:
  - `MountainRoofSystem`
  - `MountainShadowSystem`
  - `Chunk`
  - `ChunkManager`
- What does NOT change:
  - TileMap/scene-tree mutation remains main-thread only

### Affected layer: World Pre-pass

- What changes:
  - the remaining measured dense-grid bottlenecks move behind native kernel entrypoints in Iteration 3, with GDScript fallback retained
- New invariants:
  - GDScript and native paths must publish the same deterministic pre-pass semantics
  - the runtime still publishes one pre-pass snapshot per requested seed
  - native migration counts only if it materially reduces GDScript work or bridge payloads
- Who adapts:
  - `WorldPrePass`
  - `WorldGenerator`
  - `WorldPrePassKernels`
- What does NOT change:
  - `WorldPrePass` stays the single macro structure truth for runtime

### Affected layer: Native chunk generation bridge

- What changes:
  - Iteration 3 may replace the current per-tile GDScript authoritative input packing loop with a native-friendly cached or slab-based bridge
- New invariants:
  - `ChunkGenerator.generate_chunk()` still requires authoritative inputs and must fail closed on malformed or missing authoritative truth
  - native chunk generation must not self-sample divergent runtime channels or structures
  - payload wire format remains unchanged for downstream consumers
- Who adapts:
  - `ChunkContentBuilder`
  - `WorldGenerator`
  - `ChunkGenerator`
- What does NOT change:
  - downstream chunk payload readers
  - `generation_source` proof/debug provenance requirement

## Iterations

### Iteration 1 — Correctness-first roof reveal fix

Goal: eliminate the stale-roof bug before any broader performance redesign.

What is done:

- `MountainRoofSystem` stops using the player’s current opened-tile state as the sole gate for mining-triggered reveal invalidation.
- reveal refresh seed selection becomes explicit and ordered:
  - reuse the active zone seed if the mined tile extends or touches the active opened zone
  - otherwise use the mined tile itself when it became `MINED_FLOOR` or `MOUNTAIN_ENTRANCE`
  - otherwise fall back to the player tile only if the player is already inside an opened pocket
  - otherwise clear the active zone honestly
- mining a first entrance tile from outside must still schedule reveal work and cover apply for the touched loaded chunks.
- loaded seam neighbors touched by the newly opened tile must continue to converge through the sanctioned invalidation path.

What is NOT done:

- no topology architecture redesign
- no new worker thread path
- no C++ migration
- no attempt to optimize `WorldPrePass`
- no change to the public mining API surface

Acceptance tests:

- [ ] manual: on a fixed seed, mining the first mountain entrance from outside removes the stale roof over the opened entrance and the roof does not remain visible over an already opened tile
- [ ] manual: on a fixed seed, performing the same action near a loaded chunk seam still converges correctly on both touched chunks
- [ ] static/code proof: `MountainRoofSystem` no longer relies only on `_is_player_on_opened_mountain_tile()` to decide whether a mining-triggered refresh is needed
- [ ] static/code proof: no new direct terrain write path is introduced outside `ChunkManager.try_harvest_at_world()`
- [ ] runtime proof: repeated mining on the sanctioned route produces no `ERROR` or `assert`

Files that may be touched:

- `core/systems/world/mountain_roof_system.gd`
- `core/systems/world/chunk_manager.gd`
- `core/debug/runtime_validation_driver.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must NOT be touched:

- `core/systems/world/chunk.gd`
- `core/systems/world/world_pre_pass.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/autoloads/world_generator.gd`
- `gdextension/src/world_prepass_kernels.cpp`
- `gdextension/src/world_prepass_kernels.h`
- `gdextension/src/chunk_generator.cpp`
- `gdextension/src/chunk_generator.h`

### Iteration 2 — Evict reveal/topology hot work from the main thread

Goal: keep the synchronous mining path within contract by moving the heavy reveal/topology consequences into queued, worker, or budgeted processing.

What is done:

- `ChunkManager.try_harvest_at_world()` is reduced to local mutation, local neighbor normalization, immediate local patch response, and dirty work enqueue.
- reveal no longer recomputes opened pockets through `query_local_underground_zone()` as the default runtime path after every mine. The default runtime path becomes topology/open-component driven.
- topology processing becomes dirty-unit based:
  - changed tiles and touched seams are queued
  - component-local updates are preferred over full loaded-bubble snapshot rebuild
  - full rebuild remains a fallback for explicit invalidation or recovery, not the default consequence of one mine event
- `MountainRoofSystem` computes prepared per-chunk cover deltas off the interactive path and applies only bounded payloads on the main thread.
- `MountainShadowSystem` is aligned to the same dirty-unit boundaries so mining no longer triggers unbounded presentation consequences.
- `Chunk` cover publication uses `changed_tiles` delta payloads by default; full per-chunk cover apply remains a fallback for invalidation, initial sync, or recovery.
- if any remaining reveal/topology step still fails budget in GDScript, it must move to worker processing now instead of remaining synchronous “because it only happens sometimes”.

What is NOT done:

- no `WorldPrePass` math migration to C++
- no second world-truth path
- no public manual reveal API
- no broad gameplay redesign of mining or mountain traversal

Acceptance tests:

- [ ] fixed-seed runtime mining proof shows no `ChunkManager.query_local_underground_zone` contract warnings in the hot mining path
- [ ] fixed-seed runtime mining proof shows no `MountainRoofSystem._refresh_local_zone` or `MountainRoofSystem._request_refresh` contract warnings
- [ ] fixed-seed runtime mining proof keeps `ChunkManager.try_harvest_at_world()` below the `< 2 ms` synchronous contract
- [ ] fixed-seed runtime mining/traversal proof keeps `FrameBudgetDispatcher.topology.chunk_manager.topology_rebuild` within the `1-2 ms` intended envelope on average and eliminates the current triple-digit spike class
- [ ] fixed-seed runtime mining proof keeps `MountainRoofSystem._process_cover_step` within the `2 ms` contract per chunk, or further splits the work until that is true
- [ ] manual: after repeated mining inside mountains and across loaded seams, roof and shadow converge without stale visible cover over already opened tiles

Files that may be touched:

- `core/systems/world/chunk_manager.gd`
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/world/chunk.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `core/systems/world/world_perf_probe.gd`
- `core/debug/runtime_validation_driver.gd`
- `tools/perf_log_summary.gd`
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must NOT be touched:

- `core/systems/world/world_pre_pass.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/autoloads/world_generator.gd`
- `gdextension/src/world_prepass_kernels.cpp`
- `gdextension/src/world_prepass_kernels.h`
- `gdextension/src/chunk_generator.cpp`
- `gdextension/src/chunk_generator.h`

### Iteration 3 — Native C++ migration for the remaining heavy math

Goal: move the remaining measured pure-data hotspots and bridge-heavy chunk input packing into native code without creating alternate world truth.

What is done:

- `WorldPrePassKernels` gains native entrypoints for the remaining measured heavy stages, starting with:
  - `flow_directions`
  - `flow_accumulation`
  - `mountain_mass_grid`
  - `erosion_proxy`
  - `slope_grid`
  - `rain_shadow`
- if post-Iteration-2 measurement still shows lake extraction as a meaningful hotspot, the native pre-pass surface may also grow the helper needed to remove that residual cost.
- `WorldPrePass.compute()` remains the orchestrator and timing surface. Native kernels replace the heavy inner loops, not the high-level ownership or truth model.
- `ChunkContentBuilder` / `WorldGenerator` / `ChunkGenerator` reduce the current bridge-heavy `authoritative_inputs` packing cost by switching from repeated per-tile GDScript sampling loops to a native-friendly cached or slab-based authoritative input path.
- proof tooling is updated so boot/runtime summaries continue to show migrated stage timings and script/native parity remains auditable.

What is NOT done:

- no new macro structure algorithm in C++
- no duplicate ridge/river/mountain truth beside `WorldPrePass`
- no scene-tree or Node access from native code
- no reintroduction of legacy directed-band structure formulas

Acceptance tests:

- [ ] fixed-seed boot proof on the current machine reduces `WorldGenerator._setup_world_pre_pass.compute` from the 2026-04-09 baseline `5995.06 ms` to `<= 3000 ms`
- [ ] on the same fixed-seed boot proof, none of `WorldPrePass.compute.rain_shadow`, `flow_accumulation`, `flow_directions`, `slope_grid`, `erosion_proxy`, or `mountain_mass_grid` remains a `> 500 ms` GDScript hotspot
- [ ] fixed-seed startup/runtime proof no longer shows the current repeated `slow native generate_chunk` hot window in the `575-859 ms` range for the startup bubble; target `<= 400 ms` per-chunk hot window
- [ ] fixed-seed script/native compare still reports zero mismatches for `terrain`, `biome`, `secondary_biome`, `ecotone`, `variation`, `flora_density`, and `flora_modulation`
- [ ] static/code proof: no new native fallback path synthesizes alternate world truth when authoritative inputs or pre-pass snapshot are missing

Files that may be touched:

- `core/systems/world/world_pre_pass.gd`
- `gdextension/src/world_prepass_kernels.h`
- `gdextension/src/world_prepass_kernels.cpp`
- `gdextension/src/register_types.h`
- `gdextension/src/register_types.cpp`
- `core/systems/world/chunk_content_builder.gd`
- `core/autoloads/world_generator.gd`
- `gdextension/src/chunk_generator.h`
- `gdextension/src/chunk_generator.cpp`
- `core/debug/world_preview_proof_driver.gd`
- `scenes/ui/world_lab.gd`
- `tools/perf_log_summary.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must NOT be touched:

- `core/systems/world/mountain_roof_system.gd`
- `core/systems/world/chunk.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `core/systems/world/chunk_manager.gd`

## Implementation order and dependencies

Required order:

1. Iteration 1
2. Iteration 2
3. Iteration 3

Dependency rationale:

- Iteration 1 must land first because performance work must not be allowed to mask or normalize an incorrect roof state.
- Iteration 2 depends on the correctness rules from Iteration 1 and establishes the final runtime architecture for reveal/topology consequences.
- Iteration 3 depends on post-Iteration-2 measurement so native work targets the remaining bottlenecks rather than stale suspects.

Each iteration must ship with its own closure report and its own sanctioned proof artifacts.

## Required contract and API updates after implementation

When this spec is implemented, update:

- `DATA_CONTRACTS.md`
  - Mining layer: make the post-mine reveal/topology consequence chain explicit
  - Topology layer: document whether `query_local_underground_zone()` remains primary truth, fallback truth, or debug-only helper after Iteration 2
  - Reveal layer: document mined-tile/component-driven refresh semantics and delta-apply policy
  - Presentation layer: document the bounded cover/shadow publication contract
  - World Pre-pass layer: document any newly sanctioned native kernel ownership and invariants
- `PUBLIC_API.md`
  - `ChunkManager.try_harvest_at_world()` postconditions if roof/reveal semantics become stricter
  - `ChunkManager.query_local_underground_zone()` semantics if its role changes after Iteration 2
  - `WorldGenerator.build_chunk_native_data()` and `ChunkGenerator.generate_chunk()` if the authoritative-input bridge changes in Iteration 3

## Out-of-scope

- save/load format redesign
- underground fog redesign beyond any minimal compatibility touch required by proof harnesses
- changing mining gameplay reward, mining speed, or tool balance
- arbitrary `load_radius` / `unload_radius` tuning as a substitute for architectural fixes
- renderer, GPU, or Godot engine source changes
- seed reroll, beauty filtering, or any post-hoc “pick a prettier world” bootstrap logic
