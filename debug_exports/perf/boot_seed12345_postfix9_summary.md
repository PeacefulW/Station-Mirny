# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_seed12345_postfix9.log`
- Lines: `14979`
- Errors: `1`
- Warnings: `7`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `24941.41 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.72 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `15536.71 ms`

## Frame summary
- Avg: `7.30 ms`
- P99: `25.00 ms`
- Hitches: `3`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1137.28 ms`
- `WorldPrePass.compute.flow_accumulation`: `908.67 ms`
- `WorldPrePass.compute.flow_directions`: `660.74 ms`
- `WorldPrePass.compute.lake_aware_fill`: `547.35 ms`
- `WorldPrePass.compute.slope_grid`: `432.83 ms`
- `WorldPrePass.compute.spine_seeds`: `390.33 ms`
- `WorldPrePass.compute.erosion_proxy`: `325.48 ms`
- `WorldPrePass.compute.sample_height_grid`: `134.64 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `59.88 ms`
- `WorldPrePass.compute.continentalness`: `53.22 ms`
- `WorldPrePass.compute.ridge_graph`: `43.52 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `26.46 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `541.71 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `39.54 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `17.09 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `7.18 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.46 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.64 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `3.65 ms`
- `WorldPrePass.compute.continentalness.measure_max_distance`: `2.23 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 9.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 11.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 11.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 8.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 8.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 9.2 ms (budget 8.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 8.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.31 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.61 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 15396.55 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 0)@z0: 15452.29 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 6.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.15 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.40 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 0)@z0: 15450.43 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 15415.09 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 4.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.02 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.41 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 15389.71 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 15356.36 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 15402.97 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 15366.81 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 5.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.02 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.42 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 15536.71 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
