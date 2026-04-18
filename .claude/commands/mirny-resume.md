---
description: "Station Mirny: resume the current active epic safely"
argument-hint: "[optional focus]"
disable-model-invocation: true
---

Resume Station Mirny work using the current task brief and any existing task tracker.

Optional focus:
$ARGUMENTS

Steps:
- Read `.claude/agent-memory/active-epic.md` if it exists and is the tracker for this task.
- Identify the current in-progress or pending iteration.
- Read the referenced spec.
- Read `AGENTS.md`, `docs/00_governance/WORKFLOW.md`, and `docs/00_governance/ENGINEERING_STANDARDS.md`.
- Read relevant living canonical docs before opening code.
- Report the current task, iteration, scope, acceptance tests, known blockers, and pending canonical-doc checks.
- Do not code until the resumed scope is clear.
