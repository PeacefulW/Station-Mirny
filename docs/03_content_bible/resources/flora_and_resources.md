---
title: Flora and Resources
doc_type: content_bible
status: approved
owner: design
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - ../../02_system_specs/progression/resource_progression.md
  - ../../03_content_bible/lore/canon.md
---

# Flora and Resources

This is the canonical content-bible home for resource and flora identity in Station Mirny.

## Scope

This file owns:
- resource identity
- flora identity
- visual role
- biome placement flavor
- world flavor associations
- content-side distinctions between familiar and alien materials

This file does not own:
- progression bottlenecks
- unlock dependencies
- systemic branch gating
- economic pacing

Those belong in:
- [Resource Progression](../../02_system_specs/progression/resource_progression.md)

## Content philosophy

The world should not read as generic Earth wilderness.

Important content rules:
- Earth-like familiarity exists in useful materials
- the planet still feels alien in its lifeforms and environmental expression
- "flora" is the preferred category, not default Earth-tree assumptions

This supports the world's lore identity:
- the planet is connected to humanity
- but not simply a reskinned Earth

## Resources of the world

### Familiar base materials

These resources anchor the player in understandable survival logic.

#### Iron ore

Visual identity:
- brownish stone with rusty-orange veins

World feel:
- common enough to become the obvious structural backbone

Content role:
- visually communicates "foundational industry"

#### Copper ore

Visual identity:
- stone with greenish inclusions

World feel:
- recognizable, slightly less common than iron

Content role:
- visually communicates transition into electrical thinking

#### Stone

Visual identity:
- plain gray or heavy raw mineral mass

World feel:
- abundant, coarse, crude, dependable

Content role:
- basic construction and primitive fabrication material

#### Scrap

Visual identity:
- metallic wreckage with artificial geometry and shine

World feel:
- not natural
- emotionally tied to the crash and the Ark

Content role:
- reinforces the survival-from-wreckage start

## Alien and dangerous-zone materials

These resources should feel more specific, rarer, and biome-linked.

### Siderite

Visual identity:
- dark metal with purple tint

Biome flavor:
- volcanic or otherwise dangerous industrial-feeling zones

Content role:
- should look immediately more advanced and less mundane than iron

### Halkite

Visual identity:
- translucent green crystal

Biome flavor:
- spore-heavy or strange organic zones

Content role:
- should visually read as cognitively or technologically special, not as brute-force metal

## Rare materials

### Precursor alloy

Visual identity:
- ancient, refined, clearly not improvised by the player

Content role:
- must feel like a relic or recovered wonder, not another mined commodity

### Sporite

Visual identity:
- condensed spore-like crystalline matter

Content role:
- should feel dangerous and unstable even when valuable

### Kriostal

Visual identity:
- transparent or glass-like cold mineral

Content role:
- should communicate precision, optics, cold purity

## Flora philosophy

There are no default Earth trees as the baseline assumption.

Instead, the planet's flora should feel like alien ecological analogs:
- tree-like, but not trees
- root-like, but not simple roots
- coral-like, fungal, luminous, or biologically engineered in feel

This protects the world's identity and supports the lore that the planet followed a different biological history.

## Flora entries

### Sporestalks

Visual identity:
- tall fungal or pillar-like growths
- orange-brown or similarly planet-native coloration

Biome flavor:
- plains
- spore forests

Content role:
- the closest analogue to a common harvestable large growth
- should visually communicate that this is the world's "wood-like" utility organism without being a literal tree

### Coral spires

Visual identity:
- brittle mineral-organic towers
- pale or whitish formations

Biome flavor:
- shorelines
- lowlands

Content role:
- visually distinct from heavier spore flora
- should make the world feel geologically and biologically unusual

### Veinroots

Visual identity:
- thick root-like masses with visible fluid or organic pressure

Biome flavor:
- wet zones

Content role:
- should read as living infrastructure of the ecosystem
- useful for water-related flavor identity

### Glowmoss

Visual identity:
- bioluminescent blue or cold-glow growth

Biome flavor:
- caves
- precursor areas

Content role:
- naturally supports navigation, ruins mood, and subterranean alien atmosphere

### Spore clusters

Visual identity:
- pulsing sacs or dense biological masses

Biome flavor:
- spore forests
- caves

Content role:
- should immediately communicate risk and contamination, not just harvest value

## Placement flavor rules

At the content-bible level, resources and flora should obey these identity rules:

- base materials appear where the player expects broad early survival support
- alien advancement materials are visually tied to dangerous or more specialized regions
- flora should reinforce local biome mood, not feel randomly shuffled
- rare materials should feel narratively loaded or ecologically special

Exact spawning logic belongs elsewhere, but these identity expectations should remain stable.

## Lore associations

Resources and flora should support the world's deeper truth:
- familiar enough to suggest connection to humanity
- alien enough to sustain the mystery
- biologically and materially strange enough to imply deep time and divergent evolution or engineered ecology

Flora especially should help sell that the planet is not just another frontier colony world.

## Acceptance criteria

The content layer is working when:
- resources feel visually and narratively distinct
- flora does not collapse into generic Earth trees and bushes
- biome identity is reinforced by what grows there and what can be extracted there
- the player can visually feel the difference between foundational, dangerous-zone, and rare materials

## Failure signs

The content architecture is wrong if:
- the world reads like standard Earth survival game foliage with renamed labels
- multiple resources look or feel interchangeable
- dangerous materials do not feel biome-linked
- flora identity does not reinforce the planet's alien history

## Transitional source note

The migration source for this content layer was:

That root addendum should now be treated as a migration source rather than the canonical home for resource/flora identity.
