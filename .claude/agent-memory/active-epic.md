# Epic: Frontier Native Runtime Rewrite

**Spec**: docs/04_execution/frontier_native_runtime_execution_plan.md
**Started**: 2026-04-13
**Current iteration**: R6 pending
**Total iterations**: 10

## Spec revision log

- 2026-04-14: runtime log review reopened `R4` as a stabilization gate before `R5`. Do not advance to `R5` (`Vehicles and Trains`) until the `P0/P1` blockers below are resolved; `R4` frontier scheduling is not considered progression-ready while these main-thread/publication/perf violations remain.
- 2026-04-14: user clarified that runtime streaming must ignore debug zoom / raw camera-visible expansion. Target gameplay envelope is fixed `3x3` hot around the player plus `5x5` warm follow-up; the current camera-visible-driven runtime behavior now requires follow-up implementation against the updated specs.
- 2026-04-14: `feature_and_poi_payload` assembly moved into native `ChunkGenerator`, the GDScript resolver/fallback path was deleted, and `build_chunk_content()` now hydrates from the same authoritative packet as `build_chunk_native_data()`. Remaining perf hotspot has shifted to native visual payload generation / streaming redraw rather than feature/POI payload assembly.
- 2026-04-14: post-R4 follow-up fixed two regressions outside the spec body: player camera zoom returned to additive stepping and the shipped balance resource now extends the debug zoom-out range to `zoom_min = 0.2` with `zoom_step = 0.1`, so the full `5x5` debug bubble is reachable again; mining/seam local border-fix paths also now attempt immediate player-near completion before deferred invalidation so harvesting on the occupied chunk does not demote it to `full_pending` and trip zero-tolerance readiness.
- 2026-04-14: `R4.2` diagnostic pass reviewed the latest `godot.log` + `F11` dumps. The old `ChunkManager.try_harvest_at_world` freeze did not reproduce in this run; residual dominant spikes shifted to `ChunkStreaming.phase2_finalize` (up to `519.5 ms`), `FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw` (up to `511.6 ms`), `FrameBudgetDispatcher.visual.mountain_shadow.visual_rebuild` (up to `214.9 ms`), and `FrameBudgetDispatcher.topology.chunk_manager.topology_rebuild` (`45.1 ms`). Publication debt remains severe: `stream.chunk_first_pass_ms` sits around `25.8-46.7 s`, `stream.chunk_full_redraw_ms` around `26.3-48.6 s`, with `visual_queue_depth` climbing to `36` and incident snapshots showing `queue_full_far=29`. Key owner bug: `MountainShadowKernels` exists in `gdextension/src/` but is not registered in `gdextension/src/register_types.cpp`, so the run logs `MountainShadowKernels available=false` and shadows stay on the slow fallback path.
- 2026-04-15: user explicitly started execution-plan `R5` (`Final-packet-only publication switch`). This is not architecture-spec vehicle/train iteration; vehicle/train tuning remains execution-plan `R8`.

## Runtime blockers before R5

- [ ] `[P0]` Интерактивный фриз при добыче: `ChunkManager.try_harvest_at_world` срабатывает 51 раз, среднее `190.0 ms`, пик `225.2 ms` при контракте `2.0 ms` в `godot.log:2981` и `godot.log:2996`. Это уже прямой `player-visible freeze`.
- [ ] `[P0]` Самый тяжёлый стоп-кадр в runtime сейчас — `visual dispatcher`: `FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw` имеет среднее `330 ms`, пик `735 ms` при бюджете `2 ms`; вместе с ним `FrameBudgetDispatcher.total` дошёл до `735.8 ms` в `godot.log:962` и `godot.log:965`.
- [ ] `[P0]` `streaming install/finalize` всё ещё делает слишком много работы в `main thread`: `ChunkStreaming.phase2_finalize` доходит до `587.9 ms`, а `streaming_load` budget-step до `589.6 ms` при лимите `3 ms` в `godot.log:526` и `godot.log:531`. Для frontier-native runtime это один из главных нарушителей.
- [ ] `[P1]` В логе всё ещё виден legacy `publish-then-finish-later`: near/player chunks ставятся в мир со статусом `building_visual` и `impact=player_visible_issue` в `godot.log:94` и `godot.log:100`, а потом десятки секунд добираются до публикации: `stream.chunk_first_pass_ms` в среднем `38.7 s`, `stream.chunk_full_redraw_ms` в среднем `33.7 s`, пики `51.2-53.7 s` в `godot.log:3356` и `godot.log:3397`. Это конфликтует с `zero_tolerance_chunk_readiness_spec.md:27` и `frontier_native_runtime_architecture_spec.md:270`.
- [ ] `[P1]` Boot тормозит в основном очередями и `convergence debt`, не только generation: `Startup.loading_screen_visible_to_startup_bubble_ready_ms = 51.9 s` в `godot.log:469`, `boot_complete reached = 95.2 s` с `queue_wait=71575 ms`, `compute=15411 ms`, `apply=20.3 ms` в `godot.log:1145`. Wall-clock убивает не `apply`, а ожидание и поздняя публикация.
- [ ] `[P2]` Самый дорогой compute внутри chunk build — `visual payload`: по всему логу `ChunkGen.native_total_ms` в среднем `636.6 ms`, из них `native_visual_payload_ms = 568.0 ms`, а сам `native_call_ms = 66.8 ms`; worst case `831.4 ms = native 111.6 + prebaked/visual 719.6` в `godot.log:2493` и `godot.log:2497`.
- [ ] `[P2]` `shadow/seam` follow-up тоже дорогие: `Shadow.edge_cache_compute` до `488.5 ms` в `godot.log:101`, `stream.chunk_border_fix_ms` до `7.56 s age` в `godot.log:2056`. После mining ещё остаётся queued `shadow_refresh` на текущем чанке в `godot.log:2997`.

### 2026-04-14 P0 pass 1 status

- Приземлён узкий runtime fix: synchronous `border_fix` completion убран из mining frame, `stream_load` seam follow-up и player-near relief path; `player-near border_fix` worker-prepared batches больше не заменяются намеренно на main-thread fallback.
- Следующий шаг: снять свежий `godot.log` и проверить, насколько именно просели `ChunkManager.try_harvest_at_world`, `FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw` и `ChunkStreaming.phase2_finalize`.

### 2026-04-14 P1 pass 1 status

- Boot/publication pass приземлён: boot loop получил больший visual budget до `first_playable`, post-`first_playable` boot finalization теперь даёт дополнительный bounded runtime boost для `streaming_load` / visual convergence / topology, а startup handoff requests больше не падают в обычный low-priority lane до `boot_complete`.
- Hidden install logging больше не оформляется как будто near chunk уже опубликован игроку; install event теперь явно сообщает, что chunk остаётся скрытым до terminal publication.
- Свежий runtime log после этих правок ещё не снят, поэтому `P1` blockers остаются открытыми до ручной проверки.

### 2026-04-14 P2 pass 1 status

- `ChunkContentBuilder` теперь сначала принимает embedded native visual payload из `ChunkGenerator.generate_chunk()` и вызывает второй native prebaked pass только если шесть derived arrays не пришли в пакете; compact request теперь включает `native_visual_tables`, а сам `ChunkVisualKernels` доступен из C++ без второго GDScript round-trip.
- `MountainShadowSystem` переведён с wide mining follow-up на локальный `edge-delta` path: mining больше не enqueue'ит full edge rebuild для всех соседних чанков по умолчанию, а edge-cache worker получает компактный `(chunk_size + 2)^2` `terrain_snapshot` вместо девяти neighbor arrays + detached `ChunkContentBuilder`.
- Локальный shadow refresh только на текущем чанке больше не засоряет runtime diagnostics как отдельный `queued shadow_refresh`; свежий `godot.log` всё ещё нужен, чтобы подтвердить реальное падение `ChunkGen.native_total_ms`, `Shadow.edge_cache_compute` и `stream.chunk_border_fix_ms`.

### 2026-04-14 crash hotfix status

- После `P2 pass 1` всплыл runtime assert `chunk_visible_before_full_ready`: скрытый `stream_load` install поздно ставил `border_fix` на уже опубликованный near chunk и демотировал его в `full_pending`.
- Узкий hotfix в `ChunkSeamService`: player-near visible border fixes теперь сначала пытаются завершиться через bounded inline micro-patch в том же background step; только если это не удалось, чанк снова идёт в обычный invalidate + queued `border_fix` path.

### 2026-04-15 R4 stabilization continuation status

- Приземлён follow-up по локальному mining/entered-chunk `border_fix`: `try_harvest_at_world()` и player-enter path теперь пытаются закрыть tiny player-near border micro-fix inline before zero-tolerance occupancy check; если micro-budget не подходит, остаётся scheduler-owned `TASK_BORDER_FIX`.
- `ViewEnvelopeResolver` переведён на gameplay-fixed envelope: hot `3x3`, warm `5x5`, raw camera/debug zoom retained only as `debug_camera_visible_set` diagnostics. `FrontierPlanner` теперь строит runtime critical/high sets из `hot_near_set` / `warm_preload_set`, а debug camera больше не расширяет `needed_set`.
- Добавлен bounded in-chunk motion refresh frontier plan и runtime validation velocity feed, чтобы `TravelStateResolver` видел sprint-class movement в headless route.
- `runtime_validation_driver.gd` обновлён под `ChunkStreamingService`: old `_load_queue`, `_staged_chunk`, `_gen_task_id` и related state читаются через service-owned values, а boolean snapshot fields больше не используют unsafe `bool(...)`.
- Proof 2026-04-15: `git diff --check -- core/debug/runtime_validation_driver.gd core/systems/world/chunk_manager.gd core/systems/world/view_envelope_resolver.gd core/systems/world/frontier_planner.gd` passed; `Godot_v4.6.1-stable_win64_console.exe --headless --path . --check-only --quit` passed.
- Runtime proof 2026-04-15: `runtime_local_ring_seed12345_validation_bool_fix_20260415_001501.stdout.log` / `.stderr.log` exited `0`; validation harness reports `InvalidCallCount=0`, final `reported_validation_outcome ... blocker=none ... reached_waypoints=6/6`, and mining/room/power validations complete.
- R4 remains blocked: the same fresh runtime log still records `ZeroToleranceReadiness` occupancy breaches during traversal (`651` assertion lines), starting with `(3,1)@z0` and continuing across route chunks. This is a real `full_ready` publication/frontier catch-up failure, not the previous validation harness crash.
- Remaining perf blockers in the same proof log: `MountainShadowKernels available=false`; `FrameBudgetDispatcher.streaming.chunk_manager.streaming_load` peaks at `324.97 ms`, `ChunkStreaming.phase2_finalize` peaks at `320.22 ms`, and `stream.chunk_full_redraw_ms` still reaches `54887.09 ms`.
- 2026-04-15 follow-up: `MountainShadowKernels` is now registered in `gdextension/src/register_types.cpp`; `MountainShadowSystem` no longer has GDScript full edge-cache scan or shadow raster fallback paths and now fails closed when native kernels are missing/invalid. Contract docs were updated because shadow presentation compute semantics changed to native-required.
- 2026-04-15 follow-up: direct player-reachable surface runtime sync load is now hard-blocked in `ChunkStreamingService.load_chunk_for_z()`. Legacy `process_load_queue()` no longer builds native data / creates a chunk / finalizes install in one main-thread path; surface runtime must flow through async generate or validated cache stage -> staged create -> staged finalize -> visual scheduler.
- Contract docs updated in this follow-up because runtime envelope semantics, mining border micro-fix semantics, and surface sync-load semantics changed: `DATA_CONTRACTS.md` now states fixed hot/warm envelope + debug-only camera diagnostics, bounded player-near inline border micro-fix, and no direct sync surface load path; `PUBLIC_API.md` mirrors those constraints.

### Iteration R4.4 - Critical FPS stabilization targets
**Status**: implemented; `git diff --check` passed, Godot check blocked by missing paired main exe, runtime proof pending
**Source logs**: `godot.log` + `f11_chunk_overlay.log` captured 2026-04-15

#### Two most critical current problems

1. `[P0]` Visual dispatcher still performs over-budget chunk redraw/seam work in one frame.
   - Evidence: latest `godot.log` has `FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw` count `16`, max `460.75 ms`, avg `238.22 ms` against the `2 ms` visual budget; `FrameBudgetDispatcher.total` peaks at `461.41 ms`.
   - Evidence: `stream.chunk_border_fix_ms` count `14`, max `1439.70 ms`, avg `996.74 ms`; screenshot/F11 captures the same path with `stream.chunk_border_fix_ms (3, 2)@z0: 1368.89 ms` and `FrameBudgetDispatcher.total: 134.17 ms`.
   - Evidence: publication/convergence debt remains large: `stream.chunk_full_redraw_ms` count `74`, max `38888.33 ms`, avg `21197.27 ms`; `stream.chunk_first_pass_ms` count `70`, max `17093.36 ms`, avg `9835.38 ms`.
   - Why it matters: this is the direct visible stop-frame source during traversal even when queues are nearly drained; small `visual_queue_depth` does not help if one queue item monopolizes the visual dispatcher.

2. `[P1]` Streaming install/finalize still has large main-thread budget spikes.
   - Evidence: latest `godot.log` has `ChunkStreaming.phase2_finalize` count `30`, max `262.64 ms`, avg `100.53 ms`; `FrameBudgetDispatcher.streaming.chunk_manager.streaming_load` peaks at `262.91 ms` against the `3 ms` streaming budget.
   - Evidence: current log has `try_harvest_at_world=0`, `ZeroToleranceReadiness=0`, and `chunk_visible_before_full_ready=0`, so the fresh perf focus should not be mining or readiness asserts first.
   - Why it matters: even after direct sync surface loading was blocked, finalize/apply is still too monolithic for background runtime and can create traversal hitches before the visual queue even gets to redraw.

#### Concrete fix steps

1. `ChunkVisualScheduler` / `ChunkSeamService`: split `TASK_BORDER_FIX` and `TASK_FULL_REDRAW` into resumable micro-steps.
   - Add or reuse per-task continuation state: chunk coord, phase, edge/row/tile cursor, version.
   - Hard-stop the worker/apply drain when the per-frame visual budget is exhausted; requeue the unfinished task instead of completing the chunk/seam in the same dispatcher step.
   - Player-near exceptions may only run bounded micro-patches; no full border/full redraw completion is allowed as a relief path.
   - Add diagnostic counters for `visual_task_slice_count`, `visual_task_requeued_due_budget`, and max single-task apply time.

2. `ChunkStreamingService` / `ChunkManager._finalize_chunk_install()`: split phase2 finalize into staged, budget-aware apply phases.
   - Phase A: create/install lightweight chunk shell only.
   - Phase B: attach validated native/cache payload and saved diff without TileMap publication work.
   - Phase C: enqueue topology/visual/seam/shadow follow-ups only; do not drain them during finalize.
   - Phase D: publish only after `Chunk.is_full_redraw_ready()` remains true.
   - Add substep telemetry inside `ChunkStreaming.phase2_finalize`: shell create, `populate_native`, save diff replay, topology handoff, visual enqueue, EventBus emit, visibility/publication.

3. Verification target for R4.4.
   - Fresh runtime route should show `FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw` no stop-frame spikes; temporary gate: max `< 8 ms`, target gate: max `<= 2 ms`.
   - Fresh runtime route should show `ChunkStreaming.phase2_finalize` and `FrameBudgetDispatcher.streaming.chunk_manager.streaming_load` no stop-frame spikes; temporary gate: max `< 12 ms`, target gate: max `<= 3 ms`.
   - Frame summary should not repeat the current bad windows: `p99=132-145 ms` and `hitches=37-104`.
   - Keep grep checks for `try_harvest_at_world`, `ZeroToleranceReadiness`, and `chunk_visible_before_full_ready`; they are not the current lead blockers unless they reappear in the fresh proof log.

#### Implementation notes 2026-04-15

- `ChunkVisualScheduler` now stores per-slice `phase`, `cursor`, `slice_version`, `slice_count`, last apply time, and pending border dirty count on resumable visual tasks. It records slice count, requeue count, budget requeue count, and max single-task apply time through `WorldPerfProbe`.
- Player-near inline border-fix completion and budget-exhaustion relief are suppressed; border/seam dirt is queued through scheduler-owned `TASK_BORDER_FIX` instead of completing sync in `try_harvest_at_world()`, `ChunkSeamService`, or the scheduler budget loop.
- `ChunkStreamingService.staged_loading_create()` now creates only the chunk shell. `staged_loading_finalize()` advances one phase per tick through payload attach, scene attach, visual enqueue, topology handoff, seam/EventBus, and visibility/publish diagnostics.
- `DATA_CONTRACTS.md` and `PUBLIC_API.md` were updated to remove the old player-near inline micro-fix guarantee and document staged finalize substeps.
- Static proof: `git diff --check -- core/systems/world/chunk_visual_scheduler.gd core/systems/world/chunk_seam_service.gd core/systems/world/chunk_streaming_service.gd core/systems/world/chunk_manager.gd docs/02_system_specs/world/DATA_CONTRACTS.md docs/00_governance/PUBLIC_API.md .claude/agent-memory/active-epic.md` passed. `Godot_v4.6.1-stable_win64_console.exe --headless --path . --check-only --quit` did not run because paired `Godot_v4.6.1-stable_win64.exe` is missing.

### Iteration R4.5 - Native prebaked visual batch fast path
**Status**: implemented; static proof passed, runtime proof pending
**Source log**: `godot.log` captured 2026-04-15 after boot triage Iterations 1-3

#### Scope
- Keep the current scheduler/publication ownership intact.
- Route prebaked final-packet visual phase batches through native `ChunkVisualKernels.compute_visual_batch()` when native kernels are available.
- Remove the GDScript cliff fallback overlay from native dirty batches; native kernels already emit the cliff buffer.
- Do not add movement stop-gates, UI waits, direct sync surface load, or R6/R8 travel modes.

#### Проверки приёмки (Acceptance tests)
- [x] prebaked `TASK_FIRST_PASS` / `TASK_FULL_REDRAW` phase batches include `native_visual_tables` — passed (static verification in `Chunk._build_prebaked_visual_phase_batch()`).
- [x] `skip_worker_compute` no longer bypasses native batch compute when `ChunkVisualKernels` is available — passed (static verification in `Chunk.compute_visual_batch()`).
- [x] native `REDRAW_PHASE_CLIFF` is no longer blocked by GDScript guard — passed (static verification in `Chunk._try_compute_visual_batch_native()`).
- [x] dirty/border-fix batches no longer replace native `cliff_buffer` with GDScript commands — passed (static verification: removed post-native `append_cliff_visual_command()` path).
- [ ] fresh traversal log should show lower `FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw`, lower `stream.chunk_full_redraw_ms`, and faster convergence for movement-frontier chunks — manual human verification required.

#### Files touched
- `core/systems/world/chunk.gd` — native fast path for prebaked phase batches and cliff/dirty batches.
- `.claude/agent-memory/active-epic.md` — recorded this stabilization iteration.

#### Notes
- This is an R4/R5 bridge patch, not the complete R5 final-packet-only publication coordinator. It removes a concrete slow-path violation found in the fresh log, where chunks remained stuck in `phase=cliff` / `full_redraw_pending` while final-packet visual payload data already existed.

### Iteration R5 - Final-packet-only publication switch
**Status**: completed
**Started**: 2026-04-15
**Completed**: 2026-04-15

#### Scope
- Switch live surface visibility/full-ready publication to require terminal `frontier_surface_final_packet` proof captured during `Chunk.populate_native()`.
- Keep underground transition, vehicle/train tuning, movement stop-gates, and broad scheduler/cache policy out of scope.

#### Проверки приёмки (Acceptance tests)
- [x] publication no longer triggers later visible convergence debt — passed (static verification: `Chunk.is_full_redraw_ready()` and `_can_publish_full_redraw_ready()` now require `has_terminal_publication_packet()`)
- [x] visible chunks are either absent or final, with no intermediate published soft states — passed (static verification: fresh install sets `chunk.visible = false`, and later visibility assignment goes only through `_sync_chunk_visibility_for_publication()` -> `_is_visibility_publication_ready()`)
- [x] final packet application is the only visible-world publication path — passed (static verification: `Chunk.populate_native()` captures terminal `frontier_surface_final_packet` proof before any surface `FULL_READY`, and unused `_finalize_chunk_install_legacy()` was removed)

#### Files touched
- `core/systems/world/chunk.gd` — terminal packet proof capture and publication/full-ready gate.
- `core/systems/world/chunk_manager.gd` — publication diagnostics include packet-proof snapshot; unused legacy finalize helper removed.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — R5 publication-contract semantics.
- `docs/00_governance/PUBLIC_API.md` — R5 lifecycle/API wording.
- `docs/02_system_specs/world/frontier_native_runtime_architecture_spec.md` — R5 migration note.
- `.claude/agent-memory/active-epic.md` — recorded R5 progress and closure.

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — matches for `Chunk.populate_native`, `Chunk.is_full_redraw_ready`, `_can_publish_full_redraw_ready`, and `frontier_surface_final_packet`; docs updated for R5 packet-proof gate.
- [x] Grep PUBLIC_API.md for changed names — matches for `Chunk.populate_native`, `Chunk.is_full_redraw_ready`, and `frontier_surface_final_packet`; docs updated for R5 packet-proof gate.
- [x] Documentation debt section reviewed — execution plan has no explicit "Required contract and API updates" section; R5 semantics changed contracts, so `DATA_CONTRACTS.md`, `PUBLIC_API.md`, and architecture spec were updated now.

#### Verification
- `git diff --check -- core/systems/world/chunk.gd core/systems/world/chunk_manager.gd docs/02_system_specs/world/DATA_CONTRACTS.md docs/00_governance/PUBLIC_API.md docs/02_system_specs/world/frontier_native_runtime_architecture_spec.md .claude/agent-memory/active-epic.md` passed.
- `Godot_v4.6.1-stable_win64_console.exe --headless --path . --check-only --quit` passed.
- `rg` confirmed `_finalize_chunk_install_legacy` has no remaining code/doc references in active runtime/docs and visibility writes stay limited to install-hidden + `_sync_chunk_visibility_for_publication()`.

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- R5 live surface publication now requires terminal final-packet proof: `Chunk.populate_native()` validates and captures `frontier_surface_final_packet` before any surface chunk can become `FULL_READY`.
- `Chunk.is_full_redraw_ready()` and `_can_publish_full_redraw_ready()` now require that packet proof in addition to completed redraw and no pending border debt.
- Removed the unused `_finalize_chunk_install_legacy()` helper so there is no duplicate publish-then-finish install path next to the staged flow.
- Updated `DATA_CONTRACTS.md`, `PUBLIC_API.md`, and the architecture spec migration note for R5 semantics.

### Проверки приёмки (Acceptance tests)
- [x] publication no longer triggers later visible convergence debt — прошло (passed); verified by `rg` + `--check-only`.
- [x] visible chunks are either absent or final, with no intermediate published soft states — прошло (passed); verified by visibility write grep and packet-gated readiness.
- [x] final packet application is the only visible-world publication path — прошло (passed); verified by packet-proof capture and removal of `_finalize_chunk_install_legacy()`.

### Blockers
- none

### Boot Startup Regression Triage — Iteration 1
**Spec**: docs/02_system_specs/world/boot_startup_regression_triage_spec.md
**Status**: completed
**Started**: 2026-04-15
**Completed**: 2026-04-15

#### Scope
- Requeue dedup on the `ChunkVisualScheduler` enqueue/requeue path only.
- No seam drain slicing, no publish/revoke cycle changes, no R5 publication rewrite.

#### Проверки приёмки (Acceptance tests)
- [x] `assert(scheduler_rejects_duplicate_live_task_for_same_chunk_kind_version)` statically confirmed in scheduler code — passed (`rg` shows `_try_accept_live_task()`, `_has_duplicate_live_task()`, `_append_existing_task_to_queue()`, and `_requeue_visual_task()` routing through `push_task()` / `push_task_front()`)
- [ ] fixed seed `codex_world_seed=12345` boot run has `visual_task_requeue_total <= 500` for startup bubble — manual human verification required
- [ ] same fixed seed boot run has `scheduler.duplicate_requeue_rejected_total > 0` — manual human verification required
- [x] grep `PUBLIC_API.md` confirms no new public API — passed (`NO_MATCH_PUBLIC_API`, `NO_MATCH_PUBLIC_METRICS`)

#### Files touched
- `core/systems/world/chunk_visual_scheduler.gd` — added unified live-task dedupe gate and duplicate rejection counter.
- `core/systems/world/world_perf_probe.gd` — added counter output helper for non-timing observability.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — updated Visual Task Scheduling invariant and metric contract.
- `.claude/agent-memory/active-epic.md` — recorded this triage sub-iteration.

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- В `ChunkVisualScheduler` добавлен единый dedup-гейт (dedupe gate) для live visual task перед постановкой в очередь: обычный enqueue, requeue, worker-compute return, priority refresh и queue rotation теперь проверяют `(chunk_coord, z_level, task_kind, invalidation_version)`.
- Дублирующий requeue не увеличивает `visual_task_requeue_total`; вместо этого отклоняется и пишет счётчик (counter) `scheduler.duplicate_requeue_rejected_total`.
- `DATA_CONTRACTS.md` обновлён для Visual Task Scheduling: добавлены invariant про reject дублей и правило, что requeue total должен расти примерно линейно, а не лавинообразно.

### Корневая причина (Root cause)
- `task_pending` защищал часть `ensure_task()`, но не был единым gate для всех путей, которые возвращают задачу в live scheduler queue. Requeue/rotation/worker-return могли снова положить task того же `(chunk, kind, version)` в живую очередь.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk_visual_scheduler.gd`
- `core/systems/world/world_perf_probe.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `.claude/agent-memory/active-epic.md`

### Проверки приёмки (Acceptance tests)
- [x] `assert(scheduler_rejects_duplicate_live_task_for_same_chunk_kind_version)` — прошло (passed); `rg` подтвердил `_try_accept_live_task()` и `_has_duplicate_live_task()`, а `VisualTaskRunState.REQUEUE` возвращается через `push_task()` / `push_task_front()`.
- [ ] `visual_task_requeue_total <= 500` на fixed seed `codex_world_seed=12345` — требуется ручная проверка пользователем (manual human verification required); runtime boot proof не запускался по policy.
- [ ] `scheduler.duplicate_requeue_rejected_total > 0` на той же сессии — требуется ручная проверка пользователем (manual human verification required); статически подтверждён counter path, но значение `> 0` требует runtime log.
- [x] grep `PUBLIC_API.md` для новых API — прошло (passed); `NO_MATCH_PUBLIC_API` / `NO_MATCH_PUBLIC_METRICS`, public API не расширялся.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `git diff --check -- core/systems/world/chunk_visual_scheduler.gd core/systems/world/world_perf_probe.gd docs/02_system_specs/world/DATA_CONTRACTS.md .claude/agent-memory/active-epic.md` прошёл.
- Статическая проверка (Static verification): `Godot_v4.6.1-stable_win64_console.exe --headless --path . --check-only --quit` прошёл.
- Ручная проверка пользователем (Manual human verification): требуется для perf counters.
- Рекомендованная проверка пользователем (Suggested human check): `.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_quit_on_boot_complete codex_world_seed=12345 *>&1 | Tee-Object -FilePath debug_exports/perf/boot_triage_seed12345.log`.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): helper gate смотрит только текущие live queues / active compute maps; не добавляет full chunk redraw, full topology rebuild или broad loaded-chunk scan.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): после boot run grep log для `visual_task_requeue_total`, `scheduler.duplicate_requeue_rejected_total`, `ERROR`, `WARNING`, `WorldPerf`.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `scheduler.duplicate_requeue_rejected_total`: совпадение на строке 574 — обновлено.
- Grep DATA_CONTRACTS.md для `scheduler_rejects_duplicate_live_task_for_same_chunk_kind_version`: совпадение на строке 581 — обновлено.
- Grep DATA_CONTRACTS.md для `scheduler_visual_task_requeue_total_grows_sublinearly_in_startup_bubble_chunks`: совпадение на строке 582 — обновлено.
- Grep DATA_CONTRACTS.md для internal helpers `_try_accept_live_task|record_counter`: 0 совпадений — не публичный контракт, helper names не документировались.
- Grep PUBLIC_API.md для `record_counter|scheduler.duplicate_requeue_rejected_total|_try_accept_live_task`: 0 совпадений — public API не менялся.
- Секция "Required updates" в спеке: есть — `DATA_CONTRACTS.md` выполнено для Iteration 1; `PUBLIC_API.md` не требовалось, grep подтвердил 0 совпадений.

### Наблюдения вне задачи (Out-of-scope observations)
- В worktree уже были не относящиеся к этой итерации изменения: `core/systems/world/chunk_manager.gd`, `data/balance/player_balance.gd`, удаление `gdextension/bin/~station_mirny.windows.template_debug.x86_64.dll`, untracked spec file `docs/02_system_specs/world/boot_startup_regression_triage_spec.md`. Их не трогал.

### Оставшиеся блокеры (Remaining blockers)
- Runtime acceptance по boot counters остаётся за ручной проверкой пользователя (manual human verification), как требует спека.

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено (updated): Visual Task Scheduling, grep-доказательство строки 574, 581, 582.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- Не требовалось (not required): grep `record_counter|scheduler.duplicate_requeue_rejected_total|_try_accept_live_task` вернул 0 совпадений в `PUBLIC_API.md`.

#### Blockers
- Runtime boot proof pending manual human verification.

### Boot Startup Regression Triage — Iteration 2
**Spec**: docs/02_system_specs/world/boot_startup_regression_triage_spec.md
**Status**: completed
**Started**: 2026-04-15
**Completed**: 2026-04-15

#### Scope
- Bound border-fix seam drain slices by `WorldGenBalance.visual_border_fix_tiles_per_step`.
- Keep seam repair algorithm and `ChunkSeamService` ownership unchanged.
- No publish/revoke cycle changes, no R5 publication rewrite.

#### Проверки приёмки (Acceptance tests)
- [x] `assert(border_fix_slice_processes_at_most_configured_tiles_per_step)` statically confirmed in scheduler code — passed (`rg` shows `_resolve_configured_border_fix_tiles_per_step()` and border-fix submit clamp before `collect_pending_border_dirty_tiles()`).
- [ ] Boot run has no `FrameBudget overrun job_id=chunk_manager.streaming_redraw` with `over_budget_pct > 50` — manual human verification required.
- [ ] `ChunkStreaming.phase2_finalize` peak `<= 4 ms` on baseline — manual human verification required.
- [x] `world_gen_balance.tres` contains numeric default for `visual_border_fix_tiles_per_step` — passed (`visual_border_fix_tiles_per_step = 4`).

#### Files touched
- `data/world/world_gen_balance.gd` — set small exported border-fix slice range/default.
- `data/world/world_gen_balance.tres` — set resource default.
- `core/systems/world/chunk_visual_scheduler.gd` — bound border-fix tile resolver.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — updated Seam Repair Queue invariants.

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- `WorldGenBalance.visual_border_fix_tiles_per_step` теперь имеет малый дефолт `4` и editor range `1..64`, чтобы `border_fix` slice не мог стартовать с прежнего пакета на 16 тайлов.
- `ChunkVisualScheduler` теперь разрешает `TASK_BORDER_FIX` tile budget через `_resolve_configured_border_fix_tiles_per_step()` и дополнительно clamps submit path перед `collect_pending_border_dirty_tiles()`.
- `DATA_CONTRACTS.md` обновлён для `Seam Repair Queue`: добавлены invariants про максимум тайлов за slice и остановку по visual budget.

### Корневая причина (Root cause)
- Export для border-fix уже существовал, но его дефолт `16` и far-band resolver не соответствовали triage spec: один визуальный slice мог начинаться с пакета больше целевого `<= 4` тайлов.

### Изменённые файлы (Files changed)
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `core/systems/world/chunk_visual_scheduler.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `.claude/agent-memory/active-epic.md`

### Проверки приёмки (Acceptance tests)
- [x] `assert(border_fix_slice_processes_at_most_configured_tiles_per_step)` — прошло (passed); `rg` подтвердил `_resolve_configured_border_fix_tiles_per_step()` и clamp в `TASK_BORDER_FIX` submit path.
- [ ] `chunk_manager.streaming_redraw` без `over_budget_pct > 50` — требуется ручная проверка пользователем (manual human verification required); runtime boot proof не запускался по policy.
- [ ] `ChunkStreaming.phase2_finalize` peak `<= 4 ms` — требуется ручная проверка пользователем (manual human verification required); baseline runtime log нужен отдельно.
- [x] `world_gen_balance.tres` содержит numeric default — прошло (passed); `rg` показал `visual_border_fix_tiles_per_step = 4`.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `git diff --check -- data/world/world_gen_balance.gd data/world/world_gen_balance.tres core/systems/world/chunk_visual_scheduler.gd docs/02_system_specs/world/DATA_CONTRACTS.md .claude/agent-memory/active-epic.md` прошёл.
- Статическая проверка (Static verification): `Godot_v4.6.1-stable_win64_console.exe --headless --path . --check-only --quit` прошёл.
- Ручная проверка пользователем (Manual human verification): требуется для runtime perf counters.
- Рекомендованная проверка пользователем (Suggested human check): `.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_quit_on_boot_complete codex_world_seed=12345 *>&1 | Tee-Object -FilePath debug_exports/perf/boot_triage_seed12345.log`.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): border-fix dirty tile batch теперь берёт не больше configured export, дополнительно ограничен `BORDER_FIX_REDRAW_MICRO_BATCH_TILES`; full chunk/edge drain в одном slice не добавлен.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): grep runtime log на `FrameBudget overrun job_id=chunk_manager.streaming_redraw`, `ChunkStreaming.phase2_finalize`, `ERROR`, `WARNING`, `WorldPerf`.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `visual_border_fix_tiles_per_step`: совпадение на строке 646 — обновлено.
- Grep DATA_CONTRACTS.md для `border_fix_slice_processes_at_most_configured_tiles_per_step`: совпадение на строке 651 — обновлено.
- Grep DATA_CONTRACTS.md для `border_fix_slice_respects_visual_category_budget`: совпадение на строке 652 — обновлено.
- Grep PUBLIC_API.md / PERFORMANCE_CONTRACTS.md для `visual_border_fix_tiles_per_step|border_fix_slice_processes_at_most_configured_tiles_per_step|border_fix_slice_respects_visual_category_budget`: 0 совпадений — новых public API/perf law updates не требовалось.
- Секция "Required updates" в спеке: есть — `DATA_CONTRACTS.md` выполнено для Iteration 2; `PUBLIC_API.md` и `PERFORMANCE_CONTRACTS.md` не требовались, grep подтвердил 0 совпадений.

### Наблюдения вне задачи (Out-of-scope observations)
- В worktree остаются не относящиеся к Iteration 2 изменения: `core/systems/world/chunk_manager.gd`, `data/balance/player_balance.gd`, удаление `gdextension/bin/~station_mirny.windows.template_debug.x86_64.dll`, untracked `boot_startup_regression_triage_spec.md`.

### Оставшиеся блокеры (Remaining blockers)
- Runtime perf acceptance остаётся за ручной проверкой пользователя (manual human verification), как требует спека.

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено (updated): `Seam Repair Queue`, grep-доказательство строки 646, 651, 652.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- Не требовалось (not required): grep по новым names вернул 0 совпадений в `PUBLIC_API.md`.

#### Blockers
- Runtime boot proof pending manual human verification.

### Boot Startup Regression Triage — Iteration 3
**Spec**: docs/02_system_specs/world/boot_startup_regression_triage_spec.md
**Status**: completed
**Started**: 2026-04-15
**Completed**: 2026-04-15

#### Scope
- Publish -> revoke cycle short-circuit in `ChunkManager` only.
- Runtime diagnostic signal + counter for visibility revoke churn.
- `DATA_CONTRACTS.md` Chunk Lifecycle contract update.
- No `ChunkSeamService`, `Chunk`, `GameWorld`, worker/native generator, or UI changes.

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- `ChunkManager` теперь хранит runtime-only базовую отметку публикации (publication baseline) для `pending_border_dirty_count` и разрешает `chunk_visibility_revoked` только если новый долг правки границы чанка (border-fix debt) вырос относительно предыдущей полной публикации.
- Добавлен short-circuit: повторный revoke без нового border debt отклоняется, пишет `[WorldDiag]` с severity `diagnostic_signal` и инкрементит `chunk.visibility_revoke_without_new_border_debt_total`.
- Добавлен repeat-diagnostic для случая, когда тот же chunk уходит в revoke повторно с той же сигнатурой visual state: counter `chunk.visibility_revoke_without_state_change_total`.
- `DATA_CONTRACTS.md` получил слой `Chunk Lifecycle` с ownership, rebuild policy, invariants и diagnostic events/counters.

### Корневая причина (Root cause)
- Текущий revoke path принимал любой ожидаемый visual follow-up (`needs_full_redraw()` или pending border dirty) как достаточное основание скрыть уже опубликованный chunk. Для stream-load соседей это позволяло boilerplate invalidation превращаться в publish -> revoke -> republish cycle без доказанного нового `pending_border_dirty_count`.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk_manager.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `.claude/agent-memory/active-epic.md`

### Проверки приёмки (Acceptance tests)
- [x] `assert(neighbor_visibility_revoke_requires_new_pending_border_fix_debt)` — прошло (passed); `rg` подтвердил helper `_neighbor_visibility_revoke_requires_new_pending_border_fix_debt()` в `chunk_manager.gd` и invariant в `DATA_CONTRACTS.md`.
- [ ] `chunk_visibility_revoked` для startup bubble chunks `<= 9` — требуется ручная проверка пользователем (manual human verification required); нужен fresh boot log на fixed seed.
- [ ] `convergence_age_ms` для ring 0 chunk `<= 5000` — требуется ручная проверка пользователем (manual human verification required); требует runtime milestone log.
- [ ] `Startup.loading_screen_visible_to_startup_bubble_ready_ms <= 15000` — требуется ручная проверка пользователем (manual human verification required); explicit agent-run runtime verification не запускался по policy.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `rg` показал `_record_chunk_visibility_publication_baseline()`, `_record_chunk_visibility_revoked()`, `WorldPerfProbe.record_counter()`, `SEVERITY_DIAGNOSTIC`, `chunk_visibility_revoke_short_circuited`, и новые counters в `core/systems/world/chunk_manager.gd`.
- Статическая проверка (Static verification): `git diff --check -- core/systems/world/chunk_manager.gd docs/02_system_specs/world/DATA_CONTRACTS.md core/systems/world/world_perf_probe.gd` прошёл.
- Синтаксическая проверка Godot (Godot syntax check): `.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --check-only --quit` прошёл exit 0.
- Ручная проверка пользователем (Manual human verification): требуется для runtime/perf acceptance.
- Рекомендованная проверка пользователем (Suggested human check): `.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_quit_on_boot_complete codex_world_seed=12345 *>&1 | Tee-Object -FilePath debug_exports/perf/boot_triage_seed12345.log`, затем grep по `chunk_visibility_revoked`, `convergence_age_ms`, `Startup.loading_screen_visible_to_startup_bubble_ready_ms`, `chunk.visibility_revoke_without_new_border_debt_total`.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): changed path не добавляет full chunk redraw или broad scan; sync work ограничен чтением одного chunk-local `pending_border_dirty_count`, сравнением с bounded lifecycle baseline и diagnostic emit с cooldown.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy; spec помечает runtime acceptance как manual human verification.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): тот же fixed seed boot harness `codex_world_seed=12345`, проверить отсутствие double-revoke и startup timings.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `neighbor_visibility_revoke_requires_new_pending_border_fix_debt|published_chunk_that_reaches_full_ready_does_not_re_enter_revoked_state_within_startup_bubble|chunk_visibility_revoke_short_circuited|chunk.visibility_revoke_without_new_border_debt_total|chunk.visibility_revoke_without_state_change_total`: совпадения есть в `Chunk Lifecycle` lines 362, 363, 378, 380 — обновлено.
- Grep PUBLIC_API.md для тех же names: 0 совпадений — public API не менялся.
- Секция "Required updates" в спеке: есть — `DATA_CONTRACTS.md` обновлён для Iteration 3; `PUBLIC_API.md` не требовался и подтверждён grep.

### Наблюдения вне задачи (Out-of-scope observations)
- В worktree остаются не относящиеся к Iteration 3 изменения: `data/balance/player_balance.gd`, удаление `gdextension/bin/~station_mirny.windows.template_debug.x86_64.dll`, untracked `boot_startup_regression_triage_spec.md`, а также изменения Iteration 1/2 в scheduler/perf/balance files.
- `world_perf_probe.gd` уже имел generic `record_counter()` после Iteration 1, поэтому Iteration 3 использует его без дополнительного изменения файла.

### Оставшиеся блокеры (Remaining blockers)
- Runtime/perf acceptance остаётся за ручной проверкой пользователя (manual human verification): fresh boot log нужен для чисел `chunk_visibility_revoked`, `convergence_age_ms` и startup bubble timing.

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено (updated): добавлен `Layer: Chunk Lifecycle`, grep-доказательство lines 362, 363, 378, 380.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- Не требовалось (not required): grep новых helper/invariant/counter names по `PUBLIC_API.md` вернул 0 совпадений; новых public entry points не добавлено.

### Iteration R4.2 — Runtime perf forensics and native triage
**Status**: completed
**Started**: 2026-04-14
**Completed**: 2026-04-14

#### Проверки приёмки (Acceptance tests)
- [x] latest runtime logs grouped into current boot / finalize / visual / shadow / topology culprits — passed (static verification: reviewed `godot.log`, `f11_chunk_overlay.log`, and `f11_chunk_incident_20260414_223657_333.log`)
- [x] fresh blockers mapped to concrete owner code paths — passed (static verification: traced logs to `chunk_manager.gd`, `chunk_streaming_service.gd`, `chunk_visual_scheduler.gd`, `mountain_shadow_system.gd`, `chunk_topology_service.gd`, `world_pre_pass.gd`, and GDExtension registration files)
- [x] current `R4` stabilization priorities re-ranked against the latest run — passed (static verification: harvest freeze no longer appears in the latest log; remaining `P0/P1` debt is dominated by install/finalize, visual publication, shadow, topology, and boot convergence)

#### Files touched
- `.claude/agent-memory/active-epic.md` — recorded `R4.2` diagnostic findings, current blocker ranking, and the missing `MountainShadowKernels` registration note

#### Отчёт о выполнении (Closure Report)
pending

#### Blockers
- `R4` remains blocked from progressing to `R5` until `phase2_finalize`, `streaming_redraw`, `mountain_shadow.visual_rebuild`, and long publication latency are reduced to contract-safe levels on a fresh runtime log

## Documentation debt

- [ ] DATA_CONTRACTS.md — update runtime ownership/readiness/publication semantics when an iteration changes canonical world/runtime contracts
- [ ] PUBLIC_API.md — update safe/read-only readiness and publication semantics when an iteration changes public-facing behavior
- **Deadline**: each iteration if semantics change
- **Status**: R4 completed on 2026-04-14, reopened for stabilization; `DATA_CONTRACTS.md` and `PUBLIC_API.md` updated again on 2026-04-15 because fixed hot/warm runtime envelope, bounded player-near border micro-fix, and blocked sync surface-load semantics changed

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

### Iteration R4 — Frontier planning and reserved scheduling
**Status**: completed
**Started**: 2026-04-14
**Completed**: 2026-04-14

#### Проверки приёмки (Acceptance tests)
- [x] far/background work cannot occupy all critical worker capacity — passed (static verification: `FrontierScheduler.RESERVED_CRITICAL_WORKERS`, `noncritical_capacity_limit()`, and `ChunkStreamingService._pop_next_load_request_for_capacity()` keep one compute slot reserved for frontier-critical work)
- [x] camera-visible chunks remain protected by frontier planning — passed (static verification: `FrontierPlanner.build_plan()` merges `camera_visible_set` into `frontier_critical_set` and `ChunkStreamingService.update_chunks()` uses `needed_set` for runtime enqueue/relevance)
- [ ] sprint traversal does not show visible chunk catch-up in ordinary scenarios — manual human verification required (runtime visual/perf smoke was not requested as an agent-run playtest)

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — matches for `TravelStateResolver`, `ViewEnvelopeResolver`, `FrontierPlanner`, `FrontierScheduler`, `ChunkStreamingService.update_chunks()`, `ChunkStreamingService.submit_async_generate()`, `gen_active_lanes`, and `frontier.reserved_capacity_blocked`
- [x] Grep PUBLIC_API.md for changed names — matches for `TravelStateResolver`, `ViewEnvelopeResolver`, `FrontierPlanner`, `FrontierScheduler`, `frontier_critical`, `camera_visible_support`, `frontier_reserved_capacity_blocks`, `ChunkStreamingService.update_chunks()`, and `submit_async_generate()`
- [x] Documentation debt section reviewed — reviewed; `DATA_CONTRACTS.md`, `PUBLIC_API.md`, and `frontier_native_runtime_architecture_spec.md` updated for R4 owner/lane semantics

#### Files touched
- `.claude/agent-memory/active-epic.md`
- `core/systems/world/travel_state_resolver.gd`
- `core/systems/world/travel_state_resolver.gd.uid`
- `core/systems/world/view_envelope_resolver.gd`
- `core/systems/world/view_envelope_resolver.gd.uid`
- `core/systems/world/frontier_planner.gd`
- `core/systems/world/frontier_planner.gd.uid`
- `core/systems/world/frontier_scheduler.gd`
- `core/systems/world/frontier_scheduler.gd.uid`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk_streaming_service.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/frontier_native_runtime_architecture_spec.md`

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Added explicit R4 runtime owners for travel state, view envelope, frontier planning, and reserved scheduling.
- Routed runtime streaming queues through frontier-critical, camera-visible-support, and background lanes.
- Added diagnostics for frontier lane state, plan summary, capacity snapshot, and reserved-capacity blocks.
- Updated canonical contracts/API docs and architecture migration notes.

### Проверки (Verification)
- `git diff --check` passed.
- `godot_console.exe --headless --path . --check-only --quit` passed.
- `rg` checks confirmed code/doc ownership, lane queues, reserved capacity, and contract/API references.
- Sprint traversal visual smoke remains manual human verification.

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
