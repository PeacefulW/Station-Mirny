---
description: "Station Mirny: safe plan-mode analysis before implementation"
argument-hint: "<task or feature idea>"
disable-model-invocation: true
---

Use plan mode for this Station Mirny task.

Task:
$ARGUMENTS

Follow this contract:
- Read `AGENTS.md`, `docs/00_governance/WORKFLOW.md`, and `docs/00_governance/ENGINEERING_STANDARDS.md` before code.
- If this is world/chunk/mining/topology/reveal/presentation work, read the relevant world/runtime ADRs and the current world spec in `docs/02_system_specs/world/` if the task uses it.
- If this is runtime-sensitive or extensible, also read `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md` and the relevant subsystem spec or ADR.
- Do not edit files yet.
- Produce a narrow implementation plan with scope, forbidden scope, allowed files, acceptance tests, and canonical-doc impact.
- If no approved feature spec exists for feature work, stop and recommend spec creation instead of implementation.
