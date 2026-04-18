---
description: "Station Mirny: prepare the required closure report with proof"
argument-hint: "<what changed>"
disable-model-invocation: true
---

Prepare a Station Mirny closure report for:
$ARGUMENTS

Before writing the report:
- Use `verification-before-completion`.
- List acceptance tests and map each to static verification, manual human verification, or explicit agent-run runtime verification.
- Run concrete verification commands for every test marked `passed`.
- Grep the relevant living canonical docs and ADRs for changed function, constant, signal, entrypoint, hook, or workflow names.
- Check the relevant spec's `Required updates` section if a spec exists.

Report in Russian with canonical English terms in parentheses, using the exact closure format from `docs/00_governance/WORKFLOW.md`.
