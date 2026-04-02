---
name: lore-bible-architect
description: >
  Expand or reorganize Station Mirny lore while preserving locked canon from
  `docs/03_content_bible/lore/canon.md`. Use when the user asks "как расширить
  лор", "переделай лор", "перепиши лор", "придумай глубже мифологию",
  "собери лор-библию", "rewrite lore", "lore bible", or wants canon-aware
  worldbuilding that must separate locked truth from open expansion space.
---

# Lore Bible Architect

Use this skill for canon-aware lore architecture.

This skill owns high-level lore expansion, lore restructuring, and canon-safe
worldbuilding support for Station Mirny.

## Read first

- `docs/03_content_bible/lore/canon.md`
- `docs/03_content_bible/lore/open_questions.md`
- `docs/01_product/GAME_VISION_GDD.md`

## What this skill does

1. Extract the locked truths that the request must not contradict.
2. Separate canon facts from expandable space and unresolved questions.
3. Propose additions that reinforce Station Mirny's tone, reveal cadence, and
   player-facing mystery.
4. Keep new material tagged as locked canon, safe expansion, or open question
   instead of silently upgrading ideas into truth.

## Default workflow

1. Read `canon.md` first and write down the locked premises that constrain the task.
2. Read `open_questions.md` to identify what can still expand without redefining canon.
3. Preserve the current canon around the Ark, the Engineer, spores, Precursors,
   and the late ancestral reveal unless the human explicitly asks for a canon change.
4. When reorganizing lore, split the output into clear buckets such as `Locked canon`,
   `Expansion space`, and `Open questions`.
5. If a proposed idea would change locked truth, stop and frame it as an explicit
   canon-change proposal rather than blending it into normal lore work.

## Typical smells

- new lore collapses the mystery too early and skips the three-stage reveal cadence
- atmospheric details quietly contradict locked world truth
- open questions are presented as settled canon
- lore expansion becomes generic sci-fi instead of lonely, severe, melancholic Station Mirny

## Compose with other skills

- Load `faction-voice-keeper` when the request needs a specific archive, faction,
  or transmission voice.
- Load `poi-story-seeder` when the lore must land in ruins, POIs, terminals, or
  environmental storytelling.
- Load `brainstorming` when the request is still vague and should stay in design space.

## Boundaries

- Do not use this as the main skill for line-level diegetic writing that needs a
  specific in-world speaker voice. Use `faction-voice-keeper`.
- Do not use this as the main skill for location-tied ruin history or discovery
  beats. Use `poi-story-seeder`.
- Do not silently rewrite locked canon from `docs/03_content_bible/lore/canon.md`.
