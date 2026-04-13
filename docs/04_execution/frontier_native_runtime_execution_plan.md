---
title: Frontier Native Runtime Execution Plan
doc_type: execution_plan
status: draft
owner: engineering+design
source_of_truth: false
version: 0.1
last_updated: 2026-04-13
related_docs:
  - ../02_system_specs/world/zero_tolerance_chunk_readiness_spec.md
  - ../02_system_specs/world/zero_tolerance_chunk_readiness_legacy_delete_list.md
  - ../02_system_specs/world/frontier_native_runtime_architecture_spec.md
  - ../02_system_specs/world/DATA_CONTRACTS.md
  - ../00_governance/PUBLIC_API.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/SIMULATION_AND_THREADING_MODEL.md
---

# Frontier Native Runtime Execution Plan

This document sequences the rewrite from the current legacy chunk runtime to the new frontier-native runtime.

It does not override:

- governance docs
- system specs
- public/data contracts

The source of truth remains the spec stack:

- `zero_tolerance_chunk_readiness_spec.md`
- `zero_tolerance_chunk_readiness_legacy_delete_list.md`
- `frontier_native_runtime_architecture_spec.md`

This plan exists so agents can execute the rewrite in narrow, reviewable waves instead of creating another hybrid runtime.

## Core execution rule

Hard rule:

- one iteration per run
- do not bundle multiple iterations into one patch
- do not preserve old behavior "for safety" if the spec explicitly forbids it
- if an iteration discovers that the current docs are wrong, fix docs in the same run or stop and report
- if a fix requires breaking internal APIs, break them cleanly instead of adding adapters that preserve forbidden legacy semantics

## Why this plan exists

The project currently suffers from the worst possible middle state:

- partial native generation
- script fallback still alive in critical paths
- publish-now / finish-later semantics
- worker starvation between far work and player-relevant work
- a runtime that still allows the player to see or enter incomplete chunks

That state is harder to reason about than either:

- a clean old script runtime
- or a clean new native runtime

This plan exists to eliminate the hybrid state quickly and deliberately.

## Non-goals for this plan

This plan is not trying to:

- preserve the current runtime structure
- preserve current chunk size
- preserve old world generation output
- preserve current internal file layout
- optimize every system in the game before the world runtime is fixed

## Success condition for the whole plan

The plan is successful only when:

- current runtime is no longer the active architecture target
- visible-world and player-occupancy correctness are both guaranteed
- no player-reachable critical path depends on GDScript fallback
- walking, sprinting, vehicles, trains, and underground traversal obey the same seamless contract

## Agent guidance

Recommended execution behavior:

- medium/default model may handle documentation and deletion-only passes
- higher-effort model is preferred for runtime ownership changes, packet contract changes, and scheduler/caching redesign
- agents must not silently add compatibility shims
- agents must not widen scope beyond the current iteration

## Global stop conditions

Stop and report instead of widening the patch if any of the following occurs:

- a patch tries to keep both old and new runtime semantics alive in the same player path
- an iteration discovers that the target packet contract is not yet precise enough
- an iteration starts rewriting unrelated gameplay systems without a direct runtime dependency
- startup, underground, or train behavior becomes entangled enough to require a new spec clarification
- smoke tests fail and the agent starts widening the patch rather than reverting to a smaller iteration

## Global instrumentation rules

All runtime-facing iterations must keep or improve observability.

At minimum, the runtime must be able to report:

- player chunk readiness state
- camera-visible set readiness state
- frontier-critical queue depth
- background queue depth
- packet build latency
- publication latency
- any attempted visibility/occupancy breach before `full_ready`

## Priority order

1. `R0` Truth alignment and freeze on the old runtime
2. `R1` Delete critical fallback and publish-later permissions
3. `R2` Introduce versioned native final packet contract
4. `R3` Build native final packet pipeline for surface chunks
5. `R4` Introduce frontier planning and reserved scheduling
6. `R5` Switch publication to final-packet-only semantics
7. `R6` Underground transition contract
8. `R7` Chunk-size bake-off and residency policy
9. `R8` Vehicles and trains
10. `R9` Revalidation and closure

## Iterations

## R0: Truth alignment and legacy freeze

### Goal

Make it impossible for future work to pretend the old runtime is still acceptable.

### In scope

- doc truth alignment
- mark current runtime as legacy
- execution references
- no behavior change yet beyond explicit freeze/deprecation markers

### Out of scope

- runtime logic rewrites
- packet schema work

### Files likely involved

- `docs/02_system_specs/world/zero_tolerance_chunk_readiness_spec.md`
- `docs/02_system_specs/world/frontier_native_runtime_architecture_spec.md`
- `docs/04_execution/frontier_native_runtime_execution_plan.md`
- doc indexes if needed

### Implementation steps

1. Link this plan from any relevant world/runtime indexes.
2. Explicitly mark current chunk runtime as legacy/deprecated in docs where needed.
3. Add a short execution note that no new feature work should extend the old hybrid player path.

### Smoke tests

- docs consistently call the current runtime legacy
- no doc still describes first-pass or publish-later semantics as acceptable player behavior

### Definition of done

- a medium-strength agent can read the docs and will not assume the old runtime is still the target

## R1: Delete critical fallback and publish-later permissions

### Goal

Remove the worst hybrid escape hatches before building the new runtime.

### In scope

- deletion/blocking of critical fallback use in player-reachable paths
- deletion/blocking of publish-now / finish-later permissions in player-reachable paths
- runtime assertions/fatal diagnostics for forbidden occupancy/visibility states

### Out of scope

- final packet builder
- full frontier planner

### Files likely involved

- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk_visual_scheduler.gd`
- related runtime diagnostics files

### Implementation steps

1. Inventory all critical fallback entry points in chunk generation and critical visual paths.
2. Remove them or hard-block them in player-reachable runtime.
3. Add fatal/assert diagnostics for:
   - player occupancy of non-`full_ready` chunk
   - visibility of non-`full_ready` chunk
4. Delete any logic that still treats first-pass or delayed convergence as permission for visible/player-reachable publication.

### Smoke tests

- no critical player path silently falls back to GDScript
- logs/asserts fire if old soft-readiness states are still reached

### Definition of done

- the runtime cannot quietly preserve the old model through hidden fallback or permissive publication rules

## R2: Versioned native final packet contract

### Goal

Define the final authoritative chunk packet that future publication will consume.

### In scope

- packet schema design
- packet versioning
- exact field ownership
- docs and contracts

### Out of scope

- full runtime switch-over
- scheduler work

### Files likely involved

- native binding / packet definition files
- `core/systems/world/chunk_content_builder.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md` if read APIs change

### Implementation steps

1. Define a versioned final packet schema covering all `full_ready` layers.
2. Document ownership and invariants.
3. Remove ambiguity about which systems still owe post-publication work.
4. Ensure packet determinism assumptions are explicit.

### Smoke tests

- schema is documented and versioned
- no required `full_ready` layer is left undocumented or marked "later convergence"

### Definition of done

- final publication can be described as "apply final packet", not "apply packet and then let systems catch up"

## R3: Native final packet pipeline for surface chunks

### Goal

Make surface chunk final-packet production real.

### In scope

- surface chunk native packet generation
- removal of script-based critical completion for surface visible/player paths
- native packet validation

### Out of scope

- underground runtime
- vehicle/train prediction

### Files likely involved

- native world generation / visual packet builder sources
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk_streaming_service.gd`
- `core/systems/world/chunk_surface_payload_cache.gd`

### Implementation steps

1. Build final native surface packet production.
2. Ensure packet includes everything required for terminal surface publication.
3. Remove surface player-visible dependence on script convergence.
4. Keep packet validation strict and fail fast on incomplete packet shapes.

### Smoke tests

- surface visible chunks are publishable from final packet only
- no surface visible chunk still owes later flora/cliff/seam completion

### Definition of done

- surface chunk final publication no longer depends on progressive visible convergence

## R4: Frontier planning and reserved scheduling

### Goal

Ensure chunks are ready before visibility and before occupancy.

### In scope

- travel state resolver
- view envelope resolver
- frontier planner
- reserved frontier scheduling

### Out of scope

- underground transition
- vehicle/train tuning beyond architecture scaffolding

### Files likely involved

- new runtime ownership files such as:
  - `travel_state_resolver.*`
  - `view_envelope_resolver.*`
  - `frontier_planner.*`
  - `frontier_scheduler.*`
- `core/systems/world/chunk_manager.gd` or replacement coordinator

### Implementation steps

1. Introduce travel mode and speed-class planning inputs.
2. Resolve camera-visible set and motion frontier set explicitly.
3. Build frontier-critical/high/background queue separation.
4. Reserve critical capacity so background work cannot steal it.
5. Add observability for frontier starvation attempts.

### Smoke tests

- far/background work cannot occupy all critical worker capacity
- camera-visible chunks remain protected by frontier planning
- sprint traversal does not show visible chunk catch-up in ordinary scenarios

### Definition of done

- the runtime has explicit frontier planning and strict reserved scheduling, not just reprioritized legacy queues

## R5: Final-packet-only publication switch

### Goal

Make live chunk publication mechanical and terminal.

### In scope

- publication coordinator
- final-packet-only apply path
- removal of publish-then-finish semantics

### Out of scope

- underground transition
- train/vehicle tuning

### Files likely involved

- `publication_coordinator.*` or equivalent
- `core/systems/world/chunk_streaming_service.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_manager.gd` or replacement coordinator

### Implementation steps

1. Switch live visible/player-reachable publication to final packet only.
2. Remove any remaining permission for visible partial states.
3. Make node apply minimal and bounded.
4. Ensure a chunk becomes visible/occupiable only after final apply succeeds.

### Smoke tests

- publication no longer triggers later visible convergence debt
- visible chunks are either absent or final, with no intermediate published soft states

### Definition of done

- final packet application is the only visible-world publication path

## R6: Underground transition contract

### Goal
n
Bring stair transitions under the same zero-tolerance readiness model.

### In scope

- staircase fade/handoff
- target-envelope readiness
- underground visible-world guarantee

### Out of scope

- train/vehicle tuning

### Files likely involved

- `underground_transition_coordinator.*`
- underground chunk runtime files
- staircase/transition gameplay scripts

### Implementation steps

1. Treat underground target envelope as frontier-critical.
2. Allow fade-out before target reveal.
3. Forbid fade-in until target visible envelope is `full_ready`.
4. Remove any reveal-now / finish-later underground behavior.

### Smoke tests

- staircase transition never reveals incomplete underground world
- fade-in happens only after target envelope is ready

### Definition of done

- underground transitions obey the same contract as surface, with fade used only for layer switch, not to hide incompleteness after reveal

## R7: Chunk-size bake-off and residency policy

### Goal

Choose chunk size and cache policy based on measured contract performance, not inertia.

### In scope

- candidate chunk-size experiments
- residency/cache policy
- hot/warm/cold packet retention rules

### Out of scope

- unrelated gameplay optimization

### Files likely involved

- world balance/config files
- packet cache/residency files
- execution artifacts or benchmark notes

### Implementation steps

1. Benchmark candidate chunk sizes.
2. Measure packet build latency, publication overhead, memory residency, and seam complexity.
3. Measure sustained traversal with reversals.
4. Choose chunk size and retention policy based on contract results.

### Smoke tests

- chosen policy is justified by measurements on the baseline machine
- cache growth is policy-driven, not blind

### Definition of done

- chunk size and residency policy are intentional and documented, not leftovers from the old runtime

## R8: Vehicles and trains

### Goal

Scale the same architecture to high-speed travel.

### In scope

- travel-state planner updates for vehicles and trains
- prediction horizon tuning
- cache/frontier width tuning

### Out of scope

- unrelated vehicle gameplay work

### Files likely involved

- travel state resolver
- frontier planner
- scheduler and cache policy files
- vehicle/train gameplay integration points

### Implementation steps

1. Add vehicle speed classes and braking windows.
2. Add train speed classes and prediction horizon rules.
3. Tune frontier width and cache retention for sustained high-speed travel.
4. Validate that visible-world correctness holds at speed.

### Smoke tests

- vehicle traversal shows no visible chunk catch-up
- train traversal shows no visible chunk catch-up

### Definition of done

- high-speed traversal obeys the same seamless contract as walking/sprinting

## R9: Revalidation and closure

### Goal

Close the rewrite truthfully.

### In scope

- full run-through validation
- doc truth alignment
- residual backlog declaration

### Out of scope

- new feature work

### Files likely involved

- specs/docs touched during earlier iterations
- validation artifacts/log summaries
- this plan

### Implementation steps

1. Run long traversal tests for all supported movement modes.
2. Review logs/telemetry for any visibility or occupancy breach.
3. Confirm no critical fallback remains.
4. Update docs to reflect true final state.
5. If any contract remains partial, mark it partial instead of claiming victory.

### Smoke tests

- visible-world and occupancy tests pass on the baseline machine
- no critical fallback remains in player-reachable paths
- docs and code tell the same story

### Definition of done

- the project can honestly say the old runtime is no longer the target and the new frontier-native runtime is active

## Residual backlog rule

At the end of any iteration, if something remains incomplete, the execution artifacts must explicitly say whether it is:

- blocked
- deferred
- intentionally out of scope
- still violating the main contract

Never hide unfinished runtime debt behind optimistic wording.

## Suggested agent prompt framing

When using agents on this plan, give them instructions in this shape:

- execute exactly one iteration from `frontier_native_runtime_execution_plan.md`
- re-read all referenced specs before editing
- do not preserve legacy semantics that the specs forbid
- do not widen scope beyond the target iteration
- if docs and code disagree, fix docs or stop and report
- include smoke-test evidence and exact files changed

## Final note

A mediocre rewrite will try to keep both runtimes alive.

This plan forbids that outcome.

The whole point is to get out of the hybrid swamp quickly, in controlled slices, without giving agents room to smuggle the old behavior back in under new names.
