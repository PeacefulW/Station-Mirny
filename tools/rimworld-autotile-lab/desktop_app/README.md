# Cliff Forge Desktop

Native-core desktop rewrite for the legacy RimWorld-style autotile generator.

## Stack

- Rust core: tile generation, atlas rendering, preview rendering, recipe export
- Python shell: desktop UI, map editing, preset control, texture loading, export

## Goals of this rewrite

- keep the tool separate from the legacy HTML version
- make `draft preview` actually cheap
- keep notch cuts visually consistent with ordinary edges
- provide a cleaner request/output contract through JSON + PNG assets

## Run

1. Build the Rust core:

```bat
tools\rimworld-autotile-lab\desktop_app\build_core.cmd
```

2. Launch the desktop shell:

```bat
tools\rimworld-autotile-lab\desktop_app\run_desktop_tool.cmd
```

## Current feature set

- presets: `mountain`, `wall`, `earth`
- 47 canonical signatures
- map painter with blob / room / cave helpers
- draft preview and full atlas generation
- separate preview and atlas tabs so the preview can use the main workspace
- Russian `Материалы` tab with separate Top / Face / Base layer-stack settings
- material source per layer: procedural, image file, or flat color
- procedural material kinds: stone bricks, cracked dry earth, rough stone, worn metal, wood planks, packed dirt, concrete, ice / frost, ash / burnt ground, snow, sand, moss, gravel / regolith, rusty metal, concrete floor (seamed), ribbed steel
- procedural feature sizes (brick width, plank width, voronoi cell, scratch period) scale with `tile_size`, so 32 px and 128 px tiles stay readable
- procedural controls per layer: scale, contrast, crack amount, wear, grain, edge darkening, seed, Color A, Color B, highlight
- anti-aliased sampling for loaded texture files
- continuous map-space texture projection in the live preview
- texture zoom semantics: values above `1.0` zoom source textures in; values below `1.0` zoom them out
- dynamic-lighting-ready normals: shape normals use a 3x3 height blur plus Sobel gradients, with `normal_strength` defaulting to `tile_size / 32.0`
- optional baked height shading in albedo, disabled by default for dynamic lighting
- optional color overlay for loaded texture files, disabled by default
- named export workflow: `asset_name` must be `snake_case` and prefixes every PNG and recipe export
- optional target export folder in the shell; when set, Full Generate writes directly to that folder and asks before overwriting matching `asset_name` files
- export modes:
  - `Full47`: full `47 x N` shape/material export for the legacy Cliff Forge atlas flow
  - `BaseVariantsOnly`: `1 x N` full-tile base material atlas for transition-overlay base passes
  - `MaskOnly`: shared `47 x N` mask atlas without albedo/material exports
- Decals tab for the terrain decal layer authoring pass:
  - `4 x 4` mixed-size atlas with `16`, `32`, `64`, and `128` px decal cells centered inside the selected max cell size
  - per-cell source: procedural, image file, or color
  - per-cell size class, seed, pivot, color, and optional image path
  - optional outline toggle, disabled by default
- Silhouettes tab for the mountain wall silhouette authoring pass:
  - `3 variants x 8 directions` atlas by default: four cardinal sprites plus four corner sprites
  - sprite size defaults to `64 x 96` px and can be adjusted for authoring
  - face material reuses the existing Top / Face / Base material stack
  - top jitter and roughness controls keep the rock-wall top edge continuous through corner cells
- variant count defaults to `6`, which matches the runtime transition overlay consumer; other values are supported for authoring experiments only
- `Full47` exports:
  - `{asset_name}_preview.png`
  - `{asset_name}_atlas_albedo.png`
  - `{asset_name}_atlas_mask.png`
  - `{asset_name}_atlas_height.png`
  - `{asset_name}_atlas_normal.png`
  - `{asset_name}_top_albedo.png`
  - `{asset_name}_face_albedo.png`
  - `{asset_name}_base_albedo.png`
  - `{asset_name}_top_modulation.png`
  - `{asset_name}_face_modulation.png`
  - `{asset_name}_top_normal.png`
  - `{asset_name}_face_normal.png`
  - `{asset_name}_recipe.json`
- `BaseVariantsOnly` exports:
  - `{asset_name}_preview.png`
  - `{asset_name}_atlas_albedo.png`
  - `{asset_name}_recipe.json`
- `MaskOnly` exports:
  - `{asset_name}_preview.png`
  - `{asset_name}_atlas_mask.png`
  - `{asset_name}_recipe.json`
- Decals export:
  - `{asset_name}_decal_atlas.png`
  - `{asset_name}_decal_metadata.json`
- Silhouettes export:
  - `{asset_name}_silhouette_atlas.png`
  - `{asset_name}_silhouette_metadata.json`
- recipe save/load in the shell

## Notes

- The shell uses `Pillow` for image display.
- The Rust core will rebuild on first use if the release binary is missing.
- Atlases refresh on `Full Generate`; draft updates only the live preview.
