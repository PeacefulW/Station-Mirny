# Tech Plan — Data-Oriented World Core for Station Mirny

Status: draft tech plan (pre-spec)
Target: Station Mirny, Godot 4.6, 2D top-down, GDScript orchestration + GDExtension C++ core
Plan owner: engineering
Alignment target: ADR-0001, ADR-0002, ADR-0003, ADR-0005, ADR-0006, ADR-0007, `docs/02_system_specs/world/world_grid_rebuild_foundation.md`, `docs/00_governance/ENGINEERING_STANDARDS.md`

---

## 1. Context

The post-deletion world runtime is absent in code. Stub references to a chunk manager exist in `core/entities/player/player.gd` and `core/systems/building/building_system.gd`, but no chunk manager, chunk generator, chunk view, streamer, or persisted per-chunk diff pipeline is instantiated. `gdextension/` carries only the godot-cpp submodule and a minimal `SConstruct`; `gdextension/src/` is empty. GDScript infrastructure that the new world runtime must plug into already exists: `FrameBudgetDispatcher`, `TimeManager`, `EventBus`, `SaveManager`, `ItemRegistry`, `BiomeRegistry`, `FloraDecorRegistry`, `WorldPerfProbe`, `RuntimeDirtyQueue`, `RuntimeBudgetJob`, `RuntimeWorkTypes`.

The canonical rebuild contract is already locked: one tile = 32 px, one chunk = 32×32 tiles, world X wraps cylindrically, world Y does not. Base world is immutable and reconstructible from `world_seed + chunk_coord + world_version`; runtime state is a per-chunk diff; environment runtime is layered on top of worldgen (stable base → slow world state → local runtime → presentation). Light is a gameplay-authoritative value, not a renderer scrape. Subsurface is a separate streaming layer.

This plan replaces the ad-hoc narrative direction the user dictated with an implementation-shape that fits the living governance docs exactly. It deliberately does not authorize code changes — the first artifact is a system spec set, not a `.cpp` file.

## 2. Goals and Non-Negotiables

Goals:
- reintroduce a chunked world runtime that scales cleanly to hundreds of hot-loaded chunks and arbitrary cold diffs
- keep the interactive path bounded at <2 ms per local mutation (ADR-0001, ENGINEERING_STANDARDS.md Law 0, Law 11)
- move all per-chunk heavy compute (noise, biome resolve, placement, mask solve, packet build, cold diff merge) into GDExtension C++ workers
- keep all scene-tree mutation on the main thread, budgeted through `FrameBudgetDispatcher`
- support mountains, biomes, seasons, snow, ice, weather without rewriting the generator or stream path later
- keep save files small by persisting only runtime diffs on top of a deterministic base (ADR-0003)

User-directed non-negotiables folded into this plan:
1. Use existing `TimeManager` as canonical time authority. Do not introduce `SunSystem` or any parallel time owner.
2. Target Godot 4.6 (already declared in `project.godot` `features = ("4.6", "GL Compatibility")`). Bump `gdextension/station_mirny.gdextension` `compatibility_minimum` to `4.3` → `4.3`/`4.6` consistent (keep `4.3` for forward-compat of any 4.3+ editor, document 4.6 as primary target).
3. The velocity-biased forward lobe must be a parameter of the single existing streaming policy, not a second streamer. There is one streamer with an asymmetric ring descriptor.
4. Layer model must match ADR-0003 (immutable base + runtime diff) and ADR-0007 (environment runtime layered above worldgen). No new parallel vocabulary: use `canonical base / runtime diff / environment overlay / presentation`, map 1:1 to the ADRs.
5. TileMap runtime path must never trigger a whole-chunk or whole-world rebuild. This rule is stated in the spec and enforced by code boundaries (see §9).

Non-goals for this plan: multiplayer wire protocol, BRG-style rendering, 3D, Unity evaluation, migration from pre-rebuild `64×64` saves (deferred by `world_grid_rebuild_foundation.md`).

## 3. Four-Layer World Model (maps to existing ADRs)

The user proposed a 4-layer split. The plan keeps the split but renames and re-anchors each layer to existing canonical docs so no new parallel vocabulary is introduced.

| Plan layer              | Canonical anchor           | Owner (new class)          | Mutates?          | Persisted?          |
|-------------------------|----------------------------|----------------------------|-------------------|---------------------|
| Canonical base          | ADR-0003 immutable base    | `WorldCore` (C++)          | never             | no (from seed)      |
| Runtime diff            | ADR-0003 runtime diff      | `WorldDiffStore` (GDScript thin + C++ merge) | player/system mutations | yes (per-chunk)     |
| Environment runtime     | ADR-0007 slow + local      | Future environment-runtime owner | simulation ticks  | slow state only     |
| Presentation            | ADR-0007 presentation      | `WorldView` / `ChunkView` (GDScript) | view-local        | no                  |

Rules (carried from the ADRs, repeated here for plan-level clarity):
- canonical base never mutates after generation; mountains, biome classification, and base resource spots are base
- seasonal snow cover is a presentation layer driven by environment runtime + time/season — not a new world generation pass
- all visuals derive from `base + diff + overlay`; view state is never authoritative

Cross-layer read rules:
- worldgen never reads environment runtime (ADR-0007)
- presentation never mutates base or diff; may only subscribe to events
- environment overlay may read base (biome base temperature, altitude) but not mutate it
- runtime diff is the only authoritative mutable gameplay state between sessions

## 4. Runtime Work Classes (ADR-0001) Applied to the World Runtime

Per ADR-0001 the new world stack classifies every code path into one of four classes. This is the gating contract.

| Path                                                                 | Class          | Budget                           |
|----------------------------------------------------------------------|----------------|----------------------------------|
| Player places a building / mines one tile / steps                    | interactive    | <2 ms per call                   |
| Chunk generation (noise, biome solve, placement, mask, packet build) | background worker + compute/apply | worker off-thread, apply ≤1.5 ms/frame per chunk slice |
| Chunk publish to scene tree (TileMapLayer apply, MultiMesh attach, collisions, visibility toggle) | background apply | dispatcher STREAMING category, slice-bounded |
| Topology / diff / room / power recompute                             | background     | dispatcher TOPOLOGY category     |
| Presentation fill (grass, decor, far shadows)                        | background     | dispatcher VISUAL category       |
| Initial chunk bubble load + topology prime                           | boot           | behind loading screen            |
| TimeManager tick, overlay slow-state advance                         | background     | TOPOLOGY or LOW_FREQUENCY cadence |

Three independent budgets (the user's "three bubbles / three budgets" model), mapped onto the existing `FrameBudgetDispatcher`:
- **generation budget** → worker-thread budget (not dispatcher); uses `WorkerThreadPool` tasks that call into C++
- **publish budget** → `FrameBudgetDispatcher` `CATEGORY_STREAMING` (current order: streaming > topology > visual > spawn)
- **simulation budget** → `FrameBudgetDispatcher` `CATEGORY_TOPOLOGY` for overlay advance / recompute

No new dispatcher category. The four existing categories already carry the contract.

## 5. Streaming Policy — One Streamer, Asymmetric Ring Descriptor

Per the user's fourth constraint the forward-lobe is not a parallel system. There is a single `WorldStreamer` (GDScript orchestrator, C++ ring math), and it consumes a single policy object:

```
struct StreamingPolicy {
  int   data_ring_radius_base        // hidden data ring baseline (chunks)
  int   visible_ring_radius_base     // chunks with gameplay-critical layers ready
  int   simulation_ring_radius_base  // chunks that tick overlays + AI
  float forward_lobe_gain            // 0.0 = symmetric, 1.0 = full asymmetric lead
  float forward_lobe_cos_min         // angular envelope for the lobe
  float lead_time_seconds            // = p95_chunk_ready_time + safety_margin
  int   p95_chunk_ready_ms           // measured, updated by WorldPerfProbe
}
```

The streamer computes each tick:
- forward vector from player/transport velocity (or zero when stationary → fully symmetric)
- per-candidate chunk: `base_radius + forward_lobe_gain * max(0, cos(angle) - forward_lobe_cos_min) * (speed * lead_time_seconds)`
- per-chunk target state: Absent / Requested / GeneratingData / ReadyCritical / Visible / ReadyCosmetic / Dormant / Evicting

Three overlapping sets (the "three rings"):
- **data set** = chunks with generated `ChunkPacket` in RAM (may be Dormant)
- **visible set** = chunks attached to the render scene tree
- **simulation set** = chunks with overlay tick subscribers

Rules:
- data set ⊇ visible set ⊇ simulation set, with optional exception for remote simulation events (none in V1)
- wrap-world is respected (ADR-0002): X distance uses modular arithmetic; Y does not wrap
- surface vs subsurface follow ADR-0006: Z-level manager streams only the active Z and its immediate neighbors; no streamer crosses Z-levels silently

The streamer never shows a chunk whose gameplay-critical layers are not ready. Cosmetic layers may arrive after publish (ENGINEERING_STANDARDS.md Law 10).

## 6. Chunk Life Cycle and Packet Shape

Chunk states (single-word enum, owned by `WorldStreamer`):

```
Absent → Requested → GeneratingData → ReadyCritical → Visible → ReadyCosmetic
                                    ↘ Dormant (data kept, view detached)
                                    ↘ Evicting (data dropped, diff flushed to save sink if dirty)
```

Transitions are driven by the streamer tick; dispatcher only executes slices, it does not own state.

`ChunkPacket` is one compact native-to-script boundary crossing per chunk (ENGINEERING_STANDARDS.md Law 6). Proposed shape (native-side, exposed as `Dictionary` of `Packed*Array` fields — packet_schemas.md must be updated before code, see §11):

| Field                       | Type                    | Notes                                                      |
|-----------------------------|-------------------------|------------------------------------------------------------|
| `chunk_coord`               | `Vector2i`              | canonical, wrap-safe on X                                  |
| `world_seed`                | `int`                   | mirrors save meta, used for verification on load           |
| `world_version`             | `int`                   | bumped on any canonical generation change (Law 4)          |
| `z_level`                   | `int`                   | surface = 0, subsurface < 0                                |
| `terrain_ids`               | `PackedInt32Array`      | length 1024 (32×32), atlas id per tile                     |
| `flags`                     | `PackedByteArray`       | bitfield per tile: walkable, mountain_block, cliff |
| `tile_variants`             | `PackedInt32Array`      | precomputed atlas variant ids / transition mask ids       |
| `placement_batches`         | `Array[PackedInt32Array]` | per-species packed `[x, y, variant, rotation]`           |
| `resource_spots`            | `PackedInt32Array`      | packed `[x, y, item_id_index, yield_bucket]`              |
| `climate_bytes`             | `PackedByteArray`       | optional `[temp_u8, moisture_u8, continentalness_u8, ridge_u8]` per tile — derived fields only, not authoritative |
| `connector_requests`        | `PackedInt32Array`      | Z-level connectors declared by this chunk (ADR-0006)      |

Never: per-tile Dictionary, per-tile call, nested Dictionary. The boundary is one packet per chunk.

Base chunks are pure f(seed, coord, version). Load path merges the packet with `WorldDiffStore.get_chunk_diff(coord)` before publish. Merge runs in C++ (native cache + diff overlay), main thread only calls `WorldCore.materialize_with_diff(coord)`.

## 7. GDExtension C++ Core — Scope and Layout

The C++ world core is engine-agnostic core + a thin Godot adapter. File layout under `gdextension/src/`:

```
gdextension/src/
  core/                       // engine-agnostic, no Godot dependency
    world_seed.h/.cpp
    world_coords.h/.cpp       // wrap-safe X, identity Y, chunk↔tile↔world conversions
    noise/                    // world channels: height, moisture, temperature, continentalness, ridge
    macro_field_cache.h/.cpp  // lazy macro-cell LRU cache (ADR-0002 wrap-safe)
    terrain_solve.h/.cpp      // base terrain id decision
    biome_solve.h/.cpp        // biome classification over resolved channels
    mountain_solve.h/.cpp     // mountain mass, cliff/block mask
    placement_solve.h/.cpp    // flora/resource/POI batches
    tile_mask_solve.h/.cpp    // atlas variants, transition masks (precomputed!)
    diff_merge.h/.cpp         // base + runtime diff fused output
    chunk_packet.h/.cpp       // POD packet construction
  godot/                      // Godot adapter — uses godot-cpp
    register_types.cpp        // exposes WorldCore, ChunkGenNode, PacketCodec
    world_core.h/.cpp         // GDExtension class: generate_chunk_packet(coord, seed, version) → Dictionary
    packet_codec.h/.cpp       // PackedArray conversions, kept minimal
    worker_tasks.h/.cpp       // WorkerThreadPool-friendly task entry points
```

Rules:
- core/ has zero Godot dependency → compiles standalone, unit-testable with plain C++ test runner
- godot/ is thin: it wraps core calls, converts to `Packed*Array`, owns no gameplay logic
- each core solve is a pure function; the LRU cache lives behind a mutex; no static mutable globals
- generated chunk packets are owned by `WorldCore`; script side holds a handle, not raw pointers

Entry symbol stays `station_mirny_init` (already declared). Build keeps SCons; `gdextension/SConstruct` will add core/ and godot/ source dirs. Target compiler: MSVC (Windows), Clang (Linux). C++20.

`compatibility_minimum = "4.3"` in `station_mirny.gdextension` is retained — the project targets Godot 4.6 for editor, but the extension is safe on any 4.3+ engine; forward-compat is a feature, not a bug.

## 8. GDScript Adapter — What Stays In Script

Only orchestration, apply, UI, save/load, debug. All of these are already present or trivial additions:

| New GDScript class        | Responsibility                                                                                       | Dispatcher category |
|---------------------------|------------------------------------------------------------------------------------------------------|---------------------|
| `WorldStreamer`           | ring math driver (uses C++ for geometry), chunk state machine, enqueue gen / publish / evict         | STREAMING           |
| `ChunkGenQueue`           | thin queue wrapping `WorkerThreadPool` tasks that call `WorldCore.generate_chunk_packet_async(...)`  | —                   |
| `ChunkPublishQueue`       | main-thread publisher: creates/reuses `ChunkView`, applies `TileMapLayer`, attaches MultiMesh        | STREAMING           |
| `ChunkView` (Node2D)      | per-chunk scene root; owns its subchunk TileMapLayers, MultiMesh nodes, collision bodies             | —                   |
| `WorldDiffStore`          | per-chunk diff storage; thin API over native diff representation; save/load collector               | —                   |
| Future environment runtime | slow world state (season/weather), local runtime state (wind, temp), snow flags                    | TOPOLOGY            |
| `WorldMutationCommands`   | `MineTileCommand`, `PlaceTerrainDiffCommand` under existing `CommandExecutor` (LAW 8, LAW 5)         | —                   |

Existing autoloads stay owners:
- `TimeManager` — sole time-of-day authority (user non-negotiable #1). Future environment runtime must subscribe to existing time events. No new time owner.
- `FrameBudgetDispatcher` — sole per-frame budget executor. `WorldStreamer`, `ChunkPublishQueue`, and future environment runtime register jobs here; they do not run their own per-frame loops.
- `EventBus` — domain event fan-out. New events defined in §11.
- `SaveManager` — sole save orchestrator. `WorldDiffStore` plugs in via `SaveCollectors.collect_chunk_data()` / `SaveAppliers.apply_chunk_data()` (current stubs).

GDScript is forbidden from: iterating over tiles in a loop, computing noise, resolving biomes, deciding tile variants, building masks, instantiating one node per flora item. All of these are C++ side.

## 9. TileMap Runtime Path — No Full Rebuilds, Ever

Per user non-negotiable #5 this rule is stated explicitly in the plan and must carry into the world runtime spec.

Rules the spec will document and the code must enforce:
- each `ChunkView` holds its own local TileMapLayers, keyed 0..31 in chunk-local coords; world offset lives on `ChunkView.global_position`. This avoids Godot's TileMapLayer 16-bit serialization edge.
- terrain critical grid goes through TileMapLayer. Mass decor (grass, flowers, small rocks, stubs) goes through `MultiMeshInstance2D`, never node-per-object (Law 13).
- the runtime never calls `set_cells_terrain_connect(...)` or any neighbour-solving TileMap API on a hot streaming path. All transition masks, atlas variants, and autotile results are precomputed in C++ (`tile_mask_solve`) and arrive inside `ChunkPacket.tile_variants`. Apply is `set_cell(coord, source, atlas)` batched by subchunk.
- the publisher applies at most one 16×16 subchunk per frame slice and yields when its dispatcher budget is exhausted. Never `TileMapLayer.clear()` followed by whole-chunk re-apply on a runtime path.
- mining/placement is a single-cell diff apply: `WorldDiffStore.set_diff(coord, tile)` → local `TileMapLayer.set_cell(local_coord, ...)` + `RuntimeDirtyQueue.enqueue(region)` for bounded downstream recompute (rooms, collision shapes). No full chunk redraw.
- chunk eviction hides the `ChunkView`, detaches (not `queue_free`) the TileMapLayer and collision bodies into a small reuse pool; native packet data is dropped with a refcount hit. Re-entry reuses from the pool.

Failure modes the spec must forbid (repeating the ENGINEERING_STANDARDS anti-patterns for clarity):
- `TileMapLayer.clear()` on a loaded chunk from a runtime path
- mass `set_cell` loop over an entire chunk in one frame
- scene-tile path (`TileSetScenesCollectionSource`) for mass decor
- GDScript fallback that loops over 1024 tiles (Law 1, Law 9)

## 10. Save / Load Integration

Persisted state:
- `chunks/<x>_<y>_<z>.json` per dirty chunk diff (schema defined in new `packet_schemas.md` entry)
- `world.json` extended with `world_version` (new field, defaulting to 0 on legacy saves)
- `environment.json` for slow world state (season is already in `time.json`; wind vector baseline and weather cursor go here if implemented)

Not persisted (regenerable):
- base chunk data (regenerated from `world_seed + chunk_coord + world_version`)
- environment local runtime state (wind at a position, spore density)
- presentation

Rules:
- on load: `world_version` from save compared against the current `world_version`. Mismatch is logged and forces canonical regeneration (player diffs still apply onto the newer base; a dedicated migration boundary is deferred per `world_grid_rebuild_foundation.md`).
- `WorldDiffStore.save_state()` / `load_state()` are the only sanctioned entry points; direct writes to `SaveManager.current_slot` are forbidden (`save-load-regression-guard` rule).
- empty-diff chunks do not write a file; the G0/G1 reconciliation behavior in `ADR-0001` §Iteration 6 continues to govern stale file cleanup.

## 11. Spec Work Required Before Any Code

AGENTS.md rule-of-the-house: structural change without an approved spec must stop at spec creation, not coding. This plan therefore blocks on a small spec delta set before any implementation starts.

Required spec/ADR changes (create/refine, in the order they should land):

1. **New system spec**: `docs/02_system_specs/world/world_runtime.md`
   - Scope: chunk life cycle, `ChunkPacket` shape, streaming policy (including forward-lobe parameters), C++/GDScript boundary, TileMap runtime rules, publish rules, eviction/reuse pool, Z-level streaming integration.
   - Cites: ADR-0001, ADR-0002, ADR-0003, ADR-0006, ADR-0007, `world_grid_rebuild_foundation.md`.
   - Establishes the `world_version` semantics and the interactive/background/boot classification for every new code path.

2. **New system spec**: future environment runtime spec
   - Scope: slow world state (season is already owned by `TimeManager`; this spec only adds weather cursor and wind baseline), local runtime derivation of `temp(x,y)`, ice/snow overlay flags, interaction with biome and `TimeManager`.
   - Cites: ADR-0007, ADR-0005.

3. **New ADR** (optional but recommended): `docs/05_adrs/0008-world-core-is-cpp-owned.md`
   - Decision: canonical worldgen, solve, and packet build live in C++ GDExtension; GDScript is orchestration + apply. Confirms Law 1 / Law 9 at the architecture level.

4. **Packet schema update**: `docs/02_system_specs/meta/packet_schemas.md`
   - Add `ChunkPacket` shape (§6) and `ChunkDiffEntry` save shape.
   - Today the file explicitly flags `ChunkPacket` as not yet confirmed — this entry removes that gap.

5. **Event contracts update**: `docs/02_system_specs/meta/event_contracts.md`
   - Confirm emitter+listener for `chunk_loaded`, `chunk_unloaded`, `chunk_evicted`, `chunk_published_critical`, `chunk_published_cosmetic` (signals already declared in `EventBus`).
   - Confirm emitter+listener names for future environment runtime events.

6. **System API update**: `docs/02_system_specs/meta/system_api.md`
   - Add safe reads: `WorldCore.get_tile_at(x, y, z)`, `WorldDiffStore.get_diff(coord)`, and future environment-runtime query surfaces.
   - Add safe mutation paths: `MineTileCommand`, `PlaceTerrainDiffCommand`.

7. **Save/persistence update**: `docs/02_system_specs/meta/save_and_persistence.md`
   - Add `world_version` field, `chunks/*.json` diff layout, environment slow-state file, migration boundary clause.

8. **Glossary**: `docs/00_governance/PROJECT_GLOSSARY.md`
   - Add: `Canonical base`, `Runtime diff store`, `Environment overlay (slow/local)`, `Streaming policy`, `Forward lobe`, `Chunk packet`, `Chunk view`, `Publish budget`.

9. **world_grid_rebuild_foundation.md** iteration 2/3 fleshed out to reference this plan's runtime architecture, without duplicating it.

Until items 1–4 are approved, no `.gd` or `.cpp` work on the new runtime begins. This is the explicit spec-first gate.

## 12. Iteration Roadmap (post-spec-approval)

Each iteration lands a shippable slice under the same streaming contract. No iteration is allowed to introduce a parallel stream architecture; all add parameters and data to the single streamer.

**V1 — Core loop, one biome, no decor.** Surface only (z=0). `WorldCore` generates packets with terrain_ids, flags, a single biome, base resource spots. `WorldStreamer` runs a symmetric ring (forward_lobe_gain=0.0). `ChunkView` applies TileMapLayer from packet. `WorldDiffStore` persists mined-tile diffs. Acceptance: player can walk, chunks stream in and out without hitches, save/load round-trips a dug hole.

**V2 — Mountains.** Layer 2 solves added to `WorldCore`. `world_version` bumps to 1. Mountain_block flag drives collisions.

**V3 — Biomes.** Biome resolver added behind existing `BiomeRegistry`; biomes drive terrain atlas and resource spots. No code branches per biome — data-driven via existing `BiomeData` resources.

**V4 — Environment runtime + seasons.** Future environment runtime subscribes to `TimeManager` and owns seasonal temperature modifier and (later) weather cursor. `world_version` is NOT bumped for overlay changes.

**V5 — Mass decor via MultiMesh.** `placement_batches` consumed by `MultiMeshInstance2D` per species per subchunk. Proximity-activation promotes near-player flora to real interactive objects through `ItemRegistry`-driven factories.

**V6 — Forward-lobe streaming.** `StreamingPolicy.forward_lobe_gain` becomes > 0.0 once `p95_chunk_ready_ms` is stable. Measured from `WorldPerfProbe`. Transport integration supplies the velocity vector. No new streamer, only new parameters.

**V7 — Subsurface.** Z-level streaming per ADR-0006. Separate ring per Z-level, shared policy.

## 13. Critical Files (reference, not a change list)

Read-only referents for the implementation phase, so the work stays localized:

- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- `docs/05_adrs/0002-wrap-world-is-cylindrical.md`
- `docs/05_adrs/0003-immutable-base-plus-runtime-diff.md`
- `docs/05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md`
- `docs/05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md`
- `docs/02_system_specs/world/world_grid_rebuild_foundation.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/event_contracts.md`
- `docs/00_governance/ENGINEERING_STANDARDS.md`
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `core/autoloads/time_manager.gd`
- `core/autoloads/frame_budget_dispatcher.gd`
- `core/autoloads/event_bus.gd`
- `core/autoloads/save_manager.gd`
- `core/runtime/runtime_work_types.gd`
- `core/runtime/runtime_dirty_queue.gd`
- `core/runtime/runtime_budget_job.gd`
- `gdextension/station_mirny.gdextension`
- `gdextension/SConstruct`
- `project.godot` (Godot 4.6 features line)

Files to add (spec phase):
- `docs/02_system_specs/world/world_runtime.md`
- `docs/02_system_specs/world/environment_overlay.md`
- `docs/05_adrs/0008-world-core-is-cpp-owned.md`

Files to add (first implementation iteration, after spec approval):
- `gdextension/src/core/*` (noise, solve, packet)
- `gdextension/src/godot/world_core.h/.cpp` + `register_types.cpp`
- `core/systems/world/world_streamer.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/chunk_publish_queue.gd`
- `core/systems/world/world_diff_store.gd`
- `core/systems/world/streaming_policy.gd` (resource or plain struct)
- `core/commands/world/mine_tile_command.gd`

## 14. Verification

Per-iteration acceptance (applies to V1..V7, tightened later iterations):
- static verification: script parse, extension build succeeds, spec citations grep-verified
- performance contracts (`WorldPerfProbe` contract table updated):
  - interactive mine/build ≤ 2.0 ms (ADR-0001)
  - `FrameBudgetDispatcher.CATEGORY_STREAMING` per-frame total ≤ 2.5 ms average (within 6 ms total)
  - chunk publish slice ≤ 1.5 ms per frame per subchunk
  - p95 chunk ready time measured and logged
- headless world script (`scripts/codex_validate_runtime.sh` or equivalent) extended with a chunk streaming round-trip scenario
- save/load round-trip scenario: mine a tile, save, reload, verify diff applied over freshly regenerated base
- manual human verification: player walk test across a wrap-X seam and into subsurface and back
- canonical docs grep: every new symbol has a hit in `system_api.md`, every new event in `event_contracts.md`, every new schema in `packet_schemas.md`

Rule reminders that gate closure:
- `passed` requires evidence in session (WORKFLOW §Acceptance)
- `not required` for docs requires grep proof (WORKFLOW §Closure)
- any change to canonical base output bumps `world_version` (Law 4)

## 15. Open Questions (resolve during spec-writing)

1. Where do the shared grid constants live (autoload vs balance resource vs dedicated world config)? `world_grid_rebuild_foundation.md` already lists this as open.
2. Should `ChunkPacket` be exposed as typed `Dictionary` or as a native class bound through godot-cpp (with getters)? Default recommendation: typed `Dictionary` of `Packed*Array` for simplicity and pickle-compatibility; revisit only if boundary cost becomes measurable.
3. Does V1 need the reuse pool for `ChunkView` / `TileMapLayer` nodes, or is `free` / re-instantiate fast enough at 32×32? Default: implement the reuse pool from V1 — cheaper to build once than to retrofit.
4. Does future environment runtime need its own dispatcher job id or share `topology` budget with a secondary slice? Default: its own named job for observability.

## 16. Out-of-Scope Observations

- Unity/BRG/DOTS comparison: captured in context of the user directive; not actionable inside Station Mirny.
- Multiplayer authority deltas for the new streamer: ADR-0004 exists; will be revisited in a dedicated follow-up after V1 ships.
- BRG-style rendering path in Godot: out of scope; MultiMesh is the canonical mass rendering path here.
- Pre-rebuild `64×64` save migration: explicitly deferred by `world_grid_rebuild_foundation.md`.

---

End of tech plan.
