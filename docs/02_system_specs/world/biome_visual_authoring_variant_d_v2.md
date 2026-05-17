---
title: Biome Visual Authoring - Variant D v2 Godot-Native Terrain Workbench
doc_type: system_spec
status: approved
owner: engineering+art
source_of_truth: true
version: 1.1
last_updated: 2026-05-17
supersedes:
  - ./biome_visual_authoring_variant_d.md
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ./biome_visual_authoring_variant_d.md
  - ./terrain_hybrid_presentation.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - ../meta/modding_extension_contracts.md
---

# Biome Visual Authoring - Variant D v2 Godot-Native Terrain Workbench

## 1. Статус документа (Document Status)

Этот документ намеренно создан как **отдельный Variant D v2**, а не как
переписывание существующего `Biome Visual Authoring - Variant D`.

`biome_visual_authoring_variant_d.md` теперь является superseded
историческим/transition документом. V2 фиксирует более строгий и более полный
целевой путь:
**портировать и улучшать старый terrain generator внутри Godot**, чтобы
editor preview и runtime game view использовали один source of truth, один
solver и один rendering contract.

Статус V2 утверждён пользователем 2026-05-17. IT9 decision: Variant D v2 is
the canonical terrain visual path для новых задач по переносу, улучшению и
runtime/editor применению terrain generator. V1 остаётся историческим reference
для уже принятых решений v1, но не должен расширяться как активный целевой путь.

## 2. Короткая формулировка решения (Decision Summary)

Variant D v2 - это не rollback к старому PNG atlas и не сохранение текущего
упрощённого Godot-прототипа.

Variant D v2 - это **Godot-native terrain workbench**:

- старый `tools/rimworld-autotile-lab/desktop_app` используется как
  reference donor, test oracle и список доказанных алгоритмов;
- финальный authored truth живёт в Godot `.tres` resources;
- тяжёлый contour/SDF/height/normal solve живёт в native GDExtension;
- editor tool и runtime `ChunkView` потребляют один и тот же
  `TerrainVisualRecipe`;
- shader получает уже решённые поля: mask coverage, zone ids, height, normal,
  material projection coordinates;
- gameplay terrain truth остаётся в world base + runtime diff, а визуальные
  packets/caches остаются derived state.

Главная цель: **одна истина и один рендер внутри игры**, но без отказа от
качества старого генератора.

## 3. Почему нужен V2 (Why V2 Exists)

Существующий Variant D v1 правильно зафиксировал идею "один Godot shader +
`.tres` параметры", но этого оказалось недостаточно для реального переноса
старого generator.

Проблема не в том, что старый generator нужно вернуть как внешний tool.
Проблема в том, что текущий Godot-путь не портировал важные части старого
алгоритма:

- нет global signed-distance field (SDF) для непрерывного контура;
- нет полноценного top/edge/face/back zone solve;
- нет height field как основы для normal response;
- нет contour tangent/depth material projection для фасада;
- нет нормального procedural material stack;
- нет shape supersampling для сглаживания краёв;
- нет dirty patch model для runtime mutation;
- shader пытается угадывать геометрию локальными эвристиками вместо того,
  чтобы получать solved visual fields.

Из-за этого новый generator визуально даёт "ломаную пластиковую плиту", а
старый reference даёт цельный terrain mass: фасад, губу (rim), высоту,
органический край, материал и нормали.

V2 фиксирует: **shader не должен изобретать topology**. Shader должен
рендерить packet, который был построен тем же native solver'ом, что использует
editor workbench.

## 4. Непереговорные цели (Non-Negotiable Goals)

1. **Не возвращать старый runtime.** Старый desktop app не становится runtime
   dependency и не остаётся активной второй системой авторинга.
2. **Не откатывать игру на baked PNG atlas как source of truth.** PNG может
   быть reference artifact или exported test image, но не canonical visual
   source.
3. **Портировать алгоритм, а не картинку.** В Godot переезжают SDF, zones,
   height, normals, material projection и procedural material semantics.
4. **Editor и runtime используют один solver.** Нельзя иметь "tool renderer"
   и "game renderer", которые расходятся.
5. **Rock first, architecture expandable.** Первая рабочая цель - mountain /
   rock. Но schema не должна закрывать путь к ground, lake bank, snow, ash,
   dirt и будущим biome surfaces.
6. **Frame budget важнее удобства.** Full chunk visual solve не может
   запускаться синхронно на каждую mining/mutation операцию.
7. **Visual packets are derived state.** Save/load хранит gameplay diff, а не
   mask/height/normal/outline cache.
8. **Gameplay light authority не читает pixels.** Normal/height могут помогать
   render lighting, но visibility/safety остаются за gameplay authority.

## 5. Что является source of truth (Authority Model)

### 5.1 Gameplay truth

Gameplay truth:

- deterministic world base;
- runtime diff from player/world mutation;
- `terrain_id`, walkability, blocking, excavation state;
- biome identity and generated world channels.

Owner: world/runtime systems, согласно ADR-0003.

Variant D v2 не меняет этот truth и не добавляет visual data в save payload.

### 5.2 Visual authoring truth

Visual authoring truth:

- `TerrainVisualRecipe` `.tres`;
- `TerrainVisualMaterialSlot` subresources;
- optional image textures referenced by the recipe;
- procedural material parameters stored in the recipe.

Owner: art/design via Godot editor.

Runtime reads these resources as read-only content.

### 5.3 Derived visual state

Derived visual state:

- `TerrainVisualPacket`;
- per-chunk/per-patch SDF samples;
- mask coverage textures;
- zone id textures;
- height textures;
- normal textures;
- material projection coordinate textures;
- outline/contact polylines;
- cached `ImageTexture` / `Texture2D` objects.

Owner: terrain visual presentation pipeline.

These values are rebuildable from gameplay truth + `TerrainVisualRecipe`.
They must not be persisted as authoritative save state.

## 6. Runtime work class (Runtime Work Classification)

### 6.1 Boot

Boot work:

- load `TerrainVisualRecipe` resources;
- validate schema version and required material slots;
- preload referenced textures;
- register native solver API availability;
- initialize reusable visual packet buffers if needed.

Boot work may be synchronous behind loading screen. It must not be confused
with ordinary runtime mutation.

### 6.2 Background

Background work:

- solve visual packets for newly loaded chunks;
- solve larger dirty regions after bulk terrain changes;
- build or refresh chunk-level texture data from native packet output;
- perform golden/reference image generation in tests/dev tools.

Required shape:

```text
terrain/base+diff available
  -> visual dirty mark
  -> queued background solve
  -> bounded native compute
  -> bounded main-thread apply
```

The job must be able to split work by chunk, subchunk, edge band or dirty
rect. A single monolithic "solve all loaded mountains now" path is forbidden.

### 6.3 Interactive

Interactive work:

- mutate the authoritative tile/diff;
- mark one visual dirty patch;
- optionally apply a tiny immediate local result if it is proven bounded;
- enqueue background visual solve for anything bigger.

For mining one mountain tile, the dirty unit is not "the whole chunk". The
dirty unit is:

- changed tile;
- one-tile topology halo around it;
- visual radius needed by SDF/material projection;
- clamped `dirty_rect_px` for texture update.

If V2 cannot prove the solve is bounded, it must queue background work instead
of doing full synchronous refresh.

Target performance contract:

- interactive mutation path: under 2 ms;
- no full `ChunkView` rebuild;
- no mass `queue_free()`;
- no per-cell Node creation;
- no GDScript loop over all pixels or all chunk cells.

## 7. Target scale (Scale Scenario)

V2 must be designed against at least this target:

- 9 loaded chunks visible/near-active;
- each chunk can contain mountain edges;
- chunk size is currently 16x16 tiles but the design must not depend on only
  16x16 forever;
- tile presentation size may be 64 px now, while old generator defaults and
  authoring references include 128 px;
- one frame can receive a mining mutation while background chunk visual solves
  are still queued;
- future ground/water surfaces reuse the same pipeline rather than adding
  separate bespoke loops.

The acceptable scale path is:

- native compute for SDF/height/zones;
- packed arrays/textures for apply;
- local dirty patch updates;
- background jobs for chunk or large region rebuilds;
- optional C++ buffer reuse/native cache for heavy repeated solve state.

## 8. Existing generator as reference donor (Reference Donor)

The old generator path:

```text
tools/rimworld-autotile-lab/desktop_app
```

is a reference donor, not a runtime dependency.

Important proven features to port conceptually:

- full 16-case marching-squares geometry;
- global signed-distance field for live map preview;
- `SurfaceZone`: top, edge, face, back, empty;
- height sampling based on SDF and facade depth;
- 3x3 height blur plus Sobel-style normal encoding;
- shape supersampling for curved mask/height/normal edges;
- contour controls:
  - `corner_round_px`;
  - `diagonal_smooth_px`;
  - `outer_corner_radius`;
  - `inner_corner_radius`;
  - `contour_warp_px`;
  - `geometry_variance`;
- facade controls:
  - `south_height`;
  - `north_height`;
  - `side_height`;
  - `face_power`;
  - `back_drop`;
- edge/rim controls:
  - `rim_width`;
  - `edge_debris`;
  - `edge_color_strength`;
  - `mountain_outline_enabled`;
  - `mountain_outline_width`;
- material model:
  - procedural, image file, flat color;
  - top/face/base material slots;
  - scale, contrast, crack amount, wear, grain, edge darkening, seed,
    color A, color B, highlight;
- material projection:
  - map-space projection for top/base;
  - contour tangent/depth projection for face/back/edge;
- dynamic-lighting-ready normal output;
- unlit albedo by default, with optional lit preview only for inspection.

Important reference artifacts:

```text
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/
```

These may be used for visual regression and parity checks, but they are not
runtime assets and not canonical source of truth.

## 9. What V2 explicitly fixes vs current Godot prototype

V2 rejects the following implementation shape:

- one rectangular `Polygon2D` pretending to be mountain mass;
- shader deciding face/back from only above/below neighbour checks;
- no SDF field;
- no solved height;
- no normal map derived from height;
- no material projection field;
- `ChunkView` rebuilding all rock visuals for one tile update;
- default biome visual resource used for every chunk instead of resolved biome;
- tests expecting old node names while preview scene already changed;
- editor preview and runtime using different codepaths.

The corrected shape is:

- native solver reads terrain mask + recipe;
- native solver emits explicit visual packet;
- shader renders packet;
- editor workbench and runtime call the same native solver;
- dirty patch apply updates only local visual textures/nodes.

## 10. High-level architecture (Architecture)

```text
Authored content:
  data/terrain_visual/recipes/*.tres
  data/terrain_visual/materials/*.tres
  optional referenced textures

Editor:
  addons/biome_visual_authoring_v2/
    -> mask editor / test map editor
    -> recipe inspector binding
    -> preview modes
    -> calls TerrainVisualSolver

Runtime:
  world base + runtime diff
    -> chunk terrain mask
    -> TerrainVisualSolver
    -> TerrainVisualPacket
    -> TerrainVisualPresenter
    -> shader/material/canvas draw

Tests:
  fixtures masks + recipes
    -> TerrainVisualSolver
    -> golden packet assertions
    -> screenshot/reference comparison
```

Core invariant:

```text
same recipe + same terrain mask + same world origin + same seed
  = same visual packet
  = same rendered result, within documented tolerance
```

## 11. Data model: TerrainVisualRecipe

Working name:

```gdscript
class_name TerrainVisualRecipe
extends Resource
```

Final class name can change during implementation, but the responsibilities
must stay stable.

### 11.1 Identity fields

Required fields:

- `id: StringName`
- `schema_version: int`
- `display_name_key: StringName`
- `surface_kind: StringName`
- `solver_family_id: StringName`
- `default_seed: int`
- `tile_size_px: int`
- `variant_count: int`

`surface_kind` examples:

- `rock`
- `ground`
- `lake_bank`
- `snow`
- `ash`

V2 implementation is rock-first. Other kinds are schema-compatible future
consumers, not required in Iteration 1.

### 11.2 Shape fields

Required rock fields:

- `south_height_px: float`
- `north_height_px: float`
- `side_height_px: float`
- `face_power: float`
- `back_drop: float`
- `crown_bevel_px: float`
- `outer_corner_radius_px: float`
- `inner_corner_radius_px: float`
- `corner_round_px: float`
- `diagonal_smooth_px: float`
- `contour_relax: float`
- `contour_warp_px: float`
- `corner_variation: float`
- `geometry_variance: float`
- `shape_supersampling: int`

Meaning:

- `south_height_px` controls front/south facade depth;
- `north_height_px` controls visible north/back projection;
- `side_height_px` controls east/west facade depth;
- `face_power` controls non-linear falloff on the face;
- `back_drop` controls back-side height loss;
- `crown_bevel_px` softens top crown near exposed edge;
- corner/diagonal controls shape the SDF contour;
- `contour_warp_px` and `geometry_variance` add deterministic organic noise;
- `shape_supersampling` anti-aliases solved coverage.

### 11.3 Edge/rim fields

Required fields:

- `rim_width_px: float`
- `edge_debris: float`
- `edge_color_strength: float`
- `contact_outline_enabled: bool`
- `contact_outline_width_px: float`
- `contact_outline_color: Color`

Meaning:

- rim is a visible lip where top and face overlap;
- edge debris chips height/normal/albedo inside the edge band;
- contact outline is optional bottom/contact grounding, not a gameplay
  collision edge.

### 11.4 Normal/lighting fields

Required fields:

- `normal_strength: float`
- `normal_detail_strength: float`
- `height_to_normal_blur_radius_px: float`
- `bake_height_shading_for_reference: bool`

Rules:

- runtime albedo should remain unlit by default;
- height/normal are render inputs;
- gameplay light/visibility authority does not read normal/albedo pixels.

### 11.5 Material slots

Required slots for rock:

- `top_material: TerrainVisualMaterialSlot`
- `face_material: TerrainVisualMaterialSlot`
- `base_material: TerrainVisualMaterialSlot`
- `back_material: TerrainVisualMaterialSlot`
- `edge_material_override: TerrainVisualMaterialSlot | null`

The old generator had top/face/base. V2 adds explicit `back_material` because
runtime packets distinguish top/edge/face/back/empty.

## 12. Data model: TerrainVisualMaterialSlot

Working name:

```gdscript
class_name TerrainVisualMaterialSlot
extends Resource
```

Required fields:

- `source: StringName`
- `procedural_kind: StringName`
- `image_albedo: Texture2D`
- `image_normal: Texture2D`
- `image_modulation: Texture2D`
- `flat_color: Color`
- `color_a: Color`
- `color_b: Color`
- `highlight_color: Color`
- `scale: float`
- `contrast: float`
- `crack_amount: float`
- `wear: float`
- `grain: float`
- `edge_darkening: float`
- `seed: int`
- `normal_mix: float`
- `modulation_strength: float`

Allowed `source` values:

- `procedural`
- `image`
- `flat`

Initial `procedural_kind` values should be ported from the old generator only
as needed for rock-first acceptance:

- `stratified_rock`
- `rough_stone`
- `cracked_dry_earth`
- `packed_dirt`

Additional kinds from the old generator are allowed later, but must land as
data-driven material kinds, not hardcoded shader branches per biome.

## 13. Runtime packet: TerrainVisualPacket

Working name:

```text
TerrainVisualPacket
```

It can be represented as a `Resource`, a `Dictionary` with strict keys, or a
GDExtension object. The implementation iteration must choose one and update
`packet_schemas.md` if it becomes a public packet boundary.

Required logical fields:

- `schema_version: int`
- `recipe_id: StringName`
- `surface_kind: StringName`
- `world_origin_tile: Vector2i`
- `chunk_coord: Vector2i`
- `dirty_rect_tiles: Rect2i`
- `dirty_rect_px: Rect2i`
- `tile_size_px: int`
- `pixel_width: int`
- `pixel_height: int`
- `zone_ids: PackedByteArray`
- `coverage_top: PackedByteArray`
- `coverage_edge: PackedByteArray`
- `coverage_face: PackedByteArray`
- `coverage_back: PackedByteArray`
- `height_q16: PackedByteArray`
- `normal_rgba8: PackedByteArray`
- `material_u_q16: PackedByteArray`
- `material_v_q16: PackedByteArray`
- `outline_polylines: Array[PackedVector2Array]`
- `debug_counters: Dictionary`

Rules:

- packed arrays are preferred over per-pixel dictionaries;
- `zone_ids` classify top/edge/face/back/empty;
- coverage arrays allow anti-aliased blending;
- height and normal are derived from the same solved field;
- material coordinates are solved by topology/SDF, not guessed in shader;
- `outline_polylines` are optional render/contact helpers, not save truth.

## 14. Native solver contract (TerrainVisualSolver)

Working name:

```text
TerrainVisualSolver
```

The solver must be deterministic and mostly stateless.

### 14.1 Responsibilities

The solver owns:

- terrain mask expansion with halo;
- global or patch-local SDF compute;
- contour gradient sampling;
- zone classification;
- height solve;
- edge/rim solve;
- material projection coordinate solve;
- normal source height field;
- outline/contact polyline extraction;
- debug counters for verification.

The solver does not own:

- gameplay terrain truth;
- save/load state;
- scene tree nodes;
- editor UI;
- biome registry lookup;
- texture loading from disk during hot path.

### 14.2 Proposed API

Exact binding can change, but the public shape should remain close to:

```text
build_chunk_visual_packet(
  terrain_mask,
  mask_width_tiles,
  mask_height_tiles,
  recipe_payload,
  world_origin_tile,
  seed
) -> TerrainVisualPacket

build_patch_visual_packet(
  terrain_mask_with_halo,
  mask_width_tiles,
  mask_height_tiles,
  recipe_payload,
  world_origin_tile,
  dirty_rect_tiles,
  seed
) -> TerrainVisualPacket

build_editor_preview_packet(
  editor_mask,
  mask_width_tiles,
  mask_height_tiles,
  recipe_payload,
  preview_origin_tile,
  seed
) -> TerrainVisualPacket
```

`recipe_payload` should be a packed/native-friendly representation prepared
from `TerrainVisualRecipe`. The solver must not pull values directly from
Godot resources inside deep pixel loops.

### 14.3 Determinism requirements

Same inputs must produce same outputs:

- same mask;
- same recipe schema and values;
- same world origin;
- same seed;
- same solver version.

Floating-point tolerances must be documented in tests if exact byte equality
is not feasible.

## 15. Shader contract (Shader Contract)

The shader is a renderer, not the topology solver.

Shader inputs:

- coverage/mask textures;
- zone texture;
- height texture;
- normal texture;
- material coordinate textures;
- material textures or procedural parameters;
- recipe render parameters.

Shader outputs:

- albedo;
- alpha/coverage;
- normal/light response;
- optional debug visualization modes.

Shader forbidden responsibilities:

- infer mountain topology from neighbour tiles;
- decide top/face/back from local screen-space rules;
- run SDF;
- run marching squares;
- generate dirty patch data;
- decide gameplay visibility/safety.

Required debug modes:

- `albedo`;
- `zone`;
- `coverage`;
- `height`;
- `normal`;
- `material_uv`;
- `lit_preview`.

`lit_preview` is an inspection mode. It must not bake gameplay lighting into
authored albedo.

## 16. Presenter contract (TerrainVisualPresenter)

Working name:

```text
TerrainVisualPresenter
```

The presenter may be a new node/helper or a responsibility inside `ChunkView`
during early implementation, but the ownership must be explicit.

Presenter responsibilities:

- own visual textures for one chunk/surface layer;
- apply full packets on chunk load;
- apply patch packets on local mutation;
- reuse `ImageTexture`/material instances where Godot allows;
- update only `dirty_rect_px` for patch packets;
- keep debug overlay optional;
- free visual resources on chunk unload.

Presenter forbidden responsibilities:

- mutate gameplay terrain;
- choose biome by hidden fallback;
- run heavy per-pixel GDScript loops;
- create one node per terrain pixel;
- rebuild all visual children for one tile mutation;
- serialize packet data into save.

## 17. Editor workbench contract (Godot-Native Workbench)

Working directory target:

```text
addons/biome_visual_authoring_v2/
```

The existing `addons/biome_visual_authoring/` can remain for Variant D v1 or
transitional work. V2 should either use a separate addon directory or an
explicit `v2` namespace to avoid pretending that old preview scenes are the
new solver.

Required editor capabilities:

- select/create `TerrainVisualRecipe`;
- edit a mask/test map inside Godot;
- paint terrain solid/empty cells for preview;
- change shape controls and see auto-refresh;
- change material controls and see auto-refresh;
- switch preview modes;
- run same native solver as runtime;
- export reference screenshots for tests;
- show dirty rect/debug counters;
- show warning when recipe schema is invalid.

Editor forbidden capabilities for early iterations:

- custom broad content manager that edits unrelated biome data;
- save game mutation;
- runtime world mutation;
- second software renderer that does not call native solver;
- PNG atlas as required intermediate.

## 18. Biome binding (Biome Binding)

Biome resources may reference visual recipes, but biome identity remains
worldgen/content truth.

Recommended binding shape:

```text
BiomeData
  rock_visual_recipe: TerrainVisualRecipe
  ground_visual_recipe: TerrainVisualRecipe
  water_visual_recipe: TerrainVisualRecipe
```

For V2 rock-first implementation, only `rock_visual_recipe` is required.

Runtime resolution must use the actual chunk/terrain biome context. It must
not silently use `get_default_biome()` for every chunk visual unless the chunk
really has no biome data and the fallback is logged as a validation warning.

If this binding becomes public modding API, update
`modding_extension_contracts.md` in the same implementation task.

## 19. Save/load boundary (Save/Load Boundary)

Save files store:

- world seed/settings;
- authoritative runtime diff;
- terrain mutations;
- gameplay state.

Save files must not store:

- visual recipe parameter snapshots;
- visual packet arrays;
- generated SDF fields;
- generated height/normal textures;
- outline polylines;
- editor preview masks unless they are explicit editor assets.

On load:

```text
world base regenerated
  -> runtime diff applied
  -> visible chunks publish terrain state
  -> visual dirty solve runs as boot/background work
  -> visual packet applied
```

The first correct visual after load must use base+diff, not base-only.

## 20. Surface/subsurface boundary (Surface/Subsurface Boundary)

ADR-0006 requires surface and subsurface to stay separate but linked.

V2 implications:

- surface rock and underground rock can share solver code;
- they may use different `TerrainVisualRecipe` resources;
- underground cannot inherit surface daylight assumptions;
- underground fog/light pressure remains gameplay/runtime authority, not
  shader truth;
- chunk z-level must be part of recipe resolution or render context if
  surface/subsurface visuals diverge.

Rock visual authoring must not collapse surface and underground terrain into
one monolithic renderer with hidden layer assumptions.

## 21. Environment runtime boundary (Environment Runtime Boundary)

ADR-0007 separates worldgen from environment runtime.

V2 implications:

- visual recipe defines stable material identity;
- weather/season/time-of-day may tint or modulate presentation later;
- environment runtime must not rewrite `TerrainVisualRecipe` as mutable state;
- presentation response can be layered on top of solved visual packet;
- local environment effects are transient and not part of the terrain visual
  recipe.

Example acceptable future extension:

```text
snowstorm runtime overlay -> shader snow accumulation parameter
```

Example forbidden extension:

```text
weather system mutates rock_visual_recipe.top_material.color_a every frame
```

## 22. Performance guardrails (Performance Guardrails)

Hard requirements:

- no full chunk visual refresh in interactive mining path;
- no all-loaded-chunks visual rebuild from one local mutation;
- no per-pixel GDScript solve;
- no per-tile Node2D tree for terrain surface;
- no hidden GDScript fallback when native solver is unavailable;
- no texture loading from disk during chunk apply;
- no unique shader source per biome;
- no unbounded `TileMapLayer.clear()` style apply for local patch.

Allowed escalation:

- if patch solve exceeds budget, enqueue background visual job;
- if chunk solve exceeds budget, split by dirty rect/subchunk/edge band;
- if GDScript apply becomes heavy, move packing/update helpers native;
- if one native solve is still too heavy, introduce native cache with explicit
  owner/invalidation.

Native cache rules:

- cache is derived;
- cache owner is terrain visual solver/presenter;
- cache invalidates by recipe id/version, chunk coord, z-level and dirty rect;
- cache is not save state;
- cache must expose debug counters for tests.

## 23. Validation model (Validation)

Validation must happen before hot runtime paths.

Recipe validation checks:

- `id` exists and is unique where registry-owned;
- `schema_version` is supported;
- `tile_size_px` is positive and within supported range;
- heights/radii/rim widths are clamped or rejected explicitly;
- `shape_supersampling` is one of supported values;
- required material slots exist;
- material source values are valid;
- required textures exist if source is `image`;
- procedural kind is supported by solver/shader;
- shader family matches packet fields.

Packet validation checks:

- all packed arrays match `pixel_width * pixel_height`;
- dirty rect lies inside packet dimensions;
- zone ids use known enum values;
- coverage values are normalized or intentionally overlapping for edge/rim;
- height/normal textures are present when shader requires them;
- debug counters are present in dev/test builds.

Failure policy:

- editor shows actionable error;
- boot validation fails loudly;
- runtime chunk apply logs explicit validation error and uses a known debug
  placeholder only if project policy allows visible error materials;
- silent fallback to old atlas is forbidden.

## 24. Testing strategy (Testing Strategy)

### 24.1 Native solver unit tests

Required cases:

- empty mask;
- full solid rectangle;
- single solid cell;
- straight south edge;
- straight east/west side edge;
- diagonal marching-square case;
- inner hole;
- concave notch;
- wrap/edge halo where relevant;
- dirty patch around one changed tile.

Assertions:

- zones are expected at key sample points;
- height changes across face depth;
- normal changes when height changes;
- material coordinates rotate/follow contour on face;
- dirty patch output does not touch pixels outside declared dirty rect;
- same input produces deterministic output.

### 24.2 Editor/runtime parity

Required parity checks:

- same recipe and same mask in editor workbench and runtime fixture;
- same solver packet or byte-equivalent packet;
- screenshot comparison in controlled viewport;
- debug mode screenshots for zone/height/normal.

Tolerance must be documented. If exact byte equality is impossible because of
GPU differences, define a maximum per-channel delta and maximum differing
pixel ratio.

### 24.3 Performance tests

Required checks:

- single tile mining marks local visual dirty patch;
- no full chunk rebuild log for single tile mutation;
- patch solve/apply under interactive contract or queued to background;
- chunk load visual solve appears as background/boot, not interactive;
- no per-frame visual solve when no dirty data exists.

### 24.4 Save/load regression

Required checks:

- save payload does not contain `TerrainVisualPacket`;
- save payload does not contain generated height/normal/mask data;
- after load, visual packet is regenerated from base+diff;
- mined rock remains mined visually after load because authoritative diff is
  applied before visual solve.

## 25. Implementation iterations (Implementation Plan)

Each iteration is a separate task. Do not merge future iterations into the
current one unless the user explicitly asks.

### V2-IT0 - Spec only

Goal:

- create this V2 spec;
- link it from documentation indexes;
- do not change runtime code.

Allowed files:

- `docs/02_system_specs/world/biome_visual_authoring_variant_d_v2.md`
- `docs/README.md`
- `docs/02_system_specs/README.md`

Forbidden files:

- runtime code;
- GDExtension code;
- existing Variant D v1 spec content;
- old desktop app code.

Acceptance:

- V2 exists as separate document;
- old Variant D remains untouched;
- indexes point to V2;
- no code behavior changed.

### V2-IT1 - Resource schema and validation

Goal:

- add `TerrainVisualRecipe`;
- add `TerrainVisualMaterialSlot`;
- add rock default `.tres`;
- add editor/dev validation without runtime rendering cutover.

Runtime work class:

- boot validation only.

Required docs:

- update `modding_extension_contracts.md` if resources are public extension
  points.

Acceptance:

- invalid recipe fails validation with explicit error;
- valid rock recipe loads;
- no save payload change;
- no runtime visual cutover yet.

### V2-IT2 - Native SDF/zone/height solver for editor fixture

Goal:

- port minimal SDF/zone/height solve from reference generator into native
  GDExtension;
- support editor/test masks;
- emit `TerrainVisualPacket` without runtime `ChunkView` integration.

Runtime work class:

- editor/test/background compute only.

Required docs:

- update `system_api.md` if solver is exposed as callable API;
- update `packet_schemas.md` if packet boundary is public/stable.

Acceptance:

- unit tests for empty/full/single/diagonal/notch masks;
- deterministic packet output;
- no GDScript per-pixel solve.

### V2-IT3 - Shader consumes packet fields

Goal:

- create shader/material path that renders packet textures;
- implement debug modes;
- keep runtime game cutover disabled.

Runtime work class:

- test/editor render path.

Acceptance:

- test scene renders zone/height/normal/albedo from packet;
- shader does not infer topology from neighbours;
- no second renderer.

### V2-IT4 - Godot editor workbench V2

Goal:

- create `addons/biome_visual_authoring_v2/`;
- edit preview mask;
- edit recipe;
- auto-refresh via same native solver;
- export reference screenshots.

Runtime work class:

- editor-only.

Acceptance:

- changing height/rim/material controls changes preview;
- preview uses native solver packet;
- no PNG atlas required.

### V2-IT5 - Procedural material parity

Goal:

- port initial material kinds and projection semantics:
  - `stratified_rock`;
  - `rough_stone`;
  - `cracked_dry_earth`;
  - `packed_dirt`;
- support image/flat/procedural sources;
- implement contour tangent/depth projection for face/back/edge.

Runtime work class:

- editor/test/background compute and shader render.

Acceptance:

- face material follows cliff contour instead of screen-horizontal stretching;
- top/base use stable map-space projection;
- reference screenshots are close to old generator for selected fixtures.

### V2-IT6 - Runtime ChunkView integration behind feature flag

Goal:

- integrate solved packet into visible chunks;
- resolve recipe from real biome/chunk context;
- keep feature flag or dev toggle until acceptance passes.

Runtime work class:

- boot/background compute;
- bounded main-thread apply;
- interactive only marks dirty patch.

Required docs:

- update `system_api.md` / `packet_schemas.md` if public boundaries change;
- update `modding_extension_contracts.md` if biome recipe binding is public.

Acceptance:

- rock chunk renders through V2 packet/shader;
- default biome fallback is not used for chunks with known biome;
- no save payload change;
- V1 path can remain available until cutover decision.

### V2-IT7 - Interactive dirty patch updates

Goal:

- mining one rock tile updates only local visual patch;
- no full visual rebuild for local mutation;
- instrumentation proves interactive contract.

Runtime work class:

- interactive dirty mark;
- background/bounded apply solve.

Acceptance:

- logs/counters show dirty patch dimensions;
- no full chunk refresh on one tile;
- visible result updates correctly after mining;
- save/load remains authoritative through terrain diff.

### V2-IT8 - Golden visual regression

Goal:

- lock fixtures and screenshot comparisons;
- compare old generator reference where useful;
- compare editor and runtime for same recipe/mask.

Runtime work class:

- test-only.

Acceptance:

- golden tests catch zone/height/normal regressions;
- tolerated deltas documented;
- CI/dev command documented.

Current IT8 harness:

- golden fixture path:
  `tests/visual/golden/terrain_visual_v2_golden.json`;
- test suite:
  `tests/visual/test_terrain_visual_golden_regression.gd`;
- dev/CI command:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent/Invoke-GdUnit4.ps1 -NoHeadless -TestPath res://tests/visual/test_terrain_visual_golden_regression.gd`;
- `-NoHeadless` is required because controlled viewport screenshot capture needs
  the real renderer; the headless dummy renderer returns null viewport textures.

Locked checks:

- packet digests for `zone_ids`, `height_q16`, `normal_rgba8`,
  `material_u_q16`, and `material_v_q16`;
- controlled viewport screenshot digests for `albedo`, `zone`, `height`, and
  `normal` debug modes;
- editor/runtime packet byte equivalence for the same recipe and mask.

Documented tolerances:

- `packet_hash_delta = 0`;
- `screenshot_hash_delta = 0`;
- `max_channel_delta_lsb = 0`;
- `max_differing_pixel_ratio = 0.0`.

### V2-IT9 - Cutover and cleanup decision

Goal:

- decide whether V2 supersedes Variant D v1;
- archive or quarantine transitional V1 files;
- update approved specs through workflow.

Required docs:

- update this V2 spec status if approved;
- update or supersede `biome_visual_authoring_variant_d.md`;
- reconcile `terrain_hybrid_presentation.md`;
- update meta docs for final public contracts.

Acceptance:

- one canonical terrain visual path remains;
- no ghost transitional generator path is presented as active truth;
- old desktop app is archived as historical reference or removed by explicit
  approved task.

IT9 decision:

- IT9 decision: Variant D v2 is the canonical terrain visual path for rock
  runtime/editor presentation.
- Variant D v2 supersedes `biome_visual_authoring_variant_d.md` as the active
  terrain visual source of truth.
- `station_mirny/terrain_visual/v2_chunk_runtime_enabled` is enabled by default.
  Keeping the setting is allowed only as an explicit diagnostic escape hatch,
  not as a second canonical renderer.
- `tools/rimworld-autotile-lab/desktop_app` remains archived as historical
  reference and test-oracle material. It is not a runtime source of truth.

## 26. Required boundary documentation updates (Required Updates)

Current IT9 status:

- `docs/02_system_specs/meta/system_api.md` documents the `ChunkView` V2 bridge
  as the canonical runtime presentation bridge, with dirty patch apply as the
  safe entrypoint.
- `docs/02_system_specs/meta/packet_schemas.md` documents
  `TerrainVisualPacketV0` as the stable derived visual packet used by editor,
  runtime chunk presentation, and dirty patch apply.
- `docs/02_system_specs/meta/modding_extension_contracts.md` documents
  `TerrainVisualRecipe` and `BiomeData.rock_visual_recipe` as public authored
  content extension seams for the canonical V2 path.
- `commands.md` and `event_contracts.md` are not updated by IT9 because no
  gameplay command or public event payload changes.

Future implementation tasks must update these docs in the same task when they
cross the listed boundary:

- `docs/02_system_specs/meta/system_api.md`
  - when `TerrainVisualSolver` becomes a callable native/Godot API;
  - when a safe runtime entrypoint for visual dirty marking is introduced.
- `docs/02_system_specs/meta/packet_schemas.md`
  - when `TerrainVisualPacket` becomes a stable packet/schema boundary;
  - when chunk packets carry additional visual fields.
- `docs/02_system_specs/meta/modding_extension_contracts.md`
  - when `TerrainVisualRecipe` or biome visual bindings become mod extension
    points.
- `docs/02_system_specs/meta/commands.md`
  - only if gameplay commands change; visual packet generation alone should
    not create a new gameplay command.
- `docs/02_system_specs/meta/event_contracts.md`
  - only if public domain events are added for terrain visual invalidation.

## 27. Anti-patterns (Forbidden Patterns)

Forbidden:

1. Reverting to the old external desktop app as the active generator.
2. Treating PNG exports as canonical terrain visual truth.
3. Building a second independent renderer for editor preview.
4. Letting shader infer topology from neighbour booleans.
5. Doing SDF/height/normal solve in GDScript.
6. Full chunk visual rebuild on one tile mutation.
7. Saving generated visual packets.
8. Using default biome visual resource for all chunks with no validation.
9. Creating one Node2D/Line2D per cell or per pixel.
10. Adding one shader source per biome.
11. Mutating recipe resources during environment runtime.
12. Letting gameplay visibility/safety query shader pixels or normals.
13. Hiding native solver failure behind old atlas fallback.
14. Expanding rock-first work into ground/water runtime cutover without a
    separate iteration.
15. Editing the old Variant D v1 spec silently while implementing V2.

## 28. Open questions (Open Questions)

These are implementation questions, not blockers for creating the V2 spec:

- Final class names:
  - `TerrainVisualRecipe` vs `BiomeVisualRecipe`;
  - `TerrainVisualSolver` vs `TerrainSdfVisualSolver`;
  - `TerrainVisualPresenter` vs `ChunkTerrainVisualPresenter`.
- Whether `TerrainVisualPacket` should be a GDExtension class, Resource, or
  strict Dictionary wrapper.
- Exact packed texture formats:
  - `height_q16`;
  - `normal_rgba8`;
  - `material_uv_q16`;
  - coverage channels.
- Exact tolerance for old-generator reference comparison.
- Whether contact outline should be packet polyline, shader mask channel, or
  both.
- Whether surface and underground rock share one default recipe or split early.
- Whether procedural material generation should live fully in shader or partly
  in native precomputed packet fields.

## 29. Acceptance criteria for V2 as a whole (Overall Acceptance)

V2 is considered successful only when:

- editor workbench and runtime render the same recipe/mask through the same
  solver and shader contract;
- rock visually recovers the old generator's major qualities:
  - continuous contour;
  - readable facade;
  - rim/edge band;
  - material projection following the cliff;
  - dynamic-lighting-ready normals;
  - anti-aliased organic edge;
- mining one tile updates a bounded dirty patch, not a full chunk;
- save/load stores gameplay diff only and regenerates visuals;
- adding a new material variation is data/resource work, not a new runtime
  branch;
- old desktop app is no longer needed for day-to-day terrain authoring;
- approved docs are reconciled before V2 becomes source of truth.

## 30. Out-of-scope observations (Out-of-Scope Observations)

Observed but not fixed by this spec-only task:

- Existing Variant D v1 may already have transitional implementation files in
  the repository. This V2 document does not revert or delete them.
- `terrain_hybrid_presentation.md` still describes baked shape atlases as an
  approved architecture. V2 intentionally conflicts with that direction for
  rock and must be reconciled in a later approval task.
- The old generator contains valuable tests and reference exports. They should
  be mined for V2 golden tests before archival.
- Ground and water need their own scoped iterations after rock is proven.
