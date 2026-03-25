---
title: Lighting, Visibility and Darkness
doc_type: system_spec
status: draft
owner: design+engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
depends_on:
  - environment_runtime_foundation.md
related_docs:
  - environment_runtime_foundation.md
  - world_generation_foundation.md
  - subsurface_and_verticality_foundation.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - ../meta/multiplayer_authority_and_replication.md
  - ../meta/save_and_persistence.md
---

# Lighting, Visibility and Darkness

This document defines the gameplay-support role of lighting, darkness, and visibility in Station Mirny.

This is not a renderer-only document.
It exists to make sure that lighting remains one of the core emotional and gameplay-support foundations of the project rather than drifting into a purely cosmetic effect.

## Purpose

The purpose of this document is to define a stable foundation for:

- light as safety
- darkness as pressure
- visibility as readability and risk management
- day/night readability shifts
- underground readability and fear
- the relationship between lighting, power, weather, shelter, and player comfort

It protects one of the central truths of the game:

**inside the base should feel warm, lit, readable, and safe; outside and underground should become frightening, uncertain, and dangerous when light is insufficient.**

## Gameplay goal

Lighting must support the product fantasy that:

- the base feels inhabited and protective
- returning to light feels relieving
- darkness outside is emotionally dangerous even before direct combat begins
- night changes how the player reads the world and plans movement
- underground exploration becomes tense because light is limited and local
- environmental hostility is amplified by low visibility

The player should not experience lighting as a decorative layer pasted on top of the game.
The player should experience it as one of the things that makes safety, danger, and mood legible.

## Scope

This spec owns:

- the gameplay-support meaning of light and darkness
- visibility/readability contexts
- indoor / outdoor / underground readability expectations
- the relationship between lighting and environmental runtime
- the relationship between lighting and power / shelter / local light sources
- distinctions between authoritative gameplay-facing lighting state and purely visual lighting presentation
- performance-safe architectural direction

This spec does not own:

- low-level shadow renderer implementation details
- exact final shader techniques
- exact final numerical visibility formulas
- low-level GPU material behavior
- exact art tuning of every light source

Those belong in implementation-specific rendering documents or engine-level tech notes.

## Core architectural statement

Lighting in Station Mirny is not optional polish.

It is a foundational support system for:

- atmosphere
- fear
- safety
- readability
- navigation
- return-to-base relief
- underground tension
- environmental storytelling

If the lighting system becomes visually impressive but stops reinforcing those functions, it is failing the game.

## Product-level truth

The game is built around a hard emotional contrast:

- lit shelter vs unlit exposure
- human-made order vs planetary indifference
- controlled interior space vs hostile unknown exterior
- preparation vs vulnerability

Lighting is one of the primary carriers of that contrast.

A warm lit base must feel meaningfully different from:

- a dark storm outside
- an unlit night expedition
- a failed power situation
- a cramped underground dig with only local light

## What lighting must do for the game

### 1. Mark safety
A lit interior should communicate:

- shelter
- civilization
- human presence
- recoverability
- the possibility to breathe, work, plan, and rest

Light is one of the first ways the player should feel that a place is habitable.

### 2. Mark vulnerability
Darkness should communicate:

- limited knowledge
- incomplete perception
- danger of the unknown
- risk of moving too far from secure infrastructure
- fear of what may exist beyond current vision

### 3. Mark navigability
Lighting should help the player read:

- where they are safe to move
- where walls, entrances, exits, and thresholds are
- what part of the room or terrain is readable
- whether a route feels traversable or risky

### 4. Support emotional rhythm
The core expedition rhythm is:

- prepare in light
- go into uncertainty
- endure low-visibility pressure
- return to light
- feel relief

Lighting is one of the main reasons that this rhythm works emotionally.

### 5. Support underground identity
Underground space should feel different not just because of walls and excavation, but because:

- darkness is stronger there
- local light matters more
- visibility is more fragile
- the player is often operating in tighter spaces with less information

## Lighting, darkness, and visibility are not the same thing

The project should distinguish conceptually between:

### Lighting
Presence of light sources and their ability to make space readable, safe-feeling, and visually structured.

### Darkness
Absence or insufficiency of useful light, causing uncertainty, pressure, and loss of clarity.

### Visibility
How well the player can read the world in practice, which may depend on:

- light
- darkness
- weather
- particles
- fog-like effects
- underground context
- occlusion
- storm severity

This distinction matters because a place may technically have some light, while still being functionally difficult to read.

## Canonical design rules

### Rule 1: Light is safety
Light should make the player feel more in control.

### Rule 2: Darkness is pressure
Darkness should increase tension, uncertainty, and caution.

### Rule 3: Interior and exterior must not read the same
A lit room and a dark exterior should produce a strong emotional contrast.

### Rule 4: Underground darkness must matter
Underground areas should not feel like just another room painted darker.

### Rule 5: A power failure or light loss must matter emotionally
If base lighting fails, the player should feel a shift in security, not just a cosmetic mood change.

## Visibility contexts

The game should support several distinct readability contexts.

## 1. Warm interior / stable base readability
Expected qualities:

- highest readability
- strongest sense of safety
- clear object silhouettes
- clear room boundaries
- visible machinery and interactables
- emotionally comforting light identity

This context should feel like the player has pushed back against the planet.

## 2. Daytime exterior readability
Expected qualities:

- broad world readability
- long-range terrain reading compared to night
- visibility of flora motion and weather response
- enough clarity for route planning and exploration
- outside still feels exposed, even when readable

Day should not erase danger.
It should create a different, more navigable form of danger.

## 3. Night exterior readability
Expected qualities:

- reduced information
- stronger dependence on local light sources
- more threatening silhouettes
- increased uncertainty outside lit zones
- more stressful navigation and perimeter awareness

Night should change behavior.
It should not merely tint the screen darker.

## 4. Severe weather exterior readability
Expected qualities:

- degraded visibility
- shifting readability due to wind, precipitation, atmospheric clutter, or storm state
- stronger reliance on known routes and light discipline
- increased sense of exposure and vulnerability

The player should feel that weather can make an already dangerous exterior worse.

## 5. Underground readability
Expected qualities:

- darkness as baseline
- strong local dependence on placed or carried light
- short confidence radius around the player or installed lighting
- tension about what lies outside the lit area
- claustrophobic but readable if prepared correctly

Underground light must feel earned and necessary.

## 6. Emergency / degraded interior readability
Expected qualities:

- base is still familiar, but security feels weakened
- some zones may become partially unreadable
- anxiety rises because a normally safe place is no longer fully safe-feeling

This context is important because it attacks the emotional core of the game directly.

## Light source classes

The project should distinguish conceptually between different kinds of light sources.

### Structural base lighting
Examples:

- room lights
- powered lamps
- corridor lights
- floodlights integrated into infrastructure

Expected meaning:

- stable habitation
- deliberate engineering
- comfort and functionality

### Portable light sources
Examples:

- carried lamps
- temporary work lights
- hand-held tools with light

Expected meaning:

- local temporary safety
- expedition support
- fragile extension of human control into darkness

### Fire-based or improvised lights
Examples:

- torches
- emergency flames
- fuel-based temporary local light

Expected meaning:

- lower-tech survival
- tension mixed with comfort
- unstable or partial safety

### Exterior perimeter / large-area lighting
Examples:

- base perimeter lamps
- watch lights
- approach lights

Expected meaning:

- expansion of safety outward
- a visible threshold between the human zone and the hostile dark

### Environmental or non-human light sources
Examples:

- bioluminescent flora
- anomalous ruins
- atmospheric glow events

Expected meaning:

- not necessarily safe
- often uncanny
- should be used carefully so the player does not automatically read all light as human protection

## Darkness classes

Darkness should not be treated as one flat universal state.
The project should allow different emotional kinds of darkness.

### Ordinary exterior night darkness
Read as:

- natural reduction of control
- increased danger and caution

### Storm-darkened exterior
Read as:

- hostile suppression of visibility
- active environmental pressure

### Underground darkness
Read as:

- intimate uncertainty
- claustrophobic lack of information
- strong dependency on what the player brought with them

### Interior power-loss darkness
Read as:

- violation of sanctuary
- loss of confidence
- stress inside what should have been safe

### Alien / anomalous darkness later if used
Read as:

- wrongness
- unfamiliarity
- a possible lore-level or biome-specific threat carrier

## Relationship with environment runtime

Lighting must integrate cleanly with the environment runtime layer.

The lighting/visibility system should be able to react to:

- day/night phase
- season mood if relevant
- weather severity
- storm density
- wind-driven atmospheric clutter
- underground/outdoor context

Important rule:

environment runtime provides environmental state,
lighting/visibility interprets how readable and safe-feeling the space is under that state.

## Relationship with power and infrastructure

Lighting is a major part of the base fantasy because it is part of infrastructure.

The player should feel that working lighting represents:

- functioning systems
- energy discipline
- room utility
- base maturity
- human control of the space

The project should support the idea that lighting can depend on:

- powered infrastructure
- emergency systems
- temporary solutions
- portable expedition gear

This does not mean the whole file defines engineering rules.
It means lighting should be architecturally compatible with them.

## Relationship with building and room identity

A room is not fully readable as a room only by walls and floor.
Light contributes heavily to whether a space reads as:

- inhabited
- useful
- safe
- maintained
- abandoned
- damaged
- under threat

This means lighting is part of room identity and room mood, not just global ambience.

## Relationship with underground gameplay

Underground lighting has special importance.

Underground readability should support:

- deliberate player-made safe pockets
- risky expansion into darkness
- emotional fear of what is outside the lit zone
- useful visibility for mining and construction when prepared
- stronger contrast between secure dug-out spaces and raw, unlit mass

Canonical rule:
underground should never be tuned as if darkness there were optional flavor.

## Readability goals by distance and purpose

Lighting and visibility should support several kinds of reading at once.

### Immediate interaction readability
The player should be able to read:

- what is directly around them
- nearby interactables
- local obstacles
- safe standing and building space

### Short-route readability
The player should be able to read:

- where the next safe step or corridor is
- whether a passage continues into uncertainty
- where the edge of the current safe zone lies

### Threat silhouette readability
The player should be able to feel:

- whether something is present in or near darkness
- whether a route feels open, enclosed, or compromised
- that darkness can conceal threat even if details are not fully visible

### Base-perimeter readability
The player should be able to perceive:

- where the base protection visually ends
- which areas are watched, lit, or maintained
- which areas are outside the protection envelope

## Visibility pressure should influence behavior

Lighting and visibility should affect how the player behaves even if no hard stat penalty exists.

The player should naturally want to:

- bring light
- maintain power
- establish lit routes
- secure underground work areas
- think twice before going out at night or during storms

This is a major success condition.
If the player does not care about light, the system is underperforming.

## Gameplay-facing state vs renderer internals

The gameplay architecture must not depend on scraping renderer internals to answer important questions.

Other systems may need to know things like:

- is this area effectively lit?
- is this area low-visibility?
- is this room in a degraded readability state?
- is the player inside a protected lit zone?

These should be exposed through clear gameplay-facing queries or state categories, not inferred by fragile visual hacks.

## Authority, derived state, and client-local presentation

This distinction is mandatory.

### Gameplay-facing authoritative or shared state may include:

- whether a light source is on or off
- whether a room is powered
- whether a zone counts as dark / degraded / lit enough for gameplay semantics
- whether a base perimeter light network is functioning

### Derived reconstructible state may include:

- combined visibility classes in local zones
- aggregated zone-level light confidence maps if used
- cached readability masks built from current authoritative inputs

### Client-local presentation may include:

- shadow softness
- local flicker phase
- subtle post-process variation
- cosmetic local shimmer or volumetric response
- exact interpolation of moving light visuals

Canonical rule:
make gameplay meaning stable;
allow presentation richness to vary locally when safe.

## Multiplayer direction

The lighting foundation must remain compatible with future co-op.

This means:

- do not assume a single player and a single camera define all relevant visibility state
- do not assume local visual lighting alone is enough to define shared gameplay meaning
- keep a distinction between shared light-relevant state and client-local rendering details

Example direction:

- lamp on/off may be shared authoritative state
- exact shadow animation may remain client-local

## Save and persistence direction

Persistence should keep meaningful lighting-related state, not full-frame renderer output.

Likely persistent classes:

- placed light sources and their configuration
- whether infrastructure lights exist and are connected
- room or zone states that matter to gameplay if such states are stored
- power-dependent lighting state where necessary

Likely reconstructible or non-persistent:

- exact flicker phase
- exact frame-level shadow shape
- exact local cosmetic darkness modulation

## Performance direction

Lighting is important enough that the project may use custom shadow technology.
That does not remove performance law.

The system must avoid:

- giant synchronous relight passes in the interactive path
- world-scale visibility rebuilds for one local light change
- coupling every local change to full redraw of loaded space
- treating all lighting response as equally expensive and equally urgent

Preferred direction:

- local updates stay local when possible
- larger derived products are incremental, cached, or budgeted
- presentation degrades before frame pacing does
- renderer richness must not force gameplay hitching

## Simulation cadence direction

The lighting/visibility system should not be one monolithic always-per-frame gameplay simulation.

The intended direction is layered:

- fast local visual presentation updates
- lower-frequency gameplay-facing visibility state updates where appropriate
- event-driven updates when lights, power, or environment conditions change materially
- budgeted recomputation for heavier derived products

## Minimal architectural seams

These are illustrative, not final APIs.

### Visibility state query

```gdscript
class_name VisibilityService
extends RefCounted

func sample_visibility(world_pos: Vector2i) -> VisibilitySample:
    pass
```

### Lighting context query

```gdscript
class_name LightingService
extends RefCounted

func is_effectively_lit(world_pos: Vector2i) -> bool:
    pass

func get_lighting_context(world_pos: Vector2i) -> LightingContext:
    pass
```

### Example data shape direction

```gdscript
class_name VisibilitySample
extends RefCounted

var visibility_class: int
var effective_light_level: float
var darkness_pressure: float
var weather_visibility_modifier: float
var underground_modifier: float
var comfort_lighting_modifier: float
```

These are only examples.
The important part is that gameplay systems consume explicit visibility/lighting answers rather than poking directly into renderer internals.

## Success conditions

This foundation is successful when:

- the base feels emotionally safer because of light, not just walls
- night materially changes how exterior travel feels
- underground exploration becomes more tense and more deliberate because of limited local light
- weather and darkness can make familiar areas feel newly dangerous
- losing light in a supposedly safe zone feels serious
- lighting improves readability without flattening fear
- the architecture remains compatible with performance constraints and future co-op

## Failure signs

This foundation is wrong if:

- light is treated as pure eye-candy
- darkness is only a color tint with no experiential consequence
- night does not change player behavior
- underground remains fully comfortable and readable without deliberate lighting
- base lighting failure feels trivial
- gameplay systems depend on renderer internals for critical logic
- local light changes cause brute-force large-scale rebuilds

## Open questions

The following remain intentionally open:

- exact final visibility class taxonomy
- exact hard vs soft gameplay consequences of darkness
- exact integration with late-game threat behavior and stealth-like pressure if any
- exact degree to which perimeter lighting affects fauna/threat systems
- exact final relationship between comfort lighting, warmth, and shelter mood
- exact renderer-side implementation details for dynamic shadows and special light source behavior

These may evolve without changing the foundation above.
