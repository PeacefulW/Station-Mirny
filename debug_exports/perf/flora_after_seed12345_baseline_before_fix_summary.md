# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/flora_after_seed12345_baseline_before_fix.log`
- Lines: `23449`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `27104.92 ms`
- `Startup.start_to_loading_screen_visible_ms`: `14.08 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `18577.25 ms`

## Frame summary
- Avg: `12.60 ms`
- P99: `35.70 ms`
- Hitches: `9`

## Runtime validation
- Route preset: `local_ring`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1154.46 ms`
- `WorldPrePass.compute.flow_accumulation`: `944.95 ms`
- `WorldPrePass.compute.flow_directions`: `786.39 ms`
- `WorldPrePass.compute.lake_aware_fill`: `609.39 ms`
- `WorldPrePass.compute.spine_seeds`: `479.21 ms`
- `WorldPrePass.compute.slope_grid`: `450.23 ms`
- `WorldPrePass.compute.erosion_proxy`: `336.03 ms`
- `WorldPrePass.compute.sample_height_grid`: `133.42 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `71.48 ms`
- `WorldPrePass.compute.ridge_graph`: `51.18 ms`
- `WorldPrePass.compute.continentalness`: `40.52 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `27.95 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `602.90 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `29.20 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `16.65 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `6.43 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `6.30 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `5.75 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `3.04 ms`
- `WorldPrePass.compute.continentalness.measure_max_distance`: `2.06 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 7.65 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.97 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.08 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.74 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.65 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 23.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 175.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.82 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.09 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.58 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.85 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 20.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 175.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 7.56 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.87 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.26 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 2.06 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 5.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 20.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 175.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.66 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.11 ms`

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
