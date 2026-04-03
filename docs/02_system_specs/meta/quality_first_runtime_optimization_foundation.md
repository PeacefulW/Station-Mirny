---
title: Quality-First Runtime Optimization Foundation
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-04-03
related_docs:
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../../00_governance/SYSTEM_INVENTORY.md
  - ../world/DATA_CONTRACTS.md
  - save_and_persistence.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Quality-First Runtime Optimization Foundation

This document defines the staged optimization program for Station Mirny's runtime foundation.

It exists to solve a specific product problem:

- the game already has strong performance architecture pieces
- but the player can still feel microstutter, delayed shadows, late flora/decor, and heavy startup friction
- naive "make it faster" optimization would risk visible pop-in, broken mountain presentation, and fake readiness

This spec chooses a different rule:

- **near-player visual honesty matters more than earliest possible publication**

If the game must choose between:

- showing the world earlier but obviously unfinished
- or waiting slightly longer and showing the player a stable truthful result

the foundation should prefer the second option for the near-visible bubble.

## Player priorities captured for this spec

The current human-approved priorities are:

- microstutters during movement are a top-level failure
- shadows must not visibly lag or "correct themselves later" near the player
- flora and decor must not visibly pop in near the player
- visible nearby chunks must not look half-drawn
- cliffs, rock edges, roof/cover, and mountain silhouettes must not flicker into correctness
- mining and other direct interactions must stay immediate
- the loading screen should appear immediately after pressing Start, rather than after a long hidden stall
- runtime smoothness and future scaling headroom matter more than the absolute shortest startup time
- a larger honest startup bubble is acceptable if it produces stable visuals and stronger future scalability

## Purpose

This spec owns:

- startup-path optimization from pressing `Start` to player handoff
- near / mid / far publication rules for streamed chunks
- shadow correctness and shadow compute/apply architecture
- heavy world visual prep that is eligible for multithreading
- hot-path runtime scaling for AI scans, local lookups, and UI spam
- save/autosave hitch reduction
- the rules for when C++ migration is justified
- the guardrails needed for a much larger future project with more buildings, recipes, AI, content, and mods

This spec does not own:

- new gameplay mechanics
- content additions
- visual redesign of tilesets, flora art, or mountain art
- changing canonical world truth or bypassing safe entrypoints
- fake optimization that makes the game visibly less truthful near the player
- "optimize everything nearby" scope creep outside the listed iterations

## Design intent

The desired player result is:

- "I run around and do not see chunk loading happening in front of me"
- "Shadows are already right when I see a mountain edge near me"
- "Trees and decor do not appear late in my face"
- "Mining and building still answer immediately"
- "Autosave does not hitch the game"
- "The project can grow much larger without collapsing under scene-tree scans, giant main-thread loops, or hidden sync rebuilds"

## Core problem statement

The current runtime has the right ingredients:

- budgeted scheduling
- compute/apply split
- worker-thread chunk generation
- native terrain/topology builders
- chunk readiness contracts

But the remaining problems are not solved by raw speed alone.

The real issue is mismatched publication quality:

- some work still lands too visibly in the player's near field
- some heavy compute is still too main-thread-shaped
- some hot gameplay paths still scale with scene-tree size instead of local relevance
- startup still hides work before the loading screen is honestly visible

The project now needs a stricter optimization foundation that protects both:

- frame stability
- and perceptual truth near the player

## Architectural statement

Station Mirny should follow these rules:

### 1. Near-visible publication quality beats earliest publication

Anything that the player can reasonably notice nearby must not publish in an obviously incomplete state.

For the near-visible bubble, "good enough" means:

- terrain silhouette is correct
- cliff / cover / roof state is correct
- flora/decor required by the chosen quality gate is present
- shadows are either already correct or deliberately withheld by a truthful gate

### 2. Interactive response stays local and immediate

Player-triggered operations such as:

- movement
- mining
- building placement/removal
- nearby interaction

must keep their synchronous part local.

Heavy consequences may be deferred, but the player should not feel delayed response.

### 3. Multithreading is for compute, not unsafe apply

Worker threads are allowed for:

- deterministic detached compute
- snapshot-based analysis
- payload preparation
- serialization and disk write

Worker threads are not allowed to mutate:

- TileMaps
- scene tree
- Sprite/Canvas objects
- EventBus-driven gameplay state

### 4. C++ is justified only when it strengthens the architecture

C++ migration is valid only when all of the following are true:

- the work is deterministic and data-heavy
- it does not require direct scene-tree mutation
- it materially reduces main-thread cost or bridge payload size
- parity with the existing result can be verified

C++ is not a reward for "feels expensive."

### 5. Far-field compromise is allowed; near-field compromise is not

The project may:

- delay cosmetic work farther away
- simplify or defer far-field density
- use larger caches and background convergence

The project may not:

- make the near-visible bubble visibly incomplete just to reach a milestone earlier

## Quality-zone model

This feature introduces a stricter quality-zone direction.

### Near-visible bubble

This is the area around the player that must look finished when published.

The exact chunk radius remains tuning-owned, but the rule is:

- nothing in this zone should visibly "finish loading" on screen

This bubble should include:

- the visible screen
- a safety margin beyond the screen edge
- enough extra space to cover camera movement and edge-of-screen perception

### Mid ring

This zone may continue budgeted convergence, but must preserve:

- truthful terrain shape
- truthful rock/open silhouette
- no obviously broken shadow/cliff/cover seams

Cosmetic follow-up may still occur here if it is not player-obvious.

### Far ring

This zone may use:

- delayed cosmetic convergence
- reduced density
- larger cache dependence
- lower-priority queue service

Far ring optimization is allowed only if it does not create a new near-ring lie.

## Data Contracts - new and affected

### New layer: Near-Visible Quality Gate

- What:
  - per-chunk publication class and required readiness level for the current player neighborhood
- Where:
  - `core/systems/world/chunk_manager.gd`
  - `core/systems/world/chunk.gd`
  - `data/world/world_gen_balance.gd`
- Owner (WRITE):
  - `ChunkManager`
- Readers (READ):
  - `GameWorld`
  - `Chunk`
  - `MountainShadowSystem`
  - loading/progress UI
- Invariants:
  - near-visible chunks must not become visible before their required quality gate is satisfied
  - the quality gate may be stricter than `first_pass_ready`
  - far-field convergence policy must not weaken mining or interaction responsiveness
  - visual invalidation near the player must revoke publication readiness until the owed work is honestly closed
- Event after change:
  - none required yet; read probes are acceptable
- Forbidden:
  - no fake "quality ready" flag that ignores missing flora/cover/shadow debt
  - no direct scene-visible publish just because raw terrain apply completed

### Affected layer: Boot Readiness

- What changes:
  - startup handoff may become stricter than the current `first_playable` gate for the startup bubble
  - pressing `Start` must show the loading screen before expensive boot work begins
- What must not change:
  - post-handoff boot work remains budgeted
  - the game must not re-block after the player has control

### Affected layer: Visual Task Scheduling

- What changes:
  - scheduler ownership expands from "eventual convergence" toward "quality-gated publication for near-visible chunks"
- What must not change:
  - no full synchronous redraw in interactive gameplay

### Affected layer: Presentation

- What changes:
  - publication timing becomes stricter near the player
  - shadow correctness joins the visible-quality discussion
- What must not change:
  - canonical world truth remains outside presentation

### Affected layer: Save / load orchestration

- What changes:
  - save path may move to snapshot + worker serialization
- What must not change:
  - canonical apply order and safe entrypoints

### Affected layer: Noise / hearing input and enemy runtime

- What changes:
  - hot-path scans should stop depending on whole-scene group scans
- What must not change:
  - gameplay detection semantics
  - z-aware correctness

## Non-negotiable rules for this optimization program

- Do not publish nearby chunks with missing flora just to hit `first_playable` faster.
- Do not publish nearby mountain chunks with visibly wrong shadows that "fix themselves later."
- Do not delay mining/building response just to move cost off the main thread.
- Do not introduce fake readiness flags that misrepresent actual visible quality.
- Do not move scene-tree mutation into workers.
- Do not migrate logic to C++ unless parity and payload shape are explicitly preserved.
- Do not add runtime lazy loading of visible near-player assets as a shortcut.

## Iterations

Each iteration is intentionally scoped to one architectural step.
Do not skip ahead.

### Iteration 1 - Start-To-Loading-Screen Handoff And Perf Baseline

Goal:
Make the loading screen appear immediately after pressing `Start`, and establish the performance/queue metrics needed for all following work.

What is done:

- move or defer hidden heavy work that currently happens before the loading screen is shown
- add timing milestones for:
  - `Start -> loading screen visible`
  - `loading screen visible -> startup bubble ready`
  - `startup bubble ready -> full boot complete`
- add queue/latency telemetry for:
  - urgent visual wait
  - shadow stale age
  - autosave snapshot time
  - autosave write time
- add balance/config values for near / mid / far zone sizing and startup bubble sizing

Acceptance tests:

- [ ] Pressing `Start` shows the loading screen before expensive world boot begins.
- [ ] `WorldPerfProbe` or equivalent records `Start -> loading screen`, `loading screen -> startup bubble ready`, and urgent visual wait metrics.
- [ ] This iteration does not yet change chunk publication semantics near the player.

Files that will be touched:

- `scenes/ui/main_menu.gd`
- `scenes/ui/loading_screen.gd`
- `scenes/world/game_world.gd`
- `core/systems/world/chunk_manager.gd`
- `core/autoloads/world_perf_monitor.gd`
- `core/systems/world/world_perf_probe.gd`
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`

Files that must not be touched:

- `core/systems/lighting/mountain_shadow_system.gd`
- `core/entities/fauna/basic_enemy.gd`
- `core/autoloads/save_manager.gd`
- GDExtension files

### Iteration 2 - Near-Visible Chunk Quality Gate

Goal:
Nearby chunks must not become visible until they reach the chosen near-visible quality bar.

What is done:

- introduce an explicit near-visible publication class
- require near-visible chunks to satisfy a stricter gate than raw `first_pass_ready`
- near-visible gate should include:
  - terrain
  - cover / roof
  - cliff / silhouette correctness
  - flora/decor required by the chosen startup/runtime quality rule
- keep mid/far rings budgeted and staged
- ensure invalidation revokes near-visible publication honestly until debt is closed

Acceptance tests:

- [ ] Near-visible chunks do not appear without flora/cover/cliff completion.
- [ ] Mid/far chunks may still converge later under scheduler budget.
- [ ] Mining/building responsiveness does not regress.
- [ ] No synchronous full redraw is introduced into interactive gameplay.

Files that will be touched:

- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `scenes/world/game_world.gd`
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must not be touched:

- `core/systems/lighting/mountain_shadow_system.gd`
- `core/autoloads/save_manager.gd`
- enemy AI files
- GDExtension files

### Iteration 3 - Shadow Correctness Pipeline Before Native Migration

Goal:
Remove visibly wrong-then-correct shadow behavior near the player and prepare shadows for safe worker/native execution.

What is done:

- introduce snapshot/versioned shadow build inputs
- separate shadow compute from shadow apply more explicitly
- drop stale shadow results when sun angle or source terrain changed
- define the near-visible rule for shadows:
  - either the chunk waits for valid shadow readiness
  - or the chunk uses an explicitly approved no-shadow-safe publish mode
- keep all final texture/sprite apply on the main thread

Acceptance tests:

- [ ] Near-visible mountain chunks no longer show visibly wrong shadows that later correct themselves.
- [ ] Stale shadow results are discarded instead of being applied.
- [ ] No synchronous post-handoff shadow rebuild is introduced.

Files that will be touched:

- `core/systems/lighting/mountain_shadow_system.gd`
- `core/systems/world/chunk_manager.gd`
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must not be touched:

- mining safe entrypoints
- `core/autoloads/save_manager.gd`
- enemy AI files
- GDExtension files

### Iteration 4 - Hot-Path Scaling Cleanup For AI, Player Lookup, Inventory, And Power

Goal:
Remove obvious scene-tree-scale hot paths and replace them with future-proof local/runtime-owned access patterns.

What is done:

- replace hot-path `get_nodes_in_group()` scans in AI and player utility paths
- introduce runtime-owned registries or local lookup structures for:
  - noise sources
  - burner/building refuel lookup
- change distance comparisons to squared distance where appropriate
- batch inventory update events for bulk add/remove
- collapse redundant power registry passes where safe
- prepare an optional z-aware spatial hash direction for future AI scale

Acceptance tests:

- [ ] Enemy scan no longer depends on `get_nodes_in_group("noise_sources")` in the hot path.
- [ ] Burner refuel lookup no longer depends on `get_nodes_in_group("buildings")` in the hot path.
- [ ] Bulk inventory changes emit one UI update instead of one per inserted stack fragment.
- [ ] Power recompute housekeeping no longer does avoidable repeated registry sweeps.

Files that will be touched:

- `core/entities/fauna/basic_enemy.gd`
- `core/entities/player/player.gd`
- `core/entities/components/inventory_component.gd`
- `core/systems/power/power_system.gd`
- `core/entities/components/noise_component.gd`
- new registry/autoload files if required
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must not be touched:

- chunk visual scheduler
- shadow raster logic
- save/load files
- GDExtension files

### Iteration 5 - Save/Autosave Snapshot And Honest Startup Bubble

Goal:
Remove save hitching and make the startup bubble larger and more truthful without hidden pre-loading stalls.

What is done:

- refactor save path into:
  - main-thread snapshot
  - worker serialization/write
  - bounded completion callback
- measure snapshot budget separately from disk write budget
- make startup bubble size/config explicit
- allow the loading screen to wait for a larger honest startup bubble if configured
- keep post-handoff convergence budgeted

Acceptance tests:

- [ ] Autosave no longer performs full serialization/write on the main thread.
- [ ] Loading screen appears before heavy work begins.
- [ ] Player handoff waits for the configured startup bubble quality gate rather than a hidden pre-loading stall.
- [ ] No re-blocking occurs after handoff.

Files that will be touched:

- `core/autoloads/save_manager.gd`
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_io.gd`
- `scenes/ui/main_menu.gd`
- `scenes/ui/loading_screen.gd`
- `scenes/world/game_world.gd`
- `core/systems/world/chunk_manager.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must not be touched:

- enemy AI files
- shadow native migration files
- chunk redraw native files

### Iteration 6 - Native Compute Kernels Phase 1

Goal:
Move proven deterministic heavy compute into C++ only after the publication and worker contracts are stable.

What is done:

- add `NativeShadowBuilder` or equivalent shadow raster compute kernel
- add `NativeChunkRedrawPrep` / classification kernel for terrain-layer prep only
- keep all scene-tree and TileMap apply on the main thread
- keep parity with the current result shape
- add A/B metric hooks to compare native vs script cost and output parity

Acceptance tests:

- [ ] Native shadow compute consumes detached snapshot inputs and produces apply-ready payloads.
- [ ] Native redraw prep consumes raw chunk data and produces deterministic apply-ready classification payloads.
- [ ] Main-thread apply remains bounded and scene-tree-only.
- [ ] Script/native comparison telemetry exists for at least one hot path.

Files that will be touched:

- `gdextension/src/*shadow*`
- `gdextension/src/*chunk*`
- `core/systems/lighting/mountain_shadow_system.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `core/autoloads/world_generator.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must not be touched:

- save/load orchestration
- enemy AI logic
- new gameplay systems

### Iteration 7 - Large-Project Scaling Policies

Goal:
Make future growth safer before the project gains many more buildings, recipes, AI actors, and mods.

What is done:

- formalize cache sizing policy for surface payloads and similar runtime caches
- add telemetry-based rules before queue aging is allowed
- define z-level unload retention policy for larger future level counts
- add registry cold-start caching / manifest direction where safe
- allow far-field flora density reduction only outside the near-visible bubble and only if later profiling justifies it

Acceptance tests:

- [ ] Cache policies and thresholds are documented and observable.
- [ ] Any queue-aging policy is gated by telemetry rather than blindly enabled.
- [ ] Z-level retention policy prevents unbounded memory growth for future larger z-counts.
- [ ] No near-visible compromise is introduced by far-field scaling rules.

Files that will be touched:

- `core/systems/world/chunk_manager.gd`
- `core/autoloads/world_generator.gd`
- registry files only if required by the chosen cold-start cache path
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/meta/save_and_persistence.md` if save/cache semantics are affected

Files that must not be touched:

- direct mining interaction timing
- near-visible quality gate semantics from earlier iterations

## Recommended implementation order

1. Iteration 1 - Start-To-Loading-Screen Handoff And Perf Baseline
2. Iteration 2 - Near-Visible Chunk Quality Gate
3. Iteration 3 - Shadow Correctness Pipeline Before Native Migration
4. Iteration 4 - Hot-Path Scaling Cleanup For AI, Player Lookup, Inventory, And Power
5. Iteration 5 - Save/Autosave Snapshot And Honest Startup Bubble
6. Iteration 6 - Native Compute Kernels Phase 1
7. Iteration 7 - Large-Project Scaling Policies

## Why this order

The order is intentional:

- first make the bottlenecks and startup handoff visible
- then stop lying to the player near the camera
- then fix the most obvious shadow correctness problem
- then remove easy scaling hazards in gameplay hot paths
- then remove save/startup hitches
- only then move heavy deterministic math to C++
- and finally formalize the long-term growth policies

This order avoids a common trap:

- migrating code to C++ first
- while the publication rules are still wrong

That would make the game faster at showing the wrong thing.

This spec intentionally refuses that path.

## Required contract and API updates

The following documentation work is expected as this feature advances:

- After Iteration 2:
  - update `DATA_CONTRACTS.md` for the new near-visible quality gate and any changed chunk publication invariants
  - update `PUBLIC_API.md` if new read probes such as quality-ready or startup-bubble-ready are added
- After Iteration 3:
  - update `DATA_CONTRACTS.md` for shadow snapshot/version/apply semantics if they become canonical
- After Iteration 4:
  - update `DATA_CONTRACTS.md` / `PUBLIC_API.md` if new sanctioned registry read paths replace group scans
- After Iteration 5:
  - update `DATA_CONTRACTS.md` / `PUBLIC_API.md` if save semantics, startup handoff semantics, or safe entrypoints change
- After Iteration 6:
  - update `DATA_CONTRACTS.md` if native compute kernels become canonical writers/readers of derived runtime products
- After Iteration 7:
  - update the relevant canonical docs if cache/z-retention policies become normative rather than experimental

Canonical rule:

- no iteration may claim "docs not required" without grep proof at closure time

## Explicit non-goals

This feature must not quietly turn into:

- a renderer rewrite
- a generic engine abstraction cleanup
- a broad AI redesign
- a mod system redesign
- a save-format rewrite unless explicitly required by an iteration
- a "let's optimize every old file we touch" refactor wave

## Success conditions

This feature is successful when all of the following are true:

- the loading screen appears immediately after pressing `Start`
- the near-visible bubble no longer shows obvious chunk/flora/shadow catch-up
- movement no longer suffers from the current class of visible microstutters
- direct interaction remains immediate
- autosave is no longer a visible hitch source
- heavy deterministic compute is prepared for worker/native execution safely
- the architecture is better prepared for a much larger future content and simulation load
