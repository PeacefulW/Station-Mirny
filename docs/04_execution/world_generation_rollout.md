---
title: World Generation Rollout
doc_type: execution
status: approved
owner: engineering+design
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - ../02_system_specs/world/world_generation_foundation.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../04_execution/MASTER_ROADMAP.md
---

# World Generation Rollout

This document defines the execution rollout for procedural world generation in Station Mirny.

## Purpose

This file exists to answer:
- in what order world generation should be built
- what should be stabilized first
- what must not be skipped
- how to avoid content explosion before the foundation is solid

It is an execution document, not the architectural truth of the generator itself.

The architectural truth lives in:
- [World Generation Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\world_generation_foundation.md)

## Rollout philosophy

The correct rollout principle is:

**stabilize geometry and continuity first, then enrich transitions, then expand content.**

Do not start by trying to define every final biome.
Do not start by adding rare zones before the base terrain logic reads well.
Do not start by overfitting one biome visually before the world foundation is coherent.

## Hard rollout rules

1. Large-scale continuity is more important than biome count.
2. Rivers and mountains must become readable before exotic content grows.
3. Local variation should reduce repetition before new top-level biome types are added.
4. Any expensive generation pass must remain in boot/background work only.
5. Data-driven biome/content extension is a success criterion, not a later luxury.

## Recommended iteration order

### Iteration 1 — Continuous world channels

Goal:
- establish global deterministic sampling

Deliverables:
- stable world channels such as height, temperature, moisture, ruggedness, flora density
- deterministic sampling by canonical world coordinates
- wrap-safe sampling on the accepted world topology

Success criteria:
- same seed and coordinates always produce the same channel values
- movement across chunk borders does not create channel seams

### Iteration 2 — Biome resolver foundation

Goal:
- stop thinking in random chunk biomes

Deliverables:
- data-driven biome resources
- deterministic resolver using channel values
- first resolver pass that can choose from a small biome set by score/conditions

Success criteria:
- adding a biome candidate no longer requires core generator surgery
- biome choice is explainable by world conditions, not chunk randomness

### Iteration 3 — Large terrain structures

Goal:
- make the world readable at distance

Deliverables:
- first mountain/ridge logic
- first river or water-flow logic
- ability for the biome resolver to see these structures as context

Success criteria:
- mountains read as ranges/ridges rather than noisy blobs
- rivers read as systems, not accidental blue lines

### Iteration 4 — Local variation layer

Goal:
- reduce repetition without multiplying main biomes

Deliverables:
- subzones such as sparse flora, dense flora, clearings, rocky patches, wet patches
- local modifiers that apply inside biome identity rather than replacing it

Success criteria:
- one biome can still produce several visually and tactically distinct local areas
- pressure to invent many fake "micro-biomes" is reduced

### Iteration 5 — Chunk content builder stabilization

Goal:
- turn world truth into streamed chunk output cleanly

Deliverables:
- chunk build pipeline separated from world truth
- terrain/content output based on sampler + resolver + local variation
- clear responsibility boundary between world truth and chunk materialization

Success criteria:
- chunk is only a build/cache/streaming container
- no chunk-local random identity replaces global world logic

### Iteration 6 — Flora and decor sets

Goal:
- give biomes and subzones visible life without collapsing architecture

Deliverables:
- flora-set resources
- decor-set resources
- data-driven assignment by biome and subzone

Success criteria:
- flora distribution reflects biome + local variation
- world identity expands through data, not generator branching

### Iteration 7 — Feature and POI hooks

Goal:
- open the system to authored or semi-authored points of interest

Deliverables:
- hook layer for feature injection
- compatibility between generated structure, biome context, and POI placement

Success criteria:
- POIs do not fight the base geography
- generation remains deterministic and composable

### Iteration 8 — Mod-facing extension layer

Goal:
- let external content safely plug into the world model

Deliverables:
- registration path for new `BiomeData`
- registration path for new flora/decor sets
- optional registration path for features

Success criteria:
- mods can extend the world without patching generator core

### Iteration 9 — Transition polish

Goal:
- improve visual and experiential continuity

Deliverables:
- ecotone refinement
- riverbank polish
- snowline or climate-edge polish
- readability improvements for long travel

Success criteria:
- transitions feel more natural without requiring architectural change

### Iteration 10 — Content growth

Goal:
- expand the world after the foundation is stable

Deliverables:
- more biomes
- more flora/resource patterns
- more rare zones
- more authored exceptions

Success criteria:
- content growth rides on the established architecture instead of destabilizing it

## Recommended MVP

The MVP should be small in content but complete in architectural direction.

Recommended MVP:
- channels: height, temperature, moisture, ruggedness, flora_density
- biome set: plains, foothills, mountains, wet lowland/floodplain, dry/scorched zone, cold zone
- large structures: at least one ridge system and one river system
- local variation: sparse flora, dense flora, clearing, rocky patch, wet patch
- topology: X-wrap, Y-latitude logic

This MVP is enough to prove:
- continuity
- readable large structures
- local variation
- extensibility path

## What not to do too early

Do not:
- define dozens of final biomes before the base structure works
- hardcode biome logic into core if/else chains
- attach all visual diversity directly to top-level biome identity
- chase full realism before achieving continuity and readability
- move expensive world generation work into gameplay-triggered code

## Performance execution note

World generation rollout must obey runtime law:
- heavy generation work belongs to boot/background
- chunk materialization must be streamable/staged
- player interaction must not trigger full world-side rebuild

See:
- [Performance Contracts](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\PERFORMANCE_CONTRACTS.md)

## Acceptance checkpoints

The rollout is on track only if the following become true in order:

1. Long-distance travel feels continuous.
2. Rivers and mountains are recognizable systems.
3. Biome transitions make sense.
4. Local variety exists without biome explosion.
5. Chunk borders do not define world identity.
6. New biome/content definitions can be added as data.

## Known failure modes

The rollout is off track if:
- each chunk looks like an isolated random postcard
- every new biome requires code surgery
- local diversity is missing, causing endless top-level biome growth
- generation gets tied to chunk-local randomness instead of world truth
- performance problems appear because rebuilds leak into interactive paths

## Source note

This rollout document was derived from:
- `M:\Downloads\fundament_procedural_world_generation_mirny.docx`

That external file should now be treated as a migration input, not the canonical execution home for this topic.
