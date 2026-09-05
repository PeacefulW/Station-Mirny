---
title: Plains Trees Presentation and Depth Layering V0
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.5
last_updated: 2026-08-17
related_docs:
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/WORKFLOW.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - ../meta/event_contracts.md
  - ../meta/commands.md
  - world_object_placement_v0.md
  - wind_and_grass_scatter_presentation.md
  - terrain_hybrid_presentation.md
  - world_runtime.md
  - ../../03_content_bible/resources/flora_and_resources.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Plains Trees Presentation and Depth Layering V0

## Purpose

Define the first contract for generated surface **trees** on the `plains`
biome as a world-object family, with one non-negotiable architectural rule:

> **Tree ↔ grass ↔ player depth is owned by one shared ordering system. It is
> never a per-object hardcoded `z_index`, never a baked grass overlay, and never
> a tree-specific layer placed above or below grass.**

Since Iteration 1 of the render-world work that shared system is the native
painter tuple `(feet_y, semantic_layer, stable_id)` inside one global sorted
snapshot, not the former per-stripe mid-layer ladder. The rule above is
unchanged; only its owner moved.

This spec rides `world_object_placement_v0.md` (placement, batching, depth
ladder) and `wind_and_grass_scatter_presentation.md` (wind, the per-stripe
mid-layer ladder) instead of inventing a parallel system. It establishes the
procedural tree atlas authoring path, the batched per-stripe presentation, wind
response, fixed-azimuth time-stretched silhouette shadows, and the accepted
chunk-scoped trunk-collision proof. Harvest remains deferred.

### Why this spec exists

A throwaway visual sketch proved the **look** (procedural generator, muted
autumn palette, smooth continuous trunk, time-stretched shadows, wind sway). But the
sketch placed trees as a flat overlay **outside** the streamer's depth
ownership and produced two project anti-patterns:

- **per-object fixed `z_index`** (a tree-only layer above grass), and
- a **baked grass fringe** painted into the tree texture to fake grass at the
  trunk base.

Both are hardcoding (`ENGINEERING_STANDARDS` anti-patterns: "magic numbers",
"multiple systems acting as owners of the same data"). They do not scale to
hundreds of object types and make depth undebuggable. The visible bug — a whole
tree flipping above/below grass as the player walked north — was a **stale z**:
the overlay set tree z once at spawn while `WorldStreamer` kept re-assigning
grass z on player movement. The fix is not a smarter per-object rule; it is to
make trees ride the canonical ladder so the single z owner manages them exactly
like grass and decor.

## Gameplay Goal

The `plains` surface gains a readable, alive autumn forest that sits **natively**
in the world:

- grass in front of a trunk covers only the trunk **base** (where they overlap
  on screen), never the whole tree;
- the player walks correctly **in front of / behind** trees;
- canopies sway on the **same wind** as the grass;
- shadows always fall **screen south-east** from the fixed north-west authored
  sun; dawn/dusk stretch them while the root stays planted;
- adding a new tree / bush / flora type later requires only **data + an atlas**,
  never new depth code.

## Scope (V0)

- `plains` biome only; surface layer (`z = 0` gameplay plane).
- Trees as a new **world-object family** in the native object packet
  (`object_kind` tree value), placed deterministically (LAW 3).
- A **procedural tree atlas** exported by a generator tool (Variant D path,
  like the grass tuft atlas), committed as a PNG, runtime-preloaded only.
- **Records in the global sorted snapshot** owned by `WorldRenderWorld`; one
  tree is one packed instance ordered by its **base (feet) Y**, interleaved with
  grass, other object families and actors in the same fixed passes.
- **Order ownership stays outside the object**: the native painter tuple
  `(feet_y, semantic_layer, stable_id)` decides it. Trees carry no independent
  z. *(Before Iteration 1 this was `WorldStreamer`'s `_ladder_anchor_stripe` +
  `update_mid_ladder_z` re-assignment; the rule is unchanged, the owner moved.)*
- **Wind** response: the shared wind global uniforms drive a tree wind material
  (canopy sways, base planted), no new wind owner.
- **Fixed-azimuth silhouette cast shadow**: fixed south-east direction from
  `WorldVisualLightingProfile` / the layered bake contract, with length and
  visibility derived from time of day. Each shadow bucket rides its caster's
  feet row for bare-ground composition. The shadow is an ordinary record of the
  fixed `shadow` pass and is ordered by the same global painter tuple as every
  body, so there is no absolute cast-shadow z and no receiver mask.
- **Deterministic per-instance variation** (atlas variant, scale tier, tint,
  wind phase) from a hash of seed / chunk / tile (no `randf` — LAW: deterministic
  hashing).
- **Density / palette / scale tiers as authored data** (muted, walkable forest).

## Out of Scope (V0)

- Per-tree bodies, crown/full-cell collision, and registry-driven general object
  collision remain out of scope. Current trees do have chunk-scoped trunk shape
  owners derived from `object_kind == 4`; matching visuals and collision are
  staged and revealed atomically, never as one body per tree.
- **Harvest / chopping / wood yield / runtime diff** — later iteration; adds
  `commands.md`, `event_contracts.md`, save diff (`world_object_placement_v0`
  Iteration 2).
- A second biome; full biome resolver; biome blending.
- **fade-on-overlap** transparency when a tall tree covers the player (design
  noted in Open Questions; later polish, data/shader, not hardcode).
- Runtime atlas painting (`Image.set_pixel` at boot is forbidden).
- **Explicitly forbidden, not merely deferred** (these are the sketch
  anti-patterns this spec exists to ban):
  - a baked grass fringe / baked occlusion painted into the tree atlas;
  - a per-object fixed `z_index`;
  - any tree-specific z layer placed wholesale above or below the grass scatter
    instead of interleaved on the shared ladder;
  - a GDScript per-frame loop assigning tree z.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Tree **placement** is canonical immutable base output (LAW 5), deterministic (LAW 3). Sprite/depth/wind/shadow batches are derived visuals; loaded trunk collision is a gameplay proof derived from the same `object_kind == 4` record. |
| Save/load required? | No in V0 (placement is derived from seed+version; presentation is derived). Harvest iteration adds a runtime diff. |
| Deterministic? | Placement: yes — pure function of seed, version, chunk, settings, content set. Wind/shadow animation: intentionally non-deterministic visual drift, never read by gameplay. |
| Must it work on unloaded chunks? | Placement is derivable on demand. CPU results may live in bounded source/warm caches and GPU layers in bounded hot/pool/retire residency without a `ChunkView`; no whole-world presentation state is retained. |
| C++ compute or main-thread apply? | Placement solve, packet build and the sorted render snapshot are C++ (`WorldCore`). Main thread only bulk-uploads finished page buffers, one bounded page bundle per streaming tick. |
| Dirty unit | One chunk's tree presentation buffer (rebuild on diff, like grass). Publication unit: one render page bundle per bounded upload phase. Incremental per-page residency is Iteration 3 scope and is **not** implemented; a changed chunk currently rebuilds the global snapshot. |
| Single owner | Placement: `WorldCore`. Scheduling/cache/envelope: `WorldStreamer`. GPU buffers and lifecycle: `WorldRenderWorld` (sole GPU owner). Collision rectangles: `WorldObjectCollisionOwner`; `ChunkView` adopts that reference only. Painter order: native `(feet_y, semantic_layer, stable_id)` — no per-family z owner. Wind state: `WindRuntime` (read-only consumer). |
| 10x / 100x scale path | More trees stay in per-stripe batch buffers (no per-instance calls). More object types share the **one** ladder and opt into authored caster/receiver height tiers; the receiver pass stays viewport-bounded. |
| Main-thread blocking risk | Bounded per-chunk buffer apply through the existing decorative visual upload path; a 16 px anchor move is one linear-root z write plus clamp-boundary migrations, not a 64-stripe walk. |
| Hidden fallback? | Forbidden (LAW 9). No GDScript placement fallback when native is unavailable; fail explicitly. |
| Could it become heavy later? | Yes (dense forests, collision, harvest) — which is why placement is native-first and depth is on the shared ladder now. |
| Whole-world prepass or local compute only? | Local per-chunk compute only (LAW 12). |

## Design Intent

### Depth is owned by the shared ladder, never by the object

The world already cuts the mid-layer into absolute 16 px horizontal stripes
(`WorldRuntimeConstants.DEPTH_STRIPE_PX`) and assigns each stripe a z
**relative to the player's feet stripe**, clamped to
`±DEPTH_LADDER_HALF_RANGE_STRIPES`, via
`z_for_stripe_vs_anchor(world_stripe, anchor_stripe, is_object)`. Grass scatter,
object decor, loose rocks, and the player all share this ladder; `WorldStreamer`
owns the anchor (`_ladder_anchor_stripe`) and broadcasts it through
`update_mid_ladder_z`. Chunk batch owners implement the same clamped formula
with `DepthLadderBandRoot`: fixed north/south roots and one rebased linear root.
One normal anchor step therefore updates one root and only the stripe nodes
crossing a clamp boundary, with no all-stripe walk and no buffer rebuild.

A tree is **just another mid-layer object on this ladder**. It is bucketed by
its **base (feet) stripe** into a sparse per-stripe `MultiMeshInstance2D`
batch, interleaved with the grass scatter stripes — exactly the
`world_object_placement_v0.md` Batch Presentation Contract ("bounded sparse
per-stripe batch layers interleaved with the grass scatter stripes, the player
constant at the ladder center"). Consequences, all for free, with zero
per-object tuning:

- A grass tuft whose base stripe is **south of** (in front of) the trunk base
  lands on a more-forward stripe and overdraws the part of the tree it overlaps
  on screen — the trunk **base** only (grass is low on screen; the canopy is
  high and north of it, so it is never covered).
- The **player** sorts in front of / behind a tree by its own feet stripe.
- The single z owner re-assigns tree z together with grass on movement, so the
  sketch's stale-z flip is structurally impossible.

This is the native 2D "Y-sort by feet" concept; the stripe ladder is the
project's scalable form of it (Godot `y_sort` orders nodes, not instances inside
a dense grass `MultiMesh`, so the project pre-buckets into stripes — see
`wind_and_grass_scatter_presentation.md`). Trees join it; they do not get a
private scheme.

### Tall billboards sort by their feet

A tree's canopy extends many stripes north of its base, but the whole instance
is sorted by its **base stripe** (its feet) and drawn at that stripe's z. This
is the standard top-down billboard rule and is correct: a tree behind the player
(base stripe north of the player) is drawn behind even though its canopy is high
on screen, because nothing in front overlaps the canopy region. The one inherent
billboard artifact — a tree whose feet are just south of the player overlapping
the player — is accepted by the genre (see Open Questions for the optional
fade-on-overlap polish). No per-pixel depth and no sprite splitting are required
in V0.

### One wind truth

Trees read the shared wind global uniforms written once per frame by
`WindRuntime` (`wind_time`, `wind_direction`, `wind_strength`,
`wind_gust_scroll_px`), like grass. A tree wind material sways the canopy and
keeps the base planted: sway weight rises toward the top of the sprite
(`1 - UV.y`, base anchored at the texture bottom), amplitude is an authored
fraction of tree height, strength drives **tempo and a bounded lean**, never
stretch (same contract as grass). Trees respond more slowly and weakly than
grass via authored per-material params. No new wind owner, no per-consumer
broadcast.

### Fixed-azimuth silhouette shadow, time-stretched from a planted root

The cast shadow is the tree silhouette projected onto the ground (the same
texture, flattened and sheared from the base). The authored sun azimuth is
fixed north-west, so the projection always runs screen south-east. Time of day
changes only length, softness, and visibility; the shader stretches only the
far side while the root side remains pinned to the object anchor.

The shadow is registered in the same shared depth stripe as its caster at
`DEPTH_CHANNEL_GROUND_SHADOW_OFFSET`, below trunk/body, foliage, and snow.
Consequently a northern tree's shadow is below every southern object's body
without a global fixed `z_index`, while the existing three-band ladder keeps
anchor rebases bounded.

Feet depth and physical height were originally treated as two separate axes,
because a scalar `z_index` cannot simultaneously express all three requirements:
a tree shadow must cover low grass/stone pixels, a tree body must cover that
shadow, and ordinary bodies must still sort by their feet.

Under the Shared RenderWorld Painter that cycle is resolved by the sort key, not
by a second pass. Every record — grass, tree, bush, rock, actor body and every
shadow — enters one global snapshot sorted by
`(feet_y, semantic_layer, stable_id)`. `semantic_layer` separates shadow from
body inside the same feet row, so a northern tree's shadow lands below every
southern body without a reserved z, a receiver mask or a CPU overlap test.

> **Retired (2026-08-11).** The former height-tier receiver pass —
> `WorldHeightShadowField`, its half-resolution `SubViewport`, its reserved
> Canvas visibility layer, `WorldHeightShadowProfile` and
> `world_height_shadow_profile.tres` — was removed together with its shader
> include and debug counter. Caster/receiver height tiers no longer exist.

### Procedural atlas, generator-first; palette is data

The tree silhouette/canopy atlas is produced by a **procedural generator tool**
(Variant D), exported as a committed PNG and preloaded at runtime — the same
authoring path as the grass tuft atlas. A discrete billboard does not need the
shader-procedural treatment that ground/mountain need (it is not tiled and not
derived from runtime tile topology), so a baked atlas is the correct runtime
form; the **procedural part is the authoring**. Palette, density, scale tiers,
tint range, wind response, and shadow params are **authored data**, not code
constants — the muted autumn tone that matches the dry-grass ground lives in the
material/profile, tunable without code.

## Data Model

Tree content rides the existing object placement and terrain-presentation data
models. Placement tuning is authored in
`data/world_objects/placement_groups/plains_trees.tres`
(`PlainsTreePlacementSettings`) and frozen into the per-save
`worldgen_settings.plains_trees` copy when a new world is created.

### World object definition

A `WorldObjectData` family for trees (registry-addressable, namespaced IDs),
e.g. `core:plains_tree`. `category = "flora"`, `biome_tags` includes `plains`,
and `presentation_profile_id` points at the tree presentation profile.
`WorldObjectData.blocks_movement` is not collision authority for the current
native packet path: loaded trunk collision derives from `object_kind == 4` and
`tree_collision_records`; registry metadata and `object_flags` do not gate it.
Localization keys (`FLORA_*`) are present when a player-facing name becomes
visible.

### Placement set

A `PlainsTreePlacementSettings` resource `core:plains_trees`: authored
`density`, scatter grid, optional per-chunk cap, spacing, edge padding, size
tiers, and the plains-grass placement mask threshold. The checked-in default is
`data/world_objects/placement_groups/plains_trees.tres`. Authored density
targets a **walkable** forest (open ground between trees) by default.

### Object packet extension

The compact native object packet (`world_object_placement_v0.md`) gains a tree
family value in `object_kind`. Trees reuse the existing presentation-oriented,
byte-packed fields (`object_local_x_px_q4`, `object_local_y_px_q4`,
`object_size_px`, `object_atlas_index`, `object_variant`, `object_flags`,
`object_tint`, `object_phase`). `object_size_px` is a byte (≤ 255 rendered px);
landmark trees exceeding it require either an authored scale multiplier on the
tree presentation profile or a packet extension — resolved in implementation and
recorded in `packet_schemas.md`.

### Presentation profile

A `WorldObjectPresentationData` for trees: tree atlas path, atlas region/grid,
optional normal/mask, batch material id (the tree batch shader), wind material
params, and a shadow profile id. Plus authored sampling params: density, scale
tiers (small / normal / hero fractions), per-instance tint range, wind response
(amplitude fraction, gust scale, lean cap), and shadow params (base foreshorten,
opacity).

### Tree atlas asset

```
assets/sprites/flora/atlases/plains_trees_atlas.png
```

Fixed frame grid (variants × rotations / poses), alpha background, **trunk base
anchored at a defined anchor point** per frame (frame metadata), produced by the
generator tool. Runtime preloads the PNG only; runtime atlas painting forbidden.

## Runtime Architecture

### Owners

| Concern | Owner |
|---|---|
| Tree placement compute | `WorldCore` (C++) |
| Tree object packet | `WorldCore`, alongside terrain + existing objects |
| Global snapshot apply + GPU lifecycle | `WorldRenderWorld` (fixed passes; no per-family `MultiMesh`) |
| Tree collision rectangles | `WorldObjectCollisionOwner`; `ChunkView` adopts the completed reveal/collision reference |
| **Painter order** | native `(feet_y, semantic_layer, stable_id)` inside the global sorted snapshot |
| Tree look + wind response | tree batch shader/material + authored profile |
| Wind state + globals write | `WindRuntime` (read-only consumer here) |
| Fixed sun azimuth | `WorldVisualLightingProfile` + layered asset bake contract |
| Time-varying shadow length/visibility | `TimeManager` progress read through `WorldVisualLightingProfile` |
| Directional shadow records | fixed `shadow` pass in `WorldRenderWorld`; the retired tall-caster receiver mask has no replacement |

### Placement flow (LAW 6)

`WorldCore` emits tree records in the per-chunk object packet (one packet per
chunk, byte-packed). No per-tile or per-object boundary calls. Placement is a
pure function of seed / version / chunk / settings / content set (LAW 3); it
reads deterministic world fields and terrain tags only, never scene/player/
runtime-diff state. For current worlds, the tree portion of `settings` is the
saved `worldgen_settings.plains_trees` copy packed into native
`settings_packed[22..43]`; load must not re-read the repository `.tres`.

### Presentation: records in the global sorted snapshot

`WorldRenderWorld` is the single GPU owner. Native tree records carry a
descriptor id and a variant/frame; they enter the global snapshot through the
fixed `body`, `shadow` and — where authored — `emissive`/`overhead` passes, and
are sorted by `(feet_y, semantic_layer, stable_id)` into absolute 1024 px render
pages. The instance transform carries rendered size and the compact per-instance
payload selects atlas frame / tint / wind phase / alpha through the render-class
LUTs. Trees hold **no** independent z, and adding a tree species changes data
only — no renderer source, shader sampler or `MultiMesh` is added per family.
`ChunkView` adopts only the completed collision reference. The tree is one
packed instance per object (LAW 13: no node-per-object).

> **Superseded (2026-08-11).** The per-stripe `MultiMeshInstance2D` batches
> built by the world-parented `WorldObjectPacketLayer`, the chunk-local stripe
> bucketing (`DEPTH_STRIPES_PER_CHUNK`) and the `update_mid_ladder_z(anchor)`
> three-band root are gone. `world_object_packet_layer.gd` survives only as a
> deprecated script-name bridge to `WorldObjectCollisionOwner` for isolated old
> tools; it owns no atlas, material, mesh, `MultiMesh` or GPU payload.

### Wind

The tree batch material reads the shared wind globals and animates vertices in
the shader (canopy sways, base planted). No per-frame CPU work touches trees; no
per-frame `set_shader_parameter` broadcast (the globals are written once by
`WindRuntime`).

### Shadow

Silhouette shadows are ordinary records of the fixed `shadow` pass, ordered by
the same painter tuple as the bodies; non-ground object shadows share one
`object_shadow_buffer`. Direction is the fixed south-east authored projection;
shared catalog uniforms update only length/opacity as time changes. There is no
per-object CPU geometry rebuild, no absolute cast-shadow z, no chunk-wide depth
walk, and no separate caster viewport or receiver mask.

### Diff refresh

When a chunk's authoritative tiles change (mining / diff apply), the chunk's
tree presentation buffer rebuilds through the same bounded decorative path.
Dirty unit: the chunk. The synchronous mutation call must not rebuild or upload
tree buffers.

### Failure policy (LAW 9)

If native tree placement is unavailable or returns malformed data, the layer
fails explicitly (error + no trees). No GDScript placement fallback, no silent
empty-buffer masking of a contract violation.

## Event Contracts

None in V0. The harvest iteration must update `event_contracts.md` if it adds
`world_object_harvested` / `world_object_removed`.

## Save / Persistence Contracts

Tree placements are immutable base output, recreated from seed +
`world_version` + `worldgen_settings.plains_trees` (LAW 5). New worlds read the
checked-in `.tres` once, then write the frozen tuning copy into `world.json`.
Current-version load requires `worldgen_settings.plains_trees` and does not
inject defaults from the repository resource. The harvest iteration persists
only runtime diff entries (removed / changed generated instances) keyed by
stable / deterministic instance identity, never display names or asset paths.

## Performance Class

- Placement solve: native `boot` / `background` packet generation.
- Presentation packing: native worker compute produces ready per-stripe buffers
  and flat trunk-collision descriptors from the same immutable object records.
- Presentation apply: bounded main-thread publish (per-chunk non-empty stripe
  buffers plus bounded collider slices) on the visual upload path. Since the
  accepted current tree proof includes blocking trunks, a chunk reveals only
  after its complete tree/small-rock presentation and matching chunk-scoped
  collision commit coherently; no object family is allowed to pop in after the
  reveal (LAW 10).
- Depth rebase: one linear-root `z_index` write per loaded tree batch owner plus
  only active nodes crossing a clamp boundary on each 16 px anchor step —
  O(loaded chunk owners), no 64-stripe walk and no buffer rebuild. Shadow,
  trunk, foliage, and snow migrate together as channels of the same stripe.
- Wind: O(1) global write per frame (shared), shader animates.
- Shadow: shader-uniform / bounded transform update per frame; no per-object
  rebuild. Height reception adds one half-resolution viewport pass over the
  already-batched visible tree shadow CanvasItems plus O(1) viewport transform
  synchronization; its CPU cost is independent of tree count.
- Target scale: a walkable forest across loaded chunks; authored per-chunk
  instance cap; importance-ordered buffers + zoom `visible_instance_count`
  trimming available later (as grass), no rebuild.
- Escalation path: lower authored density; native placement; per-stripe batch;
  shader animation.

## Modding / Extension Points

- New tree / bush / flora type = a new `WorldObjectData` + atlas + placement set
  entry. It inherits depth, wind, and shadow from the shared systems with **no
  new depth code** — the explicit scalability goal of this spec.
- A new object family adds one descriptor to
  `data/world_render/render_class_registry.json` plus its packed atlas channels;
  it does not add a renderer branch, a shader sampler, a `MultiMesh`, a
  project-wide z rule or an object-overlap loop.
- Look / density / palette tuning is authored data, not code constants. Plains
  tree density and spacing are tuned in
  `data/world_objects/placement_groups/plains_trees.tres`.
- A future biome adds its own tree presentation profile + placement set; native
  placement takes field params from authored data, not hardcoded plains numbers.

## Acceptance Criteria

V0 is acceptable when:

- **Depth is on the shared ladder, not the object** (the core criterion):
  - a render probe at a fixed scene shows grass in front of a trunk covering
    **only the trunk base**, never the whole tree, and trees never wholly
    disappear under grass;
  - **moving the player** north/south does **not** flip whole trees above/below
    grass (the sketch bug is gone) — verified by a before/after panel at two
    player positions;
- the shared player/grass ladder retains the player's visual-feet anchor. The
  tree root is the southern edge of its rectangular trunk footprint, and its
  scaled depth is at least 34 pixels: the 18-pixel visual-feet-to-collider
  clearance plus one full 16-pixel depth stripe;
- at rear collision contact every one of the eight production tree variants
  strictly renders above the player, including depth-stripe boundary phases;
  at southern collision contact the player strictly renders above the trunk;
- the per-variant
  `meta.json.collision_footprint { offset_x_px, width_px, depth_px }`
  aligns the collider with the visible trunk base. Offset and dimensions use
  the same fixed visual scale, and do not change with packet size tier;
  - a northern tree shadow renders below a southern tree/bush/rock body; within
    one stripe the strict order is shadow → body/trunk → foliage → snow;
  - the same shadow visibly darkens overlapping grass tufts and small-rock
    albedo/snow because their receiver height is below the tree caster height;
    it does not stamp across another tree body;
  - static check: no per-tree `z_index` assignment, no baked grass fringe in the
    atlas pipeline, no absolute cast-shadow z outside the shared ladder, no
    GDScript per-frame tree-z loop;
- trees are emitted from the **native object packet**, not a GDScript scatter
  loop, and rendered as **per-stripe `MultiMeshInstance2D` batches**, not one
  node per tree (static check);
- placement is identical for identical seed / version / chunk / settings /
  content set (re-run probe);
- the tree atlas is a checked-in PNG produced by the generator tool; no runtime
  atlas painting;
- canopies sway on the shared wind (strength 0 freezes sway; pause stops it);
  the runtime contains no per-frame wind broadcast for trees;
- shadows always fall screen south-east; setting the hour changes length,
  softness, and visibility but never direction, and the root stays planted;
- tree visuals and loaded trunk collision remain one coherent transaction; the
  visual layer may not be removed independently while claiming unchanged
  collision/gameplay semantics;
- `res://scenes/dev/tree_collision_depth_dev_scene.tscn` shows all eight current
  `rust_crown` variants through the production native buffer path, with exact
  highlighted tree/player collision and every player reset behind its tree.

## Failure Cases / Risks

This design is wrong if:

- any tree carries its own `z_index` or a baked occlusion appears in the atlas;
- a tree-specific z layer is placed wholesale above/below grass instead of
  interleaved on the ladder;
- tree placement appears in a GDScript loop or as one node per tree;
- the shared wind gets a second writer or a per-tree broadcast path returns;
- any runtime consumer rotates a sun shadow away from screen south-east, or
  stretches the root side away from the object anchor;
- tree preparation runs synchronously on the main thread, or a tree-bearing
  chunk reveals before its matching trunk collision is committed;
- VRAM/buffer growth: dense-chunk tree buffer must stay within the authored cap.

## Open Questions

- Final `object_size_px` handling for landmark trees (authored scale multiplier
  vs packet extension)?
- fade-on-overlap: when a tall tree covers the player, fade it to a bounded
  transparency (data/shader, deterministic by overlap test) — adopt in V0 or
  defer to a polish iteration? (Default: defer.)
- Does the canopy ever need true split-depth (base in ladder, crown above) for
  very large hero trees, or is feet-stripe sorting sufficient at all sizes?
  (Default: feet-stripe sufficient; revisit only if a probe shows a real
  artifact.)
- Future collision broadphase representation beyond the current accepted
  chunk-scoped trunk shape owners (for example a native aggregate) remains open;
  the current visual/collision identity and coherent reveal rule are not open.

## Implementation Iterations

### Iteration 0 — Spec landing

- This spec lands as draft; both doc indexes link it.
- No runtime changes.

### Iteration 1 — Generator tool + tree atlas

- Move the procedural tree generator into a Godot tool/export path; commit the
  PNG atlas with frame anchor metadata.
- Authored presentation profile / material / shader-family resources (muted
  palette, scale tiers, wind, shadow params as data).
- No placement yet; a tool-scene render proof of the atlas.

### Iteration 2 — Native placement + per-stripe batch on the ladder

> **Delivered, then superseded (2026-08-11).** Native placement stands; the
> per-stripe batch/ladder presentation was replaced by the Shared RenderWorld
> Painter. Kept as implementation history.

- Add the tree `object_kind` to native object placement (LAW 3/6); bump
  `world_version` (canonical placement output changes — LAW 4).
- World-parented `WorldObjectPacketLayer`: per-stripe batches interleaved with
  grass, z and lifecycle owned by `WorldStreamer`; `ChunkView` adopts by reference.
- Wind material + shared globals; fixed-azimuth, time-stretched silhouette
  shadow channel on the shared ladder.
- Render probes: the depth acceptance criteria (grass-covers-base, player sort,
  no flip on movement), density/seam/zoom series, wind freeze, shadow vs hour.
- Doc updates in the same task: `packet_schemas.md` (tree packet value + any
  `object_size_px` extension), `world_object_placement_v0.md` cross-reference,
  `world_version` bump note.

### Iteration 2a — Placement profile resource

- `core/resources/plains_tree_placement_settings.gd` owns the save shape and
  native packed layout for plains tree placement settings.
- `data/world_objects/placement_groups/plains_trees.tres` is the checked-in
  authoring source for new worlds.
- `WorldStreamer` freezes the profile into
  `worldgen_settings.plains_trees`; native `WorldCore` reads packed indices
  `22..43`.
- `WorldRuntimeConstants.WORLD_VERSION` advances to `60` because same seed /
  version / settings can now intentionally produce different tree placement
  when the authored profile changes before new-world creation.

### Iteration 3 — Collision + tuning

- Chunk-scoped static collision at the trunk base (large-rock proof pattern),
  reveal-ready (LAW 10). Each variant authors
  `collision_footprint { offset_x_px, width_px, depth_px }`; native
  scales it into one `RectangleShape2D` whose southern edge ends at the tree
  root. A 34-pixel runtime minimum guarantees collision-relative rear ordering
  while preserving the existing grass-safe visual-feet player anchor.
- Eight-variant collision/depth lab scene plus native contract and scene smoke
  tests.
- Density / palette / scale / wind / shadow tuning via authored data + probes.
- Optional importance-ordered buffers + zoom `visible_instance_count` trimming.

### Iteration 4 — Harvest (separate contract)

- Command-backed chopping → wood; runtime diff + save/load; domain event.
- Required doc updates: `commands.md`, `event_contracts.md`,
  `packet_schemas.md` + `save_and_persistence.md` for the diff shape.

## Required Updates

- `docs/README.md` and `docs/02_system_specs/README.md`: link this spec (done
  with spec landing).
- `packet_schemas.md`: updated for the tree packet family,
  `worldgen_settings.plains_trees`, and the authored rectangular collision
  footprint record.
- `world_object_placement_v0.md`: cross-reference this spec for the tree family
  (Iteration 2) and document the collision-relative depth invariant.
- `world_version` (`WorldRuntimeConstants.WORLD_VERSION`): bumped to `60` for
  the data-driven tree placement profile.
- `system_api.md`: updated for the optional new-world tree profile argument,
  settings resource, and stride-`4` rectangular collision result.
- `save_and_persistence.md`: updated for frozen per-save tree settings.
- `event_contracts.md`, `commands.md`: required at the harvest iteration
  (Iteration 4), not before; recheck at each iteration.
