---
title: Agent Entry Contract
doc_type: agent_entrypoint
status: draft
owner: engineering
source_of_truth: false
version: 1.3
last_updated: 2026-04-09
related_docs:
  - docs/00_governance/DOCUMENT_PRECEDENCE.md
  - docs/00_governance/WORKFLOW.md
  - docs/00_governance/PUBLIC_API.md
  - docs/02_system_specs/world/DATA_CONTRACTS.md
  - docs/00_governance/ENGINEERING_STANDARDS.md
  - docs/00_governance/PERFORMANCE_CONTRACTS.md
---

# AGENTS.md

This file is the operational entrypoint for agents working in this repository.

It is **not** the architectural source of truth.
If this file conflicts with canonical documentation, follow:
- `docs/00_governance/DOCUMENT_PRECEDENCE.md`

## Purpose

This file exists to keep agents from:
- expanding the scope without approval
- scanning large parts of the repository "for context"
- turning a small task into a subsystem rewrite
- changing contracts or APIs silently
- continuing after the requested step is already complete

## Canonical rule

This file tells the agent **how to work**.
The canonical documents tell the agent **what is true**.

Use this file as a guardrail and routing layer.
Do not use it as a replacement for contracts, APIs, specs, or ADRs.

## Required reading order

### For every task
1. `AGENTS.md`
2. the user prompt or task brief
3. `docs/00_governance/WORKFLOW.md`
4. `docs/00_governance/PUBLIC_API.md`
5. the relevant feature spec for the task
6. the relevant contract document for the affected subsystem
7. only then the exact code files listed in the task/spec

If the task adds or changes runtime-sensitive, loading-sensitive, streaming, world,
AI, building, flora, or otherwise extensible gameplay behavior, also read before
opening code:
- `docs/00_governance/PERFORMANCE_CONTRACTS.md`
- `docs/00_governance/ENGINEERING_STANDARDS.md`

For those tasks, "it is only one tree/chunk/object right now" is not a valid
reason to skip scale-safe architecture.

### Skills — read before starting and before closing

This project uses three distinct skill locations:
- project-specific Station Mirny skills in `.agents/skills/`
- compatibility mirrors in `.claude/skills/`
- global/system Codex skills in `$CODEX_HOME/skills/` (or `~/.codex/skills/` when `CODEX_HOME` is unset)

**Do not treat all three locations as simultaneously mandatory.**
Pick the relevant skill source by concern and use the smallest valid set.

**For project-specific Station Mirny behavior in Codex:**
- use the relevant skills in `.agents/skills/`
- do not additionally load `.claude/skills/` for the same purpose unless the task explicitly involves mirror sync or legacy compatibility

**For Claude or legacy compatibility behavior:**
- `.claude/skills/` remains a mirror for tooling that still expects it
- the mirror is compatibility state, not a second source of truth

**For global/system behavior:**
- use relevant skills from `$CODEX_HOME/skills/` only for cross-repository workflows that are not owned by the Station Mirny project skill pack
- do not let a global skill override repo-specific guidance from `.agents/skills/`

**Project skill routing for this repository:**
- `.agents/skills/mirny-task-router/SKILL.md` — broad Station Mirny task routing and multi-skill composition
- `.agents/skills/persistent-tasks/SKILL.md` — multi-iteration or resume-sensitive work
- `.agents/skills/verification-before-completion/SKILL.md` — proof-based closure and documentation checks
- use the relevant domain specialist skill in `.agents/skills/` for performance, lore, UI, content, balance, localization, playtest, or prompt-shaping tasks

**Global Codex skill routing when installed in the active runtime:**
- `$CODEX_HOME/skills/spec-first-feature-work/SKILL.md` — if the task is a new feature idea or structural change without an approved spec
- `$CODEX_HOME/skills/world-contract-discipline/SKILL.md` — for world / chunk / mining / topology / reveal / presentation tasks
- `$CODEX_HOME/skills/save-load-change-check/SKILL.md` — for save/load and persistence-impact tasks
- `$CODEX_HOME/skills/docs-impact-check/SKILL.md` — before writing the closure report for any non-trivial change, and whenever semantics or docs may have changed

**Shared project memory for multi-iteration work:**
- use `.claude/agent-memory/active-epic.md` as the persistent task tracker regardless of runtime
- the tracker file is shared project state; it is not a reason to load both skill families

If you skip a skill that was relevant inside the active runtime's skill family, the closure report is incomplete.

### For world / chunk / mining / topology / reveal / presentation tasks
Required contract document:
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

### For architecture conflicts
Required decision document:
- `docs/00_governance/DOCUMENT_PRECEDENCE.md`

## Non-negotiable working rules

### 1. Documentation before code
Do not build the architecture from code.
Read the governing docs first.
Open code only after the relevant contract, API, and spec are known.

### 2. No broad exploration by default
Do not run broad repository audits, multi-file fishing expeditions, or parallel exploration unless the task explicitly asks for them.

If the task names a spec, a contract, an API surface, or a file list, stay inside that boundary.

### 3. One task, one step
Do only the requested step.
If the spec says "Iteration 1", do not implement Iteration 2 or 3.
If the user asks for a bug fix, do not redesign the subsystem.

### 4. Smallest valid change wins
Prefer the smallest change that satisfies the spec, contract, and acceptance tests.
Do not introduce a new manager, service, pipeline, or architecture layer unless the task explicitly requires it.

Smallest valid change does **not** mean "smallest code that works at today's tiny
content count". It means the smallest change that remains correct at the feature's
intended scale and does not knowingly push large future cost into the interactive path.

### 5. Performance law beats local convenience
For any runtime-sensitive or extensible change, explicitly determine before coding:
- runtime work class (`boot`, `background`, or `interactive`)
- intended growth case, not just the current sample size
- authoritative source of truth and single write owner
- what data is derived/cache versus authoritative
- the local dirty unit that is allowed to update synchronously
- the escalation path for larger work (`queue`, `worker`, `native cache`, `C++`, or another approved path)

If you cannot explain why the synchronous path stays bounded when content density grows,
the design is not ready to implement.

### 6. No silent contract or API drift
If the implementation changes a data contract, owner boundary, invariant, safe entry point, or API semantics, update the canonical docs in the same task.

At minimum, check whether the task requires updates to:
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

### 7. Stop when done
If the requested step is complete, the acceptance tests pass, and no blocker remains, stop.
Do not continue because there are nearby improvements, possible refactors, or architectural cleanup ideas.

## Default forbidden behavior

Unless the task explicitly asks for it, do **not**:
- fix adjacent issues
- do opportunistic refactors
- run a wide architecture re-audit
- run a perf audit just because the area looks hot
- open or modify files outside the allowed task/spec scope
- change public boundaries casually
- implement future iterations early
- replace the requested step with a bigger "ideal" solution
- justify synchronous runtime work with "currently there are only a few instances"
- add a new mutable mirror/cache without naming its authoritative owner and invalidation path

Anything noticed outside scope goes into:
- `Out-of-scope observations`

## Contract and API discipline

Before changing code, determine:
- which data layers are affected
- who owns write access to those layers
- which safe entry points are allowed
- whether the current task changes API semantics or only implementation details
- what runtime work class the change belongs to
- what the authoritative source of truth is, and what is only derived/cache state
- what dirty unit is allowed to execute synchronously
- what work must escalate to queue/worker/native instead of staying in the interactive path

If the task changes any of the following, update canonical docs before considering the task complete:
- layer ownership
- invariants
- mutation paths
- lifecycle semantics
- safe entry points
- public read semantics
- boot/readiness semantics

## Allowed code reading model

Read only what is needed to complete the current step:
- the files named in the task
- the files named in the feature spec
- the files named in the relevant contracts or API docs

Do **not** read half the repository for context.
The documentation should provide the context.

## Spec-first rule for feature work

If the task is a new feature or a structural change and there is no approved feature spec yet:
- do not start coding
- create or refine the spec first

Feature work should be implemented from a spec with:
- design intent
- affected contracts
- allowed files
- forbidden files
- acceptance tests
- explicit iteration boundaries

## What counts as a blocker

Treat the task as incomplete if any of the following is true:
- an acceptance test fails
- a crash, assert, or obvious regression appears in the touched path
- a documented owner boundary is violated
- a public contract or safe entry point is broken
- save/load behavior breaks in the touched path
- the task requires a performance constraint and the result clearly violates it
- a runtime-sensitive change has no credible scale path beyond today's tiny content count
- a new mutable cache/mirror was introduced without an explicit source of truth and write owner

## What does not justify continuing forever

These are **not** sufficient reasons to keep working once the requested step is done:
- "the API could be prettier"
- "the surrounding code could be cleaner"
- "there is another likely refactor nearby"
- "I found another contract gap"
- "I can imagine a more ideal architecture"

Record them as out-of-scope observations and stop.

## Minimal expected task output

Every completed task must end with a closure report.

Use this structure:

```md
## Closure Report

### Implemented
- ...

### Root cause
- ...

### Files changed
- ...

### Acceptance tests
- [ ] ... passed / failed (метод верификации)

### Contract/API documentation check
- Grep DATA_CONTRACTS.md для `changed_name`: [результат]
- Grep PUBLIC_API.md для `changed_name`: [результат]
- Секция "Required updates" в спеке: [есть/нет] — [статус]

### Out-of-scope observations
- ...

### Remaining blockers
- ...

### DATA_CONTRACTS.md updated
- ... / not required (с grep-доказательством)

### PUBLIC_API.md updated
- ... / not required (с grep-доказательством)
```

**Правило**: "not required" без grep-доказательства = невалидный closure report.
См. полный формат и процедуру в `docs/00_governance/WORKFLOW.md`.

## Practical prompt discipline

A good implementation prompt should specify:
- what to read first
- exact task scope
- what not to do
- allowed files
- forbidden files
- acceptance tests
- required closure report
- whether `DATA_CONTRACTS.md` and `PUBLIC_API.md` must be updated

If those constraints are missing, assume the narrower interpretation, not the broader one.

## Final principle

This repository already has enough governance to support disciplined execution.

The agent's job is not to improve everything.
The agent's job is to complete the current step cleanly, update the canonical docs when required, and stop.
