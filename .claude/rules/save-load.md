---
paths:
  - "core/autoloads/save_manager.gd"
  - "core/**/*save*.gd"
  - "core/**/save_*/*.gd"
  - "docs/02_system_specs/**/*save*.md"
---

# Save Load Rules

- Use `save-load-regression-guard` for any new runtime state, restore behavior, save collector, save applier, slot metadata, or persistence boundary change.
- Separate generated/base data from runtime diff. Save data, not implicit scene state.
- New mutable runtime state must answer: what persists, what is regenerated, who collects it, who applies it, and how old saves get defaults.
- Do not write directly to `SaveManager.current_slot`, `SaveManager.is_busy`, or pending-load internals. Use the sanctioned entry points described in `docs/02_system_specs/meta/save_and_persistence.md` and the live runtime docs.
- Any save/load semantic change requires a canonical-documentation check before closure.
