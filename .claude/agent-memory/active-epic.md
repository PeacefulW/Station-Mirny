# Epic: AI Performance Observatory

**Spec**: `docs/02_system_specs/meta/ai_performance_observatory_spec.md`
**Started**: 2026-04-16
**Current iteration**: 2
**Total iterations**: 5

## Documentation debt

- [x] `DATA_CONTRACTS.md` - documented `Perf Telemetry Snapshot` ownership for Iteration 1 on 2026-04-16
- [x] `DATA_CONTRACTS.md` - documented `Validation Scenario Proof Records` ownership for Iteration 2 on 2026-04-16
- [ ] `PUBLIC_API.md` - update only if a new public read-only observability accessor becomes sanctioned
- **Deadline**: after iteration 4, or earlier in any iteration that changes documented semantics
- **Status**: Iteration 1 and Iteration 2 contract docs landed; `PUBLIC_API.md` remains not required for the current implementation

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
**Status**: pending

### Iteration 4 - Stress / Scale Presets
**Status**: pending

### Iteration 5 - Streaming Optimization Handoff (Separate Spec Required)
**Status**: pending
