---
name: content-pipeline-author
description: >
  Add or change Station Mirny items, buildings, recipes, flora, POIs, and
  similar content through the correct registry, data, localization, and
  mod-extension path. Use when the user asks for "новый предмет",
  "новую постройку", "новый рецепт", "добавь контент", "content wiring",
  "new content definition", or any task where content should be added without
  hardcoding it into gameplay scripts.
---

# Content Pipeline Author

Use this skill for Station Mirny content-definition and content-wiring work.

This skill owns the path from "we need new content" to "the content is added in
the right data/registry/localization lane" without turning the task into ad hoc
script edits or hidden one-off data islands.

## Read first

- `docs/00_governance/AI_PLAYBOOK.md`
- `docs/00_governance/ENGINEERING_STANDARDS.md`
- `docs/00_governance/SYSTEM_INVENTORY.md`
- `docs/02_system_specs/meta/modding_extension_contracts.md`
- `docs/02_system_specs/meta/localization_pipeline.md`
- the relevant content bible or system spec for the content domain

## What this skill does

1. Route new or changed content through the correct registry and resource layer.
2. Preserve stable IDs, namespacing, and mod-extension compatibility.
3. Keep player-facing names, descriptions, and messages in the localization
   pipeline rather than raw strings in code or resources.
4. Distinguish between content-definition work, content-wiring work, and real
   gameplay-system changes so the task stays scoped.

## Default workflow

1. Classify the content type: item, recipe, building, flora, POI, registry
   definition, or mixed content bundle.
2. Read `SYSTEM_INVENTORY.md` and the relevant spec to confirm the canonical
   registry/service path instead of inventing a new one.
3. Add or update data/resources with stable IDs and the smallest required
   wiring through existing registries, factories, or content loaders.
4. Route any player-facing text through localization keys and compose with
   `localization-pipeline-keeper` if visible text is introduced.
5. Check whether the task also affects balance, save identity, or lore-facing
   canon, and compose with the relevant companion skills before finishing.

## Typical smells

- gameplay logic loads content by hardcoded path instead of registry lookup
- new content depends on raw strings instead of localization keys
- content identity depends on display text, file order, or scene paths
- one "small content task" quietly rewrites core systems instead of extending
  the existing data-driven seam
- a new POI, flora family, or building variant ignores the project content docs
  and invents private rules

## Compose with other skills

- Load `localization-pipeline-keeper` when the task adds player-facing strings.
- Load `balance-simulator` when the content changes pacing, cost, power/O2
  pressure, expedition value, or reward loops.
- Load `save-load-regression-guard` when the new content adds runtime state or
  affects save/load identity.
- Load `lore-bible-architect`, `faction-voice-keeper`, or `poi-story-seeder`
  when the content carries canon-sensitive lore or place storytelling.

## Boundaries

- Do not use this as the main skill for freeform lore writing or faction voice.
- Do not skip registry, localization, or ID discipline because the content task
  looks "small".
- Do not smuggle in a gameplay subsystem rewrite when the task is only to add
  or wire content.
