---
name: perf-observatory
description: >
  Compatibility mirror for the Station Mirny performance observatory workflow.
  Use when legacy Claude-style skill discovery expects `.claude/skills`, while
  the source of truth remains `.agents/skills/perf-observatory/SKILL.md`.
---

# Perf Observatory

Use `C:/Users/peaceful/Station Peaceful/Station Peaceful/.agents/skills/perf-observatory/SKILL.md`
as the source of truth.

Keep the workflow JSON-first:

1. Run or read a `codex_perf_test` artifact from `debug_exports/perf/*.json`.
2. Treat non-empty `contract_violations` as a bug.
3. Compare candidate versus baseline with `tools/perf_baseline_diff.gd`.
4. Mark regressions worse than 20% as fail and improvements better than 10% as
   progress.
5. Point the report at `boot`, `frame_summary`, `native_profiling`,
   `scenarios`, or `streaming` instead of free-form guesswork.

Do not maintain this mirror without updating the repo-local skill.
