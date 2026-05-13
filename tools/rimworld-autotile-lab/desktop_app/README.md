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
- 16 true marching-squares signatures
- map painter with blob / room / cave helpers
- draft preview and full atlas generation
- separate preview and atlas tabs so the preview can use the main workspace
- Russian `Материалы` tab with separate Top / Face / Base layer-stack settings
- material source per layer: procedural, image file, or flat color
- procedural material kinds: stratified rock, stone bricks, cracked dry earth, rough stone, worn metal, wood planks, packed dirt, concrete, ice / frost, ash / burnt ground, snow, sand, moss, gravel / regolith, rusty metal, concrete floor (seamed), ribbed steel
- mountain preset is self-contained by default and uses procedural stratified rock for the cliff face instead of requiring local source textures
- procedural feature sizes (brick width, plank width, voronoi cell, scratch period) scale with `tile_size`, so 32 px and 128 px tiles stay readable
- procedural controls per layer: scale, contrast, crack amount, wear, grain, edge darkening, seed, Color A, Color B, highlight; `scale > 1.0` zooms procedural detail in to match loaded texture zoom semantics
- anti-aliased sampling for loaded texture files
- continuous map-space texture projection in the live preview; SDF facade zones project face materials in contour-tangent/depth coordinates so procedural and image textures turn with the cliff wall instead of staying screen-horizontal
- live map preview uses a single global signed-distance field (SDF) for
  smoother cross-tile facade height/normal transitions while honoring the
  contour roundness, diagonal smoothing, outer/inner corner radius, warp,
  roughness, and edge controls; automatic variants vary material sampling
  without splitting one mountain's preview contour into per-cell geometry
- texture zoom semantics: values above `1.0` zoom source textures and procedural materials in; values below `1.0` zoom them out
- true marching-squares terrain geometry: the full shape atlas now uses 16 corner-mask cases (`ms_0..ms_f`) instead of the old 47 center-cell adjacency family
- Geometry tab controls are grouped by visible output: `Форма / mask`, `Высота / normal`, and `Материал / albedo`
- active marching-squares smoothing controls: `corner_round_px` rounds current `ms_*` contour masks and `diagonal_smooth_px` softens diagonal marching cases
- organic terrain geometry controls: `contour_warp_px` adds map-space contour noise, `rim_width`, `edge_debris`, `colors.edge`, and `edge_color_strength` control the visible cliff lip, `mountain_outline_enabled` / `mountain_outline_width` add an optional bottom-only black contact outline for mountain faces, and `normal_detail_strength` adds height relief for dynamic lighting
- default terrain presets use gentler `roughness` / `contour_warp_px` values so rounded corners stay readable
- rim and chip controls: `rim_width` and `edge_debris` add a visible live-preview cliff-lip edge band plus broken height/normal relief for authored ledges without baking drop shadows into albedo; `edge_debris` grows in gradually from zero instead of adding a full-width lip at the first nonzero value; `north_height` and `side_height` may be set to `0` for a strict front-only preview that keeps the lip without side/back facade protrusions
- dynamic-lighting-ready normals: shape normals use a 3x3 height blur plus Sobel gradients, with `normal_strength` defaulting to `tile_size / 32.0`; live SDF preview normals sample map-space height across tile boundaries, and `normal_detail_strength` adds extra height relief for more readable dynamic lighting
- optional lit preview mode (`lit`) visualizes the exported normal/height response inside the generator only; exported albedo remains unlit for the game's dynamic lighting, and the shell exposes a light-angle slider for inspecting normal response
- shape supersampling: `shape_supersampling` anti-aliases curved mask/height/normal edges and blends partial live-preview albedo coverage against the base material; current quality presets default to `4`
- optional baked height shading in albedo, disabled by default for dynamic lighting
- optional color overlay for loaded texture files, disabled by default
- named export workflow: `asset_name` must be `snake_case` and prefixes every PNG and recipe export
- optional target export folder in the shell; when set, Full Generate writes directly to that folder and asks before overwriting matching `asset_name` files
- export modes:
  - `Full47`: full `16 x N` marching-squares shape/material export; the serialized key is kept for older UI state and recipes
  - `BaseVariantsOnly`: `1 x N` full-tile base material atlas for transition-overlay base passes
  - `MaskOnly`: shared `16 x N` marching-squares mask atlas without albedo/material exports
  - `RuntimeSdfContour`: target game contour export; writes a runtime SDF recipe plus reference mask/height/normal/albedo images from the same global SDF map-preview path used by the live preview
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
- Draft preview in the shell is transient: the core process returns PNG bytes over stdout and does not write a preview PNG during slider-driven refreshes. CLI draft renders without `--inline-preview --transient` still export:
  - `{asset_name}_preview.png`
- `Full47` / marching-squares full generation exports:
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
- For legacy atlas modes, SDF is still preview-only; `Full47` / `MaskOnly`
  atlas exports still use the per-cell marching-squares path until atlas parity
  is implemented.
  `RuntimeSdfContour` is the target game export path and uses the global SDF
  map-preview path for its reference images. Automatic SDF preview variants keep
  geometry continuous and vary material sampling only.
- `BaseVariantsOnly` full generation exports:
  - `{asset_name}_atlas_albedo.png`
  - `{asset_name}_recipe.json`
- `MaskOnly` full generation exports:
  - `{asset_name}_atlas_mask.png`
  - `{asset_name}_recipe.json`
- `RuntimeSdfContour` full generation exports:
  - `{asset_name}_runtime_sdf_recipe.json`
  - `{asset_name}_reference_mask.png`
  - `{asset_name}_reference_height.png`
  - `{asset_name}_reference_normal.png`
  - `{asset_name}_reference_albedo.png`
  - `{asset_name}_top_albedo.png`
  - `{asset_name}_face_albedo.png`
  - `{asset_name}_base_albedo.png`
  - `{asset_name}_top_modulation.png`
  - `{asset_name}_face_modulation.png`
  - `{asset_name}_top_normal.png`
  - `{asset_name}_face_normal.png`
- Decals export:
  - `{asset_name}_decal_atlas.png`
  - `{asset_name}_decal_metadata.json`
- Silhouettes export:
  - `{asset_name}_silhouette_atlas.png`
  - `{asset_name}_silhouette_metadata.json`
- recipe save/load in the shell

## Notes

- The shell uses `Pillow` for image display.
- The Rust request contract is introspectable from the core binary with `--print-default-request` and `--print-request-schema`.
- The Rust core will rebuild on first use if the release binary is missing. The shell keeps one `cliff_forge_core --serve` process alive and cancels/restarts it when a newer preview request supersedes an in-flight render.
- Atlases refresh on `Full Generate`; the full core run does not recompute
  `{asset_name}_preview.png`, and the shell queues a draft refresh afterward
  so the live preview stays current without making atlas generation pay for it.
