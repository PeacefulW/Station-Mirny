---
title: Rock Shader Presentation - Iteration Brief
doc_type: iteration_brief
status: draft
owner: engineering+art
source_of_truth: false
version: 0.1
last_updated: 2026-04-19
related_docs:
  - world_runtime.md
  - world_grid_rebuild_foundation.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Rock Shader Presentation - Iteration Brief

## Goal

Upgrade surface `rock` presentation from baked color-atlas tiles to `shape atlas + shader material`
while preserving the current authoritative world/runtime contract.

The new look should:
- keep the existing `47-case` rock silhouette logic
- reduce visible tile seams on rock tops
- support procedural/hybrid material rendering suitable for more realistic rock
- prepare dynamic lighting via normal-aware presentation

## Non-Goals

- no changes to authoritative terrain ids
- no packet schema changes
- no save/load format changes
- no ground/sand migration in this iteration
- no move of neighbour-solving into shaders
- no full chunk redraws in the interactive path

## Runtime Classification

- authoritative state: unchanged (`terrain_id`, `walkable`)
- derived state: `terrain_atlas_indices`, rock material presentation
- runtime work class:
  - boot/background: chunk publish with shader-backed rock cells
  - interactive: one local tile mutation plus bounded local visual patch refresh only
- dirty unit:
  - one changed tile for authoritative mutation
  - bounded local adjacency patch for rock presentation refresh

## Files Likely Involved

- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_streamer.gd`
- `assets/sprites/terrain/plain_rock_atlas.png`
- `assets/sprites/terrain/plain_rock_normal_atlas.png`
- `assets/shaders/` (new rock terrain shader/material inputs)
- tooling/script path for generating rock mask atlas and helper textures

## Forbidden Files / Boundaries

- no changes to packet shape in `gdextension/src/world_core.cpp`
- no changes to authoritative diff ownership in `core/systems/world/world_diff_store.gd`
- no gameplay changes in harvesting/building/player systems

## Risks

- shader path may accidentally depend on broad per-frame world reads
- mask atlas and material shader may diverge from current 47-case mapping
- too much procedural breakup may harm readability versus rock silhouette
- too many texture samples could bloat the `TileMapLayer` hot render path

## Implementation Steps

1. Replace baked rock color atlas usage with a rock shape/mask atlas.
2. Add a bounded shader material path on `ChunkView` rock presentation only.
3. Keep current atlas-index solving in native/script unchanged.
4. Drive top/facade rock appearance from procedural/hybrid shader inputs:
   - palette-driven base color
   - world-space macro breakup
   - small debris/dust variation
   - normal-aware relief
5. Preserve local runtime patch refresh through existing `_refresh_loaded_visual_patch_for_tiles`.

## Smoke Tests

- rock chunks still publish through existing `terrain_atlas_indices`
- rock mutation still refreshes only bounded local loaded patch
- plains ground remains unchanged visually and architecturally
- save/load still restores rock diffs correctly
- shader path does not require full chunk republish on one tile mutation

## Definition of Done

- rock render path uses `shape atlas + shader material`
- visible rock top seams are reduced versus the current baked atlas
- runtime local refresh still stays bounded
- no authoritative boundary or packet contract is changed
