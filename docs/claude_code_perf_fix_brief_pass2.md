# Claude Code — performance fix brief (pass 2, narrow scope)

## Goal
The previous pass was successful. The system is now **much better**, but not fully finished.

At this point the remaining performance work is narrow and specific:
1. identify and reduce the remaining **visual finalize spikes**
2. prove with measurements whether `WorldGenerator.get_chunk_data()` is now the dominant remaining streaming bottleneck

Do **not** do a broad refactor. This pass should be small, targeted, and measurement-driven.

---

## Current accepted state
Do not regress these:
- interactive mining path is fast enough
- roof cover setup is budgeted
- shadow rebuild is progressive
- staged chunk loading is split into 3 phases
- general hitching is meaningfully reduced

---

## Remaining observed issues
From the latest measurements:
- typical `visual` tick is now around budget, but there are still **rare visual spikes ~8–11 ms**
- streaming is much better, but there are still **streaming spikes ~10–16 ms**
- likely remaining dominant source: `WorldGenerator.get_chunk_data()`
- this is not yet proven cleanly enough in logs per phase

---

## Required work

## P0.1 Add phase-specific instrumentation for chunk streaming
Files:
- `core/systems/world/chunk_manager.gd`

Required change:
Add explicit `WorldPerfProbe` timing around each staged load phase separately:
- `_staged_loading_generate`
- `_staged_loading_create`
- `_staged_loading_finalize`

Goal:
Make logs clearly show which phase still dominates.

Acceptance:
- logs include separate measurements for all 3 phases
- it is obvious from data whether generate-phase is the main remaining offender

---

## P0.2 Add explicit instrumentation around visual finalize steps
Files:
- `core/systems/lighting/mountain_shadow_system.gd`
- possibly `core/systems/world/chunk.gd`
- possibly `core/systems/world/mountain_roof_system.gd`

Required change:
Instrument the expensive finalize-like steps separately, especially:
- shadow finalize / `ImageTexture.create_from_image(...)`
- any cover redraw finalize or unusually heavy cover slice
- any large texture/layer clear or large redraw completion step

Goal:
Do not guess the source of remaining visual spikes. Measure it.

Acceptance:
- logs can distinguish:
  - progressive shadow work slices
  - shadow finalization
  - cover redraw slices / completion
- the remaining source of rare `visual` spikes is explicitly identified

---

## P0.3 Reduce finalize spike only if it is localized and cheap to fix
Required change:
After instrumentation, only fix the remaining visual spike if the fix is small and low-risk.

Examples of acceptable fixes:
- defer or stagger texture finalization
- reduce per-finalize work size
- avoid rebuilding/clearing more than necessary
- split a completion step into smaller substeps if practical

Non-goal:
Do not start another wide architectural rewrite.

Acceptance:
- if a small safe fix exists, implement it
- if not, leave the code stable and document the exact measured cause

---

## P1.1 Decide whether main-thread streaming is now exhausted
Required outcome:
Based on the new per-phase logs, state one of the following clearly:

### Option A
`WorldGenerator.get_chunk_data()` is now the dominant remaining cost, and further meaningful improvement requires threading / worker execution / native acceleration.

### Option B
There is still meaningful main-thread work outside `get_chunk_data()` that should be sliced further before considering threading.

This conclusion must be evidence-based.

---

## Constraints
- no broad refactor
- no regression in mining latency
- no regression in current roof/shadow architecture
- no “average FPS is good enough” reasoning
- prioritize proof and precise diagnosis over speculative cleanup

---

## Deliverables expected from Claude Code
1. code changes for targeted instrumentation
2. optional small safe fix for the remaining finalize spike, if clearly justified
3. before/after measurements
4. explicit conclusion:
   - whether `get_chunk_data()` is truly the remaining bottleneck
   - whether the next step should be threading or another small main-thread refinement
