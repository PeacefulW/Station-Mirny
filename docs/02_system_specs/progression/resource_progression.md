---
title: Resource Progression
doc_type: system_spec
status: approved
owner: design
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - ../../03_content_bible/resources/flora_and_resources.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../02_system_specs/base/engineering_networks.md
---

# Resource Progression

This is the canonical system spec for resource roles, tiering, and progression dependencies in Station Mirny.

## Purpose

This system exists to define how resources drive progression.

It should answer:
- what each resource tier is for
- why a player risks entering a biome
- how materials unlock tools, infrastructure, and branches
- where the game creates bottlenecks and why

This is not the full flavor catalog of every resource. It is the progression logic behind them.

## Gameplay goal

Resources should not just be "things to collect".

They should provide:
- clear short-term goals
- visible midgame bottlenecks
- biome-driven risk/reward routing
- long-term branch identity

The player should understand:
- what they need next
- where it comes from
- why the trip is dangerous
- what new capability it unlocks

## Scope

This spec owns:
- resource progression philosophy
- tier structure
- unlock dependencies
- biome risk/reward logic
- branch-specific late-game value
- economic chain direction
- progression role of tools/material eras

This spec does not own:
- final content flavor text
- visual appearance details
- full flora identity
- detailed lore associations

Those belong in:
- [Flora and Resources](../../03_content_bible/resources/flora_and_resources.md)
- lore/content bible files

## Core progression philosophy

The planet contains both familiar and alien resources.

Progression logic:
- familiar base materials provide understandable early stability
- dangerous-zone materials create targeted capability jumps
- rare/endgame materials create branch identity and finite high-value decisions

The system should avoid "new ore for its own sake".
Each new resource tier should unlock a concrete new possibility.

## Resource tiers

### Tier 1 — Base survival materials

Role:
- stabilize the first shelter
- create the first tools
- bootstrap basic building and crafting

Typical examples:
- iron ore
- copper ore
- stone
- crash scrap

Design role:
- reachable from or near the safer early area
- familiar enough that the player immediately understands their purpose

### Tier 2 — Biome-risk advancement materials

Role:
- push the player into dangerous biomes
- unlock meaningful infrastructure or progression acceleration

Typical examples:
- siderite
- halkite

Design role:
- not generic upgrades
- each should unlock a specific new strategic capability

### Tier 3 — Rare/high-value materials

Role:
- create strong late-game decisions
- support branch identity
- gate top-tier equipment and infrastructure

Typical examples:
- precursor alloy
- sporite
- kriostal

Design role:
- scarce, dangerous, or structurally gated
- never just "bigger numbers ore"

## Base material roles

### Iron

Progression role:
- foundation of physical construction and tool baseline

It should support:
- walls
- frames
- baseline tools
- baseline weapons
- general structural expansion

### Copper

Progression role:
- entry into electrical and control infrastructure

It should support:
- wires or their equivalent electrical infrastructure
- circuits
- electronics
- the first serious engineering expansion

### Stone

Progression role:
- crude but accessible construction base

It should support:
- primitive structures
- the earliest fabrication or processing stations
- fallback construction when better refinement is not yet available

### Scrap

Progression role:
- finite early bootstrap resource

Important rule:
- scrap is not the endless main economy
- it enables the first steps and teaches the player to transition into real extraction

## Advanced material roles

### Siderite

Progression role:
- infrastructure reach
- lossless or improved power transmission
- better anti-corrosion or hostile-environment durability

Why it matters:
- it converts the player from local base scale to broader territorial scale

Expected unlock effect:
- expansion, outposts, longer logistics, higher-tier tools

### Halkite

Progression role:
- decryption/research acceleration

Why it matters:
- it is not just another building metal
- it accelerates access to future capability

Expected unlock effect:
- faster tech recovery
- deeper progression branch access

## Rare material roles

### Precursor alloy

Progression role:
- top-tier limited material

Design rule:
- it should feel found, not mass-produced
- it should support best-in-class outcomes or irreplaceable constructions

### Sporite

Progression role:
- branch-sensitive late-game material

Design role:
- Adaptation path: mutation/biological progression
- Terraformer path: high-energy or alternative fuel logic

### Kriostal

Progression role:
- precision/optics/high-end systems support

Design role:
- improves advanced technical capability rather than raw brute-force construction

## Tool and capability eras

The progression is not meant to read as a simple primitive civilization ladder.

The Engineer is already highly educated.
The arc is about recovering and rebuilding capability under hostile conditions.

### Era 1 — Wreckage and salvage

Player condition:
- damaged equipment
- weak tools
- high friction

Progression function:
- teach scarcity
- make every processed material matter
- create desire for automation and better infrastructure

### Era 2 — Basic metal recovery

Player condition:
- reliable manual progression
- better tools
- first useful stations

Progression function:
- reduce raw friction
- introduce first automation taste

### Era 3 — Electronics and systems

Player condition:
- infrastructure accelerates progress
- automation begins to matter
- research/decryption pressure becomes meaningful

Progression function:
- free the player from purely manual throughput
- introduce larger strategic tradeoffs

### Era 4 — Branch identity / endgame

Player condition:
- the player is no longer only surviving
- they are choosing what kind of power they are becoming

Progression function:
- make the two long-form paths materially distinct

## Economic chain

The canonical high-level chain is:

### Early
- salvage and raw extraction
- crude processing
- foundational tools and shelter

### Mid
- refined materials
- infrastructure expansion
- better processing throughput
- access to dangerous biome materials

### Late
- branch-sensitive materials
- limited elite materials
- high-end infrastructure and identity-defining tools

## Risk/reward geography

A biome should matter because of what it asks from the player and what it gives back.

The canonical resource logic is:
- safer biome = base stability materials
- dangerous biome = strategic unlock materials
- rare ruin/deep zone = exceptional or finite-value materials

That risk/reward mapping is a core progression rule, not just flavor.

## Branch interaction

Resources should support the late-game branch split rather than ignore it.

Canonical direction:
- some materials are shared infrastructure essentials
- some materials become disproportionately valuable to one path
- late resources should help make Terraformer and Adaptation feel materially different

## System dependencies

Resource progression connects directly to:
- building progression
- engineering infrastructure
- tools
- decryption/research
- biome exploration
- long-range expansion

This means changes in resource roles can have major downstream effects and should be treated as system design, not just content flavor.

## Acceptance criteria

The system works when:
- each major resource has a clear gameplay reason to exist
- the player can explain why they need a resource before they have it
- biome danger and resource reward feel intentionally paired
- late resources meaningfully differentiate advanced play instead of just raising numbers
- progression bottlenecks feel motivating rather than arbitrary

## Failure signs

The progression architecture is wrong if:
- multiple resources are interchangeable with no clear strategic role
- a dangerous biome gives nothing that changes how the player plays
- new resources only exist to pad crafting trees
- late materials do not reinforce branch identity
- the player cannot tell what resource is the next meaningful target

## Open questions

Still open at system-spec level:
- exact balance curve of each tier
- final scarcity model for rare materials
- exact ship/other-planet progression role
- exact number of tool eras kept in final design
- exact branch lock versus shared access on late materials

These should be solved without breaking the role structure above.
