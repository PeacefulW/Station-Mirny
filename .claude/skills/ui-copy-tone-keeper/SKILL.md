---
name: ui-copy-tone-keeper
description: >
  Keep Station Mirny player-facing copy consistent with tone, clarity, and the
  project's localization-ready UI model. Use when the user asks to rewrite
  button text, HUD messages, menu labels, tooltips, tutorial/system text, or
  says "перепиши текст интерфейса", "кнопки звучат плохо", "нужны лучшее HUD
  сообщения", "menu copy", or "UI wording". This skill keeps wording aligned
  with `docs/01_product/GAME_VISION_GDD.md` and `docs/01_product/NON_NEGOTIABLE_EXPERIENCE.md`
  without collapsing into vague flavor text.
---

# UI Copy Tone Keeper

Use this skill for Station Mirny player-facing interface writing.

This skill owns button labels, HUD messages, menu text, tutorial phrasing, and
other player-facing UI copy where clarity, tone, and future localization
discipline must work together.

## Read first

- `docs/01_product/GAME_VISION_GDD.md`
- `docs/01_product/NON_NEGOTIABLE_EXPERIENCE.md`

## What this skill does

1. Keep UI copy clear under pressure while sounding like Station Mirny rather
   than generic app or generic military-sci-fi language.
2. Separate action clarity from atmosphere so warnings, instructions, and labels
   stay readable first and flavorful second.
3. Preserve terminology that supports sanctuary, exposure, survival pressure,
   and engineered control.
4. Keep wording structured so it can survive future localization work cleanly.

## Default workflow

1. Identify the copy surface: urgent HUD state, calm base menu, tutorial/help,
   warning/alert, or systemic feedback message.
2. Decide what the player must understand immediately, what emotional color is
   still useful, and what tone would confuse the action.
3. Write the shortest text that preserves both clarity and Station Mirny mood.
4. Avoid idioms, puns, or layout-dependent wording that would age badly or make
   future localization harder.
5. If the task also changes layout, composition, or state readability, compose
   with `ui-experience-composer` and `sanctuary-contrast-guardian`.

## Typical smells

- a warning sounds atmospheric but hides the action the player needs to take
- button labels are vague, overdramatic, or interchangeable
- every UI string speaks in the same dramatic voice regardless of urgency
- copy introduces generic corporate or shooter jargon that weakens Station Mirny's tone
- text depends on one language's wordplay instead of clear transferable meaning

## Compose with other skills

- Load `ui-experience-composer` when wording changes are part of a broader UI
  flow, hierarchy, or menu-feel revision.
- Load `sanctuary-contrast-guardian` when the wording must reinforce the safe
  interior versus hostile exterior contrast.
- Load `localization-pipeline-keeper` when the task introduces shipped player-facing
  strings that must go through the localization workflow.

## Boundaries

- Do not use this as the main skill for visual layout, spacing, animation, or
  palette decisions. Use `ui-experience-composer`.
- Do not use UI copy as a place to smuggle in new canon truths or lore reveals.
- Do not sacrifice immediate comprehension for flavor.
