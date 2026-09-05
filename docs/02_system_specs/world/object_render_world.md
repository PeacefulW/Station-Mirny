---
title: Object Render World — fixed passes and data-driven descriptors
doc_type: system_spec
status: proposed
owner: engineering+design
source_of_truth: false
version: 0.3
last_updated: 2026-08-12
related_docs:
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - world_runtime.md
  - world_object_placement_v0.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
---

# Object Render World

> Iteration 2 is implemented and verified, but remains pending manual acceptance.
> `world_runtime.md`, `system_api.md`, and `packet_schemas.md` are the canonical
> runtime boundaries; this document records the renderer-specific design and
> acceptance evidence.

## Purpose

Chunk remains the unit of generation, storage, collision and streaming. GPU
submission is instead bounded by a small fixed set of pass/material semantics.
Adding an object family or atlas variant must not add a per-family renderer,
shader sampler bank, `MultiMeshInstance2D`, or source-code branch.

## Production architecture

`WorldRenderClassRegistry` loads
`data/world_render/render_class_registry.json` and owns:

- five fixed passes: `ground`, `body`, `shadow`, `emissive`, `overhead`;
- descriptor metadata and LUTs for atlas rect, layout, flags, frame data, crops
  and anchors;
- generic native source bindings from an accepted worker result key to a
  descriptor, geometry rule, painter semantic and pass mask;
- boot-resident static and actor atlas channels;
- authored CPU/GPU hard bounds.

Production currently has nine descriptors: four static families and five Player
clips. The fixed materials are six including the sparse spore pass. Sampler
budgets are fixed at ground `5`, body `9`, shadow `4`, emissive `3`, and overhead
`3`; family count does not enter those budgets.

The generated static atlas channels are `body_base`, `foliage`, `snow_overlay`,
`wind_mask`, `snow_mask`, `season_mask`, `shadow`, `emissive`, and `overhead`.
Player body and shadow clips are packed into their own shared actor atlases.
Runtime instances carry a descriptor id and variant/frame; the renderer never
loads a family asset path while publishing a snapshot.

## Native snapshot contract

`WorldCore.build_world_render_snapshot(chunk_origins, object_results,
grass_results, source_bindings, grass_lod_fraction)` parses every source binding
generically, creates compact `RenderAtom` records, sorts indices by
`(feet_y, semantic_layer, stable_id)`, and emits a dense window of absolute
1024-pixel pages. The page window is bounded to 17 slots, including empty gaps.

Each page can contain the five fixed streams. Non-ground object shadows share a
single `object_shadow_buffer`; ground shadows remain page-local for their ground
ordering, and actor shadows share one `actor_shadow_buffer`. At the accepted
zoom `0.2`, grass directional-shadow LOD is zero, so the active world uses two
shadow MultiMeshes: object and actor.

The GPU instance ABI is 16 floats. Painter metadata stays in compact CPU arrays
and no longer consumes unused GPU fields. The native implementation reserves
atom storage once, sorts lightweight indices, and reports its actual
`RenderAtom` stride and bounded capacities.

## Ownership

- `WorldRenderWorld` is the only GPU owner for renderer-active static objects,
  grass, Player body/shadow and future registered visual proxies.
- `WorldObjectCollisionOwner` consumes only compact tree collision rectangles.
  It owns no atlas, material, mesh, MultiMesh or GPU payload.
- `world_object_packet_layer.gd` is a deprecated script-name bridge for isolated
  old tools; production preloads `WorldObjectCollisionOwner` directly.
- `WorldLayeredObjectAssetCatalog` remains CPU metadata/collision source only.
- `ChunkView` owns terrain and adopts the chunk collision owner; it does not
  render the static object families handled by `WorldRenderWorld`.

The old tall-caster/height-shadow path is removed completely. It has no node,
viewport, material, resource, native payload or debug counter in production.

## Grass and compositor

Grass body and shadow alpha crops are generated offline into registry metadata;
boot no longer scans 614,400 pixels with `Image.get_pixel()`. Grass uses the
cheap ground material and its directional-shadow count is independently
data-driven by zoom LOD.

At `world_render_scale == 1.0`, `WorldResolutionCompositor` routes the world
directly to the main viewport, disables the auxiliary `SubViewport`, and hides
the fullscreen composite layer. Sub-native scales enable that viewport. Render
timing collection defaults off and is instrumentation-only.

## Hard bounds

| Resource | Authored maximum |
|---|---:|
| descriptors | 64 |
| variants per descriptor | 256 |
| fixed passes | 5 |
| render page slots | 17 |
| visible static instances | 1,048,576 |
| visible actors | 4,096 |
| spore instances | 1,048,576 |
| GPU instance payload | 320 MiB |
| CPU RenderAtom envelope | 160 MiB |
| CPU sort indices | 8 MiB |
| native snapshot working-set ceiling | 1 GiB |

The current native `RenderAtom` is 136 bytes, so its reported capacity is
136 MiB. The 1 GiB value bounds this native snapshot workspace, not total engine
memory, imported textures, terrain caches or the process working set.

## Scale proof

The generator checks in synthetic packs with nine and ten static families,
ten variants per family, and mixed ordinary cutout, foliage/wind, emissive and
overhead semantics. The tenth family is an append-only data/assets change. The
contract test verifies that its id is absent from C++, GDScript and shader source
and that native packing emits the expected 100 body, 100 shadow, 30 emissive and
20 overhead instances.

## Verification evidence

Target: Godot 4.7, Forward+, D3D12, NVIDIA GTX 1060 6 GB, 1920×1080,
zoom `0.2`, north route.

- Debug and Release GDExtension builds pass.
- Iteration-2 architecture, fixed sampler, synthetic 10-family, compositor,
  collision-only owner and CPU-bound contract: PASS.
- Actor runtime, queue/cache, teardown, shadow direction and MultiMesh painter
  contracts: PASS.
- Player pixel parity: exact at zoom `1.0` and `0.2` (`diff = 0`).
- Tree/Player overlap: PASS north/south at zoom `1.0` and `0.2`.
- Valid 90-second control route: 10,780 samples, zero missing/hidden/stale/
  incomplete viewport chunks, zero frames above `16.67 ms`, frame average
  `7.261 ms`, P95 `9.630 ms`, P99 `10.470 ms`, max `14.096 ms`, GPU P95
  `9.481 ms`. Object ablation changed 303,689 pixels; maxima were 1,188 trees,
  4,576 rocks and 926 bushes.

The hard 60 FPS/content gate passes. The Iteration-1 comparison does not:
Iteration-1 frame P95 was `8.949 ms`, so this control is `0.681 ms` (`7.6%`)
slower at P95 despite a lower maximum. This exception is intentionally left for
manual acceptance; no further shader micro-optimisation belongs to this pass.

Report:
`C:/Users/peaceful/AppData/Roaming/Godot/app_userdata/Станция Мирный/gpu_bench_iteration2_control_north_result.json`.

## Acceptance state

- Fixed pass/material cost independent of family count: satisfied.
- Data-only tenth family: satisfied.
- Dormant visual/tall-caster production resources absent: satisfied.
- Explicit authored CPU/GPU bounds: satisfied.
- Visual, ordering and runtime contracts: satisfied.
- 60 FPS hard bound and complete viewport content: satisfied.
- No slower than Iteration 1 P95: not satisfied; manual decision required.

Iteration 3 was rejected and rolled back on 2026-08-12. The accepted runtime
baseline remains Iterations 1–2.
