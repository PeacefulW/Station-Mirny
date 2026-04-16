# Epic: AI Performance Observatory

**Spec**: `docs/02_system_specs/meta/ai_performance_observatory_spec.md`
**Started**: 2026-04-16
**Current iteration**: 5
**Total iterations**: 5

## Documentation debt

- [x] `DATA_CONTRACTS.md` - documented `Perf Telemetry Snapshot` ownership for Iteration 1 on 2026-04-16
- [x] `DATA_CONTRACTS.md` - documented `Validation Scenario Proof Records` ownership for Iteration 2 on 2026-04-16
- [x] `PUBLIC_API.md` - updated debug artifact semantics for optional `stress` payload on 2026-04-16
- **Deadline**: after iteration 4, or earlier in any iteration that changes documented semantics
- **Status**: Iteration 1/2 contract docs landed, and Iteration 4 updated both `DATA_CONTRACTS.md` and `PUBLIC_API.md` for stress-proof semantics

## Iterations

### Iteration 1 - Telemetry + Native Profiling
**Status**: completed
**Started**: 2026-04-16
**Completed**: 2026-04-16

#### Проверки приёмки (Acceptance tests)
- [x] `codex_perf_test codex_world_seed=12345` writes JSON with `meta`, `boot`, `streaming`, `frame_summary`, `contract_violations`, `scenarios`, and `native_profiling`
- [x] JSON parses without schema-breaking errors
- [x] collector remains disabled when `codex_perf_test` is absent
- [x] `native_profiling.chunk_generator` contains internal phase breakdown
- [x] `native_profiling.topology_builder` contains internal phase breakdown
- [x] no second always-on diagnostics bus or console-log parser is introduced

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `Perf Telemetry Snapshot` - section + layer-map entry landed
- [x] Grep `PUBLIC_API.md` for observatory symbols - no sanctioned public accessor found; update not required
- [x] Documentation debt section reviewed - Iteration 1 requirement satisfied

#### Files touched
- `docs/02_system_specs/meta/ai_performance_observatory_spec.md` - promoted to `approved`, version `0.2`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - documented `Perf Telemetry Snapshot`
- `.claude/agent-memory/active-epic.md` - updated iteration tracker
- `core/debug/perf_telemetry_collector.gd`
- `core/debug/runtime_validation_driver.gd`
- `core/debug/world_runtime_diagnostic_log.gd`
- `core/autoloads/world_perf_monitor.gd`
- `core/systems/world/world_perf_probe.gd`
- `core/systems/world/chunk_boot_pipeline.gd`
- `core/systems/world/chunk_streaming_service.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/world_pre_pass.gd`
- `core/autoloads/frame_budget_dispatcher.gd`
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_tileset_factory.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `scenes/world/game_world.gd`
- `scenes/world/game_world_debug.gd`
- `gdextension/src/chunk_generator.cpp`
- `gdextension/src/mountain_topology_builder.h`
- `gdextension/src/mountain_topology_builder.cpp`
- `debug_exports/perf/result.json`
- `debug_exports/perf/baseline_seed12345.json`

#### Отчёт о выполнении (Closure Report)
- Implemented explicit-run `PerfTelemetryCollector` JSON export path with `codex_perf_test`, `codex_perf_output`, and `codex_quit_on_perf_complete`.
- Wired `WorldPerfMonitor`, `WorldPerfProbe`, runtime validation results, chunk boot/runtime profile forwarding, and native `_prof_*` payloads into one self-contained artifact.
- Added bounded `WorldPerfProbe` contract violation snapshots and `WorldPerfMonitor.build_perf_observatory_snapshot()` for JSON-ready export.
- Added native `_prof_chunk_generator` and `_prof_topology_builder` timing payloads; collector falls back to a loaded-chunk topology rebuild sample when no runtime topology profile exists yet.
- Suppressed human-facing proof spam (`WorldPerf`, `CodexValidation`, `WorldDiag`, `FrameBudget`, `ChunkGen`, boot/status prints) so JSON stays the authoritative machine-readable observability channel and the console shows only real engine warnings/errors by default.
- Captured and copied a fixed-seed baseline artifact at `debug_exports/perf/baseline_seed12345.json`.

#### Proof artifacts
- `debug_exports/perf/result.json`
- `debug_exports/perf/baseline_seed12345.json`
- `debug_exports/perf/observatory_iteration1_quieter_seed12345.log`
- `debug_exports/perf/no_perf_disable_check_seed12345.log`

#### Residual notes
- Non-validation perf runs currently finalize at `first_playable` once the explicit proof gate is reached, so `boot.game_world_boot_complete` may remain `false` while `boot.chunk_manager_first_playable` is `true`; both booleans are serialized in JSON by contract.
- The headless proof still exits with engine-level `ObjectDB instances leaked at exit` / `resources still in use at exit` warnings. Treat this as a follow-up investigation, not as an Iteration 1 contract blocker.

#### Blockers
- none

---

### Iteration 2 - Scenario Factory
**Status**: implemented with remaining blocker
**Started**: 2026-04-16

#### Проверки приёмки (Acceptance tests)
- [x] `codex_validate_scenarios=route,room,power,mining` runs only the requested scenarios
- [x] each executed scenario writes its own result block into JSON
- [x] modular scenarios cover `deep_mine`, `mass_placement`, `speed_traverse`, and `chunk_revisit`
- [x] scenario code uses existing safe entrypoints / commands instead of direct hidden mutations
- [ ] route-like scenarios complete without `ZeroToleranceReadiness` assertion spam in headless verification

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `Validation Scenario Proof Records` / `ValidationScenario` - ownership section landed
- [x] Grep `PUBLIC_API.md` for `RuntimeValidationDriver`, `ValidationScenario`, and `codex_validate_scenarios` - no sanctioned public accessor found; update not required
- [x] Documentation debt section reviewed - Iteration 2 requirement satisfied

#### Files touched
- `.claude/agent-memory/active-epic.md` - updated iteration tracker
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - documented validation scenario ownership
- `core/debug/runtime_validation_driver.gd`
- `core/debug/scenarios/validation_scenario.gd`
- `core/debug/scenarios/validation_context.gd`
- `core/debug/scenarios/route_validation_scenario.gd`
- `core/debug/scenarios/room_validation_scenario.gd`
- `core/debug/scenarios/power_validation_scenario.gd`
- `core/debug/scenarios/mining_validation_scenario.gd`
- `core/debug/scenarios/mass_placement_validation_scenario.gd`
- `debug_exports/perf/iteration2_route_room_power_mining.json`
- `debug_exports/perf/iteration2_route_room_power_mining.log`
- `debug_exports/perf/iteration2_extended_scenarios.json`
- `debug_exports/perf/iteration2_extended_scenarios.log`

#### Отчёт о выполнении (Closure Report)
- Refactored runtime validation into an explicit scenario factory driven by `codex_validate_scenarios=...`.
- Introduced `ValidationScenario` subclasses and `ValidationContext` so room, power, mining, route, deep mining, mass placement, speed traverse, and chunk revisit checks no longer live as one hardcoded script block.
- Kept scenario mutations on existing safe paths such as building placement/removal entrypoints and `HarvestTileCommand` via `CommandExecutor`.
- Preserved per-run JSON proof output so each executed scenario now serializes its own block, while `RuntimeValidationDriver` stays the orchestrator and final summary owner.
- Verified both requested and extended scenario selections with fixed-seed headless runs.

#### Proof artifacts
- `debug_exports/perf/iteration2_route_room_power_mining.json`
- `debug_exports/perf/iteration2_route_room_power_mining.log`
- `debug_exports/perf/iteration2_extended_scenarios.json`
- `debug_exports/perf/iteration2_extended_scenarios.log`

#### Residual notes
- Both headless runs finish and serialize the expected scenario blocks, but route-like scenarios still emit repeated `ZeroToleranceReadiness` assertion spam in the logs.
- Treat the route-like readiness assertion as a follow-up blocker; Iteration 2 architecture landed, but route verification is not yet clean enough to call fully accepted.

#### Blockers
- `ZeroToleranceReadiness` assertion spam remains reproducible in `route`, `speed_traverse`, and `chunk_revisit` verification paths.

### Iteration 3 - Observatory Skill + Baseline Diff
**Status**: completed
**Started**: 2026-04-16
**Completed**: 2026-04-16

#### Проверки приёмки (Acceptance tests)
- [x] skill instructions use JSON artifacts as the primary proof source
- [x] diff helper flags non-empty `contract_violations` as failure
- [x] diff helper reports `>20%` regressions and `>10%` improvements
- [x] repo-specific observatory workflow is not stored only in `.claude/skills/`

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `perf-observatory`, `perf_baseline_diff`, `codex_perf_baseline`, and `codex_perf_candidate` - `0 matches`; update not required
- [x] Grep `PUBLIC_API.md` for `perf-observatory`, `perf_baseline_diff`, `codex_perf_baseline`, and `codex_perf_candidate` - `0 matches`; update not required
- [x] Documentation debt section reviewed - Iteration 3 repo-structure rule satisfied; `PUBLIC_API.md` still not required until a sanctioned read-only observability accessor exists

#### Files touched
- `.claude/agent-memory/active-epic.md` - moved tracker through Iteration 3 and recorded closure evidence
- `.agents/skills/perf-observatory/SKILL.md` - added repo-specific observatory workflow with JSON-first proof rules
- `.claude/skills/perf-observatory.md` - added compatibility mirror that points back to the repo-local source of truth
- `tools/perf_baseline_diff.gd` - added JSON baseline diff helper with contract/regression/progress heuristics
- `docs/02_system_specs/meta/ai_performance_observatory_design_brief.md` - updated the skill-path example to the repo-specific location and clarified mirror-only `.claude` usage
- `debug_exports/perf/iteration3_clean_baseline_fixture.json` - generated clean fixture without contract violations for helper verification
- `debug_exports/perf/iteration3_regression_fixture.json` - generated synthetic `+25%` regression fixture
- `debug_exports/perf/iteration3_progress_fixture.json` - generated synthetic `-15%` improvement fixture
- `debug_exports/perf/iteration3_contract_violation_check_diff_summary.json`
- `debug_exports/perf/iteration3_contract_violation_check_diff_summary.md`
- `debug_exports/perf/iteration3_clean_stable_check_diff_summary.json`
- `debug_exports/perf/iteration3_clean_stable_check_diff_summary.md`
- `debug_exports/perf/iteration3_regression_check_diff_summary.json`
- `debug_exports/perf/iteration3_regression_check_diff_summary.md`
- `debug_exports/perf/iteration3_progress_check_diff_summary.json`
- `debug_exports/perf/iteration3_progress_check_diff_summary.md`

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлен repo-specific skill `perf-observatory` в `.agents/skills/perf-observatory/SKILL.md` с санкционированным workflow `run -> read JSON -> diff baseline -> report`.
- Добавлен compatibility mirror `.claude/skills/perf-observatory.md`, который явно указывает на repo-local source of truth и не становится единственной копией workflow.
- Реализован helper `tools/perf_baseline_diff.gd`, который читает два observatory JSON-артефакта, считает diff по ключевым метрикам и помечает `contract_violations`, регрессии `>20%` и улучшения `>10%`.
- Обновлён design brief, чтобы пример skill-пути соответствовал repo-specific правилу из текущей approved spec.

### Корневая причина (Root cause)
- В approved spec уже был описан observatory workflow для агента, но в репозитории не существовало одной санкционированной repo-local инструкции и не было baseline diff helper'а. Из-за этого workflow существовал как намерение в документах, а не как готовый воспроизводимый инструмент.

### Изменённые файлы (Files changed)
- `.claude/agent-memory/active-epic.md`
- `.agents/skills/perf-observatory/SKILL.md`
- `.claude/skills/perf-observatory.md`
- `tools/perf_baseline_diff.gd`
- `docs/02_system_specs/meta/ai_performance_observatory_design_brief.md`
- `debug_exports/perf/iteration3_clean_baseline_fixture.json`
- `debug_exports/perf/iteration3_regression_fixture.json`
- `debug_exports/perf/iteration3_progress_fixture.json`
- `debug_exports/perf/iteration3_contract_violation_check_diff_summary.json`
- `debug_exports/perf/iteration3_contract_violation_check_diff_summary.md`
- `debug_exports/perf/iteration3_clean_stable_check_diff_summary.json`
- `debug_exports/perf/iteration3_clean_stable_check_diff_summary.md`
- `debug_exports/perf/iteration3_regression_check_diff_summary.json`
- `debug_exports/perf/iteration3_regression_check_diff_summary.md`
- `debug_exports/perf/iteration3_progress_check_diff_summary.json`
- `debug_exports/perf/iteration3_progress_check_diff_summary.md`

### Проверки приёмки (Acceptance tests)
- [x] Инструкции skill используют JSON-артефакты как основной источник доказательства (primary proof source) — прошло (passed); проверено: `python C:/codex-data/skills/.system/skill-creator/scripts/quick_validate.py .agents/skills/perf-observatory` вернул `Skill is valid!`, а grep по `SKILL.md` показывает формулировку `primary proof source` и правила по `contract_violations`, `20%`, `10%`.
- [x] Diff helper помечает непустой `contract_violations` как failure — прошло (passed); проверено: `Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tools/perf_baseline_diff.gd -- codex_perf_baseline=debug_exports/perf/baseline_seed12345.json codex_perf_candidate=debug_exports/perf/baseline_seed12345.json codex_perf_output_prefix=iteration3_contract_violation_check` создал summary со `Status: fail` и `Candidate count: 1`.
- [x] Diff helper репортит регрессии `>20%` и улучшения `>10%` — прошло (passed); проверено: `iteration3_regression_check_diff_summary.md` содержит `frame_summary.latest_frame_ms` `+25.0%` -> `Status: fail`, а `iteration3_progress_check_diff_summary.md` содержит `native_profiling.chunk_generator.phase_avg_ms.total_ms` `-15.0%` -> `Status: progress`.
- [x] Repo-specific observatory workflow не хранится только в `.claude/skills/` — прошло (passed); проверено: существует `.agents/skills/perf-observatory/SKILL.md`, существует `.claude/skills/perf-observatory.md`, а design brief теперь прямо говорит, что `.claude` допускается только как compatibility mirror.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `quick_validate.py` для `.agents/skills/perf-observatory`, grep по `SKILL.md` / mirror / design brief, чтение generated diff summary `.md` файлов.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): запущен только для helper-скрипта через `Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tools/perf_baseline_diff.gd`; артефакты: `iteration3_contract_violation_check_diff_summary.*`, `iteration3_clean_stable_check_diff_summary.*`, `iteration3_regression_check_diff_summary.*`, `iteration3_progress_check_diff_summary.*`.
- Ручная проверка пользователем (Manual human verification): не требуется.
- Рекомендованная проверка пользователем (Suggested human check): при желании попросить агента "сравни новый perf artifact с baseline" и убедиться, что он идёт через JSON-first workflow и `tools/perf_baseline_diff.gd`.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): helper сравнивает 35 числовых метрик из `boot.observations`, `frame_summary.category_peaks`, `frame_summary.latest_debug_snapshot`, `native_profiling.chunk_generator.*`, `native_profiling.topology_builder.*` и отдельно проверяет `contract_violations`.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): выполнен для helper-инструмента, не для gameplay-scene proof. Результаты: `baseline_seed12345.json -> fail` из-за `contract_violations=1`; `iteration3_clean_baseline_fixture.json -> stable`; `iteration3_regression_fixture.json -> fail` из-за `frame_summary.latest_frame_ms +25.0%`; `iteration3_progress_fixture.json -> progress` из-за `native_profiling.chunk_generator.phase_avg_ms.total_ms -15.0%`.
- Ручная проверка пользователем (Manual human verification): не требуется.
- Рекомендованная проверка пользователем (Suggested human check): после следующего реального `codex_perf_test` прогнать helper на свежем `result.json` против `baseline_seed12345.json` и проверить, что summary выделяет только фактические contract/regression/progress изменения.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep `DATA_CONTRACTS.md` для `perf-observatory`: `0 matches`
- Grep `DATA_CONTRACTS.md` для `perf_baseline_diff`: `0 matches`
- Grep `DATA_CONTRACTS.md` для `codex_perf_baseline` / `codex_perf_candidate`: `0 matches`
- Grep `PUBLIC_API.md` для `perf-observatory`: `0 matches`
- Grep `PUBLIC_API.md` для `perf_baseline_diff`: `0 matches`
- Grep `PUBLIC_API.md` для `codex_perf_baseline` / `codex_perf_candidate`: `0 matches`
- Секция "Required updates" в спеке: есть — Iteration 3 требует repo-structure rule; `DATA_CONTRACTS.md` / `PUBLIC_API.md` не требовались в этой итерации, rule выполнен через repo-specific skill + optional mirror

### Наблюдения вне задачи (Out-of-scope observations)
- В epic всё ещё висит вне scope blocker из Iteration 2: `ZeroToleranceReadiness` assertion spam в `route`, `speed_traverse`, `chunk_revisit`.

### Оставшиеся блокеры (Remaining blockers)
- Для Iteration 3: нет.
- Для всего epic вне scope текущего шага: остаётся Iteration 2 blocker с `ZeroToleranceReadiness` assertion spam.

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- не требовалось (not required) - grep для `perf-observatory`, `perf_baseline_diff`, `codex_perf_baseline`, `codex_perf_candidate` вернул `0 matches`

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) - grep для `perf-observatory`, `perf_baseline_diff`, `codex_perf_baseline`, `codex_perf_candidate` вернул `0 matches`

### Iteration 4 - Stress / Scale Presets
**Status**: completed
**Started**: 2026-04-16
**Completed**: 2026-04-16

#### Проверки приёмки (Acceptance tests)
- [x] `codex_stress_mode=mass_buildings codex_stress_count=200` runs headless and exits cleanly
- [x] resulting JSON contains a `stress` block with mode, target count, actual count, and timing/frame metrics
- [x] stress collection remains disabled outside explicit stress args
- [x] stress tooling does not silently widen gameplay scope or bypass runtime-safe entrypoints

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `StressDriver`, `stress_run_completed`, `codex_stress_mode`, and `PerfTelemetryCollector` - stress-driver layer landed; collector ownership/rebuild policy updated
- [x] Grep `PUBLIC_API.md` for `StressDriver`, `stress_run_completed`, `codex_stress_mode`, and `PerfTelemetryCollector` - `StressDriver` / signal stay non-public, `codex_stress_mode` + artifact semantics documented in debug artifact section
- [x] Documentation debt section reviewed - Iteration 4 requirement satisfied with `DATA_CONTRACTS.md` + `PUBLIC_API.md` updates

#### Files touched
- `.claude/agent-memory/active-epic.md` - moved epic to Iteration 4 completion and recorded closure evidence
- `core/debug/stress_driver.gd` - added explicit debug-only stress runner for `mass_buildings`, `long_traverse`, `speed_traverse`, `deep_mine`, plus explicit refusal for unsupported presets without sanctioned entrypoints
- `core/debug/perf_telemetry_collector.gd` - waited for stress completion, serialized `stress` block, and exposed stress-enabled metadata in the JSON artifact
- `scenes/world/game_world_debug.gd` - wired `StressDriver` into the existing debug/bootstrap path and collector setup
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - documented `Stress Driver Proof Record` ownership and updated `Perf Telemetry Snapshot` semantics
- `docs/00_governance/PUBLIC_API.md` - documented optional `stress` payload in `debug_exports/perf/result.json`
- `debug_exports/perf/iteration4_mass_buildings.json`
- `debug_exports/perf/iteration4_mass_buildings.log`
- `debug_exports/perf/iteration4_no_stress.json`
- `debug_exports/perf/iteration4_no_stress.log`

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлен отдельный debug-only драйвер нагрузки `StressDriver`, который включается только через `codex_stress_mode=...` и собирает proof summary для stress/scalability сценариев.
- Для текущей итерации драйвер реально выполняет `mass_buildings`, `long_traverse`, `speed_traverse` и `deep_mine`, а для `entity_swarm` / `dense_world` честно останавливается с явным сообщением, потому что в текущем `PUBLIC_API.md` нет санкционированного пути для swarm spawn или runtime density override.
- `PerfTelemetryCollector` теперь ждёт завершения stress-run, пишет top-level `stress` block в тот же observatory JSON и выставляет `stress_enabled` / `stress_completion` в `meta`.
- Обновлены канонические документы: в `DATA_CONTRACTS.md` добавлен слой `Stress Driver Proof Record`, а в `PUBLIC_API.md` уточнено, что `debug_exports/perf/result.json` может содержать optional `stress` payload при явном stress-run.

### Корневая причина (Root cause)
- До этой итерации observatory умел мерить обычный perf/runtime proof, но не имел отдельного owner для масштабных stress/scalability прогонов. Из-за этого large-scale proof нужно было бы собирать ad hoc, без отдельного JSON-summary и без явной contract-дисциплины по safe entrypoints.

### Изменённые файлы (Files changed)
- `.claude/agent-memory/active-epic.md`
- `core/debug/stress_driver.gd`
- `core/debug/perf_telemetry_collector.gd`
- `scenes/world/game_world_debug.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`
- `debug_exports/perf/iteration4_mass_buildings.json`
- `debug_exports/perf/iteration4_mass_buildings.log`
- `debug_exports/perf/iteration4_no_stress.json`
- `debug_exports/perf/iteration4_no_stress.log`

### Проверки приёмки (Acceptance tests)
- [x] `codex_stress_mode=mass_buildings codex_stress_count=200` запускается headless и корректно завершает run — прошло (passed); проверено: `Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_stress_mode=mass_buildings codex_stress_count=200 codex_world_seed=12345 codex_perf_output=debug_exports/perf/iteration4_mass_buildings.json codex_quit_on_perf_complete` завершился с `exit_code=0`, лог записан в `debug_exports/perf/iteration4_mass_buildings.log`
- [x] JSON содержит `stress` block с mode / target_count / actual_count / timing/frame metrics — прошло (passed); проверено: `iteration4_mass_buildings.json` содержит `mode=mass_buildings`, `target_count=200`, `actual_count=200`, `total_placement_ms=72.3560000000001`, `avg_placement_ms=0.36178`, `peak_placement_ms=0.712`, `frame_avg_during_ms=7.29313275613276`, `frame_p99_during_ms=16.6666666666667`, `hitches_during=1`
- [x] stress collection остаётся выключенным без явных stress args — прошло (passed); проверено: отдельный headless run без `codex_stress_mode` записал `debug_exports/perf/iteration4_no_stress.json` с `meta.stress_enabled=false` и пустым `stress { }`
- [x] stress tooling не обходит runtime-safe entrypoints и не расширяет gameplay scope молча — прошло (passed); проверено: grep в `core/debug/stress_driver.gd` показывает `can_place_selected_building_at`, `place_selected_building_at`, `remove_building_at`, `ValidationContext.collect_validation_scrap()`, `ValidationContext.mine_tile()`, а unsupported presets завершаются явным failure вместо скрытого bypass

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): grep по `core/debug/stress_driver.gd`, `DATA_CONTRACTS.md`, `PUBLIC_API.md`, чтение `iteration4_mass_buildings.json` и `iteration4_no_stress.json`
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): выполнен дважды через headless `GameWorld`; артефакты: `debug_exports/perf/iteration4_mass_buildings.json`, `debug_exports/perf/iteration4_mass_buildings.log`, `debug_exports/perf/iteration4_no_stress.json`, `debug_exports/perf/iteration4_no_stress.log`
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): при желании повторно запустить `codex_perf_test codex_stress_mode=mass_buildings codex_stress_count=200` и убедиться, что `stress` block появляется только в stress-run, а без `codex_stress_mode` остаётся пустым

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): `StressDriver` пишет per-action/per-frame summary только в explicit `codex_stress_mode` path; `PerfTelemetryCollector` ждёт stress completion и сериализует `stress` только при explicit stress request
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): выполнен. Команды:
  - `Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_stress_mode=mass_buildings codex_stress_count=200 codex_world_seed=12345 codex_perf_output=debug_exports/perf/iteration4_mass_buildings.json codex_quit_on_perf_complete`
  - `Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_world_seed=12345 codex_perf_output=debug_exports/perf/iteration4_no_stress.json codex_quit_on_perf_complete`
- Сводка (Summary): `iteration4_mass_buildings.json` -> `stress.state=passed`, `actual_count=200`, `frame_avg_during_ms=7.29313275613276`, `frame_p99_during_ms=16.6666666666667`, `hitches_during=1`; `iteration4_no_stress.json` -> `meta.stress_enabled=false`, empty `stress {}`
- Проверенные метрики / строки: `mode`, `target_count`, `actual_count`, `total_placement_ms`, `avg_placement_ms`, `peak_placement_ms`, `frame_avg_during_ms`, `frame_p99_during_ms`, `hitches_during`, `stress_enabled`
- `ERROR` / `WARNING`: в `iteration4_mass_buildings.log` и `iteration4_no_stress.log` остались только уже наблюдавшиеся engine-exit noise (`ObjectDB instances leaked at exit`, `resources still in use at exit`); warning из переполнения inventory был устранён правкой этого шага
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): если понадобится оценить другие presets, запускать их только как explicit proof run с отдельным `codex_perf_output`

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep `DATA_CONTRACTS.md` для `StressDriver`: matches в строках `67`, `786`, `816-838` — обновлено (added new layer + collector ownership)
- Grep `DATA_CONTRACTS.md` для `stress_run_completed`: match в строке `838` — обновлено
- Grep `DATA_CONTRACTS.md` для `codex_stress_mode`: matches в строках `67`, `816`, `819`, `821` — обновлено
- Grep `DATA_CONTRACTS.md` для `PerfTelemetryCollector`: matches в строках `64-67`, `154`, `762`, `786-803`, `818` — обновлено/актуализировано для stress semantics
- Grep `PUBLIC_API.md` для `StressDriver`: `0 matches` — не является sanctioned public surface
- Grep `PUBLIC_API.md` для `stress_run_completed`: `0 matches` — signal remains internal/debug-only
- Grep `PUBLIC_API.md` для `codex_stress_mode`: match в строке `1787` — обновлено
- Grep `PUBLIC_API.md` для `PerfTelemetryCollector`: matches в строках `221`, `1787-1788` — обновлено/актуализировано для optional `stress` payload
- Секция "Required updates" в спеке: есть — Iteration 4 требует document `Stress Driver` ownership; выполнено через `DATA_CONTRACTS.md`, а `PUBLIC_API.md` дополнительно синхронизирован с artifact semantics

### Наблюдения вне задачи (Out-of-scope observations)
- `entity_swarm` и `dense_world` intentionally оставлены explicit unsupported presets, потому что в текущем `PUBLIC_API.md` нет санкционированного spawn/density entrypoint и Iteration 4 не даёт права придумывать обходной owner path
- В headless логах по-прежнему остаётся старый engine-exit noise (`ObjectDB instances leaked at exit`, `resources still in use at exit`)
- В эпике всё ещё висит вне scope blocker из Iteration 2: `ZeroToleranceReadiness` assertion spam в `route`, `speed_traverse`, `chunk_revisit`

### Оставшиеся блокеры (Remaining blockers)
- Для Iteration 4: нет
- Для всего epic вне scope текущего шага: остаётся Iteration 2 blocker с `ZeroToleranceReadiness` assertion spam

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- обновлено: добавлен `Stress Driver Proof Record`, обновлены row/owner/invariants для `Perf Telemetry Snapshot`; grep для `StressDriver`, `stress_run_completed`, `codex_stress_mode`, `PerfTelemetryCollector` это подтверждает

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- обновлено: `debug_exports/perf/result.json` теперь явно описывает optional `stress` block при `codex_stress_mode=...`; grep для `codex_stress_mode` и `PerfTelemetryCollector` подтверждает строку `1787`

### Iteration 5 - Streaming Optimization Handoff (Separate Spec Required)
**Status**: blocked
**Started**: 2026-04-16
**Completed**: —

#### Проверки приёмки (Acceptance tests)
- [ ] a separate approved streaming optimization spec exists before optimization code starts — требуется ручная проверка пользователем (manual human verification required); создан draft `docs/02_system_specs/world/frontier_streaming_optimization_spec.md`, но approval должен дать человек
- [x] observatory can report before/after metrics for that future spec without schema changes — прошло (passed); проверено чтением `debug_exports/perf/baseline_seed12345.json`, `debug_exports/perf/iteration2_route_room_power_mining.json`, `debug_exports/perf/iteration2_extended_scenarios.json`: уже существуют поля `contract_violations[]`, `frame_summary.latest_frame_ms`, `frame_summary.category_peaks.visual/dispatcher`, `frame_summary.latest_debug_snapshot.visual_build_ms/dispatcher_ms`, `streaming.overlay_snapshot.metrics.average_chunk_processing_time_ms`, `streaming.overlay_snapshot.metrics.worst_chunk_stage_time_ms`, `streaming.overlay_snapshot.metrics.queue_sizes.frontier_capacity.queue_frontier_critical`, `streaming.overlay_snapshot.metrics.queue_sizes.frontier_plan.speed_class/travel_mode`, а также scenario-блоки `route`, `speed_traverse`, `chunk_revisit`

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `frontier_streaming_optimization_spec`, `streaming_opt_before_seed12345`, and `streaming_opt_candidate_seed12345` - `0 matches`; contract docs not updated by this doc-only handoff step
- [x] Grep `PUBLIC_API.md` for `frontier_streaming_optimization_spec`, `streaming_opt_before_seed12345`, and `streaming_opt_candidate_seed12345` - `0 matches`; public API docs not updated by this doc-only handoff step
- [x] Documentation debt section reviewed - observatory doc debt was already satisfied in Iteration 4; Iteration 5 adds a separate draft spec without changing runtime semantics

#### Files touched
- `.claude/agent-memory/active-epic.md` - recorded Iteration 5 handoff state and blocker
- `docs/02_system_specs/world/frontier_streaming_optimization_spec.md` - added separate draft streaming optimization spec with observatory-proof contract and future implementation iterations

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Создана отдельная draft-спека `docs/02_system_specs/world/frontier_streaming_optimization_spec.md` для будущей streaming optimization feature, как требует Iteration 5 из observatory spec.
- В новой спеке зафиксированы performance/scalability guardrails, affected owners, запрещённые shortcuts и разбивка на будущие implementation iterations без правок observatory/runtime-кода.
- Before/after proof contract привязан только к уже существующим observatory JSON-полям и scenario-блокам, чтобы будущая оптимизация не требовала schema change в `PerfTelemetryCollector`.

### Корневая причина (Root cause)
- Observatory уже умеет собирать машинно-читаемые артефакты, но без отдельной streaming optimization spec следующая фаза работы рисковала смешать proof infrastructure с runtime optimization и начать менять streaming code без отдельного spec-first контракта.

### Изменённые файлы (Files changed)
- `.claude/agent-memory/active-epic.md`
- `docs/02_system_specs/world/frontier_streaming_optimization_spec.md`

### Проверки приёмки (Acceptance tests)
- [ ] Отдельная approved streaming optimization spec существует до начала optimization code — требуется ручная проверка пользователем (manual human verification required); сейчас создан только draft, нужен review/approval человеком
- [x] Observatory может репортить before/after метрики для будущей спеки без schema changes — прошло (passed); проверено чтением существующих JSON-артефактов и подтверждением наличия всех field paths, на которые ссылается новая спека

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): grep по `frontier_streaming_optimization_spec.md`, чтение `debug_exports/perf/baseline_seed12345.json`, `debug_exports/perf/iteration2_route_room_power_mining.json`, `debug_exports/perf/iteration2_extended_scenarios.json`
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy; использованы существующие observatory artifacts
- Ручная проверка пользователем (Manual human verification): требуется для approval новой draft-спеки
- Рекомендованная проверка пользователем (Suggested human check): прочитать `docs/02_system_specs/world/frontier_streaming_optimization_spec.md` и либо одобрить её как baseline для streaming optimization, либо вернуть замечания до старта runtime-кода

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): существующие observatory artifacts уже содержат поля `contract_violations`, `frame_summary`, `streaming.overlay_snapshot.metrics.queue_sizes.*`, `average_chunk_processing_time_ms`, `worst_chunk_stage_time_ms`, а также scenario proof records `route`, `speed_traverse`, `chunk_revisit`
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy
- Ручная проверка пользователем (Manual human verification): не требуется для field-presence proof, требуется только для approval draft-спеки
- Рекомендованная проверка пользователем (Suggested human check): после approval использовать команды из новой спеки для фиксации dedicated streaming baseline и кандидата на одном и том же seed

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep `DATA_CONTRACTS.md` для `frontier_streaming_optimization_spec`: `0 matches`
- Grep `DATA_CONTRACTS.md` для `streaming_opt_before_seed12345`: `0 matches`
- Grep `DATA_CONTRACTS.md` для `streaming_opt_candidate_seed12345`: `0 matches`
- Grep `PUBLIC_API.md` для `frontier_streaming_optimization_spec`: `0 matches`
- Grep `PUBLIC_API.md` для `streaming_opt_before_seed12345`: `0 matches`
- Grep `PUBLIC_API.md` для `streaming_opt_candidate_seed12345`: `0 matches`
- Секция "Required updates" в observatory spec: есть — Iteration 5 требует separate streaming optimization spec; выполнено созданием draft-спеки, approval остаётся за человеком

### Наблюдения вне задачи (Out-of-scope observations)
- Design brief упоминает `deferred terrain-only fast pass`, но из-за `DOCUMENT_PRECEDENCE.md`, `zero_tolerance_chunk_readiness_spec.md` и `frontier_native_runtime_architecture_spec.md` это нельзя трактовать как player-visible publish-first shortcut; в новой спеке этот вариант оставлен только как возможный hidden prewarm через будущую amendment
- В эпике всё ещё остаётся старый blocker из Iteration 2: `ZeroToleranceReadiness` assertion spam в route-like proof paths

### Оставшиеся блокеры (Remaining blockers)
- Нужен human review/approval для `docs/02_system_specs/world/frontier_streaming_optimization_spec.md`, иначе первую acceptance-проверку Iteration 5 нельзя честно отметить как passed

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- не требовалось (not required) - grep для `frontier_streaming_optimization_spec`, `streaming_opt_before_seed12345`, `streaming_opt_candidate_seed12345` вернул `0 matches`

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) - grep для `frontier_streaming_optimization_spec`, `streaming_opt_before_seed12345`, `streaming_opt_candidate_seed12345` вернул `0 matches`

#### Blockers
- Human approval of `docs/02_system_specs/world/frontier_streaming_optimization_spec.md` is required before any streaming optimization code starts
