---
name: localization-pipeline-keeper
description: >
  Enforce the Station Mirny localization pipeline whenever a task adds or
  changes player-facing text. Use when the user asks for "локализация",
  "добавь перевод", "новый текст", "button text", "localized content",
  "UI wording", or any change where new visible strings, localization keys, or
  translation coverage must be wired correctly. This skill keeps work aligned
  with `docs/02_system_specs/meta/localization_pipeline.md`.
---

# Localization Pipeline Keeper

Use this skill for Station Mirny localization-safe text work.

This skill owns the rule that gameplay and content ship keys and arguments, not
scattered final strings. It helps the agent keep UI, data resources, and
gameplay messages inside the same localization contract.

## Read first

- `docs/02_system_specs/meta/localization_pipeline.md`
- `docs/00_governance/AI_PLAYBOOK.md`
- `docs/00_governance/ENGINEERING_STANDARDS.md`

## What this skill does

1. Keep player-facing text out of gameplay logic and out of hidden one-off
   text islands.
2. Require localization keys, structured args, and predictable translator-facing
   locations for new visible text.
3. Keep resource definitions language-agnostic by storing keys rather than
   final translated strings.
4. Preserve Russian and English coverage expectations for newly shipped content
   unless the task explicitly says otherwise.

## Default workflow

1. Identify every player-visible string the task introduces or changes: UI
   label, tooltip, command result, lore snippet, content name, or tutorial copy.
2. Decide which layer should own the key: UI, content/resource data, or
   gameplay message contract.
3. Add or update localization keys instead of embedding final text in code.
4. Ensure UI and commands consume `message_key` / `message_args`-style data or
   equivalent localization-safe wiring.
5. Verify that translation coverage and missing-key behavior remain explicit,
   not accidental.

## Typical smells

- raw visible text appears in code "temporarily"
- data resources store final translated names/descriptions instead of keys
- one feature invents its own private translation structure
- localization-sensitive sentences are stitched together by string concatenation
- English and Russian coverage silently diverge for shipped player-facing text

## Compose with other skills

- Load `ui-copy-tone-keeper` when wording quality and tone are part of the task.
- Load `content-pipeline-author` when the text belongs to items, buildings,
  recipes, flora, POIs, or other data-defined content.
- Load `faction-voice-keeper` when localized text must preserve a specific
  in-world voice or archive tone.
- Load `playtest-triage` when player feedback suggests a text or onboarding
  issue but the root cause is still unclear.

## Boundaries

- Do not use this as the main skill for purely visual UI composition.
- Do not turn localization work into a lore rewrite or a balance pass.
- Do not accept raw shipped strings in gameplay code just because the task is
  "only placeholder text".
