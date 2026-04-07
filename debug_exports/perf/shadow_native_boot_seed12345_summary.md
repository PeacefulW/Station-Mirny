# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/shadow_native_boot_seed12345.log`
- Lines: `11769`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `23255.99 ms`
- `Startup.start_to_loading_screen_visible_ms`: `14.40 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `14747.09 ms`

## Frame summary
- Avg: `6.90 ms`
- P99: `6.90 ms`
- Hitches: `0`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `992.88 ms`
- `WorldPrePass.compute.flow_accumulation`: `811.50 ms`
- `WorldPrePass.compute.flow_directions`: `674.71 ms`
- `WorldPrePass.compute.lake_aware_fill`: `542.50 ms`
- `WorldPrePass.compute.slope_grid`: `394.84 ms`
- `WorldPrePass.compute.spine_seeds`: `384.68 ms`
- `WorldPrePass.compute.erosion_proxy`: `306.74 ms`
- `WorldPrePass.compute.sample_height_grid`: `124.35 ms`
- `WorldPrePass.compute.ridge_graph`: `46.65 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `40.38 ms`
- `WorldPrePass.compute.continentalness`: `37.14 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `24.52 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `536.98 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `26.93 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `14.57 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `5.49 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.38 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.48 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.92 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -2)@z0: 14464.94 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, -2)@z0: 14422.90 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 14423.30 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 9.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.15 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.34 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, 2)@z0: 14345.83 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 14379.75 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 14419.72 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 14419.74 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 14383.33 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 5.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 4.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.48 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.70 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 14348.21 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 14360.11 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 2)@z0: 14339.63 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 14302.50 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 4.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.88 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.07 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 14747.09 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
