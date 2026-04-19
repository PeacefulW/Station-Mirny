# Task: Rimworld Autotile Generator Runtime Export Upgrade

Spec or source:
- user request in current Codex thread
- [rimworld_autotile_generator.html](/C:/Users/peaceful/Station%20Peaceful/Station%20Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator.html)

Current iteration:
- Iteration 6 - Shader Composite world-space preview fix

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

Remaining:
- Manual browser-side visual verification is still recommended for final feel tuning.
- If visual seams or shape edge-cases remain, the next pass is artistic tuning rather than missing wiring.

Canonical docs to verify:
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/docs/README.md` - repo entrypoint already checked.
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/docs/00_governance/WORKFLOW.md` - workflow and closure contract already checked.
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/docs/00_governance/ENGINEERING_STANDARDS.md` - visual tool stays presentation-only; no runtime boundary drift expected.

Latest proof:
- `node --check C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js`
- grep verification on HTML + JS confirms requested controls, exports, and preview modes are present.
- grep verification on HTML + JS confirms `topTintOpacity`, `faceTintOpacity`, `baseTintOpacity`, and tint blending logic are present.
- grep verification on JS confirms `drawContinuousBasePreview`, `globalPreviewOffsets`, and world-space `paintLayeredTile(..., originX, originY)` preview path exist.

Latest closure report:
- pending
