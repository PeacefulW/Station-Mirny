---
title: World Runtime V0
doc_type: system_spec
status: approved
owner: engineering
source_of_truth: true
version: 2.4
last_updated: 2026-07-29
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../meta/save_and_persistence.md
  - world_grid_rebuild_foundation.md
  - world_object_placement_v0.md
---

# World Runtime V0

## Purpose

Define the smallest working vertical slice of the rebuilt world runtime.

This spec does not authorize water generation, multiple biomes, decor streaming, or other
future systems. Its only job is to prove that the new chunked runtime works
end-to-end without architectural cheating.

## Gameplay Goal

The player must be able to:
- move across chunk boundaries without visible world breakage
- see deterministic chunks stream in and out from `world_seed + chunk_coord + world_version`
- modify one local terrain tile
- save and reload that one tile diff correctly on top of regenerated base terrain

## Scope

V0 includes only:
- surface layer only (`z = 0`)
- one canonical base biome only: `plains`
- one minimal deterministic base terrain palette for plains, including only the
  tile kinds required for walkability plus one single-tile mutation proof
- one compact `ChunkPacketV0`
- one native packet batch entrypoint:
  `WorldCore.generate_chunk_packets_batch(seed, coords, world_version, settings_packed)`
- one GDScript streamer/orchestrator
- one symmetric ring streaming policy with simple distance ordering
- one `ChunkView` root per visible chunk
- one `TileMapLayer` path for gameplay-critical terrain cells
- one runtime diff store for tile overrides only
- one save/load path for changed chunk diffs only
- integration with existing `FrameBudgetDispatcher`, `EventBus`, `SaveManager`,
  and the current `chunk_manager` compatibility expectations in gameplay code

## Out of Scope

V0 explicitly does not include:
- water generation
- mountain gameplay rules beyond the active visual-only mountain presentation
  bridge documented below
- multiple biomes
- climate data
- biome blend logic
- placements
- decor
- foliage batching
- resource spot streaming beyond the single mutation proof
- environment overlay
- seasons, snow, ice, weather
- subsurface
- Z-level linking
- connector requests
- forward lobe / velocity-biased streaming
- hidden preload experiments
- general-purpose or unbounded node reuse pools; the narrow bounded
  object-presentation envelope pool is authorized by the amendment below
- a broad native framework or multi-class native API

### Narrow Visual Object Presentation Amendment

`World Object Placement V0` authorizes one narrow exception to the original
decor/placement exclusion: a `plains`-only generated object presentation layer
scheduled and retained by `WorldStreamer` through `WorldObjectPacketLayer`.
`ChunkView` adopts the completed layer by reference for atomic reveal, including
chunk-scoped trunk collision derived for current tree records.

This amendment does not add gameplay placements to `ChunkPacketV0`, harvesting,
resource yield, save diffs, commands, events, or non-`plains` biome placement.
It does authorize additive visual object fields in `ChunkPacketV0` for accepted
flora, trees, and visual-only small rock proofs. The visual layer is derived
presentation from the already loaded chunk packet and must remain bounded by
chunk-level batches, sparse layered object roots, and shader uniforms, not CPU
draw operations per object.

Chunk reveal is coherent for the current layered object families: tree channel
batches, small-rock channel batches, and tree trunk shape owners are staged
incrementally while hidden, then enabled in one main-thread commit. Empty depth
buckets are skipped without consuming an upload slice; visible asset pop-in is
not an accepted substitute for a shorter queue. Prepared tree shapes remain on
collision layer `0` until the owning chunk itself becomes visible, because
Canvas visibility does not disable physics.

The object upload lane is completion-biased. Reveal-frontier/live transactions
always precede source-padding prestage, and the selected atomic transaction
keeps the lane until `COMPLETE` unless a higher urgency class or genuinely
closer same-class reveal deadline arrives. Within an urgency class, wrapped
squared chunk distance from the player orders the current player-centered
viewport from its central coverage outward; enqueue turn is the stable tie
breaker. Enqueue detects that preemption in
O(1); equal/lower priority dirtiness waits for the focused transaction instead
of repeatedly rescanning and starving uploads. The unique-token visual queue is
hard-capped to the current plus outgoing source windows, removes tokens through
an O(1) swap index, and refreshes its bounded priority snapshot incrementally in
a standalone callback. Worker completion only enqueues a lightweight prestage envelope;
hidden `Node`/RenderingServer allocation is created one transaction at a time
inside the separately budgeted object presentation job. Incomplete hidden work
is discarded immediately after it leaves source demand. A bounded GPU-resident
hot cache complements (but does not replace) the packed CPU warm cache: a
completed layer can survive temporary zoom/radius eviction and return with zero
raw `MultiMesh.buffer` uploads. Promoted layers stay on the world presentation
root and `ChunkView` owns their reveal/collision state by reference, avoiding a
reveal-frame CanvasItem reparent while preserving identical world transforms.
The dispatcher never performs raw apply and reveal in one callback: one APPLY
phase may consume several predictively bounded sub-slices, then a
later FINALIZE phase adopts the completed world-parented layer and releases
visibility plus collision atomically. Safe homogeneous phases may keep the
dispatcher job active in the same process frame only while the lane's measured
elapsed time plus a phase-specific conservative lookahead fits its `0.75 ms`
budget. This continuation is limited to an incomplete bounded priority scan,
incremental begin work that touches no Nodes/GPU/colliders, warmed APPLY slices
whose phase hint remains unchanged, and explicitly measured allocation-only
reservation described below. Upload-to-collider/family/retire/commit transitions
are process-frame boundaries. Priority
selection commit, cold envelope construction, depth-anchor rebase,
COMPLETE/cache commit, and FINALIZE always yield; a hard callback cap also
protects zero-resolution timer cases. The
process-frame reveal guard prevents both a repeated object callback and the
mountain visual job from bypassing the APPLY-to-FINALIZE boundary later in the
same frame. A small bounded boot/recycle pool owns first-use family envelopes and
their first stripe resources outside the moving-player deadline. Every envelope
also prepares the fixed depth-band roots and optional living contact-shadow
graph. After the boot pool is exhausted, the cold transaction persists across
explicit callbacks: bare shell, tree fixed bands, rock fixed bands, optional
flora fixed graphs, collision owner, then incremental family begin. Before raw
apply, every enabled tree, living-flora, spiky-flora, or rock family counts its
non-empty worker buckets and reserves missing per-stripe draw capacity through
an explicit allocation-only API. The first cold allocation of each family
always yields. Later allocations of that same family may request one additional
dispatcher callback only when its monotonic per-family measured high-water plus
`25% + 25 us` safety margin keeps the allocation lane within `0.65 ms`; at most
two allocation-only callbacks may run in one process frame. A high outlier
raises the session high-water and stops continuation. Allocation never advances
the staged cursor, and the first packed visual/shadow upload always waits for a
later process frame. The latest depth-ladder anchor is
rebased once after `COMPLETE` in its own callback before adoption/reveal, so a
moving player cannot combine a band migration with raw upload or cause hidden
staging to chase every anchor stripe.
An incomplete presentation that is the only reveal transaction for a live hidden
chunk is counted as transient visible-ring working set, not reusable hot-cache
residency. Trimming skips it instead of evicting and recursively restaging the
same reservation; after `COMPLETE`, promotion or normal eviction restores the
configured residency cap. Cached worker payloads remain immutable across this
lifecycle: recycle drops packed-array aliases and never clears the source arrays.
Committed residency weights count all retained CanvasItem owners and release
inactive dense `MultiMesh` buffers after sparse reuse before recording exact GPU
bytes. Active, retiring, and pooled graphs all participate in the same
conservative residency totals. Eviction only enqueues retirement; a separate
lane performs exactly one visual-slot/collider/reset/pool-shrink operation per
callback and never chains the next operation. Source-only prestage retains its
token under retirement or budget pressure and retries autonomously, while live
reveal work bypasses that admission backpressure. Only fully cleaned layers may
enter the bounded pool, whose overflow shrinks one resource at a time.

Layered visual batches use `QuadMesh`, whose primitive V axis is opposite the
PNG/Canvas top-left convention. Every layered trunk/foliage/albedo/snow shader
must convert `UV.y` exactly once before atlas, mask, wind, and top-factor
sampling. The custom projected-shadow mesh already owns Canvas-oriented UVs and
must not receive that conversion. This is a visual identity contract, not LOD.

Layered tree/rock materials belong to the boot-prepared shared asset catalog,
not to individual chunks. A sun-state change updates those shared shader
uniforms once in `WorldStreamer`; chunk iteration is reserved for legacy or
truly chunk-owned materials. Catalog setters are idempotent so a repeated
identical state cannot multiply RenderingServer writes by the loaded view count.
Pooled/cold batch layers read the current catalog season and sun values when
configured; their compatibility setters update only local visibility/state and
must never write shared catalog uniforms.

Every layered object cast shadow is registered in the caster's own feet stripe
at `DEPTH_CHANNEL_GROUND_SHADOW_OFFSET`. The object's base, overlay, and top
overlay occupy the following shared depth channels. No layered family may use
an absolute cast-shadow z-index: a northern caster's shadow must remain below
the body of an object in the same or any more southern stripe.

Tall-caster shadow reception is an orthogonal material-height contract, not
another z ladder. Tree shadow CanvasItems also opt into the reserved
`WorldHeightShadowProfile.CASTER_VISIBILITY_LAYER`; `WorldHeightShadowField`
renders only that layer through a half-resolution `SubViewport` sharing the
current `World2D` and camera canvas transform. Grass and small-rock shared
materials sample its alpha through `SCREEN_UV` and receive it only when
`caster_height > receiver_height`. Tree/bush/player materials are not
receivers. Heights, receiver strengths, tint, and render scale are authored in
`data/world_objects/presentation_profiles/world_height_shadow_profile.tres`.
The pass is viewport-bounded, reuses existing MultiMeshes/materials, does no
per-instance CPU work, and leaves canonical packets, worldgen, gameplay,
collision, and saves unchanged.

Only approved tree trunks expose collision in the current proof. Their collision
must be chunk-scoped through one `StaticBody2D` with shape owners per loaded
chunk layer, derived from the same deterministic visual size as the rendered
object, and not saved as authoritative world state. Accepted dense object
collision for mod-scale content must stay in the native packet-backed object
placement path before it becomes production gameplay.

The amendment also allows a narrow visual-only animated flora proof. This flora
is emitted as native object packet records, must be batched, must use one fixed
south/front-facing atlas row, must animate through shader atlas-frame selection,
and must not add collision, harvesting, save identity, commands, events, or
authoritative placement state.

The amendment also allows a narrow visual-only static spiky flora proof. This
flora is emitted as native object packet records using the same orange biofield
organic field as the chunk overlay, must use batched atlas presentation with a
fixed front/top baked-shadow frame, and must not add collision, harvesting, save
identity, commands, events, or authoritative placement state.

The amendment also allows a narrow small static biofield flora proof in the
spiky flora family. It is emitted as native object packet records with spiky
flora atlas index `1`, must pass the deterministic orange biofield mask before
placement, and must not add collision, harvesting, save identity, commands,
events, or per-object scene nodes.

The amendment also allows replacement visual-only small rocks as
`object_kind == 7`. They are emitted as native object packet records from the
shared plains grass field transition, use deterministic layered Blender-baked
asset directories selected by `object_variant`, expose no collision, use no
wind mask, and stretch their baked sun shadow at low sun using the same fixed
direction rule as layered trees.

## Law 0 Classification

| Question | V0 answer |
|---|---|
| Canonical or runtime? | Base chunk terrain is canonical; tile overrides are runtime diff; `ChunkView` is presentation only |
| Save/load required? | Yes, for per-chunk tile overrides only |
| Deterministic? | Yes, base packet is pure `f(seed, coord, world_version)` |
| Must work on unloaded chunks? | Yes, diff store remains authoritative when a chunk is not loaded |
| C++ compute or main-thread apply? | Canonical generation and transient object/grass buffer packing in C++ workers; bounded scene/GPU/physics apply on the main thread only |
| Dirty unit | `16 x 16` chunk for generation, one tile for authoritative mutation, one chunk object packet for visual object placement, bounded local visual patch for adjacency-dependent terrain presentation, bounded cell batches for publish |
| Single owner | `WorldCore` owns canonical base output; `WorldDiffStore` owns persisted overrides; `WorldStreamer` owns streaming/presentation scheduling, caches, pool, and retirement; `ChunkView` owns chunk terrain and the adopted reveal/collision reference |
| 10x / 100x scale path | More chunks increase queued packet generation and sliced publish work; they do not expand the interactive mutation path |
| Main-thread blocking risk | Allowed only for bounded apply slices; heavy generation stays off-thread |
| Hidden GDScript fallback? | Forbidden; native world core is required |
| Could it become heavy later? | Yes; V0 already keeps generation in native code and publish sliced |
| Whole-world prepass? | Forbidden; V0 is local chunk generation only |

## Core Contract

### Chunk Geometry

- one world tile = `64 px`
- one chunk = `16 x 16` tiles
- chunk-local cell coordinates are `0..15` on each axis
- world X wrap follows ADR-0002
- world Y does not wrap

### ChunkPacketV0

`ChunkPacketV0` is the only hot-path native-to-script boundary for chunk data.

Required fields:

| Field | Type | Notes |
|---|---|---|
| `chunk_coord` | `Vector2i` | canonical chunk coordinate |
| `world_seed` | `int` | copied into the packet for validation/debug |
| `world_version` | `int` | first V0 runtime value starts at `1`; current active contract is `63` |
| `terrain_ids` | `PackedInt32Array` | length `256`, one terrain id per local tile |
| `terrain_atlas_indices` | `PackedInt32Array` | length `256`, derived presentation atlas index per local tile |
| `walkable_flags` | `PackedByteArray` | length `256`, `1 = walkable`, `0 = blocked` |

Approved additive visual object fields:

| Field | Type | Notes |
|---|---|---|
| `object_kind` | `PackedByteArray` | V0 family id: `2` living flora, `3` spiky flora, `4` tree, `7` small rock; historical ids `1`, `5`, and `6` are not emitted in current packets |
| `object_local_x_px_q4` | `PackedByteArray` | chunk-local pixel X quantized to `4 px` |
| `object_local_y_px_q4` | `PackedByteArray` | chunk-local pixel Y quantized to `4 px` |
| `object_size_px` | `PackedByteArray` | rendered sprite size in pixels |
| `object_atlas_index` | `PackedByteArray` | prepared atlas bank index for the family; spiky flora index `1` is the small static brown seaweed biofield object; tree and small rock use index `0` |
| `object_variant` | `PackedByteArray` | atlas frame / animation view variant; small rock selects the layered asset directory |
| `object_flags` | `PackedByteArray` | reserved; current packets write `0`. Tree collision derives from `object_kind == 4`/native tree collision records, never from bit `0`; small rocks have none |
| `object_tint` | `PackedByteArray` | `0..255` presentation tint scalar |
| `object_phase` | `PackedByteArray` | `0..255` deterministic animation phase |

All visual object arrays must have identical length and are immutable generated
presentation records. Loaded tree-trunk collision derives from current
`object_kind == 4` records, not from `object_flags`; the arrays are not saved as
gameplay object state.

`terrain_atlas_indices` rules:
- it is derived presentation metadata, not authoritative terrain state
- it may be computed in native code for base packets
- runtime diff save files do not persist it
- loaded mutation paths may recompute only a bounded local visual patch instead
  of republishing a full chunk
- plains ground uses solid atlas variants only

Forbidden packet fields in V0:
- climate bytes
- water-generation masks
- mountain masks
- biome blend data
- gameplay placement identity beyond the approved visual object packet
- precomputed decor batch buffers
- connector requests
- seasonal or weather state

`ObjectPresentationBufferResult` is not a packet field. It is a transient,
revision-tagged worker result derived from the approved `object_*` arrays and is
documented separately in `meta/packet_schemas.md`. Keeping it outside
`ChunkPacketV1` preserves the canonical native packet boundary above.
The worker result contains ready raw stripe buffers for living flora, both
spiky-flora atlas banks, trees, and small rocks plus derived living shadows and
tree collision descriptors. Runtime publication validates and incrementally
stages all of them before the owning chunk is revealed; it never rescans the
packet to rebuild flora on the main thread.
The worker receives enable flags derived from actually prepared flora sources.
Known living/spiky records are suppressed with zero presentation payload when
their sources are disabled, so canonical placement may stay stable without
changing current visuals or blocking chunk reveal.

### Terrain Palette

V0 keeps the terrain palette intentionally tiny:
- one plains walkable ground tile class; presentation may use derived atlas indices
- one plains modified-result tile class if the mutation proof needs a distinct
  post-dig state

This does not authorize broader biome or terrain taxonomy work.

## Runtime Architecture

### Native Boundary

V0 uses one native class only:

```text
WorldCore.generate_chunk_packets_batch(
    seed: int,
    coords: PackedVector2Array,
    world_version: int,
    settings_packed: PackedFloat32Array
) -> Array
```

Rules:
- the method is synchronous
- `WorldStreamer` owns async scheduling by calling it from worker tasks
- one batch request returns one packet per input coord, in input order
- no per-tile callbacks
- the live runtime uses one native packet boundary only; no single-chunk helper
  API remains

The same native class also exposes narrow synchronous pure-compute presentation
helpers such as `build_object_presentation_buffers(...)`. They are invoked only
on worker-local `WorldCore` instances. They do not generate placement truth,
touch Resources/Nodes/GPU state, or add fields to the canonical chunk packet.

Packet, mountain-mask, grass, and object-presentation requests share one
distance-aware worker pool. Its size is derived from logical CPU count while
reserving main/render capacity and is capped independently of the number of
compute kinds. Interactive/reveal work precedes streaming/background work;
dispatch-turn aging prevents starvation within one priority class. Cross-class
ordering uses a bounded weighted-fair quota: interactive work is never delayed,
while a sustained reveal flood yields one oldest streaming request after five
reveal request dispatches; sustained non-background work likewise yields one
oldest background request after 31 request dispatches. Every detached packet-
batch member counts separately toward that debt. Thus source prefetch retains a finite
latency bound for vehicle travel without allowing aged low-priority work to form
a burst ahead of the visible frontier.
Source-padding object packing is streaming class and is promoted to reveal class
when the chunk enters the visible/publish frontier. Native packet batches are
bounded, require exact settings equality, and may combine only requests on the
same priority frontier. An incompatible exact-priority request closes that FIFO
frontier, so a far or later-compatible batch cannot delay a newly urgent mining
mask or chunk-reveal presentation job.

Implementation shape is intentionally flat:
- keep native sources directly under `gdextension/src/`
- do not introduce `/core` vs `/godot` source trees in V0
- keep `gdextension/SConstruct` simple; extend only as much as the single native
  world core class requires

### Script Ownership

V0 introduces only three world runtime roles:

| Role | Owner | Responsibility |
|---|---|---|
| Orchestrator | `WorldStreamer` | stream ring, request packets, receive results, schedule publish, expose compatibility reads/mutation |
| State | `WorldDiffStore` | store per-chunk tile overrides, feed save/load |
| View | `ChunkView` | own one chunk root and one local `TileMapLayer` |
| Visual bridge | `WorldStreamer` + `ChunkView` | own chunk-scoped 2D mountain native masks, publish derived mask textures, and keep old page work out of normal streaming |

V0 does not add:
- a separate publish queue object
- a second streamer
- an environment overlay owner
- a generic world service graph

### Runtime 2D Mountain Native Masks

The active world version includes a transitional native-mask bridge for the
accepted 2D mountain look:

- `WorldStreamer` remains the stream orchestrator. It does not queue FHD
  mountain render pages for normal chunk streaming; runtime mountain
  presentation is a chunk-owned native halo mask applied directly to each
  `ChunkView`.
- The authoritative source stays unchanged: `ChunkPacketV0` plus
  `WorldDiffStore`. Native masks are derived presentation/cache data and are not
  saved.
- The source cache radius for terrain packets is the visible stream radius plus
  one chunk. This gives each visible chunk enough neighbour truth to build its
  local mountain halo without waiting for a separate mountain-page pipeline.
- `WorldStreamer` builds only the small solid halo from loaded packets and
  runtime diffs on the main thread. `WorldCore.build_mountain_halo_mask` runs as
  a `mountain_halo_mask` job in `WorldChunkPacketBackend` worker threads. The
  native method returns an `L8` alpha mask at bounded pixels-per-tile
  resolution. For an excavated roof-bearing request, the same worker also calls
  `WorldCore.build_mountain_skylight_exposure` over immutable closed roof `C`
  and live remaining mass `V`, attaching a bounded derived L8 exposure field
  under the same epoch/revision. Zero-dug requests skip that second field.
  Publish waits for gameplay-ready mask bytes before exposing a chunk that
  contains mountain surface. Mining may apply only a local dirty rect to
  existing bytes synchronously, then queues a worker reconciliation for
  affected halo chunks.
- The publish/mining path may only store mask bytes and mark the chunk for
  visual upload; it must not create or update `ImageTexture` synchronously.
  `ImageTexture` creation/update belongs to the separate
  `FrameBudgetDispatcher.CATEGORY_VISUAL` job
  `world.mountain_native_mask_visual_upload`, which processes queued native-mask
  texture uploads only while the current visual budget remains. A completed
  native mask worker result must not enqueue a full chunk republish for an
  already visible chunk; visible chunks keep their current `ChunkView` and only
  swap the derived mask textures, including the optional skylight exposure
  texture, through the visual queue.
- `ChunkView` suppresses square mountain tile visuals while the native mask
  shader paints the accepted top/facade textures through the same mask. This
  prevents visible square terrain from leaking while keeping one logical
  `64px` tile as the gameplay unit.
- Dry terrain ground may use the same bounded native halo mask path with
  `mask_purpose = terrain_edge`. `WorldStreamer` derives dry terrain vs visible
  water from `terrain_ids + lake_flags`, queues the mask through the existing
  `WorldChunkPacketBackend` worker pool, and `ChunkView` paints a visual-only
  terrain top plus low facade above the water layer. While this mask is active,
  square base terrain tiles are suppressed for covered dry terrain. The terrain
  ground mask is derived cache data and must not affect walkability, collision,
  mining, lake simulation, or save/load.
- Visual sun/shadow parameters are locked in
  `WorldVisualLightingProfile`. Runtime `WorldStreamer` reads the current
  `TimeManager` hour/progress, takes the fixed north-west sun azimuth from that
  profile, derives projected shadow length, opacity, softness, and dusk/dawn
  fade from time, then pushes only shader material parameters into loaded
  `ChunkView` instances. Object shadows therefore always project screen
  south-east with a planted caster foot; dawn/dusk stretch them without rotating
  them. This is visual presentation work; it does not create a gameplay light
  authority and does not mutate world generation, save state, terrain ids, or
  walkability.
  Small generated decor, such as `plains` rocks, may clamp projected shadow
  length to zero and use a centered contact shadow when a directional cast
  shadow makes the sprite read as floating.
- Dry-ground grass / straw and rocky ground patch overlays are visual-only and
  belong to `ChunkView`. They reuse the ready terrain-ground halo mask texture
  as a clip mask, sample preloaded albedo/normal material maps, derive organic
  coverage from world-space coordinates in shader, and render only the exact
  owned chunk interior. They must not use decorative chunk-edge alpha feathering
  or a visible-chunk-wide rebuild to hide seams. The overlay must not affect
  terrain ids, walkability, collision, mining, save/load, lake simulation, or
  chunk packet schemas.
- Chunk-local mountain foothill / rocky apron overlay is visual-only and
  belongs to `ChunkView`. It captures the first valid ready mountain native
  mask for the chunk view as a separate footprint mask, renders below the
  mountain material and above ground/grass, and samples preloaded
  albedo/normal material maps. Its outer apron width may vary locally in shader
  from world-space noise, and the footprint may remain visible inside the
  former mountain edge after mining clears the live mountain mask. It must not
  fill the interior of mined-out mountain space, because full footprint fills
  are chunk-local visual pages and can show as hard rectangular stains. This
  footprint remains presentation cache only: the authoritative source, dirty
  owner, terrain ids, walkability, collision, mining, save/load, and chunk
  packet schemas stay unchanged. Full chunk unload/reset may clear it.
- When square mountain tiles are suppressed in favor of the native mask, the
  hidden terrain base cell beneath mountain surface uses the ordinary organic
  plains ground visual. Mined `TERRAIN_PLAINS_DUG` tiles keep the same visual
  ground under the mountain mask instead of exposing a separate square dug tile;
  the authoritative terrain and runtime diff state remain unchanged.
- Dev visual lock scenes that evaluate the accepted mountain/terrain/shadow
  look must use the same `WorldVisualLightingProfile` values as runtime. Local
  hardcoded shadow ranges in dev scenes are invalid because they make runtime
  screenshots and authoring screenshots disagree.
- The local dirty unit for mining is one authoritative tile plus the affected
  chunk native mask. Adjacent chunk masks are refreshed only when the changed
  tile lies inside their fixed halo. Mining must not rebuild the whole mountain
  or all nearby chunks synchronously. A mountain-surface dig must not repaint
  the ordinary square terrain cell in the interactive frame; the visible change
  goes through the bounded native-mask dirty rect so the player never sees an
  intermediate square tile. The synchronous dirty rect is collision/resource
  bytes only; texture creation/update must stay in the visual upload job after
  native reconciliation produces the next derived mask.
- Inside a ready native mask, `is_walkable_at_world`,
  `has_resource_at_world`, and `try_harvest_at_world` sample the same mask bytes
  queued for presentation. Gameplay/collision readiness is based on the mask
  bytes, not on visual texture upload completion. The owner chunk sample wins
  when the world position is
  inside that chunk mask; neighbour masks are consulted only for overlap.
- Mining still resolves the sampled visual pixel back to one authoritative
  exposed mountain tile and writes through `WorldDiffStore`. Inside a ready
  native mask, visible solid mask pixels and the narrow south contour lip remain
  blocking even when the sampled authoritative tile is already `dug`; open mask
  pixels, including the mined tile center, become walkable immediately without
  waiting for a full visual rebuild.
- The FHD mountain raster/dev-scene path remains an authoring and probe tool
  until the accepted look is promoted into authored terrain resources. It is not
  the normal runtime streaming path. Legacy raster chunk-hit requests must not
  emit or display a raster ground patch in runtime: terrain ground is owned by
  the chunk terrain material, while raster ground output is probe-only and can
  otherwise leak as a flat coloured interior fill after mountain excavation.

### Existing Compatibility Surface

The V0 world runtime root must join the existing `chunk_manager` group and
provide the smallest compatibility surface already expected by gameplay code:

```text
is_walkable_at_world(world_pos: Vector2) -> bool
has_resource_at_world(world_pos: Vector2) -> bool
try_harvest_at_world(world_pos: Vector2) -> Dictionary
```

V0 interpretation:
- `is_walkable_at_world` reads `base + diff`; inside a ready mountain raster hit
  mask it samples the owner native contour first. Solid mask pixels and the
  narrow south contour lip block movement even when the underlying authoritative
  tile is already `dug`, while open mask pixels release rounded-off square
  corners and mined tile centers to the authoritative walkability diff
- `has_resource_at_world` is allowed only as the single-tile mutation proof for
  the current diggable surface class provided by the active world runtime;
  diagonal-only sealed rock does not qualify, because the candidate tile must
  have at least one orthogonally exposed walkable face. Inside a ready raster hit
  mask it first requires a solid mountain pixel or narrow south contour lip,
  then resolves that pixel to the nearest exposed authoritative mountain tile.
  Dug tiles are not resources when the sampled mask pixel is open
- `try_harvest_at_world` is allowed only to convert that one diggable tile into
  its post-mutation state and return the minimal harvest/mutation result payload;
  raster contour mining uses the same mutation path after resolving the visual
  pixel to the authoritative tile
  the current harvest input path must resolve the nearest qualifying tile along
  the player-to-cursor ray and must not skip through a nearer blocking solid

This compatibility surface is not permission to reintroduce general resource
streaming in V0.

### V1-R1B Spawn, Bounds, and Substrate Amendment

For `world_version >= 9`, the active new-world path also carries
`worldgen_settings.world_bounds` and `worldgen_settings.foundation` into the
native `settings_packed` payload.

Rules:
- X chunk coordinates are canonicalized modulo `world_bounds.width_tiles`.
- Y chunk requests outside `world_bounds.height_tiles` are filtered by the
  streamer and clipped by native generation if a caller submits them anyway.
- the preview/new-game spawn-safe patch must be resolved from the native
  `WorldPrePass` substrate through
  `WorldCore.resolve_world_foundation_spawn_tile(...)` on the worker path before
  progressive preview chunks are queued.
- the spawn resolver rejects candidates in ocean/burning masks, reserved
  non-land massing, high wall density, and lake coarse nodes
  (`lake_id > 0`), then returns the selected
  `spawn_tile` plus `spawn_safe_patch_rect`.
- `WorldCore` still mirrors the selected safe patch as mountain-safe output in
  chunk packets so the first loaded area stays walkable.
- runtime new-game start queues the same native spawn resolver on the world
  packet worker, applies the returned `spawn_tile` to the local player through
  `PlayerAuthority`, and only then allows the streaming ring to enqueue chunks.
- save/load remains authoritative for persisted player position; `load_world_state`
  does not apply new-game spawn placement.
- script code may parse the native spawn result, but must not rederive substrate
  channels or provide a hidden GDScript fallback for `world_version >= 9`.

### Streaming Policy V0

V0 uses one streamer and one symmetric ring only.

Rules:
- no forward lobe
- no transport-aware lead
- no hidden second preload ring
- candidate chunks are ordered by simple distance from the player
- queued packet requests are coalesced by `(epoch, chunk_coord)`. Replacement
  swaps the complete generation snapshot (seed, version, exact settings and
  priority) while preserving enqueue age/FIFO sequence; it never combines old
  generation inputs with a new request
- priority selection and packet-batch detachment each make one linear queue pass
  under the shared mutex. A batch requires exact native `PackedFloat32Array`
  settings equality and one priority frontier; an incompatible exact-priority
  request is a stable FIFO barrier
- weighted-fair debt is charged for every request in a native batch, and a batch
  stops at the remaining quota boundary. A fairness grant is exactly one request
  and cannot open another batch
- object-presentation enqueue retains ref-counted copy-on-write `PackedArray`
  snapshots in O(1) relative to payload size. Producer and worker only read them
  through completion; rebinding is safe, mutating shared ownership violates the
  contract
- queued requests have distance priority refreshed when the desired source
  bubble changes and are removed before compute when no longer relevant
- work already executing cannot be cancelled; its epoch-tagged result is
  accepted only against current demand, otherwise it may enter the bounded
  warm base-packet cache
- chunk lifecycle stays minimal: `absent -> queued -> generating -> ready ->
  visible -> evicted/warm-cached`

The streamer owns one bounded LRU-style warm cache of **immutable native base
packets**. Its capacity is the maximum viewport source-bubble footprint
(`121` chunks with the current radius contract). It is derived runtime state:
never saved, never authoritative, and cleared on world reset. A cache hit moves
the base packet back into the resident source set and reapplies the current
`WorldDiffStore` before publish; diff-applied packets are never stored as the
base. The cache does not retain `ChunkView` nodes or GPU presentation resources.
This makes zoom-in/zoom-out and short backtracking avoid redundant native world
generation without turning the cache into a second preload ring.

### Observable Readiness Diagnostics Amendment (S2)

`WorldStreamer` exposes one developer-only, read-only readiness snapshot for
the current bounded streaming working set. The snapshot observes the existing
streamer; it does not own demand, schedule work, change priority, reveal a
chunk, or retain/evict resources.

The lifecycle vocabulary is:

```text
requested -> generated -> gameplay_ready -> presentation_ready
          -> reserve_ready -> visible -> retained / evicted
```

Semantics:

- `requested`: a current source-demand packet request exists, but no accepted
  packet is resident yet.
- `generated`: the immutable base packet plus current diff-applied packet are
  resident; gameplay publication or its required native mask bytes are not
  complete yet.
- `gameplay_ready`: terrain publication and gameplay-critical mask/collision
  bytes are ready; blocking visual presentation may still be pending.
- `presentation_ready`: all currently required visual families for the chunk
  have a ready presentation result. This includes terrain/mountain visuals,
  object families, grass, and current roof/cavity presentation where
  applicable. A layer that is intentionally absent is `not_applicable`, not
  missing.
- `reserve_ready`: a source-demand chunk outside the visible ring has the
  currently available packet and presentation preparation needed by the
  existing implementation. S2 reports honestly when the current streamer does
  not prepare a required layer this far ahead; it does not add that work.
- `visible`: the owning `ChunkView` is visible. A visible chunk may still report
  a missing non-blocking layer (for example current late grass); visibility is
  not treated as proof that every presentation layer is ready.
- `retained`: demand ended, but an existing warm/hot packet, view, object, or
  grass cache still owns reusable data.
- `evicted`: demand ended and no tracked reusable resident data remains.

For every reported chunk, the snapshot contains exactly one
`blocking_reason` and `blocking_layer` when `ready == false`, chosen by stable
precedence from the real current owner state. It also contains per-layer state
for `packet`, `gameplay`, `terrain`, `mountain_mask`, `terrain_edge_mask`,
`objects`, `grass`, `roof_cavity`, and `visibility`. Every waiting layer reports
one concrete reason and elapsed wait time. Readiness diagnostics must never
replace an error with a generic `not_ready` reason when a current queue,
inflight request, retry, upload, reveal guard, missing source, or terminal
failure is observable.

Timing is transient diagnostic state. Stage/reason timestamps are recorded in
O(1) at the existing enqueue, completion, publication, reveal, retention, and
eviction transitions and are cleared on world reset. They are not save data or
gameplay truth.

Performance contract:

- ordinary inactive gameplay pays no per-frame scan;
- `get_perf_hud_snapshot()` remains O(1) and the F4 numeric trace keeps its
  fixed-field sampling path;
- the detailed snapshot may scan only the already bounded desired/resident
  working set and is built only for an explicit diagnostic capture, bounded
  probe sample, or recorder finalization;
- no filesystem, viewport, native generation, scene-tree group, tile, object,
  or whole-world scan is allowed while building the snapshot;
- diagnostic state is derived/transient, bounded to current source demand plus
  a small retained/evicted terminal-history cap, and cannot become a second streamer or
  presentation framework.

S2 changes public debug read semantics only. It does not change streaming
radius, zoom demand, priority, generation, publication, reveal, residency,
visual quality, collision, lighting, save shape, commands, or events.

### Honest Initial Loading Gate Amendment (S3)

`WorldStreamer` owns one transient initial-loading gate for new-game and load
startup. `WorldRuntimeV0Scene` owns the blocking UI and player-input pause, but
it may only read and present the streamer's gate state. UI progress, fade
timing, or a fixed timeout can never decide world readiness.

The initial target is established after the authoritative player/spawn
position is available:

- the visible envelope is the current maximum zoom-out radius
  (`MAX_VIEWPORT_STREAM_RADIUS_CHUNKS`, currently `4`);
- the movement reserve is one additional source ring (currently radius `5`);
- every valid target coordinate is generated and materialized as a
  `ChunkView`; the outer reserve remains hidden and collision-inactive until it
  later becomes visible demand;
- a pre-presentation position change (including the deterministic mountain dev
  teleport) recenters and restarts the bounded target accounting. Normal player
  movement is disabled by the loading host until the first world frame is
  presented.

For each target chunk the authoritative gate advances monotonically through:

```text
requested -> generated -> gameplay_ready -> presentation_ready -> reserve_ready
```

`gameplay_ready` requires committed terrain cells and every applicable
gameplay mask/collision construction. `presentation_ready` additionally
requires mountain/roof, shoreline, object, and grass presentation to be fully
committed. `reserve_ready` means a visible-envelope chunk has passed its normal
reveal guard, or an outer-reserve chunk owns the same complete materialized
presentation while intentionally hidden. Intentionally absent authored layers
are ready, not missing.

Gate evaluation is incremental and bounded to a fixed number of target chunks
per streaming tick. The compact state returned to UI is O(1); the detailed S2
diagnostic scan remains explicit-only. Heavy packet/mask/object/grass compute
continues through the existing shared worker backend, and all scene/GPU apply
continues through existing frame-budgeted lanes.

The screen may begin its visual fade only when all target chunks are
`reserve_ready`. The target stays pinned through that fade and through the
first unobscured world frame. `WorldRuntimeV0Scene` then acknowledges that
frame, restores player processing, and releases the startup-only pin. This
amendment does not define steady-state movement or zoom residency; those remain
S4/S5 work.

The compact gate state measures cold-start wall time, cumulative and
per-stage times, prepared chunks/second, first presented process frame, and
static/video memory after the completed bubble. It contains no fixed timeout
and never reports `ready` from estimated/decorative progress. All state is
derived, bounded, cleared on world reset, and excluded from saves, commands,
events, replication, and canonical world output.

### Steady Terrain Preparation Envelope Amendment (S4)

After the S3 first-world-frame acknowledgement, `WorldStreamer` transfers the
startup bubble into one bounded steady-state terrain preparation envelope
instead of shrinking materialization back to the visible ring.

The three nested rings have distinct ownership:

- `visible`: the current camera-derived stream radius; terrain/water/mountain
  views may become visible only after their terrain and mask reveal guards;
  object presentation and its blocking collisions remain inactive until the
  existing object reveal guard completes;
- `terrain reserve`: one symmetric chunk ring beyond visible demand; every
  chunk owns a hidden `ChunkView` with committed terrain/water cells and all
  applicable mountain plus shoreline mask bytes/textures;
- `packet support`: one additional packet-only ring; immutable packets stay
  resident only to provide complete cross-chunk halo input for the terrain
  reserve and never create a `ChunkView`.

With the current maximum radius `4`, the bounded ordinary working set is
`81 visible + 40 terrain reserve + 48 packet support = 169` resident base
packets and at most `121` materialized chunk views. Finite-world Y clipping and
cylindrical X canonicalization still apply.

Demand is rebuilt only when the player crosses a chunk boundary or the current
stream radius changes. A newly entered terrain-reserve frontier has one full
`1024 px` chunk traversal, `3.2 s` at the current maximum ordinary player speed
of `320 px/s`, to finish before it can enter visible demand. Ordering stays
distance-based and symmetric so an immediate direction change does not expose
an unprepared side; S4 does not add a forward lobe or transport prediction.

Terrain reserve preparation reuses the existing packet worker, bounded terrain
publish slices, combined halo cache, native mountain/terrain-edge mask jobs,
and visual upload lane. It does not add another streamer or presentation
framework. Reserve views remain hidden and collision-inactive. When a prepared
chunk enters visible demand, terrain, water, and applicable masks may not begin
publication after that transition.

S4 does not change object, decor, or grass generation, packing, upload,
readiness, visual identity, or cache policy. Existing object/grass work may
continue through its current paths for a materialized reserve view, but it is
neither required for nor evidence of terrain-reserve readiness. After the S3
startup gate, an unfinished object presentation may no longer keep an otherwise
complete terrain view hidden: that object's existing external presentation and
blocking collision remain inactive until its own reveal guard completes. The
S3 startup gate keeps its atomic full-presentation rule. Zoom-independent
residency and hysteresis remain explicitly deferred to S5.

All S4 state is derived and transient. It is excluded from saves, commands,
events, replication, canonical world output, and `world_version`.

### Publish / Apply Rules

`ChunkView` rules:
- one root per chunk
- one `TileMapLayer` child for gameplay-critical terrain
- only local chunk coordinates are written into the layer
- the world-space offset is stored on the chunk root, not baked into tile keys

Main-thread publish rules:
- chunk publish runs through `FrameBudgetDispatcher.CATEGORY_STREAMING`
- publish must be sliced into bounded cell batches
- worker threads must not touch `Node`, `TileMapLayer`, or any active scene-tree object
- worker threads must not emit scene-dependent events
- `TileMapLayer.clear()` is forbidden on runtime mutation paths
- TileMap autotiling / neighbour-solving APIs are forbidden on runtime hot paths
- publish/visibility readiness checks must be O(1); diagnostic halo counts are
  maintained when the halo changes and must not be rescanned during ordinary
  chunk publication

Single-tile mutation rules:
- write one override into `WorldDiffStore`
- update walkability locally
- if adjacency-dependent terrain presentation needs neighbour correction,
  recompute only the bounded local visual patch around the changed tile for
  already-loaded chunks
- do not regenerate the whole chunk packet
- do not republish the entire chunk view

## Persistence Contract

### Authoritative Save Shape

V0 save/load uses:
- `world.json` for `world_seed` and `world_version`
- `worldgen_settings.world_bounds` and `worldgen_settings.foundation` for
  `world_version >= 9`
- `chunks/<x>_<y>.json` for dirty chunk tile overrides only

Rules:
- base chunk data is never saved
- empty chunk diff = no chunk file
- load order is `regenerate base -> apply diff -> publish`
- missing or non-current `world_version` is incompatible in the active
  pre-alpha load path; old saves are rejected before chunk diffs or other
  runtime state are applied

### ChunkDiffV0

Each dirty chunk file stores only the minimum data needed to reapply local
terrain overrides:

```text
{
  "chunk_coord": {"x": int, "y": int},
  "tiles": Array[
    {
      "local_x": int,
      "local_y": int,
      "terrain_id": int,
      "walkable": bool,
    }
  ],
}
```

This shape is intentionally tile-only. No chunk-level cached presentation state
belongs in save files.

## Event Contract for V0

V0 reuses existing world-facing `EventBus` signals only:
- `world_initialized(seed_value: int)`
- `chunk_loaded(chunk_coord: Vector2i)`
- `chunk_unloaded(chunk_coord: Vector2i)`

V0 does not add new world runtime events unless implementation proves that the
existing signal set is insufficient.

## Performance Class

- interactive:
  - one tile mutation
  - one local diff write
  - one bounded local visible patch apply if loaded; for mountain-surface digs
    this explicitly excludes the ordinary square terrain cell
  - one bounded native-mask dirty rect byte patch for mining if a ready mask is
    loaded
- background compute:
  - native chunk generation off-thread
  - chunk mountain halo mask generation in `WorldChunkPacketBackend` worker
    threads
- background apply:
  - sliced chunk publish through `FrameBudgetDispatcher`
  - chunk mountain native mask texture upload through
    `FrameBudgetDispatcher.CATEGORY_VISUAL`; publish/mining only enqueues this
    work after storing gameplay-ready mask bytes, and post-mining native mask
    reconciliation does not republish already visible chunks
- boot/load:
  - initial chunk bubble materialization and diff restore

V0 is invalid if it:
- moves scene-tree work into workers
- adds a GDScript generator fallback
- falls back from native batch chunk generation to single-chunk generation when
  the batch contract is broken
- rebuilds a full chunk for one tile mutation
- performs a whole-world prepass

## Acceptance Criteria

- [ ] player crosses chunk boundaries without visible world breakage
- [ ] the same `world_seed + chunk_coord + world_version` always yields the same `ChunkPacketV0`
- [ ] chunks stream in and out deterministically under a symmetric ring policy
- [ ] one modified tile survives save/load on top of regenerated base terrain
- [ ] visual object packet fields remain deterministic and same-length for the
  same `world_seed + chunk_coord + world_version`
- [ ] no worker thread touches the active scene tree
- [ ] single-tile mutation does not trigger full chunk rebuild or full chunk redraw

## Files That May Be Touched In The First Implementation Task

- `gdextension/SConstruct`
- `gdextension/station_mirny.gdextension`
- new native files under `gdextension/src/`
- new files under `core/systems/world/`
- `core/autoloads/save_manager.gd`
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_appliers.gd`
- `core/autoloads/save_io.gd`
- `core/autoloads/event_bus.gd`
- `core/entities/player/player.gd`
- `core/systems/building/building_system.gd`
- `scenes/world/world_runtime_v0.tscn`
- `scenes/world/world_runtime_v0_scene.gd`
- `scenes/ui/main_menu.gd`
- `scenes/ui/save_load_tab.gd`
- `scenes/ui/death_screen.gd`
- the active world/gameplay scene that instantiates the V0 world runtime root

## Files That Must Not Be Touched In The First Implementation Task

- biome registries and biome data resources
- flora/decor batching systems
- environment overlay systems
- subsurface / Z-level runtime beyond current read-only compatibility
- unrelated combat, UI, progression, or lore systems
- any deleted legacy world runtime files

## Required Canonical Doc Follow-Ups When Code Lands

When V0 is implemented, the same task must update:
- `docs/02_system_specs/meta/packet_schemas.md` with `ChunkPacketV0` and `ChunkDiffV0`
- `docs/02_system_specs/meta/save_and_persistence.md` with `world_version` and `chunks/*.json`
- `docs/02_system_specs/meta/system_api.md` with the documented `chunk_manager` compatibility surface if it remains public
- `docs/02_system_specs/meta/event_contracts.md` once `world_initialized`, `chunk_loaded`, and `chunk_unloaded` have confirmed emitters and listeners
- `docs/02_system_specs/meta/commands.md` only if implementation introduces a dedicated world mutation command object

These follow-ups are intentionally deferred until code confirms the final names
and payloads.

## Risks

- treating V0 as permission to pre-design V2+ systems
- allowing packet fields to grow before there is a consumer
- hiding a whole-chunk redraw inside a "temporary" helper
- implementing a native async API before the single synchronous packet boundary
  is proven sufficient

## Open Questions

- which existing scene is the smallest safe host for the `WorldStreamer` root?
- should the single-tile mutation proof use the current harvest input path or a
  smaller developer-only trigger in the first implementation task?
- is one chunk publish slice best expressed as rows, fixed-size cell batches, or
  another equally local apply unit?

## Implementation Iterations

### V0 - End-to-end chunk runtime proof

Goal:
- prove chunk streaming, deterministic generation, and one persisted tile diff
  without building future systems early

What changes:
- add one native world core class with `generate_chunk_packet`
- add one script streamer, one diff store, and one chunk view
- hook save/load for chunk diffs
- wire the minimal `chunk_manager` compatibility surface used by current
  gameplay code

What does not change:
- biome/content pipeline
- environment runtime layering
- mountain or placement solves
- transport-aware streaming
- chunk view reuse/pooling

Verification expectation:
- static verification in-session is mandatory
- runtime crossing / save-load / hot-path behavior remains manual human
  verification unless a later implementation task explicitly runs Godot
