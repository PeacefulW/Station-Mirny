---
name: perf-observatory
description: >
  Inspect Station Mirny performance artifacts and compare candidate results
  against a baseline when the task explicitly provides JSON exports, structured
  logs, or a named perf harness.
---

# Perf Observatory

Use this skill for proof-based performance review.

Treat repository artifacts as the source of truth: JSON exports, structured
logs, existing perf notes, or the current task's named harness. Do not assume
deleted observatory docs, removed scene paths, or retired harness commands
still exist.

## Read first

- `docs/00_governance/ENGINEERING_STANDARDS.md`
- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- the relevant subsystem spec or ADR for the workload under review
- the current task brief naming the artifact, baseline, or harness

## Default workflow

1. Choose the proof source already available in the task: JSON artifact,
   structured report, existing perf note, or repository probe output.
2. If a baseline is provided, compare against that exact baseline. Do not invent
   a default baseline unless the repository already ships one and the task
   clearly uses it.
3. Treat explicit contract or budget violations as failures even if averages
   improve.
4. Point the diagnosis at the exact section, metric, or artifact field that
   moved.
5. If the repository does not currently ship a runnable harness for the task, do
   not fabricate a dead command. Report the missing harness and continue with
   artifact-based analysis.

## Sanctioned checks

- read the artifact directly
- grep for the metric, marker, or harness name before citing it
- inspect `core/runtime/world_perf_probe.gd` when the task is about the current
  world perf probe path
- use only commands and harnesses that are present in the repo or explicitly
  supplied by the task

## Reporting guidance

- name the baseline and candidate artifacts you actually compared
- separate regressions, improvements, and unknowns
- call out missing proof when the task asks for a comparison but only one
  artifact exists
- prefer exact metrics over narrative guesses

## Boundaries

- Do not quote deleted docs or removed scene paths as current truth.
- Do not treat console memory from a prior run as proof.
- Do not add always-on diagnostics as part of observatory review.
