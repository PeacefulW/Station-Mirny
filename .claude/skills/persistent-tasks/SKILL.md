---
name: persistent-tasks
description: >
  Compatibility mirror for the Station Mirny persistent task tracking workflow.
  Use `.agents/skills/persistent-tasks/SKILL.md` as the source of truth.
---

# Persistent Task Tracking

Use `.agents/skills/persistent-tasks/SKILL.md` as the source of truth.

Mirror summary:

1. Do not assume a single repo-global tracker file is authoritative.
2. Prefer the current task brief, approved spec/ADR, and any tracker already
   tied to this exact task.
3. A tracker is supplemental status, not canonical design truth.
4. If no tracker exists and the user did not ask for one, keep the handoff in
   the closure report instead of inventing new tracker structure.
