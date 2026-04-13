# Epic: Chunk System Refactor — Service Ownership Cleanup

**Spec**: docs/04_execution/chunk_system_refactor_spec_2026-04-12.md
**Started**: 2026-04-13
**Current iteration**: 9
**Total iterations**: 10

## Documentation debt

- [x] DATA_CONTRACTS.md — update Topology / Boot Readiness / Boot Compute Queue ownership and write operations after service extraction
- [x] PUBLIC_API.md — update internal owner-path references for topology and boot orchestration after service extraction
- **Deadline**: each iteration if semantics change
- **Status**: done

## Iterations

### Iteration 9 — Manager decomposition pass 2 and scheduler cleanup
**Status**: completed
**Started**: 2026-04-13
**Completed**: 2026-04-13

#### Проверки приёмки (Acceptance tests)
- [x] `chunk_manager.gd` is visibly reduced to orchestration/public API — passed (static verification: `git diff --stat -- core/systems/world/chunk_manager.gd` shows `574 deletions / 108 insertions`; `rg -n "^var _boot_|^var _native_topology" core/systems/world/chunk_manager.gd` returned 0 matches)
- [x] scheduler internals are owned by the dedicated scheduler module — passed (static verification: `class_name ChunkVisualScheduler` in `core/systems/world/chunk_visual_scheduler.gd`; owner rows present in `DATA_CONTRACTS.md` and `PUBLIC_API.md`)
- [x] cache internals are owned by the cache module — passed (static verification: `class_name ChunkSurfacePayloadCache` in `core/systems/world/chunk_surface_payload_cache.gd`; owner rows present in `DATA_CONTRACTS.md` and `PUBLIC_API.md`)
- [x] seam internals are owned by the seam module — passed (static verification: `class_name ChunkSeamService` in `core/systems/world/chunk_seam_service.gd`; owner rows present in `DATA_CONTRACTS.md` and `PUBLIC_API.md`)
- [x] boot pipeline internals are owned by `chunk_boot_pipeline.gd` — passed (static verification: `class_name ChunkBootPipeline` in `core/systems/world/chunk_boot_pipeline.gd`; `ChunkManager.boot_load_initial_chunks()` delegates into `_chunk_boot_pipeline`; owner rows present in `DATA_CONTRACTS.md` and `PUBLIC_API.md`)
- [x] topology runtime ownership is routed through `chunk_topology_service.gd` — passed (static verification: `class_name ChunkTopologyService` in `core/systems/world/chunk_topology_service.gd`; `ChunkManager._tick_topology()` / `_on_mountain_tile_changed()` / topology install-unload facades forward into `_chunk_topology_service`; owner rows present in `DATA_CONTRACTS.md` and `PUBLIC_API.md`)

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — `ChunkTopologyService`, `ChunkBootPipeline`, `ChunkVisualScheduler`, `ChunkSurfacePayloadCache`, `ChunkSeamService` all found and aligned with owner/write semantics
- [x] Grep PUBLIC_API.md for changed names — `ChunkTopologyService`, `ChunkBootPipeline`, `ChunkVisualScheduler`, `ChunkSurfacePayloadCache`, `ChunkSeamService`, `_tick_topology`, `_setup_native_topology_builder`, `_on_mountain_tile_changed`, `boot_load_initial_chunks` all found and aligned with public-facade/internal-owner split
- [x] Documentation debt section reviewed — updated this iteration; both debt items cleared

#### Files touched
- `.claude/agent-memory/active-epic.md` — resumed iteration tracking for boot/topology service extraction
- `core/systems/world/chunk_manager.gd` — removed boot/topology mutable state ownership and kept facade/orchestration entrypoints
- `core/systems/world/chunk_boot_pipeline.gd` — extracted boot readiness, compute/apply queues, and runtime handoff ownership
- `core/systems/world/chunk_topology_service.gd` — extracted topology builder state, dirty tracking, and load/unload/mining mutation bridge
- `core/systems/world/chunk_streaming_service.gd` — routed topology unload follow-up through manager/service facade
- `core/systems/world/chunk_visual_scheduler.gd` — retained scheduler ownership and hot-path debug guard cleanup from the same iteration
- `core/systems/world/chunk_visual_kernel.gd` — documented explicit visual kernel contract
- `core/systems/world/chunk.gd` — removed legacy cover-edge dictionary cache path
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — documented extracted ownership for topology / boot layers and existing iteration-9 services
- `docs/00_governance/PUBLIC_API.md` — documented internal owner services behind public `ChunkManager` facades

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлены `core/systems/world/chunk_boot_pipeline.gd` и `core/systems/world/chunk_topology_service.gd` как internal owners для boot state/queues и topology runtime state.
- `ChunkManager` переведён на public facade / orchestration role: boot/topology state удалён из manager-owned `var`, а boot/topology entrypoints делегируют в новые сервисы.
- `ChunkStreamingService` unload path переведён на manager/service topology facade, а `DATA_CONTRACTS.md` и `PUBLIC_API.md` обновлены под новый ownership split.

### Корневая причина (Root cause)
- Boot pipeline и topology orchestration оставались как mutable state внутри `ChunkManager`, из-за чего публичный фасад и реальный write owner расходились с целевой архитектурой.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk_boot_pipeline.gd`
- `core/systems/world/chunk_topology_service.gd`
- `core/systems/world/chunk_streaming_service.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

### Проверки приёмки (Acceptance tests)
- [x] `chunk_manager.gd` reduced to orchestration/public API — passed (static verification: `git diff --stat -- core/systems/world/chunk_manager.gd` shows `574 deletions / 108 insertions`; `rg -n "^var _boot_|^var _native_topology"` returned 0 matches)
- [x] boot pipeline internals are owned by `chunk_boot_pipeline.gd` — passed (static verification: `class_name ChunkBootPipeline`; manager boot entrypoint delegates into `_chunk_boot_pipeline`)
- [x] topology runtime ownership is routed through `chunk_topology_service.gd` — passed (static verification: `class_name ChunkTopologyService`; manager topology/mining/install/unload facades delegate into `_chunk_topology_service`)
- [x] scheduler/cache/seam owners remain extracted and documented — passed (static verification: `class_name ChunkVisualScheduler` / `ChunkSurfacePayloadCache` / `ChunkSeamService`; owner rows present in docs)
- [x] headless project smoke check after extraction — passed (explicit agent-run runtime verification: `godot_console.exe --headless --path . --quit-after 1`)

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): grep confirmed new services, manager facades, zero old boot/topology owner vars, and updated contract/API references.
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): загрузить мир, дождаться boot handoff, затем проверить chunk unload/reload и mining на границе чанка без topology regressions.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): topology rebuild remains budgeted through `_tick_topology()` / `ChunkTopologyService.tick()`, and boot work remains inside `ChunkBootPipeline` instead of returning mutable queues into `ChunkManager`.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): perf/profile run не запускался в этой задаче по policy; выполнен только headless smoke check
- Ручная проверка пользователем (Manual human verification): требуется для фактического frame-time / boot-time confirmation
- Рекомендованная проверка пользователем (Suggested human check): снять profiler на boot + mining seam scenario и убедиться, что topology convergence остаётся в budgeted path.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `ChunkTopologyService`: matches at `55`, `127`, `384-407` — updated
- Grep PUBLIC_API.md для `ChunkTopologyService`: matches at `197`, `209`, `316`, `322`, `357-360`, `527` — updated
- Grep DATA_CONTRACTS.md для `ChunkBootPipeline`: matches at `66`, `130`, `822-906` — updated
- Grep PUBLIC_API.md для `ChunkBootPipeline`: matches at `197-198`, `209`, `316-317`, `454`, `528` — updated
- Секция "Required updates" в спеке: нет — `rg -n "Required contract and API updates|Required updates" docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` returned 0 matches

### Наблюдения вне задачи (Out-of-scope observations)
- Iteration 10 final dead-code deletion / stable ownership freeze remains future spec work.

### Оставшиеся блокеры (Remaining blockers)
- none

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- updated: Layer Map, current source-of-truth summary, `Layer: Topology`, `Layer: Boot Readiness`, and `Layer: Boot Compute Queue`

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- updated: boot/topology safe entrypoints, topology internal-method notes, Iteration 9 ownership note, and internal service table rows for `ChunkTopologyService.*` / `ChunkBootPipeline.*`

#### Blockers
- none

---

### Emergency performance hotfix — 2026-04-13
**Status**: implemented; pending manual F11 validation

#### Scope
- Investigated user-provided runtime/F11 logs for severe freezes and chunk streaming stalls.
- Targeted the confirmed `chunk_manager.streaming_redraw` frame-budget offender instead of broad subsystem rewrite.

#### Implemented
- Removed synchronous flora texture loading from the visual apply/draw path; `ChunkFloraPresenter` now uses threaded resource requests and fallback packet colors while textures resolve.
- Tightened visual scheduler defaults and adaptive apply caps so terrain/cover/cliff/border batches are smaller and closer to the 1-2 ms visual rebuild contract.
- Added phase telemetry for native chunk generation (`authoritative_inputs`, native call, validate, prebaked visual payload, worker total, submit-to-collect overhead).
- Added one-time `MountainShadowKernels` availability logging and warning markers if blocking shadow boot APIs are called after `Boot.first_playable`.
- Updated `DATA_CONTRACTS.md` and `PUBLIC_API.md` for non-blocking flora texture priming and blocking shadow API runtime warnings.

#### Verification
- `godot_console.exe --headless --path . --quit-after 1` — passed.
- `git diff --check -- <touched files>` — passed; only existing CRLF warning for `data/world/world_gen_balance.gd`.
- Static grep confirmed no `ResourceLoader.load()` remains in `core/systems/world/chunk_flora_presenter.gd`.

#### Remaining validation
- Manual F11 streaming run required to confirm `FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw` no longer spikes into hundreds of ms and that near chunks converge without visible raw build-up.
