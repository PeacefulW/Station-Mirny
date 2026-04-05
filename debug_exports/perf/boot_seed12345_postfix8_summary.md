# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_seed12345_postfix8.log`
- Lines: `15631`
- Errors: `1`
- Warnings: `10`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `25832.08 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.84 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `16928.72 ms`

## Frame summary
- Avg: `7.60 ms`
- P99: `24.70 ms`
- Hitches: `3`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1104.39 ms`
- `WorldPrePass.compute.flow_accumulation`: `947.42 ms`
- `WorldPrePass.compute.flow_directions`: `687.39 ms`
- `WorldPrePass.compute.lake_aware_fill`: `561.90 ms`
- `WorldPrePass.compute.slope_grid`: `407.17 ms`
- `WorldPrePass.compute.spine_seeds`: `384.60 ms`
- `WorldPrePass.compute.erosion_proxy`: `309.94 ms`
- `WorldPrePass.compute.sample_height_grid`: `148.78 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `63.87 ms`
- `WorldPrePass.compute.ridge_graph`: `45.64 ms`
- `WorldPrePass.compute.continentalness`: `41.05 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.48 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `556.02 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `30.57 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `14.12 ms`
- `WorldPrePass.compute.lake_aware_fill.duplicate_height_grid`: `5.71 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `3.00 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 11.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 11.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 10.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 10.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 10.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 9.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 9.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 10.0 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 12.8 ms (budget 8.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.total: 3.67 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 0)@z0: 16816.33 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 8.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.97 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.25 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 16747.89 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 16763.46 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 6.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.31 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.58 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 16723.96 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 16606.66 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 0)@z0: 16845.01 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 3.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.11 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.33 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 16746.00 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 16659.10 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 16643.06 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 16928.72 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
