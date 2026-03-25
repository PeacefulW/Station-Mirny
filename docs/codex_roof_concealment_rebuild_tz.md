# Codex TZ — rebuild cave roof concealment model from the current reverted baseline

## Current baseline
Do **not** revert anything else.
Claude already reverted the failed sync-diff roof experiment.
Start from the current working baseline where:
- chunk streaming improvements remain
- shadow improvements remain
- roof system is back to the older stable-but-slow behavior

This task is **only** about redesigning the cave roof concealment model.

---

## Why this task exists
We have already proven both failure modes:

### Failure mode A — progressive redraw roof model
- frame-safe enough after budgeting
- but nearby roof opens/closes too slowly
- player sees wrong roof state for too long
- entering/exiting a cave feels delayed and bad

### Failure mode B — sync diff-based roof model
- attempted immediate tile-diff update on enter/exit
- caused catastrophic stalls in `MountainRoofSystem._request_refresh`
- runtime warnings reached hundreds of milliseconds and even multi-second stalls
- completely unacceptable

Conclusion:
- queue tuning is not enough
- sync `TileMapLayer` diff-apply is also not acceptable
- the **model itself** must change

---

## Core diagnosis
A simple UX event:
- player enters cave
- player exits cave

must **not** translate into a workload whose core operation is rewriting many cover tiles.

That is the root architectural flaw.

The correct model should make roof concealment primarily a **cheap visual state change**, not a tile-rewrite workflow.

---

## Hard rules

### Rule 1
Do **not** build another solution whose enter/exit hot path fundamentally depends on mass `TileMapLayer` updates such as:
- large `erase_cell()` batches
- large `set_cell()` batches
- sync diff application over many affected tiles
- progressive redraw being the main near-player UX mechanism

### Rule 2
Do **not** solve this with threading.
Threading is for chunk generation, not for roof UX.
This problem is about the visual application model, not expensive background computation.

### Rule 3
Do **not** ship another queue-tuning-only attempt.
Changing only:
- rows per step
- queue ordering
- chunks per tick
- hide vs reveal aggressiveness
is not enough.

---

## Target architecture

## 1) Separate logic from visual application
Keep the gameplay/topology logic conceptually:
- detect whether player is on opened mountain tiles
- determine active mountain key
- determine affected chunks / active mountain membership

But change how this is applied visually.

`MountainRoofSystem` should remain a **state coordinator**.
It should stop acting as a system whose player-facing correctness depends on redrawing many cover tiles.

---

## 2) Introduce a persistent chunk-local roof visual representation
Each chunk should have a roof visual representation that is already present and can be controlled cheaply.

Acceptable implementation directions:
- a dedicated chunk-local roof overlay node/layer whose visibility/alpha can be changed cheaply
- a persistent roof visual representation separate from heavy cover tile mutation logic
- another equivalent chunk-local visual model with the same runtime behavior

Important:
- choose the simplest robust design that fits the current project
- do not overengineer it
- but the result must be **architecturally different** from the old redraw-based model

The runtime transition target is:
- change visual state cheaply
- not rewrite many roof tiles at enter/exit time

---

## 3) Nearby transitions must be immediate and smooth
When entering a cave:
- nearby roof should start disappearing immediately
- transition should feel smooth

When exiting a cave:
- nearby roof should start reappearing immediately
- transition should feel smooth

Strong recommendation:
- implement this through cheap visual state control such as visibility / alpha / modulate / tween on the roof visual representation
- not through large tile updates

Acceptance:
- the player no longer waits seconds for the nearby roof to become correct
- the transition begins right away near the player

---

## 4) Hybrid behavior is allowed
Not every affected chunk must complete instantly.

Correct target behavior:
- nearby chunks: immediate correct visual state + smooth transition
- farther chunks: may complete later if some background maintenance is still needed

This is acceptable because player UX depends mainly on the nearby visible area.

But near-player correctness must no longer depend on draining a large redraw queue.

---

## 5) Any remaining background work must become secondary
If some background completion path still exists after the redesign, that is acceptable.
But it must be secondary.

The primary near-player UX result must come from the new cheap visual model, not from waiting for bulk redraw completion.

---

## Recommended implementation shape
This is guidance, not a mandatory class diagram.

### In `MountainRoofSystem`
- detect active mountain transitions as before
- determine affected chunks as before
- immediately apply target visual state to nearby chunks
- trigger smooth transition
- optionally schedule non-urgent completion for the rest if still needed

### In `Chunk`
- introduce a persistent roof visual representation
- keep it ready so enter/exit mostly changes visibility/alpha/transition state
- avoid reauthoring the roof content at every enter/exit

### In the old cover redraw path
- either reduce it drastically
- or keep it only for setup/non-urgent maintenance
- but do not leave it as the main near-player concealment mechanism

---

## Explicit anti-patterns to avoid
Do **not** deliver any of these:
- another sync diff-based `erase_cell/set_cell` approach in `_request_refresh`
- another progressive redraw queue that still controls near-player UX correctness
- another solution that works only by retuning budget numbers
- another solution that makes nearby enter/exit wait on many chunk slices

---

## Files likely involved
At minimum, expect to work in:
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/world/chunk.gd`
- possibly `core/systems/world/chunk_manager.gd` only if needed for chunk ordering/context

Do not change chunk threading/generation here.
Do not rework shadow here.

---

## Acceptance criteria
This task is successful only if all of the following are true:

1. Entering a cave makes nearby roof start disappearing immediately and smoothly.
2. Exiting a cave makes nearby roof start reappearing immediately and smoothly.
3. Nearby correctness no longer depends on bulk cover-tile redraw.
4. Runtime roof transitions are primarily cheap visual state changes.
5. No large stalls appear in `MountainRoofSystem._request_refresh`.
6. The result is architecturally different from both:
   - the old budgeted progressive redraw model
   - the failed sync diff-based model
7. The code clearly explains the separation between:
   - logical active-mountain state
   - chunk-local roof visual representation
   - optional secondary background completion

---

## Deliverables expected from Codex
1. code changes implementing the new roof concealment model
2. short explanation of the new architecture
3. before/after UX notes for cave enter/exit
4. perf notes confirming there is no major frame pacing regression
5. explicit explanation of why the new model is superior to the old redraw-based model
