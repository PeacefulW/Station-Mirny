---
title: World Object Placement V0
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.7
last_updated: 2026-07-11
related_docs:
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../meta/modding_extension_contracts.md
  - ../meta/localization_pipeline.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - world_runtime.md
  - world_foundation_v1.md
  - ../../03_content_bible/resources/flora_and_resources.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# World Object Placement V0

## Purpose

Define the first scalable contract for generated surface world objects:
flora, trees, and inert decor.

Current implementation note (2026-07-09): `world_version == 63` keeps the
previous generated stone/rock object families removed (`object_kind` values
`1`, `5`, and `6`) and uses clustered replacement small rocks as visual-only
`object_kind == 7`. The replacement uses Blender-baked layered assets, snow
masks, anchored north-east-bake to south-east-runtime shadow rotation/stretch,
edge/rocky-patch placement bias, and close
intra-cluster spacing; it does not use wind masks, collision, harvest, ore, or
stone resource node data.

This spec exists so adding plants and authored objects does not become a set of ad-hoc
scene paths or generator branches. V0 is intentionally narrow: it proves the
data, asset, registry, packet, and presentation boundaries for one biome before
expanding to broader worldgen content.

## Gameplay Goal

The player should see the `plains` biome gain readable local identity through
small generated objects:

- alien flora that supports the content bible's non-Earth baseline;
- flora and trees that make the terrain feel tactile without adding
  gameplay-authored resource nodes yet;
- deterministic placement that is stable for the same seed and chunk;
- content that can later be extended by mods without rewriting core worldgen.

V0 does not need to make every object interactive. It should establish the
content and placement seam first.

## Scope

V0 includes only:

- surface layer only (`z = 0`);
- the `plains` biome only;
- generated world objects that are part of the immutable base placement result;
- registry-backed content definitions with namespaced IDs;
- a compact per-chunk object placement packet shape;
- batched or pooled presentation for visible objects;
- deterministic visual variation derived from seed, chunk, tile, and object ID;
- a narrow visual-only animated flora proof gated by chunk-local grass patches,
  using one fixed south/front-facing atlas row for presentation;
- a narrow visual-only static spiky flora proof restricted to chunk-local
  orange biofield patches, using a fixed front/top baked-shadow atlas frame;
- a narrow small static biofield flora proof restricted to chunk-local orange
  biofield patches, using spiky flora atlas index `1` and no collision;
- a tree proof using `object_kind == 4`, authored plains-tree placement
  settings, batched/layered presentation, sun silhouette shadows, and
  chunk-scoped trunk collision shape owners;
- a small rock proof using `object_kind == 7`, authored plains-small-rock
  placement settings, Blender-baked layered presentation, snow masks, and
  anchored bake-to-runtime south-east sun-shadow rotation/stretch with no
  collision or wind mask;
- no active historical generated stone/rock/ore object families `1`, `5`, or
  `6` in `world_version >= 61`;
- asset folder rules for sprites, atlases, and related presentation assets;
- mod-compatible additive content registration direction for `plains`.

## Out of Scope

V0 explicitly does not include:

- non-`plains` biome placement;
- full biome resolver work;
- biome blending;
- seasonal, weather, wind, or environment-runtime object changes;
- harvest, mining, chopping, pickup, or resource yield gameplay;
- object destruction runtime diff;
- generated stone/rock/ore collision, harvesting, resource nodes, and item
  yields; the active small rock proof is visual-only decor;
- harvesting, save identity, or gameplay commands for visual-only flora proofs;
- rotation variation for the visual-only animated flora proof;
- dedicated harvest commands or events;
- save migration for older `world_version` values;
- one `Node` per generated object;
- runtime synchronous asset loading;
- arbitrary mod scripting.

Harvesting and object mutation belong to a later iteration after the placement
packet and presentation seam are accepted.

## Related Documents

- `docs/00_governance/ENGINEERING_STANDARDS.md`
- `docs/02_system_specs/meta/modding_extension_contracts.md`
- `docs/02_system_specs/meta/localization_pipeline.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/02_system_specs/world/world_runtime.md`
- `docs/02_system_specs/world/world_foundation_v1.md`
- `docs/03_content_bible/resources/flora_and_resources.md`
- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- `docs/05_adrs/0003-immutable-base-plus-runtime-diff.md`
- `docs/05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md`

## Dependencies

V0 depends on:

- registry-first content access;
- stable namespaced content IDs;
- chunk packet generation through the native world boundary;
- `base + diff` world truth separation;
- no node-per-object presentation for mass flora, decor, and debris;
- preloaded or boot-prepared presentation assets.

## Data Model

### World Object Definition

Every generated object type must have a stable ID and data definition.

Direction:

```text
WorldObjectData
{
  id: StringName,                         # "core:sporestalk_small"
  category: StringName,                   # "flora", "resource_node", "decor"
  display_name_key: StringName,
  description_key: StringName,
  biome_tags: Array[StringName],          # V0 requires "plains"
  footprint_tiles: Vector2i,
  blocks_movement: bool,
  presentation_profile_id: StringName,
  placement_tags: Array[StringName],
}
```

Specialized resource types may extend this direction, but gameplay systems must
still consume them through registry lookup rather than hardcoded paths.

### Placement Set

`PlacementSetData` defines where a family of objects can appear.

Direction:

```text
PlacementSetData
{
  id: StringName,                         # "core:plains_surface_objects"
  biome_id: StringName,                   # V0: "core:plains"
  object_ids: Array[StringName],
  density: float,
  min_spacing_tiles: int,
  terrain_allow_tags: Array[StringName],
  terrain_deny_tags: Array[StringName],
  slope_or_ruggedness_range: Vector2,
  moisture_range: Vector2,
  deterministic_salt: int,
}
```

V0 placement sets are `plains`-only. Adding another biome requires a later spec
or an explicit update to this spec.

### Presentation Profile

Presentation data references already imported assets and atlas metadata.

Direction:

```text
WorldObjectPresentationData
{
  id: StringName,
  atlas_texture_path: String,
  atlas_region_count: int,
  normal_texture_path: String,
  shadow_profile_id: StringName,
  batch_material_id: StringName,
}
```

The asset path is presentation metadata, not gameplay identity.

## Asset Folder Contract

All world object sprites, atlases, normals, and related presentation assets must
live under `assets/sprites/` in domain-specific folders.

V0 folder direction:

```text
assets/sprites/flora/plains/
assets/sprites/flora/atlases/
assets/sprites/resources/plains/
assets/sprites/resources/atlases/
assets/sprites/decor/plains/
assets/sprites/decor/atlases/
```

Rules:

- flora sprites for the `plains` biome go under `assets/sprites/flora/plains/`;
- future resource-node sprites for `plains` go under
  `assets/sprites/resources/plains/` when that content is restored;
- inert visual decor goes under `assets/sprites/decor/plains/`;
- atlases are grouped by domain under the matching `atlases/` folder;
- normal maps, masks, or modulation maps stay next to the atlas they support
  and use the same basename with a suffix such as `_normal`, `_mask`, or
  `_modulation`;
- gameplay code must not treat a sprite path as canonical object identity;
- imported `.import` files are Godot import artifacts and should sit beside
  their source asset;
- generated or experimental art should not be promoted into these folders until
  the matching content definition is also present.

Example:

```text
assets/sprites/flora/plains/sporestalk_small_01.png
assets/sprites/flora/atlases/plains_flora_atlas.png
assets/sprites/flora/atlases/plains_flora_atlas_normal.png
assets/sprites/resources/plains/future_resource_node_01.png
assets/sprites/resources/atlases/plains_resource_nodes_atlas.png
```

The existing flat folders under `assets/sprites/flora/` and
`assets/sprites/resources/` may remain for legacy assets. New V0 world-object
assets should use the biome-scoped folders above.

## Runtime Architecture

### Generation

The placement solver produces a deterministic placement result from:

```text
world_seed
chunk_coord
world_version
worldgen_settings
biome_id
placement_set_id
registered object definitions
```

The solver may read deterministic world channels and terrain tags, but it must
not read scene tree state, player position, save state, or environment runtime
state.

Changing canonical placement output for the same seed and settings requires a
`world_version` bump.

Plains tree placement settings are authored in
`data/world_objects/placement_groups/plains_trees.tres`
(`PlainsTreePlacementSettings`) for new worlds, then frozen into
`worldgen_settings.plains_trees` and packed into native settings indices
`22..43`. Runtime object packets remain immutable generated output; changing the
checked-in `.tres` affects newly created worlds, not already saved worlds.

Plains small rock placement settings are authored in
`data/world_objects/placement_groups/plains_small_rocks.tres`
(`PlainsSmallRockPlacementSettings`) for new worlds, then frozen into
`worldgen_settings.plains_small_rocks` and packed into native settings indices
`44..70`. The active assets live under
`assets/sprites/decor/plains/layered_small_rocks/small_rock_01..10`.

### Packet Shape Direction

V0 extends `ChunkPacketV0` additively with a compact visual object section.
The accepted first packet shape is presentation-oriented and intentionally
byte-packed:

```text
object_kind: PackedByteArray          # current family id: 2 living flora, 3 spiky flora, 4 tree, 7 small rock
object_local_x_px_q4: PackedByteArray # chunk-local pixel X quantized to 4 px
object_local_y_px_q4: PackedByteArray # chunk-local pixel Y quantized to 4 px
object_size_px: PackedByteArray       # rendered sprite size in pixels
object_atlas_index: PackedByteArray   # prepared atlas bank index; spiky flora index 1 is small static brown seaweed; tree and small rock use index 0
object_variant: PackedByteArray       # atlas frame / animation view variant; small rock selects layered asset dir
object_flags: PackedByteArray         # bit flags reserved for object collision/proof data; active tree collision is derived from object_kind 4; small rock has none
object_tint: PackedByteArray          # 0..255 presentation tint scalar
object_phase: PackedByteArray         # 0..255 deterministic animation phase
```

All object arrays must have identical length. The packet is generated by
`WorldCore` alongside terrain data and is consumed by `WorldObjectPacketLayer`
inside `ChunkView`.

This V0 shape does not replace the long-term registry identity direction.
When gameplay object identity or modded object families become authoritative,
the registry must own the stable ID to numeric index mapping. The mapping must
be deterministic for the loaded content pack set and must not depend on random
file order.

### Presentation

`ChunkView` or a dedicated view helper may render generated objects, but it must
not own gameplay truth.

Rules:

- mass flora, trees, decor, and future debris use batched rendering or pooled
  lightweight presentation;
- V0 must not instantiate one node per generated object;
- assets must be preloaded or prepared outside interactive paths;
- presentation may choose deterministic atlas variants;
- presentation state is derived and not persisted.
- accepted V0 flora and trees consume native object packet arrays; local
  GDScript scatter helpers are legacy/reference only and not the production
  placement source.
- static biofield flora atlas bank index `0` is the orange spiky plant; index
  `1` is the small brown seaweed object and must pass the same deterministic
  orange biofield mask before emission.
- for `world_version >= 61`, native object packets do not emit historical
  stone/rock families (`object_kind` values `1`, `5`, and `6`).
- for `world_version >= 62`, native object packets may emit visual-only
  `object_kind == 7` small rocks from `worldgen_settings.plains_small_rocks`.
  Their layered runtime reuses the tree rule: clip/stretch on the authored
  north-east bake axis, then rotate around the anchor to runtime south-east,
  loads snow masks/overlays, and intentionally has no wind or collision path.
- for `world_version >= 63`, small rock placement is clustered: candidate
  centers are accepted by grass/soil edge score, rocky-patch score, and path-edge
  score, then emit several close visual rocks within an elliptical local scatter.
- living flora, spiky flora, and trees keep local clearance from canonical
  mountain wall/foot terrain so batched decor does not appear underneath the
  organic runtime mountain mask.
- trees use `object_kind == 4`; presentation may use the classic atlas batch or
  the layered-tree runtime, and trunk collision is chunk-scoped on one
  `StaticBody2D` per object packet layer.
- small rocks use `object_kind == 7`; presentation uses the layered-rock
  runtime only, remains sparse, and must not create collision shapes.

### Batch Presentation Contract

Production presentation for mass objects must use data buffers and
`MultiMeshInstance2D` batches, not per-object `_draw()` calls.

Required direction:

- one chunk object placement result produces compact presentation buffers;
- a dedicated decor batch helper owns `MultiMeshInstance2D` layers and shader
  materials;
- sprite atlas frame, tint, depth bucket, wind phase, and shadow parameters are
  presentation data, not gameplay identity;
- sprite-frame animation for living decor must stay in shader/material uniforms,
  not per-frame CPU buffer rebuilds;
- batched contact-shadow, dynamic sun-shadow, or wind changes update shader
  uniforms; layered authored-shadow objects may rebuild only their bounded
  loaded presentation polygons when lighting-profile inputs change, never
  placement or gameplay state;
- depth ordering uses the shared player-relative mid-layer depth ladder
  (`WorldRuntimeConstants.DEPTH_STRIPE_PX` / `DEPTH_STRIPES_PER_CHUNK`,
  anchor owned by `WorldStreamer`): bounded sparse per-stripe batch layers
  interleaved with the grass scatter stripes, the player constant at the
  ladder center — not one node per object, no periodic stripe classes, no
  separate player-reference split;
- source textures are preloaded or boot-prepared before runtime publish;
- `ChunkView` may host the batch helper, but it must not compute canonical
  placement truth.
- `WorldObjectPacketLayer` consumes native packet records and builds bounded
  chunk-local `MultiMeshInstance2D` sprite/shadow batches plus the explicit
  tree trunk collision proof.
- temporary local scatter adapters are allowed only as disabled reference tools;
  accepted dense placement must stay in the native packet path before content
  is enabled at scale.

Forbidden in the production path:

- `CanvasItem._draw()` loops over every world object;
- `draw_texture_rect_region()` or `draw_colored_polygon()` per object;
- `queue_redraw()` as the normal sun, wind, or time-of-day update path;
- synchronous `load()` when a chunk enters view;
- rebuilding object placement just because lighting changed.

### Tree Collision Proof

Current `world_version >= 61` allows one explicit collision proof: generated
plains trees may expose static obstacle collision for their trunks while crowns
remain passable presentation.

Rules:

- collision is allowed only for trees derived from the same deterministic native
  object packet record as the visual or layered tree presentation;
- collision must be chunk-scoped: one `StaticBody2D` per loaded chunk layer with
  shape owners, not one physics node per tree;
- collision uses the obstacle-compatible layer expected by the player movement
  mask;
- shape size is derived from the same visual `size_px` as the rendered tree and
  must stay smaller than the crown footprint;
- collision records are derived presentation/physics proof data, not saved
  authoritative world state;
- this proof does not add harvesting, resource yield, object commands, object
  events, save diffs, non-`plains` placement, or mod script hooks;
- accepted dense placement and collision for mod-scale content must remain in
  the native packet path before it is treated as production object gameplay.

## Event Contracts

V0 does not introduce new gameplay events.

Later harvest/mutation iterations must update
`docs/02_system_specs/meta/event_contracts.md` if they add events such as
`world_object_harvested` or `world_object_removed`.

## Save / Persistence Contracts

V0 generated placements are immutable base output and are not saved.

Since V0 does not include harvesting or destruction, it does not add a new
runtime diff shape.

Later mutation iterations must persist only runtime diff entries, for example:

```text
chunk_object_diffs:
  removed_generated_instances: [...]
  changed_generated_instances: [...]
  placed_runtime_instances: [...]
```

The save identity must use stable content IDs or deterministic generated
instance identity, never display names or asset paths.

## Performance Class

Runtime work class:

- placement generation: native `boot` or `background` packet generation;
- chunk publish / presentation apply: bounded main-thread apply;
- interactive gameplay path: static physics broadphase for loaded tree trunks
  only; no scatter rebuild, asset load, or shape regeneration in an interactive
  input path.

Dirty unit:

- one chunk object placement packet;
- later object mutation: one generated object instance plus its owning chunk.

Target scale:

- hundreds of visible generated objects across loaded chunks;
- hundreds of wind-reactive flora instances across loaded chunks;
- thousands of generated definitions across content packs without hot-path
  string/path lookup per rendered object.

Escalation path:

- native placement solve for dense object generation;
- additive native object packet records for visual-only living flora,
  visual-only spiky flora, and trees;
- additive native placement for small static biofield flora objects that reuse
  the spiky flora packet family and atlas index `1`;
- registry-prepared numeric indices for hot packets;
- `MultiMeshInstance2D` batched rendering for mass presentation;
- shader-uniform updates for dynamic wind and fake shadows;
- GPU atlas-frame animation for visual-only living flora;
- fixed front/top baked-shadow static atlas frames for visual-only spiky flora;
- chunk-scoped static collision shape owners for loaded tree trunks only;
- pooled interactive proxies only near the player in later iterations.

## Modding / Extension Points

V0 must keep the following extension direction open:

- mods can add `plains` world object definitions;
- mods can add additive `plains` placement sets;
- overrides require explicit precedence and must not depend on accidental load
  order;
- modded content must provide localization keys;
- missing mod content in a save must remain diagnosable in later mutation
  iterations.

## Localization

World object definitions store localization keys, not display text.

Expected key families:

- `FLORA_*`
- `ITEM_*` or `RESOURCE_*` where the object is resource-facing;
- `LORE_*` only for lore-facing entries.

V0 content additions must include RU and EN keys when player-facing names or
descriptions are visible.

## Implementation Iterations

### Iteration 0 - Spec and contract alignment

Goal:

- land this spec;
- update documentation indexes;
- do not change runtime code or assets yet.

Acceptance:

- `docs/README.md` and `docs/02_system_specs/README.md` link this spec;
- packet/save/event/API docs are checked for whether updates are required.

### Iteration 1 - Plains static presentation proof

Goal:

- add a minimal native-packet-backed `plains`-only placement path for
  non-interactive generated objects.
- `ChunkView` presentation must consume native object packet records and must
  remain presentation-only except for the explicit tree-trunk collision proof
  above.

Allowed content:

- visual-only animated flora atlases under `assets/sprites/flora/atlases/`;
- visual-only static spiky flora atlases under `assets/sprites/flora/atlases/`;
- plains tree atlases or layered-tree assets under `assets/sprites/flora/`;
- later flora object, such as `core:sporestalk_small`.

Non-goals:

- harvesting;
- resource yield;
- commands;
- object save diffs;
- non-`plains` biome support.

### Iteration 2 - Harvest and runtime diff

Goal:

- add a command-backed mutation path for harvesting or removing a generated
  object instance.

Required doc updates:

- `commands.md`;
- `event_contracts.md` if a domain event is emitted;
- `packet_schemas.md` and `save_and_persistence.md` for the diff shape.

## Acceptance Criteria

V0 is acceptable when:

- new object content is defined through data/registry entries, not code paths;
- all new world object art lives under the documented `assets/sprites/`
  folders;
- generated objects appear only in `plains`;
- chunk placement is deterministic for the same seed, chunk, version, and
  content pack set;
- visible mass objects are batched or pooled, not one node per object;
- animated living flora uses shader frame selection, not per-frame instance
  buffer rebuilds;
- static spiky flora is batched, restricted to orange biofield patches, and not
  emitted as scene nodes;
- small static brown seaweed biofield objects are batched through spiky flora
  atlas index `1`, restricted to orange biofield patches, and not emitted as
  scene nodes;
- trees are emitted through `object_kind == 4`, use deterministic variants, and
  use chunk-scoped trunk collision shape owners only;
- small rocks are emitted through `object_kind == 7`, use deterministic
  layered variants, have snow masks/overlays, rotate baked shadows around their
  anchors onto the south-east axis before low-sun stretch, and create no
  collision;
- accepted flora, trees, and small rocks are emitted from the native object
  packet, not from a runtime GDScript scatter generator;
- active generated stone/rock object families `1`, `5`, and `6` are not emitted
  for `world_version >= 61`;
- canonical generated placements are not saved as full chunk content;
- mods have an additive content path that does not require core generator
  surgery.

## Failure Cases / Risks

This design is wrong if:

- adding one new plant requires editing generator `if` branches;
- asset paths become gameplay identity;
- placement output depends on file order;
- visible objects are instantiated as one node each across loaded chunks;
- accepted object placement remains in a local GDScript scatter path instead of
  the native packet;
- collision is added as one node per generated object or rebuilt during
  interactive input;
- animated flora updates rebuild instance buffers every frame;
- V0 quietly expands beyond `plains`;
- object harvesting is added before command/save/event contracts are defined.

## Open Questions

- Exact final class names for `WorldObjectData`, `PlacementSetData`, and
  presentation resources.
- Whether the hot packet stores numeric registry indices or compact string IDs.
- Whether atlas construction is manual, Godot-import-driven, or generated by a
  tool in a later content pipeline task.
- Exact override precedence for multiple mods targeting the same `plains`
  placement set.
