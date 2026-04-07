# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_seam_cross_seed12345.log`
- Lines: `467`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `23539.24 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.25 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `14503.00 ms`

## Frame summary
- Avg: `11.00 ms`
- P99: `44.30 ms`
- Hitches: `22`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1021.69 ms`
- `WorldPrePass.compute.flow_accumulation`: `811.29 ms`
- `WorldPrePass.compute.flow_directions`: `644.97 ms`
- `WorldPrePass.compute.lake_aware_fill`: `545.22 ms`
- `WorldPrePass.compute.slope_grid`: `399.76 ms`
- `WorldPrePass.compute.spine_seeds`: `380.19 ms`
- `WorldPrePass.compute.erosion_proxy`: `310.50 ms`
- `WorldPrePass.compute.sample_height_grid`: `123.87 ms`
- `WorldPrePass.compute.ridge_graph`: `43.45 ms`
- `WorldPrePass.compute.continentalness`: `38.02 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.52 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.46 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `540.08 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.55 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.83 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 12.59 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 10.64 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 10.45 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (3, -2)@z0: 663.74 ms`
- `[WorldPerf] PlayerChunk coord=(1, -2) z=0 trigger=scheduler loaded=true visible=true state=full_ready phase=done first_pass=true full_ready=true issues=healthy ages(first=-ms full=-ms border=-ms apply=25389ms converge=1849ms) queues(fast=0 urgent=0 near=14 full_near=0 full_far=34) requests(load=false staged=false generating=false) scheduler(step=3.11ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (2, -4): 68.07 ms`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=scheduler loaded=true visible=true state=full_ready phase=done first_pass=true full_ready=true issues=healthy ages(first=-ms full=-ms border=-ms apply=37729ms converge=10437ms) queues(fast=0 urgent=0 near=4 full_near=0 full_far=43) requests(load=false staged=false generating=false) scheduler(step=3.79ms exhausted=false)`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=11.0 ms, p99=44.3 ms, hitches=22`
- `[WorldPerf] Frame budget: dispatcher=8.3ms streaming=0.0ms streaming_load=0.3ms streaming_redraw=0.1ms topology=0.1ms building=0.0ms power=0.0ms visual=0.0ms shadow=8.4ms spawn=0.0ms total=17.1ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=8.1ms, scheduler.max_urgent_wait_ms=8.1ms`
- `[WorldPerf] Shadow.edge_cache_compute (62, -3): 63.89 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -3)@z0: 5025.28 ms`
- `[WorldPerf] Shadow.edge_cache_compute (4, -1): 68.91 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 77.35 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 77.62 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=true state=full_ready phase=done first_pass=true full_ready=true issues=healthy ages(first=-ms full=-ms border=-ms apply=38675ms converge=11222ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=17) requests(load=false staged=false generating=false) scheduler(step=4.33ms exhausted=true)`
- `[WorldPerf] Shadow.edge_cache_compute (4, 0): 151.12 ms`
- `[WorldPerf] Shadow.edge_cache_compute (4, -2): 62.39 ms`
- `[WorldPerf] Shadow.edge_cache_compute (4, -3): 61.40 ms`
- `[WorldPerf] FPS: 114.0`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 61.87 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 62.09 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, -3)@z0: 6676.20 ms`

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
- `[CodexValidation] route start: preset=seam_cross waypoints=6`
- `[CodexValidation] reached waypoint 1/6 at (8192.0, 0.0)`
- `[CodexValidation] reached waypoint 2/6 at (8192.0, 8192.0)`
- `[CodexValidation] reached waypoint 3/6 at (253952.0, 8192.0)`
- `[CodexValidation] reached waypoint 4/6 at (253952.0, -8192.0)`
- `[CodexValidation] reached waypoint 5/6 at (8192.0, -8192.0)`
- `[CodexValidation] reached waypoint 6/6 at (0.0, 0.0)`
- `[CodexValidation] route complete: preset=seam_cross reached=6/6 draining_background_work=true`
- `[CodexValidation] route drain complete; preset=seam_cross reached=6/6 redraw_backlog=false`
