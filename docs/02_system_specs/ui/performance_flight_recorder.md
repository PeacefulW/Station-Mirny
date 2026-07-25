---
title: Performance Flight Recorder V0
doc_type: system_spec
status: approved
owner: engineering
source_of_truth: true
version: 1.3
last_updated: 2026-07-22
related_docs:
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../world/world_runtime.md
  - ui_ux_foundation.md
---

# Performance Flight Recorder V0

## Purpose

Turn the in-game performance HUD into an actionable diagnostic surface without
making capture work a new source of ordinary gameplay hitches.

V0 adds:

- `F2`: one manual diagnostic capture (`PNG` plus structured sidecar data)
- `F4`: start or stop one bounded flight-recorder session
- per-frame compact telemetry for frame and render timing
- low-rate O(1) world-streaming context
- event screenshots only for distinct spikes or pressure transitions
- a session summary and trace under `user://performance_captures/`

The recorder is a developer diagnostic. It does not change gameplay, world
generation, streaming priority, visual quality, save state, or camera limits.

## Law 0 Classification

| Question | V0 answer |
|---|---|
| Canonical, runtime overlay, or visual only? | Transient diagnostic runtime state plus a visual-only HUD status |
| Save/load required? | No; captures are external diagnostic artifacts, never game save data |
| Deterministic? | No gameplay result depends on the recorder; timestamps and hardware counters are intentionally session-local |
| Must work on unloaded chunks? | No; it records the currently materialized runtime only |
| C++ compute or main-thread apply? | O(1) engine counters and SceneTree reads happen on the main thread; image encoding and artifact serialization use one worker task |
| Dirty unit | One frame sample, one 250 ms context sample, or one distinct capture event |
| Single owner | `PerformanceFlightRecorder` owns session buffers, capture policy, and artifact writes; `WorldStreamer` remains owner of streaming truth |
| 10x / 100x scale path | Storage is capped by time, samples, screenshots, and retained sessions rather than world/object count |
| Main-thread blocking risk | Viewport readback is unavoidable and therefore event/manual-only; no per-frame PNG or disk write is allowed |
| Hidden GDScript fallback? | Not applicable; this is sanctioned debug/UI orchestration, not world compute |
| Could it become heavy later? | Yes; all buffers, event counts, capture rate, worker concurrency, and retention are bounded in V0 |
| Whole-world prepass? | Forbidden; only O(1) live snapshots and current viewport/player state are read |

## Runtime Work Contract

- Recorder sampling is `background diagnostic` work enabled only by `F4`.
- `F2` is an explicit developer interaction. It may request one viewport
  readback after `RenderingServer.frame_post_draw`.
- Every ordinary recording frame performs only fixed-field writes. It must not
  scan chunks, objects, mountain masks, scene-tree groups, or filesystem state.
- `WorldStreamer.get_perf_hud_snapshot()` is the only world context read and is
  sampled at most four times per second.
- Detailed readiness is not added to that four-Hz path. An explicit F2
  snapshot or F4 finalization may call
  `WorldStreamer.get_streaming_readiness_debug_snapshot()` once and attach the
  bounded result as `streaming_readiness`. This preserves the O(1) trace path
  while making a captured missing chunk/layer explainable.
- `WorldPerfProbe` observation is reference-counted so the HUD and recorder can
  coexist without stealing or clearing each other's samples.
- Viewport readback taints the following three process samples. The recorder
  excludes them from spike and queue-pressure transitions, and the live HUD
  omits them from its graph/peak window so the diagnostic cannot report its own
  synchronization cost as a gameplay hitch. A pressure transition that remains
  active is evaluated once after the taint expires.
- During gameplay, PNG encoding, JSON/CSV serialization, and file writes run in
  one worker lane. Worker code must not touch Nodes, Viewports, RenderingServer,
  or gameplay state. The only synchronous exception is the final trace flush
  after the recorder has already left gameplay through shutdown/scene exit.

## Bounds

| Resource | Bound |
|---|---|
| Session duration | 120 seconds |
| Frame samples | 28,800 (supports 240 samples/s for the full session) |
| Context cadence | 4 Hz |
| Automatic screenshots | 12 per session |
| Total event records (automatic + manual) | 64 per session |
| Screenshot cooldown | 5 seconds |
| Concurrent artifact workers | 1 |
| Retained sessions | 8 newest sessions |

If a bound is reached, the recorder must stop or omit the new diagnostic item;
it must not expand memory or queue work without limit.

An active F4 session is serialized synchronously if its recorder leaves the
scene tree. Shutdown/scene replacement is outside gameplay frame budgeting, and
preserving the trace is preferable to leaving an empty session directory.

## Event Semantics

`sustained_slow` and `frame_spike` are separate conditions:

- sustained slow: frame time remains over the 60 FPS budget for at least two
  seconds; one transition event is emitted, not one event per slow frame
- frame spike: after warm-up, a non-tainted frame is at least `50 ms` and at
  least `1.75x` the bounded recent baseline
- queue pressure: visibility or upload pressure crosses its critical threshold
  and was not already active
- manual bookmark: the user presses `F2`

Nearby automatic events are deduplicated by cooldown. Continuous 30 FPS is a
slow-frame plateau, not hundreds of identical hitches.

## Artifact Shape

```text
user://performance_captures/<timestamp>/
  session.json
  trace.csv
  events/
    0001_<reason>.json
    0001_<reason>.png
```

The session metadata includes renderer/driver context, VSync mode, refresh
rate, FPS cap, viewport size, debug/editor state, sample counts, p95/p99/max,
render CPU/GPU maxima, draw-call maxima, queue maxima, distance travelled, and
event references.

F2 sidecars and the final F4 `session.json` include the bounded
`StreamingReadinessDiagnosticSnapshot` documented in `packet_schemas.md`.
Ordinary per-frame CSV rows remain numeric and do not duplicate per-chunk
records.

The trace records frame time, measured viewport CPU/GPU time, frame setup CPU,
process/physics monitors, canvas draw/object counts, player position, camera
zoom, the tracked `WorldPerfProbe` phases, and the latest low-rate streaming
context.

## UI Contract

- The normal survival HUD remains minimal; diagnostics stay hidden by default.
- The F3 panel footer advertises `F2` and `F4` without adding another card.
- While recording, one restrained red `REC mm:ss` indicator appears in the
  existing performance panel.
- A short localized toast confirms capture/record completion and shows the
  absolute artifact directory.
- `Performance.TIME_PROCESS` is labelled as whole-frame time, never as pure CPU
  time.

## Allowed Files

- `core/runtime/performance_flight_recorder.gd`
- `core/runtime/performance_flight_recorder_artifact_writer.gd`
- `scenes/world/world_runtime_v0_scene.gd`
- `scenes/ui/hud/hud_manager.gd`
- `scenes/ui/hud/hud_performance_widget.gd`
- `core/runtime/performance_hud_metrics.gd`
- `locale/ru/messages.po`
- `locale/en/messages.po`
- recorder/HUD tests under `tools/`
- this spec and the documentation index

## Forbidden Changes

- streaming radius, queue priority, generation output, object/grass visuals
- gameplay input semantics outside the new F2/F4 diagnostic controls
- save schemas, world packet schemas, commands, or EventBus contracts
- per-frame screenshots, per-frame filesystem writes, forensic chunk scans
- periodic detailed readiness scans in the four-Hz context sampler

## Acceptance Criteria

- [ ] `F2` writes one non-empty PNG and one sidecar record after frame draw
- [ ] `F4` records and stops one bounded session without requiring the F3 HUD
- [ ] the trace contains viewport CPU/GPU and streaming context columns
- [ ] sustained 30 FPS creates one plateau event, not a screenshot storm
- [ ] capture-tainted frames cannot recursively trigger captures
- [ ] active F4 data survives recorder shutdown or scene replacement
- [ ] smoke tests use an isolated `user://test_artifacts/` root and cannot evict
      player captures
- [ ] HUD and recorder observation reference counts coexist correctly
- [ ] RU and EN text coverage is complete
- [ ] a real manual windowed play session produces parseable artifacts
- [ ] F2 sidecars and final F4 metadata identify each missing working-set
      chunk/layer with one reason and elapsed wait without changing trace cadence

## Required Canonical Updates

- `docs/README.md`: add this approved UI diagnostic spec.
- No `system_api.md`, `event_contracts.md`, `packet_schemas.md`, or `commands.md`
  update is required because V0 adds no gameplay/public system boundary, event,
  packet, save shape, or mutation command.
