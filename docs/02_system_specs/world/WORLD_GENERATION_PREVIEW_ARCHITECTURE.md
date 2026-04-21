---
title: World Generation Preview Architecture
doc_type: design_proposal
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-04-21
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - world_grid_rebuild_foundation.md
  - world_runtime.md
  - mountain_generation.md
---

# World Generation Preview Architecture

> This file is a design proposal, not source of truth.
> Before implementation, land an approved spec update or implementation brief.

## Goal

Add a live new-game preview that shows the actual worldgen result around the
start area while the player edits seed and mountain settings.

The UX target is a progressive chunk-by-chunk fill from the spawn area outward.
The engineering target is zero architectural divergence from runtime worldgen.

## Core rule

Use the same canonical chunk packet as runtime, but a different render path.

In short:

`same packet generation, separate preview renderer`

Preview must not become:
- a second generator
- a hidden gameplay world running inside the menu
- a save-producing or diff-producing path

## Existing foundations in the repo

Current code already gives the needed base:

- `scenes/ui/new_game_panel.gd` owns seed text and `MountainGenSettings`
- `core/systems/world/world_streamer.gd` already owns
  worker thread, request queue, result queue, packed settings, and `epoch`
- `WorldCore.generate_chunk_packet(...)` already generates runtime chunk packets
- `ChunkPacketV1` already carries mountain fields
- `world.json` already persists `worldgen_settings.mountains`

Because of this, preview should consume the same packet contract instead of
inventing preview-only generation math.

## Architectural shape

Recommended split:

- `NewGamePanel`
  - UI owner only
  - emits normalized seed + settings snapshot for preview and start

- `WorldChunkPacketBackend`
  - shared request/result worker wrapper
  - accepts `seed`, `coord`, `world_version`, `settings_packed`, `epoch`
  - returns full chunk packet
  - knows nothing about `ChunkView`, save/load, or menu UI

- `WorldPreviewController`
  - preview orchestrator
  - debounce
  - epoch bump
  - spawn resolution
  - spiral order build
  - packet cache
  - stale-result drop

- `WorldPreviewCanvas`
  - lightweight draw surface
  - draws ready preview patches by chunk coordinate
  - draws spawn marker and optional chunk grid

- `WorldPreviewPalette`
  - packet-to-image mapping
  - builds one small preview patch per chunk

- `WorldSpawnResolver`
  - authoritative start-tile seam for both runtime and preview

## What must stay true

### 1. Seed normalization must be shared

Preview must use the same seed resolution path as `Start`:
empty seed fallback, integer parse, and hashed text path must never diverge.

### 2. Packet boundary must stay the same

Do not add preview-only per-tile native calls.
Do not create a second packet format if `ChunkPacketV1` is sufficient.

### 3. Preview is transient only

Preview must never:
- write `world.json`
- write chunk diff files
- mutate `WorldDiffStore`
- emit world runtime lifecycle events as if the game already started

## Scheduling and fill order

Preview should not request the full outer radius as one monolithic pass.

If the window is about `spawn ±500 tiles`, then with `32 x 32` chunks it is
roughly `33 x 33 = 1089` chunks. That is acceptable only as progressive fill.

Use two stages:

1. fast pass
- small inner radius around spawn
- gives immediate visual feedback

2. full pass
- keeps filling outer rings afterward

Chunk order should be a deterministic square spiral around the spawn chunk.

## Render strategy

Do not render real gameplay chunks in the menu.

One preview chunk should become one lightweight patch:
- `Image`
- `ImageTexture`
- one patch per chunk
- nearest-neighbor scale

This keeps the main thread bounded:
- one packet result arrives
- one patch is built
- one patch is published
- no whole-image rebuild

The preview may be stylized.
It must be shape-true, not necessarily tileset-perfect.

## Performance guardrails

Interactive path may do only:

- slider or seed input change
- debounce reset
- epoch increment
- queue rebuild
- bounded patch publish

Forbidden on the menu hot path:

- full preview redraw on every ready chunk
- per-tile native queries
- hidden `WorldRuntimeV0` scene boot
- real `ChunkView` / `TileMapLayer` generation
- whole-world prepass

Cancellation is mandatory:
old results whose `epoch` does not match the current preview epoch are dropped.

## File scope for the first implementation task

### New files

- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/world_spawn_resolver.gd`
- `core/systems/world/world_preview_palette.gd`
- `core/systems/world/world_preview_controller.gd`
- `scenes/ui/world_preview_canvas.gd`

### Modified files

- `core/systems/world/world_streamer.gd`
- `scenes/ui/new_game_panel.gd`

### Files that should stay out of scope

- save payload shape
- building and power systems
- combat systems
- z-level runtime
- mountain generation math itself, unless a separate versioned worldgen task is approved

## Acceptance criteria

- [ ] changing seed or mountain settings rebuilds preview without freezing the menu
- [ ] preview uses the same normalized seed and packed settings layout as the start path
- [ ] preview fills by chunk patches, not by hidden gameplay chunks
- [ ] preview begins from the spawn chunk and expands outward in stable spiral order
- [ ] fast pass gives early feedback; outer rings continue progressively
- [ ] stale results from old settings are never published
- [ ] preview writes nothing to save files before `Start`

## Follow-ups when code lands

If implementation introduces a new public runtime boundary, update in the same task:

- `system_api.md`
- `packet_schemas.md`
- `event_contracts.md`
- `commands.md`

Preferred MVP outcome:
no new canonical packet schema and no new global event surface are needed.
