---
title: Performance Contracts
doc_type: governance
status: approved
owner: engineering
source_of_truth: true
version: 2.0
last_updated: 2026-03-25
depends_on:
  - DOCUMENT_PRECEDENCE.md
---

# Performance Contracts

This document is the canonical runtime/performance law for Station Mirny.

It exists to prevent the project from drifting into hitch-prone architecture where expensive world work lands in the player's interactive path.

## Scope

This document owns:
- boot/background/interactive work split
- frame-time contracts
- dirty queue + budget as the default runtime pattern
- immutable base + runtime diff
- staged loading and degraded mode
- incremental update rules
- main-thread hazards
- native bridge constraints for runtime-sensitive systems
- performance validation rules

This document does not own:
- code style and naming
- general engineering architecture outside runtime constraints
- product vision or roadmap

## 1. Runtime work classes

Every operation must be classified before implementation.

### 1.1 Boot-time work

Runs:
- under a loading screen
- during world boot
- during save-load restore

Typical examples:
- start bubble generation
- first topology/mask/cache build
- tileset/material warmup
- initial registry and content load

Rules:
- may be expensive
- should be predictable and bounded
- should not be repeated in normal gameplay

### 1.2 Background work

Runs:
- during normal gameplay
- under an explicit per-frame budget
- through queues and incremental steps

Typical examples:
- chunk streaming
- progressive redraw
- topology rebuild
- shadow/cover/cliff refresh
- pathfinding cache maintenance
- decor/resource/entity warmup

Rules:
- always budgeted
- always chunked/incremental
- must degrade gracefully if unfinished

### 1.3 Interactive work

Runs:
- directly because of player action
- in the same response chain as input

Typical examples:
- mine one tile
- place/remove one building
- one step movement update
- open/close door
- craft one item

Rules:
- only local work
- no full rebuilds
- heavy consequences are queued into background work

### 1.4 Interactive whitelist

Allowed synchronously:
- mutate one gameplay tile/cell/object
- update a small local dirty region
- enqueue background work
- switch flags / state / animation
- spawn one lightweight object

Forbidden synchronously:
- full chunk redraw
- full topology rebuild
- full cover/shadow/cliff/fog rebuild
- loop over all loaded chunks
- mass `add_child`, `queue_free`, `set_cell`, `clear`

If an operation is ambiguous, treat it as forbidden until profiled and justified.

## 2. Frame and operation budgets

### 2.1 Frame budget model

At 60 FPS the frame budget is roughly `16.6 ms`.

The working target is not merely “60 average FPS”, but:
- no visible hitches during core gameplay
- stable frame time
- expensive work moved out of interactive paths

### 2.2 Background budget targets

Suggested per-frame envelopes:
- chunk streaming: `2-4 ms`
- topology rebuild: `1-2 ms`
- visual rebuild: `1-2 ms`
- spawn/decor/content prep: `1-2 ms`

Total background work should stay within a controlled shared budget, typically around `6 ms/frame`.

### 2.3 Interactive contracts

These numbers apply to the synchronous part only.

| Operation | Target |
|---|---:|
| mine tile | `< 2 ms` |
| place/remove building | `< 2 ms` |
| enter mountain | `< 4 ms` |
| player step | `< 1 ms` |
| craft item | `< 1 ms` |
| door toggle | `< 1 ms` |

If an action exceeds its contract, the architecture is wrong even if the game “usually feels okay”.

### 2.4 Acceptance-level frame quality

A system is accepted only when:
- there are no visible hitches in normal gameplay
- frame time remains stable under intended usage
- any rare spikes happen only during boot/loading or clearly non-interactive warmup

## 3. Measurement rules

Use `WorldPerfProbe` or equivalent instrumentation on runtime-sensitive paths.

Important:
- function timing is not the whole frame
- a clean function log does not automatically mean the game is hitch-free

If the user feels a hitch, also inspect:
- frame time in the Godot profiler
- TileMap batching/update cost
- scene tree mutations
- GDScript/native bridge payload volume

## 4. Dirty Queue + Budget

This is the default pattern for heavy runtime work.

### Rule

Do not “finish everything now”.
Mark dirty and process incrementally within a time budget.

### Desired shape

`event -> dirty queue -> per-frame budgeted processing -> eventual completion`

### Main-thread principle

The main thread must not perform large-scale world work in one frame because of one player event.

If a player action triggers loops over:
- all tiles in a chunk
- all loaded chunks
- all world nodes

that is almost certainly an architectural error.

## 5. Immutable Base + Runtime Diff

World and system data should be split into:
- immutable/generated base data
- persisted runtime diffs

Examples:
- terrain bytes vs modified tiles
- static topology metadata vs mined/opened tiles
- generated resource placements vs depleted nodes

Rules:
- base data is generated or restored once
- runtime saves store diffs, not redundant full state
- rendering and logic should read `base + diff`, not rebuild base every time

## 6. Precompute / Native Cache

Everything deterministic, grid-heavy, and expensive should be computed:
- at generation time, or
- in a native cache

Good candidates:
- terrain classification
- topology/component ids
- edge/interior visual classes
- static shadow metadata
- room graph seeds
- static pathing grids

Important:
- moving code to C++ alone is not enough
- the optimization only counts if heavy state stays native-side or bridge payload shrinks materially

## 7. Staged Loading

### Rule

Chunk/world loading must be phase-based rather than monolithic whenever one-shot loading causes hitches.

Typical phases:
- create node/state shell
- populate terrain/base data
- progressive redraw
- overlays/secondary visuals
- finalize

### Degraded mode

It is acceptable for a just-loaded chunk to temporarily show:
- terrain without all overlays
- incomplete secondary visuals
- delayed noncritical decoration

This is preferable to blocking a frame.

## 8. Incremental Update

Golden rule:

If one tile changes, synchronously update only a local dirty region, not the full chunk or full system.

Examples of correct shape:
- mined tile + its neighbors
- one wall + affected local room boundary
- one edge caster + local shadow diff

Examples of wrong shape:
- rebuild all topology
- clear and rebuild full cover layer
- iterate all loaded chunks after one tile event

## 9. Main-thread hazards

These operations are known hitch risks and must be treated with suspicion:
- `TileMapLayer.clear()`
- mass `set_cell()`
- mass `add_child()`
- mass `queue_free()`
- full overlay/cover/shadow rebuild
- large dictionary/array bridge payloads

These are not “forbidden forever”, but must not land in the interactive path and must be profiled carefully.

## 10. Native bridge rules

Bad native usage:
- doing heavy work in C++ but pulling huge payloads back into GDScript every frame

Good native usage:
- keep heavy world state native-side
- query only local/component/ready-to-apply payloads
- avoid repeated marshaling of whole-chunk or whole-world dictionaries

## 11. Performance validation checklist

Before implementation:
- classify the work
- define the contract
- define base vs diff
- define dirty units
- define degraded mode if needed

After implementation:
- instrument the hot path
- stress test gameplay scenarios
- verify no hidden full rebuild remains
- verify the player does not feel hitch even if logs look clean

## 12. Final principle

Performance in this project is not something we “optimize later”.

The architectural goal is:
- heavy work should structurally avoid the gameplay path
- expensive systems should default to incremental, budgeted, cache-aware behavior

If a feature requires a full rebuild or sync cache wait during gameplay, redesign the feature before shipping the code.
