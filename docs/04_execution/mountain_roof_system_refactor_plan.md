---
title: Mountain Roof System Refactor Plan
doc_type: execution_plan
status: draft
owner: engineering+design
source_of_truth: false
version: 0.5
last_updated: 2026-03-25
related_docs:
  - MASTER_ROADMAP.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../02_system_specs/world/subsurface_and_verticality_foundation.md
  - ../02_system_specs/world/lighting_visibility_and_darkness.md
  - ../02_system_specs/world/environment_runtime_foundation.md
  - ../02_system_specs/meta/multiplayer_authority_and_replication.md
---

# Mountain Roof System Refactor Plan

This document is the execution-layer plan for replacing the current `MountainRoofSystem` runtime model.

It does not override:
- governance rules
- ADRs
- system specs

Those remain the source of truth for runtime, performance, underground identity, lighting/visibility, and future co-op constraints.

## Documentation Compliance Rule

All work under this plan must be implemented strictly in accordance with the canonical documentation set.

Hard rule:

- execution work may sequence and decompose the refactor
- execution work may not override governance, ADRs, or system specs
- if implementation pressure conflicts with docs, higher-precedence docs win
- if the docs are ambiguous, the ambiguity must be resolved in docs/ADR before the implementation is treated as final

In practice this means every iteration under this plan must stay aligned with:

- `docs/00_governance/ENGINEERING_STANDARDS.md`
- `docs/00_governance/PERFORMANCE_CONTRACTS.md`
- `docs/00_governance/SIMULATION_AND_THREADING_MODEL.md`
- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- `docs/02_system_specs/world/subsurface_and_verticality_foundation.md`
- `docs/02_system_specs/world/lighting_visibility_and_darkness.md`
- `docs/02_system_specs/world/environment_runtime_foundation.md`
- `docs/02_system_specs/meta/multiplayer_authority_and_replication.md`

## Goal

Replace the current mountain roof runtime behavior with a model that matches the approved docs:

- mountain exterior presentation remains stable
- entering underground reveals only the local underground space relevant to the current player
- one player's underground visibility does not expose the whole mountain
- multiple players can occupy different underground pockets without globally revealing each other's spaces
- runtime work stays local, bounded, deferred where needed, and observable

## Non-Goals

This refactor does not aim to:

- rewrite mountain terrain generation from scratch
- redesign world streaming
- redesign lighting as a whole
- redesign building/power systems
- add new underground content or mechanics
- create a generic rendering framework v2

## Why This Is Not A One-Iteration Rewrite

This refactor should not be attempted as one large code dump.

Reasons:

- the current bug is not isolated to one script; it crosses `Chunk`, `ChunkManager`, topology, mining updates, and player-local presentation
- the replacement changes the reveal authority model, not just performance tuning
- the local underground reveal domain is still a design-sensitive choice: open-space pocket vs room-aware partition
- the result must remain compatible with save/load and future host-authoritative co-op
- one-shot replacement would make it too easy to regress mining, streaming, or underground readability with no controlled rollback point

Canonical execution rule for this plan:

- replace the legacy roof system in staged slices
- keep the game playable after each slice
- remove old authority only after the new local reveal path is validated

## Why The Current System Must Be Replaced

The current `MountainRoofSystem` is structurally misaligned with the docs.

### Current architectural failures

- reveal is tied to a full `mountain_key` / connected mountain component rather than the player's local underground space
- multiple visual truths exist at once: `cover_layer`, persistent roof layers, and runtime reveal state
- user-visible reveal depends on heavy background rebuild behavior instead of a cheap local visibility answer
- mining can desync topology, reveal state, and roof visuals
- the model assumes one shared reveal domain more than one player can end up fighting over

### User-visible failures

- roof reveal can be too slow
- only part of the mountain opens
- further digging can stop updating the visible opening correctly
- one underground area can accidentally expose too much of the same mountain
- exiting/entering can make mountain presentation feel unstable

## Hard Requirements

The replacement system must satisfy all of the following:

1. Roof opens only for the underground area the current player is actually using.
2. A different underground area in the same mountain remains hidden.
3. A different player must not reveal another player's underground area by default.
4. Exterior mountain presentation must remain visually the same after exiting underground.
5. No new mountain exterior texture set should appear just because the player entered or exited.
6. Only real world changes remain visible in world truth:
   - entrance opening
   - mined/open tiles
   - any future explicit structural changes
7. Runtime updates must stay local and bounded.
8. Save/load must persist world truth, not ephemeral per-player reveal state.

## Canonical Refactor Direction

### 1. Keep mountain generation

Mountain generation remains the producer of stable world truth:

- rock
- mined floor
- mountain entrance
- connected underground mass/topology data

The current problem is not primarily the generated mountain shape.
The problem is the runtime roof/reveal model layered over that shape.

### 2. Make exterior cover the only visual source of truth

The mountain shell visible from outside should be represented by one canonical presentation path.

Direction:

- `cover_layer` becomes the authoritative exterior mountain shell presentation
- entering/exiting underground changes visibility/masking, not the mountain's exterior art identity
- persistent roof cache layers stop being the authority for whether space is currently revealed

### 3. Replace full-mountain reveal with local underground visibility zones

Reveal must be computed for the player's local underground zone, not the entire connected mountain component.

Initial execution target:

- use the player's current opened underground pocket / local contiguous open-space zone

Future-compatible target:

- if underground room partitioning becomes available, reveal can consume that richer partition
- but the runtime contract remains local-player, local-zone, not global-mountain

### 4. Make reveal player-local, not world-global

Reveal is a visibility/presentation product, not shared world truth.

Direction:

- each player gets an independent underground reveal mask/product
- host-authoritative world state keeps terrain truth
- local/camera/player presentation decides what that player currently sees uncovered

### 5. Keep runtime work local and bounded

The replacement must not introduce:

- world-scale roof rebuilds for one local mining change
- full-mountain relight/reveal updates for one player transition
- interactive-path heavy recomputation

## Execution Phases

## Phase 0: Freeze Legacy Authority

Goal:
- stop treating the current `MountainRoofSystem` roof rebuild pipeline as the authoritative reveal path

Tasks:
- identify all legacy code paths where persistent roof layers decide reveal
- mark those paths as deprecated in implementation notes/comments where needed
- keep the game playable while preparing the replacement

## Phase 1: Establish Single Exterior Shell Model

Goal:
- guarantee that the visible exterior mountain shell comes from one stable source

Tasks:
- define `cover_layer` as the canonical exterior shell
- ensure entering/exiting underground does not swap mountain art identity
- ensure leaving underground restores the same shell presentation except for real mined/entrance changes

## Phase 2: Introduce Local Underground Zone Query

Goal:
- answer "which underground space is this player currently occupying?" without using the whole mountain as the reveal domain

Tasks:
- add a query/helper for local underground zone membership around the player
- base the first version on connected opened underground space
- keep the API future-compatible with room-aware partitioning

## Phase 3: Apply Player-Local Reveal Mask

Goal:
- reveal only the player's local underground zone in loaded chunks

Tasks:
- apply cover hide/show only to tiles in the player's current local underground zone
- keep neighboring hidden underground pockets covered
- ensure reveal state is player-local and not persisted as world truth

## Phase 4: Integrate Mining And Topology Updates

Goal:
- mining immediately updates the currently visible underground zone without global reveal churn

Tasks:
- wire mining/open-tile changes into local zone invalidation
- update only affected local chunks/tiles
- ensure topology/background rebuild remains a support system, not the visual truth owner

## Phase 5: Remove Legacy Roof Cache Authority

Goal:
- delete or demote the old system pieces that are no longer needed

Tasks:
- remove current `MountainRoofSystem` logic that assumes one active revealed mountain
- remove persistent roof rebuild paths as reveal authority
- keep only any presentation-only fades/effects that remain useful and docs-compliant

## Phase 6: Revalidate Single-Player And Future Co-op Behavior

Goal:
- confirm the replacement matches both current gameplay expectations and future multiplayer constraints

Tasks:
- validate one player entering/exiting one underground base
- validate multiple underground pockets in one mountain
- validate chunk streaming boundaries
- validate save/load restoration
- validate that the architecture remains compatible with more than one player

## Delivery Iterations

The refactor should be delivered as the following concrete iterations.

### Iteration R0: Legacy Audit And Freeze

Goal:
- freeze the current problem space and mark the exact legacy authority paths that must be retired

Scope:
- audit current reveal authority
- audit mining update path
- audit topology dependencies
- audit which parts are world truth vs derived state vs local presentation
- add or update execution notes only where needed

Must establish:
- where `MountainRoofSystem` currently decides reveal
- where `Chunk` currently decides shell presentation
- where mining can leave roof/reveal desynced
- which states are currently shared/global but should become player-local

Non-goals:
- no runtime redesign yet
- no partial hotfix layering

Definition of done:
- the team can point to one authoritative list of legacy code paths to remove or demote
- the reveal contract for the replacement is written down and unambiguous enough to start implementation

### Iteration R1: Single Exterior Shell Foundation

Goal:
- make one canonical exterior mountain shell path and stop relying on mixed visual truths

Scope:
- `cover_layer` becomes the canonical exterior shell representation
- entering/exiting underground no longer changes mountain art identity
- any persistent roof cache remains presentation-only during migration

Must establish:
- exterior mountain art is stable before and after entry/exit
- no "new roof texture state" appears on exit
- world truth still only changes on real mining / entrance changes

Non-goals:
- no local underground zone reveal yet
- no multiplayer-specific behavior yet beyond not making it worse

Definition of done:
- a player can leave underground and the mountain exterior reads the same as before
- shell rendering no longer depends on the old full-mountain reveal model

### Iteration R2: Local Underground Zone Query

Goal:
- introduce the new reveal domain: local underground zone instead of whole mountain component

Scope:
- add a query/product for "current local underground zone for this player"
- first implementation may use connected open underground pocket
- API must remain future-compatible with room-aware partitioning

Must establish:
- the system can answer which loaded tiles/chunks belong to the player's current underground zone
- zone updates are local and bounded
- no full-mountain reveal dependency remains in the zone query

Non-goals:
- no final polish of reveal visuals
- no shared/global reveal state

Definition of done:
- the project has a working local-zone data product that can drive presentation
- mining/open-tile changes can invalidate this zone locally

### Iteration R3: Player-Local Reveal Application

Goal:
- apply reveal/hide only to the current player's local underground zone

Scope:
- use the local-zone product to hide shell only where the current player should see underground
- keep neighboring underground pockets covered
- keep the reveal product local presentation, not shared world truth

Must establish:
- only the active underground area is uncovered
- unrelated underground areas in the same mountain remain hidden
- exiting the zone restores shell presentation cleanly

Non-goals:
- no final removal of all legacy code yet
- no full co-op implementation

Definition of done:
- one player entering one underground area no longer reveals the entire mountain
- user-visible behavior matches the intended single-player reading

### Iteration R4: Mining And Streaming Integration

Goal:
- make mining, chunk streaming, and local reveal stay coherent under runtime change

Scope:
- local zone invalidation on mining/open-tile changes
- local shell update on affected chunks/tiles only
- streaming-safe reveal restoration when chunks load/unload

Must establish:
- digging deeper extends reveal correctly
- further mining does not stop updating the visible opening
- chunk boundaries do not produce half-open / half-stale roof behavior

Non-goals:
- no presentation polish beyond correctness

Definition of done:
- mining and streaming no longer desync roof visibility
- no global rebuild churn is required for routine underground changes

### Iteration R5: Legacy Roof Authority Removal

Goal:
- delete or demote the old system so only the new reveal model remains authoritative

Scope:
- remove legacy `MountainRoofSystem` assumptions about one active revealed mountain
- remove persistent roof cache as reveal authority
- keep only presentation-only helpers that remain useful

Must establish:
- there is one clear reveal authority path
- no hidden fallback keeps reintroducing full-mountain behavior

Non-goals:
- no extra new features

Definition of done:
- the old full-mountain roof model is no longer functionally required
- the code path is simpler, narrower, and aligned with docs

### Iteration R6: Revalidation And Follow-Up Contract

Goal:
- verify correctness, performance, and future co-op compatibility after the replacement lands

Scope:
- gameplay validation
- perf validation
- save/load validation
- future co-op architecture check
- docs/ADR updates only if implementation clarified canonical behavior

Must establish:
- local underground reveal remains bounded and observable
- no world-scale reveal rebuilds occur for local changes
- the final model does not assume one globally meaningful player

Non-goals:
- no networking implementation

Definition of done:
- the replacement is stable enough to become the new baseline
- remaining work, if any, is additive or polish-level rather than architectural rescue

## Recommended Immediate Next Iteration

The correct next implementation step is `Iteration R1: Single Exterior Shell Foundation`.

Reason:

- the current system still has multiple competing visual truths
- until the exterior shell path is singular, local reveal work will keep fighting stale legacy behavior
- this is the smallest safe slice that moves the architecture toward the target model without another fake hotfix

## R0 Audit Result

Status:
- completed on 2026-03-25

R0 did not change the runtime model.
It established the current legacy authority paths, the state classification that the replacement must follow, and the freeze rules for all later iterations.

### R0 Doc Constraints Confirmed

The audit confirms the following constraints from the canonical docs set:

- underground visibility/reveal cannot be treated as a fake one-off visual trick
- client-local presentation must not become hidden gameplay/world authority
- more than one player and more than one underground area must be imaginable in the architecture now, not later
- opening one underground area must not imply rebuilding or revealing the entire mountain/underground domain
- visibility products are allowed to be derived and local, but world truth must remain stable and persistent

### R0 State Classification

The replacement must separate these state classes clearly.

Authoritative world truth:
- terrain type at tile (`ROCK`, `MINED_FLOOR`, `MOUNTAIN_ENTRANCE`)
- chunk terrain bytes / saved modifications
- excavation results and entrances

Derived reconstructible state:
- mountain topology maps in `ChunkManager`
- local underground zone products that will later drive reveal
- any rebuildable shell/reveal helper data

Client-local / player-local presentation:
- which underground area is currently uncovered for this player
- reveal mask / shell hide state
- alpha / fade / visual transition state

Canonical R0 conclusion:
- the current implementation mixes derived topology and local presentation into a de facto shared reveal authority
- that is the primary architecture defect to remove

### R0 Legacy Authority Paths

The following paths are now explicitly classified as legacy authority that must be removed or demoted in later iterations.

1. Global active-mountain reveal authority
   - `core/systems/world/mountain_roof_system.gd::_request_refresh`
   - `core/systems/world/chunk_manager.gd::set_active_mountain_key`
   - Problem:
     - reveal domain is the full connected `mountain_key`
     - one global `_active_mountain_key` becomes the practical reveal authority
     - this silently assumes one globally meaningful player/underground area

2. Persistent roof cache as reveal authority
   - `core/systems/world/mountain_roof_system.gd::_tick_roof_visuals`
   - `core/systems/world/chunk.gd::begin_roof_visual_build`
   - `core/systems/world/chunk.gd::continue_roof_visual_build`
   - `core/systems/world/chunk.gd::_redraw_roof_visual_tile`
   - Problem:
     - user-visible reveal depends on persistent roof layer rebuild behavior
     - topology-keyed roof caches are being treated as if they decide what is uncovered right now

3. Per-mountain-key chunk reveal application
   - `core/systems/world/chunk.gd::set_revealed_mountain_key`
   - `core/systems/world/chunk.gd::_apply_revealed_mountain_state`
   - Problem:
     - reveal is still keyed by one `mountain_key`
     - this cannot represent multiple hidden/revealed underground spaces inside the same mountain correctly

4. Cover-layer fallback still using whole-mountain domain
   - `core/systems/world/chunk.gd::_sync_cover_reveal_state`
   - Problem:
     - even the fallback path currently erases/restores shell by whole `mountain_key`
     - this is still the wrong domain even if it is faster than the old roof-cache path

5. Mining update path coupled to roof build completion
   - `core/systems/world/mountain_roof_system.gd::_on_mountain_tile_mined`
   - Problem:
     - if a chunk is already roof-build-complete, the current path can skip needed reveal update work
     - this is a direct source of "part of the roof opens, further digging stops updating"

6. Topology treated as immediate visual authority
   - `core/systems/world/chunk_manager.gd::_incremental_topology_patch`
   - `core/systems/world/chunk_manager.gd::get_mountain_key_at_tile`
   - Problem:
     - topology is valid as derived data support
     - topology should not be the direct authoritative answer for player-local reveal over a whole mountain component

7. Full-world / broad cache invalidation legacy paths
   - `core/systems/world/mountain_roof_system.gd::_mark_all_loaded_roof_visuals_dirty`
   - `core/systems/world/mountain_roof_system.gd::_queue_local_roof_visual_rebuild`
   - Problem:
     - both paths assume the roof cache remains central to reveal correctness
     - these are cache management paths and must not remain reveal authority

### R0 Freeze Rules

Until the refactor is complete, the following rules apply:

1. Do not add new gameplay meaning to `_active_mountain_key`.
2. Do not add new systems that depend on full `mountain_key` reveal semantics.
3. Do not add new user-visible behavior that requires persistent roof cache rebuild to finish before reveal becomes correct.
4. Do not encode player-local underground reveal as saved world truth.
5. Do not widen chunk invalidation or roof rebuild churn as a substitute for correct local reveal logic.
6. Do not treat topology products as the final reveal domain contract.

### R0 Removal / Demotion List For Later Iterations

These are the exact legacy responsibilities that later iterations must retire.

Remove as authority:
- global `_active_mountain_key` reveal ownership
- `mountain_key` as the primary reveal domain
- persistent roof cache as the deciding runtime reveal path
- mining correctness tied to roof build completion state

Demote to derived/support only:
- mountain topology maps
- roof cache layers if any remain temporarily useful for presentation
- broad roof rebuild queue management

Keep as stable world truth:
- terrain generation
- excavation/open-tile truth
- entrances and mined geometry
- chunk persistence data

### R0 Conclusion

R0 confirms that the project does not need a full rewrite of mountain terrain generation.

What must be replaced is the current mountain roof / underground reveal authority model:

- from global mountain-component reveal
- to player-local underground zone reveal
- from mixed visual truths
- to one stable exterior shell plus local presentation mask

## R1 Result

Status:
- completed on 2026-03-25

R1 established a single exterior shell authority path for the current runtime baseline.

### R1 What Changed

1. `cover_layer` is now the only active exterior shell authority for mountain hide/reveal behavior.
2. `MountainRoofSystem` no longer uses the background roof rebuild queue as the runtime reveal path.
3. `FrameBudgetDispatcher.visual.mountain_roof.visual_rebuild` is removed from the active runtime path for this stage.
4. Refresh of active shell state is now driven directly through chunk cover application, with topology refresh support for reapplying the current active mountain after chunk/topology changes.
5. `ChunkManager.set_active_mountain_key(...)` now supports forced recomputation of affected chunks when topology changes without a key change.

### R1 What Was Demoted

Demoted from authority:
- persistent roof cache rebuild
- roof build queue ordering
- roof cache completion state as a reveal-correctness requirement

Still present temporarily as legacy implementation residue:
- roof cache helpers in `Chunk`
- roof cache node/layer scaffolding
- roof-cache-specific legacy methods not yet physically deleted

Canonical R1 rule:
- these legacy pieces are no longer allowed to define whether the mountain is currently visually open or closed

### R1 Known Limitations

R1 does **not** solve the reveal-domain problem yet.

Current limitation after R1:
- reveal is still keyed to the active connected `mountain_key`
- entering one underground area in a mountain can still reveal too much of that same connected mountain

This is expected at R1.
The purpose of R1 was to stop mixed visual truths first, not to finish the final local-zone behavior.

### R1 Validation Outcome

Observed in headless validation:
- world boots successfully
- runtime validation route completes without GDScript parse/runtime errors
- the old `mountain_roof.visual_rebuild` dispatcher job is no longer active in the runtime log

Remaining non-R1 issue:
- topology catch-up timeout still exists in the validation route and remains outside the scope of this shell-foundation slice

### R1 Exit Criteria Reached

R1 is considered complete because:

- exterior mountain shell now has one active runtime authority path
- entering/exiting no longer depends on persistent roof-cache rebuild completion
- the project is ready for `R2: Local Underground Zone Query`

## R2 Result

Status:
- completed on 2026-03-25

R2 established the first player-local underground zone product without using full mountain reveal as the query domain.

### R2 What Changed

1. `ChunkManager` now exposes a dedicated local-zone query for the player's current underground space.
2. The first zone implementation is a loaded connected open-pocket query seeded from the player's current underground tile.
3. The query is independent from `mountain_key` as a reveal domain and does not depend on full-mountain roof cache state.
4. `MountainRoofSystem` now caches this derived zone product locally:
   - zone seed
   - zone kind
   - zone tiles
   - affected chunk coords
   - truncation flag for unloaded boundaries
5. Local-zone refresh now re-runs on:
   - entering underground
   - moving outside the cached open-pocket while still underground
   - mining changes while the player remains underground
6. The zone product is instrumented through `WorldPerfProbe` so oversized queries become visible instead of silent.

### R2 Canonical Interpretation

R2 does **not** yet change the final user-visible reveal domain.

After R2:
- the project has a working player-local underground zone data product
- reveal application is still temporarily driven by the active `mountain_key`
- `R3` remains the stage where presentation will switch from full connected mountain reveal to local zone reveal

This is intentional.
R2 exists to separate query/model concerns before changing user-visible reveal behavior.

### R2 Validation Outcome

Observed in headless runtime validation:
- world boots successfully
- the validation route completes without GDScript parse/runtime errors
- the new local-zone instrumentation does not emit contract violations in the validation log
- the project now has a reproducible path for asking "what is the player's current loaded underground pocket?"

Still outside R2 scope:
- reveal is still whole-`mountain_key` based until `R3`
- topology catch-up timeout still appears in the validation route and remains a separate issue
- the current zone query is limited to loaded tiles and may report truncation at unloaded boundaries

### R2 Exit Criteria Reached

R2 is considered complete because:

- the project now has a working local-zone data product that can drive presentation
- mining/open-tile changes can invalidate and refresh this zone locally
- no full-mountain reveal dependency remains inside the zone query itself
- the project is ready for `R3: Player-Local Reveal Application`

## R3 Result

Status:
- completed on 2026-03-25

R3 switched the active runtime reveal path from whole connected mountain reveal to player-local underground zone reveal.

### R3 What Changed

1. `MountainRoofSystem` now applies reveal using the current local-zone product instead of chunk lists derived from active `mountain_key`.
2. Affected chunks are now the union of:
- chunks from the previous revealed local zone
- chunks from the new revealed local zone
3. `Chunk` cover application is no longer keyed by "hide every tile in this mountain component".
4. `Chunk` now derives a local revealed cover set from:
- open tiles in the active local underground zone
- nearby cave-edge rock tiles that should become visible as interior boundary walls
5. Restoring reveal now redraws only tiles that were previously uncovered by the local zone and are no longer part of the active zone reveal.
6. `ChunkManager` no longer pre-applies full-mountain reveal to newly created chunks during load/stage creation.
7. `mountain_key` remains only as a temporary sidecar datum for topology awareness and later cleanup work; it is no longer the active presentation authority.

### R3 Canonical Interpretation

After R3:
- one player entering one underground space no longer needs to reveal the whole connected mountain
- neighboring underground pockets in the same mountain remain covered unless their tiles are part of the active local zone
- exterior shell presentation still comes from `cover_layer`
- reveal remains local presentation, not shared world truth

Still intentionally deferred to later iterations:
- chunk-boundary / streaming edge cases
- final removal of all legacy roof helpers
- full co-op visibility resolution

### R3 Validation Outcome

Observed in headless runtime validation:
- world boots successfully
- the validation route completes
- route drain completes and exits normally without the earlier topology catch-up timeout in this run
- no new GDScript parse/runtime errors appear
- the old `mountain_roof.visual_rebuild` dispatcher job remains absent from the active runtime path
- new local-zone reveal application does not emit contract violations in the validation log

Known remaining limitation after R3:
- local reveal still uses the loaded open-pocket query from `R2`, so loaded/unloaded chunk boundaries can still affect where the visible pocket ends
- legacy roof-cache code still exists in `Chunk`, but is no longer the active reveal authority

### R3 Exit Criteria Reached

R3 is considered complete because:

- one player entering one underground area no longer depends on full connected mountain reveal
- user-visible reveal authority is now the player-local zone product
- the project is ready for `R4: Mining And Streaming Integration`

## R4 Result

Status:
- completed on 2026-03-25

R4 hardened the local reveal path against runtime mining changes and chunk streaming boundaries.

### R4 What Changed

1. `MountainRoofSystem` now tracks not only zone-owned chunks, but the full reveal-affected chunk set for the current local zone.
2. This reveal-affected chunk set includes neighboring chunk coordinates around zone tiles so chunk-boundary wall reveal no longer depends on whole-mountain fallback.
3. Reveal refresh now applies to the union of:
- chunks affected by the previous local reveal state
- chunks affected by the new local reveal state
4. On `chunk_loaded`, if the chunk is already inside the current reveal-affected set, the current local reveal is applied immediately before the next refresh pass completes.
5. Newly streaming chunks now re-apply local-zone cover hiding while progressive `cover` redraw is still in flight, so redraw no longer temporarily paints stale mountain cover back over the active underground pocket.
6. Mining/open-tile change handling remains local:
- active underground mining schedules zone refresh
- refresh recomputes only local reveal state
- no global roof rebuild churn is reintroduced

### R4 Canonical Interpretation

After R4:
- digging deeper can extend the currently visible underground pocket without requiring global mountain reveal
- loading or unloading neighboring chunks no longer relies on a later full reset to make local reveal coherent again
- the remaining problems are now mostly legacy cleanup and validation depth, not missing reveal authority

Still intentionally deferred:
- full removal of legacy roof-cache helpers
- deeper multiplayer-specific visibility ownership
- final gameplay/perf revalidation as a dedicated wrap-up stage

### R4 Validation Outcome

Observed in headless runtime validation:
- world boots successfully
- the route completes
- no new GDScript parse/runtime errors appear after the streaming/mining integration changes
- the old `mountain_roof.visual_rebuild` dispatcher path still does not return

Observed limitation in this run:
- the validation route still ended with the known topology catch-up timeout
- the existing route driver validates streaming movement, but does not yet provide a dedicated automated mining scenario

### R4 Exit Criteria Reached

R4 is considered complete because:

- mining and chunk streaming no longer depend on full-mountain reveal authority
- local reveal restoration is now explicitly integrated with chunk load and progressive cover redraw
- the project is ready for `R5: Legacy Roof Authority Removal`

## R5 Result

Status:
- completed on 2026-03-25

R5 removed the remaining legacy full-mountain roof authority so the runtime reveal model now has one active path.

### R5 What Changed

1. `Chunk` no longer contains the old persistent roof-cache runtime scaffold:
- no per-mountain roof layers
- no roof fade authority
- no roof build queue state
- no legacy "revealed mountain key" presentation path
2. `Chunk` now keeps only the active local-zone `cover_layer` reveal state as the runtime shell authority.
3. `MountainRoofSystem` no longer tracks or waits on an active revealed `mountain_key` for presentation.
4. `MountainRoofSystem` no longer depends on topology catch-up to apply the current reveal state.
5. `ChunkManager` no longer carries the old active-mountain reveal sidecar API used by the removed full-mountain model.
6. Old roof-runtime-specific balance knobs were removed from `WorldGenBalance` because they no longer participate in the active runtime path.

### R5 Canonical Interpretation

After R5:
- the only active runtime reveal authority is player-local zone application onto `cover_layer`
- mountain topology remains a data/query product, not a reveal authority
- any remaining roof-related helpers are no longer required for runtime correctness

Presentation data intentionally kept:
- static mountain art colors and tileset generation inputs remain valid
- `cover_layer` wall presentation remains the user-visible mountain shell path

### R5 Validation Outcome

Observed in headless runtime validation:
- world boots successfully
- the route completes
- no new GDScript parse/runtime errors appear after the legacy cleanup
- the removed `mountain_roof.visual_rebuild` path does not return

Observed limitation in this run:
- the known topology catch-up timeout still appears in the validation route
- the main remaining runtime offender in the log is `chunk_manager.streaming_redraw`, not mountain roof authority

### R5 Exit Criteria Reached

R5 is considered complete because:

- the old full-mountain roof model is no longer functionally required
- the runtime reveal code path is narrower and aligned with the docs-driven local-zone model
- the project is ready for `R6: Revalidation And Follow-Up Contract`

## R6 Result

Status:
- completed on 2026-03-25

R6 validated the replacement as the new baseline and identified the remaining non-roof follow-up work.

### R6 What Changed

1. The runtime validation harness now includes a controlled mining scenario instead of route-only movement.
2. The validation run now checks:
- a mountain edge can be mined into an underground pocket
- entering the pocket activates a local reveal zone
- deeper mining expands the active local zone
- exiting back to exterior clears the active local reveal zone
3. The validation run now includes persistence-boundary assertions:
- chunk save payload does not leak local reveal / roof / zone presentation keys
- chunk save payload does not change from reveal-only movement without new mining
- `SaveCollectors.collect_chunk_data(...)` matches the `ChunkManager` save snapshot
4. `MountainRoofSystem` exposes minimal read-only validation helpers for active local-zone state.

### R6 Validation Outcome

Observed in headless validation:
- boot succeeds
- controlled mining validation succeeds
- route validation succeeds
- no new GDScript parse/runtime errors appear
- the old `mountain_roof.visual_rebuild` path does not return

Observed roof-specific conclusions:
- local reveal is active only while the player occupies the mined underground pocket
- digging deeper expands the local zone as expected
- reveal-only movement does not pollute the chunk save payload
- the new roof model is compatible with the current save boundary because only world truth diffs remain persisted

Observed remaining runtime limitation:
- the validation route still ends with the known topology catch-up timeout
- the main remaining background offender is `chunk_manager.streaming_redraw`, not mountain roof authority

### R6 Future Co-op Check

The final runtime shape now aligns with the co-op direction in the docs because:

- reveal is derived local presentation, not world truth
- topology remains a query/data layer, not a reveal authority
- save boundaries remain authoritative-world-only
- the loaded-space policy is still simple today, but the reveal authority no longer assumes that one globally revealed mountain meaningfully exists

No extra ADR update was required in this iteration because the implemented model matches the already-established canonical direction rather than redefining it.

### R6 Exit Criteria Reached

R6 is considered complete because:

- the replacement is stable enough to become the new baseline
- remaining work is follow-up validation/perf hardening rather than architectural rescue
- mountain roof authority is no longer the primary source of correctness or performance risk in this area

## Files Likely Involved

- `core/systems/world/mountain_roof_system.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_manager.gd`
- `scenes/world/game_world.gd`
- related debug/perf validation helpers if needed

Potential follow-up docs if architecture is clarified during implementation:

- `docs/05_adrs/*`
- `docs/02_system_specs/world/subsurface_and_verticality_foundation.md`
- `docs/02_system_specs/world/lighting_visibility_and_darkness.md`
- `docs/02_system_specs/meta/multiplayer_authority_and_replication.md`

## Risks

- ambiguity between "underground room" and "underground pocket"
- edge cases where one connected pocket contains several player-made bases
- loaded/unloaded chunk boundaries causing reveal artifacts
- accidental persistence of player-local reveal state
- over-optimizing too early before the new visual truth is simplified

## Open Questions

1. For the first replacement, is the reveal domain:
   - a connected open underground pocket
   - a formal underground room partition
   - a hybrid of the two
2. Should revealed space include a small buffer past the player room/pocket boundary for readability?
3. Should per-player reveal be resolved entirely in local presentation, or through a host-auth visibility product with local consumption?

## Smoke Tests

1. Enter one underground base: only that local underground space becomes uncovered.
2. Exit the base: exterior mountain shell looks the same as before, except real entrances/mined tiles.
3. Mine deeper inside the active underground space: the newly opened area reveals correctly without exposing unrelated pockets.
4. Open a second underground pocket in the same mountain: the first pocket does not automatically reveal the second.
5. Stream chunks in/out while underground: reveal remains coherent.
6. Save/load and re-enter: world truth restores correctly and reveal remains runtime-local.

## Definition Of Done

This refactor is only done when:

- `MountainRoofSystem` no longer uses full mountain component reveal as its main model
- entering underground no longer reveals the whole mountain
- reveal is local to the player's underground zone
- multiple underground spaces in one mountain remain independently hidden unless explicitly occupied
- exterior mountain presentation is stable before and after entry/exit
- player-local reveal is compatible with future multiplayer
- runtime logs show bounded local work rather than large roof rebuild churn
