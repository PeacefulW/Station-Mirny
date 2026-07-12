# Layered Asset Bake Contract

This contract keeps Blender-baked 2D world objects visually consistent across
trees, rocks, props, and future assets.

The machine-readable source of truth is:

`tools/tree_atlas/layered_asset_bake_profile.json`

Current profile: `station_peaceful_layered_asset_bake_v1`.

## Fixed Bake Rules

- `frame_size: 768`
- `default_yaw_degrees: 90`
- `sun_azimuth_degrees: 315`
- `albedo_sun_elevation_degrees: 52`
- `shadow_sun_elevation_degrees: 42`
- `root_embed_fraction: 0.065`
- Camera type is orthographic.
- Render view transform is Filmic with Medium High Contrast.
- Shadow textures are authored toward screen north-east; this is the texture-space
  bake axis, not the final runtime direction.
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

Runtime rotates the authored north-east shadow around the object anchor onto the
canonical cast-shadow axis. With the fixed north-west light (`225°`), the final
screen-space shadow points south-east (`45°`). Time of day may change length,
opacity, and softness, but not that azimuth. Stretching happens away from the
root after this rotation; the root side stays pinned to the object anchor.

Dynamic light shadows are runtime fake shadows. They are separate from this
sun-shadow bake contract.

Normal maps stay generated for future experiments, but runtime tree materials do
not receive or write `NORMAL_MAP` until the lighting pipeline is retuned.

## Authoring Notes

Use the shared profile instead of hand-entering Blender settings. If a specific
asset needs a different yaw for silhouette quality, pass it explicitly and make
sure the resulting `classification.json` and `meta.json` record it.

Do not manually recolor a final sprite to "make it match"; fix the Blender bake,
postprocess, or profile instead. The goal is that future assets can be rebaked
and compared without guessing which settings were used.
