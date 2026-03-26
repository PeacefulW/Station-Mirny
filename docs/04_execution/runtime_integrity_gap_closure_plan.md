---
title: Runtime Integrity Gap Closure Plan
doc_type: execution_plan
status: draft
owner: engineering+design
source_of_truth: false
version: 0.1
last_updated: 2026-03-26
related_docs:
  - MASTER_ROADMAP.md
  - ../00_governance/DOCUMENT_PRECEDENCE.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../02_system_specs/base/building_and_rooms.md
  - ../02_system_specs/base/engineering_networks.md
  - ../02_system_specs/meta/save_and_persistence.md
  - ../02_system_specs/meta/multiplayer_authority_and_replication.md
---

# Runtime Integrity Gap Closure Plan

This document sequences closure of the confirmed runtime, save/load, and authority gaps found during the 2026-03-26 review pass.

It does not override:
- governance rules
- ADRs
- system specs

Those remain the source of truth.

## Documentation Compliance Rule

All work under this plan must be implemented strictly in accordance with the canonical documentation set.

Hard rule:
- execution work may sequence and decompose the fixes
- execution work may not override governance, ADRs, or system specs
- if implementation pressure conflicts with docs, higher-precedence docs win
- if the docs are wrong or stale, fix the docs in the same iteration instead of silently coding around them

## Why this plan exists

The review found that the project is no longer in a broad runtime emergency state.

Roof/reveal, streaming, and general play-session smoothness are much healthier than before.

The remaining important problems are narrower and more dangerous:
- save/load correctness holes
- docs claiming refactors are complete when code is not there yet
- authoritative mutation paths still bypassing the Command Pattern
- building/power background jobs that are deferred but still not truly bounded or local

This plan exists to close those gaps without reopening already-stabilized world runtime areas.

## Confirmed gaps

### Gap A: unsafe in-place load from pause menu

Current problem:
- `SaveLoadTab` calls `SaveManager.load_game()` directly into the live world scene
- `SaveManager.load_game()` reapplies world/chunks/buildings/player state without rebuilding the scene/runtime shell
- loaded chunk nodes are not fully reset first

Risk:
- mixed old scene state + new save truth
- hard-to-reproduce load corruption

## Gap B: stale chunk diff files can survive slot overwrite

Current problem:
- if a save operation produces no chunk diffs, chunk save sync is skipped
- old `chunks/*.json` files in that slot can remain on disk

Risk:
- loading an overwritten slot can replay stale terrain diffs from an older save

## Gap C: save slot UI reads the wrong metadata keys

Current problem:
- save metadata writes `save_time` and `game_day`
- UI reads `date` and `day`

Risk:
- slot list displays wrong fallback values
- misleading save UX

## Gap D: room recompute is still a full flood fill

Current problem:
- `BuildingSystem` defers room recompute through `FrameBudgetDispatcher`
- but each tick still clears dirty state and runs full `IndoorSolver.recalculate(walls)`
- `IndoorSolver.recalculate()` is still a full-bounds flood fill

Evidence:
- live gameplay log shows `FrameBudgetDispatcher.topology.building.room_recompute` at `10.44 ms`, `11.27 ms`, `11.16 ms`, `9.99 ms`

Risk:
- interactive building remains capable of causing visible background spikes
- ADR/runtime status claims are currently overstated

## Gap E: power recompute is still a global scene-tree scan

Current problem:
- `PowerSystem` still scans `power_sources` and `power_consumers` from groups on recompute
- periodic heartbeat still forces dirty recomputation

Risk:
- not multiplayer-safe enough
- not registry-based
- not genuinely local/partition-aware
- docs/ADR overstate completion

## Gap F: terrain excavation bypasses the mandatory command boundary

Current problem:
- player harvest path calls `ChunkManager.try_harvest_at_world()` directly

Risk:
- world mutation is not routed through deterministic command execution
- save replay / host-authoritative future becomes harder

## Gap G: docs currently overstate implementation completeness

Current problem:
- ADR-0001 currently marks room/power hazards resolved and the refactor series complete
- code and live telemetry do not support that claim

Risk:
- future iterations start from a false premise
- medium-strength executor may follow stale docs and make bad assumptions

## Explicit non-priority items for this wave

The following are real but are not the first closure targets in this plan:
- direct combat damage path still bypasses a formal command boundary
- single-player chunk streaming assumptions in foundational world services
- `Topology.runtime.commit` residual tail
- `7 resources still in use at exit`

These may become follow-up work after the gaps above are closed.

## Model guidance

`gpt-5.4 medium/default` is acceptable for this plan only under the following rules:
- execute one iteration at a time
- do not bundle multiple iterations into one pass
- do not widen scope beyond the iteration
- if an iteration discovers a doc conflict, stop and fix docs first

Recommended model by iteration:
- `G0`, `G1`, `G2`, `G5`: `gpt-5.4 medium/default` is acceptable
- `G3`, `G4`: prefer `gpt-5.4 high`
- `xhigh` is only justified if the executor discovers a real architectural ambiguity that cannot be resolved without deeper redesign analysis

Reason:
- `G3` and `G4` touch runtime contracts, bounded work, and correctness-sensitive derived state
- those two are the easiest place for a medium-strength pass to accidentally ship a fake fix

## Global execution rules

- One iteration per run.
- Re-read required docs before each iteration.
- Do not touch roof/reveal architecture as part of this plan.
- Do not reopen `streaming_redraw` work unless the target iteration proves a regression.
- If an iteration changes canonical behavior, update the relevant docs/ADR in the same turn.
- If smoke tests fail, stop and report instead of widening the patch.

## Priority order

1. `G0` Documentation truth alignment
2. `G1` Save/load integrity closure
3. `G2` Excavation command boundary closure
4. `G3` Room recompute bounded/local patch
5. `G4` Power recompute registry de-globalization
6. `G5` Revalidation and truthful ADR closure

## Iterations

## G0: Documentation truth alignment

### Goal

Remove false “resolved/complete” claims so execution work starts from true project state.

### In scope

- ADR-0001 status wording
- explicit note that room/power work is not complete yet
- link this plan from the docs index if needed

### Out of scope

- runtime code changes

### Files likely involved

- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- `docs/README.md`
- this plan

### Implementation steps

1. Downgrade false completion claims in ADR-0001.
2. Mark room recompute and power recompute as still open or partial.
3. Add live evidence note for room spike and save/load gaps.
4. Keep roof/streaming improvements marked as real completed work.

### Smoke tests

- docs read consistently
- no execution doc contradicts governance/spec layers

### Definition of done

- ADR no longer says the series is fully complete if code and logs disagree
- a medium executor can read the docs without inheriting false assumptions

## G1: Save/load integrity closure

### Goal

Make save/load correct before further runtime refactors.

### In scope

- safe load path from pause menu
- stale chunk diff cleanup
- save slot metadata schema fix

### Out of scope

- full save system redesign
- migration framework redesign
- world boot pipeline redesign

### Files likely involved

- `core/autoloads/save_manager.gd`
- `core/autoloads/save_collectors.gd`
- `scenes/ui/save_load_tab.gd`
- `scenes/world/game_world.gd`
- `core/systems/world/chunk_save_system.gd`

### Implementation steps

1. Remove direct in-place `SaveManager.load_game()` usage from pause-menu load flow.
2. Route in-game load through `SaveManager.pending_load_slot` plus scene reload or the same boot path already used by main menu load.
3. Ensure slot overwrite always reconciles chunk diff files.
4. Preferred direction:
   `SaveManager.save_game()` must always call chunk sync logic, even when the current diff set is empty.
5. Fix slot UI to read `save_time` and `game_day`.
6. Do not claim live in-scene load safety unless the scene/runtime shell is actually rebuilt first.

### Smoke tests

- save to a slot with terrain edits, overwrite the same slot with a clean state, reload, verify no stale terrain diff remains
- load from pause menu, verify the world resets cleanly into the selected slot
- slot list shows correct day/time metadata

### Definition of done

- no direct live-world load path remains in pause menu
- stale chunk diff files cannot survive a clean overwrite
- save slot labels read correct metadata

## G2: Excavation command boundary closure

### Goal

Bring terrain excavation under the mandatory Command Pattern.

### In scope

- harvest/mining world mutation path
- command executor path for excavation

### Out of scope

- full combat command framework
- all future interaction commands

### Files likely involved

- `core/entities/player/player.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/commands/`
- `scenes/world/game_world.gd`

### Implementation steps

1. Introduce a command object for excavation/harvest world mutation.
2. Route player harvest through `CommandExecutor`.
3. Keep `ChunkManager.try_harvest_at_world()` as the implementation target behind the command, not the direct player callsite.
4. Preserve existing result payload, pickups, popups, and event emission.
5. If combat is not being fixed in the same pass, explicitly leave it out and do not silently mix scopes.

### Smoke tests

- normal mining still works
- mined terrain persists through save/load
- no direct player-to-chunk-manager excavation call remains

### Definition of done

- terrain excavation reaches authoritative world mutation through a command path
- UX remains unchanged for the player

## G3: Room recompute bounded/local patch

### Goal

Replace fake deferred full recompute with real bounded room patching.

### In scope

- `BuildingSystem` dirty-region model
- `IndoorSolver` local patching
- room recompute telemetry

### Out of scope

- redesign of room semantics
- full building feature expansion
- unrelated UI work

### Files likely involved

- `core/systems/building/building_system.gd`
- `core/systems/building/building_indoor_solver.gd`
- `core/autoloads/world_perf_monitor.gd`
- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`

### Hard implementation rule

Do not treat “queued full flood fill” as a successful fix.

### Implementation steps

1. Replace cell-only dirty queue semantics with dirty regions carrying at least:
   - changed footprint
   - padded bounds
   - reason (`place`, `remove`, `destroy`, `load`)
2. Process one merged bounded region per dispatcher tick.
3. Add a local room patch solver that returns:
   - cells added to indoor
   - cells removed from indoor
   - whether the patch stayed within the allowed local proof boundary
4. Apply patch results into `indoor_cells` incrementally instead of wholesale replacement.
5. Reserve full rebuild only for boot/load or explicit fallback paths that are not reachable from ordinary runtime mutations.
6. Instrument recompute cost and keep live runtime visibility in logs.

### Smoke tests

- place/remove/destroy walls around a small room
- indoor state updates correctly
- save/load restores indoor truth
- live log no longer shows `building.room_recompute` spikes near `10-11 ms`

### Definition of done

- ordinary runtime room recompute no longer calls full `IndoorSolver.recalculate(walls)`
- background room work becomes genuinely bounded/local

## G4: Power recompute registry de-globalization

### Goal

Remove scene-tree group scans from the power recompute path and move to explicit registration.

### In scope

- source/consumer registration lifecycle
- dirty power recompute path
- removal of periodic global scan behavior

### Out of scope

- full electrical partition simulation redesign
- new engineering gameplay

### Files likely involved

- `core/systems/power/power_system.gd`
- `core/entities/components/power_source_component.gd`
- `core/entities/components/power_consumer_component.gd`
- powered structure scripts that own those components
- ADR/status docs if behavior meaning changes

### Hard implementation rule

Do not claim this iteration complete if it only hides the old scan behind a different wrapper.

### Implementation steps

1. Add explicit register/unregister flow for sources and consumers.
2. Keep authoritative source/consumer sets inside `PowerSystem`, not by repeated `get_nodes_in_group(...)`.
3. Dirty recompute should operate on registered sets only.
4. Heartbeat must stop forcing blind full tree scans.
5. If partition-aware recompute is not actually implemented yet, do not mark the higher contract as resolved in ADR/docs.

### Smoke tests

- place/remove powered structures
- supply/demand updates correctly
- brownout behavior remains correct
- no `get_nodes_in_group("power_sources")` or `("power_consumers")` remains in runtime recompute path

### Definition of done

- power recompute no longer depends on scene-tree group scans
- docs truthfully describe whether the result is registry-global or truly partition-local

### Execution note (2026-03-26)

- `PowerSystem` now keeps explicit source/consumer registries and recomputes only from those registries.
- `PowerSourceComponent` and `PowerConsumerComponent` register and unregister with `PowerSystem` during lifecycle changes.
- headless validation now includes a battery place/remove case that verifies source registration and life-support restore on removal.
- contract status remains `PARTIAL`: the runtime path is no longer a scene-tree scan, but it is still registry-global rather than dirty-network or partition-local.

## G5: Revalidation and truthful closure

### Goal

Close the wave with truthful telemetry and docs, not optimistic wording.

### In scope

- live log review
- headless validation
- ADR status reconciliation
- residual backlog note

### Out of scope

- starting new foundation refactors

### Files likely involved

- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- this plan
- validation artifacts/logs

### Implementation steps

1. Run headless validation.
2. Run a fresh live session log with building, mining, save/load, and powered structures.
3. Verify:
   - no in-place load corruption
   - no stale diff replay
   - no room recompute `10-11 ms` spikes
   - power recompute no longer uses group scans
   - excavation runs through command path
4. Only then update ADR statuses.
5. If any contract is still partial, mark it partial.

### Smoke tests

- headless validation passes
- live session log is reviewed
- docs and code tell the same story

### Definition of done

- no known hole from this plan remains undocumented
- ADR closure is truthful
- residual backlog is explicit

### Execution note (2026-03-26)

- Current headless `codex_validate_runtime` passes the room, power, and mining+persistence validation cases without new parse/runtime errors.
- A fresh post-fix live gameplay log no longer shows standalone `building.room_recompute` spikes in the `10-11 ms` range; `building.room_recompute` now stays at `0.0ms` in frame-budget summaries, and late-session dispatcher summaries settle around `total=3.4ms/6.0ms`.
- Hazard A is now considered runtime-resolved: the remaining oversized path is staged and bounded rather than a single live spike source.
- `power.balance_recompute` no longer appears as a meaningful runtime offender, and the authoritative recompute path no longer depends on scene-tree group scans.
- Save/load holes from `G0/G1` are fixed in code, but a fresh manual GUI save/load session using the current build is still pending as explicit residual backlog.
- Additional residual backlog remains explicit: direct combat damage still bypasses a formal command boundary; power is still registry-global rather than partition-local; headless validation still ends with `topology catch-up timeout`.
- This plan is closed as a truth-alignment pass, not as a claim that every follow-up concern is fully resolved.

## Stop conditions

Do not continue widening this plan if any of the following happens:
- an iteration uncovers a deeper architecture conflict that needs ADR/spec changes first
- an iteration begins to reopen roof/streaming regressions
- an iteration tries to redesign building, power, save/load, and command boundaries in one pass

In those cases, stop, document the blocker, and create a narrower follow-up plan.
