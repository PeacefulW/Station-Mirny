---
title: ADR-0004 Host-Authoritative Multiplayer
doc_type: adr
status: approved
owner: engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-26
related_docs:
  - ../02_system_specs/meta/multiplayer_authority_and_replication.md
  - 0001-runtime-work-and-dirty-update-foundation.md
---

# ADR-0004 Host-Authoritative Multiplayer

## Context

The game targets 2-4 player co-op. We need to decide now who owns gameplay truth, because entity identity, state ownership, and save architecture all depend on this.

## Decision

The host is the single authority for all gameplay state:
- **Host decides** what happened: building placed, enemy spawned, tile mined, power state changed, time of day.
- **Clients receive** truth from the host. Clients may predict locally for responsiveness, but host corrects.
- **No split authority.** There is no "client owns their own chunk" model. One world, one truth, one host.

This applies even before multiplayer is implemented. Code written now must:
- Keep state ownership explicit (who mutates, who reads).
- Avoid client-local gameplay state that would conflict with a future host.
- Separate authoritative state from client-local presentation (camera shake, particle effects, UI).

## Consequences

- Entity identity must be clean and host-assignable.
- Save files are host-side only.
- All gameplay-affecting mutations flow through authoritative paths (commands, EventBus), not local hacks.
- Client-local presentation (visual effects, sound, UI polish) is allowed to diverge — it's not gameplay truth.
