---
title: In-Game Chunk Debug Overlay
doc_type: feature_spec
status: draft
owner: engineering
source_of_truth: false
version: 0.2
last_updated: 2026-04-16
related_docs:
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - DATA_CONTRACTS.md
---

# Feature: In-Game Chunk Debug Overlay

## Design Intent

The F11 overlay is a compact in-world chunk-state map, not a multi-panel diagnostics console.

Its on-screen job is limited to:

- showing chunk rectangles around the player
- coloring each rectangle by a simplified chunk status
- drawing the factual `load_radius` and `unload_radius` rings
- showing a compact corner HUD with `FPS` and the current player chunk coordinates

Detailed queue state, timeline history, performance breakdown, and forensics stay available for explicit diagnostics, but they move out of the on-screen overlay and into the `PerfTelemetryCollector` JSON artifact.

The overlay must observe existing debug state only. It must not own gameplay state, request chunks, unload chunks, or become a second diagnostics bus.

## Performance / Scalability Contract

- Runtime class: `interactive` debug presentation.
- Target scale / density: safe with dozens of loaded chunks and large internal queues because the overlay renders only a bounded chunk snapshot plus one compact HUD line.
- Authoritative source of truth: `ChunkManager`, `ChunkDebugSystem`, `WorldPerfMonitor`, and `WorldRuntimeDiagnosticLog` remain the owners of their existing data.
- Write owner: `WorldChunkDebugOverlay` owns only draw state and one HUD label; `PerfTelemetryCollector` owns the explicit JSON artifact for detailed diagnostics.
- Derived/cache state: overlay snapshot is transient, read-only, bounded by player-centered debug radius, and not persisted.
- Dirty unit: one chunk entry and one HUD refresh.
- Allowed synchronous work: bounded snapshot polling, chunk rectangle drawing, ring drawing, and one compact HUD string update.
- Escalation path: queue/timeline/forensics/perf detail is exported through `PerfTelemetryCollector` during explicit perf runs instead of being formatted into live overlay panels.
- Forbidden shortcuts: no full-world scan per frame, no mode cycling, no text walls, no world mutation from overlay code.

## Data Contracts - New And Affected

### Chunk Debug Overlay Snapshot

- What: transient bounded snapshot for F11 debug presentation.
- Where: `core/systems/world/chunk_manager.gd` exposes it; `core/debug/world_chunk_debug_overlay.gd` consumes only the compact subset needed for rectangles, rings, and HUD.
- Owner (WRITE): `ChunkDebugSystem`, coordinated by `ChunkManager`.
- Readers (READ): `WorldChunkDebugOverlay`, `PerfTelemetryCollector`, debug inspection.
- Invariants:
  - `assert(snapshot_is_read_only, "chunk debug overlay snapshot must not mutate chunk lifecycle")`
  - `assert(snapshot_radius_is_clamped, "chunk debug overlay snapshot must stay bounded around player")`
  - `assert(on_screen_overlay_uses_compact_subset_only, "F11 on-screen overlay must not render queue/timeline/forensics panels anymore")`
- Forbidden: treating snapshot data as gameplay truth, persistence data, or a mutation API.

### Perf Telemetry Snapshot

- What changes: removed on-screen diagnostics now serialize into JSON for explicit perf/debug runs.
- Where: `core/debug/perf_telemetry_collector.gd`.
- Owner (WRITE): `PerfTelemetryCollector`.
- Readers (READ): agents, humans doing offline/debug review.
- Required JSON groups:
  - `debug_diagnostics.queue_state`
  - `debug_diagnostics.timeline_history`
  - `debug_diagnostics.forensics`
  - `debug_diagnostics.perf_breakdown`
- What does not change: runtime ownership of queue/timeline/forensics/perf data stays with their existing owner systems.

### Presentation

- What changes: `WorldChunkDebugOverlay` becomes a single-mode renderer with no queue panel, no timeline panel, no legend panel, no perf graph panel, and no mode switching.
- New invariants:
  - `assert(f11_toggle_does_not_change_world_state, "F11 visibility toggle must remain presentation-only")`
  - `assert(single_mode_overlay_has_no_mode_cycle, "single-mode overlay must not expose expanded/queue/timeline/perf/forensics modes")`
- Who adapts: `GameWorldDebug` owns the F11 toggle wiring and no longer routes modifier keys into overlay modes.

## Required Contract And API Updates

- `DATA_CONTRACTS.md`: update the overlay/presentation and perf-telemetry sections for single-mode F11 behavior and JSON ownership of removed diagnostics.
- `PUBLIC_API.md`: update `ChunkManager.get_chunk_debug_overlay_snapshot()` usage notes and remove obsolete F11 log / incident-dump artifact notes.
- `PerfTelemetryCollector` artifact schema: bump schema version and document the explicit `debug_diagnostics` groups.

## Iteration - Single-Mode F11 Overlay

Goal: keep F11 useful as an at-a-glance chunk map while moving detailed diagnostics into offline JSON.

What is done:

- Simplify `WorldChunkDebugOverlay` to one rendering mode.
- Keep only chunk rectangles, load/unload rings, compact FPS, and player chunk coordinates.
- Remove queue/timeline/perf/forensics/legend UI from the overlay.
- Remove mode cycling from `GameWorldDebug`.
- Export removed detail into `PerfTelemetryCollector` JSON.
- Update `DATA_CONTRACTS.md` and `PUBLIC_API.md`.

Acceptance tests:

- [ ] `assert(GameWorldDebug handles KEY_F11 and only toggles WorldChunkDebugOverlay visibility)` - no mode switching remains.
- [ ] `assert(WorldChunkDebugOverlay renders only chunk rectangles, load/unload rings, FPS, and player chunk coordinates)` - no text panels remain.
- [ ] `assert(WorldChunkDebugOverlay does not call chunk mutation APIs)` - overlay stays read-only.
- [ ] `assert(PerfTelemetryCollector artifact contains debug_diagnostics.queue_state)` - queue detail moved to JSON.
- [ ] `assert(PerfTelemetryCollector artifact contains debug_diagnostics.timeline_history)` - timeline detail moved to JSON.
- [ ] `assert(PerfTelemetryCollector artifact contains debug_diagnostics.forensics)` - forensics detail moved to JSON.
- [ ] `assert(PerfTelemetryCollector artifact contains debug_diagnostics.perf_breakdown)` - perf detail moved to JSON.
- [ ] Manual human verification: run `res://scenes/world/game_world.tscn`, press F11, and confirm the overlay shows only colored chunk rectangles, two radius rings, compact FPS, and player chunk coordinates.

Files that may be touched:

- `docs/02_system_specs/world/chunk_debug_overlay_spec.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`
- `core/debug/world_chunk_debug_overlay.gd`
- `core/debug/perf_telemetry_collector.gd`
- `scenes/world/game_world_debug.gd`

Files that must not be touched:

- chunk generation algorithms
- gameplay content registries
- save/load formats
- mining/topology/reveal mutation semantics
- worker-thread compute ownership

## User-visible Behavior

- `F11` toggles the overlay on and off.
- The world view shows chunk rectangles colored by simplified status:
  - loaded = green
  - generating = yellow
  - staged = blue
  - queued = gray
  - error / timeout = red
- `load_radius` and `unload_radius` are shown as chunk-space rings.
- A small HUD in the corner shows `FPS` and the current player chunk coordinates.
- No queue panel, timeline panel, perf graph, legend, or mode text is shown.

## Diagnostic Export Behavior

- Queue state, timeline history, forensics, and perf breakdown are not rendered on-screen.
- Those details remain available through the `PerfTelemetryCollector` JSON artifact during explicit perf runs.
- The overlay remains a compact live view; the collector remains the detailed offline proof artifact.
