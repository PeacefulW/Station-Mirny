---
title: AI Performance Observatory
doc_type: system_spec
status: approved
owner: engineering
source_of_truth: true
version: 0.2
last_updated: 2026-04-16
depends_on:
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../world/DATA_CONTRACTS.md
related_docs:
  - ai_performance_observatory_design_brief.md
  - runtime_budget_overrun_observability_spec.md
  - ../world/boot_performance_instrumentation_spec.md
  - ../world/frontier_native_runtime_architecture_spec.md
---

# Feature: AI Performance Observatory

## Design Intent

This feature turns the current world-performance instrumentation into a machine-readable,
repeatable observability loop for agents and humans:

- run a fixed headless scenario
- capture one self-contained JSON artifact
- compare it to a known baseline
- see which contract or subphase regressed
- iterate without reverse-engineering console text by hand

The observatory is not the streaming optimization itself.
It is the proof and diagnosis infrastructure that future optimization specs will use.

This spec is created from the existing design brief and is the required spec-first bridge.
Until a human reviews this spec, implementation work is blocked by `WORKFLOW.md`.

## Performance / Scalability Contract

Runtime work classes for this feature:

- `boot`: collecting startup milestones and boot aggregates during headless proof
- `background`: collecting bounded per-frame summaries and chunk lifecycle timeline rows
- `interactive`: none; observatory work must not add new synchronous gameplay work in player input paths

Authoritative write owners:

- `WorldPerfProbe`: raw timing records, contract violations, and milestone markers
- `WorldPerfMonitor`: per-frame aggregation and read-only debug snapshot assembly
- `RuntimeValidationDriver` or later `ValidationScenario` subclasses: validation/scenario outcomes
- native `ChunkGenerator` / `MountainTopologyBuilder`: `_prof_*` subphase timing payloads
- `PerfTelemetryCollector`: derived JSON assembly and file serialization only

Dirty units and safe synchronous scope:

- one metric record
- one frame summary update
- one scenario result record
- one chunk lifecycle/timeline row
- one final JSON write at the end of an explicit perf/stress run

Rules:

- observatory collection must stay disabled unless explicit user args request it
- no new always-on log parsing, polling loops over loaded world, or second diagnostics bus
- no gameplay system may start reading JSON artifacts as runtime truth
- structured JSON must be assembled from owner-fed dictionaries, not reconstructed from console text
- if profiling fields are absent from native payloads, runtime must fail open for observability and keep gameplay semantics unchanged

## Public API impact

Current public APIs affected semantically:

- `WorldPerfMonitor.get_debug_snapshot() -> Dictionary`
- `WorldRuntimeDiagnosticLog.get_timeline_snapshot(limit: int = 24) -> Array[Dictionary]`

Potential new public read surfaces:

- none required for the initial write path
- if a new read-only accessor is introduced for JSON-ready summary export, it must be documented in `PUBLIC_API.md`

Non-public surfaces introduced by this feature:

- `codex_perf_test`
- `codex_perf_output=...`
- `codex_quit_on_perf_complete`
- `codex_validate_scenarios=...`
- `codex_stress_mode=...`

Those user args are debug/proof surfaces, not permission to mutate gameplay ownership or runtime truth.

## Data Contracts - new and affected

### New layer: Perf Telemetry Snapshot

- What:
  - one self-contained JSON artifact per explicit proof run
- Where:
  - `core/debug/perf_telemetry_collector.gd`
  - `debug_exports/perf/*.json`
- Owner (WRITE):
  - `PerfTelemetryCollector` writes the derived JSON artifact
  - source systems feed it through narrow direct calls
- Readers (READ):
  - agents
  - manual perf review
  - optional diff/summarizer tools
- Invariants:
  - JSON must remain self-contained for one run
  - collector must not become a second gameplay event bus
  - collector must not parse console text as its primary source
  - writes happen only for explicit perf/stress runs
  - disabled runs do not allocate or write JSON artifacts
- Forbidden:
  - always-on artifact writes during normal gameplay
  - treating exported JSON as save/load or gameplay truth
  - reconstructing lifecycle order from ad-hoc string parsing when structured owner data exists

### Affected layer: Runtime diagnostics

- What changes:
  - existing performance and timeline owners may feed structured observatory data
- Who adapts:
  - `WorldPerfProbe`
  - `WorldPerfMonitor`
  - `RuntimeValidationDriver`
- What does NOT change:
  - `WorldPerfMonitor` remains read-only aggregation
  - `WorldRuntimeDiagnosticLog` remains a bounded diagnostic timeline, not a bulk telemetry sink
  - gameplay systems do not gain direct write access to collector internals

### Affected layer: Native profiling payload

- What changes:
  - native runtime helpers may append debug-only `_prof_*` timings into their existing result dictionaries
- Who adapts:
  - `ChunkGenerator`
  - `MountainTopologyBuilder`
- Invariants:
  - `_prof_*` keys are derived profiling payload only
  - gameplay correctness must not depend on `_prof_*` fields
  - missing `_prof_*` keys must not change generation/topology semantics

### Affected layer: Validation scenario orchestration

- What changes:
  - `RuntimeValidationDriver` evolves from one script with hardcoded checks into a scenario orchestrator
- Who adapts:
  - `RuntimeValidationDriver`
  - new `ValidationScenario` subclasses
- Invariants:
  - scenario code uses existing safe entrypoints and command paths
  - scenario results are derived proof records, not gameplay truth
  - scenario selection is explicit by CLI arg, not always-on

## Required contract and API updates after implementation

When this feature is implemented:

- `DATA_CONTRACTS.md`
  - document `Perf Telemetry Snapshot` ownership once Iteration 1 lands
  - document `Validation Scenario` ownership once Iteration 2 lands
  - document `Stress Driver` ownership once Iteration 4 lands
- `PUBLIC_API.md`
  - update only if a new public read-only observatory accessor becomes sanctioned
  - do not document write-only internal collector hooks as public API

Iteration 3 also has a repository-structure rule:

- repo-specific observatory skill lives in `.agents/skills/perf-observatory/`
- `.claude/skills/perf-observatory.md` may exist only as a compatibility mirror, not as the sole source

## Iterations

### Iteration 1 - Telemetry + Native Profiling

Goal:
One explicit perf run produces one parseable JSON artifact with structured boot, streaming,
frame, contract, scenario, and native profiling data.

What is done:

- add `PerfTelemetryCollector` as a debug-only derived collector
- enable it only with `codex_perf_test`
- write one JSON artifact to `codex_perf_output` or `debug_exports/perf/result.json`
- feed boot milestones, frame summary, chunk readiness timeline, contract violations, and scenario outcomes into the collector
- append debug-only `_prof_*` phase timings in native `ChunkGenerator`
- append debug-only `_prof_*` phase timings in native `MountainTopologyBuilder`
- add `codex_quit_on_perf_complete` so explicit perf runs can finish headless and exit
- commit one fixed-seed baseline artifact only after a real proof run

Acceptance tests:

- [ ] `codex_perf_test codex_world_seed=12345` writes a JSON file containing `meta`, `boot`, `streaming`, `frame_summary`, `contract_violations`, `scenarios`, and `native_profiling`
- [ ] the JSON file parses without schema-breaking errors
- [ ] collector remains disabled when `codex_perf_test` is absent
- [ ] `native_profiling.chunk_generator` contains internal phase breakdown
- [ ] `native_profiling.topology_builder` contains internal phase breakdown
- [ ] implementation does not introduce a second always-on diagnostics bus or console-log parser

Files that may be touched:

- `core/debug/perf_telemetry_collector.gd`
- `core/debug/runtime_validation_driver.gd`
- `core/autoloads/world_perf_monitor.gd`
- `core/systems/world/world_perf_probe.gd`
- `core/systems/world/chunk_streaming_service.gd`
- `core/systems/world/chunk_boot_pipeline.gd`
- `scenes/world/game_world.gd`
- `scenes/world/game_world_debug.gd`
- `gdextension/src/chunk_generator.h`
- `gdextension/src/chunk_generator.cpp`
- `gdextension/src/mountain_topology_builder.h`
- `gdextension/src/mountain_topology_builder.cpp`
- `debug_exports/perf/baseline_seed12345.json`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` only if ownership/invariants become normative
- `docs/00_governance/PUBLIC_API.md` only if a new public read accessor is added

Files that must NOT be touched:

- streaming architecture ownership
- chunk publication rules
- mining/building/power gameplay semantics
- save/load format
- any new autoload registration unless the iteration spec is amended and reviewed

### Iteration 2 - Scenario Factory

Goal:
Turn validation into modular scenarios so proofs can target route traversal, room, power,
mining, speed traversal, mass placement, deep mining, and chunk revisit independently.

What is done:

- introduce `ValidationScenario` and `ValidationContext`
- refactor existing room/power/mining checks out of `RuntimeValidationDriver`
- support `codex_validate_scenarios=...`
- add at least `speed_traverse`, `mass_placement`, `deep_mine`, and `chunk_revisit`
- serialize each scenario result as its own JSON block

Acceptance tests:

- [ ] `codex_validate_scenarios=route,room,power,mining` runs only the requested scenarios
- [ ] each executed scenario writes its own result block into JSON
- [ ] existing route/room/power/mining proof behavior still works after refactor
- [ ] `speed_traverse` reports readiness-versus-traverse outcome instead of silent success
- [ ] scenario code uses existing safe entrypoints / commands rather than direct hidden mutations

Files that may be touched:

- `core/debug/runtime_validation_driver.gd`
- `core/debug/scenarios/validation_scenario.gd`
- `core/debug/scenarios/validation_context.gd`
- `core/debug/scenarios/*.gd`
- `core/debug/perf_telemetry_collector.gd`
- `scenes/world/game_world_debug.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` only if scenario ownership becomes normative
- `docs/00_governance/PUBLIC_API.md` only if a new public read accessor is added

Files that must NOT be touched:

- production gameplay ownership boundaries
- command-executor bypasses
- chunk lifecycle/publication semantics
- save/load semantics except proof reads already covered by safe APIs

### Iteration 3 - Observatory Skill + Baseline Diff

Goal:
Give the agent one sanctioned repository-local workflow for `run -> read JSON -> diff baseline -> report`.

What is done:

- add repo-specific skill at `.agents/skills/perf-observatory/SKILL.md`
- add optional `.claude/skills/perf-observatory.md` mirror only if compatibility is needed
- add a baseline diff helper that compares JSON artifacts
- document simple pass/fail heuristics:
  - non-empty `contract_violations` means bug
  - regression worse than 20% means fail
  - improvement better than 10% means progress

Acceptance tests:

- [ ] skill instructions use JSON artifacts as the primary proof source
- [ ] diff helper flags non-empty `contract_violations` as failure
- [ ] diff helper reports >20% regressions and >10% improvements
- [ ] repo-specific observatory workflow is not stored only in `.claude/skills/`

Files that may be touched:

- `.agents/skills/perf-observatory/SKILL.md`
- `.claude/skills/perf-observatory.md`
- `tools/perf_baseline_diff.gd`
- `debug_exports/perf/*.json`
- `docs/02_system_specs/meta/ai_performance_observatory_design_brief.md`
- `docs/02_system_specs/meta/ai_performance_observatory_spec.md`

Files that must NOT be touched:

- gameplay/runtime ownership code unless a separate iteration explicitly requires it
- public API docs unless new public read surfaces are added

### Iteration 4 - Stress / Scale Presets

Goal:
Measure scale behavior explicitly instead of assuming current low density is representative.

What is done:

- add `StressDriver` for explicit scale scenarios
- support presets such as `mass_buildings`, `entity_swarm`, `long_traverse`, `speed_traverse`, `deep_mine`, and `dense_world`
- serialize a `stress` block into the same JSON artifact

Acceptance tests:

- [ ] `codex_stress_mode=mass_buildings codex_stress_count=200` runs headless and exits cleanly
- [ ] resulting JSON contains a `stress` block with mode, target count, actual count, and timing/frame metrics
- [ ] stress collection remains disabled outside explicit stress args
- [ ] stress tooling does not silently widen gameplay scope or bypass runtime-safe entrypoints

Files that may be touched:

- `core/debug/stress_driver.gd`
- `core/debug/perf_telemetry_collector.gd`
- `core/debug/runtime_validation_driver.gd`
- `scenes/world/game_world_debug.gd`
- `scenes/world/game_world.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` only if stress-driver ownership becomes normative
- `docs/00_governance/PUBLIC_API.md` only if a new public read accessor is added

Files that must NOT be touched:

- streaming architecture / scheduler semantics
- chunk publication and readiness contracts
- gameplay save/load data model

### Iteration 5 - Streaming Optimization Handoff (Separate Spec Required)

Goal:
Use the observatory as proof infrastructure for a future streaming optimization feature.

What is done:

- no observatory runtime code changes by default
- create or refine a separate streaming optimization spec before implementation work begins there
- define before/after metrics that observatory artifacts must prove for that future spec

Acceptance tests:

- [ ] a separate approved streaming optimization spec exists before optimization code starts
- [ ] observatory can report before/after metrics for that future spec without schema changes

Files that may be touched:

- future streaming optimization spec documents only

Files that must NOT be touched:

- observatory implementation code under this iteration
- streaming runtime code without the separate approved spec

## Verification recipe for implementation

Headless perf run:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_world_seed=12345 codex_quit_on_perf_complete
```

Scenario-selective runtime proof:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,room,power,mining codex_world_seed=12345 codex_quit_on_perf_complete
```

Stress proof:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_stress_mode=mass_buildings codex_stress_count=200 codex_world_seed=12345 codex_quit_on_perf_complete
```

## Out-of-scope

- rewriting streaming architecture in this feature
- changing chunk publication/readiness contracts as part of observatory alone
- creating a second standalone profiler subsystem
- making `.claude/skills/` the sole source of repo-specific observatory workflow
- using design-brief Iteration 5 as permission to optimize streaming without a separate approved spec
