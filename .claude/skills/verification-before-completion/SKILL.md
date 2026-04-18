---
name: verification-before-completion
description: >
  Compatibility mirror for the Station Mirny proof-based closure workflow.
  Use `.agents/skills/verification-before-completion/SKILL.md` as the source of truth.
---

# Verification Before Completion

Use `.agents/skills/verification-before-completion/SKILL.md` as the source of truth.

Mirror summary:

1. Never mark `passed` without evidence from this session.
2. Always include a closure report.
3. Always include grep evidence for the relevant living canonical docs.
4. Use manual human verification for runtime checks unless the task explicitly
   asked the agent to run them.
