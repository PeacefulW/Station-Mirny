---
title: Plains Trees Presentation and Depth Layering V0
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.4
last_updated: 2026-07-13
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

> **Tree ↔ grass ↔ player depth is owned by the existing shared mid-layer
> depth ladder. It is never a per-object hardcoded `z_index`, never a baked
> grass overlay, and never a tree-specific layer placed above or below grass.**

This spec rides `world_object_placement_v0.md` (placement, batching, depth
ladder) and `wind_and_grass_scatter_presentation.md` (wind, the per-stripe
mid-layer ladder) instead of inventing a parallel system. It establishes the
procedural tree atlas authoring path, the batched per-stripe presentation, wind
response, and fixed-direction physical shadows. Collision and harvest are deferred.

### Why this spec exists

A throwaway visual sketch proved the **look** (procedural generator, muted
autumn palette, smooth continuous trunk, physical shadows, wind sway). But the
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
- physical shadows keep the selected fixed east-south-east direction while only
  visibility and far-end length change with time of day;
- adding a new tree / bush / flora type later requires only **data + an atlas**,
  never new depth code.

## Scope (V0)

- `plains` biome only; surface layer (`z = 0` gameplay plane).
- Trees as a new **world-object family** in the native object packet
  (`object_kind` tree value), placed deterministically (LAW 3).
- A **procedural tree atlas** exported by a generator tool (Variant D path,
  like the grass tuft atlas), committed as a PNG, runtime-preloaded only.
- **Batched per-stripe `MultiMeshInstance2D`** presentation on the shared
  player-relative mid-layer depth ladder; one tree is one instance bucketed by
  its **base (feet) stripe**, interleaved with the grass scatter stripes.
- **z ownership stays with `WorldStreamer`** (the existing `_ladder_anchor_stripe`
  + `update_mid_ladder_z` re-assignment). Trees carry no independent z.
- **Wind** response: the shared wind global uniforms drive a tree wind material
  (canopy sways, base planted), no new wind owner.
- **Fixed-direction physical cast shadow**: visible above-ground GLB geometry is
  baked with the selected screen `10:00` Sun and the cast shadow at
  east-south-east. Runtime reads the
  authored direction/contact lock from metadata and uses the canonical sun
  model only for visibility and length, as a derived layer below grass.
- **Deterministic per-instance variation** (atlas variant, scale tier, tint,
  wind phase) from a hash of seed / chunk / tile (no `randf` — LAW: deterministic
  hashing).
- **Density / palette / scale tiers as authored data** (muted, walkable forest).

## Out of Scope (V0)

- **Collision / `blocks_movement`** (tree as obstacle). Deferred: blocking cells
  must be reveal-ready (LAW 10); when added, it follows the loaded large-rock
  collision proof from `world_object_placement_v0.md` (chunk-scoped static shape
  owners), not one body per tree.
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
| Canonical world data, runtime overlay, or visual only? | Tree **placement** is canonical immutable base output (LAW 5), deterministic (LAW 3). Tree **presentation** (sprites, depth z, wind, shadow) is visual only, derived. |
| Save/load required? | No in V0 (placement is derived from seed+version; presentation is derived). Harvest iteration adds a runtime diff. |
| Deterministic? | Placement: yes — pure function of seed, version, chunk, settings, content set. Wind/shadow animation: intentionally non-deterministic visual drift, never read by gameplay. |
| Must it work on unloaded chunks? | Placement derivable for any chunk on demand. Presentation buffers exist only for loaded chunk views. |
| C++ compute or main-thread apply? | Placement solve and packet build in C++ (`WorldCore`). Main thread only applies finished per-stripe buffers and writes plain `z_index` on stripe nodes. |
| Dirty unit | One chunk's tree presentation buffer (rebuild on diff, like grass). Depth re-assignment dirty unit: the ladder anchor change → plain z writes on existing stripe nodes (no buffer rebuild). |
| Single owner | Placement: `WorldCore`. Presentation apply + lifecycle: `ChunkView`. Ladder anchor + z assignment: `WorldStreamer`. Wind state: `WindRuntime` (read-only consumer). |
| 10x / 100x scale path | More trees stay in per-stripe batch buffers (no per-instance calls). More object types share the **one** ladder (no per-type depth code). |
| Main-thread blocking risk | Bounded per-chunk buffer apply through the existing decorative visual upload path; z re-assignment is plain `z_index` writes on existing nodes. |
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
owns the anchor (`_ladder_anchor_stripe`) and re-assigns z on every chunk's
stripe nodes (`update_mid_ladder_z`) when the player's feet stripe changes
(plain `z_index` writes, no buffer rebuild).

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

### Fixed physical shadow, root-pinned and stretch-only

The cast shadow is the complete physical Cycles shadow baked from all visible
above-ground GLB geometry under the selected screen `10:00` Sun. Every tree is
normalized with `root_embed_fraction: 0.07`, then the production bake performs a
deterministic `physical_mesh_bisect` at ground `Z=0` before every pass. Buried
root geometry is absent from both the visible sprite and shadow caster, while
every visible root surface remains a physical caster. Its screen direction is
fixed east-south-east at `[0.866025, 0.5]`. A low opposite shadowless Spot with
energy `100` is an offline albedo-bake aid only and does not contribute to the
physical shadow pass. Runtime
reads `fixed_shadow_direction_vector_screen` and
`shadow_contact_lock_source_px` from asset metadata, keeps the tree anchor and
the first `48 px` of the shadow invariant, and stretches only the farther end
from `get_shadow_length_factor()`. The derived layer remains **below** the grass
stripes so grass can overdraw it on the ground. Runtime never rebuilds shadow
geometry per object, rotates the shadow through the day, erases visible root
casters, or adds a synthetic contact silhouette.

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
`presentation_profile_id` points at the tree presentation profile,
`blocks_movement = false` in V0 (collision deferred). Localization keys present
(`FLORA_*`) when a player-facing name becomes visible.

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
| Per-stripe batch apply + layer lifecycle | `ChunkView` tree decor layer |
| Mid-layer **depth ladder anchor + z assignment** | `WorldStreamer` (`_ladder_anchor_stripe`, `update_mid_ladder_z`) |
| Tree look + wind response | tree batch shader/material + authored profile |
| Wind state + globals write | `WindRuntime` (read-only consumer here) |
| Sun model (shadow visibility + length) | `TimeManager` (read-only consumer here) |

### Placement flow (LAW 6)

`WorldCore` emits tree records in the per-chunk object packet (one packet per
chunk, byte-packed). No per-tile or per-object boundary calls. Placement is a
pure function of seed / version / chunk / settings / content set (LAW 3); it
reads deterministic world fields and terrain tags only, never scene/player/
runtime-diff state. For current worlds, the tree portion of `settings` is the
saved `worldgen_settings.plains_trees` copy packed into native
`settings_packed[22..43]`; load must not re-read the repository `.tres`.

### Presentation: per-stripe batch on the shared ladder

`ChunkView` consumes the native tree records and builds bounded **per-stripe**
`MultiMeshInstance2D` batches, the tree base bucketed into its chunk-local
stripe (`DEPTH_STRIPES_PER_CHUNK`), interleaved with the grass scatter stripe
nodes. The instance transform carries the rendered size and the per-instance
color packs atlas frame / tint / wind phase / alpha (existing decor convention).
`WorldStreamer` assigns and re-assigns these stripe nodes' `z_index` through the
same `update_mid_ladder_z(anchor)` path it uses for grass — trees hold **no**
independent z. The tree is one batched instance per object (LAW 13: no
node-per-object).

### Wind

The tree batch material reads the shared wind globals and animates vertices in
the shader (canopy sways, base planted). No per-frame CPU work touches trees; no
per-frame `set_shader_parameter` broadcast (the globals are written once by
`WindRuntime`).

### Shadow

A derived physical-shadow layer renders below the grass stripes
(`Z_GRASS_SHADOW` neighborhood). Direction and the root contact lock come from
the v2 tree metadata; the canonical sun supplies only opacity and length. A
bounded transform update stretches the far polygon while the root-side polygon
stays fixed. There is no per-object CPU geometry rebuild.

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
- Presentation apply: bounded main-thread publish (per-chunk per-stripe buffer)
  on the decorative visual upload path; trees never block chunk reveal (LAW 10 —
  cosmetic-later, since V0 trees are non-blocking).
- Depth re-assignment: plain `z_index` writes on existing stripe nodes when the
  ladder anchor changes — O(loaded stripe nodes), no buffer rebuild.
- Wind: O(1) global write per frame (shared), shader animates.
- Shadow: bounded transform update of existing polygons; metadata-fixed
  direction and contact zone, no per-object rebuild.
- Target scale: a walkable forest across loaded chunks; authored per-chunk
  instance cap; importance-ordered buffers + zoom `visible_instance_count`
  trimming available later (as grass), no rebuild.
- Escalation path: lower authored density; native placement; per-stripe batch;
  shader animation.

## Modding / Extension Points

- New tree / bush / flora type = a new `WorldObjectData` + atlas + placement set
  entry. It inherits depth, wind, and shadow from the shared systems with **no
  new depth code** — the explicit scalability goal of this spec.
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
  - the player sorts in front of / behind trees by feet stripe;
  - static check: no per-tree `z_index` assignment, no baked grass fringe in the
    atlas pipeline, no tree z layer outside the shared ladder, no GDScript
    per-frame tree-z loop;
- trees are emitted from the **native object packet**, not a GDScript scatter
  loop, and rendered as **per-stripe `MultiMeshInstance2D` batches**, not one
  node per tree (static check);
- placement is identical for identical seed / version / chunk / settings /
  content set (re-run probe);
- the tree atlas is a checked-in PNG produced by the generator tool; no runtime
  atlas painting;
- canopies sway on the shared wind (strength 0 freezes sway; pause stops it);
  the runtime contains no per-frame wind broadcast for trees;
- shadows fall in the fixed **east-south-east** direction; setting the hour changes
  only opacity/far-end length, while the tree anchor and first `48 px` remain
  invariant;
- removing the tree layer entirely leaves gameplay, saves, grass, and other
  systems untouched.

## Failure Cases / Risks

This design is wrong if:

- any tree carries its own `z_index` or a baked occlusion appears in the atlas;
- a tree-specific z layer is placed wholesale above/below grass instead of
  interleaved on the ladder;
- tree placement appears in a GDScript loop or as one node per tree;
- the shared wind gets a second writer or a per-tree broadcast path returns;
- the shadow rotates away from the metadata-authored east-south-east direction or
  the root/contact zone moves while length changes;
- tree buffers block first chunk reveal or rebuild during interactive input;
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
- Tree collision model (V-next): chunk-scoped static shape owners at the trunk
  base only, following the large-rock proof.

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

- Add the tree `object_kind` to native object placement (LAW 3/6); bump
  `world_version` (canonical placement output changes — LAW 4).
- `ChunkView` tree decor layer: per-stripe batches interleaved with grass,
  z owned by `WorldStreamer` via `update_mid_ladder_z`.
- Wind material + shared globals; fixed east-south-east physical shadow layer.
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

### Iteration 3 — Collision (optional) + tuning

- Optional chunk-scoped static collision at the trunk base (large-rock proof
  pattern), reveal-ready (LAW 10).
- Density / palette / scale / wind / shadow tuning via authored data + probes.
- Optional importance-ordered buffers + zoom `visible_instance_count` trimming.

### Iteration 4 — Harvest (separate contract)

- Command-backed chopping → wood; runtime diff + save/load; domain event.
- Required doc updates: `commands.md`, `event_contracts.md`,
  `packet_schemas.md` + `save_and_persistence.md` for the diff shape.

## Required Updates

- `docs/README.md` and `docs/02_system_specs/README.md`: link this spec (done
  with spec landing).
- `packet_schemas.md`: updated for the tree packet family and
  `worldgen_settings.plains_trees`.
- `world_object_placement_v0.md`: cross-reference this spec for the tree family
  (Iteration 2).
- `world_version` (`WorldRuntimeConstants.WORLD_VERSION`): bumped to `60` for
  the data-driven tree placement profile.
- `system_api.md`: updated for the optional new-world tree profile argument and
  settings resource.
- `save_and_persistence.md`: updated for frozen per-save tree settings.
- `event_contracts.md`, `commands.md`: required at the harvest iteration
  (Iteration 4), not before; recheck at each iteration.
