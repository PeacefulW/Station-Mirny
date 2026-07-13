# Layered Asset Bake Contract

This contract keeps Blender-baked 2D world objects visually consistent across
trees, rocks, props, and future assets.

The machine-readable sources of truth are:

- `tools/tree_atlas/layered_asset_bake_profile.json` for the legacy shared v1
  small-rock bake;
- `tools/tree_atlas/layered_tree_bake_profile_10_oclock_fill_20.json` for
  production layered trees;
- `tools/grass_atlas/grass_tuft_bake_profile.json` for the production grass
  albedo and physical-shadow atlases.

Current profiles:

- `station_peaceful_layered_asset_bake_v1` for small rocks;
- `station_mirny_layered_tree_10_oclock_lamp100_root7_v5` for trees;
- `station_mirny_grass_tuft_10_oclock_lamp100_v3` for grass;
- `station_mirny_layered_tree_fixed_nw_winter_v2` is the superseded tree
  profile retained for bake history and proof reproducibility; it used
  `sun_azimuth_degrees: 205.201124`.
- `station_mirny_layered_tree_10_oclock_fill_20_v4` is the superseded tree
  production profile retained for bake history.
- `station_mirny_grass_tuft_10_oclock_fill_20_v2` is the superseded grass
  production profile retained for bake history; it used the tree v4 lighting
  rig and `20%` low opposite Spot.

## Fixed Tree Bake Rules (V5)

- `frame_size: 768`
- `default_yaw_degrees: 90`
- `tree_06 yaw_degrees: 180` is the single approved silhouette exception
- `sun_azimuth_degrees: 219`
- `albedo_sun_elevation_degrees: 38`
- `shadow_sun_elevation_degrees: 42`
- `root_embed_fraction: 0.07`
- Camera type is orthographic.
- Render view transform is Filmic with Medium High Contrast.
- Screen-space Sun uses the selected `10:00` key and the physical cast direction
  is screen east-south-east (`[0.866025, 0.5]`).
- A low opposite Spot at normalized `(2.25, -2.05, 0.08h)`, aimed at `0.43h`,
  uses energy `100`, cone `52 degrees`, blend `0.88`, and `use_shadow=false`.
  It affects the albedo bake only and creates no second shadow.
- After normalized planting, `ground_clip.mode: physical_mesh_bisect` removes
  geometry below ground `Z=0` with tolerance `0.00001` before every output pass.
  The sprite and the physical Cycles shadow therefore contain all and only the
  visible above-ground trunk, crown and root geometry. No visible root caster is
  suppressed and no synthetic, erased or postprocessed contact silhouette is
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

## Fixed Grass Bake Rules (V3)

- Atlas layout remains `4 x 8` frames at `160 x 120` per frame.
- Grass reuses the tree v5 screen `10:00` Sun, Filmic Medium High Contrast,
  `0.75` exposure, and the same low opposite shadowless Spot at energy `100`.
- The Spot affects albedo only and is hidden from every shadow-catcher render.
- Cycles Sun lighting supplies real blade-to-blade self-shadow in the albedo
  frames and a separate complete physical ground-shadow atlas.
- Grass does not inherit tree planting: it has no normalized
  `root_embed_fraction`, global downward translation, ground-plane clip or mesh
  bisect. The authored `tuft.root_z_min: -0.055` and `root_z_max: 0.035`
  per-blade variation and all other geometry values remain unchanged from v2.
- The authored and runtime ground-shadow direction is fixed screen
  east-south-east (`[0.866025, 0.5]`).
- The tuft root, shadow contact, direction and length remain fixed while wind
  moves only the visible tuft. Grass does not inherit the tree time-of-day
  shadow stretch.
- Existing wind, season, snow and palette-bank masks remain unchanged.

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

Grass promotion replaces only `grass_tuft_atlas.png` and
`grass_tuft_shadow_atlas.png`; wind/season/snow helper atlases stay on their
existing production assets.

Tree `meta.json` records the v5 profile, numeric yaw, ground-clip contract,
fixed screen shadow direction, and contact-lock distance. Rock `meta.json`
continues to record the
legacy shared v1 profile.

## Runtime Rules

Production tree sun shadows use the baked fixed east-south-east physical shadow.
The visible tree and shadow share the metadata anchor. Time-of-day may change
shadow visibility and stretch the far end, but it must not rotate the shadow,
move the root-side contact zone, suppress visible root geometry, or create a
second synthetic shadow. All visible root geometry remains in the authored physical
caster; buried source geometry is already absent from the baked sprite and
shadow due to the v5 ground-plane bisect.

Production grass uses its paired baked east-south-east physical-shadow atlas.
Per-tuft lean and non-uniform scale are cancelled around the authored root so
wind cannot rotate or detach the shadow. Runtime does not stretch grass shadows.

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
