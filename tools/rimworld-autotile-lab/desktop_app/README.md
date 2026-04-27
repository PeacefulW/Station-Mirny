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
- exports:
  - `preview.png`
  - `atlas_albedo.png`
  - `atlas_mask.png`
  - `atlas_height.png`
  - `atlas_normal.png`
  - `top_albedo.png`
  - `face_albedo.png`
  - `base_albedo.png`
  - `top_modulation.png`
  - `face_modulation.png`
  - `top_normal.png`
  - `face_normal.png`
  - `recipe.json`
- recipe save/load in the shell

## Notes

- The shell uses `Pillow` for image display.
- The Rust core will rebuild on first use if the release binary is missing.
- Atlases refresh on `Full Generate`; draft updates only the live preview.
