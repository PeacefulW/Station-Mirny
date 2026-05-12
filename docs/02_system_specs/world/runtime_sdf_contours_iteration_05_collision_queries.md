---
title: Runtime SDF Contours - Iteration 05 Collision Queries
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
---

# Runtime SDF Contours - Iteration 05 Collision Queries

## Goal

Make movement collision read the same contour field that renders mountain mass,
so blocking follows the visible terrain boundary rather than square logical
tiles.

## Non-Goals

- no building placement redesign
- no room solver redesign
- no save/load change
- no physics-body terrain collider requirement
- no square tile fallback for movement after collision cutover

## Runtime Classification

- authoritative state: terrain packet, runtime diff, contour recipe
- derived state: collision SDF field per loaded chunk
- runtime work class: O(1) movement-time read from cached contour data
- dirty unit: one chunk collision field revision

## Allowed Files

- `core/systems/world/world_streamer.gd`
- `core/entities/player/player.gd`
- `gdextension/src/world_contour_field.cpp`
- `gdextension/src/world_contour_field.h`
- new `tools/runtime_sdf_contour_collision_smoke_test.gd`
- `docs/02_system_specs/meta/system_api.md`

## Forbidden Boundaries

- no physics-body terrain mesh generation
- no GDScript SDF computation
- no save/load changes
- no building placement changes

## Implementation Shape

1. Add `WorldStreamer.is_movement_blocked_at_world(world_pos)`.
2. Make `WorldStreamer.is_walkable_at_world(world_pos)` combine raw tile
   walkability with contour collision blocking.
3. Add `WorldStreamer.is_raw_tile_walkable_at_world(world_pos)`.
4. Add `WorldStreamer.get_effective_tile_data_at_world(world_pos)`.
5. Sample collision fields by chunk coordinate and class.
6. Treat missing or stale collision data as not movement-ready.
7. Preserve the player's existing multi-point footprint sampling, but each
   point now reads contour-aware walkability.
8. Add edge tests that sample points just inside and just outside a rounded
   mountain contour.
9. Add seam tests that sample across two adjacent chunks.

## Raw Tile Query Consumers

These systems must use `get_effective_tile_data_at_world()` or
`is_raw_tile_walkable_at_world()` rather than movement-facing
`is_walkable_at_world()`:

- mining and `try_harvest_at_world()`
- resource checks and `has_resource_at_world()`
- build placement
- debug overlays
- save/diff inspection tools
- future AI/path planning until an AI movement contour spec exists

The player movement path keeps using `is_walkable_at_world()`.

## Required Tests and Commands

Run Godot smoke test:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful"
godot --headless --path . --script res://tools/runtime_sdf_contour_collision_smoke_test.gd
```

The smoke test must assert:

- `is_walkable_at_world()` blocks inside visible mountain occupancy
- `is_walkable_at_world()` allows movement outside rounded visible occupancy
- `is_raw_tile_walkable_at_world()` returns logical tile walkability without
  contour blocking
- missing or stale collision data returns not movement-ready for movement
- seam sampling reads the correct neighboring contour field

## Smoke Tests

- player cannot enter visible mountain mass
- player can approach rounded corners without hitting invisible square corners
- player cannot move into chunks whose contour collision is not ready
- water and non-mountain tile semantics remain governed by existing walkability
  rules
- raw tile query still returns logical tile truth for non-movement systems
- player movement still calls the contour-aware query

## Definition of Done

- movement collision follows visible mountain occupancy
- square tile corners no longer block movement outside the visible contour
- no visible mountain contour can be walked through
- collision readiness is part of chunk readiness
- system API documents the distinction between raw tile walkability and movement
  walkability
