---
description: "Station Mirny: resume the current active epic safely"
argument-hint: "[optional focus]"
disable-model-invocation: true
---

Resume Station Mirny work using `.claude/agent-memory/active-epic.md`.

Optional focus:
$ARGUMENTS

Steps:
- Read `.claude/agent-memory/active-epic.md`.
- Identify the current in-progress or pending iteration.
- Read the referenced spec.
- Read `AGENTS.md`, `docs/00_governance/WORKFLOW.md`, and `docs/00_governance/PUBLIC_API.md`.
- Read relevant contract docs before opening code.
- Report the current epic, iteration, scope, acceptance tests, known blockers, and documentation debt.
- Do not code until the resumed scope is clear.
