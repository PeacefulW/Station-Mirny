# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/shadow_native_runtime_seed12345.log`
- Lines: `20009`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `23315.67 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.85 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `14861.29 ms`

## Frame summary
- Avg: `10.90 ms`
- P99: `45.60 ms`
- Hitches: `17`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `970.96 ms`
- `WorldPrePass.compute.flow_accumulation`: `824.77 ms`
- `WorldPrePass.compute.flow_directions`: `657.99 ms`
- `WorldPrePass.compute.lake_aware_fill`: `539.02 ms`
- `WorldPrePass.compute.slope_grid`: `398.10 ms`
- `WorldPrePass.compute.spine_seeds`: `379.78 ms`
- `WorldPrePass.compute.erosion_proxy`: `300.37 ms`
- `WorldPrePass.compute.sample_height_grid`: `128.30 ms`
- `WorldPrePass.compute.ridge_graph`: `43.45 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `40.41 ms`
- `WorldPrePass.compute.continentalness`: `37.96 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `24.00 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `533.64 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.60 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `14.41 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `5.58 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.21 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.44 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.90 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.07 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.95 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 9.93 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 3.33 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 16.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.81 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.71 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 7.25 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.32 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 17.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.58 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.77 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 4.94 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 17.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.56 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.76 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.08 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 14.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.30 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.96 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.27 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 17.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 7.38 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.52 ms`

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
