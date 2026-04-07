# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_local_ring_seed12345.log`
- Lines: `715`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `23770.33 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.05 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `14587.84 ms`

## Frame summary
- Avg: `11.50 ms`
- P99: `34.50 ms`
- Hitches: `15`

## Runtime validation
- Route preset: `local_ring`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `973.84 ms`
- `WorldPrePass.compute.flow_accumulation`: `818.86 ms`
- `WorldPrePass.compute.flow_directions`: `637.18 ms`
- `WorldPrePass.compute.lake_aware_fill`: `586.53 ms`
- `WorldPrePass.compute.slope_grid`: `397.61 ms`
- `WorldPrePass.compute.spine_seeds`: `383.43 ms`
- `WorldPrePass.compute.erosion_proxy`: `310.29 ms`
- `WorldPrePass.compute.sample_height_grid`: `124.69 ms`
- `WorldPrePass.compute.ridge_graph`: `43.91 ms`
- `WorldPrePass.compute.continentalness`: `37.58 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `27.08 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.37 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `581.30 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.33 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.81 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 10.76 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 12.82 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 14.96 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 14.23 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 11.43 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, -1)@z0: 600.98 ms`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=entered_chunk loaded=true visible=false state=full_pending phase=cliff first_pass=true full_ready=false issues=full_redraw_pending ages(first=-ms full=317ms border=-ms apply=918ms converge=918ms) queues(fast=0 urgent=0 near=11 full_near=3 full_far=136) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 16.95 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 14.41 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 10.61 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 11.04 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 0)@z0: 631.48 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=entered_chunk loaded=true visible=false state=full_pending phase=cliff first_pass=true full_ready=false issues=full_redraw_pending ages(first=-ms full=295ms border=-ms apply=927ms converge=927ms) queues(fast=1 urgent=0 near=9 full_near=3 full_far=140) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 11.47 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 14.11 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 12.35 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 11.61 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 11.77 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 1)@z0: 602.47 ms`
- `[WorldPerf] FPS: 84.0`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=11.5 ms, p99=34.5 ms, hitches=15`
- `[WorldPerf] Frame budget: dispatcher=9.1ms streaming=0.0ms streaming_load=0.6ms streaming_redraw=0.4ms topology=0.1ms building=0.0ms power=0.0ms visual=0.0ms shadow=8.4ms spawn=0.0ms total=18.5ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=11.5ms, scheduler.max_urgent_wait_ms=11.5ms`

## Recent CodexValidation lines
- `[CodexValidation] mining validation prepared at (59, 0)`
- `[CodexValidation] boot complete; route prepared`
- `[CodexValidation] built validation room`
- `[CodexValidation] removed validation room wall (5, 4)`
- `[CodexValidation] re-placed validation room wall (5, 4)`
- `[CodexValidation] destroyed validation room wall (4, 5)`
- `[CodexValidation] room validation complete`
- `[CodexValidation] placed validation battery (8, 4)`
- `[CodexValidation] removed validation battery (8, 4)`
- `[CodexValidation] power validation complete`
- `[CodexValidation] mined entry tile (59, 0)`
- `[CodexValidation] mined interior tile (60, 0)`
- `[CodexValidation] mined deeper tile (61, 0)`
- `[CodexValidation] moved player back to exterior tile (58, 0)`
- `[CodexValidation] mining + persistence validation complete`
- `[CodexValidation] route start: preset=local_ring waypoints=6`
- `[CodexValidation] reached waypoint 1/6 at (24576.0, 0.0)`
- `[CodexValidation] reached waypoint 2/6 at (24576.0, 20480.0)`
- `[CodexValidation] reached waypoint 3/6 at (241664.0, 20480.0)`
- `[CodexValidation] reached waypoint 4/6 at (241664.0, -16384.0)`
- `[CodexValidation] reached waypoint 5/6 at (0.0, -16384.0)`
- `[CodexValidation] reached waypoint 6/6 at (0.0, 0.0)`
- `[CodexValidation] route complete: preset=local_ring reached=6/6 draining_background_work=true`
- `[CodexValidation] route drain complete; preset=local_ring reached=6/6 redraw_backlog=false`
