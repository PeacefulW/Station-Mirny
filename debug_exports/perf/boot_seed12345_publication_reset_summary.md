# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_seed12345_publication_reset.log`
- Lines: `14294`
- Errors: `1`
- Warnings: `9`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `25095.83 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.84 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `14598.29 ms`

## Frame summary
- Avg: `7.00 ms`
- P99: `8.30 ms`
- Hitches: `0`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1111.60 ms`
- `WorldPrePass.compute.flow_accumulation`: `780.63 ms`
- `WorldPrePass.compute.flow_directions`: `641.17 ms`
- `WorldPrePass.compute.lake_aware_fill`: `525.84 ms`
- `WorldPrePass.compute.spine_seeds`: `430.31 ms`
- `WorldPrePass.compute.slope_grid`: `391.05 ms`
- `WorldPrePass.compute.erosion_proxy`: `327.25 ms`
- `WorldPrePass.compute.sample_height_grid`: `129.71 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `66.26 ms`
- `WorldPrePass.compute.ridge_graph`: `42.60 ms`
- `WorldPrePass.compute.continentalness`: `40.20 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `28.00 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `520.20 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `28.48 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `14.03 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `6.02 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.45 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.43 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.88 ms`
- `WorldPrePass.compute.continentalness.measure_max_distance`: `2.40 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, -1) took 8.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 9.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 12.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 11.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 9.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 8.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 8.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 9.0 ms (budget 8.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.total: 3.87 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -2)@z0: 14455.92 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 6.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.11 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.26 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 14398.63 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 14443.85 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 7.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 4.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.14 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.32 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 14365.85 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 3.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.58 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.76 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 14392.85 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 14461.73 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 14404.40 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 5.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.95 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.14 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 14598.29 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
