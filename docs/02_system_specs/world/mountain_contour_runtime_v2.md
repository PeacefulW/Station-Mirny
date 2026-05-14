---
title: Mountain Contour Runtime V2
doc_type: system_spec
status: draft
owner: engineering+art
source_of_truth: false
version: 0.1
last_updated: 2026-05-13
related_docs:
  - ../../05_adrs/0008-generator-authored-contour-mesh-runtime.md
  - mountain_contour_runtime_v2_design_brief.md
  - terrain_hybrid_presentation.md
  - mountain_generation.md
  - lake_generation.md
  - ../meta/packet_schemas.md
  - ../meta/system_api.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
---

# Mountain Contour Runtime V2

## Purpose

Define the target architecture for rendering, colliding with, and mining
mountains as continuous generator-authored contour terrain rather than visible
64 px square cells.

This spec exists because the previous runtime SDF transfer approach attempted
to rebuild per-chunk mask/height/normal/collision textures in game runtime and
caused unacceptable chunk-load and excavation latency. The target approach keeps
the game world logically tile-based, but derives a fast contour mesh and contour
collision cache from the same effective tile state used by mining.

The generator remains the authoring source for mountain appearance. The game
runtime remains the owner of fast derived topology, collision, and dirty updates.

## Gameplay Goal

Mountains must look and feel like high natural cliff mass in cross-section:

- no visible square mountain cells;
- top plateau, vertical/front facade, rim/kromka, bottom-only outline, organic
  edge folds, high-resolution top and face materials;
- dynamic-lighting-ready normals for top, face, rim, and facade shape response;
- collision follows the same visible contour footprint, including the bottom
  visible line of the facade;
- mining one logical tile updates visual mesh and collision immediately enough
  to feel synchronous in play;
- generator preview remains the visual target, so changing rim width, outline,
  texture colour, normal maps, facade height, and similar authoring settings in
  the generator can be exported and reflected in game without gameplay-code
  rewrites.

## Scope

This spec covers the first production wave for **mountains only**:

- mountain wall / mountain foot visual replacement;
- generator-authored mountain contour style export;
- native contour mesh build from effective mountain solid state;
- mountain contour shader and material binding;
- contour collision query for player, NPC, and future placement checks;
- mining dirty updates for visual and collision;
- seam and parity validation against generator reference output.

## Out of Scope

The first wave does **not** implement:

- plains ground contour presentation;
- dug-ground contour presentation;
- lake-bed contour presentation;
- river/lake shoreline contour banks;
- multi-biome mountain material switching by rock ore/composition;
- procedural whole-world SDF baking;
- save format changes;
- logical tile size or chunk size changes;
- a full replacement of the terrain hybrid presentation system for every
  terrain class.

Ground, dug ground, and water banks should later use the same architectural
language, but they are not acceptance blockers for the mountain-only cutover.

## Current Baseline

The current world contract is still tile/chunk based:

- one logical tile is `64 px`;
- one chunk is `16 x 16` tiles;
- one chunk packet contains `256` entries;
- terrain truth is represented by arrays such as `terrain_ids`,
  `walkable_flags`, `lake_flags`, `mountain_id_per_tile`, and
  `mountain_flags`.

Current F10 mountain contour debug is useful proof of fast topology, but it is
not production terrain. It returns only debug vertices/indices and is documented
as not being authoritative terrain, walkability, collision, navigation, or save
data.

Current movement checks still use tile-derived walkability. Mountain Contour
Runtime V2 must replace that for contour-owned mountain terrain.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Canonical world data remains `base + runtime diff` tile state. Mountain contour visual and collision are derived runtime caches from that state. |
| Save/load required? | No new save fields. Save files continue to store only authoritative diffs such as terrain id and walkability. |
| Deterministic? | Yes. Same seed, same diffs, same style package, and same world settings produce the same contour visual/collision. |
| Must it work on unloaded chunks? | Queries into unloaded or unbuilt contour chunks are blocked/not walkable. No square fallback is allowed. |
| C++ compute or main-thread apply? | Native/GDExtension builds contour mesh and collision loops. GDScript applies bounded mesh/material updates. Shader renders pixels and normals. |
| Dirty unit | Changed logical tile plus exact seam/overhang-neighbour chunks required by halo and facade ownership. Blind 3x3 refresh is forbidden for ordinary mining. |
| Single owner | World tile state owns truth. Native contour builder owns contour topology. Generator style package owns presentation parameters. Contour collision cache owns movement/building queries. |
| 10x / 100x scale path | Runtime cost scales with contour edge complexity, not chunk pixel count. No per-chunk SDF image rebuilds. |
| Main-thread blocking risk | Mesh/collision apply must be tightly local and measured. Large ImageTexture creation on mining is forbidden. |
| Hidden fallback? | Forbidden. No visual fallback to square mountain TileMap cells and no collision fallback to square walkable flags for contour-owned mountain terrain. |
| Could it become heavy later? | Yes, if visual style is implemented as runtime textures. Therefore the accepted path is mesh + shader + pre-exported material/normal textures. |
| Whole-world prepass or local compute only? | Local compute only. No whole-world presentation bake at startup. |

## Design Principles

### 1. Keep tile truth, replace mountain presentation and collision

Mining, save/load, chunk diffs, and world generation remain tile-based. A mined
mountain tile still becomes an authoritative terrain override such as
`TERRAIN_PLAINS_DUG`.

The player does not see or collide with square mountain cells. The visible
mountain and its blocking footprint are derived from the effective mountain mask
inside loaded chunks plus halo.

### 2. Generator owns style, game owns topology

The generator exports a contour style package. The game does not hardcode the
final artistic values of rim, outline, facade height, colours, material scale,
or normals.

The game builds runtime contour topology from live world state and binds the
exported style to that topology.

### 3. No runtime SDF texture rebuild on mining

Mining must not create per-chunk `mask`, `height`, `normal`, or
`collision_sdf` textures. Mining updates a small derived mesh/collision cache.

Runtime may use small pre-exported LUT/profile textures from the generator, but
those textures are loaded as assets and are not regenerated per chunk during
play.

### 4. Visual and collision are siblings

The same contour result drives:

1. top/facade/rim/outline visual mesh;
2. collision footprint loops;
3. debug/parity state.

Collision is not sampled from a rendered image, and visual mesh does not diverge
from collision topology.

### 5. No stale readiness after mining

After a tile is mined, the visible mountain and contour collision must update in
the same interactive response window. A chunk must not remain visibly stale while
an async contour worker catches up.

If a contour cache is missing for an area, movement/building queries are blocked
there until the cache exists.

### 6. Preview parity is a required product feature

Generator preview is not merely inspiration. It is the visual target. The game
runtime must have parity tests against generator reference output for fixed
masks and fixed style packages.

## Core Terms

### `effective tile state`

The authoritative terrain state after applying runtime diff to generated base
packet data.

### `mountain solid mask`

A compact boolean mask where `1` means the effective tile is a solid mountain
participant for contour topology. The first wave includes mountain wall and
mountain foot tiles that are not walkable and belong to a valid mountain id.

### `solid halo`

The mountain solid mask for the local chunk plus at least one tile of neighbour
context. The current debug path uses `(chunk_size + 2)^2`; the production path
may use a larger radius only if the style contract proves it is necessary.

### `contour style package`

The generator-authored JSON + PNG package consumed by the runtime contour
shader and validator.

### `top contour`

The continuous top plateau polygon of the mountain mass.

### `facade`

The front/down-facing cliff wall extruded from visible contour edges according
to the generator-authored style.

### `rim`

The visual upper edge band of the mountain, controlled by generator-exported
style parameters and textures.

### `bottom outline`

The dark contact line drawn only where the mountain facade meets the visible
ground below. It is not a full outline around the whole mountain.

### `bottom visible line`

The visible lower boundary of the facade/outline. This line participates in the
collision footprint. The player should not walk through the visible mountain
facade.

### `collision footprint`

The blocked 2D polygon/loops derived from the top contour plus facade extrusion
down to the bottom visible line.

### `contour revision`

A monotonically increasing transient revision for a chunk's derived contour
cache. It is not save data.

## Generator Export Contract

### Export mode

Add a lightweight export mode:

```text
MountainContourStyleV1
```

This mode exports a style package for runtime contour mesh rendering. It does
not export a per-chunk runtime SDF field and does not require the game to
regenerate chunk images.

### Required files

For asset name `mountain`, the export package should contain:

```text
mountain_contour_style.v1.json
mountain_top_albedo.png
mountain_face_albedo.png
mountain_base_albedo.png
mountain_top_modulation.png
mountain_face_modulation.png
mountain_top_normal.png
mountain_face_normal.png
mountain_edge_profile_lut.png        # optional in v1 if shader can compute profile analytically
mountain_height_profile_lut.png      # optional in v1 if shader can compute profile analytically
mountain_reference_preview.png
mountain_reference_normal.png
mountain_reference_mask.png
```

The reference images are for parity/debug tests. They are not runtime chunk
textures.

### JSON shape

```text
MountainContourStyleV1 {
  "schema_id": "mountain_contour_style.v1",
  "asset_name": String,
  "preset_id": String,
  "tile_size_px": int,
  "authoring_tile_size_px": int,
  "version": int,

  "textures": {
    "top_albedo": String,
    "face_albedo": String,
    "base_albedo": String,
    "top_modulation": String,
    "face_modulation": String,
    "top_normal": String,
    "face_normal": String,
    "edge_profile_lut"?: String,
    "height_profile_lut"?: String
  },

  "geometry": {
    "south_height_px": float,
    "north_height_px": float,
    "side_height_px": float,
    "corner_round_px": float,
    "diagonal_smooth_px": float,
    "contour_warp_px": float,
    "corner_variation": float,
    "rim_width_px": float,
    "edge_debris": float,
    "edge_color_strength": float,
    "mountain_outline_enabled": bool,
    "mountain_outline_width_px": float
  },

  "material_sampling": {
    "top_world_scale_px": float,
    "face_world_scale_px": float,
    "macro_world_scale_px": float,
    "modulation_strength": float,
    "modulation_contrast": float,
    "texture_scale": float
  },

  "lighting": {
    "normal_strength": float,
    "normal_detail_strength": float,
    "bake_height_shading": bool
  },

  "colors": {
    "top": String,
    "face": String,
    "edge": String,
    "back": String,
    "base": String
  },

  "noise": {
    "seed": int,
    "roughness": float,
    "geometry_variance": float
  },

  "reference": {
    "mask": String,
    "preview": String,
    "normal": String
  }
}
```

### Export invariants

- `tile_size_px` must match the game logical tile size for this wave: `64`.
- `authoring_tile_size_px` may be higher if the generator internally authored
  at high resolution, but exported runtime sampling must be defined in game
  pixels.
- Texture paths must be relative to the exported package or Godot `res://` after
  installation.
- The style package must include enough data for the runtime shader to reproduce
  top, face, rim, bottom outline, and normals without per-chunk image generation.
- Runtime must fail validation on missing required textures. It must not fall
  back to anonymous/legacy recipes.

## Runtime Style Resource Contract

Godot should load the generator package into a runtime resource or immutable
configuration object:

```text
MountainContourStyleResource {
  id: StringName,
  schema_id: StringName,
  tile_size_px: int,
  geometry_params: PackedFloat32Array,
  sampling_params: Dictionary,
  color_params: Dictionary,
  top_albedo: Texture2D,
  face_albedo: Texture2D,
  base_albedo: Texture2D,
  top_modulation: Texture2D,
  face_modulation: Texture2D,
  top_normal: Texture2D,
  face_normal: Texture2D,
  edge_profile_lut?: Texture2D,
  height_profile_lut?: Texture2D
}
```

Validation must happen before any chunk publication or mining path can use the
style.

Failure policy:

- invalid style package = startup/dev validation failure;
- missing style for mountain contour runtime = no cutover;
- no silent fallback to `unnamed_recipe.json`, legacy Full47, or square TileMap
  presentation.

## Native Runtime Contour Contract

### Entry point

Add a production native helper distinct from the current debug helper:

```text
WorldCore.build_mountain_contour_runtime(
  solid_halo: PackedByteArray,
  chunk_size: int,
  tile_size_px: int,
  contour_params: PackedFloat32Array,
  revision: int
) -> Dictionary
```

`contour_params` is derived from `MountainContourStyleResource.geometry_params`.
Texture/material values are not passed to native.

### Input invariants

- `solid_halo` must represent effective mountain solid state after runtime diff.
- `solid_halo` must include neighbour data needed for seam-stable contour
  construction.
- `chunk_size` must be `16` for current world version.
- `tile_size_px` must be `64` for current world version.
- The helper must not read global world state, texture files, or Godot scene
  nodes.

### Output shape

```text
MountainContourRuntimeResultV1 {
  "schema_id": "mountain_contour_runtime_result.v1",
  "revision": int,
  "chunk_size": int,
  "tile_size_px": int,
  "halo_side": int,
  "solid_sample_count": int,

  "top_vertices": PackedVector2Array,
  "top_indices": PackedInt32Array,
  "top_custom0": PackedFloat32Array,

  "face_vertices": PackedVector2Array,
  "face_indices": PackedInt32Array,
  "face_custom0": PackedFloat32Array,

  "rim_vertices": PackedVector2Array,
  "rim_indices": PackedInt32Array,
  "rim_custom0": PackedFloat32Array,

  "outline_vertices": PackedVector2Array,
  "outline_indices": PackedInt32Array,
  "outline_custom0": PackedFloat32Array,

  "collision_loops": Array[PackedVector2Array],
  "collision_aabbs": Array[Rect2],

  "seam_keys": Dictionary,
  "stats": Dictionary
}
```

All vertices are in local chunk pixel coordinates. Visual vertices may extend
outside the local chunk rectangle when the owning contour edge has a facade that
overdraws into a neighbour chunk. This is allowed only by the deterministic
ownership rules below.

### Mesh ownership rules

- A facade/outline segment is owned by the chunk containing the solid mountain
  tile or contour edge that generated it.
- A chunk may draw facade geometry outside its local `0..chunk_px` rectangle by
  at most the style's maximum facade/outline overhang.
- Neighbour chunks must not duplicate the same facade segment.
- Seam ownership must be deterministic from tile coordinates and not from chunk
  load order.
- When mining affects a seam-owned segment, the dirty resolver must rebuild all
  chunks that can own or collide with the changed segment.

### Required topology features

The production builder must support:

- filled top surfaces;
- smooth/rounded contour corners according to style parameters;
- diagonal smoothing according to style parameters;
- facade strips along visible front/down and diagonal edges according to the
  same visual rules used by generator reference output;
- bottom-only outline geometry;
- collision loops matching the blocked visual footprint;
- inner holes caused by mining/caves;
- seam-stable output with halo context.

## Shader Contract

The runtime shader must render mountain contour meshes using generator-exported
textures and parameters.

Required inputs:

- world position;
- local contour attributes from `*_custom0` arrays;
- zone/kind: top, face, rim, outline;
- edge/facade depth or equivalent scalar;
- material textures: top/face albedo, modulation, normal;
- shape/profile LUTs if exported;
- style sampling params.

Required behaviour:

- top areas sample `top_albedo`, `top_modulation`, `top_normal`;
- facade areas sample `face_albedo`, `face_modulation`, `face_normal`;
- rim and bottom outline use style params, edge/profile data, and exported
  material maps;
- final normal blends material normal with contour/height/profile normal;
- dynamic lighting uses the final normal map response;
- no baked chunk lighting is required for normal operation;
- no per-chunk normal texture is generated on mining.

## Visual Layer Contract

Add a production layer under `ChunkView`, for example:

```text
MountainContourLayer
```

Responsibilities:

- own MeshInstance2D/ArrayMesh surfaces for top, face, rim, and outline;
- bind one `MountainContourStyleResource` and shared shader material(s);
- apply `MountainContourRuntimeResultV1` for the chunk;
- expose debug counters and parity hooks;
- update only changed chunk meshes on mining;
- avoid creating unique per-tile materials.

Forbidden:

- rendering mountain wall/foot through visible square TileMap cells after
  cutover;
- using current F10 debug layer as production rendering;
- drawing a cyan/debug contour as a gameplay layer;
- silently keeping old mountain TileMap cells visible under the contour layer.

## Collision Contract

Add a contour collision owner, for example:

```text
ContourCollisionWorld
```

Responsibilities:

- store chunk-local contour collision loops and AABBs;
- answer capsule/point/polygon queries in world coordinates;
- support player and NPC movement;
- support future building footprint checks;
- invalidate and rebuild exact dirty chunks on mining;
- block queries when required contour cache is missing.

### Movement query

Required public query shape:

```text
is_capsule_walkable_at_world(world_pos: Vector2, radius_px: float) -> bool
move_capsule_with_slide(start: Vector2, motion: Vector2, radius_px: float) -> Dictionary
```

The exact API names may differ, but the movement system must be able to query a
capsule, not only a point or tile coordinate.

### Collision source of truth

For contour-owned mountain terrain:

- blocked shape comes from `MountainContourRuntimeResultV1.collision_loops`;
- loops represent the visual mountain footprint down to the bottom visible line;
- square tile `walkable_flags` are not a movement fallback;
- unloaded or cache-missing contour chunks are treated as blocked/not walkable;
- NPC movement uses the same query as the player.

### Building placement

Future building placement near contour mountains must use the same contour
collision cache for footprint checks. It must not require walls to align only to
orth/south/east/west square tile edges if the visible mountain edge is diagonal
and the building footprint fits.

## Mining Dirty Update Contract

When mining removes one mountain tile:

1. Apply the authoritative tile override to runtime diff.
2. Update loaded packet arrays for the changed tile.
3. Resolve exact dirty contour chunks.
4. Rebuild `MountainContourRuntimeResultV1` for those chunks.
5. Apply updated visual mesh.
6. Apply updated collision cache.
7. Emit or update any existing mountain/mining events only after the derived
   visual/collision state is consistent enough for the next movement tick.

### Dirty resolver

The dirty resolver must not blindly rebuild 3x3 chunks for every mining action.

Expected dirty set:

- center chunk always;
- horizontal/vertical neighbour when the changed tile is within required halo
  radius of that seam;
- diagonal neighbour only when contour case ownership or smoothing radius can
  affect the diagonal seam;
- downward neighbour when facade/outline overhang from the changed edge can
  enter that chunk;
- any additional chunks only with a documented style parameter proving the need.

### Latency budget

Hard budget:

- mining visual + collision update must complete within `100 ms` for ordinary
  loaded-world mining cases.

Target budget:

- ordinary non-seam mining: `<= 16-33 ms`;
- seam/overhang mining: `<= 50 ms`;
- `100 ms` is a failure threshold, not the desired steady-state.

Forbidden:

- queuing a mining contour rebuild that leaves visible/collision state stale
  for later async completion;
- allowing movement through stale contour state after a tile was mined;
- hiding stale state with square fallback collision.

## Packet and Save Contract

No packet or save fields are added for Mountain Contour Runtime V2 first wave.

The existing `ChunkPacketV1` shape remains authoritative for terrain state:

- `terrain_ids`;
- `walkable_flags`;
- `mountain_id_per_tile`;
- `mountain_flags`;
- `mountain_atlas_indices` if still used by non-contour roof/legacy paths.

Chunk diff save files continue to persist only authoritative tile changes. The
contour result, style resource, mesh arrays, collision loops, and revisions are
transient derived runtime state and must not be written into save files.

If a later wave adds biome/ore-specific contour material selection that cannot
be derived from existing terrain/world data, `packet_schemas.md` must be updated
in the same task.

## Relationship to Existing Terrain Hybrid Presentation

The existing terrain hybrid presentation system remains valid for terrain
classes not yet cut over to contour runtime.

Mountain Contour Runtime V2 is a new derived visual+collision path for mountain
terrain. It does not replace the whole `TerrainPresentationRegistry` model in
one step.

Required interaction:

- contour style resources may reuse the same material texture concepts as
  `TerrainMaterialSet`;
- mountain wall/foot visible TileMap cells are disabled after mountain cutover;
- non-mountain terrain can continue through current TileMap/terrain presentation
  until later contour waves;
- `ChunkView` must have a clear owner boundary between legacy TileMap terrain
  layers and `MountainContourLayer`.

## Performance Contract

### Runtime forbidden operations on mining path

The following are forbidden in the mountain contour mining hot path:

- create a per-chunk mask image;
- create a per-chunk height image;
- create a per-chunk normal image;
- create a per-chunk collision SDF image;
- call `ImageTexture.create_from_image()` for contour result updates;
- rebuild all visible chunks;
- rebuild blind 3x3 chunks without exact dirty cause;
- instantiate per-tile materials;
- block on generator logic or external tools.

### Runtime expected operations on mining path

Allowed hot-path operations:

- mutate one tile override;
- rebuild a small native contour result for exact dirty chunks;
- replace/update chunk-local mesh arrays;
- update chunk-local collision loops/AABBs;
- update debug counters;
- sample already-loaded textures in shader.

### Scale target

The system must remain playable when the visible map area contains mostly or
entirely mountains. Cost must scale with changed contour boundaries and loaded
chunk count, not with per-pixel SDF buffers.

Target hardware for validation:

```text
GPU: GTX 1060 class
CPU: Ryzen 2600 class
Frame goal: stable 60 FPS, preferably 120 FPS where other systems allow it
```

## Parity and Validation Contract

### Generator parity cases

The generator must export reference images for fixed masks used by tests. The
first parity matrix must include:

- single solid tile;
- blob mountain;
- diagonal contact;
- narrow diagonal passage;
- concave notch;
- inner hole/cave;
- mined one-tile cut;
- chunk seam crossing;
- bottom-edge facade overhang.

### Godot render parity

A headless or scripted Godot render test must render the same masks with the
same style package and compare against generator reference output.

Required comparisons:

- silhouette/alpha difference;
- albedo difference;
- normal-map difference;
- bottom outline placement;
- seam pixels;
- absence of visible square cells.

Initial automated thresholds:

```text
silhouette_mismatch_ratio <= 0.005
mean_rgb_delta <= 0.02
p95_rgb_delta <= 0.08
normal_mean_angle_delta_deg <= 5.0
seam_gap_pixels == 0
```

Human visual review is still required for first approval, but automated parity
must exist so regressions are caught before gameplay testing.

### Collision tests

Required collision tests:

- capsule cannot enter visible mountain footprint;
- capsule slides along convex rounded contour;
- capsule slides along concave contour without jitter;
- diagonal visual passage is passable if capsule fits;
- diagonal visual passage is blocked if capsule does not fit;
- cache-missing query returns blocked/not walkable;
- player and NPC use the same contour query;
- building footprint near a diagonal wall uses contour collision, not square
  tile fallback.

### Mining tests

Required mining tests:

- mining one mountain tile changes visual mesh in the same test step;
- mining one mountain tile changes collision cache in the same test step;
- mining seam tile leaves no visual seam;
- mining seam tile leaves no collision seam;
- 100 sequential mining operations stay under the hard latency threshold;
- no old square mountain cells remain visible after cutover.

### Forbidden fallback tests

Add static or scripted tests proving:

- no `RuntimeSdfContour` cutover path is used for mountain contour mining;
- no contour mining path creates per-chunk mask/height/normal textures;
- no `ImageTexture.create_from_image()` is called by contour mining updates;
- `is_walkable_at_world` or its replacement does not fall back to square
  `walkable_flags` for contour-owned mountain terrain;
- square mountain TileMap cells are not visible after cutover.

## Implementation Iterations

### Iteration 0 — Land docs and decision records

Goal: ensure the architecture is documented before code work begins.

Files:

- `docs/02_system_specs/world/mountain_contour_runtime_v2_design_brief.md`
- `docs/05_adrs/0008-generator-authored-contour-mesh-runtime.md`
- `docs/02_system_specs/world/mountain_contour_runtime_v2.md`
- `docs/05_adrs/README.md`

Tasks:

- [ ] Land the design brief.
- [ ] Land ADR-0008 as draft or approved.
- [ ] Land this spec as draft.
- [ ] Add ADR-0008 to the ADR index.
- [ ] Confirm that implementation work does not begin from `perenos v.1`.

Acceptance:

- [ ] docs explicitly reject runtime per-chunk SDF texture rebuild on mining.
- [ ] docs explicitly reject square visual/collision fallback.
- [ ] docs keep save format and logical tile/chunk size unchanged.

### Iteration 1 — Generator `MountainContourStyleV1` export

Goal: add a lightweight generator export that captures the full mountain style
without asking the game to regenerate chunk images.

Files:

- `tools/rimworld-autotile-lab/desktop_app/core/src/model.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/render.rs`
- `tools/rimworld-autotile-lab/desktop_app/shell/app.py`
- `tools/rimworld-autotile-lab/desktop_app/shell/presets.py`
- generator tests under `tools/rimworld-autotile-lab/desktop_app/**/tests`

Tasks:

- [ ] Add export mode `MountainContourStyleV1`.
- [ ] Export `mountain_contour_style.v1.json`.
- [ ] Export required top/face/base albedo, modulation, and normal textures.
- [ ] Export optional edge/height profile LUTs if shader parity needs them.
- [ ] Export reference preview, normal, and mask images for parity tests.
- [ ] Include all geometry/material/lighting params from the current mountain
      preset that affect preview output.
- [ ] Validate export paths and `tile_size_px`.

Acceptance:

- [ ] Changing rim width in generator changes exported style data/reference.
- [ ] Changing bottom outline width changes exported style data/reference.
- [ ] Changing top/face texture or colour changes exported textures/reference.
- [ ] Export does not produce a required per-chunk runtime SDF texture package.

### Iteration 2 — Godot style loader and validator

Goal: load the exported style package in game without changing rendering yet.

Files:

- new `core/systems/world/mountain_contour_style.gd`
- new `core/systems/world/mountain_contour_style_registry.gd` or equivalent
- validation smoke test under `tools/`
- asset install paths under `assets/textures/terrain/mountains/**`

Tasks:

- [ ] Add a runtime resource/loader for `MountainContourStyleV1`.
- [ ] Load all required textures and params.
- [ ] Fail validation on missing texture, wrong schema id, wrong tile size, or
      missing geometry fields.
- [ ] Ensure no legacy `unnamed_recipe.json` is accepted as a contour style.
- [ ] Add debug summary for loaded style.

Acceptance:

- [ ] Headless validation passes for a valid exported package.
- [ ] Headless validation fails for missing `face_normal`.
- [ ] Headless validation fails for wrong `tile_size_px`.
- [ ] No gameplay chunk is published with an invalid mountain contour style.

### Iteration 3 — Native production contour result

Goal: add production contour topology output independent of F10 debug rendering.

Files:

- new `gdextension/src/mountain_contour_runtime.h`
- new `gdextension/src/mountain_contour_runtime.cpp`
- modify `gdextension/src/world_core.h`
- modify `gdextension/src/world_core.cpp`
- native/Godot smoke tests under `tools/`

Tasks:

- [ ] Add `WorldCore.build_mountain_contour_runtime(...)` binding.
- [ ] Build top mesh from solid halo.
- [ ] Build face/rim/bottom-outline mesh according to contour params.
- [ ] Build collision loops down to bottom visible line.
- [ ] Add seam ownership metadata.
- [ ] Add stats for vertex counts, edge counts, loops, and build time.
- [ ] Keep current `build_mountain_contour_debug(...)` only as debug helper or
      remove later after cutover.

Acceptance:

- [ ] Single-tile mountain result has top, face, outline, and collision loops.
- [ ] Blob result has continuous top mesh and closed collision footprint.
- [ ] Diagonal result does not incorrectly merge diagonal-only solid components.
- [ ] Native result does not allocate per-pixel chunk buffers.
- [ ] Production result shape is documented and tested separately from F10.

### Iteration 4 — MountainContourLayer visual prototype

Goal: render one loaded chunk through contour mesh and shader, side-by-side with
reference/debug, without enabling full gameplay cutover yet.

Files:

- new `core/systems/world/mountain_contour_layer.gd`
- new `assets/shaders/mountain_contour_runtime.gdshader`
- modify `core/systems/world/chunk_view.gd`
- modify `core/systems/world/world_streamer.gd` only for controlled prototype
  wiring
- render probe under `tools/`

Tasks:

- [ ] Add `MountainContourLayer` under `ChunkView`.
- [ ] Apply `MountainContourRuntimeResultV1` to ArrayMesh surfaces.
- [ ] Bind exported style textures to shader.
- [ ] Render top, face, rim, and bottom outline.
- [ ] Add debug toggle/report for contour render state.
- [ ] Keep old mountain TileMap visible only in explicit comparison/debug mode,
      not as hidden fallback.

Acceptance:

- [ ] One chunk renders mountain contour with no cyan debug layer.
- [ ] Shader uses exported top/face albedo and normals.
- [ ] Bottom outline appears only at bottom contact line.
- [ ] No per-chunk generated mask/height/normal textures are used.
- [ ] Initial visual comparison against generator reference is possible.

### Iteration 5 — Generator/Godot parity harness

Goal: prove that the runtime contour renderer matches generator preview for
fixed masks before gameplay cutover.

Files:

- generator reference case exports under
  `tools/rimworld-autotile-lab/desktop_app/exports/contour_parity_v1/**`
- new `tools/mountain_contour_parity_render_test.gd`
- optional comparison utility under `tools/`

Tasks:

- [ ] Export fixed parity masks and reference images from generator.
- [ ] Render the same masks in Godot using `MountainContourLayer`.
- [ ] Compare silhouette, albedo, normal, and seam pixels.
- [ ] Report image diff stats.
- [ ] Add failure thresholds from this spec.

Acceptance:

- [ ] Blob parity passes.
- [ ] Diagonal parity passes.
- [ ] Notch parity passes.
- [ ] Inner-hole parity passes.
- [ ] Seam parity passes.
- [ ] Normal-map parity passes within threshold.

### Iteration 6 — Contour collision cache and movement query

Goal: make collision follow the visible mountain footprint before mining cutover.

Files:

- new `core/systems/world/contour_collision_world.gd`
- modify `core/systems/world/world_streamer.gd`
- modify movement/authority systems that currently call square walkability
- collision tests under `tools/`

Tasks:

- [ ] Store collision loops from `MountainContourRuntimeResultV1`.
- [ ] Add capsule query.
- [ ] Add capsule slide or movement integration hook.
- [ ] Route player movement through contour query for mountain terrain.
- [ ] Route NPC movement through the same query, or add explicit integration
      task if NPC movement is not currently implemented.
- [ ] Treat missing contour cache as blocked.
- [ ] Add building-footprint query stub for future placement use.

Acceptance:

- [ ] Player cannot enter visible mountain footprint.
- [ ] Player slides along rounded mountain contour.
- [ ] Diagonal passage is passable when capsule fits.
- [ ] Diagonal passage is blocked when capsule does not fit.
- [ ] Missing cache blocks movement.
- [ ] No square `walkable_flags` fallback occurs for contour-owned mountains.

### Iteration 7 — Mining dirty update integration

Goal: mining a mountain tile updates visual contour and collision cache within
budget.

Files:

- modify `core/systems/world/world_streamer.gd`
- modify `core/systems/world/chunk_view.gd`
- modify/add `core/systems/world/contour_dirty_resolver.gd`
- mining regression tests under `tools/`

Tasks:

- [ ] Add exact dirty resolver for contour chunks.
- [ ] Rebuild contour result after mountain tile override.
- [ ] Apply visual mesh update in same mining response window.
- [ ] Apply collision cache update in same mining response window.
- [ ] Rebuild seam/overhang neighbours only when required.
- [ ] Add telemetry for mining contour update time.
- [ ] Prevent movement into stale/missing contour cache.

Acceptance:

- [ ] Mining one center tile updates visual/collision immediately.
- [ ] Mining one seam tile updates visual/collision with no seam gap.
- [ ] Mining 100 sequential tiles stays below hard latency threshold.
- [ ] No async stale period exists after mining.
- [ ] No blind 3x3 rebuild is used for ordinary mining.

### Iteration 8 — Mountain visual cutover

Goal: remove visible square mountain cells from normal gameplay.

Files:

- modify `core/systems/world/chunk_view.gd`
- modify `core/systems/world/world_tile_set_factory.gd` only if needed to avoid
  creating visible mountain sources for contour-owned terrain
- modify debug/probe tools

Tasks:

- [ ] Disable visible TileMap rendering for `TERRAIN_MOUNTAIN_WALL` and
      `TERRAIN_MOUNTAIN_FOOT` in normal gameplay.
- [ ] Keep logical packet terrain ids unchanged.
- [ ] Keep roof/cover systems compatible with contour visual ownership.
- [ ] Ensure `MountainContourLayer` owns normal mountain visuals.
- [ ] Ensure square mountain cells cannot appear under the contour layer.

Acceptance:

- [ ] No visible square mountain cells remain in gameplay.
- [ ] Mountain roof/cover debug still reports meaningful state.
- [ ] Save/load round trip does not persist contour runtime state.
- [ ] Mountain mining still works after cutover.

### Iteration 9 — Full mountain acceptance pass

Goal: prove the first production wave satisfies product requirements.

Files:

- combined validation runner under `tools/`
- performance reports under `artifacts/mountain_contour_runtime_v2/**`

Tasks:

- [ ] Run generator/Godot parity matrix.
- [ ] Run collision matrix.
- [ ] Run mining latency matrix.
- [ ] Run seam stress cases.
- [ ] Run loaded-area stress with mostly/all mountain chunks.
- [ ] Capture before/after screenshots for manual review.
- [ ] Run static forbidden-fallback checks.

Acceptance:

- [ ] Visual parity is accepted.
- [ ] Collision is accepted.
- [ ] Mining latency is accepted.
- [ ] No seams are accepted.
- [ ] No square fallback is detected.
- [ ] No save/packet format changes occurred.

### Iteration 10 — Future terrain contour expansion planning

Goal: prepare but not implement ground/dug/water-bank contour work.

Files:

- future design brief/spec updates only

Tasks:

- [ ] Record lessons from mountain cutover.
- [ ] Decide whether plains ground, dug ground, and shore banks use the same
      contour style package format or a generalized `TerrainContourStyleV1`.
- [ ] Decide how water surface and shoreline masks participate.
- [ ] Do not modify ground/water gameplay visuals in this iteration.

Acceptance:

- [ ] Future ground/water work has a separate approved brief/spec before code.

## First Playable Milestone

No partial implementation should be treated as gameplay-ready until all of the
following are true for mountains:

- generator style export exists;
- Godot style validation passes;
- production native contour result exists;
- visual contour layer renders top/face/rim/outline;
- collision cache blocks/slides by visible footprint;
- mining updates visual and collision within budget;
- square mountain TileMap cells are not visible;
- no collision fallback to square `walkable_flags` exists;
- parity and seam tests pass.

## Required Meta Doc Updates

Update these docs when this spec is approved or implementation changes their
boundary:

- `docs/05_adrs/README.md` — add ADR-0008;
- `docs/02_system_specs/meta/system_api.md` — only if new public methods become
  part of the confirmed API boundary;
- `docs/02_system_specs/meta/packet_schemas.md` — only if packet/result shapes
  become public confirmed contracts or if chunk packet/save shapes change;
- `docs/02_system_specs/world/terrain_hybrid_presentation.md` — clarify the
  relationship between legacy tile presentation and contour mesh presentation;
- `docs/02_system_specs/world/mountain_generation.md` — cross-link once mountain
  contour runtime becomes approved implementation target.

## Risks

### Preview mismatch risk

If generator and game use different contour math, the generator stops being a
trustworthy authoring tool. Mitigation: parity harness before cutover.

### Performance regression risk

If any implementation reintroduces per-chunk runtime images, mining and chunk
load will regress. Mitigation: forbidden-fallback static tests and telemetry.

### Collision/visual mismatch risk

If collision loops are generated separately from visual contour, the player may
hit invisible walls or walk through visible cliffs. Mitigation: collision loops
come from the same native result and are tested against visual footprint.

### Seam ownership risk

Facade overhang across chunk seams can double-render or gap if ownership is not
deterministic. Mitigation: explicit owner rules and seam parity cases.

### Scope creep risk

Ground, dug ground, water banks, ore-specific rock, and biome styles are all
important, but adding them before mountain acceptance will hide core failures.
Mitigation: mountain-only first wave.

## Open Questions

- Should `MountainContourStyleV1` later generalize into
  `TerrainContourStyleV1` for ground and banks?
- How much of generator preview logic should be shared as data/LUTs versus
  duplicated analytically in the Godot shader?
- Should the native contour builder own corner rounding fully, or should some
  apparent smoothing remain shader-side through edge-distance attributes?
- What exact building placement API will consume contour collision after the
  first mountain cutover?
- Should roof/cover use contour-specific masks or keep current mountain id / roof
  mask logic until a later cave/roof pass?

## Decision Summary

Mountain Contour Runtime V2 uses:

```text
effective tile state + diff
        ↓
solid halo
        ↓
native production contour result
        ↓
visual mesh + collision loops
        ↓
generator-authored shader style
```

It explicitly does **not** use:

```text
runtime per-chunk SDF image generation
square mountain TileMap visual fallback
square walkable_flags collision fallback
save/packet changes for visual style
logical tile/chunk size changes
```
