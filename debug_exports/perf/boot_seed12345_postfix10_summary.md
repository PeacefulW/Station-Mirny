# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_seed12345_postfix10.log`
- Lines: `15491`
- Errors: `1`
- Warnings: `9`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `24126.14 ms`
- `Startup.start_to_loading_screen_visible_ms`: `28.08 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `15384.82 ms`

## Frame summary
- Avg: `7.30 ms`
- P99: `16.70 ms`
- Hitches: `2`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `973.58 ms`
- `WorldPrePass.compute.flow_accumulation`: `960.75 ms`
- `WorldPrePass.compute.flow_directions`: `680.66 ms`
- `WorldPrePass.compute.lake_aware_fill`: `568.68 ms`
- `WorldPrePass.compute.spine_seeds`: `423.41 ms`
- `WorldPrePass.compute.slope_grid`: `396.36 ms`
- `WorldPrePass.compute.erosion_proxy`: `300.73 ms`
- `WorldPrePass.compute.sample_height_grid`: `272.97 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `63.34 ms`
- `WorldPrePass.compute.ridge_graph`: `50.00 ms`
- `WorldPrePass.compute.continentalness`: `37.63 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.00 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `563.49 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.32 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `14.31 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `5.54 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.06 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.44 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.89 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 8.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 9.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 9.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 10.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 12.5 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 10.0 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 8.5 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 9.8 ms (budget 8.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.total: 2.60 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -2)@z0: 15277.14 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 8.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.09 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.54 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 15266.78 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 7.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.32 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.51 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 0)@z0: 15314.63 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 0)@z0: 15306.93 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 15181.17 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 4.00 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 15236.53 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 15199.21 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 15207.69 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.94 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.17 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 15250.04 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 15384.82 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
