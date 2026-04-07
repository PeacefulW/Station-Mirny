# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/shadow_native_runtime_before_seed12345.log`
- Lines: `20958`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `27445.46 ms`
- `Startup.start_to_loading_screen_visible_ms`: `14.58 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `17004.00 ms`

## Frame summary
- Avg: `8.40 ms`
- P99: `55.50 ms`
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
- `WorldPrePass.compute.rain_shadow`: `1039.10 ms`
- `WorldPrePass.compute.flow_accumulation`: `950.40 ms`
- `WorldPrePass.compute.flow_directions`: `685.44 ms`
- `WorldPrePass.compute.lake_aware_fill`: `588.28 ms`
- `WorldPrePass.compute.slope_grid`: `443.12 ms`
- `WorldPrePass.compute.spine_seeds`: `414.86 ms`
- `WorldPrePass.compute.erosion_proxy`: `343.31 ms`
- `WorldPrePass.compute.sample_height_grid`: `142.04 ms`
- `WorldPrePass.compute.continentalness`: `68.96 ms`
- `WorldPrePass.compute.ridge_graph`: `55.02 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `46.40 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `29.55 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `581.96 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `44.72 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `15.05 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `11.02 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `8.45 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `6.12 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `5.01 ms`
- `WorldPrePass.compute.continentalness.measure_max_distance`: `4.23 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 6.59 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 16.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.97 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.11 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.76 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 15.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 7.18 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.31 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.17 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 3.83 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 14.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.44 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.04 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.23 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 16.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.70 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.17 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.97 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 4.59 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.80 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 19.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.52 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.85 ms`

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
