---
title: Legacy Root Doc Audit
doc_type: governance
status: approved
owner: design+engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - DOCUMENT_PRECEDENCE.md
  - DOCUMENTATION_MIGRATION_PLAN.md
  - ../README.md
---

# Legacy Root Doc Audit

This file classifies the markdown files that still live in the repository root.

Its purpose is to stop root documents from silently acting as equal peers after the layered `docs/` architecture was introduced.

## Classification legend

- **Canonical entrypoint only**: still useful, but should mainly redirect into `docs/`
- **Legacy detailed source**: still contains meaningful detail not fully migrated yet
- **Migration source only**: use only when extracting remaining detail into canonical docs
- **Archive candidate later**: can likely be archived once references are cleaned

## Root markdown audit

### README.md
Status:
- canonical entrypoint only

Reason:
- now points into `docs/`
- no longer acts as the primary truth for project phase or scope

## Immediate operating rule

When working on documentation:
- start from `docs/`
- use this audit before trusting a root markdown file
- treat any root markdown not explicitly marked canonical as lower-precedence than the layered `docs/` structure

## Next cleanup step

The next safe step is:
- create ADRs for already-stable architectural decisions
- keep root cleanup aligned with actual remaining root files only
