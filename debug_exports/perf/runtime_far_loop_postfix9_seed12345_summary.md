# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_far_loop_postfix9_seed12345.log`
- Lines: `41726`
- Errors: `1`
- Warnings: `10`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `24866.66 ms`
- `Startup.start_to_loading_screen_visible_ms`: `15.41 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `15871.75 ms`

## Frame summary
- Avg: `12.30 ms`
- P99: `28.10 ms`
- Hitches: `12`

## Runtime validation
- Route preset: `far_loop`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1021.30 ms`
- `WorldPrePass.compute.flow_accumulation`: `880.74 ms`
- `WorldPrePass.compute.flow_directions`: `657.57 ms`
- `WorldPrePass.compute.lake_aware_fill`: `551.24 ms`
- `WorldPrePass.compute.slope_grid`: `403.75 ms`
- `WorldPrePass.compute.spine_seeds`: `384.57 ms`
- `WorldPrePass.compute.erosion_proxy`: `330.55 ms`
- `WorldPrePass.compute.sample_height_grid`: `132.17 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `62.95 ms`
- `WorldPrePass.compute.ridge_graph`: `45.25 ms`
- `WorldPrePass.compute.continentalness`: `38.44 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `26.79 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `545.90 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `28.03 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `17.53 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `5.57 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.13 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `5.03 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.91 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 10.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 9.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 9.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 9.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 11.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 9.1 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 8.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 9.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 12.8 ms (budget 8.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.31 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.45 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 6.24 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 23.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 353.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.54 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.68 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.76 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 3.68 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 23.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 353.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 7.76 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.92 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 5.80 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.85 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 23.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 353.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 9.19 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 9.33 ms`

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
