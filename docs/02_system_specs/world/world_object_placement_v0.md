---
title: World Object Placement V0
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.4
last_updated: 2026-06-08
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
flora, loose stones, small resource nodes, and inert decor.

This spec exists so adding plants and rocks does not become a set of ad-hoc
scene paths or generator branches. V0 is intentionally narrow: it proves the
data, asset, registry, packet, and presentation boundaries for one biome before
expanding to broader worldgen content.

## Gameplay Goal

The player should see the `plains` biome gain readable local identity through
small generated objects:

- alien flora that supports the content bible's non-Earth baseline;
- loose stones or small rock/resource forms that make the terrain feel tactile;
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
- a narrow loaded-chunk collision proof for large `plains` rocks only;
- a narrow visual-only animated flora proof gated by chunk-local grass patches,
  using one fixed south/front-facing atlas row for presentation;
- a narrow visual-only static spiky flora proof restricted to chunk-local
  orange biofield patches, using a fixed front/top baked-shadow atlas frame;
- a narrow small static biofield flora proof restricted to chunk-local orange
  biofield patches, using spiky flora atlas index `1` and no collision;
- a narrow rare large rock-family proof restricted to chunk-local rocky ground
  patch coverage, using rock atlas index `3` and the existing loaded large-rock
  collision proof;
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
- broad generated object collision beyond the explicit large `plains` rock
  loaded-chunk proof in Iteration 1;
- harvesting, collision, save identity, or gameplay commands for visual-only
  flora proofs;
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
- rock/resource-node sprites for `plains` go under
  `assets/sprites/resources/plains/`;
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
assets/sprites/resources/plains/loose_stone_01.png
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

### Packet Shape Direction

V0 extends `ChunkPacketV0` additively with a compact visual object section.
The accepted first packet shape is presentation-oriented and intentionally
byte-packed:

```text
object_kind: PackedByteArray          # V0 family id: 1 rock, 2 living flora, 3 spiky flora
object_local_x_px_q4: PackedByteArray # chunk-local pixel X quantized to 4 px
object_local_y_px_q4: PackedByteArray # chunk-local pixel Y quantized to 4 px
object_size_px: PackedByteArray       # rendered sprite size in pixels
object_atlas_index: PackedByteArray   # prepared atlas bank index; spiky flora index 1 is small static brown seaweed, rock index 3 is rare rocky-patch rock formation
object_variant: PackedByteArray       # atlas frame / animation view variant
object_flags: PackedByteArray         # bit flags; bit 0 = large-rock collision proof
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

- mass flora, stones, decor, and debris use batched rendering or pooled
  lightweight presentation;
- V0 must not instantiate one node per generated object;
- assets must be preloaded or prepared outside interactive paths;
- presentation may choose deterministic atlas variants;
- presentation state is derived and not persisted.
- accepted V0 rocks and flora consume native object packet arrays; local
  GDScript scatter helpers are legacy/reference only and not the production
  placement source.
- static biofield flora atlas bank index `0` is the orange spiky plant; index
  `1` is the small brown seaweed object and must pass the same deterministic
  orange biofield mask before emission.
- rock atlas bank indices `0..2` are ordinary loose plains rocks; rock atlas
  index `3` is reserved for the rare large rocky-patch rock formation and must
  pass the deterministic rocky ground patch mask before emission.

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
- contact-shadow, dynamic sun-shadow, or wind changes update shader uniforms,
  not per-object CPU geometry;
- depth ordering may use bounded depth buckets per chunk, but not one node per
  object;
- source textures are preloaded or boot-prepared before runtime publish;
- `ChunkView` may host the batch helper, but it must not compute canonical
  placement truth.
- `WorldObjectPacketLayer` consumes native packet records and builds bounded
  chunk-local `MultiMeshInstance2D` sprite/shadow batches plus the explicit
  loaded-rock collision proof.
- temporary local scatter adapters are allowed only as disabled reference tools;
  accepted dense placement must stay in the native packet path before content
  is enabled at scale.

Forbidden in the production path:

- `CanvasItem._draw()` loops over every world object;
- `draw_texture_rect_region()` or `draw_colored_polygon()` per object;
- `queue_redraw()` as the normal sun, wind, or time-of-day update path;
- synchronous `load()` when a chunk enters view;
- rebuilding object placement just because lighting changed.

### Loaded Large Rock Collision Proof

Iteration 1 allows one explicit collision exception: large visual rocks in
`plains` may expose static obstacle collision while the final packet-backed
object placement path is still being proven.

Rules:

- collision is allowed only for large rocks derived from the same deterministic
  native object packet record as the visual rock batch;
- collision must be chunk-scoped: one `StaticBody2D` per loaded chunk layer with
  shape owners, not one physics node per rock;
- collision uses the obstacle-compatible layer expected by the player movement
  mask;
- shape size is derived from the same visual `size_px` as the rendered rock and
  must stay smaller than the sprite footprint;
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
- interactive gameplay path: static physics broadphase for large loaded rocks
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
- additive native object packet records for rocks, visual-only living flora,
  and visual-only spiky flora;
- additive native placement for small static biofield flora objects that reuse
  the spiky flora packet family and atlas index `1`;
- sparse native placement for rare large rock-family objects that reuse the rock
  packet family and atlas index `3`;
- registry-prepared numeric indices for hot packets;
- `MultiMeshInstance2D` batched rendering for mass presentation;
- shader-uniform updates for dynamic wind and fake shadows;
- centered contact shadows for small static rocks when directional cast shadows
  make the sprite read as floating;
- GPU atlas-frame animation for visual-only living flora;
- fixed front/top baked-shadow static atlas frames for visual-only spiky flora;
- chunk-scoped static collision shape owners for large loaded rocks only;
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
  remain presentation-only except for the explicit large-rock loaded collision
  proof above.

Allowed content:

- non-interactive `plains` rock atlases under
  `assets/sprites/resources/atlases/`;
- visual-only animated flora atlases under `assets/sprites/flora/atlases/`;
- visual-only static spiky flora atlases under `assets/sprites/flora/atlases/`;
- later flora object, such as `core:sporestalk_small`;
- later loose stone/resource-like definition, such as `core:loose_stone`.

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
- rare large rock-family objects are batched through rock atlas index `3`,
  restricted to rocky ground patch coverage, and use chunk-scoped collision
  shape owners only;
- accepted rocks and flora are emitted from the native object packet, not from
  a runtime GDScript scatter generator;
- large loaded rocks with collision use chunk-scoped shape owners, not one
  physics node per rock;
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
- collision is added as one node per rock or rebuilt during interactive input;
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
