---
name: persistent-tasks
description: >
  Persistent task tracking for multi-iteration Station Mirny work. Use when a
  task spans multiple iterations, is being resumed, or needs an explicit
  handoff between sessions.
---

# Persistent Task Tracking

Use this skill when work spans multiple sessions or iterations.

## Core principle

Do not assume a single repo-global tracker file exists or is authoritative.
The source of truth is, in order:

1. the current user request or task brief
2. the approved spec, ADR, issue, or PR linked by the task
3. any tracker file that the user explicitly named or that is already being
   maintained for this exact task

A tracker is supplemental status, not canonical design truth.

## Preferred workflow

1. Read the current user request and the approved spec/ADR first.
2. If the task already has a tracker file, read it as status only.
3. Restate the current iteration, what is done, what is pending, and what docs
   still need checking.
4. Keep status notes short, factual, and tied to the approved scope.

## Minimal tracker template

If the user explicitly wants a tracker, or the task already has one, keep it
small and operational:

```md
# Task: [name]

Spec or source:
- [path or link]

Current iteration:
- [iteration name or "single-step task"]

Status:
- in_progress | completed | blocked

Done:
- [fact]

Remaining:
- [fact]

Canonical docs to verify:
- [doc path] - [why]

Latest proof:
- [verification command or artifact]

Latest closure report:
- [path, summary, or "pending"]
```

## Resume workflow

When the user says "continue", "resume", or asks where work stopped:

1. Read the task brief/spec.
2. Read any existing tracker tied to that task, if one exists.
3. Reconstruct the current state from completed proof and the last closure report.
4. Confirm the next scoped step before making edits.

## Updating task state

Update the tracker only when one of these is true:

- the task already uses a tracker file
- the user explicitly asked for persistent tracking
- the session is ending mid-iteration and a short handoff prevents rework

Record only:

- current scope
- completed proof-backed work
- pending work
- blockers
- outstanding canonical-doc checks

## Documentation debt in multi-session work

At each iteration boundary, explicitly note:

- which living canonical docs were checked
- which docs still need updates later
- whether the current iteration changed semantics enough to require immediate
  doc updates

Do not defer a required canonical-doc update just because a tracker exists.

## What this skill is not

- not a replacement for the spec
- not a replacement for canonical docs
- not a requirement to create `.claude/agent-memory/active-epic.md`

If no tracker exists and the user did not ask for one, keep the handoff inside
the normal closure report and current task context.

## Boundaries

- Do not invent a global tracker hierarchy by default.
- Do not copy large parts of the spec into a tracker.
- Do not treat scratchpad status as authoritative architecture.
