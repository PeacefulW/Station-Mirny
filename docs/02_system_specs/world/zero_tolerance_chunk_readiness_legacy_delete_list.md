---
title: Zero-Tolerance Chunk Readiness Legacy Delete List
doc_type: system_spec_addendum
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-13
depends_on:
  - zero_tolerance_chunk_readiness_spec.md
related_docs:
  - chunk_visual_pipeline_rework_spec.md
---

# Addendum: Forbidden legacy patterns to delete first

This addendum exists to make the parent spec operationally unambiguous.

Parent spec:

- `docs/02_system_specs/world/zero_tolerance_chunk_readiness_spec.md`

Intent:

- list the legacy runtime patterns that must be deleted early
- prevent agents from "keeping the old path for safety"
- prevent soft-readiness behavior from being reintroduced under a different name

These are not optional cleanups. They are first-wave deletions.

## 1. `first_pass_ready` as permission for player entry

Delete any logic where:

- `first_pass_ready` is treated as sufficient for player occupancy
- a chunk can be visible, traversable, or enterable before terminal readiness
- a first-pass state is used as a hidden substitute for final publication

Reason:

- this directly violates the zero-tolerance readiness contract

## 2. `full_redraw later` semantics

Delete any logic where:

- a chunk is published now and finalized later
- cliffs, seams, roof, flora, shadows, or overlays are allowed to catch up after entry
- the runtime accepts delayed convergence as normal for player-reachable chunks

Reason:

- this is the exact old behavior the parent spec forbids

## 3. Any critical GDScript fallback in the chunk pipeline

Delete any fallback path for:

- chunk generation
- prebaked visual payload generation
- critical near/player visual batch computation
- critical final-publication computation

Reason:

- if the native implementation is missing, the feature is incomplete
- the correct action is to implement native support, not preserve fallback

## 4. Shared worker saturation that can starve frontier work

Delete any scheduling model where:

- far/background tasks can occupy all worker capacity
- player/frontier tasks can repeatedly requeue because of compute-cap exhaustion
- queue fairness is valued above frontier correctness

Reason:

- player/frontier readiness is a product invariant, not a fair-share scheduling preference

## 5. Publication before seam-complete / flora-complete / final-layer-complete

Delete any publication rule where the chunk can be considered playable while any final layer is still pending.

This includes publication before completion of:

- flora
- cliffs
- seam repair
- roof / cover correctness
- lighting / shadows required for final presentation
- final overlays

Reason:

- the parent spec defines `full_ready` as all-inclusive, including flora and cosmetics

## 6. Compatibility helpers whose only purpose is to preserve the old soft model

Delete helpers, states, and adapters whose only purpose is to keep the old phased runtime alive.

Examples include:

- compatibility redraw helpers kept only because some old path still depends on them
- dual-path state machines where one branch preserves legacy convergence semantics
- temporary adapters that silently convert hard readiness requirements back into soft readiness behavior

Reason:

- these helpers are where deleted behavior comes back to life

## 7. Two-track semantics where diagnostics are strict but runtime behavior is permissive

Delete any architecture where:

- diagnostics say the player should not be on the chunk
- runtime still allows movement / visibility / occupancy anyway
- breach is logged as a warning instead of treated as correctness failure

Reason:

- observability without enforcement preserves the broken runtime under a nicer dashboard

## 8. Hidden redefinition of `full_ready`

Delete any attempt to redefine `full_ready` to mean:

- final enough
- terrain plus essentials
- ready except cosmetics
- visually acceptable for now
- good enough under load

Reason:

- the parent spec already defines `full_ready`; redefining it is an architectural violation

## Expected first-wave deletion checklist

Before any frontier runtime rewrite is considered complete, the implementation plan must explicitly name and remove:

- all critical fallback entry points
- all publish-now / finish-later paths for player-reachable chunks
- all readiness gates based on first pass rather than terminal readiness
- all worker-pool policies that allow frontier starvation
- all compatibility adapters that preserve hybrid behavior

## Definition of done for this addendum

This addendum is satisfied only when the implementation artifacts clearly show that the listed legacy patterns were deleted, not merely deprioritized or bypassed.
