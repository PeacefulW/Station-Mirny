---
paths:
  - "AGENTS.md"
  - "CLAUDE.md"
  - ".claude/**/*.md"
  - "docs/**/*.md"
---

# Documentation Governance Rules

- Documentation is the source of truth for architecture. Do not make code-driven architecture claims that contradict canonical docs.
- Preserve document precedence from `docs/00_governance/DOCUMENT_PRECEDENCE.md`.
- Feature work without an approved feature spec must stop at spec creation or refinement. Do not start implementation in the same step unless the user explicitly approved the spec.
- Closure reports must be Russian-first with canonical English terms in parentheses and must include concrete verification evidence.
- `not required` for `DATA_CONTRACTS.md` or `PUBLIC_API.md` is valid only with grep evidence.
- Do not expand scope while editing docs. Out-of-scope findings go into `Out-of-scope observations`.
