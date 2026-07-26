# Layered Asset Bake Contract

This contract keeps Blender-baked 2D world objects visually consistent across
trees, rocks, props, and future assets.

The machine-readable source of truth is:

`tools/tree_atlas/layered_asset_bake_profile.json`

Current profile: `station_peaceful_layered_asset_bake_v1`, revision `version: 4`.

Revision 2 moved the sun to azimuth 225 (shadows run screen south-east) and
sank roots to 7%. Revision 3 restored sun self-shadowing and revision 4 replaced the frontal
fill with a ground bounce: see **Lighting Rig** below. Object families migrate to a new revision one at a time; see
**Sun Migration Status**.

## Fixed Bake Rules

- `frame_size: 768`
- `default_yaw_degrees: 90`
- `sun_azimuth_degrees: 225`
- `albedo_sun_elevation_degrees: 52`
- `shadow_sun_elevation_degrees: 42`
- `root_embed_fraction: 0.07`
- Camera type is orthographic.
- `exposure: 0.0`
- Layer passes render with layer cross-shadows on.
- Render view transform is Filmic with Medium High Contrast.
- `albedo_sun_energy: 7.5`
- ground bounce `energy: 150`, casts no shadow, absent from the shadow pass
- Shadows are baked toward screen south-east.
- normal maps are generated but disabled in runtime.

## Required Outputs

Each layered asset directory must contain:

- `albedo.png`
- `shadow.png`
- `snow_mask.png`
- `snow_overlay.png`
- `height.png`
- `normal.png`
- `meta.json`
- `preview_panel.png`

Tree assets additionally contain `trunk.png`, `foliage.png`, `wind_mask.png`,
and `season_mask.png`. Static small rock assets intentionally do not contain a
wind mask or season mask; their body layer is `albedo.png`.

`meta.json` must include a `bake_profile` block with the profile id, version,
frame size, sun angles, and root embed fraction used for the bake.

## Runtime Rules

Sun shadows are baked fixed south-east and can only stretch away from the root.
The root side must stay pinned to the object anchor. The sun does not orbit: its
direction is fixed and only the shadow *length* responds to time of day, which
is why the runtime splits each shadow into a static root side and a stretched
far side.

Two runtime values must agree with the baked direction, or a lengthening shadow
walks off its own sprite:

- the stretch direction (`TREE_SHADOW_DIRECTION` in
  `world_layered_object_asset_catalog.gd`), and
- the output window the shadow is rasterised into
  (`TREE_SHADOW_OUTPUT_UV_MIN` / `_MAX`), which must open toward the shadow.

`test_tree_runtime_shadow_stretch_matches_the_baked_sun` pins that agreement.

## Lighting Rig

Two lights, and each has exactly one job.

**Sun** — the only shadow caster, fixed at azimuth 225. Because that puts it
north-west, behind the subject from the camera, the face the camera sees is the
shaded one. That is by design; do not fight it by moving the sun.

**Ground bounce** — an area light low on the camera side, aimed upward
(`pitch_degrees: 135`), below the ground plane (`location.z < 0`), casting
nothing and excluded from the shadow pass. It lifts the shaded face and the
trunk. Coming from below, it reaches undersides that the sun cannot, so it
*cannot* brighten a sunlit top: the rig has no way to blow out a highlight.

Three failure modes are already documented in this file's history; do not
reintroduce them.

- **A frontal fill flattens everything.** At `fill_energy: 130` against
  `albedo_sun_energy: 2.25` the sun contributed about five percent of the image —
  switching the sun off entirely moved mean brightness by less than four levels,
  and the object had no self-shadowing at all despite every light being
  nominally correct.
- **Exposure is not a brightness dial for a dark shaded face.** Raising
  `render.exposure` lifts the sunlit tops just as much, and Filmic desaturates as
  it clips: the canopy went pale peach with a quarter of it brighter than any
  pixel in the reference bake. Lift the shaded side with the bounce instead.
- **A layer pass hides the other layers from the camera, not from the sun.**
  `trunk.png` and `foliage.png` are composited at runtime, so a shadow the canopy
  casts on the trunk has to be inside the trunk pass. Setting `hide_render` drops
  the layer out of the shadow map too. Use `visible_camera = False` with
  `visible_shadow = True` instead, which is what `layer_cross_shadows` means.

When retuning, measure the foliage layer, not the whole sprite: mean luma, the
90th percentile, saturation, and the fraction above 200. The reference look has
no pixel above 200 at all.

## Sun Migration Status

| family | profile revision | baked shadow | runtime framing |
| --- | --- | --- | --- |
| layered trees | 4 | screen south-east | `TREE_SHADOW_*` |
| layered small rocks | 1 | screen north-east | shared `SHADOW_*` |
| mountains, decor, living flora | not on this contract | — | — |

Rocks are knowingly a revision behind and are pinned by
`test_small_rock_assets_still_await_the_current_sun`. When a family migrates,
re-bake it, flip its runtime framing constants, and move its row here in the same
change. Do not flip a shared runtime constant while any family on it is still
baked against the old sun.

Dynamic light shadows are runtime fake shadows. They are separate from this
sun-shadow bake contract.

Normal maps stay generated for future experiments, but runtime tree materials do
not receive or write `NORMAL_MAP` until the lighting pipeline is retuned.

## Snow Model (trees)

Snow is not "the silhouette, but white". Tunables live in the shared profile
under `postprocess.snow`; do not hand-tune a snow sprite.

- **Where it lands** is decided by the screen-space orientation of the surface,
  taken from the gradient of the layer alpha at two blur scales. Only sky-facing
  surfaces collect snow. A vertical trunk flank and the underside of a branch
  collect none.
- **How far it drapes** is a settle pass with a short full-depth plateau and then
  a falloff. Each layer settles inside its own alpha, so canopy snow never runs
  down the trunk behind it.
- **Its edge** is broken by multi-octave value noise built from bicubic-upscaled
  random grids. Do not reintroduce a sine-sum noise; on wide canopies that
  produced a visible diagonal lattice.
- **Its shading** is computed from the relief of the drift itself, not from the
  tree under it, and is lit by `postprocess.snow.light_direction`, which follows
  the same fixed bake sun as the shadows.

`snow_mask.png` channels:

| channel | meaning |
| --- | --- |
| R | accumulation order — higher snows over earlier as `season_amount` rises |
| G | snow lighting term used by `snow_overlay.png` |
| B | cap depth, the snow standing above the silhouette |
| A | coverage, silhouette plus cap |

R is the channel the runtime shaders sample
(`layered_object_snow_batch.gdshader`, `layered_tree_snow_accumulation.gdshader`);
it must stay a smooth ramp. The crisp, irregular full-winter boundary belongs to
the overlay alpha, not to the mask.

Static small rock assets have their own snow path in
`postprocess_layered_rock_asset.py` and are not covered by this model.

## Authoring Notes

Use the shared profile instead of hand-entering Blender settings. If a specific
asset needs a different yaw for silhouette quality, pass it explicitly and make
sure the resulting `classification.json` and `meta.json` record it.

Do not manually recolor a final sprite to "make it match"; fix the Blender bake,
postprocess, or profile instead. The goal is that future assets can be rebaked
and compared without guessing which settings were used.

## Silhouette Variations From One Source GLB

Several silhouettes can be derived from one source GLB instead of sourcing a new
model per tree. That path is `tools/tree_atlas/make_tree_variations.py`, driven
by `tools/tree_atlas/tree_variation_profiles.json`
(`station_peaceful_tree_variation_v1`).

It does not own bake settings. Camera, lighting, engines, layer split, root
embed and postprocess all still come from this contract; the variation step only
deforms geometry between GLB import and the canonical bake.

Three rules keep those bakes valid:

- The deformation is one continuous field evaluated around the reconstructed
  trunk axis and applied to every mesh part with the same function. Source GLBs
  are usually one surface split into many parts, so per-part rotation would tear
  the mesh.
- **Foliage must stay attached to branch geometry.** Canopy clusters are rotated
  and scaled around their attachment vertex, never their centroid, so the
  contact point is a fixed point of the transform. A cluster that already
  floated in the source GLB is snapped onto its nearest branch. The bake
  measures every cluster afterwards and fails loudly if any gap exceeds
  `attachment.gap_tolerance_fraction`; it never ships a detached canopy. The
  measured gaps land in `variation.json` under `applied.attachment`.
- Each variant directory additionally records `variation.json` with the variant
  parameters and a `framing` block (`ortho_scale`, `pixels_per_world_unit`,
  `world_bbox`, `world_height`). The canonical camera refits every asset to the
  same frame fraction, so without that block the intended size difference
  between variations is not recoverable from the sprite.

### Variation parameters

Every variant is one entry in `tree_variation_profiles.json`. All of it is
deterministic: the same `seed` always produces the same tree.

| key | what it changes |
| --- | --- |
| `yaw_degrees` | which side of the model the camera sees |
| `twist_degrees`, `twist_power` | rotation around the trunk axis, growing with height — this is what swings branches to other sides |
| `lean`, `lean_power` | steady tilt, as a fraction of tree height |
| `sway` | a mid-height bulge, for an S-curve rather than a straight tilt |
| `spread` | canopy pushed out from or pulled in toward the axis |
| `droop` | branch sag, strongest far from the trunk |
| `height_scale`, `width_scale` | overall proportions |
| `cluster_scale`, `cluster_scale_jitter` | canopy blob size |
| `cluster_yaw_degrees` | per-blob swing around its attachment point |
| `cluster_sink` | how deep a blob is pushed onto its branch |
| `cull_foliage` | how many of the smallest blobs are removed, leaving bare twigs |

Keep a spread of characters rather than six near-copies: one slender, one broad,
one leaning, one crooked, one short and stocky, one sparse. The world-scale proof
sheet is what makes that spread checkable.

### Adding a new source model

1. Add six entries to `tree_variation_profiles.json` with distinct seeds.
2. `python tools/tree_atlas/make_tree_variations.py --glb <model.glb> --out-dir artifacts/<name>`
3. Check `comparison_world_scale.png`; check `applied.attachment.max_gap_after`
   in every `variation.json`.
4. Copy the twelve output files plus `meta.json` into
   `assets/sprites/flora/layered_trees/tree_NN`, setting `meta.asset` to match
   the directory.
5. Register the new directories in **three** places, which must stay in sync:
   `TREE_SOURCE_DIRS` and `TREE_COLUMNS` in
   `world_layered_object_asset_catalog.gd`, the same two in
   `tools/build_layered_object_channel_atlases.gd`, and
   `PLAINS_LAYERED_TREE_ASSET_DIRS` in `world_streamer.gd`.
6. Rebuild the atlases — the batched runtime reads atlases, not asset
   directories, so a new asset is invisible until this runs:
   `Godot --headless --path . -s tools/build_layered_object_channel_atlases.gd`
7. Extend `TREE_IDS` in `test_layered_asset_bake_contract.py`.
