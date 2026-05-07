---
title: Mountain Contour Mesh L1 - Debug Foundation
doc_type: iteration_brief
status: draft
owner: engineering+art
source_of_truth: false
version: 0.2
last_updated: 2026-05-07
related_docs:
  - world_runtime.md
  - world_grid_rebuild_foundation.md
  - mountain_generation.md
  - terrain_hybrid_presentation.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Mountain Contour Mesh L1 - Debug Foundation

## Goal

Add the smallest reliable marching-squares contour foundation for surface
mountains, with debug views that make the source tiles, solid mask, and
generated contour visible.

L1 is a diagnostic and data-foundation step. It is not expected to make the
normal mountain art look better yet. If debug is off, square mountain
presentation may still look unchanged after L1.

## Player / Developer Experience

The developer must be able to stand near a mountain edge and answer three
questions without guessing:

1. What are the actual `64 px` gameplay tiles?
2. Which tiles does the runtime currently treat as solid mountain?
3. What contour mesh is being generated from that solid mask?

Keyboard contract:

| Key | Debug view |
|---|---|
| `F6` | Toggle `64 px` tile grid. |
| `F7` | Toggle mountain solid mask. |
| `F10` | Toggle contour mesh debug overlay. |

`F8` must not be used. In the Godot editor it can conflict with editor run/stop
shortcuts and previously closed the game during testing.

## Non-Goals

- no visible art replacement in normal gameplay
- no collision replacement
- no navigation/pathfinding changes
- no save/load changes
- no `WORLD_VERSION` bump
- no worldgen algorithm changes
- no generator integration
- no changes to mining/building semantics
- no per-tile or per-segment scene nodes
- no GDScript marching-squares fallback for runtime

## Law 0 Classification

| Question | L1 answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Derived runtime/debug overlay. `terrain_ids`, `walkable_flags`, `mountain_id_per_tile`, and `mountain_flags` remain authoritative packet truth. |
| Save/load required? | No. Contour debug data is rebuilt from base + diff and never persisted. |
| Deterministic? | Yes. Same packet data and diff state produce the same contour. |
| Must it work on unloaded chunks? | No. Only loaded/published chunks need debug geometry. |
| C++ compute or main-thread apply? | Native/GDExtension computes contour streams. Main thread only applies debug draw/mesh data. |
| Dirty unit | One loaded chunk plus direct seam-neighbour participants for contour continuity. |
| Single owner | Native world contour helper owns derived contour geometry; `ChunkView` or dedicated debug visual layer owns draw/apply. |
| 10x / 100x scale path | More loaded mountain chunks create more queued chunk-local contour outputs; no whole-world prepass and no per-frame global scan. |
| Main-thread blocking risk | Apply must be bounded to one chunk/debug layer update. No mass scene-tree rebuild on a single tile mutation. |
| Hidden GDScript fallback? | Forbidden for marching-squares solve. Missing native support must disable/fail L1 explicitly in dev. |
| Could it become heavy later? | Yes. The solve starts native now so later visual/collision steps do not move tile loops into script. |
| Whole-world prepass or local compute only? | Local compute only. |

## Authoritative Inputs

L1 reads the current effective mountain state from loaded chunk data:

- `terrain_ids`
- `walkable_flags`
- `mountain_id_per_tile`
- `mountain_flags`
- runtime diff overrides already applied through the existing world runtime path

The solid mask must answer only:

```text
is this tile currently solid mountain for the surface layer?
```

It must not read rendered pixels, atlas colours, texture alpha, or generator
exports.

## Contour Source Rules

The L1 contour is derived from `base + diff`, not from canonical worldgen alone.

Rules:

- mined mountain tiles must disappear from the debug solid mask when the
  existing terrain mutation says they are no longer solid
- contour extraction must include a one-tile halo or equivalent seam data so
  chunk borders do not show false gaps
- diagonal-only contact does not create a face-connected solid component
- ambiguous marching-squares cases must use one deterministic tie-break rule
- contour vertices are in chunk-local pixel coordinates unless the existing
  runtime apply path requires world-space coordinates
- one world tile remains `64 px`

## Expected L1 Debug Artifacts

`F10` is a raw debug view, not final art.

Allowed in L1:

- triangle diagonals inside the contour mesh
- doubled cyan strips if the debug view draws both fill and wire
- small mitre spikes at ambiguous cases
- visible chunk-local triangulation

Not allowed:

- contour output missing a boundary where `F7` shows a continuous solid edge
- contour output crossing far into a walkable area unrelated to the source mask
- contour gaps caused by chunk seams
- debug overlay crashing the game or stealing editor shortcuts

L2 is responsible for hiding raw triangulation artifacts from the normal visual
presentation. L3 is responsible for collision alignment.

## Proposed Runtime Output

If L1 adds packet/debug fields across the native-to-script boundary, use compact
packed arrays and update `packet_schemas.md` in the same implementation task.

Candidate shape:

```text
mountain_contour_vertices: PackedVector2Array
mountain_contour_indices: PackedInt32Array
mountain_contour_edge_flags: PackedByteArray optional
```

Rules:

- arrays are derived runtime/debug data
- arrays are not saved
- arrays are not authoritative for walkability
- no nested dictionaries on the hot path
- no per-tile native calls

## Debug Rendering Contract

Layering:

1. normal terrain / mountain presentation
2. `F7` solid mask tint
3. `F6` tile grid
4. `F10` contour mesh overlay

Debug overlays must be easy to distinguish:

- `F6`: thin neutral grid lines aligned to `64 px` tiles
- `F7`: translucent solid-tile fill, not an outline-only view
- `F10`: high-contrast contour mesh, with visible vertices/triangles if useful

The debug layer must never change gameplay collision, walkability, mining,
save/load, or worldgen output.

## Files Likely Involved

- `core/systems/world/chunk_view.gd`
- `core/systems/world/chunk_debug_visual_layer.gd` or the existing equivalent
  debug owner if present
- `core/systems/world/world_streamer.gd`
- `core/systems/world/world_runtime_constants.gd` only for debug key constants
  if that is the existing local pattern
- `gdextension/src/world_core.cpp`
- `gdextension/src/mountain_contour.*` or equivalent native helper
- `docs/02_system_specs/meta/packet_schemas.md` if new packet fields are
  confirmed
- `docs/02_system_specs/meta/system_api.md` if a new public/debug entrypoint is
  confirmed

## Forbidden Files / Boundaries

- no save/load code
- no `WorldDiffStore` ownership changes
- no `WORLD_VERSION` bump
- no desktop generator changes
- no building/power/room/combat changes
- no pathfinding/navigation rewrite
- no `F8` input binding

## Implementation Steps

1. Identify the existing debug-input owner and register only `F6`, `F7`, and
   `F10`.
2. Add or restore the `64 px` tile grid debug draw behind `F6`.
3. Add or restore the mountain solid mask overlay behind `F7`.
4. Add native contour extraction from the same effective mountain solid source
   used by the loaded chunk runtime.
5. Apply the contour output through a chunk-owned debug visual layer.
6. Add seam-neighbour handling so contour debug does not break at chunk borders.
7. Add smoke tests or static checks for key bindings, no `F8`, and no save or
   `WORLD_VERSION` changes.
8. Update packet/API docs only for confirmed new boundary fields or entrypoints.

## Smoke Tests

- `F6` toggles the `64 px` grid without changing gameplay state.
- `F7` toggles the solid mountain mask and agrees with blocked mountain tiles.
- `F10` toggles contour mesh debug without closing the game.
- `F8` is not bound anywhere by this feature.
- Standing near a continuous mountain edge shows a continuous contour across
  loaded chunk seams.
- Debug overlays can be turned off and leave normal gameplay presentation as it
  was before L1.
- Existing save/load and `ChunkDiffFile` shapes remain unchanged.
- `WORLD_VERSION` remains unchanged.

## Definition of Done

- L1 gives reliable visual diagnostics for tile grid, mountain solid mask, and
  contour mesh.
- L1 does not promise art improvement in normal play.
- L1 contour geometry is derived, transient, and native-computed.
- L1 does not introduce gameplay collision changes.
- The key contract is documented and tested: `F6`, `F7`, `F10`, never `F8`.

## Manual Human Verification Required

Run the game from the Godot editor and check:

1. Press `F6`: grid appears/disappears.
2. Press `F7`: mountain solid mask appears/disappears.
3. Press `F10`: contour debug appears/disappears and the game does not close.
4. Compare `F7` and `F10` along a mountain edge and at one chunk seam.

## Required Updates When Implementing

- Update `packet_schemas.md` if the implementation adds contour arrays to the
  runtime packet/result shape.
- Update `system_api.md` if a new public/debug read surface is introduced.
- Do not update save/persistence docs unless the implementation accidentally
  changes save behavior; that would be a blocker, not expected scope.

