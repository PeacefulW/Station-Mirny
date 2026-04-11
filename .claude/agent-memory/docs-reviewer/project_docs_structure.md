---
name: Station Mirny documentation structure
description: Layered docs architecture under docs/ with YAML frontmatter, 8 layers (00-06 + 99_archive), known indexing gaps
type: project
---

Station Mirny uses a layered documentation architecture under `docs/` with 8 folders (00_governance through 06_templates, plus 99_archive).

All docs use YAML frontmatter with fields: title, doc_type, status, owner, source_of_truth, version, last_updated, and optional depends_on/related_docs.

**Why:** The project migrated from flat root markdown files to a structured layered system with explicit precedence rules. Governance > ADRs > system specs > product > content > execution.

**How to apply:** When reviewing docs, check frontmatter consistency across all fields. Cross-reference links use absolute Windows paths with backslashes in some markdown files — this breaks on Linux/macOS. Watch for these recurring issues:

- `docs/00_governance/WORKFLOW.md` has NO frontmatter (broken convention)
- `docs/README.md` and `docs/02_system_specs/README.md` are missing ~20 newer world specs (boot_chunk_*, streaming_redraw_budget, chunk_visual_pipeline_rework, mountain_reveal_*, world_lab_spec, etc.)
- `CLAUDE.md` and `ENGINEERING_STANDARDS.md` both cite non-existent constants `PRIME_A`/`PRIME_B`; real hash in `core/systems/world/chunk.gd::_hash32_xy` uses literal primes 374761393 / 668265263 / 1442695041
- Root `README.md` has mixed slashes in markdown links (`docs/00_governance\AI_PLAYBOOK.md`) — breaks GitHub linkifying
- `99_archive/` is empty (just README)
- `AGENTS.md` has `status: draft` and last_updated 2026-04-09 — newer than most governance files
- Save version is 4, file names are correct in CLAUDE.md
- Autoload list in CLAUDE.md matches project.godot exactly (14 entries)
- FrameBudgetDispatcher TOTAL_BUDGET_MS = 6.0; priority order streaming > topology > visual > spawn is correct
