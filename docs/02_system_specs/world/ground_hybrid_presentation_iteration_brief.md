---
title: Ground Hybrid Presentation - Iteration Brief
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

# Ground Hybrid Presentation - Iteration Brief

## Goal

Extend the current hybrid terrain presentation path from `rock` to the current
walkable surface ground, so the base biome terrain also renders as
`shape/occupancy atlas + shader material`, not as a baked color atlas.

This iteration establishes the generic ground hybrid seam using the existing
`plains ground` path only.

## Non-Goals

- no packet schema changes
- no save/load changes
- no new authoritative terrain ids
- no biome expansion in native generation
- no full chunk republish on one tile mutation
- no migration of `dug` presentation in this iteration

## Runtime Classification

- authoritative state: unchanged (`terrain_id`, `walkable`)
- derived state: `terrain_atlas_indices`, ground presentation material
- runtime work class:
  - boot/background: chunk publish with shader-backed ground cells
  - interactive: bounded local runtime cell update only
- dirty unit:
  - one changed tile authoritatively
  - bounded local adjacency patch for atlas index refresh

## Allowed Files

- `assets/shaders/ground_hybrid_material.gdshader`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/chunk_view.gd` if strictly needed for presentation wiring
- `assets/textures/terrain/terrain_plains_albedo.png`
- `assets/textures/terrain/terrain_plains_modulation.png`

## Forbidden Files / Boundaries

- no changes to `gdextension/src/world_core.cpp`
- no changes to `core/systems/world/world_diff_store.gd`
- no changes to save/load contract docs or packet docs
- no reintroduction of chunk-wide blend-map generation on runtime hot paths

## Implementation Shape

1. Keep existing atlas-index solve for plains ground untouched.
2. Use the current plains atlas only as tile occupancy/shape source.
3. Apply a world-space ground shader per plains tile through `TileData.material`.
4. Drive visible color from external albedo/modulation textures instead of atlas RGB.
5. Leave `dug` as-is for this iteration.

## Smoke Tests

- plains ground still publishes through the existing `terrain_atlas_indices`
- rock path remains intact
- dug path remains intact
- no packet/schema/save contract changes
- editor/runtime still start after the shader-backed plains path is introduced

## Definition of Done

- current plains ground no longer depends on baked atlas color in runtime
- plains ground uses hybrid material inputs from dedicated texture files
- future biome-specific ground textures can extend this pattern without changing
  authoritative world contracts
