# Epic: Frontier Native Runtime Rewrite

**Spec**: docs/04_execution/frontier_native_runtime_execution_plan.md
**Started**: 2026-04-13
**Current iteration**: R1
**Total iterations**: 10

## Documentation debt

- [ ] DATA_CONTRACTS.md — update runtime ownership/readiness/publication semantics when an iteration changes canonical world/runtime contracts
- [ ] PUBLIC_API.md — update safe/read-only readiness and publication semantics when an iteration changes public-facing behavior
- **Deadline**: each iteration if semantics change
- **Status**: pending

## Iterations

### Iteration R0 — Truth alignment and legacy freeze
**Status**: completed
**Started**: 2026-04-13
**Completed**: 2026-04-13
**Started**: 2026-04-13
**Completed**: 2026-04-13

#### Проверки приёмки (Acceptance tests)
- [x] docs consistently call the current runtime legacy — passed (static verification: `docs/README.md`, `docs/02_system_specs/README.md`, and `docs/04_execution/MASTER_ROADMAP.md` now route to the frontier-native stack and label the old first-pass docs as `Legacy rollout`)
- [x] no doc still describes first-pass or publish-later semantics as acceptable player behavior — passed (static verification: `chunk_visual_pipeline_rework_spec.md`, `boot_fast_first_playable_spec.md`, `boot_visual_completion_spec.md`, `streaming_redraw_budget_spec.md`, and `boot_chunk_readiness_spec.md` now begin with `Legacy Status` and explicitly mark those semantics as superseded)

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — no matches for `zero_tolerance_chunk_readiness_spec|frontier_native_runtime_architecture_spec|frontier_native_runtime_execution_plan`; DATA_CONTRACTS.md update not required in R0
- [x] Grep PUBLIC_API.md for changed names — no matches for `zero_tolerance_chunk_readiness_spec|frontier_native_runtime_architecture_spec|frontier_native_runtime_execution_plan`; PUBLIC_API.md update not required in R0
- [x] Documentation debt section reviewed — reviewed; not due this iteration because R0 changed doc routing/deprecation markers only and did not change canonical runtime contract/API semantics

#### Files touched
- `.claude/agent-memory/active-epic.md` — created new active tracker for frontier-native runtime and recorded R0 completion
- `.claude/agent-memory/paused/chunk-system-refactor-service-ownership-cleanup.md` — parked the previous active epic before switching features
- `docs/README.md` — added frontier-native docs to canonical navigation and labeled legacy rollout specs in the index
- `docs/02_system_specs/README.md` — added frontier-native specs and explicit note that first-pass/publish-later specs are legacy rollout records
- `docs/04_execution/MASTER_ROADMAP.md` — linked the active frontier-native runtime stack from the execution roadmap
- `docs/02_system_specs/world/chunk_visual_pipeline_rework_spec.md` — marked as legacy interim rollout and superseded for active target selection
- `docs/02_system_specs/world/boot_fast_first_playable_spec.md` — marked as legacy hybrid-runtime optimization pass
- `docs/02_system_specs/world/boot_visual_completion_spec.md` — marked as legacy boot-visual rollout
- `docs/02_system_specs/world/streaming_redraw_budget_spec.md` — marked as legacy redraw-mitigation rollout
- `docs/02_system_specs/world/boot_chunk_readiness_spec.md` — marked as legacy boot-readiness rollout

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлены canonical navigation-ссылки на `zero_tolerance_chunk_readiness_spec.md`, `frontier_native_runtime_architecture_spec.md` и `frontier_native_runtime_execution_plan.md` в индексах документации.
- Старые world-runtime спеки с `first-pass` / `terrain-first` / `publish-later` семантикой явно помечены как `Legacy Status` и как superseded для active target selection.
- Предыдущий active epic припаркован в `paused`, создан новый `active-epic.md` для frontier-native rewrite.

### Корневая причина (Root cause)
- До R0 индексы и несколько старых runtime-спеков всё ещё можно было прочитать так, будто hybrid/soft-readiness runtime остаётся допустимой целевой архитектурой.

### Изменённые файлы (Files changed)
- `.claude/agent-memory/active-epic.md`
- `.claude/agent-memory/paused/chunk-system-refactor-service-ownership-cleanup.md`
- `docs/README.md`
- `docs/02_system_specs/README.md`
- `docs/04_execution/MASTER_ROADMAP.md`
- `docs/02_system_specs/world/chunk_visual_pipeline_rework_spec.md`
- `docs/02_system_specs/world/boot_fast_first_playable_spec.md`
- `docs/02_system_specs/world/boot_visual_completion_spec.md`
- `docs/02_system_specs/world/streaming_redraw_budget_spec.md`
- `docs/02_system_specs/world/boot_chunk_readiness_spec.md`

### Проверки приёмки (Acceptance tests)
- [x] docs consistently call the current runtime legacy — passed (static verification: doc indexes and roadmap point to frontier-native stack; old specs are labeled `Legacy rollout` / `Legacy Status`)
- [x] no doc still describes first-pass or publish-later semantics as acceptable player behavior — passed (static verification: the affected legacy specs now explicitly mark those semantics as superseded and non-target)

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `git diff --check -- <touched files>` passed; `Select-String` confirmed frontier-native links in indexes and `Legacy Status` blocks in legacy specs.
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): открыть `docs/README.md` и `docs/02_system_specs/README.md`, убедиться, что active runtime target читается как frontier-native stack с первого экрана.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): runtime/code paths не менялись; R0 ограничен truth alignment и deprecation markers.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy; R0 не меняет runtime behavior
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): не требуется

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `zero_tolerance_chunk_readiness_spec|frontier_native_runtime_architecture_spec|frontier_native_runtime_execution_plan`: no matches — R0 не требовал обновления `DATA_CONTRACTS.md`
- Grep PUBLIC_API.md для `zero_tolerance_chunk_readiness_spec|frontier_native_runtime_architecture_spec|frontier_native_runtime_execution_plan`: no matches — R0 не требовал обновления `PUBLIC_API.md`
- Секция "Required updates" в спеке: нет в `frontier_native_runtime_execution_plan.md`; R0 ограничен doc truth alignment и freeze markers

### Наблюдения вне задачи (Out-of-scope observations)
- Старые legacy-спеки по-прежнему содержат исторический rollout detail; R0 только оградил их от ошибочного чтения как active target, но не переписывал их содержание под новую архитектуру.

### Оставшиеся блокеры (Remaining blockers)
- none

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- не требовалось (not required) — grep `zero_tolerance_chunk_readiness_spec|frontier_native_runtime_architecture_spec|frontier_native_runtime_execution_plan` по `docs/02_system_specs/world/DATA_CONTRACTS.md` вернул no matches; R0 не менял canonical layer ownership/invariants

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) — grep `zero_tolerance_chunk_readiness_spec|frontier_native_runtime_architecture_spec|frontier_native_runtime_execution_plan` по `docs/00_governance/PUBLIC_API.md` вернул no matches; R0 не менял public entrypoint semantics

#### Doc check
- [x] Grep DATA_CONTRACTS.md for `flora_placements|Chunk.continue_redraw|surface_native_generation_fails_closed_when_native_generator_unavailable` вЂ” matches updated native-only/fail-closed contract and zero-tolerance publication semantics
- [x] Grep PUBLIC_API.md for `Chunk.needs_full_redraw|ChunkManager.boot_load_initial_chunks(progress_callback: Callable)` вЂ” matches updated non-publication first-pass semantics and fail-closed boot behavior
- [x] Documentation debt section reviewed вЂ” reviewed; `DATA_CONTRACTS.md` and `PUBLIC_API.md` were updated in this iteration because runtime/public semantics changed

#### Files touched
- `.claude/agent-memory/active-epic.md`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk_visual_scheduler.gd`
- `core/systems/world/chunk_boot_pipeline.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

#### Proof summary
- `git diff --check -- <R1 files>` passed
- `Select-String` confirmed presence of `_block_legacy_surface_generation_fallback`, `_block_legacy_visual_batch_fallback`, `_report_zero_tolerance_contract_breach`, `_enforce_player_chunk_full_ready`, `boot_missing_detached_builder`
- `Select-String` confirmed absence of `compute_visual_batch_fallback`, `_run_chunk_redraw_compat`, `_has_full_publication_once`, `visible_before_first_pass`, `using sync fallback`
- Runtime verification was not run in this environment: `godot` / `godot4` executable not found
- Suggested human smoke check: boot the game and cross several surface chunk boundaries to confirm no zero-tolerance breach triggers on the normal path

#### Out-of-scope observations
- `Chunk.build_prebaked_visual_payload()` / generation-time prebaked visual derivation still remain GDScript-owned helper paths for surface payload build; R1 blocked critical player-reachable fallback/publication escape hatches, but native final-packet work and deeper payload hardening remain for later iterations

#### Blockers
- none

---

### Iteration R1 — Delete critical fallback and publish-later permissions
**Status**: completed

#### Проверки приёмки (Acceptance tests)
- [x] all critical fallback paths are either deleted or explicitly blocked from use in player-reachable runtime вЂ” passed (static verification: no matches for `compute_visual_batch_fallback`, `_run_chunk_redraw_compat`, `_has_full_publication_once`, `visible_before_first_pass`, or `using sync fallback`; blocking guards now exist in `chunk_content_builder.gd`, `chunk.gd`, `chunk_visual_scheduler.gd`, `chunk_manager.gd`, and `chunk_boot_pipeline.gd`)
- [x] runtime asserts or fatal diagnostics exist for player occupancy of a non-`full_ready` chunk вЂ” passed (static verification: `ChunkManager._report_zero_tolerance_contract_breach()` plus `_enforce_player_chunk_full_ready()` assert/log the occupancy breach, and `_sync_chunk_visibility_for_publication()` asserts/logs publish-later visibility breach)
- [x] `first_pass_ready` is no longer treated as sufficient for player entry anywhere in the runtime вЂ” passed (static verification: chunk visibility now gates only on `is_full_redraw_ready()`, player-chunk diagnostics flag `visible_before_full_ready`, and the canonical docs/public API now describe `first_pass` as an internal milestone only)

#### Blockers
- none
