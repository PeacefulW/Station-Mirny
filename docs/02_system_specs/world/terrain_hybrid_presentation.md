---
title: Terrain Hybrid Presentation
doc_type: system_spec
status: approved
owner: engineering+art
source_of_truth: true
version: 0.5
last_updated: 2026-04-29
related_docs:
  - ../../README.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - world_runtime.md
---

# Terrain Hybrid Presentation

## Purpose

Define the canonical presentation architecture for terrain that uses:

- baked shape geometry from authored atlases
- runtime material rendering from shared shaders
- unchanged authoritative world/runtime contracts unless topology rules truly change

This spec exists so terrain presentation can scale to new biomes, cliffs, banks,
and material families without turning `WorldTileSetFactory` into a hardcoded list
of one-off texture paths.

## Gameplay Goal

Terrain must feel more continuous and material-rich than a purely baked tile
atlas while preserving:

- deterministic terrain classification and walkability
- bounded chunk publish/apply work
- readable cliffs, banks, and edges
- support for multiple biome materials without rewriting native generation for
  each art variant

## Scope

This spec covers:

- terrain presentation only
- authored shape geometry for terrain silhouettes and ledges
- shader-driven terrain materials
- how shape data and material data are split
- how runtime selects terrain presentation without mutating canonical world data
- how new biome materials and new baked shape families should extend the system

## Out of Scope

This spec does not define:

- canonical biome generation rules
- water simulation
- climate simulation
- save payload changes
- multiplayer packet evolution
- procedural geometry generation at runtime
- editor UX for the generator itself

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Terrain hybrid presentation is visual only. Canonical terrain ids and walkability stay authoritative elsewhere. |
| Save/load required? | Only for authored assets and data resources, not as runtime save state. |
| Deterministic? | Yes for visible output at a given world position, shape set, and material set. |
| Must it work on unloaded chunks? | Yes. Presentation selection must remain derivable from loaded packet data plus preloaded resources. |
| C++ compute or main-thread apply? | Topology solve stays in C++; scene apply stays on the main thread; shader renders pixels. |
| Dirty unit | One authoritative tile mutation plus bounded local visual patch for adjacency-dependent atlas decisions. |
| Single owner | Native owns terrain classification and atlas decisions. Presentation owns only shape/material rendering. |
| 10x / 100x scale path | Adding materials must not add new native generation branches or per-tile script compute loops. |
| Main-thread blocking risk | Only bounded publish/apply is allowed. No sync material generation on hot paths. |
| Hidden fallback? | Forbidden. Native topology paths do not silently fall back to GDScript compute. |
| Could it become heavy later? | Yes. Therefore topology and atlas decisions remain native-owned now. |
| Whole-world prepass or local compute only? | Local compute only. No planet-scale presentation bake at startup. |

## Design Intent

Terrain presentation is split into two authored layers:

1. **Shape set**
   - baked geometry and zone masks
   - authored offline in the generator
   - reused by many materials

2. **Material set**
   - color, breakup, and lighting response
   - consumed by a shared shader family at runtime
   - reused by many shapes

The runtime does **not** compute geometric parameters such as `height`, `lip`,
`roughness`, `north rim`, or `inner corners` from numbers in code. Those are
authoring parameters of the generator and are baked into the shape set exports.

## Core Terms

### `shape set`

A baked terrain geometry package exported by the generator.

It contains:

- `mask atlas`
- `shape normal atlas`
- one full case set for the topology family it supports

The shape set answers:

- where the top surface is
- where the facade / bank face is
- where the rim / back rim is
- how corners and inner cuts are shaped

The shape set does **not** define the final material appearance.

### `material set`

A terrain material package consumed by the runtime shader.

It contains:

- `top albedo`
- `face albedo`
- `top modulation`
- `face modulation`
- `top normal`
- `face normal`

The material set answers:

- what the terrain looks like
- how top and face surfaces vary
- how the material responds to light

The material set does **not** define edge geometry.

### `hybrid terrain presentation`

A terrain rendering model where:

- geometry comes from a baked shape atlas
- material comes from shader-driven sampling

This is "hybrid" because it is neither:

- a fully baked final-color tile atlas
- nor a fully procedural runtime geometry system

## Architectural Principles

### 1. Generator owns geometric authoring

Parameters such as:

- `height`
- `lip`
- `roughness`
- `north rim`
- `inner corners`

belong to the generator and are baked into the exported shape set.

The game runtime must not reconstruct these geometric decisions numerically.

### 2. Runtime owns material rendering, not geometric invention

At runtime, the shader is allowed to:

- sample `albedo`
- sample `modulation`
- sample `normal`
- blend zones such as `top`, `face`, and `rim`

It is not allowed to invent new terrain geometry that was not authored into the
shape set.

### 3. One topology family can serve many materials

If `dirt`, `sand`, `snow`, `ash`, and similar terrain types all use the same
ledge logic, they should share the same topology family and only differ by:

- which shape set is selected
- which material set is selected

Example:
- `low_bank` shape + `sand` material
- `low_bank` shape + `snow` material
- `high_cliff` shape + `rock` material

### 4. Material-only expansion must not require native changes

Adding a new biome material must ideally require:

- new authored material assets
- one new material resource/profile entry

It must not require:

- new native packet fields
- new native generation branches
- a new shader per biome

### 5. New topology requires explicit native/spec review

If a new visual family still uses the same neighbor logic and case system, it
is only a new shape set.

If a new visual family requires:

- new adjacency rules
- new atlas-decision logic
- new topology classes

then native/autotile logic must change and the relevant runtime/meta docs must
be updated in the same task.

## Canonical Data Model

## `TerrainShapeSet`

Authoring/export data resource describing one baked shape family.

Canonical fields:

- `id: StringName`
- `topology_family_id: StringName`
- `mask_atlas: Texture2D`
- `shape_normal_atlas: Texture2D`
- `tile_size_px: int`
- `case_count: int`
- `variant_count: int`

Notes:

- `topology_family_id` identifies the neighbor/case logic expected by the atlas.
- `case_count` and `variant_count` are data-validation fields, not gameplay truth.
- The runtime uses the shape set only if its topology family matches the atlas
  decisions produced by native code.

## `TerrainMaterialSet`

Authoring/runtime data resource describing one terrain material family.

Canonical fields:

- `id: StringName`
- `top_albedo: Texture2D`
- `face_albedo: Texture2D`
- `top_modulation: Texture2D`
- `face_modulation: Texture2D`
- `top_normal: Texture2D`
- `face_normal: Texture2D`
- `shader_family_id: StringName`
- `sampling_params: Dictionary`

Notes:

- `top_albedo` and `face_albedo` are authored textures supplied by the content
  pipeline, typically exported from the terrain generator.
- `sampling_params` may contain values such as UV scale, modulation strength,
  contrast, tint opacity, or material-specific shader tuning.
- Missing required maps should fail validation; they should not silently
  degrade on runtime hot paths.

## `TerrainShaderFamily`

Authoring/runtime data resource describing one shared shader family.

Canonical fields:

- `id: StringName`
- `render_layer_id: StringName`
- `shader: Shader`
- `shape_texture_params: Dictionary`
- `material_texture_params: Dictionary`

Notes:

- `TerrainShaderFamily` maps one shared shader to canonical texture-slot names
  from `TerrainShapeSet` and `TerrainMaterialSet`.
- `render_layer_id` is authored data, not a hardcoded `if terrain is rock`
  branch in runtime code.
- A shader family may intentionally omit `shader` only for presentation paths
  such as `simple_tile` that do not instantiate a runtime shader material.

## `TerrainPresentationProfile`

Runtime binding between gameplay terrain classification and authored visuals.

Canonical fields:

- `id: StringName`
- `terrain_class_id: StringName`
- `terrain_ids: Array[int]`
- `shape_set_id: StringName`
- `material_set_id: StringName`
- `shader_family_id: StringName`

The profile answers:

- which shape set to use
- which material set to use
- which shared shader family renders them

Notes:

- `terrain_ids` is the authored registry-binding list used to build the single
  canonical `terrain_id -> TerrainPresentationProfile` mapping.
- Multiple terrain ids may intentionally point to the same profile by sharing
  one `terrain_ids` list.
- River Generation V1 currently maps hydrology terrain ids `5..10`
  (`riverbed_shallow`, `riverbed_deep`, `lakebed`, `ocean_floor`, `shore`,
  `floodplain`) through individual `hydrology:*_profile` placeholder profiles.
  This is a temporary simple-tile presentation bridge with diagnostic colours
  so the live packet boundary has readable profiles. The floodplain placeholder
  is an invisible overlay profile drawn over plains ground underlay so authored
  transparent floodplain texture can replace it later. It is not the final
  water/shore material contract.
- `terrain_class_id` is a descriptive/category field for authoring and grouping.
- `shader_family_id` must resolve through authored `TerrainShaderFamily` data,
  not a hardcoded runtime switch in `WorldTileSetFactory`.
- `terrain_class_id` is not permission for a second hidden runtime resolution
  path.

## Registry and ID Model

Terrain presentation should be resolved through IDs and data resources, not
through long hardcoded file lists inside gameplay scripts.

Recommended canonical runtime surfaces:

- `TerrainShapeRegistry`
- `TerrainMaterialRegistry`
- authored `TerrainShaderFamily` resources resolved by `TerrainPresentationRegistry`
- `TerrainPresentationRegistry`

These registries are read-only lookup layers for presentation data.

They must not own:

- canonical terrain truth
- save state
- world mutation

## Canonical Profile Resolution Path

There must be exactly one canonical runtime resolution path for terrain
presentation:

```text
terrain_id -> TerrainPresentationProfile
```

Rules:

- `terrain_id` is the authoritative runtime input already present in chunk
  packets and diff-applied terrain state.
- `TerrainPresentationRegistry` is the single owner of the mapping from
  `terrain_id` to `TerrainPresentationProfile`.
- `WorldTileSetFactory`, `ChunkView`, and shader setup code may consume the
  resolved profile, but they may not invent parallel profile-selection rules.
- If multiple terrain ids intentionally share the same visuals, they do so by
  pointing to the same `TerrainPresentationProfile` in the registry.
- A future `terrain_class_id` abstraction is allowed only if it still resolves
  through one explicit registry-owned path and does not create parallel lookup
  logic in multiple systems.

Forbidden:

- resolving profiles partly in `WorldStreamer`
- resolving profiles partly in `WorldTileSetFactory`
- resolving profiles partly in shader code
- "local inference" of the profile from texture availability or asset names

## Runtime Architecture

### Native / C++ responsibilities

Native owns:

- terrain classification
- walkability
- topology solve
- atlas/case decisions
- chunk packet preparation

Native does **not** own:

- `albedo`
- `modulation`
- `normal`
- texture paths
- terrain shader branching by biome art

### GDScript responsibilities

GDScript owns:

- registry/resource lookup
- material instance setup
- chunk view publish/apply
- orchestrating which terrain presentation profile is applied to a visible
  terrain class

GDScript does **not** own:

- heavy topology loops over chunk tiles
- shape generation
- hidden fallback recomputation of atlas decisions

### Shader responsibilities

The shared terrain shader family owns:

- world-space sampling of material textures
- top/face/rim blending
- modulation-driven breakup
- normal blending and lighting response

The shader does **not** own:

- gameplay truth
- terrain classification
- save state
- topology-family selection

## Validation Model

Terrain presentation resources must be validated before gameplay hot paths use
them.

Required validation stage:

- registry bootstrap
- project startup preload phase
- explicit editor/dev validation tools

Validation must confirm:

- the referenced shape set exists
- the referenced material set exists
- required textures exist and load successfully
- the shape set's `topology_family_id` matches the topology family expected by
  the runtime path that will consume it
- `mask atlas` and `shape normal atlas` are structurally valid for the declared
  case family
- required material maps are present for the shader family being used

Failure policy:

- invalid presentation resources fail validation early
- bootstrap/registry validation must report explicit errors
- chunk publish/apply must not become the first place where missing or invalid
  terrain resources are discovered

Forbidden:

- deferring topology-family mismatch detection to chunk publish
- discovering missing textures during visible chunk publication
- silent fallback to a "best effort" material on the runtime hot path

## Packet Contract Compatibility

For material-only expansion, the current packet contract should remain valid:

- `terrain_ids`
- `terrain_atlas_indices`
- `walkable_flags`

This means:

- no PNG paths in chunk packets
- no texture IDs in chunk packets for simple material expansion
- no save payload changes for shape/material swaps

The current `ChunkPacketV0` remains sufficient as long as runtime presentation
selection is registry-resolved from the existing authoritative terrain id.

If a future design requires new presentation-selection data that is not locally
derivable, then `packet_schemas.md` must be updated in the same task.

## Save / Load Contract

Terrain hybrid presentation is derived visual state.

It must not be written into chunk save diffs as:

- atlas PNG references
- texture paths
- material shader params

Persisted chunk diffs continue to store only authoritative terrain changes such
as:

- `terrain_id`
- `walkable`

## Event and Command Contract Impact

Terrain hybrid presentation does not require new commands or domain events by
default.

It should reuse existing world mutation paths:

- native packet generation
- diff application
- bounded chunk publish

Only if terrain presentation gains a new public runtime control surface should
the relevant boundary docs be updated:

- `system_api.md`
- `commands.md`
- `event_contracts.md`

## Asset Layout Rule

The canonical architecture should move toward data-driven grouping, not flat
hardcoded one-off files.

Recommended target layout:

```text
assets/
  terrain/
    shapes/
      low_bank/
        mask_atlas.png
        shape_normal_atlas.png
      high_cliff/
        mask_atlas.png
        shape_normal_atlas.png
    materials/
      dirt/
        top_albedo.png
        face_albedo.png
        top_modulation.png
        face_modulation.png
        top_normal.png
        face_normal.png
      snow/
        ...
data/
  terrain/
    shape_sets/
      low_bank.tres
      high_cliff.tres
    material_sets/
      dirt.tres
      snow.tres
    shader_families/
      ground_hybrid.tres
      rock_shape.tres
    presentation_profiles/
      plains_ground.tres
      snow_bank.tres
      mountain_rock.tres
```

Current hardcoded paths may exist during transition, but they are not the
desired long-term architecture.

## Performance Class

### Offline / authoring

Generator work is offline-only and has no runtime frame budget impact.

### Runtime compute

Must remain bounded:

- topology solve in native only
- one packet per chunk
- no per-tile GDScript geometry reconstruction

### Runtime apply

Must remain bounded:

- assign preloaded shared materials/resources
- apply visible cells in sliced publish batches
- do not create unique materials per tile

### Shader cost

Shader sampling must scale by shader family, not by per-biome shader count.

Preferred model:

- one shared terrain surface shader family
- one shared terrain cliff/bank shader family when needed
- data changes through resources, not new shader source files for every biome

## Extension Rules

### Adding a new biome material

Allowed path:

1. author a new `TerrainMaterialSet`
2. register a new `TerrainPresentationProfile`
3. keep the same shape set if geometry is unchanged

This should not require native changes.

### Adding a new baked silhouette

Allowed path:

1. create a new shape set in the generator
2. export new mask/shape-normal atlases
3. register a new `TerrainShapeSet`
4. bind it through a presentation profile

This should not require native changes **if** the topology family is unchanged.

### Adding a new topology family

Required path:

1. update the topology solve and atlas-decision logic
2. update the relevant world/runtime specs and packet/schema docs if needed
3. author a matching shape set for that new topology family

## Anti-Patterns

Forbidden:

- runtime numeric terrain geometry such as `height` or `lip` computed in code
- one shader source per biome
- one hardcoded texture constant per biome in long switch/if chains
- saving presentation-only texture references in chunk diffs
- GDScript fallback topology solve when native is missing
- per-tile unique material creation on hot paths
- treating `modulation` as a replacement for `albedo`
- storing canonical terrain truth inside `ChunkView` or a shader

## Acceptance Criteria

The terrain hybrid architecture is considered correctly implemented when:

- shape geometry comes only from baked shape atlases
- terrain materials are selected through data/resources, not a hardcoded file list
- adding a new biome material does not require a new native packet contract
- modulation remains a secondary breakup layer, not the primary color source
- normals remain independent lighting data, not color proxies
- the runtime hot path contains no GDScript geometry solve loop over chunk tiles
- save/load contracts remain presentation-agnostic unless explicitly changed

## Risks

- A transitional implementation may still hardcode some resource paths before
  registries/resources are introduced.
- If shape family selection is underspecified, future tasks may accidentally
  mutate packet contracts too early.
- If shader families diverge per biome, the system will regress into special
  cases instead of becoming more data-driven.

## Open Questions

- Should flat ground and bank/cliff terrain share one shader family or two
  related families under one material contract?
- What is the minimal public registry/API surface needed for mods to extend
  terrain presentation safely?
- Should water-adjacent low banks remain the same topology family as taller
  cliffs, or do they justify a separate family later?

## Implementation Iterations

### Iteration 1 - Validate the split

- prove that one terrain family can use baked shape plus shader material
- keep current packet contract unchanged
- no broad registry refactor yet

### Iteration 1.5 - Transition bridge from current state

- wrap current `plains` and `rock` terrain presentation assets into the first
  `TerrainShapeSet`, `TerrainMaterialSet`, and `TerrainPresentationProfile`
  resources
- keep the current packet/apply contract unchanged
- keep current topology solve native-owned
- allow `WorldTileSetFactory` to act as a temporary consumer of registry-backed
  resources instead of acting as the long-term owner of hardcoded paths
- do not leave the codebase in a half-hardcoded / half-registry state where
  multiple profile-selection mechanisms coexist

### Iteration 2 - Introduce data resources

- add `TerrainShapeSet`
- add `TerrainMaterialSet`
- add `TerrainPresentationProfile`
- move profile resolution to one registry-owned path
- remove hardcoded per-material file lists from the presentation wiring

### Iteration 3 - Unify terrain material families

- route multiple biome materials through shared shader families
- keep topology rules native-owned
- extend banks/cliffs/ground through data, not special-case shaders

### Iteration 4 - Extension and mod path

- expose registry-backed terrain presentation selection for content/mod systems
- update `system_api.md` if new safe public entrypoints are introduced

## Required Updates

This spec does **not** automatically require changes to:

- `packet_schemas.md`
- `system_api.md`
- `event_contracts.md`
- `commands.md`

unless a future implementation task changes one of these boundaries:

- packet shape
- public registry/API surface
- command path
- event contract

When that happens, update the relevant meta docs in the same task.
