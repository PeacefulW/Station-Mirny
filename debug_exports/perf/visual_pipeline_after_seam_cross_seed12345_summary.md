# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/visual_pipeline_after_seam_cross_seed12345.log`
- Lines: `20458`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `25229.75 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.69 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `17116.84 ms`

## Frame summary
- Avg: `10.60 ms`
- P99: `38.00 ms`
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
- `WorldPrePass.compute.rain_shadow`: `1021.30 ms`
- `WorldPrePass.compute.flow_accumulation`: `876.56 ms`
- `WorldPrePass.compute.flow_directions`: `664.66 ms`
- `WorldPrePass.compute.lake_aware_fill`: `533.38 ms`
- `WorldPrePass.compute.slope_grid`: `408.45 ms`
- `WorldPrePass.compute.spine_seeds`: `387.54 ms`
- `WorldPrePass.compute.erosion_proxy`: `330.55 ms`
- `WorldPrePass.compute.sample_height_grid`: `126.20 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `60.67 ms`
- `WorldPrePass.compute.continentalness`: `43.79 ms`
- `WorldPrePass.compute.ridge_graph`: `43.26 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.87 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `527.41 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `32.74 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `14.53 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `6.04 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.80 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.63 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.92 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 7.65 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 5.35 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 3.21 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 17.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.38 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.56 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 3.33 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 4.90 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 17.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.50 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.45 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 4.91 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 16.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.62 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.99 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_prepare_step.terrain: 4.26 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 5.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 19.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.81 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.12 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 19.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.98 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.09 ms`

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
