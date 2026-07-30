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
- tree ground bounce `energy: 150`; small rocks use `30%` of it (`energy: 45`)
- ground bounce casts no shadow and is absent from the shadow pass
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
and `season_mask.png`. Bush assets ship the same tree channel set: they are
baked on this contract from procedural Blender geometry
(`tools/bush_atlas/`), not from a source GLB. Static small rock assets intentionally do not contain a
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

Trees use the full authored bounce (`150`). Small rocks use a family-specific
`0.30` multiplier (`45`). Their compact lower face otherwise reads as if a
second light were shining upward from the side opposite the sun, erasing
self-shadowing. Every rock `meta.json` records both
`rock_bounce_energy_scale: 0.3` and `rock_bounce_energy: 45.0`; this is a
rock-family bake override and does not change the shared profile revision or
tree lighting.

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
| layered small rocks | 4 | screen south-east | shared `SHADOW_*` |
| layered bushes | 4 | screen south-east | `BUSH_SHADOW_*` |
| mountains, decor, living flora | not on this contract | — | — |

When a family migrates, re-bake it, flip its runtime framing constants, and move
its row here in the same change. Do not flip a shared runtime constant while any
family on it is still baked against the old sun.

The rock family migrated on 2026-07-28. Two things had to move with the re-bake,
and both are pinned by `test_runtime_shadow_stretch_matches_the_baked_sun`:
`SHADOW_*` in `world_layered_object_asset_catalog.gd`, and the layer's own copy
of `SHADOW_DIRECTION` in `layered_rock_object_layer.gd`. They now hold the same
values as the tree constants but stay separate, because the next family to
migrate will need its own.

Re-baking a shipped family is `tools/tree_atlas/rebake_small_rock_assets.py`,
driven by `small_rock_source_manifest.json`, which records the source GLB per
asset so the re-bake does not have to read it back out of the `meta.json` files
it is about to overwrite. Baking and promotion are separate steps (`--promote`),
so the before/after sheet still has the old bake to compare against.

Note that `blender_layered_rock_asset_bake.py` could not run against revision 4
at all before this migration: it read `lighting.fill_energy`, which revision 4
removed. A family left un-migrated long enough stops being merely stale.

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

## Procedural Stone Silhouettes (No Source Model)

Rocks do not need a source GLB at all. That path is
`tools/tree_atlas/make_rock_variations.py`, driven by
`tools/tree_atlas/rock_variation_profiles.json`
(`station_peaceful_rock_variation_v1`), with the Blender side in
`blender_rock_variation_bake.py`.

Like the tree variation step, it does not own bake settings — camera, lighting,
engines, render passes and postprocess all still come from this contract. It
replaces only the *source* stage: an icosphere shaped by four deterministic
passes.

| stage | what it does |
| --- | --- |
| anisotropic shape | `flatten`, `elongation`, `taper` set the family's proportions |
| facet cuts | `facet_count` planes project everything past them flat, `facet_sharpness` scales how completely |
| chips | `chip_count` local bites break the outline out of convexity |
| erosion | summed Perlin octaves along the radius, `erosion_scale` / `erosion_strength` |

The order matters: cuts run before chips so a chip can bite into an already flat
face, and erosion runs last so its grain survives instead of being flattened by
a later cut.

**A slab is not a separate code path.** It is the same generator with `flatten`
low and `embed_fraction` high, so the stone reads as sunk into the ground rather
than resting on it. One generator therefore covers slab, boulder, shard and
pebble; adding a fifth family means adding parameter entries, not a branch.

Four rules keep those bakes valid:

- **Facet normals must stay near-horizontal** (`facet_max_vertical`). A cut from
  directly above an already-flattened slab shaves the whole top surface off
  instead of breaking the outline — and the outline is what carries the variety.
- **Sharp edges are split, not shaded.** Flat shading over ~1300 eroded faces
  reads as noise; pure smooth shading rounds the facet cuts away. Edges steeper
  than `sharp_edge_angle_degrees` are split and everything is then shaded smooth.
- **Slabs sink deeper than the shared tree ceiling allows**, so the generator
  carries its own `max_embed_fraction` instead of silently clamping to `0.22`.
- **Surface tone is measured, not eyeballed.** The authored base colour is the
  actual surface tone; compare mean/p90 luma of the albedo against the shipped
  rocks (`small_rock_03` sits at mean luma ≈ 100) and adjust
  `material.base_color_srgb`, never the exposure.

The crack network is a Voronoi distance-to-edge ramp. **Run it white→black**, so
the mask is 1 on the seam: the other direction lights the seams and darkens the
cells, which reads as reptile skin rather than stone. Seams are then gated
behind a low-frequency mask, because an evenly cracked stone looks manufactured.

Both detail layers are bump only. Displacing them into geometry would fight the
silhouette work, and the runtime does not consume normal maps yet.

### Adding a procedural stone

1. Add entries to `rock_variation_profiles.json` with distinct seeds.
2. `python tools/tree_atlas/make_rock_variations.py --out-dir artifacts/<name>`
3. Check `comparison_world_scale.png` for a real spread of silhouettes, and the
   albedo luma against the shipped rocks.
4. Promote into `assets/sprites/decor/plains/layered_small_rocks/`, register the
   new directories, and rebuild the channel atlases — a new asset is invisible
   until that runs.

The whole bake is bit-for-bit reproducible from the seeds, including the Cycles
shadow pass: two runs of the same profile produce identical layers.

### Adding a new source model

1. Add six entries to `tree_variation_profiles.json` with distinct seeds.
2. `python tools/tree_atlas/make_tree_variations.py --glb <model.glb> --out-dir artifacts/<name>`
3. Check `comparison_world_scale.png`; check `applied.attachment.max_gap_after`
   in every `variation.json`.
4. Copy the twelve output files plus `meta.json` into
   `assets/sprites/flora/layered_trees/<family>_NN`, setting `meta.asset` to
   match the directory. The shipped plains family is `rust_crown_01..08`, grown
   procedurally by `tools/tree_atlas/blender_rust_crown_tree_bake.py` rather
   than imported from a GLB; the older `tree_01..06` bakes still sit on disk but
   are no longer registered anywhere in the runtime.
5. Register the new directories in **three** places, which must stay in sync:
   `TREE_SOURCE_DIRS` and `TREE_COLUMNS` in
   `world_layered_object_asset_catalog.gd`, the same two in
   `tools/build_layered_object_channel_atlases.gd`, and
   `PLAINS_LAYERED_TREE_ASSET_DIRS` in `world_streamer.gd`.
6. Rebuild the atlases — the batched runtime reads atlases, not asset
   directories, so a new asset is invisible until this runs:
   `Godot --headless --path . -s tools/build_layered_object_channel_atlases.gd`
7. Extend `TREE_IDS` in `test_layered_asset_bake_contract.py`.
