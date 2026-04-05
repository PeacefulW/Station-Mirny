# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/visual_pipeline_before_seam_cross_seed12345.log`
- Lines: `22814`
- Errors: `1`
- Warnings: `10`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `25357.64 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.08 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `16279.95 ms`

## Frame summary
- Avg: `13.70 ms`
- P99: `56.10 ms`
- Hitches: `25`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `944.33 ms`
- `WorldPrePass.compute.flow_accumulation`: `834.88 ms`
- `WorldPrePass.compute.flow_directions`: `637.01 ms`
- `WorldPrePass.compute.lake_aware_fill`: `538.51 ms`
- `WorldPrePass.compute.slope_grid`: `390.29 ms`
- `WorldPrePass.compute.spine_seeds`: `380.80 ms`
- `WorldPrePass.compute.erosion_proxy`: `336.25 ms`
- `WorldPrePass.compute.sample_height_grid`: `123.55 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `61.25 ms`
- `WorldPrePass.compute.ridge_graph`: `43.42 ms`
- `WorldPrePass.compute.continentalness`: `37.10 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `25.29 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `533.10 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `26.89 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `14.14 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `5.44 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.16 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.49 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.91 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 8.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 8.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 8.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 9.5 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 10.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 9.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 10.0 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 9.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 9.8 ms (budget 8.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.15 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.25 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.80 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.81 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.85 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.53 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.63 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.52 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.82 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.54 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.80 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.68 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.87 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 4.41 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.69 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.86 ms`

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
