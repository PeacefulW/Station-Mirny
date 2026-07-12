# Layered Asset Bake Contract

This contract keeps Blender-baked 2D world objects visually consistent across
trees, rocks, props, and future assets.

The machine-readable sources of truth are:

- `tools/tree_atlas/layered_asset_bake_profile.json` for the legacy shared v1
  small-rock bake;
- `tools/tree_atlas/layered_tree_bake_profile_10_oclock_fill_20.json` for
  production layered trees.

Current profiles:

- `station_peaceful_layered_asset_bake_v1` for small rocks;
- `station_mirny_layered_tree_10_oclock_fill_20_v4` for trees;
- `station_mirny_layered_tree_fixed_nw_winter_v2` is the superseded tree
  profile retained for bake history and proof reproducibility; it used
  `sun_azimuth_degrees: 205.201124`.

## Fixed Tree Bake Rules (V4)

- `frame_size: 768`
- `default_yaw_degrees: 90`
- `tree_06 yaw_degrees: 180` is the single approved silhouette exception
- `sun_azimuth_degrees: 219`
- `albedo_sun_elevation_degrees: 38`
- `shadow_sun_elevation_degrees: 42`
- `root_embed_fraction: 0.011`
- Camera type is orthographic.
- Render view transform is Filmic with Medium High Contrast.
- Screen-space Sun uses the selected `10:00` key and the physical cast direction
  is screen east-south-east (`[0.866025, 0.5]`).
- A low opposite Spot at normalized `(2.25, -2.05, 0.08h)`, aimed at `0.43h`,
  uses energy `23.3515625`, cone `52 degrees`, blend `0.88`, and
  `use_shadow=false`. It affects the albedo bake only and provides the selected
  measured `20%` dark-trunk lift without creating a second shadow.
- Complete physical Cycles shadows from all GLB geometry are baked from the Sun
  alone; no root caster is suppressed and no synthetic contact silhouette is
  added.
- The first `48 px` along the authored shadow direction is the fixed contact
  zone. Runtime may stretch only the farther shadow end.
- Winter keeps the complete foliage alpha silhouette, freezes/desaturates the
  leaves, adds light crown frost, and composites supported snow from
  `snow_overlay.png`.
- normal maps are generated but disabled in runtime.

## Legacy Small-Rock Bake Rules (V1)

- `frame_size: 768`
- `default_yaw_degrees: 90`
- `sun_azimuth_degrees: 315`
- `albedo_sun_elevation_degrees: 52`
- `shadow_sun_elevation_degrees: 42`
- `root_embed_fraction: 0.065`
- Camera type is orthographic.
- Render view transform is Filmic with Medium High Contrast.
- Legacy v1 shadow textures are authored toward screen north-east; this remains
  the texture-space bake axis for assets that have not moved to the v2 profile.
- normal maps are generated but disabled in runtime.
- Existing small-rock assets remain on this profile until a separately approved
  rock rebake.

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

Tree `meta.json` records the v4 profile, numeric yaw, fixed screen shadow
direction, and contact-lock distance. Rock `meta.json` continues to record the
legacy shared v1 profile.

## Runtime Rules

Production tree sun shadows use the baked fixed east-south-east physical shadow.
The visible tree and shadow share the metadata anchor. Time-of-day may change
shadow visibility and stretch the far end, but it must not rotate the shadow,
move the root-side contact zone, suppress root geometry, or create a second
synthetic shadow.

Winter is a reversible presentation amount. It may recolour/freeze foliage and
reveal supported snow/frost, but it must not reduce foliage alpha or produce a
detached snow crown.

Dynamic light shadows are separate runtime presentation. Normal maps stay
generated for future experiments, but runtime tree materials do not receive or
write `NORMAL_MAP` until the lighting pipeline is retuned.

## Authoring Notes

Use the relevant versioned profile instead of hand-entering Blender settings.
If a specific asset needs a different yaw for silhouette quality, pass it
explicitly and make sure `classification.json` and production `meta.json`
record it.

Do not manually recolour a final sprite to make it match. Fix the Blender bake,
postprocess, or profile so future assets remain reproducible.
