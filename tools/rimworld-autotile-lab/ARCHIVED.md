# ARCHIVED

Этот инструмент архивирован 2026-05-17 в рамках перехода на
Variant D v2 (Godot-native terrain workbench).

It is a historical reference and not a runtime source of truth.

- Active spec:
  `docs/02_system_specs/world/biome_visual_authoring_variant_d_v2.md`.
- Superseded v1 spec:
  `docs/02_system_specs/world/biome_visual_authoring_variant_d.md`.
- Implementation iterations:
  `docs/04_spec_iteration/biome_visual_authoring_variant_d_iterations.md`.
- Параметры визуала и материал переехали в:
  `data/terrain_visual/recipes/rock_default.tres`.
- Authoring новый — через Godot editor plugin:
  `addons/biome_visual_authoring_v2/`.

**Не вноси сюда изменения.** Если нужно извлечь дополнительный
параметр — это change-request к spec Variant D v2, не правка этого
инструмента. Старый desktop_app не является runtime dependency.

Окончательное удаление этой директории — отдельная follow-up
таска (Spec секция 25c), будет выполнено после git tag
`archive/rimworld-autotile-lab-v1`.
