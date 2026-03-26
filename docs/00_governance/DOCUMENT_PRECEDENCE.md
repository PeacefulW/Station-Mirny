---
title: Document Precedence
doc_type: governance
status: approved
owner: design+engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - AI_PLAYBOOK.md
  - ENGINEERING_STANDARDS.md
  - PERFORMANCE_CONTRACTS.md
---

# Document Precedence

This file defines which document wins when documents disagree.

## Global precedence

1. `docs/00_governance/ENGINEERING_STANDARDS.md`
2. `docs/00_governance/PERFORMANCE_CONTRACTS.md`
3. `docs/05_adrs/*`
4. relevant `docs/02_system_specs/*`
5. `docs/01_product/GAME_VISION_GDD.md`
6. `docs/03_content_bible/*`
7. `docs/04_execution/*`
8. `README.md`
9. archived or deprecated documents

## Special rules

### Lore canon
Canonical lore lives in:
- `docs/03_content_bible/lore/canon.md`

### Runtime/performance
If a product or system document suggests an implementation that violates performance rules, [Performance Contracts](PERFORMANCE_CONTRACTS.md) wins.

### Execution docs
Roadmaps and iteration briefs do not override approved architecture or standards.

### Legacy root docs
During migration, old root docs are valid only in the areas where the new `docs/` canonical file explicitly points back to them.

## Decision rule for conflicts

If two documents disagree:
1. identify their layer
2. use the higher-precedence layer
3. if both are in the same layer, prefer:
   - `approved` over `draft`
   - `source_of_truth: true` over `false`
   - newer `last_updated`
4. if still ambiguous, create or update an ADR
