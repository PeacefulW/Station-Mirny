# Epic: Boot Fast First-Playable & Streaming Hitch Elimination

**Spec**: docs/02_system_specs/world/boot_fast_first_playable_spec.md
**Started**: 2026-03-31
**Current iteration**: 3 (all complete)
**Total iterations**: 3

## Documentation debt

- [x] DATA_CONTRACTS.md — Boot Readiness invariants updated in Iteration 1 (change 1E)
- [x] PUBLIC_API.md — not required (signature/owner unchanged per spec, verified by grep)
- **Status**: all debt cleared

## Iterations

### Iteration 1 — Boot gate relaxation + ring 2 deferral + priority redraw
**Status**: completed
**Started**: 2026-03-31
**Completed**: 2026-03-31

#### Files touched
- `core/systems/world/chunk_manager.gd` — 4 changes (1A, 1B, 1C, 1D)
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — Boot Readiness invariants updated (1E)

---

### Iteration 2 — TileMapLayer warm-up + progressive redraw budget tuning
**Status**: completed
**Started**: 2026-03-31
**Completed**: 2026-03-31

#### Files touched
- `core/systems/world/chunk.gd` — warmup_tile_layers(), REDRAW_TIME_BUDGET_USEC 1500→2500, check_interval 1→4
- `core/systems/world/chunk_manager.gd` — warmup call in _boot_apply_from_queue()

---

### Iteration 3 — Defer neighbor borders from streaming finalize
**Status**: completed
**Started**: 2026-03-31
**Completed**: 2026-03-31

#### Acceptance tests
- [x] `_staged_loading_finalize()` calls `_enqueue_neighbor_border_redraws()` instead of `_redraw_neighbor_borders()` (grep: line 1741)
- [x] `_enqueue_neighbor_border_redraws()` exists with correct dirty marking logic (grep: line 647)
- [x] `enqueue_dirty_border_redraw()` exists in chunk.gd (grep: line 463)
- [x] `_pending_border_dirty` variable exists in chunk.gd (grep: line 76)
- [x] `_tick_redraws()` processes `_pending_border_dirty` (grep: lines 1763-1765)
- [x] `_redraw_neighbor_borders()` preserved for other call sites (grep: lines 620, 1199, 2965)
- [ ] `ChunkStreaming.finalize.emit` < 5ms — BLOCKED: requires Godot editor runtime
- [ ] `ChunkStreaming.phase2_finalize` < 10ms — BLOCKED: requires runtime
- [ ] No visible hitches during fast movement — BLOCKED: requires runtime
- [ ] Border seam tiles correct — BLOCKED: requires visual runtime verification
- [ ] No crash/assert during fast movement — BLOCKED: requires runtime
- [ ] No crash/assert surface↔underground — BLOCKED: requires runtime

#### Doc check
- [x] Grep DATA_CONTRACTS.md for `_enqueue_neighbor_border_redraws`: 0 matches — not referenced
- [x] Grep DATA_CONTRACTS.md for `enqueue_dirty_border_redraw`: 0 matches — not referenced
- [x] Grep DATA_CONTRACTS.md for `_pending_border_dirty`: 0 matches — not referenced
- [x] Grep DATA_CONTRACTS.md for `_redraw_neighbor_borders`: 0 matches — not referenced
- [x] Grep PUBLIC_API.md for all changed names: 0 matches — not referenced
- [x] Spec "Required updates" section: all updates completed in Iteration 1 (last-iteration debt check passed)
- [x] Documentation debt section reviewed — all debt cleared

#### Files touched
- `core/systems/world/chunk_manager.gd` — `_staged_loading_finalize()` call replaced, new `_enqueue_neighbor_border_redraws()`, `_tick_redraws()` border processing
- `core/systems/world/chunk.gd` — new `_pending_border_dirty` var, new `enqueue_dirty_border_redraw()`

#### Blockers
- Runtime acceptance tests require Godot editor
