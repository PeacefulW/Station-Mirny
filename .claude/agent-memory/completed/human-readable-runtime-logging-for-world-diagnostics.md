# Epic: Human Readable Runtime Logging For World Diagnostics

**Spec**: `docs/02_system_specs/world/human_readable_runtime_logging_spec.md`
**Started**: 2026-04-10
**Current iteration**: 4
**Total iterations**: 4

## Documentation debt

Track required documentation updates from the spec's "Required contract and API updates"
section. Review every iteration and update immediately if semantics drift beyond the
preferred transient-log-only path.

- [x] `DATA_CONTRACTS.md` — not required by default; Iteration 4 stayed transient-log-only and grep found 0 references to new dedupe/severity helper names
- [x] `PUBLIC_API.md` — not required by default; Iteration 4 added no public gameplay/read API and grep found 0 references to new dedupe/severity helper names
- [x] `PERFORMANCE_CONTRACTS.md` — updated in Iteration 4 with canonical log layers, severity/root-cause rules, anti-spam policy, and explicit-request runtime proof wording
- [x] `WORKFLOW.md` — not required by default; Iteration 4 did not change closure-report governance or require a new per-spec logging vocabulary rule
- **Deadline**: review every iteration; `PERFORMANCE_CONTRACTS.md` is due no later than Iteration 4 if that policy lands
- **Status**: done

## Iterations

### Iteration 1 — Logging vocabulary and canonical message shape
**Status**: completed
**Started**: 2026-04-10
**Completed**: 2026-04-10

#### Проверки приёмки (Acceptance tests)
- [x] A captured human summary line includes actor, action, target, reason, impact, and state in human wording — verified by file read/grep in `core/debug/world_runtime_diagnostic_log.gd` (`format_summary`, `emit_summary`) and populated records in `core/systems/world/world_perf_probe.gd` / `core/systems/world/chunk_manager.gd`
- [x] A captured human summary line does not expose bare private names such as `_request_refresh`, `streaming_truth`, or `border_fix` without a human gloss — verified by summary using `*_human` fields, glossary entries in `core/debug/world_runtime_diagnostic_log.gd`, and raw terms staying in detail/perf code fields only
- [x] A captured technical detail line still contains stable key fields and useful internal terminology for grep/debug — verified by `format_detail()` emitting `actor/action/target/reason/impact/state/code` and `ChunkManager` passing queue/issues detail
- [x] Static review confirms no runtime behavior, queue ownership, or mutation semantics changed outside logging call sites — verified by bounded review of the touched hunks in `world_perf_probe.gd` and `chunk_manager.gd`; queueing/mutation paths were not changed

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — `WorldRuntimeDiagnosticLog`: `0 matches`; `report_budget_overrun`: `0 matches`; `_maybe_log_player_chunk_visual_status`: `0 matches`
- [x] Grep PUBLIC_API.md for changed names — `WorldRuntimeDiagnosticLog`: `0 matches`; `report_budget_overrun`: `0 matches`; `_maybe_log_player_chunk_visual_status`: `0 matches`
- [x] Documentation debt section reviewed — current implementation stayed on the preferred transient-log-only path; `DATA_CONTRACTS.md`, `PUBLIC_API.md`, and `WORKFLOW.md` remain not due; `PERFORMANCE_CONTRACTS.md` review stays pending until Iteration 4

#### Files touched
- `.claude/agent-memory/active-epic.md` — started Iteration 1 tracking for the runtime logging spec
- `core/debug/world_runtime_diagnostic_log.gd` — added shared human-summary / technical-detail formatting helper and glossary
- `core/systems/world/world_perf_probe.gd` — added human-readable perf summary emission for contract overruns, threshold timings, and budget overruns
- `core/systems/world/chunk_manager.gd` — replaced raw player-chunk visual status print with summary/detail diagnostic emission

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлен общий helper `WorldRuntimeDiagnosticLog`, который собирает человекочитаемую сводку (human summary) и техническую строку деталей (technical detail) из одних и тех же семантических полей.
- В `WorldPerfProbe` пилотно подключены человекочитаемые perf-сводки для трёх surface'ов: превышение budget, превышение contract и заметный timing threshold, при этом точные `[WorldPerf]` raw строки сохранены.
- В `ChunkManager` raw-лог статуса текущего чанка игрока заменён на связку summary/detail с явными `actor`, `action`, `target`, `reason`, `impact`, `state` и внутренним `code` только в detail.

### Корневая причина (Root cause)
- Текущие world/runtime/perf логи были перегружены внутренними именами и queue-терминами, поэтому человек должен был угадывать, кто именно сообщил о проблеме, насколько она заметна игроку и является ли это root cause или только follow-up диагностикой.

### Изменённые файлы (Files changed)
- `.claude/agent-memory/active-epic.md` — переключён tracker на новую spec и зафиксирован статус Iteration 1
- `core/debug/world_runtime_diagnostic_log.gd` — новый formatter/glossary для summary/detail diagnostic records
- `core/systems/world/world_perf_probe.gd` — человекочитаемые perf summary lines поверх существующих raw timing/warning lines
- `core/systems/world/chunk_manager.gd` — player-chunk diagnostic surface переведён на canonical message shape

### Проверки приёмки (Acceptance tests)
- [x] Human summary line включает actor, action, target, reason, impact и state в human wording — прошло (passed) (`format_summary()` читает все шесть human fields, а call sites в `WorldPerfProbe` и `ChunkManager` заполняют их явно)
- [x] Human summary line не выбрасывает bare `_request_refresh`, `streaming_truth` или `border_fix` без human gloss — прошло (passed) (summary использует только `*_human`; glossary покрывает `_request_refresh` и `border_fix`, raw `code` остаётся в detail/perf paths)
- [x] Technical detail line сохраняет стабильные key fields и grep-friendly internal terms — прошло (passed) (`format_detail()` эмитит `actor/action/target/reason/impact/state/code`, а `ChunkManager` добавляет `issues_internal`, queue depths и request flags)
- [x] Runtime behavior / queue ownership / mutation semantics вне logging call sites не изменены — прошло (passed) (bounded static review изменённых hunk'ов в `world_perf_probe.gd` и `chunk_manager.gd`)

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `rg -n "format_summary|actor_human|action_human|target_human|reason_human|impact_human|state_human" core/debug/world_runtime_diagnostic_log.gd`; `rg -n "actor=|action=|target=|reason=|impact=|state=|emit_detail|emit_summary" core/debug/world_runtime_diagnostic_log.gd core/systems/world/chunk_manager.gd`; `rg -n "WorldRuntimeDiagnosticLog|_emit_budget_overrun_summary|_emit_contract_overrun_summary|_emit_threshold_timing_summary|_emit_player_chunk_visual_status_diag|_build_player_chunk_visual_diag_record" core/debug/world_runtime_diagnostic_log.gd core/systems/world/world_perf_probe.gd core/systems/world/chunk_manager.gd`
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): опционально запустить любой существующий world/perf route и убедиться, что рядом с raw `[WorldPerf]` строками появились понятные summary/detail сообщения

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): helper строит строки только из уже известных локальных фактов и не сканирует loaded world; `WorldPerfProbe` и `ChunkManager` меняют только formatting/emission layer
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): при желании прогнать текущий perf harness и проверить, что human summary не заменяет raw timings, а дополняет их

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `WorldRuntimeDiagnosticLog`: `0 matches`
- Grep DATA_CONTRACTS.md для `report_budget_overrun`: `0 matches`
- Grep DATA_CONTRACTS.md для `_maybe_log_player_chunk_visual_status`: `0 matches`
- Grep PUBLIC_API.md для `WorldRuntimeDiagnosticLog`: `0 matches`
- Grep PUBLIC_API.md для `report_budget_overrun`: `0 matches`
- Grep PUBLIC_API.md для `_maybe_log_player_chunk_visual_status`: `0 matches`
- Секция "Required updates" в спеке: есть — текущая Iteration 1 осталась в transient-log-only scope, поэтому `DATA_CONTRACTS.md` и `PUBLIC_API.md` не требовались; review `PERFORMANCE_CONTRACTS.md` отложен до Iteration 4 по самой spec

### Наблюдения вне задачи (Out-of-scope observations)
- В `chunk_manager.gd` уже есть более ранние незакоммиченные изменения вне этой итерации; они не трогались.
- Standalone `Godot --script --check-only` для `chunk_manager.gd` упёрся в существующее разрешение `FrameBudgetDispatcher` на строке 313, то есть вне нового logging-hunk; это не меняло scope текущей итерации.

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- не требовалось (not required) (`WorldRuntimeDiagnosticLog`, `report_budget_overrun`, `_maybe_log_player_chunk_visual_status` — по grep `0 matches`)

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) (`WorldRuntimeDiagnosticLog`, `report_budget_overrun`, `_maybe_log_player_chunk_visual_status` — по grep `0 matches`)

#### Blockers
- none

---

### Iteration 2 — Route/validation outcome logging
**Status**: completed
**Started**: 2026-04-10
**Completed**: 2026-04-10

#### Проверки приёмки (Acceptance tests)
- [x] After route validation, the final summary line says in human language whether the route `finished`, `not converged`, or `blocked`, and names the blocker — verified by captured runtime log lines `1071-1072` in `debug_exports/perf/runtime_logging_iteration2_seed12345.log`; static code review also confirms explicit `finished` / `not_converged` / `blocked` branches in `core/debug/runtime_validation_driver.gd`
- [x] The log distinguishes `player_visible_issue` from `background_debt_only` — verified by runtime detail line `1072` (`impact=player_visible_issue`) plus static review of `WorldRuntimeDiagnosticLog` impact constants and `_resolve_validation_impact()` in `core/debug/runtime_validation_driver.gd`
- [x] The log names the impacted chunk, region, or scope for the blocker — verified by runtime summary/detail lines `1071-1072` (`текущий чанк игрока (0,0)`, `scope=player_chunk`, `target_chunk=(0,0)`) plus static review of `_resolve_validation_target_scope()` / `_resolve_validation_target_human()`
- [x] The human summary line is understandable without knowing private field names such as `_is_topology_dirty` or `_redrawing_chunks` — verified by captured summary line `1071` and by `_resolve_validation_reason_human()` / `_resolve_validation_target_human()` in `core/debug/runtime_validation_driver.gd`

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — `VALIDATION_PREFIX`, `humanize_known_term`, `_emit_validation_wait_status`, `_emit_validation_outcome`, `_emit_validation_failure` => `0 matches`
- [x] Grep PUBLIC_API.md for changed names — `VALIDATION_PREFIX`, `humanize_known_term`, `_emit_validation_wait_status`, `_emit_validation_outcome`, `_emit_validation_failure` => `0 matches`
- [x] Documentation debt section reviewed — Iteration 2 stayed in transient diagnostic/logging scope; `DATA_CONTRACTS.md` and `PUBLIC_API.md` remain not due, `PERFORMANCE_CONTRACTS.md` is still deferred to Iteration 4 by spec

#### Files touched
- `.claude/agent-memory/active-epic.md` — Iteration 2 started
- `core/debug/world_runtime_diagnostic_log.gd` — added validation prefix constant and glossary/humanization support for validation vocabulary
- `core/debug/runtime_validation_driver.gd` — replaced raw route/catch-up/failure prints with human summary + technical detail outcome logs and target-scope classification

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- В `RuntimeValidationDriver` добавлены человекочитаемые outcome-логи для маршрута ручной проверки (manual validation route): ожидание сходимости, финальный исход и failure-path теперь идут через summary/detail формат.
- Driver теперь классифицирует blocker, impacted scope и impact band: `player_chunk` / `adjacent_loaded_chunk` / `far_runtime_backlog` и `player_visible_issue` / `background_debt_only` / `informational_only`.
- Техническая detail-строка сохраняет grep-friendly поля `actor`, `action`, `target`, `reason`, `impact`, `state`, raw blocker `code` и queue/topology snapshot без вываливания этих private names в human summary.
- В `WorldRuntimeDiagnosticLog` добавлены validation prefix и human glossary entries для route/blocker vocabulary, чтобы `[CodexValidation]` summary оставался русскоязычным и понятным.

### Корневая причина (Root cause)
- До Iteration 2 validation-driver писал в лог в основном raw строки с internal terms и state dumps, поэтому человек видел `blocker=topology` или технические флаги, но не получал прямого ответа: маршрут завершён, не сошёлся или заблокирован, где именно проблема и насколько это заметно игроку.

### Изменённые файлы (Files changed)
- `.claude/agent-memory/active-epic.md` — зафиксирован прогресс Iteration 2 и приложен closure report
- `core/debug/world_runtime_diagnostic_log.gd` — validation vocabulary support (`VALIDATION_PREFIX`, `manual_validation_route`, `topology`, `redraw_only`, `humanize_known_term`)
- `core/debug/runtime_validation_driver.gd` — human-readable wait/outcome/failure emission, blocker/scope classification, runtime detail snapshot

### Проверки приёмки (Acceptance tests)
- [x] Финальная summary line после route validation говорит, что маршрут `blocked`, и называет blocker — прошло (passed) (`debug_exports/perf/runtime_logging_iteration2_seed12345.log`, строки `1071-1072`; code branches для `finished` / `not_converged` / `blocked` подтверждены статически в `core/debug/runtime_validation_driver.gd`)
- [x] Лог различает `player_visible_issue` и `background_debt_only` — прошло (passed) (runtime detail line `1072` показывает `impact=player_visible_issue`; статическая проверка `_resolve_validation_impact()` подтверждает ветку `background_debt_only` для дальнего backlog)
- [x] Лог называет затронутый chunk/scope blocker'а — прошло (passed) (runtime summary/detail `1071-1072` показывают `текущий чанк игрока (0,0)` и `scope=player_chunk`; статические resolver'ы покрывают `adjacent_loaded_chunk` и `far_runtime_backlog`)
- [x] Human summary line читается без знания private field names — прошло (passed) (runtime summary `1071` использует human wording, а private flags остаются только в detail fields)

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `rg -n 'emit_summary\\(record, WorldRuntimeDiagnosticLog\\.VALIDATION_PREFIX\\)|emit_detail\\(record, detail_fields, WorldRuntimeDiagnosticLog\\.VALIDATION_PREFIX\\)|\"finished\"|\"not_converged\"|\"blocked\"|_resolve_validation_reason_human|_resolve_validation_target_human|_resolve_validation_target_scope' core/debug/runtime_validation_driver.gd`; `rg -n 'IMPACT_PLAYER_VISIBLE|IMPACT_BACKGROUND_DEBT|player_chunk|adjacent_loaded_chunk|far_runtime_backlog|reached_waypoints|target_chunk|scope|load_queue_preview|failure_message' core/debug/runtime_validation_driver.gd core/debug/world_runtime_diagnostic_log.gd`
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): `.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_validate_runtime codex_validate_route=local_ring codex_world_seed=12345`
- Артефакты: `debug_exports/perf/runtime_logging_iteration2_seed12345.log`
- Проверенные строки: `1016-1019` (wait summary/detail), `1071-1072` (final blocked summary/detail)
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): при желании открыть лог и убедиться, что `[CodexValidation]` summary остаётся читаемым даже без знания `topology_dirty`, `load_queue` и других private markers

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): logging-layer собирает message fields только из уже имеющихся owner facts и не меняет validation behavior
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): выполнен; лог `debug_exports/perf/runtime_logging_iteration2_seed12345.log`
- Сводка (Summary): отдельный summary artifact не создавался
- Проверенные метрики / строки: captured `[CodexValidation]` wait/outcome lines, `impact=player_visible_issue`, `scope=player_chunk`, `reason=topology_rebuild_not_complete`
- `ERROR` / `WARNING`: есть — pre-existing `WorldPerf` budget warnings по streaming/topology/redraw и shutdown `ERROR: 16 resources still in use at exit`; logging-итерация не добавила новых error markers со своим namespace
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): если захотите сравнить ещё и `not_converged` / `background_debt_only` case, повторить тот же harness на seed/route, где validation route дойдёт до drain without timeout

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `VALIDATION_PREFIX`: `0 matches`
- Grep DATA_CONTRACTS.md для `humanize_known_term`: `0 matches`
- Grep DATA_CONTRACTS.md для `_emit_validation_wait_status`: `0 matches`
- Grep DATA_CONTRACTS.md для `_emit_validation_outcome`: `0 matches`
- Grep DATA_CONTRACTS.md для `_emit_validation_failure`: `0 matches`
- Grep PUBLIC_API.md для `VALIDATION_PREFIX`: `0 matches`
- Grep PUBLIC_API.md для `humanize_known_term`: `0 matches`
- Grep PUBLIC_API.md для `_emit_validation_wait_status`: `0 matches`
- Grep PUBLIC_API.md для `_emit_validation_outcome`: `0 matches`
- Grep PUBLIC_API.md для `_emit_validation_failure`: `0 matches`
- Секция "Required updates" в спеке: есть — текущая Iteration 2 осталась в preferred transient-log-only path; `DATA_CONTRACTS.md` и `PUBLIC_API.md` не требовались, `PERFORMANCE_CONTRACTS.md` по spec всё ещё отложен до Iteration 4

### Наблюдения вне задачи (Out-of-scope observations)
- На seed `12345` runtime route завершился не успехом, а timeout-blocked состоянием из-за незавершённой topology rebuild; новая logging-итерация это корректно показала, но не пыталась чинить сам convergence debt.
- В том же логе остаются pre-existing `WorldPerf` warnings по `chunk_manager.streaming_load`, `chunk_manager.streaming_redraw`, `chunk_manager.topology_rebuild` и shutdown resource leak.
- Standalone `--check-only --script res://core/debug/runtime_validation_driver.gd` по-прежнему упирается в autoload-dependent `WorldGenerator` на старой строке `112`, поэтому для этой итерации опирались на runtime harness + статический review, а не на isolated script parse.

### Оставшиеся блокеры (Remaining blockers)
- нет для Iteration 2 logging scope

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- не требовалось (not required) (`VALIDATION_PREFIX`, `humanize_known_term`, `_emit_validation_wait_status`, `_emit_validation_outcome`, `_emit_validation_failure` — в `DATA_CONTRACTS.md` по grep `0 matches`)

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) (`VALIDATION_PREFIX`, `humanize_known_term`, `_emit_validation_wait_status`, `_emit_validation_outcome`, `_emit_validation_failure` — в `PUBLIC_API.md` по grep `0 matches`)

#### Blockers
- none

### Iteration 3 — Mining / border-fix / roof causality logging
**Status**: completed
**Started**: 2026-04-10
**Completed**: 2026-04-10

#### Проверки приёмки (Acceptance tests)
- [x] The log distinguishes initiators `stream_load`, `seam_mining_async`, `roof_restore`, `local_patch`, `shadow_refresh`, and `manual_validation_route` — verified by static grep in `core/debug/world_runtime_diagnostic_log.gd`, `core/systems/world/chunk_manager.gd`, `core/systems/world/mountain_roof_system.gd`, `core/systems/lighting/mountain_shadow_system.gd`, and `core/debug/runtime_validation_driver.gd`; runtime boot log also captured `actor=stream_load` lines `299-300`
- [x] For the seam/mining case, the log names the affected chunk or region and whether it is the player chunk, adjacent loaded chunk, or far backlog work — verified by static grep for `_emit_border_fix_queue_diag`, `queued_chunks`, `target_scope`, and `source_tile` in `core/systems/world/chunk_manager.gd`
- [x] For the roof-related case, the log can distinguish `wrong_state_calculated` from `later_overwrite` — verified by static grep for `_emit_roof_local_patch_diag`, `_emit_roof_restore_overwrite_diag`, `wrong_state_calculated`, and `later_overwrite` in `core/systems/world/mountain_roof_system.gd`
- [x] A seam-mining summary line states the queued follow-up work in human wording, while technical detail preserves internal terms such as `border_fix` — verified by static grep for `локальную правку и правку границы чанка`, `code_term = "border_fix"`, `follow_up`, and the `seam_mining_async` call site in `core/systems/world/chunk_manager.gd`
- [x] The human summary line does not require knowledge of private function names or queue symbols — verified by runtime boot log lines `299-300` for a human summary/detail pair and static review showing private terms stay in `code` / detail fields

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — `describe_chunk_scope`, `describe_term_list`, `format_coord_list`, `_emit_border_fix_queue_diag`, `_emit_roof_local_patch_diag`, `_emit_roof_restore_overwrite_diag`, `_emit_shadow_refresh_diag`, `seam_mining_async`, `roof_restore`, `shadow_refresh`, `wrong_state_calculated`, `later_overwrite`: `0 matches`; `local_patch`: matches existing unrelated indoor solver references at lines `1079`, `1096`
- [x] Grep PUBLIC_API.md for changed names — `describe_chunk_scope`, `describe_term_list`, `format_coord_list`, `_emit_border_fix_queue_diag`, `_emit_roof_local_patch_diag`, `_emit_roof_restore_overwrite_diag`, `_emit_shadow_refresh_diag`, `seam_mining_async`, `roof_restore`, `shadow_refresh`, `wrong_state_calculated`, `later_overwrite`: `0 matches`; `local_patch`: matches existing unrelated `IndoorSolver.solve_local_patch(...)` at line `1132`
- [x] Documentation debt section reviewed — Iteration 3 stayed in transient logging scope; `DATA_CONTRACTS.md` and `PUBLIC_API.md` remain not due, `PERFORMANCE_CONTRACTS.md` remains deferred to Iteration 4 by spec

#### Files touched
- `.claude/agent-memory/active-epic.md` — Iteration 3 progress, verification, and closure report
- `core/debug/world_runtime_diagnostic_log.gd` — added actor glossary and shared chunk-scope / term / coord formatting helpers
- `core/debug/world_runtime_diagnostic_log.gd.uid` — Godot-generated UID sidecar for the diagnostic helper
- `core/systems/world/chunk_manager.gd` — added `stream_load` and `seam_mining_async` border-fix queue diagnostics with target scope and queued chunk detail
- `core/systems/world/mountain_roof_system.gd` — added `local_patch` / `roof_restore` diagnostics for `wrong_state_calculated` and `later_overwrite`
- `core/systems/lighting/mountain_shadow_system.gd` — added `shadow_refresh` diagnostics when mining-driven shadow follow-up is queued

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлены owner-attributed diagnostics для `stream_load`, `seam_mining_async`, `local_patch`, `roof_restore` и `shadow_refresh`.
- `ChunkManager` теперь логирует, какой chunk получил `border_fix` follow-up и какой scope у target: `player_chunk`, `adjacent_loaded_chunk` или `far_runtime_backlog`.
- `MountainRoofSystem` теперь различает неполный локальный roof-патч (`wrong_state_calculated`) и deferred restore, который позже перезапишет owner чанка (`later_overwrite`).
- `MountainShadowSystem` теперь логирует mining-driven shadow follow-up с edge-cache / dirty-target detail.

### Корневая причина (Root cause)
- Mining / border-fix / roof / shadow цепочка раньше оставляла часть causal attribution в raw/internal терминах или вообще без отдельной owner-readable строки, поэтому из лога было трудно понять, кто поставил follow-up в очередь, какой chunk затронут и является ли причина неполным расчётом или поздним overwrite.

### Изменённые файлы (Files changed)
- `.claude/agent-memory/active-epic.md` — зафиксирован статус Iteration 3
- `core/debug/world_runtime_diagnostic_log.gd` — glossary + shared formatting helpers
- `core/debug/world_runtime_diagnostic_log.gd.uid` — Godot-generated UID sidecar для нового helper script
- `core/systems/world/chunk_manager.gd` — border-fix queue diagnostics для `stream_load` и `seam_mining_async`
- `core/systems/world/mountain_roof_system.gd` — roof causality diagnostics для `local_patch` / `roof_restore`
- `core/systems/lighting/mountain_shadow_system.gd` — shadow refresh diagnostics для mining follow-up

### Проверки приёмки (Acceptance tests)
- [x] Initiators `stream_load`, `seam_mining_async`, `roof_restore`, `local_patch`, `shadow_refresh`, `manual_validation_route` различаются — прошло (passed); проверено: `rg` по actor/call sites, runtime log lines `299-300` для `actor=stream_load`
- [x] Seam/mining log names affected chunk/scope — прошло (passed); проверено: `rg` показал `_emit_border_fix_queue_diag`, `queued_chunks`, `target_scope`, `source_tile`
- [x] Roof log distinguishes `wrong_state_calculated` и `later_overwrite` — прошло (passed); проверено: `rg` по `_emit_roof_local_patch_diag`, `_emit_roof_restore_overwrite_diag`, `wrong_state_calculated`, `later_overwrite`
- [x] Seam-mining summary states queued follow-up while detail preserves `border_fix` — прошло (passed); проверено: `rg` показал human wording `локальную правку и правку границы чанка` и detail/code fields with `border_fix`
- [x] Human summary does not require private function names — прошло (passed); проверено: runtime summary/detail pair in `debug_exports/perf/runtime_logging_iteration3_boot_seed12345_v2.log` lines `299-300`, plus static review of `*_human` fields

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `git diff --check`; `rg -n "stream_load|seam_mining_async|roof_restore|local_patch|shadow_refresh|manual_validation_route" ...`; `rg -n "_emit_border_fix_queue_diag|queued_chunks|target_scope|source_tile|правку границы чанка|последующая перерисовка|code.*border_fix" core/systems/world/chunk_manager.gd`; `rg -n "_emit_roof_local_patch_diag|_emit_roof_restore_overwrite_diag|wrong_state_calculated|later_overwrite" core/systems/world/mountain_roof_system.gd`; `rg -n "_emit_shadow_refresh_diag|shadow_refresh|edge cache|dirty_targets|edge_dirty_coords" core/systems/lighting/mountain_shadow_system.gd`
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): `.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_quit_on_boot_complete codex_world_seed=12345`
- Артефакты: `debug_exports/perf/runtime_logging_iteration3_boot_seed12345_v2.log`
- Проверенные строки: `299-300` (`stream_load` summary/detail), `515` (`boot_complete reached`), `518` (`boot proof complete; quitting`)
- Ручная проверка пользователем (Manual human verification): не требуется для статически проверенных logging call sites
- Рекомендованная проверка пользователем (Suggested human check): опционально выполнить ручной seam-mining сценарий у загруженной границы чанка и проверить появление `actor=seam_mining_async`, `actor=local_patch`, `actor=roof_restore`, `actor=shadow_refresh`

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): новые logs строятся из уже известных owner facts; нет сканирования всех loaded chunks, persistent mirrors или per-frame summary emission
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): выполнен boot-only proof; dedicated seam-mining route не запускался, потому что spec не требовала agent-run mining proof
- Проверенные метрики / строки: `boot_complete reached`, `boot proof complete`, captured `stream_load` border-fix queue summaries
- `ERROR` / `WARNING`: есть pre-existing `WorldPerf` budget warnings and shutdown `ERROR: 16 resources still in use at exit`; новых `SCRIPT ERROR` / `Compile Error` в proof log не найдено
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): если нужен runtime sample именно для seam/roof/shadow causal chain, выполнить mining у шва чанков и проверить новые actor/detail fields в консоли

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `describe_chunk_scope`, `describe_term_list`, `format_coord_list`, `_emit_border_fix_queue_diag`, `_emit_roof_local_patch_diag`, `_emit_roof_restore_overwrite_diag`, `_emit_shadow_refresh_diag`, `seam_mining_async`, `roof_restore`, `shadow_refresh`, `wrong_state_calculated`, `later_overwrite`: `0 matches`
- Grep DATA_CONTRACTS.md для `local_patch`: `2 matches` (`building_indoor_solver.gd::solve_local_patch`, `IndoorSolver.solve_local_patch`) — unrelated indoor solver references, not this logging actor
- Grep PUBLIC_API.md для `describe_chunk_scope`, `describe_term_list`, `format_coord_list`, `_emit_border_fix_queue_diag`, `_emit_roof_local_patch_diag`, `_emit_roof_restore_overwrite_diag`, `_emit_shadow_refresh_diag`, `seam_mining_async`, `roof_restore`, `shadow_refresh`, `wrong_state_calculated`, `later_overwrite`: `0 matches`
- Grep PUBLIC_API.md для `local_patch`: `1 match` (`IndoorSolver.solve_local_patch(...)`) — unrelated indoor solver reference, not this logging actor
- Секция "Required updates" в спеке: есть — Iteration 3 осталась в preferred transient-log-only path; `DATA_CONTRACTS.md` и `PUBLIC_API.md` не требовались, `PERFORMANCE_CONTRACTS.md` остаётся due after Iteration 4 if policy lands

### Наблюдения вне задачи (Out-of-scope observations)
- Worktree уже содержит много unrelated modified/deleted/untracked files from prior work; они не трогались и не откатывались.
- Boot proof всё ещё показывает pre-existing `WorldPerf` budget warnings и shutdown `ERROR: 16 resources still in use at exit`.
- Runtime proof для конкретного seam-mining / roof / shadow сценария не запускался; Iteration 3 закрыта статической проверкой call sites плюс boot compile/proof.

### Оставшиеся блокеры (Remaining blockers)
- нет для Iteration 3 logging scope

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- не требовалось (not required) — grep по новым helper / actor / cause names дал `0 matches`, кроме unrelated `local_patch` indoor solver references

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) — grep по новым helper / actor / cause names дал `0 matches`, кроме unrelated `local_patch` indoor solver reference

#### Blockers
- none

### Iteration 4 — Noise control / dedupe / severity rules
**Status**: completed
**Started**: 2026-04-10
**Completed**: 2026-04-10

#### Проверки приёмки (Acceptance tests)
- [x] An identical human summary line does not print every frame; it re-emits only when state, impact, target, dominant reason, or cooldown boundary changes — verified by static grep for `_build_summary_dedupe_key()`, `DEFAULT_SUMMARY_COOLDOWN_MS`, `_claim_summary_emission()`, and key fields `actor/action/target/reason/impact/state` in `core/debug/world_runtime_diagnostic_log.gd`
- [x] One blocked route or backlog state does not print root cause and every downstream follower as equal-priority warnings — verified by static grep for `severity`, `SEVERITY_ROOT_CAUSE`, `SEVERITY_FOLLOW_UP`, `SEVERITY_DIAGNOSTIC`, validation severity classification, and follow-up severity in chunk/roof/shadow call sites
- [x] Technical detail and perf logs still preserve queue depth, backlog, timing, and budget values for agent/developer analysis — verified by static grep for `load_queue`, `redraw_backlog`, `queue_*`, `dirty_targets_count`, `affected_count`, `used_ms`, `budget_ms`, `elapsed_ms`, and `over_budget_pct`
- [x] The implementation remains inside logging/observability scope and does not require a broad runtime refactor — verified by bounded diff review; changed paths stayed within iteration allowlist and helper does not scan loaded chunks or add persistent gameplay state
- [x] `PERFORMANCE_CONTRACTS.md` documents canonical log layers, root-cause rules, and anti-spam policy if Iteration 4 lands — verified by grep lines `515`, `520-523`, `525`, and `531-536`

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — `SEVERITY_ROOT_CAUSE`, `SEVERITY_FOLLOW_UP`, `SEVERITY_DIAGNOSTIC`, `SEVERITY_INFORMATIONAL`, `DEFAULT_SUMMARY_COOLDOWN_MS`, `emit_record`, `humanize_severity`, `_claim_summary_emission`, `_build_summary_dedupe_key`, `_dedupe_field`, `_PERF_HUMAN_SUMMARY_COOLDOWN_MS`, `_resolve_validation_severity`, `emit_summary`: `0 matches`
- [x] Grep PUBLIC_API.md for changed names — same set: `0 matches`
- [x] Documentation debt section reviewed — `PERFORMANCE_CONTRACTS.md` updated in Iteration 4; `DATA_CONTRACTS.md`, `PUBLIC_API.md`, and `WORKFLOW.md` not required because no shared read-visible diagnostic snapshot, gameplay safe entrypoint, or closure workflow semantics were added

#### Files touched
- `.claude/agent-memory/active-epic.md` — started Iteration 4 tracking
- `core/debug/world_runtime_diagnostic_log.gd` — added transition-based summary dedupe, cooldown reminders, severity defaults, and `emit_record()` summary/detail gating
- `core/systems/world/world_perf_probe.gd` — routed human-readable perf summaries through dedupe and marked perf timing/budget output as `diagnostic_signal`
- `core/debug/runtime_validation_driver.gd` — routed validation summary/detail pairs through `emit_record()` and classified validation severity
- `core/systems/world/chunk_manager.gd` — routed player-chunk and border-fix diagnostics through `emit_record()` and marked border-fix follow-up severity
- `core/systems/world/mountain_roof_system.gd` — marked roof local-patch root/follow-up severity and routed roof diagnostics through `emit_record()`
- `core/systems/lighting/mountain_shadow_system.gd` — marked shadow-refresh diagnostics as follow-up and routed through `emit_record()`
- `docs/00_governance/PERFORMANCE_CONTRACTS.md` — documented canonical log layers, root-cause/severity rules, and anti-spam policy

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлен переходный dedupe (transition-based dedupe) для человекочитаемой сводки (human summary): ключ строится из `actor + action + target + reason + impact + state`, а повтор печатается только при смене ключа или после cooldown boundary.
- Добавлен уровень важности диагностики (diagnostic severity): `root_cause`, `follow_up`, `diagnostic_signal`, `informational`; perf timing не заявляет root cause только по миллисекундам.
- Summary/detail пары переведены на `emit_record()`, чтобы suppressed summary не оставлял рядом такую же шумную detail-строку; при cooldown reminder detail получает `suppressed_repeats`.
- `PERFORMANCE_CONTRACTS.md` обновлён: canonical log layers, root-cause/severity rules и anti-spam policy теперь закреплены как project policy.

### Корневая причина (Root cause)
- После Iterations 1-3 логи уже стали читаемыми, но одинаковые summary lines могли повторяться при долгой сходимости, а root cause, follow-up work и perf timing ещё не имели единого severity rule. Это могло снова превращать длинный route/backlog лог в шум.

### Изменённые файлы (Files changed)
- `.claude/agent-memory/active-epic.md` — Iteration 4 closure and documentation debt status
- `core/debug/world_runtime_diagnostic_log.gd` — dedupe, severity, `emit_record()`
- `core/systems/world/world_perf_probe.gd` — perf summary dedupe + diagnostic severity
- `core/debug/runtime_validation_driver.gd` — validation `emit_record()` + severity classification
- `core/systems/world/chunk_manager.gd` — border-fix / player-chunk diagnostics use `emit_record()`
- `core/systems/world/mountain_roof_system.gd` — roof diagnostic severity + `emit_record()`
- `core/systems/lighting/mountain_shadow_system.gd` — shadow follow-up severity + `emit_record()`
- `docs/00_governance/PERFORMANCE_CONTRACTS.md` — Iteration 4 logging policy documentation

### Проверки приёмки (Acceptance tests)
- [x] Identical human summary не печатается every frame — прошло (passed); проверено: `rg` показал `_build_summary_dedupe_key()`, `DEFAULT_SUMMARY_COOLDOWN_MS`, `_claim_summary_emission()`, `suppressed_repeats`, и key fields `actor/action/target/reason/impact/state`
- [x] Blocked route/backlog не печатает root cause и downstream followers как equal-priority warnings — прошло (passed); проверено: `rg` показал `SEVERITY_ROOT_CAUSE`, `SEVERITY_FOLLOW_UP`, `SEVERITY_DIAGNOSTIC`, `_resolve_validation_severity()`, и follow-up severity в chunk/roof/shadow call sites
- [x] Technical detail и perf logs сохраняют queue depth/backlog/timing/budget values — прошло (passed); проверено: `rg` по `load_queue`, `redraw_backlog`, `queue_*`, `dirty_targets_count`, `affected_count`, `used_ms`, `budget_ms`, `elapsed_ms`, `over_budget_pct`
- [x] Scope остался logging/observability без broad runtime refactor — прошло (passed); проверено: bounded diff review + `git diff --check`; helper не сканирует loaded chunks и не создаёт persistent gameplay mirror
- [x] `PERFORMANCE_CONTRACTS.md` документирует canonical log layers, root-cause rules и anti-spam policy — прошло (passed); проверено: `rg` lines `515`, `520-523`, `525`, `531-536`

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `git diff --check -- ...` passed; `git diff --check --no-index -- /dev/null core/debug/world_runtime_diagnostic_log.gd` produced no whitespace warnings; `rg` checks listed above
- Parse check: `Godot_v4.6.1-stable_win64_console.exe --headless --path . --check-only --script res://core/debug/world_runtime_diagnostic_log.gd` passed; same command for `res://core/systems/world/world_perf_probe.gd` passed
- Standalone parse limitation: `runtime_validation_driver.gd`, `chunk_manager.gd`, `mountain_roof_system.gd`, and `mountain_shadow_system.gd` still hit existing autoload-only identifiers (`WorldGenerator`, `FrameBudgetDispatcher`, `EventBus`) before the new logging code, so those standalone checks were not usable as pass/fail proof for this iteration
- Ручная проверка пользователем (Manual human verification): не требуется для закрытия статически проверяемой Iteration 4
- Рекомендованная проверка пользователем (Suggested human check): опционально запустить `local_ring` runtime validation route и убедиться, что repeated `[WorldDiag]` / `[CodexValidation]` summary lines collapse into cooldown reminders while detail retains queue/backlog values

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): dedupe state is transient in `WorldRuntimeDiagnosticLog`; message construction uses already-known record/detail fields; no loaded-world scan, no save persistence, no broad synchronous runtime work
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy; Iteration 4 acceptance was verified statically
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): optional log review on a long route/backlog case to confirm cooldown cadence in real console output

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `SEVERITY_ROOT_CAUSE|SEVERITY_FOLLOW_UP|SEVERITY_DIAGNOSTIC|SEVERITY_INFORMATIONAL|DEFAULT_SUMMARY_COOLDOWN_MS|emit_record|humanize_severity|_claim_summary_emission|_build_summary_dedupe_key|_dedupe_field|_PERF_HUMAN_SUMMARY_COOLDOWN_MS|_resolve_validation_severity|emit_summary`: `0 matches`
- Grep PUBLIC_API.md для того же набора имён: `0 matches`
- Секция "Required updates" в спеке: есть — `PERFORMANCE_CONTRACTS.md` required after Iteration 4 if policy lands; выполнено в section `12.8 Human-readable runtime logging policy`

### Наблюдения вне задачи (Out-of-scope observations)
- Worktree остаётся dirty с unrelated modified/deleted/untracked files from prior work; они не откатывались.
- Standalone `--check-only --script` limitations for autoload-dependent scripts are still present and unrelated to the Iteration 4 logging changes.

### Оставшиеся блокеры (Remaining blockers)
- нет для Iteration 4 scope

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- не требовалось (not required) — grep по новым dedupe/severity/helper names дал `0 matches`; shared read-visible diagnostic snapshot or gameplay owner boundary were not introduced

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) — grep по новым dedupe/severity/helper names дал `0 matches`; no new public read API or gameplay safe entrypoint was added

#### Blockers
- none
