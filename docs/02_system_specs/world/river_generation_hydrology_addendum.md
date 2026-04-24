---
title: River Generation V2 Hydrology Addendum
doc_type: system_spec_addendum
status: approved
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-04-24
related_docs:
  - river_generation.md
  - mountain_generation.md
  - world_runtime.md
---

# River Generation V2 Hydrology Addendum

## Purpose

Tighten `river_generation.md` after early implementation showed that local
scribbles, long trunk corridors, sinusoidal centerlines, and lowland threshold
masks do not produce convincing rivers.

This addendum is binding for V2 river implementation until merged back into the
main river spec.

## Core Decision

V2 rivers are **hydrology-inspired static worldgen**, not fluid simulation.

Required implementation shape:

```text
mountain / height / valley fields
-> bounded macro guide grid
-> directed downstream graph
-> flow accumulation
-> visible river network extraction
-> smoothed centerline chains
-> flow-based width with obstacle-clearance clipping
-> shallow/deep riverbed rasterization
-> optional controlled island/split-channel masks
-> water occupancy later
```

Forbidden implementation shape:

```text
noise threshold river mask
independent trunk corridors
sinusoidal decorative lines
random walkers as final river routes
local macro scribbles
route crossings that do not merge
mountain-foot attraction
runtime fluid simulation
hydraulic erosion
whole-world water prepass
```

## Hydrology Scope

The system must implement only a small static hydrology skeleton:

- no particles
- no erosion
- no dynamic water levels
- no runtime water simulation
- no global ocean/sea solve
- no runtime rerouting after terrain changes

The required hydrology is:

- each guide node chooses one deterministic downstream neighbor
- multiple upstream nodes may flow into the same downstream node
- flow accumulation is computed on the directed graph
- only guide nodes / edges above a visible-flow threshold become visible rivers
- width is derived from accumulated flow and then clipped by obstacle clearance

This is intentionally a river-network generator, not a water simulator.

## Guide Fields

The existing mountain field is upstream data for river generation, but mountain
or lowland masks are **not** final river masks.

The macro guide grid must derive these fields per guide node:

| Field | Meaning |
|---|---|
| `hydro_height` | Synthetic flow potential used for downstream selection. It may include mountain elevation, broad world slope, and low-frequency relief noise. |
| `valley_potential` | Preference for open low corridors between obstacles. This is a routing cost input, not a river mask. |
| `wall_block` | Hard blocker derived from `mountain_wall` density/proximity. |
| `foot_penalty` | Soft obstacle derived from `mountain_foot` density/proximity. Foot must not attract rivers. |
| `wall_clearance` | Distance to nearest wall-like obstacle, used for early smooth bypass and width clipping. |
| `local_source_score` | Deterministic source/rain contribution, biased by high terrain and mountain-adjacent candidate regions. |

Lowlands/valleys are allowed to guide rivers. They are not allowed to directly
become rivers by thresholding.

## Downstream Graph Contract

For every valid guide node, choose at most one downstream neighbor from the
8-neighborhood.

Required behavior:
- `mountain_wall` is a hard blocker
- `mountain_foot` is a soft obstacle, not an attraction target
- downstream choices prefer lower `hydro_height`
- downstream choices prefer open valley corridors with enough wall clearance
- downstream choices penalize sharp turns once a route chain is extracted
- cycles must be broken deterministically
- local minima may terminate as dry-end sinks in V2-R1, but may not create lakes
  unless a later lake spec lands
- X-wrap neighbors are valid; Y never wraps

Tie-breaking must be deterministic and independent of chunk generation order.

## Flow Accumulation Contract

After downstream graph construction, compute flow accumulation:

```text
flow[node] = local_source_score[node] + sum(flow[upstream_nodes])
```

Visible rivers are extracted only where accumulated flow crosses a versioned
threshold.

Consequences:
- small source noise must not create visible disconnected mini-rivers
- tributaries merge into larger routes instead of crossing them
- main stems become wider downstream
- river width must respond to actual accumulated flow, not only to UI width
  settings

## Mountain Bypass Contract

Rivers must not be merely pushed away after colliding with mountains. They must
begin turning before collision through clearance-aware routing.

Rules:
- `mountain_wall` is impassable except for source/waterfall mouth presentation
  already defined by `river_generation.md`
- `mountain_foot` may be crossed only when the selected graph route is already a
  valid valley/pass route; it must not be used as a sticky route rail
- routes should prefer open corridors between wall/foot obstacles
- near wall/foot obstacles, actual channel width must shrink before any terrain
  overwrite would cut into protected mountain geometry

Width clipping rule:

```text
desired_width = base_width + sqrt(flow) * flow_width_gain + bounded_width_noise
actual_width = min(desired_width, wall_or_strong_foot_clearance * 2 - safety_margin)
```

If `actual_width` falls below the minimum viable riverbed width, the channel may
become a hidden flow segment rather than a visible riverbed.

## Centerline Extraction and Smoothing

Centerlines must be extracted from the visible drainage graph, not generated as
standalone trunk curves.

Rules:
- graph chains may be smoothed using deterministic Catmull-Rom, Bezier, or
  equivalent curve fitting
- smoothing must preserve endpoint order, chunk seam continuity, and X-wrap
  continuity
- smoothing must not move centerlines into hard blockers
- smoothing must not create crossings between unrelated routes
- if a smoothed segment approaches a hard blocker, the segment is reprojected or
  the visible width is clipped

## Route Merge and Crossing Rules

Rivers form a directed network.

Required behavior:
- tributaries may merge into downstream routes
- two unrelated routes must not cross like rails
- if a new visible segment touches an existing downstream route at a valid
  junction angle, it merges
- if it would cross an existing route at an invalid angle, it is rerouted,
  hidden, or rejected deterministically
- parallel routes closer than the minimum spacing are merged, repelled, or one
  is hidden according to deterministic priority

## Shallow / Deep Classification

The existing `<= 4` shallow-only and `>= 5` shallow-shelf + deep-center rule
remains valid.

Implementation detail:
- after rasterization, classify deep bed from distance-to-bank / distance-to-edge
  inside the final clipped channel mask
- `distance_to_edge <= 1` should remain shallow in MVP
- interior tiles beyond the shallow shelf become deep bed

This avoids blocky deep centers on bends and around future islands.

## Controlled Islands and Split Channels

V2 may support island-looking geometry only as a controlled static event.

Allowed MVP approach:
- on a wide, calm, non-junction segment, subtract a deterministic dry island
  lens/capsule from the riverbed mask
- the remaining riverbed must stay connected around the island
- the island must not intersect mountain wall, protected foot, source mouths, or
  chunk/macro seam guard bands

Allowed later approach:
- create two temporary offset channel centerlines that split from the main route
  and are guaranteed to rejoin within a bounded distance

Forbidden:
- arbitrary random route splits
- split channels that do not rejoin
- island generation before the drainage graph and base riverbed are stable
- island masks that break route continuity

## Debug / Verification Requirements

Before judging visual riverbed rasterization, implementation must expose or dump
these debug layers for preview/development:

- guide grid nodes
- downstream arrows
- `hydro_height` heatmap
- `valley_potential` heatmap
- wall/foot obstacle and clearance maps
- flow accumulation heatmap
- visible river graph before smoothing
- smoothed centerlines
- desired width vs actual clipped width
- final shallow/deep riverbed raster

Acceptance must reject a build if only final river tiles are visible and the
intermediate graph/flow layers cannot be inspected.

## Acceptance Additions

The river implementation is not acceptable until:

- [ ] `amount = 0.0` produces no visible riverbed
- [ ] lowland/valley threshold alone never writes riverbed tiles
- [ ] visible river segments come from accumulated flow, not standalone trunk
      lines
- [ ] at least one debug preview can show downstream arrows and flow
      accumulation
- [ ] major visible rivers have increasing or stable width downstream, except
      where clearance clipping narrows them
- [ ] tributaries merge instead of crossing
- [ ] no unrelated river routes cross as rails
- [ ] rivers turn before hitting mountain walls rather than bouncing at contact
- [ ] mountain foot is not a sticky attraction rail
- [ ] river width clips near protected mountain geometry
- [ ] wide channels classify shallow shelves and deep center by distance-to-edge
- [ ] controlled islands, if enabled, keep riverbed connectivity around them

## Practical Implementation Iteration

### V2-R1A.1 - Hydrology debug only

Implement macro guide grid, downstream graph, cycle breaking, and flow
accumulation. Do not rasterize final riverbed yet except optional debug overlay.

### V2-R1A.2 - Visible river graph

Extract visible river network from flow threshold and verify merges/continuity.
Still no terrain writes.

### V2-R1A.3 - Dry riverbed rasterization

Rasterize smoothed graph chains into shallow/deep dry riverbed with width from
flow and clearance clipping.

### V2-R1A.4 - Controlled islands

Add optional static island masks only after base dry riverbed passes visual and
performance review.

### V2-R1B - Water occupancy

Enable deterministic static water overlay only after dry riverbeds are approved.
