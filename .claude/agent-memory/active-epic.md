# Epic: Chunk Visual Pipeline Rework

**Spec**: docs/02_system_specs/world/chunk_visual_pipeline_rework_spec.md
**Started**: 2026-03-31
**Current iteration**: 2
**Total iterations**: 3

## Documentation debt

- [x] DATA_CONTRACTS.md — Iteration 1 `Visual Task Scheduling` layer landed; Iteration 2-3 rewrites for `Presentation`, `Boot Readiness`, and `Chunk Lifecycle` remain pending
- [x] PUBLIC_API.md — Iteration 1 grep verified no new scheduler API surface; existing `boot_load_initial_chunks()` wording aligned with scheduler semantics; Iteration 2-3 readiness-query updates remain pending if public semantics change
- **Deadline**: by the end of Iteration 3
- **Status**: Iteration 1 debt cleared; future-iteration debt pending

## Iterations

### Iteration 1 - Scheduler Surgery + Telemetry Baseline
**Status**: completed
**Started**: 2026-03-31
**Completed**: 2026-03-31

#### Acceptance tests
- [x] `WorldGenBalance` exports all `visual_*` scheduler fields — verified by `rg -n` in `data/world/world_gen_balance.gd` at lines 14-20
- [x] `world_gen_balance.tres` sets concrete defaults for the new scheduler fields — verified by `rg -n` in `data/world/world_gen_balance.tres` at lines 14-20
- [x] `chunk_manager.gd` owns explicit urgent/near/full/border/far/cosmetic visual queues — verified by `rg -n` in `core/systems/world/chunk_manager.gd` at lines 68-73
- [x] `_tick_visuals()` processes multiple tasks while budget remains — verified by file read showing `while _has_pending_visual_tasks()` in `_tick_visuals_budget()` and runtime log entries with `processed=5` / `processed=8`
- [x] `_tick_redraws()` is reduced to a compatibility adapter — verified by file read showing `func _tick_redraws() -> bool: return _tick_visuals()`
- [x] scheduler telemetry records queue depth, processed count, budget exhaustion, and urgent wait — verified by `rg -n` hits for `scheduler.max_urgent_wait_ms` (1417), `scheduler.visual_tasks_processed` (1473), `scheduler.visual_queue_depth.*` (1474-1479), and `scheduler.visual_budget_exhausted_count` (1586)
- [x] no new public API surface is introduced in Iteration 1 — verified by grep returning `0 matches in PUBLIC_API.md for Iteration 1 internal scheduler names`
- [x] runtime validation: urgent queue no longer starves behind far work — verified by `artifacts_visual_iter1.log`: `0 matches for urgent task waited`, `scheduler.max_urgent_wait_ms: 64.96 ms`, repeated `starvations=0`, and `route drain complete; quitting`

#### Doc check
- [x] Grep DATA_CONTRACTS.md for `ChunkManager.boot_load_initial_chunks` — 1 match at line 465; still accurate writer reference
- [x] Grep DATA_CONTRACTS.md for `Chunk.is_redraw_complete` — 0 matches; not referenced
- [x] Grep PUBLIC_API.md for `ChunkManager.boot_load_initial_chunks` — 3 matches at lines 194, 291, 431; wording updated to scheduler semantics
- [x] Grep PUBLIC_API.md for `Chunk.is_redraw_complete` — 1 match at line 225; still accurate
- [x] Documentation debt section reviewed — Iteration 1 portion cleared; Iteration 2-3 items remain pending

#### Files touched
- `core/systems/world/chunk_manager.gd` — scheduler queues, budgeted tick loop, border/boot/runtime scheduling, telemetry, and compatibility invalidation fixes
- `data/world/world_gen_balance.gd` — exported visual scheduler knobs
- `data/world/world_gen_balance.tres` — concrete default values for visual scheduler knobs
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `Visual Task Scheduling` layer and scheduler-owned runtime invariants
- `docs/00_governance/PUBLIC_API.md` — `boot_load_initial_chunks()` wording aligned with scheduler semantics

#### Closure report
## Closure Report

### Implemented
- Added explicit visual scheduler queues plus budgeted `_tick_visuals()` ownership in `ChunkManager`, keeping `_tick_redraws()` as a compatibility adapter.
- Routed load/boot/runtime chunk visual work and neighbor border fixes through scheduler-owned task queues, dedupe/version tracking, and telemetry.
- Added `WorldGenBalance` visual scheduler knobs and updated canonical docs for the new `Visual Task Scheduling` layer plus current `boot_load_initial_chunks()` semantics.

### Root cause
- `_redrawing_chunks` mixed urgent first-pass work, far convergence work, and border repair in one compatibility queue, so near-player visual work had no explicit ownership, priority bands, or starvation evidence.
- Canonical docs still described the pre-scheduler boot/presentation ownership model.

### Files changed
- `core/systems/world/chunk_manager.gd`
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

### Acceptance tests
- [x] `WorldGenBalance` exports exist for all Iteration 1 `visual_*` fields — verified: `rg -n` in `data/world/world_gen_balance.gd` lines 14-20
- [x] `world_gen_balance.tres` provides concrete defaults for the new `visual_*` fields — verified: `rg -n` in `data/world/world_gen_balance.tres` lines 14-20
- [x] explicit urgent/near/full/border/far/cosmetic queues exist — verified: `rg -n` in `core/systems/world/chunk_manager.gd` lines 68-73
- [x] `_tick_visuals()` loops while budget remains and can process more than one task per tick — verified: file read shows `while _has_pending_visual_tasks()` and runtime log shows `processed=5` / `processed=8`
- [x] `_tick_redraws()` is only a compatibility adapter — verified: file read shows `return _tick_visuals()`
- [x] scheduler telemetry records processed count, queue depths, budget exhaustion, and urgent wait — verified: `rg -n` hits at 1417, 1473-1479, 1586 in `chunk_manager.gd`
- [x] no new public API surface is introduced in Iteration 1 — verified: grep on `PUBLIC_API.md` for `visual_scheduler_budget_ms`, `_tick_visuals`, `_visual_q_terrain_urgent` returned 0 matches
- [x] runtime validation: urgent queue does not starve behind far work during sprinting across chunk boundaries — verified: `artifacts_visual_iter1.log` has `0 matches for urgent task waited`, repeated `starvations=0`, `scheduler.max_urgent_wait_ms: 64.96 ms`, and `route drain complete; quitting`

### Contract/API documentation check
- Grep DATA_CONTRACTS.md for `Visual Task Scheduling`: 2 matches — lines 56 and 344; updated
- Grep DATA_CONTRACTS.md for `visual_scheduler_budget_ms`: 1 match — line 355; updated invariant
- Grep DATA_CONTRACTS.md for `ChunkManager.boot_load_initial_chunks`: 1 match — line 465; still accurate
- Grep DATA_CONTRACTS.md for `Chunk.is_redraw_complete`: 0 matches — not referenced
- Grep PUBLIC_API.md for `Visual Task Scheduling`: 0 matches — internal contract only, not public API
- Grep PUBLIC_API.md for `visual_scheduler_budget_ms`: 0 matches — no new public API surface
- Grep PUBLIC_API.md for `ChunkManager.boot_load_initial_chunks`: 3 matches — lines 194, 291, 431; updated to scheduler semantics
- Grep PUBLIC_API.md for `Chunk.is_redraw_complete`: 1 match — line 225; still accurate
- Spec section `Required contract and API updates`: exists — Iteration 1 `DATA_CONTRACTS.md` landed; `PUBLIC_API.md` grep was required and wording was aligned because existing entries were stale; Iteration 2-3 doc debt remains pending

### Out-of-scope observations
- `artifacts_visual_iter1.log` still shows a sustained `full_near` / `full_far` backlog and some frame-budget totals above 6 ms even though urgent starvation warnings no longer fire.
- The worktree still contains unrelated deletions and runtime artifacts from prior sessions (`docs/04_execution/chunk_visual_pipeline_rework_plan.md`, temp DLL deletion, `.tmp_appdata`, runtime logs, spec file status) that were left untouched.

### Remaining blockers
- none for Iteration 1
- Iteration 2-3 readiness and full-convergence documentation debt remains pending by spec

### DATA_CONTRACTS.md updated
- updated — grep shows `Visual Task Scheduling` at lines 56 and 344, plus `visual_scheduler_budget_ms` at line 355

### PUBLIC_API.md updated
- updated — grep shows `ChunkManager.boot_load_initial_chunks` at lines 194, 291, 431; grep for internal scheduler names returned 0 matches

#### Blockers
- none

---

### Iteration 2 - First-Pass Readiness State Machine
**Status**: pending
**Started**: —
**Completed**: —

#### Acceptance tests
- [ ] `ChunkVisualState` and first-pass/full-ready query methods exist
- [ ] boot first-playable depends on first-pass readiness for ring 0-1
- [ ] runtime staged finalize schedules separate first-pass and full-redraw work
- [ ] `GameWorld` distinguishes first-playable from boot-complete
- [ ] docs updated for the new readiness contract

#### Doc check
- [ ] Grep DATA_CONTRACTS.md for `ChunkVisualState`
- [ ] Grep DATA_CONTRACTS.md for `is_first_pass_ready`
- [ ] Grep PUBLIC_API.md for `is_first_pass_ready`
- [ ] Grep PUBLIC_API.md for `is_boot_first_playable`
- [ ] Documentation debt section reviewed

#### Files touched
- pending

#### Closure report
- pending

#### Blockers
- not started

---

### Iteration 3 - Full Redraw as Canonical Convergence + Explicit Border Fix
**Status**: pending
**Started**: —
**Completed**: —

#### Acceptance tests
- [ ] full-redraw and border-fix task kinds exist with version-aware invalidation
- [ ] visible seam repair outranks far convergence
- [ ] boot critical path no longer depends on `complete_terrain_phase_now()` / `warmup_tile_layers()`
- [ ] `VISUAL_FULL_READY` is the only terminal visual state
- [ ] boot-complete depends on full-ready startup chunks plus support systems
- [ ] docs updated for terminal/full-convergence semantics

#### Doc check
- [ ] Grep DATA_CONTRACTS.md for `VISUAL_FULL_READY`
- [ ] Grep DATA_CONTRACTS.md for `complete_terrain_phase_now`
- [ ] Grep PUBLIC_API.md for `VISUAL_FULL_READY`
- [ ] Grep PUBLIC_API.md for `complete_terrain_phase_now`
- [ ] Documentation debt section reviewed

#### Files touched
- pending

#### Closure report
- pending

#### Blockers
- not started