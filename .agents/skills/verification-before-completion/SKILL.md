---
name: verification-before-completion
description: >
  Enforces proof-based task completion for Station Mirny. Use this skill whenever
  you are about to close a task, claim acceptance tests passed, or write a
  closure report.
---

# Verification Before Completion

Use this skill whenever work is approaching completion.

## Core rule

Do not write `passed` in a closure report unless you ran a concrete verification
command in this session and saw the output.

Reasoning, confidence, rereading your own diff, or quoting earlier memory does
not count as proof.

## User-facing report rule

The closure report is user-facing and must be written in Russian with canonical
English terms in parentheses. Introduce important technical terms on first use
as `russian term (english term)`.

## Verification modes

Choose one of these modes for each acceptance test:

1. `static verification`
   - grep, file reads, structured diff checks, syntax/resource checks, broken-link scans
   - mandatory for every task
2. `manual human verification`
   - visual/runtime/perf results that were not explicitly assigned to the agent
   - default for Godot/editor/play-session checks unless the task explicitly asks
     you to run them
3. `explicit agent-run runtime verification`
   - only when the user, task brief, or spec explicitly requires the agent to
     run the runtime harness itself

## What counts as proof

- a validation or lint command
- a grep/search command with useful output
- a file read that shows the final state
- a structured artifact read such as JSON, TRES, or log output
- a broken-link or reference scan for documentation work

## What does not count as proof

- "the logic looks correct"
- "I already changed it"
- "the diff is obvious"
- "it should pass"

## Required workflow before the closure report

1. List the acceptance tests for the current task.
2. Map each test to a concrete verification method.
3. Run the verification commands and inspect the output.
4. Perform the mandatory canonical-documentation check.
5. Only then write the closure report.

## Canonical documentation check (mandatory)

Every non-trivial task must verify whether living canonical docs stayed accurate.
Do not assume the old contract/API files still exist.

### How to do it

1. Collect the changed names, removed paths, renamed files, and semantics that
   moved in this task.
2. Identify the living canonical docs for this subsystem. Typical sources are:
   - `AGENTS.md`
   - `docs/00_governance/WORKFLOW.md`
   - `docs/00_governance/ENGINEERING_STANDARDS.md`
   - `docs/00_governance/PROJECT_GLOSSARY.md`
   - the relevant subsystem spec in `docs/02_system_specs/`
   - the relevant ADR in `docs/05_adrs/`
   - `docs/README.md` when path/index references matter
3. Grep those docs for the changed names or removed paths.
4. If the matches are stale, update them in the same task.
5. Record the grep evidence in the closure report.

### Closure report evidence example

```md
### Proverka kanonicheskoi dokumentatsii (Canonical documentation check)
- Grep `docs/README.md` for `old/path.md`: 2 matches - updated
- Grep `docs/02_system_specs/meta/save_and_persistence.md` for `SaveManager`: 3 matches - still accurate
- Spec "Required updates" section: not present - no extra doc debt
```

If a relevant doc has zero matches, say so explicitly. Do not write "not required"
without grep evidence.

## Static verification examples

- symbol exists: `rg -n "func save_game" core/autoloads/save_manager.gd`
- localization key wired: `rg -n "ui\\.inventory\\." data translations core scenes`
- deleted path removed from docs: `rg -n "removed/legacy/path.md" AGENTS.md docs .agents`
- broken markdown links in docs: run a repository link check and record the result

## When runtime checks are not in scope

If the task did not explicitly ask the agent to run Godot, headless scenes, or
perf harnesses, leave those items as `manual human verification required` with
a concrete handoff.

Use `BLOCKED` only when the task explicitly required agent-run runtime proof and
the environment prevented it.

## Boundaries

- Never mark `passed` without session-local evidence.
- Never skip the canonical-documentation grep step on non-trivial work.
- Never assume deleted docs or removed scene paths are still the contract.
- Never replace a concrete human handoff with a guessed runtime result.
