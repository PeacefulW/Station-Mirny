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
- Shadows are baked toward screen north-east.
- normal maps are generated but disabled in runtime.

## Required Outputs

Each layered asset directory must contain:

- `albedo.png`
- `trunk.png` or the closest object-body layer for non-tree objects
- `foliage.png` or the closest top/detail layer for non-tree objects
- `shadow.png`
- `wind_mask.png` when the object can move
- `snow_mask.png`
- `snow_overlay.png`
- `season_mask.png`
- `height.png`
- `normal.png`
- `meta.json`
- `preview_panel.png`

`meta.json` must include a `bake_profile` block with the profile id, version,
frame size, sun angles, and root embed fraction used for the bake.

## Runtime Rules

Sun shadows are baked fixed north-east and can only stretch away from the root.
The root side must stay pinned to the object anchor.

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
