# Claude Code — performance fix brief (next pass)

## Context
Current state is **better but not finished**. Interactive mining path is acceptable, crash is fixed, but there are still **visible micro-stutters** during chunk streaming and shadow rebuild.

Key measured symptoms from the latest run:
- Idle: ~16.7 ms avg, stable
- Walking without loading: ~16.7–16.9 ms avg, mostly stable
- Walking + chunk loading: ~18.5–19.5 ms avg, **p99 45–55 ms**, **24–54 hitches / 300 s**
- Mining: ~16.7 ms avg, stable
- `ChunkManager.try_harvest_at_world`: ~0.47–1.23 ms
- `MountainRoofSystem._request_refresh`: ~0.10 ms
- Streaming spikes: `streaming=17.6–23.2 ms`
- Visual spikes: `visual=13–16 ms`

## Important conclusion
Do **not** treat this as complete. Average FPS is acceptable, but frame pacing is still not. The remaining problem is **background work granularity**, not interactive path latency.

---

## What is already good enough
These parts should be preserved:

1. `ChunkManager.try_harvest_at_world()` is fast enough and must remain on the incremental path.
2. Crash is fixed.
3. `FrameBudgetDispatcher` exists and category separation is useful.
4. Runtime chunk loading is already split into staged phase 0 / phase 1.
5. Roof redraw and shadow rebuild are partially moved toward queued work.

Do not regress these.

---

## What is NOT finished

### 1) `FrameBudgetDispatcher` does not actually protect frame budget yet
Problem:
- Jobs are budgeted only at the **loop boundary**.
- If a single callable invocation is expensive, it can still blow the frame.
- Current logs show background work exceeding the intended total budget.

Meaning:
- Dispatcher currently **measures** overruns, but does not guarantee them away.

### 2) `MountainRoofSystem` still does part of the work outside the budgeted pipeline
Problem:
- `_process_cover_setup()` drains `_cover_dirty_queue` in normal `_process()`.
- This means cover setup still happens synchronously outside `FrameBudgetDispatcher`.
- Only the later redraw step is budgeted.

Meaning:
- The roof system is only half-converted to a proper queued pipeline.

### 3) Chunk streaming phase 0 is still too coarse
Problem:
- `_staged_loading_phase0()` still performs in one tick:
  - `WorldGenerator.get_chunk_data(coord)`
  - `Chunk.new()` / `setup()`
  - `populate_native(...)`
  - `set_mountain_cover_hidden(...)`
- This unit of work is still large enough to create visible spikes.

Meaning:
- Current staged loading is a good first step, but still too chunky.

### 4) Shadow rebuild is still one heavy job per chunk
Problem:
- `_tick_shadows()` pops one chunk and calls `_build_chunk_shadow(coord)`.
- `_build_chunk_shadow()` still performs a large monolithic rebuild:
  - create image
  - iterate edge sources
  - run Bresenham rays
  - read/write pixels
  - create texture

Meaning:
- Visual spikes are expected as long as one tick == one full chunk shadow build.

### 5) Incremental topology patch is fast, but may be logically incomplete
Problem:
- `_incremental_topology_patch()` updates local structures and neighbor open-state.
- It does **not** appear to handle component split/merge correctness in difficult mining cases.

Meaning:
- Performance is good, but correctness risk remains for rare topology edge cases.

---

## Required fixes (ordered)

## P0 — must fix now

### P0.1 Move `MountainRoofSystem` cover setup fully under frame budget
Files:
- `core/systems/world/mountain_roof_system.gd`

Required change:
- Remove the unbounded drain behavior from `_process_cover_setup()`.
- Convert cover setup into a budgeted step, similar to redraw.
- Each tick should process only a small number of dirty chunk coords.
- `update_chunk_cover(coord)` must happen inside the budgeted path, not in plain `_process()`.

Acceptable structure:
- one queue for `dirty coords`
- one queue for `chunks awaiting progressive redraw`
- both queues advanced only from budgeted tick functions

Acceptance:
- No synchronous full drain of `_cover_dirty_queue` in `_process()`.
- Cover setup work appears under `visual` budget only.

### P0.2 Break shadow rebuild into smaller units than “one full chunk”
Files:
- `core/systems/lighting/mountain_shadow_system.gd`

Required change:
- Replace one-shot `_build_chunk_shadow(coord)` work units with progressive work.
- A single dispatcher tick must not rebuild a full chunk shadow from scratch.

Possible implementations:
- per-row / row-band image generation
- per-batch of edge tiles
- incremental buffer build with finalize step

Constraints:
- Keep edge cache optimization.
- Do not revert to full world rebuilds.

Acceptance:
- `visual` spikes from shadow rebuild should no longer jump into ~13–16 ms territory from a single chunk task.
- One tick should represent only a small slice of shadow work.

### P0.3 Split chunk loading phase 0 into finer-grained sub-phases
Files:
- `core/systems/world/chunk_manager.gd`
- possibly `core/systems/world/chunk.gd`
- possibly `WorldGenerator` / related generator code

Required change:
- Current phase 0 is still too large.
- Split it into smaller stateful steps.

Target structure example:
1. acquire/generate chunk data
2. instantiate chunk node
3. setup chunk
4. populate bytes / saved modifications
5. attach to scene tree
6. enqueue progressive redraw
7. topology registration / cover state finalize

Important:
- If `WorldGenerator.get_chunk_data()` is still a hard monolith, reduce the size of the rest of the phase anyway.
- Do not claim “threading is the only next step” until main-thread granularity is actually exhausted.

Acceptance:
- Streaming jobs must be smaller than the current 17–23 ms spikes.
- Runtime chunk loading should no longer produce frequent single-frame hitches of the current magnitude.

---

## P1 — should fix in the same pass if possible

### P1.1 Add rare-case fallback for topology split / merge correctness
Files:
- `core/systems/world/chunk_manager.gd`

Required change:
- Keep incremental patch for the common case.
- Add a conservative fallback when mining may disconnect or merge mountain components.
- A local/component rebuild fallback is acceptable.
- Full rebuild should remain rare and never happen on the hot path unless strictly necessary.

Acceptance:
- No obvious correctness risk for mountain key / open tile bookkeeping in complex mining shapes.

### P1.2 Strengthen dispatcher semantics / instrumentation
Files:
- `core/autoloads/frame_budget_dispatcher.gd`

Required change:
- Make it clearer in code and logs when a single callable unit itself is too large.
- Add instrumentation for “oversized single task” cases.
- Optionally track per-job worst-case slice time, not just category average.

Acceptance:
- Logs make it obvious which job unit is still too large.
- Dispatcher remains simple and deterministic.

---

## P2 — only after the above

### P2.1 Evaluate threading only after main-thread granularity is improved
Possible future directions:
- `WorkerThreadPool`
- threaded terrain generation
- native/C++ acceleration for generator-heavy path

Do not jump here first. First finish the main-thread pipeline cleanup above.

---

## Concrete implementation guidance

### For `MountainRoofSystem`
Target pattern:
- `_request_refresh()` only enqueues affected chunk coords
- new budgeted tick processes `N` coords from `_cover_dirty_queue`
- `update_chunk_cover(coord)` happens there
- chunks needing redraw are appended to redraw queue
- redraw queue continues through `continue_cover_redraw(...)`

### For `MountainShadowSystem`
Target pattern:
- replace `_dirty_queue: Array[Vector2i]` with a queue of rebuild tasks/state objects
- each task stores chunk coord + partial progress
- `_tick_shadows()` advances one task slice
- texture finalize only when image generation is complete

### For `ChunkManager`
Target pattern:
- replace the current `_staged_chunk` / `_staged_coord` two-step state with a richer load task state object
- each tick advances exactly one small step
- avoid large combined work inside a single callable

---

## Non-goals
- Do not rewrite the whole world system.
- Do not remove the dispatcher.
- Do not revert to synchronous full redraw/full rebuild approaches.
- Do not optimize only for average FPS; optimize for hitch reduction and frame pacing.

---

## Final acceptance criteria
This pass is successful only if all of the following are true:

1. Interactive path remains fast:
   - `try_harvest_at_world < 2 ms`
   - roof refresh trigger remains cheap
2. No synchronous unbounded queue drains remain in roof/shadow/runtime streaming paths.
3. Background work is split into genuinely small slices.
4. Walking + chunk loading shows a substantial hitch reduction relative to current `p99 45–55 ms` and `24–54 hitches / 300 s`.
5. Shadow rebuild no longer causes regular visible single-frame spikes from full-chunk jobs.
6. Any remaining limitation is explicitly identified with measured evidence, not assumption.

---

## Deliverables expected from Claude Code
1. Code changes
2. Short explanation of the new task slicing model
3. Before/after performance numbers
4. Explicit note of anything still limited by `WorldGenerator.get_chunk_data()` after the refactor
