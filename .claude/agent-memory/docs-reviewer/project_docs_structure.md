---
name: Station Mirny documentation structure
description: Layered docs architecture under docs/ with YAML frontmatter, absolute Windows-path links, 8 layers (00-06 + 99_archive)
type: project
---

Station Mirny uses a layered documentation architecture under `docs/` with 8 folders (00_governance through 06_templates, plus 99_archive).

All docs use YAML frontmatter with fields: title, doc_type, status, owner, source_of_truth, version, last_updated, and optional depends_on/related_docs.

**Why:** The project migrated from flat root markdown files to a structured layered system with explicit precedence rules. Governance > ADRs > system specs > product > content > execution.

**How to apply:** When reviewing docs, check frontmatter consistency across all fields. Cross-reference links use a mix of absolute Windows paths (in markdown link targets for human navigation) and relative paths (in frontmatter related_docs). The absolute paths pattern is `M:\dev\Station Peaceful\Station Peaceful\docs\...` with backslashes. The 02_system_specs/README.md index is currently incomplete -- missing 6 newer specs.
