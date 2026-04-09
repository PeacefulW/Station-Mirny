# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_seam_cross_borderfix_seed12345.log`
- Lines: `748`
- Errors: `1`
- Warnings: `79`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `19348.10 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.57 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `6511.16 ms`

## Frame summary
- Avg: `9.20 ms`
- P99: `20.40 ms`
- Hitches: `2`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## Budget overrun offenders
- Warning count: `78`
- `visual / chunk_manager.streaming_redraw`: count=`40`, budget=`4.00 ms`, max_used=`21.06 ms`, max_over=`426.4%`
- `visual / mountain_shadow.visual_rebuild`: count=`19`, budget=`1.00 ms`, max_used=`7.20 ms`, max_over=`620.1%`
- `streaming / chunk_manager.streaming_load`: count=`16`, budget=`3.00 ms`, max_used=`17.41 ms`, max_over=`480.2%`
- `topology / chunk_manager.topology_rebuild`: count=`3`, budget=`2.00 ms`, max_used=`8.45 ms`, max_over=`322.3%`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1036.09 ms`
- `WorldPrePass.compute.flow_accumulation`: `837.23 ms`
- `WorldPrePass.compute.flow_directions`: `680.24 ms`
- `WorldPrePass.compute.lake_aware_fill`: `588.88 ms`
- `WorldPrePass.compute.spine_seeds`: `468.01 ms`
- `WorldPrePass.compute.slope_grid`: `417.55 ms`
- `WorldPrePass.compute.erosion_proxy`: `312.58 ms`
- `WorldPrePass.compute.sample_height_grid`: `138.10 ms`
- `WorldPrePass.compute.continentalness`: `46.58 ms`
- `WorldPrePass.compute.ridge_graph`: `43.78 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `24.10 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.45 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `582.98 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `35.05 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.82 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.88 budget_ms=1.00 over_budget_pct=87.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=10.84 budget_ms=3.00 over_budget_pct=261.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=12.64 budget_ms=3.00 over_budget_pct=321.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.10 budget_ms=4.00 over_budget_pct=27.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=6.38 budget_ms=4.00 over_budget_pct=59.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.93 budget_ms=1.00 over_budget_pct=292.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.25 budget_ms=1.00 over_budget_pct=424.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=7.20 budget_ms=1.00 over_budget_pct=620.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.58 budget_ms=4.00 over_budget_pct=89.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.85 budget_ms=4.00 over_budget_pct=146.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=8.45 budget_ms=2.00 over_budget_pct=322.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.39 budget_ms=1.00 over_budget_pct=39.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=6.13 budget_ms=4.00 over_budget_pct=53.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.61 budget_ms=1.00 over_budget_pct=161.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.35 budget_ms=4.00 over_budget_pct=83.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.36 budget_ms=4.00 over_budget_pct=133.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=21.06 budget_ms=4.00 over_budget_pct=426.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=10.36 budget_ms=4.00 over_budget_pct=159.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=11.88 budget_ms=4.00 over_budget_pct=196.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=15.19 budget_ms=4.00 over_budget_pct=279.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=18.23 budget_ms=4.00 over_budget_pct=355.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.54 budget_ms=1.00 over_budget_pct=53.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.25 budget_ms=4.00 over_budget_pct=81.3`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.12 budget_ms=2.00 over_budget_pct=105.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.88 budget_ms=1.00 over_budget_pct=87.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=10.84 budget_ms=3.00 over_budget_pct=261.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=12.64 budget_ms=3.00 over_budget_pct=321.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.10 budget_ms=4.00 over_budget_pct=27.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=6.38 budget_ms=4.00 over_budget_pct=59.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.93 budget_ms=1.00 over_budget_pct=292.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.25 budget_ms=1.00 over_budget_pct=424.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=7.20 budget_ms=1.00 over_budget_pct=620.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.58 budget_ms=4.00 over_budget_pct=89.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.85 budget_ms=4.00 over_budget_pct=146.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=8.45 budget_ms=2.00 over_budget_pct=322.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.39 budget_ms=1.00 over_budget_pct=39.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=6.13 budget_ms=4.00 over_budget_pct=53.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.61 budget_ms=1.00 over_budget_pct=161.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.35 budget_ms=4.00 over_budget_pct=83.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.36 budget_ms=4.00 over_budget_pct=133.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=21.06 budget_ms=4.00 over_budget_pct=426.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=10.36 budget_ms=4.00 over_budget_pct=159.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=11.88 budget_ms=4.00 over_budget_pct=196.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=15.19 budget_ms=4.00 over_budget_pct=279.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=18.23 budget_ms=4.00 over_budget_pct=355.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.54 budget_ms=1.00 over_budget_pct=53.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.25 budget_ms=4.00 over_budget_pct=81.3`

## Recent WorldPerf lines
- `[WorldPerf] stream.chunk_full_redraw_ms (63, -2)@z0: 4345.93 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, 0)@z0: 6249.41 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 0)@z0: 6249.54 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, -1)@z0: 5305.69 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 5305.94 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, 1)@z0: 6695.95 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 6696.09 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (0, 2)@z0: 8698.64 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, 2)@z0: 8698.78 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (1, 2)@z0: 9035.59 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 9035.74 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (63, 2)@z0: 7756.52 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, 2)@z0: 7756.67 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (2, -2)@z0: 10330.51 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 3079.41 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, -2)@z0: 5490.52 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 5234.53 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (2, 2)@z0: 10415.53 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 2)@z0: 9519.73 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, 2)@z0: 7799.55 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 7413.34 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=9.2 ms, p99=20.4 ms, hitches=2`
- `[WorldPerf] Frame budget: dispatcher=7.3ms streaming=0.0ms streaming_load=0.0ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=8.6ms spawn=0.0ms total=15.9ms/6.0ms`

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
