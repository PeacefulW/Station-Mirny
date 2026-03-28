---
title: World Feature and POI Hooks
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-03-28
depends_on:
  - world_generation_foundation.md
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
related_docs:
  - world_generation_foundation.md
  - ../../04_execution/world_generation_rollout.md
  - ../../00_governance/WORKFLOW.md
---

# World Feature and POI Hooks

## Design Intent

This spec defines the first feature-specific implementation plan for rollout Iteration 7: `Feature and POI hooks`.

The goal is to let the world gain authored or semi-authored landmarks without breaking the existing world-generation foundation:

- world truth still comes from deterministic sampling at canonical world coordinates
- chunk remains a build/materialization unit, not the source of geography truth
- feature and POI selection remain data-driven
- chunk borders and load order must not decide what exists in the world

Player-facing intent:

- the world can contain memorable authored structures or landmark-like locations
- those locations still fit the underlying geography instead of fighting it
- the result remains deterministic and composable for a given seed

## Scope

This spec owns:

- feature-hook definitions for generator-side eligibility
- POI definitions for authored or semi-authored placement rules
- deterministic hook and placement arbitration from existing generator context
- chunk-build payload integration for feature and POI placement records
- a minimal end-to-end proof path

This spec does not own:

- mod-facing external registration workflow or extension API
- large content catalog growth
- quest/story/NPC scripting
- runtime mining/topology/reveal behavior
- new terrain semantics
- hand-placed narrative locations outside deterministic world generation

## Non-Goals

- Do not create a parallel world-generation architecture.
- Do not turn chunk-local state into world truth.
- Do not introduce runtime-only randomness for world placement.
- Do not solve Iteration 8 `Mod-facing extension layer` here.
- Do not solve Iteration 10 `Content growth` here.

## Terms

`feature hook`
- A deterministic generator-side opportunity or eligibility result derived from existing world context.

`POI definition`
- A data-authored template with placement constraints, anchor rules, and optional footprint/spacing constraints.

`anchor tile`
- The canonical world tile that owns the final placement decision for a feature or POI.

`placement payload`
- Derived chunk-build output that records selected feature or POI placements for materialization or debug consumption.

## Data Contracts — New And Affected

### New Layer: Feature And POI Definition Catalog

- `classification`: `canonical`
- `what`: data-authored definitions for feature hooks and POI templates
- `where`: resource definitions loaded through a registry
- `owner`: `WorldFeatureRegistry`
- `writers`:
  - authored `.tres` resources
  - registry boot/load path
- `readers`:
  - generator-side feature hook resolver
  - generator-side POI resolver
  - future debug/materialization consumers
- `invariants`:
  - `assert(id != &"")`
  - `assert(ids are stable and namespaced)`
  - `assert(definitions are read-only during runtime gameplay)`
  - `assert(definitions do not depend on chunk-local randomness)`
- `write operations`:
  - boot-time registry load
  - authoring or editing data resources
- `forbidden writes`:
  - `Chunk`, `ChunkManager`, or presentation systems mutating feature/POI definitions at runtime
  - generator gameplay code loading feature/POI content by hardcoded `res://` path outside the registry
- `emitted events / invalidation`:
  - boot-time registry readiness only
  - no runtime mutation signal in Iteration 7 baseline

### New Layer: Feature Hook Decisions

- `classification`: `derived`
- `what`: deterministic hook eligibility/candidate results computed from canonical generator context
- `where`: generator-side resolver output consumed during chunk build
- `owner`: `WorldGenerator` generation pipeline
- `writers`:
  - `WorldFeatureHookResolver` compute path only
- `readers`:
  - `WorldPoiResolver`
  - `ChunkContentBuilder`
  - future debug inspectors
- `invariants`:
  - `assert(same_seed_and_anchor_tile => same hook decision set)`
  - `assert(hook decisions depend only on canonical generator context plus definition catalog)`
  - `assert(hook decisions do not mutate terrain, biome, structure, or local variation answers)`
  - `assert(hook decisions are invariant across chunk-boundary evaluation)`
- `write operations`:
  - unloaded generator build/read path
  - worker-safe compute phase during chunk payload generation
- `forbidden writes`:
  - direct writes from `Chunk`, `ChunkManager`, mining, topology, reveal, or presentation systems
  - runtime RNG or load-order-dependent mutation
- `emitted events / invalidation`:
  - none as a standalone signal in the baseline
  - recompute piggybacks on chunk build requests
- `rebuild policy`:
  - deterministic on-demand recompute during chunk build
  - not a persisted truth layer

### New Layer: POI Placement Decisions

- `classification`: `derived`
- `what`: deterministic final placement/arbitration results computed from feature hook decisions plus POI definitions
- `where`: generator-side resolver output included in chunk build payload
- `owner`: `WorldGenerator` generation pipeline
- `writers`:
  - `WorldPoiResolver` compute path only
- `readers`:
  - `ChunkContentBuilder`
  - future spawn/materialization or debug consumers
- `invariants`:
  - `assert(each canonical anchor produces zero or one resolved placement per exclusive slot)`
  - `assert(placement acceptance validates biome, structure, terrain, and footprint constraints before selection)`
  - `assert(multi_chunk_poi_ownership is decided by canonical anchor, not load order)`
  - `assert(poi placement is not authoritative terrain or walkability truth)`
- `write operations`:
  - unloaded generator build/read path
  - chunk payload construction
- `forbidden writes`:
  - mutation from loaded-chunk presentation
  - using loaded runtime diffs as hidden inputs to unloaded placement truth
  - direct scene-tree spawn as the selection mechanism
- `emitted events / invalidation`:
  - none in baseline
  - placement is rebuilt from deterministic inputs when chunk payload is rebuilt
- `rebuild policy`:
  - deterministic on-demand recompute during chunk build
  - not a persisted authored runtime layer

### Affected Layer: World

- `classification`: `canonical`
- `what changes`:
  - feature and POI systems become new readers of canonical generator context
- `owner`:
  - unchanged from [World Data Contracts](DATA_CONTRACTS.md)
- `writers`:
  - unchanged
- `readers`:
  - existing readers plus feature hook and POI resolvers
- `invariants`:
  - `assert(feature and POI hooks do not redefine terrain semantics)`
  - `assert(canonical terrain, structure, biome, and local variation remain the source of truth for placement inputs)`
- `write operations`:
  - unchanged
- `forbidden writes`:
  - feature and POI systems must not mutate canonical terrain, structure context, biome result, or local variation
- `what does not change`:
  - mining
  - topology
  - reveal
  - walkability rules
  - generator terrain classification

### Affected Layer: Presentation / Chunk Materialization

- `classification`: `presentation-only`
- `what changes`:
  - chunk build output may gain feature and POI placement records or placeholder markers
- `owner`:
  - existing chunk build/materialization path
- `writers`:
  - `ChunkContentBuilder`
  - `ChunkBuildResult`
  - optional minimal debug/materialization consumer
- `readers`:
  - `Chunk`
  - future POI materialization/spawn consumers
  - debug tooling
- `invariants`:
  - `assert(feature_or_poi_materialization never becomes source_of_truth for placement semantics)`
  - `assert(presentation may be delayed or absent without changing placement truth)`
- `write operations`:
  - build payload assembly
  - optional debug/presentation apply
- `forbidden writes`:
  - presentation layer must not mutate canonical feature or POI decisions
  - presentation layer must not back-write terrain state
- `what does not change`:
  - shadow/reveal contracts
  - mining contracts
  - topology ownership

## Source Of Truth Vs Derived / Materialized State

`source of truth`

- world seed
- canonical world coordinates
- world channels
- structure context
- biome resolution
- local variation
- feature and POI definitions loaded through registry

`derived state`

- feature hook candidate sets
- POI arbitration results
- chunk-scoped placement payload

`materialized / presentation-only state`

- any debug marker
- any spawned node or overlay
- any placeholder visual created from placement payload

`explicit non-source-of-truth rules`

- chunk-local load order must not affect feature or POI selection
- a loaded chunk must not author new canonical POI truth by itself
- presentation absence or delay must not change generator answers

## Deterministic Placement Expectations

- Determinism key is `seed + canonical world coordinates + stable definitions`.
- Feature and POI selection must use deterministic hashing by world position where tie-breaking or weighted choice is needed.
- Runtime RNG must not influence placement truth.
- The same canonical anchor tile must yield the same placement answer regardless of who asks:
  - direct generator query
  - sync chunk build
  - worker/native chunk build

## Chunk Boundary Rules

- Evaluation keys must use canonical world coordinates or canonical anchor tiles, never local chunk coordinates.
- A feature or POI that spans multiple chunks must be selected once by the chunk that owns the anchor tile.
- Neighbor chunks may materialize the footprint, but they do not re-arbitrate ownership.
- Chunk border loading order must not duplicate, suppress, or replace a placement.
- East-west wrap behavior must remain seamless on the accepted cylindrical topology.
- If a placement cannot validate its required footprint deterministically from canonical generator context, it must be rejected or deferred. It must not guess from partial loaded state.

## Loaded Vs Unloaded Read Rules

- Unloaded surface read path must be sufficient to compute feature hook and POI placement truth.
- Loaded chunk presentation may consume placement payload, but it must not become the source of that payload.
- Iteration 7 baseline does not allow feature or POI truth to depend on loaded-world runtime diffs.
- If a future POI type requires loaded-world or runtime-diff awareness, that is a separate contract change and is out of scope here.

## Feature Hooks Vs POI Placement Hooks

`feature hooks`

- derive eligibility from world channels, structure context, biome, and local variation
- do not select final authored content by themselves
- do not mutate terrain or chunk output directly

`POI placement hooks`

- consume feature hook results plus POI definitions
- perform deterministic arbitration, anchor ownership, and compatibility checks
- output final derived placement records for chunk build integration

`generator-side world truth`

- sampled and resolved world context
- feature and POI definitions
- deterministic placement decisions

`chunk materialization / presentation only`

- placement payload forwarding
- debug or placeholder markers
- future spawned POI visuals or scene instances

## Implementation Iterations

### Iteration 7.1 — Definition Resources And Registry Baseline

Goal:
- introduce content definitions and registry access for features and POIs without touching terrain semantics

What is done:

- add `FeatureHookData` resource type
- add `PoiDefinition` resource type
- add `WorldFeatureRegistry` for boot-time loading of base definitions
- add minimal base definitions used for implementation and tests
- do not add placement logic yet

Acceptance tests:

- [ ] `assert(WorldFeatureRegistry.get_feature_by_id(&"base:test_feature") != null)` — feature definitions resolve through the registry
- [ ] `assert(WorldFeatureRegistry.get_poi_by_id(&"base:test_poi") != null)` — POI definitions resolve through the registry
- [ ] `assert(WorldFeatureRegistry.get_all_feature_hooks().size() >= 1)` — at least one base feature definition loads
- [ ] `assert(WorldFeatureRegistry.get_all_pois().size() >= 1)` — at least one base POI definition loads
- [ ] Manual review: generator gameplay code does not direct-`load()` feature or POI resources outside the registry

Files that will be touched:

- `core/autoloads/world_feature_registry.gd`
- `data/world/features/feature_hook_data.gd`
- `data/world/features/poi_definition.gd`
- `data/world/features/*.tres`
- `project.godot` only if autoload registration is needed

Files that must not be touched:

- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk_build_result.gd`
- mining/topology/reveal/presentation runtime files

### Iteration 7.2 — Deterministic Feature Hook Resolver

Goal:
- derive feature-hook opportunities from canonical generator context only

What is done:

- add a generator-side resolver that reads existing channels, structure context, biome result, and local variation
- compute deterministic feature-hook candidate results keyed by canonical anchor tile
- keep output detached from presentation and chunk-local identity
- do not select final POIs yet

Acceptance tests:

- [ ] `assert(resolve_feature_hooks(seed, anchor_tile) == resolve_feature_hooks(seed, anchor_tile))` — repeated evaluation is stable
- [ ] `assert(resolve_feature_hooks(seed, anchor_tile) is identical when requested from neighboring chunk builds)` — chunk borders do not change the answer
- [ ] `assert(feature_hook_compute does not modify terrain, structure, biome, or local_variation outputs)` — canonical inputs remain read-only
- [ ] Manual verification: same seed and same canonical anchor tile produce stable hook ids and scores across repeated runs

Files that will be touched:

- `core/systems/world/world_feature_hook_resolver.gd`
- `core/autoloads/world_generator.gd`
- `core/systems/world/world_compute_context.gd` only if feature-resolver wiring is needed

Files that must not be touched:

- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_manager.gd`
- mining/topology/reveal systems

### Iteration 7.3 — POI Arbitration And Anchor Ownership

Goal:
- deterministically select POI placements that respect geography and chunk borders

What is done:

- add a POI resolver consuming feature-hook candidates plus POI definitions
- define canonical anchor ownership
- define spacing, conflict, and footprint eligibility rules
- reject placements that fail biome, structure, terrain, or footprint constraints
- keep result generator-side derived state

Acceptance tests:

- [ ] `assert(each exclusive anchor or slot resolves to at most one final POI placement)` — arbitration is unambiguous
- [ ] `assert(a multi_chunk_poi is selected once by canonical anchor ownership, independent of chunk load order)` — border-safe ownership
- [ ] `assert(pois_with_unmet_constraints are rejected deterministically)` — geography compatibility is enforced
- [ ] `assert(poi_arbitration uses deterministic hashing by world position and no runtime RNG)` — deterministic placement only

Files that will be touched:

- `core/systems/world/world_poi_resolver.gd`
- `data/world/features/poi_definition.gd`
- `core/autoloads/world_generator.gd`

Files that must not be touched:

- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_manager.gd`
- runtime reveal/topology/mining code

### Iteration 7.4 — Chunk Build Payload Integration

Goal:
- expose deterministic feature and POI results through existing chunk build outputs without making chunk the source of truth

What is done:

- extend `ChunkBuildResult` payload with feature and POI placement records
- extend `build_chunk_content()` and `build_chunk_native_data()` outputs to carry the same placement truth
- wire `ChunkContentBuilder` and `WorldGenerator` to include the derived placement payload
- maintain sync and worker/native parity for payload generation
- do not add full gameplay/entity materialization yet

Acceptance tests:

- [ ] `assert(build_chunk_content(coord) and build_chunk_native_data(coord) carry equivalent feature_and_poi placement data)` — sync/native parity
- [ ] `assert(feature_and_poi payload is deterministic for the same seed and canonical chunk coord)` — stable build output
- [ ] `assert(base terrain, height, variation, and biome answers remain unchanged by feature_and_poi payload integration)` — canonical world semantics stay intact
- [ ] Manual verification: a chunk containing a test anchor exposes the same placement payload whether built synchronously or through the worker/native path

Files that will be touched:

- `core/systems/world/chunk_build_result.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_manager.gd` only if staged or worker payload forwarding requires it

Files that must not be touched:

- `core/systems/world/chunk.gd` except optional debug proof consumer
- mining/topology/reveal runtime code
- presentation/shadow systems

### Iteration 7.5 — Minimal End-To-End Proof And Contract Sync

Goal:
- prove the hook layer end-to-end without expanding into full content growth or gameplay systems

What is done:

- add one minimal non-authoritative debug or placeholder materialization consumer for selected placements
- update `DATA_CONTRACTS.md` with the new derived layers and boundary rules
- update `PUBLIC_API.md` only for the final safe registry/build entrypoints
- do not add full quest, story, or entity systems

Acceptance tests:

- [ ] `assert(a test feature_or_poi placement can be observed through a debug or placeholder consumer without mutating canonical terrain state)` — end-to-end proof
- [ ] `assert(disabling or delaying presentation does not change placement truth)` — presentation is not authoritative
- [ ] `assert(DATA_CONTRACTS.md and PUBLIC_API.md document owner, writers, readers, invariants, forbidden writes, and safe entrypoints)` — contract sync complete
- [ ] Manual review: no parallel public API path exists for feature or POI placement generation

Files that will be touched:

- `core/systems/world/chunk.gd` or a dedicated debug consumer only if needed for proof
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`
- implementation files from previous iterations only as needed

Files that must not be touched:

- modding extension docs or APIs
- content-growth files beyond one minimal proof definition
- unrelated runtime systems

## Out Of Scope / Deferred

Deferred to Iteration 8:

- mod-facing external registration workflow
- plugin/mod packaging rules for feature or POI content
- hot-reload or override semantics for external feature packs

Deferred to Iteration 10:

- large POI catalog growth
- biome-specific authored landmark breadth
- broad content expansion for rare zones, loot patterns, or special resource clusters

Separate future specs:

- quest-linked or story-authored POIs
- NPC, loot, combat, or encounter population inside POIs
- runtime destruction, depletion, or player-authored mutation of generated POIs

## Proposed DATA_CONTRACTS.md Deltas

Do not apply in this Phase B task. Apply only during implementation iterations that actually introduce these contracts.

Proposed additions:

- add `Feature Hooks` derived layer between canonical world truth and chunk materialization
- add `POI Placement` derived layer, or document it as a named sublayer of `Feature Hooks` if implementation stays tightly coupled
- update `Current Source Of Truth Summary` to state that feature and POI truth are derived from canonical generator context and definitions, not from chunk-local presentation
- add loaded vs unloaded read rules for feature and POI placement payloads
- add chunk-boundary ownership rules for multi-chunk placements and X-wrap behavior
- add postconditions for `build_chunk_content()` / `build_chunk_native_data()` once placement payload is part of the contract

## Proposed PUBLIC_API.md Deltas

Do not apply in this Phase B task. Apply only during implementation iterations that introduce these public surfaces.

Preferred public API shape:

- add safe registry reads:
  - `WorldFeatureRegistry.get_feature_by_id(id: StringName) -> FeatureHookData`
  - `WorldFeatureRegistry.get_all_feature_hooks() -> Array`
  - `WorldFeatureRegistry.get_poi_by_id(id: StringName) -> PoiDefinition`
  - `WorldFeatureRegistry.get_all_pois() -> Array`
- keep `WorldGenerator.build_chunk_content()` and `WorldGenerator.build_chunk_native_data()` as the canonical chunk-build entrypoints
- extend existing build outputs instead of adding a parallel `generate_feature_chunk()` or `generate_poi_chunk()` public API
- if future tooling needs a dedicated inspection API, it should be read-only and added explicitly after contract review

## Closure Report

### Implemented

- Created a new Iteration 7 feature spec at `docs/02_system_specs/world/world_feature_and_poi_hooks.md`
- Decomposed rollout Iteration 7 into five implementation iterations
- Defined proposed new and affected data layers, with owner/writer/reader/invariant/forbidden-write fields
- Documented source-of-truth vs derived/materialized boundaries, deterministic expectations, loaded vs unloaded rules, and chunk-boundary rules
- Added proposed `DATA_CONTRACTS.md` and `PUBLIC_API.md` deltas without applying them

### Root Cause

- Rollout Iteration 7 existed only as a high-level execution line item in `world_generation_rollout.md`
- By `WORKFLOW.md`, code work must not start before a feature spec exists

### Files Changed

- `docs/02_system_specs/world/world_feature_and_poi_hooks.md` — new feature spec for `Feature and POI hooks`

### Acceptance Tests

- [x] `docs/02_system_specs/world/world_feature_and_poi_hooks.md` created
- [x] Rollout Iteration 7 decomposed into concrete sub-iterations
- [x] Each sub-iteration includes explicit acceptance tests
- [x] Affected data layers, owners, writers, readers, invariants, and forbidden actions are documented
- [x] Source of truth vs derived/materialized state is documented
- [x] Spec stays out of Iteration 8 mod-facing design and Iteration 10 content growth except for explicit defer notes
- [x] Proposed contract/API deltas are listed without being applied

### Out Of Scope Observations

- `world_generation_foundation.md` still marks the exact final POI hook layer as an open question; this spec narrows implementation sequencing but does not claim the question is globally closed
- No runtime code, `DATA_CONTRACTS.md`, or `PUBLIC_API.md` changes are applied in this Phase B task

### Remaining Blockers

- Human review and approval of this spec are required before any Iteration 7 implementation work
- Concrete runtime file choices may need adjustment during implementation if existing safe extension points differ, but the contract boundaries in this spec should remain stable

### DATA_CONTRACTS.md Updated

- not required in this Phase B task
