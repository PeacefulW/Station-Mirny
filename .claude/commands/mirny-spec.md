---
description: "Station Mirny: create or refine a feature spec before code"
argument-hint: "<feature idea>"
disable-model-invocation: true
---

Create or refine a Station Mirny feature spec for:
$ARGUMENTS

Use `docs/00_governance/WORKFLOW.md` Phase B as the required template.

Requirements:
- Do not write gameplay code.
- Include design intent, performance/scalability contract, data contracts, required contract/API updates, iterations, allowed files, forbidden files, and concrete acceptance tests.
- For runtime-sensitive or extensible features, explicitly state runtime class, target scale, source of truth, write owner, derived/cache state, dirty unit, allowed sync work, escalation path, degraded mode, and forbidden shortcuts.
- End by asking for human approval of the spec before implementation.
