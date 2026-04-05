# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_seed12345_postfix7.log`
- Lines: `15535`
- Errors: `1`
- Warnings: `11`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `30821.63 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.65 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `18627.25 ms`

## Frame summary
- Avg: `6.90 ms`
- P99: `6.90 ms`
- Hitches: `0`

## WorldPrePass phases
- `WorldPrePass.compute.river_extraction`: `1949.22 ms`
- `WorldPrePass.compute.lake_aware_fill`: `1655.79 ms`
- `WorldPrePass.compute.continentalness`: `1606.45 ms`
- `WorldPrePass.compute.rain_shadow`: `998.97 ms`
- `WorldPrePass.compute.flow_accumulation`: `814.79 ms`
- `WorldPrePass.compute.flow_directions`: `739.54 ms`
- `WorldPrePass.compute.slope_grid`: `393.94 ms`
- `WorldPrePass.compute.spine_seeds`: `376.79 ms`
- `WorldPrePass.compute.erosion_proxy`: `299.34 ms`
- `WorldPrePass.compute.sample_height_grid`: `134.77 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `61.99 ms`
- `WorldPrePass.compute.ridge_graph`: `44.73 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.river_extraction.distance_propagation`: `1933.72 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `1573.08 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `1085.57 ms`
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `569.03 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.69 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `15.26 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `3.23 ms`
- `WorldPrePass.compute.continentalness.measure_max_distance`: `2.07 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 9.5 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 10.1 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 11.5 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 9.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 10.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 9.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 11.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 11.0 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 11.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] native flora empty for (2, 2) — GDScript flora fallback in worker`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.total: 2.07 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.mountain_shadow.visual_rebuild: 2.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.23 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.18 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.03 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.07 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.08 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.10 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.01 ms`
- `[WorldPerf] Shadow.edge_cache_slice: 2.06 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.mountain_shadow.visual_rebuild: 2.17 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.35 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.03 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.15 ms`
- `[WorldPerf] Shadow.edge_cache_slice: 2.64 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.mountain_shadow.visual_rebuild: 2.79 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.05 ms`
- `[WorldPerf] Shadow.edge_cache_slice: 2.22 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.mountain_shadow.visual_rebuild: 2.36 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.56 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.01 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.06 ms`
- `[WorldPerf] Shadow.stale_age_ms: 18605.85 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 18627.25 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
