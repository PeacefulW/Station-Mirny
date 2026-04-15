---
title: Dual-Granularity Frontier Runtime
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-15
depends_on:
  - zero_tolerance_chunk_readiness_spec.md
  - frontier_native_runtime_architecture_spec.md
  - zero_tolerance_chunk_readiness_legacy_delete_list.md
  - DATA_CONTRACTS.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
related_docs:
  - ../../04_execution/frontier_native_runtime_execution_plan.md
---

# Feature: Dual-Granularity Frontier Runtime

## Why this spec exists

After implementing underground transition work, runtime behavior now shows a more important architectural signal than any single optimization pass:

- staircase transition wait is too long
- underground entry waits on too much world at once
- surface and underground preparation still appear to be dominated by chunk-sized readiness assumptions

This is a design smell.

The zero-tolerance contract is still correct:

- the player must never see or enter incomplete world
- `full_ready` still means fully finished, including flora and cosmetics

What is now under challenge is not the contract, but the granularity of runtime preparation and publication.

## Decision

Do **not** continue blindly to `R9` on the assumption that the current chunk-granular runtime is fundamentally correct and only needs tuning.

Instead, the architecture is amended as follows:

- chunks are no longer assumed to be the only practical unit of runtime preparation and reveal
- the runtime is split into two different granularities
- coarse units exist for determinism, storage, caching, and ownership
- fine units exist for near-player reveal, publication, and transition latency control

This is a pivot in runtime granularity, not a retreat from the zero-tolerance readiness contract.

## Core principle

**Storage granularity and reveal granularity are not the same thing.**

The old mental trap is:

- if the world is chunk-based, the player must wait for chunk-sized work

This spec rejects that assumption.

The new mental model is:

- macro units own world truth, residency, save keys, and large-scale generation
- micro units own what is allowed to become visible or occupiable right now

## Runtime units

### 1. Macro unit

A macro unit is the coarse world ownership unit.

Responsibilities:

- deterministic world indexing
- save/load ownership
- residency/caching ownership
- feature/POI authority ownership
- large-scale terrain and structure context
- cross-page seam ownership

A macro unit may still be a chunk, or it may become a different coarse unit after chunk-size bake-off.

The macro unit is **not** automatically the reveal unit.

### 2. Micro publication unit

A micro publication unit is the smallest unit allowed to enter visible/player-reachable space.

Responsibilities:

- final-ready publication near the player
- low-latency reveal around the player and around staircase targets
- directional frontier fill during movement
- page-local application to live TileMap/render representation

Allowed forms:

- micro-chunk page
- tile page
- strip page
- fixed-size subchunk such as `8x8`, `16x16`, or another measured size

Forbidden form:

- one giant chunk-sized publication requirement when the actual visible or actionable need is much smaller

## Key decision: do not go fully naive tile-by-tile

A pure per-tile runtime sounds attractive, but it has serious risks:

- excessive scheduler overhead
- excessive TileMap mutation overhead
- poor batching/coherency
- too many tiny dependency checks
- state explosion for diagnostics and save reconciliation

Therefore this spec does **not** require naive single-tile scheduling as the primary runtime model.

Instead, the recommended direction is:

- tile-level reasoning for visibility and player action reach
- page-level publication for execution

In plain language:

- the runtime may think in terms of tiles
- but it should usually build and publish in small pages, not one tile at a time

## New invariant

The zero-tolerance contract is refined like this:

- every tile that is visible or occupiable must belong to a micro publication unit that is already `full_ready`
- a macro unit may remain partially unprepared outside the active reveal envelope
- this is allowed because the player never sees or touches the unprepared part

This preserves the player contract while removing unnecessary whole-chunk waiting.

## Underground design consequence

Underground is the clearest proof that coarse chunk publication is wrong.

Typical underground entry case:

- staircase target area contains a small walkable pocket
- nearby world is mostly `ROCK`
- the player only needs a compact initial actionable/visible area to appear instantly after fade-in

Therefore underground runtime must be redesigned around an **entry pocket** model.

### Underground entry pocket

At staircase transition time, the runtime must prepare:

- the staircase landing tile(s)
- the immediate walkable pocket around the player
- the visible ring of nearby `ROCK` and revealed cave walls
- any immediately relevant cave props, collisions, fog, lighting, and overlays

It must **not** wait for an entire coarse chunk if only a small pocket is required for immediate play.

### Underground rule

Fade-in is allowed only when the target entry pocket is `full_ready`.

The rest of the surrounding macro unit may continue preparing in background **only if it is outside the current visible/occupiable envelope**.

That is not a compromise. That is the correct granularity.

## Surface design consequence

The same principle applies on the surface.

The runtime should stop thinking like this:

- player moved north, so now the next whole northern chunk must be fully ready before anything useful can happen

Instead it should think like this:

- player movement reveals a directional frontier
- the nearest micro publication pages in that direction must become `full_ready` first
- pages behind or far lateral to current motion may be deprioritized
- macro-unit completion may proceed in the background only outside the hot reveal envelope

This means the frontier fills in the direction of motion using final-ready pages, not delayed chunk-wide convergence.

## Full-ready still means full-ready

This spec does **not** weaken `full_ready`.

A micro publication page is only publishable when all of its tiles are final for that page, including:

- terrain
- cliffs
- flora
- props/features visible in the page
- seam correctness against already-published neighbors
- collisions/pathing needed for that page
- required lighting/fog/overlay correctness for that page

What changes is not the strictness of readiness.

What changes is the size of the thing that must be ready before reveal.

## New architecture amendment

The frontier-native runtime architecture is amended with the following components.

### 1. Macro World Ownership Layer

Owns:

- macro-unit indexing
- deterministic generator context
- save/load ownership
- large feature and POI ownership
- packet cache rooted at coarse units

### 2. Micro Page Planner

Owns:

- page coordinates inside or across macro units
- visible/occupiable page sets
- directional lead pages for motion
- staircase entry pocket pages

### 3. Micro Final Packet Builder

Owns:

- building final-ready page packets from native world context
- ensuring page packet is terminal, not progressive
- page-local seam correctness against already published neighbors

### 4. Page Publication Coordinator

Owns:

- applying final pages to live world representation
- ensuring visible world is assembled from final pages only
- revealing pages only after success

## Macro/micro dependency rules

Hard rules:

- micro publication may depend on macro context
- macro readiness is not required everywhere before micro publication begins
- player-visible publication may never depend on unfinished post-publication convergence
- page packets must remain deterministic for the same macro context and generator version

## Recommended initial sizes

This spec does not lock a final page size, but it strongly recommends testing:

- `8x8`
- `16x16`
- narrow directional strips for motion-led publication

Underground staircase target pockets should be assembled from the smallest page size that keeps publication and TileMap apply efficient.

## Memory policy

The same memory rule still applies:

- spending more memory is allowed if it measurably protects seamlessness
- blindly exploding memory just to hide wrong granularity is forbidden

Expected cache hierarchy:

- macro cache for context and ownership
- hot page cache for visible/player-near pages
- warm page cache for predicted directional lead pages

## Scheduler amendment

The scheduler must now distinguish between:

- macro-context work
- micro-page final packet work
- page publication work

Priority order:

1. currently visible/occupiable pages
2. immediate directional lead pages
3. staircase target pocket pages during transition
4. remaining hot bubble pages
5. warm directional pages
6. background macro completion outside the hot reveal envelope

Far/background macro work may never block visible or occupiable page readiness.

## Save/load and determinism policy

The runtime is still allowed to change generation quality and world output.

Required:

- deterministic macro context for same seed/config/version
- deterministic page packet output for same macro context/version
- stable ownership boundaries between macro save data and page publication caches

Page caches are runtime artifacts, not canonical save truth.

## New execution consequence

The current execution plan must be interpreted with this correction:

- do not continue the rewrite as though chunk-sized publication is the only target shape
- before pushing deeper into later iterations, agents must treat macro/micro split as the target direction

In practice:

- `R7-R9` should not proceed as if the present chunk-granular reveal model merely needs optimization
- runtime work from this point forward should bias toward dual-granularity design

## Acceptance criteria

This spec is satisfied only when all of the following are true:

- underground staircase fade-in waits only for the final-ready entry pocket, not a whole coarse chunk
- surface movement reveals final-ready near pages in motion direction without visible catch-up
- visible/occupiable pages are always final
- unfinished macro-area work outside the active reveal envelope is allowed without violating the contract
- runtime latency for underground and directional traversal is materially lower than chunk-granular publication on the same hardware

## Explicitly forbidden misread

This spec must **not** be misread as:

- permission to show unfinished tiles
- permission to publish terrain first and flora later
- permission to rebuild the old first-pass model at page scale
- permission to abandon coarse world ownership and save determinism

The contract stays strict.

The granularity changes.
