---
title: World Generation Preview - Iteration 3 Brief
doc_type: iteration_brief
status: draft
owner: engineering+ui
source_of_truth: false
version: 0.1
last_updated: 2026-04-21
related_docs:
  - WORLD_GENERATION_PREVIEW_ARCHITECTURE.md
  - world_generation_preview_iteration_1_brief.md
  - world_generation_preview_iteration_2_brief.md
  - world_runtime.md
  - mountain_generation.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# World Generation Preview - Iteration 3 Brief

## Goal

Turn the live new-game preview into a lightweight worldgen-lab mode for
developer tuning and debugging.

Iteration 3 is optional from a player-facing point of view.
Its purpose is to let the team inspect the same canonical packet data through
multiple diagnostic render modes without changing the underlying worldgen.

This iteration should make it easier to answer questions like:
- where one mountain begins and another ends
- whether `wall`, `foot`, and `interior` classification matches expectations
- whether the preview spawn marker and the real spawn-safe area agree
- whether large mountain shapes and seam transitions look correct without
  relying on the "pretty" terrain palette alone

## Non-Goals

- no packet schema changes
- no save/load format changes
- no `WorldCore.generate_chunk_packet(...)` signature changes
- no hidden gameplay chunk rendering in the menu
- no new authoritative worldgen logic
- no river, climate, biome, or resource overlay work yet
- no replacement of the normal player-facing preview with a debug-first UI
- no permanent save of debug/worldgen-lab preferences unless a later UX task
  explicitly asks for it

## Runtime Classification

- authoritative state: unchanged (`world_seed`, `world_version`,
  `worldgen_settings.mountains`, canonical chunk packets)
- derived state: alternate preview patch presentation derived from already
  generated packet data
- runtime work class:
  - background compute: unchanged canonical packet generation
  - main-thread apply: bounded republish of preview patches for the active
    render mode only
  - interactive: render-mode switch, optional zoom/pan input, bounded redraw
- dirty unit:
  - one preview chunk patch for presentation refresh
  - one render-mode switch for the visible preview state

## Scope of Iteration 3

Iteration 3 adds diagnostic visibility and optional camera controls to the
existing live preview.

Recommended render modes:
- `terrain`
  - the normal player-facing preview from iteration 1/2
- `mountain_id`
  - each distinct mountain rendered with a deterministic debug color
- `mountain_classification`
  - explicit colors for `wall`, `foot`, `interior`, and non-mountain ground
- `spawn_safe_patch`
  - normal terrain preview plus an overlay for the current spawn-safe area

Optional interaction additions:
- preview zoom in/out
- bounded pan inside the generated preview window
- reset-view action back to spawn-centered framing

These tools are for development and tuning.
They must not replace the normal default terrain preview for ordinary players.

## Architectural Rule

Iteration 3 must keep the packet/render separation intact:

`same packet generation, multiple preview render modes`

That means:
- render modes reuse the same canonical packet cache whenever possible
- switching render modes must not trigger a full worldgen recompute if the
  packet data is already available
- debug overlays may change palette or patch composition only

## Files Likely Involved

### Modified
- `core/systems/world/world_preview_palette.gd`
- `core/systems/world/world_preview_patch_cache.gd`
- `core/systems/world/world_preview_controller.gd`
- `core/systems/world/world_spawn_resolver.gd`
- `scenes/ui/world_preview_canvas.gd`
- `scenes/ui/new_game_panel.gd`

### New
- no mandatory new files
- optional helper if needed:
  - `core/systems/world/world_preview_render_mode.gd`

## Forbidden Files / Boundaries

- no changes to `gdextension/src/world_core.cpp`
- no changes to `ChunkPacketV1`
- no changes to `core/systems/world/world_diff_store.gd`
- no changes to runtime save files for debug overlay state
- no gameplay/system changes outside preview UI and preview rendering
- no new worldgen layers folded into this iteration

## Implementation Steps

1. Add explicit preview render modes.
   - The preview controller should own the active mode.
   - The default mode remains the normal terrain preview.
   - Diagnostic modes must be explicitly opt-in.

2. Extend the preview palette layer.
   - `terrain` mode keeps current mapping.
   - `mountain_id` mode colors each `mountain_id` deterministically.
   - `mountain_classification` mode maps packet flags to stable debug colors.
   - `spawn_safe_patch` mode overlays the current spawn-safe zone on top of the
     normal terrain view.

3. Reuse patch cache intelligently.
   - If cache keys already include render mode, reuse cached patch results when
     possible.
   - If cache stores packet-only data, regenerate only the lightweight patch,
     not the canonical packet.
   - Switching render modes must be much cheaper than changing world settings.

4. Add spawn-safe visualization.
   - Reuse `WorldSpawnResolver` or a closely related seam so the visual overlay
     reflects the same start-area contract used by the real start flow.
   - Do not hardcode an unrelated visual rectangle in UI space.

5. Add optional zoom/pan controls.
   - Keep them bounded to the generated preview window.
   - Provide reset-to-spawn-center.
   - Controls must not introduce hidden world loading beyond the current target
     preview window.

6. Keep publication bounded.
   - Switching render mode may require republishing visible preview patches, but
     that republish must stay bounded.
   - No giant one-frame full preview rebuild is allowed.

## UI / UX Rule for Iteration 3

The normal preview remains the default.

Diagnostic tools must feel like an extra layer for tuning, not a replacement
for the main new-game experience.

Recommended UI shape:
- compact render-mode selector
- diagnostic modes grouped or visually marked as debug/lab modes
- zoom reset / center-on-spawn action if zoom/pan is implemented

If the menu starts to feel cluttered, diagnostic controls should be collapsible
or tucked behind an advanced/developer section.

## Performance Rules

- no canonical packet recompute on render-mode switch if packet data is already
  available for the current epoch
- no unbounded republish of the whole preview in one frame when switching modes
- no per-frame scan of all cached chunks if only currently visible patches need
  redraw
- no world-size growth caused by pan/zoom in this iteration; navigation remains
  bounded to the already generated preview window

## Risks

- render-mode switching may accidentally become expensive if cache reuse is not
  separated from packet recompute
- `mountain_id` colors may flicker between rebuilds unless the color mapping is
  deterministic
- spawn-safe overlay may drift from real start logic if it bypasses the spawn
  resolver seam
- extra controls may clutter the new-game panel if they are not clearly grouped
  as optional tools

## Smoke Tests

- normal terrain preview still works exactly as before when no diagnostic mode
  is selected
- switching to `mountain_id` does not trigger canonical worldgen recompute for
  already available packets
- switching to `mountain_classification` clearly distinguishes wall/foot/interior
- `spawn_safe_patch` overlay matches the actual preview start area contract
- zoom/pan, if implemented, stay bounded and can reset back to spawn-centered
  framing
- no debug overlay state leaks into save files or world runtime state

## Definition of Done

- diagnostic render modes exist and are opt-in
- render modes reuse canonical packet data instead of recomputing worldgen
- spawn-safe visualization is tied to the authoritative spawn seam
- normal preview remains the default player-facing mode
- any zoom/pan remains bounded and resettable
- no authoritative packet/save/runtime ownership boundary is changed

## Out of Scope Follow-Ups

Handle in later iterations, not here:
- rivers, temperature, biome, and resource overlays
- spawn scoring overlays for future smart spawn search
- export/share/seed-comparison UX
- screenshot/export pipeline
- broader in-game worldgen inspector outside the new-game screen
