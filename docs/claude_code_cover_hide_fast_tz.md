# Claude Code — TZ: make cave roof hide fast after player exits mountain

## Problem
After the recent performance work, roof/cover redraw became very safe for frame pacing, but the UX regressed:
- when the player leaves the cave / mountain interior
- the roof over the mountain reappears too slowly
- the base inside the mountain remains visible for several seconds

This is not acceptable UX even if FPS is stable.

We need a targeted fix with this rule:

## UX rule
**Hide must be fast.**
When the player exits the mountain, the nearby cave roof must close quickly enough to hide the base almost immediately.

At the same time:
- do not reintroduce the old visual spikes
- do not revert to unbounded synchronous full redraw

---

## Scope
Focus only on the cave roof / cover pipeline.

Relevant files:
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/world/chunk.gd`
- possibly `core/systems/world/chunk_manager.gd` only if needed for priority/order information

Do not touch threaded chunk generation in this pass.
Do not do a broad performance refactor.

---

## Current issue hypothesis
The current budgeted cover system is too conservative:
- work is split into safe slices
- each slice is cheap enough for frame pacing
- but there are too many slices before full roof restoration completes

Result:
- visually safe
- UX too slow

We need to rebalance toward:
- **fast hide near the player / active mountain exit area**
- still budgeted, but more aggressive than now

---

## Required behavior

## P0.1 Prioritize hide-on-exit over generic cover redraw
When the player exits the mountain and cover needs to close again:
- prioritize the chunks that matter most for quickly hiding the interior/base
- do not process cover chunks in a naive generic order if a more relevant order is possible

Target behavior:
- chunks closest to the player / relevant exit area should redraw first
- distant chunks may complete later

Acceptance:
- visible nearby mountain roof closes first
- the base is hidden quickly even if some distant cover redraw is still in progress

---

## P0.2 Make hide mode more aggressive than reveal mode
Different UX importance:
- reveal can be gradual
- hide must be fast

Implement a mode distinction if needed:
- when entering / revealing mountain interior → current conservative behavior may stay
- when exiting / hiding the interior again → allow more aggressive redraw

Acceptable mechanisms:
- larger `rows_per_step` for hide than for reveal
- more than one cover chunk per tick for hide mode if budget allows
- a temporary burst mode for the first few ticks after exit

Important:
- keep this bounded and deterministic
- no return to synchronous full redraw of all affected chunks in one frame

Acceptance:
- hide completes substantially faster than current behavior
- no severe frame pacing regression

---

## P0.3 Use available visual budget more intelligently
Recent logs showed that the system often had visual budget headroom while still taking a long time to finish cover restoration.

Required change:
- if there is safe room to process more cover work, use it
- avoid a policy that is so strict that the queue lives for seconds

This can be implemented by:
- processing multiple cover chunks in one tick when they are in hide mode
- or dynamically increasing rows per step during hide mode
- or both

Acceptance:
- cover queue drains faster in the exit/hide case
- visual cost stays controlled

---

## P0.4 Preserve frame safety
This pass is **not** successful if it simply restores the old spikes.

Constraints:
- no unbounded draining in `_process()`
- no full synchronous redraw of all affected cover chunks in one frame
- no large visual spikes comparable to the old regressions

Acceptance:
- roof closes much faster
- frame pacing remains clearly better than the old pre-budgeted implementation

---

## Recommended implementation direction
Use the smallest safe change that improves UX.

A good approach would be something like this:

### In `MountainRoofSystem`
- detect when the transition is specifically a **hide** transition (player leaving mountain / active mountain becoming invalid)
- enqueue affected chunks in a priority order (nearest first / most relevant first)
- during hide mode, process cover work more aggressively than normal

### In `Chunk` / cover redraw
- allow a separate hide-mode redraw speed, e.g. larger row step than reveal mode
- keep the redraw progressive, not synchronous

This should feel like:
- nearby roof snaps back quickly
- full restoration may continue for a short time afterward
- the player does not see the base exposed for several seconds

---

## Non-goals
- do not redesign the whole roof system
- do not change chunk streaming / threading here
- do not optimize shadow again
- do not add speculative complexity unrelated to hide UX

---

## Acceptance criteria
This task is successful only if all of the following are true:

1. After the player exits the mountain, nearby roof cover closes quickly enough to hide the base almost immediately.
2. Hide behavior is noticeably faster than the current gradual redraw.
3. Nearby/relevant chunks are prioritized over distant ones.
4. The cover pipeline remains budgeted and bounded.
5. No major regression in frame pacing is introduced.
6. Reveal behavior may remain gradual if needed; hide is the priority.

---

## Deliverables expected from Claude Code
1. code changes for fast hide behavior in the roof/cover system
2. short explanation of how hide mode differs from normal/reveal mode
3. before/after perf and UX notes
4. explicit confirmation that the fix improves concealment speed without reintroducing large spikes
