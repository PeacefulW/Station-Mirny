# Epic: 2D Mountain Plateau Visual Recovery

**Source**: user directive in current Codex thread
**Started**: 2026-05-21
**Current iteration**: 2D plateau facade/rim pass
**Status**: in_progress

## Working Rule

- Return to 2D mountains and solve the original visual goal deliberately.
- No hidden compatibility fallbacks for required native world data paths.
- Gameplay truth stays the current 2D grid: terrain ids, walkability, mining, save/load.
- The new visual direction should be tested in isolated dev scenes before touching runtime gameplay.

## Current Goal

Create a stable 2D development scene that renders a real mountain from the
current in-game world generation. This scene is the baseline for later plateau /
organic cliff experiments.

## Done

- Rejected the 3D terrain migration direction for now.
- Created `res://scenes/dev/mountain_2d_dev_scene.tscn`.
- Created `res://scenes/dev/mountain_2d_dev_scene.gd`.
- Created `res://tools/mountain_2d_dev_scene_smoke_test.gd`.
- Created dev-only `res://scenes/dev/mountain_plateau_2d_layer.gd`.
- Wired the plateau layer into `res://scenes/dev/mountain_2d_dev_scene.tscn` through
  `mountain_2d_dev_scene.gd`.
- The dev scene:
  - instantiates native `WorldCore`;
  - uses current `WorldRuntimeConstants.WORLD_VERSION`;
  - uses current hard-coded mountain/foundation settings and current lake balance data;
  - resolves the current-world spawn tile;
  - scans nearby generated chunks for a real mountain chunk;
  - renders a 5x5 chunk window around the chosen target through existing `ChunkView`;
  - renders a first-pass organic plateau mask above the TileMap baseline;
  - supports dev toggles: `P` plateau layer, `T` TileMap baseline, `E` plateau edge debug;
  - exposes a debug snapshot for smoke verification.

## Current Iteration

2D plateau silhouette/mask pass:

- Keep the scene visual-only.
- Do not change `WorldStreamer`, `ChunkView`, mining, save/load, or gameplay truth.
- Use the current in-game chunk packet data as the source of truth.
- Prove that real mountain tiles can be presented as a single organic 2D plateau
  mask before adding cliff-band material work.

## Remaining

- Visually inspect `res://scenes/dev/mountain_2d_dev_scene.tscn` in Godot.
- Decide whether the first organic silhouette is good enough as the base.
- Validate the current cliff pass: lab-default south facade, rim, outline, and
  exported `top.png` / `face.png` texture overlays.
- After the cliff band is accepted, replace debug colors with texture/material sampling.

## Non-Goals For Current Iteration

- No mining visual updates.
- No runtime cutover.
- No player/building integration.
- No save/load schema changes.
- No world generation changes.
- No formal documentation update until the visual direction is accepted.

## Latest Visual Direction

- Use `tools/rimworld-autotile-lab/desktop_app` mountain defaults as the visual
  baseline, scaled from 128px lab tiles to the game's 64px logical tiles.
- Keep generation/gameplay truth untouched: the dev layer consumes only current
  generated mountain tiles.
- Current scaled defaults:
  - south facade height: `32px`;
  - rim width: `8px`;
  - outline width: `3px`;
  - contour/corner round: `16px`;
  - roughness: `5px`;
  - north/side projection: `0px`.
- Use exported textures from `C:/Users/peaceful/Station Peaceful/Новая папка (3)`:
  - `top.png` for plateau top;
  - `face.png` for facade.
- Current implementation builds smoothed boundary loops from generated mountain
  tiles and draws the top/rim/facade from those loops, so the dev scene no
  longer depends on visible square tile rectangles for the mountain silhouette.
- The rim/facade are drawn before the top fill, so the dark edge no longer sits
  on top of the plateau surface.
- The contour now applies closed-loop Chaikin smoothing and drops the old
  tile-by-tile debris pass to avoid visible 64px rhythm.
- The dev scene now hides the old `ChunkView` baseline by default while the
  plateau layer is enabled. Press `T` only for comparison. The plateau layer
  draws its own ground backdrop so old square mountain tiles cannot bleed
  through trimmed organic corners.
- Bottom facade/outline bands use an outward contour offset instead of a fixed
  vertical `+Y` offset, so they track the same smoothed mountain boundary on
  diagonal and side edges.
- The per-segment quad strip attempt was rejected because it produced visible
  eyelash-like radial strips along curved cliffs. The prototype is back to
  continuous contour bands, and static cliff shadows were removed completely
  because the game is expected to light cliffs dynamically through normals.
- The facade now follows the generator default direction model: only
  south-facing contour normals project the cliff face. Northern and side-facing
  contour parts keep only the rim/bevel edge, with no full-height facade band.
- The south facade projection now drops vertically in screen space instead of
  expanding along outward normals. This removes sharp curled hooks at
  south/side transitions and better matches the lab reference where only
  `south height` is non-zero.
- South facade height is now sampled from a wider contour window and smoothed
  around the closed loop before projection. This treats stair-step diagonals as
  one gradual transition instead of alternating side/south pockets.
- After re-reading `tools/rimworld-autotile-lab/desktop_app/core/src/render.rs`,
  the dev layer now follows the front-only SDF reference more directly: the
  facade is a vertical projection of the top silhouette. It no longer derives
  facade shape from local south/side contour weights, because the lab explicitly
  tests that front-only face pixels must be supported by top coverage above.
- Added a second dev-only presentation path:
  `res://scenes/dev/mountain_plateau_2d_raster_layer.gd`. It builds a raster
  coverage mask from the same generated mountain tiles, applies a small
  SDF-like blur/threshold pass to hide tile stairs, and renders top/rim/south
  facade into one `ImageTexture`.
- The dev scene now defaults to the raster layer (`R`), keeps the older vector
  contour layer available for comparison (`P`), and keeps the TileMap baseline
  available for comparison (`T`).
- The raster layer is intentionally a dev-only visual proof, not the final
  runtime path. The heavy 1:1 raster mask/blur/projection compute now runs in
  native GDExtension through `WorldCore.build_mountain_plateau_raster_image`;
  GDScript only loads textures, owns the tuning panel, and publishes the
  returned `ImageTexture`.
- Raster visual review quality was raised after the first blurred pass:
  `SAMPLE_STEP_PX` changed from `4.0` to `2.0`, the tile/facade/blur sample
  counts are now derived from pixel sizes, and the final raster texture uses
  nearest filtering to avoid extra presentation blur.
- Close-up raster quality was raised again for FHD-style visual review:
  `SAMPLE_STEP_PX` is now `1.0`, so one rendered image pixel maps to one world
  pixel. Top and rim alpha thresholds were narrowed so the SDF blur rounds the
  shape but no longer turns the rim/outline into a broad blurry band.
- Added a dev-only raster tuning panel to
  `res://scenes/dev/mountain_2d_dev_scene.tscn`. It exposes sliders for
  facade height, rounding, thresholds, edge warp, texture scale/blend, macro
  variation, rim strength, outline strength, and face darkening.
- The tuning panel is intentionally manual-apply: moving sliders only changes a
  pending preset, and `Apply` triggers the expensive 1:1 raster rebuild. `Save`
  and `Load` use `res://scenes/dev/mountain_2d_raster_preset.json`, so accepted
  local settings can be reused in the dev scene without changing runtime.
- The raster layer now caches preset values at the start of each render pass.
  This keeps the dev proof usable while preserving the no-runtime-cutover rule.
- Native rasterization moved the dev scene smoke from several minutes to single
  digits while preserving 1:1 raster output. The runtime cutover still needs a
  proper cached dirty visual product, not a direct copy of this dev scene.
- The tuning panel was widened and localized to Russian for dev usability.
  Each raster parameter now has a Russian label, section grouping, a wider
  slider, and a numeric `SpinBox` for precise edits before pressing
  `Применить`.

## Latest Proof

- `Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tools/mountain_2d_dev_scene_smoke_test.gd`
  - Passed with `mountain_2d_dev_scene_smoke_test: OK`.
  - Confirms the dev scene loads, finds generated mountain chunks, builds the
    vector plateau layer, and builds the raster/SDF proof layer with top,
    facade, rim, non-empty image output, and `sample_step_px <= 1.0`.
  - The 1:1 GDScript proof is expensive: the headless smoke run currently takes
    roughly 174 seconds and must not be treated as the final runtime path.
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tools/mountain_2d_dev_scene_smoke_test.gd`
  - Passed with `mountain_2d_dev_scene_smoke_test: OK` after adding the tuning
    panel and preset contract.
  - Current 1:1 GDScript proof smoke time is roughly 217 seconds; this is
    acceptable for dev tuning, but still not acceptable as the final runtime
    rendering path.
- `python -m SCons -Q platform=windows target=template_debug`
  - Passed after adding `gdextension/src/mountain_plateau_raster.cpp`.
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tools/mountain_2d_dev_scene_smoke_test.gd`
  - Passed with `mountain_2d_dev_scene_smoke_test: OK` after moving raster
    build to native.
  - Runtime dropped to about `7.7s` including Godot startup.
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/Godot_v4.6.2-stable_win64_console.exe --headless --path . --scene res://scenes/dev/mountain_2d_dev_scene.tscn --quit-after 2`
  - Passed in about `7.4s` including Godot startup.
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tools/mountain_2d_dev_scene_smoke_test.gd`
  - Passed after the Russian tuning panel update.
  - Confirms the panel exposes Russian labels, wide sliders, and one numeric
    input per raster slider.
- `C:/Users/peaceful/Station Peaceful/Station Peaceful/Godot_v4.6.2-stable_win64_console.exe --headless --path . --scene res://scenes/dev/mountain_2d_dev_scene.tscn --quit-after 2`
  - Passed after the Russian tuning panel update.
- `Godot_v4.6.2-stable_win64_console.exe --headless --path . --scene res://scenes/dev/mountain_2d_dev_scene.tscn --quit-after 2`
  - Passed without scene-load errors.
- `git diff --check`
  - Passed.
