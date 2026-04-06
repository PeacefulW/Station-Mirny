# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/flora_after_seed12345.log`
- Lines: `19830`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `24667.10 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.48 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `16520.80 ms`

## Frame summary
- Avg: `9.80 ms`
- P99: `39.30 ms`
- Hitches: `7`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1022.11 ms`
- `WorldPrePass.compute.flow_accumulation`: `890.06 ms`
- `WorldPrePass.compute.flow_directions`: `674.27 ms`
- `WorldPrePass.compute.lake_aware_fill`: `554.01 ms`
- `WorldPrePass.compute.slope_grid`: `423.71 ms`
- `WorldPrePass.compute.spine_seeds`: `384.19 ms`
- `WorldPrePass.compute.erosion_proxy`: `340.80 ms`
- `WorldPrePass.compute.sample_height_grid`: `138.99 ms`
- `WorldPrePass.compute.ridge_graph`: `45.85 ms`
- `WorldPrePass.compute.continentalness`: `43.43 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `42.17 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.85 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `548.63 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `31.75 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `15.05 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `6.02 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.18 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.73 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `3.46 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.total: 8.05 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 6.75 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 7.17 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 17.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 79.57 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 79.73 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 6.64 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 16.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.32 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.17 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 6.38 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.36 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 16.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.41 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.63 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 15.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.55 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.85 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 8.35 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 6.07 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 16.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.74 ms`
- `[WorldPerf] Shadow.edge_cache_compute (4, -3): 78.55 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.16 ms`

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
