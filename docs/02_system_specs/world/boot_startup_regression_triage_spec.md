---
title: Boot Startup Regression Triage
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-15
depends_on:
  - zero_tolerance_chunk_readiness_spec.md
  - frontier_native_runtime_architecture_spec.md
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/WORKFLOW.md
related_docs:
  - ../../04_execution/frontier_native_runtime_execution_plan.md
  - boot_chunk_readiness_spec.md
  - chunk_visual_pipeline_rework_spec.md
  - streaming_redraw_budget_spec.md
---

# Feature: Boot Startup Regression Triage

## Spec Classification

Это `interim triage spec`, а не `architecture spec` и не `legacy extension`.

- `frontier_native_runtime_architecture_spec.md` (`R5`) остаётся единственной авторитетной конечной архитектурой для публикации чанков.
- `zero_tolerance_chunk_readiness_spec.md` остаётся авторитетным product contract для readiness.
- Эта спека не продлевает устаревшие семантики (`first_pass`, `publish-now / finish-later`, прогрессивная visible convergence). Она ограничена удалением трёх измеримых патологий старого hybrid runtime, которые блокируют возможность работать над `R5` вообще.
- После слияния `R5` эта спека становится `legacy` и архивируется.

Любая итерация этой спеки, которая добавляет новые прогрессивные semantics или расширяет hybrid runtime, нарушает условия спеки и должна быть отклонена в ревью.

## Design Intent

Текущая загрузка мира на референсной машине занимает порядка 210 секунд, из них 104 секунды — `Startup.loading_screen_visible -> startup_bubble_ready`, ещё 106 секунд — `startup_bubble_ready -> boot_complete`. При этом нативная генерация 90 чанков занимает около 9 секунд суммарно, а `WorldPrePass` укладывается в 2.3 секунды. Остальные ~200 секунд уходят в visual convergence cascade на главном потоке.

Эта спека определяет bounded удаление трёх конкретных runtime патологий, подтверждённых логом:

1. **Visual task requeue runaway.** Счётчик `visual_task_requeue_total` достигает 21 643 событий на 90 чанков стартового пузыря (~240 requeue/chunk). Это прямое нарушение инварианта `task_dedupe_and_versioning_prevent_duplicate_live_work_for_same_chunk_kind` (`DATA_CONTRACTS.md`). Задачи одного чанка/kind/version накапливаются в живой очереди вместо дедупа.

2. **Seam drain без bounded slice.** `chunk_manager.streaming_redraw` выдаёт спайки `used_ms = 135 / 164 / 202 / 281 / 548 / 552 мс` при `budget_ms = 2.00`. Один slice вычищает до 62 seam-тайлов одного чанка за один main-thread шаг. Это нарушает `seam_repair_drain_is_bounded_per_step` (`DATA_CONTRACTS.md`).

3. **Publish -> revoke -> republish cycle.** После каждой публикации соседа чанки снова отзываются (`chunk_visibility_revoked`) и перерисовываются как `border_fix`. Для одного чанка игрока итоговый `convergence_age_ms = 92 768`. При этом native ChunkGen для того же чанка завершился за ~100 мс.

Эти три поведения вместе делают невозможным достижение ordinary seamless опыта и блокируют любой дальнейший rollout `R4`/`R5`, потому что на каждую итерацию требуется ждать 3.5 минуты загрузки.

## Performance / Scalability Contract

- **Runtime class:** `boot` (стартовый пузырь) + `background` (последующий seam drain и visual tick). Interactive path этой спекой не затрагивается.
- **Target scale / density:** стартовый пузырь `3x3` ring 0..1 на референсной машине (R5 2600 + GTX 1060, baseline из `zero_tolerance_chunk_readiness_spec.md`), до `5x5` включая warm ring 2 на `boot_complete`. Плотность seam-тайлов на границе чанка = `chunk_size` (сейчас 64 на сторону); количество visual-kind задач на чанк ограничено константой сверху.
- **Authoritative source of truth:**
  - `ChunkManager` — canonical chunk lifecycle, publication flip, revoke flip.
  - `ChunkVisualScheduler` — единственный mutable store визуальных очередей (`first_pass`, `terrain_continue`, `full_redraw`, `border_fix`, `cosmetic`) с их dedup/version helpers.
  - `ChunkSeamService` — автор seam-dirty events, читает/ставит задачи только через `ChunkVisualScheduler`.
- **Write owner:** `ChunkManager` для lifecycle/publication, `ChunkVisualScheduler` для task queue/version/latency, `ChunkSeamService` для enqueue seam work. Спека запрещает появление параллельных mutable mirrors вокруг этих трёх.
- **Derived/cache state:**
  - scheduler task index и version map — derived от chunk visual state; инвалидируется через `ChunkManager._invalidate_chunk_visual_convergence()`.
  - seam dirty set — derived от pair соседей `(chunk, neighbor, edge)`; инвалидируется при явной смене visual state соседей и только там.
  - никаких новых derived layers эта спека не добавляет.
- **Dirty unit:**
  - 1 visual task = 1 `(chunk, task_kind, version)` — единственный scheduler-side dirty element.
  - 1 seam-tile = 1 `(chunk, edge_index, tile_position)` — единственный apply-side dirty element.
  - Ни полный чанк, ни полный edge не являются легитимной dirty unit.
- **Allowed synchronous work:**
  - установка/снятие флагов publication в `ChunkManager`.
  - enqueue ровно одной dedup'нутой задачи через scheduler API.
  - обработка `N` seam-тайлов за один slice, где `N` ограничено новым экспортом `WorldGenBalance.visual_border_fix_tiles_per_step`.
- **Escalation path:**
  - если пакет seam-тайлов для одного чанка превышает slice budget — остаток остаётся в очереди до следующего tick, slice не продолжается синхронно.
  - если `ChunkVisualScheduler` детектит повторный requeue одинакового `(chunk, kind, version)` в пределах одного tick — задача отклоняется и инкрементится counter `scheduler.duplicate_requeue_rejected_total`.
  - задачи, не укладывающиеся в budget за несколько tick подряд, эскалируются в worker через существующий `ChunkVisualScheduler` worker path, как прописано в `DATA_CONTRACTS.md`. Новых worker entry points эта спека не добавляет.
- **Degraded mode:** отсутствует для player-reachable publication. `zero_tolerance_chunk_readiness_spec.md` прямо запрещает первый проход и flora-позже. Единственная допустимая «деградация» — увеличить время до `startup_bubble_ready` за счёт более ровной, budget-friendly работы без спайков. Показывать неполные чанки игроку запрещено так же, как и сейчас.
- **Forbidden shortcuts:**
  - публиковать чанк с нерешённым `pending_border_dirty_count > 0` и позже доправлять seam.
  - ввести `first_pass_ready` handoff для стартового пузыря.
  - снять revoke-флаг через UI/scene/диагностический код.
  - ослабить `FULL_READY` invariant (`chunk_full_ready_requires_redraw_done_and_no_pending_border_fix`).
  - добавить новый mutable mirror для scheduler state в обход `ChunkVisualScheduler`.
  - увеличить `FrameBudgetDispatcher` total budget выше 6 мс/кадр.
  - исправить visibility revoke cycle за счёт того, что `ChunkSeamService` будет помечать dirty только часть соседей.

## Data Contracts — new and affected

### Affected layer: Visual Task Scheduling (`DATA_CONTRACTS.md`)

- **Что меняется:**
  - `ChunkVisualScheduler` обязан соблюдать `task_dedupe_and_versioning_prevent_duplicate_live_work_for_same_chunk_kind` на ENQUEUE пути и на REQUEUE пути одинаково. Сейчас инвариант формально существует, но runtime выдаёт 21 643 requeue на 90 чанков, что является контрактным breach.
  - добавляется новая observable метрика `scheduler.duplicate_requeue_rejected_total`, принадлежащая тому же владельцу.
- **Новые инварианты:**
  - `assert(scheduler_rejects_duplicate_live_task_for_same_chunk_kind_version, "requeue must not resurrect a live task for an identical chunk/kind/version triple")`.
  - `assert(scheduler_visual_task_requeue_total_grows_sublinearly_in_startup_bubble_chunks, "startup bubble requeue must scale roughly linearly with chunks, not quadratically")`.
- **Кто адаптируется:** `ChunkVisualScheduler` (write), `ChunkManager` (enqueue caller), `WorldPerfProbe` (reader).
- **Что НЕ меняется:** набор task kinds, их приоритеты, ownership over apply-phase mutation, shapes `Chunk.*_ready()` APIs.

### Affected layer: Seam Repair Queue (`DATA_CONTRACTS.md`)

- **Что меняется:**
  - `ChunkSeamService.enqueue_neighbor_border_redraws()` обязан удерживать инвариант `seam_repair_drain_is_bounded_per_step` под фактической нагрузкой startup bubble. Сейчас один slice обрабатывает 62 тайла при budget 2 мс.
  - `WorldGenBalance` получает новый numeric export `visual_border_fix_tiles_per_step` с явным дефолтом, ограничивающим batch одного slice.
- **Новые инварианты:**
  - `assert(border_fix_slice_processes_at_most_configured_tiles_per_step, "one border-fix slice must not exceed visual_border_fix_tiles_per_step")`.
  - `assert(border_fix_slice_respects_visual_category_budget, "border-fix slice must stop when visual category budget is exhausted within the same tick")`.
- **Кто адаптируется:** `ChunkSeamService` (write), `ChunkVisualScheduler` (slicer), `WorldGenBalance` + `world_gen_balance.tres` (data export), `WorldPerfProbe` (reader).
- **Что НЕ меняется:** identity of seam-dirty entries, edge ownership, сигнатура публичного entry point.

### Affected layer: Chunk Lifecycle (`DATA_CONTRACTS.md`)

- **Что меняется:**
  - публикация чанка не должна пересекаться с `chunk_visibility_revoked` для соседей, у которых pending border-fix уже был rendered-finalized до их собственной предыдущей публикации. Revoke допустим только если соседу действительно нужна повторная финализация, иначе это regression.
  - добавляется runtime assertion/diagnostic, фиксирующий, если один чанк ушёл через `chunk_visibility_revoked -> republish` больше одного раза подряд без настоящего state change.
- **Новые инварианты:**
  - `assert(neighbor_visibility_revoke_requires_new_pending_border_fix_debt, "revoke must be caused by newly discovered border debt, not by boilerplate invalidation")`.
  - `assert(published_chunk_that_reaches_full_ready_does_not_re_enter_revoked_state_within_startup_bubble, "startup publication is terminal unless real new debt appears")`.
- **Кто адаптируется:** `ChunkManager` (owner). `ChunkSeamService` не получает новых прав записи.
- **Что НЕ меняется:** определение `FULL_READY`, порядок state machine, ownership boundary.

### New layer: Startup Bubble Convergence Budget (observability only)

- **Что:** набор readonly метрик, которые уже вычисляются scheduler-ом и perf probe, но сейчас не сведены в один snapshot для проверки acceptance tests этой спеки.
- **Где:** `core/systems/world/world_perf_probe.gd` + вспомогательная сборка в `core/systems/world/chunk_visual_scheduler.gd` (если scheduler класс выделен, иначе соответствующий раздел `ChunkManager`).
- **Владелец (WRITE):** `WorldPerfProbe`.
- **Читатели (READ):** acceptance tests этой спеки, `[WorldPerf]` log channel, `GameWorldDebug`.
- **Инварианты:**
  - `assert(startup_bubble_convergence_snapshot_is_read_only_for_non_owner, "only WorldPerfProbe may write convergence snapshot fields")`.
- **Событие после изменения:** нет, readonly snapshot.
- **Запрещено:**
  - использовать snapshot как источник истины для publication, revoke или handoff. Это только диагностика.

## Required contract and API updates

- `DATA_CONTRACTS.md`:
  - добавить/уточнить invariants в разделах `Visual Task Scheduling`, `Seam Repair Queue`, `Chunk Lifecycle` (см. выше).
  - добавить observability-only `Startup Bubble Convergence Budget` snapshot как read-only artifact.
- `PUBLIC_API.md`:
  - `не требуется` для новых публичных write entry points: эта спека их не добавляет. Явно подтвердить grep'ом в closure report.
  - если реализация Iteration 1 добавит новый readonly helper (например, `WorldPerfProbe.get_startup_bubble_convergence_snapshot()`), обновить `PUBLIC_API.md` одновременно с реализацией.
- `PERFORMANCE_CONTRACTS.md`:
  - `не требуется`. Основная law этой спеки уже есть в §1.4, §2.2 и §7. Эта спека фиксит несоответствие реализации, а не меняет law. Подтвердить grep'ом.
- `ENGINEERING_STANDARDS.md`:
  - `не требуется`. Pattern set не меняется.
- `frontier_native_runtime_execution_plan.md` и `zero_tolerance_chunk_readiness_spec.md`:
  - добавить cross-reference, что interim triage закрывает startup-level regression до `R5`, но не заменяет `R5`.

## Iterations

### Iteration 1 — Requeue dedup on the enqueue-and-requeue path

**Цель:** устранить visual requeue runaway, не вводя новую очередь и не расширяя legacy semantics.

Что делается:
- обзор всех call sites, которые сейчас приводят к добавлению визуальной задачи в live scheduler очередь (enqueue, reschedule, invalidate -> reschedule, seam -> reschedule).
- ввести единую dedup-гейт функцию внутри `ChunkVisualScheduler`, которая rejects task с идентичным `(chunk_coord, task_kind, version)`, уже находящимся в live-set, и инкрементит счётчик `scheduler.duplicate_requeue_rejected_total`.
- прогнать эту гейт-функцию на пути requeue, а не только enqueue. Сейчас patология именно в requeue пути.
- обновить `DATA_CONTRACTS.md` раздел `Visual Task Scheduling` с новыми инвариантами и обозначением read-only счётчика.

Acceptance tests:
- [ ] `assert(scheduler_rejects_duplicate_live_task_for_same_chunk_kind_version)` статически подтверждён по коду scheduler.
- [ ] при стартовой загрузке на fixed seed `codex_world_seed=12345` и baseline машине `visual_task_requeue_total <= 500` для 90 чанков стартового пузыря (вместо 21 643 сейчас). `manual human verification required`, harness `godot_console --scene res://scenes/world/game_world.tscn -- codex_quit_on_boot_complete codex_world_seed=12345`.
- [ ] `scheduler.duplicate_requeue_rejected_total > 0` на той же сессии, что подтверждает, что dedup действительно отрабатывает, а не исчезновение сигнала.
- [ ] grep `PUBLIC_API.md` для новых API: ни одного не добавлено, или добавлены только readonly getters.

Файлы, которые будут затронуты:
- `core/systems/world/chunk_visual_scheduler.gd` (если scheduler выделен в отдельный файл; иначе соответствующая секция `core/systems/world/chunk_manager.gd`).
- `core/systems/world/world_perf_probe.gd` (readonly counter).
- `docs/02_system_specs/world/DATA_CONTRACTS.md` (Visual Task Scheduling раздел).

Файлы, которые НЕ ДОЛЖНЫ быть затронуты:
- `core/systems/world/chunk.gd`.
- `core/systems/world/chunk_seam_service.gd`.
- `scenes/world/game_world.gd`.
- `core/autoloads/world_generator.gd`.
- `core/autoloads/frame_budget_dispatcher.gd`.
- любой mining/topology/shadow/flora runtime.

### Iteration 2 — Bounded seam drain slice

**Цель:** устранить 135–552 мс спайки `streaming_redraw` через явное budget-slicing seam drain.

Что делается:
- добавить export `visual_border_fix_tiles_per_step: int` в `WorldGenBalance` с дефолтом, подобранным из измерений p99 стоимости одного seam-тайла (ориентир — p99 `phase2_finalize` даёт ~30 мс/чанк на 62 тайла, то есть ~0.5 мс/тайл; дефолт должен быть `<= 4` тайла/slice, чтобы уложиться в 2 мс budget).
- дополнить `ChunkVisualScheduler` slicer'ом seam drain по `(chunk, edge)` пакетам размером не больше этого export'а; остаток пакета остаётся в очереди до следующего tick.
- оставить сам алгоритм seam drain неизменным; поменять только frame policy.
- обновить `DATA_CONTRACTS.md` раздел `Seam Repair Queue` с новыми инвариантами и ссылкой на balance export.

Acceptance tests:
- [ ] `assert(border_fix_slice_processes_at_most_configured_tiles_per_step)` статически подтверждён по коду slicer.
- [ ] В новом стартовом прогоне `chunk_manager.streaming_redraw` не имеет событий `over_budget_pct > 50` для `category=visual`. `manual human verification required` по тому же harness, grep лога на `FrameBudget overrun job_id=chunk_manager.streaming_redraw` после исправления.
- [ ] `ChunkStreaming.phase2_finalize` peak не превышает `<= 4 мс` на чанк на baseline машине (сейчас 12–35 мс).
- [ ] `world_gen_balance.tres` содержит numeric default для `visual_border_fix_tiles_per_step`.

Файлы, которые будут затронуты:
- `data/world/world_gen_balance.gd`.
- `data/world/world_gen_balance.tres`.
- `core/systems/world/chunk_visual_scheduler.gd` (или соответствующая секция `chunk_manager.gd`).
- `docs/02_system_specs/world/DATA_CONTRACTS.md` (Seam Repair Queue раздел).

Файлы, которые НЕ ДОЛЖНЫ быть затронуты:
- `core/systems/world/chunk_seam_service.gd` (service может запросить slicer, но не меняет own ownership).
- `core/systems/world/chunk.gd`.
- `scenes/world/game_world.gd`.
- native runtime и generator.

### Iteration 3 — Publish -> revoke cycle short-circuit

**Цель:** устранить массовый `chunk_visibility_revoked` для чанков, у которых новая border-debt не появилась.

Что делается:
- ужесточить условие в `ChunkManager`, при котором сосед переводится в `chunk_visibility_revoked` после появления нового загруженного соседа: revoke обязан требовать нового increment `pending_border_dirty_count` на стороне соседа. Сейчас revoke флипается как boilerplate при любом `queue_follow_up`.
- добавить runtime diagnostic (не assert fatal, а `[WorldDiag]` severity='diagnostic_signal' + counter) для случая, когда тот же чанк уходит в revoke более одного раза подряд без actual state change.
- обновить `DATA_CONTRACTS.md` раздел `Chunk Lifecycle` с новыми инвариантами.

Acceptance tests:
- [ ] `assert(neighbor_visibility_revoke_requires_new_pending_border_fix_debt)` статически подтверждён.
- [ ] В новом стартовом прогоне количество `chunk_visibility_revoked` событий для чанков стартового пузыря `<= 9` (один раз на чанк максимум). Сейчас 8 видно только для очень ранней фазы, но следует убедиться, что не появляется double-revoke.
- [ ] `convergence_age_ms` для ring 0 чанка `<= 5000` (вместо 92 768). `manual human verification required`.
- [ ] `Startup.loading_screen_visible_to_startup_bubble_ready_ms <= 15000` на fixed seed baseline. Сейчас 103 995.

Файлы, которые будут затронуты:
- `core/systems/world/chunk_manager.gd`.
- `core/systems/world/world_perf_probe.gd` (readonly counter + diagnostic).
- `docs/02_system_specs/world/DATA_CONTRACTS.md` (Chunk Lifecycle раздел).

Файлы, которые НЕ ДОЛЖНЫ быть затронуты:
- `core/systems/world/chunk.gd`.
- `core/systems/world/chunk_seam_service.gd`.
- `scenes/world/game_world.gd`.
- worker/native generator.
- любой UI.

## Acceptance — aggregate

После всех трёх итераций и на fixed seed `codex_world_seed=12345` на baseline машине:

- [ ] `Startup.loading_screen_visible_to_startup_bubble_ready_ms <= 15000` (было 103 995).
- [ ] `Startup.startup_bubble_ready_to_boot_complete_ms <= 30000` (было 105 606).
- [ ] `visual_task_requeue_total <= 500` на 90 чанков стартового пузыря.
- [ ] ни одного `FrameBudget overrun` для `chunk_manager.streaming_redraw` с `used_ms > 6 мс`.
- [ ] ни одного `ChunkStreaming.phase2_finalize` события с `> 4 мс`.
- [ ] ни одного чанка стартового пузыря с `chunk_visibility_revoked` более одного раза.
- [ ] `FULL_READY` контракт `chunk_full_ready_requires_redraw_done_and_no_pending_border_fix` по-прежнему выполняется.
- [ ] `zero_tolerance_chunk_readiness_spec.md` contract остаётся ненарушенным: нет `first_pass` публикации, нет visible catch-up после reveal.

Все runtime acceptance требуют `manual human verification required` по policy, harness — `godot_console --scene res://scenes/world/game_world.tscn -- codex_quit_on_boot_complete codex_world_seed=12345 *>&1 | Tee-Object -FilePath debug_exports/perf/boot_triage_seed12345.log`. Статические инварианты проверяются grep/read по коду и DATA_CONTRACTS.md.

## Explicitly Out of Scope

- замена legacy chunk runtime на frontier-native (это `R5` из execution plan).
- изменение ownership boundary между `ChunkManager`, `ChunkVisualScheduler`, `ChunkSeamService`.
- новые task kinds или новая scheduler архитектура.
- `WorldPrePass` оптимизации (например миграция `sample_height_grid` 751 мс в native).
- увеличение `max_concurrent` worker pool.
- fixing `ERROR: 16 resources still in use at exit` (отдельное расследование).
- `MountainShadowKernels available=false` и shadow kernel native миграция.
- fixing mojibake в `[WorldDiag]` сообщениях.
- save/load round-trip behaviour.

Out-of-scope наблюдения из анализа лога идут в отдельный backlog, не в эту спеку.

## Migration / Sunset Rule

Когда `R5` (Final-packet-only publication switch) будет слит:

- эта спека автоматически помечается `legacy` и перемещается в `docs/99_archive/`.
- introduced `visual_border_fix_tiles_per_step` export переоценивается на предмет удаления; final packet publication не должен нуждаться в seam slicing вовсе.
- `scheduler.duplicate_requeue_rejected_total` counter остаётся как regression tripwire, если сам scheduler не удалён целиком в рамках `R5`.

## Forbidden shortcuts (summary)

Ни одна из итераций этой спеки не имеет права:

- вводить `first_pass_ready` handoff или любую форму прогрессивной публикации для player-reachable чанков.
- расширять `FrameBudgetDispatcher` total budget выше 6 мс.
- снимать `FULL_READY` invariant про `no pending_border_fix`.
- публиковать чанк, который ещё имеет pending seam debt.
- вводить параллельный scheduler или cache в обход `ChunkVisualScheduler`.
- "убирать" requeue runaway путём удаления счётчика вместо источника.
- "убирать" seam spike путём подавления log warning вместо slice bound.
- "убирать" revoke cycle путём широкого отключения invalidation.

---

## Требуется одобрение человека (Human approval required)

Эта спека ещё не авторизована для реализации. Перед тем как агент получит задачу "реализуй Iteration 1" (и далее 2, 3), пользователь должен явно подтвердить:

1. Классификация как `interim triage spec`, а не как продление legacy hybrid runtime — корректна.
2. Три таргетируемые патологии (requeue runaway, unbounded seam slice, publish-revoke cycle) действительно являются приоритетом до `R5`, и их фикс сейчас не конкурирует с `R4`/`R5` работой.
3. Acceptance numbers (`<= 15000 мс` для `startup_bubble_ready`, `<= 500` requeue, `<= 6 мс` streaming_redraw peak) приемлемы как триаж-цель. Они не претендуют на seamless target — это просто удаление аномалии, дающее возможность работать над `R5`.
4. Список файлов allowed/forbidden в каждой итерации — корректный.
5. Out-of-scope список полный.

Если одобрение дано — реализация идёт строго по одной итерации за раз (`Iteration 1` -> review -> `Iteration 2` -> review -> `Iteration 3` -> review). Никаких "заодно починим и shadow" или "заодно ускорим WorldPrePass".

Если одобрение не дано или требуются правки — в эту спеку вносятся изменения, и только после следующего approval работа над Iteration 1 может начаться.
