---
title: Ground Elevation Faces
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: false
version: 0.1
last_updated: 2026-03-30
depends_on:
  - world_generation_foundation.md
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
related_docs:
  - native_chunk_generation_spec.md
  - boot_visual_completion_spec.md
---

# Feature: Ground Elevation Faces

## Design Intent

Ground tiles adjacent to WATER should display elevation faces — wall-like edges that create a visual impression of raised terrain next to water, like a riverbank or coastline cliff. This gives the world a 3D depth effect: water sits lower, ground sits higher, with visible edges at the boundary.

Uses the same 47-tile wall form system as mountains (`rock_faces_atlas.png`), but with a separate atlas (`ground_faces_atlas.png`) that has shorter wall height and neutral gray base color. The biome-specific ground color is applied at runtime via `modulate`, so one atlas serves all biomes.

Sand tiles adjacent to WATER use a separate atlas (`sand_faces_atlas.png`) with the same approach.

## Visual Model

```
Render order (bottom to top):
1. Water tile (WATER terrain in _terrain_layer, z=-10)
2. Ground/Sand tile (biome-colored flat fill in _terrain_layer, z=-10)
3. Ground faces overlay (ground_faces_atlas tinted by biome color, z=-9.5)
   OR Sand faces overlay (sand_faces_atlas, z=-9.5)
4. Rock faces overlay (rock_faces_atlas, z=-9)
```

Ground faces are ONLY drawn on GROUND/GRASS tiles that have at least one WATER neighbor. The wall form selection logic is identical to rock wall forms — same 47-type neighbor analysis, same cardinal + diagonal checks. The difference is:
- "open" for ground faces = neighbor is WATER (not "neighbor is non-ROCK")
- Ground face atlas has shorter walls (lower elevation)
- Color is biome `ground_color` applied via modulate

Sand faces follow the same pattern but:
- Drawn on SAND tiles adjacent to WATER
- Use `sand_faces_atlas.png`
- Color is biome `sand_color` via modulate

## Atlases

### ground_faces_atlas.png
- Location: `assets/sprites/terrain/ground_faces_atlas.png`
- Format: same layout as `rock_faces_atlas.png` — 47 tile definitions, potentially multiple variants
- Color: neutral gray (code applies biome color via modulate)
- Alpha: transparent outside face geometry, opaque on face surface
- Wall height: shorter than rock (represents terrain elevation, not mountain wall)

### sand_faces_atlas.png
- Location: `assets/sprites/terrain/sand_faces_atlas.png`
- Format: same 47-tile layout
- Color: neutral gray or sand-tinted (code applies biome sand_color via modulate)

## Architecture

### New TileMapLayer: `_ground_face_layer`
- z_index: -9 (between terrain at -10 and rock at -9... need to adjust)
- Actually: terrain=-10, ground_faces=-9.5 is not possible with int z_index
- Solution: terrain=-12, ground_faces=-11, rock=-10, cliff=-9

### Wall form selection for ground faces
Reuse `_surface_rock_visual_class()` logic but with different "open" definition:
- For rock: open = non-ROCK terrain
- For ground faces: open = WATER only

New function `_ground_face_visual_class(local_tile)`:
- Same 47-type neighbor analysis
- `_is_water_neighbor(terrain_type)` = `terrain_type == WATER`
- Cardinal + diagonal checks identical to rock wall form
- Returns same WALL_* constants (same atlas layout)

### Biome color tinting
Ground face tiles need biome-specific coloring. Options:
1. **Per-tile modulate** — `_ground_face_layer.set_cell()` with modulate via TileData
2. **Per-chunk modulate** — single modulate on layer (only works if chunk = one biome)
3. **Pre-tinted atlas per biome** — generate colored atlas at tileset build time

Option 3 is most consistent with current rock atlas approach. `ChunkTilesetFactory` already builds per-biome tilesets. Add ground face tiles to the tileset, pre-tinted with `biome.ground_color`.

### Integration with redraw
In `_redraw_terrain_tile()`:
- If terrain_type is GROUND/GRASS and any cardinal/diagonal neighbor is WATER:
  - Compute ground face visual class (same 47-type logic, open = WATER)
  - Set cell in `_ground_face_layer` with tinted atlas coords
- If terrain_type is SAND and any neighbor is WATER:
  - Compute sand face visual class
  - Set cell in `_ground_face_layer` with sand atlas coords
- Else: erase `_ground_face_layer` cell

## Data Contracts

### Affected layer: Presentation
- What changes: new `_ground_face_layer` TileMapLayer in Chunk for elevation faces
- New invariants:
  - ground faces drawn ONLY on GROUND/GRASS tiles adjacent to WATER
  - sand faces drawn ONLY on SAND tiles adjacent to WATER
  - wall form selection identical to rock (47 types, cardinal + diagonal)
  - ground face color = biome ground_color, sand face color = biome sand_color
- Who adapts: Chunk, ChunkTilesetFactory
- What does NOT change: rock layer, terrain layer, cover layer

## Iterations

### Iteration 1 — Ground faces next to water

Goal: GROUND/GRASS tiles adjacent to WATER show elevation edge faces.

What is done:
- Load `ground_faces_atlas.png` in ChunkTilesetFactory
- Add pre-tinted ground face tiles to per-biome tileset (colored by ground_color)
- Add `_ground_face_layer` TileMapLayer to Chunk (z_index between terrain and rock)
- New `_ground_face_visual_class(local_tile)` — same 47-type logic, open = WATER
- In `_redraw_terrain_tile()`: if GROUND/GRASS and has WATER neighbor → set ground face
- Clear ground face layer in `_redraw_all()` and `_begin_progressive_redraw()`

Acceptance tests:
- [ ] GROUND tiles next to river show elevation faces
- [ ] Face form matches neighbor pattern (corners, edges, peninsulas correct)
- [ ] Face color matches biome ground_color
- [ ] GROUND tiles NOT next to water have no faces
- [ ] No performance regression (ground face check is O(8 neighbors) per tile, same as rock)

Files that may be touched:
- `core/systems/world/chunk.gd` — new layer, new visual class function, redraw integration
- `core/systems/world/chunk_tileset_factory.gd` — load ground atlas, add tinted tiles to tileset

Files that must NOT be touched:
- `core/systems/world/chunk_manager.gd`
- `core/autoloads/world_generator.gd`
- C++ code

### Iteration 2 — Sand faces next to water

Goal: SAND tiles adjacent to WATER show sand elevation faces.

What is done:
- Load `sand_faces_atlas.png` in ChunkTilesetFactory
- Add pre-tinted sand face tiles to per-biome tileset (colored by sand_color)
- In `_redraw_terrain_tile()`: if SAND and has WATER neighbor → set sand face
- Same visual class logic as ground faces

Acceptance tests:
- [ ] SAND tiles next to river show sand elevation faces
- [ ] Sand face color matches biome sand_color
- [ ] Sand and ground faces don't conflict at boundaries

Files that may be touched:
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_tileset_factory.gd`

### Iteration 3 — Progressive redraw integration

Goal: ground/sand faces participate in progressive redraw correctly.

What is done:
- Ground face layer cleared in progressive redraw init
- Ground faces drawn during TERRAIN redraw phase (same pass as terrain tiles)
- Cross-chunk neighbor reads work for ground faces (same as rock)
- Boot and runtime streaming handle ground faces without additional cost

Acceptance tests:
- [ ] Progressive redraw shows ground faces correctly
- [ ] No visual pop-in of ground faces after chunk loads
- [ ] Cross-chunk water boundaries show correct ground faces

## Out-of-scope

- Ground faces at biome boundaries (ground-to-ground transitions)
- Ground faces next to SAND (only next to WATER)
- Animated water edges
- Height variation within ground faces
- Underground ground faces
