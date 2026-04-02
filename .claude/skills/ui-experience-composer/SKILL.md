---
name: ui-experience-composer
description: >
  Shape Station Mirny UI work as game-feel, readability, and atmosphere instead
  of generic interface polish. Use when the user asks "сделай интерфейс
  красивее", "улучши HUD", "сделай меню атмосфернее", "хочу чтобы UI ощущался
  лучше", mentions readability, menu mood, HUD feel, or wants player-facing
  presentation to reinforce the sanctuary fantasy from `docs/01_product/GAME_VISION_GDD.md`
  and `docs/01_product/NON_NEGOTIABLE_EXPERIENCE.md`.
---

# UI Experience Composer

Use this skill for Station Mirny UI composition, feel, and readability work.

This skill owns the player-facing experience shape of menus, HUD, overlays, and
other interface surfaces where layout, hierarchy, motion, and visual mood must
support the game's core fantasy instead of defaulting to generic sci-fi UI.

## Read first

- `docs/01_product/GAME_VISION_GDD.md`
- `docs/01_product/NON_NEGOTIABLE_EXPERIENCE.md`

## What this skill does

1. Translate UI requests into experience goals such as sanctuary, pressure,
   preparedness, relief, or controlled urgency.
2. Preserve functional readability while making the interface feel authored and
   distinctly Station Mirny.
3. Use hierarchy, spacing, emphasis, and motion to support the loop of prepare,
   risk, return, and recovery.
4. Keep visual composition work separate from wording and localization concerns.

## Default workflow

1. Identify the interface surface: sanctuary/base management, expedition prep,
   in-field pressure, warning state, or meta menu.
2. Map the requested change to the product pillars in `GAME_VISION_GDD.md` and
   the experience filters in `NON_NEGOTIABLE_EXPERIENCE.md`.
3. Decide what the player must notice first, what can stay quiet, and where the
   UI should feel calm versus tense.
4. Shape layout, density, icon rhythm, animation, and emphasis around that
   emotional goal instead of polishing every element equally.
5. If the request also changes labels, tutorials, or message wording, compose
   with `ui-copy-tone-keeper` rather than solving copy tone here.

## Typical smells

- the UI looks like interchangeable sci-fi software instead of Station Mirny
- every panel carries the same urgency, so tension and relief blur together
- atmosphere is added by clutter rather than by hierarchy and contrast
- readability gets worse because decorative treatment outranks player task flow
- the interface feels pleasant but does not reinforce sanctuary, exposure, or return-home relief

## Compose with other skills

- Load `sanctuary-contrast-guardian` when the request affects the inside-safe /
  outside-hostile contrast, lighting cues, or emotional readability of safety.
- Load `ui-copy-tone-keeper` when buttons, HUD messages, tutorials, or other
  player-facing text are part of the request.
- Load `brainstorming` when the request is still vague and should stay in design
  exploration before implementation.

## Boundaries

- Do not use this as the main skill for wording, terminology, or localization-ready
  player-facing copy. Use `ui-copy-tone-keeper`.
- Do not treat a prettier layout as success if the interface stops supporting
  gameplay clarity under pressure.
- Do not flatten Station Mirny into a neutral productivity UI with no shelter,
  dread, or return-home relief.
