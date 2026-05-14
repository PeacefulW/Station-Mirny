---
title: ADR-0008 Generator-Authored Contour Mesh Runtime
doc_type: adr
status: draft
owner: engineering+art
source_of_truth: false
version: 0.1
last_updated: 2026-05-13
related_docs:
  - ../02_system_specs/world/mountain_contour_runtime_v2_design_brief.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../02_system_specs/world/terrain_hybrid_presentation.md
  - ../02_system_specs/world/world_runtime.md
  - ../02_system_specs/world/mountain_generation.md
  - ../02_system_specs/world/lake_generation.md
  - 0001-runtime-work-and-dirty-update-foundation.md
  - 0003-immutable-base-plus-runtime-diff.md
---

# ADR-0008 Generator-Authored Contour Mesh Runtime

## Context

The current world runtime is logically tile-based: one world tile is `64 px`, one chunk is `16 x 16` tiles, and chunk packet arrays contain `256` entries. World generation, save/load, mining, and runtime diffs are already built around this contract.

The terrain generator (`Cliff Forge`, under `tools/rimworld-autotile-lab/desktop_app`) can author a much richer terrain look than the in-game square TileMap path: organic contour edges, top material, face material, rim/lip, bottom outline, albedo, height, normals, modulation, and dynamic-lighting-ready normal maps. The generator preview is the desired authoring target because art iteration must stay data-driven: change the generator controls, export, and see the new terrain style in game without rewriting runtime code for ordinary style changes.

A previous full transfer attempt (`perenos v.1`) used a runtime SDF texture pipeline. It tried to generate or refresh per-chunk mask, height, normal, and collision data at runtime. That approach caused loading and mining latency, stale contour readiness, and visual mismatch with the generator preview. It also mixed too many concerns at once: parity with the generator, rendering cutover, streaming, collision, and mining dirty updates.

The current F10 mountain contour path is fast because it builds a small native marching-squares mesh from effective mountain solidity and a one-tile halo. However, the current F10 result is debug-only: it is not terrain truth, not collision, not walkability, and not save data. It also returns only simple vertices and indices, so it cannot by itself carry the full generator-authored style.

The project needs a runtime terrain presentation path that satisfies all of these constraints:

- terrain must not visibly render as square cells;
- mountain terrain must look maximally close to the generator preview;
- top, face, rim, bottom outline, high-resolution albedo, and normals are required;
- dynamic lighting must use top and face normal maps plus shape normals;
- mining one logical tile must update the visible contour and collision immediately, with an absolute interactive ceiling of `100 ms` and a target below one or two frames;
- movement, NPCs, and building placement must use the same contour collision shape, not square `walkable_flags` near contour terrain;
- no hidden square fallback is allowed for visual or collision behavior;
- save format, logical tile size, and chunk size must not change.

## Decision

Adopt a **Generator-Authored Contour Mesh Runtime** for terrain presentation and contour collision.

The runtime will not ask the generator, Godot, or native code to redraw full chunk images after mining. Instead:

1. The world remains logically tile-based.
2. The authoritative gameplay state remains `immutable base + runtime diff`.
3. Native code derives a small production contour result from the effective tile state plus halo.
4. Godot renders that contour result as mesh geometry rather than square TileMap cells.
5. A shader applies the generator-authored style to the runtime contour mesh.
6. Movement, NPCs, and building placement query a collision cache derived from the same contour result.

The accepted runtime flow is:

```text
base terrain + runtime diff
        ↓
effective chunk terrain + one-tile or bounded halo
        ↓
native production contour builder
        ↓
ContourChunkRuntimeResult
        ↓
1) top / face / rim / bottom-outline visual mesh
2) collision footprint loops / capsule query cache
3) edge metadata for shader sampling and parity tests
```

The generator owns **appearance**. The runtime owns **topology and collision**.

The generator must export a lightweight contour style package, not a runtime chunk image. The first style package is expected to include:

```text
<asset>_contour_style.v1.json
<asset>_top_albedo.png
<asset>_face_albedo.png
<asset>_base_albedo.png
<asset>_top_normal.png
<asset>_face_normal.png
<asset>_top_modulation.png
<asset>_face_modulation.png
<asset>_edge_profile_lut.png
<asset>_height_profile_lut.png
<asset>_reference_preview.png
<asset>_reference_normal.png
```

The style JSON must carry the generator-authored controls needed by the runtime shader and contour builder, including but not limited to:

```text
tile_size_px
south_height_px
north_height_px
side_height_px
corner_round_px
diagonal_smooth_px
contour_warp_px
roughness
rim_width
edge_debris
edge_color_strength
mountain_outline_enabled
mountain_outline_width
normal_strength
normal_detail_strength
top_world_scale_px
face_world_scale_px
macro_world_scale_px
texture_scale
colors
seed
```

Ordinary art iteration must be possible by changing generator settings and re-exporting the style package. Runtime code changes are required only when the generator introduces a new effect that is not represented by the existing style contract or shader contract.

## Runtime Ownership Rules

### Logical terrain truth

Logical terrain truth remains tile-based.

Rules:

- Mining still mutates one logical tile through the runtime diff store.
- Save files continue to store diffs, not contour meshes, collision loops, SDF buffers, or generated images.
- Base terrain remains reconstructible from seed/settings.
- Contour visual and contour collision are derived transient caches.
- No contour runtime field may be persisted into chunk diff JSON.

### Visual terrain truth

For contour-enabled terrain classes, visual truth is the contour mesh plus generator-authored style.

Rules:

- Mountain wall and mountain foot must not render through square TileMap cells once the contour runtime is enabled for them.
- The contour runtime must render top, face, rim, and bottom outline from one coherent contour result.
- The mountain bottom outline is bottom/contact-only, not a full outline around the entire contour.
- Facade presentation follows the generator-authored perspective rules, including front/downward face behavior.
- Top and face material sampling uses world-space and/or face-space UVs defined by the style contract.
- Shape normals must be combined with generator-exported top and face material normals for dynamic lighting.

### Collision truth

For contour-enabled terrain classes, collision truth is the collision footprint derived from the same contour result that drives the visible mesh.

Rules:

- Player movement must query contour collision, not square `walkable_flags`, near contour terrain.
- NPC movement must use the same contour collision path.
- Building placement must query contour collision/footprint, so diagonal placement along contour walls can be valid when the shape fits.
- Collision must align to the visible lower/contact boundary of the cliff/facade footprint, not just the original logical tile edge.
- If a required contour collision cache is missing, the area is treated as not ready / blocked. There is no square fallback.

### Mining updates

Mining one terrain tile must trigger a local contour rebuild.

Rules:

- The dirty unit is the changed tile's chunk plus seam-neighbor chunks only when the changed tile can affect a seam.
- Rebuilds must update visual mesh and collision cache together.
- A mined tile must not disappear logically while the old visual/collision contour remains stale for visible gameplay.
- The runtime target is same-frame or next-frame update; the hard ceiling for ordinary mining feedback is `100 ms`.
- Batch-only delayed mining updates are not acceptable for the tile disappearance event.

## Rejected Alternatives

### 1. Return to the full RuntimeSdfContour texture pipeline

Rejected.

Reason:

- It recreates large per-chunk mask, height, normal, and collision buffers.
- It risks main-thread texture creation/update during interactive mining.
- It previously caused loading and mining latency.
- It can make movement and mining wait on asynchronous contour readiness.
- It mixes visual parity, streaming, collision, and mining updates into one heavy cutover.

Runtime SDF-style data may still exist inside the generator for authoring and preview. It must not be the interactive in-game dirty-update mechanism for mined terrain.

### 2. Use the current F10 debug contour directly as final terrain

Rejected as-is.

Reason:

- The current F10 helper returns only a debug mesh.
- It does not carry top/face/rim/outline mesh separation.
- It does not carry edge metadata needed for generator-style shader sampling.
- It is explicitly documented as not being terrain, walkability, collision, or save data.

Accepted replacement:

- Promote the idea behind F10 into a production native contour builder.
- Keep the cheap halo/marching-squares/local rebuild model.
- Extend the output contract for visual presentation and collision.

### 3. Keep square TileMap terrain and improve only the atlas art

Rejected.

Reason:

- Square cells would remain visible in silhouettes, collision, mining holes, and shorelines.
- Collision would still be tied to `walkable_flags` instead of the visible contour.
- It cannot satisfy diagonal wall movement/building placement goals.

TileMap may remain for non-contour terrain during transition, but contour-enabled terrain must move to contour mesh presentation.

### 4. Render exported generator preview images directly in chunks

Rejected.

Reason:

- Static preview images do not update cheaply after mining.
- Runtime mining would require regenerating or patching large images.
- Seam parity and dynamic changes become expensive and fragile.
- Collision still needs separate derived geometry.

The generator exports style, not chunk pictures.

### 5. Use square walkability as hidden collision fallback

Rejected.

Reason:

- It creates invisible walls and visible/passable mismatch.
- It violates the requirement that collision follows the visible contour.
- It would hide cache readiness bugs instead of exposing them.

If contour collision is required and missing, the affected area is not ready / blocked.

### 6. Spawn many scene-tree `CollisionPolygon2D` nodes as the primary collision model

Rejected as the default implementation.

Reason:

- Recreating many scene-tree physics nodes during mining risks main-thread spikes.
- The collision model needs fast capsule and building-footprint queries, not only Godot physics callbacks.
- A data cache is easier to validate against the visual contour result.

A bounded debug or editor-only physics visualization is acceptable. The primary runtime collision path is a data-oriented contour collision cache.

## Consequences

### Positive consequences

- Mining updates change small mesh/collision caches instead of large runtime textures.
- The generator remains the authoring source for terrain appearance.
- Dynamic lighting can use generator-exported top and face normals.
- Visual terrain and collision terrain share one derived contour result.
- Diagonal movement and diagonal building placement along walls become possible.
- The save format and logical world contract remain stable.
- The failed `perenos v.1` path is explicitly avoided.

### Negative consequences / costs

- The runtime needs a new production contour result contract, not just the existing debug F10 output.
- Generator preview and runtime shader must share a strict style contract to maintain visual parity.
- Any new generator effect that changes the rendering model may require adding a field or shader branch to the runtime style contract.
- Visual parity testing becomes mandatory; subjective "looks close enough" is not a sufficient acceptance gate.
- Contour collision must be implemented and tested before mountain visual cutover is accepted.

### Compatibility consequences

- `ChunkPacketV1` does not gain contour fields.
- `ChunkDiffFile` does not gain contour fields.
- Logical tile size remains `64 px`.
- Chunk size remains `16 x 16`.
- World save/load continues to use base regeneration plus runtime diffs.
- Existing generator runtime SDF exports may continue to exist for parity/debug, but they are not the in-game dirty-update rendering path.

## Required Follow-Up Specs

This ADR approves the architectural direction only. It must be followed by concrete specs before implementation cutover:

1. **Contour Style Export Spec**
   - exact JSON schema;
   - required PNG assets;
   - versioning rules;
   - validation rules;
   - backward/forward compatibility policy.

2. **Contour Runtime Result Spec**
   - native input contract;
   - output arrays;
   - mesh surfaces;
   - edge metadata;
   - seam behavior;
   - debug stats;
   - performance limits.

3. **Contour Collision Spec**
   - footprint definition;
   - capsule movement query;
   - NPC query;
   - building footprint query;
   - missing-cache policy;
   - seam ownership.

4. **Generator/Runtime Parity Test Spec**
   - canonical masks;
   - reference images;
   - albedo comparison;
   - normal comparison;
   - silhouette comparison;
   - allowed diff thresholds.

5. **Implementation Plan**
   - mountains first;
   - visual and collision together;
   - mining stress tests;
   - NPC/building adoption;
   - later extension to ground, dug ground, lake bed, and shoreline.

## Acceptance Gates

This ADR is considered satisfied only when the first mountain contour runtime cutover passes these gates:

- mountain wall/foot no longer render as square TileMap cells;
- generator-exported style controls top, face, rim, bottom outline, albedo, modulation, and normals;
- Godot runtime render matches generator reference preview within documented thresholds;
- normal output matches generator reference normal within documented thresholds;
- mining one mountain tile updates visual mesh and collision cache within `100 ms`, with target below `33 ms`;
- seam mining does not create cracks, overlaps, stale collision, or stale visual contours;
- player capsule slides along contour collision rather than square tile edges;
- NPCs use the same contour collision path;
- building placement uses contour footprint checks rather than square blocked cells near contour terrain;
- no square visual fallback is present for contour-enabled mountain terrain;
- no square collision fallback is present for contour-enabled mountain terrain;
- no per-mining runtime mask/height/normal `ImageTexture` rebuild is present;
- save/load format remains unchanged.

## Implementation Status

Draft. No code is approved by this ADR until the follow-up specs and implementation plan are written and accepted.

The intended first implementation scope is mountain terrain only:

```text
TERRAIN_MOUNTAIN_WALL
TERRAIN_MOUNTAIN_FOOT
```

Ground, dug ground, lake bed, and shorelines should adopt the same architecture later, after the mountain visual/collision/mining path is proven.

## Status Rationale

This ADR is a draft because it records the selected architectural direction after the failed full RuntimeSdfContour transfer and before the concrete contour style, runtime result, collision, and parity specs are written.

It should become approved only after the owner accepts the non-negotiable constraints:

- generator-authored appearance;
- runtime mesh/collision derivation;
- no interactive SDF texture rebuilds;
- no square fallback for contour-enabled terrain;
- no save or logical grid changes;
- mountains first, with visual and collision shipped together.
