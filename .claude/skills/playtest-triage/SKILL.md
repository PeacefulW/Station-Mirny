---
name: playtest-triage
description: >
  Convert raw Station Mirny playtest notes into prioritized actionable tasks
  with likely root cause, routing hints, and acceptance checks. Use when the
  user shares "заметки плейтеста", "playtest feedback", "bug list cleanup",
  "что из этого важнее", or a mixed pile of complaints about feel, bugs,
  pacing, UI clarity, or content confusion that needs to be turned into clean work.
disable-model-invocation: true
---

# Playtest Triage

Use this skill for sorting messy player feedback into real next actions.

This skill helps the agent separate bugs, balance problems, onboarding gaps,
content issues, and atmospheric misses so a playtest dump becomes an ordered set
of tasks instead of an undifferentiated wall of complaints.

## Read first

- `docs/00_governance/AI_PLAYBOOK.md`
- `docs/00_governance/WORKFLOW.md`
- `docs/01_product/GAME_VISION_GDD.md`
- `docs/01_product/NON_NEGOTIABLE_EXPERIENCE.md`

## What this skill does

1. Normalize each note into symptom, player impact, context, and likely domain.
2. Separate "bug", "balance", "UI/readability", "content gap", and "needs more evidence".
3. Prioritize by player harm, recurrence, blocker risk, and conflict with core
   product pillars.
4. Hand each actionable note to the right follow-up skill or prompt shape.

## Default workflow

1. Break the notes into distinct observations; do not let one vague paragraph
   hide three different problems.
2. For each observation, ask what the player actually experienced and what they
   could not do, understand, or feel.
3. Classify the note by domain and severity.
4. Connect it to Station Mirny intent: survival pressure, sanctuary contrast,
   readability under stress, progression rhythm, or content clarity.
5. Output the smallest useful next action: a fix prompt, a balance review, a UI
   wording task, a content task, or a request for more repro data.

## Typical smells

- the same symptom appears in different wording across multiple notes
- "this feels bad" is really a reproducible bug
- "this is unfair" is actually a copy/tutorial/readability problem
- one urgent blocker is buried under many low-severity taste notes
- feedback asks for a solution, but the evidence only supports identifying the problem

## Compose with other skills

- Load `bugfix-prompt-smith` when a note should become an implementation prompt.
- Load `balance-simulator` when the core problem is pacing, scarcity, or reward.
- Load `ui-copy-tone-keeper` or `ui-experience-composer` when confusion is UI or
  wording driven.
- Load `loading-lag-hunter` or `world-perf-doctor` when the complaint is about
  boot, loading, or interactive hitch.

## Boundaries

- Do not implement fixes directly from raw feedback unless the user asks.
- Do not flatten all notes into equal-priority backlog items.
- Do not confuse a desired solution with the validated problem.
