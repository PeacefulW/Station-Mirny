# RimWorld Autotile Lab

Authoring workspace for Cliff Forge terrain presentation assets. The desktop
tool lives in `desktop_app/`; the bridge script in this folder converts exported
recipes and PNG sets into Godot `.tres` resources under `data/terrain/...`.

## Authoring Modes

### Terrain Materials

The Materials tab supports three export modes:

- `Full47`: exports a full `47 x N` terrain shape set plus material textures.
- `BaseVariantsOnly`: exports a `1 x N` base material atlas for split
  base/transition rendering.
- `MaskOnly`: exports only the shared `47 x N` grayscale mask atlas.

All terrain exports use the authored `asset_name` prefix, for example
`plains_ground_atlas_mask.png` and `plains_ground_recipe.json`.

### Decals

The Decals tab exports one mixed-size `4 x 4` atlas:

- `{asset_name}_decal_atlas.png`
- `{asset_name}_decal_metadata.json`

The metadata must describe `16` cells with size class and pivot data.

### Silhouettes

The Silhouettes tab exports the first-biome rock wall silhouette atlas:

- `{asset_name}_silhouette_atlas.png`
- `{asset_name}_silhouette_metadata.json`

The first expected layout is `3` variants by `8` directions
(`N / E / S / W / NE / SE / SW / NW`), with `64 x 96` cells by default.

## Recipe To `.tres` Bridge

Run the bridge from the project root after exporting a recipe and PNG set:

```powershell
python tools/rimworld-autotile-lab/recipe_to_tres.py `
  assets/textures/terrain/plains_ground/plains_ground_recipe.json `
  --asset-dir assets/textures/terrain/plains_ground `
  --target data/terrain `
  --project-root .
```

`--target` should point at the `data/terrain` root. The bridge writes into the
canonical subfolders:

- `Full47` -> `shape_sets/{asset_name}_shape_set.tres` and
  `material_sets/{asset_name}_material_set.tres`
- `BaseVariantsOnly` -> `material_sets/{asset_name}_material_set.tres`
- `MaskOnly` -> `shape_sets/{asset_name}_shape_set.tres`
- `--mode Decals` -> `decals/{asset_name}_atlas.tres`
- `--mode Silhouettes` -> `silhouettes/{asset_name}.tres`

Use `--dry-run` to print the planned `.tres` files without writing:

```powershell
python tools/rimworld-autotile-lab/recipe_to_tres.py `
  assets/textures/terrain/plains_ground/plains_ground_recipe.json `
  --asset-dir assets/textures/terrain/plains_ground `
  --target data/terrain `
  --project-root . `
  --dry-run
```

Use `--mode Decals` or `--mode Silhouettes` when converting decal or silhouette
exports, because their recipe can share the terrain request shape while the
metadata files define the intended resource family.

## Validation

The bridge validates input before writing:

- `Full47` and `MaskOnly` mask atlases must be `47 * tile_size_px` wide by
  `variant_count * tile_size_px` high.
- `Full47` shape normal atlases must match the same dimensions.
- `BaseVariantsOnly` base atlases are validated as `1 x variant_count` when an
  `{asset_name}_atlas_albedo.png` file is present.
- `Full47` material output requires the six canonical material maps:
  `top_albedo`, `face_albedo`, `top_modulation`, `face_modulation`,
  `top_normal`, and `face_normal`.
- Decal metadata must describe a `4 x 4` atlas with `16` cells.
- Silhouette metadata must match the exported atlas dimensions and direction
  count.

All texture references are written as `res://...` paths relative to
`--project-root`.
