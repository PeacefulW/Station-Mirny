---
title: Mountain Contour Mesh L3 - Collision Alignment
doc_type: iteration_brief
status: draft
owner: engineering
source_of_truth: false
version: 0.2
last_updated: 2026-05-07
related_docs:
  - mountain_contour_mesh_l1_debug_foundation_iteration_brief.md
  - mountain_contour_mesh_l2_visual_replacement_iteration_brief.md
  - world_runtime.md
  - mountain_generation.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Mountain Contour Mesh L3 - Collision Alignment

## Goal

Align mountain gameplay collision with the contour-driven mountain presentation
introduced by L2, without making collision or visuals the source of gameplay
truth.

L3 makes the new mountain edge feel physically believable: the player should
not walk through the visible rock face, and the player should not be blocked by
large invisible square tile corners that L2 no longer shows.

## Player Experience

The player can walk along a contour-shaped mountain edge and feel the collision
following the visible rock mass closely enough for normal top-down movement.

The result does not need pixel-perfect physics. It must be coherent:

- no obvious invisible square wall where the visual edge is rounded
- no pass-through gap through the visible rock face
- no stuck points on normal edge-following movement

## Non-Goals

- no new terrain ids
- no worldgen algorithm changes
- no save/load changes
- no `WORLD_VERSION` bump
- no pathfinding/navigation rewrite
- no building placement rewrite
- no mining semantics rewrite
- no generator integration
- no collision for water, dirt, caves, biomes, or future terrain families
- no per-tile or per-segment collision nodes
- no GDScript marching-squares/collision fallback for runtime

## Law 0 Classification

| Question | L3 answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Derived runtime collision overlay. Tile terrain/walkability remains authoritative gameplay truth. |
| Save/load required? | No. Collision is rebuilt from base + diff when chunks load. |
| Deterministic? | Yes. Same solid mask/contour settings produce the same collision shapes. |
| Must it work on unloaded chunks? | No persisted collision for unloaded chunks; loaded chunks must be safe before movement-ready. |
| C++ compute or main-thread apply? | Native/GDExtension computes collision polygon streams. Main thread registers bounded collision shapes. |
| Dirty unit | One loaded chunk plus direct seam-neighbour participants after local mountain mutation. |
| Single owner | Native contour/collision helper owns derived geometry. `ChunkView` owns collision node apply. `WorldDiffStore` remains authoritative diff owner. |
| 10x / 100x scale path | More mountain edges add chunk-local collision polygons; no whole-world collision bake and no node per segment. |
| Main-thread blocking risk | Collision node apply must stay bounded and avoid mass scene-tree churn. |
| Hidden GDScript fallback? | Forbidden. Missing native collision extraction disables/fails L3 explicitly in dev. |
| Could it become heavy later? | Yes. Polygon simplification and batching must be native/bounded now. |
| Whole-world prepass or local compute only? | Local loaded-chunk compute/apply only. |

## Authority Contract

`WorldStreamer.is_walkable_at_world(world_pos)` remains the public walkability
read and continues to read `base + diff`.

Rules:

- tile walkability remains the authoritative gameplay gate
- collision must not be saved
- collision must not mutate `WorldDiffStore`
- collision must not decide mining eligibility
- collision must not decide building placement
- if collision and tile walkability disagree, tile walkability wins for
  gameplay rules and the mismatch is a bug to debug, not a new authority model

L3 is allowed to improve player physics contact with mountains. It is not
allowed to replace the tile-based world model.

## Collision Source

Collision is derived from the same effective mountain solid mask used by L1 and
the same visible contour family used by L2.

Forbidden sources:

- rendered pixels
- texture alpha
- generator output masks
- screenshot/image analysis
- ad-hoc visual mesh edits that do not trace back to `base + diff`

The collision shape may be simplified relative to the visual mesh, but it must
stay within an agreed tolerance of the visible L2 edge.

## Proposed Runtime Output

If L3 adds packet/result fields across the native/script boundary, use compact
packed arrays and update `packet_schemas.md` in the same implementation task.

Candidate shape:

```text
mountain_collision_vertices: PackedVector2Array
mountain_collision_polygon_offsets: PackedInt32Array
mountain_collision_polygon_count: int
mountain_collision_debug_flags: PackedByteArray optional
```

Rules:

- no nested dictionaries on hot paths
- no per-tile collision nodes
- no per-segment collision nodes
- no saved collision data
- no texture paths in collision packets

## Collision Apply Model

`ChunkView` should own one collision root for mountain contour collision in a
chunk.

Allowed apply shape:

- one chunk-owned collision root
- a small bounded number of polygon children per chunk
- clear/reuse the chunk collision root on unload
- register collision only after the corresponding chunk terrain is ready

Forbidden apply shape:

- one node per tile
- one node per segment
- rebuilding every loaded chunk after one local mutation
- `queue_free()` storms in the interactive mining frame
- applying collision before gameplay-critical terrain/walkability is ready

## Debug Contract

The existing debug keys remain stable:

| Key | Debug view |
|---|---|
| `F6` | `64 px` tile grid |
| `F7` | mountain solid mask |
| `F10` | contour debug overlay |

L3 may extend `F10` to show collision alignment in a second colour, for example:

- visual/source contour: cyan
- collision polygon: magenta or orange
- mismatch warning: red

Do not bind `F8`.

`F10` must make it clear whether a visible diagonal is a harmless triangle edge
from debug triangulation or an actual collision boundary.

## Runtime Mutation Rules

When mining changes one mountain tile:

1. existing authoritative terrain diff is written
2. affected loaded chunk and direct seam neighbours are marked collision-dirty
3. stale contour collision is cleared, degraded, or kept behind a safety gate
4. native collision refresh is queued/bounded
5. main-thread apply registers only the affected collision roots/polygons
6. save payload remains unchanged

During refresh, tile walkability remains the safety gate. The player must not be
allowed to pass through authoritative blocked terrain because contour collision
is temporarily stale.

## Movement Readiness

If L3 is enabled, a chunk is movement-ready only when:

- terrain and walkability are ready
- blocking mountain terrain from the authoritative packet/diff is ready
- contour collision for visible mountain edges is either applied or explicitly
  disabled behind a documented dev feature flag

This follows Engineering Standards LAW 10: gameplay-critical movement and
collision layers must be ready before showing a chunk as playable.

## Files Likely Involved

- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_streamer.gd`
- `core/systems/world/chunk_debug_visual_layer.gd` or equivalent
- `core/systems/world/world_runtime_constants.gd` only if a local debug flag/key
  pattern already lives there
- `gdextension/src/mountain_contour.*`
- `gdextension/src/world_core.cpp`
- smoke/headless tests for mountain contour collision if the project has a
  nearby runtime test surface
- `docs/02_system_specs/meta/packet_schemas.md` if packet/result fields change
- `docs/02_system_specs/meta/system_api.md` if a public/debug read surface is
  added

## Forbidden Files / Boundaries

- no save/load code changes
- no `WORLD_VERSION` bump
- no desktop generator changes
- no worldgen settings/resource changes
- no building placement rewrite
- no pathfinding/navigation rewrite
- no combat/player controller redesign beyond using the normal Godot collision
  path already used by terrain/world obstacles
- no `F8` input binding

## Implementation Steps

1. Confirm L1 and L2 source contour are stable with `F6`, `F7`, and `F10`.
2. Add native collision polygon extraction from the same contour/solid source.
3. Add polygon simplification/clamping so collision does not create excessive
   vertices or tiny snag triangles.
4. Apply collision through one chunk-owned collision root.
5. Extend `F10` to show visual contour and collision contour together.
6. Wire mining/local terrain mutation to mark only affected collision dirty
   units.
7. Add smoke tests/static checks for no save fields, no `WORLD_VERSION` bump,
   no `F8`, no per-tile/per-segment nodes, and no full loaded-world rebuild.
8. Update packet/API docs only for confirmed new boundary fields or entrypoints.

## Smoke Tests

- Player cannot walk through visible L2 mountain rock faces.
- Player is not blocked by large invisible square corners after L2 visual
  replacement.
- Walkable tile centers remain reachable unless authoritative tile walkability
  says blocked.
- One mined mountain tile refreshes only local collision dirty units.
- Save/load payload shapes remain unchanged.
- `WORLD_VERSION` remains unchanged.
- No collision data appears in `ChunkDiffFile`.
- `F6`, `F7`, and `F10` still work; `F8` remains unbound.
- Dense mountain edges do not create per-tile or per-segment collision nodes.

## Definition of Done

- Mountain collision follows the L2 visible contour closely enough for normal
  top-down movement.
- Tile walkability remains authoritative for gameplay rules.
- Collision is derived, transient, chunk-owned, and not persisted.
- Runtime mutation uses bounded dirty collision refresh.
- Debug views expose grid, mask, visual contour, and collision alignment without
  using `F8`.

## Manual Human Verification Required

Run the game and check one mountain edge:

1. Debug off: walk along the visible mountain edge and look for invisible square
   walls or pass-through gaps.
2. `F6`: confirm the tile grid still explains the underlying cells.
3. `F7`: confirm the solid mask still matches authoritative mountain tiles.
4. `F10`: confirm collision and visual contour alignment.
5. Mine one exposed mountain tile and check that collision refreshes locally.

## Required Updates When Implementing

- Update `packet_schemas.md` if collision polygon fields cross the native/script
  boundary.
- Update `system_api.md` if a new public/debug collision read surface is added.
- Do not update save/persistence docs unless the implementation changes save
  behavior; that would be a blocker, not expected scope.

