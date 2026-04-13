---
paths:
  - "core/systems/world/**/*.gd"
  - "core/runtime/**/*.gd"
  - "scenes/world/**/*"
  - "scenes/ui/world_lab.gd"
  - "docs/02_system_specs/world/**/*.md"
---

# World Runtime Rules

- Before code, read `AGENTS.md`, `docs/00_governance/WORKFLOW.md`, `docs/00_governance/PUBLIC_API.md`, and `docs/02_system_specs/world/DATA_CONTRACTS.md`.
- For runtime-sensitive world, chunk, topology, reveal, streaming, flora, or presentation changes, also read `docs/00_governance/PERFORMANCE_CONTRACTS.md` and `docs/00_governance/ENGINEERING_STANDARDS.md`.
- Classify runtime work as `boot`, `background`, or `interactive` before proposing a patch.
- Interactive paths may only do bounded local work, dirty marking, and queue handoff. Do not introduce full chunk redraws, full topology rebuilds, or loops over all loaded chunks.
- Use only safe entry points from `PUBLIC_API.md`. If an operation is not listed there, stop and ask instead of discovering a private workaround in code.
- Any changed owner boundary, invariant, mutation path, lifecycle semantic, safe entry point, or public read semantic must update canonical docs in the same task.
