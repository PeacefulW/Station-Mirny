---
title: Runtime SDF Contours - Iteration 03 Streaming Packets
doc_type: iteration_brief
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-05-12
related_docs:
  - runtime_sdf_terrain_contours.md
  - world_runtime.md
  - mountain_generation.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Runtime SDF Contours - Iteration 03 Streaming Packets

## Goal

Connect native contour compute to the chunk streaming lifecycle so loaded chunks
receive contour results derived from effective base packet data plus runtime
diff.

## Non-Goals

- no visible rendering cutover
- no movement collision cutover
- no save/load changes
- no `autotile_47` fallback path for the target contour result
- no full-world contour prepass

## Runtime Classification

- authoritative state: existing chunk packet plus runtime diff
- derived state: loaded `ContourChunkResultV1` per chunk and terrain class
- runtime work class: worker compute and main-thread result registration
- dirty unit: one loaded chunk plus halo participants

## Allowed Files

- `core/systems/world/world_streamer.gd`
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_core.h`
- new `tools/runtime_sdf_contour_streaming_smoke_test.gd`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/packet_schemas.md`

## Forbidden Boundaries

- no `ChunkView` visual replacement in this iteration
- no movement query semantic change
- no save-slot file changes
- no per-tile native calls from GDScript

## Implementation Shape

1. Load contour recipes into the terrain presentation registry.
2. Teach `WorldStreamer` to assemble halo masks for `mountain_mass`,
   `ground_surface`, and `water_surface` from effective loaded packet data.
3. Include runtime diff overrides when assembling masks.
4. For halo cells whose neighbor chunks are not loaded, request or reuse native
   base packet data through the existing `WorldCore.generate_chunk_packets_batch`
   path, then apply runtime diff overrides on top.
5. Use a fixed halo of `2` tiles for all contour requests in this iteration.
6. Request one native contour build per class per chunk.
7. Store results by chunk coordinate, class, recipe id, and diff revision.
8. Mark contour result readiness separately from packet readiness.
9. Keep chunk movement readiness false until required contour collision data is
   ready once collision cutover is enabled.
10. Add debug readback methods for contour result metadata.
11. Document result ownership and lifecycle in `system_api.md`.

## Halo Assembly Contract

For a target chunk `(cx, cy)`, `WorldStreamer` assembles a
`(CHUNK_SIZE + 4) x (CHUNK_SIZE + 4)` tile halo.

Source priority for each halo tile:

1. loaded runtime diff override
2. loaded chunk packet
3. unloaded runtime diff override from `WorldDiffStore`
4. generated base packet for the neighbor chunk
5. empty tile if Y is outside world bounds

X coordinates wrap before packet lookup. Generated neighbor base packets used
only for halo assembly are transient and must not become visible loaded chunks.

## Required Tests and Commands

Run Godot smoke test:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful"
godot --headless --path . --script res://tools/runtime_sdf_contour_streaming_smoke_test.gd
```

The smoke test must assert:

- a target chunk can assemble a `20 x 20` halo for each contour class
- unloaded neighbor halo cells are filled from generated base packet data
- runtime diff overrides win over generated base packet data
- X seam halo wraps
- stale results with an older `diff_revision` are rejected

## Smoke Tests

- streamer can build a mountain solid halo from loaded packets and diff
- streamer can build a ground surface halo from loaded packets and diff
- streamer can build halo data when direct neighbor chunks are not loaded
- X seam masks wrap correctly
- Y outside-world masks are empty
- stale contour results are ignored when diff revision changes
- unloading a chunk releases contour result references

## Definition of Done

- loaded chunks can request and receive contour results
- results are keyed by revision so stale visual/collision data cannot apply
- no scene rendering depends on the result yet
- debug readback confirms result size, class, recipe id, and readiness
