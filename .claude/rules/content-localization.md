---
paths:
  - "data/**/*.{tres,res}"
  - "locale/**/*"
  - "core/autoloads/*registry*.gd"
  - "core/entities/**/*.{gd,tres,res}"
  - "scenes/ui/**/*.{gd,tscn}"
---

# Content And Localization Rules

- Content must enter through data resources, registries, localization keys, and mod-compatible extension paths. Do not hardcode gameplay content in scripts.
- Player-facing text must use localization keys. Do not add raw Russian or English UI text in GDScript or data resources.
- Use `content-pipeline-author` for items, buildings, recipes, flora, POIs, and registry/data wiring.
- Use `localization-pipeline-keeper` when adding or changing any visible text, tooltip, label, menu copy, tutorial text, or content display name.
- Validate both Russian and English locale coverage when new keys are introduced.
- If content affects balance, progression, or resource pressure, route through `balance-simulator` before coding.
