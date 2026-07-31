---
title: Plains Ground Gravel Relief — Lit Micro-Stones on Open Soil
doc_type: system_spec
status: approved
source_of_truth: true
owner: engineering+art
version: 1.0
last_updated: 2026-07-31
related_docs:
  - plains_ground_field_composition.md
  - plains_ground_cosmetic_shading.md
  - plains_bare_ground_stone_scatter.md
  - terrain_hybrid_presentation.md
  - mountain_cavity_skylight_occlusion.md
  - visual_runtime_lab.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
---

# Plains Ground Gravel Relief — Lit Micro-Stones on Open Soil

**Approved by the owner on 2026-07-31; Iteration 1 landed the same day. The
remaining open items are the mountain-cavity read and the owner's visual
acceptance — see Acceptance Criteria.**

## Purpose

Open plains soil currently reads as a painted plane. The existing transition
scree ([`plains_ground_field_composition.md`](plains_ground_field_composition.md)
Iteration 2) is a thresholded `fbm2` multiplied into colour — it has no
silhouette and no light response, which is exactly why
[`plains_bare_ground_stone_scatter.md`](plains_bare_ground_stone_scatter.md)
records that *"it reads as dirt grain, not as stones"*.

This spec adds the missing third relief scale: **discrete lit gravel**, roughly
`5..14 px` across, dense on open soil and along paths, carrying its own
sun-directional shading and contact shadow so the ground gains readable volume.

Two scales already exist and stay untouched:

| scale | knob | owner |
|---|---|---|
| macro form | `shade_scale_px = 3500` | `plains_ground_cosmetic_shading.md` |
| meso soil masses | `soil_field_scale_px = 2400`, `macro_drift_scale_px = 4600` | `plains_ground_field_composition.md` |
| **micro gravel** | **`gravel_cell_px ≈ 22`** | **this spec** |

## Gameplay Goal

Walking across open soil, the player sees ground that is physically littered
rather than tinted: individual stones catch the sun on one side, sit in their
own small shadow, and thin out as grass takes over. Bare clearings and trails
stop reading as flat orange paint without any new object being placed.

## Scope

- one new procedural **cell-based** (jittered-grid) stone field in
  [`ground_hybrid_material.gdshader`](../../../assets/shaders/ground_hybrid_material.gdshader),
  evaluated in world space;
- analytic dome height per stone, its analytic gradient, and sun-directional
  shading driven by the **existing** `ground_sun_angle_deg` / `ground_sun_day`
  uniforms;
- a per-stone contact shadow offset along the same sun direction;
- silhouette antialiasing and a zoom-based LOD fade;
- a coverage mask restricting gravel to open soil and paths;
- new authored `sampling_params` knobs in
  [`plains_ground_material_set.tres`](../../../data/terrain/material_sets/plains_ground_material_set.tres);
- a downward retune of `scree_open_amount` if the render probe shows double
  littering.

## Out of Scope

- any change to `grass_density`, the field formula, placement, or packet params
  (therefore **no C++ field mirror, no `WORLD_VERSION` bump, no DLL rebuild**);
- `MultiMeshInstance2D` gravel instances, a new `object_kind`, or reviving the
  removed families `1` / `5` / `6`;
- per-chunk mask textures or any per-chunk state in the ground shader;
- `NORMAL_MAP` output (`temporary_disable_terrain_normals = true`; there is no
  `Light2D` to consume ground normals — see ADR-0005);
- gameplay light, visibility, collision, harvest, walkability, save/load;
- gravel on the mountain wall/roof material or in the foothill overlay;
- non-`plains` biomes.

## Dependencies

- Ground composition contract: [`terrain_hybrid_presentation.md`](terrain_hybrid_presentation.md)
  ("Runtime 2D Terrain Ground Composition").
- Field composition and the `scree` / `path_open` / `grass_density_visual`
  terms: [`plains_ground_field_composition.md`](plains_ground_field_composition.md).
- The single cosmetic sun source: [`plains_ground_cosmetic_shading.md`](plains_ground_cosmetic_shading.md)
  and [`world_visual_lighting_profile.gd`](../../../core/systems/world/world_visual_lighting_profile.gd).
- Baked-asset sun agreement (screen south-east, bake profile revision `4`):
  [`plains_bare_ground_stone_scatter.md`](plains_bare_ground_stone_scatter.md).
- Param wiring: [`world_tile_set_factory.gd:250`](../../../core/systems/world/world_tile_set_factory.gd:250)
  copies every `sampling_params` entry onto the shader material by name — new
  uniforms need **no** GDScript change.
- Authoring surface: [`visual_runtime_lab.md`](visual_runtime_lab.md).

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Visual only. Owns no terrain id, walkability, placement, or save state. |
| Save/load required? | No. Knobs live in the material set resource. |
| Deterministic? | Yes. A pure function of `world_pos` and authored params. |
| Must it work on unloaded chunks? | Yes, and it does by construction — no chunk-local input exists. |
| C++ compute or main-thread apply? | Neither. GPU fragment work in an already-bound material. |
| Dirty unit | None new. No CPU recomputation is introduced. |
| Single owner | This spec owns the gravel term; `plains_ground_field_composition.md` keeps the density field; `plains_ground_cosmetic_shading.md` keeps the sun model. |
| 10x / 100x scale path | Cost is per visible fragment, not per stone. Stone count does not exist as a runtime quantity. |
| Main-thread blocking risk | None. |
| Hidden fallback? | Forbidden. A `sampling_params` key that does not match a uniform is silently dropped by `set_shader_parameter` — see Risks; the acceptance check greps both sides. |
| Whole-world prepass? | No. |

## Design Intent

### 1. Cells, not fbm — this is the whole point

Every existing ground field is `fbm`. `fbm` thresholded gives *regions*, and a
region has no interior structure, which is why scree reads as grain. Gravel
needs *objects*: a discrete centre, a radius, an edge, and a height.

A jittered grid delivers exactly that at O(1) per fragment. For each fragment
the shader walks the `3×3` cell neighbourhood of `world_pos / gravel_cell_px`.
Each cell deterministically holds at most one stone:

```glsl
vec2  cell   = base_cell + vec2(float(dx), float(dy));
float roll   = hash12(cell + vec2(3.7, 11.3));
if (roll > gravel_coverage) continue;          // this cell is empty soil

vec2  jit    = vec2(hash12(cell + vec2(19.1, 5.9)),
                    hash12(cell + vec2(-7.3, 27.7)));
vec2  centre = (cell + 0.25 + jit * 0.5) * gravel_cell_px;
float radius = mix(gravel_size_min, gravel_size_max,
                   hash12(cell + vec2(41.9, -13.1))) * gravel_cell_px;
```

The `3×3` walk is what lets a stone overlap its cell border, so the grid never
shows through as a lattice. Jitter is confined to the middle half of the cell
(`0.25 + jit * 0.5`) so `radius` stays bounded by one cell and the `3×3`
neighbourhood is provably sufficient — a wider jitter would need `5×5`.

Stones are **not circles**: the local offset is rotated by a per-cell angle and
squashed on one axis, giving elongated pebbles at varied headings. The radius
roll is passed through `pow(hash, gravel_size_bias)` so the calibre is skewed
toward small stones — many fine ones with occasional large ones, rather than one
uniform field of identical bumps.

### 2. Volume comes from analytic light, not from a normal map

`NORMAL_MAP` is inert here (`temporary_disable_terrain_normals = true`, and
ADR-0005 keeps `Light2D` a gameplay system, not a ground-relief tool). So the
gravel lights itself into `COLOR`, reusing the pattern the cosmetic shading
block already established at
[`ground_hybrid_material.gdshader:390`](../../../assets/shaders/ground_hybrid_material.gdshader:390).

Each stone is a dome. Inside it:

```glsl
float t2 = dot(dl, dl) / (radius * radius);    // dl = rotated local offset
float h  = sqrt(1.0 - t2);                     // dome height, 1 at centre
vec2  slope = -dl / max(radius * h, 0.001);    // analytic gradient, free
```

The gradient falls out of the same values the coverage test already computed —
no second sample, no finite difference. Shading is then a plain dot product
against the **existing** sun vector:

```glsl
vec2  sun_dir = vec2(cos(radians(ground_sun_angle_deg)),
                     sin(radians(ground_sun_angle_deg)));
float lambert = dot(normalize(slope), -sun_dir);
float lit     = 1.0 + lambert * gravel_relief_strength;
```

Only the nearest/highest stone wins (`if (h > height)`), never a sum — stones
are opaque and must not add up into bright blobs where they overlap.

### 3. The contact shadow must agree with every baked asset

Iteration 2 of the stone-scatter spec had to re-bake all ten rocks because two
sun directions in one frame is *"a visible defect, not a nuance"*. Gravel is
bound by the same rule: its contact shadow is the same stone silhouette pushed
along `-sun_dir` by `gravel_shadow_offset_px`, tested in the same cell walk, and
applied **only where no stone covers the fragment** — otherwise a stone would
render its neighbour's shadow on top of itself.

There is no second lighting curve, no second sun angle, and no new light
uniform: the ground material already receives the sun model from
`WorldVisualLightingProfile`.

### 4. Gravel lives on open soil and paths — resolved

Owner decision (2026-07-31): gravel appears **only** on open ground and along
paths, and **not under the mountain**.

Open ground and paths are read from terms the shader already has, one line
after the scree block:

```glsl
float gravel_open = 1.0 - smoothstep(gravel_grass_start, gravel_grass_end,
                                     grass_density_visual);
float gravel_path = (1.0 - path_open) * gravel_path_amount;
float gravel_band = max(gravel_open, gravel_path);
gravel_band *= 1.0 - rock_region_visual * gravel_rock_suppress;
```

`grass_density_visual` (not `grass_density`) is deliberate: it carries the
ragged ecotone mottling from Iteration 3, so the gravel edge interfingers with
the visible grass edge instead of following the smoother placement field. This
is a **read** of a visual value; nothing here writes back into the density
field, which is what keeps this spec out of the Field-Mirror Law.

The `rock_region_visual` suppression keeps gravel off exposed rocky patches,
where it would only duplicate the rock texture's own grain.

### 5. "Not under the mountain" needs no new mechanism — resolved

This was checked before proposing anything, because the obvious implementation
(feed the chunk's mountain halo mask into the ground shader) would introduce
per-chunk state into a shader whose header states *"there is NO per-chunk state
here, so chunk seams cannot exist"*. That is not an acceptable trade.

It is also unnecessary. There are three distinct "under the mountain" cases:

| case | what already happens | gravel work needed |
|---|---|---|
| under the roof / wall | mountain overlays draw **above** the ground material and fully cover it | none — gravel is invisible by construction |
| excavated cavities | [`mountain_cavity_skylight_field.gdshader`](../../../assets/shaders/mountain_cavity_skylight_field.gdshader) darkens the cavity floor to `deep_cave_color` at `deep_darkness_opacity = 1.0` | none — gravel darkens with the rest of the floor, exactly as the existing cosmetic shading does |
| foothill apron | `mountain_foothill_overlay` draws above the ground | none; `gravel_rock_suppress` additionally thins gravel there |

So the requirement is met by the existing layer order plus one authored knob.
The cavity case is nevertheless an explicit acceptance item: gravel's sun-lit
face must not punch through the cavity darkening at the authored
`deep_cave_ambient_floor = 0.12`.

### 6. Zoom LOD is mandatory, not polish

A `5..14 px` feature is below one screen pixel when the camera pulls back, and
an unfaded procedural field at that scale is a shimmering noise carpet. Repeat
textures in this shader solve it with mipmaps; a procedural field has none, so
it fades explicitly:

```glsl
float world_px = fwidth(world_pos.x) + fwidth(world_pos.y);
float lod = 1.0 - smoothstep(gravel_lod_fade_start_px, gravel_lod_fade_end_px,
                             world_px);
```

The silhouette edge is antialiased against the same `world_px`, so stone rims
stay smooth instead of stair-stepping at close zoom.

`gravel_band * lod` also gates the whole cell walk with an early-out, so dense
grass, far zoom, and the mountain interior pay close to nothing.

### 7. Placement order in the fragment

Gravel is inserted immediately after the transition-scree block
([`:358`](../../../assets/shaders/ground_hybrid_material.gdshader:358)) and
**before** `macro_drift` and the cosmetic shading block. Consequence: the macro
tone drift and the large-scale AO modulate gravel together with the soil under
it, so stones stay inside the biome's tonal masses instead of floating as a
separately-lit layer.

### 8. Relationship to the other two stone systems

| layer | scale | mechanism | role after this spec |
|---|---|---|---|
| shader scree | sub-object grain | `fbm2` threshold into colour | stays as grain; `scree_open_amount` retuned down if the probe shows mud |
| **gravel relief** | **`5..14 px`** | **this spec** | **the mass — volume across all open soil** |
| `object_kind == 7` | `7..26 px` baked assets | `MultiMeshInstance2D` | unchanged: sparse readable accents on the ecotone contour |

Mass belongs in the shader and accents belong in instances. The instance path
carries 21 stones per chunk on average against a 121-chunk readiness gate of
`23960 ms`. A `1024×1024 px` chunk at `gravel_cell_px = 22` holds about `2170`
cells, so at `gravel_coverage = 0.55` gravel is roughly **`1200` stones per
chunk** — a `57×` increase on a path whose current cost is already the measured
bottleneck. That path is therefore explicitly rejected for the mass.

## Data Model

New authored `sampling_params` in
[`plains_ground_material_set.tres`](../../../data/terrain/material_sets/plains_ground_material_set.tres),
mirrored one-to-one as shader uniforms. Values below are the Iteration 1 landing
values, calibrated on the render probe; the visual runtime lab owns further
tuning.

| key | value | meaning |
|---|---|---|
| `gravel_cell_px` | `30.0` | jittered-grid cell size; sets stone spacing |
| `gravel_coverage` | `0.55` | fraction of cells that hold a stone |
| `gravel_size_min` | `0.20` | min stone radius as a fraction of the cell |
| `gravel_size_max` | `0.54` | max stone radius as a fraction of the cell |
| `gravel_size_bias` | `1.4` | `>1` skews the calibre toward small stones |
| `gravel_elongation` | `1.6` | max axis squash, so stones are not discs |
| `gravel_ambient_strength` | `0.22` | night-surviving dome form (rim darker than crown) |
| `gravel_relief_strength` | `0.55` | day-only sun-directional light/dark across the dome |
| `gravel_shadow_strength` | `0.45` | contact shadow depth |
| `gravel_shadow_offset_px` | `2.2` | contact shadow offset along `-sun_dir` |
| `gravel_tint` | `0.35` | how far stone colour departs from the soil below |
| `gravel_grass_start` | `0.06` | `grass_density_visual` where gravel starts fading |
| `gravel_grass_end` | `0.26` | `grass_density_visual` where gravel is gone |
| `gravel_path_amount` | `1.0` | gravel strength inside path trails |
| `gravel_rock_suppress` | `0.80` | suppression on `rock_region_visual` |
| `gravel_lod_fade_start_px` | `5.0` | world px per screen px where the fade begins |
| `gravel_lod_fade_end_px` | `11.0` | where gravel is fully faded out |

Two of these were added or moved during Iteration 1, both for reasons the probe
made visible:

- **`gravel_size_bias`** was not in the original table. With a flat radius roll
  every stone read as the same bump and the field looked like a uniform pebbled
  skin. Skewing the calibre toward small stones gives many fine ones with
  occasional large ones, which is what gravel actually looks like, and it is
  also the strongest mitigation against reading the cell grid.
- **`gravel_ambient_strength`** implements the hybrid model this project already
  uses for ground shading: the dome's ambient form survives the night while the
  directional term fades with `ground_sun_day`. Without it stones would flatten
  into painted discs after dusk.

The LOD window moved from `1.6..4.0` to `5.0..11.0` because the first values
killed gravel at zoom `0.45`, a perfectly ordinary play zoom. The relationship
is `world_px ≈ 2 / zoom`, so `5.0..11.0` keeps gravel to zoom `≈0.4` and fades
it out by `≈0.18`, where a stone is under three screen pixels.

Stone albedo reuses the already-bound `rock_top_albedo_tex` sampled in the
stone's local frame, tinted per stone by a cell hash. **No new texture asset,
no new atlas, no new preload.**

## Runtime Architecture

- **Shader (GPU):** one `3×3` cell walk plus the shading math, gated by
  `gravel_band * lod`.
- **CPU:** none. `world_tile_set_factory.gd` already copies every
  `sampling_params` key onto the material by name, so no GDScript, no packed
  param slot, and no native change is involved.
- **Authoring:** the visual runtime lab does **not** derive its sliders from
  `sampling_params` — this spec originally claimed it did, and that was wrong.
  Its controls are an authored list in `CONTROL_GROUPS`
  ([`visual_runtime_lab_panel.gd`](../../../scenes/dev/visual_runtime_lab_panel.gd))
  plus matching `get_value` / `set_value` arms in
  [`visual_runtime_lab_authoring.gd`](../../../scenes/dev/visual_runtime_lab_authoring.gd)
  and one localization key per control. Eight gravel controls were declared in a
  `UI_VISUAL_LAB_GROUP_GRAVEL` group: coverage, cell size, both calibres, relief
  strength, contact-shadow strength, tint, and the LOD fade end. The remaining
  nine knobs stay `.tres`-only.
- **Lab zoom caveat:** the lab opens at the maximum play zoom-out
  (`zoom_min ≈ 0.20`), where `world_px ≈ 10` and the default LOD window has
  already faded gravel to near nothing. Gravel must be judged zoomed in
  (mouse wheel, the production `PlayerCamera` is live there), or by raising
  `gravel_lod_fade_end_px` — which is exactly why that knob is one of the eight.
- **No new public API, command, event, packet field, or extension seam.**

## Performance Class

- Runtime class: GPU fragment work inside an already-bound material. No `boot`,
  `background`, or `interactive` CPU work is added, so ADR-0001 budgets are
  untouched.
- **Estimated fragment cost.** The cell walk is at most 9 iterations × ~4
  `hash12` calls ≈ 36 `hash12`. For comparison, one `fbm2` is 2 ×
  `gradient_noise` × 4 × `random_gradient` × 2 `hash12` ≈ 16 `hash12`, and the
  fragment already evaluates more than ten `fbm2`/`fbm3` calls. Gravel is
  therefore on the order of **two existing fbm calls**, before the early-out.
- **After the early-out** the cost is near zero over dense grass, over the
  mountain interior, and at far zoom — that is, over most of a typical frame.
- The `gravel_coverage` `continue` skips the expensive part of empty cells.

**Measured** by [`ground_gravel_relief_probe.gd`](../../../tools/ground_gravel_relief_probe.gd)
on 2026-07-31, one machine, one session, vsync disabled, `1280×720`, 240 frames
per sample. `off` is the same build with `gravel_coverage = 0.0`, so it still
walks the cells and the delta isolates the stones themselves:

| view | zoom | off (ms) | on (ms) | delta |
|---|---|---|---|---|
| closeup | `2.20` | `12.133` | `13.501` | `+1.368` (`+11.3%`) |
| play | `1.00` | `13.640` | `15.327` | `+1.687` (`+12.4%`) |
| wide | `0.45` | `18.545` | `20.132` | `+1.587` (`+8.6%`) |
| far | `0.18` | `25.714` | `25.507` | `−0.207` (`−0.8%`, noise) |
| cavity | `2.20` | `13.452` | `14.859` | `+1.407` (`+10.5%`) |

Two readings matter. First, gravel costs about `1.6 ms` on a play-zoom frame —
more than the "two fbm calls" the static estimate suggested, and worth knowing
before anyone adds a second cell field. Second, at zoom `0.18` the delta is
inside measurement noise, which is the LOD early-out doing exactly what it was
written for: gravel pays nothing where it is not visible.

## Save / Load Contract

No change. Gravel is derived per fragment and never persisted.

## Event and Command Contract Impact

None. No commands, no EventBus signals, no packet schema change.

## Field-Mirror Law compliance

[`plains_ground_field_composition.md`](plains_ground_field_composition.md)
requires that any change to the density formula be mirrored across the GLSL
shader, `grass_scatter::sample_fields`, and `world_core` tree gating.

This spec **reads** `grass_density_visual`, `path_open`, and
`rock_region_visual` and **writes** only `top_color`. It does not participate in
the mirror, and `grass_scatter.cpp` / `world_core.cpp` must remain byte-identical
across the change. That is an acceptance item, not an assumption.

## Extension Points

- Other biome ground materials reuse the same uniforms with different values;
  a stony biome raises `gravel_coverage`, a silty one drops it to zero.
- The cell walk is reusable for future micro-decor (shells, bone chips) by
  swapping the albedo source, without touching the field formula.

## Acceptance Criteria

Visual criteria are `manual human verification` per the project's visual-proof
rule; they are verified through a render probe with before/after panels.
Artifacts live in `artifacts/gravel_relief/{on,off}/`.

- [x] The shader exposes every `gravel_*` uniform from the Data Model table and
      `plains_ground_material_set.tres` carries a matching `sampling_params`
      entry for each, with **no key present on only one side** — **passed**:
      both key sets extracted and `diff`ed, 17 keys, identical.
- [x] Gravel reads only `grass_density_visual`, `path_open`, and
      `rock_region_visual`, and writes only `top_color`; `grass_density` is not
      assigned after the gravel block — **passed** (final shader read).
- [x] `gdextension/src/grass_scatter.cpp`, `gdextension/src/world_core.cpp`, and
      `WORLD_VERSION` are unchanged — **passed**: `git diff --stat -- gdextension/ core/`
      returns empty; `WORLD_VERSION` stays `65`.
- [x] The gravel block sits after the scree block and before `macro_drift`
      — **passed** (line order in the final shader).
- [x] Render probe: open soil and paths carry dense readable gravel with a lit
      side, a dark side, and a contact shadow — **rendered**; the on/off pair at
      `closeup` and `play` shows painted soil becoming littered soil.
      Owner's read still pending.
- [x] Render probe: gravel thins out through the ecotone and is absent under
      dense grass — **rendered** (`play.png`: grass mass on the left carries no
      gravel, open soil on the right is fully littered). Owner's read pending.
- [ ] Render probe: gravel light and contact shadows point the same screen
      direction as tree and `object_kind == 7` rock shadows — one sun in frame
      (manual human verification — the probe frames contain trees, stones and
      gravel together, so the comparison is available in a single image).
- [x] Zoom sweep: pulling the camera back fades gravel smoothly with no
      shimmer, crawl, or moiré, and no visible `gravel_cell_px` lattice at any
      zoom — **rendered** across `2.20 / 1.00 / 0.45 / 0.18`; gravel is fully
      gone by `0.18` and no lattice is visible at any step. Static frames cannot
      prove absence of crawl in motion; that part stays with the owner.
- [ ] Mountain probe: inside an excavated cavity no sun-lit gravel face punches
      through the skylight darkening; under the roof and wall gravel is not
      visible at all — **partially covered**: the roof/wall case is confirmed in
      every probe frame (gravel never appears on mountain surface), but the
      automated dig excavates only **one** sample per run
      (`debug_dig_target_once` does not re-target), which is too small a cavity
      to judge. Needs a manual dig session in
      `mountain_runtime_dig_dev_scene`.
- [x] Chunk-boundary probe: no seam in gravel density or phase across chunk
      borders — **passed by construction and by frame**: the field reads only
      `world_pos`, and the `wide`/`far` frames span several chunks with no
      visible discontinuity.
- [x] GPU frame-time comparison before/after on the same probe view, recorded
      as numbers — **passed**: see the table in Performance Class.
- [x] `scree_open_amount` is either kept with evidence that gravel and scree do
      not mud together, or retuned down — **kept at `0.25`**: on the `closeup`
      on/off pair the soil gains discrete stones without losing its underlying
      grain, and no muddying is visible. Re-open if the owner's read disagrees.

## Risks

- **Lattice read-through.** A jittered grid can still betray its cell period if
  `gravel_size_max` approaches the cell and jitter is small. Mitigation: jitter
  across the middle half of the cell, per-cell radius and rotation variance, and
  `gravel_coverage < 1` leaving empty cells. The probe is the gate, not the
  parameter table.
- **Silent knob drop.** `set_shader_parameter` ignores a name that no uniform
  matches, so a typo in `sampling_params` fails invisibly — a hidden fallback,
  which the project forbids. Mitigation: the key-set diff is the first
  acceptance item.
- **Double litter with scree** producing mud, the same failure the stone-scatter
  spec warns about. Mitigation: probe first, retune `scree_open_amount` second.
- **Shimmer at far zoom** if the LOD fade window is mistuned. Mitigation: the
  zoom sweep is an explicit acceptance item, not a spot check.
- **Fragment cost on low-end GPUs.** Mitigation: the early-out, and a measured
  before/after rather than a claim.
- **Two suns** if the gravel shading derives its own angle. Mitigation: the spec
  forbids any new light uniform; the existing `ground_sun_angle_deg` is the only
  source.

## Resolved Decisions

- **Coverage → open soil and paths only** (owner, 2026-07-31). Gravel under
  dense grass would be invisible while still being paid for per fragment.
- **Not under the mountain → no new mechanism** (see Design Intent 5). Feeding
  a chunk mountain mask into the ground shader is rejected because it
  reintroduces per-chunk state into a deliberately stateless shader.
- **Per-chunk gravel mask texture → rejected.** A `1024×1024 px` chunk mask is
  `1 MiB` per chunk even at R8 (`~121 MiB` for a loaded ring), regenerated on
  every streaming step, and it reintroduces both chunk seams and a
  chunk-period wallpaper grid at far zoom.
- **`MultiMeshInstance2D` gravel → rejected for the mass** (see Design
  Intent 8), retained for accents through the existing `object_kind == 7`.
- **Cell field over `fbm` → required.** `fbm` cannot produce a stone edge, which
  is the entire reason the existing scree fails to read as stones.

## Open Questions

- Stones are smooth domes. Real gravel is angular, and faceting the silhouette
  would read as crushed rock rather than pebbles. Deliberately out of Iteration
  1: it costs extra ALU per cell on a term already measured at `+1.6 ms`.
- Whether a second, coarser cell field on top would help, now that the measured
  cost of one field is known. It roughly doubles the cell walk.
- Whether `scree` survives at all once gravel lands, or is retired as redundant
  in a follow-up. Kept for now with evidence, not by default.
- Whether the gravel tint should follow `soil_mix` (warm dirt vs cold gravel)
  rather than being a single authored constant.
- Whether `+1.6 ms` on a play-zoom frame is acceptable on the target low-end
  GPU. Measured only on the development machine.

## Implementation Iterations

### Iteration 1 — Gravel relief (single iteration)

**Status: landed 2026-07-31.** Touched exactly the two planned files —
`assets/shaders/ground_hybrid_material.gdshader` and
`data/terrain/material_sets/plains_ground_material_set.tres` — plus a new probe
`tools/ground_gravel_relief_probe.gd`. No forbidden file was needed.

Three things the implementation had to resolve beyond the plan:

- **The probe pattern in this repo needed fixing before it could prove
  anything.** A first probe modelled on `tools/ground_rock_islet_probe.gd`
  captured the loading screen instead of the world: that pattern gates on
  `_streamer._requested_chunks.is_empty()`, which is trivially true on the first
  tick, before streaming has started. The landed probe waits for the dev scene's
  own readiness plus `get_initial_loading_state().presented`, and additionally
  fails loudly on a near-black frame rather than saving one. See Out-of-scope
  note in the closure report — `ground_rock_islet_probe.gd` still carries the
  original gate.
- **The first LOD window was far too aggressive** (`1.6..4.0`), erasing gravel
  at zoom `0.45`. The corrected window and the `world_px ≈ 2 / zoom` relation
  are recorded in Data Model.
- **A flat calibre roll read as a uniform bumpy skin,** which added
  `gravel_size_bias` and widened the radius range.

Original internal ordering, followed as written:

1. Cell walk + silhouette + antialiased edge, flat colour only. Probe the
   distribution: the gate here is "no lattice", before any lighting exists.
2. Dome height, analytic gradient, sun-directional shading. Probe volume.
3. Contact shadow. Probe against tree/rock shadows in the same frame.
4. Coverage mask (`grass_density_visual`, `path_open`, `rock_region_visual`)
   and the early-out.
5. LOD fade. Probe the zoom sweep.
6. Mountain cavity probe.
7. Retune `scree_open_amount` if needed; record the GPU before/after.

**Forbidden files for this iteration:** `gdextension/src/**`,
`core/systems/world/world_streamer.gd`, `core/systems/world/chunk_view.gd`,
anything under `data/world_objects/`, and `WORLD_VERSION`. If the
implementation finds it needs any of them, the design is wrong and the work
stops for a spec revision.

## Required Updates

All completed with the Iteration 1 landing on 2026-07-31:

- [x] [`terrain_hybrid_presentation.md`](terrain_hybrid_presentation.md) —
      "Runtime 2D Terrain Ground Composition" now records the gravel relief term
      and its owner beside the macro-mass/path bullet.
- [x] [`plains_ground_field_composition.md`](plains_ground_field_composition.md) —
      Iteration 2 (scree) records that gravel owns the object-scale litter and
      that `scree_open_amount` stays at `0.25` with probe evidence.
- [x] [`plains_bare_ground_stone_scatter.md`](plains_bare_ground_stone_scatter.md) —
      "Relationship to shader scree" is now a three-layer table
      (scree grain / gravel mass / instance accents).
- [x] `docs/02_system_specs/README.md` — index entry present.
- [x] `packet_schemas.md`, `system_api.md`, `commands.md`, `event_contracts.md` —
      no change required: `grep -c gravel` returns `0` in each, and this spec
      adds no packet field, API, command, or event.
