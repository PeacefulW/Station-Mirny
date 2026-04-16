---
name: perf-observatory
description: >
  Run Station Mirny observatory proofs, read `codex_perf_test` JSON artifacts,
  compare a candidate run against a baseline, and report contract violations,
  regressions, and improvements. Use when the user asks "запусти перф-тест",
  "сравни с baseline", "проверь регрессию", "benchmark", "perf test", or wants
  machine-readable performance diagnosis from `debug_exports/perf/*.json`.
---

# Perf Observatory

Use the repository-local observatory workflow. Treat the JSON artifact from
`PerfTelemetryCollector` as the primary proof source, not the console log, F11
overlay, or memory of a prior run.

## Read first

- `docs/02_system_specs/meta/ai_performance_observatory_spec.md`
- `docs/00_governance/PERFORMANCE_CONTRACTS.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

## Default workflow

1. Choose the proof source:
   - explicit run: launch the headless scene with `codex_perf_test`
   - existing artifact: inspect `debug_exports/perf/*.json`
2. Prefer the fixed-seed baseline at `debug_exports/perf/baseline_seed12345.json`
   unless the task explicitly names a different baseline.
3. Read the candidate JSON first. Confirm the expected blocks exist:
   `meta`, `boot`, `streaming`, `frame_summary`, `contract_violations`,
   `scenarios`, and `native_profiling`.
4. Treat non-empty `contract_violations` as a bug even if other metrics improve.
5. Run `tools/perf_baseline_diff.gd` when baseline comparison is needed:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tools/perf_baseline_diff.gd -- codex_perf_baseline=debug_exports/perf/baseline_seed12345.json codex_perf_candidate=debug_exports/perf/result.json
```

6. Use simple heuristics in the report:
   - regression worse than 20% = fail
   - improvement better than 10% = progress
   - non-empty `contract_violations` = fail
7. Point diagnosis at the JSON section that moved:
   - boot/readiness: `boot`
   - frame and budget pressure: `frame_summary`
   - native chunk/topology work: `native_profiling`
   - scenario proof outcome: `scenarios`
   - queue/timeline context: `streaming`
8. If runtime proof was not explicitly requested, do not invent extra Godot
   runs just to be exhaustive. Reuse the existing artifact and leave a manual
   handoff when human validation is still required.

## Sanctioned commands

Headless perf run:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_world_seed=12345 codex_quit_on_perf_complete
```

Selective validation run:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,room,power,mining codex_world_seed=12345 codex_quit_on_perf_complete
```

Baseline diff with explicit outputs:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tools/perf_baseline_diff.gd -- codex_perf_baseline=debug_exports/perf/baseline_seed12345.json codex_perf_candidate=debug_exports/perf/result.json codex_perf_output_prefix=observatory_diff
```

## Boundaries

- Do not treat console text as the primary proof source when the JSON artifact
  already contains the needed facts.
- Do not add always-on diagnostics, new gameplay APIs, or new ownership paths as
  part of observatory review.
- Do not let `.claude/skills/perf-observatory.md` become the only maintained
  copy of this workflow; it is a compatibility mirror at most.
