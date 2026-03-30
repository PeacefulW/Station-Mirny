---
title: Agent Task — Mountain Cover / Variant Fix
doc_type: execution_task
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-03-30
related_docs:
  - mountain_roof_system_refactor_plan.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
---

# Agent Task — Mountain Cover / Variant Fix

## Iteration Goal

Deliver one **targeted** runtime fix iteration for mountain exterior tile application so that:

1. wall/rock **variant selection actually works** again;
2. mountain **cover tiles use the correct neighbor-driven shape**, instead of a coarse fallback;
3. cover presentation keeps the same art identity as the visible mountain wall layer before/after mining/reveal.

This is a **single-iteration corrective patch**, not a new rendering redesign.

## Problem Summary

Current runtime behavior shows three concrete issues in mountain tile presentation:

### 1. Atlas wall variation is disabled in runtime selection
`core/systems/world/chunk.gd::_resolve_variant_atlas(...)` currently always returns variant `0`.

Effect:
- atlas wall variants never rotate through the available sprite sets;
- mountains look too repetitive;
- user-facing variability appears broken.

### 2. Surface mountain presentation effectively loses most randomization
For the visible wall layer, alternative tile selection is gated in a way that suppresses flip alternatives on the surface path.

Effect:
- surface mountains get even less perceived variation than intended;
- cover/reveal can look more repetitive than underground runtime visuals.

### 3. `cover_layer` shape selection is too coarse
`core/systems/world/chunk.gd::_redraw_cover_tile(...)` currently resolves cover base shape through `_cover_rock_atlas(...)`, which only returns a coarse fallback (`WALL_SOUTH` / `WALL_INTERIOR`) instead of a full neighbor-driven wall visual class.

Effect:
- cover tiles can visually disagree with the actual local mountain geometry;
- user-visible shell can look like the wrong tile was applied;
- reveal/restoration can preserve identity poorly.

## Scope

### In scope

Patch only the runtime tile selection/presentation logic necessary to fix:
- atlas variant selection;
- surface flip/alternative usage where appropriate;
- cover-layer base-shape selection parity with mountain wall geometry.

### Out of scope

Do **not** in this iteration:
- redesign `MountainRoofSystem` authority;
- redesign chunk streaming;
- redesign cliff overlay composition;
- add a brand-new art pipeline;
- broaden the patch into unrelated roof/fog systems.

## Files To Modify

Primary expected files:
- `core/systems/world/chunk.gd`

Possible secondary touchpoints only if truly required:
- `core/systems/world/chunk_tileset_factory.gd`
- lightweight validation helpers/tests if the repo already has an established place for them

## Required Changes

### A. Re-enable atlas wall-variant selection

In `core/systems/world/chunk.gd`:
- replace the hardcoded `variant 0` behavior in `_resolve_variant_atlas(...)`;
- select `variant_index` from a stable deterministic tile hash;
- use `ChunkTilesetFactory.wall_variant_count` as the upper bound;
- preserve deterministic per-tile output across redraws/save-load.

Required behavior:
- if `wall_variant_count <= 1`, behavior remains safe and identical to today;
- if `wall_variant_count > 1`, different wall tiles across the world can pick different atlas variants;
- the choice must remain spatially stable for the same global tile.

### B. Restore intended alternative/flip variability for surface mountain presentation

In `core/systems/world/chunk.gd`:
- audit how `_resolve_variant_alt_id(...)` is invoked for mountain wall presentation;
- ensure surface mountain rendering is not unintentionally locked out of allowed alternative-tile flips;
- keep behavior deterministic and bounded by `ChunkTilesetFactory._WALL_FLIP_CLASS` and `wall_flip_alt_count`.

Important rule:
- do **not** introduce random flicker across redraws;
- do **not** use non-deterministic RNG;
- use the existing stable hash-driven path.

### C. Make `cover_layer` choose the correct wall form

In `core/systems/world/chunk.gd`:
- stop using the coarse `_cover_rock_atlas(...)` fallback as the primary shape authority for cover presentation;
- make cover select its **base wall class** from the same or equivalent neighbor-driven geometry logic used by visible mountain wall rendering;
- after that, resolve atlas variant and alternative tile id using the same deterministic rules as the visible wall layer.

Goal:
- cover restoration should preserve mountain shell identity instead of collapsing to a generic south/interior fallback;
- tiles near corners/peninsulas/corridors/notches should use the correct visual class.

Implementation note:
- prefer extracting/reusing a shared helper over duplicating wall-shape logic in multiple places.

## Guardrails

1. Keep the patch local and surgical.
2. Do not widen `MountainRoofSystem` responsibilities.
3. Do not introduce non-deterministic random calls for tile choice.
4. Do not add heavy per-frame recomputation.
5. Do not break underground fog or local-zone reveal semantics.
6. Do not change saved world truth formats for this iteration.

## Acceptance Criteria

The iteration is done only if all of the following are true:

### Visual correctness
- surface mountain walls no longer appear locked to a single atlas variant everywhere;
- cover tiles use the correct neighbor-driven wall form instead of obvious generic fallback placement;
- cover hide/show after mining/reveal restores the same mountain identity expected for that tile;
- corners/corridors/peninsulas do not collapse into `WALL_SOUTH` / `WALL_INTERIOR` unless that is genuinely the correct class.

### Runtime correctness
- tile choice remains deterministic for the same global tile across redraws;
- no flicker appears when chunks redraw progressively;
- no save/load pollution is introduced;
- no new runtime errors or parse errors appear.

### Scope discipline
- patch remains limited to this presentation bugfix area;
- no opportunistic refactor of unrelated world systems is mixed into the change.

## Suggested Validation

### Manual validation
1. Load a surface mountain-heavy area.
2. Inspect a broad mountain face:
   - confirm atlas variants are not all identical.
3. Inspect corners / indentations / peninsulas:
   - confirm cover geometry matches expected wall form.
4. Mine into a mountain and expand a small pocket.
5. Exit / re-enter / force redraw conditions if available.
6. Confirm restored shell still matches the expected local wall class and stable variant identity.

### Code-level validation
- verify `_resolve_variant_atlas(...)` no longer hardcodes variant `0`;
- verify cover path and visible wall path both use the same deterministic variant policy;
- verify `set_cell(..., atlas, alt_id)` is correctly applied for cover where supported.

## Deliverable Format

Agent should produce:
1. a single focused patch/PR for this iteration;
2. a concise implementation note summarizing exactly which runtime rules changed;
3. before/after validation notes tied to the acceptance criteria above.

## Non-Negotiable Constraint

This iteration is a **bugfix slice**, not an architecture rewrite.
Solve the concrete tile selection and cover-shape defects first, with the smallest clean patch that restores intended behavior.
