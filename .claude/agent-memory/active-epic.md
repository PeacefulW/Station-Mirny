# Epic: Player-Hot Chunk Publication Recovery

**Spec**: `docs/02_system_specs/world/player_hot_chunk_publication_recovery_spec.md`
**Started**: 2026-04-16
**Current iteration**: 1
**Total iterations**: 3

## Documentation debt

- [ ] `DATA_CONTRACTS.md` — if validation outcome invariants change in Iteration 1, document the tightened proof semantics
- [ ] `DATA_CONTRACTS.md` — if visual scheduler / shadow / publication ownership changes in Iteration 2, document the new invariants
- [ ] `DATA_CONTRACTS.md` — if runtime generation ownership or packet/cache ownership changes in Iteration 3, document the new invariants
- [ ] `PUBLIC_API.md` — not required by default; update only if a new sanctioned read-only proof accessor is added
- [ ] `ai_performance_observatory_spec.md` — update only if sanctioned proof semantics or command expectations become canonical
- [ ] `human_readable_runtime_logging_spec.md` — update only if validation wording/severity becomes canonical
- **Deadline**: review at the end of each iteration; mandatory immediately in the iteration that changes documented semantics
- **Status**: pending

## Iterations

### Iteration 1 - Player-Hot Proof Hardening
**Status**: in_progress
**Started**: 2026-04-16
**Completed**: —

#### Проверки приёмки (Acceptance tests)
- [ ] `before` and `candidate` artifacts use `seed=12345` and scenarios `route,speed_traverse,chunk_revisit`
- [ ] `assert(meta.validation_completion.outcome != "finished")` whenever final `streaming.debug_diagnostics.forensics.chunk_causality_rows` still contains an entry with `is_player_chunk == true` and `state == "stalled"`
- [ ] `assert(meta.validation_completion.outcome != "finished")` whenever final `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.full_near"] > 0` or `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.terrain_near"] > 0`
- [ ] `assert(meta.schema_version == before.meta.schema_version)` and top-level JSON sections remain unchanged

#### Doc check
- [ ] Grep `DATA_CONTRACTS.md` for changed names — pending
- [ ] Grep `PUBLIC_API.md` for changed names — pending
- [ ] Documentation debt section reviewed — pending

#### Files touched
- `.claude/agent-memory/active-epic.md` — created tracker for the new recovery epic

#### Отчёт о выполнении (Closure Report)
pending

#### Blockers
- none

---

### Iteration 2 - Player-Hot Publication Priority And Shadow Isolation
**Status**: pending

### Iteration 3 - Runtime Chunk Generation Cost Recovery
**Status**: pending
