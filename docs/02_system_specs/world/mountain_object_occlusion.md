---
title: Mountain vs Object Occlusion — Z Order Decision
doc_type: system_spec
status: approved
source_of_truth: true
owner: engineering+art
version: 2.4
last_updated: 2026-08-17
related_docs:
  - wind_and_grass_scatter_presentation.md
  - plains_trees_presentation.md
  - world_runtime.md
  - object_render_world.md
---

# Mountain vs Object Occlusion — Z Order Decision

## Problem (render-proof screenshots, 2026-07-04)

Tree canopies near a mountain silhouette were hard-clipped by the mountain's own
rendering: the mountain layers used fixed `z = 300/301`, far above the object depth
ladder (`21..214`), so the mountain unconditionally covered every tree/rock/player
sprite that overlapped its pixels — even when the object was clearly standing in
front of (south of, closer to the camera than) that part of the mountain.

## Rejected approach (v1 of this doc): canopy alpha carve

A shader-side carve (bounded footprint gather → per-material uniform array → final
alpha suppression under canopies) was implemented and render-probed. The mechanism
worked, but the USER REJECTED it on sight: translucent canopy-shaped holes in the
rock read as decay/holes in the mountain, not as trees standing in front. All carve
code was fully reverted (shader uniforms + final block, `ChunkView` propagation,
`WorldStreamer` gather, canopy-extent plumbing in `WorldObjectPacketLayer`).

## Final decision: mountain BELOW the object ladder

The mountain passes moved from `300/301` down below the object ladder — between
the grass contact shadows (`Z_GRASS_SHADOW = Z_WORLD_SHADOW = 18`) and the object
body pages. `world_runtime_constants.gd` is the authoritative source; the current
band is:

| Constant | Value |
|---|---:|
| `Z_WORLD_SHADOW` / `Z_GRASS_SHADOW` | `18` |
| `Z_MOUNTAIN_PAGE` | `19` |
| `Z_MOUNTAIN_TORCH_SHADOW` | `20` |
| `Z_MOUNTAIN_TOP` | `21` |
| `Z_MOUNTAIN_ROOF` | `22` |
| `Z_ACTOR_SHADOW` | `23` |
| `Z_RENDER_BODY_PAGE_BASE` (= `Z_MID_LADDER_BASE`) | `24` |

Trees, rocks and the player are published by `WorldRenderWorld` into the dense
body pages starting at `24`, so they always draw OVER every mountain pass. The
former per-object depth ladder (`21..214` with the player fixed at `118`) was
replaced in Iteration 1 by the global painter tuple `(feet_y, semantic_layer,
stable_id)`; the player no longer holds a fixed z. See `world_runtime.md` for the
full Canvas pass order, including the emissive (`260`) and overhead (`300`)
page windows.

This is geometrically correct, not a compromise:
- objects are never placed on mountain wall/foot tiles (native clearance,
  `OBJECT_MOUNTAIN_CLEARANCE_PX`), and
- sprites extend UPWARD (north) from their ground anchors,
- therefore an object's pixels can only overlap mountain pixels when the object
  stands SOUTH of (in front of) that part of the silhouette — exactly the case
  where the object must win.

Raising only the trees above `300` instead was considered and rejected: at the
time the player was the fixed ladder anchor (`z = 118`), so trees above `300`
would always cover the player and break the confirmed player↔tree Y-sort. Under
the global painter that objection is now structural rather than numeric — trees
and the player share one sorted pass and must not be split across z bands.

## Consequences (accepted)

- The interior roof (`RoofLayer`, `Z_DEBUG_OVERLAY = 350`) still hides unrevealed
  cavities — unchanged.
- Layered object cast shadows ride the caster's feet stripe in the shared
  ground-shadow depth channel. They can fall onto rock near the base of a
  mountain, but remain below object bodies in the same or any more southern
  stripe — physically plausible, accepted.
- Biofield spores (`Z_GRASS_SPORE = 290`) now render above mountain pixels at edges —
  they are airborne particles, accepted.
- The mountain's projected sun shadow (part of the BASE mask sprite, z 19)
  renders under grass tufts (z 21+); grass inside long dawn/dusk mountain shadows
  pops slightly. Accepted as minor; revisit only if a probe shows it objectionable.

## Follow-up: grass tufts visible inside the mountain (fixed 2026-07-04)

The z-flip above made a second, distinct bug visible: grass tufts (also on the
object ladder, now z 21+) occasionally rendered on/inside solid mountain rock —
not the "front overlap is correct" case above, but tufts genuinely inside the
mountain's silhouette. Unlike the tree-canopy case, this was a real bug, not a
consequence to accept: grass placement already had a "keep clear of mountain
tiles" clearance (`GRASS_MOUNTAIN_CLEARANCE_PX`, `grass_scatter.cpp`), but it
only read the current chunk's own `terrain_ids` — a candidate near a chunk
seam got zero clearance whenever the nearest mountain tile sat in the
*neighbouring* chunk, regardless of how large the clearance distance was set.
Fixed by reusing `WorldStreamer`'s existing cross-chunk `mountain_solid_halo`
(already built for the mountain mask itself) as the clearance source, and by
replacing the old 8-point ring sample with an exhaustive small-radius tile
scan (a ring can jump over a mountain feature thinner than the sampled
radius). Full details: `wind_and_grass_scatter_presentation.md` Iteration 5.

## Related tweak (same user request)

Tree collision circles are raised by half their radius above the ground anchor
(`_append_tree`, `world_object_packet_layer.gd`) so the player can approach a trunk
closely from the south. F11 debug boxes follow automatically (built from the same
records).
