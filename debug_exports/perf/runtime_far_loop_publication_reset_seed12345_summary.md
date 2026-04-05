# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_far_loop_publication_reset_seed12345.log`
- Lines: `40138`
- Errors: `1`
- Warnings: `6`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `25425.47 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.01 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `13748.15 ms`

## Frame summary
- Avg: `11.90 ms`
- P99: `27.50 ms`
- Hitches: `8`

## Runtime validation
- Route preset: `far_loop`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `953.40 ms`
- `WorldPrePass.compute.flow_accumulation`: `790.94 ms`
- `WorldPrePass.compute.flow_directions`: `640.79 ms`
- `WorldPrePass.compute.lake_aware_fill`: `518.68 ms`
- `WorldPrePass.compute.spine_seeds`: `396.61 ms`
- `WorldPrePass.compute.slope_grid`: `380.00 ms`
- `WorldPrePass.compute.erosion_proxy`: `309.99 ms`
- `WorldPrePass.compute.sample_height_grid`: `142.80 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `59.40 ms`
- `WorldPrePass.compute.ridge_graph`: `42.41 ms`
- `WorldPrePass.compute.continentalness`: `36.57 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.05 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `513.37 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `26.45 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `14.67 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `5.38 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.11 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.52 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.90 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, -1) took 9.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 12.5 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 8.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 11.5 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 10.1 ms (budget 8.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] scheduler.visual_tasks_processed: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 23.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 350.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.67 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.81 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.75 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.79 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.61 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 23.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 350.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 8.71 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 8.86 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.83 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.79 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.76 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 23.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 350.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 8.94 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 9.10 ms`

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
- `[CodexValidation] route start: preset=far_loop waypoints=6`
- `[CodexValidation] reached waypoint 1/6 at (49152.0, 0.0)`
- `[CodexValidation] reached waypoint 2/6 at (49152.0, 32768.0)`
- `[CodexValidation] reached waypoint 3/6 at (221184.0, 32768.0)`
- `[CodexValidation] reached waypoint 4/6 at (221184.0, -32768.0)`
- `[CodexValidation] reached waypoint 5/6 at (0.0, -32768.0)`
- `[CodexValidation] reached waypoint 6/6 at (0.0, 0.0)`
- `[CodexValidation] route complete: preset=far_loop reached=6/6 draining_background_work=true`
- `[CodexValidation] route drain complete; preset=far_loop reached=6/6 redraw_backlog=false`
