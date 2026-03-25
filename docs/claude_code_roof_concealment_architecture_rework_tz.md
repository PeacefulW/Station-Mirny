# Claude Code — architectural TZ: redesign mountain roof concealment model

## Purpose
This is **not** another tuning pass.
This is a full architectural redesign of the roof concealment model.

The current model has produced two opposite failures:
- old approach: roof updates were too heavy and caused frame spikes
- new budgeted approach: roof updates became safe, but roof reveal/hide near the player became visibly delayed and unacceptable UX

This means the problem is not just numbers or queue tuning.
The problem is the **model itself**.

We must redesign roof concealment so that:
- near-player enter/exit transitions feel immediate and smooth
- concealment/reveal is cheap at runtime
- chunk cover visibility is not primarily dependent on long progressive tile redraw queues
- frame pacing remains good

---

## Required design conclusion
The current roof system is too tightly coupled to tile redraw.
That is the architectural problem.

Right now a simple UX event:
- player enters cave
- player exits cave

turns into:
- update active mountain state
- compute affected chunks
- update chunk cover state
- progressively redraw cover tile layers over time

That is the wrong abstraction for this problem.

Roof concealment should become primarily a **cheap visual state transition**, not a bulk tile rebuild workflow.

---

## High-level target model
Keep the gameplay/topology logic.
Replace the visual application model.

### Keep
- mountain topology / active mountain logic
- determination of which mountain component is currently revealed
- chunk-level knowledge of whether a chunk belongs to active mountain / hidden roof / visible roof state

### Replace
- cover visibility changing by repeatedly rebuilding many cover tiles through progressive redraw as the primary enter/exit mechanism

### New target
- cover/roof visibility should be controlled through a lightweight visual overlay or equivalent visual state layer
- nearby roof should be able to switch state immediately and then transition smoothly
- distant/non-critical updates may still complete progressively if necessary

---

## Architectural requirements

## P0.1 Decouple visual roof state from tile redraw as the primary transition mechanism
Relevant files likely include:
- `core/systems/world/chunk.gd`
- `core/systems/world/mountain_roof_system.gd`
- possibly related rendering helpers if needed

Required change:
- redesign chunk roof concealment so that changing roof visibility for a chunk does **not** primarily require iterating and repainting cover tiles at transition time
- cover tile generation may still exist as data/setup, but runtime enter/exit transitions must not depend on long redraw queues to become locally correct

Target idea:
- roof visuals should already exist in a form that can be shown/hidden/faded cheaply
- runtime transition should mostly change visual state, not rebuild it

Acceptance:
- near-player roof transitions are no longer fundamentally gated by many redraw slices

---

## P0.2 Introduce a dedicated roof visual layer / overlay model per chunk
In each chunk, the roof should be represented as a dedicated visual layer that can be controlled cheaply.

Acceptable implementation directions include:
- a chunk-local roof overlay node/layer with fast visibility/modulate control
- a dedicated visual representation for roof concealment separate from terrain mutation logic
- another equivalent chunk-level visual model with the same runtime behavior

Important:
- choose the smallest robust design that fits the current project
- do not build an overcomplicated system if a simple chunk-local visual layer is enough

Strong requirement:
- the runtime show/hide of roof must become a cheap visual operation
- not a large tile rewrite operation on every enter/exit

Acceptance:
- nearby roof can start changing immediately with minimal runtime cost

---

## P0.3 Support smooth fade transitions for roof show/hide
This redesign must support smooth transitions:
- entering cave / active mountain reveal → nearby roof fades out
- exiting cave / losing active mountain → nearby roof fades back in

The fade must be driven by a cheap visual property where possible:
- alpha/modulate/tween on the roof visual layer
- or another bounded chunk-local visual transition

Important:
- smooth transition must not depend on waiting for a long progressive redraw queue to finish
- visual transition should begin immediately for nearby chunks

Acceptance:
- enter/exit feels smooth and immediate near the player
- no multi-second wait for the correct nearby state

---

## P0.4 Keep logical active mountain selection, but change how it is applied visually
`MountainRoofSystem` should remain responsible for deciding:
- whether the player is in an opened mountain area
- which mountain key is active
- which chunks are affected

But it should stop behaving like a large redraw orchestrator for the player-facing nearby result.

Required change:
- `MountainRoofSystem` should become primarily a **state/transition coordinator**
- not a system whose UX correctness depends on draining a large redraw queue near the player

That means:
- active mountain changes are resolved logically
- nearby chunks switch/fade visually right away
- background completion for secondary chunks can still exist if needed

Acceptance:
- state calculation and visual application are more clearly separated

---

## P0.5 Allow hybrid handling: immediate local correctness, progressive background completion if needed
A full architectural rewrite does **not** need to make every chunk instant in the same frame.

Correct target behavior:
- nearby chunks: immediate correct visual state + smooth transition
- farther chunks: may still use delayed/background completion if required

This is acceptable because UX depends mainly on what the player sees nearby.

Important:
- the nearby subset must no longer wait on the full bulk workflow
- background work should remain bounded if any still exists

Acceptance:
- local UX becomes immediate
- global frame safety remains intact

---

## P0.6 Remove dependence on queue-tuning as the main UX solution
Do not solve this by merely changing:
- `rows_per_step`
- queue order
- number of chunks per tick
- hide/reveal aggressiveness alone

Those knobs may still exist, but they must become secondary.
The primary fix must be architectural.

Acceptance:
- the new system is not just a retuned version of the old progressive redraw model

---

## Standards alignment
This redesign must align with the project standards and performance fundamentals:
- interactive/player-facing transitions should not trigger heavy rebuilds on the hot path
- background work may exist, but nearby visual correctness must not remain wrong for too long
- dirty queues and budgets are tools, not the whole acceptance target
- acceptance includes both frame pacing and player-facing responsiveness/clarity

This task should explicitly respect that principle.

---

## Strong implementation guidance
A good redesign likely looks like this:

### In `Chunk`
- introduce a dedicated roof visual representation that is persistent
- keep it ready so runtime enter/exit changes mostly affect visibility/alpha/transition state
- avoid reauthoring the full cover tile content every time concealment changes

### In `MountainRoofSystem`
- detect active mountain changes
- identify affected chunks
- immediately apply the correct visual target state to nearby chunks
- trigger fade transitions
- optionally schedule background completion for the rest if any remaining expensive maintenance is still needed

### In the old redraw path
- either reduce its role drastically
- or keep it only for setup/non-urgent maintenance
- but do not leave it as the main near-player UX mechanism

---

## Non-goals
- do not work on threaded chunk generation here
- do not optimize world generation here
- do not revisit shadow optimization here
- do not ship another queue-tuning-only attempt
- do not retain the old architecture and merely hide the symptom

---

## Acceptance criteria
This redesign is successful only if all of the following are true:

1. Entering a cave causes nearby roof to start disappearing immediately and smoothly.
2. Exiting a cave causes nearby roof to start reappearing immediately and smoothly.
3. Nearby concealment/reveal no longer depends on waiting for many progressive redraw slices.
4. Runtime roof transitions are primarily cheap visual state changes.
5. The system preserves good frame pacing and does not reintroduce the old severe spikes.
6. The result is architecturally different from the reverted redraw-queue tuning approach.
7. The new model is clearly explained in terms of logic layer vs visual application layer.

---

## Deliverables expected from Claude Code
1. code changes implementing the new roof concealment architecture
2. a short explanation of the new model:
   - logical active mountain selection
   - chunk-local roof visual representation
   - immediate local transition behavior
   - any remaining background completion path
3. before/after UX notes for entering and exiting caves
4. perf notes confirming no major regression in frame pacing
5. explicit explanation of why the new model is superior to the old tile-redraw-based concealment model
