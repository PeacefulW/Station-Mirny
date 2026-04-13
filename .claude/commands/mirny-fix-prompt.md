---
description: "Station Mirny: convert a vague bug into a narrow implementation prompt"
argument-hint: "<bug report>"
disable-model-invocation: true
---

Convert this Station Mirny bug report into a narrow implementation prompt:
$ARGUMENTS

Use `bugfix-prompt-smith` and follow `docs/00_governance/WORKFLOW.md`.

The output must include:
- Required reading order.
- Exact task and context.
- Contract or invariant likely violated.
- Performance/scalability guardrails if runtime-sensitive.
- Scope: what to do.
- Scope: what not to do.
- Files allowed to touch.
- Files forbidden to touch.
- Acceptance tests.
- Required closure report and contract/API grep evidence.

Do not implement the fix.
