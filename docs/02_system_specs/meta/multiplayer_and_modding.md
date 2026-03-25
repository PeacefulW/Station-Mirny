---
title: Multiplayer and Modding Constraints
doc_type: system_spec
status: approved
owner: design+engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - ../../00_governance/ENGINEERING_STANDARDS.md
---

# Multiplayer and Modding Constraints

## Purpose

This document captures future-facing architectural constraints that should influence today's implementation choices even before full multiplayer or mod support exists.

## Multiplayer target

The intended future model is small-scale co-op:
- 2-4 engineers
- shared world
- host-authoritative session

Current implication:
- entity identity and persistence must be clean
- world state ownership must be explicit
- systems should avoid assumptions that only one player exists

## Modding target

Modding should support:
- new data content
- extended biomes/resources/recipes/entities
- later total conversions

Current implication:
- data must not be hardcoded
- registry-driven identity matters
- event/hook surfaces matter
- resource loading needs clear override rules

## Acceptance criteria

- current systems do not hard-lock the project out of future co-op
- current systems remain data-extensible for mods
