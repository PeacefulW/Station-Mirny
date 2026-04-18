---
title: Workflow - Task Execution Order
doc_type: governance
status: approved
owner: engineering
source_of_truth: true
version: 1.2
last_updated: 2026-04-18
related_docs:
  - ENGINEERING_STANDARDS.md
  - PROJECT_GLOSSARY.md
  - ../README.md
  - ../02_system_specs/README.md
  - ../02_system_specs/meta/system_api.md
  - ../02_system_specs/meta/event_contracts.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../02_system_specs/meta/commands.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# WORKFLOW - Order of Work for Any Task

> This document is mandatory for every agent and developer.
> Breaking this order means the work is considered undisciplined.

## Rule #0: Documentation is the source of truth, not code

An agent must not build its understanding of the architecture from code.
Read living canonical docs first, then open code.

### Base reading order

1. `AGENTS.md`
2. the user prompt or task brief
3. `docs/README.md`
4. `docs/00_governance/WORKFLOW.md`
5. `docs/00_governance/ENGINEERING_STANDARDS.md`
6. `docs/00_governance/PROJECT_GLOSSARY.md`
7. the relevant approved spec or ADR
8. only after that, the concrete code files named by the task

### Additional reading for runtime-sensitive tasks

If the task touches runtime, loading, streaming, save/load, world,
simulation, or any other scalable behavior, also read before code:
- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- the relevant ADR from the world/runtime stack, if it actually applies

### Additional reading for feature / boundary-sensitive tasks

If the task:
- adds a new feature
- changes a public/system boundary
- introduces a new safe entrypoint
- introduces a new important event
- changes a payload, save shape, command result, or another boundary schema
- adds a new mutation path between systems, tools, or mods

then, before opening code, also read and cross-check:
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/event_contracts.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/commands.md`

If the required boundary is missing there:
- you may not silently route around it through a private/internal method, raw
  `Dictionary`, or ad-hoc mutation path
- within the same task, you must explicitly decide which canonical boundary doc
  needs to be updated

## Rule #1: Do not start broad repository exploration by default

It is forbidden to scan the repository "to understand context" if the task
already names the spec, ADR, subsystem surface, or file list.

If the task does not name a file:
- find the relevant spec or ADR
- determine the owner boundary and safe path from living canonical docs
- only then open the minimum code needed

If neither the task nor the docs let you localize the file without a broad
scan, stop and ask the human to clarify the task.

## Before any code work

1. Read the relevant docs and record:
   - the authoritative source of truth
   - the single write owner
   - the derived/cache state
   - the dirty unit
   - the runtime work class: `boot`, `background`, or `interactive`
2. Read the current feature spec or bug brief, if one exists.
3. For a feature / boundary-sensitive task, record:
   - which existing safe path from `system_api.md`, `commands.md`,
     `event_contracts.md`, or `packet_schemas.md` must be used
   - which surface is missing and which canonical doc must be updated
   - what is forbidden outside the documented API / command / event / schema
4. Determine the allowed files and forbidden files.
5. Only then open code.

If an approved feature spec does not exist for a new feature or structural
change, do not code. Create the spec first.

## Implementation rules

### 1. One task, one step

Do not implement future iterations early.
Do not turn a bug fix into a refactor of the whole subsystem.

### 2. Minimum sufficient change

Prefer the smallest change that:
- satisfies the spec
- preserves owner boundaries
- does not break the scale path
- closes the acceptance tests

### 3. Performance law

For runtime-sensitive and extensible changes, determine in advance:
- the target scale / density
- why the sync path remains bounded
- what must move to a queue / worker / native path

The phrase "the object count is still small" is never valid performance
justification.

### 4. No silent documentation drift

If any of the following changed:
- ownership
- invariants
- mutation paths
- lifecycle semantics
- save/load semantics
- safe entry points
- public read semantics
- command set
- event names, payloads, emitters, or listener-facing guarantees
- packet / payload / save / result schemas at boundaries
- extension seams

then the relevant canonical docs must be updated in the same task.

For boundary-sensitive tasks, this means checking and updating if needed:
- `system_api.md`
- `event_contracts.md`
- `packet_schemas.md`
- `commands.md`

## Allowed code-reading model

Read only what the current step needs:
- files named by the task
- files named by the spec
- files named by, or logically implied from, the relevant spec / ADR

Do not open half the repository "just in case."

## Acceptance tests and verification

### Main principle

You may write `passed` only after a real verification command in this session.

Acceptable methods:
- grep/search
- reading the final file state
- parse/syntax/static checks
- a validation script
- an explicit runtime run, if it was explicitly assigned

What does not count as proof:
- "the logic looks correct"
- retelling your own diff without a command
- memory from a previous session

### Verification modes

1. `static verification`
   - mandatory for every task
2. `manual human verification`
   - the honest default for visual/runtime/perf outcomes when no runtime run
     was explicitly requested
3. `explicit agent-run runtime verification`
   - only if the task, the human, or the acceptance test explicitly requires it

## Closure report

Every completed task ends with a user-facing closure report written in Russian,
with canonical English terms in parentheses.

Use this structure:

```md
## Closure Report

### Implemented
- ...

### Root Cause
- ...

### Files Changed
- ...

### Acceptance Tests
- [ ] ... passed / failed / manual human verification required (verification method)

### Proof Artifacts
- Static verification: ...
- Manual human verification: [required / not required]
- Suggested human check: ...

### Performance Artifacts
- Static verification: ...
- Explicit agent-run runtime verification: ... / not run in this task per policy
- Manual human verification: [required / not required]
- Suggested human check: ...

### Canonical Documentation Check
- Grep `<doc path>` for `<changed_name or keyword>`: [N matches, lines X, Y - updated / still accurate / 0 matches]
- "Required updates" section in spec/ADR: [present / absent] - [completed / not applicable / deferred]

### Out-of-Scope Observations
- ...

### Remaining Blockers
- ...

### Canonical Docs Updated
- `<doc path>` - updated / not required (with grep proof)
```

You must still render the actual user-facing report in Russian. The template
above defines the required structure in English only.

Writing `not required` without grep proof is forbidden.

## Bug-fix order

1. Read the relevant spec/ADR and determine which invariant or safe path is
   broken.
2. Find the minimum owner-boundary file responsible for the problem.
3. Fix only the current step.
4. Run the acceptance checks.
5. Update the relevant canonical docs if the documented semantics changed.
6. Write the closure report.

## Optimization order

1. Read the relevant spec/ADR and ADR-0001.
2. Classify the work as `boot`, `background`, or `interactive`.
3. Record the target scale, dirty unit, and escalation path.
4. Prove that the hot path remains bounded.
5. Do not hide a missing architecture boundary behind "it is fast for now."

## How to prepare an implementation prompt

A good prompt must include:
- what to read first
- what exactly to do
- what not to do
- which boundary docs (`system_api.md`, `event_contracts.md`,
  `packet_schemas.md`, `commands.md`) must be checked before code
- allowed files
- forbidden files
- acceptance tests
- the closure-report requirement
- the doc-check requirement for relevant canonical docs

Template:

```md
## Required reading before you start
- [governing docs]

## Task
- [one concrete step]

## Context
- [which problem this solves]

## Boundary contract check
- Existing safe path to use: [...]
- Which of `system_api.md` / `event_contracts.md` / `packet_schemas.md` / `commands.md` must be checked: [...]
- If new public API / event / schema / command appears: update the corresponding canonical doc in the same task

## Performance / scalability guardrails
- Runtime class: [...]
- Target scale / density: [...]
- Source of truth + write owner: [...]
- Dirty unit: [...]
- Escalation path: [...]

## Scope - what to do
- [...]

## Scope - what NOT to do
- [...]

## Files that may be touched
- [...]

## Files that must NOT be touched
- [...]

## Acceptance tests
- [ ] [...]

## Result format
- Closure report following the format from WORKFLOW.md
- Check and update relevant canonical docs when needed
```

## Anti-patterns

Forbidden by default:
- scanning the repository instead of reading docs
- coding without an approved spec for a new feature
- doing multiple iterations in a row without closing the current one
- writing subjective acceptance criteria
- fixing adjacent problems
- changing documented semantics without updating docs
- adding a new public API / command / event / boundary schema without updating
  the corresponding canonical meta-doc
- using another system's private/internal method when a documented safe path
  already exists
- writing `passed` without proof
- writing `not required` about documentation without grep confirmation

## Checklist: "Can coding start?"

- [ ] `AGENTS.md` read?
- [ ] `docs/README.md` read?
- [ ] `WORKFLOW.md` read?
- [ ] `ENGINEERING_STANDARDS.md` and `PROJECT_GLOSSARY.md` read?
- [ ] relevant spec/ADR read?
- [ ] relevant `system_api.md` / `event_contracts.md` /
      `packet_schemas.md` / `commands.md` checked for feature /
      boundary-sensitive work?
- [ ] acceptance tests concrete and verifiable?
- [ ] target scale / dirty unit / escalation path defined for
      runtime-sensitive work?
- [ ] if a new API / event / schema / command appears, is the update to the
      corresponding canonical doc included in scope?
- [ ] allowed files and forbidden files named?

If even one answer is "no," coding may not start.
