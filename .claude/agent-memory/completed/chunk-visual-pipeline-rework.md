# Epic: Chunk Visual Pipeline Rework

**Spec**: docs/02_system_specs/world/chunk_visual_pipeline_rework_spec.md
**Started**: 2026-03-31
**Current iteration**: 3
**Total iterations**: 3

## Documentation debt

- [x] DATA_CONTRACTS.md - Iteration 1 `Visual Task Scheduling` layer landed; Iteration 2-3 rewrites for `Presentation`, `Boot Readiness`, and terminal/full-convergence semantics landed on 2026-04-02
- [x] PUBLIC_API.md - Iteration 1 grep verified no new scheduler API surface; Iteration 2-3 readiness-query and diagnostics-only helper semantics landed on 2026-04-02
- **Deadline**: by the end of Iteration 3
- **Status**: cleared by Iteration 3 on 2026-04-02

## Iterations

### Iteration 1 - Scheduler Surgery + Telemetry Baseline
**Status**: completed
**Started**: 2026-03-31
**Completed**: 2026-03-31

#### Acceptance tests
- [x] `WorldGenBalance` exports all `visual_*` scheduler fields - verified in `data/world/world_gen_balance.gd` and `data/world/world_gen_balance.tres`
- [x] `chunk_manager.gd` owns explicit urgent/near/full/border/far/cosmetic visual queues
- [x] `_tick_visuals()` processes multiple tasks while budget remains
- [x] `_tick_redraws()` is reduced to a compatibility adapter
- [x] scheduler telemetry records queue depth, processed count, budget exhaustion, and urgent wait
- [x] no new public API surface is introduced in Iteration 1

#### Doc check
- [x] Grep DATA_CONTRACTS.md for `ChunkManager.boot_load_initial_chunks`
- [x] Grep DATA_CONTRACTS.md for `Chunk.is_redraw_complete`
- [x] Grep PUBLIC_API.md for `ChunkManager.boot_load_initial_chunks`
- [x] Grep PUBLIC_API.md for `Chunk.is_redraw_complete`
- [x] Documentation debt section reviewed

#### Files touched
- `core/systems/world/chunk_manager.gd`
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

#### Closure report
- Iteration 1 established scheduler-owned visual queues, budgets, and telemetry without adding new public API surface.

#### Blockers
- none

---

### Iteration 2 - First-Pass Readiness State Machine
**Status**: completed
**Started**: 2026-04-01
**Completed**: 2026-04-02

#### Acceptance tests
- [x] `ChunkVisualState` and first-pass/full-ready query methods exist - verified in `core/systems/world/chunk.gd` at lines 17, 434-445
- [x] boot first-playable depends on first-pass readiness for ring 0-1 - verified in `core/systems/world/chunk_manager.gd` at lines 3120-3135 and `scenes/world/game_world.gd` at lines 212-213, 309-335
- [x] runtime staged finalize schedules separate first-pass and full-redraw work - verified in `core/systems/world/chunk_manager.gd` at lines 1415-1424 and 1601-1623
- [x] `GameWorld` distinguishes first-playable from boot-complete - verified in `scenes/world/game_world.gd`
- [x] docs updated for the new readiness contract - verified in `DATA_CONTRACTS.md` and `PUBLIC_API.md`

#### Doc check
- [x] Grep DATA_CONTRACTS.md for `ChunkVisualState`
- [x] Grep DATA_CONTRACTS.md for `is_first_pass_ready`
- [x] Grep PUBLIC_API.md for `is_first_pass_ready`
- [x] Grep PUBLIC_API.md for `is_boot_first_playable`
- [x] Documentation debt section reviewed

#### Files touched
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_manager.gd`
- `scenes/world/game_world.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

#### Closure report
- Iteration 2 introduced the chunk-local readiness state machine and separated `first_playable` from `boot_complete`.

#### Blockers
- none

---

### Iteration 3 - Full Redraw as Canonical Convergence + Explicit Border Fix
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] full-redraw and border-fix task kinds exist with version-aware invalidation - verified in `core/systems/world/chunk_manager.gd` at lines 1386, 1396-1397, and 1590
- [x] visible seam repair outranks far convergence - verified in `core/systems/world/chunk_manager.gd` via `VisualPriorityBand.BORDER_FIX_NEAR/BORDER_FIX_FAR` and `_pop_next_visual_task()` ordering
- [x] boot critical path no longer depends on `complete_terrain_phase_now()` / `warmup_tile_layers()` - verified by grep: 0 call sites in `core/systems/world/chunk_manager.gd`
- [x] `FULL_READY` is the only terminal visual state - verified in `core/systems/world/chunk.gd` via `ChunkVisualState` and `_mark_visual_full_redraw_ready()` / `_can_publish_full_redraw_ready()`
- [x] boot-complete depends on full-ready startup chunks plus support systems - verified in boot readiness code and docs
- [x] docs updated for terminal/full-convergence semantics - verified in `docs/02_system_specs/world/DATA_CONTRACTS.md` and `docs/00_governance/PUBLIC_API.md`

#### Doc check
- [x] Grep DATA_CONTRACTS.md for `is_full_redraw_ready` - matches at lines 487 and 495
- [x] Grep DATA_CONTRACTS.md for `complete_terrain_phase_now` - matches at lines 500 and 531
- [x] Grep PUBLIC_API.md for `is_full_redraw_ready` - matches at lines 197, 230, 243, and 449
- [x] Grep PUBLIC_API.md for `complete_terrain_phase_now` - matches at lines 475 and 479
- [x] Documentation debt section reviewed

#### Files touched
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_manager.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

#### Closure report
- Iteration 3 landed without introducing a new scheduler. `ChunkVisualState` now honestly drops terminal/full-ready on convergence debt, seam repair is scheduler-owned border-fix work, boot first-playable no longer depends on sync terrain helpers, and canonical docs/API wording were updated in the same task.

#### Blockers
- none
