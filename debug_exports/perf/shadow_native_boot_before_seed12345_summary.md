# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/shadow_native_boot_before_seed12345.log`
- Lines: `12624`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `27111.21 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.50 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `16838.90 ms`

## Frame summary
- Avg: `6.90 ms`
- P99: `6.90 ms`
- Hitches: `0`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1001.30 ms`
- `WorldPrePass.compute.flow_accumulation`: `940.38 ms`
- `WorldPrePass.compute.flow_directions`: `693.36 ms`
- `WorldPrePass.compute.lake_aware_fill`: `574.41 ms`
- `WorldPrePass.compute.slope_grid`: `412.19 ms`
- `WorldPrePass.compute.spine_seeds`: `401.81 ms`
- `WorldPrePass.compute.erosion_proxy`: `330.84 ms`
- `WorldPrePass.compute.sample_height_grid`: `155.91 ms`
- `WorldPrePass.compute.ridge_graph`: `57.80 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `47.16 ms`
- `WorldPrePass.compute.continentalness`: `45.27 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `31.32 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `568.86 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `34.23 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `16.43 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `5.89 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.39 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.71 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.98 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.34 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.56 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, -2)@z0: 16469.25 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 16469.51 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 16429.51 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 16429.41 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 6.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.93 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.16 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 16452.70 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 16452.78 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 16369.45 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 16381.73 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.61 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.94 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 2)@z0: 16410.56 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 16365.38 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 2.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.33 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.58 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 16838.90 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
