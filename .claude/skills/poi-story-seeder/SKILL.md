---
name: poi-story-seeder
description: >
  Generate place-based story hooks, ruin history, discovery beats, and
  environmental storytelling for Station Mirny locations. Use when the user asks
  "придумай POI", "придумай руины", "записка в локации", "терминал в руинах",
  "environmental storytelling", "ruin history", "discovery beat", or wants
  diaries, notes, logs, or terminals tied to a specific place while staying
  consistent with `docs/03_content_bible/lore/canon.md`.
disable-model-invocation: true
---

# Poi Story Seeder

Use this skill for location-tied narrative design.

This skill owns place-based storytelling: why a site exists, what happened there,
what traces remain, and how the player infers story from space, props, and discoveries.

## Read first

- `docs/03_content_bible/lore/canon.md`
- `docs/03_content_bible/lore/open_questions.md`
- `docs/01_product/GAME_VISION_GDD.md`

## What this skill does

1. Start from the physical place, not from an abstract lore essay.
2. Build a local site history that fits locked canon and leaves mystery where canon stays open.
3. Turn story into spatial evidence: ruins, layout, residue, terminals, notes, traces,
   and discovery order.
4. Keep the player's reveal cadence intact so locations hint, pressure, and confirm
   truth at the right stage of the game.

## Default workflow

1. Read `canon.md` and list which locked truths the location may imply, hint at, or must avoid spoiling.
2. Read `open_questions.md` to find safe expansion space for local history, symbolism,
   and unresolved interpretation.
3. Define the place: owner, original purpose, failure mode, current condition, and
   the strongest visual or interactive traces left behind.
4. Map the narrative into discovery beats: what the player sees first, what they infer,
   and what optional artifacts or terminals deepen the reading.
5. Treat uncertain history as a plausible site story, rumor, or partial archive rather
   than as locked canon unless the human explicitly wants to promote it.

## Typical smells

- the output is a lore essay with no spatial storytelling
- every POI reveals too much too early and spoils the late ancestral reveal
- notes and terminals feel detachable from the site that supposedly produced them
- the location is atmospheric but says nothing about survival pressure, spores, ruins, or old systems

## Compose with other skills

- Load `lore-bible-architect` when the location design depends on broader canon expansion.
- Load `faction-voice-keeper` when diaries, terminals, radio text, or archive fragments
  need a specific authored voice.

## Boundaries

- Do not use this as the main skill for abstract lore-bible restructuring. Use `lore-bible-architect`.
- Do not treat local site interpretation as locked world truth by default.
- Do not generate interchangeable ruins; each POI should carry narrative through place, not only exposition.
