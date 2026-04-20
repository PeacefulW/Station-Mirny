# Task: Rimworld Autotile Generator Runtime Export Upgrade

Spec or source:
- user request in current Codex thread
- [rimworld_autotile_generator.html](/C:/Users/peaceful/Station%20Peaceful/Station%20Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator.html)

Current iteration:
- Iteration 10 - Material Layer Stack (v2)

Status:
- completed

Done:
- Task-local tracker created for the four requested iterations.
- Iteration 1 completed: old inline script is disabled in the HTML and replaced with a dedicated runtime-export pipeline script.
- Iteration 1 completed: preview modes `Albedo`, `Mask`, `Shape Height`, `Shape Normal`, `Shader Composite` now run from one JS pipeline.
- Iteration 1 completed: atlas exports for `Albedo`, `Mask`, and `Shape Normal` are wired.
- Iteration 2 completed: procedural `Top Modulation` and `Face Modulation` maps are generated and exported.
- Iteration 2 completed: `2x2` tiling preview for top and face is wired in the UI.
- Iteration 3 completed: `Shader Composite` mode and `JSON Material Recipe` export are wired.
- Iteration 4 completed: shape controls `backRimRatio`, `northRimThickness`, `faceSlope`, and `innerCornerMode` now affect runtime tile assembly.
- Current implementation lives in `rimworld_autotile_generator_runtime_export.js`, while the legacy inline script remains commented out for rollback safety.
- Iteration 5 completed: `Top tint opacity`, `Face tint opacity`, and `Base tint opacity` sliders added to the generator UI.
- Iteration 5 completed: when a user texture is loaded, tint can now be blended from `0` to `100` instead of always fully recoloring the image.
- Iteration 6 completed: `Shader Composite` preview on the map now renders from world-space sampling instead of drawing pre-baked per-tile composite canvases.
- Iteration 6 completed: continuous base preview and continuous top/facade sampling were added so the map preview matches intended shader behavior more closely and no longer shows obvious tile-square reset artifacts by default.
- Iteration 7 completed: staged rebuild, draft preview, cache, HiDPI presentation, Undo/Redo, JSON import, and pointer-capture stability were added.
- Iteration 8 completed: collapsible groups, control search, tooltips, drag-drop textures, preview zoom/pan, hotkeys, custom presets, session restore, and ZIP export were added.
- Iteration 9 completed: `state.materialLayers` is now the authoritative editor-side material layer stack for ordered material layering.
- Iteration 9 completed: five starter layers (`brick`, `plank`, `stoneCluster`, `snowDrift`, `cracks`) are available through a reorderable UI with enable, strength, blend, mask, and height contribution controls.
- Iteration 9 completed: layer stack state is now serialized through JSON recipe export/import, custom presets, and last-session restore.
- Iteration 10 completed: the v2 layer library adds `moss`, `rivets`, `runes`, `puddles`, `debris`, `rust`, `sand`, `concrete`, `mud`, `hex`, and `cobblestone`.
- Iteration 10 completed: the editor can now add and remove material layers from the stack through a library picker.
- Iteration 10 completed: `noise presets`, `biome palettes`, lightweight texture-derived tint extraction, and directional weathering via `sun azimuth` are wired into the authoring flow.

Remaining:
- Manual browser-side visual verification is still recommended for final feel tuning.
- If visual seams, palette surprises, or performance edge-cases remain, the next pass is artistic tuning rather than missing wiring.

Canonical docs to verify:
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/docs/README.md` - repo entrypoint already checked.
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/docs/00_governance/WORKFLOW.md` - workflow and closure contract already checked.
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/docs/00_governance/ENGINEERING_STANDARDS.md` - visual tool stays presentation-only; no runtime boundary drift expected.

Latest proof:
- `node --check C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js`
- grep verification on HTML + JS confirms requested controls, exports, and preview modes are present.
- grep verification on HTML + JS confirms `topTintOpacity`, `faceTintOpacity`, `baseTintOpacity`, and tint blending logic are present.
- grep verification on JS confirms `drawContinuousBasePreview`, `globalPreviewOffsets`, and world-space `paintLayeredTile(..., originX, originY)` preview path exist.
- `git diff --check -- C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator.html C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator_active_epic.md C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator_iteration_9_brief.md`
- grep verification on HTML + JS confirms `materialLayers`, `renderMaterialLayerControls`, `buildLayeredMaterialMap`, `layerStack`, and recipe `version: 4` are present.
- `git diff --check -- C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator.html C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator_active_epic.md C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator_iteration_10_brief.md`
- grep verification on HTML + JS confirms `layerLibraryType`, `addMaterialLayer`, `removeMaterialLayer`, `noisePreset`, `applyNoisePreset`, `extractPaletteFromTextures`, `sunAzimuth`, and recipe `version: 5` are present.

Latest closure report:
- Iteration 10 completed in-thread with static verification; manual browser verification still pending.
