# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_prepass_native_seed12345_before.log`
- Lines: `9028`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `23502.80 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.37 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `15747.38 ms`

## Frame summary
- Avg: `6.90 ms`
- P99: `7.00 ms`
- Hitches: `0`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `968.37 ms`
- `WorldPrePass.compute.flow_accumulation`: `843.86 ms`
- `WorldPrePass.compute.flow_directions`: `663.64 ms`
- `WorldPrePass.compute.lake_aware_fill`: `525.70 ms`
- `WorldPrePass.compute.slope_grid`: `398.17 ms`
- `WorldPrePass.compute.spine_seeds`: `379.15 ms`
- `WorldPrePass.compute.erosion_proxy`: `325.59 ms`
- `WorldPrePass.compute.sample_height_grid`: `124.80 ms`
- `WorldPrePass.compute.continentalness`: `48.53 ms`
- `WorldPrePass.compute.ridge_graph`: `43.12 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `41.06 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.63 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `520.31 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `33.70 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `14.47 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `6.38 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `5.37 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `5.21 ms`
- `WorldPrePass.compute.river_extraction.distance_propagation`: `4.66 ms`
- `WorldPrePass.compute.continentalness.measure_max_distance`: `2.71 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -2)@z0: 15464.61 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, -2)@z0: 15424.62 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 15425.26 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 15391.21 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 8.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.98 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 5.18 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 15431.37 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 15395.88 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 15395.90 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, 2)@z0: 15363.38 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 15327.47 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 5.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 3.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 4.47 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 4.66 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 15364.59 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 2)@z0: 15354.65 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 15320.70 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.75 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.93 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 15747.38 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
