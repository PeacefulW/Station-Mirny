# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_seed12345_postfix6.log`
- Lines: `15613`
- Errors: `1`
- Warnings: `11`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `28803.60 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.38 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `16889.54 ms`

## Frame summary
- Avg: `6.90 ms`
- P99: `6.90 ms`
- Hitches: `0`

## WorldPrePass phases
- `WorldPrePass.compute.river_extraction`: `1933.05 ms`
- `WorldPrePass.compute.lake_aware_fill`: `1704.08 ms`
- `WorldPrePass.compute.continentalness`: `1579.43 ms`
- `WorldPrePass.compute.rain_shadow`: `1017.97 ms`
- `WorldPrePass.compute.flow_accumulation`: `813.42 ms`
- `WorldPrePass.compute.flow_directions`: `788.78 ms`
- `WorldPrePass.compute.slope_grid`: `393.16 ms`
- `WorldPrePass.compute.spine_seeds`: `390.75 ms`
- `WorldPrePass.compute.erosion_proxy`: `297.10 ms`
- `WorldPrePass.compute.sample_height_grid`: `129.52 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `59.09 ms`
- `WorldPrePass.compute.ridge_graph`: `49.30 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.river_extraction.distance_propagation`: `1917.15 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `1547.13 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `1084.76 ms`
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `617.73 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.45 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `15.64 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.87 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, -1) took 9.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 0) took 8.1 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 8.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 8.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 8.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 10.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 11.0 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 12.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 10.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] native flora empty for (2, 2) — GDScript flora fallback in worker`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -2)@z0: 16769.39 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 11.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.05 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.28 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 16724.08 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 16673.57 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 16657.51 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 0)@z0: 16812.79 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, 2)@z0: 16784.13 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 16649.65 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 16620.63 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 16696.03 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 3.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.45 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.74 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 16755.52 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 16709.55 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, -2)@z0: 16828.08 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 7.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.76 ms`
- `[WorldPerf] Shadow.stale_age_ms: 16870.51 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 16889.54 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
