# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/terrain_native_seam_cross_seed12345.log`
- Lines: `14341`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `23502.61 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.02 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `14808.08 ms`

## Frame summary
- Avg: `8.20 ms`
- P99: `54.60 ms`
- Hitches: `4`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `973.70 ms`
- `WorldPrePass.compute.flow_accumulation`: `831.10 ms`
- `WorldPrePass.compute.flow_directions`: `648.82 ms`
- `WorldPrePass.compute.lake_aware_fill`: `546.88 ms`
- `WorldPrePass.compute.slope_grid`: `395.23 ms`
- `WorldPrePass.compute.spine_seeds`: `372.68 ms`
- `WorldPrePass.compute.erosion_proxy`: `322.29 ms`
- `WorldPrePass.compute.sample_height_grid`: `123.15 ms`
- `WorldPrePass.compute.ridge_graph`: `43.51 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `41.90 ms`
- `WorldPrePass.compute.continentalness`: `40.68 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `30.57 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `541.33 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `30.40 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `15.25 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `5.39 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.33 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.75 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `3.00 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.total: 6.10 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 18.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.67 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.87 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.51 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.69 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 15.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.71 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.84 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 7.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 18.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.53 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.78 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 18.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.55 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.98 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 18.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 7.21 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.35 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 18.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 7.02 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.16 ms`

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
