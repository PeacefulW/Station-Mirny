---
title: World Generation Preview - Iteration 1 Brief
doc_type: iteration_brief
status: draft
owner: engineering+ui
source_of_truth: false
version: 0.1
last_updated: 2026-04-21
related_docs:
  - WORLD_GENERATION_PREVIEW_ARCHITECTURE.md
  - world_runtime.md
  - mountain_generation.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# World Generation Preview - Iteration 1 Brief

## Goal

Ship the first playable live preview on the new-game screen for the current
mountain worldgen only.

The preview must:
- use canonical chunk packet generation, not preview-only generation math
- start from the current spawn-safe area and fill outward chunk-by-chunk
- stay responsive while seed and mountain sliders change
- remain fully transient and never behave like a hidden gameplay world

This iteration is about the architectural seam and a working vertical slice,
not about max radius, minimap polish, or future rivers/climate overlays.

## Non-Goals

- no packet schema changes
- no save/load format changes
- no `WorldCore.generate_chunk_packet(...)` signature changes
- no hidden `WorldStreamer` / `ChunkView` gameplay world inside the menu
- no diff-store writes or runtime world events from preview
- no river, temperature, biome, resource, or climate overlays
- no perfect final art treatment for preview colors
- no `spawn ±500 tiles` requirement yet; iteration 1 keeps a bounded radius
  while preserving the architecture needed to grow later

## Runtime Classification

- authoritative state: unchanged (`world_seed`, `world_version`,
  `worldgen_settings.mountains`, canonical chunk packets)
- derived state: preview patch images produced from chunk packets
- runtime work class:
  - background compute: canonical packet generation through a shared backend
  - main-thread apply: bounded preview patch publish only
  - interactive: debounce, epoch bump, queue rebuild, bounded texture upload
- dirty unit:
  - one preview chunk patch for publish
  - one preview epoch for invalidation/cancellation

## Scope of Iteration 1

Iteration 1 should ship a real working preview with these deliberate limits:

- mountains/ground only
- one preview mode only
- deterministic square-spiral chunk fill
- one fast inner pass and one bounded outer pass
- current spawn area only; not a future smart spawn-search system

Recommended radius for iteration 1:
- fast pass: `3` chunks around the spawn chunk
- full pass: `8` chunks around the spawn chunk

That yields a useful visible area while keeping menu responsiveness sane.
The architecture must allow this radius to grow later without redesign.

## Spawn Rule for Iteration 1

Use an explicit resolver seam even though the current answer is simple.

Add `WorldSpawnResolver.resolve_preview_spawn_tile(...)`.

For iteration 1, the resolver should return the center of the current
spawn-safe patch defined by mountain generation for the active world version.
For current mountain worlds this is the center tile of the canonical
`12..20 x 12..20` safe patch.

This keeps preview aligned with the current world contract while preserving a
clean seam for future spawn logic.

## Files Likely Involved

### New
- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/world_spawn_resolver.gd`
- `core/systems/world/world_preview_palette.gd`
- `core/systems/world/world_preview_controller.gd`
- `scenes/ui/world_preview_canvas.gd`

### Modified
- `scenes/ui/new_game_panel.gd`
- `core/systems/world/world_streamer.gd`
- `core/systems/world/world_runtime_constants.gd` (only if new preview-only
  constants are needed and they are clearly presentation/runtime constants,
  not canonical worldgen rules)

## Forbidden Files / Boundaries

- no changes to `gdextension/src/world_core.cpp`
- no changes to `ChunkPacketV1` shape
- no changes to `core/systems/world/world_diff_store.gd`
- no gameplay changes in building/power/combat systems
- no save-pipeline changes
- no river/climate/biome generation work folded into this task

## Architectural Rule

Preview must use:

`same packet generation, separate preview renderer`

That means:
- shared canonical packet generation backend
- separate preview queue/controller
- separate preview canvas/patch renderer
- no gameplay `ChunkView` creation in the menu

## Implementation Steps

1. Add a shared packet backend.
   - Extract the worker/request/result behavior that is currently embedded in
     `WorldStreamer` into `world_chunk_packet_backend.gd`.
   - Keep the packet contract identical to runtime.
   - Keep `epoch` support in the backend request/response path.

2. Rewire `WorldStreamer` to use the shared backend.
   - This task is part of iteration 1 specifically to avoid creating two
     separate packet-generation implementations.
   - Runtime behavior must remain unchanged.

3. Add `WorldSpawnResolver`.
   - Expose a small authoritative seam for preview spawn selection.
   - For iteration 1, resolve to the center of the current spawn-safe patch.

4. Add `WorldPreviewPalette`.
   - Convert one canonical chunk packet into one lightweight preview patch.
   - Use a simple shape-true mapping for now:
     - plains/ground
     - mountain wall
     - mountain foot
   - The palette is allowed to be visually simple; it must stay faithful to
     generated mountain shape.

5. Add `WorldPreviewCanvas`.
   - Draw one patch per chunk.
   - Support nearest-neighbor scaling.
   - Draw spawn marker.
   - Optional: draw a subtle chunk grid if it helps readability.

6. Add `WorldPreviewController`.
   - Own preview debounce.
   - Own current settings snapshot.
   - Own preview `epoch`.
   - Build square-spiral chunk order around the spawn chunk.
   - Run the two-stage request order: fast pass first, then outer pass.
   - Drop stale results whose `epoch` no longer matches.

7. Wire preview into `NewGamePanel`.
   - Reuse the same seed normalization rules as the `Start` path.
   - Regenerate preview when:
     - seed text changes
     - random-seed button is pressed
     - mountain sliders change
   - Use debounce so dragging a slider does not enqueue a full rebuild on every
     tiny intermediate value.

## UI / UX Rule for Iteration 1

The user must see the map fill in chunks, not as one final static image.

Required behavior:
- fast response near the spawn chunk first
- visible outward fill after that
- old preview work disappears cleanly when settings change
- no menu freeze while the preview is rebuilding

## Risks

- extracting the packet backend may accidentally regress runtime streaming if
  responsibilities are copied instead of truly shared
- preview may still hitch if patch publish rebuilds one giant image instead of
  one chunk patch at a time
- slider spam may create stale work unless debounce and epoch-drop are both
  enforced
- preview may drift from real start position later if the resolver seam is not
  created now

## Smoke Tests

- editing seed text rebuilds the preview without freezing the menu
- pressing random seed rebuilds the preview and visibly changes the map
- moving mountain sliders changes the preview shape in a way that matches the
  current worldgen contract
- preview starts from the spawn chunk and fills outward in stable spiral order
- rapid slider movement does not publish stale old settings after the new epoch
  has started
- starting a new world still works and does not depend on preview state
- no save files or chunk diffs are written before `Start`

## Definition of Done

- new-game screen shows a live preview built from canonical chunk packets
- preview uses a shared packet backend, not a second generator
- preview is centered on the current spawn-safe area through an explicit
  resolver seam
- preview fills chunk-by-chunk with fast pass first, then bounded outer pass
- preview uses bounded patch publish only
- runtime world start path still works unchanged
- no authoritative packet/save/runtime ownership boundary is changed

## Out of Scope Follow-Ups

Handle in later iterations, not here:
- larger preview radius such as `spawn ±500 tiles`
- extra preview layers: rivers, temperature, biome, resources
- prettier terrain colors/shaders/material polish
- zoom/pan interactions
- debug overlays such as `mountain_id`, cavity shells, or spawn scoring
- future smart spawn search when spawn rules become more complex
