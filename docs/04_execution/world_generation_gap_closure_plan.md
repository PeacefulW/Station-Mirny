---
title: World Generation Iteration 1-6 Status Review
doc_type: execution_plan
status: draft
owner: engineering+design
source_of_truth: false
version: 0.2
last_updated: 2026-03-27
related_docs:
  - MASTER_ROADMAP.md
  - world_generation_rollout.md
  - ../00_governance/DOCUMENT_PRECEDENCE.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../00_governance/PROJECT_GLOSSARY.md
  - ../02_system_specs/world/world_generation_foundation.md
  - ../02_system_specs/meta/modding_extension_contracts.md
  - ../03_content_bible/resources/flora_and_resources.md
  - ../05_adrs/0002-wrap-world-is-cylindrical.md
---

# World Generation Iteration 1-6 Status Review

This document replaces the earlier pre-`Iteration 6` gap framing.

It is a current-state audit of the shipped world-generation rollout through `Iteration 6`, based on:
- current code
- rollout/spec docs
- discussion notes from the 2026-03-27 audit pass
- a local launch log captured after the `Iteration 6` implementation landed

It does not change rollout order or architectural truth.

It exists to answer one practical question:
- what is actually done through `Iteration 6`
- what is only partial
- what is actively broken at runtime
- what must be closed before the foundation can be treated as ready for `Iteration 7+`

## 2026-03-27 Execution Progress Note

Implemented in the current correction pass:
- shipped flora/decor resources now load cleanly at startup again
- sync and async surface chunk paths now both carry flora/decor placement inputs
- surface terrain truth was moved out of `ChunkContentBuilder` into detached compute/resolver code, so the builder is back to chunk materialization work
- biome explainability payloads now carry real channel/structure score evidence
- surface payload caching, queue compaction, and non-spinning async polling now remove the earlier route-return generation backlog
- chunk flora redraw now uses tile-local placement lookup instead of scanning the full placement list per tile
- headless runtime validation now completes room, power, mining, chunk-persistence, and the full `6/6` route with `exit code 0`; catch-up closure now treats `streaming_truth` and `topology` as blockers while logging redraw-only tail as residual background work

Still open after this pass:
- route drain can still finish with a redraw-only backlog, so visual catch-up is still slower than ideal
- a perf contract overrun still appears in `ChunkManager.try_harvest_at_world()` in the current validation path
- wider geography/readability tuning should continue after the current runtime-stability closure

## Scope

This review stops at `Iteration 6`.

Out of scope:
- `Iteration 7` POI/feature hooks
- `Iteration 8` mod-facing extension closure
- late content growth beyond the current MVP biome/flora/decor set
- full resource catalog expansion

## Documentation Compliance Rule

All work sequenced under this document must remain subordinate to the canonical docs.

Hard rule:
- this file is an execution/status layer
- it may decompose or reprioritize follow-up work
- it may not override governance, ADRs, or system specs
- if the implementation and docs disagree, higher-precedence docs win
- if the docs are stale, fix the docs explicitly rather than silently treating execution notes as the new truth

## What changed since v0.1

The old version of this task is no longer accurate in three major ways:
- `Iteration 6` is not "not started"; the flora/decor architecture exists in code
- flora identity is no longer the main gap; the immediate problem is runtime loadability and load-path parity
- the review question is no longer "can we start `Iteration 6`?" but "what remains open after landing through `Iteration 6`?"

At the same time, some earlier concerns remain valid:
- large-structure wrap continuity is still not fully closed
- chunk materialization still owns part of world truth
- resolver explainability is still scaffolded but not finished
- docs are still stale against current implementation

## Current verdict

Current rollout state:
- `Iteration 1`: done
- `Iteration 2`: done as foundation, partial on explainability/debug evidence
- `Iteration 3`: implemented, not closed
- `Iteration 4`: MVP implemented, not closed
- `Iteration 5`: partial, not closed
- `Iteration 6`: implemented as MVP architecture, runtime-stable in validation, but not closed

Practical conclusion:
- do not reopen `Iteration 6` as greenfield work
- do not pretend `Iteration 6` is fully closed either
- the next work should close the concrete open issues below so the foundation is honest and stable before `Iteration 7+`

## Iteration-by-iteration status

### Iteration 1 — Continuous world channels

Status:
- done

What is true now:
- `PlanetSampler` samples `height`, `temperature`, `moisture`, `ruggedness`, and `flora_density`
- channel sampling uses periodic X-wrap via `WorldNoiseUtils`
- `WorldGenerator` exposes canonical tile/chunk/world helpers and routes sampling through canonical coordinates

Why this counts as done:
- deterministic world channels exist
- X-wrap is implemented at the channel layer
- chunk borders do not define channel identity

### Iteration 2 — Biome resolver foundation

Status:
- done as foundation
- partial on explainability closeout

What is true now:
- biomes are real `.tres` resources under `data/biomes/`
- `BiomeRegistry` loads biome resources without hardcoded biome branches
- `BiomeResolver` is deterministic and uses channel plus structure ranges/weights from `BiomeData`

What remains open:
- `BiomeResult.channel_scores` and `structure_scores` still receive empty dictionaries from `BiomeResolver`
- the rollout success criterion "biome choice is explainable by world conditions" is only partially met in runtime/debug terms

### Iteration 3 — Large terrain structures

Status:
- implemented
- not closed

What is true now:
- `LargeStructureSampler` exists and outputs mountain mass, ridge strength, river strength, and floodplain strength
- structure context is visible to biome resolution and tile generation
- debug/preview tooling already renders structure fields

What remains open:
- structure wrap continuity is not fully closed at the band phase level
- current geography still reads more like directional prototype bands than fully convincing systems

### Iteration 4 — Local variation layer

Status:
- MVP implemented
- not closed

What is true now:
- the five expected variation kinds exist
- variation sampling is seeded, periodic, and balance-driven for frequency/octaves/min score
- variation ids propagate into chunk output
- `flora_density` and `flora_modulation` already influence `ChunkFloraBuilder`

What remains open:
- `wetness_modulation`, `rockiness_modulation`, and `openness_modulation` are computed but still barely consumed downstream
- the subzone contract is materially better than v0.1 assumed, but still not fully leveraged

### Iteration 5 — Chunk content builder stabilization

Status:
- partial
- not closed

What is true now:
- there is a clear build pipeline: samplers/resolvers feed chunk content output
- chunk build output is separate from `Chunk` scene-node materialization

What remains open:
- `ChunkContentBuilder` still owns private mountain noise and uses it in terrain classification
- `WorldGenerator.get_terrain_type_fast()` still routes world-truth queries through builder logic
- the world-truth vs materialization boundary is still muddy

### Iteration 6 — Flora and decor sets

Status:
- implemented as MVP architecture
- runtime-stable in the current headless validation pass
- not closed

What is true now:
- `FloraSetData`, `DecorSetData`, `FloraDecorRegistry`, `ChunkFloraBuilder`, and `ChunkFloraResult` exist
- biomes already reference flora/decor set ids
- flora/decor resources exist under `data/flora/` and `data/decor/`
- shipped flora/decor entries and sets load cleanly at startup again
- sync and async surface chunk loading both compute equivalent flora/decor placements from the same deterministic inputs
- `Chunk` redraw renders placeholder flora/decor and now uses tile-local flora lookup instead of scanning all placements for every tile

What remains open:
- redraw-only visual backlog can remain after long route completion even when streaming truth and topology are already caught up
- flora/decor presentation is still placeholder-level and should be improved later as a quality/content pass

## Confirmed current issues

### Issue A: large-structure wrap seam is still open

Current problem:
- structure noise warp is periodic
- but the actual ridge/river band phase is still computed via `_directed_coordinate(...)` plus `_sample_repeating_band(..., spacing, ...)`
- that band phase repeats by `ridge_spacing_tiles` and `river_spacing_tiles`, not by the world wrap width

Why this matters:
- channel wrap continuity is not enough if structure truth itself shifts at the X seam
- `Iteration 3` cannot be considered fully closed while ridges/rivers remain mathematically seam-sensitive

Concrete evidence:
- `core/systems/world/large_structure_sampler.gd`
- `core/systems/world/world_noise_utils.gd`
- `data/world/world_gen_balance.gd`

Concrete proof on current constants:
- ridge X-wrap phase shift is not an integer multiple of ridge spacing
- river X-wrap phase shift is not an integer multiple of river spacing
- direct formula check on the current values gives:
  - ridge band at `y=0`: `x=0 -> 1.0`, `x=4095 -> 0.046`
  - river band at `y=0`: `x=0 -> 1.0`, `x=4095 -> 0.481`

Definition of done:
- band phase itself becomes wrap-safe
- or the structure model is reformulated so structure truth is seam-stable at X-wrap

### Issue B: large-structure readability is still prototype-grade

Current problem:
- ridges and rivers now exist as explicit systems
- but the current output still reads mostly like warped directional bands
- mountain surface classification still receives help from builder-private blob/detail noise

Why this matters:
- `Iteration 3` is not only about having structure channels
- it is about the world reading as readable geography at distance

Concrete evidence:
- `core/systems/world/large_structure_sampler.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/debug/world_preview_exporter.gd`

Definition of done:
- mountains read primarily from structural logic, not blob accidents
- rivers read as coherent systems in preview/debug, not repeated band artifacts

### Issue C: biome explainability is still scaffold-only

Current problem:
- `BiomeResult` already has `channel_scores` and `structure_scores`
- `BiomeData` already knows how to compute resolver scores
- `BiomeResolver` still writes empty dictionaries into the result

Why this matters:
- `Iteration 2` is functionally there
- but its explainability success criterion is not honestly closed

Concrete evidence:
- `core/systems/world/biome_resolver.gd`
- `core/systems/world/biome_result.gd`
- `data/biomes/biome_data.gd`

Definition of done:
- resolved biome results carry non-empty score evidence
- debug can answer "why did this biome win here?" without reverse-engineering code

### Issue D: local variation downstream contract is only partially consumed

Current problem:
- local variation is no longer "visual only"
- but in practice the strongest downstream consumers are still:
  - variation id
  - flora density
  - flora modulation
- the other modulation channels mostly stop at `TileGenData`

Why this matters:
- `Iteration 4` is now beyond a pure prototype
- but it still does not deliver a fully exploited biome-plus-subzone contract

Concrete evidence:
- `core/systems/world/local_variation_resolver.gd`
- `core/systems/world/local_variation_context.gd`
- `core/systems/world/tile_gen_data.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk_flora_builder.gd`

Definition of done:
- downstream systems consume more than just a flat variation id and one flora modulation
- subzone identity affects more than placeholder surface variety

### Issue E: chunk builder still owns part of world truth

Current problem:
- `ChunkContentBuilder` still owns `_mountain_blob_noise` and `_mountain_detail_noise`
- `_is_mountain_tile()` still uses those private noises to classify terrain
- `WorldGenerator.get_terrain_type_fast()` still routes world-truth queries through builder logic

Why this matters:
- `Iteration 5` requires the chunk builder to be a materialization/cache step
- the builder should not be an invisible co-owner of terrain truth

Concrete evidence:
- `core/systems/world/chunk_content_builder.gd`
- `core/autoloads/world_generator.gd`

Definition of done:
- builder consumes upstream world truth rather than inventing part of it locally
- terrain truth no longer lives partly in materialization code

### Issue F: Iteration 6 runtime resource load failures

Status:
- resolved in the current correction pass

Current state:
- shipped flora and decor entry resources now parse cleanly at startup
- dependent flora/decor sets load again
- `FloraDecorRegistry` starts with usable base sets instead of missing content

Definition of done:
- met for runtime loadability

### Issue G: async streaming path drops flora placement

Status:
- resolved in the current correction pass

Current state:
- sync and async surface chunk loading now both preserve the flora/decor inputs needed by `ChunkFloraBuilder`
- surface payload caching and staged creation reuse the same deterministic native payload + flora result path
- `Iteration 6` no longer changes behavior based on whether a chunk arrived through sync boot load or async streaming

Definition of done:
- met for load-path parity

### Issue H: documentation is still stale against current code

Current problem:
- `PROJECT_GLOSSARY.md` still says key worldgen pieces are not implemented or not enforced
- `world_generation_rollout.md` still reads as a rollout order document only and has no current-state overlay through `Iteration 6`
- the previous version of this task itself had stale assumptions

Why this matters:
- the code has moved
- without docs sync, the next executor starts from false premises

Concrete evidence:
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `docs/04_execution/world_generation_rollout.md`
- this file

Definition of done:
- docs tell the truth about what exists, what is partial, and what is broken

## What is explicitly no longer treated as a blocker from v0.1

These older assumptions should not drive new work anymore:
- flora/decor architecture is not missing
- `Iteration 6` should not be restarted from scratch
- flora identity is not the main failure mode for this review
- resource-node breadth remains thin, but that is a later content-growth concern, not the core `Iteration 1-6` closure blocker
- chunk-edge invalidation is currently better framed as a runtime test-risk than as the main architectural blocker for this task

## Revised work order

1. Close the `Iteration 5` world-truth vs materialization boundary.
2. Close the remaining runtime tail: redraw backlog and the last `ChunkManager.try_harvest_at_world()` overrun.
3. Close the `Iteration 3` wrap seam at the structure phase level.
4. Improve `Iteration 3` readability from prototype bands toward readable systems.
5. Finish `Iteration 2` explainability and `Iteration 4` downstream contract closure.
6. Sync rollout/glossary/status docs after the code truth is stable.

## Task breakdown

### T0: repair shipped Iteration 6 resources

Goal:
- make the shipped flora/decor content load cleanly at runtime

Status:
- done in the current correction pass

In scope:
- fix parse-invalid entry resources
- verify dependent flora/decor sets resolve cleanly
- confirm `FloraDecorRegistry` actually registers the base sets

Likely files:
- `data/flora/entries/*.tres`
- `data/decor/entries/*.tres`
- `data/flora/*.tres`
- `data/decor/*.tres`
- optionally a tiny runtime validation hook if needed

### T1: make Iteration 6 load-path behavior consistent

Goal:
- remove sync/async divergence in flora/decor placement

Status:
- done in the current correction pass

In scope:
- either carry the needed flora data through `to_native_data()`
- or compute placements in staged loading with the same truth inputs used by sync loading

Likely files:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk_build_result.gd`
- `core/systems/world/chunk_flora_builder.gd`

### T2: close the Iteration 5 truth boundary

Goal:
- remove builder-private mountain truth

In scope:
- move mountain truth ownership out of `ChunkContentBuilder`
- keep builder focused on materialization

Likely files:
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_content_builder.gd`
- possibly `core/systems/world/large_structure_sampler.gd`

### T3: close the Iteration 3 seam

Goal:
- make large-structure truth obey the same cylindrical wrap contract as channels

In scope:
- ridge/river continuity at X-wrap
- validation around the seam

Likely files:
- `core/systems/world/large_structure_sampler.gd`
- `data/world/world_gen_balance.gd`
- debug preview/export tooling

### T4: close Iteration 3 readability

Goal:
- move from prototype bands to readable geography

In scope:
- ridge readability
- river readability
- reducing dependence on non-structural blob support

Likely files:
- `core/systems/world/large_structure_sampler.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/debug/world_preview_exporter.gd`

### T5: finish Iteration 2 and 4 closeout work

Goal:
- close the low-risk but still open quality seams

In scope:
- biome explainability output
- stronger downstream use of local-variation modulation

Likely files:
- `core/systems/world/biome_resolver.gd`
- `core/systems/world/biome_result.gd`
- `core/systems/world/local_variation_resolver.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk_flora_builder.gd`

### T6: sync the docs

Goal:
- make the written rollout state match the actual code state through `Iteration 6`

In scope:
- glossary cleanup
- rollout status overlay
- keep this task aligned with the corrected baseline

Likely files:
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `docs/04_execution/world_generation_rollout.md`
- this file

## Immediate next action

The next correct step is not another broad re-audit.

It is:
- finish the remaining runtime tail around redraw backlog and `ChunkManager.try_harvest_at_world()`
- then close the structural truth debts in `Iteration 5` and `Iteration 3`
- then continue the geography/readability quality pass on top of the stabilized runtime path

Until those are done, the honest status of the worldgen rollout through `Iteration 6` is:
- materially progressed
- architecturally promising
- already beyond prototype in several layers
- not yet cleanly closed
