---
title: Runtime SDF Contours - Iteration 06 Excavation Dirty Updates
doc_type: iteration_brief
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-05-12
related_docs:
  - runtime_sdf_terrain_contours.md
  - mountain_generation.md
  - world_runtime.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Runtime SDF Contours - Iteration 06 Excavation Dirty Updates

## Goal

Refresh contour visuals and collision after mining or digging mutates a logical
mountain tile, without full-world rebuilds and without leaving stale collision
at the dug edge.

## Non-Goals

- no new mining gameplay
- no save format change
- no whole-mountain contour rebuild
- no full-world contour invalidation
- no visual-only update without matching collision update

## Runtime Classification

- authoritative state: runtime diff tile override
- derived state: dirty contour visual and collision revisions
- runtime work class: interactive dirty mark plus worker refresh
- dirty unit: one tile mutation, affected chunk, and direct seam-neighbor chunks

## Allowed Files

- `core/systems/world/world_streamer.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_diff_store.gd`
- `gdextension/src/world_contour_field.cpp`
- new `tools/runtime_sdf_contour_excavation_smoke_test.gd`
- `docs/02_system_specs/meta/system_api.md`

## Forbidden Boundaries

- no change to saved diff payload shape
- no whole-world scans
- no GDScript pixel-level contour recompute
- no update that refreshes visuals but leaves old collision active

## Implementation Shape

1. `WorldDiffStore` owns a monotonic integer `diff_revision`.
2. Every successful tile override increments `diff_revision` exactly once.
3. After `try_harvest_at_world()` commits a dug tile override, read the new
   `diff_revision`.
4. Mark the owning chunk contour dirty.
5. Mark direct seam-neighbor chunks dirty when the changed tile can affect their
   halo.
6. Enqueue native contour rebuild request assembly for dirty classes and chunks
   under the streaming budget; the interactive harvest call must not build full
   contour requests synchronously.
7. Block movement through dirty contour regions until the matching collision
   revision is ready.
8. Swap visual textures and collision fields together by the affected chunk's
   required revision.
9. Keep mountain cover/cavity updates synchronized with the contour revision.
   An already-published chunk may keep its previous visual revision visible
   while dirty, but movement/collision readiness still fails closed.
10. Add tests that dig edge, corner, and seam tiles.

## Revision Contract

`ContourChunkResultV1.diff_revision` must equal the affected chunk's required
revision at apply time. Older results for that chunk are discarded.

`WorldDiffStore.diff_revision` remains a global monotonic change id, but it does
not invalidate every loaded chunk. Unaffected chunks keep their existing ready
revision valid until their own tile data or bounded contour halo changes.

`WorldStreamer` stores:

```text
_contour_requested_revision_by_chunk: Dictionary
_contour_ready_revision_by_chunk: Dictionary
```

A chunk is movement-ready only when required contour classes have ready results
for that chunk's required contour revision.

## Required Tests and Commands

Run Godot smoke test:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful"
godot --headless --path . --script res://tools/runtime_sdf_contour_excavation_smoke_test.gd
```

The smoke test must assert:

- a successful harvest increments `WorldDiffStore.diff_revision` once
- the owning chunk is marked dirty
- seam-neighbor chunks are marked dirty when the tile is within two tiles of a
  chunk edge
- stale contour results are discarded
- an unrelated global diff does not make unaffected chunks stale
- visual and collision revisions become ready together

## Smoke Tests

- mining a mountain edge opens the visible contour at that location; a
  chunk-local runtime cutout may provide immediate presentation feedback, but
  movement remains blocked until the matching collision revision is ready
- movement can pass through the new opening after the contour revision is ready
- movement cannot pass through stale visual/collision mismatch during refresh
- digging a seam tile refreshes both neighboring chunks
- runtime diff save/load still persists the dug tile without saving contour data
- `diff_revision` is not serialized into save data

## Definition of Done

- excavation updates contour visuals and collision from one logical mutation
- stale contour revisions cannot be applied after newer diff revisions
- seam-neighbor dirty refresh works
- save/load remains unchanged for contour caches
