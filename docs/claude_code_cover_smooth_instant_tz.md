# Claude Code — TZ: smooth cave roof show/hide without delayed redraw

## Problem
The previous roof/cover optimization solved frame spikes, but created bad UX:
- when entering the cave, roof disappears too late
- when exiting the cave, roof appears too late
- the player sees the wrong state for too long

The attempted "hide fast" tuning was reverted because it made reveal/hide timing worse overall.

We need a **different approach**, not another queue tuning pass.

---

## Key conclusion
Do **not** solve this with threading.

Why:
- the current issue is not expensive background computation
- the issue is delayed cover state application / progressive tile redraw on the main thread
- cover visibility is a visual scene-layer problem, not a chunk generation bottleneck
- moving chunk generation to worker threads will not make cave roof enter/exit transitions feel immediate

So this pass must focus on the cover UX architecture itself.

---

## Desired UX
Roof transitions should feel like this:
- when entering a cave / mountain interior, the nearby roof should start disappearing immediately and feel smooth
- when exiting, the nearby roof should start closing immediately and feel smooth
- distant chunks may finish later if needed
- the player must not wait seconds for the correct nearby roof state

In short:

## UX rule
**Immediate local correctness + smooth visual transition**

Not:
- huge synchronous redraw of everything
- not:
- extremely slow progressive redraw of everything

---

## Scope
Relevant files:
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/world/chunk.gd`
- possibly `core/systems/world/chunk_manager.gd` only if ordering/context is needed

Do not touch threaded chunk generation in this pass.
Do not rework chunk streaming.
Do not optimize shadow again.

---

## Current architectural issue
Current cover system ties visual correctness too directly to progressive tile redraw.
That creates a bad tradeoff:
- redraw fast => spikes
- redraw slowly => delayed visibility state

We need to split the problem into two layers:

1. **Immediate nearby state correction**
   - so the player sees the right result near them immediately

2. **Smooth visual transition**
   - so the roof does not pop harshly

3. **Progressive completion for the rest**
   - so distant or less important chunks can still be handled in a budgeted way

---

## Required implementation direction
Use a hybrid approach.

## P0.1 Introduce an urgent local cover path for nearby chunks
When cave enter/exit happens:
- identify the most important nearby affected chunks first
- apply the new cover state for those chunks immediately or near-immediately
- do not wait for the long generic progressive queue before nearby correctness is visible

Important:
- this urgent path must be limited to a small number of nearby chunks only
- do not synchronously redraw the whole affected mountain/component in one frame

Suggested target:
- the chunks nearest to the player / cave entrance area become visually correct first
- outer affected chunks may still complete progressively afterward

Acceptance:
- nearby roof starts changing immediately on enter/exit
- player no longer sees obviously wrong roof state for several seconds

---

## P0.2 Add smooth fade for the nearby roof transition
Do not rely on tile redraw speed alone to create good UX.

Add a visual transition for the nearby cover change:
- entering cave: nearby roof visually fades out
- exiting cave: nearby roof visually fades back in

Use the smallest safe mechanism that fits current architecture.
Possible implementations:
- per-chunk alpha tween / modulate tween on the nearby cover layer
- a dedicated temporary transition state for nearby chunks
- another simple bounded visual transition mechanism

Important:
- do not build a huge overengineered system
- use the simplest approach that produces smooth nearby roof transitions

Acceptance:
- enter/exit feels visually smooth instead of delayed or popping
- transition begins immediately for nearby chunks

---

## P0.3 Keep progressive redraw only for the non-urgent remainder
After nearby chunks are corrected and transitioning smoothly:
- the rest of the affected chunks may still use the existing budgeted progressive path
- that preserves frame safety

This means the system should become hybrid:
- urgent local update for player-facing correctness
- progressive budgeted completion for the rest

Acceptance:
- no more all-or-nothing dependence on the long cover queue
- local UX becomes good without bringing back global spikes

---

## P0.4 Separate transition semantics from queue semantics
Do not try another tuning-only solution like:
- only changing rows per step
- only changing queue ordering
- only making hide/reveal more aggressive globally

The previous attempts show that queue tuning alone is not enough.

Required design shift:
- nearby visual correctness must not depend entirely on finishing many progressive redraw slices

Acceptance:
- code clearly distinguishes urgent local transition from bulk progressive completion

---

## Strong recommendations for implementation
A good minimal architecture would look like this:

### In `MountainRoofSystem`
- detect cave state transition (enter / exit)
- compute affected chunks
- split them into:
  - high-priority nearby chunks
  - normal/background chunks
- send only nearby chunks through an urgent transition path
- send the rest into the existing progressive pipeline

### In `Chunk`
Provide a way to support nearby immediate/smooth cover transition.
This may involve one of these minimal strategies:
- a limited immediate cover rebuild for a chunk plus alpha tween
- a limited immediate cover visibility state swap plus fade
- another equally simple chunk-local approach

Do not choose a solution that still makes the player wait on dozens of progressive slices before the nearby roof looks correct.

---

## Constraints
- no broad rewrite of the roof system
- no speculative shader overhaul unless absolutely necessary
- no threading work here
- no unbounded full redraw of all affected chunks
- no return to the old frame-spike behavior

---

## Acceptance criteria
This task is successful only if all of the following are true:

1. When entering a cave, nearby roof starts disappearing immediately and feels smooth.
2. When exiting a cave, nearby roof starts reappearing immediately and feels smooth.
3. The player no longer waits several seconds for the correct nearby roof state.
4. Only a limited nearby subset is handled urgently; the rest may still complete progressively.
5. The solution does not reintroduce the old severe frame spikes.
6. The solution is architecturally different from the reverted queue-tuning-only approach.

---

## Deliverables expected from Claude Code
1. code changes implementing the hybrid urgent-local + smooth-transition roof behavior
2. short explanation of how nearby chunks are handled differently from background chunks
3. before/after UX notes specifically for cave enter/exit
4. perf notes confirming no major frame pacing regression
