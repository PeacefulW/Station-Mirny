# S4 Candidate Closure — Seamless Terrain While Moving

Status: `candidate_ready`  
Date: 2026-07-23  
Baseline: accepted S1, S2 and S3 on `121331d runtie debugger`  
Scene: `res://scenes/dev/mountain_runtime_dig_dev_scene.tscn`  
Probe: `res://tools/world_terrain_streaming_mountain_probe.gd`

## Outcome

The steady runtime now prepares terrain, water, mountains, shoreline masks and
mountain presentation masks before they enter the maximum zoom-out visible
envelope at the ordinary maximum player speed of `320 px/s`.

At stream radius `4`, the bounded working envelope is:

- `81` visible chunks;
- `40` additional hidden, fully materialized terrain-reserve chunks;
- `48` additional packet-only halo-support chunks;
- `169` resident base packets and at most `121` materialized `ChunkView`
  owners in ordinary steady demand.

The final long automatic route moved south for `80 s` / `25,600 px`, crossed
`25` chunk boundaries and sampled every visible terrain owner on every one of
`4,800` route frames plus the immediate stop frame. It observed:

- `216` newly visible chunks;
- `0` chunks that became visible before terrain readiness;
- `0` missing/hidden/uncommitted visible terrain samples;
- `0` missing applicable mountain or shoreline masks;
- `0` immediate-stop issues;
- minimum measured terrain-ready lead: `144` frames.

The automatic result makes S4 ready for manual F4 visual acceptance. It does
not replace the user's judgement of seams, black regions or visual pop.

## Root Cause

The accepted S3 startup bubble materialized radius `5` and generated a packet
halo at radius `6`, but the steady-state path discarded that support after the
loading handoff:

- only the visible radius `4` was eligible for `ChunkView` materialization;
- radius `5` was packet source data only;
- a terrain view and its mountain/shore masks could therefore begin publication
  only after the chunk had already entered visible demand;
- the whole `ChunkView` reveal also waited for object presentation, so an
  already complete terrain owner could remain hidden for an unrelated S6 layer.

Increasing only the visible radius would not have established the required
full halo or bounded ownership contract. S4 instead keeps two distinct steady
support rings and preserves their responsibilities across the S3 handoff.

## Implementation

- `WorldStreamer` keeps a symmetric materialized terrain reserve at
  `visible radius + 1`.
- A separate packet-only support ring at `visible radius + 2` supplies complete
  cross-chunk halo input without allocating another `ChunkView`.
- Packet generation, publication, combined halo creation and mask work reuse
  the existing worker/backends and bounded dispatcher lanes.
- Reserve views remain hidden and collision-inactive. When they enter visible
  demand, committed terrain and completed masks are revealed immediately.
- After the S3 startup gate, unfinished object presentation no longer keeps
  ready terrain hidden. Its existing external object layer and blocking
  collisions remain inactive until the existing object reveal guard completes.
- The S3 loading gate retains its existing full-presentation rule.
- No new manager, streamer, save state, packet schema, command, event type,
  canonical worldgen output or `world_version` was introduced.

No object/flora/decor/grass generator, batcher, shader or asset was changed by
S4. The reveal boundary above only prevents those deferred layers from hiding
an otherwise complete terrain owner.

## Automatic Verification

Commands completed with exit code `0` on 2026-07-23:

```powershell
godot_console --headless --path . --editor --quit
godot_console --headless --path . --script res://tools/world_terrain_streaming_mountain_probe.gd -- --seconds=80 --allow-accepted-s3-terrain-handoff
godot_console --headless --path . --script res://tools/world_terrain_streaming_mountain_probe.gd -- --seconds=8 --allow-accepted-s3-terrain-handoff
godot_console --headless --path . --script res://tools/mountain_runtime_dig_dev_scene_determinism_test.gd
godot_console --headless --path . --script res://tools/world_streaming_readiness_diagnostics_smoke_test.gd
godot_console --headless --path . --script res://tools/world_streaming_queue_cache_smoke_test.gd
powershell -File tools/agent/Invoke-GdUnit4.ps1
```

Results:

- project script/class parse: PASS;
- 80-second S4 route:
  `boundaries=25`, `new_visible=216`, `min_lead_frames=144`,
  `missing_visible_samples=0`, `envelope_mismatches=0/0/0`,
  `resident_max=121/169`, `endpoint_issues=0`;
- final 8-second route with explicit ring-size assertions:
  `boundaries=2`, `new_visible=9`, `min_lead_frames=147`,
  `missing_visible_samples=0`, `envelope_mismatches=0/0/0`,
  `resident_max=121/169`, `endpoint_issues=0`;
- deterministic F-scene: PASS twice in one run, seed `131071`, world version
  `63`, signature `b797f4120400f757a08bf5a14e6a6c09721e51fd`,
  mountain `(2104,464)`, stand `(2103,465)`;
- readiness diagnostics smoke: PASS;
- streamer queue/cache regression smoke: PASS;
- `tests/unit` GdUnit4 invocation: PASS;
- new S4 probe formatter and lint: PASS;
- `git diff --check`: PASS.

The queue/cache smoke deliberately emits its existing synthetic object failure
and retry messages while proving its recovery path. The deterministic scene and
S4 route retain the known Godot ObjectDB/resource warnings at process shutdown.

The accepted S3 headless probe can remain in object staging even after every S4
terrain/mask target is ready. The S4 probe therefore exposes an explicit
`--allow-accepted-s3-terrain-handoff` test-only mode. It logs the override,
requires all `121` initial terrain/mask targets to be ready first, and does not
change the runtime or loading-screen gate. The final runs deliberately started
with `94-96` object blockers, providing a stronger proof that ready terrain is
no longer hidden by an out-of-scope presentation family.

The repository formatter reports older formatting differences elsewhere in
the already-dirty `world_streamer.gd`; applying its whole-file rewrite would
alter accepted S2/S3 work outside S4. The S4 visibility hunk was aligned with
the formatter output, and the new probe passes the complete format/lint check.

## Files in S4 Scope

- `core/systems/world/world_streamer.gd`
- `tools/world_terrain_streaming_mountain_probe.gd` and generated UID
- `docs/02_system_specs/world/world_runtime.md`
- `docs/00_governance/SEAMLESS_WORLD_STREAMING_TASK.md`
- this closure report

All previously dirty S1-S3 files and the temporary GDExtension DLL state were
preserved. No branch, commit, staging, stash, reset, cleanup or push was used.

## Manual F4 Acceptance

Run the accepted F scene and record one uninterrupted route:

1. Start `mountain_runtime_dig_dev_scene.tscn` with F6 and begin F4 recording.
2. Wait for the honest loading screen to finish.
3. Set maximum zoom-out (`0.2`).
4. Move south at ordinary maximum speed for `80 s`; use only short A/D
   corrections around obstacles and do not pause for streaming catch-up.
5. Stop, immediately take an F2 capture, then stop F4.

Accept S4 only if terrain, water, mountain bodies and their shoreline/mountain
masks remain complete during movement and on the immediate stop frame: no
black/empty chunks, seams or terrain appearing after it enters the viewport.

Trees, rocks, decor and grass are not acceptance evidence for S4; they remain
S6/S7. Zoom-driven residency is S5. Stable 60 FPS and scale proof remain S8.
S5 stays locked until the user explicitly accepts this candidate.
