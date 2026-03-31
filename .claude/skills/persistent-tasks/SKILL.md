---
name: persistent-tasks
description: >
  Persistent task tracking between sessions for Station Mirny. Solves the problem of
  context loss when a long feature implementation spans multiple Claude sessions.
  Use this skill when: starting work on a multi-iteration feature, resuming work after
  a previous session, the user says "продолжи", "где мы остановились", "что осталось",
  "continue", "resume", "status", or when beginning any task from docs/02_system_specs/
  that has multiple iterations. Also use when you notice the current task has more than
  3 steps and might not fit in one session.
---

# Persistent Task Tracking

Station Mirny features are broken into iterations (WORKFLOW.md Phase B), and each iteration
has acceptance tests, file lists, and contract updates. When a session ends mid-feature,
the next session starts with zero context. The agent re-reads docs, guesses where things
were left off, and sometimes redoes work or skips steps.

This skill solves that by maintaining a persistent state file that survives between sessions.

## How it works

Task state lives in `.claude/agent-memory/active-epic.md` — a single markdown file that
tracks the current feature being implemented. This file is the agent's persistent memory.

## Starting a new epic

When beginning work on a multi-iteration feature, create the tracking file:

```markdown
# Epic: [Feature Name]

**Spec**: docs/02_system_specs/[spec_file].md
**Started**: [date]
**Current iteration**: 1
**Total iterations**: [N]

## Documentation debt

Track required documentation updates from the spec's "Required contract and API updates"
section. This section is filled in at epic creation and checked at every iteration close.

- [ ] DATA_CONTRACTS.md — [what to update, copied from spec]
- [ ] PUBLIC_API.md — [what to update, copied from spec]
- **Deadline**: after iteration [N] (from spec) or "each iteration if semantics change"
- **Status**: pending | done

## Iterations

### Iteration 1 — [name from spec]
**Status**: in_progress | completed | blocked
**Started**: [date]
**Completed**: [date or —]

#### Acceptance tests
- [ ] [test 1 from spec]
- [ ] [test 2 from spec]

#### Doc check
- [ ] Grep DATA_CONTRACTS.md for changed names — [result]
- [ ] Grep PUBLIC_API.md for changed names — [result]
- [ ] Documentation debt section reviewed — [still pending / updated / not due yet]

#### Files touched
- [file 1] — [what changed]

#### Closure report
[paste the closure report here when done, or "pending"]

#### Blockers
- [any blockers, or "none"]

---

### Iteration 2 — [name from spec]
**Status**: pending
[filled in when this iteration begins]
```

## Resuming work

When the user asks to continue, or when you're starting a session that involves an existing
feature:

1. **Read `.claude/agent-memory/active-epic.md`** — this tells you where things stand
2. **Find the current iteration** — the one marked `in_progress` or the first `pending`
3. **Read the spec** — the spec path is in the epic file header
4. **Read DATA_CONTRACTS.md and PUBLIC_API.md** — standard pre-task reading
5. **Report status to the human** before doing anything:

```
Resuming Epic: Temperature System
Current iteration: 2 of 4 — "Тепловые источники"
Previous iteration 1 completed on [date]:
  - [x] TemperatureLayer exists in DATA_CONTRACTS.md
  - [x] BaseTemperatureResource created
  Closure report: filed

This iteration's scope:
  - Add HeatSourceComponent
  - Register in BuildingFactory
  - EventBus: heat_source_activated / heat_source_deactivated

Ready to begin?
```

## Updating the epic file

Update `active-epic.md` at these moments:

1. **When an iteration starts** — mark status as `in_progress`, record date
2. **When an acceptance test passes** — check the box, note verification method
3. **When a file is changed** — add to "Files touched" with brief description
4. **When a closure report is written** — paste it into the iteration section
5. **When an iteration completes** — mark status as `completed`, record date, and check documentation debt
6. **When blocked** — mark status as `blocked`, describe the blocker

### Documentation debt check at iteration close

Every time you complete an iteration, look at the "Documentation debt" section:

- If this is the **last iteration** and debt items are still unchecked — **do them now**,
  in this same task. Do not close the iteration without clearing the debt.
- If this is a **middle iteration** but your code changed the semantics of something
  referenced in DATA_CONTRACTS.md or PUBLIC_API.md — update the docs now, and check the
  relevant debt item.
- If documentation debt remains pending and is not yet due — leave it, but confirm by
  writing "Doc debt reviewed — not due until iteration [N]" in the iteration's Doc check.

This is the safety net for multi-session epics. Each session sees the debt. The last session
must clear it. No session can claim "not required" without checking.

Do NOT wait until the end of the session to update. Update as you go — if the session
crashes or times out, the file should reflect the last known good state.

## When the epic is done

When all iterations are completed:

1. Move the file to `.claude/agent-memory/completed/[feature-name].md`
2. Create a brief summary in `.claude/agent-memory/active-epic.md`:

```markdown
# No active epic

Last completed: [Feature Name] ([date])
See: .claude/agent-memory/completed/[feature-name].md
```

This way, the next session knows there's no ongoing work.

## Multiple features

If the human asks to switch to a different feature mid-epic:

1. Save current state (make sure `active-epic.md` is up to date)
2. Rename to `.claude/agent-memory/paused/[feature-name].md`
3. Create new `active-epic.md` for the new feature
4. When the human wants to resume the paused feature, swap them back

## What this file is NOT

- It's not a replacement for the feature spec — the spec is the source of truth for design
- It's not a replacement for DATA_CONTRACTS.md — contracts are the source of truth for data
- It's not a task management system — it tracks ONE active feature's implementation progress

It's a memory aid. It tells the next session: "here's what was done, here's what's left,
here's what's blocked." Nothing more.

## Integration with existing governance

This skill works within the project's existing structure:

- The spec (WORKFLOW.md Phase B) defines WHAT to do
- The governance docs define HOW to do it
- This skill tracks WHERE you are in doing it

The epic file references the spec but doesn't duplicate it. Acceptance tests are copied
from the spec so progress can be tracked, but the spec remains authoritative.

## Directory structure

```
.claude/agent-memory/
├── active-epic.md          ← current feature in progress (or "no active epic")
├── completed/              ← finished epics for reference
│   ├── power-grid-v2.md
│   └── temperature-system.md
└── paused/                 ← features put on hold
    └── trading-system.md
```

Create the `completed/` and `paused/` directories only when needed, not preemptively.
