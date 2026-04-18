---
name: Station Mirny documentation structure
description: Layered docs architecture under docs/, known indexing gaps, and archive notes for docs review work
type: project
---

Station Mirny uses a layered documentation architecture under `docs/`, with the
current live entrypoints routed through `AGENTS.md`, `docs/README.md`,
`docs/00_governance/WORKFLOW.md`, and `docs/00_governance/ENGINEERING_STANDARDS.md`.

All current docs use YAML frontmatter where applicable and are expected to keep
`title`, `doc_type`, `status`, `owner`, `source_of_truth`, `version`, and
`last_updated` accurate.

## Review Notes

- treat `docs/README.md` as the live navigation hub
- prefer living specs and ADRs over removed legacy root-doc names
- watch for broken markdown links and mixed path separators
- treat archive or memory notes as historical context, not canonical truth
