---
name: perf-observatory
description: >
  Compatibility mirror for the Station Mirny performance observatory workflow.
  Use when legacy Claude-style skill discovery expects `.claude/skills`, while
  the source of truth remains `.agents/skills/perf-observatory/SKILL.md`.
---

# Perf Observatory

Use `.agents/skills/perf-observatory/SKILL.md`
as the source of truth.

Keep the workflow artifact-first:

1. Read the current task artifact, structured log, or repo-local perf note first.
2. Treat explicit budget or contract violations as a bug.
3. Compare candidate versus baseline only when both artifacts actually exist.
4. Point the report at the exact metric or artifact section that moved.
5. Do not quote deleted harness commands or removed scene paths as current truth.

Do not maintain this mirror without updating the repo-local skill.
