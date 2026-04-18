---
title: Engineering Networks
doc_type: system_spec
status: approved
owner: design+engineering
source_of_truth: true
version: 1.1
last_updated: 2026-03-25
related_docs:
  - ../README.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../01_product/GAME_VISION_GDD.md
---

# Engineering Networks

This is the canonical system spec for engineering distribution inside and around the player's base.

## Purpose

The purpose of this system is to make infrastructure matter without turning the base into unreadable wire spaghetti.

Engineering networks in Station Mirny are meant to:
- reinforce the fantasy that safety is engineered, not granted
- create meaningful layout and placement decisions
- keep the base legible
- let the player feel smart for solving distribution problems

## Gameplay goal

The player should be able to reason about:
- where power comes from
- how oxygen reaches rooms
- how water gets processed and delivered
- how heat spreads

The system should create tradeoffs, not pure busywork.

## Scope

This spec owns:
- room-based power distribution
- room-to-room power transfer
- compressor and air distribution rules
- exterior pipe chains
- interior water endpoints
- hot-water-driven heating endpoints
- engineering overlay responsibilities

This spec does not own:
- exact recipe costs
- full building catalog
- runtime performance law
- product fantasy

Those belong in:
- progression specs
- content docs
- [ADR-0001 Runtime Work and Dirty Update Foundation](../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md)
- [Game Vision GDD](../../01_product/GAME_VISION_GDD.md)

## Core architectural statement

Engineering networks are intentionally split into two interaction zones:

### Outside the base

Real infrastructure is visible and placed tile-by-tile.

Examples:
- pipes
- pumps
- exterior processors
- vulnerable utility lines

### Inside the base

Infrastructure is abstracted through room logic and wall-mounted modules.

Examples:
- electrical distribution through rooms/walls
- ventilation grilles
- wall taps
- wall radiators/batteries

This split is deliberate.

It preserves:
- readability
- meaningful base design
- tactical vulnerability outside
- convenience and clarity inside

## Zone model

### Exterior zone

Characteristics:
- tile-by-tile placement is appropriate
- lines are exposed
- lines can be vulnerable
- routing is spatially obvious

### Interior zone

Characteristics:
- one-click wall modules are preferred over manual micro-routing
- the room becomes the unit of distribution logic
- the player solves network structure at the room/wall level, not with dozens of interior pipe segments

## Power model

### Core rule

A generator powers the room it is in automatically.

Interior wires are abstracted away.
The room is the local power domain.

### Room-to-room transfer

Power crosses from one room to another through a wall-mounted **distributor**.

Distributor role:
- mounted on the wall between rooms
- transfers power from room A to room B
- may introduce loss depending on material tier

Design purpose:
- create meaningful placement decisions
- avoid interior wire clutter
- preserve engineering legibility

### Intended consequences

- central generator placement reduces path losses but may expose the heart of the base
- edge placement protects the core but may cost more transfer efficiency

## Air model

### Core rule

A compressor services its own room automatically.

To push oxygen into adjacent rooms, the player uses wall-mounted **vent grilles**.

### Vent grille role

Vent grilles:
- are mounted on a wall
- transfer oxygen from one serviced room into an adjacent room
- consume power
- are capped by compressor capacity

The exact efficiency numbers may vary by balance, but the structural rule is locked:
- one compressor can support only a limited number of room-to-room air links

### Door and breach interactions

Air distribution must remain compatible with:
- door leakage
- closed-room integrity
- airlock behavior
- breach consequences

The engineering network does not replace those systems; it must integrate with them.

## Water model

### Core rule

Water travels through visible exterior pipe chains from source to base connection.

Typical flow:
- source or pump
- pipe line
- optional processing
- wall connection
- interior endpoint

### Why outside pipes stay explicit

Because water sourcing and routing should feel infrastructural and exposed:
- path choice matters
- distance matters
- utility chains can be vulnerable
- the player sees the logistical footprint of the base

## Water processing model

The water line may include processors such as:
- cleaner/purifier
- boiler

These processors can exist:
- outside
- in a utility annex
- inside the base

The rule is not "must be outside".
The rule is:
- they are part of the line before interior use
- their placement has tactical and logistic consequences

## Interior water and heat endpoints

After the line reaches the base, interior use should happen through wall-mounted endpoints.

### Tap

Role:
- makes water available inside the room
- represents room-facing water access

### Hot-water radiator / battery

Role:
- uses hot-water infrastructure to provide heating inside a room

Important design value:
- heat can come from engineered fluid infrastructure, not only electric devices

## Heat model

The system should support multiple heating paradigms, for example:
- local combustion heat
- electrically powered heat
- hot-water-driven heat
- heated air distribution

This spec does not lock the full final heater list.
It locks the engineering principle:

**heat is a first-class infrastructure problem, not only a passive environmental modifier.**

## Overlay responsibility

Engineering overlays are mandatory to keep the network readable.

At minimum the system should support player-facing overlays for:
- electricity
- air
- water
- temperature

Overlay purpose:
- reveal hidden engineering state
- preserve clean normal-mode visuals
- let the player debug the base without debug tools

## Data and system boundaries

This system should remain compatible with:
- room logic
- indoor/outdoor logic
- power system
- future water/heat processing systems
- wall-mounted building data

It should be expressed through:
- building/resource data
- room contracts
- wall endpoint contracts
- overlays

not through giant direct dependencies between unrelated systems.

## Runtime architecture expectations

Engineering networks are world-sensitive systems.

They must follow runtime law:
- no full rebuild in interactive path
- room/network recalculation must be dirty-driven
- visual overlays must remain decoupled from heavy gameplay recomputation

See:
- [ADR-0001 Runtime Work and Dirty Update Foundation](../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md)

## Save contract

Persistent state should include:
- placed engineering structures
- room-to-room transfer modules
- exterior pipe layout
- relevant stateful machinery data

The save model should preserve:
- room topology consequences
- engineering connectivity
- infrastructure placement decisions

## Acceptance criteria

The system is successful when:
- the player can understand how power reaches a room
- the player can understand how oxygen reaches a room
- the player can understand how water reaches a room
- the player can reason about heating as infrastructure
- normal mode stays readable
- overlay mode makes hidden logic legible
- infrastructure placement creates meaningful tradeoffs

## Failure signs

The architecture should be considered wrong if:
- interior rooms require manual wire spaghetti for every connection
- the player cannot explain why one room has power/air/water and another does not
- exterior utility lines do not matter spatially
- infrastructure is so abstract that layout decisions stop mattering
- or so explicit that the base becomes unreadable busywork

## Extension points

This system should be able to grow by data through:
- better distributors
- better grilles
- new processors
- new endpoint modules
- path-specific heating or supply variants

without replacing the underlying room-vs-exterior model.

## Open questions

Still open at system-spec level:
- final exact loss model for power transfer
- final exact cap model for compressors and vents
- final exact number of supported endpoint variants
- whether all heat endpoints are room-scoped or some can affect adjacent spaces
- exact overlay UX sequencing

These should be resolved without breaking the accepted core structure above.
