---
title: ADR-0003 Immutable Base + Runtime Diff
doc_type: adr
status: approved
owner: engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-26
related_docs:
  - ../02_system_specs/meta/save_and_persistence.md
  - ../02_system_specs/world/world_generation_foundation.md
  - 0001-runtime-work-and-dirty-update-foundation.md
---

# ADR-0003 Immutable Base + Runtime Diff

## Context

The world is procedurally generated from a seed. Players modify it (mining, building, terrain changes). We need a clear model for what is permanent truth vs what changes.

## Decision

The world has two layers:

1. **Immutable base.** Generated deterministically from seed + coordinates. Never changes after generation. Same seed = same world, always. This is the "what the planet was before the engineer arrived."

2. **Runtime diff.** Everything the player and game systems change: mined tiles, placed buildings, terrain modifications, destroyed structures. Stored as per-chunk diffs on top of the base.

Rules:
- Save files store only diffs, not the full world. On load: regenerate base from seed, apply diffs.
- Rendering reads `base + diff`. If no diff exists for a tile, use the base value.
- Diffs are authoritative gameplay state. Base is reconstructible from seed.
- No system may modify the base layer. All mutations go to the diff layer.

## Consequences

- Save files are small (only changes, not the full world).
- Multiplayer sync is efficient (send diffs, not world state).
- World generation can be improved without breaking existing saves (base changes, diffs still apply).
- Clear separation: "what the world is" vs "what happened in it."
