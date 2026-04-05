# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/flora_before_instrumented_seed12345.log`
- Lines: `27478`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `36052.04 ms`
- `Startup.start_to_loading_screen_visible_ms`: `14.17 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `24453.09 ms`

## Frame summary
- Avg: `11.10 ms`
- P99: `21.10 ms`
- Hitches: `2`

## Runtime validation
- Route preset: `local_ring`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1643.07 ms`
- `WorldPrePass.compute.flow_accumulation`: `952.13 ms`
- `WorldPrePass.compute.flow_directions`: `698.59 ms`
- `WorldPrePass.compute.slope_grid`: `648.75 ms`
- `WorldPrePass.compute.lake_aware_fill`: `571.68 ms`
- `WorldPrePass.compute.erosion_proxy`: `480.28 ms`
- `WorldPrePass.compute.spine_seeds`: `431.52 ms`
- `WorldPrePass.compute.sample_height_grid`: `163.90 ms`
- `WorldPrePass.compute.continentalness`: `87.68 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `66.25 ms`
- `WorldPrePass.compute.ridge_graph`: `45.73 ms`
- `WorldPrePass.compute.river_extraction`: `28.12 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `566.34 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `66.01 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `22.86 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `10.15 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `7.46 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.16 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.92 ms`
- `WorldPrePass.compute.continentalness.measure_max_distance`: `2.98 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 20.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 160.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.33 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.50 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.88 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 3.19 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 22.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 160.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.96 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.22 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 3.50 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 22.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 160.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.53 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.70 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.13 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 6.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 17.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 160.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.78 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.99 ms`

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
