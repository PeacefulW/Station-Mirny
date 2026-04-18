---
title: ADR-0002 Wrap-World Is Cylindrical
doc_type: adr
status: approved
owner: engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-26
related_docs:
  - ../00_governance/PROJECT_GLOSSARY.md
  - 0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# ADR-0002 Wrap-World Is Cylindrical

## Context

The world needs a defined topology before worldgen, streaming, navigation, and multiplayer can be built without conflicting assumptions.

## Decision

The world is a cylinder:
- **X axis wraps.** Moving far enough east returns you to the west. Seamless, no edge.
- **Y axis does not wrap.** Y carries latitude logic: temperature gradient from equator to poles.
- Noise sampling, chunk streaming, pathfinding, and multiplayer replication must all respect this topology.
- There is no "edge of the world" on X. Y boundaries are soft (extreme cold / extreme heat makes travel impractical, not a wall).

## Consequences

- All world channel samplers must be wrap-safe on X.
- Chunk coordinates on X are modular (wrap at world width).
- Navigation and minimap must handle X-wrap correctly.
- Save files store canonical coordinates that survive wrap arithmetic.
