---
paths:
  - "AGENTS.md"
  - ".claude/**/*.md"
  - "docs/**/*.md"
---

# Documentation Governance Rules

- Documentation is the source of truth for architecture. Do not make code-driven architecture claims that contradict canonical docs.
- Follow the living document-routing order from `AGENTS.md` and `docs/README.md`.
- Feature work without an approved feature spec must stop at spec creation or refinement. Do not start implementation in the same step unless the user explicitly approved the spec.
- Closure reports must be Russian-first with canonical English terms in parentheses and must include concrete verification evidence.
- `not required` for canonical-doc updates is valid only with grep evidence against the relevant living docs.
- Do not expand scope while editing docs. Out-of-scope findings go into `Out-of-scope observations`.
