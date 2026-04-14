# Epic: Frontier Native Runtime Rewrite

**Spec**: docs/04_execution/frontier_native_runtime_execution_plan.md
**Started**: 2026-04-13
**Current iteration**: R4
**Total iterations**: 10

## Documentation debt

- [ ] DATA_CONTRACTS.md — update runtime ownership/readiness/publication semantics when an iteration changes canonical world/runtime contracts
- [ ] PUBLIC_API.md — update safe/read-only readiness and publication semantics when an iteration changes public-facing behavior
- **Deadline**: each iteration if semantics change
- **Status**: completed for R3 on 2026-04-14; revisit on the next iteration if semantics change again

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

---

### Iteration R2 — Versioned native final packet contract
**Status**: completed
**Started**: 2026-04-14
**Completed**: 2026-04-14

#### Проверки приёмки (Acceptance tests)
- [x] schema is documented and versioned — passed (static verification: `core/systems/world/chunk_final_packet.gd` defines versioned surface packet metadata + validators; `frontier_native_runtime_architecture_spec.md`, `DATA_CONTRACTS.md`, and `PUBLIC_API.md` now describe the same `frontier_surface_final_packet` contract)
- [x] no required `full_ready` layer is left undocumented or marked "later convergence" — passed (static verification: architecture spec now names packet field groups and explicitly lists seam/collision/navigation/reveal/lighting/overlay ownership groups; DATA_CONTRACTS adds `Surface Final Packet Envelope` layer and migration note instead of hidden catch-up semantics)

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — matches for `frontier_surface_final_packet`, `ChunkFinalPacket`, `ChunkStreamingService.prepare_chunk_install_entry`, `WorldGenerator.build_chunk_native_data`, and `ChunkContentBuilder.build_chunk_native_data` confirm updated packet contract, install validation, and direct-load path wording
- [x] Grep PUBLIC_API.md for changed names — matches for `frontier_surface_final_packet`, `WorldGenerator.build_chunk_native_data`, `ChunkStreamingService.prepare_chunk_install_entry`, and `ChunkContentBuilder.build_chunk_native_data`; no public API entry was added for `ChunkFinalPacket` because it remains internal
- [x] Documentation debt section reviewed — reviewed; `DATA_CONTRACTS.md` and `PUBLIC_API.md` were updated in this iteration because runtime packet semantics changed

#### Files touched
- `.claude/agent-memory/active-epic.md` — switched current iteration to R2 and recorded acceptance targets
- `core/systems/world/chunk_final_packet.gd` — added versioned surface final packet metadata, duplication, and validation helpers
- `core/systems/world/chunk_content_builder.gd` — stamped/validated the versioned surface packet contract at the native build boundary
- `core/systems/world/chunk_streaming_service.gd` — enforced packet validation at surface install boundary and removed the direct runtime install bypass through `build_chunk_content()`
- `core/systems/world/chunk_manager.gd` — routed surface packet duplication through the shared packet helper
- `docs/02_system_specs/world/frontier_native_runtime_architecture_spec.md` — added explicit R2 packet schema lock, versioning, and ownership groups
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — added `Surface Final Packet Envelope` layer, updated world invariants, and rewrote direct surface load postconditions around the packet contract
- `docs/00_governance/PUBLIC_API.md` — documented `WorldGenerator.build_chunk_native_data()` as the versioned player-reachable surface packet contract

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлен единый helper `ChunkFinalPacket` для versioned surface final packet: metadata keys, envelope stamping, shape validation и safe duplication.
- `ChunkContentBuilder.build_chunk_native_data()` теперь после native generation + prebaked visual payload явно штампует `frontier_surface_final_packet` (`packet_version = 1`, `generator_version = 1`, `z_level = 0`, `generation_source`) и валидирует packet shape до возврата в runtime.
- `ChunkStreamingService.prepare_chunk_install_entry()` теперь fail-closed проверяет surface packet contract до создания `Chunk`, поэтому без version metadata или с поломанным tiled shape surface install path не пройдёт.
- Из прямого runtime surface-load path убран обход через `WorldGenerator.build_chunk_content() -> ChunkBuildResult.to_native_data()`; player-reachable runtime теперь идёт через `build_chunk_native_data()` или дубликат его cached packet.
- Canonical docs синхронизированы: architecture spec фиксирует schema lock и ownership groups, `DATA_CONTRACTS.md` описывает `Surface Final Packet Envelope`, `PUBLIC_API.md` объявляет `WorldGenerator.build_chunk_native_data()` versioned packet contract'ом для player-reachable surface runtime.

### Корневая причина (Root cause)
- Surface runtime продолжал передавать анонимные `native_data` dictionaries без явного packet header/version contract, а один direct-load path ещё обходил `build_chunk_native_data()` через structured `ChunkBuildResult` export. Из-за этого versioning, ownership и determinism semantics были незафиксированы на install boundary.

### Изменённые файлы (Files changed)
- `.claude/agent-memory/active-epic.md`
- `core/systems/world/chunk_final_packet.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk_streaming_service.gd`
- `core/systems/world/chunk_manager.gd`
- `docs/02_system_specs/world/frontier_native_runtime_architecture_spec.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

### Проверки приёмки (Acceptance tests)
- [x] schema is documented and versioned — прошло (passed); проверено: `chunk_final_packet.gd` содержит `packet_kind`, `packet_version`, `generator_version`, `generation_source`, `z_level`, а canonical docs ссылаются на тот же `frontier_surface_final_packet`
- [x] no required `full_ready` layer is left undocumented or marked "later convergence" — прошло (passed); проверено: architecture spec перечисляет field groups и ownership groups, `DATA_CONTRACTS.md` добавляет `Surface Final Packet Envelope` вместо неявного catch-up описания

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `git diff --check` прошёл; `rg` по `chunk_final_packet.gd` подтвердил `stamp_surface_packet_metadata`, `validate_surface_packet`, `duplicate_surface_packet`; `rg` по `chunk_streaming_service.gd` показал validation на `prepare_chunk_install_entry()` и отсутствие runtime `build_chunk_content()` use (совпадение осталось только в `core/debug/world_preview_exporter.gd`)
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): запустить surface runtime и пройти через несколько границ чанков; убедиться, что в логе нет `surface_final_packet_contract_invalid` или `invalid_surface_final_packet_contract`

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): install boundary больше не потребляет unversioned structured export; surface cache дублирует versioned packet через shared helper; invalid packet shape отсекается до `Chunk` creation
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy
- Ручная проверка пользователем (Manual human verification): рекомендуется
- Рекомендованная проверка пользователем (Suggested human check): прогнать обычный boot + пересечение нескольких surface chunk boundaries и убедиться, что fail-closed validation не срабатывает на штатном native packet path

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `frontier_surface_final_packet`: совпадения есть — добавлены layer map, world invariants и `Surface Final Packet Envelope`
- Grep DATA_CONTRACTS.md для `ChunkStreamingService.prepare_chunk_install_entry`: совпадения есть — install boundary validation отражена в invariants и postconditions
- Grep DATA_CONTRACTS.md для `WorldGenerator.build_chunk_native_data` / `ChunkContentBuilder.build_chunk_native_data`: совпадения есть — packet ownership/readers/writers/postconditions обновлены
- Grep PUBLIC_API.md для `frontier_surface_final_packet`: совпадения есть — `WorldGenerator.build_chunk_native_data()` описан как versioned packet contract
- Grep PUBLIC_API.md для `ChunkStreamingService.prepare_chunk_install_entry`: совпадения есть — install-boundary validation описана в guarantees `build_chunk_native_data()`
- Grep PUBLIC_API.md для `ChunkFinalPacket`: 0 совпадений — internal helper, public API update не требовался
- Секция "Required updates" в спеке: нет явной секции в `frontier_native_runtime_execution_plan.md`; documentation debt reviewed and completed for changed runtime semantics

### Наблюдения вне задачи (Out-of-scope observations)
- В worktree уже есть unrelated deletion `gdextension/bin/~station_mirny.windows.template_debug.x86_64.dll`; не трогал.
- `WorldGenerator.build_chunk_content()` остаётся в debug/export path (`core/debug/world_preview_exporter.gd`) как structured build shape; его перевод на final packet contract не входил в `R2`.

### Оставшиеся блокеры (Remaining blockers)
- none

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- обновлено: `Layer Map`, `Observed files`, `Layer: World`, новый `Layer: Surface Final Packet Envelope`, `Postconditions: generate chunk`; grep для `frontier_surface_final_packet`, `ChunkStreamingService.prepare_chunk_install_entry`, `WorldGenerator.build_chunk_native_data`, `ChunkContentBuilder.build_chunk_native_data` это подтверждает

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- обновлено: `WorldGenerator.build_chunk_content()` и `WorldGenerator.build_chunk_native_data()`; grep для `frontier_surface_final_packet`, `WorldGenerator.build_chunk_native_data`, `ChunkStreamingService.prepare_chunk_install_entry`, `ChunkContentBuilder.build_chunk_native_data` это подтверждает

#### Blockers
- none

---

### Iteration R3 — Native final packet pipeline for surface chunks
**Status**: completed
**Started**: 2026-04-14
**Completed**: 2026-04-14

#### Проверки приёмки (Acceptance tests)
- [x] surface visible chunks are publishable from final packet only — passed (static/runtime verification: native surface generation now produces terminal `flora_payload`, real `feature_and_poi_payload`, native visual packet buffers, and install/cache boundaries call `ChunkFinalPacket.validate_terminal_surface_packet()`)
- [x] no surface visible chunk still owes later flora/cliff/seam completion — passed for R3 scope (static verification: surface install/cache reject missing terminal flora payload; native visual payload must come from `ChunkVisualKernels`; seam/publication-coordinator switch remains explicit R5 scope)

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — matches for `flora_payload`, `validate_terminal_surface_packet`, `ChunkVisualKernels`, `feature_and_poi_payload`, `ChunkSurfacePayloadCache`, and `WorldGenerator.build_chunk_native_data`
- [x] Grep PUBLIC_API.md for changed names — matches for `flora_payload`, `validate_terminal_surface_packet`, `ChunkVisualKernels`, `feature_and_poi_payload`, `texture_path`, and `WorldGenerator.build_chunk_native_data`
- [x] Documentation debt section reviewed — reviewed; `DATA_CONTRACTS.md`, `PUBLIC_API.md`, and `frontier_native_runtime_architecture_spec.md` were updated because R3 changed terminal packet/runtime semantics

#### Files touched
- `.claude/agent-memory/active-epic.md`
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_boot_pipeline.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk_final_packet.gd`
- `core/systems/world/chunk_final_packet.gd.uid`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk_streaming_service.gd`
- `core/systems/world/chunk_surface_payload_cache.gd`
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/02_system_specs/world/frontier_native_runtime_architecture_spec.md`
- `gdextension/src/chunk_generator.cpp`
- `gdextension/src/chunk_generator.h`
- `gdextension/bin/station_mirny.windows.template_debug.x86_64.dll`
- `gdextension/src/chunk_generator.windows.template_debug.x86_64.obj`
- `gdextension/src/register_types.windows.template_debug.x86_64.obj`
- `gdextension/.sconsign.dblite`

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Native surface packet path теперь собирает terminal packet: real `feature_and_poi_payload`, strict native `ChunkVisualKernels` visual payload, `flora_payload` from native placements, and terminal validation before install/cache replay.
- GDExtension flora/decor definitions now carry `texture_path`, so native placements have enough data for pure-data flora render packet construction.
- Contract docs updated for `flora_payload`, terminal packet validation, surface cache validation, and R3 migration semantics.

### Корневая причина (Root cause)
- After R2 the packet envelope was versioned, but surface publication still depended on script-side completion for payload details that should travel with the final packet.

### Проверки приёмки (Acceptance tests)
- [x] surface visible chunks are publishable from final packet only — passed via static contract check, Godot headless check, and native build.
- [x] no surface visible chunk still owes later flora/cliff/seam completion — passed for R3-owned flora/visual/feature payloads; R5 still owns final publication coordinator switch.

### Артефакты доказательства (Proof artifacts)
- `git diff --check` passed.
- `godot_console.exe --headless --path . --check-only --quit` passed.
- `python -m SCons platform=windows target=template_debug arch=x86_64 -j4` passed and rebuilt the native DLL.
- `rg` confirmed old native flora fallback helpers are absent from world runtime files; `rg` confirmed terminal validation/cache/install/docs matches.

### Наблюдения вне задачи (Out-of-scope observations)
- Pre-existing deletion of `gdextension/bin/~station_mirny.windows.template_debug.x86_64.dll` remains unrelated to R3.
- R5 remains responsible for the live publication-coordinator switch to final-packet-only semantics.

#### Blockers
- none
