---
title: ADR-0007 Environment Runtime Is Layered and Distinct from Worldgen
doc_type: adr
status: approved
owner: design+engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-26
related_docs:
  - ../02_system_specs/world/environment_runtime_foundation.md
  - ../02_system_specs/world/world_generation_foundation.md
  - 0003-immutable-base-plus-runtime-diff.md
---

# ADR-0007 Environment Runtime Is Layered and Distinct from Worldgen

## Context

Two systems touch the world but answer different questions. Without a clear boundary, they will merge into an unmaintainable mess.

## Decision

**World generation** and **environment runtime** are separate systems with distinct responsibilities:

### World generation answers: "What IS this place?"
- Biome, terrain type, elevation, moisture, resource deposits, flora, large structures
- Deterministic from seed. Permanent. Does not change during gameplay.
- Generated once, cached in chunks, persisted as immutable base.

### Environment runtime answers: "What does this place feel like RIGHT NOW?"
- Time of day, season, weather, wind, temperature, visibility, spore density
- Changes every frame / every hour / every season. Transient.
- Not generated from seed. Driven by simulation clocks and event systems.

### Layered model
The environment runtime is itself layered:
1. **Stable generated base** — biome identity, terrain (from worldgen, never changes)
2. **Slow world state** — season, world-clock, regional weather patterns (changes over hours/days)
3. **Local runtime state** — current temperature, wind, precipitation, spore concentration (changes per frame/minute)
4. **Presentation response** — visual tint, sound mix, particle intensity, camera effects (client-local, non-authoritative)

### Rules
- Worldgen never reads environment runtime. Environment runtime reads worldgen (biome base temperature).
- Environment runtime state is authoritative for gameplay (temperature affects player). Presentation is derived.
- Saving environment state: only slow world state (season, day). Local runtime reconstructs on load.
- Multiplayer: host owns slow world state and local runtime. Clients own presentation only.

## Consequences

- Adding weather does not touch worldgen code.
- Adding a biome does not touch environment runtime code.
- Temperature at a position = `biome.base_temp + season_modifier + time_of_day_modifier + weather_modifier + altitude_modifier`. Each term comes from its own system.
- Save files store world clock and season, not per-tile temperature snapshots.
