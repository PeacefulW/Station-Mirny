---
title: World Generation Foundation
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - ../README.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../03_content_bible/resources/flora_and_resources.md
---

# World Generation Foundation

This is the canonical system-spec foundation for procedural world generation in Station Mirny.

## Purpose

The purpose of this document is to define a stable architectural foundation for world generation that:
- produces a coherent world instead of isolated random chunks
- supports iterative expansion without rewriting the generator every time
- stays compatible with the project's data-driven and mod-extensible architecture
- respects runtime and streaming constraints

This document is not a fixed catalog of every final biome.
It is the architectural contract that allows the project to start small and scale safely.

## Gameplay goal

World generation must support the product fantasy that:
- the world feels continuous over long travel
- major landforms are readable
- biomes feel physically and visually grounded
- local variation prevents repetition
- the player can eventually experience a world that is large, strange, and coherent rather than stitched together

## Scope

This spec owns:
- global world channels
- large-scale terrain structures
- biome resolution architecture
- local variation / subzone logic
- chunk build responsibilities
- deterministic sampling rules
- wrap-world assumptions
- generation-side data contracts
- extension points for biomes/flora/features

This spec does not own:
- final content catalog for all biomes
- low-level rendering implementation details unrelated to generation contracts
- runtime performance law
- execution sequencing
- final lore canon

Those belong in:
- [Performance Contracts](../../00_governance/PERFORMANCE_CONTRACTS.md)
- [Master Roadmap](../../04_execution/MASTER_ROADMAP.md)
- [Game Vision GDD](../../01_product/GAME_VISION_GDD.md)
- [Flora and Resources](../../03_content_bible/resources/flora_and_resources.md)

## Core architectural statement

Beautiful procedural generation in this project does **not** come from choosing a random biome per chunk.

It comes from:
1. several continuous world-scale fields
2. large natural structures
3. a deterministic biome resolver
4. a separate layer of local variation

This is the non-negotiable foundation.

## Constraints inherited from project governance

World generation must comply with the following project rules:
- data-driven architecture
- service separation instead of monolithic generators
- no heavy rebuild in interactive path
- chunk as streaming/cache unit, not as the source of world truth
- immutable base + runtime diff for persisted world changes
- mod-compatible extension through resources and registries

This means:
- no giant one-class generator that owns everything forever
- no hardcoded biome logic in long `if` chains as the final architecture
- no runtime full rebuilds from player actions

## What "good generation" means here

Generation quality in Station Mirny is defined by observable properties:

### Continuity
The player should be able to travel far and feel that the world changes gradually, not chunk-by-chunk as disconnected postcards.

### Readable large structures
Rivers should read as rivers. Mountains should read as ranges or ridges. Wet zones should feel physically connected to terrain and moisture.

### Natural transitions
Biomes should often blend through ecotones, foothills, floodplains, sparse/dense flora bands, or other intermediate states instead of abrupt random edges.

### Local variety
Even within one biome, there should be variation:
- sparse flora
- dense flora
- rocky patch
- clearing
- wet patch
- visually calmer or harsher subareas

### Determinism
The same seed and world coordinates must produce the same world answer.

### Extensibility
Adding a biome, feature, or flora family should be a data and resolver extension problem, not a generator rewrite.

## World model

The world is generated from several layers.

### Layer 1: Global continuous channels

These are world-scale sampled fields such as:
- height
- temperature
- moisture
- ruggedness
- flora_density

They are continuous over the world and do not reset per chunk.

Their role:
- provide the underlying "physics-like" shape of the world
- give the biome resolver stable inputs
- support continuity and wrap behavior

### Layer 2: Large natural structures

Some world features should not emerge from simple noise alone.

Examples:
- mountain ridges
- river systems
- floodplains
- major dry belts
- cold belts by latitude

These large structures must exist as explicit generation concepts, not just as accidental outcomes of one noise field.

### Layer 3: Biome resolution

Biomes are resolved by a deterministic resolver that evaluates biome candidates against the channel values and structural context at a world position.

Biomes are therefore:
- data-driven
- deterministic
- condition-resolved
- not chosen by random chunk lottery

### Layer 4: Local subzones and variation

Inside a biome, there should be local variation that does not require inventing a new full biome every time.

Examples:
- sparse flora patch
- dense flora patch
- clearing
- rocky edge
- wet pocket

This protects the project from exploding into too many "main biomes" just to get local diversity.

### Layer 5: Decor, flora, features, POI hooks

After biome and local context are known, the system can choose:
- flora sets
- decor sets
- resource surface expressions
- feature hooks
- POI hooks

This layer should remain content-driven and extensible.

## Chunk role

The chunk is:
- a streaming unit
- a caching unit
- a build-output container

The chunk is **not** the truth of the world's climate, biome logic, or structural identity.

Canonical rule:
- world truth lives at world coordinates through deterministic sampling and generation contracts
- chunks materialize that truth for streaming and rendering

## Determinism and wrap assumptions

The generator must be deterministic by:
- seed
- canonical world coordinates
- stable sampling rules

Current foundation assumption for world topology:
- cylindrical wrap-world
- X wraps
- Y carries latitude-like logic

This means:
- east-west wrap must remain seamless
- north-south progression may support climate bands and latitudinal logic

If this topology changes later, it should be treated as a major architectural change, not a casual tweak.

## Biome resolution model

Biomes should be represented as data resources evaluated by a resolver.

The intended model is:
- each biome defines preferred ranges and tags
- resolver computes candidate scores
- best valid biome wins
- local modifiers refine the result

This avoids:
- giant hardcoded biome `if` trees
- brittle per-biome code branches
- impossible-to-modify biome logic

## Flora model

The project should think in terms of a broad **flora** layer, not "normal Earth trees" as the default assumption.

This matters because Station Mirny's world identity expects non-Earth life.

The flora layer should therefore allow:
- alien tree-like forms
- fungal columns
- coral-like growths
- bioluminescent growths
- biome-specific vegetation sets

Flora distribution should be driven by:
- biome
- local subzone
- flora_density
- special feature rules

## Services and responsibilities

The generation architecture should be decomposed into services with narrow responsibilities.

At minimum the mental model should be:

### World channel sampler
Returns continuous channel values for world coordinates.

### Large structure sampler/generator
Defines and exposes mountain/ridge/river/major structure influence.

### Biome resolver
Determines biome result from channels and structure context.

### Local variation resolver
Determines subzones and local modulation inside the biome.

### Chunk content builder
Builds concrete chunk output from the above layers.

This decomposition is more important than the exact final class names.

## Data model direction

The following data types are expected as the system matures:

- `BiomeData`
- `FloraSetData`
- `DecorSetData`
- `FeatureData`
- channel and world-generation balance resources

These are expected to be registry-friendly and mod-extensible.

## Minimal technical contracts

These are not final APIs, but they represent the intended architectural seams.

### World channel sampler

```gdscript
class_name PlanetSampler
extends RefCounted

func sample_world_channels(world_pos: Vector2i) -> WorldChannels:
    pass
```

### Biome resolver

```gdscript
class_name BiomeResolver
extends RefCounted

func resolve_biome(world_pos: Vector2i, channels: WorldChannels) -> BiomeResult:
    pass
```

### Chunk content builder

```gdscript
class_name ChunkContentBuilder
extends RefCounted

func build_chunk(chunk_coord: Vector2i) -> ChunkBuildResult:
    pass
```

### Example biome data direction

```gdscript
class_name BiomeData
extends Resource

@export var id: StringName
@export var tags: Array[StringName]
@export var min_height: float
@export var max_height: float
@export var min_temperature: float
@export var max_temperature: float
@export var min_moisture: float
@export var max_moisture: float
@export var flora_set_ids: Array[StringName]
@export var decor_set_ids: Array[StringName]
@export var priority: int
```

These fields are not final. They illustrate the intended style:
- data-driven
- explicit
- registry-compatible

## Performance class

World generation belongs primarily to:
- Boot work
- Background work

It must not migrate heavy generation logic into the interactive path.

Implications:
- channel sampling should be deterministic and cheap
- chunk building should be staged/streamable
- heavy rebuilds must respect dirty queue + budget
- player actions must modify runtime diff, not force world-base regeneration

See:
- [Performance Contracts](../../00_governance/PERFORMANCE_CONTRACTS.md)

## Save contract

Canonical rule:
- generated world base is deterministic from seed and coordinates
- player impact is stored as runtime diff

This means:
- chunk save data should store modifications, not full replacement world truth
- wrap-world identity must preserve canonical coordinate consistency
- future biomes/features must respect immutable base + diff

## MVP recommendation

The recommended minimum viable implementation is intentionally small in content but complete in architecture.

### Recommended MVP channels
- height
- temperature
- moisture
- ruggedness
- flora_density

### Recommended MVP biome set
- plains
- foothills
- mountains
- wet lowland / floodplain
- scorched or dry wasteland
- cold zone

### Recommended MVP major structures
- at least one mountain/ridge system
- at least one river system

### Recommended MVP local variation
- sparse flora
- dense flora
- clearing
- rocky patch
- wet patch

### Recommended MVP world topology
- X wrap
- Y latitude logic

The target experience of this MVP is:
- long readable river
- clear rise into foothills/mountains
- visible climatic drift into colder areas
- obvious difference between dense and sparse flora zones

That is enough to produce a world that already feels coherent without prematurely exploding content scope.

## Acceptance criteria

The foundation is considered successful when:
- long-distance travel feels continuous
- rivers and mountains read as large systems rather than noisy accidents
- biome transitions are explainable by terrain, moisture, temperature, or ecotones
- local variety exists inside major biomes
- wrap seams are not visibly broken
- new biome or flora content can be added without rewriting generator core

## Failure signs

The architecture should be considered wrong if:
- each chunk looks like a separate random postcard
- biome borders feel arbitrary and unexplained
- every new biome requires generator surgery
- local diversity is missing, so new "main biomes" must be invented just to add variation
- player interaction triggers full world-side rebuilds
- wrap-world traversal produces seams or identity mismatch

## Main risks and anti-patterns

### Random biome choice per chunk
Creates patchwork instead of a world.

### Monolithic world generator
Becomes fragile, hard to extend, and hostile to mods.

### Hardcoded biome logic in long branches
Breaks the data-driven architecture and scales badly.

### Trying to define every final biome too early
Turns the project into content explosion before the base geometry is stable.

### Mixing biome identity with decor identity
Creates too many top-level biomes instead of a clean biome + local variation model.

### Doing heavy generation rebuild in gameplay-triggered code
Violates the performance model and causes hitch.

### Chasing realism before readability
The early goal is coherent, legible, expandable world generation, not perfect planetary simulation.

## Extension points

The architecture must support future extension by:
- new `BiomeData`
- new flora sets
- new decor sets
- new feature definitions
- later biome-specific rules
- modded biome or flora registries

Extension should happen through:
- resources
- registries
- resolver rules
- chunk builder hooks

not through direct rewrites of the foundation.

## Open questions

These remain system-spec-level questions rather than locked decisions:
- exact final set of world channels
- exact river algorithm
- exact ridge/mountain algorithm
- exact scoring model for biome resolution
- exact boundary between base biome and local subzone data
- exact POI hook layer

These questions should be refined without breaking the accepted foundation principles above.

## Transitional source note

The foundation input for this migrated spec came from:
- `M:\Downloads\fundament_procedural_world_generation_mirny.docx`

That document should now be treated as a migration source, not as the canonical home for this system contract.
