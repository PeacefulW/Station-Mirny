# Epic: Mountain Reveal And World Perf Recovery

**Spec**: `docs/02_system_specs/world/mountain_reveal_and_world_perf_recovery_spec.md`
**Started**: 2026-04-09
**Current iteration**: 2
**Total iterations**: 3

## Documentation debt

Track required documentation updates from the spec's "Required contract and API updates"
section. Review every iteration and update immediately if semantics drift.

- [ ] `DATA_CONTRACTS.md` — Mining post-mine reveal/topology consequence chain; Topology role of `query_local_underground_zone()` after Iteration 2; Reveal mined-tile/component refresh semantics and delta-apply policy; Presentation bounded cover/shadow publication contract; World Pre-pass native kernel ownership and invariants
- [ ] `PUBLIC_API.md` — `ChunkManager.try_harvest_at_world()` postconditions if roof/reveal semantics become stricter; `ChunkManager.query_local_underground_zone()` semantics after Iteration 2; `WorldGenerator.build_chunk_native_data()` / `ChunkGenerator.generate_chunk()` bridge semantics after Iteration 3
- **Deadline**: review every iteration; required updates must land in the iteration where semantics change, and no later than Iteration 3
- **Status**: pending

## Iterations

### Iteration 1 — Correctness-first roof reveal fix
**Status**: blocked
**Started**: 2026-04-09
**Completed**: —

#### Acceptance tests
- [ ] manual: on a fixed seed, mining the first mountain entrance from outside removes the stale roof over the opened entrance and the roof does not remain visible over an already opened tile — BLOCKED: no sanctioned visual proof artifact captured in this headless session
- [ ] manual: on a fixed seed, performing the same action near a loaded chunk seam still converges correctly on both touched chunks — BLOCKED: seam-specific visual proof was not run in-session
- [x] static/code proof: `MountainRoofSystem` no longer relies only on `_is_player_on_opened_mountain_tile()` to decide whether a mining-triggered refresh is needed — verified by file read/grep in `core/systems/world/mountain_roof_system.gd` (`_find_mining_refresh_start` at lines 251-260, `_should_reuse_active_zone_seed` at lines 263-270, `_needs_zone_refresh` assignment at lines 292-293)
- [x] static/code proof: no new direct terrain write path is introduced outside `ChunkManager.try_harvest_at_world()` — verified by `rg "_set_terrain_type|mark_tile_modified|set_mining_write_authorized|try_mine_at\\(" core/systems/world/mountain_roof_system.gd core/debug/runtime_validation_driver.gd` => `0 matches`
- [ ] runtime proof: repeated mining on the sanctioned route produces no `ERROR` or `assert` — BLOCKED: headless runtime proof completed the mining validation and showed `0 matches` for `validation failed|assert`, but Godot still emitted shutdown `ERROR: 16 resources still in use at exit`

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `ChunkManager.try_harvest_at_world` matches at lines 319, 329, 340, 347, 350, 699, 700; `EventBus.mountain_tile_mined` at 343, 345, 427, 428, 522, 713, 714; `query_local_underground_zone` at 357, 368, 369, 733, 748, 769, 1474; `_is_player_on_opened_mountain_tile` at 714; `_find_mining_refresh_start|_should_reuse_active_zone_seed` => `0 matches`
- [x] Grep `PUBLIC_API.md` for changed names — `ChunkManager.try_harvest_at_world` matches at lines 41, 150, 158, 173, 183, 312, 314, 371, 452, 715, 1582; `EventBus.mountain_tile_mined` at 183, 534; `query_local_underground_zone` at 340; `_find_mining_refresh_start|_should_reuse_active_zone_seed|_is_player_on_opened_mountain_tile` => `0 matches`
- [x] Documentation debt section reviewed — Iteration 1 semantics updated in both canonical docs; broader Iterations 2-3 doc items remain pending

#### Files touched
- `.claude/agent-memory/active-epic.md` — started Iteration 1 tracking for this spec
- `core/systems/world/mountain_roof_system.gd` — replaced player-only mining refresh gate with explicit mining-seed selection and active-zone reuse
- `core/debug/runtime_validation_driver.gd` — added headless proof checks/logs for first-entrance reveal activation from exterior
- `docs/00_governance/PUBLIC_API.md` — documented surface mining-triggered reveal refresh semantics for Iteration 1
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — documented reveal/mining invariants and postconditions for mining-triggered surface refresh

#### Closure report
## Closure Report

### Implemented
- `MountainRoofSystem` no longer seeds mining-triggered surface refresh only from the player tile.
- Added explicit mining refresh selection order: reuse active zone seed when the mined tile touches the active zone, otherwise seed from the mined open tile, and only then fall back to the player tile if the player is already inside an opened pocket.
- Headless runtime mining validation now proves that the first mined entrance activates a local reveal zone before the player steps inside.
- Updated `DATA_CONTRACTS.md` and `PUBLIC_API.md` to reflect the stricter Iteration 1 reveal semantics.

### Root cause
- `MountainRoofSystem._on_mountain_tile_mined()` only set `_needs_zone_refresh` when `_is_player_on_opened_mountain_tile(player_tile)` was already true, while `_find_reveal_start()` only seeded from the player tile. Mining the first entrance from outside therefore did not schedule a reveal refresh from the newly opened tile and could leave stale roof cover visible.

### Files changed
- `.claude/agent-memory/active-epic.md` — Iteration 1 tracking, doc check, and closure report
- `core/systems/world/mountain_roof_system.gd` — explicit mining refresh seed logic and non-player-only refresh trigger
- `core/debug/runtime_validation_driver.gd` — first-entrance-from-exterior reveal proof logging
- `docs/00_governance/PUBLIC_API.md` — public reveal/mining semantics updated
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — reveal/mining contract updated

### Acceptance tests
- [ ] manual: first entrance mined from outside removes stale roof over the opened entrance — BLOCKED (headless session; no visual proof artifact captured)
- [ ] manual: seam-adjacent first entrance still converges on both touched chunks — BLOCKED (manual seam proof not run in-session)
- [x] static/code proof: `MountainRoofSystem` no longer relies only on `_is_player_on_opened_mountain_tile()` — verified by file read/grep in `core/systems/world/mountain_roof_system.gd` (lines 244-260 and 292-293)
- [x] static/code proof: no new direct terrain write path outside `ChunkManager.try_harvest_at_world()` — verified by `rg` returning `0 matches` in changed non-owner files
- [ ] runtime proof: repeated mining on the sanctioned route produces no `ERROR` or `assert` — BLOCKED (`validation failed|assert` grep returned `0 matches`, mining validation completed, but Godot shutdown still emitted `ERROR: 16 resources still in use at exit`)

### Proof artifacts
- Seed: `12345`
- Harness / mode: `RuntimeValidationDriver` via `res://scenes/world/game_world.tscn` with `codex_validate_runtime` and `codex_validate_route=local_ring`
- Artifacts: `debug_exports/perf/mountain_reveal_iteration1_runtime_seed12345.log`
- Visible proof status: blocked for this iteration in the current headless session

### Performance artifacts
- Seed: `12345`
- Harness / mode: `RuntimeValidationDriver`
- Command: `.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_validate_runtime codex_validate_route=local_ring codex_world_seed=12345`
- Log: `debug_exports/perf/mountain_reveal_iteration1_runtime_seed12345.log`
- Summary: not applicable
- Checked lines / metrics: `first entrance reveal activated from exterior`, `entered mined pocket`, `mining + persistence validation complete`, `validation failed|assert`
- `ERROR` / `WARNING`: warnings present from existing boot/streaming/shadow perf debt; shutdown `ERROR: 16 resources still in use at exit` still present and blocks this acceptance line

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `ChunkManager.try_harvest_at_world`: matches at lines 319, 329, 340, 347, 350, 699, 700 — updated where Iteration 1 semantics changed
- Grep `DATA_CONTRACTS.md` for `EventBus.mountain_tile_mined`: matches at lines 343, 345, 427, 428, 522, 713, 714 — updated where Iteration 1 semantics changed
- Grep `DATA_CONTRACTS.md` for `query_local_underground_zone`: matches at lines 357, 368, 369, 733, 748, 769, 1474 — still accurate for Iteration 1
- Grep `DATA_CONTRACTS.md` for `_is_player_on_opened_mountain_tile`: match at line 714 — updated
- Grep `DATA_CONTRACTS.md` for `_find_mining_refresh_start|_should_reuse_active_zone_seed`: `0 matches` — internal helpers not referenced
- Grep `PUBLIC_API.md` for `ChunkManager.try_harvest_at_world`: matches at lines 41, 150, 158, 173, 183, 312, 314, 371, 452, 715, 1582 — updated where Iteration 1 semantics changed
- Grep `PUBLIC_API.md` for `EventBus.mountain_tile_mined`: matches at lines 183, 534 — still accurate
- Grep `PUBLIC_API.md` for `query_local_underground_zone`: match at line 340 — still accurate for Iteration 1
- Grep `PUBLIC_API.md` for `_find_mining_refresh_start|_should_reuse_active_zone_seed|_is_player_on_opened_mountain_tile`: `0 matches` — internal helpers not referenced
- Spec "Required updates" section: exists — Iteration 1 Mining / Reveal / `ChunkManager.try_harvest_at_world()` semantics updated now; later Iteration 2-3 doc items remain pending

### Out-of-scope observations
- The runtime proof still shows substantial pre-existing boot/streaming/shadow budget warnings unrelated to this correctness-first Iteration 1 scope.
- Godot still emits the pre-existing shutdown resource-leak `ERROR` at the end of the headless validation run.

### Remaining blockers
- Capture sanctioned visual proof for the first entrance mined from outside.
- Capture sanctioned visual proof for the seam-adjacent case.
- Resolve or explicitly waive the existing headless shutdown `ERROR` so the runtime acceptance line can be marked passed honestly.

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `EventBus.mountain_tile_mined`, `ChunkManager.try_harvest_at_world`, and `_is_player_on_opened_mountain_tile`

### PUBLIC_API.md updated
- updated — grep evidence recorded above for `ChunkManager.try_harvest_at_world`

#### Blockers
- manual visual proof for first entrance / seam case is still missing
- headless runtime proof still exits with the pre-existing Godot resource-use `ERROR`

---

### Iteration 2 — Evict reveal/topology hot work from the main thread
**Status**: blocked
**Started**: 2026-04-09
**Completed**: —

#### Acceptance tests
- [x] fixed-seed runtime mining proof shows no `ChunkManager.query_local_underground_zone` contract warnings in the hot mining path — verified by `rg -n "WorldPerf\\] WARNING: ChunkManager\\.query_local_underground_zone" debug_exports/perf/mountain_reveal_iteration2_runtime_seed12345.log` => `0 matches`
- [ ] fixed-seed runtime mining proof shows no `MountainRoofSystem._refresh_local_zone` or `MountainRoofSystem._request_refresh` contract warnings — BLOCKED: latest proof still reports `_refresh_local_zone took 3.48 ms` and `_request_refresh took 5.42 ms` / `8.59 ms`
- [ ] fixed-seed runtime mining proof keeps `ChunkManager.try_harvest_at_world()` below the `< 2 ms` synchronous contract — BLOCKED: latest proof still reports `6.77 ms` and `8.22 ms`
- [x] fixed-seed runtime mining/traversal proof keeps `FrameBudgetDispatcher.topology.chunk_manager.topology_rebuild` within the `1-2 ms` intended envelope on average and eliminates the current triple-digit spike class — verified by repeated `chunk_manager.topology_rebuild=0.0ms(...)` lines in `debug_exports/perf/mountain_reveal_iteration2_runtime_seed12345.log`
- [ ] fixed-seed runtime mining proof keeps `MountainRoofSystem._process_cover_step` within the `2 ms` contract per chunk, or further splits the work until that is true — BLOCKED: latest proof still reports `_process_cover_step (2, 1) took 24.29 ms`
- [ ] manual: after repeated mining inside mountains and across loaded seams, roof and shadow converge without stale visible cover over already opened tiles — not run in-session; only headless proof captured

#### Doc check
- [ ] Grep `DATA_CONTRACTS.md` for changed names — pending
- [ ] Grep `PUBLIC_API.md` for changed names — pending
- [ ] Documentation debt section reviewed — pending

#### Files touched
- `.claude/agent-memory/active-epic.md` — advanced tracking to Iteration 2 and recorded current blockers
- `core/systems/world/mountain_roof_system.gd` — topology-first reveal query, truncated-zone incremental growth, live-state cover diff attempts, and delta-first queueing refinements
- `core/systems/lighting/mountain_shadow_system.gd` — moved mining-triggered shadow edge invalidation to queued edge/shadow dirty work instead of synchronous cache mutation
- `core/systems/world/chunk.gd` — exposed live revealed-cover readback for queued cover publication decisions

#### Closure report
Iteration 2 made real architecture progress but is not closable yet. Runtime proof now shows that mining no longer emits hot-path `ChunkManager.query_local_underground_zone` warnings and `chunk_manager.topology_rebuild` stays at `0.0ms` through the fixed-seed route, which confirms the topology-first / queued-dirty direction is taking effect. However, the iteration still fails the contract gates on seam mining and cover publication: `ChunkManager.try_harvest_at_world()` remains above the `< 2 ms` contract, `MountainRoofSystem._request_refresh` still overruns, and `MountainRoofSystem._process_cover_step` is still effectively doing too much work in one chunk step.

Latest sanctioned proof artifact:
- `debug_exports/perf/mountain_reveal_iteration2_runtime_seed12345.log`

Latest notable proof lines:
- `first entrance reveal activated from exterior; zone_tiles=1`
- `entered mined pocket; zone_tiles=2`
- `mining + persistence validation complete`
- `ChunkManager.try_harvest_at_world took 6.77 ms`
- `ChunkManager.try_harvest_at_world took 8.22 ms`
- `MountainRoofSystem._refresh_local_zone took 3.48 ms`
- `MountainRoofSystem._request_refresh took 5.42 ms`
- `MountainRoofSystem._request_refresh took 8.59 ms`
- `MountainRoofSystem._process_cover_step (2, 1) took 24.29 ms`
- repeated `chunk_manager.topology_rebuild=0.0ms(...)`

#### Blockers
- seam mining still pays too much synchronous work inside `ChunkManager.try_harvest_at_world()` / `Chunk.try_mine_at()`
- `MountainRoofSystem` incremental cover/update path still exceeds contract on `_request_refresh`
- cover publication still needs per-step splitting or another bounded delta path to get `_process_cover_step` under `2 ms`
- manual seam/visual proof remains missing
- headless runtime still exits with the pre-existing `ERROR: 16 resources still in use at exit`

### Iteration 3 — Native C++ migration for the remaining heavy math
**Status**: pending
