---
title: New-Game Composite World Overview
doc_type: iteration_brief
status: approved
owner: design+engineering
source_of_truth: false
version: 0.1
last_updated: 2026-04-29
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - world_foundation_v1.md
  - river_generation_v1.md
  - world_runtime.md
  - WORLD_GENERATION_PREVIEW_ARCHITECTURE.md
---

# New-Game Composite World Overview

## Goal

Make the full-world map in the new-game panel readable as one geographic map
instead of forcing the player to switch between relief and water modes.

The player-facing default overview should show:

- terrain / relief underlay: ground, mountain foot, mountain wall, and subtle
  height readability;
- water overlay: rivers, lakes, deltas / estuaries, and the north ocean;
- existing spawn marker, detail-preview region, and X-wrap hints.

The result should answer "what kind of world is this seed?" in one glance.

## Design Decision

Add a new overview mode:

```text
WorldFoundationPalette.COMPOSITE = &"composite"
```

`COMPOSITE` is the default player-facing overview mode and the first option in
the mode selector. Existing `terrain`, `hydrology_water`, and `hydro_height`
modes remain available as diagnostic / debug-style views.

The composite mode is presentation-only. It must not change canonical terrain,
hydrology, packet fields, save shape, `world_version`, spawn selection, or
runtime gameplay behavior.

## Current Boundary

Current code has three separate overview modes:

- `terrain` through `WorldCore.get_world_foundation_overview(...)`;
- `hydrology_water` through `WorldCore.build_world_hydrology_prepass(...)` and
  `WorldCore.get_world_hydrology_overview(...)`;
- `hydro_height` through `WorldCore.get_world_foundation_overview(...)` with a
  height-map layer mask.

The current hydrology overview image is opaque and includes its own backing
colors, so it cannot be drawn directly over the foundation overview without
hiding relief. Composite mode needs either a transparent hydrology-water overlay
or a native composite image path.

## Runtime / Performance Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Visual only. |
| Save/load required? | No. |
| Deterministic? | Yes, because both source overview images are deterministic reads of existing seed/settings/world-version data. |
| Must work on unloaded chunks? | Yes. It uses existing full-world overview worker paths and does not instantiate gameplay chunks. |
| C++ compute or main-thread apply? | Existing foundation and hydrology overview compute stays native/worker-owned. Main thread only receives and publishes one texture. |
| Dirty unit | One overview image per seed/settings/overview-mode epoch. |
| Single owner | `WorldPreviewController` owns requested mode and publication; `WorldChunkPacketBackend` owns worker requests; native `WorldCore` owns source overview images. |
| 10x / 100x scale path | Overview dimensions stay tied to substrate / hydrology overview image size and `OVERVIEW_PIXELS_PER_CELL`, not full tile count. No gameplay-path work. |
| Main-thread blocking risk | Forbidden. No main-thread pixel composition or whole-world generation. |
| Hidden fallback? | Forbidden for native source overview APIs. Missing native support should fail with an explicit preview error. |
| Could it become heavy later? | Yes. Any image composition must run on the existing preview worker path or native helper, not in UI draw. |
| Whole-world prepass? | Existing approved preview exception only: worker preview with no gameplay world active. |

Runtime class: `background/new-game-preview worker`, not interactive gameplay.

## Implementation Shape

Preferred implementation:

1. Add `COMPOSITE` to `WorldFoundationPalette`.
2. Make `COMPOSITE` the default `_active_mode` and first ordered mode.
3. Add localization keys for the selector label in RU and EN.
4. Route `COMPOSITE` overview requests through `WorldChunkPacketBackend` as a
   distinct overview request path, not as plain `hydrology_water`.
5. Build the source foundation overview and source hydrology water overlay on
   the preview worker path.
6. Composite water over the foundation image before returning the final
   overview result to `WorldPreviewController`.
7. Keep `WorldOverviewCanvas` unchanged unless a tiny visual polish is needed;
   the canvas should still draw one texture snapshot plus existing UI overlays.

Implementation may use either:

- a native transparent hydrology-water overlay image plus worker-side image
  blending; or
- a native composite overview helper that writes the final composite image.

The selected path must not add GDScript world/tile generation logic. If
GDScript performs image blending, it must run inside the existing preview worker
thread and only over the bounded overview image, not over world tiles.

## Scope - What To Do

- Make combined relief + water the default overview shown in the new-game panel.
- Preserve the existing mode selector, with combined first.
- Preserve terrain, water, and height modes for diagnostics.
- Ensure seed/settings changes still debounce and cancel by epoch.
- Keep spawn marker, detail region, and wrap hints visible above the composite
  texture.
- Use existing native source data and existing overview request lifecycle.

## Scope - What Not To Do

- Do not create an in-game map or PDA map.
- Do not change chunk packet fields.
- Do not change river, lake, ocean, mountain, or foundation generation output.
- Do not bump `WORLD_VERSION`.
- Do not add save fields.
- Do not generate gameplay chunks for the full-world overview.
- Do not add water simulation, drought/refill, weather, climate, or biome
  content.
- Do not remove diagnostic modes unless a separate UI decision approves that.

## Files Likely Involved

Allowed implementation files:

- `core/systems/world/world_foundation_palette.gd`
- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/world_preview_controller.gd`
- `scenes/ui/new_game_panel.gd`
- `locale/ru/messages.po`
- `locale/en/messages.po`

Allowed only if the implementation chooses native overlay/composite support:

- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_hydrology_prepass.h`
- `gdextension/src/world_hydrology_prepass.cpp`

Allowed documentation updates when code lands:

- `docs/02_system_specs/world/world_foundation_v1.md`
- `docs/02_system_specs/world/WORLD_GENERATION_PREVIEW_ARCHITECTURE.md`
- `docs/02_system_specs/meta/system_api.md` only if a new native public method
  or new documented overview layer mask is introduced.

Forbidden files:

- gameplay runtime world streaming outside the preview path;
- save/load systems;
- biome/content registries;
- building, power, combat, progression, and subsurface systems;
- world generation settings resources, unless only a label/reference is needed.

## Acceptance Tests

- [ ] Opening the new-game panel shows the combined relief + water overview by
      default.
- [ ] The overview selector lists combined first, then terrain, water, and
      height / diagnostic modes.
- [ ] The combined overview shows mountain relief and visible rivers, lakes, and
      ocean in one image for a river-enabled `world_version >= 20` preview.
- [ ] Switching to terrain-only still hides water and shows the existing relief
      view.
- [ ] Switching to water-only still shows the existing hydrology water overview.
- [ ] Switching to height still shows the diagnostic height-map view.
- [ ] Seed, size, geology, and water setting changes still rebuild through the
      existing debounce / epoch path and do not publish stale images.
- [ ] The overview canvas still draws spawn marker, detail region, and wrap hints
      over the final map texture.
- [ ] Static search confirms no save fields, packet fields, or `WORLD_VERSION`
      constants changed.
- [ ] Static search confirms no gameplay `ChunkView` / `TileMapLayer` path is
      introduced for full-world overview rendering.

## Proof Expectations

Required agent-run verification:

- static grep for the new `COMPOSITE` mode and localization keys;
- static grep showing `WORLD_VERSION` unchanged;
- static grep showing no new save or packet fields;
- static read of the final files to confirm `COMPOSITE` is default and first in
  the ordered mode list.

Runtime / visual verification:

- Manual human verification is acceptable unless the task explicitly asks the
  agent to run Godot or capture screenshots.
- Suggested human check: open the new-game panel, change water settings, and
  verify the full-world overview still shows relief while rivers/lakes/ocean are
  visible without switching modes.

## Required Canonical Documentation Check

When implementation lands, update canonical docs if the visible default behavior
changes:

- `world_foundation_v1.md`: default player overview now uses composite terrain +
  water presentation for river-enabled worlds; terrain-only remains diagnostic.
- `WORLD_GENERATION_PREVIEW_ARCHITECTURE.md`: overview mode list and default
  mode must mention composite.
- `system_api.md`: update only if a new native public method or documented layer
  mask is added.

No `packet_schemas.md`, `commands.md`, `event_contracts.md`, or
`save_and_persistence.md` update is expected unless implementation unexpectedly
changes those boundaries.

## Definition Of Done

- The new-game panel default overview is composite.
- Existing diagnostic modes still work.
- No canonical generation, save/load, packet, command, or event boundary is
  changed.
- Relevant docs are updated if code changes player-facing default behavior.
- Closure report includes static proof for unchanged `WORLD_VERSION`, save
  shape, and packet shape.
