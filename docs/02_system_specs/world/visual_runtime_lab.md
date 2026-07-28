---
title: Visual Runtime Lab V0
doc_type: system_spec
status: approved
owner: engineering+art
source_of_truth: true
version: 1.0
last_updated: 2026-07-28
related_docs:
  - ../../README.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ../meta/system_api.md
  - ../meta/localization_pipeline.md
  - world_runtime.md
  - terrain_hybrid_presentation.md
  - mountain_generation.md
  - lake_generation.md
  - wind_and_grass_scatter_presentation.md
  - plains_trees_presentation.md
---

# Visual Runtime Lab V0

## Purpose

Define one fast developer scene for evaluating the current production world
presentation at the player's maximum zoom-out. The lab is a thin host around
`world_runtime_v0.tscn`; it must not recreate terrain, water, mountain, grass,
flora, tree, rock, lighting, or streaming presentation through a parallel
renderer.

## Gameplay Goal

An artist or developer can open one scene and immediately inspect:

- the production plains ground material and every authored ground texture zone;
- production grass, trees, flora, spiky flora, and small rocks;
- a mountain mass framed on the right side of the camera;
- one small lake containing both shallow and deep water;
- the exact maximum player zoom-out, never a wider debug-only camera;
- texture-zone overlays, tile/mountain/collision overlays, and the terrain
  material under the cursor;
- a focused set of visual tuning controls;
- an explicit apply path for the current lab and an explicit save path back to
  the production authoring resources.

## Scope

V0 includes:

- a new scene under `scenes/dev/` that instantiates
  `scenes/world/world_runtime_v0.tscn`;
- a deterministic boot-only probe selector that samples production
  `ChunkPacketV1` output and chooses a bounded camera patch containing shallow
  water, deep water, and a mountain to the right;
- maximum zoom-out from `PlayerBalance.zoom_min`;
- a localized developer panel with:
  - ground texture-zone mode;
  - existing tile-grid, mountain-mask, and object-collision overlays;
  - terrain/material inspection under the cursor;
  - ground, grass, tree, small-rock, lake, and mountain tuning controls;
  - apply, reset, and save-to-runtime actions;
- an exact ground-zone debug mode inside the production ground shader. It uses
  the already-computed shader fields and is disabled by default;
- completion of the existing `WorldStreamer.initialize_new_world(...)`
  authoring input with the already-owned bare-ground stone settings resource,
  so every ground-field consumer receives one coherent working copy;
- a developer-only presentation-cache reset called only after the previous
  embedded runtime has left the scene tree;
- persistence of edited authoring values to the existing production `.tres`
  resources.

## Out of Scope

- changing canonical terrain ids, walkability, lake or mountain algorithms;
- changing `WORLD_VERSION`;
- mutating an existing save's frozen `worldgen_settings`;
- adding a second streamer, a GDScript world generator, or per-object scene
  nodes;
- saving debug overlay visibility into gameplay saves;
- exporting a standalone release build of the lab;
- editing atlas PNGs, shader families other than plains ground, or object
  placement packet schemas;
- guaranteeing that every future mod-provided texture appears in this V0 panel.

## Related Documents

The related documents in frontmatter govern ownership. In particular:

- `world_runtime.md` owns the production scene and maximum streaming envelope;
- `terrain_hybrid_presentation.md` owns terrain materials;
- `wind_and_grass_scatter_presentation.md` owns grass compute/presentation;
- `mountain_generation.md` and `lake_generation.md` own canonical geography;
- `localization_pipeline.md` owns all visible panel copy.

## Dependencies

- native `WorldCore` GDExtension;
- `WorldStreamer.initialize_new_world(...)`;
- `WorldStreamer.get_chunk_packet(...)`;
- `WorldTileSetFactory.get_built_material_for_terrain(...)`;
- production terrain and placement resources under `data/`;
- current RU and EN gettext catalogs.

## Law 0 Classification

| Question | V0 answer |
|---|---|
| Canonical, runtime overlay, or visual only? | The lab, controls, overlays, and shader zone mode are developer-only presentation. It reads canonical packets but owns no world truth. |
| Save/load required? | Lab state is not gameplay save state. Explicit save writes authoring values to production `.tres` files; existing game saves remain unchanged. |
| Deterministic? | Patch selection and runtime output are deterministic for the current seed, version, and authoring resources. |
| Must it work on unloaded chunks? | No. Inspection is limited to loaded packets. Patch selection may sample packets at boot through native batch generation. |
| C++ compute or main-thread apply? | World/placement compute remains native. The lab performs bounded boot-time orchestration and main-thread UI/presentation only. |
| Dirty unit | One complete embedded lab runtime restart for placement/worldgen tuning; one shared material uniform for zone overlay. |
| Single owner | Existing runtime owners remain unchanged. The lab authoring model owns only unsaved working copies until explicit resource save. |
| 10x / 100x scale path | The lab is bounded to one maximum-zoom streaming envelope and a fixed probe radius. It never scans the whole world. |
| Main-thread blocking risk | Native packet probe runs only at dev boot with bounded batches and early exit. Apply is a boot-class embedded-runtime restart behind the normal loading gate. |
| Hidden GDScript fallback? | Forbidden. Missing `WorldCore` fails the lab explicitly. |
| Could it become heavy later? | Yes. Therefore all world/placement generation stays in existing native packet paths and no live full-world rebuild is introduced. |
| Whole-world prepass? | No new prepass. The lab reuses the production bounded `WorldPrePass` prepared by `WorldStreamer`. |

## Data Model

The lab edits working copies of these existing resources:

- `data/terrain/material_sets/plains_ground_material_set.tres`;
- `data/terrain/material_sets/grass_scatter_material_set.tres`;
- `data/world_objects/placement_groups/plains_trees.tres`;
- `data/world_objects/placement_groups/plains_small_rocks.tres`;
- `data/world_objects/placement_groups/plains_bare_ground_stones.tres`;
- `data/balance/lake_gen_settings.tres`;
- `data/balance/mountain_gen_settings.tres`.

V0 exposes only already-defined fields and their existing validation ranges.
No new save/resource schema is introduced.

The source `.tres` files are the write target only after an explicit
save-to-runtime action. Ordinary slider edits remain in working copies.

## Runtime Architecture

### Production runtime reuse

The dev scene instantiates `world_runtime_v0.tscn`. It does not instantiate
`ChunkView` or presentation layers itself.

### Patch selection

The boot-only selector:

1. reads the streamer's frozen seed, version, and packed settings;
2. validates the seed-707 prepared `9 x 9` neighbourhood through bounded native
   packet batches totalling 81 packets;
3. summarizes packet terrain/object fields in GDScript as dev-only work;
4. prefers a patch with both lake-bed classes, visible object families, and a
   mountain chunk east of the lake;
5. positions the real player/camera and lets the production loading gate
   re-center and finish.

If tuning moves a requested feature out of that prepared neighbourhood, the
same deterministic camera patch is used and the panel reports the incomplete
match. The selector does not broaden into a world scan.

### Tuning apply

There is no live canonical world mutation.

- Ground zone overlay is a uniform-only visual toggle.
- Tuning that affects native scatter or packet placement applies by destroying
  the current embedded runtime, resetting presentation caches, and starting one
  new embedded runtime with working-copy settings.
- The same production loading gate blocks presentation until the new bounded
  visible envelope is ready. A developer-only boot option excludes only the
  invisible movement-reserve ring from that gate; the production streamer keeps
  loading the reserve in the background.

This is `boot` work, not an interactive gameplay path.

### Authoring save

`Save to runtime` writes the working copies through `ResourceSaver` to the
existing resource paths and then performs the same boot-class lab restart.

The action affects defaults for newly created worlds. Existing saves keep their
embedded `worldgen_settings` by contract.

## Event Contracts

No new `EventBus` events.

The lab consumes the existing `world_initialized` signal indirectly through the
embedded `WorldRuntimeV0Scene`.

## Save / Persistence Contracts

- No new gameplay save section.
- No chunk diff changes.
- No environment save changes.
- Existing current-version saves are never rewritten by the lab.
- Explicit authoring save changes repository `.tres` defaults only.

## Performance Class

- Patch selection: bounded dev `boot` work; the prepared neighbourhood is 81
  native packets. GDScript summarizes only those returned packets.
- Apply: dev `boot` restart through production streaming/background queues.
- Zone overlay: one shared uniform update; shader branch is uniform and disabled
  by default.
- Cursor inspection: at most one loaded chunk-packet lookup when the hovered
  world tile changes.
- Shift texture probe: one `1 x 1` GPU sample of the same built production
  ground shader after cursor movement, throttled to eight world pixels and
  active only while Shift is held. No full-viewport GPU readback is used.
- No per-frame scan of loaded chunks, tiles, objects, or files.

## Modding / Extension Points

V0 reports the active material/profile ids and texture resource paths, so
registry overrides remain visible. Adding editable fields or mod-owned resources
requires a later spec amendment with an explicit write-authority decision.

## Acceptance Criteria

- [ ] The lab instantiates `world_runtime_v0.tscn`; no duplicate renderer or
  generator exists.
- [ ] Camera zoom equals `PlayerBalance.zoom_min` and cannot zoom farther out.
- [ ] The selected patch contains shallow water, deep water, and mountain
  presentation on the right, or reports an explicit bounded-probe failure.
- [ ] Grass, native object families, ground, mountain, and water are produced by
  the production runtime paths.
- [ ] Ground-zone mode colors the exact shader-computed texture zones and is off
  by default outside the lab.
- [ ] Holding Shift over the world reports the exact shader zone, its color
  meaning, and applied albedo texture filename; purple reports the scree blend
  (`rock_top_albedo.png` plus `foothill_albedo.png`).
- [ ] Existing grid, mountain-mask, and collision overlays are reachable from
  buttons.
- [ ] Cursor inspection reports terrain id, profile id, material id, and texture
  paths without reading private streamer dictionaries.
- [ ] Ground, grass, tree, rock, lake, and mountain controls can be changed and
  applied through a bounded embedded-runtime restart.
- [ ] Explicit save writes valid production resources; reset restores disk
  values.
- [ ] Existing saves are not mutated.
- [ ] New visible copy has RU and EN translations.
- [ ] Static and headless scene smoke checks pass.
- [ ] Final visual quality remains a manual human verification.

## Failure Cases / Risks

- Resetting static presentation caches while an old world is still live can
  leave mismatched materials. The lab must await removal of the old embedded
  runtime first.
- Resource save may fail in an exported/read-only build. V0 must report the
  error and keep working copies intact.
- A future generator/profile change may make the preferred patch unavailable.
  The bounded selector must report the missing feature instead of broadening
  beyond its prepared 81-packet neighbourhood.
- A ground field change that bypasses the existing shader computations can make
  the zone overlay stale. The debug colors must stay inside the same fragment
  path after field values are computed.

## Files Allowed

- `docs/02_system_specs/world/visual_runtime_lab.md`
- `docs/02_system_specs/README.md`
- `docs/02_system_specs/meta/system_api.md`
- `assets/shaders/ground_hybrid_material.gdshader`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/world_streamer.gd` only for the additive optional
  `plains_bare_ground_stone_settings` new-game argument and the developer-only
  visible-envelope initial-loading option
- new files under `scenes/dev/visual_runtime_lab*`
- new focused smoke checks under `tools/visual_runtime_lab*`
- `locale/ru/messages.po`
- `locale/en/messages.po`

Production `.tres` values are runtime write targets of the completed lab, not
implementation-time default changes for this iteration.

## Files Forbidden

- native world-generation sources;
- `ChunkPacketV1`, packet schemas, commands, events, or save schemas;
- `ChunkView`, `WorldDiffStore`, and `SaveManager`;
- gameplay scenes outside the new dev host;
- unrelated assets, systems, or documentation.

## Required Updates

- `docs/02_system_specs/README.md` — index this approved dev-tool spec.
- `docs/02_system_specs/meta/system_api.md` — document the developer-only
  presentation-cache reset.
- `commands.md`, `event_contracts.md`, `packet_schemas.md`, and
  `save_and_persistence.md` — no contract change expected; verify by grep at
  closure.

## Open Questions

None for V0. Broader authoring of mod resources or existing-save worldgen
mutation requires a separate approved iteration.

## Implementation Iterations

### V0 — Single implementation

Land the scene, panel, working-copy authoring model, bounded selector, exact
ground-zone shader mode, cache reset, localization, smoke checks, and closure
proof together.
