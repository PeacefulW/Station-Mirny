# Claude Code — detailed TZ for threaded chunk generation

## Context
Main-thread streaming optimization is largely complete.
Current runtime chunk loading already has a staged pipeline in `core/systems/world/chunk_manager.gd`:
- `ChunkStreaming.phase0_generate`
- `ChunkStreaming.phase1_create`
- `ChunkStreaming.phase2_finalize`

The remaining dominant runtime streaming cost is `phase0_generate`, which currently calls:
- `WorldGenerator.get_chunk_data(coord)`

Important grounding from the current codebase:
- the active hot path is currently **GDScript** `WorldGenerator.get_chunk_data()` in `core/autoloads/world_generator.gd`
- there is also `_native_generator.generate_chunk(...)` exposed via `get_chunk_data_native()`, but runtime chunk streaming currently uses `get_chunk_data()`, not `get_chunk_data_native()`
- therefore this task must be based on the real active path, not on assumptions about the gdextension path

Relevant current code locations:
- `core/systems/world/chunk_manager.gd`
- `core/autoloads/world_generator.gd`

---

## Objective
Implement **safe threaded generation for runtime chunk data only**.

Meaning:
- move the expensive `WorldGenerator.get_chunk_data(coord)` computation off the main thread
- keep scene tree mutation, chunk node creation, `populate_native`, `add_child`, topology registration, redraw queueing, and event emission on the main thread
- preserve the existing staged loading architecture as much as possible

This is **not** a broad multithreading rewrite.
This is a targeted change for one expensive CPU step.

---

## Non-goals
Do **not** do any of the following in this pass:
- do not move `Chunk.new()`, `chunk.setup()`, `chunk.populate_native()`, `add_child()`, `EventBus.chunk_loaded.emit()`, or topology code into background threads
- do not rewrite cover/shadow systems again
- do not change boot-time loading unless needed for consistency
- do not switch the whole project to a different generator implementation unless explicitly required by thread-safety evidence
- do not assume the gdextension/native generator is already the active hot path

---

## Current architecture to preserve
Current runtime loading flow in `ChunkManager`:
1. `_tick_loading()` chooses the next coord
2. `_staged_loading_generate(coord)` computes chunk data
3. `_staged_loading_create()` builds the `Chunk` node and populates it
4. `_staged_loading_finalize()` attaches it to the scene and registers runtime systems

Target architecture after this task:
1. `_tick_loading()` schedules generation work in background
2. background worker computes chunk data only
3. main thread polls completed results
4. completed results feed into the existing `create -> finalize` stages

In other words:
- replace synchronous phase0 generation with asynchronous generation
- keep phases 1 and 2 on the main thread

---

## Required implementation

## P0.1 Introduce background generation queue/state in `ChunkManager`
File:
- `core/systems/world/chunk_manager.gd`

Add explicit state for async generation.
Suggested minimum state:
- `_generating_coords: Dictionary` — coords currently being generated
- `_ready_chunk_data: Dictionary` — completed results waiting for consumption by main thread
- `_ready_chunk_order: Array[Vector2i]` — preserve deterministic completion/consumption order if needed
- thread-safety primitive(s): `Mutex` and/or another safe handoff mechanism
- optional `_generation_request_queue` if needed separately from `_load_queue`

Important:
- prevent duplicate generation for the same coord
- if a coord is unloaded / no longer needed before completion, handle this safely
- do not let stale completed data create invalid chunks far outside current load radius without validation

Acceptance:
- runtime system can track pending generation requests and ready results explicitly

---

## P0.2 Run only chunk-data generation in a worker thread
Files:
- `core/systems/world/chunk_manager.gd`
- `core/autoloads/world_generator.gd`
- possibly a small helper class/file if that simplifies worker payload handling

Required behavior:
- background worker computes only the equivalent of current `WorldGenerator.get_chunk_data(coord)`
- the result must be pure data only (Dictionary / Packed arrays / scalar values)
- no scene tree access in background code
- no Node creation in background code

Preferred rollout strategy:
- start with **at most one active runtime generation task at a time**
- correctness and stability first; do not jump immediately to multiple simultaneous workers

Why this matters:
- even one worker task removes the expensive generation from the main thread
- one-at-a-time generation minimizes thread-safety risk for shared generator state

Acceptance:
- `ChunkStreaming.phase0_generate` no longer represents main-thread generation cost in the old synchronous sense
- runtime generation is performed asynchronously

---

## P0.3 Main thread must consume completed results safely
File:
- `core/systems/world/chunk_manager.gd`

Required behavior:
- during `_process()` and/or `_tick_loading()`, poll for completed generation results
- when a result is ready and still relevant, move it into the existing staged create/finalize flow
- validate that:
  - chunk is not already loaded
  - chunk is still within the desired load radius or otherwise still needed
  - chunk has not been invalidated by unload/state transitions

Strong recommendation:
- do **not** bypass the existing staged create/finalize structure unless there is a very strong reason
- integrate ready data into the existing `_staged_data` / `_staged_coord` model or a close equivalent

Acceptance:
- completed runtime chunk data enters the already working main-thread pipeline
- no duplicate loads
- no stale loads appearing after the player has moved far away

---

## P0.4 Thread-safety validation for `WorldGenerator`
File:
- `core/autoloads/world_generator.gd`
- inspect any relevant gdextension/native generator code if needed

This is mandatory.
Do not assume `WorldGenerator.get_chunk_data()` is automatically thread-safe.

The current active generator uses shared fields such as:
- `_height_noise`
- `_mountain_blob_noise`
- `_mountain_chain_noise`
- `_mountain_detail_noise`
- `balance`
- `spawn_tile`
- `world_seed`

You must explicitly decide which of these are safe to read/call from a worker thread.

Required output from this task:
- a clear statement of which thread-safety strategy is used

Acceptable strategies:

### Strategy A — one runtime worker at a time, using current generator state read-only
Use only one active generation job at a time if the current generator path is effectively safe under read-only access.

### Strategy B — dedicated worker-side generator data / cloned noise instances
If shared `FastNoiseLite` objects are not safe for threaded use, create worker-local noise instances or a worker-local generator context.

### Strategy C — mutex-guarded generator call
If there is unavoidable shared mutable state, guard generation with a mutex. This still removes work from the main thread, though it limits parallelism.

Important:
- choose the safest minimal solution first
- explicitly document why the chosen strategy is valid

Acceptance:
- no hand-wavy assumptions about thread safety
- code/comments explain the chosen safety model

---

## P0.5 Keep boot-time loading behavior simple
File:
- `core/systems/world/chunk_manager.gd`

Boot-time initial loading under the loading screen does not have the same UX constraints as runtime streaming.

Preferred behavior:
- keep boot loading synchronous unless there is a strong reason to unify the pipeline
- do not complicate startup flow unnecessarily in this pass

Reason:
- this task is specifically about removing runtime streaming hitches
- startup loading is already masked by a loading screen

Acceptance:
- boot loading remains stable and simple
- runtime threaded generation is the primary target of the change

---

## P1.1 Instrument the new async pipeline clearly
Files:
- `core/systems/world/chunk_manager.gd`
- possibly `WorldPerfProbe` usage only, no architecture change needed

Add useful measurements for the new flow.
Suggested metrics:
- enqueue generation request
- worker generation duration
- ready-result handoff latency (optional)
- main-thread create duration
- main-thread finalize duration
- count of pending generated chunks / dropped stale results (optional)

Goal:
Make it obvious from logs that main-thread streaming spikes are no longer caused by generation.

Acceptance:
- logs clearly distinguish worker-side generation from main-thread chunk attach work
- after the change, runtime main-thread streaming should no longer show the old generation cost as a frame spike

---

## P1.2 Handle stale completion safely
Files:
- `core/systems/world/chunk_manager.gd`

Potential issue:
- player moves away while a chunk is still generating
- result arrives later
- system must not blindly instantiate that chunk if it is no longer needed

Required behavior:
- on result consumption, re-check whether the coord is still wanted
- discard stale results safely if they are no longer relevant
- clean up any bookkeeping for discarded results

Acceptance:
- no late chunk pop-in outside the current desired streaming window
- no stale task leaks in dictionaries/queues

---

## Recommended implementation shape
The exact implementation may differ, but the architecture should look close to this:

### Main thread
- `_tick_loading()`:
  - if a create/finalize stage is active, continue it
  - otherwise, if a completed result exists, promote it into `_staged_data`
  - otherwise, if no generation is active and a wanted coord exists, enqueue async generation

### Worker side
- compute only chunk data for one coord
- write completed result into a thread-safe handoff structure

### Main thread again
- consume completed result
- call existing `_staged_loading_create()`
- next tick call existing `_staged_loading_finalize()`

This preserves your staged pipeline while removing generation from the main thread.

---

## Risks to guard against
1. **Thread-unsafe generator state**
   - do not assume shared noise objects are safe

2. **Using engine objects from worker thread**
   - do not touch scene tree or Node APIs in worker code

3. **Duplicate generation requests**
   - must be prevented explicitly

4. **Stale completed results**
   - must be validated before chunk creation

5. **Overcomplicating boot path**
   - avoid unnecessary startup pipeline complexity

---

## Acceptance criteria
This task is successful only if all of the following are true:

1. Runtime chunk generation no longer executes synchronously on the main thread.
2. Existing main-thread staged create/finalize flow is preserved or minimally adapted.
3. Scene tree work remains on the main thread.
4. Thread-safety strategy for `WorldGenerator` is explicit and justified.
5. Duplicate or stale chunk generation is handled safely.
6. Logs clearly show that old `phase0_generate` frame spikes are gone from the main thread.
7. No regression in chunk correctness, cover/shadow behavior, or boot loading stability.

---

## Deliverables expected from Claude Code
1. Code changes implementing threaded runtime chunk generation
2. Clear explanation of the chosen thread-safety strategy
3. Before/after perf numbers focused on runtime chunk streaming
4. Explicit note on whether the current active generator remains GDScript-based or was intentionally switched to another implementation
5. Any remaining bottleneck after threaded generation, if one still matters
