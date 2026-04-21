---
title: World Generation Preview - Iteration 2 Brief
doc_type: iteration_brief
status: draft
owner: engineering+ui
source_of_truth: false
version: 0.1
last_updated: 2026-04-21
related_docs:
  - WORLD_GENERATION_PREVIEW_ARCHITECTURE.md
  - world_generation_preview_iteration_1_brief.md
  - world_runtime.md
  - mountain_generation.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# World Generation Preview - Iteration 2 Brief

## Goal

Scale the live new-game preview from the iteration-1 MVP into a
large-area, production-feeling preview closer to the intended
Factorio-style experience.

Iteration 2 should:
- keep the shared canonical packet backend introduced in iteration 1
- expand preview coverage from the bounded MVP radius toward the real target
  window around spawn
- remain responsive while progressively filling a much larger chunk set
- introduce explicit queue backpressure and publish budgeting so large preview
  windows do not turn into menu hitching

This iteration is about scale, pacing, and resilience under a large preview
window. It is not yet about new worldgen layers such as rivers/climate.

## Non-Goals

- no packet schema changes
- no save/load format changes
- no `WorldCore.generate_chunk_packet(...)` signature changes
- no preview-only worldgen approximation or low-fidelity generator
- no hidden gameplay `ChunkView` path in the menu
- no river, temperature, biome, or resource overlays yet
- no preview-state persistence
- no broad free-camera map viewer beyond the bounded preview window

## Runtime Classification

- authoritative state: unchanged (`world_seed`, `world_version`,
  `worldgen_settings.mountains`, canonical chunk packets)
- derived state: larger preview patch set plus controller-side queue/cache
  bookkeeping
- runtime work class:
  - background compute: canonical packet generation through the shared backend
  - main-thread apply: bounded per-frame preview patch publication
  - interactive: stage reset, epoch bump, bounded queue rebuild, progress UI
- dirty unit:
  - one preview chunk patch for publication
  - one preview epoch for cancellation
  - one stage transition in the progressive fill plan

## Scope of Iteration 2

Iteration 2 grows the preview from MVP scale to a large target window.

Recommended target window:
- target view: approximately `spawn ±500 tiles`
- with `32 x 32` chunks this is approximately `33 x 33 = 1089` chunks

This must remain progressive, not monolithic.

Recommended staged fill plan:
- stage A: `5 x 5` chunks around spawn
- stage B: `13 x 13` chunks around spawn
- stage C: `21 x 21` chunks around spawn
- stage D: `33 x 33` chunks around spawn

The exact stage sizes may change in implementation, but the rule is fixed:
small useful result first, then medium, then large, then full target window.

## Architectural Rule

Iteration 2 must not weaken the core rule from the architecture doc:

`same packet generation, separate preview renderer`

Scaling up the radius is not permission to:
- add a second simplified generator
- add whole-preview synchronous rebuilds
- fall back to hidden gameplay chunk rendering

## Files Likely Involved

### New
- `core/systems/world/world_preview_patch_cache.gd` (recommended)

### Modified
- `core/systems/world/world_preview_controller.gd`
- `core/systems/world/world_preview_palette.gd`
- `scenes/ui/world_preview_canvas.gd`
- `scenes/ui/new_game_panel.gd`
- `core/systems/world/world_chunk_packet_backend.gd`

## Forbidden Files / Boundaries

- no changes to `gdextension/src/world_core.cpp`
- no changes to `ChunkPacketV1`
- no changes to `core/systems/world/world_diff_store.gd`
- no changes to save collectors/appliers for preview state
- no unrelated gameplay/system changes
- no rivers/climate/biome generation work folded into this task

## Implementation Steps

1. Add a preview patch cache.
   - Cache key should include at minimum:
     - normalized seed
     - `world_version`
     - stable settings signature
     - preview chunk coord
     - preview render mode / palette id
   - The cache is controller/view-local runtime state only.
   - It must never be saved.

2. Extend the preview controller to multi-stage fill.
   - Keep stable square-spiral order.
   - Generate stage A fully before stage B begins, and so on.
   - When the epoch changes, clear the pending plan and restart from stage A.

3. Add explicit request backpressure.
   - Cap the number of in-flight backend requests.
   - Do not enqueue all `1089` chunks at once when the settings change.
   - The controller should feed work gradually as packets complete.

4. Add bounded publish budgeting.
   - The canvas/controller must publish only a limited number of ready chunk
     patches per frame.
   - No whole-texture rebuild is allowed when one patch becomes ready.

5. Add progress reporting.
   - The user should be able to tell that the preview is still filling.
   - Minimal acceptable UI:
     - current stage label or ring count
     - ready chunk count / target chunk count
   - Progress UI must stay lightweight and must not become a second scheduler.

6. Add cache reuse on non-worldgen view changes if applicable.
   - If iteration 1 already introduced zoom or simple presentation toggles,
     reuse existing patch cache where the canonical packet did not change.
   - If no such controls exist yet, skip this step.

7. Keep epoch-drop behavior strict.
   - Stale packets from an older settings snapshot must be discarded even if
     they were expensive to compute.
   - Correctness beats salvage.

## Performance Rules

Iteration 2 exists specifically to keep large preview windows under control.
These rules are mandatory:

- no enqueueing of the full final window in one burst
- no publication of an unlimited number of ready patches in one frame
- no rebuilding of one giant preview image after each ready chunk
- no per-frame full sort of all already-known preview chunks if a stable stage
  plan can be preserved incrementally
- no unbounded cache growth across multiple dead epochs

Recommended controller caps for the first implementation pass:
- in-flight requests cap: `4..16`
- per-frame patch publish cap: `2..8`
- dead-epoch patch/cache eviction: immediate or next rebuild boundary

Exact values may change after testing, but bounded caps are required.

## UI / UX Rule for Iteration 2

The user should feel that the preview is alive, not stalled.

Required behavior:
- the center arrives fast
- medium rings keep appearing without visible menu hitching
- the outer target window completes progressively
- when settings change mid-fill, the old world stops expanding and the new one
  restarts cleanly from the center

## Risks

- large preview windows may create queue explosions unless the controller owns
  explicit backpressure
- cache keys may become incorrect if settings signature is not stable and shared
- progress UI may be misleading if it counts queued chunks rather than actually
  ready/published chunks
- outer-ring publication may starve the center if stage ordering is not strict

## Smoke Tests

- preview still starts at the current spawn-safe area
- preview reaches a much larger window than iteration 1 without freezing the menu
- outer rings continue to fill while the menu remains interactive
- changing a slider during stage C or D cancels the old fill and restarts the
  new epoch from the center
- no stale chunks from the old epoch remain on screen after the restart
- no preview state leaks into save files or runtime world state

## Definition of Done

- preview scales from MVP radius to a large target window through staged fill
- controller uses explicit request backpressure
- preview publication is budgeted and bounded per frame
- progress UI communicates that the large window is still filling
- restart-on-change remains clean under heavy slider edits
- no authoritative packet/save/runtime ownership boundary is changed

## Out of Scope Follow-Ups

Handle in later iterations, not here:
- overlay/render modes such as `mountain_id`, wall/foot/interior, or spawn-safe
  patch visualization
- rivers, temperature, biomes, and resource overlays
- smarter spawn search and spawn scoring visualizations
- full pan/zoom world-lab interaction surface
- export/share/copy-seed UX
