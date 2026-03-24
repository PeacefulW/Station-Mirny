# Claude Code — performance fix brief (pass 3, finalize decomposition)

## Goal
The latest profiling isolated the remaining major runtime hitch source much more precisely:
- shadow system is no longer the problem
- cover likely improved and is now secondary
- the main remaining streaming problem is inside `ChunkStreaming.phase2_finalize`

This pass is **only** about decomposing and diagnosing `phase2_finalize`.
Do not do a broad refactor.

---

## What is already known
Current measured chunk streaming phases:
- `phase0_generate`: ~13–15 ms
- `phase1_create`: ~0.10–0.21 ms
- `phase2_finalize`: ~16–36 ms

This means:
- `phase1_create` is not the issue
- `phase0_generate` is still expensive and remains a likely threading candidate
- but `phase2_finalize` is currently even more dangerous for frame pacing

At the moment, saying “it is definitely `add_child()`” is still only a strong hypothesis.
We need proof.

---

## Required work

## P0.1 Decompose `ChunkStreaming.phase2_finalize` into sub-metrics
Files:
- `core/systems/world/chunk_manager.gd`

Required change:
Inside `_staged_loading_finalize()`, add separate `WorldPerfProbe` timing around each meaningful sub-step.

At minimum, split and log these independently:
1. `ChunkStreaming.finalize.add_child`
2. `ChunkStreaming.finalize.register_topology`
3. `ChunkStreaming.finalize.emit_chunk_loaded`
4. `ChunkStreaming.finalize.enqueue_redraw`
5. `ChunkStreaming.finalize.total`

If the actual order/structure differs, keep the measurements semantically equivalent.

Goal:
Identify exactly which sub-step dominates `phase2_finalize`.

Acceptance:
- logs clearly show per-substep timings
- it becomes obvious whether the main cost is:
  - scene tree attach / rendering activation
  - topology registration
  - event emission / downstream listeners
  - something else in finalize

---

## P0.2 If event emission is expensive, identify the subscriber side
Files:
- `core/systems/world/chunk_manager.gd`
- any systems reacting to `EventBus.chunk_loaded`

Required change:
Only if logs suggest `emit_chunk_loaded` is expensive:
- instrument the major subscribers triggered by `EventBus.chunk_loaded`
- do not instrument everything blindly; only the obvious listeners on the hot path

Goal:
Avoid blaming `emit` itself if the real cost is in subscriber work.

Acceptance:
- if `emit_chunk_loaded` is cheap, say so explicitly
- if it is expensive, identify which subscriber path is responsible

---

## P0.3 Apply only a small safe follow-up optimization if the culprit is obvious
After decomposition, only implement a fix if it is narrow and low-risk.

Examples of acceptable fixes:
- reorder finalize steps to reduce attach cost
- defer a non-critical post-attach step
- move expensive subscriber work to a budgeted queue
- attach a lighter node state first, then complete setup progressively

Non-goals:
- no broad architectural rewrite
- no speculative threading work in this pass
- no large changes to chunk loading design unless the metrics make it unavoidable

Acceptance:
- either a small safe fix is implemented
- or the pass ends with a precise diagnosis and a justified next-step recommendation

---

## Decision expected after this pass
At the end, provide one of these evidence-based conclusions:

### Option A
`phase2_finalize` is dominated by scene-tree attach / rendering activation cost, and the next step is to restructure how/when the chunk becomes visually active.

### Option B
`phase2_finalize` is dominated by topology or event-subscriber work, and that work should be re-budgeted or deferred.

### Option C
`phase2_finalize` is not dominated by one single cause; provide the real breakdown percentages and the smallest next improvement.

---

## Constraints
- keep current instrumentation style consistent
- do not regress mining latency
- do not regress shadow improvements
- do not broaden scope back to “optimize everything”
- prefer measurement and proof over intuition

---

## Deliverables expected from Claude Code
1. code changes for `phase2_finalize` sub-metrics
2. optional small safe fix, only if strongly justified
3. logs with clear per-substep numbers
4. explicit conclusion about the real dominant cost inside finalize
5. recommendation for the next pass after that
