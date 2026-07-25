# S2 Candidate Closure — Observable Readiness Contract

Status: `accepted`  
Date: 2026-07-22  
Accepted by user: 2026-07-23  
Baseline: `121331d runtie debugger`  
Probe: `s1_mountain_runtime_baseline_v1`  
Route: `S1-MOUNTAIN-SOUTH-01`

## Outcome

S2 adds read-only diagnostics to the existing `WorldStreamer`; it does not fix
streaming. Every current source-demand chunk now reports its lifecycle stage,
all required layer states, one stable overall blocker when missing, and elapsed
wait time. Retained/evicted transitions are kept in a capped 32-entry terminal
history.

The real deterministic mountain probe continues to expose the current deficit
rather than hiding it: in the final automatic run it observed 49 demanded
chunks, 48 missing, with the following unique blocker distribution:

- `terrain_reserve_not_materialized=24`
- `terrain_publish_queued=19`
- `object_presentation_gpu_upload=4`
- `terrain_publish_applying=1`

This is diagnostic evidence for later subgoals, not an S3/S4 fix.

## Root Cause Addressed by S2

The previous HUD/flight-recorder contract exposed aggregate queue counters but
could not answer which chunk or visual family was late, its current owner state,
or how long that state had lasted. That made a screenshot of a hole impossible
to connect to packet generation, terrain publication, an object/grass worker,
GPU upload, a mask, or the reveal guard.

## Implementation

- `WorldStreamer.get_streaming_readiness_debug_snapshot()` classifies the
  existing packet, publication, view, object, grass, mask, and visibility owner
  dictionaries. It neither schedules nor mutates streaming work.
- `WorldStreamingReadinessTracker` records O(1) transition clocks and a bounded
  terminal history. It is transient derived state and is cleared on world reset.
- Current entries are exactly the current bounded source-demand set. A detailed
  scan runs only for F2, F4 finalization, or an explicit probe; the four-Hz F4
  sampler and ordinary per-frame path remain unchanged.
- Manual F2 JSON sidecars and final F4 `session.json` receive schema version 1
  readiness snapshots. Automatic event captures do not perform the detailed
  scan.
- `Test-S2MountainReadinessCapture.ps1` validates the accepted S1 route and the
  readiness contract without modifying the capture.

## Automatic Verification

All commands completed with exit code 0 on 2026-07-22:

```powershell
godot_console --headless --path . --editor --quit
godot_console --headless --path . --script res://tools/world_streaming_readiness_diagnostics_smoke_test.gd
godot_console --headless --path . --script res://tools/performance_hud_smoke_test.gd
godot_console --headless --path . --script res://tools/world_streaming_queue_cache_smoke_test.gd
godot_console --headless --path . --script res://tools/mountain_runtime_dig_dev_scene_determinism_test.gd
godot_console --headless --path . --script res://tools/world_streaming_readiness_mountain_probe.gd
```

Results:

- script/class parse: PASS
- readiness lifecycle/schema/timing smoke: PASS
- F2-only plus F4-final recorder integration: PASS
- existing streamer queue/cache regression smoke: PASS
- deterministic mountain run: PASS twice; seed `131071`, version `63`, signature
  `b797f4120400f757a08bf5a14e6a6c09721e51fd`, mountain `(2104,464)`, stand
  `(2103,465)`
- deterministic scene-ready samples: `3459.705 ms`, `1919.390 ms`
- real readiness snapshot: `49` entries, `48` missing, `6593 us`
- detailed read left packet-request, publish, and visibility-wait counters
  unchanged before/after the snapshot
- `git diff --check`: PASS
- PowerShell analyzer parse: PASS

The queue/cache smoke deliberately emits its existing synthetic terminal error
and retry warning while testing recovery; it still exits successfully. The two
mountain runners also retain their known Godot ObjectDB/resource-leak warnings
at process shutdown.

## Performance Assessment

The only detailed working-set scan measured `6.593 ms` in a headless debug
probe and is below the probe's `10 ms` soft ceiling. It is not a frame-periodic
operation. Existing FrameBudget samples in the same run were approximately
`0.3 ms` idle and `2.2 ms` during active streaming against the existing `6 ms`
streaming budget; these are contextual samples, not a claimed S2 speedup.

## Files in S2 Scope

- `core/systems/world/world_streaming_readiness_tracker.gd` and generated UID
- `core/systems/world/world_streamer.gd`
- `core/runtime/performance_flight_recorder.gd`
- `tools/world_streaming_readiness_diagnostics_smoke_test.gd` and UID
- `tools/world_streaming_readiness_mountain_probe.gd` and UID
- `tools/performance_hud_smoke_test.gd`
- `tools/agent/Test-S2MountainReadinessCapture.ps1`
- canonical specs: `world_runtime.md`, `performance_flight_recorder.md`,
  `system_api.md`, `packet_schemas.md`
- this task tracker and closure report

Pre-existing dirty S1/governance/dev-scene files and the missing temporary
GDExtension DLL were preserved; no branch, staging, commit, reset, stash, or
cleanup operation was performed.

## Manual Acceptance

The user accepted S2 on 2026-07-23 using raw F4 capture
`20260723_132327_539`. The readiness validator passed:

- `121` current source-demand entries;
- `73` missing entries, all with a concrete stage, blocker, and elapsed time;
- blocker distribution:
  `terrain_reserve_not_materialized=40`,
  `object_presentation_gpu_upload=30`,
  `object_presentation_cpu_ready_not_staged=3`;
- oldest wait:
  `(126,42) terrain/terrain_reserve_not_materialized 42930 ms`;
- `19` manual F2 sidecars with readiness schema version 1.

The unchanged S1 route validator reported a shorter-than-gate sample:
`78.745 s` total, `56.618 s` at zoom `0.2`, and `15109 px` ordinary-route
distance. The user explicitly waived that route-shape shortfall for S2 because
the instrumentation contract itself was proven and the change cannot repair or
redefine streaming behavior. Captured frames continued to show the known S1
black-chunk defect rather than hiding it. The user also accepted that repeating
cave/torch evidence was unnecessary for this diagnostics-only change.

S3 is now `pending_user_start`; it was not started as part of S2.

## Out of Scope / Not Claimed

- no streaming hole or object pop was fixed;
- no loading gate or initial bubble was added;
- no radius, priority, zoom demand, residency, generation, publish, unload, or
  reveal behavior was changed;
- no visual, cave, torch, lighting, save, or gameplay behavior was changed;
- stable 60 FPS is not claimed by S2.
