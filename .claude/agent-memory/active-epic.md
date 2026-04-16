# Epic: Player-Hot Chunk Publication Recovery

**Spec**: `docs/02_system_specs/world/player_hot_chunk_publication_recovery_spec.md`
**Started**: 2026-04-16
**Current iteration**: 2
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
**Status**: completed
**Started**: 2026-04-16
**Completed**: 2026-04-16

#### Проверки приёмки (Acceptance tests)
- [x] `before` and `candidate` artifacts use `seed=12345` and scenarios `route,speed_traverse,chunk_revisit`
- [x] `assert(meta.validation_completion.outcome != "finished")` whenever final `streaming.debug_diagnostics.forensics.chunk_causality_rows` still contains an entry with `is_player_chunk == true` and `state == "stalled"`
- [x] `assert(meta.validation_completion.outcome != "finished")` whenever final `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.full_near"] > 0` or `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.terrain_near"] > 0`
- [x] `assert(meta.schema_version == before.meta.schema_version)` and top-level JSON sections remain unchanged

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — helper names `0 matches`; `validation_completion` updated at line `769`
- [x] Grep `PUBLIC_API.md` for changed names — helper names and `validation_completion` `0 matches`; sanctioned read-only accessors `get_chunk_debug_overlay_snapshot()` and `WorldPerfMonitor.get_debug_snapshot()` still present
- [x] Documentation debt section reviewed — `DATA_CONTRACTS.md` updated for new invariant, `ai_performance_observatory_spec.md` updated because sanctioned proof semantics changed, `PUBLIC_API.md` not required

#### Files touched
- `.claude/agent-memory/active-epic.md` — created tracker for the new recovery epic
- `core/debug/runtime_validation_driver.gd` — fail-closed final proof audit against player-hot stalled rows and near queue debt
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — documented new validation-completion invariant
- `docs/02_system_specs/meta/ai_performance_observatory_spec.md` — documented sanctioned fail-closed proof semantics
- `debug_exports/perf/player_hot_publication_before_seed12345.json` — before artifact on fixed scenario matrix
- `debug_exports/perf/player_hot_publication_candidate_seed12345.json` — candidate artifact after proof hardening
- `debug_exports/perf/player_hot_publication_seed12345_diff_summary.json` — helper diff artifact
- `debug_exports/perf/player_hot_publication_seed12345_diff_summary.md` — human-readable helper diff summary

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- В `RuntimeValidationDriver` добавлен финальный fail-closed аудит explicit proof перед сериализацией `validation_completion`.
- Итоговый verdict теперь не может остаться `finished`, если финальный `chunk_causality_rows` всё ещё показывает stalled player-hot chunk.
- Итоговый verdict теперь не может остаться `finished`, если в финальном `WorldPerfMonitor.get_debug_snapshot().ops` остаётся near visual debt по `scheduler.visual_queue_depth.full_near` или `scheduler.visual_queue_depth.terrain_near`.
- Top-level observatory JSON shape и `schema_version` не менялись.
- Обновлены канонические документы для новых proof semantics.

### Корневая причина (Root cause)
- До правки `RuntimeValidationDriver._build_run_completion_summary()` доверял только per-scenario states.
- Route-like scenarios могли завершиться `finished`, даже когда финальный debug proof всё ещё показывал stalled player-hot publication или near queue debt.
- Из-за этого observatory artifact маркировал run как зелёный (`finished`) при уже доказанном player-facing bad state.

### Изменённые файлы (Files changed)
- `.claude/agent-memory/active-epic.md`
- `core/debug/runtime_validation_driver.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/02_system_specs/meta/ai_performance_observatory_spec.md`
- `debug_exports/perf/player_hot_publication_before_seed12345.json`
- `debug_exports/perf/player_hot_publication_candidate_seed12345.json`
- `debug_exports/perf/player_hot_publication_seed12345_diff_summary.json`
- `debug_exports/perf/player_hot_publication_seed12345_diff_summary.md`

### Проверки приёмки (Acceptance tests)
- [x] `before` и `candidate` artifacts используют `seed=12345` и scenarios `route,speed_traverse,chunk_revisit` — прошло (passed); проверено чтением `meta.world_seed`, `meta.cmdline_args` и `meta.validation_completion.selected_scenarios` в обоих JSON
- [x] `meta.validation_completion.outcome != "finished"` при stalled player-hot row — прошло (passed); проверено: в `candidate` `meta.validation_completion.outcome = not_converged`, при этом `streaming.debug_diagnostics.forensics.chunk_causality_rows` содержит player row c `state = stalled`
- [x] `meta.validation_completion.outcome != "finished"` при final near-queue debt — прошло (passed); проверено: в `candidate` `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.terrain_near"] = 5.0`, а `meta.validation_completion.outcome = not_converged`
- [x] `meta.schema_version == before.meta.schema_version` и top-level JSON sections unchanged — прошло (passed); проверено: в обоих artifacts `schema_version = 2`, top-level sections одинаковые: `boot`, `contract_violations`, `frame_summary`, `meta`, `native_profiling`, `scenarios`, `streaming`, `stress`

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): чтение `core/debug/runtime_validation_driver.gd`, grep новых helper names, grep `DATA_CONTRACTS.md` / `PUBLIC_API.md`
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): выполнен
- Артефакты: `debug_exports/perf/player_hot_publication_before_seed12345.json`, `debug_exports/perf/player_hot_publication_candidate_seed12345.json`, `debug_exports/perf/player_hot_publication_seed12345_diff_summary.json`, `debug_exports/perf/player_hot_publication_seed12345_diff_summary.md`
- Ручная проверка пользователем (Manual human verification): не требуется для acceptance checks этой итерации
- Рекомендованная проверка пользователем (Suggested human check): открыть оба JSON и убедиться, что `before.meta.validation_completion.outcome = finished`, а `candidate.meta.validation_completion.outcome = not_converged` при сохранении stalled player-hot proof rows

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): финальный verdict теперь читается из уже существующих owner-owned proof fields, без новых JSON sections и без правки runtime world logic
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): выполнен командами из спеки для `before` и `candidate` matrix на `seed=12345`
- Сводка (Summary): `before` завершился с `validation_completion.outcome = finished`; `candidate` завершился с `validation_completion.outcome = not_converged`, `blocker = streaming_truth`, `exit_code = 1`
- Проверенные метрики / строки: player-hot `chunk_causality_rows.state = stalled`, `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.full_near"]`, `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.terrain_near"]`, `meta.schema_version`, top-level sections
- `ERROR` / `WARNING`: есть — `ZeroToleranceReadiness` assertion spam в headless log остаётся воспроизводимым и подтверждает, что реальный runtime bug ещё не исправлен; это ожидаемое состояние после Iteration 1 и материал для Iteration 2
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): использовать `player_hot_publication_candidate_seed12345.json` как новый red-state proof для старта Iteration 2

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep `DATA_CONTRACTS.md` для `_get_final_overlay_snapshot`: `0 matches`
- Grep `DATA_CONTRACTS.md` для `_get_final_world_perf_snapshot`: `0 matches`
- Grep `DATA_CONTRACTS.md` для `_audit_final_publication_proof`: `0 matches`
- Grep `DATA_CONTRACTS.md` для `_audit_player_hot_stall`: `0 matches`
- Grep `DATA_CONTRACTS.md` для `_audit_final_near_queue_debt`: `0 matches`
- Grep `DATA_CONTRACTS.md` для `_stringify_variants`: `0 matches`
- Grep `DATA_CONTRACTS.md` для `validation_completion`: line `769` — updated
- Grep `PUBLIC_API.md` для `_get_final_overlay_snapshot`: `0 matches`
- Grep `PUBLIC_API.md` для `_get_final_world_perf_snapshot`: `0 matches`
- Grep `PUBLIC_API.md` для `_audit_final_publication_proof`: `0 matches`
- Grep `PUBLIC_API.md` для `_audit_player_hot_stall`: `0 matches`
- Grep `PUBLIC_API.md` для `_audit_final_near_queue_debt`: `0 matches`
- Grep `PUBLIC_API.md` для `_stringify_variants`: `0 matches`
- Grep `PUBLIC_API.md` для `validation_completion`: `0 matches`
- Grep `PUBLIC_API.md` для `get_chunk_debug_overlay_snapshot`: lines `71`, `219` — still accurate sanctioned read-only accessor
- Grep `PUBLIC_API.md` для `get_debug_snapshot`: lines `71`, `1774` for `WorldPerfMonitor` — still accurate sanctioned read-only accessor
- Секция "Required updates" в спеке: есть — `DATA_CONTRACTS.md` updated because validation outcome invariant changed; `ai_performance_observatory_spec.md` updated because sanctioned proof semantics changed; `PUBLIC_API.md` not required

### Наблюдения вне задачи (Out-of-scope observations)
- Per-scenario route records (`route`, `speed_traverse`, `chunk_revisit`) сами по себе всё ещё остаются `finished`; fail-closed tightening сейчас сделан только на top-level `validation_completion`, чтобы не менять scenario payload shape в Iteration 1
- Runtime starvation itself remains reproducible: player-hot chunk still stalls and `terrain_near` debt remains positive in the candidate artifact

### Оставшиеся блокеры (Remaining blockers)
- Для Iteration 1: нет
- Для feature в целом: actual player-hot publication starvation and `ZeroToleranceReadiness` failures remain; next step is Iteration 2

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- обновлено: в `Validation Scenario Proof Records` добавлен invariant `validation_completion_fails_closed_for_player_hot_publication_debt`; grep для `validation_completion` подтверждает line `769`

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) — grep для новых helper names и `validation_completion` вернул `0 matches`; sanctioned read-only accessors `get_chunk_debug_overlay_snapshot()` и `WorldPerfMonitor.get_debug_snapshot()` уже задокументированы и оставались без semantic drift

#### Blockers
- none

---

### Iteration 2 - Player-Hot Publication Priority And Shadow Isolation
**Status**: in_progress
**Started**: 2026-04-16
**Completed**: —

#### Проверки приёмки (Acceptance tests)
- [ ] `assert(meta.validation_completion.outcome == "finished")` on the primary proof
- [ ] final `streaming.debug_diagnostics.forensics.chunk_causality_rows` contains no entry with `is_player_chunk == true` and `state == "stalled"`
- [ ] final `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.full_near"] == 0`
- [ ] final `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.terrain_near"] == 0`
- [ ] `frame_summary.session_observations["Scheduler.urgent_visual_wait_ms"]` improves versus the dedicated before-state
- [ ] contract violations filtered by `category=visual` and `job_id in {"chunk_manager.streaming_redraw","mountain_shadow.visual_rebuild"}` improve, or at minimum one improves while the other does not regress by more than `20%`

#### Doc check
- [ ] Grep `DATA_CONTRACTS.md` for changed names
- [ ] Grep `PUBLIC_API.md` for changed names
- [ ] Documentation debt section reviewed

#### Files touched
- `core/systems/world/chunk_manager.gd` — pending
- `core/systems/world/chunk_visual_scheduler.gd` — pending
- `core/systems/lighting/mountain_shadow_system.gd` — pending
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — pending review
- `docs/00_governance/PUBLIC_API.md` — pending review

#### Отчёт о выполнении (Closure Report)
pending

#### Blockers
- none

### Iteration 3 - Runtime Chunk Generation Cost Recovery
**Status**: pending
