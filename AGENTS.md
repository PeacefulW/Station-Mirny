---
title: Agent Entry Contract
doc_type: agent_entrypoint
status: draft
owner: engineering
source_of_truth: false
version: 1.0
last_updated: 2026-03-29
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

### 5. No silent contract or API drift
If the implementation changes a data contract, owner boundary, invariant, safe entry point, or API semantics, update the canonical docs in the same task.

At minimum, check whether the task requires updates to:
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

### 6. Stop when done
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

Anything noticed outside scope goes into:
- `Out-of-scope observations`

## Contract and API discipline

Before changing code, determine:
- which data layers are affected
- who owns write access to those layers
- which safe entry points are allowed
- whether the current task changes API semantics or only implementation details

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
- [ ] ... passed / failed

### Out-of-scope observations
- ...

### Remaining blockers
- ...

### DATA_CONTRACTS.md updated
- ... / not required

### PUBLIC_API.md updated
- ... / not required
```

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
