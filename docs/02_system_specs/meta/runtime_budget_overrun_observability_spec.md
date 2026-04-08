---
title: Runtime Budget Overrun Observability
doc_type: system_spec
status: approved
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-08
depends_on:
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../world/DATA_CONTRACTS.md
related_docs:
  - ../world/boot_performance_instrumentation_spec.md
  - quality_first_runtime_optimization_foundation.md
---

# Feature: Runtime Budget Overrun Observability

## Design Intent

The runtime already routes heavy background work through `FrameBudgetDispatcher`,
but the current logs still make it too hard to answer a narrow production
question:

- which budgeted background job is actually eating frame budget

This feature adds attribution for real budget overruns only.

The intent is:

- log only jobs that exceed their own per-step budget
- keep the success path quiet
- preserve existing interactive contract warnings
- surface repeat offenders through the existing canonical performance harnesses
- avoid any scheduler rewrite, new profiler subsystem, or always-on debug spam

## Public API impact

Current public APIs affected semantically:

- none required for the write path; instrumentation stays owner-internal

Required API/documentation outcome after implementation:

- `PUBLIC_API.md` does not need to expose internal overrun emitters
- if `WorldPerfMonitor` or another existing surface gains a new read-only recent
  offender accessor, that read API must be documented in `PUBLIC_API.md`
- no gameplay system may gain direct write access to performance summaries or
  cooldown state

## Data Contracts - new and affected

### New layer: Budget Overrun Observability

- What:
  - owner-managed runtime observability records for budgeted background jobs that
    exceed their configured per-step budget
- Where:
  - `core/autoloads/frame_budget_dispatcher.gd`
  - `core/systems/world/world_perf_probe.gd`
  - `core/autoloads/world_perf_monitor.gd`
  - `tools/perf_log_summary.gd` if summary extraction needs the new signal shape
- Owner (WRITE):
  - `FrameBudgetDispatcher` detects and emits over-budget job records
  - `WorldPerfProbe` owns canonical warning formatting and anti-spam/cooldown
  - `WorldPerfMonitor` owns recent-offender aggregation for summaries
- Readers (READ):
  - console/log review
  - `tools/perf_log_summary.gd`
  - existing perf/debug consumers that already read `WorldPerf` summaries
- Invariants:
  - within-budget background work must not emit a new per-step warning
  - every emitted over-budget record must include stable `job_id`, category,
    `used_ms`, `budget_ms`, and percent over budget
  - over-budget warnings must flow through the canonical `WorldPerfProbe` path
    rather than ad-hoc `push_warning()` calls in unrelated systems
  - repeated overruns from the same job must be cooldown-limited so one offender
    does not spam every frame
  - instrumentation must not change scheduler priorities, per-category budgets,
    total frame budget, or gameplay behavior
- Event after change:
  - none required beyond the existing log/instrumentation path
- Forbidden:
  - success-path "all good" logging
  - a second standalone perf subsystem
  - synthetic debug hacks that fabricate permanent overruns just to prove the
    warning path

### Affected layer: Visual Task Scheduling

- What changes:
  - `FrameBudgetDispatcher` emits attributed over-budget diagnostics for
    budgeted background jobs
- New invariants:
  - background overrun attribution is job-level, not only category-level
  - over-budget detection must not add per-frame noise for jobs that stay within
    budget
- Who adapts:
  - `FrameBudgetDispatcher`
  - `WorldPerfProbe`
  - `WorldPerfMonitor`
- What does NOT change:
  - scheduler ownership
  - category priorities
  - job execution order
  - total shared frame budget

## Iterations

### Iteration 1 - Over-Budget-Only Attribution For Budgeted Background Jobs

Goal:
Make real budgeted background offenders attributable without adding success-path
noise.

What is done:

- detect per-step budget overruns for budgeted background jobs in
  `FrameBudgetDispatcher`
- emit over-budget-only records through `WorldPerfProbe` or a minimal extension
  of its canonical warning/cooldown path
- include stable owner/job identity in every emitted overrun record:
  - `job_id`
  - `category`
  - `used_ms`
  - `budget_ms`
  - percent over budget
- preserve the current interactive contract-warning behavior unchanged
- surface recent offenders through `WorldPerfMonitor` and/or
  `tools/perf_log_summary.gd` so a proof run can show which jobs repeatedly
  exceeded budget
- keep the success path quiet: no new per-step warning when a job stays within
  budget

Acceptance tests:

- [ ] If the exact approved spec is still absent, this draft spec exists and no
  code changes are made in the same task.
- [ ] Within-budget background work creates no new per-step warning noise.
  Method: canonical fixed-seed perf proof plus grep for `WARNING`,
  `WorldPerf`, and `FrameBudget`.
- [ ] Any real over-budget budget-job warning emitted during proof contains
  `job_id`, category, `used_ms`, `budget_ms`, and percent over budget in one
  line, and the same offender is cooldown-limited instead of warning every
  frame.
- [ ] If the chosen fixed-seed proof run produces no real background budget
  overrun, the closure report states that honestly instead of fabricating a new
  ad-hoc tool or synthetic permanent debug path.
- [ ] Existing interactive contract warnings still behave as before.
- [ ] `WorldPerfMonitor` and/or `tools/perf_log_summary.gd` can identify recent
  recurring over-budget offenders from the saved log.
- [ ] No always-on success-path spam is added.
- [ ] Perf artifacts are saved under `debug_exports/perf/` and are actually read
  during verification.

Files that may be touched:

- `core/autoloads/frame_budget_dispatcher.gd`
- `core/systems/world/world_perf_probe.gd`
- `core/autoloads/world_perf_monitor.gd`
- `tools/perf_log_summary.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` only if observability
  ownership/invariants become normative there
- `docs/00_governance/PUBLIC_API.md` only if a new public read accessor is added

Files that must NOT be touched:

- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `core/systems/building/building_system.gd`
- `core/systems/power/power_system.gd`
- `scenes/world/game_world.gd`
- any new autoload registration
- any new standalone perf tooling when the same result can be achieved by
  extending the canonical harnesses

## Verification recipe for implementation

Boot proof:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_quit_on_boot_complete codex_world_seed=12345 *>&1 | Tee-Object -FilePath debug_exports/perf/boot_budget_obs_seed12345.log
```

Runtime proof:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_validate_runtime codex_validate_route=seam_cross codex_world_seed=12345 *>&1 | Tee-Object -FilePath debug_exports/perf/runtime_budget_obs_seam_cross_seed12345.log
```

Summary extraction:

```powershell
godot.exe --headless --path . --script res://tools/perf_log_summary.gd -- codex_perf_log=debug_exports/perf/runtime_budget_obs_seam_cross_seed12345.log
```

Mandatory log review:

```powershell
rg -n "ERROR|WARNING|WorldPerf|FrameBudget|CodexValidation" debug_exports/perf/runtime_budget_obs_seam_cross_seed12345.log
```

## Required contract and API updates after implementation

When this iteration is implemented, update:

- `DATA_CONTRACTS.md`
  - only if the project decides the new observability writer/reader ownership or
    invariants belong in the canonical world/runtime contract
- `PUBLIC_API.md`
  - only if a new public read-only summary accessor becomes part of the
    sanctioned API surface

Closure reports for implementation must include grep proof for those decisions.

## Out-of-scope

- HUD, overlay, or new debug scene work
- CSV export or external profiler integration
- a new autoload or separate perf subsystem
- scheduler architecture changes
- category-priority changes
- total frame-budget changes
- gameplay semantic changes
- refactors in `ChunkManager`, `BuildingSystem`, `PowerSystem`, or
  `WorldGenerator`
- baseline diff frameworks, autosave instrumentation, UI profiler work, or a
  full regression suite
