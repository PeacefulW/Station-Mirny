---
title: Performance Contracts
doc_type: governance
status: approved
owner: engineering
source_of_truth: true
version: 2.1
last_updated: 2026-04-09
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

### 1.5 Scale horizon rule

Runtime architecture is judged against intended scale, not today's tiny sample size.

Invalid reasoning:
- "it is only one tree right now"
- "currently there are only a few objects in the chunk"
- "we can keep it synchronous until content grows"

Required reasoning for every new runtime-sensitive or extensible feature:
- what density/fan-out it must tolerate in intended gameplay
- what data is authoritative truth and who is the single write owner
- what the local dirty unit is
- what work is allowed to stay synchronous
- what work escalates to queue, worker-thread compute, native cache, or C++

If those answers are missing, the design is not performance-safe yet.

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
- player-visible world publication is honest: no green/raw chunks, no near-world holes, no visible on-screen build-up of terrain/cliff/flora/shadows during the accepted handoff moment
- metric wins do not count if the player can still outrun streaming and watch the world finish in front of their eyes

## 3. Measurement rules

Use `WorldPerfProbe` or equivalent instrumentation on runtime-sensitive paths.

Important:
- function timing is not the whole frame
- a clean function log does not automatically mean the game is hitch-free
- lower `ms` numbers are not proof if visible world completeness regressed
- performance validation for world/loading work must include player-facing proof that near-visible chunks, flora, and shadows are not still building on screen at the accepted handoff point

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
- every mutable or cached layer must name one authoritative source of truth and one write owner
- derived caches/mirrors must declare invalidation/rebuild rules; duplicated mutable truth without ownership is forbidden

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

### 6.1 Escalation path requirement

For new runtime-sensitive/extensible work, the author must explicitly decide whether the heavy part should be:
- local synchronous GDScript
- budgeted background queue work
- worker-thread compute plus bounded main-thread apply
- native cache / C++ ownership

Staying on the main thread in pure GDScript is acceptable only when the synchronous work is truly local and remains bounded by the declared dirty unit, not by total content count in the loaded area.

If the workload is grid-heavy, repeated across many entities/tiles, or likely to grow with mod/content density, you must seriously evaluate worker/native ownership instead of defaulting to "leave it in script for now".

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
- define the intended scale / density
- define the authoritative truth and write owner
- define base vs diff
- define dirty units
- define escalation path (`queue`, worker, native cache, C++, etc.)
- define degraded mode if needed

After implementation:
- instrument the hot path
- stress test gameplay scenarios
- verify no hidden full rebuild remains
- verify the design is not justified only by today's tiny content count
- verify the player does not feel hitch even if logs look clean

## 12. Standard performance proof recipe

Performance work must be proven with repeatable harnesses and readable artifacts.

### 12.1 What counts as proof

Acceptable proof may include:
- boot/load milestone timings
- frame summary metrics
- runtime validation route logs
- explicit review of `ERROR` / `WARNING` / backlog lines
- project-local saved log files

This is not enough:
- "feels faster"
- "I moved work to background, so it should be fine"
- "the code is incremental now"
- "a log exists somewhere"

### 12.2 Sanctioned harnesses

Use these first:
- `WorldPerfProbe`
- `WorldPerfMonitor`
- `RuntimeValidationDriver`
- `tools/perf_log_summary.gd`
- `GameWorld` boot milestones (`Startup.loading_screen_visible`, `Startup.startup_bubble_ready`, `Startup.boot_complete`)

### 12.3 Boot/load proof

Use when validating:
- startup time
- loading-screen drag
- first-playable delay
- boot completion drag

Recipe:
1. Run the real world scene.
2. Prefer a console binary (`godot_console.exe` or repo-local `Godot_v4.6.1-stable_win64_console.exe` when present).
3. Capture a project-local log artifact with PowerShell `Tee-Object`.
4. For boot-only proof, pass `codex_quit_on_boot_complete` so the scene quits immediately after `Startup.boot_complete`.
5. Read the log yourself.
6. Extract and cite:
   - `Startup.start_to_loading_screen_visible_ms`
   - `Startup.loading_screen_visible_to_startup_bubble_ready_ms`
   - `Startup.startup_bubble_ready_to_boot_complete_ms`
   - relevant `Boot.*` / `WorldPerf` detail lines
7. Grep the same log for:
   - `ERROR`
   - `WARNING`
   - `WorldPerf`
   - `Boot`

Recommended command shape:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_quit_on_boot_complete codex_world_seed=<seed> *>&1 | Tee-Object -FilePath debug_exports/perf/<name>.log
```

Recommended fixed-seed example:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_quit_on_boot_complete codex_world_seed=12345 *>&1 | Tee-Object -FilePath debug_exports/perf/boot_seed12345.log
```

Default fallback log location when `--log-file` is not used or manual review is needed:

```text
C:\Users\peaceful\AppData\Roaming\Godot\app_userdata\Станция Мирный\logs
```

### 12.4 Runtime/streaming proof

Use when validating:
- route traversal hitching
- chunk streaming lag
- catch-up after movement
- "the world should load around the player without missing chunks"

Recipe:
1. Run the real world scene with `RuntimeValidationDriver`.
2. Use a fixed seed.
3. Let the driver:
   - wait for boot readiness
   - traverse the sanctioned route
   - wait for streaming/topology catch-up
   - report success or timeout/failure
4. Pick one sanctioned route preset:
   - `local_ring` for near-base streaming churn
   - `seam_cross` for repeated chunk-boundary crossing
   - `far_loop` for long-travel load/catch-up proof
5. Prefer a console binary (`godot_console.exe` or repo-local `Godot_v4.6.1-stable_win64_console.exe` when present).
6. Capture the route log with PowerShell `Tee-Object`.
7. Read the log yourself.
8. Confirm:
   - route started
   - waypoints were reached
   - no validation failure fired
   - no catch-up timeout fired
   - successful route drain / quitting line appeared
   - unexplained `ERROR` / `WARNING` lines are absent

Recommended command shape:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_validate_runtime codex_validate_route=<local_ring|seam_cross|far_loop> codex_world_seed=<seed> *>&1 | Tee-Object -FilePath debug_exports/perf/<name>.log
```

Recommended fixed-seed examples:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_validate_runtime codex_validate_route=local_ring codex_world_seed=12345 *>&1 | Tee-Object -FilePath debug_exports/perf/runtime_local_ring_seed12345.log
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_validate_runtime codex_validate_route=far_loop codex_world_seed=12345 *>&1 | Tee-Object -FilePath debug_exports/perf/runtime_far_loop_seed12345.log
```

### 12.5 Log summary extraction

After boot/load or runtime proof, run the project-local summary parser on the saved log.

Recommended command shape:

```powershell
godot.exe --headless --path . --script res://tools/perf_log_summary.gd -- codex_perf_log=debug_exports/perf/<name>.log
```

Default outputs:
- `debug_exports/perf/<name>_summary.json`
- `debug_exports/perf/<name>_summary.md`

### 12.6 Log review is mandatory

For perf tasks, producing a log file is not enough. The agent must read it.

Minimum review:
- grep `ERROR`
- grep `WARNING`
- grep `WorldPerf`
- grep `CodexValidation`
- grep subsystem-specific markers relevant to the task

If warnings or errors exist, the closure report must say whether they:
- are caused by the current task
- are known pre-existing noise
- block acceptance

### 12.7 Artifact path

Unless a subsystem spec says otherwise, performance proof artifacts should live in:

```text
debug_exports/perf/
```

This may contain:
- boot/load logs
- runtime validation logs
- extracted metric summaries

### 12.8 Extend canonical harnesses, not ad-hoc tooling

If current proof is close but not sufficient:
- extend `WorldPerfProbe`
- extend `WorldPerfMonitor`
- extend `RuntimeValidationDriver`

Do not create one-off perf tooling if the same result can be achieved by extending the canonical harness.

## 13. Final principle

Performance in this project is not something we “optimize later”.

The architectural goal is:
- heavy work should structurally avoid the gameplay path
- expensive systems should default to incremental, budgeted, cache-aware behavior
- scalable systems should declare authoritative truth, dirty units, and escalation paths before code lands

If a feature requires a full rebuild or sync cache wait during gameplay, redesign the feature before shipping the code.
