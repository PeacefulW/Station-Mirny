---
title: River Generation V1
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.5
last_updated: 2026-04-30
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - world_runtime.md
  - world_foundation_v1.md
  - mountain_generation.md
  - terrain_hybrid_presentation.md
  - ../meta/packet_schemas.md
  - ../meta/system_api.md
  - ../meta/save_and_persistence.md
---

# River Generation V1

## Status and Current-Code Boundary

This spec approves the design contract for river generation. Current runtime
has the first river-enabled boundary at `world_version = 17`; V1-R4 lakebed
rasterization advances lake-enabled worlds to `world_version = 18`, and V1-R5
delta / controlled-split rasterization advances current new worlds to
`world_version = 19`. V1-R6 added the runtime water overlay seam without
changing canonical worldgen output, so the V1-R6 boundary remained
`world_version = 19`.
V1-R8 changes canonical river/lake raster output and advances current new
worlds to `world_version = 20`. V1-R9 changes canonical ocean-edge packet
output and advances current new worlds to `world_version = 21`. V1-R10 changes
canonical river centerline geometry and advances current new worlds to
`world_version = 22`. V1-R11 changes canonical river width/depth classification
from refined-edge curvature and post-confluence context, so current new worlds
advance to `world_version = 23`. V1-R12 changes canonical confluence shape by
marking native Y-shaped confluence zones around qualifying joins, so current new
worlds advance to `world_version = 24`. V1-R13 changes canonical split-branch
shape by replacing simple controlled braid offsets with native rejoining island
loops, so current new worlds advance to `world_version = 25`. V1-R14 changes
canonical lake shape by deriving lakebed depth/rim from basin contour and spill
diagnostics, so current new worlds advance to `world_version = 26`. V1-R15
changes canonical ocean output by adding native organic coastline distance,
shallow-shelf classification, and river-mouth influence on top of the existing
hydrology skeleton, so current new worlds advance to `world_version = 27`.

V1-R3B has landed the first gameplay packet rasterization:

- `WorldCore.generate_chunk_packets_batch(...)` consumes the native
  `WorldHydrologyPrePass` snapshot for river-enabled world versions;
- chunk packets emit hydrology arrays, riverbed shallow/deep terrain, shore /
  bank / floodplain markers, ocean-floor output for the north ocean sink, and
  default water classes;
- `WorldStreamer` and preview packing include `RiverGenSettings`; new saves
  write `worldgen_settings.rivers`, while missing river settings on a
  river-enabled load use an explicit hard-coded default migration;
- the current presentation path uses temporary hydrology placeholder profiles
  until dedicated water/shore art lands.

V1-R4 has landed the first natural lake pass:

- `WorldHydrologyPrePass` selects deterministic natural lake basins for
  `world_version >= 18`;
- legacy `world_version = 17` hydrology snapshots keep `lake_id = 0`;
- chunk packets rasterize lakebed terrain, lake shoreline / bank markers,
  default shallow/deep lake water classes, and lake outlet continuation through
  the existing river graph path.

V1-R5 has landed the first delta / controlled-split pass:

- `world_version >= 19` widens river-mouth reaches into delta / estuary packet
  output using existing `delta_scale`;
- eligible high-order reaches may emit deterministic fork/rejoin braid split
  raster edges using existing `braid_chance`;
- split and distributary output stays inside the existing chunk packet shape
  through `HYDROLOGY_FLAG_DELTA` and `HYDROLOGY_FLAG_BRAID_SPLIT`;
- legacy `world_version = 18` packets keep pre-R5 river/lake output and do not
  emit V1-R5 delta or split flags.

V1-R6 has landed the current water overlay seam:

- `EnvironmentOverlay` owns explicit dry/wet overrides for current water state;
- riverbed, lakebed, shore, ocean floor, and floodplain terrain ids remain
  immutable base terrain under that overlay;
- one water overlay mutation dirties an aligned `16 x 16` tile block through
  `water_overlay_changed(region: Rect2i, reason: StringName)`;
- `WorldStreamer` applies that dirty block only to loaded packet walkability;
- explicit local overrides may persist in `world.json.water_overlay`, while the
  seed-derived default `water_class` packet array remains unsaved and immutable.

V1-R7 has landed preview and performance closure:

- the new-game overview exposes a water mode rendered from the native hydrology
  overview image;
- that water mode renders river, lake, and ocean overlay pixels from
  `WorldHydrologyPrePass`;
- deterministic and performance smoke coverage now exercises the largest world
  preset;
- worker overview publication builds/reads native hydrology only and does not
  instantiate gameplay chunks or write save data.

V1-R8 has landed organic water shape and Water Sector exposure:

- `world_version >= 20` uses deterministic shoreline noise for natural lake
  chunk rasterization and hydrology overview pixels;
- river raster edges use deterministic meander subdivision plus per-edge width
  modulation, and the hydrology overview water mode uses the same organic
  overview raster path for visible river lines;
- the new-game Water Sector exposes existing `RiverGenSettings` controls for
  river count, network density, width scale, lake chance, meander strength,
  braid chance, shallow crossings, and delta scale;
- preview/settings signatures now use the live Water Sector settings instead
  of hard-coded river defaults;
- no packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added.

V1-R9 has landed ocean shore band rasterization:

- `world_version >= 21` turns ocean-edge packet output into a real walkable
  `TERRAIN_SHORE` band with `HYDROLOGY_FLAG_SHORE | HYDROLOGY_FLAG_BANK`;
- north-ocean floor remains `TERRAIN_OCEAN_FLOOR` with default
  `WATER_CLASS_OCEAN` and blocking walkability;
- ocean floor and ocean shore publish a stable ocean hydrology id in packet
  output except where a river-mouth delta keeps its river segment id;
- no packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added.

V1-R10 has landed refined river centerline substrate and direction memory:

- `world_version >= 22` builds native refined river edges from the whole
  `river_segment_ranges` path instead of independently bending each coarse
  hydrology edge;
- refined centerlines use Catmull-Rom interpolation, low-frequency
  deterministic bend memory, and slope / floodplain / mountain-clearance
  heuristics derived from the existing `WorldHydrologyPrePass` fields;
- chunk rasterization queries refined river candidates through a native spatial
  index owned by the hydrology snapshot, so chunks do not scan every river
  feature as river counts grow;
- hydrology overview river pixels use the same refined centerline substrate as
  chunk rasterization;
- no packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added.

V1-R11 has landed curvature-aware width/depth:

- `world_version >= 23` classifies refined river edges by signed curvature and
  post-confluence context while keeping the existing hydrology graph as the
  river skeleton;
- chunk rasterization widens curved reaches and post-confluence reaches from
  native refined-edge data, then shifts the deep thalweg toward the outer side
  of bends;
- post-confluence riverbed and bank/shore output may carry the existing
  `HYDROLOGY_FLAG_CONFLUENCE` to mark the widened reach;
- hydrology build/debug snapshots expose aggregate curvature/confluence edge
  counts for smoke coverage only;
- no packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added.

V1-R12 has landed Y-shaped confluence zones:

- `world_version >= 24` keeps the existing hydrology graph as the skeleton but
  derives a native Y-confluence influence zone around qualifying confluence
  nodes;
- refined river edges on two or more upstream arms taper into the join, while
  the downstream reach tapers out from the join;
- chunk rasterization reads the same refined spatial-index candidates and marks
  the upstream/downstream confluence zone with the existing
  `HYDROLOGY_FLAG_CONFLUENCE`;
- hydrology build/debug snapshots expose aggregate Y-confluence zone and edge
  counts for smoke coverage only;
- no packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added.

V1-R13 has landed braid island loops:

- `world_version >= 25` keeps the existing hydrology graph as the skeleton but
  derives deterministic, RAM-only braid loop branches for eligible high-order,
  low-slope/floodplain reaches;
- braid branches now start on the main reach, arc asymmetrically around an
  implicit island, and rejoin the same downstream reach through multi-edge
  native geometry instead of a simple parallel offset;
- candidate loop points reject mountain exclusion, lake, and ocean cells before
  refined edges are emitted;
- chunk rasterization continues to use the existing refined-edge spatial index
  and existing `HYDROLOGY_FLAG_BRAID_SPLIT`;
- hydrology build/debug snapshots expose aggregate braid-loop candidate and
  edge counts for smoke coverage only;
- no packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added.

V1-R14 has landed basin-contour lakes and oxbow preparation:

- `world_version >= 26` derives selected lake depth ratio and spill/outlet
  diagnostics from the existing native depression-fill basin data;
- lake chunk rasterization uses the depth ratio to keep shallow spill/rim tiles
  and deeper low-basin tiles in the same lake packet shape;
- hydrology build/debug snapshots expose aggregate basin-contour lake node,
  spill point, outlet connection, and oxbow candidate counts for smoke coverage
  only;
- rare oxbow candidates are detected from high-curvature lowland refined river
  bends as RAM-only preparation data and do not mutate the active river graph;
- no packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added.

V1-R15 has landed organic coastline and shelf output:

- `world_version >= 27` adds native RAM-only coast distance, shelf depth, and
  river-mouth influence fields to the hydrology prepass;
- ocean-floor packet output now distinguishes walkable shallow shelf from
  blocking deep ocean using the existing `water_class` array;
- river-mouth influence widens local shore/shelf classification around valid
  ocean terminals without changing the active river graph;
- no packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added.

V1-R1 landed the boundary/settings preparation:

- `RiverGenSettings` resource and default data file exist;
- reserved river/lake/ocean terrain ids, water classes, and hydrology flag
  constants exist;
- meta docs record the approved future packet/API/save boundary.

V1-R2 has landed the native diagnostic hydrology substrate:

- `WorldCore.build_world_hydrology_prepass(...)` builds a RAM-only
  `WorldHydrologyPrePassSnapshot` from seed, world version, foundation,
  mountain, and river settings;
- the snapshot includes effective hydrology height, irregular north ocean sink,
  Priority-Flood-style filled elevation, flow direction, flow accumulation,
  watershed labels, mountain exclusion mask, and floodplain potential;
- dev/debug snapshot and overview reads exist.

V1-R3A has landed the native diagnostic river graph:

- selected river node mask from flow accumulation / stream-order proxy;
- river source count and segment count;
- per-node segment id, stream order, and discharge arrays;
- compact six-int segment range records and path node index storage;
- debug overview rendering for selected river nodes.

Still not landed: dedicated water/shore materials, broad drought/refill
simulation, high-detail confluence scour/shore art, active oxbow lake
rasterization, and optional small ocean-island generation. V1-R15 adds the
first native organic coastline and shelf pass.

## Purpose

Define a deterministic, native-owned river and water terrain generation model
for the finite cylindrical surface world.

River Generation V1 adds the contract for:

- a north ocean sink with irregular coastline, estuaries, and deltas;
- continuous river networks from southern/highland sources to lake or ocean
  terminals;
- confluences that widen downstream channels;
- controlled splits and island-forming braided or distributary branches;
- natural lakes with spill outlets;
- mountain avoidance around both mountain wall and mountain foot terrain;
- shallow and deep water classes;
- persistent dry riverbeds under current water;
- chunk-local rasterization output that remains compact and native-owned.

## Gameplay Goal

The player should read the surface map as a coherent hydrological world:

- the north edge is an ocean, not a straight blue strip;
- rivers visibly travel across the vertical span of the map;
- small southern/headwater channels merge into wider downstream rivers;
- some reaches split around islands and rejoin or discharge into lakes/ocean;
- lakes have organic shapes and connected inflow/outflow;
- mountains feel like real obstacles that rivers bend around smoothly;
- shallow water creates crossing opportunities, while deep water is a real
  traversal blocker;
- drought or drying can remove current water while leaving riverbeds and
  lakebeds behind.

## Design Principles

### Hydrology first, not blue noise lines

Rivers are generated from a hydrology graph and then rasterized. They are not
painted as independent noise curves on top of terrain.

### Mountains first

Mountain wall and mountain foot output is already canonical. River generation
must consume mountain output as a hard no-go mask plus a configurable clearance
buffer. A river may bend around a mountain or split around a massif, but it must
not cross mountain wall/foot tiles and must not run directly adjacent to them.

### Riverbed and water are separate

Riverbeds, lakebeds, shore, and ocean floor are canonical base terrain. Current
water presence is a gameplay-authoritative overlay on top of water-capable
terrain. Drying changes the overlay; it does not rewrite the immutable base.

### Native compute only

Hydrology solve, river graph construction, rasterization, SDF sampling,
transition masks, and atlas decisions belong in C++/GDExtension. GDScript may
orchestrate worker requests and apply compact packets only.

### Chunk packets stay local

Whole-world hydrology may be solved at world load or new-game preview time, but
live chunk publication still receives compact per-chunk arrays through the
existing native packet boundary. No script-side loop over world or chunk tiles is
allowed on the hot path.

## Scope

River Generation V1 includes:

- `RiverGenSettings` saved into `worldgen_settings.rivers`;
- a native `WorldHydrologyPrePass` owned by `WorldCore`;
- north-ocean sink and shoreline generation;
- hydrology graph solve using depression handling, flow direction, flow
  accumulation, and watershed labels;
- river trunk and tributary selection from accumulation / stream order;
- lake basin detection, lake filling to spill point, and outlet continuation;
- controlled braided/distributary split generation;
- centerline smoothing and meander shaping;
- river/lake/ocean rasterization into chunk packet fields;
- bank and floodplain rasterization into compact chunk packet fields;
- base terrain classes for beds and shore;
- current water-depth classes for shallow/deep water;
- performance, determinism, save, and preview contracts.

## Out of Scope

River Generation V1 does not implement:

- full hydraulic erosion simulation;
- sediment transport simulation;
- physically accurate flood dynamics;
- weather-driven water volume simulation;
- seasonal ice/snow behavior beyond reserving the overlay seam;
- dynamic drought gameplay tuning beyond the bed/water separation contract;
- subsurface rivers or underground aquifers;
- water pumps, water treatment, or engineering-network gameplay;
- boats or swimming;
- multiplayer packet transport changes beyond deterministic regeneration.

## Related Documents

- `world_foundation_v1.md` owns finite world bounds, ocean band, and the
  existing substrate baseline.
- `mountain_generation.md` owns mountain wall/foot terrain and mountain masks.
- `world_runtime.md` owns chunk packet publication and streaming discipline.
- `terrain_hybrid_presentation.md` owns visual terrain materials and shape
  families.
- `packet_schemas.md`, `system_api.md`, and `save_and_persistence.md` must be
  amended by the implementation iteration that changes those live boundaries.

## Dependencies

- ADR-0001: hydrology prepass is boot/new-game-preview worker work, never
  interactive work.
- ADR-0002: X wraps cylindrically; Y is bounded, with the ocean at top-Y.
- ADR-0003: riverbeds are immutable base; water overlay is runtime state.
- ADR-0007: worldgen defines water-capable terrain; environment runtime may
  change current water state later.
- Mountain Generation V1: mountain wall and foot are hard blockers for rivers.
- World Foundation V1: hydrology reads world bounds, ocean band, `hydro_height`,
  `continent_mask`, and coarse mountain density context.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical, runtime overlay, or visual only? | Riverbeds, lakebeds, shore, ocean floor, river graph, lake basins, and default channel geometry are canonical worldgen data. Current water depth/presence is a gameplay-authoritative water overlay. Presentation is derived. |
| Save / load required? | Yes for `worldgen_settings.rivers`. Hydrology snapshots and chunk river arrays are not persisted. `EnvironmentOverlay` may persist explicit local current-water overrides in `world.json.water_overlay`; future broad drought state still requires its own approved slow-state shape. |
| Deterministic? | Yes. Hydrology output is pure `f(world_seed, world_version, world_bounds, foundation_settings, mountain_settings, river_settings)`. |
| Must work on unloaded chunks? | Yes. The hydrology substrate is independent of loaded chunks; chunk packets can be regenerated from seed/settings. |
| C++ compute or main-thread apply? | Hydrology solve, graph construction, SDF rasterization, and atlas decisions are C++ worker/native compute. Main thread only applies finished chunk packet arrays and water overlay updates. |
| Dirty unit | Hydrology prepass: whole world hydrology grid, once per world load/new-game preview. Chunk rasterization: `32 x 32` chunk packet. Runtime water overlay: aligned `16 x 16` tile dirty block for explicit local overrides. |
| Single owner | `WorldCore` owns canonical hydrology and rasterized base output. `EnvironmentOverlay` owns current water state. `WorldDiffStore` owns player/runtime terrain diffs only. |
| 10x / 100x scale path | Hydrology grid is coarse and native; packet rasterization builds a bounded native candidate set per chunk and may graduate to a cached spatial index when river counts grow. No GDScript tile loops or whole-world gameplay path. |
| Main-thread blocking? | Forbidden. Hydrology prepass runs on worker behind load/preview debounce. Chunk apply remains sliced through the streaming budget. |
| Hidden GDScript fallback? | Forbidden. Missing native hydrology support must fail loudly for river-enabled world versions. |
| Could it become heavy later? | Yes. Therefore hydrology solve and rasterization are native from the first implementation. |
| Whole-world prepass? | Permitted only as a documented ADR-0001 / ENGINEERING_STANDARDS Law 12 exception: worker-only, RAM-only, cache-keyed, world-load or new-game-preview class, never interactive. |

## Data Model

### `RiverGenSettings`

`RiverGenSettings` is a resource embedded into `worldgen_settings.rivers` for
new worlds and loaded from `world.json` for existing saves.

| Field | Range | Meaning |
|---|---|---|
| `enabled` | bool | Enables river generation for worlds at the river world-version boundary. |
| `target_trunk_count` | `0..256` | Desired number of major river trunks before density/spacing filters. `0` means auto-scale by world size. |
| `density` | `0.0..1.0` | Controls how many river trunks and tributaries survive graph selection. |
| `width_scale` | `0.25..4.0` | Multiplies channel width derived from discharge / stream order. |
| `lake_chance` | `0.0..1.0` | Probability that eligible depressions become natural lakes instead of breached drainage. |
| `meander_strength` | `0.0..1.0` | Controls centerline lateral offset and curvature after graph solve. |
| `braid_chance` | `0.0..1.0` | Controls eligible low-slope/high-discharge split creation. |
| `shallow_crossing_frequency` | `0.0..1.0` | Controls generated shallow ford / riffle opportunities. |
| `mountain_clearance_tiles` | `1..16` | Minimum distance from mountain wall/foot tiles to any wet river/lake/ocean cell. |
| `delta_scale` | `0.0..2.0` | Controls river-mouth widening, distributaries, and estuary carving at the ocean. |
| `north_drainage_bias` | `0.0..1.0` | Bias that makes the top-Y ocean the preferred terminal while still respecting local height and mountain avoidance. |
| `hydrology_cell_size_tiles` | `8..64` | Coarse hydrology graph cell size. Default target: `16` tiles. Changing the default requires `WORLD_VERSION` review. |

Default new-world values live in `data/balance/river_gen_settings.tres`.
Existing saves must load the embedded `worldgen_settings.rivers` copy once a
river-enabled world version exists; they must not reread the repository `.tres`
on load.

### Terrain classes

V1-R1 reserves concrete numeric ids in `world_runtime_constants.gd` and documents
them in `packet_schemas.md`.

| Terrain class id | Numeric id | Base meaning | Default traversal |
|---|---:|---|---|
| `TERRAIN_RIVERBED_SHALLOW` | 5 | Canonical shallow riverbed under water-capable channel. | Walkable when dry or shallow water overlay. |
| `TERRAIN_RIVERBED_DEEP` | 6 | Canonical deep riverbed under main channel. | Walkability comes from current water overlay; deep water blocks. |
| `TERRAIN_LAKEBED` | 7 | Canonical lake floor under natural lake outline. | Walkability comes from current water overlay. |
| `TERRAIN_OCEAN_FLOOR` | 8 | Canonical ocean floor inside top-Y ocean / estuary. | Default current water is ocean/deep and blocks. |
| `TERRAIN_SHORE` | 9 | Land/water transition band around ocean, lakes, and wider rivers. | Walkable unless current water overlay says otherwise. |
| `TERRAIN_FLOODPLAIN` | 10 | Canonical low river-adjacent land that reads as flood-shaped terrain. | Walkable by default; water overlay may temporarily wet it. |

Water classes are not immutable terrain ids. They are packet/overlay classes:

| Water class | Numeric id | Meaning | Traversal |
|---|---:|---|---|
| `WATER_CLASS_NONE` | 0 | Dry bed / dry land. | Uses base terrain walkability. |
| `WATER_CLASS_SHALLOW` | 1 | Shallow current water. | Walkable with movement penalty in future tuning. |
| `WATER_CLASS_DEEP` | 2 | Deep current water. | Blocking. |
| `WATER_CLASS_OCEAN` | 3 | Ocean / impassable sea water. | Blocking. |

### Hydrology substrate snapshot

`WorldHydrologyPrePassSnapshot` is RAM-only and regenerated from seed/settings.
It is not saved.

Required coarse fields:

| Field | Type | Meaning |
|---|---|---|
| `grid_width`, `grid_height` | int | Hydrology graph dimensions. |
| `cell_size_tiles` | int | Versioned hydrology cell size. |
| `hydro_elevation` | float array | Effective hydrology height after mountain barriers and north sink bias. |
| `filled_elevation` | float array | Depression-handled height used for drainage. |
| `flow_dir` | byte array | Quantized downstream neighbor direction or terminal marker. |
| `flow_accumulation` | float array | Upstream contributing area / discharge proxy. |
| `watershed_id` | int array | Drainage basin label. |
| `lake_id` | int array | Natural lake basin id, `0` for none. |
| `ocean_sink_mask` | byte array | Top-Y ocean / estuary terminal cells. |
| `mountain_exclusion_mask` | byte array | Mountain wall/foot plus clearance buffer. |
| `floodplain_potential` | float array | Lowland area around rivers/lakes eligible for floodplain rasterization. |
| `river_node_mask` | byte array | Diagnostic selected river graph nodes from flow accumulation; not gameplay terrain. |
| `river_segment_id` | int array | Per-node diagnostic river segment id, `0` for non-river nodes. |
| `river_stream_order` | byte array | Per-node compact stream-order / discharge bucket for selected river nodes. |
| `river_discharge` | float array | Per-node discharge proxy copied from flow accumulation for selected river nodes. |
| `river_segment_ranges` | int array | Six-int records: segment id, path offset, path length, head node, tail node, max stream order. |
| `river_path_node_indices` | int array | Concatenated hydrology node indices for diagnostic river segment paths. |
| `river_segment_index` | native candidate set / spatial index | River/lake/ocean segments for chunk rasterization. V1-R3B uses bounded native candidate filtering; larger counts may require a persistent index. |

### Chunk packet additions

The river implementation must extend `ChunkPacketV1` additively. Existing
fields are not removed or reshaped.

Target packet fields:

| Field | Type | Length | Meaning |
|---|---|---|---|
| `terrain_ids` | `PackedInt32Array` | 1024 | Existing field now may include riverbed, lakebed, ocean floor, shore, and floodplain terrain ids. |
| `walkable_flags` | `PackedByteArray` | 1024 | Derived from base terrain plus default current water class for the initial packet. Runtime overlay may override loaded walkability locally. |
| `hydrology_id_per_tile` | `PackedInt32Array` | 1024 | `0 = no hydrology`; otherwise stable river/lake/ocean feature id. |
| `hydrology_flags` | `PackedInt32Array` | 1024 | Bitfield for riverbed, lakebed, shore, bank, floodplain, delta, braid/split, confluence, and source markers. |
| `floodplain_strength` | `PackedByteArray` | 1024 | Optional `0..255` strength used by presentation and future wetting overlays. |
| `water_class` | `PackedByteArray` | 1024 | Default current water class: none, shallow, deep, ocean. This is seed-derived default overlay state, not immutable terrain. |
| `flow_dir_quantized` | `PackedByteArray` | 1024 | Optional compact direction for water animation and debug, not authoritative pathfinding. |
| `stream_order` | `PackedByteArray` | 1024 | Compact stream order / discharge bucket for visuals and tuning. |
| `water_atlas_indices` | `PackedInt32Array` | 1024 | Derived presentation atlas index for water/shore edge rendering. |

`hydrology_flags` uses `PackedInt32Array` because V1 needs more than eight
stable flags without nesting dictionaries in chunk packets.

## Runtime Architecture

### Ownership

`WorldCore` owns:

- `WorldHydrologyPrePass`;
- hydrology graph generation;
- river/lake/ocean rasterization;
- terrain id and atlas decisions for water-related base output.

`WorldStreamer` owns:

- scheduling native packet generation;
- publishing finished chunks through existing streaming budget;
- never deriving hydrology in GDScript.

`EnvironmentOverlay` owns:

- explicit local current-water overrides;
- local overlay dirty updates.

Future environment specs may extend it with:

- broad drought / refilling state;
- frozen water or seasonal water state.

`WorldDiffStore` owns:

- player/runtime diffs on top of the immutable base;
- never the seed-derived river graph.

### Hydrology prepass lifecycle

```
new world / load world / preview settings change
  -> pack worldgen_settings.rivers with foundation + mountain settings
  -> worker builds or reuses WorldPrePass
  -> worker builds WorldHydrologyPrePassSnapshot
  -> native cache publishes snapshot by signature
  -> chunk packet generation reads snapshot through native candidate filtering / spatial index
  -> main thread receives compact chunk packets only
```

The snapshot cache key must include:

- `world_seed`
- `world_version`
- `world_bounds`
- `foundation_settings`
- `mountain_settings`
- `river_settings`

Changing any canonical river output requires a `WORLD_VERSION` bump.

### Chunk rasterization

Chunk generation queries the native hydrology segment index for the chunk plus
a bounded halo. Rasterization is:

1. river/lake/ocean centerline or outline query;
2. signed distance field (SDF) evaluation in native code;
3. terrain class assignment for bed, shore, banks, and floodplain;
4. default water class assignment for shallow/deep/ocean water;
5. transition and atlas index solve;
6. compact packet return.

GDScript must not sample centerlines, build SDFs, loop through river pixels, or
perform water adjacency solving.

### Preview integration

The new-game overview may render river/lake/ocean overlays through the water
overview mode. The mode is a worker image publish sourced from the native
hydrology snapshot and must not instantiate gameplay chunks or write save data.

Debug height/hydrology layers that do not represent current gameplay terrain
remain diagnostic only and must not be presented as gameplay truth.

## Hydrology Algorithm Contract

### 1. Build effective hydrology height

The effective height field combines:

- `WorldPrePass.hydro_height`;
- mountain elevation and mountain density context;
- a northward drainage bias toward the top-Y ocean sink;
- low-frequency relief for broad valleys;
- hard mountain exclusion and clearance costs.

Mountain wall and foot tiles plus `mountain_clearance_tiles` form an exclusion
mask. Rivers and lakes cannot occupy excluded tiles.

### 2. Create irregular north ocean sink

The top-Y ocean is not a straight terrain strip. The hydrology prepass creates:

- a broad ocean sink in the top band;
- a coastline SDF with seeded irregularity;
- estuary widening around river mouths;
- delta/distributary regions controlled by `delta_scale`.

Ocean terrain remains connected to the top boundary and is impassable by
default.

### 3. Depression handling and lakes

Use a Priority-Flood style depression pass or an equivalent native algorithm to
guarantee drainage.

Eligible depressions may become lakes according to `lake_chance`, size, slope,
and mountain clearance. A lake fills to its spill point, receives inflows, and
must emit an outlet unless it is intentionally terminal in the ocean band.

Non-lake depressions are filled or breached in the hydrology field so every
river path has a valid downstream continuation.

### 4. Flow direction, accumulation, and watersheds

Compute flow direction and flow accumulation over the hydrology grid. Derive
watershed ids from terminal sinks and spill paths.

River trunks and tributaries are selected from:

- accumulation / discharge;
- stream order;
- minimum length;
- source distribution;
- `target_trunk_count`;
- desired density;
- spacing from other major trunks.

### 5. Rivers from source to terminal

Sources prefer southern/highland and valley-adjacent cells. Rivers must travel
downstream through the graph until they:

- join a larger river;
- enter a lake and leave through the lake outlet;
- enter the ocean / estuary.

No river segment may terminate on ordinary land.

### 6. Confluences and width

Channel width derives from discharge and stream order:

```
width_tiles = base_width + width_scale * pow(discharge_bucket, width_power)
```

The exact formula is implementation-owned but must obey:

- width increases at confluences;
- width is allowed to vary locally;
- shallow crossings may temporarily narrow or shoal the channel;
- downstream rivers generally read wider than upstream sources.

### 7. Meanders

Centerlines are smoothed after graph extraction. Meander offsets are applied
only where slope, clearance, and spacing allow it.

Use the hydrology rule of thumb that meander wavelength is tied to channel
width. USGS Professional Paper 282-B reports meander wavelength commonly around
7-12 channel widths; V1 may use this as a tuning target rather than a strict
simulation law.

### 8. Splits, islands, and braids

Splits are allowed only under controlled conditions:

- low slope;
- high discharge / high stream order;
- enough local clearance;
- `braid_chance` permits it;
- each branch rejoins downstream or exits into a lake/ocean/delta.

The hydrology graph must remain deterministic and acyclic. Orphan branches,
infinite loops, and land-terminating split branches are invalid.

### 9. Lakes and islands

Lake outlines are rasterized from basin shape plus seeded shoreline roughness.
Small islands may appear inside lakes or braided reaches only when clearance
and minimum island size allow readable terrain.

Lakebeds remain canonical base terrain even when water overlay dries.

### 10. Riverbeds and water depth

Rasterization must produce both:

- bed terrain (`riverbed_shallow`, `riverbed_deep`, `lakebed`, `ocean_floor`,
  `shore`, `floodplain`);
- default current water class (`none`, `shallow`, `deep`, `ocean`).
- bank and floodplain masks / strengths for presentation and future wetting.

Drying systems later change only current water class / overlay state, not bed
terrain ids.

## Event Contracts

River Generation V1 does not require new gameplay events for immutable river
generation.

V1-R6 approves the current local overlay event and updates
`event_contracts.md` in the same task:

- `water_overlay_changed(region: Rect2i, reason: StringName)`

Still future and not approved as a current runtime event:

- `river_water_state_changed(hydrology_id: int, state: StringName)`

## Save / Persistence Contracts

Saved:

- `worldgen_settings.rivers`;
- `world_version` boundary that includes river generation;
- explicit local water overlay overrides through `world.json.water_overlay`.

Not saved:

- hydrology prepass arrays;
- river segment graph;
- per-tile river/lake/ocean packet arrays;
- derived atlas indices;
- default water depth class if it is seed-derived and unmodified.
- transient water overlay dirty queues.

Load order:

1. restore seed, world version, world bounds, foundation, mountain, and river
   settings;
2. rebuild native foundation and hydrology snapshots on worker/boot path;
3. generate chunk packets from base + hydrology;
4. apply `WorldDiffStore` tile diffs;
5. apply current water overlay state if that system exists.

## Performance Class

| Operation | Class | Dirty unit | Budget / rule |
|---|---|---|---|
| Hydrology prepass | Boot/new-game-preview worker | Whole hydrology grid | Target <= 1500 ms on largest V1 preset at default `16`-tile hydrology cells; no main-thread wait outside load/preview progress. |
| Chunk river rasterization | Background worker chunk generation | `32 x 32` chunk plus bounded halo | Runs inside native packet generation; no GDScript tile loop. |
| Chunk water apply | Background apply | Sliced chunk packet publish | Uses existing streaming publish budget and compact arrays. |
| Runtime water overlay update | Interactive-local for one explicit override; background for future broad drought/refill | Aligned `16 x 16` water block | Only local overlay dirty update may be synchronous; broader changes are queued. |
| Player movement query | Interactive | One loaded tile | Reads already-materialized walkability; never computes hydrology. |

Forbidden:

- hydrology solve during gameplay input handling;
- hydrology solve on the main thread;
- mandatory whole-world tile-resolution raster storage in GDScript;
- per-tile native calls from script;
- hidden GDScript fallback when native hydrology is unavailable;
- `TileMapLayer.clear()` or whole-chunk redraw caused by one water overlay
  change.

## Modding / Extension Points

River V1 is setting-driven, not arbitrary script-driven.

Allowed mod extension:

- override `RiverGenSettings` defaults for new worlds;
- add presentation profiles for riverbed, lakebed, shore, and water materials;
- add biome rules that react to river/floodplain structure through an approved
  structure-context read seam.

Forbidden without a new spec:

- script-defined per-tile river generators;
- mod hooks that mutate the hydrology snapshot after compute;
- changing current water overlay ownership;
- changing packet fields through ad-hoc dictionaries.

## Acceptance Criteria

- [ ] Same seed, world version, bounds, mountain settings, foundation settings,
      and river settings produce identical hydrology output.
- [ ] Current chunk packets remain compact and additive; no existing packet
      fields are removed or reshaped.
- [ ] Rivers never occupy mountain wall or mountain foot terrain and respect
      `mountain_clearance_tiles`.
- [ ] Rivers form continuous downstream paths to confluence, lake outlet, or
      ocean.
- [ ] Confluences increase downstream width or stream order.
- [ ] Generated splits either rejoin or discharge into lake/ocean/delta.
- [ ] Lakes have spill outlets unless explicitly terminal in the ocean band.
- [ ] Shallow water is walkable; deep/ocean water is blocking.
- [ ] Dried rivers/lakes leave riverbed/lakebed terrain behind.
- [ ] North ocean coastline is irregular, with wider estuary/delta shapes at
      river mouths.
- [ ] New-game overview and runtime chunk rasterization agree at the level of
      river/lake/ocean placement.
- [ ] No GDScript code computes hydrology, rasterizes SDFs, or loops through
      chunk tiles for river generation.
- [ ] Hydrology prepass and chunk generation fail loudly if native support is
      missing for a river-enabled world version.
- [ ] Performance profiling confirms no interactive frame hitch is introduced
      by river generation or water overlay reads.

## Failure Cases / Risks

| Risk | Mitigation |
|---|---|
| Rivers look like straight vertical drains | Centerline smoothing, meander offsets tied to channel width, and obstacle-aware path cost are required. |
| Rivers cut through mountains | Mountain wall/foot plus clearance buffer is a hard exclusion mask. Acceptance tests must probe this directly. |
| Hydrology prepass becomes too slow | Keep grid coarse, use native arrays and priority queues, profile largest preset, and reduce optional braids/lake detail before reducing correctness. |
| Lakes trap rivers without outlets | Depression handling must produce spill points and outlet continuation. |
| Splits create broken or cyclic graphs | Split branches are controlled DAG branches with required rejoin or valid terminal. |
| Drying rewrites base terrain | Riverbed/lakebed are immutable base; water presence is overlay-only. |
| Packet grows too large | Keep per-tile fields byte/int arrays; keep heavy flow data in native substrate. |
| Current docs drift from current code | Meta docs update only when implementation changes live packet/API/save surfaces; this spec records future target shape. |

## External References

These references are design inputs, not implementation dependencies:

- Jean-David Genevaux, Eric Galin, Eric Guerin, Adrien Peytavie, Bedrich
  Benes. "Terrain Generation Using Procedural Models Based on Hydrology",
  ACM TOG 2013. Hydrology-first terrain generation: river network,
  watersheds, springs, deltas, then terrain carving.
  <https://www.cs.purdue.edu/cgvlab/www/publications/Genevaux13ToG/>
- Adrien Peytavie, Thibault Dupont, Eric Guerin, Yann Cortial, Bedrich Benes,
  James Gain, Eric Galin. "Procedural Riverscapes", Computer Graphics Forum
  2019. River trajectories from heightfields, riverbed carving, width/depth
  from terrain and river type.
  <https://diglib.eg.org/handle/10.1111/cgf13814>
- Richard Barnes, Clarence Lehman, David Mulla. "Priority-Flood: An Optimal
  Depression-Filling and Watershed-Labeling Algorithm for Digital Elevation
  Models", Computers & Geosciences 2014 / arXiv. Depression handling and
  guaranteed drainage.
  <https://arxiv.org/abs/1511.04463>
- Luna B. Leopold and M. Gordon Wolman. "River channel patterns: Braided,
  meandering, and straight", USGS Professional Paper 282-B, 1957. Meander,
  riffle, width, and braiding heuristics.
  <https://pubs.usgs.gov/publication/pp282B>

## Required Updates Before Implementation

V1-R1 has updated the static boundary for:

- `docs/02_system_specs/meta/packet_schemas.md` terrain ids, hydrology packet
  fields, water classes, and bit layouts;
- `docs/02_system_specs/meta/system_api.md` native hydrology prepass target,
  preview/debug reads, and settings resource surface;
- `docs/02_system_specs/meta/save_and_persistence.md`
  `worldgen_settings.rivers` target shape;
- `docs/00_governance/PROJECT_GLOSSARY.md` riverbed, water overlay, hydrology
  prepass, stream order, confluence, delta, and shallow/deep water;
- `docs/02_system_specs/world/world_runtime.md` river-enabled chunk readiness
  and walkability rules.

V1-R3A has updated the diagnostic boundary for:

- `docs/02_system_specs/meta/packet_schemas.md` hydrology build-result and
  debug-snapshot river graph fields;
- `docs/02_system_specs/meta/system_api.md` current `WorldHydrologyPrePass`
  debug-read note;
- `docs/02_system_specs/world/world_runtime.md` current no-gameplay-river note.

V1-R3B has updated the live runtime boundary for:

- `docs/02_system_specs/meta/packet_schemas.md` current `ChunkPacketV1`
  hydrology fields for `world_version >= 17`;
- `docs/02_system_specs/meta/system_api.md` river-enabled native packing,
  `generate_chunk_packets_batch(...)`, and `WorldStreamer` settings/save
  surfaces;
- `docs/02_system_specs/meta/save_and_persistence.md`
  `worldgen_settings.rivers` as current save shape for `world_version >= 17`;
- `docs/02_system_specs/world/world_runtime.md` current river-enabled chunk
  readiness and water-class walkability;
- `docs/02_system_specs/world/terrain_hybrid_presentation.md` the temporary
  hydrology placeholder presentation profiles for terrain ids `5..10`.

V1-R4 has updated the live lake boundary for:

- `docs/02_system_specs/meta/packet_schemas.md` current `lake_id` and lakebed
  packet semantics for `world_version >= 18`;
- `docs/02_system_specs/meta/system_api.md` `WorldCore` hydrology note for
  native lake basin selection and packet rasterization;
- `docs/02_system_specs/meta/save_and_persistence.md` current
  `world_version = 18` river/lake-enabled baseline;
- `docs/02_system_specs/world/world_runtime.md` current lakebed chunk readiness
  and water-class walkability;
- `docs/02_system_specs/world/world_foundation_v1.md` current river/lake
  `WORLD_VERSION` history;
- `docs/02_system_specs/world/terrain_hybrid_presentation.md` current wording
  for hydrology placeholder profiles.

V1-R5 has updated the live delta/split boundary for:

- `docs/02_system_specs/meta/packet_schemas.md` current `world_version = 19`
  and live `HYDROLOGY_FLAG_DELTA` / `HYDROLOGY_FLAG_BRAID_SPLIT` semantics;
- `docs/02_system_specs/meta/system_api.md` current `WorldCore` chunk packet
  note for delta / estuary widening and controlled split rasterization;
- `docs/02_system_specs/meta/save_and_persistence.md` current
  `world_version = 19` baseline without changing the save shape;
- `docs/02_system_specs/world/world_runtime.md` current delta/split chunk
  readiness and ownership notes;
- `docs/02_system_specs/world/world_foundation_v1.md` current river/lake/delta
  `WORLD_VERSION` history.

V1-R6 has updated the runtime water overlay seam for:

- `docs/02_system_specs/meta/event_contracts.md`
  `water_overlay_changed(region: Rect2i, reason: StringName)`;
- `docs/02_system_specs/meta/packet_schemas.md`
  `world.json.water_overlay` explicit override shape and current overlay
  notes;
- `docs/02_system_specs/meta/save_and_persistence.md` explicit water overlay
  override persistence rules;
- `docs/02_system_specs/meta/system_api.md` `EnvironmentOverlay` and
  `WorldStreamer` current-water entrypoints;
- `docs/02_system_specs/world/world_runtime.md` bounded water overlay dirty
  block and load/apply order;
- `docs/00_governance/PROJECT_GLOSSARY.md` current `Water overlay`
  definition.

V1-R7 has updated the preview/performance closure boundary for:

- `docs/02_system_specs/meta/packet_schemas.md`
  `WorldHydrologyOverviewImage` current river/lake/ocean overview notes;
- `docs/02_system_specs/meta/system_api.md` worker-published hydrology overview
  note;
- `docs/02_system_specs/world/world_runtime.md` new-game overview water mode
  ownership and no-save/no-gameplay-chunk boundary.
- `docs/02_system_specs/world/world_foundation_v1.md` clarification that river
  and lake overlays are excluded from the default foundation overview, not from
  the separate hydrology overview mode.

The new-game composite overview iteration has updated the same boundary for:

- `docs/02_system_specs/meta/system_api.md` transparent hydrology overview
  overlay bit and worker-side composition note;
- `docs/02_system_specs/world/world_runtime.md` composite overview no-save /
  no-gameplay-chunk boundary;
- `docs/02_system_specs/world/world_foundation_v1.md` default
  `WorldFoundationPalette.COMPOSITE` player-facing palette;
- `docs/02_system_specs/world/WORLD_GENERATION_PREVIEW_ARCHITECTURE.md`
  one-image composite overview pipeline.

V1-R8 has updated the organic water/settings boundary for:

- `docs/02_system_specs/meta/packet_schemas.md` current `world_version = 20`
  and organic river/lake raster semantics without packet shape changes;
- `docs/02_system_specs/meta/system_api.md` current `WorldCore` chunk packet
  and hydrology overview notes for organic lake shorelines, meandered river
  raster edges, and dynamic river width;
- `docs/02_system_specs/meta/save_and_persistence.md` current
  `world_version = 20` baseline without changing the save shape;
- `docs/02_system_specs/world/world_runtime.md` current organic water chunk
  readiness and no-interactive-hydrology ownership note;
- `docs/02_system_specs/world/world_foundation_v1.md` current river/lake/delta
  `WORLD_VERSION` history and Water Sector UI exposure boundary.

V1-R9 has updated the ocean-shore boundary for:

- `docs/02_system_specs/meta/packet_schemas.md` current `world_version = 21`
  ocean shore band and stable ocean hydrology-id semantics;
- `docs/02_system_specs/meta/system_api.md` current `WorldCore` chunk packet
  note for native ocean shore band rasterization;
- `docs/02_system_specs/meta/save_and_persistence.md` current
  `world_version = 21` baseline without changing the save shape;
- `docs/02_system_specs/world/world_runtime.md` current ocean shore chunk
  readiness and no-interactive-hydrology ownership note;
- `docs/02_system_specs/world/world_foundation_v1.md` current
  `WORLD_VERSION` history.

V1-R10 has updated the refined-centerline boundary for:

- `docs/02_system_specs/meta/packet_schemas.md` current `world_version = 22`,
  refined river centerline semantics, and hydrology build/debug diagnostic
  counts without changing `ChunkPacketV1`;
- `docs/02_system_specs/meta/system_api.md` current `WorldCore` chunk packet
  and hydrology overview notes for native refined centerlines and bounded
  spatial-index river candidate queries;
- `docs/02_system_specs/meta/save_and_persistence.md` current
  `world_version = 22` baseline without changing the save shape;
- `docs/02_system_specs/world/world_runtime.md` current refined river
  centerline chunk readiness and no-interactive-hydrology ownership note;
- `docs/02_system_specs/world/world_foundation_v1.md` current
  `WORLD_VERSION` history.

V1-R11 has updated the curvature-aware width/depth boundary for:

- `docs/02_system_specs/meta/packet_schemas.md` current `world_version = 23`,
  existing `HYDROLOGY_FLAG_CONFLUENCE` reach semantics, and hydrology
  build/debug diagnostic counts without changing `ChunkPacketV1`;
- `docs/02_system_specs/meta/system_api.md` current `WorldCore` chunk packet
  note for curvature-aware river width/depth and post-confluence reach flags;
- `docs/02_system_specs/meta/save_and_persistence.md` current
  `world_version = 23` baseline without changing the save shape;
- `docs/02_system_specs/world/world_runtime.md` current curvature-aware river
  chunk readiness and no-interactive-hydrology ownership note;
- `docs/02_system_specs/world/world_foundation_v1.md` current
  `WORLD_VERSION` history.

V1-R12 has updated the Y-shaped confluence boundary for:

- `docs/00_governance/PROJECT_GLOSSARY.md` current `Confluence` definition;
- `docs/02_system_specs/meta/packet_schemas.md` current `world_version = 24`,
  existing `HYDROLOGY_FLAG_CONFLUENCE` Y-zone semantics, and hydrology
  build/debug diagnostic counts without changing `ChunkPacketV1`;
- `docs/02_system_specs/meta/system_api.md` current `WorldCore` chunk packet
  note for native Y-shaped confluence zones;
- `docs/02_system_specs/meta/save_and_persistence.md` current
  `world_version = 24` baseline without changing the save shape;
- `docs/02_system_specs/world/world_runtime.md` current Y-confluence river
  chunk readiness and no-interactive-hydrology ownership note;
- `docs/02_system_specs/world/world_foundation_v1.md` current
  `WORLD_VERSION` history.

V1-R13 has updated the braid island loop boundary for:

- `docs/00_governance/PROJECT_GLOSSARY.md` current `Braid island loop`
  definition;
- `docs/02_system_specs/meta/packet_schemas.md` current `world_version = 25`,
  existing `HYDROLOGY_FLAG_BRAID_SPLIT` loop semantics, and hydrology
  build/debug diagnostic counts without changing `ChunkPacketV1`;
- `docs/02_system_specs/meta/system_api.md` current `WorldCore` chunk packet
  note for native rejoining braid island loops;
- `docs/02_system_specs/meta/save_and_persistence.md` current
  `world_version = 25` baseline without changing the save shape;
- `docs/02_system_specs/world/world_runtime.md` current braid-loop river chunk
  readiness and no-interactive-hydrology ownership note;
- `docs/02_system_specs/world/world_foundation_v1.md` current
  `WORLD_VERSION` history.

V1-R14 has updated the basin-contour lake and oxbow-prep boundary for:

- `docs/00_governance/PROJECT_GLOSSARY.md` current `Basin-contour lake` and
  `Oxbow lake` definitions;
- `docs/02_system_specs/meta/packet_schemas.md` current `world_version = 26`,
  unchanged `ChunkPacketV1` shape, and hydrology build/debug diagnostic counts;
- `docs/02_system_specs/meta/system_api.md` current `WorldCore` chunk packet
  and hydrology overview notes for basin-contour lake output;
- `docs/02_system_specs/meta/save_and_persistence.md` current
  `world_version = 26` baseline without changing the save shape;
- `docs/02_system_specs/world/world_runtime.md` current basin-contour lake
  chunk readiness and no-interactive-hydrology ownership note;
- `docs/02_system_specs/world/world_foundation_v1.md` current
  `WORLD_VERSION` history.

V1-R15 has updated the organic coastline and shelf boundary for:

- `docs/00_governance/PROJECT_GLOSSARY.md` current `Organic coastline` and
  `Ocean shelf` definitions;
- `docs/02_system_specs/meta/packet_schemas.md` current `world_version = 27`,
  unchanged `ChunkPacketV1` shape, shallow/deep ocean shelf semantics, and
  hydrology build/debug diagnostic counts;
- `docs/02_system_specs/meta/system_api.md` current `WorldCore` chunk packet
  and hydrology overview notes for coastline/shelf output;
- `docs/02_system_specs/meta/save_and_persistence.md` current
  `world_version = 27` baseline without changing the save shape;
- `docs/02_system_specs/world/world_runtime.md` current organic coastline chunk
  readiness and no-interactive-hydrology ownership note;
- `docs/02_system_specs/world/world_foundation_v1.md` current
  `WORLD_VERSION` history.

Future iterations that change live behavior must still update:

- `docs/02_system_specs/world/world_foundation_v1.md` if hydrology reuses or
  extends foundation substrate fields;
- `docs/02_system_specs/world/terrain_hybrid_presentation.md` if water/shore
  atlas topology or material families require new presentation contracts;
- `docs/02_system_specs/meta/event_contracts.md` if additional runtime water
  events are introduced.

Implementation must also bump `WORLD_VERSION` for any canonical river/lake/ocean
output change.

## Implementation Iterations

### V1-R1 - Boundary docs and settings

Landed:
- `RiverGenSettings` resource and default data file.
- reserved terrain ids, water classes, hydrology flags, and packet fields.
- glossary and runtime/API/save boundary docs.

Still true:
- no river generation code yet.

### V1-R2 - Native hydrology substrate

Landed:
- `WorldHydrologyPrePass` in native code.
- effective hydrology height, irregular north ocean sink,
  Priority-Flood-style depression handling, flow direction, accumulation, and
  watershed labels.
- dev-only snapshot/overview for diagnostics.

Still true:
- No gameplay river terrain yet.

### V1-R3A - Diagnostic river graph selection

Landed:
- select diagnostic river nodes from flow accumulation / stream-order proxy;
- expose source count, segment count, per-node segment id, stream order, and
  discharge arrays through debug snapshot;
- expose compact segment ranges plus concatenated path node indices;
- render selected river nodes in the diagnostic hydrology overview.

At the V1-R3A boundary:
- no gameplay riverbed/water rasterization yet;
- live chunk packet hydrology fields had not landed yet;
- no river-enabled `WORLD_VERSION` bump yet.

### V1-R3B - Main river trunks and rasterized beds

Landed:
- selected river graph from the V1-R3A hydrology snapshot is rasterized into
  gameplay chunk packets;
- `WORLD_VERSION` is `17` for the first river-enabled canonical output;
- chunk packets emit `hydrology_id_per_tile`, `hydrology_flags`,
  `floodplain_strength`, `water_class`, `flow_dir_quantized`, `stream_order`,
  and `water_atlas_indices`;
- riverbed shallow/deep, shore, floodplain, and ocean-floor terrain ids are
  emitted by native chunk generation;
- default `walkable_flags` reflects water class: shallow is walkable, deep and
  ocean are blocking;
- river settings are packed by runtime/preview and saved in
  `worldgen_settings.rivers`.

Still true:
- final water/shore art is still a future iteration;
- broad drought/refill simulation is not implemented.

### V1-R4 - Lakes and outlets

Landed:
- natural lake basin selection in native `WorldHydrologyPrePass` for
  `world_version >= 18`;
- legacy `world_version = 17` snapshots keep `lake_id = 0` for compatibility;
- lake basins use the filled hydrology elevation as their spill surface and
  record deterministic `lake_id` values in the debug snapshot;
- lakebed, lake shoreline / bank, default shallow/deep lake water classes, and
  outlet continuation are rasterized into chunk packets.

Still true:
- lake shapes remain hydrology-grid coarse for `world_version = 18..19`
  compatibility output;
- dedicated water/shore art remains a future iteration.

### V1-R5 - Deltas, estuaries, and controlled splits

Landed:
- river-mouth widening and delta/estuary chunk packet shapes for
  `world_version >= 19`;
- deterministic controlled braid/distributary split raster edges for eligible
  high-order reaches;
- every split edge either rejoins the main reach in the same downstream edge or
  terminates in the ocean as a delta distributary;
- `HYDROLOGY_FLAG_DELTA` and `HYDROLOGY_FLAG_BRAID_SPLIT` are live packet
  semantics; no new packet arrays, save fields, or runtime events were added.

Still true:
- islands are implicit ground left between fork/rejoin channels, not a new
  terrain id;
- dedicated water/shore art remains a future iteration;
- broad drought/refill simulation is not implemented.

### V1-R6 - Water overlay seam

Landed:
- `EnvironmentOverlay` owns explicit local current-water overrides.
- Riverbed/lakebed terrain remains immutable; overlay changes only current
  water class and derived walkability.
- One mutation dirties an aligned `16 x 16` tile block and emits
  `water_overlay_changed(region: Rect2i, reason: StringName)`.
- `WorldStreamer` applies the dirty block to loaded packet walkability without
  regenerating a chunk or redrawing the whole chunk.
- Optional `world.json.water_overlay` stores explicit local overrides only;
  dirty queues and seed-derived default packet `water_class` are not saved.

Still true:
- broad drought/refill simulation is not implemented;
- dedicated water/shore art remains a future iteration.

### V1-R7 - Preview and performance closure

Landed:
- render river/lake/ocean overlays in the new-game overview through
  `WorldFoundationPalette.HYDROLOGY_WATER`;
- route that overview request through `WorldChunkPacketBackend` to native
  `WorldCore.build_world_hydrology_prepass(...)` and
  `WorldCore.get_world_hydrology_overview(...)`;
- add deterministic and performance validation on the largest world preset;
- close the no-GDScript-loop and no-interactive-hydrology acceptance checks with
  a smoke test that rejects script-side hydrology snapshot reads for preview
  generation.

Still true:
- dedicated water/shore art remains a future iteration;
- broad drought/refill simulation remains a future iteration.

### V1-R8 - Organic water shape and Water Sector settings

Landed:
- current new worlds advance to `world_version = 20` because canonical
  river/lake/ocean raster output changes for the same seed/settings;
- lakebed and hydrology overview lake pixels use deterministic shoreline noise
  to break up hydrology-cell rectangles while keeping stable `lake_id` and
  packet fields;
- river raster edges and hydrology overview river lines use deterministic
  meander subdivision, controlled branch/fan edges, and dynamic width
  modulation derived from existing `RiverGenSettings` values;
- new-game Water Sector exposes existing river settings for river count,
  density, width, lake chance, meander, braid chance, shallow crossings, and
  delta scale;
- preview rebuild signatures and native settings packing consume the live
  Water Sector values.

Still true:
- no script code owns river/lake rasterization;
- dedicated water/shore art remains a future iteration;
- broad drought/refill simulation remains a future iteration.

### V1-R9 - Ocean shore band

Landed:
- current new worlds advance to `world_version = 21` because canonical ocean
  edge packet output changes for the same seed/settings;
- ocean coast chunks now publish walkable `TERRAIN_SHORE` tiles around the
  north-ocean sink instead of relying only on ground-edge presentation beside
  `TERRAIN_OCEAN_FLOOR`;
- ocean shore tiles carry `HYDROLOGY_FLAG_SHORE | HYDROLOGY_FLAG_BANK`,
  `WATER_CLASS_NONE`, and a stable ocean hydrology id;
- ocean floor remains blocking through `WATER_CLASS_OCEAN`;
- delta/estuary output keeps river segment ids where a river mouth overrides
  the generic ocean identity.

Still true:
- no script code owns ocean rasterization;
- no new packet arrays, save fields, or runtime events were added;
- dedicated water/shore art remains a future iteration;
- broad drought/refill simulation remains a future iteration.

### V1-R10 - Refined river centerlines and direction memory

Landed:
- current new worlds advance to `world_version = 22` because canonical river
  channel geometry changes for the same seed/settings;
- `WorldHydrologyPrePass` now owns a RAM-only refined centerline substrate and
  spatial index in addition to the existing coarse hydrology graph;
- river rasterization uses whole-path Catmull-Rom samples with low-frequency
  bend memory, slope-aware meander amplitude, mountain-clearance damping, and
  floodplain/terminal width modulation;
- chunk generation uses bounded native spatial-index queries for river
  candidates before per-tile rasterization;
- the hydrology overview reads the same refined centerline edges, keeping
  debug overview and chunk output aligned at the river-shape level.

Still true:
- the existing hydrology graph remains the skeleton; V1-R10 does not replace
  drainage, lake, delta, or braid graph ownership;
- no script code owns river/lake/ocean rasterization;
- no new packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added;
- dedicated water/shore art remains a future iteration;
- broad drought/refill simulation remains a future iteration.

### V1-R11 - Curvature-aware width/depth

Landed:
- current new worlds advance to `world_version = 23` because canonical river
  bed width/depth classification changes for the same seed/settings;
- refined river edges now carry signed curvature and post-confluence reach
  classification in the native RAM-only substrate;
- chunk rasterization widens curved reaches and post-confluence reaches, shifts
  the deepest thalweg toward the outer bank of a bend, and marks widened
  post-confluence riverbed/bank/shore tiles with the existing
  `HYDROLOGY_FLAG_CONFLUENCE`;
- hydrology build/debug snapshots expose aggregate
  `curvature_refined_river_edge_count` and
  `confluence_refined_river_edge_count` diagnostics for smoke tests.

Still true:
- V1-R11 itself only widens and deepens post-confluence reaches; V1-R12 lands
  the first Y-shaped confluence zone pass;
- the existing hydrology graph remains the skeleton;
- no script code owns river/lake/ocean rasterization;
- no new packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added;
- dedicated water/shore art remains a future iteration;
- broad drought/refill simulation remains a future iteration.

### V1-R12 - Y-shaped confluence zones

Landed:
- current new worlds advance to `world_version = 24` because canonical river
  confluence shape changes for the same seed/settings;
- `WorldHydrologyPrePass` now derives RAM-only Y-confluence influence around
  qualifying confluence nodes, using the existing hydrology graph as the source
  of truth;
- upstream refined edges taper into the confluence and downstream refined edges
  taper out of it, so packet rasterization can mark a continuous Y-shaped join
  instead of only a widened downstream reach;
- chunk packets continue to use the existing `HYDROLOGY_FLAG_CONFLUENCE`;
- hydrology build/debug snapshots expose aggregate `y_confluence_zone_count`
  and `y_confluence_refined_river_edge_count` diagnostics for smoke tests.

Still true:
- this is a geometric/rasterization pass, not a new drainage solver;
- the existing hydrology graph remains the skeleton;
- no script code owns river/lake/ocean rasterization;
- no new packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added;
- dedicated water/shore art remains a future iteration;
- broad drought/refill simulation remains a future iteration.

### V1-R13 - Braid island loops

Landed:
- current new worlds advance to `world_version = 25` because canonical split
  branch shape changes for the same seed/settings;
- eligible high-order braid branches are now native multi-edge loops that start
  from the main reach and rejoin the same downstream reach, leaving an implicit
  island between the active channels;
- loop candidates use slope/floodplain/mountain-clearance heuristics from the
  existing `WorldHydrologyPrePass` substrate and reject lake/ocean/mountain
  control points before emitting refined edges;
- chunk packets continue to use the existing `HYDROLOGY_FLAG_BRAID_SPLIT`;
- hydrology build/debug snapshots expose aggregate `braid_loop_candidate_count`
  and `braid_loop_refined_river_edge_count` diagnostics for smoke tests.

Still true:
- this is a geometric/rasterization pass, not a new drainage solver;
- the existing hydrology graph remains the skeleton;
- no script code owns river/lake/ocean rasterization;
- no new packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added;
- dedicated water/shore art remains a future iteration;
- basin-contour lakes and oxbow candidate preparation land in V1-R14; organic
  coastline/shelf output lands in V1-R15; active oxbow lake rasterization
  remains a future iteration.

### V1-R14 - Basin-contour lakes and oxbow prep

Landed:
- current new worlds advance to `world_version = 26` because canonical lake
  raster shape changes for the same seed/settings;
- selected lake nodes now record a RAM-only depth ratio derived from the filled
  basin spill surface, so chunk rasterization can keep a shallow rim and deeper
  low-basin water in the same lake body;
- selected lake candidates expose aggregate spill point and outlet connection
  diagnostics in build/debug results;
- native refined river geometry is scanned after centerline build for rare
  high-curvature lowland oxbow candidates; this is preparation only and does
  not alter the active river graph;
- chunk packets keep the same terrain, hydrology flag, and water-class arrays.

Still true:
- this is a geometric/rasterization pass, not a new drainage solver;
- the existing hydrology graph remains the skeleton;
- no script code owns river/lake/ocean rasterization;
- no new packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added;
- active oxbow lake rasterization remains a future iteration.

### V1-R15 - Organic coastline and shelf

Landed:
- current new worlds advance to `world_version = 27` because canonical ocean
  raster output changes for the same seed/settings;
- the north-ocean mask keeps the existing hydrology skeleton stable, while
  native RAM-only coast distance, shelf depth, and river-mouth influence fields
  refine visible ocean shape on top of it;
- ocean-floor tiles near the coast may now publish `WATER_CLASS_SHALLOW` as a
  walkable shallow shelf, while farther ocean-floor tiles remain
  `WATER_CLASS_OCEAN` and blocking;
- hydrology build/debug snapshots expose aggregate coastline, shallow-shelf,
  and river-mouth influence diagnostics;
- hydrology overview ocean pixels may distinguish shallow shelf from deep ocean
  using native prepass fields.

Still true:
- this is a geometric/rasterization pass, not a new drainage solver;
- the existing hydrology graph remains the skeleton;
- no script code owns river/lake/ocean rasterization;
- no new packet arrays, save fields, runtime events, or script-side hydrology
  rasterization were added;
- optional small ocean islands, active oxbow lake rasterization, dedicated
  water/shore art, and broad drought/refill simulation remain future work.

### New-game composite overview - Default player map

Landed:
- `WorldFoundationPalette.COMPOSITE` is the default new-game overview mode;
- terrain-only, water-only, and height-map modes remain diagnostic options;
- `WorldChunkPacketBackend` composes the foundation terrain overview with a
  transparent native hydrology overlay and publishes one image to the menu;
- no script code reads hydrology snapshot arrays or rasterizes rivers/lakes.

Still true:
- dedicated water/shore art remains a future iteration;
- broad drought/refill simulation remains a future iteration;
- the feature is menu presentation only and does not change save data,
  gameplay chunk generation, or `world_version`.
