---
title: Mountain Contour Mesh L2 - Visual Replacement Prototype
doc_type: iteration_brief
status: draft
owner: engineering+art
source_of_truth: false
version: 0.2
last_updated: 2026-05-07
related_docs:
  - mountain_contour_mesh_l1_debug_foundation_iteration_brief.md
  - world_runtime.md
  - mountain_generation.md
  - terrain_hybrid_presentation.md
  - ../meta/packet_schemas.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Mountain Contour Mesh L2 - Visual Replacement Prototype

## Goal

Replace the visible square/stair-step mountain edge in normal gameplay with a
contour-driven mountain presentation prototype.

L2 is the first step that should visibly change what the player sees. It folds
the previous "L1.2 Visual Replacement Prototype" idea into the clean L1/L2/L3
roadmap:

- L1: prove and debug the source contour
- L2: use the contour for visible mountain art
- L3: align gameplay collision with that contour

## Player Experience

With debug off, the mountain should read less like a block of square tiles and
more like one continuous natural rock mass. It does not need final production
quality yet, but the obvious `64 px` stair-step edge should no longer be the
dominant shape at normal gameplay zoom.

## Non-Goals

- no collision replacement
- no pathfinding/navigation changes
- no mining/building semantics changes
- no save/load changes
- no `WORLD_VERSION` bump
- no worldgen classification changes
- no runtime call into the desktop generator
- no per-tile render nodes
- no full chunk republish on one tile mutation
- no final biome-wide terrain art system

## Law 0 Classification

| Question | L2 answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Visual presentation only. Gameplay truth remains `terrain_ids`, `walkable_flags`, and runtime diff. |
| Save/load required? | No. Visual resources are authored assets; runtime mesh/material state is not saved. |
| Deterministic? | Yes for a given contour source, material profile, seed, chunk, and diff state. |
| Must it work on unloaded chunks? | No runtime mesh for unloaded chunks; it must be rebuildable when chunks stream back in. |
| C++ compute or main-thread apply? | L1/native contour data is reused. Main thread applies bounded visual mesh/material data only. |
| Dirty unit | One changed tile authoritatively; bounded local contour/presentation patch for loaded chunks and seam neighbours. |
| Single owner | `WorldCore`/native helper owns contour geometry. `ChunkView` or a mountain presentation layer owns rendering. Generator owns offline authored assets only. |
| 10x / 100x scale path | More mountain chunks add chunk-local visual meshes/materials; no global world scan or node per tile. |
| Main-thread blocking risk | Mesh/material apply must be chunk-local and budgeted. No synchronous texture loading on runtime path. |
| Hidden GDScript fallback? | Forbidden for contour solve. Visual apply may be script orchestration only. |
| Could it become heavy later? | Yes. The visual path must use packed geometry/resources, not per-tile scene nodes. |
| Whole-world prepass or local compute only? | Local loaded-chunk compute/apply only. |

## Visual Strategy

L2 should use a mesh-dominant prototype:

1. Use the L1 mountain contour as the silhouette source.
2. Render a filled mountain top surface over the old square mountain tile mass.
3. Add a readable rim/lip and facade/shadow band along the contour edge.
4. Suppress or visually neutralize the old square edge in normal gameplay.
5. Keep debug overlays above the visual layer.

The old tilemap may remain underneath as gameplay-critical terrain and a
fallback, but the player-facing mountain silhouette must come from the contour
presentation when L2 is enabled.

## Relationship to L1 Debug

The debug key contract remains:

| Key | Debug view |
|---|---|
| `F6` | `64 px` tile grid |
| `F7` | mountain solid mask |
| `F10` | contour mesh/debug overlay |

`F10` must continue to show the source/debug contour even after L2 hides raw
triangulation in normal play.

Debug artifacts that are acceptable in `F10` are not acceptable in the normal
L2 presentation. In normal gameplay:

- triangle diagonals must not be visible
- random cyan debug strips must not be visible
- contour gaps must not expose square edges underneath
- small shape irregularities are acceptable if they read as rock roughness

## Authoring / Generator Track

The desktop generator at:

```text
tools/rimworld-autotile-lab/desktop_app
```

may be updated in L2 if authored assets are needed for the prototype.

Allowed generator work:

- add a mountain contour/rock material preset for authoring
- export top/facade/rim albedo or mask textures
- export normal/height/modulation maps for rock material response
- export a small metadata file or `.tres` resource recipe that the game imports
- preview organic blobs so the generated assets match the desired look

Forbidden generator work:

- the game runtime must not launch or call the generator
- generator output must not define collision, walkability, mining, building, or
  save truth
- generator output must not introduce a second independent mountain shape source
- generator exports must not be generated during chunk publish

Generator assets are visual assets only. The contour source remains the
runtime-derived mountain solid mask from L1.

## Runtime Presentation Data

L2 may reuse the L1 contour streams. If additional visual streams are needed,
they should be compact and derived:

```text
mountain_visual_vertices: PackedVector2Array
mountain_visual_indices: PackedInt32Array
mountain_visual_uvs: PackedVector2Array optional
mountain_visual_zone_flags: PackedByteArray optional
```

Rules:

- no nested dictionaries on hot paths
- no per-tile render nodes
- no saved visual mesh state
- no texture paths in runtime packets; use preloaded/registered resources
- update `packet_schemas.md` if new packet/result fields become confirmed code
  boundaries

## Layering Rules

Normal gameplay layering:

1. ground / lake / base terrain presentation
2. old mountain gameplay tile layer, hidden/neutralized only as presentation
3. L2 contour mountain top/facade/rim presentation
4. roof/cover presentation, if active and already owned by the mountain system
5. debug overlays (`F7`, `F6`, `F10`)

L2 must not break roof/cover visibility semantics from `mountain_generation.md`.
If the existing roof system cannot safely be integrated in the same iteration,
L2 must define a guarded prototype mode rather than silently changing cover
truth.

## Runtime Mutation Rules

When one mountain tile is mined through the existing mutation path:

1. authoritative diff changes exactly as it does today
2. affected chunk and direct seam neighbours are marked dirty for contour visual
   refresh
3. stale L2 visual mesh is cleared, degraded, or locally patched
4. no full loaded-world visual rebuild happens in the interactive frame
5. no save payload changes are written

During the refresh window, gameplay remains governed by existing tile
walkability and collision. Visual mismatch during refresh is acceptable only as
a short degraded state, not as a permanent result.

## Files Likely Involved

Runtime:

- `core/systems/world/chunk_view.gd`
- `core/systems/world/chunk_debug_visual_layer.gd` or equivalent
- `core/systems/world/world_streamer.gd`
- `core/systems/world/world_tile_set_factory.gd` only if mountain tile
  presentation needs neutralization
- `assets/shaders/*mountain*`
- `assets/textures/terrain/mountains/*`
- `gdextension/src/mountain_contour.*` or equivalent native helper

Generator, if needed:

- `tools/rimworld-autotile-lab/desktop_app`

Docs, if boundaries change:

- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/world/terrain_hybrid_presentation.md`

## Forbidden Files / Boundaries

- no save/load code
- no `WorldDiffStore` ownership changes
- no `WORLD_VERSION` bump
- no worldgen classification changes
- no building/power/room/combat changes
- no player movement or collision code except debug reads needed to inspect
  current mismatch
- no `F8` input binding

## Implementation Steps

1. Confirm L1 debug views still work: `F6`, `F7`, `F10`.
2. Add preloaded/imported prototype mountain material assets.
3. Add a chunk-owned contour mountain presentation layer.
4. Render the mountain top fill from L1 contour geometry.
5. Add rim/facade/shadow zones using either authored textures or simple shader
   zones.
6. Suppress the old square mountain edge in normal view without deleting
   gameplay terrain truth.
7. Wire local dirty refresh after the existing mining mutation path.
8. Add smoke tests/static checks for no save changes, no `WORLD_VERSION` bump,
   no `F8`, and no per-tile render nodes.

## Smoke Tests

- With debug off, a mountain edge no longer reads primarily as square `64 px`
  stair steps.
- `F6`, `F7`, and `F10` still work on top of the L2 presentation.
- `F10` can explain where the visual contour came from.
- The existing harvest/mining path still works.
- Save/load payload shapes remain unchanged.
- `WORLD_VERSION` remains unchanged.
- No `F8` binding appears.
- Dense loaded mountain chunks do not create per-tile render nodes.
- One mined tile marks only local visual dirty units.

## Definition of Done

- L2 produces an obvious visual improvement over square mountain tiles in normal
  play.
- The visual source is the L1 contour, not a second generator-defined gameplay
  shape.
- Generator changes, if any, are offline authoring only.
- Gameplay truth, save/load, mining, and collision remain unchanged until L3.
- Debug keys stay stable: `F6`, `F7`, `F10`, never `F8`.

## Manual Human Verification Required

Run the game and inspect one mountain edge:

1. Debug off: check that the mountain looks contour-driven, not square-tile
   driven.
2. `F6`: confirm the tile grid can still explain the underlying cells.
3. `F7`: confirm the solid mask still matches gameplay solid tiles.
4. `F10`: confirm the contour debug aligns with the visible L2 edge.
5. Mine one exposed mountain tile and confirm the visual refresh is local.

## Required Updates When Implementing

- Update `packet_schemas.md` if visual streams cross the native/script packet
  boundary.
- Update `terrain_hybrid_presentation.md` if L2 introduces reusable
  presentation resources such as `MountainShapeSet` or a new shader family.
- Update generator README/review notes if the desktop generator gains a new
  export path.

