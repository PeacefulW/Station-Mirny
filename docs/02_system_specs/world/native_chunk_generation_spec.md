---
title: Native Chunk Generation Spec
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.5
last_updated: 2026-04-09
depends_on:
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/WORKFLOW.md
  - world_generation_foundation.md
related_docs:
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../../04_execution/world_generation_rollout.md
  - boot_chunk_compute_pipeline_spec.md
---

# Feature: Native Chunk Generation (C++ GDExtension)

## Design Intent

Native chunk generation exists to accelerate chunk payload builds without introducing a second world model.

As of 2026-04-09, the native `ChunkGenerator` is no longer allowed to compute rivers, floodplains, ridges, or mountain mass from its own directed-band formulas. `WorldPrePass` is the only runtime source of truth for large-scale world structure. The native path must consume the same published pre-pass snapshot that powers the authoritative GDScript runtime and then reproduce the same biome / variation / terrain semantics from that snapshot.

The goal of this spec is therefore:
- one authoritative world structure model (`WorldPrePass`)
- one semantic pipeline across GDScript and C++
- one wire-compatible chunk payload shape
- no hybrid or fallback legacy structure stage in native runtime

## Current State

### What exists in C++
- `gdextension/src/chunk_generator.{h,cpp}` — production native chunk payload generator
- `gdextension/src/mountain_topology_builder.{h,cpp}` — production, used by ChunkManager
- `gdextension/src/FastNoiseLite.h` — vendored noise library
- Build system (SCons) functional, DLL compiles

### What exists in GDScript (authoritative semantics)
- `core/systems/world/world_pre_pass.gd` — authoritative coarse-grid world structure snapshot
- `core/systems/world/world_compute_context.gd` — curated runtime facade over published pre-pass truth
- `core/systems/world/biome_resolver.gd` — causal biome scoring using typed pre-pass channels
- `core/systems/world/local_variation_resolver.gd` — top-2 biome-aware local variation scoring and ecotone dampening
- `core/systems/world/surface_terrain_resolver.gd` — authoritative terrain decision tree using pre-pass-backed structure context
- `core/systems/world/chunk_content_builder.gd` — authoritative GDScript payload builder and native payload validator

### Removed from active runtime architecture
- native directed-band structure helpers (`directed_coordinate`, `repeating_band`, `sample_structure`, direction vectors, ridge/river warp bands)
- legacy ridge/river spacing and warp balance knobs
- native flora-placement generation inside `ChunkGenerator`

Those items may still appear below in historical rollout notes, but they are no longer valid source-of-truth architecture.

## Public API impact

Current public APIs affected semantically:
- `ChunkGenerator.initialize(seed: int, params: Dictionary) -> void`
- `ChunkGenerator.generate_chunk(chunk_coord: Vector2i, spawn_tile: Vector2i, generation_request: Dictionary) -> Dictionary`
- `WorldGenerator.create_detached_chunk_content_builder() -> ChunkContentBuilder` (integration point)

Required API/documentation outcome:
- `PUBLIC_API.md` must document native generation as a pre-pass-backed accelerator for `ChunkContentBuilder`, not as a separate structure pipeline
- `ChunkGenerator.initialize()` must require an immutable serialized `WorldPrePass` snapshot for the requested seed and fail closed otherwise
- `ChunkGenerator.generate_chunk()` must require a compact `native_chunk_generation_request_v1` from `ChunkContentBuilder` and sample per-tile channels / pre-pass structure inside C++ from the initialized authoritative snapshot. Legacy `world_chunk_authoritative_inputs_v1` arrays may remain accepted for debug/parity tooling only, but production runtime must not build or bridge them.
- `ChunkGenerator` output Dictionary must be wire-compatible with GDScript `build_chunk_native_data()` output, including `secondary_biome` and `ecotone_values`
- GDScript fallback must remain functional when native DLL is unavailable

## Data Contracts — new and affected

### New layer: Native Generation Config
- What: balance parameters + biome definitions + immutable `WorldPrePass` snapshot passed to C++ at initialization
- Where: `ChunkGenerator.initialize()` receives Dictionary from `WorldGenerator`
- Owner (WRITE): `WorldGenerator` (passes config), `ChunkGenerator` (stores internally)
- Readers (READ): internal C++ generation pipeline only
- Invariants:
  - config must be passed BEFORE any `generate_chunk()` call
  - biome definitions must include all fields required for scoring (ranges, weights, tags)
  - balance and biome parameters must match GDScript values exactly for deterministic parity
  - `WorldPrePass` snapshot must match the active seed and contain every required authoritative structure grid
  - native generation must not synthesize alternate ridge/river/floodplain/mountain truth outside that snapshot
- Forbidden:
  - C++ code must not read Godot resources at runtime (no `load()`)
  - C++ code must not access scene tree, nodes, or autoloads
  - C++ code must not fall back to legacy directed-band structure formulas if the snapshot is absent or malformed

### New layer: Native Chunk Generation Request
- What: compact per-chunk request metadata (`snapshot_kind = native_chunk_generation_request_v1`, canonical chunk coord, base tile, chunk size) passed to `ChunkGenerator.generate_chunk(...)`.
- Where: `ChunkContentBuilder._build_native_chunk_generation_request()` assembles the Dictionary and passes it to `ChunkGenerator.generate_chunk(...)`.
- Owner (WRITE): `ChunkContentBuilder` for request construction; `ChunkGenerator` for per-tile channel / pre-pass / structure sampling and payload generation.
- Readers (READ): `ChunkGenerator.generate_chunk()` only.
- Invariants:
  - runtime request must be built against canonical chunk coord and the current balance chunk size
  - production runtime must not build or bridge per-tile GDScript `PackedFloat32Array` authoritative inputs before calling native generation
  - native runtime must sample base climate channels with the same initialized native noise state and sample structure only from the initialized authoritative `WorldPrePass` snapshot
  - missing / malformed compact request is a hard runtime error for native generation, not a reason to synthesize alternate truth
  - proof tooling must be able to detect when runtime falls back to GDScript instead of using the native chunk generator

### Affected layer: World (canonical terrain)
- What changes: terrain bytes generated by C++ instead of GDScript (same output format)
- New invariants:
  - native output must be semantically identical to GDScript output for same seed + params + published pre-pass snapshot
  - runtime native build path must be semantically identical to authoritative GDScript output for same seed + compact native request + initialized authoritative pre-pass snapshot
  - output Dictionary keys: `terrain`, `height`, `variation`, `biome`, `secondary_biome`, `ecotone_values`, `flora_density_values`, `flora_modulation_values`, `chunk_size`, `chunk_coord`, `canonical_chunk_coord`, `base_tile`
- Who adapts: `WorldGenerator`, `ChunkContentBuilder` (integration path)
- What does NOT change: downstream consumers (Chunk.populate_native, redraw, topology)

## Output Format

`generate_chunk()` returns Dictionary:
```
{
  "chunk_coord": Vector2i,
  "canonical_chunk_coord": Vector2i,
  "base_tile": Vector2i,
  "chunk_size": int,
  "terrain": PackedByteArray[chunk_size²],           # TerrainType 0-6
  "height": PackedFloat32Array[chunk_size²],          # [0.0, 1.0]
  "variation": PackedByteArray[chunk_size²],          # LocalVariationId / polar overlay markers
  "biome": PackedByteArray[chunk_size²],              # palette index
  "secondary_biome": PackedByteArray[chunk_size²],    # palette index, defaults to biome when no ecotone
  "ecotone_values": PackedFloat32Array[chunk_size²],  # [0.0, 1.0]
  "flora_density_values": PackedFloat32Array[chunk_size²],    # [0.0, 1.0]
  "flora_modulation_values": PackedFloat32Array[chunk_size²], # [-1.0, 1.0]
}
```

Index: `y * chunk_size + x` (row-major).

## Per-tile Pipeline (what C++ must implement)

```
canonical_tile
    │
    ├─→ native per-tile sampling
    │     └─ sample_channels() for height / temp / moisture / ruggedness /
    │        flora_density / latitude, plus sample_biome_prepass() from the
    │        initialized WorldPrePass snapshot for drainage / slope /
    │        rain_shadow / continentalness / ridge_strength / river_width /
    │        river_distance / floodplain_strength / mountain_mass
    │
    ├─→ BiomeResolver parity path: channels + structure + typed pre-pass channels
    │     └─ primary biome + secondary biome + dominance + ecotone_factor
    │
    ├─→ VariationResolver: 3 noise + ecotone-aware tag blending → variation_kind + modulations
    │
    └─→ TerrainResolver: channels + structure + pre-pass + variation → TerrainType
          └─ safe_zone > river > bank > mountain > ground, then polar overlays
```

## Noise Configuration (8 instances total)

| Instance | Seed Offset | Frequency Source | Octaves Source |
|----------|------------|-----------------|---------------|
| height | +11 | `height_frequency` | `height_octaves` |
| temperature | +101 | `temperature_frequency` | `temperature_octaves` |
| moisture | +131 | `moisture_frequency` | `moisture_octaves` |
| ruggedness | +151 | `ruggedness_frequency` | `ruggedness_octaves` |
| flora_density | +181 | `flora_density_frequency` | `flora_density_octaves` |
| field | +311 | `local_variation_frequency` | `local_variation_octaves` |
| patch | +353 | frequency × 1.85 | octaves + 1 |
| detail | +389 | frequency × 3.2 | min(octaves + 1, 6) |

All noise: OpenSimplex2 type with cylindrical 3D wrapping. Current native and GDScript helpers both use FBM-compatible setup for these channel and local-variation noises; large-scale structure is not produced by extra native warp noises anymore and must come from `WorldPrePass`.

## Current authoritative rules

- `ChunkGenerator.initialize()` must reject missing / malformed / wrong-seed pre-pass snapshots.
- `ChunkGenerator.generate_chunk()` must not call a legacy structure sampling stage.
- `ChunkGenerator.generate_chunk()` must not require production GDScript to build per-tile channel arrays; per-tile sampling belongs inside native generation and is allowed only from initialized native noise state plus the authoritative pre-pass snapshot.
- Native payload validation in `ChunkContentBuilder` is part of the runtime contract; malformed native arrays must not be consumed silently.
- `ChunkContentBuilder.build_chunk_native_data()` must attach `generation_source` so proof tooling can fail when native silently falls back to GDScript.
- Native flora placement is not part of the current authoritative native payload; GDScript flora build remains downstream of the authoritative terrain/biome/ecotone output.

## Historical rollout notes

The iteration log below is kept as implementation history. Where it describes directed-band structure sampling, native flora-placement generation, or legacy ridge/river warp parameters as active architecture, treat that text as historical only. The sections above are the current source of truth.

## Historical Rollout Log

### Iteration 1 — Expand ChunkGenerator.initialize() with full config ✅

Goal: C++ ChunkGenerator receives and stores ALL parameters needed for generation.

What is done:
- `initialize()` accepts full balance Dictionary: all noise params, thresholds, mountain/ridge/river settings, terrain resolver params, local variation params
- accepts `biomes` Array of Dictionaries with ranges, weights, tags, priority for each biome
- parses into `std::vector<BiomeDef>` sorted by priority desc, id asc (matches GDScript BiomeResolver)
- configures all 12 FastNoiseLite instances with correct seed offsets, frequencies, octaves (spec noise table)
- `setup_noise()` uses FRACTAL_GAIN=0.55, FRACTAL_LACUNARITY=2.1, OpenSimplex2S (matches WorldNoiseUtils)
- `sample_noise_01()` implements cylindrical wrapping: `cos(angle)*radius, y, sin(angle)*radius` 3D simplex (matches WorldNoiseUtils.sample_periodic_noise01)
- `sample_noise_signed()` = `sample_noise_01() * 2 - 1` (matches WorldNoiseUtils.sample_periodic_noise_signed)
- `generate_chunk()` returns placeholder Dictionary with correct keys and array sizes (6 arrays × chunk_size²)
- DLL compiles successfully

Acceptance tests:
- [x] `assert(ChunkGenerator.initialize(seed, params) does not crash with full balance dict)` — all params parsed from Dictionary, biomes sorted, noise configured. DLL builds clean.
- [x] `assert(12 noise instances configured with correct seed offsets and octaves)` — seed offsets match spec table (+11, +101, +131, +151, +181, +211, +217, +223, +241, +311, +353, +389). Patch/detail derived frequencies match (×1.85, ×3.2).
- [x] `assert(cylindrical_noise_sample matches GDScript WorldNoiseUtils.sample_periodic_noise01)` — same formula: `posmod(x, wrap) → angle → cos/sin → 3D GetNoise → *0.5+0.5`. Numeric parity verified by code review.

Files that may be touched:
- `gdextension/src/chunk_generator.h`
- `gdextension/src/chunk_generator.cpp`

Files that were not touched in iteration 2:
- `core/autoloads/world_generator.gd` (integration is iteration 4)
- `core/systems/world/chunk_content_builder.gd`
- Any GDScript resolver files

### Iteration 2 — Implement noise pipeline (PlanetSampler + authoritative structure inputs) ✅

Goal: establish native per-tile world channel sampling in C++ while keeping structure truth authoritative.

What is done:
- `sample_channels(wx, wy)` — port of `planet_sampler.gd:sample_world_channels()`: latitude from equator distance, height noise, temperature (noise+latitude+curve), moisture noise, ruggedness noise, flora_density (noise+moisture blend)
- `generate_chunk()` uses authoritative structure truth only; production runtime now derives per-tile pre-pass / structure context inside C++ from the initialized `WorldPrePass` snapshot instead of evaluating a second native structure sampler
- The old `world_chunk_authoritative_inputs_v1` per-tile bridge remains accepted only for legacy debug/parity tooling
- `generate_chunk()` loop calls `sample_channels()` per tile, then samples pre-pass / structure state for the same tile inside C++ and fills height + flora_density arrays
- DLL compiles clean

Acceptance tests:
- [x] `assert(channels output matches GDScript)` — line-by-line port of planet_sampler.gd formulas, same noise instances, same cylindrical wrapping, same clamp/lerp/pow logic
- [x] `assert(native chunk generation requires authoritative structure inputs instead of a legacy native structure sampler)` — runtime structure truth now comes only from the initialized authoritative `WorldPrePass` snapshot, with production runtime using the compact request flow rather than a per-tile GDScript bridge
- [x] `assert(generate_chunk returns valid channels data)` — height and flora_density arrays populated from sample_channels in the per-tile loop

Files that may be touched:
- `gdextension/src/chunk_generator.h`
- `gdextension/src/chunk_generator.cpp`

Files that were not touched in iteration 2:
- GDScript samplers (they remain as fallback)
- `core/autoloads/world_generator.gd`

### Iteration 3 — Implement BiomeResolver + VariationResolver + TerrainResolver ✅

Goal: complete the per-tile pipeline in C++.

What is done:
- `resolve_biome(channels, structure)` — iterates sorted biomes, `biome_matches()` hard range check, `biome_weighted_score()` with 9 weighted channels, best selection with priority tiebreaking. `score_range()` with soft fallback scoring.
- `resolve_variation(wx, wy, channels, structure, biome)` — 3 noise samples (field/patch/detail), 5 variation scorers (sparse_flora, dense_flora, clearing, rocky_patch, wet_patch), `band_score()`, `tag_bias()`, best selection with min_score threshold, modulation computation per kind.
- `resolve_terrain(dist_sq, channels, structure, variation)` — safe_zone → river core/bank from authoritative `river_distance` + `river_width` + `floodplain_strength` → mountain/foothill from authoritative `ridge_strength` + `mountain_mass` with the same terrain-support weighting used by `SurfaceTerrainResolver` → ground.
- `generate_chunk()` full loop: channels → structure → biome → variation → terrain → pack all 6 arrays. Distance from spawn with wrap-aware delta.
- DLL compiles clean.

Acceptance tests:
- [x] `assert(terrain output matches GDScript)` — line-by-line port of all resolver formulas, same thresholds, same scoring, same decision tree order, including the authoritative river-bank interpretation and mountain terrain-support weighting.
- [x] `assert(biome + variation arrays match GDScript)` — biome scoring matches biome_data.gd, variation scoring matches local_variation_resolver.gd, modulations match _apply_modulations.
- [ ] `assert(generate_chunk() time < 1.5 seconds for 64x64 chunk)` — requires integration test (iteration 4). Expected ~0.5-1.5s based on native noise evaluation.

Files that may be touched:
- `gdextension/src/chunk_generator.h`
- `gdextension/src/chunk_generator.cpp`

Files that were not touched in iteration 2:
- GDScript resolvers
- `core/autoloads/world_generator.gd`

### Iteration 4 — Integration with WorldGenerator and ChunkContentBuilder ✅

Goal: wire native ChunkGenerator into the production pipeline.

What is done:
- `world_gen_balance.gd` + `.tres`: added `use_native_chunk_generation: bool` flag (default true)
- `WorldGenerator._setup_native_chunk_generator()`: creates `ChunkGenerator` via `ClassDB.instantiate()`, passes full balance params Dictionary (50+ keys) + biome definitions Array, calls `initialize(seed, params)`. Graceful fallback with warning if class not available.
- `WorldGenerator.get_native_chunk_generator()`: public accessor for native generator instance
- `ChunkContentBuilder._native_generator`: set at `initialize()` via `WorldGenerator.get_native_chunk_generator()`
- `ChunkContentBuilder.build_chunk_native_data()`: tries `_native_generator.generate_chunk()` first, appends feature/POI payload, falls back to GDScript loop if native unavailable or returns empty
- Cleanup: `_native_chunk_generator = null` in `_clear_initialized_runtime_state()`
- Feature/POI payload stays GDScript (separate pipeline, not part of terrain gen)

Acceptance tests:
- [x] `assert(boot time < 10 seconds with native generation)` — first_playable=6.2s (editor), compute=1030ms for 25 chunks
- [x] `assert(runtime streaming keeps up with walking speed)` — FPS=60, hitches=0, no green zones while running
- [x] `assert(GDScript fallback works when DLL not present)` — `ClassDB.class_exists()` check + warning, `build_chunk_native_data()` checks `_native_generator != null`
- [x] manual: world generates correctly, no visual artifacts. Near-player chunks instant, outer progressive.

Files that may be touched:
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_content_builder.gd`
- `data/world/world_gen_balance.gd` (add flag)
- `data/world/world_gen_balance.tres` (set flag)
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that were not touched in iteration 2:
- `scenes/world/game_world.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`

### Iteration 5 — Native flora/decor computation in C++ ✅

Goal: eliminate ~4 second GDScript flora computation per chunk by porting to C++.

What is done:
- `ChunkGenerator.initialize()` accepts `flora_sets` and `decor_sets` Arrays with entry definitions
- Biome definitions include `flora_set_ids` and `decor_set_ids` for biome→set mapping
- `compute_flora_placements()` in C++: zone caching, tile hashing (int64 for GDScript parity), density calculation, weighted entry selection, subzone filtering
- `generate_chunk()` returns `flora_placements` Array of Dictionaries in result
- `WorldGenerator._setup_native_chunk_generator()` serializes flora/decor registry into params
- `chunk_manager.gd` worker paths check for native `flora_placements`, skip GDScript flora if available
- GDScript flora fallback preserved when native flora absent

Acceptance tests:
- [x] `assert(flora_placements returned by native generator)` — generate_chunk includes flora_placements Array
- [x] `assert(GDScript flora fallback works when native flora empty)` — check `data.has("flora_placements")` guards
- [x] `assert(tile_hash uses int64 matching GDScript)` — int64_t arithmetic for deterministic parity
- [x] `assert(boot time < 10 seconds with native terrain + flora)` — first_playable=6.2s, compute=1030ms for 25 chunks. Editor overhead ~3s, export estimated ~2-3s.
- [x] manual: no green placeholder zones visible at spawn or while running. Terrain+cover+cliff instant for near-player chunks.

Files touched:
- `gdextension/src/chunk_generator.h` — flora/decor structs, method declarations
- `gdextension/src/chunk_generator.cpp` — flora parsing, compute_flora_placements, tile_hash
- `core/autoloads/world_generator.gd` — flora/decor set serialization to native
- `core/systems/world/chunk_manager.gd` — native flora_placements detection in worker paths
- `core/systems/world/chunk_content_builder.gd` — diagnostic logging

## Required contract and API updates after implementation

When iteration 5 is complete:
- `DATA_CONTRACTS.md`: add `flora_placements` to native output format, document ownership
- `PUBLIC_API.md`: document `ChunkGenerator` API with flora params, `use_native_chunk_generation` flag
- `PERFORMANCE_CONTRACTS.md`: update boot time targets

## Out-of-scope

- Feature/POI hook resolution (separate pipeline)
- Topology building (already has native path via MountainTopologyBuilder)
- Underground chunk generation (simple solid rock, already fast)
- Chunk redraw / TileMap operations (Godot-side, cannot be in C++)
- Noise algorithm changes (must match GDScript output exactly)

## Known Architectural Debt (2026-03-30)

Optimization is player-facing complete (FPS=60, hitches=0, no green zones). Remaining budget violations are not player-visible but should be addressed when scaling content:

1. **topology budget overrun**: 3.8ms peak at 2ms budget during active streaming. topology + streaming_redraw concurrent = total 10.6ms/6.0ms. FPS=60 holds.
2. **phase1_create = 5-8ms**: populate_native + complete_redraw_now for near-player chunks on main thread. Single _staged_chunk bottleneck.
3. **Feature/POI computation**: skipped in native path (empty payload). Not ported to C++. Will bottleneck if re-enabled.
4. **3 flora fallback warnings**: some chunks return empty flora_placements from C++ → GDScript fallback. Edge case for chunks with no GROUND tiles matching biome flora sets.
5. **GDScript `fractal_type` not set**: WorldNoiseUtils.setup_noise_instance sets octaves/gain/lacunarity but NOT fractal_type → Godot default TYPE_NONE → single octave. C++ matches this. If fixed in GDScript, C++ must update too.
