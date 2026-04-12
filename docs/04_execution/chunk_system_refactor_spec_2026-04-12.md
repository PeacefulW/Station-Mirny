# Chunk System Refactor Spec
_Last updated: 2026-04-12_

## Status

Approved for execution.

## Scope

This plan covers the chunk runtime as one system, not just one file.

Primary files:

- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`

Immediate adjacent responsibilities included in scope:

- mountain topology build
- underground zone query
- visual scheduler
- streaming / staged install
- surface payload cache
- seam / border-fix processing
- debug and forensics
- flora presentation
- underground fog presentation / state
- visual compute contract and native bridge

## Inputs used to build this plan

This document merges the findings from:

- `docs/chunk_manager_review_2026-04-12.md`
- `docs/chunk_codex_review_comparison_2026-04-12.md`

It also adopts the explicit project decision that, at this stage of development, the codebase should prefer **fail-fast correctness** over fallback compatibility.

---

## Executive summary

The current chunk runtime already has useful foundations:

- compute → apply separation
- `WorkerThreadPool`
- adaptive visual budgeting
- staged boot pipeline
- cache reuse for surface payloads
- topology and seam repair infrastructure

The problem is not that the system is naive. The problem is that it is already too dense for its stage.

Two files have become architectural centers of gravity:

- `chunk_manager.gd`
- `chunk.gd`

Together they now mix:

- orchestration
- state ownership
- scene creation
- rendering policy
- visual compute preparation
- mutation and mining follow-up
- topology handling
- fog handling
- flora presentation
- diagnostics / forensics
- native / fallback branching

This creates four real risks:

1. hot-path cost is inflated by avoidable O(n) structures and release-path debug work
2. visual rules exist in multiple code paths and can drift apart
3. native and GDScript implementations coexist for the same responsibility, increasing ambiguity and maintenance cost
4. responsibility boundaries are too weak, making future changes harder and riskier than they should be

This plan fixes that in a strict order:

1. remove selected fallback paths immediately
2. enforce required native classes with fail-fast startup validation
3. eliminate the worst hot-path costs in `chunk_manager.gd`
4. split `chunk_manager.gd` into real services
5. extract peripheral responsibilities from `chunk.gd`
6. consolidate visual logic into one kernel truth source
7. convert hot data structures away from `Dictionary<Vector2i, ...>` where they matter
8. move remaining heavy pixel / BFS work to native
9. delete dead code and freeze the new contracts

---

## Binding architectural decisions

### D-01. No fallback for topology rebuild

The project will no longer maintain both:

- native mountain topology build
- GDScript mountain topology fallback

`MountainTopologyBuilder` becomes mandatory for surface topology rebuild.

If the native class is unavailable, the world runtime must fail fast during initialization with a clear error message explaining that the required GDExtension is missing or not built.

This is intentional. The project is early enough that carrying dual implementations causes more harm than value.

### D-02. No fallback for underground pocket BFS query

`query_local_underground_zone()` must no longer use a GDScript flood fill implementation in production runtime.

That query must be backed by a native kernel, with a defined hard cap on explored tiles per request.

If the native kernel is unavailable, the runtime must fail fast when the system initializes or when the feature is first required, depending on the final wiring decision.

### D-03. `chunk_manager.gd` becomes an orchestrator, not a feature monolith

The manager may coordinate services, but it must not remain the place where all of the following continue to live together:

- scheduler internals
- cache internals
- topology build internals
- seam internals
- debug / forensic internals
- boot pipeline internals

### D-04. `chunk.gd` must move toward a single source of truth for visual rules

Any duplicated “how a tile should look” logic is unacceptable.

The final system must have one visual rule source used by both:

- scene application path
- worker / request / batch preparation path

### D-05. Release hot paths must not execute forensic bookkeeping by default

Debug and forensics are allowed, but they must be isolated behind explicit guards and/or dedicated modules so that the release scheduler path does not pay for them every task.

### D-06. Early strictness is preferred over soft degradation

Where the project depends on native functionality, missing native support should produce a loud, actionable failure rather than a silent fallback.

---

## Problem inventory

### Combined problem list

| ID | Problem | File | Priority |
|---|---|---|---|
| P-01 | O(n) `_has_load_request` in streaming path | `chunk_manager.gd` | Critical |
| P-02 | O(n) LRU touch via `find()` + `remove_at()` | `chunk_manager.gd` | High |
| P-03 | repeated `has_method()` checks in wrapper helpers | `chunk_manager.gd` | High |
| P-04 | debug / forensics work inside visual scheduler hot path | `chunk_manager.gd` | Critical |
| P-05 | `_sync_loaded_chunk_display_positions` walks all loaded chunks repeatedly | `chunk_manager.gd` | High |
| P-06 | string task keys allocate in scheduler hot path | `chunk_manager.gd` | Medium |
| P-07 | duplicated finalization logic in chunk install paths | `chunk_manager.gd` | High |
| P-08 | topology native path and GDScript fallback coexist | `chunk_manager.gd` | Critical |
| P-09 | `query_local_underground_zone` flood fill in GDScript | `chunk_manager.gd` | Critical |
| P-10 | task queues store `Array[Dictionary]` objects | `chunk_manager.gd` | Medium |
| P-11 | `chunk_manager.gd` owns too many unrelated responsibilities | `chunk_manager.gd` | Critical |
| P-12 | `_loaded_chunks` alias is reassigned manually in several places | `chunk_manager.gd` | Medium |
| C-01 | `chunk.gd` is also a monolith with state + rendering + debug + flora + fog + seams | `chunk.gd` | Critical |
| C-02 | duplicated visual rule logic between instance redraw and request/batch generation | `chunk.gd` | Critical |
| C-03 | hot-path dictionaries keyed by `Vector2i` | `chunk.gd` | High |
| C-04 | visual compute request builds dictionary lookups in nested loops | `chunk.gd` | High |
| C-05 | debug markers create real scene nodes | `chunk.gd` | High |
| C-06 | flora presenter caches textures per chunk renderer instead of globally | `chunk.gd` | Medium |
| C-07 | interior macro generation does pixel work in GDScript | `chunk.gd` | High |
| C-08 | `global_to_local` / coordinate helpers also rely on reflective wrapper style | `chunk.gd` | Medium |

### What is actually wrong at a system level

The main design smell is not just file size. It is **mixed authority**.

Right now the system does not cleanly separate:

- who owns world/chunk state
- who decides visual policy
- who prepares work
- who applies scene changes
- who tracks debug evidence
- who owns caches
- who owns async lifecycle

That makes both performance and correctness harder to reason about.

---

## Target architecture

This target architecture is the end state. It does not need to be reached in one PR.

## `chunk_manager.gd` target role

`chunk_manager.gd` should end as the thin world-facing coordinator responsible for:

- player chunk tracking
- active z-level tracking
- public API entry points
- service wiring
- high-level lifecycle orchestration

It should not contain the heavy internal logic for every subsystem.

## Target service split for manager responsibilities

### 1. `chunk_manager.gd`
Responsibility:
- public API
- service ownership
- player / z-level orchestration
- high-level lifecycle routing

### 2. `chunk_streaming_service.gd`
Responsibility:
- load queue
- runtime async generation handoff
- staged install routing
- unload policy
- request relevance / pruning

### 3. `chunk_visual_scheduler.gd`
Responsibility:
- 8 queues
- task selection
- adaptive budget
- compute submission / completion intake
- task invalidation / versions

### 4. `chunk_surface_payload_cache.gd`
Responsibility:
- native surface payload cache
- flora payload/result cache
- LRU bookkeeping

### 5. `chunk_topology_service.gd`
Responsibility:
- fail-fast validation of required native topology builder
- topology rebuild scheduling
- topology update after mining / streaming
- no GDScript rebuild fallback

### 6. `chunk_seam_service.gd`
Responsibility:
- seam refresh queue
- neighbor border repair scheduling
- seam-related follow-up diagnostics

### 7. `chunk_debug_system.gd`
Responsibility:
- forensic incidents
- trace contexts
- queue snapshot data
- debug overlay data
- optional diagnostics only

### 8. `chunk_boot_pipeline.gd`
Responsibility:
- boot compute/apply queues
- first-playable gate
- boot completion gate
- runtime handoff

## Target split for `chunk.gd`

The split of `chunk.gd` must happen in phases, but the target roles are:

### 1. `chunk_state.gd`
Responsibility:
- terrain / biome / variation / height bytes
- modification state
- invalidation/version state
- packed hot-path data

### 2. `chunk_view.gd`
Responsibility:
- scene node composition
- tile layers
- applying already prepared visual commands
- visibility publication

### 3. `chunk_visual_kernel.gd`
Responsibility:
- single source of truth for visual classification and command generation
- no duplicate instance/request implementations

### 4. `chunk_cover_state.gd`
Responsibility:
- local cover reveal state
- cover edge state
- roof publication support data

### 5. `chunk_fog_presenter.gd`
Responsibility:
- underground fog layer creation and application

### 6. `chunk_flora_presenter.gd`
Responsibility:
- flora packet presentation
- shared texture cache access
- no per-chunk independent resource loading policy

### 7. `chunk_debug_renderer.gd`
Responsibility:
- optional debug visualization only
- no real marker node spam in release runtime

---

## Mandatory native contract

## Required native classes after this refactor

The exact class names may change, but the runtime must require native support for:

- mountain topology rebuild
- underground open-pocket / local zone query
- existing visual kernel bridge already in use where applicable

### Startup validation rules

Initialization must validate required native classes once and store the result in explicit capability flags.

Example required capability flags:

- `_native_topology_available`
- `_native_underground_query_available`
- `_native_visual_kernel_available`

If a required class is missing, initialization must:

1. `push_error(...)` with an actionable message
2. prevent the world runtime from continuing in a misleading partial mode
3. avoid silent GDScript fallback behavior

### Error message quality requirement

Errors must name:

- the missing native class
- the required subsystem
- the likely resolution, for example “build / load the GDExtension”

Example style:

```gdscript
push_error("Chunk runtime requires MountainTopologyBuilder. Build or load the world GDExtension before running the game.")
```

---

## Hot-path performance plan

### A. Queue membership and relevance

#### Fix A-01. `_load_queue_set`
Add an O(1) membership index for load requests.

Target:
- `_load_queue` remains ordered list
- `_load_queue_set: Dictionary` or equivalent keyed by `Vector3i`
- enqueue / prune / pop paths keep both structures in sync

Expected benefit:
- remove repeated O(n) request existence scans from `_update_chunks()` and related paths

#### Fix A-02. optional ready-queue / active-task key normalization
Normalize task and request keys away from formatted strings where it simplifies hot lookups.

This is not the first optimization to land, but it is part of the final cleanup.

### B. Reflection wrappers

#### Fix B-01. capability flags instead of repeated `has_method()`
Any wrapper helper that currently does repeated reflective checks in loops must resolve those capabilities once during init.

Targets include manager and chunk coordinate helpers.

### C. Display sync repetition

#### Fix C-01. display sync reference cache
Add `_last_display_sync_reference` or equivalent so redundant full sync passes can be skipped when the reference chunk did not change.

### D. Cache cost

#### Fix D-01. remove O(n) LRU touch behavior
Replace `find()` + `remove_at()` touching with constant-time or amortized-constant-time order bookkeeping.

### E. Release hot path diagnostics

#### Fix E-01. no forensic bookkeeping by default in scheduler hot path
Visual task scheduling and processing must not pay for deep forensic state in release runtime.

This can be achieved by:

- module extraction
- and/or explicit `_debug_enabled` guard

The end state is that release-task processing does not build incident state for every scheduled task.

### F. Data shape in chunk hot paths

#### Fix F-01. replace selected `Dictionary<Vector2i, ...>` structures
Hot-path tile sets / masks should move to packed arrays or bitsets where the access pattern is dense or chunk-local.

High-value candidates:

- `_pending_border_dirty`
- `_revealed_local_cover_tiles`
- `_cover_edge_set`
- request-time lookup structures used to build visual compute batches

### G. Scene-node debug overhead

#### Fix G-01. no mass `Polygon2D` creation for chunk debug markers
Debug rendering must not create one real scene node per marker tile as the normal strategy.

Use one of:

- a single drawing node with `_draw()`
- batched geometry
- `MultiMeshInstance2D`
- a dedicated overlay renderer

### H. Flora texture reuse

#### Fix H-01. shared flora texture cache
Flora textures must be cached globally or by shared service, not independently by every chunk presenter.

### I. Interior macro pixel work

#### Fix I-01. move interior macro image generation to native
Pixel-by-pixel image generation in GDScript is not acceptable for long-term runtime use.

---

## Visual correctness plan

## Primary correctness rule

There must be exactly one source of truth for the question:

> Given chunk state and neighbor state, what visual commands should this tile produce?

### Current correctness risk

The current codebase contains duplicated visual logic in multiple paths, including patterns like:

- per-tile redraw logic
- request/batch generation logic

That duplication is a direct bug source.

## Required end state

### V-01. single visual kernel

The final system must have one visual rule source that both of these use:

- direct apply / local redraw path
- worker-prepared batch path

### V-02. no “same rule implemented twice” policy

Any time a visual rule exists in two places, the iteration is not done.

### V-03. visual batch contract becomes explicit

The visual kernel contract must explicitly document:

- required input arrays / neighbor halo
- phase names
- command structure
- ownership of atlas / variant decisions
- rules for border fix vs full redraw vs first pass

---

## Refactor sequencing

The order below is deliberate. It is designed to reduce risk while still making fast progress.

# Iteration 0 — Baseline, contracts, and validation scenarios

## Goal
Freeze the execution plan and define how correctness will be checked during the refactor.

## Deliverables

- this spec committed to repo
- explicit manual validation matrix added to the execution checklist
- native dependency list written down
- list of expected PR boundaries

## Manual validation scenarios to keep throughout all iterations

### S-01. boot / first playable
- launch a new world
- verify startup reaches first playable
- verify boot completion continues without visible corruption

### S-02. player chunk transition
- walk across multiple chunk borders in surface world
- verify no visible empty / half-published chunk is shown
- verify load/unload behavior remains correct

### S-03. seam mining
- mine on a chunk edge and especially at corners
- verify seam normalization and border fix on both involved chunks

### S-04. interior mining
- mine away from borders
- verify local patch, visual publication, topology update, and no regressions

### S-05. underground query / reveal
- switch underground
- verify fog reveal and local open-zone behavior

### S-06. z-level switch
- switch between z-levels repeatedly
- verify active layer visibility, display positions, and no stale chunk alias state

### S-07. cache reuse
- unload and later reload surface chunks
- verify cached payload/flora reuse remains valid

### S-08. debug overlay
- debug build only
- verify overlay still works after extraction and does not crash when queues are active

## Done criteria

- manual scenario list exists and is used as checklist for every iteration
- missing native classes required by the plan are identified by name

# Iteration 1 — Native-only contract and fail-fast startup

## Goal
Delete the most harmful fallback ambiguity immediately.

## Changes

### 1. topology path
- remove GDScript topology rebuild path as a supported production path
- make native topology builder mandatory for surface topology rebuild
- fail fast if unavailable

### 2. underground zone query path
- introduce native kernel requirement for local underground open-pocket query
- remove production GDScript flood-fill fallback
- fail fast if unavailable

### 3. native capability validation
- validate required classes once during init
- store explicit capability flags
- stop relying on scattered `ClassDB.class_exists(...)` checks as implicit policy

## Explicit deletions

Delete or retire:

- GDScript topology rebuild as a supported runtime path
- any code branches that silently fall back to GDScript for the two required native subsystems above

## Acceptance

- boot fails loudly and clearly if required native classes are missing
- surface topology no longer has dual implementations
- underground local zone query no longer has dual implementations
- no code path silently downgrades behavior

# Iteration 2 — Fast hot-path wins in `chunk_manager.gd`

## Goal
Remove the clearest avoidable runtime costs before deeper decomposition.

## Changes

### 1. `_load_queue_set`
- add request membership index
- keep it synchronized in enqueue, prune, pop, z-filter, and shutdown paths

### 2. capability flags for wrapper helpers
- cache `WorldGenerator` capabilities once
- eliminate repeated `has_method()` checks inside loops

### 3. display sync cache
- add cached last display sync reference
- skip redundant full sync passes

### 4. LRU bookkeeping cleanup
- replace O(n) touch pattern with indexed or monotonic-order bookkeeping

### 5. minor queue cleanup
- avoid unnecessary sort work where list size ≤ 1
- keep semantics unchanged

## Acceptance

- functionality unchanged in all manual scenarios
- `_update_chunks()` no longer depends on linear membership scan
- repeated wrapper reflection is removed from hot loops
- cache touch no longer uses array `find()` + `remove_at()` on every hit

# Iteration 3 — Isolate debug and forensics from release hot path

## Goal
Stop paying debug cost in the core scheduler path.

## Changes

### 1. extract debug ownership
Move forensic state, incident tracking, overlay snapshots, and trace bookkeeping into `chunk_debug_system.gd`.

### 2. release-path guard
Ensure scheduler task selection and processing do not perform deep debug bookkeeping by default in release runtime.

### 3. debug API boundary
`chunk_manager.gd` may call a narrow debug API, but must not own the whole forensic implementation.

## Acceptance

- debug overlay still works in debug builds
- release scheduler path no longer performs per-task forensic enrichment by default
- no behavior changes to chunk publication or streaming correctness

# Iteration 4 — Chunk install / streaming cleanup and manager decomposition pass 1

## Goal
Remove duplicated lifecycle logic and establish real service boundaries.

## Changes

### 1. finalize path unification
- unify `_load_chunk_for_z()` and `_finalize_chunk_install()` finalization behavior
- centralize install finalization in one path only

### 2. extract streaming service
Create `chunk_streaming_service.gd` and move into it:

- load queue relevance/pruning
- runtime async generation lifecycle
- staged install handoff
- unload routing

### 3. `_loaded_chunks` alias safety
- centralize alias reassignment in one method
- stop reassigning `_loaded_chunks` ad hoc in multiple places

## Acceptance

- only one canonical chunk install finalization path remains
- `chunk_manager.gd` shrinks measurably
- z-level switching still works cleanly

# Iteration 5 — Peripheral extraction from `chunk.gd`

## Goal
Shrink `chunk.gd` without first touching the most fragile visual core.

## Changes

### 1. extract `chunk_debug_renderer.gd`
Move debug marker rendering out of `chunk.gd`.

Requirements:
- no scene-node spam strategy
- debug-only ownership
- clear on/off lifecycle

### 2. extract `chunk_fog_presenter.gd`
Move fog-layer creation and apply behavior out of general chunk logic.

### 3. extract `chunk_flora_presenter.gd`
Move flora rendering/presentation out of `chunk.gd`.

Requirements:
- introduce shared texture cache
- remove per-chunk texture loading policy as the default approach

## Acceptance

- `chunk.gd` no longer directly owns debug marker scene construction
- `chunk.gd` no longer directly owns flora presentation implementation details
- underground fog still works
- flora still renders correctly after unload/reload

# Iteration 6 — Visual kernel consolidation

## Goal
Create one source of truth for tile visual decisions.

## Changes

### 1. introduce `chunk_visual_kernel.gd`
This module becomes the owner of visual classification and command generation.

### 2. remove duplicated visual-rule implementations
Any current parallel logic that answers the same visual question in two places must be consolidated.

### 3. define explicit kernel contract
Document:

- inputs
- halo / neighbor requirements
- phase outputs
- command semantics
- border-fix semantics

## Acceptance

- duplicated visual-rule branches are removed or clearly routed through one implementation
- batch generation and direct redraw consume the same kernel logic
- seam and mining manual checks produce the same visuals as before or better

# Iteration 7 — Data-oriented hot-path conversion in `chunk.gd`

## Goal
Replace the worst dictionary-heavy chunk-local structures where it matters.

## Changes

### 1. packed/bitset conversion candidates
Convert the highest-value structures first:

- pending border dirty state
- revealed local cover state
- cover edge state
- request-time local lookup structures where dense local indexing is better

### 2. request input normalization
Visual batch request building should move away from large dictionary lookup construction for dense local data.

### 3. API contract updates
If helper contracts change between manager/kernel/chunk layers, update documentation and call sites together.

## Acceptance

- chunk-local hot structures no longer depend on broad `Dictionary<Vector2i, ...>` usage where dense array access is possible
- border fix and cover behavior remain correct
- no visible regression in chunk publication order

# Iteration 8 — Native heavy-work pass

## Goal
Move the remaining expensive algorithmic / pixel work out of GDScript.

## Changes

### 1. underground query native implementation finalization
Ensure the production path is fully native-backed with a defined exploration limit.

### 2. interior macro native implementation
Move image/pixel generation work out of GDScript.

### 3. review additional native opportunities
Evaluate whether any remaining visual prep or dense classification work should move into native now that kernel contracts are explicit.

## Acceptance

- no runtime pixel-loop interior macro generation remains in GDScript for the production path
- underground zone query is fully native-backed
- feature behavior remains correct in validation scenarios

# Iteration 9 — Manager decomposition pass 2 and scheduler cleanup

## Goal
Finish shrinking `chunk_manager.gd` and harden the long-term architecture.

## Changes

### 1. extract `chunk_visual_scheduler.gd`
Move:
- queues
- task versions
- compute active/waiting/result handling
- adaptive budget feedback
- task priority and task processing internals

### 2. extract `chunk_surface_payload_cache.gd`
Move:
- payload cache
- flora payload/result cache
- LRU bookkeeping

### 3. extract `chunk_seam_service.gd`
Move:
- seam refresh queue
- neighbor border enqueue logic
- seam follow-up repair flow

### 4. optional task-object cleanup
If still valuable after the above, replace raw queue dictionaries with a typed task structure.

This is not mandatory before the preceding higher-value items land.

## Acceptance

- `chunk_manager.gd` is visibly reduced to orchestration/public API
- scheduler internals are owned by the dedicated scheduler module
- cache internals are owned by the cache module
- seam internals are owned by the seam module

# Iteration 10 — Final contract freeze and dead-code deletion

## Goal
Remove the last ambiguity and document the new stable architecture.

## Changes

- delete dead helpers and retired fallback branches
- remove stale comments that still imply fallback support
- document module ownership and native requirements
- update any execution docs that refer to the old monolithic layout

## Acceptance

- no dead fallback branches remain for the decided native-only responsibilities
- module ownership is documented and matches code
- future contributors can tell where a responsibility belongs without guessing

---

## Order constraints

These constraints are intentional and must be respected.

### Must happen before visual kernel consolidation

These are safe shrink steps that reduce noise before touching the most sensitive visual core:

- debug renderer extraction
- fog presenter extraction
- flora presenter extraction

### Must happen before deleting production fallback

- native startup validation
- clear error messages
- required native classes available in the project build

### Must happen before data-structure rewrites in chunk hot paths

- visual kernel contract must be clear enough that behavior is frozen
- manual validation scenarios must be repeatedly exercised

---

## Things explicitly not to do

### N-01. Do not keep both topology implementations “for safety”
That is exactly the ambiguity being removed.

### N-02. Do not first split files mechanically without defining ownership
Moving methods around without responsibility cleanup just makes multiple bad files.

### N-03. Do not consolidate visual logic before peripheral extraction
The visual core is the riskiest part. Reduce surrounding noise first.

### N-04. Do not preserve release-path forensic cost in the scheduler
Debug is allowed. Paying for it all the time is not.

### N-05. Do not replace dictionaries with packed arrays blindly
Only convert structures where access is dense, local, and performance-relevant.

---

## PR strategy

Each iteration should land in a dedicated PR or small PR set.

Preferred rule:

- one architectural theme per PR
- one behavior risk surface per PR
- no mixed fallback deletion + huge file split + hot-path data rewrite in the same PR

Recommended PR grouping:

1. native contract / fail-fast
2. manager hot-path wins
3. debug extraction
4. streaming/install cleanup
5. chunk peripheral extractions
6. visual kernel consolidation
7. data-oriented chunk hot-path rewrite
8. native heavy-work pass
9. final manager decomposition
10. cleanup/docs freeze

---

## Definition of done for the whole refactor

The refactor is done only when all of the following are true:

1. `chunk_manager.gd` is primarily orchestration and public API
2. `chunk.gd` no longer directly owns debug/flora/fog presentation internals
3. topology rebuild has no production GDScript fallback
4. underground local zone query has no production GDScript fallback
5. release scheduler path no longer performs deep forensic bookkeeping by default
6. there is one source of truth for visual classification / command generation
7. the worst dense chunk-local hot data no longer relies on broad `Dictionary<Vector2i, ...>` use where indexed structures are better
8. install/finalize lifecycle duplication is gone
9. module ownership is documented and obvious from file layout
10. the manual validation matrix passes after the final cleanup

---

## Immediate execution checklist

This is the exact recommended start order.

### First
- land this spec
- confirm required native classes and build path

### Next
- Iteration 1: native-only contract and fail-fast startup

### Then
- Iteration 2: hot-path wins in `chunk_manager.gd`
- Iteration 3: debug isolation
- Iteration 4: streaming/install cleanup

### Then
- Iteration 5: extract chunk debug/fog/flora peripherals
- Iteration 6: visual kernel consolidation

### Then
- Iteration 7: data-oriented hot structures
- Iteration 8: native heavy-work pass
- Iteration 9: final manager decomposition
- Iteration 10: cleanup and freeze

---

## Final note

This spec is intentionally strict.

The codebase is still early enough that the correct move is to remove ambiguity now, not preserve it for hypothetical convenience later.

That means:

- no dual topology implementation
- no dual underground query implementation
- no silent degradation
- no “temporary” duplication of visual rules left to rot

The goal is not just to make the current runtime faster.
The goal is to make the chunk system small enough in responsibility, strict enough in contracts, and clear enough in ownership that future work stops creating new monoliths.
