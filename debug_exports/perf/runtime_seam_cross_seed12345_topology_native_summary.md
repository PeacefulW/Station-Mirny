# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_seam_cross_seed12345_topology_native.log`
- Lines: `19993`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `23827.81 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.17 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `14966.86 ms`

## Frame summary
- Avg: `8.40 ms`
- P99: `46.70 ms`
- Hitches: `5`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `998.18 ms`
- `WorldPrePass.compute.flow_accumulation`: `818.08 ms`
- `WorldPrePass.compute.flow_directions`: `658.46 ms`
- `WorldPrePass.compute.lake_aware_fill`: `548.76 ms`
- `WorldPrePass.compute.slope_grid`: `408.13 ms`
- `WorldPrePass.compute.spine_seeds`: `400.72 ms`
- `WorldPrePass.compute.erosion_proxy`: `304.14 ms`
- `WorldPrePass.compute.sample_height_grid`: `150.88 ms`
- `WorldPrePass.compute.ridge_graph`: `43.98 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `41.49 ms`
- `WorldPrePass.compute.continentalness`: `37.44 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `24.24 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `543.37 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.21 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `14.53 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `5.42 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.23 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.79 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.92 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 19.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.13 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.34 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.22 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.47 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 17.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.27 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.40 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.91 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.71 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 17.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.80 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.50 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.96 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 17.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.50 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.52 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 3.40 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 17.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.71 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.92 ms`

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
