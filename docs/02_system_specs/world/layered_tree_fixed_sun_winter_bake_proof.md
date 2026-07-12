---
title: Layered Tree Fixed Sun and Winter Bake Proof
doc_type: system_spec
status: approved
owner: art+engineering
source_of_truth: true
version: 2.9
last_updated: 2026-07-12
related_docs:
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../meta/system_api.md
  - world_dynamic_lighting_2d.md
  - plains_trees_presentation.md
  - ../../art/layered_asset_bake_contract.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Layered Tree Fixed Sun and Winter Bake Proof

## Purpose

Prove the revised layered-tree art direction on `tree_01` before any production
asset is replaced:

- screen-space sun comes from north-west;
- the baked cast shadow extends south-east;
- the root/anchor end of the shadow stays pinned and only its far end stretches
  for low-sun dawn/dusk presentation;
- the complete physical Cycles cast shadow from all GLB geometry is preserved;
  no root caster is disabled, no root-footprint alpha is erased, and no synthetic
  contact shadow is added; the tree and shadow share one invariant world-space
  anchor while length changes move only the far end of the physical shadow;
- the visible south/south-east side of the tree keeps a soft self-shadow;
- winter keeps the complete foliage silhouette, freezes/desaturates the leaves,
  adds a light crown frost, and places fluffy white snow on supported leaf and
  horizontal branch surfaces without turning the trunk and roots into a flat
  white silhouette.

## Gameplay Goal

At gameplay scale the tree should read as a stable volume under one coherent
light direction. Winter should read as snow resting on the object, not as a
white recolour of the whole tree.

## Scope

Iteration 1 is an offline authoring proof for source model:

`C:/Users/progi/project-Mirniy/tree glb/1.glb`

It may:

- add a separate proof bake profile without changing the current production v1
  profile;
- extend the layered-tree offline bake/postprocess path only where required by
  the proof;
- render and postprocess one `tree_01` proof under `artifacts/`;
- add focused offline contract tests and comparison/metrics artifacts;
- update this spec and documentation indexes.

Iterations 1B/1C additionally may use the existing dedicated dev lab to compare
proof states at gameplay scale. It may add lab-only asset/direction overrides,
debug controls, a lab-only winter shader, and automated screenshot probes.
It must not promote the proof into the production asset or runtime world path.

Iteration 1D may apply the visually accepted Iteration 1C profile to source
models `2.glb` through `6.glb` in an isolated batch-proof directory. Before the
full bakes it must render a `90/180 degree` orientation sheet and record the
single approved per-tree yaw exception explicitly instead of changing the
shared default yaw.

Iteration 2 is the explicitly authorized production promotion of the accepted
Iteration 1C/1D candidates. It may replace only the layered tree presentation
assets, add `tree_06` to the existing runtime variant list, promote the
full-foliage winter shaders, and make the tree shadow stretch read its fixed
south-east direction and `48 px` contact lock from asset metadata. It must not
change world placement, time authority, the real `DirectionalLight2D`, player
shadow, rocks, save data, or gameplay state.

Iteration 3 is an isolated `tree_01` brightness comparison requested after the
production promotion. It must render exactly three candidates without changing
production assets: A keeps the approved north-west/south-east compass and uses
exposure `0.8`; B keeps that compass, uses exposure `0.7`, and adds only a weak
symmetrical neutral ambient rig; C moves the key to approximately screen
`10 o'clock`, uses exposure `0.75`, and records the measured cast-shadow
direction. All candidates retain the complete physical cast shadow and real
Blender self-shadow.

Iteration 3A is an isolated camera-orbit diagnostic for candidate A. The source
tree, approved north-west Sun, exposure, and zero-fill lighting stay fixed
in world space; only the camera moves through eight compass viewpoints. The
west view must also be exported as a large standalone review image. It must not
promote candidate A or change production assets. Candidate B is explicitly
rejected because its ambient rig washes out the foliage self-shadow pattern.

Iteration 3B is an isolated low-rear-kicker proof based on candidate C. The
physical key returns to screen `10 o'clock`; a single soft Spot is placed low on
the opposite screen side and aimed upward at the middle/lower trunk. The Spot
casts no shadow and must not act as global ambient fill. A review sheet compares
measured dark-trunk luminance lifts of `0/2/4/6/8%`, with `2%` identified as the
user's primary candidate. Production assets remain read-only until explicit
visual selection.

Iteration 3C is an isolated evening-readability check for the `8%` Iteration 3B
candidate at gameplay hour `21:00`. It compares `0%` and `8%` under the exact
surface-night ambient floor `Color(0.03, 0.035, 0.05)`, with direct sun and
sun-cast shadow visibility at zero and no torch/local gameplay light. The raw
gameplay captures protect the outside-darkness contract; a separately labelled
gain image may reveal differences for analysis but is not visual acceptance.

Iteration 3D corrects the interpretation of the user's `21:00` wording: it
means a screen-clock Sun direction of `9 o'clock`, not gameplay nighttime. The
physical key must come from screen west, its measured physical cast shadow must
leave the root due east, and one low upward-aimed shadowless Spot must sit on
the opposite east side. The Spot is calibrated to a measured `8%` dark-trunk
luminance lift. Iteration 3C remains useful night-safety evidence but is not the
requested direction candidate.

Iteration 3E tests the next explicit clock-face request: `22:00` means the prior
screen `10 o'clock` physical Sun direction, not gameplay nighttime. It retains
candidate C's measured ESE cast direction and increases only the low opposite
shadowless Spot until dark-trunk luminance lift measures `12%`. The review must
compare `9 o'clock / 8%`, `10 o'clock / 8%`, and `10 o'clock / 12%` so direction
and fill strength remain visually separable.

Iteration 3F tests the explicit midpoint `9:30` clock-face direction with the
same measured `12%` dark-trunk lift. The physical cast shadow must be rendered
and measured near the expected `3:30` screen direction (`15 degrees` below due
east), not inferred from the light label. The review must show the complete tree
and shadow plus a `9:00 / 9:30 / 10:00` physical-shadow direction comparison.

Iteration 3G returns to the proven screen `10:00` Sun direction and changes only
the low opposite shadowless Spot calibration from `12%` to `20%` measured dark-
trunk luminance lift. It must preserve the same physical Cycles cast shadow and
strict Sun self-shadow, then compare `10:00 / 12%` directly against `10:00 /
20%` at identical framing. A full-tree composite must include the complete
physical shadow so the brighter candidate is judged without losing direction.

Iteration 4 is the explicit production promotion of the selected Iteration 3G
`10:00 / 20%` lighting rig across `1.glb` through `6.glb`. The bake must reuse
the exact Sun, exposure, low shadowless Spot geometry and energy proven on
`tree_01`, retain the complete physical Cycles shadow and full-foliage winter
outputs, preserve `90 degree` yaw for `tree_01` through `tree_05`, and preserve
the sole `180 degree` yaw exception for `tree_06`. Only production layered-tree
assets, the selected production bake profile, focused offline tooling/tests, and
the governing tree presentation docs may change. Runtime code, worldgen,
placement, saves, player shadows, rocks and the canonical visual-light owner
remain unchanged.

## Out of Scope

- rock or grass rebakes;
- runtime `TimeManager`, `DirectionalLight2D`, player shadow, world packet,
  placement, collision, save/load, or gameplay changes;
- a `world_version` bump.

## Related Documents

- `docs/art/layered_asset_bake_contract.md` owns the current production v1
  layered-asset contract.
- `docs/02_system_specs/world/plains_trees_presentation.md` owns tree
  presentation direction.
- `docs/02_system_specs/world/world_dynamic_lighting_2d.md` owns the visual sun.
- `docs/02_system_specs/progression/player_sun_shadow_v0.md` owns the player
  silhouette shadow.

## Dependencies

- Blender 5.1.2 or a compatible Blender build;
- readable `1.glb` source model;
- the existing layered-tree bake and postprocess tools;
- Pillow for offline mask/preview processing and tests.

## Data Model

The proof profile is authoritative only for this proof. It must explicitly
record:

- unique profile id and version;
- screen sun direction `north_west`;
- screen cast-shadow direction `south_east`;
- numeric Blender sun azimuth/elevations used by the proof;
- albedo key softness and fill energy used to separate readable back-side form
  from localized self-cast occlusion;
- root-pinned/stretch-only shadow semantics;
- calibrated proof root embed `0.011` and the invariant that all visible
  geometry remains above the ground receiver at `z=-0.012`; this leaves about
  `0.001` clearance for near-contact without receiver intersection;
- full physical root/trunk/canopy shadow casting from the source GLB;
- no postprocess attenuation or replacement inside the root footprint;
- separate foliage and trunk snow accumulation controls;
- windward/up-facing bias, root suppression, edge breakup, crown frost, and
  snow shading controls.

Current machine-readable proof fields are:

- `lighting.albedo_sun_elevation_degrees = 38`;
- `lighting.albedo_sun_angular_diameter_degrees = 4`;
- `lighting.fill_energy = 0` and `render.exposure = 0.5`; the rejected
  camera/south-side Area fill is not used to brighten the visible back side;
- `shadow_casters` is absent and `suppressed_shadow_casters` is empty;
- `postprocess.root_shadow_footprint` is absent;
- `lighting.fixed_shadow_direction_vector_screen = [0.707107, 0.707107]`;
- `runtime.shadow_contact_lock_source_px = 48`;
- Iteration 1C must retune lighting and snow fields from measured proof results;
- lab winter exposes no `leaf_drop_strength` axis; proof
  `postprocess.season.leaf_drop_enabled = false`.
- proof snow fades across the lower trunk/root zone from
  `root_full_until_offset_px = -96` to `root_zero_from_offset_px = -48`.

The dev lab exposes one reversible visual winter axis:

- `season_amount`: frozen foliage tint, crown frost, and supported snow
  accumulation.

The winter path must not reduce foliage alpha. Foliage-supported snow remains
attached to the complete leaf silhouette; woody branch snow remains visible on
plausible upper/horizontal surfaces. Frost is a lighter secondary response and
must not fill the full crown into an opaque white blob.

The GLB plus proof profile are authored inputs. Render passes, masks, metrics,
and previews are derived artifacts.

## Runtime Architecture

No production runtime architecture changes in Iteration 1 or 1B.

Layer classification:

- source GLB + proof profile: offline authored data;
- rendered PNG passes: derived presentation assets;
- dev lab materials and screenshot probes: derived validation-only presentation;
- gameplay/world/save state: untouched.

Single write owner: the offline layered-tree bake pipeline.

Dirty unit: one asset (`tree_01`).

## Event Contracts

None.

## Save / Persistence Contracts

None. The proof is presentation-only and is not saved by the game.

## Performance Class

- authoring work class: offline bake;
- runtime CPU/GPU change: none;
- target scale for this iteration: one source asset;
- escalation path after approval: batch offline rebake of explicitly approved
  assets, never runtime generation.

## Modding / Extension Points

No runtime extension surface changes. A later production profile must remain a
shared data-driven bake contract rather than per-asset hardcoded lighting.

## Allowed Files

- `docs/02_system_specs/world/layered_tree_fixed_sun_winter_bake_proof.md`
- `docs/README.md`
- `docs/02_system_specs/README.md`
- `tools/tree_atlas/layered_asset_bake_profile_v2_proof.json`
- `tools/tree_atlas/layered_tree_bake_profile.json`
- `tools/tree_atlas/blender_layered_tree_asset_bake.py`
- `tools/tree_atlas/postprocess_layered_tree_asset.py`
- `tools/tree_atlas/test_layered_asset_bake_contract.py`
- `tools/tree_atlas/test_layered_tree_postprocess.py`
- proof-specific focused tests under `tools/tree_atlas/`
- `tools/tree_atlas/build_layered_tree_proof_report.py`
- a proof-only Blender self-shadow diagnostic under `tools/tree_atlas/`
- `scenes/dev/layered_tree_asset_lab_scene.gd`
- `scenes/dev/layered_tree_asset_lab_scene.tscn`
- a lab-only shader under `scenes/dev/`
- `tools/layered_tree_asset_lab_scene_smoke_test.gd`
- a proof-specific lab render probe under `tools/`
- `artifacts/layered_tree_01_nw_winter_proof/**`
- a focused batch-proof/orientation runner under `tools/tree_atlas/`;
- `artifacts/layered_tree_nw_winter_batch_proof/**`.
- `artifacts/.gdignore`.
- `tools/tree_atlas/layered_tree_brightness_variants_manifest.json`;
- a focused brightness-variant runner, report builder, and test under
  `tools/tree_atlas/`;
- a focused camera-orbit diagnostic, review builder, runner, and test under
  `tools/tree_atlas/`;
- a focused low-rear-kicker diagnostic, review builder, runner, and test under
  `tools/tree_atlas/`;
- a focused lab-only `21:00` comparison probe, review builder, and test under
  `tools/` or `tools/tree_atlas/`;
- a focused `9 o'clock` Sun / `8%` kicker diagnostic, review builder, runner,
  and test under `tools/tree_atlas/`;
- a focused `10 o'clock` Sun / `12%` kicker diagnostic, review builder, runner,
  and test under `tools/tree_atlas/`;
- a focused `9:30` Sun / `12%` kicker bake, shadow-direction review builder,
  runner, and test under `tools/tree_atlas/`;
- a focused `10:00` Sun / `20%` kicker diagnostic, review builder, runner, and
  test under `tools/tree_atlas/`;
- a selected `10:00 / 20%` production bake profile, six-tree batch promotion
  runner/review/test under `tools/tree_atlas/`, and isolated batch artifacts;
- `artifacts/layered_tree_brightness_variants/**`;
- `assets/sprites/flora/layered_trees/tree_01/**` through `tree_06/**`;
- `assets/shaders/layered_tree_foliage_wind.gdshader`;
- `assets/shaders/layered_tree_snow_accumulation.gdshader`;
- `core/systems/world/layered_tree_object_layer.gd`;
- `core/systems/world/world_streamer.gd`;
- `tools/layered_tree_runtime_smoke_test.gd`;
- `docs/art/layered_asset_bake_contract.md`;
- `docs/02_system_specs/world/plains_trees_presentation.md`;
- `docs/02_system_specs/world/world_dynamic_lighting_2d.md`.

## Forbidden Files

- `assets/sprites/decor/plains/layered_small_rocks/**`
- `tools/tree_atlas/layered_asset_bake_profile.json`
- production runtime scripts/shaders/scenes outside the explicitly allowed
  tree presentation files, native world code, save schemas, localization, and
  placement settings;
- the external source GLB.
- during Iteration 3, all production tree assets, production runtime files, and
  `tools/tree_atlas/layered_tree_bake_profile.json` are read-only.
- during Iteration 3A, the same production files remain read-only and candidate
  A lighting values are read from its isolated proof profile without mutation.
- during Iteration 3B, candidate C remains an isolated input, the low rear Spot
  is diagnostic-only, and all production assets/runtime files remain read-only.
- during Iteration 3C, the `8%` derived candidate and time tint are lab-only;
  production tree assets, daylight code, TimeManager, and runtime world files
  remain read-only.
- during Iteration 3D, the west/east lighting profile and rendered candidate are
  isolated proof data; all production assets and runtime files remain read-only.
- during Iteration 3E, candidate C and both comparison candidates are read-only
  proof inputs; all production assets and runtime files remain read-only.
- during Iteration 3F, all `9:00`, `9:30`, and `10:00` candidates are isolated
  proof data; all production assets and runtime files remain read-only.
- during Iteration 3G, the `10:00 / 12%` and `10:00 / 20%` candidates are
  isolated proof data; all production assets and runtime files remain read-only.
- during Iteration 4, only `assets/sprites/flora/layered_trees/tree_01/**`
  through `tree_06/**`, the selected bake profile/tooling, proof artifacts and
  governing presentation docs are writable; production runtime code remains
  read-only because it already consumes six metadata-driven variants.

## Acceptance Criteria

- [x] The proof profile explicitly names screen sun `north_west`, cast shadow
      `south_east`, and root-pinned/stretch-only semantics.
- [x] A compass/orientation proof demonstrates the baked shadow leaves the root
      toward screen south-east; numeric azimuth is not accepted from labels
      alone.
- [ ] A gameplay-scale lab close-up shows roots reading as spread over the
      ground while retaining the complete physical root shadow; no additional
      synthetic or erased contact shape is present (manual human verification).
- [x] Candidate classification records an empty `suppressed_shadow_casters`
      array, and the proof profile contains neither a root-caster cutoff nor a
      root-footprint attenuation block (automated contract check).
- [x] Across `13:00`, `14:30`, and `16:00`, the shadow source anchor differs
      from the visible tree anchor by at most `0.5 px`; source points whose
      forward projection is at most `48 px` remain invariant, while a measured
      far-tip point stretches only along the authored `[0.707107, 0.707107]`
      axis (automated snapshot/probe).
- [x] Candidate classification records root embed `0.011`; its minimum geometry
      bound is `-0.01100004`, above the Blender shadow receiver at `-0.012`, so
      no visible mesh part crosses below the receiving plane.
- [x] `1.glb` produces the complete tree pass set and a comparison preview under
      `artifacts/layered_tree_01_nw_winter_proof/`.
- [ ] The albedo has readable soft self-shadow on the visible south/south-east
      side without crushed-black bark or foliage (manual human verification).
- [x] A strict Blender self-shadow A/B keeps camera, materials, fill, Sun
      direction, energy and exposure identical and toggles only
      `Sun.data.use_shadow`; its fixed-scale delta demonstrates whether localized
      self-cast occlusion is actually present on the visible south/back side.
- [x] Mean snow-overlay alpha on visible trunk pixels (`trunk alpha > 48`,
      `foliage alpha < 20`) is at most `0.20`; mean alpha on the same pixels in
      the root band (`y >= anchor_y - 8`) is at most `0.05`.
- [ ] Snow remains clearly present on foliage, but dark gaps and lower cluster
      undersides remain visible in the comparison preview (manual human verification).
- [x] Warm and full-winter lab captures have the same foliage alpha silhouette;
      winter may change foliage colour and overlay snow/frost but may not remove
      leaves (proof mask + lab shader contract check).
- [x] Full winter shows white fluffy snow resting on supported leaf surfaces,
      a lighter frost over the crown, and separate caps on plausible
      upper/horizontal branch surfaces; no detached snow crown remains in empty
      air and the crown is not one flat white blob (manual human verification;
      accepted for production promotion on 2026-07-12).
- [x] Active snow pixels (`alpha > 32`) have luminance standard deviation above
      `4` and range above `20`; the north-west-facing sample is at least `8`
      luminance units brighter than the south-east-facing sample.
- [x] Iterations 1A-1D kept production byte-unchanged; Iteration 2 changes only
      production trees while the shared v1 rock profile remains unchanged.
- [x] Focused offline tests pass.
- [x] A labelled orientation sheet shows `tree_02` through `tree_06` at both
      `90` and `180` degree yaw before the batch bake; the one selected
      exception is recorded in a machine-readable batch manifest.
- [x] `tree_02` through `tree_06` each produce the complete layered pass set
      under `artifacts/layered_tree_nw_winter_batch_proof/`, using the accepted
      physical-shadow, no-rear-fill, full-foliage winter contract.
- [x] A batch comparison sheet shows summer layered, full-foliage winter, and
      physical shadow for all five remaining trees (manual human verification;
      accepted by the explicit production-promotion request on 2026-07-12).
- [x] Final visual acceptance was provided by the explicit production-promotion
      request on 2026-07-12.
- [x] Production contains `tree_01` through `tree_06`, each with the complete
      required layered pass set and production v2 bake metadata.
- [x] The runtime registers all six variants and a focused Godot smoke test
      instantiates one visual and one physical baked shadow for each variant.
- [x] Runtime foliage keeps its alpha silhouette through full winter; snow adds
      crown frost and supported accumulation without enabling leaf drop.
- [x] Runtime tree shadow projection reads the authored south-east direction
      and `48 px` contact lock, keeps the root-side samples invariant, and
      stretches only the far end as the sun-length scalar changes.
- [x] Existing rocks, placement packet, `WORLD_VERSION`, save/load, player
      shadow, `TimeManager`, and `DirectionalLight2D` remain unchanged.
- [x] Iteration 3 produces exactly three isolated `tree_01` candidates: A
      (`exposure=0.8`, no ambient rig), B (`exposure=0.7`, weak symmetrical
      ambient rig), and C (`exposure=0.75`, approximately screen `10 o'clock`).
- [x] Every Iteration 3 classification keeps `suppressed_shadow_casters=[]`,
      every Sun self-shadow diagnostic toggles only `Sun.data.use_shadow`, and
      each ON capture retains measurable localized self-shadow.
- [x] A and B retain the approved south-east cast direction; C measures a more
      easterly ESE cast direction. All three retain the physical root shadow.
- [x] A labelled gameplay-scale review sheet and per-candidate luminance/shadow
      metrics are written under `artifacts/layered_tree_brightness_variants/`.
- [x] Production trees/profile/runtime remain byte-unchanged throughout
      Iteration 3.
- [x] Iteration 3A exports exactly eight labelled camera views around the fixed
      `tree_01`: south, south-west, west, north-west, north, north-east, east,
      and south-east.
- [x] Iteration 3A keeps the source transform, candidate A lighting profile,
      north-west Sun transform, Sun energy, exposure, and physical Sun shadow
      identical across all eight captures; only the camera transform and
      orthographic fit may change.
- [x] A labelled orbit sheet and a large west review image are written under
      `artifacts/layered_tree_brightness_variants/turntable/`, and a production
      hash guard proves that the diagnostic did not change production files.
- [x] Iteration 3B renders `0/2/4/6/8%` measured dark-trunk luminance-lift
      variants from one fixed candidate-C tree/camera/Sun scene.
- [x] The low rear Spot is placed on the opposite screen side from the
      `10 o'clock` Sun, below crown centre, aimed upward at the middle/lower
      trunk, uses a soft cone, and has `use_shadow=false`.
- [x] The `2%` primary candidate retains measurable physical Sun self-shadow;
      its strict ON/OFF diagnostic changes only `Sun.data.use_shadow` while the
      kicker, camera, materials, exposure, and transforms remain fixed.
- [x] A labelled full-tree sheet and crown/trunk close-up sheet report actual
      measured lift for every variant and make crown washout visible.
- [x] Production trees/profile/runtime remain byte-unchanged throughout
      Iteration 3B.
- [x] Iteration 3C builds a complete isolated layered candidate using the `8%`
      trunk/foliage renders while preserving candidate C masks, metadata frame,
      physical shadow source, winter layers, and anchor.
- [x] A lab probe captures `0%` and `8%` at exactly `21:00` with night ambient
      `Color(0.03, 0.035, 0.05)`, no direct sun, no visible sun-cast shadow, and
      no torch/local light.
- [x] The raw `21:00` comparison preserves the hostile-outside darkness
      contract: the `8%` tree may remain marginally more separable but must not
      read as emissive or comfortably lit without a gameplay light source.
- [x] A labelled review sheet keeps raw gameplay captures distinct from any
      gain-assisted analysis view, and production hashes remain unchanged.
- [x] Iteration 3D uses screen Sun `west_9_oclock`, Blender azimuth `270`, and
      measures the complete physical cast shadow within `2 degrees` of screen
      east while keeping the source/root anchor unchanged.
- [x] The opposite shadowless Spot is low on screen east, aimed upward at the
      middle/lower trunk, and is calibrated to `8% +/- 0.15%` measured dark-
      trunk luminance lift.
- [x] The `9 o'clock / 8%` strict self-shadow ON/OFF pair changes only
      `Sun.data.use_shadow` and retains measurable localized self-shadow.
- [x] A review sheet compares the prior `10 o'clock / 8%` candidate against
      `9 o'clock` with `0%` and `8%`, reports foliage lift and physical cast
      angle, and production hashes remain unchanged.
- [x] Iteration 3E retains candidate C's screen `10 o'clock` Sun, physical Sun
      self-shadow, exposure, camera, materials, and complete physical cast
      shadow while changing only the low opposite Spot energy.
- [x] The shadowless low ESE Spot calibrates to `12% +/- 0.15%` measured dark-
      trunk luminance lift and reports its measured dark-foliage lift.
- [x] The `10 o'clock / 12%` strict self-shadow ON/OFF pair changes only
      `Sun.data.use_shadow` and retains measurable localized self-shadow.
- [x] A review sheet and close-up sheet compare `9 o'clock / 8%`, `10 o'clock /
      8%`, and `10 o'clock / 12%`; production hashes remain unchanged.
- [x] Iteration 3F renders a complete physical Cycles shadow for screen Sun
      `9:30`; its measured centroid angle is within `2 degrees` of the expected
      `15 degree` screen ESE direction and the root anchor is unchanged.
- [x] The low opposite shadowless Spot is geometrically between the accepted
      `9:00` and `10:00` proof positions and calibrates to `12% +/- 0.15%`
      measured dark-trunk lift.
- [x] A full-tree composite shows the `9:30 / 12%` albedo together with its
      physical shadow, and a separate sheet compares physical directions at
      `9:00`, `9:30`, and `10:00` from the same root framing.
- [x] Strict Sun self-shadow remains measurable and production hashes remain
      unchanged throughout Iteration 3F.
- [x] Iteration 3G retains the exact `10:00` physical Sun, exposure, camera,
      materials, complete Cycles cast shadow, and low opposite Spot geometry
      while changing only the Spot energy target from `12%` to `20%`.
- [x] The shadowless Spot calibrates to `20% +/- 0.15%` measured dark-trunk lift
      and reports the measured dark-foliage lift.
- [x] A full-tree composite shows `10:00 / 20%` with the complete physical cast
      shadow, and review sheets compare `10:00 / 12%` against `10:00 / 20%` at
      identical framing.
- [x] Strict Sun self-shadow remains measurable and production hashes remain
      unchanged throughout Iteration 3G.
- [x] Iteration 4 bakes `tree_01` through `tree_06` with the exact selected
      `10:00 / 20%` rig: Sun azimuth `219`, exposure `0.75`, low shadowless Spot
      at normalized `(2.25, -2.05, 0.08h)` aimed at `0.43h`, energy `23.3515625`,
      cone `52 degrees`, blend `0.88`, and `use_shadow=false`.
- [x] All six outputs retain the complete layered pass set, full-foliage winter
      contract, empty suppressed-caster list, physical ESE cast shadow,
      metadata contact lock `48 px`, yaws `90/90/90/90/90/180`, and unchanged
      anchors between candidate and promoted production copies.
- [x] A labelled six-tree review shows the selected summer albedo, winter
      appearance and physical shadow before promotion; production hashes change
      only inside the six layered-tree asset directories and selected docs/tools.
- [x] Runtime smoke instantiates all six promoted variants and their physical
      shadows; project boot, focused batch tests and the full layered suite pass
      without a `world_version`, save/load, placement or public API change.

## Failure Cases / Risks

- Blender world azimuth and screen compass are assumed equivalent without a
  render proof.
- The proof edits the shared v1 profile or production asset directory.
- Snow coverage is reduced on the trunk but the overlay remains flat white.
- A mask fills the foliage silhouette into large foam-like blobs.
- High fill light removes the desired south-side volume.
- The proof silently expands into a runtime sun-direction implementation.
- A physical root shadow is replaced, erased, shifted, or supplemented by a
  synthetic contact silhouette.
- A self-shadow comparison rotates or removes the key light and therefore
  confuses ordinary `N dot L` darkening with real self-cast occlusion.
- Strong leaf drop hides foliage but leaves the independent snow overlay in the
  old canopy silhouette, producing floating snow.
- Any winter path removes or fades foliage alpha after the Iteration 1C decision.
- Shadow length scaling is applied around texture centre or a mutable polygon
  origin instead of the authored tree anchor, causing the shadow root to walk.
- Fill/world/specular light creates a south-side rim that reads as illumination
  from behind rather than soft ambient readability.
- A root-shadow fix moves the receiver plane and detaches the complete shadow
  from the tree in camera projection.
- A postprocess copy of the root silhouette is shifted in 2D and therefore
  cannot match the height-dependent projection of the real 3D root geometry.
- Visible albedo geometry crosses below the ground receiver and becomes unable
  to cast onto that receiver even though the transparent albedo pass shows it.

## Open Questions

- Whether `tree_06` should later become a production variant is deliberately
  deferred.
- Production-wide sun/player/runtime synchronization is a separate iteration
  after this asset proof is accepted.

## Implementation Iterations

### Iteration 1A - `tree_01` offline proof

- create an isolated v2 proof profile;
- establish screen NW sun / SE cast-shadow orientation;
- improve trunk/foliage snow accumulation and shaded snow overlay;
- render one full pass set, metrics, and before/after preview;
- do not promote production assets.

Status: technically implemented 2026-07-12. Manual feedback rejected the
physically complete visible root shadow as visually ungrounded and questioned
whether the dark back side contains real self-cast occlusion. The numeric proof
is recorded in
`artifacts/layered_tree_01_nw_winter_proof/metrics.json`: shadow angle
`46.70 degrees` screen south-east, visible-trunk snow alpha `0.0083`, root-band
snow alpha `0.0`, active-snow luminance standard deviation `4.16`, and
north-west minus south-east snow luminance `15.71`.

### Iteration 1B - Dev-lab grounding, self-shadow, and harsh-winter proof (rejected)

- compare physical root casting against an experimental suppressed version;
- produce strict `self-shadow ON/OFF` Blender captures where only shadow casting
  changes;
- let `layered_tree_asset_lab_scene.tscn` load an isolated proof asset and derive
  NE/SE stretch direction from its metadata;
- expose independent season and leaf-drop debug controls;
- gate foliage-supported snow with leaf retention and preserve woody branch snow;
- capture root-shadow and `0.26/0.70/0.90` harsh-winter A/B panels;
- do not modify production layered-tree assets or the production world path.

Status: technical proof completed 2026-07-12 and rejected by manual visual
review. Root attachment still reads as detached/moving, the broad back-side
response reads as rear illumination, and leaf removal is no longer part of the
winter direction.
The selected neutral bake uses albedo Sun elevation `38 degrees`, angular
diameter `4 degrees`, and fill energy `52`. A strict `Sun.use_shadow` ON/OFF
pair measures self-cast delta `>= 2/255` on `26.75%` of eroded interior pixels
(`max = 36/255`), proving localized self-cast occlusion while confirming that
the broad dark back side is still mostly ordinary surface orientation. Root
grounding suppresses three lowest casters, retains anchor alpha `26/255`, and
reduces mean root-zone shadow alpha to `32.73/255`; `13:00`, `14:30`, and
`16:00` lab captures remain connected. Final cast-shadow angle is `46.44
degrees` screen south-east. The winter proof recommends `0.90` as harsh winter
and `0.70` as a transition state; reverse `0.90 -> 0.0` regrowth was captured in
the same lab scene instance.

### Iteration 1C - Pinned anchor, frozen full crown, and rear-light removal (current)

- keep the complete leaf silhouette at every season amount;
- freeze/desaturate leaves, add restrained crown frost, and accumulate fluffy
  supported snow on leaves and horizontal branches;
- preserve the full physical Cycles shadow from all GLB geometry, make the
  visible tree anchor and cast-shadow source anchor identical and invariant,
  and stretch only the far shadow end at low sun;
- diagnose GLB normals/materials separately from Blender fill/world/specular
  response, then remove the smallest verified source of false rear lighting;
- capture warm/full-winter, three-hour anchor, and strict self-shadow proof;
- do not modify production layered-tree assets or production runtime.

Status: technically implemented 2026-07-12; awaiting manual visual approval.
The final candidate is
`artifacts/layered_tree_01_nw_winter_proof/candidate_v3_physical`.
`suppressed_shadow_casters` is empty and no root-footprint attenuation exists.
The `0/16/32/48 px` contact probes are coordinate-identical at `13:00`,
`14:30`, and `16:00`, while the `303 px` far probe stretches from local
`(184.26, 184.26)` to `(316.07, 316.07)`. Strict physical self-shadow measures
mean delta `4.43/255`, max `64/255`, and delta `>= 2/255` on `33.51%` of eroded
interior pixels. Full-winter snow measures active luminance standard deviation
`5.08`, range `38`, foliage covered fraction `0.519`, dark-gap fraction `0.278`,
visible-trunk mean alpha `0.102`, and root-band mean alpha `0.0`. Focused tests
and Godot lab smoke pass; visual acceptance remains manual.

GLB audit result: all `41` mesh transforms have positive determinant, stored
normals are unit length, only `0.000635%` of sampled geometric faces oppose
their stored normals, emission is absent, and disabling normal maps changes
mean luminance by only `0.00021`. The false rear light was the proof Area fill
at `(0, -2, 1)` with energy `52`, positioned on the visible south/camera side.
Iteration 1C removes that light and restores readability with camera exposure,
which cannot illuminate or erase a self-shadow.

### Iteration 1D - Remaining-tree isolated batch proof (current)

- render `90/180 degree` orientation pairs for `tree_02` through `tree_06`;
- choose exactly one per-tree additional `90 degree` yaw override from the
  orientation sheet and record it in a batch manifest;
- bake/postprocess `2.glb` through `6.glb` with the accepted Iteration 1C
  physical light, shadow, and full-foliage winter profile;
- build one labelled review sheet;
- keep `assets/sprites/flora/layered_trees/**` and the production profile
  unchanged.

Status: technically implemented 2026-07-12; awaiting manual visual approval.
The orientation sheet records the shared `90 degree` yaw for `tree_02` through
`tree_05` and the single additional rotation for `tree_06` (`180 degrees`).
The exception is stored in
`tools/tree_atlas/layered_tree_batch_proof_manifest.json`.
All five candidates have empty `suppressed_shadow_casters`, complete layered
passes, fixed south-east physical shadows, zero leaf-drop mask, and summer/full
winter Godot captures. Root-zone (`anchor_y - 64` through the bottom) mean snow
alpha ranges from `0.0` to `0.0208`; visible-trunk mean snow alpha ranges from
`0.0373` to `0.1136`. The batch render probe wrote `10` captures without
errors, and the focused suite passes `26` tests.

### Iteration 2 - Production contract and batch promotion (authorized)

- promote the accepted tree-only v2 bake profile without changing the shared
  v1 rock profile;
- replace production `tree_01` through `tree_05` and add the accepted
  `tree_06` (`180 degrees`, the single yaw exception);
- promote the full-foliage frozen-winter shader behavior;
- make runtime tree shadow stretch metadata-driven, fixed south-east, and
  contact-locked for the first `48 px` from the root;
- register all six variants and update focused production/runtime tests.

Status: completed 2026-07-12. Production contains six imported tree variants;
`tree_06` is the only `180 degree` yaw exception. The layered Python suite
passes `27` tests, Godot `--import` completed all `66` tree texture imports,
and `layered_tree_runtime_smoke_test.gd` reports `OK` after import. No public
API, placement, save, time, player-shadow, rock-profile, or world-version
change was made.

### Iteration 3 - Isolated brightness and clock-direction comparison (current)

- A: approved NW/SE compass, `exposure=0.8`, no fill;
- B: approved NW/SE compass, `exposure=0.7`, weak symmetrical neutral ambient
  rig with no shadow casting and no camera/south-only source;
- C: screen key near `10 o'clock`, `exposure=0.75`, no fill, measured ESE cast;
- render all three from `1.glb` at `yaw=90`, build a labelled review sheet, and
  run strict physical self-shadow ON/OFF diagnostics;
- do not promote a candidate until explicit manual selection.

Status: technically completed 2026-07-12; awaiting manual selection. Relative
to production mean albedo luminance `25.14`, A measures `28.95`, B measures
`44.40`, and C measures `29.71`. Strict self-shadow delta `>=2/255` remains on
`31.94%`, `28.95%`, and `32.35%` of eroded interior pixels respectively. A/B
cast angles remain `47.86/48.10 degrees` screen south-east; C measures `32.81
degrees` ESE. The layered suite passes `31` tests and the production hash guard
passes. No candidate has been promoted.

Candidate B was rejected by manual review on 2026-07-12 because the symmetrical
ambient rig washed out the foliage self-shadow pattern. Candidate A remains an
isolated review candidate; no candidate has been promoted.

### Iteration 3A - Candidate A fixed-light camera orbit (current)

- load candidate A from its isolated proof profile;
- hold the normalized source tree and all lighting fixed in world space;
- move only the camera through eight compass viewpoints;
- build a labelled orbit sheet and a large west-side review image;
- keep production assets and runtime byte-unchanged.

Status: technically completed 2026-07-12; awaiting visual feedback on candidate
A. Eight captures keep one fixed tree and fixed physical north-west Sun while
only the camera moves. The west view has mean interior luminance `52.06` and
10th-percentile luminance `12`, compared with `28.95` and `8` in the south
view. The focused turntable tests pass `3/3`, the full layered suite passes
`34/34`, and the production hash guard passes.

### Iteration 3B - Candidate C low rear kicker (current)

- restore the physical key to screen `10 o'clock` from candidate C;
- add one low, upward-aimed, shadowless soft Spot on the opposite screen side;
- calibrate and render measured dark-trunk lifts of `0/2/4/6/8%`;
- mark `2%` as the primary manual-review candidate;
- retain a strict physical Sun self-shadow ON/OFF proof at `2%`;
- keep production assets and runtime byte-unchanged.

Status: technically completed 2026-07-12; awaiting manual visual selection.
The primary `2%` candidate measures `1.997%` dark-trunk luminance lift while
dark foliage rises only `1.113%`. The shadowless Spot energy required for this
measured screen response is `11.539`; its transform remains low and fixed while
the physical `10 o'clock` Sun remains shadow-enabled. The strict Sun self-shadow
ON/OFF proof measures delta `>=2/255` on `32.25%` of eroded interior pixels and
a maximum delta of `95/255`. Focused tests pass `4/4`, the full layered suite
passes `38/38`, and the production hash guard passes. No candidate has been
promoted.

### Iteration 3C - Eight-percent candidate at 21:00 (current)

- materialize an isolated complete layered candidate from the calibrated `8%`
  trunk and foliage renders;
- compare candidate C `0%` against `8%` at the exact `21:00` ambient floor;
- disable direct sun, sun-cast shadow visibility, torch, and local light;
- provide raw gameplay captures plus a clearly labelled gain-assisted analysis;
- keep production assets, daylight ownership, and runtime byte-unchanged.

Status: technically completed 2026-07-12; awaiting manual visual selection of
the `8%` candidate for production promotion. At exact `21:00` the baseline tree
has mean raw luminance `0.774/255` and the `8%` candidate `0.779/255`, a delta
of only `0.005/255`; both have `p90 = 1/255` and `max = 4/255`. Thus the baked
kicker improves daytime readability without reading as emissive after the
night ambient floor is applied. The raw comparison uses no direct sun, visible
sun-cast shadow, torch, or local light; the separate `x16` row is analysis-only.
Focused tests pass `4/4`, the full layered suite passes `42/42`, and the
production hash guard passes. No candidate has been promoted.

### Iteration 4 - Promote selected ten o'clock / twenty-percent rig (current)

- add the proven low shadowless Spot as an optional authored bake-profile light;
- batch-bake `1.glb` through `6.glb` using yaws `90/90/90/90/90/180`;
- generate a six-tree summer/winter/physical-shadow review and batch metrics;
- replace only production `tree_01` through `tree_06` layered assets;
- retain the existing metadata-driven six-variant runtime path;
- update the production bake and presentation contracts;
- run offline, Godot runtime and boot verification.

Status: completed 2026-07-12. All six candidates were rendered from the selected
profile, the labelled review contains `12` gameplay-scale summer/winter captures,
and candidate-to-production normalized content hashes match for every runtime
layer. Focused promotion checks pass `4/4`, the full layered suite passes
`62/62`, runtime and lab-scene smoke report `OK`, and the main project exits
cleanly after headless boot. No runtime owner, world placement, save/load
contract, public API, rock asset, or `world_version` changed.

Clarification: the user's `21:00` wording meant the screen-clock direction
`9 o'clock`, not gameplay nighttime. This completed night proof remains valid
evidence that an `8%` baked lift does not become emissive, but Iteration 3D is
the requested visual candidate.

### Iteration 3D - West 9 o'clock Sun with eight-percent kicker (current)

- set the physical key to screen west / `9 o'clock`;
- measure a due-east physical cast shadow instead of trusting the label;
- place the shadowless low kicker on screen east and calibrate it to `8%`;
- compare prior `10 o'clock / 8%`, new `9 o'clock / 0%`, and new
  `9 o'clock / 8%`;
- retain strict physical Sun self-shadow proof;
- keep production byte-unchanged.

Status: technically completed 2026-07-12; awaiting manual visual selection.
The physical west key uses Blender azimuth `270 degrees`; its Cycles cast-shadow
centroid measures `1.77 degrees` from due east with delta `(197.92, 6.10)` px.
The low east Spot calibrates to `7.998%` dark-trunk lift while dark foliage rises
only `2.921%`. Strict Sun self-shadow delta `>=2/255` remains on `34.70%` of
eroded interior pixels with maximum delta `81/255`. Focused tests pass `4/4`,
the full layered suite passes `46/46`, and the production hash guard passes. No
candidate has been promoted.

### Iteration 3E - Ten o'clock Sun with twelve-percent kicker (current)

- reuse candidate C's physical screen `10 o'clock` Sun and ESE cast direction;
- keep the low opposite shadowless Spot geometry fixed;
- calibrate only Spot energy to `12%` measured dark-trunk lift;
- compare `9 o'clock / 8%`, `10 o'clock / 8%`, and `10 o'clock / 12%`;
- retain strict physical Sun self-shadow proof;
- keep production byte-unchanged.

Status: technically completed 2026-07-12; awaiting manual visual selection.
The low ESE Spot calibrates to `11.993%` dark-trunk lift while dark foliage rises
`6.990%`. Candidate C's physical cast-shadow centroid remains at `32.81 degrees`
screen ESE. Strict Sun self-shadow delta `>=2/255` remains on `31.97%` of eroded
interior pixels with maximum delta `95/255`. Focused tests pass `4/4`, the full
layered suite passes `50/50`, and the production hash guard passes. No candidate
has been promoted.

### Iteration 3F - Nine-thirty Sun with twelve-percent kicker (current)

- place the physical Sun halfway between the proven `9:00` and `10:00` keys;
- render and measure the complete physical cast shadow near screen `3:30`;
- place the low shadowless kicker between the prior east/ESE positions;
- calibrate the kicker to `12%` measured dark-trunk lift;
- show a full tree+shadow composite and a `9:00 / 9:30 / 10:00` direction sheet;
- retain strict physical self-shadow proof and keep production byte-unchanged.

Status: technically completed 2026-07-12; awaiting manual visual selection.
The physical Cycles cast shadow measures `14.588 degrees` below screen east
against the `15 degree` target, with centroid delta `(200.477, 52.174)` pixels.
The low opposite shadowless Spot calibrates to `11.995%` dark-trunk lift while
dark foliage rises `5.573%`. Strict Sun self-shadow delta `>=2/255` remains on
`32.28%` of eroded interior pixels with maximum delta `90/255`. Focused tests
pass `4/4`, the full layered suite passes `54/54`, and the production hash guard
passes. No candidate has been promoted.

### Iteration 3G - Ten o'clock Sun with twenty-percent kicker (current)

- reuse the proven physical screen `10:00` Sun and ESE cast direction;
- keep exposure, camera, materials, and low opposite Spot geometry fixed;
- calibrate only Spot energy to `20%` measured dark-trunk lift;
- compare `10:00 / 12%` directly against `10:00 / 20%`;
- show the complete physical cast shadow with the `20%` candidate;
- retain strict physical Sun self-shadow and keep production byte-unchanged.

Status: technically completed 2026-07-12; awaiting manual visual selection.
The fixed low ESE Spot calibrates to `19.993%` dark-trunk lift at energy
`23.3516`, while dark foliage rises `11.855%`. The physical cast-shadow centroid
remains at `32.814 degrees` screen ESE. Strict Sun self-shadow delta `>=2/255`
remains on `31.76%` of eroded interior pixels with maximum delta `95/255`.
Focused tests pass `4/4`, the full layered suite passes `58/58`, and the
production hash guard passes. No candidate has been promoted.

## Required Updates

- Iterations 1A/1B/1C/1D: add this spec to both documentation indexes (done); no public
  API, event, packet, command, save, or production bake-contract update.
- Iteration 2: update `docs/art/layered_asset_bake_contract.md`,
  `plains_trees_presentation.md`, and `world_dynamic_lighting_2d.md`. Recheck
  `player_sun_shadow_v0.md` and `system_api.md`; update them only if
  `get_sun_angle()` or another public runtime surface changes.
- Iteration 3: no canonical production contract update unless a candidate is
  later selected for promotion.
- Iteration 3A: no canonical production contract update; this is a derived
  camera-orbit review artifact only.
- Iteration 3B: no canonical production contract update unless the low rear
  kicker candidate is explicitly selected for production promotion.
- Iteration 3C: no canonical production contract update; it verifies the
  existing night-lighting and sanctuary/exposure contract without changing it.
- Iteration 3D: no canonical production contract update until the west/east
  candidate is explicitly selected for promotion.
- Iteration 3E: no canonical production contract update until the `10 o'clock /
  12%` candidate is explicitly selected for promotion.
- Iteration 3F: no canonical production contract update until the `9:30 / 12%`
  candidate is explicitly selected for promotion.
- Iteration 3G: no canonical production contract update until the `10:00 / 20%`
  candidate is explicitly selected for promotion.
- Iteration 4: update `docs/art/layered_asset_bake_contract.md`,
  `plains_trees_presentation.md`, and `world_dynamic_lighting_2d.md` with the
  selected `10:00 / 20%` production rig; recheck `system_api.md` and update it
  only if a public runtime surface changes.
