---
name: faction-voice-keeper
description: >
  Maintain distinct voice, ideology, terminology, and subtext for Station Mirny
  factions, archives, and diegetic text sources. Use when the user asks for
  "голос фракции", "архивный лог", "дневник", "тон передачи", "текст от лица
  фракции", "archive log", "transmission tone", "faction voice", or any
  in-world writing that must stay consistent with `docs/03_content_bible/lore/canon.md`
  without turning speaker speculation into locked canon.
---

# Faction Voice Keeper

Use this skill for in-world voice control and diegetic writing.

This skill owns tone, ideology, vocabulary, and implied worldview for factions,
archives, terminals, transmissions, and other authored voices inside Station Mirny.

## Read first

- `docs/03_content_bible/lore/canon.md`
- `docs/03_content_bible/lore/open_questions.md`
- `docs/01_product/GAME_VISION_GDD.md`

## What this skill does

1. Identify who is speaking, what they know, and what they are hiding.
2. Keep terminology, ideology, and emotional texture consistent with Station Mirny canon.
3. Distinguish narrator truth from character belief, propaganda, error, or fear.
4. Preserve room for unresolved lore by keeping uncertain claims inside the speaker's perspective.

## Default workflow

1. Read `canon.md` and note the locked truths the speaker cannot contradict.
2. Decide the source class: faction memo, archive log, engineering note, distress call,
   religious fragment, terminal text, or another diegetic channel.
3. Define the voice signature: vocabulary, sentence rhythm, emotional temperature,
   taboo words, and what this speaker refuses to say directly.
4. Mark any uncertain or expandable material as viewpoint-limited interpretation,
   not as objective world truth.
5. If the request spans multiple sources, keep each source visibly distinct instead
   of flattening them into one neutral author voice.

## Typical smells

- every faction sounds like the same neutral sci-fi narrator
- a log suddenly knows the full late reveal before the canon cadence allows it
- terminology drifts and breaks the world's internal language
- speculative details are written as hard canon instead of speaker belief

## Compose with other skills

- Load `lore-bible-architect` when the request changes the underlying lore structure
  or needs canon-aware worldbuilding first.
- Load `poi-story-seeder` when the text is tied to a specific ruin, terminal, or
  environmental story location.

## Boundaries

- Do not use this as the main skill for broad lore-bible restructuring. Use `lore-bible-architect`.
- Do not treat character voice as proof of canon. `docs/03_content_bible/lore/canon.md`
  remains the locked truth.
- Do not flatten unresolved material from `open_questions.md` into definitive exposition.
